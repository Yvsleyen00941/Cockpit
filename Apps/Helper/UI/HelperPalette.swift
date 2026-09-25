import AppKit
import CCCore
import SwiftUI

/// The blueprint palette, shared with the iPad so both ends look like one product.
enum HelperPalette {
    static let background = Color(hex: 0x0A0A0F)
    static let card = Color(hex: 0x16213E)
    static let cardTop = Color(hex: 0x1D2844)
    static let elevated = Color(hex: 0x1A2A4A)
    static let accent = Color(hex: 0x2E86AB)
    static let orange = Color(hex: 0xF18F01)
    static let green = Color(hex: 0x2ECC71)
    static let red = Color(hex: 0xE74C3C)
    static let yellow = Color(hex: 0xF5C518)
    static let primary = Color(hex: 0xF0F0F0)
    static let secondary = Color(hex: 0x888888)
    static let divider = Color(hex: 0x2A2A3A)

    static func health(_ health: IntegrationHealth) -> Color {
        switch health {
        case .ok: green
        case .warning: yellow
        case .error: red
        case .needsSetup: orange
        case .off: secondary.opacity(0.6)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// Section label: small caps, tracked — the "terminal" voice.
struct HelperLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(HelperPalette.secondary)
    }
}

/// The menu bar glyph: a landscape iPad frame with four tiles — filled when
/// a device is connected. Drawn as a template image so it follows the menu bar.
enum MenuBarGlyph {
    static func image(connected: Bool, pairing: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1.5), xRadius: 3, yRadius: 3)
            frame.lineWidth = 1.4
            NSColor.black.setStroke()
            frame.stroke()
            let inner = rect.insetBy(dx: 4, dy: 4.5)
            let gap: CGFloat = 1.6
            let w = (inner.width - gap) / 2
            let h = (inner.height - gap) / 2
            for row in 0..<2 {
                for col in 0..<2 {
                    let tile = NSRect(x: inner.minX + CGFloat(col) * (w + gap), y: inner.minY + CGFloat(row) * (h + gap), width: w, height: h)
                    let path = NSBezierPath(roundedRect: tile, xRadius: 0.8, yRadius: 0.8)
                    if connected || (pairing && row == 1 && col == 0) {
                        NSColor.black.setFill()
                        path.fill()
                    } else {
                        path.lineWidth = 0.8
                        NSColor.black.withAlphaComponent(0.55).setStroke()
                        path.stroke()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
