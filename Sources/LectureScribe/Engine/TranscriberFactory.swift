import AVFoundation
import Foundation
import Speech

enum EngineError: LocalizedError {
    case localeUnsupported(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let locale):
            return "Locale '\(locale)' is not supported by the on-device model. See `lecturescribe locales`."
        case .notRunning:
            return "The transcriber is not running."
        }
    }
}

enum TranscriberFactory {
    static func make(localeID: String) async throws -> SpeechTranscriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
            throw EngineError.localeUnsupported(localeID)
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        try await installAssets(for: transcriber, locale: locale)
        return transcriber
    }

    static func makeAnalyzer(for transcriber: SpeechTranscriber, root: URL) async -> SpeechAnalyzer {
        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
        await applyVocabulary(Vocabulary.load(root: root), to: analyzer)
        try? await analyzer.prepareToAnalyze(in: nil)
        return analyzer
    }

    static func bestFormat(for transcriber: SpeechTranscriber, source: AVAudioFormat) async -> AVAudioFormat? {
        if let best = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: source) {
            return best
        }
        return await transcriber.availableCompatibleAudioFormats.first
    }

    private static func installAssets(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        _ = try? await AssetInventory.reserve(locale: locale)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        Log.engine("downloading on-device speech model for \(locale.identifier)")
        try await request.downloadAndInstall()
        Log.engine("model installed")
    }

    private static func applyVocabulary(_ terms: [String], to analyzer: SpeechAnalyzer) async {
        guard !terms.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings = [AnalysisContext.ContextualStringsTag(rawValue: "terms"): terms]
        try? await analyzer.setContext(context)
        Log.engine("analyzer context: \(terms.count) vocabulary terms")
    }
}
