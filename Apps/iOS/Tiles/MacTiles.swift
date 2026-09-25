import CCCore
import SwiftUI

// MARK: - System (home quadrant)

/// CPU and RAM bars, now playing with skip/pause, and a mic mute toggle.
struct SystemSummaryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.store.system
        GeometryReader { proxy in
            let roomy = proxy.size.height > 280
            VStack(alignment: .leading, spacing: roomy ? 13 : 9) {
                CardHeader(title: system?.model ?? "Mac", symbol: "laptopcomputer") {
                    HStack(spacing: 6) {
                        if let thermal = system?.thermal, thermal != .nominal {
                            Pill(text: thermal.rawValue, color: thermal == .fair ? CC.yellow : CC.red, symbol: "thermometer.medium")
                        }
                        if let battery = system?.battery {
                            Pill(text: "\(Int(battery.level * 100))%", color: battery.level < 0.2 && !battery.onAC ? CC.red : CC.text2, symbol: battery.isCharging ? "bolt.fill" : "battery.75percent")
                        }
                    }
                }
                meter("CPU", value: system?.cpu ?? 0, detail: "\(Int(((system?.cpu ?? 0) * 100).rounded()))%")
                if roomy, let system {
                    CoreBars(cores: system.cpuCores, efficiency: system.efficiencyCores)
                        .frame(height: 22)
                }
                meter("Memory", value: system?.memFraction ?? 0, detail: system.map { "\(Fmt.gigabytes($0.memUsed)) / \(Fmt.gigabytes($0.memTotal)) GB" } ?? "—", color: pressureColor(system?.memPressure))
                Divider().overlay(CC.divider)
                if let track = model.store.media?.nowPlaying {
                    NowPlayingRow(track: track, artwork: roomy ? 54 : 44)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note").foregroundStyle(CC.text3)
                        Text("Nothing playing").font(.system(size: 14)).foregroundStyle(CC.text2)
                    }
                    .frame(height: roomy ? 54 : 44)
                }
                Spacer(minLength: 0)
                MicRow()
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.show(page: "mac") }
    }

    private func meter(_ label: String, value: Double, detail: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(label)
                Spacer()
                Text(detail)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CC.text)
                    .contentTransition(.numericText())
            }
            BarGauge(value: value, color: color ?? CC.load(value), height: 8)
        }
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
        HStack(spacing: 10) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(muted ? CC.red : (live ? CC.green : CC.text2))
                .frame(width: 22)
            Text("Microphone")
                .font(.system(size: 14, weight: .medium))
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
        HStack(spacing: 12) {
            Artwork(track: track, size: artwork)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    BarGauge(value: track.duration > 0 ? track.position(at: context.date) / track.duration : 0, color: CC.text2, height: 3)
                }
            }
            HStack(spacing: 4) {
                control("backward.fill", .previous, size: 14)
                control(track.isPlaying ? "pause.fill" : "play.fill", .playPause, size: 20, prominent: true)
                control("forward.fill", .next, size: 14)
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
                .frame(width: prominent ? 44 : 34, height: 44)
                .background(Circle().fill(prominent ? CC.elevated : .clear))
        }
        .buttonStyle(PressStyle(scale: 0.9))
    }
}

// MARK: - Mac monitor

