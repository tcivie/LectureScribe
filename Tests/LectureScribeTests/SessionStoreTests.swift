import Foundation
import Testing
@testable import LectureScribe

@Suite struct SessionStoreTests {
    func makeStore(_ root: URL, title: String = "Algorithms", polish: PolishMode = .off) throws -> SessionStore {
        try SessionStore(SessionRequest(title: title, localeID: "en_US", polish: polish, root: root, startedAt: fixedDate))
    }

    @Test func createsTheSessionFilesWithAHeader() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        let files = store.files
        #expect(read(files.rawMD).hasPrefix("# Algorithms — "))
        #expect(FileManager.default.fileExists(atPath: files.rawJL.path))
        #expect(!FileManager.default.fileExists(atPath: files.correctedMD.path))
        store.finish()
    }

    @Test func appendsJsonAndMergedMarkdown() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        store.appendFinal(t: 1, text: "Graphs are")
        store.appendFinal(t: 2, text: "everywhere.")
        store.finish()
        #expect(jsonLines(store.files.rawJL) == [JSONLine(t: 1, text: "Graphs are"), JSONLine(t: 2, text: "everywhere.")])
        #expect(read(store.files.rawMD).hasSuffix("[00:00:01] Graphs are everywhere.\n"))
        #expect(store.words == 3)
    }

    @Test func appendAfterFinishIsIgnored() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        store.finish()
        store.appendFinal(t: 1, text: "late")
        #expect(jsonLines(store.files.rawJL).isEmpty)
    }

    // Stop + record inside the same minute used to reuse the folder and
    // truncate the first transcript.
    @Test func secondSessionInTheSameMinuteGetsItsOwnFolder() throws {
        let temp = try TempRoot()
        let first = try makeStore(temp.url)
        first.appendFinal(t: 1, text: "keep me")
        first.finish()
        let second = try makeStore(temp.url)
        #expect(second.files.dir != first.files.dir)
        #expect(second.files.dir.lastPathComponent.hasSuffix("-2"))
        #expect(jsonLines(first.files.rawJL).count == 1)
        second.finish()
    }

    // The old rename searched for a blank line that the header never had, so
    // the header was duplicated, and an atomic rewrite orphaned the open handle.
    @Test func renameRewritesTheHeaderOnceAndKeepsWriting() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        store.appendFinal(t: 1, text: "Before.")
        store.appendFinal(t: 9, text: "Middle.")
        store.rename(to: "Data Structures")
        store.appendFinal(t: 20, text: "After.")
        store.finish()
        let text = read(store.files.rawMD)
        #expect(store.files.dir.lastPathComponent.hasSuffix("_data-structures"))
        #expect(text.hasPrefix("# Data Structures — "))
        #expect(text.components(separatedBy: "source: LectureScribe").count == 2)
        #expect(text.contains("[00:00:01] Before.") && text.contains("[00:00:20] After."))
        #expect(store.title == "Data Structures")
    }

    @Test func renameToBlankOrSameTitleDoesNothing() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        let dir = store.files.dir
        store.rename(to: "   ")
        store.rename(to: "Algorithms")
        #expect(store.files.dir == dir)
        store.finish()
    }

    @Test func latestFollowsTheNewestSessionAndRenames() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        let latest = temp.url.appendingPathComponent("latest").path
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: latest) == store.files.dir.path)
        store.rename(to: "Renamed")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: latest) == store.files.dir.path)
        store.finish()
    }

    @Test func statusFileIsValidJson() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url)
        store.appendFinal(t: 1, text: "two words")
        store.writeStatus(state: "recording", lengthSeconds: 12, now: fixedDate)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let status = try decoder.decode(SessionStatus.self, from: Data(contentsOf: store.files.status))
        #expect(status.state == "recording" && status.words == 2 && status.seconds == 12)
        #expect(status.rawTranscript == store.files.rawMD.path)
        store.finish()
    }

    @Test func blankTitleBecomesLecture() throws {
        let temp = try TempRoot()
        let store = try makeStore(temp.url, title: "  ")
        #expect(store.title == "Lecture")
        store.finish()
    }

    @Test func uniqueDirectoryCountsUp() throws {
        let temp = try TempRoot()
        let base = temp.url.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.url.appendingPathComponent("a-2"), withIntermediateDirectories: true)
        #expect(SessionStore.uniqueDirectory(base).lastPathComponent == "a-3")
    }
}
