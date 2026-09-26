import Foundation
import Testing
@testable import LectureScribe

@Suite struct TimeFormatting {
    @Test(arguments: [(0.0, "00:00:00"), (61.9, "00:01:01"), (3_725, "01:02:05"), (-5, "00:00:00"), (.nan, "00:00:00")])
    func hhmmssPadsAndClamps(seconds: Double, expected: String) {
        #expect(hhmmss(seconds) == expected)
    }

    // Raw and corrected files are joined on `t`; the key must survive float noise.
    @Test func segmentKeyJoinsNearlyEqualTimes() {
        #expect(segmentKey(12.345) == segmentKey(12.3450001))
        #expect(segmentKey(1.0) != segmentKey(1.01))
    }

    @Test func defaultTitleUsesMinuteStamp() {
        #expect(defaultSessionTitle(now: fixedDate).hasPrefix("Lecture 20"))
        #expect(minuteStamp(fixedDate).count == "yyyy-MM-dd HH:mm".count)
    }
}

@Suite struct Slugs {
    @Test func joinsAsciiWordsWithDashes() {
        #expect(slugify("Intro to ML — Week 3!") == "intro-to-ml-week-3")
    }

    @Test func nonAsciiOnlyFallsBack() {
        #expect(slugify("שיעור") == "lecture")
        #expect(slugify("") == "lecture")
    }

    // A 40-character cut must not leave a trailing dash in the folder name.
    @Test func cutNeverEndsWithDash() {
        let slug = slugify(String(repeating: "a", count: 39) + " bbbb")
        #expect(slug.count <= StorageConfig.standard.slugLimit)
        #expect(!slug.hasSuffix("-"))
    }
}

@Suite struct Levels {
    @Test func silenceIsZeroAndFullScaleIsOne() {
        #expect(meterLevel(rms: 0) == 0)
        #expect(meterLevel(rms: 1) == 1)
    }

    @Test func minus25dBIsHalfway() {
        let rmsAtMinus25 = Float(pow(10, -25.0 / 20))
        #expect(abs(meterLevel(rms: rmsAtMinus25) - 0.5) < 0.001)
    }

    @Test func vectorRmsMatchesDefinition() {
        let samples: [Float] = [1, -1, 1, -1]
        #expect(samples.withUnsafeBufferPointer { rms($0.baseAddress!, count: $0.count) } == 1)
        #expect(samples.withUnsafeBufferPointer { rms($0.baseAddress!, count: 0) } == 0)
    }

    @Test func quantizedRoundsToSteps() {
        #expect(quantized(0.1234, steps: 100) == 0.12)
    }
}

@Suite struct Deadlines {
    @Test func returnsTheResultInTime() async throws {
        let value = try await withDeadline(seconds: 5) { 42 }
        #expect(value == 42)
    }

    @Test func propagatesErrors() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) { _ = try await withDeadline(seconds: 5) { throw Boom() } }
    }

    // The old task-group version waited for the child even after "timing out".
    // Work that ignores cancellation must not hold the caller past the deadline.
    @Test func givesUpOnWorkThatIgnoresCancellation() async throws {
        let started = Date()
        let value = try await withDeadline(seconds: 0.1) { () -> Int in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { continuation.resume() }
            }
            return 1
        }
        #expect(value == nil)
        #expect(Date().timeIntervalSince(started) < 1.5)
    }
}

@Suite struct AtomicBoxes {
    @Test func counterSurvivesConcurrentAdds() async {
        let counter = CounterBox()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 { group.addTask { for _ in 0..<100 { counter.add(1) } } }
        }
        #expect(counter.load() == 10_000)
    }

    @Test func levelRoundTripsFloats() {
        let box = LevelBox()
        box.store(0.625)
        #expect(box.load() == 0.625)
    }

    @Test func flagRaises() {
        let flag = Flag()
        #expect(!flag.isRaised)
        flag.raise()
        #expect(flag.isRaised)
    }
}

@Suite struct Storage {
    @Test func customFolderWinsWhenSet() throws {
        let temp = try TempRoot()
        let config = StorageConfig(customRoot: temp.url.path)
        #expect(resolveTranscriptsRoot(config: config, fileManager: .default).path == temp.url.path)
    }

    @Test func desktopIsTheDefault() {
        #expect(resolveTranscriptsRoot(config: StorageConfig(customRoot: nil), fileManager: .default).path.hasSuffix("/Desktop/LectureTranscripts"))
    }

    @Test func emptyCustomFolderFallsBackToDesktop() {
        #expect(resolveTranscriptsRoot(config: StorageConfig(customRoot: ""), fileManager: .default).path.hasSuffix("/Desktop/LectureTranscripts"))
    }
}