struct SystemDetailTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let system = model.store.system
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: system?.model ?? "Mac", symbol: "gauge.with.dots.needle.67percent") {
                if let uptime = system?.uptime {
                    Text("Up \(Fmt.duration(uptime))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CC.text3)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("CPU")
                    Text("\(Int(((system?.cpu ?? 0) * 100).rounded()))%")
                        .font(CCFont.display(56))
                        .foregroundStyle(CC.load(system?.cpu ?? 0))
                        .contentTransition(.numericText())
                    Sparkline(values: model.store.cpuHistory, color: CC.accent)
                        .frame(height: 60)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    if let system {
                        HStack {
                            SectionLabel("\(system.efficiencyCores)E")
                            Spacer()
                            SectionLabel("\(system.cpuCores.count - system.efficiencyCores)P")
                        }
                        CoreBars(cores: system.cpuCores, efficiency: system.efficiencyCores)
                            .frame(height: 94)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 16) {
                gauge("GPU", system?.gpu ?? 0, "\(Int(((system?.gpu ?? 0) * 100).rounded()))%")
                gauge("Memory", system?.memFraction ?? 0, system.map { "\(Fmt.gigabytes($0.memUsed)) GB" } ?? "—")
                gauge("Disk", system.map { 1 - Double($0.diskFree) / Double(max(1, $0.diskTotal)) } ?? 0, system.map { "\(Fmt.bytes($0.diskFree)) free" } ?? "—")
            }
            Divider().overlay(CC.divider)
            HStack(spacing: 22) {
                Stat(label: "Down", value: Fmt.rate(system?.netIn ?? 0), size: 18)
                Stat(label: "Up", value: Fmt.rate(system?.netOut ?? 0), size: 18)
                Stat(label: "Swap", value: system.map { Fmt.bytes($0.swapUsed) } ?? "—", size: 18)
                Stat(label: "Pressure", value: system?.memPressure.rawValue.capitalized ?? "—", color: system?.memPressure == .normal ? CC.text : CC.orange, size: 18)
                if let battery = system?.battery {
                    Stat(label: battery.isCharging ? "Charging" : "Battery", value: "\(Int(battery.level * 100))%", color: battery.level < 0.2 ? CC.red : CC.text, size: 18)
                }
                Stat(label: "Thermal", value: system?.thermal.rawValue.capitalized ?? "—", color: system?.thermal == .nominal ? CC.green : CC.orange, size: 18)
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private func gauge(_ label: String, _ value: Double, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(label)
                Spacer()
                Text(detail)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
            }
            BarGauge(value: value, color: CC.load(value), height: 7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProcessesTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Top Processes", symbol: "list.number")
            let processes = model.store.system?.topProcesses ?? []
            if processes.isEmpty {
                Text("Idle.").font(.system(size: 14)).foregroundStyle(CC.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(processes) { process in
                HStack(spacing: 10) {
                    AppIconView(bundleID: process.bundleID, size: 26, fallback: "gearshape")
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(process.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CC.text)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int((process.cpu * 100).rounded()))%")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
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
            CardHeader(title: "Running Apps", symbol: "square.grid.3x2") {
                Text("\(apps.count)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(CC.text3)
            }
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 10) {
                    ForEach(apps) { app in
                        Button {
                            Feedback.tap()
                            model.send(.app(AppControl(.activate, bundleID: app.bundleID)))
                        } label: {
                            VStack(spacing: 7) {
                                AppIconView(bundleID: app.bundleID, size: 56)
                                    .opacity(app.isHidden ? 0.5 : 1)
                                    .overlay(alignment: .bottom) {
                                        if app.isActive {
                                            Circle().fill(CC.accent).frame(width: 5, height: 5).offset(y: 9)
                                        }
                                    }
                                Text(app.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(app.isActive ? CC.text : CC.text2)
                                    .lineLimit(1)
                                    .frame(width: 72)
                                    .padding(.top, 4)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(app.isActive ? CC.accent.opacity(0.14) : .clear))
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
            CardHeader(title: context?.url != nil ? "Current Page" : "Current Window", symbol: "macwindow")
            HStack(alignment: .top, spacing: 14) {
                AppIconView(bundleID: context?.bundleID, size: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(context?.windowTitle ?? context?.appName ?? "—")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(CC.text)
                        .lineLimit(2)
                    if let url = context?.url {
                        Text(url)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CC.accent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if let since = context?.since {
                        Text("In front for \(Fmt.duration(Date().timeIntervalSince(since)))")
                            .font(.system(size: 12))
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
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CC.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.accent.opacity(0.12)))
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
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CC.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.accent.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CC.text)
                        .lineLimit(1)
                    Pill(text: repo.branch, color: CC.accent, symbol: "arrow.triangle.branch")
                    Spacer(minLength: 0)
                    if repo.ahead > 0 { Pill(text: "↑\(repo.ahead)", color: CC.green) }
                    if repo.behind > 0 { Pill(text: "↓\(repo.behind)", color: CC.orange) }
                }
                HStack(spacing: 16) {
                    count("Staged", repo.staged, CC.green)
                    count("Changed", repo.modified, CC.orange)
                    count("New", repo.untracked, CC.accent)
                    if repo.conflicts > 0 { count("Conflicts", repo.conflicts, CC.red) }
                }
                if let commit = repo.lastCommit, !compact {
                    Text("\(commit)\(repo.lastCommitDate.map { " · \(Fmt.ago($0))" } ?? "")")
                        .font(.system(size: 12, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(CCFont.number(22))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(command == .commitAll ? Color(hex: 0x0A0A0F) : CC.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(command == .commitAll ? CC.green : CC.accent.opacity(0.13)))
        }
        .buttonStyle(PressStyle())
    }
}
