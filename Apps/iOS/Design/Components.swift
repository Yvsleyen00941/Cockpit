import CCCore
import SwiftUI

// MARK: - Press

/// Keys compress to 0.96 on touch and brighten a touch — tactile without haptics.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

// MARK: - Key face

/// A glass keycap: a face that's lighter at the top, an edge that catches the
/// scene's light, a coloured glow from below for coloured keys, and a lit ring
/// when the Mac confirms (accent) or refuses (red + shake) the action.
struct KeyFace: View {
    var color: KeyColor = .neutral
    var feedback: KeyFeedback?
    var holdProgress: Double = 0
    var radius: CGFloat = Metrics.keyRadius
    /// Wide keys wash their colour in from the icon side instead of glowing from below.
    var wide = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let tint: Color? = color == .neutral ? nil : CC.key(color)
        let light = scheme == .light
        ZStack {
            shape.fill(LinearGradient(
                colors: light ? [.white.opacity(0.92), .white.opacity(0.62)] : [.white.opacity(0.095), .white.opacity(0.04)],
                startPoint: .top, endPoint: .bottom
            ))
            if let tint {
                if wide {
                    shape.fill(LinearGradient(stops: [.init(color: tint.opacity(light ? 0.16 : 0.2), location: 0), .init(color: tint.opacity(0), location: 0.5)], startPoint: .leading, endPoint: .trailing))
                } else {
                    shape.fill(RadialGradient(colors: [tint.opacity(light ? 0.2 : 0.3), tint.opacity(0)], center: UnitPoint(x: 0.5, y: 1.1), startRadius: 0, endRadius: max(60, radius * 5)))
                }
            }
            if holdProgress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(CC.red.opacity(0.3 + holdProgress * 0.3))
                        .frame(width: proxy.size.width * holdProgress)
                }
                .clipShape(shape)
            }
            shape.strokeBorder(LinearGradient(
                colors: tint.map { [$0.opacity(0.55), $0.opacity(0.12)] } ?? (light ? [.white, Color(hex: 0x9AA9D6, alpha: 0.4)] : [.white.opacity(0.24), .white.opacity(0.05)]),
                startPoint: .top, endPoint: .bottom
            ), lineWidth: 1)
            if let ring = feedbackColor {
                shape.strokeBorder(ring.opacity(0.25), lineWidth: 5)
                shape.strokeBorder(ring, lineWidth: 1.8)
            }
        }
        .animation(.easeOut(duration: 0.3), value: feedback)
    }

    private var feedbackColor: Color? {
        switch feedback {
        case .pending: CC.accent.opacity(0.6)
        case .success: CC.accent
        case .failure: CC.red
        case nil: nil
        }
    }
}

/// Shakes horizontally when `trigger` flips to a failure.
struct Shake: GeometryEffect {
    var travel: CGFloat = 5
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}

// MARK: - Keys

/// Standard key: SF Symbol above the label, shortcut glyphs underneath.
struct KeyButton: View {
    let key: ButtonDef
    var pageID: String?
    var size: CGSize = CGSize(width: Metrics.key, height: Metrics.key)
    var editing = false
    var onEdit: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var shake: CGFloat = 0
    @State private var holdProgress: Double = 0
    @State private var holding = false

    private var feedback: KeyFeedback? { model.keyFeedback[key.id] }

