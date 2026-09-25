import AppKit
import CCCore
import Foundation

/// The single action pipeline. Every key, macro step, scene, Siri intent,
/// widget button and loopback API call runs through `run(_:origin:)`.
@MainActor
final class ActionExecutor {
    func run(_ action: ButtonAction, origin: ActionOrigin) async -> ActionResult {
        let result = await execute(action, origin: origin)
        if case .none = action {} else {
            Log.shared.action("\(origin.deviceName): \(action.typeName) \(action.summary)\(result.ok ? "" : " — \(result.message ?? "failed")")")
        }
        return result
    }

    private func execute(_ action: ButtonAction, origin: ActionOrigin) async -> ActionResult {
        let hub = Hub.shared
        switch action {
        case .keyCombo(let combo):
            return KeySynth.post(combo)

        case .text(let input):
            return await KeySynth.type(expand(input.text), pressReturn: input.pressesReturn)

        case .appleScript(let source):
            switch await AppleScriptRunner.shared.run(expand(source)) {
            case .success(let value): return ActionResult(ok: true, output: value.string?.nilIfEmpty)
            case .failure(let error): return .failure(error.localizedDescription)
            }

        case .shell(let command):
            let result = await ShellRunner.shell(expand(command.command), cwd: command.cwd, timeout: command.timeout ?? 60)
            let output = [result.output, result.errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
            return ActionResult(ok: result.status == 0, message: result.status == 0 ? (result.summary.nilIfEmpty ?? "Done") : (result.summary.nilIfEmpty ?? "Exited \(result.status)"), output: command.showOutput == true ? output.nilIfEmpty : nil)

        case .shortcut(let shortcut):
            return await ShortcutsCLI.run(shortcut.name, input: shortcut.input.map(expand))

        case .openApp(let app):
            return await openApp(app.bundleID)

        case .openURL(let ref):
            guard let url = URL(string: expand(ref.url)) else { return .failure("Invalid URL") }
            if let bundleID = ref.bundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                do {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
                    return .success
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
            return NSWorkspace.shared.open(url) ? .success : .failure("Couldn't open \(url.absoluteString)")

        case .openPath(let path):
            let expanded = Paths.expand(expand(path))
            guard FileManager.default.fileExists(atPath: expanded) else { return .failure("Not found: \(path)") }
            NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
            return .success

        case .media(let command):
            let key: KeySynth.SystemKey = switch command {
            case .playPause: .play
            case .next: .next
            case .previous: .previous
            case .volumeUp: .soundUp
            case .volumeDown: .soundDown
            case .mute: .mute
            }
            let result = KeySynth.post(key)
            Task { try? await Task.sleep(for: .milliseconds(350)); await hub.media.tick() }
            return result

        case .system(let command):
            return await SystemControls.perform(command)

        case .window(let command):
            return WindowManager.perform(command)

        case .audio(let command):
            switch command.command {
            case .micToggle:
                let muted = hub.audio.toggleMic()
                return ActionResult(ok: true, message: muted ? "Microphone muted" : "Microphone live")
            case .micMute: hub.audio.setMicMuted(true)
            case .micUnmute: hub.audio.setMicMuted(false)
            case .outputMuteToggle: hub.audio.toggleOutputMute()
            case .setOutputVolume: hub.audio.setOutputVolume(command.value ?? 0.5)
            case .setInputVolume: hub.audio.setInputVolume(command.value ?? 0.75)
            }
            return .success

        case .call(let command):
            return await CallControls.perform(command)

        case .bot(let command):
            return await hub.bot.command(command)

        case .focus(let command):
            switch command.command {
            case .on: return await hub.focus.set(on: true, name: command.name)
            case .off: return await hub.focus.set(on: false, name: nil)
            case .toggle: return await hub.focus.toggle(name: command.name)
            }

        case .timer(let command):
            return await hub.timers.handle(command)

        case .git(let command):
            return await hub.git.run(command)

        case .navigate(let page):
            navigate(to: page, origin: origin)
            return .success

        case .scene(let id):
            guard let scene = hub.workspace.scene(id) else { return .failure("Scene “\(id)” not found") }
            Log.shared.action("Scene: \(scene.name)")
            let result = await runSteps(scene.steps, origin: origin)
            if let page = scene.page { navigate(to: page, origin: origin) }
            return result.ok ? ActionResult(ok: true, message: scene.name) : result

        case .macro(let steps):
            return await runSteps(steps, origin: origin)

        case .clipboard(let command):
            let pasteboard = NSPasteboard.general
            switch command.command {
            case .setText:
                pasteboard.clearContents()
                pasteboard.setString(expand(command.text ?? ""), forType: .string)
                return ActionResult(ok: true, message: "Copied to the Mac clipboard")
            case .copyURL:
                guard let url = hub.context.currentURL else { return .failure("No browser tab in front") }
                pasteboard.clearContents()
                pasteboard.setString(url, forType: .string)
                return ActionResult(ok: true, message: "URL copied")
            }

        case .daily(let command):
            return await hub.daily.handle(command)

        case .app(let control):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: control.bundleID).first else {
                return control.command == .activate ? await openApp(control.bundleID) : .failure("Not running")
            }
            switch control.command {
            case .activate: app.unhide(); app.activate()
            case .hide: app.hide()
            case .quit: app.terminate()
            }
            return .success

        case .integration(let command):
            return await integration(command)

        case .none:
            return .success

        case .unsupported(let type):
            return .failure("This helper doesn't know “\(type)” — update it.")
        }
    }

    // MARK: Helpers

    private func runSteps(_ steps: [MacroStep], origin: ActionOrigin) async -> ActionResult {
        var firstFailure: ActionResult?
        for step in steps {
            let result = await execute(step.action, origin: origin)
            if !result.ok, firstFailure == nil { firstFailure = result }
            if let delay = step.delay, delay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            } else {
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        return firstFailure ?? .success
    }

    private func openApp(_ bundleID: String) async -> ActionResult {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            running.unhide()
            running.activate()
            return .success
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return .failure("\(bundleID) isn't installed")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// `navigate` from a device goes back to that device; from Siri, a widget
    /// or the Mac it goes to every iPad ("show the trading view on my iPad").
    private func navigate(to page: String, origin: ActionOrigin) {
        let directive = MCCBody.directive(Directive(.navigate, page: page))
        if let session = origin.sessionID, origin.platform == .iPad || origin.platform == .iPhone {
            Hub.shared.send(directive, to: session)
        } else {
            Hub.shared.broadcast(directive, platforms: [.iPad])
        }
    }

    private func integration(_ command: IntegrationCommand) async -> ActionResult {
        let hub = Hub.shared
        switch (command.integration, command.command) {
        case (.whoop, .connect): return await hub.whoop.connect()
        case (.whoop, .disconnect):
            hub.whoop.disconnect()
            return ActionResult(ok: true, message: "WHOOP disconnected")
        case (.bot, .test): return await hub.bot.test()
        case (.calendar, .connect):
            await hub.calendar.requestAccess()
            return hub.calendar.access == .granted ? .success : .failure("Calendar access wasn't granted")
        case (_, .refresh), (_, .test):
            await hub.refresh(Set(Channel.allCases))
            return ActionResult(ok: true, message: "\(command.integration.title) refreshed")
        default:
            return .failure("Open the helper's preferences on your Mac for this")
        }
    }

    /// Template values that only the Mac knows.
    private func expand(_ text: String) -> String {
        TemplateEngine.expand(text) { name in
            switch name {
            case "url": Hub.shared.context.currentURL
            case "title": Hub.shared.context.currentTitle
            case "app": Hub.shared.context.currentAppName
            case "clipboard": NSPasteboard.general.string(forType: .string)
            case "repo": Hub.shared.git.currentRepository
            default: nil
            }
        }
    }
}
