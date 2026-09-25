import AppKit
import CCCore
import CCNet
import SwiftUI

/// The menu bar popover: status at a glance, the pairing code, connected
/// devices, the running timer, integration health and missing permissions.
struct MenuBarView: View {
    @State private var hub = Hub.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            if let request = hub.pairing.current {
                pairing(request)
                divider
            }
            devices
            if let timer = hub.state.timers?.primary {
                divider
                timerRow(timer)
            }
            divider
            integrations
            if let missing = hub.permissions.statuses.first(where: { $0.required && !$0.granted }) {
                divider
                permissionWarning(missing)
            }
            divider
            footer
        }
        .frame(width: 340)
        .background(HelperPalette.background)
        .environment(\.colorScheme, .dark)
        .onAppear {
            PreferencesOpener.openWindow = openWindow
            hub.permissions.refresh()
        }
    }

    private var divider: some View {
        Rectangle().fill(HelperPalette.divider).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [HelperPalette.cardTop, HelperPalette.card], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HelperPalette.accent.opacity(0.35)))
                Image(nsImage: MenuBarGlyph.image(connected: hub.hasClients, pairing: false))
                    .renderingMode(.template)
                    .foregroundStyle(hub.hasClients ? HelperPalette.accent : HelperPalette.secondary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("ControlCenter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HelperPalette.primary)
                Text(MacInfo.model)
                    .font(.system(size: 11))
                    .foregroundStyle(HelperPalette.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(hub.server.isListening ? (hub.hasClients ? HelperPalette.green : HelperPalette.accent) : HelperPalette.red)
                    .frame(width: 7, height: 7)
                Text(hub.server.isListening ? (hub.hasClients ? "Connected" : "Ready") : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HelperPalette.secondary)
            }
        }
        .padding(14)
    }

    // MARK: Pairing

    private func pairing(_ request: PairingCenter.Request) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HelperLabel("Pairing · \(request.deviceName)")
            HStack(spacing: 6) {
                ForEach(Array(request.code.enumerated()), id: \.offset) { index, digit in
                    Text(String(digit))
                        .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(HelperPalette.primary)
                        .frame(width: 36, height: 46)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(HelperPalette.elevated))
                    if index == 2 { Spacer().frame(width: 6) }
                }
                Spacer()
            }
            HStack {
                Text("Enter this code on your \(request.platform == .iPhone ? "iPhone" : "iPad").")
                    .font(.system(size: 11))
                    .foregroundStyle(HelperPalette.secondary)
                Spacer()
                Button("Decline") { hub.pairing.decline() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HelperPalette.red)
            }
        }
        .padding(14)
        .background(HelperPalette.accent.opacity(0.08))
    }

    // MARK: Devices

    private var devices: some View {
        VStack(alignment: .leading, spacing: 10) {
            HelperLabel("Devices")
            if hub.connectedDevices.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "ipad.landscape")
                        .font(.system(size: 18))
                        .foregroundStyle(HelperPalette.secondary)
                    Text(hub.pairedDevices.isEmpty ? "Open Control Center on your iPad and choose this Mac to pair." : "Waiting for your iPad — open Control Center on it.")
                        .font(.system(size: 12))
                        .foregroundStyle(HelperPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(hub.connectedDevices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: device.platform.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(HelperPalette.accent)
                            .frame(width: 22)
                        Text(device.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HelperPalette.primary)
                        Spacer()
                        Text(device.transport.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(device.transport == .usb ? HelperPalette.green : HelperPalette.secondary)
                        if let latency = device.latencyMs {
                            Text("\(Int(latency.rounded())) ms")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(HelperPalette.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: Timer

    private func timerRow(_ timer: TimerState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: timer.kind.isBreak ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(timer.kind.isBreak ? HelperPalette.green : HelperPalette.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(timer.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HelperPalette.primary)
                Text(timer.kind == .pomodoro ? "Session \(timer.session) of \(timer.sessionsPerCycle)" : (timer.state == .paused ? "Paused" : "Running"))
                    .font(.system(size: 11))
                    .foregroundStyle(HelperPalette.secondary)
            }
            Spacer()
            Text(MenuBarTicker.shared.text ?? Fmt.countdown(timer.remaining(at: .now)))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(HelperPalette.primary)
            Button {
                Task { _ = await hub.timers.handle(TimerCommand(.toggle)) }
            } label: {
                Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(HelperPalette.elevated))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HelperPalette.primary)
            Button {
                Task { _ = await hub.timers.handle(TimerCommand(.stop)) }
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(HelperPalette.elevated))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HelperPalette.secondary)
        }
        .padding(14)
    }

    // MARK: Integrations

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 8) {
            HelperLabel("Integrations")
            ForEach(hub.integrationStatuses()) { status in
                HStack(spacing: 10) {
                    Circle().fill(HelperPalette.health(status.health)).frame(width: 6, height: 6)
                    Image(systemName: status.id.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(HelperPalette.secondary)
                        .frame(width: 16)
                    Text(status.id.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HelperPalette.primary)
                    Spacer()
                    Text(status.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HelperPalette.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 170, alignment: .trailing)
                }
            }
        }
        .padding(14)
    }

    private func permissionWarning(_ status: PermissionStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HelperPalette.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(status.kind.title) needed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HelperPalette.primary)
                Text(status.kind.purpose)
                    .font(.system(size: 11))
                    .foregroundStyle(HelperPalette.secondary)
            }
            Spacer()
            Button("Grant") { hub.permissions.request(status.kind) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HelperPalette.background)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(HelperPalette.orange))
        }
        .padding(14)
        .background(HelperPalette.orange.opacity(0.08))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                PreferencesOpener.open()
            } label: {
                Label("Preferences…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(HelperPalette.secondary)
        .padding(14)
    }
}
