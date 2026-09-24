import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Speech

enum SystemAudio {
    static let sampleRate = 48_000.0
    static let channels = 2
    static let videoEdge = 2
    static let frameInterval = CMTime(value: 1, timescale: 1)
    static let queueDepth = 3
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false)!

    static func configuration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = channels
        config.width = videoEdge
        config.height = videoEdge
        config.minimumFrameInterval = frameInterval
        config.queueDepth = queueDepth
        return config
    }

    static func displayFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else { throw SourceError.noDisplay }
        return SCContentFilter(display: display, excludingWindows: [])
    }

    static func isCompatible(_ asbd: AudioStreamBasicDescription, with format: AVAudioFormat) -> Bool {
        let float = asbd.mFormatID == kAudioFormatLinearPCM && asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let shape = asbd.mSampleRate == format.sampleRate && asbd.mChannelsPerFrame == format.channelCount
        return float && shape && planar == !format.isInterleaved
    }

    static func pcmBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat = format) -> AVAudioPCMBuffer? {
        let frames = sampleBuffer.numSamples
        guard frames > 0, let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              isCompatible(asbd, with: format),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        guard (try? sampleBuffer.copyPCMData(fromRange: 0..<frames, into: buffer.mutableAudioBufferList)) != nil else { return nil }
        return buffer
    }
}

final class AudioSampleOutput: NSObject, SCStreamOutput {
    private let onBuffer: (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.dataReadiness == .ready,
              let buffer = SystemAudio.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer(buffer)
    }
}

final class SystemAudioSource: NSObject, AudioSource, SCStreamDelegate {
    let name = "System audio"
    var sink: ((AVAudioPCMBuffer) -> Void)?
    var analyzerInputSink: ((AnalyzerInput) -> Void)?
    var onStopped: ((Error) -> Void)?

    private var stream: SCStream?
    private var output: AudioSampleOutput?
    private let queue = DispatchQueue(label: "lecturescribe.audio", qos: .userInitiated)

    func prepare() async throws -> AVAudioFormat {
        let newStream = SCStream(filter: try await SystemAudio.displayFilter(), configuration: SystemAudio.configuration(), delegate: self)
        let newOutput = AudioSampleOutput { [weak self] buffer in self?.sink?(buffer) }
        try newStream.addStreamOutput(newOutput, type: .audio, sampleHandlerQueue: queue)
        (stream, output) = (newStream, newOutput)
        return SystemAudio.format
    }

    func begin() async throws {
        try await stream?.startCapture()
    }

    func setPaused(_ paused: Bool) async {
        if paused {
            try? await stream?.stopCapture()
        } else {
            try? await stream?.startCapture()
        }
    }

    func stop() async {
        onStopped = nil
        try? await stream?.stopCapture()
        stream = nil
        output = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.engine("SCStream stopped with error: \(error.localizedDescription)")
        onStopped?(error)
    }
}
