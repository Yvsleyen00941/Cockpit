import AppKit
import CCCore
import CCNet
import Observation
import SwiftUI
import UserNotifications

/// Shows the 6-digit pairing code — in the menu bar popover and in a floating
/// HUD, so you see it without hunting for the menu bar icon.
@MainActor
@Observable
final class PairingCenter: PairingPresenter {
    struct Request: Identifiable {
        let id = UUID()
        let code: String
        let deviceName: String
        let platform: DevicePlatform
        let started = Date()
        let reject: @Sendable () -> Void
    }

    struct Outcome {
        let deviceName: String
        let success: Bool
        let date: Date
    }

    private(set) var current: Request?
    private(set) var lastOutcome: Outcome?
    private var panel: NSPanel?

    nonisolated func present(code: String, deviceName: String, platform: DevicePlatform, reject: @escaping @Sendable () -> Void) async {
        await MainActor.run {
            self.show(Request(code: code, deviceName: deviceName, platform: platform, reject: reject))
        }
    }

    nonisolated func finish(deviceName: String, success: Bool) async {
        await MainActor.run {
            self.complete(deviceName: deviceName, success: success)
        }
    }

    func decline() {
        guard let current else { return }
        current.reject()
        Log.shared.warning("Pairing with \(current.deviceName) declined")
        self.current = nil
        closePanel()
    }

    private func show(_ request: Request) {
        current = request
        lastOutcome = nil
        Log.shared.info("Pairing request from \(request.deviceName) — code \(request.code)")
        // Test runs print the code instead of putting a HUD and a chime on your screen.
        if !MacInfo.isTestRun {
            openPanel()
            NSSound(named: "Glass")?.play()
            notify(request)
        }
        if ProcessInfo.processInfo.environment["CC_PRINT_PAIRING_CODE"] != nil {
            print("CC_PAIRING_CODE=\(request.code)")
            fflush(stdout)
        }
    }

    private func complete(deviceName: String, success: Bool) {
        lastOutcome = Outcome(deviceName: deviceName, success: success, date: .now)
        current = nil
        if success {
            Log.shared.info("Paired with \(deviceName)")
            if !MacInfo.isTestRun { NSSound(named: "Hero")?.play() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                self.closePanel()
            }
        } else {
            closePanel()
        }
    }

    // MARK: HUD

    private func openPanel() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: PairingHUD(center: self))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 220, y: frame.maxY - 340))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func closePanel() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }

    private func notify(_ request: Request) {
        let content = UNMutableNotificationContent()
        content.title = "Pair \(request.deviceName)?"
        content.body = "Enter \(request.code.prefix(3)) \(request.code.suffix(3)) on your \(request.platform == .iPhone ? "iPhone" : "iPad")."
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pairing", content: content, trigger: nil))
    }
}

/// The floating code card.
struct PairingHUD: View {
    let center: PairingCenter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [HelperPalette.cardTop, HelperPalette.card], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(HelperPalette.accent.opacity(0.35), lineWidth: 1))
            if let request = center.current {
                pending(request)
            } else if let outcome = center.lastOutcome, outcome.success {
                success(outcome)
            }
        }
        .frame(width: 440, height: 300)
        .environment(\.colorScheme, .dark)
    }

    private func pending(_ request: PairingCenter.Request) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: request.platform.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(HelperPalette.accent)
                Text("PAIRING REQUEST")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(HelperPalette.secondary)
                Spacer()
            }
            VStack(spacing: 6) {
                Text(request.deviceName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HelperPalette.primary)
                Text("Enter this code on your \(request.platform == .iPhone ? "iPhone" : "iPad")")
                    .font(.system(size: 13))
                    .foregroundStyle(HelperPalette.secondary)
            }
            HStack(spacing: 8) {
                ForEach(Array(request.code.enumerated()), id: \.offset) { index, digit in
                    Text(String(digit))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(HelperPalette.primary)
                        .frame(width: 50, height: 64)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HelperPalette.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(HelperPalette.accent.opacity(0.25)))
                    if index == 2 { Spacer().frame(width: 10) }
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, 180 - context.date.timeIntervalSince(request.started))
                HStack {
                    Text("Expires in \(Fmt.countdown(remaining))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(HelperPalette.secondary)
                    Spacer()
                    Button("Decline") { center.decline() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HelperPalette.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(HelperPalette.red.opacity(0.14)))
                }
            }
        }
        .padding(26)
    }

    private func success(_ outcome: PairingCenter.Outcome) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(HelperPalette.green)
                .symbolEffect(.bounce, value: outcome.date)
            Text("Paired with \(outcome.deviceName)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HelperPalette.primary)
            Text("Future connections are automatic.")
                .font(.system(size: 13))
                .foregroundStyle(HelperPalette.secondary)
        }
    }
}
