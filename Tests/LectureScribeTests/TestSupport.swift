import Foundation
@testable import LectureScribe

/// A throwaway transcripts root per test, so tests never touch the real volume.
struct TempRoot: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lecturescribe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

func read(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

func jsonLines(_ url: URL) -> [JSONLine] {
    read(url).split(separator: "\n").compactMap { try? JSONDecoder().decode(JSONLine.self, from: Data($0.utf8)) }
}

/// Collects values from @Sendable callbacks.
final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var values: [T] { lock.withLock { items } }
}

let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)