    var body: some View {
        let compact = size.height < 90
        let iconSize = min(28, max(18, size.height * 0.26))
        Button {
            if editing { onEdit?(); return }
            if key.confirm == .hold { return }
            model.tap(key, pageID: pageID)
        } label: {
            VStack(spacing: compact ? 5 : 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: key.symbol ?? "circle.dashed")
                        .font(.system(size: iconSize, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CC.keyTint(key.color))
                        .frame(height: iconSize + 4)
                    if key.action.needsSetup {
                        GlossyOrb(color: CC.orange, size: 8).offset(x: 9, y: -3)
                    }
                }
                Text(key.label)
                    .font(.system(size: compact ? 13 : 14, weight: .medium))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if !key.displayCaption.isEmpty, size.height >= 64 {
                    Text(key.displayCaption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CC.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: size.width, height: size.height)
            .background(KeyFace(color: key.color, feedback: feedback, holdProgress: holdProgress))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .modifier(Shake(animatableData: shake))
        .onChange(of: feedback) { _, value in
            if case .failure = value {
                withAnimation(.linear(duration: 0.36)) { shake += 1 }
            }
        }
        .modifier(HoldGesture(enabled: key.confirm == .hold && !editing, progress: $holdProgress) {
            Feedback.heavy()
            model.tap(key, pageID: pageID, confirmed: true)
        })
        .accessibilityLabel(key.label)
        .accessibilityHint(key.action.summary)
    }
}

/// Press-and-hold confirmation: the key fills red over 1.2 s; release early
/// to cancel. The blueprint's "colour changes on long-press to signal a
/// destructive action".
struct HoldGesture: ViewModifier {
    var enabled: Bool
    @Binding var progress: Double
    var duration: Double = 1.2
    var onComplete: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
                progress = 0
                onComplete()
            } onPressingChanged: { pressing in
                if pressing {
                    Feedback.tap()
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
                }
            }
        } else {
            content
        }
    }
}

/// Row key: icon badge, label, caption on the right — for commands and bookmarks.
struct RowKey: View {
    let key: ButtonDef
    var pageID: String?
    var height: CGFloat = 52
    var editing = false
    var onEdit: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var holdProgress: Double = 0

