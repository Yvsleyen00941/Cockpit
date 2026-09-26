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
    static func dynamic(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let isLight = traits.userInterfaceStyle == .light
            let hex = isLight ? light : dark
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: isLight ? lightAlpha : darkAlpha)
        })
    }

    /// Ink or white — whichever reads better on a fill of this colour.
    func legibleText(in scheme: ColorScheme) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .light ? .light : .dark)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.039_28 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.32 ? CC.ink : .white
    }
}

/// Two scenes from one set of tokens: **Cobalt** (dark, the product) — an
/// ultramarine atmosphere with frosted glass — and **Porcelain** (light).
/// One cool hue family; saturated colour is kept for meaning: profit, loss,
/// status, and the light a page is lit with.
enum CC {
    /// Deep ink — the darkest thing on screen, and text on bright fills.
    static let ink = Color(hex: 0x060B26)

    // Surfaces
    static let bg = Color.dynamic(dark: 0x060B26, light: 0xE9EEF8)
    /// Opaque panel colour, for the few places glass can't go.
    static let card = Color.dynamic(dark: 0x101C58, light: 0xF8FAFF)
    static let cardTop = Color.dynamic(dark: 0x18286E, light: 0xFFFFFF)
    /// Insets on glass: rows, wells, key faces. Translucent on purpose.
    static let elevated = Color.dynamic(dark: 0xFFFFFF, light: 0xFFFFFF, darkAlpha: 0.075, lightAlpha: 0.6)
    static let elevatedTop = Color.dynamic(dark: 0xFFFFFF, light: 0xFFFFFF, darkAlpha: 0.12, lightAlpha: 0.85)
    /// Gauge and slider tracks.
    static let track = Color.dynamic(dark: 0xFFFFFF, light: 0x1B2A5C, darkAlpha: 0.085, lightAlpha: 0.09)
    static let divider = Color.dynamic(dark: 0xFFFFFF, light: 0x1B2A5C, darkAlpha: 0.09, lightAlpha: 0.1)

    // Text
    static let text = Color.dynamic(dark: 0xF3F6FF, light: 0x0B1230)
    static let text2 = Color.dynamic(dark: 0xA4AFD6, light: 0x55607F)
    static let text3 = Color.dynamic(dark: 0x6A76A6, light: 0x8B94B2)
    /// Icons on neutral keys: near-white, so colour on a key always means something.
    static let icon = Color.dynamic(dark: 0xDDE4FF, light: 0x27335A)

    // Signal
    static let accent = Color.dynamic(dark: 0x5C87FF, light: 0x2F54F5)
    static let orange = Color.dynamic(dark: 0xFF9A4D, light: 0xEC7718)
    static let green = Color.dynamic(dark: 0x3EE39A, light: 0x0C9A5F)
    static let red = Color.dynamic(dark: 0xFF5C7A, light: 0xDC3350)
    static let yellow = Color.dynamic(dark: 0xFFCB52, light: 0xC98F00)
    static let purple = Color.dynamic(dark: 0xA88BFF, light: 0x7753EC)
    static let pink = Color.dynamic(dark: 0xFF79C0, light: 0xD2459A)
    static let teal = Color.dynamic(dark: 0x3FDCCF, light: 0x0B978F)
    static let indigo = Color.dynamic(dark: 0x8C96FF, light: 0x505EE4)

    static var cardBorder: Color { divider }

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

    /// Icon tint on a key: neutral keys stay near-white.
    static func keyTint(_ color: KeyColor) -> Color {
        color == .neutral ? icon : key(color)
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
        return Color(hex: UInt32(clean, radix: 16) ?? 0x5C87FF)
    }
}

// MARK: - Type

/// SF Pro throughout. Big numbers are light and let their size do the work;
/// labels are sentence case; digits are always monospaced so nothing jitters.
enum CCFont {
    /// Hero numbers — P&L, timers, temperatures: SF Pro Display Light.
    static func display(_ size: CGFloat = 56) -> Font { .system(size: size, weight: .light).monospacedDigit() }
    /// Section headings.
    static func heading(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .semibold) }
    /// Large running text — greetings, event titles.
    static func title(_ size: CGFloat = 28, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func button(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold) }
    static let label = Font.system(size: 13, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
    static func number(_ size: CGFloat, weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight).monospacedDigit() }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
    /// Wide display type — the scene's watermark titles.
    static func wide(_ size: CGFloat, weight: Font.Weight = .ultraLight) -> Font { .system(size: size, weight: weight).width(.expanded) }
}

// MARK: - Metrics

enum Metrics {
    static let radius: CGFloat = 26
    static let keyRadius: CGFloat = 18
    static let gap: CGFloat = 14
    static let topBar: CGFloat = 62
    /// The dock plus its margin.
    static let strip: CGFloat = 86
    static let dock: CGFloat = 72
    static let key: CGFloat = 72
    static let compactKey: CGFloat = 54
    static let largeButton: CGFloat = 72
    static let cardPadding: CGFloat = 18
}

// MARK: - Glass

/// Everything sits on the scene as frosted glass: a sheen that falls from the
/// top-left (where the scene's key light is), a refraction edge that catches
/// that light, and a shadow tinted with the scene's ink instead of black.
enum Glass {
    /// The glass's own colour: the system material is neutral grey, so it's
    /// tinted with the scene's cobalt — the blue behind it stays blue.
    static func body(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .light
            ? LinearGradient(colors: [Color(hex: 0xF4F7FF, alpha: 0.35), Color(hex: 0xE3E9FB, alpha: 0.3)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(hex: 0x1C2F9C, alpha: 0.34), Color(hex: 0x0B1560, alpha: 0.46)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func sheen(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .light
            ? LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.02), .white.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func edge(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .light
            ? LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white.opacity(0.6), location: 0.45), .init(color: Color(hex: 0x9AA9D6, alpha: 0.35), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0.08), location: 0.35), .init(color: .white.opacity(0.03), location: 0.7), .init(color: .white.opacity(0.1), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x2A3A7A, alpha: 0.14) : Color(hex: 0x020619, alpha: 0.5)
    }
}
