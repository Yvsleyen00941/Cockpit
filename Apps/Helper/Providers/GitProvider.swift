import AppKit
import CCCore
import Foundation

/// Git status for the repository you're working in — Xcode's open workspace
/// when Xcode is in front, else your configured repositories.
@MainActor
final class GitProvider: PollingProvider {
    override var channels: Set<Channel> { [.git] }
    override var interval: TimeInterval { 10 }

    private var configured: [String] = []
    private var xcodeRepo: String?
    private var lastXcodeProbe = Date.distantPast

    func configure(_ repositories: [String]) {
        configured = repositories
        kick()
    }

    func contextChanged() {
        guard isActive, Hub.shared.state.context?.bundleID == Bundles.xcode, Date().timeIntervalSince(lastXcodeProbe) > 5 else { return }
        Task { await probeXcode() }
    }

    var currentRepository: String? {
        Hub.shared.state.git?.current?.path.nilIfEmpty.map(Paths.expand) ?? xcodeRepo ?? configured.first.map(Paths.expand)
    }

    override func tick() async {
        if Hub.shared.state.context?.bundleID == Bundles.xcode, Date().timeIntervalSince(lastXcodeProbe) > 30 {
            await probeXcode()
        }
        var paths: [String] = []
        for path in ([xcodeRepo].compactMap { $0 } + configured.map(Paths.expand)) where !paths.contains(path) {
            paths.append(path)
        }
        var statuses: [RepoStatus] = []
        for path in paths.prefix(6) {
            if let status = await Self.status(at: path) { statuses.append(status) }
        }
        let current = statuses.first { $0.path == xcodeRepo } ?? statuses.first
        Hub.shared.publish(.git(GitState(current: current, repos: statuses)))
    }

    private func probeXcode() async {
        lastXcodeProbe = .now
        guard !MacInfo.isTestRun else { return }
        let script = """
        with timeout of 2 seconds
        tell application id "com.apple.dt.Xcode" to return path of active workspace document
        end timeout
        """
        guard case .success(let value) = await AppleScriptRunner.shared.run(script), let path = value.string else { return }
        let folder = (path as NSString).deletingLastPathComponent
        let top = await ShellRunner.run(executable: "/usr/bin/git", arguments: ["-C", folder, "rev-parse", "--show-toplevel"], timeout: 5)
        if top.status == 0, !top.output.isEmpty, top.output != xcodeRepo {
            xcodeRepo = top.output
            await tick()
        }
    }

    static func status(at path: String) async -> RepoStatus? {
        let result = await ShellRunner.run(executable: "/usr/bin/git", arguments: ["-C", path, "status", "--porcelain=v2", "--branch"], timeout: 8)
        guard result.status == 0 else { return nil }
        var status = RepoStatus(path: path, name: (path as NSString).lastPathComponent, branch: "—")
        for line in result.output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                status.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                status.ahead = Int(parts.first?.dropFirst() ?? "0") ?? 0
                status.behind = Int(parts.last?.dropFirst() ?? "0") ?? 0
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let xy = Array(line.split(separator: " ")[1])
                if xy.count == 2 {
                    if xy[0] != "." { status.staged += 1 }
                    if xy[1] != "." { status.modified += 1 }
                }
            } else if line.hasPrefix("u ") {
                status.conflicts += 1
            } else if line.hasPrefix("? ") {
                status.untracked += 1
            }
        }
        let log = await ShellRunner.run(executable: "/usr/bin/git", arguments: ["-C", path, "log", "-1", "--format=%s%x1f%ct"], timeout: 5)
        if log.status == 0 {
            let parts = log.output.components(separatedBy: "\u{1F}")
            status.lastCommit = parts.first
            status.lastCommitDate = parts.count > 1 ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) } : nil
        }
        return status
    }

    // MARK: Commands

    func run(_ command: GitCommand) async -> ActionResult {
        guard let repo = command.repo.map(Paths.expand) ?? currentRepository else {
            return .failure("No repository — open one in Xcode or add it in the helper's Git settings.")
        }
        let quoted = "'" + (command.message ?? "").replacingOccurrences(of: "'", with: "'\\''") + "'"
        let shell: String = switch command.command {
        case .status: "git status --short --branch"
        case .pull: "git pull --ff-only"
        case .push: "git push"
        case .fetch: "git fetch --all --prune"
        case .stash: "git stash push -u"
        case .commitAll:
            (command.message ?? "").isEmpty ? "echo 'A commit message is required' >&2; exit 1" : "git add -A && git commit -m \(quoted)"
        }
        let result = await ShellRunner.shell(shell, cwd: repo, timeout: 60)
        await tick()
        let name = (repo as NSString).lastPathComponent
        if result.status == 0 {
            return ActionResult(ok: true, message: "git \(command.command == .commitAll ? "commit" : command.command.rawValue) · \(name)", output: result.output.nilIfEmpty)
        }
        return ActionResult(ok: false, message: result.summary.nilIfEmpty ?? "git failed", output: [result.output, result.errorOutput].joined(separator: "\n").nilIfEmpty)
    }
}
