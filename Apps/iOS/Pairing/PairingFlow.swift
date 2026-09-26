import CCCore
import SwiftUI

/// First launch: find the Mac, type the code it shows, done. Every future
/// connection is automatic.
struct PairingFlow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connection = model.connection
        ZStack(alignment: .topLeading) {
            SceneBackdrop(mood: .cobalt)
            VStack(alignment: .leading, spacing: -18) {
                Text("Control")
                Text("Center")
            }
            .font(CCFont.wide(128, weight: .thin))
            .foregroundStyle(LinearGradient(colors: [.white.opacity(0.92), Color(hex: 0x8FA8FF, alpha: 0.55)], startPoint: .top, endPoint: .bottom))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.leading, 50)
            .padding(.top, 44)
            .allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 40) {
                brand
                    .frame(maxWidth: 470, alignment: .leading)
                Spacer(minLength: 0)
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
                            progress("Confirming with your Mac…")
                        case .success(let name):
                            success(name)
                        }
                    }
                    .frame(width: 440, height: 560)
                    .background(CardBackground(radius: 36))
                    .animation(.spring(response: 0.4, dampingFraction: 0.86), value: connection.pairing)
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, 52)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .statusBarHidden()
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 18) {
                BrandMark()
                    .frame(width: 76, height: 76)
                Text("Your Mac, at your fingertips — contextual keys, live dashboards and your whole day, next to your keyboard.")
                    .font(.system(size: 17, weight: .regular))
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
                    .buttonStyle(CapsuleButtonStyle(color: CC.text))
                if !model.connection.pairedMacs.isEmpty {
                    Button("Back to my Mac") { model.connection.resumeConnecting() }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text2))
                }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconOrb(symbol: symbol, tint: CC.accent, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CC.text)
                Text(detail).font(.system(size: 14)).foregroundStyle(CC.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        VStack(spacing: 20) {
            Radar().frame(width: 150, height: 150)
            Text(text).font(CCFont.title(20, weight: .light)).foregroundStyle(CC.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func success(_ name: String) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Halo(color: CC.green)
                Circle().fill(LinearGradient(colors: [CC.green.opacity(0.85), CC.green], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .glow(CC.green, spread: 16, opacity: 0.5, y: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(CC.ink)
                    .symbolEffect(.bounce, value: name)
            }
            .frame(width: 96, height: 96)
            Text("Paired with \(name)")
                .font(CCFont.title(26, weight: .light))
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
                .fill(LinearGradient(colors: [Color(hex: 0x2A45D8), Color(hex: 0x0C1552)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RadialGradient(colors: [.white.opacity(0.3), .clear], center: .topLeading, startRadius: 0, endRadius: 70)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .glow(Color(hex: 0x2A45D8), spread: 16, opacity: 0.5, y: 8)
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    tile(Color(hex: 0x5C87FF)) { Sparkline(values: [2, 3, 2.6, 4, 3.6, 5, 4.6, 6], color: .white, fill: false, lineWidth: 1.6).padding(5) }
                    tile(.white.opacity(0.12)) { RingGauge(value: 0.78, color: CC.green, lineWidth: 3).padding(6) }
                }
                GridRow {
                    tile(.white.opacity(0.12)) { Image(systemName: "pause.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(CC.orange) }
                    tile(.white.opacity(0.12)) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach([0.4, 0.75, 0.55], id: \.self) { h in
                                Capsule().fill(CC.accent).frame(width: 4, height: 18 * h)
                            }
                        }
                    }
                }
            }
            .padding(11)
        }
    }

    private func tile<Content: View>(_ color: Color, @ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
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
                    .font(CCFont.title(28, weight: .light))
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
                                    IconOrb(symbol: "laptopcomputer", tint: CC.accent, size: 48)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mac.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(CC.text)
                                        Text(mac.model ?? "ControlCenter Helper").font(.system(size: 13)).foregroundStyle(CC.text2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(CC.text2)
                                        .frame(width: 30, height: 30)
                                        .background(Circle().fill(CC.elevated))
                                }
                                .padding(14)
                                .background(KeyFace(radius: 22))
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
                    .font(CCFont.title(24, weight: .light))
                    .foregroundStyle(CC.text)
                Text(attempt > 1 ? "That didn't match — check \(macName) and try again." : "\(macName) is showing a 6-digit code.")
                    .font(.system(size: 14))
                    .foregroundStyle(attempt > 1 ? CC.orange : CC.text2)
            }
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    let character = index < digits.count ? String(Array(digits)[index]) : ""
                    Text(character)
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .foregroundStyle(CC.text)
                        .frame(width: 46, height: 58)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(index == digits.count ? CC.accent : CC.divider, lineWidth: index == digits.count ? 1.6 : 1))
                        .glow(index == digits.count ? CC.accent : .clear, spread: 8, opacity: 0.45, y: 0)
                    if index == 2 { Spacer().frame(width: 8) }
                }
            }
            Grid(horizontalSpacing: 22, verticalSpacing: 12) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "✓"]], id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keypadKey(key)
                        }
                    }
                }
            }
            Button("Cancel") { model.connection.cancelPairing() }
                .font(.system(size: 15, weight: .medium))
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
                    Image(systemName: "delete.left").font(.system(size: 20, weight: .regular))
                } else if key == "✓" {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .bold))
                } else {
                    Text(key).font(.system(size: 30, weight: .light).monospacedDigit())
                }
            }
            .foregroundStyle(key == "✓" ? (digits.count == 6 ? .white : CC.text3) : CC.text)
            .frame(width: 66, height: 66)
            .background {
                if key == "✓" {
                    Circle()
                        .fill(digits.count == 6 ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6A92FF), Color(hex: 0x3A62F5)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(CC.elevated))
                        .overlay(Circle().strokeBorder(.white.opacity(digits.count == 6 ? 0.3 : 0.08), lineWidth: 1))
                        .glow(digits.count == 6 ? Color(hex: 0x3A62F5) : .clear, spread: 10, opacity: 0.5, y: 0)
                } else {
                    KeyFace(radius: 33)
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
