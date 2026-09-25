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

/// The physical key: rounded 16 pt, a faint top bevel, a subtle inner shadow at
/// rest, tinted for coloured keys, and an acknowledgement ring when the Mac
/// confirms (accent) or refuses (red + shake) the action.
struct KeyFace: View {
    var color: KeyColor = .neutral
    var feedback: KeyFeedback?
    var holdProgress: Double = 0
    var radius: CGFloat = Metrics.radius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(colors: [CC.elevatedTop, CC.elevated], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.45), radius: 2.5, x: 0, y: 1.5))
            )
            if color != .neutral {
                shape.fill(CC.key(color).opacity(0.12))
            }
            if holdProgress > 0 {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(CC.red.opacity(0.35 + holdProgress * 0.3))
                        .frame(width: proxy.size.width * holdProgress)
                }
                .clipShape(shape)
            }
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.09), .white.opacity(0.0)], startPoint: .top, endPoint: .center),
                lineWidth: 1
            )
            shape.strokeBorder(borderColor, lineWidth: feedback == nil ? 1 : 1.6)
        }
        .animation(.easeOut(duration: 0.3), value: feedback)
    }

    private var borderColor: Color {
        switch feedback {
        case .pending: CC.accent.opacity(0.55)
        case .success: CC.accent.opacity(0.95)
        case .failure: CC.red.opacity(0.95)
        case nil: color == .neutral ? CC.divider.opacity(0.9) : CC.key(color).opacity(0.32)
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
        let iconSize = min(30, max(18, size.height * 0.27))
        Button {
            if editing { onEdit?(); return }
            if key.confirm == .hold { return }
            model.tap(key, pageID: pageID)
        } label: {
            VStack(spacing: compact ? 5 : 7) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: key.symbol ?? "circle.dashed")
                        .font(.system(size: iconSize, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CC.keyTint(key.color))
                        .frame(height: iconSize + 4)
                    if key.action.needsSetup {
                        Circle().fill(CC.orange).frame(width: 7, height: 7).offset(x: 9, y: -3)
                    }
                }
                Text(key.label)
                    .font(.system(size: compact ? 12.5 : 14, weight: .medium))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if !key.displayCaption.isEmpty, size.height >= 64 {
                    Text(key.displayCaption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: size.width, height: size.height)
            .background(KeyFace(color: key.color, feedback: feedback, holdProgress: holdProgress))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
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

/// Row key: icon left, label, caption right — for commands and bookmarks.
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
                Image(systemName: key.symbol ?? "circle.dashed")
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CC.keyTint(key.color))
                    .frame(width: 24)
                Text(key.label)
                    .font(.system(size: 15, weight: .medium, design: key.action.typeName == "text" ? .monospaced : .default))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                if key.action.needsSetup {
                    Text("SET UP").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(CC.orange)
                } else if !key.displayCaption.isEmpty {
                    Text(key.displayCaption)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                } else if key.action.promptsForInput {
                    Image(systemName: "keyboard").font(.system(size: 12)).foregroundStyle(CC.text3)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(KeyFace(color: key.color, feedback: model.keyFeedback[key.id], holdProgress: holdProgress, radius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .modifier(HoldGesture(enabled: key.confirm == .hold && !editing, progress: $holdProgress) {
            Feedback.heavy()
            model.tap(key, pageID: pageID, confirmed: true)
        })
    }
}

/// Large action button: 80 pt tall, bold, full or half width — PAUSE, RESUME, START.
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

    var body: some View {
        Button {
            guard !hold else { return }
            Feedback.tap()
            action()
        } label: {
            ZStack {
                let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                if style == .filled {
                    shape.fill(LinearGradient(colors: [color.opacity(0.98), color.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .white.opacity(0.25), radius: 1, x: 0, y: 1)))
                } else {
                    shape.fill(color.opacity(0.13 + holdProgress * 0.4))
                    shape.strokeBorder(color.opacity(0.45 + holdProgress * 0.5), lineWidth: 1)
                }
                if holdProgress > 0 {
                    GeometryReader { proxy in
                        Rectangle().fill(color.opacity(0.45)).frame(width: proxy.size.width * holdProgress)
                    }
                    .clipShape(shape)
                }
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: height > 64 ? 22 : 18, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased())
                            .font(.system(size: height > 64 ? 17 : 15, weight: .bold))
                            .tracking(1.2)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .opacity(0.75)
                        }
                    }
                }
                .foregroundStyle(style == .filled ? Color(hex: 0x0A0A0F) : color)
                .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
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
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .shadow(color: color.opacity(0.6), radius: 4)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

/// Status pill: "● RUNNING", "SIM", "LIVE".
struct Pill: View {
    let text: String
    var color: Color = CC.accent
    var symbol: String?
    var dot = false

    var body: some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(color).frame(width: 6, height: 6) }
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.9)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

/// Label over a big value — the Bloomberg stat block.
struct Stat: View {
    let label: String
    let value: String
    var color: Color = CC.text
    var size: CGFloat = 22
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(CCFont.number(size))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: max(11, size * 0.5), weight: .medium))
                        .foregroundStyle(CC.text2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Gauges

struct RingGauge: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 14
    var track: Color = CC.elevated

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.65), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(1, value)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.35), radius: 6)
                .opacity(value > 0.002 ? 1 : 0)
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
                Capsule().fill(CC.elevated)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
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
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, load in
                let isEfficiency = index < efficiency
                GeometryReader { proxy in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isEfficiency ? CC.accent.opacity(0.55) : CC.load(load))
                            .frame(height: max(2, proxy.size.height * load))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(CC.elevated.opacity(0.7)))
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
                        .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    }
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 3, height: lineWidth * 3)
                        .position(points[points.count - 1])
                        .shadow(color: color, radius: 4)
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
                    y: size.height - size.height * CGFloat((value - low) / span) * 0.92 - size.height * 0.04)
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
            .foregroundStyle(colored ? CC.pnl(value) : CC.text)
            .contentTransition(.numericText(value: value))
            .animation(.snappy(duration: 0.45), value: value)
            .animation(.easeInOut(duration: 0.3), value: value >= 0)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - App icons

/// The real Mac app icon (from the helper), falling back to an SF Symbol tile.
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
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [CC.elevatedTop, CC.elevated], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: Self.symbol(for: bundleID) ?? fallback).font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(CC.accent))
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
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(CC.accent)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CC.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(CC.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CC.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(CC.accent.opacity(0.14)))
                    .buttonStyle(PressStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header row used by most cards: label, optional pill, optional trailing view.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CC.accent)
            }
            SectionLabel(title)
            Spacer(minLength: 6)
            trailing()
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.trailing = { EmptyView() }
    }
}
