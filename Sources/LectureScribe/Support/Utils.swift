import Accelerate
import Foundation
import Synchronization

var transcriptsRoot: URL {
    resolveTranscriptsRoot(config: .standard, fileManager: .default)
}

func resolveTranscriptsRoot(config: StorageConfig, fileManager: FileManager) -> URL {
    if let custom = config.customRoot, !custom.isEmpty {
        let url = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        // A custom folder on an unmounted volume (or a deleted parent) falls back to the Desktop.
        if fileManager.fileExists(atPath: url.deletingLastPathComponent().path) { return url }
        Log.engine("transcripts folder '\(url.path)' is unreachable — using the Desktop")
    }
    return fileManager.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(config.folderName, isDirectory: true)
}

struct JSONLine: Codable, Equatable {
    let t: Double
    let text: String
}

func segmentKey(_ t: Double) -> Int {
    Int((t * Clock.centisecondsPerSecond).rounded())
}

func hhmmss(_ seconds: Double) -> String {
    let whole = seconds.isFinite ? max(0, Int(seconds)) : 0
    return Duration.seconds(whole).formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 2)))
}

func defaultSessionTitle(now: Date = Date()) -> String {
    "Lecture \(minuteStamp(now))"
}

func minuteStamp(_ date: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return df.string(from: date)
}

func slugify(_ s: String, config: StorageConfig = .standard) -> String {
    let words = s.split { !isSlugCharacter($0) }.map { $0.lowercased() }
    let cut = String(words.joined(separator: "-").prefix(config.slugLimit))
    let trimmed = cut.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? config.fallbackSlug : trimmed
}

private func isSlugCharacter(_ ch: Character) -> Bool {
    ch.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
}

func decibels(rms: Float, config: MeterConfig = .standard) -> Float {
    20 * log10(max(rms, config.silenceRMS))
}

func meterLevel(rms: Float, config: MeterConfig = .standard) -> Float {
    let floor = config.floorDecibels
    return min(max((decibels(rms: rms, config: config) - floor) / -floor, 0), 1)
}

func quantized(_ value: Double, steps: Double) -> Double {
    (value * steps).rounded() / steps
}

func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
    guard count > 0 else { return 0 }
    var result: Float = 0
    vDSP_rmsqv(samples, 1, &result, vDSP_Length(count))
    return result
}

func withDeadline<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T? {
    try await withCheckedThrowingContinuation { continuation in
        let once = ResumeOnce(continuation)
        let worker = Task { once.resume(with: await outcome(of: work)) }
        Task { await once.expire(after: seconds, cancelling: worker) }
    }
}

private func outcome<T>(of work: @Sendable () async throws -> T) async -> Result<T?, Error> {
    do {
        return .success(try await work())
    } catch {
        return .failure(error)
    }
}

private final class ResumeOnce<T: Sendable>: Sendable {
    private let pending: Mutex<CheckedContinuation<T?, Error>?>

    init(_ continuation: CheckedContinuation<T?, Error>) {
        pending = Mutex(continuation)
    }

    func resume(with result: Result<T?, Error>) {
        let continuation = pending.withLock { slot in
            defer { slot = nil }
            return slot
        }
        continuation?.resume(with: result)
    }

    func expire(after seconds: Double, cancelling worker: Task<Void, Never>) async {
        try? await Task.sleep(for: .seconds(seconds))
        worker.cancel()
        resume(with: .success(nil))
    }
}

final class Flag: Sendable {
    private let value = Atomic<Bool>(false)
    func raise() { value.store(true, ordering: .relaxed) }
    var isRaised: Bool { value.load(ordering: .relaxed) }
}

final class LevelBox: Sendable {
    private let bits = Atomic<UInt32>(0)
    func store(_ v: Float) { bits.store(v.bitPattern, ordering: .relaxed) }
    func load() -> Float { Float(bitPattern: bits.load(ordering: .relaxed)) }
}

final class CounterBox: Sendable {
    private let value = Atomic<Int64>(0)
    func add(_ delta: Int64) { value.add(delta, ordering: .relaxed) }
    func load() -> Int64 { value.load(ordering: .relaxed) }
}
