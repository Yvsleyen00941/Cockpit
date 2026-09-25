import CCCore
import SwiftUI
import UIKit

// MARK: - Colour

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// A colour that follows light/dark — so the Theme setting and the system
    /// appearance just work, in the app and in widgets alike.
    static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .light ? light : dark
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// The blueprint palette. Dark is the product; light is a faithful inversion.
enum CC {
    // Surfaces
    static let bg = Color.dynamic(dark: 0x0A0A0F, light: 0xF2F3F6)
    static let card = Color.dynamic(dark: 0x16213E, light: 0xFFFFFF)
    /// Card background 3 % lighter — the top stop of every card's gradient.
    static let cardTop = Color.dynamic(dark: 0x1D2844, light: 0xFFFFFF)
    static let elevated = Color.dynamic(dark: 0x1A2A4A, light: 0xEDF0F5)
    static let elevatedTop = Color.dynamic(dark: 0x21335A, light: 0xF6F8FB)
    static let divider = Color.dynamic(dark: 0x2A2A3A, light: 0xDDE1E8)

    // Text
    static let text = Color.dynamic(dark: 0xF0F0F0, light: 0x0E1016)
    static let text2 = Color.dynamic(dark: 0x888888, light: 0x6A6F7B)
    static let text3 = Color.dynamic(dark: 0x565A6B, light: 0xA2A7B2)

    // Signal
    static let accent = Color.dynamic(dark: 0x2E86AB, light: 0x2277A0)
    static let orange = Color.dynamic(dark: 0xF18F01, light: 0xDD8000)
    static let green = Color.dynamic(dark: 0x2ECC71, light: 0x19A457)
    static let red = Color.dynamic(dark: 0xE74C3C, light: 0xD33A2B)
    static let yellow = Color.dynamic(dark: 0xF5C518, light: 0xCF9F00)
    static let purple = Color.dynamic(dark: 0x9B6BD6, light: 0x7E4FC0)
    static let pink = Color.dynamic(dark: 0xE8609A, light: 0xCC4580)
    static let teal = Color.dynamic(dark: 0x1FBFA8, light: 0x0E9C87)
    static let indigo = Color.dynamic(dark: 0x6272F0, light: 0x4B5BD6)

    static var cardBorder: Color { accent.opacity(0.2) }

    static func key(_ color: KeyColor) -> Color {
        switch color {
        case .neutral: text
        case .blue: accent
        case .orange: orange
        case .green: green
        case .red: red
        case .yellow: yellow
        case .purple: purple
        case .pink: pink
        case .teal: teal
        case .indigo: indigo
        }
    }

    /// Icon tint on a key: neutral keys use the accent blue.
    static func keyTint(_ color: KeyColor) -> Color {
        color == .neutral ? accent : key(color)
    }

    static func pnl(_ value: Double) -> Color { value >= 0 ? green : red }

    static func recovery(_ score: Double) -> Color {
        switch RecoveryZone(score: score) {
        case .green: green
        case .yellow: yellow
        case .red: red
        }
    }

    static func load(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: accent
        case ..<0.9: orange
        default: red
        }
    }

    static func hex(_ text: String) -> Color {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        return Color(hex: UInt32(clean, radix: 16) ?? 0x2E86AB)
    }
}

// MARK: - Type

/// SF Pro everywhere; digits are always monospaced so numbers never jitter.
enum CCFont {
    /// P&L, timers: SF Pro Display Bold 48–64 pt, monospaced digits.
    static func display(_ size: CGFloat = 56) -> Font { .system(size: size, weight: .bold).monospacedDigit() }
    /// Section headings: SF Pro Display Semibold 20–24 pt.
    static func heading(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .semibold) }
    /// Button labels: SF Pro Text Medium 15–17 pt.
    static func button(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .medium) }
    /// Widget labels: SF Pro Text Regular 13 pt, secondary colour.
    static let label = Font.system(size: 13)
    /// Log / feed entries: SF Mono Regular 12 pt.
    static let mono = Font.system(size: 12, design: .monospaced)
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight).monospacedDigit() }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
}

// MARK: - Metrics

enum Metrics {
    static let radius: CGFloat = 16
    static let gap: CGFloat = 12
    static let topBar: CGFloat = 50
    static let strip: CGFloat = 80
    static let key: CGFloat = 72
    static let compactKey: CGFloat = 60
    static let largeButton: CGFloat = 80
    static let cardPadding: CGFloat = 16
}

// MARK: - Card

/// Cards: 16 pt radius, a 1 pt accent border at 20 %, a gradient from the
/// card colour to 3 % lighter at the top. No drop shadows — borders define edges.
struct CardBackground: View {
    var highlight: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [CC.cardTop, CC.card], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder((highlight ?? CC.accent).opacity(highlight == nil ? 0.2 : 0.55), lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = Metrics.cardPadding, highlight: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CardBackground(highlight: highlight))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }
}

/// Small tracked uppercase label — the "terminal" voice of every card.
struct SectionLabel: View {
    let text: String
    var color: Color = CC.text2

    init(_ text: String, color: Color = CC.text2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .regular))
            .tracking(1.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
