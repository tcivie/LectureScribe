import Foundation
import Synchronization

struct TranscriptLine: Identifiable, Equatable, Sendable {
    let id: Int
    let t: Double
    let text: String
}

struct Notice: Equatable, Identifiable {
    let id = UUID()
    let text: String
}

enum UIEvent: Sendable {
    case final(TranscriptLine)
    case corrected(t: Double, text: String)
}

final class UIEventBox: Sendable {
    private let events = Mutex<[UIEvent]>([])

    func push(_ event: UIEvent) {
        events.withLock { $0.append(event) }
    }

    func drain() -> [UIEvent] {
        events.withLock { pending in
            defer { pending = [] }
            return pending
        }
    }
}

struct FeedWatchdog {
    enum Event: Equatable { case stalled, recovered }

    let limitSeconds: Double
    private var lastCount: Int64 = 0
    private var lastChange: Date
    private(set) var stalled = false

    init(limitSeconds: Double, now: Date) {
        self.limitSeconds = limitSeconds
        lastChange = now
    }

    mutating func reset(now: Date) {
        lastChange = now
        stalled = false
    }

    mutating func observe(count: Int64, now: Date, active: Bool) -> Event? {
        guard count == lastCount else { return noteFlow(count: count, now: now) }
        guard active, !stalled, now.timeIntervalSince(lastChange) > limitSeconds else { return nil }
        stalled = true
        return .stalled
    }

    private mutating func noteFlow(count: Int64, now: Date) -> Event? {
        lastCount = count
        lastChange = now
        defer { stalled = false }
        return stalled ? .recovered : nil
    }
}

struct SessionClock {
    private(set) var elapsed: Double = 0
    private var last: Date?

    mutating func advance(to now: Date, running: Bool) {
        if running, let last { elapsed += max(0, now.timeIntervalSince(last)) }
        last = now
    }

    mutating func reset() {
        elapsed = 0
        last = nil
    }
}

struct SnippetCache: Equatable {
    var limit = EngineConfig.standard.keptSnippets
    private(set) var byKey: [Int: String] = [:]

    mutating func record(t: Double, text: String) {
        byKey[segmentKey(t)] = text
        guard byKey.count > limit else { return }
        byKey.keys.sorted().prefix(byKey.count - limit).forEach { byKey.removeValue(forKey: $0) }
    }

    func text(for t: Double) -> String? {
        byKey[segmentKey(t)]
    }
}

enum Vocabulary {
    static let fileName = "vocabulary.txt"
    static let template = """
    # LectureScribe vocabulary — one term or phrase per line.
    # Given to the on-device transcriber as context so technical jargon
    # and names are recognized. Edit, then start a new recording.

    """

    static func terms(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func load(root: URL) -> [String] {
        let url = root.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        return terms(in: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }
}
