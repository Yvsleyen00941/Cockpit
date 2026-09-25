import Foundation

/// `{{date}}`, `{{date:EEEE d MMMM}}`, `{{time}}`, `{{url}}`, `{{title}}`,
/// `{{app}}`, `{{clipboard}}` — expanded on the Mac right before text is typed,
/// a shell command runs or a URL opens.
public enum TemplateEngine {
    public static func expand(_ text: String, now: Date = .now, locale: Locale = .current, resolve: (String) -> String? = { _ in nil }) -> String {
        guard text.contains("{{") else { return text }
        var output = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            output += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                output += rest[open.lowerBound...]
                return output
            }
            let token = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            output += value(for: token, now: now, locale: locale, resolve: resolve) ?? "{{\(token)}}"
            rest = rest[close.upperBound...]
        }
        output += rest
        return output
    }

    private static func value(for token: String, now: Date, locale: Locale, resolve: (String) -> String?) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1] : nil
        switch name {
        case "date":
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = argument ?? "yyyy-MM-dd"
            return f.string(from: now)
        case "time":
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = argument ?? "HH:mm"
            return f.string(from: now)
        case "weekday":
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = "EEEE"
            return f.string(from: now)
        default:
            return resolve(name)
        }
    }
}
