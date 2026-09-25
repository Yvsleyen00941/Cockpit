import Foundation

// MARK: - Modifiers

/// A keyboard modifier, as it appears in a `keyCombo` action:
/// `{ "type": "keyCombo", "keys": ["cmd", "shift", "4"] }`.
public enum KeyModifier: String, Codable, Sendable, CaseIterable, Hashable {
    case command = "cmd"
    case shift
    case option = "opt"
    case control = "ctrl"
    case function = "fn"

    /// Apple's canonical display order — ⌃ ⌥ ⇧ ⌘.
    public static let displayOrder: [KeyModifier] = [.function, .control, .option, .shift, .command]

    /// Accepts every spelling people actually type: `cmd`, `command`, `⌘`, `alt`, `⌥`…
    public init?(token: String) {
        switch token.lowercased() {
        case "cmd", "command", "⌘", "meta", "super": self = .command
        case "shift", "⇧": self = .shift
        case "opt", "option", "alt", "⌥": self = .option
        case "ctrl", "control", "ctl", "⌃": self = .control
        case "fn", "function", "globe": self = .function
        default: return nil
        }
    }

    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .shift: "⇧"
        case .option: "⌥"
        case .control: "⌃"
        case .function: "fn"
        }
    }

    public var title: String {
        switch self {
        case .command: "Command"
        case .shift: "Shift"
        case .option: "Option"
        case .control: "Control"
        case .function: "Fn"
        }
    }
}

// MARK: - Named keys

/// Keys that are not characters. Everything else in a combo is a character that
/// the Mac resolves against the *current keyboard layout* (so ⌘Z is still Undo
/// on a Belgian AZERTY board, where Z sits where QWERTY has W).
public enum NamedKey: String, CaseIterable, Sendable {
    case `return`, tab, space, delete, forwardDelete, escape
    case left, right, up, down, home, end, pageUp, pageDown, keypadEnter
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    public init?(token: String) {
        let t = token.lowercased()
        if let exact = NamedKey.allCases.first(where: { $0.rawValue.lowercased() == t }) {
            self = exact
            return
        }
        switch t {
        case "enter", "↩", "⏎", "ret": self = .return
        case "⇥": self = .tab
        case "spacebar", "␣", " ": self = .space
        case "backspace", "⌫", "bksp": self = .delete
        case "del", "⌦", "forwarddelete", "fwddelete": self = .forwardDelete
        case "esc", "⎋": self = .escape
        case "arrowleft", "←", "leftarrow": self = .left
        case "arrowright", "→", "rightarrow": self = .right
        case "arrowup", "↑", "uparrow": self = .up
        case "arrowdown", "↓", "downarrow": self = .down
        case "pgup", "⇞": self = .pageUp
        case "pgdn", "pgdown", "⇟": self = .pageDown
        case "↖": self = .home
        case "↘": self = .end
        case "⌤", "numpadenter": self = .keypadEnter
        default: return nil
        }
    }

    public var symbol: String {
        switch self {
        case .return: "↩"
        case .tab: "⇥"
        case .space: "Space"
        case .delete: "⌫"
        case .forwardDelete: "⌦"
        case .escape: "esc"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .home: "↖"
        case .end: "↘"
        case .pageUp: "⇞"
        case .pageDown: "⇟"
        case .keypadEnter: "⌤"
        default: rawValue.uppercased()
        }
    }

    /// macOS virtual key code (kVK_*) — layout independent.
    public var virtualKeyCode: UInt16 {
        switch self {
        case .return: 36
        case .tab: 48
        case .space: 49
        case .delete: 51
        case .escape: 53
        case .forwardDelete: 117
        case .home: 115
        case .end: 119
        case .pageUp: 116
        case .pageDown: 121
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        case .keypadEnter: 76
        case .f1: 122
        case .f2: 120
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .f9: 101
        case .f10: 109
        case .f11: 103
        case .f12: 111
        case .f13: 105
        case .f14: 107
        case .f15: 113
        case .f16: 106
        case .f17: 64
        case .f18: 79
        case .f19: 80
        case .f20: 90
        }
    }
}

// MARK: - Combo

/// A key combination in the blueprint's wire format: `["cmd", "shift", "4"]`.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keys: [String]

    public init(keys: [String]) {
        self.keys = keys
    }

    /// Parses `"cmd+shift+4"`, `"⇧⌘4"`, `"ctrl cmd q"`.
    public init(_ spec: String) {
        var tokens: [String] = []
        var rest = Substring(spec.trimmingCharacters(in: .whitespaces))
        // Leading modifier glyphs written without separators ("⇧⌘4").
        while let first = rest.first, "⌘⇧⌥⌃".contains(first) {
            tokens.append(String(first))
            rest = rest.dropFirst()
        }
        let isSeparator: (Character) -> Bool = { $0 == "+" || $0 == " " }
        if rest.count == 1 {
            tokens.append(String(rest))
        } else if rest.hasSuffix("++") {
            tokens += rest.dropLast(2).split(whereSeparator: isSeparator).map(String.init)
            tokens.append("+")
        } else {
            tokens += rest.split(whereSeparator: isSeparator).map(String.init)
        }
        var mods: [String] = []
        var key: String?
        for token in tokens {
            if let mod = KeyModifier(token: token) {
                if !mods.contains(mod.rawValue) { mods.append(mod.rawValue) }
            } else {
                key = NamedKey(token: token)?.rawValue ?? (token.count == 1 ? token.lowercased() : token)
            }
        }
        self.keys = mods + (key.map { [$0] } ?? [])
    }

    public static func cmd(_ key: String) -> KeyCombo { KeyCombo(keys: ["cmd", key]) }

    public var modifiers: Set<KeyModifier> {
        Set(keys.compactMap { KeyModifier(token: $0) })
    }

    /// The non-modifier key, if any.
    public var key: String? {
        keys.last { KeyModifier(token: $0) == nil }
    }

    public var namedKey: NamedKey? { key.flatMap(NamedKey.init(token:)) }

    /// `⇧⌘4`, `⌃⌘Q`, `⌥⌘←`.
    public var display: String {
        let mods = KeyModifier.displayOrder.filter(modifiers.contains).map(\.symbol).joined()
        guard let key else { return mods }
        if let named = NamedKey(token: key) {
            return mods + named.symbol
        }
        return mods + key.uppercased()
    }

    public var isEmpty: Bool { key == nil && modifiers.isEmpty }
}
