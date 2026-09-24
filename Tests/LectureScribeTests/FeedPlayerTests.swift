import Testing
@testable import LectureScribe

@MainActor
@Suite struct FeedPlayerTests {
    func line(_ id: Int, _ text: String = "one two") -> TranscriptLine {
        TranscriptLine(id: id, t: Double(id), text: text)
    }

    // Opening the HUD mid-lecture shows the tail at once instead of replaying it.
    @Test func firstSyncShowsTheTailWithoutReplay() {
        let player = FeedPlayer()
        player.sync((1...120).map { line($0) })
        #expect(player.history.count == Metrics.maxHistoryRows)
        #expect(player.active?.id == 120)
        #expect(player.settled)
    }

    @Test func newLinePlaysWordByWord() {
        let player = FeedPlayer()
        player.sync([])
        player.sync([line(1)])
        #expect(player.active?.id == 1 && !player.settled && player.revealed == 0)
        player.step(wordCount: 2)
        player.step(wordCount: 2)
        #expect(player.revealed == 2 && !player.settled)
        player.step(wordCount: 2)
        #expect(player.settled)
    }

    // A burst of finals queues up; every sentence gets its bright stage.
    @Test func burstIsPlayedInOrder() {
        let player = FeedPlayer()
        player.sync([])
        player.sync([line(1, "a"), line(2, "b"), line(3, "c")])
        var order: [Int] = []
        for _ in 0..<10 {
            if let id = player.active?.id, order.last != id { order.append(id) }
            player.step(wordCount: 1)
        }
        #expect(order == [1, 2, 3])
        #expect(player.history.map(\.id) == [1, 2])
    }

    @Test func pauseFreezesAndResumeContinues() {
        let player = FeedPlayer()
        player.sync([])
        player.sync([line(1, "a")])
        player.setPaused(true)
        player.step(wordCount: 1)
        #expect(player.revealed == 0)
        player.setPaused(false)
        player.step(wordCount: 1)
        #expect(player.revealed == 1)
    }

    @Test func newSessionResets() {
        let player = FeedPlayer()
        player.sync((1...5).map { line($0) })
        player.sync([])
        #expect(player.isEmpty)
        player.sync([line(1)])
        #expect(player.active?.id == 1 && !player.settled)
    }
}
