import CoreAudio
import Foundation

enum CoreAudioDevices {
    struct Device: Equatable {
        let id: AudioDeviceID
        let name: String
    }

    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func all() -> [AudioDeviceID] {
        var address = propertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func inputs() -> [Device] {
        all().filter { hasStreams($0, output: false) }.map { Device(id: $0, name: deviceName($0) ?? "?") }
    }

    static func input(matching query: String) -> Device? {
        let wanted = query.lowercased()
        let devices = inputs()
        return devices.first { $0.name.lowercased() == wanted } ?? devices.first { $0.name.lowercased().contains(wanted) }
    }

    static func deviceName(_ id: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = propertyAddress(kAudioDevicePropertyDeviceNameCFString)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    static func hasStreams(_ id: AudioDeviceID, output: Bool) -> Bool {
        let scope = output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    static func isRunningSomewhere(_ id: AudioDeviceID) -> Bool {
        uint32Property(kAudioDevicePropertyDeviceIsRunningSomewhere, of: id).map { $0 != 0 } ?? false
    }

    /// The Mac's own microphone. "Microphone" means this one, never the system default,
    /// which macOS may switch to an iPhone (Continuity) or a headset on its own.
    static func builtInInput() -> Device? {
        inputs().first { uint32Property(kAudioDevicePropertyTransportType, of: $0.id) == kAudioDeviceTransportTypeBuiltIn }
    }

    static func defaultDevice(output: Bool) -> AudioDeviceID? {
        let selector = output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        return uint32Property(selector, of: systemObject).flatMap { $0 == 0 ? nil : $0 }
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = propertyAddress(selector)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
