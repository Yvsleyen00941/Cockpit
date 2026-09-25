import AppKit
import CCCore
import CoreGraphics
import Foundation

/// Records keystrokes on the Mac into a macro (a listen-only event tap —
/// needs Input Monitoring). The iPad sees the steps appear live.
@MainActor
final class MacroRecorder {
    static let shared = MacroRecorder()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var steps: [MacroStep] = []
    private var lastEvent: Date?
    private var sessionID: UUID?
    private var timeout: Task<Void, Never>?

    func handle(_ command: RecordMacro.Command, for session: ClientSession) {
        switch command {
        case .start: start(for: session)
        case .stop: stop(send: true)
        case .cancel:
            steps.removeAll()
            stop(send: true)
        }
    }

    private func start(for session: ClientSession) {
        stop(send: false)
        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()
            session.send(.macroRecording(MacroRecording(steps: [], recording: false, error: "Allow ControlCenter Helper under Privacy & Security → Input Monitoring, then try again.")))
            return
        }
        sessionID = session.id
        steps = []
        lastEvent = nil
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .keyDown {
                let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                MainActor.assumeIsolated { MacroRecorder.shared.record(code: code, flags: flags) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: callback, userInfo: nil) else {
            session.send(.macroRecording(MacroRecording(steps: [], recording: false, error: "Couldn't start recording")))
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Log.shared.info("Recording a macro on the Mac")
        session.send(.macroRecording(MacroRecording(steps: [], recording: true)))
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(90))
            self?.stop(send: true)
        }
    }

    private func record(code: CGKeyCode, flags: CGEventFlags) {
        var keys: [String] = []
        if flags.contains(.maskControl) { keys.append("ctrl") }
        if flags.contains(.maskAlternate) { keys.append("opt") }
        if flags.contains(.maskShift) { keys.append("shift") }
        if flags.contains(.maskCommand) { keys.append("cmd") }
        if let named = NamedKey.allCases.first(where: { CGKeyCode($0.virtualKeyCode) == code }) {
            keys.append(named.rawValue)
        } else if let character = LayoutMap.shared.character(for: code) {
            keys.append(character)
        } else {
            return
        }
        let now = Date()
        if let lastEvent, var last = steps.popLast() {
            last.delay = min(2, (now.timeIntervalSince(lastEvent) * 20).rounded() / 20)
            steps.append(last)
        }
        lastEvent = now
        steps.append(MacroStep(.keyCombo(KeyCombo(keys: keys))))
        if let sessionID { Hub.shared.send(.macroRecording(MacroRecording(steps: steps, recording: true)), to: sessionID) }
    }

    private func stop(send: Bool) {
        timeout?.cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if send, let sessionID {
            Hub.shared.send(.macroRecording(MacroRecording(steps: steps, recording: false)), to: sessionID)
            Log.shared.info("Recorded \(steps.count) steps")
        }
        sessionID = nil
    }
}
