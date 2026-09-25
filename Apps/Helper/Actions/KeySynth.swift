import AppKit
import Carbon.HIToolbox
import CCCore
import CoreGraphics
import Foundation

/// Synthesises keystrokes with CGEvent (needs the Accessibility permission).
///
/// Characters are resolved against the **current keyboard layout**, not
/// hard-coded US key codes. On a Belgian AZERTY board Z sits where QWERTY has
/// W — a naive ⌘Z would send ⌘W and close your window. Here ⌘Z is Undo on
/// every layout, and ⇧⌘4 still hits the system screenshot shortcut.
@MainActor
enum KeySynth {
    static let accessibilityMessage = "Grant ControlCenter Helper Accessibility access (System Settings → Privacy & Security → Accessibility)."

    static func post(_ combo: KeyCombo) -> ActionResult {
        guard AXIsProcessTrusted() else { return .failure(accessibilityMessage) }
        guard let key = combo.key else { return .failure("That shortcut has no key") }
        let resolved: (code: CGKeyCode, shift: Bool)
        if let named = combo.namedKey {
            resolved = (CGKeyCode(named.virtualKeyCode), false)
        } else if let mapped = LayoutMap.shared.keyCode(for: key) {
            resolved = mapped
        } else {
            return .failure("“\(key)” isn't on the current keyboard layout")
        }
        var modifiers = combo.modifiers
        if resolved.shift { modifiers.insert(.shift) }
        press(code: resolved.code, modifiers: modifiers)
        return .success
    }

    static func press(code: CGKeyCode, modifiers: Set<KeyModifier>) {
        let source = CGEventSource(stateID: .hidSystemState)
        let ordered = KeyModifier.displayOrder.filter(modifiers.contains)
        var flags = CGEventFlags()
        for modifier in ordered {
            flags.insert(modifier.cgFlag)
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifier.keyCode, keyDown: true)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
        for modifier in ordered.reversed() {
            flags.remove(modifier.cgFlag)
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifier.keyCode, keyDown: false)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Types arbitrary text (layout independent, via Unicode key events).
    static func type(_ text: String, pressReturn: Bool) async -> ActionResult {
        guard AXIsProcessTrusted() else { return .failure(accessibilityMessage) }
        let source = CGEventSource(stateID: .hidSystemState)
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let units = Array(line.utf16)
            var offset = 0
            while offset < units.count {
                let chunk = Array(units[offset..<min(offset + 16, units.count)])
                offset += chunk.count
                for keyDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                    event?.flags = []
                    chunk.withUnsafeBufferPointer { buffer in
                        event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                    }
                    event?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: .milliseconds(4))
            }
            if index < lines.count - 1 { press(code: CGKeyCode(kVK_Return), modifiers: []) }
        }
        if pressReturn {
            try? await Task.sleep(for: .milliseconds(30))
            press(code: CGKeyCode(kVK_Return), modifiers: [])
        }
        return .success
    }

    // MARK: Media & system keys (NX_KEYTYPE_*)

    enum SystemKey: Int32 {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7, play = 16, next = 17, previous = 18
    }

    static func post(_ key: SystemKey) -> ActionResult {
        guard AXIsProcessTrusted() else { return .failure(accessibilityMessage) }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.rawValue << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return .success
    }
}

extension KeyModifier {
    var cgFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .shift: .maskShift
        case .option: .maskAlternate
        case .control: .maskControl
        case .function: .maskSecondaryFn
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .command: CGKeyCode(kVK_Command)
        case .shift: CGKeyCode(kVK_Shift)
        case .option: CGKeyCode(kVK_Option)
        case .control: CGKeyCode(kVK_Control)
        case .function: CGKeyCode(kVK_Function)
        }
    }
}

/// Character ⇄ key code for the active keyboard layout (rebuilt when you
/// switch input sources).
@MainActor
final class LayoutMap {
    static let shared = LayoutMap()

    private var forward: [String: (CGKeyCode, Bool)] = [:]
    private var reverse: [CGKeyCode: String] = [:]
    private var layoutID: String?
    private static let keypad: Set<Int> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    func keyCode(for character: String) -> (CGKeyCode, Bool)? {
        refresh()
        if let exact = forward[character] { return exact }
        if let lower = forward[character.lowercased()] { return lower }
        return Self.ansi[character.lowercased()].map { ($0, false) }
    }

    func character(for code: CGKeyCode) -> String? {
        refresh()
        return reverse[code]
    }

    private func refresh() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
        guard id != layoutID || forward.isEmpty else { return }
        layoutID = id
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var forward: [String: (CGKeyCode, Bool)] = [:]
        var reverse: [CGKeyCode: String] = [:]
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for shifted in [false, true] {
                for code in 0..<128 where !Self.keypad.contains(code) {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let modifierState: UInt32 = shifted ? UInt32((shiftKey >> 8) & 0xFF) : 0
                    let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), modifierState, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
                    guard status == noErr, length > 0 else { continue }
                    let text = String(utf16CodeUnits: characters, count: length)
                    guard text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { continue }
                    if forward[text] == nil { forward[text] = (CGKeyCode(code), shifted) }
                    if !shifted, reverse[CGKeyCode(code)] == nil { reverse[CGKeyCode(code)] = text.lowercased() }
                }
            }
        }
        self.forward = forward
        self.reverse = reverse
    }

    /// US ANSI fallback.
    static let ansi: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]
}
