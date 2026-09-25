import Foundation

/// A Sendable snapshot of an AppleScript result.
struct ScriptValue: Sendable {
    var string: String?
    var number: Double?
    var data: Data?
    var list: [ScriptValue] = []

    init(_ descriptor: NSAppleEventDescriptor) {
        if descriptor.descriptorType == typeAEList {
            let count = descriptor.numberOfItems
            if count > 0 {
                for index in 1...count {
                    if let item = descriptor.atIndex(index) { list.append(ScriptValue(item)) }
                }
            }
            return
        }
        switch descriptor.descriptorType {
        case typeIEEE64BitFloatingPoint, typeIEEE32BitFloatingPoint, typeSInt32, typeSInt16, typeUInt32, typeSInt64:
            number = descriptor.coerce(toDescriptorType: typeIEEE64BitFloatingPoint)?.doubleValue
            string = number.map { String($0) }
        case typeTrue:
            number = 1
            string = "true"
        case typeFalse:
            number = 0
            string = "false"
        default:
            string = descriptor.stringValue
            if string == nil { data = descriptor.data }
        }
    }

    var stringValue: String? { string }

    subscript(index: Int) -> ScriptValue? {
        list.indices.contains(index) ? list[index] : nil
    }
}

struct ScriptError: Error, LocalizedError, Sendable {
    let number: Int
    let message: String

    var errorDescription: String? {
        switch number {
        case -1743: "Allow ControlCenter Helper under System Settings → Privacy & Security → Automation."
        case -600: "That app isn't running."
        case -1712: "The app didn't respond in time."
        default: message
        }
    }
}

/// Runs AppleScript on one dedicated thread. NSAppleScript is not thread-safe,
/// and keeping it off the main thread means a hung app can never freeze the
/// hub. Compiled scripts are cached.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    private let thread: ScriptThread

    private init() {
        thread = ScriptThread()
        thread.name = "cc.applescript"
        thread.qualityOfService = .userInitiated
        thread.start()
        thread.ready.wait()
    }

    func run(_ source: String) async -> Result<ScriptValue, ScriptError> {
        await withCheckedContinuation { continuation in
            thread.perform { [thread] in
                continuation.resume(returning: thread.execute(source))
            }
        }
    }
}

private final class ScriptThread: Thread, @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?
    private var cache: [String: NSAppleScript] = [:]

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        let port = NSMachPort()
        RunLoop.current.add(port, forMode: .default)
        ready.signal()
        while !isCancelled {
            _ = autoreleasepool { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
    }

    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs on this thread only.
    func execute(_ source: String) -> Result<ScriptValue, ScriptError> {
        autoreleasepool {
            let script: NSAppleScript
            if let cached = cache[source] {
                script = cached
            } else {
                guard let compiled = NSAppleScript(source: source) else {
                    return .failure(ScriptError(number: -2700, message: "Could not create script"))
                }
                var compileError: NSDictionary?
                if !compiled.compileAndReturnError(&compileError) {
                    return .failure(Self.error(compileError))
                }
                if cache.count > 64 { cache.removeAll() }
                cache[source] = compiled
                script = compiled
            }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error { return .failure(Self.error(error)) }
            return .success(ScriptValue(result))
        }
    }

    private static func error(_ info: NSDictionary?) -> ScriptError {
        let number = (info?[NSAppleScript.errorNumber] as? Int) ?? -1
        let message = (info?[NSAppleScript.errorMessage] as? String) ?? "AppleScript failed"
        return ScriptError(number: number, message: message)
    }
}
