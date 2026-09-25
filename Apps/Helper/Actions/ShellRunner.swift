import Foundation

struct ShellResult: Sendable {
    var status: Int32
    var output: String
    var errorOutput: String
    var timedOut: Bool

    /// The last line worth showing in a toast.
    var summary: String {
        let text = (status == 0 ? output : (errorOutput.isEmpty ? output : errorOutput))
        return text.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// Runs processes off the main thread with a timeout, reading stdout and stderr
/// concurrently (so a chatty process can never deadlock on a full pipe).
enum ShellRunner {
    static let maxOutput = 64 * 1024

    static func shell(_ command: String, cwd: String? = nil, timeout: TimeInterval = 30) async -> ShellResult {
        // A login shell, so Homebrew, pyenv, nvm… are on PATH like in Terminal.
        await run(executable: "/bin/zsh", arguments: ["-lc", command], cwd: cwd, timeout: timeout)
    }

    static func run(executable: String, arguments: [String], cwd: String? = nil, timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable: executable, arguments: arguments, cwd: cwd, timeout: timeout))
            }
        }
    }

    private final class Box: @unchecked Sendable {
        var stdout = Data()
        var stderr = Data()
        var timedOut = false
    }

    private static func runBlocking(executable: String, arguments: [String], cwd: String?, timeout: TimeInterval) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd {
            let expanded = (cwd as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                return ShellResult(status: -1, output: "", errorOutput: "Folder not found: \(cwd)", timedOut: false)
            }
            process.currentDirectoryURL = URL(fileURLWithPath: expanded)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        environment["CONTROL_CENTER"] = "1"
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let box = Box()
        let group = DispatchGroup()
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: "", errorOutput: error.localizedDescription, timedOut: false)
        }
        group.enter()
        DispatchQueue.global().async {
            box.stdout = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            box.stderr = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let killer = DispatchWorkItem {
            if process.isRunning {
                box.timedOut = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        process.waitUntilExit()
        killer.cancel()
        _ = group.wait(timeout: .now() + 2)

        func text(_ data: Data) -> String {
            String(decoding: data.suffix(maxOutput), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ShellResult(status: process.terminationStatus, output: text(box.stdout), errorOutput: box.timedOut ? "Timed out after \(Int(timeout)) s" : text(box.stderr), timedOut: box.timedOut)
    }
}
