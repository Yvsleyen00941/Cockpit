import SwiftUI

/// A glass tile. `highlight` washes the glass with a colour from its top-left
/// corner — for states worth noticing (day started, a live call).
struct CardBackground: View {
    var highlight: Color?
    var radius: CGFloat = Metrics.radius
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Glass.body(scheme)))
            .overlay(shape.fill(Glass.sheen(scheme)))
            .overlay {
                if let highlight {
                    shape.fill(RadialGradient(colors: [highlight.opacity(scheme == .light ? 0.2 : 0.26), highlight.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 420))
                }
            }
            .overlay(shape.strokeBorder(Glass.edge(scheme), lineWidth: 1))
            .background(ShadowPlate(outline: .rounded(radius), color: Glass.shadow(scheme), radius: 22, y: 12))
    }
}

extension View {
    /// Content on a glass tile. The content is clipped to the tile; the glass
    /// (and its shadow) is not.
    func card(padding: CGFloat = Metrics.cardPadding, highlight: Color? = nil) -> some View {
        self
            .padding(padding)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .background(CardBackground(highlight: highlight))
    }
}

/// The small label over a value: sentence case, medium weight, secondary.
struct SectionLabel: View {
    let text: String
    var color: Color = CC.text2

    init(_ text: String, color: Color = CC.text2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
