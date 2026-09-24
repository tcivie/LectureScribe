import Foundation
import FoundationModels

@Generable
struct CorrectedSegments {
    @Guide(description: "Corrected text for each input segment, same order and count as the prompt")
    var segments: [String]
}

enum PolishFailure: Error, Equatable {
    case timeout
    case countMismatch(Int, Int)
    case implausible
}

struct Proofreader: Sendable {
    static let instructions = """
    You proofread automatic speech recognition output of university lectures. \
    Fix misheard words, homophones, grammar and punctuation. Keep the speaker's meaning, \
    wording style, and all technical terms. Never add, drop or merge segments. \
    Never add commentary.
    """
    static let growthLimit = 2.0
    static let growthSlack = 40

    var config = PolishConfig.standard

    func prewarm() {
        LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions).prewarm()
    }

    func correct(_ items: [PolishItem]) async throws -> [String] {
        let prompt = Self.batchPrompt(items)
        let segments = try await bounded {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: Self.instructions)
            return try await session.respond(to: prompt, generating: CorrectedSegments.self).content.segments
        }
        guard segments.count == items.count else { throw PolishFailure.countMismatch(segments.count, items.count) }
        return segments
    }

    func correctOne(_ item: PolishItem) async throws -> String {
        let prompt = Self.singlePrompt(item)
        let fixed = try await bounded {
            let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            return try await session.respond(to: prompt).content
        }
        let clean = fixed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPlausible(clean, for: item.text) else { throw PolishFailure.implausible }
        return clean
    }

    static func batchPrompt(_ items: [PolishItem]) -> String {
        let listing = items.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        return """
        Proofread these \(items.count) consecutive transcript segments. \
        Return exactly \(items.count) corrected segments in the segments array, \
        same order. Keep a segment unchanged if it is fine.

        \(listing)
        """
    }

    static func singlePrompt(_ item: PolishItem) -> String {
        "Proofread this transcript segment. Reply with the corrected segment only.\n\n\(item.text)"
    }

    static func isPlausible(_ fixed: String, for raw: String) -> Bool {
        !fixed.isEmpty && Double(fixed.count) <= Double(raw.count) * growthLimit + Double(growthSlack)
    }

    private func bounded<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let result = try await withDeadline(seconds: config.budgetSeconds, work) else { throw PolishFailure.timeout }
        return result
    }
}
