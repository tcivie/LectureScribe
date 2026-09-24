import Foundation

struct SessionFiles: Equatable {
    let dir: URL
    var rawMD: URL { dir.appendingPathComponent("transcript.md") }
    var rawJL: URL { dir.appendingPathComponent("transcript.jsonl") }
    var correctedMD: URL { dir.appendingPathComponent("transcript.corrected.md") }
    var correctedJL: URL { dir.appendingPathComponent("transcript.corrected.jsonl") }
    var status: URL { dir.appendingPathComponent("status.json") }
}

struct SessionRequest {
    var title: String
    var localeID: String
    var polish: PolishMode
    var root: URL = transcriptsRoot
    var startedAt = Date()
}

struct SessionStatus: Codable, Equatable {
    var app = "LectureScribe"
    var state: String
    var title: String
    var locale: String
    var startedAt: Date
    var seconds: Double
    var words: Int
    var rawTranscript: String
    var correctedTranscript: String
    var updatedAt: Date
}

final class SessionStore: @unchecked Sendable {
    let root: URL
    let localeID: String
    let startedAt: Date
    let polisher: Polisher

    private let lock = NSLock()
    private let md: FileHandle
    private let jl: FileHandle
    private var merger = MarkdownMerger()
    private var currentTitle: String
    private var currentFiles: SessionFiles
    private var wordCount = 0
    private var finished = false
    private var failure: String?

    init(_ request: SessionRequest, onCorrected: @escaping @Sendable (Double, String) -> Void = { _, _ in }) throws {
        let cleanTitle = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        currentTitle = cleanTitle.isEmpty ? "Lecture" : cleanTitle
        (root, localeID, startedAt) = (request.root, request.localeID, request.startedAt)
        let dir = try Self.createSessionDirectory(root: root, title: currentTitle, startedAt: startedAt)
        currentFiles = SessionFiles(dir: dir)
        let header = Self.makeHeader(title: currentTitle, localeID: localeID, startedAt: startedAt)
        md = try Self.openForAppending(currentFiles.rawMD, contents: Data(header.utf8))
        jl = try Self.openForAppending(currentFiles.rawJL, contents: Data())
        polisher = Polisher(files: currentFiles, mode: request.polish, onCorrected: onCorrected)
        Self.relinkLatest(root: root, to: dir)
    }

    var title: String { lock.withLock { currentTitle } }
    var files: SessionFiles { lock.withLock { currentFiles } }
    var words: Int { lock.withLock { wordCount } }
    var writeFailure: String? { lock.withLock { failure } }

    func rename(to newTitleRaw: String) {
        let newTitle = newTitleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        guard !newTitle.isEmpty, newTitle != currentTitle else { return }
        let newDir = Self.sessionDirectory(root: root, title: newTitle, startedAt: startedAt)
        if newDir != currentFiles.dir, !moveLocked(to: Self.uniqueDirectory(newDir)) { return }
        let oldHeader = Self.makeHeader(title: currentTitle, localeID: localeID, startedAt: startedAt)
        currentTitle = newTitle
        rewriteHeaderLocked(replacing: oldHeader)
        Self.relinkLatest(root: root, to: currentFiles.dir)
    }

    func appendFinal(t: Double, text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, let json = try? JSONEncoder().encode(JSONLine(t: t, text: text)) else { return }
        writeLocked(json + Data("\n".utf8), to: jl)
        merger.add(t: t, text: text) { writeLocked(Data($0.utf8), to: md) }
        wordCount += text.split(whereSeparator: \.isWhitespace).count
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        merger.flush { writeLocked(Data($0.utf8), to: md) }
        try? md.close()
        try? jl.close()
    }

    func writeStatus(state: String, lengthSeconds: Double, now: Date = Date()) {
        let snapshot = lock.withLock { (currentTitle, currentFiles, wordCount) }
        let status = SessionStatus(
            state: state, title: snapshot.0, locale: localeID, startedAt: startedAt, seconds: lengthSeconds,
            words: snapshot.2, rawTranscript: snapshot.1.rawMD.path, correctedTranscript: snapshot.1.correctedMD.path,
            updatedAt: now
        )
        guard let data = try? Self.statusEncoder.encode(status) else { return }
        try? data.write(to: snapshot.1.status, options: .atomic)
    }

    static let statusEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private func writeLocked(_ data: Data, to handle: FileHandle) {
        do {
            try handle.write(contentsOf: data)
        } catch {
            if failure == nil { Log.engine("transcript write failed: \(error.localizedDescription)") }
            failure = error.localizedDescription
        }
    }

    private func moveLocked(to newDir: URL) -> Bool {
        do {
            try FileManager.default.moveItem(at: currentFiles.dir, to: newDir)
        } catch {
            Log.engine("rename failed: \(error.localizedDescription)")
            return false
        }
        currentFiles = SessionFiles(dir: newDir)
        Log.engine("renamed session → \(newDir.lastPathComponent)")
        return true
    }

    private func rewriteHeaderLocked(replacing oldHeader: String) {
        guard let content = try? String(contentsOf: currentFiles.rawMD, encoding: .utf8) else { return }
        let body = content.hasPrefix(oldHeader) ? String(content.dropFirst(oldHeader.count)) : content
        let header = Self.makeHeader(title: currentTitle, localeID: localeID, startedAt: startedAt)
        do {
            try md.truncate(atOffset: 0)
            try md.write(contentsOf: Data((header + body).utf8))
        } catch {
            Log.engine("header rewrite failed: \(error.localizedDescription)")
        }
    }
}

extension SessionStore {
    static func sessionDirectory(root: URL, title: String, startedAt: Date) -> URL {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HHmm"
        return root.appendingPathComponent("\(df.string(from: startedAt))_\(slugify(title))", isDirectory: true)
    }

    static func uniqueDirectory(_ base: URL, fileManager: FileManager = .default) -> URL {
        var candidate = base
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            suffix += 1
            candidate = base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)-\(suffix)")
        }
        return candidate
    }

    static func makeHeader(title: String, localeID: String, startedAt: Date) -> String {
        let stamp = minuteStamp(startedAt)
        return """
        # \(title) — \(stamp)
        source: LectureScribe (on-device ASR) · locale: \(localeID) · started: \(stamp)
        files: transcript.md (raw, written live) · transcript.corrected.md (proofread, lags ~30 s)
        files: *.jsonl (one segment per line: {"t": seconds, "text"}) · status.json (live state)
        `<root>/latest` is a symlink to the newest session folder.


        """
    }

    static func relinkLatest(root: URL, to dir: URL) {
        let latest = root.appendingPathComponent("latest")
        let temp = root.appendingPathComponent(".latest-\(UUID().uuidString)")
        do {
            try FileManager.default.createSymbolicLink(at: temp, withDestinationURL: dir)
            guard Darwin.rename(temp.path, latest.path) == 0 else { throw POSIXError(.EIO) }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            Log.engine("could not relink latest: \(error.localizedDescription)")
        }
    }

    private static func createSessionDirectory(root: URL, title: String, startedAt: Date) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = uniqueDirectory(sessionDirectory(root: root, title: title, startedAt: startedAt))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        return dir
    }

    static func openForAppending(_ url: URL, contents: Data) throws -> FileHandle {
        guard FileManager.default.createFile(atPath: url.path, contents: contents) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}
