import Foundation

/// Formatting shared by the iPad, the iPhone, the widgets and the menu bar, so
/// a number reads the same everywhere.
public enum Fmt {
    public static func money(_ value: Double, currency: String = "EUR", signed: Bool = false, decimals: Int = 2) -> String {
        let formatted = value.formatted(
            .currency(code: currency)
                .precision(.fractionLength(decimals))
                .sign(strategy: signed ? .always() : .automatic)
        )
        return formatted
    }

    /// €48.2K / €1.24M for tight spaces.
    public static func compactMoney(_ value: Double, currency: String = "EUR") -> String {
        let symbol = currencySymbol(currency)
        let sign = value < 0 ? "−" : ""
        let a = abs(value)
        switch a {
        case 1_000_000...: return "\(sign)\(symbol)\(String(format: "%.2fM", a / 1_000_000))"
        case 10_000...: return "\(sign)\(symbol)\(String(format: "%.1fK", a / 1_000))"
        default: return "\(sign)\(symbol)\(String(format: "%.0f", a))"
        }
    }

    public static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "EUR": "€"
        case "USD": "$"
        case "GBP": "£"
        case "CHF": "CHF "
        case "JPY": "¥"
        default: code + " "
        }
    }

    /// `+1.84%` from a fraction (0.0184) when `fraction` is true, else from a percent.
    public static func percent(_ value: Double, fraction: Bool = true, signed: Bool = true, decimals: Int = 2) -> String {
        let pct = fraction ? value * 100 : value
        let sign = signed && pct > 0 ? "+" : (pct < 0 ? "−" : "")
        return "\(sign)\(String(format: "%.\(decimals)f", abs(pct)))%"
    }

    /// Adaptive precision: 62,340.00 / 2,410.5 / 0.004321.
    public static func price(_ value: Double) -> String {
        let a = abs(value)
        let decimals = a >= 1000 ? 2 : (a >= 1 ? 2 : (a >= 0.01 ? 4 : 6))
        return value.formatted(.number.precision(.fractionLength(decimals)).grouping(.automatic))
    }

    public static func quantity(_ value: Double) -> String {
        let a = abs(value)
        let decimals = a >= 100 ? 0 : (a >= 1 ? 2 : 4)
        return value.formatted(.number.precision(.fractionLength(0...decimals)))
    }

    /// 7h 42m.
    public static func hoursMinutes(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    /// 1 h 20 min / 42 min / 35 s.
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        let minutes = s / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// 24:59 or 1:24:59.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// "in 42 min", "now", "in 2 h 5 min".
    public static func until(_ date: Date, from now: Date = .now) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 30 { return "now" }
        return "in " + duration(delta)
    }

    /// "just now", "2m ago", "3h ago".
    public static func ago(_ date: Date, from now: Date = .now) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        switch delta {
        case ..<10: return "just now"
        case ..<60: return "\(Int(delta))s ago"
        case ..<3600: return "\(Int(delta / 60))m ago"
        case ..<86_400: return "\(Int(delta / 3600))h ago"
        default: return "\(Int(delta / 86_400))d ago"
        }
    }

    /// 14:05 (24-hour, as the rest of Belgium reads it).
    public static func clock(_ date: Date, seconds: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        return f.string(from: date)
    }

    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    /// 12.4 GB (one decimal, GB only) for memory bars.
    public static func gigabytes(_ value: UInt64) -> String {
        String(format: "%.1f", Double(value) / 1_073_741_824)
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        switch bytesPerSecond {
        case 1_048_576...: String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        case 1024...: String(format: "%.0f KB/s", bytesPerSecond / 1024)
        default: String(format: "%.0f B/s", bytesPerSecond)
        }
    }
}
