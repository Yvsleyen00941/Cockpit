import CCCore
import SwiftUI

// MARK: - System (home quadrant)

/// CPU and memory as big light readouts, now playing, and the mic.
struct SystemSummaryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.store.system
        GeometryReader { proxy in
            let roomy = proxy.size.height > 268
            VStack(alignment: .leading, spacing: roomy ? 14 : 11) {
                CardHeader(title: system?.model ?? "Mac", symbol: "laptopcomputer") {
                    HStack(spacing: 6) {
                        if let thermal = system?.thermal, thermal != .nominal {
                            Pill(text: thermal.rawValue.capitalized, color: thermal == .fair ? CC.yellow : CC.red, symbol: "thermometer.medium")
                        }
                        if let battery = system?.battery {
                            Pill(text: "\(Int(battery.level * 100))%", color: battery.level < 0.2 && !battery.onAC ? CC.red : CC.text2, symbol: battery.isCharging ? "bolt.fill" : "battery.75percent")
                        }
                    }
                }
                HStack(alignment: .top, spacing: 22) {
                    readout("CPU", value: "\(Int(((system?.cpu ?? 0) * 100).rounded()))", unit: "%", fraction: system?.cpu ?? 0, color: CC.load(system?.cpu ?? 0))
                    readout("Memory", value: system.map { Fmt.gigabytes($0.memUsed) } ?? "—", unit: system.map { "/ \(Fmt.gigabytes($0.memTotal)) GB" } ?? "", fraction: system?.memFraction ?? 0, color: pressureColor(system?.memPressure))
                }
                if roomy, let system {
                    CoreBars(cores: system.cpuCores, efficiency: system.efficiencyCores)
                        .frame(height: 26)
                }
                Rectangle().fill(CC.divider).frame(height: 1)
                if let track = model.store.media?.nowPlaying {
                    NowPlayingRow(track: track, artwork: roomy ? 54 : 46)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note").foregroundStyle(CC.text3)
                        Text("Nothing playing").font(.system(size: 15)).foregroundStyle(CC.text2)
                    }
                    .frame(height: roomy ? 54 : 46)
                }
                Spacer(minLength: 0)
                MicRow()
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.show(page: "mac") }
    }

    private func readout(_ label: String, value: String, unit: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(CCFont.display(34))
                    .foregroundStyle(CC.text)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CC.text2)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            BarGauge(value: fraction, color: color, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pressureColor(_ pressure: MemoryPressure?) -> Color {
        switch pressure {
        case .warning: CC.yellow
        case .critical: CC.red
        default: CC.accent
        }
    }
}

struct MicRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let audio = model.store.audio
        let muted = audio?.inputMuted ?? false
        let live = (audio?.micInUse ?? false) && !muted
        let tint = muted ? CC.red : (live ? CC.green : CC.accent)
        HStack(spacing: 11) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(muted ? CC.red : (live ? CC.green : CC.icon))
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(muted || live ? 0.18 : 0.08)))
            Text(muted ? "Microphone muted" : "Microphone")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CC.text)
            if live { Pill(text: "Live", color: CC.green, dot: true) }
            Spacer()
            CCToggle(isOn: !muted, color: live ? CC.green : CC.accent) {
                model.send(.audio(AudioCommand(.micToggle)))
            }
        }
    }
}

