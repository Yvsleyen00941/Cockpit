import Foundation

/// Tiny path resolver for mapping an existing bot's JSON onto `BotState`
/// without changing the bot: `pnl_today`, `stats.daily.pnl`, `data.positions[0].qty`.
public enum JSONPath {
    public static func value(at path: String, in root: Any) -> Any? {
        var current: Any? = root
        let trimmed = path.hasPrefix("$.") ? String(path.dropFirst(2)) : path
        guard !trimmed.isEmpty, trimmed != "$" else { return root }
        for segment in trimmed.split(separator: ".") {
            var name = Substring(segment)
            var indexes: [Int] = []
            while let open = name.lastIndex(of: "["), name.last == "]" {
                let inner = name[name.index(after: open)..<name.index(before: name.endIndex)]
                guard let index = Int(inner) else { return nil }
                indexes.insert(index, at: 0)
                name = name[..<open]
            }
            if !name.isEmpty {
                guard let dict = current as? [String: Any] else { return nil }
                current = dict[String(name)]
            }
            for index in indexes {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        if current is NSNull { return nil }
        return current
    }

    public static func double(at path: String, in root: Any) -> Double? {
        switch value(at: path, in: root) {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s.replacingOccurrences(of: ",", with: ""))
        default: return nil
        }
    }

    public static func string(at path: String, in root: Any) -> String? {
        switch value(at: path, in: root) {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    public static func bool(at path: String, in root: Any) -> Bool? {
        switch value(at: path, in: root) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["true", "yes", "1", "ok", "connected"].contains(s.lowercased())
        default: return nil
        }
    }

    /// Epoch seconds, epoch milliseconds or ISO-8601.
    public static func date(at path: String, in root: Any) -> Date? {
        switch value(at: path, in: root) {
        case let n as NSNumber:
            let v = n.doubleValue
            return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v)
        case let s as String:
            if let v = Double(s) { return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v) }
            return parseISO(s)
        default: return nil
        }
    }

    public static func parseISO(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
