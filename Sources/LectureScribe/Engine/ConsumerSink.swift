import Foundation
import Speech

final class ConsumerSink: @unchecked Sendable {
    let session: SessionStore
    let events: UIEventBox
    let onLine: ((Double, String) -> Void)?
    let onPartial: ((String) -> Void)?
    let config: EngineConfig
    private var finals = 0

    init(session: SessionStore, events: UIEventBox, callbacks: EngineCallbacks, config: EngineConfig) {
        (self.session, self.events, self.config) = (session, events, config)
        (onLine, onPartial) = (callbacks.onLine, callbacks.onPartial)
    }

    static func cleanText(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.contains(where: \.isLetter) ? text : nil
    }

    func consume(_ result: SpeechTranscriber.Result) async {
        guard let text = Self.cleanText(String(result.text.characters)) else { return }
        let t = result.range.start.seconds
        guard result.isFinal else { return partial(text) }
        await final(t: t, text: text)
    }

    private func partial(_ text: String) {
        onPartial?(String(text.prefix(config.partialLimit)))
    }

    private func final(t: Double, text: String) async {
        finals += 1
        session.appendFinal(t: t, text: text)
        events.push(.final(TranscriptLine(id: finals, t: t, text: text)))
        onLine?(t, text)
        if finals == 1 || finals % config.logEveryFinals == 0 {
            Log.engine("transcribed \(finals) finals so far (t=\(Int(t))s)")
        }
        await session.polisher.enqueue(t: t, text: text)
    }
}

struct EngineCallbacks {
    var onLine: ((Double, String) -> Void)?
    var onPartial: ((String) -> Void)?
}

struct Pipeline {
    let analyzer: SpeechAnalyzer
    let transcriber: SpeechTranscriber
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let consumer: Task<Void, Error>
    let session: SessionStore
}