struct NowPlayingRow: View {
    let track: NowPlaying
    var artwork: CGFloat = 54
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 13) {
            Artwork(track: track, size: artwork)
                .glow(CC.accent, spread: 10, opacity: 0.35, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    BarGauge(value: track.duration > 0 ? track.position(at: context.date) / track.duration : 0, color: CC.text2, height: 3)
                }
            }
            HStack(spacing: 4) {
                control("backward.fill", .previous, size: 13)
                control(track.isPlaying ? "pause.fill" : "play.fill", .playPause, size: 19, prominent: true)
                control("forward.fill", .next, size: 13)
            }
        }
    }

    private func control(_ symbol: String, _ command: MediaCommand, size: CGFloat, prominent: Bool = false) -> some View {
        Button {
            Feedback.tap()
            model.send(.media(command))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(prominent ? CC.text : CC.text2)
                .frame(width: prominent ? 46 : 34, height: 46)
                .background {
                    if prominent {
                        Circle().fill(CC.elevated).overlay(Circle().strokeBorder(CC.divider, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

// MARK: - Mac monitor

/// A vertical glass pill that fills from the bottom — the fleet dashboard's
/// battery gauge.
struct PillGauge: View {
    var value: Double
    var color: Color
    var label: String
    var detail: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let fraction = min(1, max(0, value))
                ZStack(alignment: .bottom) {
                    Capsule().fill(CC.track)
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(proxy.size.width, proxy.size.height * fraction))
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(fraction > 0.18 ? color.legibleText(in: scheme) : CC.text)
                        .padding(.bottom, 10)
                }
                .overlay(Capsule().strokeBorder(CC.divider, lineWidth: 1))
            }
            .frame(width: 54)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CC.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SystemDetailTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.store.system
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: system?.model ?? "Mac", symbol: "gauge.with.dots.needle.67percent") {
                if let uptime = system?.uptime {
                    Text("Up \(Fmt.duration(uptime))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CC.text3)
                }
            }
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("CPU")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(((system?.cpu ?? 0) * 100).rounded()))")
                            .font(CCFont.display(64))
                            .tracking(-1.5)
                            .foregroundStyle(CC.text)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(CC.load(system?.cpu ?? 0))
                    }
                    Sparkline(values: model.store.cpuHistory, color: CC.accent)
                        .frame(height: 56)
                    if let system {
                        CoreBars(cores: system.cpuCores, efficiency: system.efficiencyCores)
                            .frame(height: 44)
                        HStack {
                            SectionLabel("\(system.efficiencyCores) efficiency")
                            Spacer()
                            SectionLabel("\(system.cpuCores.count - system.efficiencyCores) performance")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 18) {
                    PillGauge(value: system?.gpu ?? 0, color: CC.load(system?.gpu ?? 0), label: "GPU", detail: "")
                    PillGauge(value: system?.memFraction ?? 0, color: memoryColor(system?.memPressure), label: "Memory", detail: system.map { "\(Fmt.gigabytes($0.memUsed)) GB" } ?? "—")
                    PillGauge(value: system.map { 1 - Double($0.diskFree) / Double(max(1, $0.diskTotal)) } ?? 0, color: CC.teal, label: "Disk", detail: system.map { "\(Fmt.bytes($0.diskFree)) free" } ?? "—")
                }
                .frame(maxHeight: .infinity)
            }
            Rectangle().fill(CC.divider).frame(height: 1)
            HStack(spacing: 24) {
                Stat(label: "Down", value: Fmt.rate(system?.netIn ?? 0), size: 19)
                Stat(label: "Up", value: Fmt.rate(system?.netOut ?? 0), size: 19)
                Stat(label: "Swap", value: system.map { Fmt.bytes($0.swapUsed) } ?? "—", size: 19)
                Stat(label: "Pressure", value: system?.memPressure.rawValue.capitalized ?? "—", color: system?.memPressure == .normal ? CC.text : CC.orange, size: 19)
                if let battery = system?.battery {
                    Stat(label: battery.isCharging ? "Charging" : "Battery", value: "\(Int(battery.level * 100))%", color: battery.level < 0.2 ? CC.red : CC.text, size: 19)
                }
                Stat(label: "Thermal", value: system?.thermal.rawValue.capitalized ?? "—", color: system?.thermal == .nominal ? CC.green : CC.orange, size: 19)
            }
        }
        .card()
    }

    private func memoryColor(_ pressure: MemoryPressure?) -> Color {
        switch pressure {
        case .warning: CC.yellow
        case .critical: CC.red
        default: CC.accent
        }
    }
}

