import CCCore
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Mood

/// The light a page is lit with. Every tile is glass, so the mood tints the
/// whole surface — the page feels like one place, not a grid of boxes.
struct SceneMood: Equatable {
    struct Lights: Equatable {
        /// Top-left: the key light. Glass edges catch it.
        var key: UInt32
        /// Right: the fill light.
        var fill: UInt32
        /// Low: the page's accent colour.
        var accent: UInt32
    }

    var name: String
    var dark: Lights
    var light: Lights
    var accentStrength: Double = 1

    func lights(_ scheme: ColorScheme) -> Lights { scheme == .light ? light : dark }

    static let cobalt = SceneMood(name: "cobalt",
                                  dark: .init(key: 0x2A4CF5, fill: 0x4A30DE, accent: 0x1C78F0),
                                  light: .init(key: 0xA8BBFF, fill: 0xCBBDFF, accent: 0xA9D2FF))
    static let sunrise = SceneMood(name: "sunrise",
                                   dark: .init(key: 0x3047E6, fill: 0x8649E6, accent: 0xFF7436),
                                   light: .init(key: 0xB3C1FF, fill: 0xE4C4FF, accent: 0xFFC49B))
    static let trading = SceneMood(name: "trading",
                                   dark: .init(key: 0x2644F2, fill: 0x2D2CB8, accent: 0x0EAFA3),
                                   light: .init(key: 0xA6B8FF, fill: 0xBBB8F7, accent: 0x9EE4D8))
    static let study = SceneMood(name: "study",
                                 dark: .init(key: 0x3B36E8, fill: 0x8451EE, accent: 0x3A78F5),
                                 light: .init(key: 0xB3B3FF, fill: 0xDAC4FF, accent: 0xB1CBFF))
    static let meeting = SceneMood(name: "meeting",
                                   dark: .init(key: 0x2153F0, fill: 0x0A8CAB, accent: 0x16AE78),
                                   light: .init(key: 0xA9C0FF, fill: 0xA2DBE8, accent: 0xA6E6C6))
    static let machine = SceneMood(name: "machine",
                                   dark: .init(key: 0x255AE8, fill: 0x1D3596, accent: 0x2FA6F0),
                                   light: .init(key: 0xA8C3FF, fill: 0xB8C3EE, accent: 0xADDBFF))
    static let markets = SceneMood(name: "markets",
                                   dark: .init(key: 0x2546E8, fill: 0x13707A, accent: 0x10B57F),
                                   light: .init(key: 0xA8BAFF, fill: 0xA5DCD5, accent: 0xA7EACD))
    static let terminal = SceneMood(name: "terminal",
                                    dark: .init(key: 0x2140D6, fill: 0x0C6A5C, accent: 0x1FC388),
                                    light: .init(key: 0xAABAF7, fill: 0xA4D9CE, accent: 0xA8E9C9))
    static let graphite = SceneMood(name: "graphite",
                                    dark: .init(key: 0x2E3D96, fill: 0x3B4170, accent: 0x5868B8),
                                    light: .init(key: 0xB9C3EA, fill: 0xC9CCE0, accent: 0xC3CDF0))
    static let safari = SceneMood(name: "safari",
                                  dark: .init(key: 0x1F5DF5, fill: 0x2C40D2, accent: 0x20B6F0),
                                  light: .init(key: 0xA6C1FF, fill: 0xB9C0FA, accent: 0xA5E0FA))
    static let xcode = SceneMood(name: "xcode",
                                 dark: .init(key: 0x2A4CF5, fill: 0x3F30D8, accent: 0x2D9BFF),
                                 light: .init(key: 0xA9BBFF, fill: 0xC3BCFA, accent: 0xA8D4FF))
    static let night = SceneMood(name: "night",
                                 dark: .init(key: 0x16237E, fill: 0x231764, accent: 0x0E2E7E),
                                 light: .init(key: 0xBAC6F2, fill: 0xCFC7F0, accent: 0xBFD4F4),
                                 accentStrength: 0.7)

    static func page(_ id: String?) -> SceneMood {
        switch id {
        case "brief": .sunrise
        case "bot": .trading
        case "study": .study
        case "meeting": .meeting
        case "mac", "app.finder": .machine
        case "markets": .markets
        case "app.terminal": .terminal
        case "app.notion": .graphite
        case "app.safari": .safari
        case "app.xcode": .xcode
        default: .cobalt
        }
    }
}

// MARK: - Backdrop

/// The atmosphere behind everything: a deep base, three soft lights, a
/// vignette and fine film grain. Rendered once into a single layer — it only
/// changes when the mood does.
struct SceneBackdrop: View {
    var mood: SceneMood
    /// Huge, faint type behind the glass ("Control Center", the time).
    var watermark: String?
    /// Extra darkness for ambient mode and dimmed states.
    var dim: Double = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let lights = mood.lights(scheme)
            let span = max(proxy.size.width, proxy.size.height)
            let dark = scheme != .light
            ZStack {
                LinearGradient(
                    colors: dark ? [Color(hex: 0x0B1654), Color(hex: 0x060B26)] : [Color(hex: 0xEEF2FB), Color(hex: 0xE2E8F5)],
                    startPoint: .top, endPoint: .bottom
                )
                bloom(lights.key, center: UnitPoint(x: 0.08, y: -0.1), radius: span * 0.8, strength: dark ? 0.95 : 0.85)
                bloom(lights.fill, center: UnitPoint(x: 1.06, y: 0.36), radius: span * 0.62, strength: dark ? 0.62 : 0.7)
                bloom(lights.accent, center: UnitPoint(x: 0.62, y: 1.06), radius: span * 0.6, strength: (dark ? 0.58 : 0.62) * mood.accentStrength)
                RadialGradient(
                    colors: [.clear, dark ? Color(hex: 0x03061A, alpha: 0.62) : Color(hex: 0xB9C4E4, alpha: 0.35)],
                    center: .center, startRadius: span * 0.3, endRadius: span * 0.82
                )
                if let watermark {
                    Text(watermark)
                        .font(CCFont.wide(min(240, proxy.size.width * 0.19)))
                        .foregroundStyle(dark ? Color.white.opacity(0.075) : Color(hex: 0x0B1230, alpha: 0.05))
                        .lineLimit(2)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 40)
                        .padding(.top, 70)
                }
                Grain(opacity: dark ? 0.16 : 0.1)
                if dim > 0 {
                    Color(hex: 0x02040F).opacity(dim)
                }
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bloom(_ hex: UInt32, center: UnitPoint, radius: CGFloat, strength: Double) -> some View {
        let color = Color(hex: hex)
        return RadialGradient(
            stops: [
                .init(color: color.opacity(strength), location: 0),
                .init(color: color.opacity(strength * 0.42), location: 0.45),
                .init(color: color.opacity(0), location: 1),
            ],
            center: center, startRadius: 0, endRadius: radius
        )
    }
}

