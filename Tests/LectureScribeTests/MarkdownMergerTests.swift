import Testing
@testable import LectureScribe

@Suite struct MarkdownMergerTests {
    // ASR emits short finals in bursts; within 1.5 s they read as one line.
    @Test func mergesFinalsInsideTheGap() {
        var merger = MarkdownMerger()
        var out: [String] = []
        merger.add(t: 1, text: "Hello") { out.append($0) }
        merger.add(t: 2, text: "world.") { out.append($0) }
        merger.flush { out.append($0) }
        #expect(out == ["[00:00:01] Hello world.\n"])
    }

    @Test func startsANewLineAfterTheGap() {
        var merger = MarkdownMerger()
        var out: [String] = []
        merger.add(t: 1, text: "One.") { out.append($0) }
        merger.add(t: 5, text: "Two.") { out.append($0) }
        merger.flush { out.append($0) }
        #expect(out == ["[00:00:01] One.\n", "[00:00:05] Two.\n"])
    }

    @Test func flushWithNothingPendingEmitsNothing() {
        var merger = MarkdownMerger()
        var out: [String] = []
        merger.flush { out.append($0) }
        #expect(out.isEmpty)
    }
}
