import Foundation
import Testing
@testable import LectureScribe

@Suite struct WatchdogTests {
    let start = fixedDate
    let limit = EngineConfig.standard.noAudioSeconds

    // Silence between sentences is normal; only a feed that stops delivering
    // buffers at all is dead.
    @Test func staysQuietWhileBuffersFlow() {
        var dog = FeedWatchdog(limitSeconds: limit, now: start)
        #expect(dog.observe(count: 10, now: start.addingTimeInterval(limit + 1), active: true) == nil)
    }

    @Test func reportsStallOnceThenRecovery() {
        var dog = FeedWatchdog(limitSeconds: limit, now: start)
        let late = start.addingTimeInterval(limit + 1)
        #expect(dog.observe(count: 0, now: late, active: true) == .stalled)
        #expect(dog.observe(count: 0, now: late.addingTimeInterval(5), active: true) == nil)
        #expect(dog.observe(count: 5, now: late.addingTimeInterval(6), active: true) == .recovered)
    }

    @Test func pausedFeedNeverStalls() {
        var dog = FeedWatchdog(limitSeconds: limit, now: start)
        #expect(dog.observe(count: 0, now: start.addingTimeInterval(limit * 3), active: false) == nil)
    }

    // A resume after a long pause must not raise a false "no audio" at once.
    @Test func resetRestartsTheWindow() {
        var dog = FeedWatchdog(limitSeconds: limit, now: start)
        let resumed = start.addingTimeInterval(limit * 3)
        dog.reset(now: resumed)
        #expect(dog.observe(count: 0, now: resumed.addingTimeInterval(1), active: true) == nil)
    }
}

@Suite struct ClockTests {
    // The old clock added 0.1 s per timer tick, so it drifted with timer jitter.
    @Test func countsWallTimeOnlyWhileRunning() {
        var clock = SessionClock()
        clock.advance(to: fixedDate, running: true)
        clock.advance(to: fixedDate.addingTimeInterval(10), running: true)
        clock.advance(to: fixedDate.addingTimeInterval(70), running: false)
        clock.advance(to: fixedDate.addingTimeInterval(75), running: true)
        #expect(clock.elapsed == 15)
        clock.reset()
        #expect(clock.elapsed == 0)
    }
}

@Suite struct SnippetCacheTests {
    // Dictionary.keys.prefix used to drop random entries, not the oldest.
    @Test func prunesTheOldestSegments() {
        var cache = SnippetCache(limit: 3)
        for t in [5.0, 1.0, 3.0, 4.0, 2.0] { cache.record(t: t, text: "t\(t)") }
        #expect(cache.byKey.keys.sorted() == [300, 400, 500])
        #expect(cache.text(for: 5) == "t5.0")
        #expect(cache.text(for: 1) == nil)
    }
}

@Suite struct VocabularyTests {
    @Test func skipsCommentsAndBlanks() {
        #expect(Vocabulary.terms(in: "# header\n\n  Dijkstra \nB-tree\n#x") == ["Dijkstra", "B-tree"])
    }

    @Test func createsTheTemplateOnce() throws {
        let temp = try TempRoot()
        #expect(Vocabulary.load(root: temp.url).isEmpty)
        try "Dijkstra\n".write(to: temp.url.appendingPathComponent(Vocabulary.fileName), atomically: true, encoding: .utf8)
        #expect(Vocabulary.load(root: temp.url) == ["Dijkstra"])
    }
}

@Suite struct EventBoxTests {
    @Test func drainReturnsEventsInOrderAndEmpties() {
        let box = UIEventBox()
        box.push(.final(TranscriptLine(id: 1, t: 0, text: "a")))
        box.push(.corrected(t: 0, text: "A"))
        #expect(box.drain().count == 2)
        #expect(box.drain().isEmpty)
    }
}

@Suite struct ConsumerTextTests {
    @Test func dropsTextWithoutLetters() {
        #expect(ConsumerSink.cleanText("  ...  ") == nil)
        #expect(ConsumerSink.cleanText(" Hello. ") == "Hello.")
    }
}
