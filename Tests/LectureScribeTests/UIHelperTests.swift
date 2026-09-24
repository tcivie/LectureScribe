import AppKit
import Foundation
import Testing
@testable import LectureScribe

@Suite struct MergeTranscriptTests {
    @Test func correctedTextReplacesRawBySegmentTime() {
        let raw = #"{"t":1,"text":"helo"}"# + "\n" + #"{"t":2,"text":"world"}"# + "\n"
        let corrected = #"{"t":1.0000001,"text":"Hello"}"# + "\n"
        #expect(mergeTranscript(raw: raw, corrected: corrected) == [
            MergedLine(t: 1, text: "Hello", polished: true), MergedLine(t: 2, text: "world", polished: false)
        ])
    }

    @Test func skipsBrokenLines() {
        #expect(mergeTranscript(raw: "not json\n{\"t\":1", corrected: "").isEmpty)
    }
}

@Suite struct PlacementTests {
    @Test func smallMovesAreClicksNotDrags() {
        #expect(!PanelPlacement.isDrag(from: .zero, to: NSPoint(x: 2, y: 2)))
        #expect(PanelPlacement.isDrag(from: .zero, to: NSPoint(x: 5, y: 0)))
    }
}

@Suite struct LiveButtonTests {
    // The content grows a moment before the auto-scroll catches up; a strict
    // "at bottom" check made the Live button blink on every new line.
    @Test func appearsOnlyAfterScrollingUpSeveralLines() {
        #expect(TranscriptScroll.isNearBottom(distance: 0))
        #expect(TranscriptScroll.isNearBottom(distance: TranscriptScroll.lineHeight * 2))
        #expect(!TranscriptScroll.isNearBottom(distance: TranscriptScroll.lineHeight * TranscriptScroll.liveThresholdLines))
    }
}

@Suite struct WindowPlacementTests {
    // Floating over another app's full-screen Space needs both flags; the old
    // window had only .fullScreenAuxiliary, so it stayed on the desktop Space.
    @Test func onTopJoinsEverySpaceIncludingFullScreen() {
        #expect(WindowPlacement.behavior(onTop: true).isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary]))
        #expect(!WindowPlacement.behavior(onTop: false).contains(.canJoinAllSpaces))
    }
}

@Suite struct TransportLookTests {
    @Test func toolbarFollowsTheEngineState() {
        #expect(TransportLook(state: .idle) == TransportLook(state: .idle))
        #expect(TransportLook(state: .idle).primaryLabel == "Record" && !TransportLook(state: .idle).stopEnabled)
        #expect(TransportLook(state: .recording).primarySymbol == "pause.fill" && TransportLook(state: .recording).stopEnabled)
        #expect(TransportLook(state: .paused).primaryLabel == "Resume")
    }
}

@Suite struct StatusMenuTests {
    @Test func idleOffersStartOnly() {
        let titles = StatusMenu.entries(state: .idle, windowVisible: true, onTop: true).map(\.title)
        #expect(titles.first == "Start Recording")
        #expect(!titles.contains("Pause"))
        #expect(titles.contains("Hide Window"))
    }

    @Test func pausedOffersResume() {
        let entries = StatusMenu.entries(state: .paused, windowVisible: false, onTop: true)
        #expect(entries.map(\.title).prefix(2) == ["Stop and Save", "Resume"])
        #expect(entries.map(\.title).contains("Show Window"))
        #expect(entries.first { $0.title == "Keep on Top" }?.checked == true)
    }
}

@Suite struct WordDiffTests {
    @Test func replacedWordsAreMarked() {
        #expect(WordDiff.changedWords(raw: "the cash is cold", corrected: "the cache is cold") == [1])
    }

    // Case and punctuation fixes are not "corrections" to the reader; underlining
    // them would mark almost every line.
    @Test func caseAndPunctuationFixesAreNotMarked() {
        #expect(WordDiff.changedWords(raw: "so we start", corrected: "So, we start.").isEmpty)
    }

    @Test func insertedWordsAreMarkedAndTheRestAligns() {
        #expect(WordDiff.changedWords(raw: "go to store", corrected: "go to the store") == [2])
    }

    @Test func identicalTextHasNoMarks() {
        #expect(WordDiff.changedWords(raw: "same text", corrected: "same text").isEmpty)
    }
}

@Suite struct LineTextTests {
    // The underline sits on the word only, never on the space before it, and a
    // hidden word shows no underline until it is revealed.
    @Test func correctedWordGetsTheDashedUnderline() {
        let text = LineText.attributed("the cache is", revealed: Int.max, corrected: [1])
        let underlined = text.runs.filter { $0.underlineStyle != nil }.map { String(text[$0.range].characters) }
        #expect(underlined == ["cache"])
        #expect(LineText.attributed("the cache is", revealed: 1, corrected: [1]).runs.allSatisfy { $0.underlineStyle == nil })
    }

    // Hidden words stay in the string as clear text, so the line keeps its final
    // wrap from the first frame and nothing re-flows while words appear.
    @Test func hiddenWordsKeepTheirPlace() {
        let text = LineText.attributed("one two three", revealed: 1)
        #expect(String(text.characters) == "one two three")
        let hidden = text.runs.filter { $0.foregroundColor == .clear }.map { String(text[$0.range].characters) }
        #expect(hidden == ["two", "three"])
    }

    @Test func fullyRevealedHasNoClearRuns() {
        #expect(LineText.attributed("a b", revealed: Int.max).runs.allSatisfy { $0.foregroundColor == nil })
    }
}

@MainActor
@Suite struct CalendarTitleTests {
    let now = fixedDate

    func slot(_ title: String?, from start: Double, to end: Double, allDay: Bool = false) -> CalendarSlot {
        CalendarSlot(title: title, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), isAllDay: allDay)
    }

    // An all-day "Birthday" starts at midnight and used to win over the lecture.
    @Test func allDayEventsNeverWin() {
        let slots = [slot("Birthday", from: -36_000, to: 50_000, allDay: true), slot("Compilers", from: -600, to: 3_000)]
        #expect(LectureTitle.pickTitle(from: slots, now: now) == "Compilers")
    }

    @Test func theMostRecentlyStartedRunningEventWins() {
        let slots = [slot("Long block", from: -7_200, to: 3_600), slot("Seminar", from: -300, to: 3_000)]
        #expect(LectureTitle.pickTitle(from: slots, now: now) == "Seminar")
    }

    @Test func blankTitlesAreSkipped() {
        #expect(LectureTitle.pickTitle(from: [slot("  ", from: -10, to: 10), slot(nil, from: -5, to: 5)], now: now) == nil)
    }
}
