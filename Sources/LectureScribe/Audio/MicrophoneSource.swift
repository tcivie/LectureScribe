import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Speech

final class MicrophoneSource: AudioSource {
    static let tapFrames: AVAudioFrameCount = 4096

    var name: String { deviceName }
    var sink: ((AVAudioPCMBuffer) -> Void)?
    var analyzerInputSink: ((AnalyzerInput) -> Void)?
    var onStopped: ((Error) -> Void)?

    private let deviceQuery: String?
    private var engine: AVAudioEngine?
    private var format: AVAudioFormat?
    private var configObserver: NSObjectProtocol?
    private var deviceName: String

    init(deviceQuery: String?) {
        self.deviceQuery = deviceQuery
        deviceName = deviceQuery ?? "Microphone"
    }

    func prepare() async throws -> AVAudioFormat {
        let engine = AVAudioEngine()
        if let query = deviceQuery, !query.isEmpty { try select(query, on: engine) }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SourceError.noMicrophone }
        (self.engine, self.format) = (engine, format)
        return format
    }

    func begin() async throws {
        guard let engine, let format else { throw SourceError.noMicrophone }
        engine.inputNode.installTap(onBus: 0, bufferSize: Self.tapFrames, format: format) { [weak self] buffer, _ in
            self?.sink?(buffer)
        }
        engine.prepare()
        try engine.start()
        observeConfigurationChanges(of: engine)
    }

    func setPaused(_ paused: Bool) async {
        guard let engine else { return }
        if paused { engine.pause() } else { try? engine.start() }
    }

    func stop() async {
        onStopped = nil
        configObserver.map(NotificationCenter.default.removeObserver)
        configObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    private func select(_ query: String, on engine: AVAudioEngine) throws {
        guard let device = CoreAudioDevices.input(matching: query) else { throw SourceError.deviceNotFound(query) }
        guard engine.inputNode.withAudioUnit({ unit in unit.map { Self.setCurrentDevice(device.id, on: $0) } ?? false }) else {
            throw SourceError.deviceSelectFailed(device.name)
        }
        deviceName = device.name
    }

    static func setCurrentDevice(_ id: AudioDeviceID, on unit: AudioUnit) -> Bool {
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &value, size) == noErr
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.onStopped?(SourceError.deviceChanged)
        }
    }
}
