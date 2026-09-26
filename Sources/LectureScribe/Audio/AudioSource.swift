import AVFoundation
import CoreAudio
import Foundation
import Speech

enum SourceKind: Equatable, Hashable, Sendable {
    case system
    case microphone
    case device(name: String)

    static let devicePrefix = "device:"

    var displayName: String {
        switch self {
        case .system: return "System audio (Safari, etc.)"
        case .microphone: return "Microphone (built-in)"
        case .device(let name): return name
        }
    }

    var storageKey: String {
        switch self {
        case .system: return "system"
        case .microphone: return "microphone"
        case .device(let name): return Self.devicePrefix + name
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "speaker.wave.2.fill"
        case .microphone: return "mic.fill"
        case .device: return "hifispeaker.2.fill"
        }
    }

    static func from(storageKey key: String) -> SourceKind {
        if key == "microphone" { return .microphone }
        if key.hasPrefix(devicePrefix) { return .device(name: String(key.dropFirst(devicePrefix.count))) }
        return .system
    }
}

enum SourceError: LocalizedError {
    case deviceNotFound(String)
    case deviceSelectFailed(String)
    case noMicrophone
    case noDisplay
    case conversionFailed
    case deviceChanged

    var errorDescription: String? {
        switch self {
        case .deviceChanged:
            return "The input device changed or was unplugged."
        case .deviceNotFound(let query):
            return "No input device matching '\(query)'. Check `lecturescribe devices`."
        case .deviceSelectFailed(let name):
            return "Could not capture from \(name)."
        case .noMicrophone:
            return "No microphone access. Allow Microphone for this app (System Settings → Privacy → Microphone), then try again."
        case .noDisplay:
            return "No display found for system-audio capture."
        case .conversionFailed:
            return "Could not prepare the audio conversion for the speech analyzer."
        }
    }
}

protocol AudioSource: AnyObject {
    var name: String { get }
    var sink: ((AVAudioPCMBuffer) -> Void)? { get set }
    var analyzerInputSink: ((AnalyzerInput) -> Void)? { get set }
    var providesAnalyzerInput: Bool { get }
    var inputLevel: Float { get }
    var onStopped: ((Error) -> Void)? { get set }
    func prepare() async throws -> AVAudioFormat
    func begin() async throws
    func setPaused(_ paused: Bool) async
    func stop() async
}

extension AudioSource {
    var providesAnalyzerInput: Bool { false }
    var inputLevel: Float { 0 }
}

func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let channels = max(1, Int(buffer.format.channelCount))
    var power: Float = 0
    for channel in 0..<channels {
        let value = rms(data[channel], count: Int(buffer.frameLength))
        power += value * value
    }
    return meterLevel(rms: (power / Float(channels)).squareRoot())
}
