import Foundation
import FoundationModels
import Testing
@testable import LectureScribe

@Suite struct PolishBatcherTests {
    let now = fixedDate

    func batcher(_ items: [(Double, String)], at time: Date) -> PolishBatcher {
        var batcher = PolishBatcher()
        items.forEach { batcher.add(PolishItem(t: $0.0, text: $0.1), now: time) }
        return batcher
    }

    @Test func emptyIsNeverReady() {
        #expect(!PolishBatcher().isReady(now: now, pressure: .init()))
    }

    @Test func readyAtTheBatchLimit() {
        let limit = PolishConfig.standard.batchLimit
        let items = (0..<limit).map { (Double($0), "s\($0)") }
        #expect(batcher(Array(items.dropLast()), at: now).isReady(now: now, pressure: .init()) == false)
        #expect(batcher(items, at: now).isReady(now: now, pressure: .init()))
    }

    // Low Power Mode doubles the batch, so the model runs half as often.
    @Test func lowPowerWaitsForABiggerBatch() {
        let items = (0..<PolishConfig.standard.batchLimit).map { (Double($0), "s") }
        #expect(!batcher(items, at: now).isReady(now: now, pressure: .init(lowPower: true)))
    }

    @Test func readyWhenTheSpanIsLong() {
        let span = PolishConfig.standard.spanSeconds
        #expect(batcher([(0, "a"), (span, "b")], at: now).isReady(now: now, pressure: .init()))
    }

    // Sparse speech must still get polished once the room goes quiet.
    @Test func readyAfterIdleSilence() {
        let quiet = now.addingTimeInterval(PolishConfig.standard.idleFlushSeconds)
        #expect(batcher([(0, "a")], at: now).isReady(now: quiet, pressure: .init()))
    }

    // A hot Mac defers proofreading; the stop flush still drains everything.
    @Test func hotMacDefers() {
        let items = (0..<PolishConfig.standard.batchLimit).map { (Double($0), "s") }
        #expect(!batcher(items, at: now).isReady(now: now, pressure: .init(hot: true)))
    }

    @Test func takeEmptiesThePending() {
        var b = batcher([(0, "a"), (1, "b")], at: now)
        #expect(b.take().map(\.text) == ["a", "b"])
        #expect(b.pending.isEmpty)
    }
}

@Suite struct PolisherModeTests {
    @Test func unavailableModelFallsBackToMirror() {
        let (mode, reason) = Polisher.resolve(.proofread, availability: .unavailable(.appleIntelligenceNotEnabled))
        #expect(mode == .mirror)
        #expect(reason?.contains("turned off") == true)
    }

    @Test func availableModelKeepsProofread() {
        #expect(Polisher.resolve(.proofread, availability: .available) == (.proofread, nil))
    }

    @Test func offStaysOff() {
        #expect(Polisher.resolve(.off, availability: .unavailable(.deviceNotEligible)).0 == .off)
    }

    // The old writer fired onCorrected twice per segment, and never flushed the
    // last merged line into transcript.corrected.md.
    @Test func mirrorWritesEverySegmentOnceAndFlushesTheTail() async throws {
        let temp = try TempRoot()
        let files = SessionFiles(dir: temp.url)
        let seen = Recorder<Double>()
        let polisher = Polisher(files: files, mode: .mirror) { t, _ in seen.append(t) }
        await polisher.enqueue(t: 1, text: "First.")
        await polisher.enqueue(t: 9, text: "Second.")
        await polisher.flush()
        #expect(seen.values == [1, 9])
        #expect(jsonLines(files.correctedJL).map(\.text) == ["First.", "Second."])
        #expect(read(files.correctedMD).hasSuffix("[00:00:09] Second.\n"))
    }

    @Test func offWritesNothing() async throws {
        let temp = try TempRoot()
        let files = SessionFiles(dir: temp.url)
        let polisher = Polisher(files: files, mode: .off) { _, _ in }
        await polisher.enqueue(t: 1, text: "x")
        await polisher.flush()
        #expect(!FileManager.default.fileExists(atPath: files.correctedJL.path))
    }
}

@Suite struct ProofreaderTests {
    @Test func batchPromptNumbersTheSegments() {
        let prompt = Proofreader.batchPrompt([PolishItem(t: 0, text: "alpha"), PolishItem(t: 1, text: "beta")])
        #expect(prompt.contains("1. alpha\n2. beta"))
        #expect(prompt.contains("exactly 2"))
    }

    // A plain-String answer can drift into commentary; reject long rewrites.
    @Test func plausibilityRejectsEmptyAndRunaway() {
        #expect(Proofreader.isPlausible("Fixed text.", for: "fixed text"))
        #expect(!Proofreader.isPlausible("", for: "text"))
        #expect(!Proofreader.isPlausible(String(repeating: "x", count: 500), for: "short"))
    }
}
