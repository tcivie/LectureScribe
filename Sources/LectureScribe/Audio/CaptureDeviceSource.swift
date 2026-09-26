import AVFoundation
import Foundation
import Speech

final class CaptureDeviceSource: AudioSource {
    static let nominalSampleRate = 48_000.0

    private(set) var name: String
    var sink: ((AVAudioPCMBuffer) -> Void)?
    var analyzerInputSink: ((AnalyzerInput) -> Void)?
    var onStopped: ((Error) -> Void)?
    var providesAnalyzerInput: Bool { true }
    var inputLevel: Float { meter?.box.load() ?? 0 }

    private let device: AVCaptureDevice
    private let transcriber: SpeechTranscriber
    private var provider: CaptureInputSequenceProvider?
    private var forwarder: Task<Void, Never>?
    private var meter: DeviceTap?

    init(device: AVCaptureDevice, transcriber: SpeechTranscriber) {
        self.device = device
        self.transcriber = transcriber
        name = device.localizedName
    }

    convenience init?(query: String?, transcriber: SpeechTranscriber) {
        guard let device = Self.resolve(query) else { return nil }
        self.init(device: device, transcriber: transcriber)
    }

    static func resolve(_ query: String?) -> AVCaptureDevice? {
        guard let query, !query.isEmpty else { return AVCaptureDevice.default(for: .audio) }
        let wanted = query.lowercased()
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        return devices.first { $0.localizedName.lowercased() == wanted }
            ?? devices.first { $0.localizedName.lowercased().contains(wanted) }
    }

    func prepare() async throws -> AVAudioFormat {
        provider = try await CaptureInputSequenceProvider.providerWithSession(from: device, compatibleWith: [transcriber], priority: nil)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.nominalSampleRate, channels: 1) else {
            throw SourceError.conversionFailed
        }
        return format
    }

    func begin() async throws {
        guard let provider else { throw SourceError.conversionFailed }
        await Self.run(provider.captureSession, running: true)
        // The provider's AnalyzerInputs carry no PCM copy (AnalyzerInput.buffer traps on macOS 27),
        // so the level meter taps the same device through CoreAudio instead.
        meter = CoreAudioDevices.input(matching: name).flatMap { DeviceTap(device: $0.id) }
        forwarder = Task { [weak self] in await self?.forward(provider.analyzerInputs) }
    }

    func setPaused(_ paused: Bool) async {
        guard let session = provider?.captureSession else { return }
        await Self.run(session, running: !paused)
    }

    func stop() async {
        onStopped = nil
        forwarder?.cancel()
        forwarder = nil
        meter?.close()
        meter = nil
        if let session = provider?.captureSession { await Self.run(session, running: false) }
        provider = nil
    }

    private func forward<S: AsyncSequence>(_ inputs: S) async where S.Element == AnalyzerInput {
        do {
            for try await input in inputs { analyzerInputSink?(input) }
        } catch where !Task.isCancelled && !(error is CancellationError) {
            onStopped?(error)
        } catch {
            return
        }
    }

    private static func run(_ session: AVCaptureSession, running: Bool) async {
        await Task.detached { running ? session.startRunning() : session.stopRunning() }.value
    }
}