/// Monochrome film grain, generated once and tiled — it breaks up the
/// gradients the way the texture on a print does.
struct Grain: View {
    var opacity: Double

    var body: some View {
        Image(uiImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }

    private static let tile: UIImage = {
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage.empty()
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.1])
        let area = CGRect(x: 0, y: 0, width: 180, height: 180)
        guard let image = CIContext().createCGImage(mono.cropped(to: area), from: area) else { return UIImage() }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()
}

// MARK: - Glass pieces

/// The glass material in any shape — the dock, capsules, circle buttons.
struct GlassShape<S: InsettableShape>: View {
    var shape: S
    var tint: Color?
    var shadow = true
    /// The outline its shadow follows.
    var outline: ShadowPlate.Outline = .capsule
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Glass.body(scheme)))
            .overlay(shape.fill(Glass.sheen(scheme)))
            .overlay {
                if let tint { shape.fill(tint) }
            }
            .overlay(shape.strokeBorder(Glass.edge(scheme), lineWidth: 1))
            .background {
                if shadow { ShadowPlate(outline: outline, color: Glass.shadow(scheme), radius: 16, y: 8) }
            }
    }
}

/// An inset well on glass — what the dock's live capsules and a tile's
/// rows sit in.
struct Well: View {
    var radius: CGFloat = 16
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(CC.elevated))
            .overlay(shape.strokeBorder(tint?.opacity(0.28) ?? CC.divider, lineWidth: 1))
    }
}

/// A small lit sphere — the status light for the connection, the mic, Focus.
struct GlossyOrb: View {
    var color: Color
    var size: CGFloat = 12
    var glow = true

    var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.38)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: size * 0.1, endRadius: size * 0.72))
            Circle().fill(RadialGradient(colors: [.white.opacity(0.9), .white.opacity(0)], center: UnitPoint(x: 0.34, y: 0.27), startRadius: 0, endRadius: size * 0.32))
        }
        .frame(width: size, height: size)
        .glow(glow ? color : .clear, spread: size * 0.7, opacity: 0.65, y: 0)
    }
}

/// The circular icon badge that opens every tile header.
struct IconOrb: View {
    let symbol: String
    var tint: Color = CC.accent
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
}

/// A round glass button — the top bar's tools.
struct GlassIconButton: View {
    let symbol: String
    var active = false
    var size: CGFloat = 42
    var help: String
    let action: () -> Void

    var body: some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundStyle(active ? CC.accent : CC.icon)
                .frame(width: size, height: size)
                .background(GlassShape(shape: Circle(), tint: active ? CC.accent.opacity(0.2) : nil, shadow: false))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(help)
    }
}

/// A full-width primary capsule — cobalt, lit from above, glowing softly.
struct GlowCapsuleStyle: ButtonStyle {
    var color: Color = CC.accent
    var height: CGFloat = 46
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color.legibleText(in: scheme))
            .padding(.horizontal, 22)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.92), color], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .glow(color, spread: 12, opacity: 0.42, y: 6)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Cheap light

/// A drop shadow drawn by Core Animation from a fixed path. The system
/// composites it, so live content on top never makes it re-blur — a SwiftUI
/// `.shadow` on a tile would be re-rendered every time a number in it ticks.
struct ShadowPlate: UIViewRepresentable {
    enum Outline: Equatable {
        case rounded(CGFloat)
        case capsule
    }

    var outline: Outline
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    func makeUIView(context: Context) -> PlateView {
        let view = PlateView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlateView, context: Context) {
        view.outline = outline
        view.layer.shadowColor = UIColor(color).cgColor
        view.layer.shadowOpacity = 1
        view.layer.shadowRadius = radius / 2
        view.layer.shadowOffset = CGSize(width: 0, height: y)
        view.setNeedsLayout()
    }

    final class PlateView: UIView {
        var outline: Outline = .rounded(Metrics.radius)

        override func layoutSubviews() {
            super.layoutSubviews()
            let corner: CGFloat = switch outline {
            case .rounded(let radius): radius
            case .capsule: min(bounds.width, bounds.height) / 2
            }
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: corner).cgPath
        }
    }
}

extension View {
    /// A soft light behind the view, painted as an elliptical gradient that
    /// follows its shape. No blur — free to redraw with live content.
    func glow(_ color: Color, spread: CGFloat = 14, opacity: Double = 0.45, y: CGFloat = 5) -> some View {
        background(
            EllipticalGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), color.opacity(0)], center: .center, startRadiusFraction: 0.2, endRadiusFraction: 0.5)
                .padding(-spread)
                .offset(y: y)
                .allowsHitTesting(false)
        )
    }
}
