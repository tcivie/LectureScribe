import AVFoundation
import Foundation
import Speech

enum SourceFactory {
    static func make(kind: SourceKind, transcriber: SpeechTranscriber) async throws -> (AudioSource, AVAudioFormat) {
        guard kind != .system else {
            let source = SystemAudioSource()
            return (source, try await source.prepare())
        }
        let query = deviceQuery(for: kind)
        if let provided = try? await providerSource(query: query, transcriber: transcriber) { return provided }
        let fallback = MicrophoneSource(deviceQuery: query)
        return (fallback, try await fallback.prepare())
    }

    static func begin(_ source: AudioSource) async throws {
        do {
            try await source.begin()
        } catch {
            await source.stop()
            throw error
        }
    }

    static func deviceQuery(for kind: SourceKind) -> String? {
        switch kind {
        case .device(let name): return name
        case .microphone: return CoreAudioDevices.builtInInput()?.name
        case .system: return nil
        }
    }

    private static func providerSource(query: String?, transcriber: SpeechTranscriber) async throws -> (AudioSource, AVAudioFormat)? {
        guard let source = CaptureDeviceSource(query: query, transcriber: transcriber) else { return nil }
        do {
            return (source, try await source.prepare())
        } catch {
            Log.engine("provider path failed for '\(source.name)' (\(error.localizedDescription)) — audio-engine fallback")
            throw error
        }
    }
}

struct AnalyzerFeed: @unchecked Sendable {
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let samples: CounterBox
    let level: LevelBox

    func connect(_ source: AudioSource, format: AVAudioFormat, transcriber: SpeechTranscriber) async throws {
        guard !source.providesAnalyzerInput else {
            source.analyzerInputSink = { [weak source] in forward($0, level: source?.inputLevel ?? 0) }
            return Log.engine("source '\(source.name)' → analyzer (CaptureInputSequenceProvider)")
        }
        guard let target = await TranscriberFactory.bestFormat(for: transcriber, source: format) else {
            throw SourceError.conversionFailed
        }
        let converter = AnalyzerInputConverter(analyzerFormat: target)
        source.sink = { convert($0, with: converter) }
        Log.engine("source '\(source.name)' \(format.sampleRate)Hz/\(format.channelCount)ch → analyzer \(target.sampleRate)Hz/\(target.channelCount)ch")
    }

    func forward(_ input: AnalyzerInput, level inputLevel: Float) {
        samples.add(Int64((input.bufferDuration.seconds * input.bufferFormat.sampleRate).rounded()))
        level.store(inputLevel)
        continuation.yield(input)
    }

    func convert(_ buffer: AVAudioPCMBuffer, with converter: AnalyzerInputConverter) {
        samples.add(Int64(buffer.frameLength))
        level.store(rmsLevel(buffer))
        let inputs = (try? converter.convert(buffer, at: nil)) ?? []
        inputs.forEach { continuation.yield($0) }
    }
}
