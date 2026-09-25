import CCCore
import SwiftUI

/// First launch: find the Mac, type the code it shows, done. Every future
/// connection is automatic.
struct PairingFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connection = model.connection
        ZStack {
            CC.bg.ignoresSafeArea()
            RadialGradient(colors: [CC.accent.opacity(0.22), .clear], center: .topLeading, startRadius: 20, endRadius: 700)
                .ignoresSafeArea()
            HStack(spacing: 60) {
                brand
                    .frame(maxWidth: 440, alignment: .leading)
                VStack {
                    Group {
                        switch connection.pairing {
                        case .none, .failed:
                            MacList(error: {
                                if case .failed(let message) = connection.pairing { return message }
                                return nil
                            }())
                        case .connecting(let name):
                            progress("Connecting to \(name)…")
                        case .enterCode(let name, let attempt):
                            CodeEntry(macName: name, attempt: attempt)
                        case .verifying:
                            progress("Verifying…")
                        case .success(let name):
                            success(name)
                        }
                    }
                    .frame(width: 460, height: 520)
                    .background(CardBackground())
                    .animation(.spring(response: 0.4, dampingFraction: 0.86), value: connection.pairing)
                }
            }
            .padding(60)
        }
        .statusBarHidden()
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 26) {
            BrandMark()
                .frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 10) {
                Text("Control Center")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(CC.text)
                Text("Your Mac, at your fingertips — contextual keys, live dashboards and your whole day on the iPad next to your keyboard.")
                    .font(.system(size: 18))
                    .foregroundStyle(CC.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("rectangle.3.group.fill", "Keys that follow you", "Safari, Xcode, Notion, Terminal, calls — the right keys for whatever's in front.")
                feature("chart.line.uptrend.xyaxis", "Live, not polled", "Bot P&L, WHOOP, calendar, music and your Mac's vitals, pushed the moment they change.")
                feature("lock.shield.fill", "Private by design", "Local network only. Paired once with a code, encrypted end to end.")
            }
            HStack(spacing: 12) {
                Button("Explore the demo first") { model.setDemo(true) }
                    .buttonStyle(CapsuleButtonStyle(color: CC.accent))
                if !model.connection.pairedMacs.isEmpty {
                    Button("Back to my Mac") { model.connection.resumeConnecting() }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text2))
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CC.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(CC.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CC.text)
                Text(detail).font(.system(size: 14)).foregroundStyle(CC.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(CC.accent)
            Text(text).font(.system(size: 17, weight: .medium)).foregroundStyle(CC.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func success(_ name: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(CC.green)
                .symbolEffect(.bounce, value: name)
            Text("Paired with \(name)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CC.text)
            Text("From now on your iPad connects by itself.")
                .font(.system(size: 15))
                .foregroundStyle(CC.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            model.connection.resetPairingState()
        }
    }
}

/// The app mark: a landscape surface with four live tiles.
struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1D2844), Color(hex: 0x0A0A0F)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CC.accent.opacity(0.45), lineWidth: 1.2))
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    tile(CC.accent) { Sparkline(values: [2, 3, 2.6, 4, 3.6, 5, 4.6, 6], color: .white, fill: false, lineWidth: 1.8).padding(6) }
                    tile(Color(hex: 0x16213E)) { RingGauge(value: 0.78, color: CC.green, lineWidth: 3.2).padding(6) }
                }
                GridRow {
                    tile(Color(hex: 0x16213E)) { Image(systemName: "pause.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(CC.orange) }
                    tile(Color(hex: 0x16213E)) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach([0.4, 0.75, 0.55], id: \.self) { h in
                                Capsule().fill(CC.accent).frame(width: 4, height: 18 * h)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func tile<Content: View>(_ color: Color, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .overlay(content())
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct MacList: View {
    let error: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        let browser = model.connection.browser
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose your Mac")
                    .font(CCFont.heading(24))
                    .foregroundStyle(CC.text)
                Text("Macs running ControlCenter Helper on this network.")
                    .font(.system(size: 14))
                    .foregroundStyle(CC.text2)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CC.orange)
            }
            if browser.results.isEmpty {
                VStack(spacing: 18) {
                    Radar().frame(width: 150, height: 150)
                    Text("Looking for your Mac…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(CC.text)
                    Text("Open ControlCenter Helper on your Mac (it lives in the menu bar). Both devices need to be on the same network.")
                        .font(.system(size: 13))
                        .foregroundStyle(CC.text2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(browser.results) { mac in
                            Button {
                                Feedback.tap()
                                model.connection.pair(with: mac)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "laptopcomputer")
                                        .font(.system(size: 24, weight: .light))
                                        .foregroundStyle(CC.accent)
                                        .frame(width: 48, height: 48)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.accent.opacity(0.12)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mac.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(CC.text)
                                        Text(mac.model ?? "ControlCenter Helper").font(.system(size: 13)).foregroundStyle(CC.text2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CC.text3)
                                }
                                .padding(14)
                                .background(KeyFace(radius: 16))
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(28)
    }
}

private struct CodeEntry: View {
    let macName: String
    let attempt: Int
    @Environment(AppModel.self) private var model
    @State private var digits = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Enter the code on your Mac")
                    .font(CCFont.heading(22))
                    .foregroundStyle(CC.text)
                Text(attempt > 1 ? "That didn't match — check \(macName) and try again." : "\(macName) is showing a 6-digit code.")
                    .font(.system(size: 14))
                    .foregroundStyle(attempt > 1 ? CC.orange : CC.text2)
            }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let character = index < digits.count ? String(Array(digits)[index]) : ""
                    Text(character)
                        .font(CCFont.rounded(30, weight: .bold))
                        .foregroundStyle(CC.text)
                        .frame(width: 50, height: 62)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(index == digits.count ? CC.accent : CC.divider, lineWidth: index == digits.count ? 1.6 : 1))
                    if index == 2 { Spacer().frame(width: 8) }
                }
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✓"]], id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keypadKey(key)
                        }
                    }
                }
            }
            Button("Cancel") { model.connection.cancelPairing() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CC.text2)
        }
        .padding(28)
        .focusable()
        .focused($focused)
        .onAppear {
            digits = ""
            focused = true
        }
        .onChange(of: attempt) { _, _ in digits = "" }
        .onKeyPress { press in
            if let character = press.characters.first, character.isNumber { append(String(character)); return .handled }
            if press.key == .delete { delete(); return .handled }
            if press.key == .return { submit(); return .handled }
            return .ignored
        }
    }

    private func keypadKey(_ key: String) -> some View {
        Button {
            switch key {
            case "⌫": delete()
            case "✓": submit()
            default: append(key)
            }
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left").font(.system(size: 20, weight: .medium))
                } else if key == "✓" {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                } else {
                    Text(key).font(CCFont.rounded(26, weight: .medium))
                }
            }
            .foregroundStyle(key == "✓" ? (digits.count == 6 ? Color(hex: 0x0A0A0F) : CC.text3) : CC.text)
            .frame(width: 92, height: 54)
            .background {
                if key == "✓" {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(digits.count == 6 ? CC.accent : CC.elevated)
                } else {
                    KeyFace(radius: 14)
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private func append(_ digit: String) {
        guard digits.count < 6 else { return }
        Feedback.tap()
        digits.append(digit)
        if digits.count == 6 { submit() }
    }

    private func delete() {
        guard !digits.isEmpty else { return }
        Feedback.tap()
        digits.removeLast()
    }

    private func submit() {
        guard digits.count == 6 else { return }
        model.connection.submitCode(digits)
    }
}
