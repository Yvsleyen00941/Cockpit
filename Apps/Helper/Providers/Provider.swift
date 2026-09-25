import CCCore
import Foundation

/// A source of one or more live channels. The hub turns providers on only while
/// a client is subscribed to one of their channels.
@MainActor
protocol Provider: AnyObject {
    var channels: Set<Channel> { get }
    func setActive(_ active: Bool)
    func refreshNow() async
}

/// Polls on an interval while active.
@MainActor
class PollingProvider: Provider {
    var channels: Set<Channel> { [] }
    var interval: TimeInterval { 5 }
    private(set) var isActive = false
    private var loop: Task<Void, Never>?

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        loop?.cancel()
        loop = nil
        if active {
            loop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.tick()
                    let wait = self.interval
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
            didActivate()
        } else {
            didDeactivate()
        }
    }

    func refreshNow() async {
        await tick()
    }

    /// Restart the loop immediately (settings changed).
    func kick() {
        guard isActive else { return }
        setActive(false)
        setActive(true)
    }

    func tick() async {}
    func didActivate() {}
    func didDeactivate() {}
}