struct ProcessesTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Top processes", symbol: "list.number")
            let processes = model.store.system?.topProcesses ?? []
            if processes.isEmpty {
                Text("Idle.").font(.system(size: 15)).foregroundStyle(CC.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(processes) { process in
                HStack(spacing: 12) {
                    AppIconView(bundleID: process.bundleID, size: 30, fallback: "gearshape")
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(process.name)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(CC.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int((process.cpu * 100).rounded()))%")
                                .font(.system(size: 14, weight: .regular).monospacedDigit())
                                .foregroundStyle(CC.load(min(1, process.cpu)))
                        }
                        BarGauge(value: min(1, process.cpu), color: CC.load(min(1, process.cpu)), height: 4)
                    }
                }
                .contextMenu {
                    if let bundleID = process.bundleID {
                        Button("Bring to Front", systemImage: "macwindow") { model.send(.app(AppControl(.activate, bundleID: bundleID))) }
                        Button("Quit \(process.name)", systemImage: "xmark.circle", role: .destructive) { model.send(.app(AppControl(.quit, bundleID: bundleID))) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        .animation(.easeOut(duration: 0.3), value: model.store.system?.topProcesses.map(\.pid))
    }
}

// MARK: - Apps

struct AppSwitcherTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let apps = model.store.apps?.apps ?? []
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Running apps", symbol: "square.grid.3x2") {
                Text("\(apps.count)").font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(CC.text3)
            }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 12) {
                    ForEach(apps) { app in
                        Button {
                            Feedback.tap()
                            model.send(.app(AppControl(.activate, bundleID: app.bundleID)))
                        } label: {
                            VStack(spacing: 8) {
                                AppIconView(bundleID: app.bundleID, size: 54)
                                    .opacity(app.isHidden ? 0.5 : 1)
                                    .glow(app.isActive ? CC.accent : .clear, spread: 12, opacity: 0.55, y: 0)
                                Text(app.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(app.isActive ? CC.text : CC.text2)
                                    .lineLimit(1)
                                    .frame(width: 74)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background {
                                if app.isActive { Well(radius: 18, tint: CC.accent) }
                            }
                        }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            Button("Hide", systemImage: "eye.slash") { model.send(.app(AppControl(.hide, bundleID: app.bundleID))) }
                            Button("Quit", systemImage: "xmark.circle", role: .destructive) { model.send(.app(AppControl(.quit, bundleID: app.bundleID))) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .card()
    }
}

/// What's in the frontmost window — and, for browsers, the page: copy its
/// URL, continue it on the iPad, share it.
struct AppContextTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let context = model.store.context
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: context?.url != nil ? "Current page" : "Current window", symbol: "macwindow")
            HStack(alignment: .center, spacing: 16) {
                AppIconView(bundleID: context?.bundleID, size: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text(context?.windowTitle ?? context?.appName ?? "—")
                        .font(CCFont.title(21, weight: .medium))
                        .foregroundStyle(CC.text)
                        .lineLimit(2)
                    if let url = context?.url {
                        Text(url)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(CC.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if let since = context?.since {
                        Text("In front for \(Fmt.duration(Date().timeIntervalSince(since)))")
                            .font(.system(size: 13))
                            .foregroundStyle(CC.text2)
                    }
                }
            }
            Spacer(minLength: 0)
            if let urlString = context?.url, let url = URL(string: urlString) {
                HStack(spacing: 10) {
                    actionButton("Copy URL", "doc.on.doc") { model.send(.clipboard(ClipboardCommand(.copyURL))) }
                    actionButton("Open on iPad", "ipad.landscape") { openURL(url) }
                    ShareLink(item: url) {
                        actionLabel("Share", "square.and.arrow.up")
                    }
                    actionButton("Reload", "arrow.clockwise") { model.send(.keyCombo(KeyCombo("cmd+r"))) }
                }
            }
        }
        .card()
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            actionLabel(title, symbol)
        }
        .buttonStyle(PressStyle())
    }

    private func actionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(CC.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Well(radius: 21, tint: CC.accent))
    }
}

// MARK: - Git

struct GitTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 210
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                if !compact { CardHeader(title: "Repository", symbol: "arrow.triangle.branch") }
                if let repo = model.store.git?.current {
                    HStack(spacing: 8) {
                        Text(repo.name)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(CC.text)
                            .lineLimit(1)
                        Pill(text: repo.branch, color: CC.accent, symbol: "arrow.triangle.branch")
                        Spacer(minLength: 0)
                        if repo.ahead > 0 { Pill(text: "↑\(repo.ahead)", color: CC.green) }
                        if repo.behind > 0 { Pill(text: "↓\(repo.behind)", color: CC.orange) }
                    }
                    HStack(spacing: 22) {
                        count("Staged", repo.staged, CC.green)
                        count("Changed", repo.modified, CC.orange)
                        count("New", repo.untracked, CC.accent)
                        if repo.conflicts > 0 { count("Conflicts", repo.conflicts, CC.red) }
                    }
                    if let commit = repo.lastCommit, !compact {
                        Text("\(commit)\(repo.lastCommitDate.map { " · \(Fmt.ago($0))" } ?? "")")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(CC.text2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        gitButton("Pull", "arrow.down", .pull)
                        gitButton("Push", "arrow.up", .push)
                        gitButton("Commit…", "checkmark", .commitAll)
                    }
                } else {
                    SetupPrompt(symbol: "arrow.triangle.branch", title: "No repository", message: "Open a project in Xcode, or add repositories in the helper's Git settings.")
                }
            }
        }
        .card()
    }

    private func count(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(CCFont.display(30))
                .foregroundStyle(value > 0 ? color : CC.text3)
            SectionLabel(label)
        }
    }

    private func gitButton(_ title: String, _ symbol: String, _ command: GitCommand.Kind) -> some View {
        Button {
            let key = ButtonDef(id: "git.\(command.rawValue)", label: title, symbol: symbol, action: .git(GitCommand(command, message: command == .commitAll ? "{{input}}" : nil)))
            model.tap(key, pageID: nil)
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(GitButtonStyle(prominent: command == .commitAll))
    }
}

private struct GitButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? CC.green.legibleText(in: scheme) : CC.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if prominent {
                    Capsule()
                        .fill(LinearGradient(colors: [CC.green.opacity(0.85), CC.green], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .glow(CC.green, spread: 10, opacity: 0.35, y: 4)
                } else {
                    Well(radius: 20, tint: CC.accent)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
