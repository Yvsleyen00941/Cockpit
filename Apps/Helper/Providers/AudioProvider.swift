import AudioToolbox
import CCCore
import CoreAudio
import Foundation

/// Output volume, output mute, microphone mute and "mic in use" via Core Audio
/// property listeners — pushed the instant anything changes, zero polling.
///
/// The mic mute is system-wide, so it silences you in Zoom, Teams, Meet and
/// Discord alike. Devices without a hardware mute fall back to input volume 0.
@MainActor
final class AudioProvider {
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var savedInputVolume: Float32 = 0.75
    private var publishTask: Task<Void, Never>?

    func start() {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated { Hub.shared.audio.rebind() }
            }
        }
        rebind()
    }

    func rebind() {
        for (device, address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        deviceListeners.removeAll()
        outputDevice = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        inputDevice = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)

        listen(outputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        listen(outputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        listen(inputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput)
        listen(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput)
        listen(inputDevice, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal)
        schedulePublish()
    }

    private func listen(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) {
        guard device != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { Hub.shared.audio.schedulePublish() }
        }
        if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
            deviceListeners.append((device, address, block))
        }
    }

    /// Coalesce bursts (a volume slider drag fires dozens of changes).
    func schedulePublish() {
        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            Hub.shared.publish(.audio(self.state))
        }
    }

    var state: AudioState {
        let outputVolume = Self.float(outputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput) ?? 0
        let outputMuted = (Self.uint(outputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput) ?? 0) == 1
        let inputVolume = Self.float(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput) ?? 1
        let hardwareMute = (Self.uint(inputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput) ?? 0) == 1
        let running = (Self.uint(inputDevice, kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal) ?? 0) == 1
        return AudioState(
            outputVolume: (Double(outputVolume) * 100).rounded() / 100,
            outputMuted: outputMuted,
            outputDevice: Self.name(outputDevice),
            inputMuted: hardwareMute || inputVolume < 0.001,
            inputVolume: (Double(inputVolume) * 100).rounded() / 100,
            inputDevice: Self.name(inputDevice),
            micInUse: running
        )
    }

    // MARK: Commands

    func setOutputVolume(_ value: Double) {
        let clamped = Float32(min(1, max(0, value)))
        Self.setFloat(outputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput, clamped)
        if clamped > 0, state.outputMuted {
            Self.setUInt(outputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, 0)
        }
    }

    func toggleOutputMute() {
        let muted = state.outputMuted
        Self.setUInt(outputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, muted ? 0 : 1)
    }

    @discardableResult
    func setMicMuted(_ muted: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(inputDevice, &address), AudioObjectIsPropertySettable(inputDevice, &address, &settable) == noErr, settable.boolValue {
            Self.setUInt(inputDevice, kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, muted ? 1 : 0)
            // Some devices keep capturing at 0 gain only when volume drops too.
            if !muted, (Self.float(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput) ?? 1) < 0.01 {
                Self.setFloat(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput, savedInputVolume)
            }
            return true
        }
        if muted {
            if let current = Self.float(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput), current > 0.01 {
                savedInputVolume = current
            }
            return Self.setFloat(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput, 0)
        }
        return Self.setFloat(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput, savedInputVolume)
    }

    func toggleMic() -> Bool {
        let muted = !state.inputMuted
        setMicMuted(muted)
        return muted
    }

    func setInputVolume(_ value: Double) {
        Self.setFloat(inputDevice, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput, Float32(min(1, max(0, value))))
    }

    // MARK: Core Audio helpers

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private static func float(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> Float32? {
        guard device != kAudioObjectUnknown else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
        guard device != kAudioObjectUnknown else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    private static func setFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ value: Float32) -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    @discardableResult
    private static func setUInt(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ value: UInt32) -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func name(_ device: AudioObjectID) -> String {
        guard device != kAudioObjectUnknown else { return "—" }
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else { return "—" }
        return name.takeRetainedValue() as String
    }
}