    var body: some View {
        Button {
            if editing { onEdit?(); return }
            if key.confirm == .hold { return }
            model.tap(key, pageID: pageID)
        } label: {
            HStack(spacing: 12) {
                IconOrb(symbol: key.symbol ?? "circle.dashed", tint: key.color == .neutral ? CC.accent : CC.key(key.color), size: min(34, height - 16))
                Text(key.label)
                    .font(.system(size: 15, weight: .medium, design: key.action.typeName == "text" ? .monospaced : .default))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if key.action.needsSetup {
                    Text("Set up").font(.system(size: 12, weight: .semibold)).foregroundStyle(CC.orange)
                } else if !key.displayCaption.isEmpty {
                    Text(key.displayCaption)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CC.text3)
                        .lineLimit(1)
                } else if key.action.promptsForInput {
                    Image(systemName: "keyboard").font(.system(size: 12)).foregroundStyle(CC.text3)
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(KeyFace(color: key.color, feedback: model.keyFeedback[key.id], holdProgress: holdProgress, radius: min(18, height / 2), wide: true))
            .contentShape(RoundedRectangle(cornerRadius: min(18, height / 2), style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .modifier(HoldGesture(enabled: key.confirm == .hold && !editing, progress: $holdProgress) {
            Feedback.heavy()
            model.tap(key, pageID: pageID, confirmed: true)
        })
    }
}

/// A big action — PAUSE, RESUME, START. Filled: lit from above with a soft
/// glow in its own colour. Tinted: glass washed with the colour, for actions
/// that shouldn't shout (or need a hold).
struct LargeActionButton: View {
    enum Style { case filled, tinted }

    let title: String
    let symbol: String
    let color: Color
    var style: Style = .filled
    var height: CGFloat = Metrics.largeButton
    var enabled = true
    var hold = false
    var subtitle: String?
    let action: () -> Void

    @State private var holdProgress: Double = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let radius = height <= 60 ? height / 2 : 24
        Button {
            guard !hold else { return }
            Feedback.tap()
            action()
        } label: {
            ZStack {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if style == .filled {
                    shape.fill(LinearGradient(colors: [color.opacity(0.86), color], startPoint: .top, endPoint: .bottom))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    shape.strokeBorder(.white.opacity(0.3), lineWidth: 1)
                } else {
                    shape.fill(color.opacity((scheme == .light ? 0.1 : 0.13) + holdProgress * 0.4))
                    shape.strokeBorder(LinearGradient(colors: [color.opacity(0.5 + holdProgress * 0.4), color.opacity(0.18 + holdProgress * 0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                if holdProgress > 0 {
                    GeometryReader { proxy in
                        Rectangle().fill(color.opacity(0.4)).frame(width: proxy.size.width * holdProgress)
                    }
                    .clipShape(shape)
                }
                HStack(spacing: height <= 50 ? 7 : 11) {
                    Image(systemName: symbol)
                        .font(.system(size: height > 64 ? 20 : (height <= 50 ? 15 : 17), weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: height > 64 ? 18 : 16, weight: .semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12.5, weight: .medium))
                                .opacity(0.75)
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(style == .filled ? color.legibleText(in: scheme) : color)
                .padding(.horizontal, height <= 50 ? 8 : 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
            .glow(style == .filled && enabled ? color : .clear, spread: 12, opacity: scheme == .light ? 0.28 : 0.4, y: 7)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .modifier(HoldGesture(enabled: hold && enabled, progress: $holdProgress) {
            Feedback.heavy()
            action()
        })
    }
}

// MARK: - Status

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8
    var pulsing = false

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 2.8 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .glow(color, spread: size * 0.8, opacity: 0.55, y: 0)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Status pill: "● Running", "Sim", "Live".
struct Pill: View {
    let text: String
    var color: Color = CC.accent
    var symbol: String?
    var dot = false

    var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            if let symbol { Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)) }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 0.7))
    }
}

/// A small label over a value.
struct Stat: View {
    let label: String
    let value: String
    var color: Color = CC.text
    var size: CGFloat = 22
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: size, weight: size >= 24 ? .light : .regular).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: max(11, size * 0.46), weight: .medium))
                        .foregroundStyle(CC.text2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Gauges

/// A thin ring with a glowing cap where the value ends.
struct RingGauge: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 14
    var track: Color = CC.track

    var body: some View {
        let fraction = max(0.001, min(1, value))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            // The glow: a wider, faint arc under the value — no blur, cheap to redraw.
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color.opacity(0.15), style: StrokeStyle(lineWidth: lineWidth * 1.9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(min(1, fraction * 10))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.35), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * fraction)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(value > 0.002 ? 1 : 0)
            GeometryReader { proxy in
                let radius = (min(proxy.size.width, proxy.size.height) - lineWidth) / 2
                let angle = Angle.degrees(360 * fraction - 90)
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth * 0.5, height: lineWidth * 0.5)
                    .background(Circle().fill(color.opacity(0.55)).frame(width: lineWidth * 1.2, height: lineWidth * 1.2))
                    .position(x: proxy.size.width / 2 + radius * cos(angle.radians), y: proxy.size.height / 2 + radius * sin(angle.radians))
                    .opacity(value > 0.02 ? 0.95 : 0)
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85), value: value)
    }
}

struct BarGauge: View {
    var value: Double
    var color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CC.track)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: value)
    }
}

