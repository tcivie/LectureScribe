import CoreAudio
import Foundation

enum AudioDumper {
    static func dump() {
        let ids = CoreAudioDevices.all()
        guard !ids.isEmpty else { return print("❌ could not enumerate audio devices") }
        print("audio devices:")
        ids.sorted().forEach { print(describe($0)) }
        if let out = CoreAudioDevices.defaultDevice(output: true).flatMap(CoreAudioDevices.deviceName) {
            print("default OUTPUT: \(out)")
        }
        if let input = CoreAudioDevices.defaultDevice(output: false).flatMap(CoreAudioDevices.deviceName) {
            print("default INPUT:  \(input)")
        }
    }

    static func describe(_ id: AudioDeviceID) -> String {
        let name = CoreAudioDevices.deviceName(id) ?? "?"
        let alive = CoreAudioDevices.isRunningSomewhere(id) ? "alive" : "     "
        let roles = [
            CoreAudioDevices.hasStreams(id, output: true) ? "OUT" : nil,
            CoreAudioDevices.hasStreams(id, output: false) ? "IN" : nil
        ].compactMap { $0 }.joined(separator: "/")
        return "  [\(roles.padding(toLength: "OUT/IN".count, withPad: " ", startingAt: 0))][\(alive)] \(name)"
    }
}