/// Per-core CPU bars, efficiency cores dimmer.
struct CoreBars: View {
    var cores: [Double]
    var efficiency: Int

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, cores.count)
            let bar = min(20, max(4, (proxy.size.width - CGFloat(count - 1) * 5) / CGFloat(count)))
            let spacing = count > 1 ? (proxy.size.width - bar * CGFloat(count)) / CGFloat(count - 1) : 0
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                    let isEfficiency = index < efficiency
                    let color = isEfficiency ? CC.accent.opacity(0.6) : CC.load(load)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: min(4, bar / 2), style: .continuous).fill(CC.track)
                        RoundedRectangle(cornerRadius: min(4, bar / 2), style: .continuous)
                            .fill(LinearGradient(colors: [color, color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .frame(height: max(3, proxy.size.height * load))
                    }
                    .frame(width: bar)
                }
            }
        }
        .animation(.easeOut(duration: 0.5), value: cores)
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    var fill = true
    var baseline: Double?
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let points = normalized(in: proxy.size)
            if points.count > 1 {
                ZStack {
                    if fill {
                        Path { path in
                            path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                            points.forEach { path.addLine(to: $0) }
                            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                            path.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    }
                    let line = Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    // Glow first: the same line, wide and faint.
                    line.stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: lineWidth * 4, lineCap: .round, lineJoin: .round))
                    line.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(color.opacity(0.25))
                        .frame(width: lineWidth * 7, height: lineWidth * 7)
                        .position(points[points.count - 1])
                    Circle()
                        .fill(.white)
                        .frame(width: lineWidth * 2.6, height: lineWidth * 2.6)
                        .position(points[points.count - 1])
                }
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if let baseline {
            low = min(low, baseline)
            high = max(high, baseline)
        }
        let span = max(high - low, 0.000_001)
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height - size.height * CGFloat((value - low) / span) * 0.88 - size.height * 0.06)
        }
    }
}

// MARK: - Numbers

/// A number that rolls digit by digit when it changes, and crossfades colour.
struct RollingMoney: View {
    var value: Double
    var currency: String = "EUR"
    var signed = true
    var size: CGFloat = 56
    var colored = true
    var decimals = 2

    var body: some View {
        Text(Fmt.money(value, currency: currency, signed: signed, decimals: decimals))
            .font(CCFont.display(size))
            .tracking(-size * 0.02)
            .foregroundStyle(colored ? CC.pnl(value) : CC.text)
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.45), value: value)
            .animation(.easeInOut(duration: 0.3), value: value >= 0)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - App icons

/// The real Mac app icon (from the helper), falling back to a glass tile with
/// an SF Symbol.
struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 24
    var fallback = "app.dashed"

    @Environment(AppModel.self) private var model

    var body: some View {
        if let image = model.images.icon(bundleID) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [CC.accent.opacity(0.42), CC.accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.8))
                .overlay(Image(systemName: Self.symbol(for: bundleID) ?? fallback).font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }

    static func symbol(for bundleID: String?) -> String? {
        switch bundleID {
        case Bundles.safari: "safari"
        case Bundles.xcode: "hammer.fill"
        case Bundles.notion: "doc.richtext"
        case Bundles.terminal, Bundles.iterm, Bundles.warp, Bundles.ghostty: "terminal.fill"
        case Bundles.finder: "folder.fill"
        case Bundles.preview: "doc.viewfinder"
        case Bundles.notes: "note.text"
        case Bundles.mail: "envelope.fill"
        case "com.spotify.client", "com.apple.Music": "music.note"
        case "us.zoom.xos", "com.microsoft.teams2": "video.fill"
        case Bundles.chrome, Bundles.arc: "globe"
        default: nil
        }
    }
}

// MARK: - Empty states

struct SetupPrompt: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            IconOrb(symbol: symbol, tint: CC.accent, size: 52)
                .glow(CC.accent, spread: 16, opacity: 0.35, y: 0)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CC.text)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(CC.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GlowCapsuleStyle(height: 40))
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The header of most tiles: an icon badge, the title, and optional trailing
/// accessories.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = CC.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                IconOrb(symbol: symbol, tint: tint, size: 30)
            }
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CC.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color = CC.accent) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = { EmptyView() }
    }
}

/// The small glass arrow in a tile's corner: this tile opens a page.
struct GoToBadge: View {
    var body: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(CC.text2)
            .frame(width: 28, height: 28)
            .background(Circle().fill(CC.elevated))
            .overlay(Circle().strokeBorder(CC.divider, lineWidth: 1))
    }
}

/// A short tinted tag: BUY, SELL, LONG, SHORT.
struct Tag: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }
}
