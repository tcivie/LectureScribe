import Foundation
import FoundationModels

enum PolishMode: Sendable, Equatable {
    case off
    case mirror
    case proofread
}

struct PolishItem: Sendable, Equatable {
    let t: Double
    let text: String
}

struct PolishPressure: Sendable, Equatable {
    var lowPower = false
    var hot = false

    static var current: PolishPressure {
        let info = ProcessInfo.processInfo
        return PolishPressure(lowPower: info.isLowPowerModeEnabled, hot: info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue)
    }
}

struct PolishBatcher {
    var config = PolishConfig.standard
    private(set) var pending: [PolishItem] = []
    private var lastEnqueue = Date.distantPast

    mutating func add(_ item: PolishItem, now: Date) {
        pending.append(item)
        lastEnqueue = now
    }

    func isReady(now: Date, pressure: PolishPressure) -> Bool {
        guard let first = pending.first, let last = pending.last, !pressure.hot else { return false }
        let limit = pressure.lowPower ? config.lowPowerBatchLimit : config.batchLimit
        let idle = now.timeIntervalSince(lastEnqueue) >= config.idleFlushSeconds
        return pending.count >= limit || last.t - first.t >= config.spanSeconds || idle
    }

    mutating func take() -> [PolishItem] {
        defer { pending = [] }
        return pending
    }
}

actor Polisher {
    let mode: PolishMode
    let unavailableReason: String?
    private(set) var polishedCount = 0
    private(set) var keptRawCount = 0
    private var batcher = PolishBatcher()
    private var writer: CorrectedWriter?
    private var worker: Task<Void, Never>?
    private let proofreader: Proofreader?
    private let onCorrected: @Sendable (Double, String) -> Void

    init(files: SessionFiles, mode requested: PolishMode, onCorrected: @escaping @Sendable (Double, String) -> Void) {
        let (resolved, reason) = Self.resolve(requested, availability: SystemLanguageModel.default.availability)
        (mode, unavailableReason, self.onCorrected) = (resolved, reason, onCorrected)
        writer = resolved == .off ? nil : CorrectedWriter(files: files)
        proofreader = resolved == .proofread ? Proofreader() : nil
        if let reason { Log.engine("proofreading off: \(reason) — corrected files mirror the raw text") }
    }

    static func resolve(_ requested: PolishMode, availability: SystemLanguageModel.Availability) -> (PolishMode, String?) {
        guard requested == .proofread, case .unavailable(let reason) = availability else { return (requested, nil) }
        return (.mirror, describe(reason))
    }

    static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "this Mac cannot run Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is turned off in System Settings"
        case .modelNotReady: return "the Apple Intelligence model is still downloading"
        @unknown default: return "the on-device model is unavailable"
        }
    }

    func prewarm() {
        proofreader?.prewarm()
    }

    func enqueue(t: Double, text: String) {
        guard mode != .off else { return }
        batcher.add(PolishItem(t: t, text: text), now: Date())
        startWorkerIfReady()
    }

    func tick() {
        startWorkerIfReady()
    }

    func flush() async {
        while let running = worker { await running.value }
        let rest = batcher.take()
        if !rest.isEmpty { await process(rest) }
        writer?.finish()
        writer = nil
    }

    private func startWorkerIfReady() {
        guard worker == nil, batcher.isReady(now: Date(), pressure: .current) else { return }
        worker = Task(priority: .utility) { await self.drain() }
    }

    private func drain() async {
        while batcher.isReady(now: Date(), pressure: .current) {
            await process(batcher.take())
        }
        worker = nil
    }

    private func process(_ items: [PolishItem]) async {
        guard let proofreader else { return items.forEach { emit($0.t, $0.text) } }
        do {
            let fixed = try await proofreader.correct(items)
            zip(items, fixed).forEach { emit($0.t, $1) }
        } catch PolishFailure.timeout {
            keepRaw(items, because: "timed out")
        } catch {
            await retryOneByOne(items, with: proofreader)
        }
    }

    private func retryOneByOne(_ items: [PolishItem], with proofreader: Proofreader) async {
        for item in items {
            guard let fixed = try? await proofreader.correctOne(item) else {
                keepRaw([item], because: "refused by the model's guardrails")
                continue
            }
            emit(item.t, fixed)
        }
    }

    private func keepRaw(_ items: [PolishItem], because reason: String) {
        keptRawCount += items.count
        Log.engine("\(items.count) segment(s) kept raw — \(reason)")
        items.forEach { emit($0.t, $0.text) }
    }

    private func emit(_ t: Double, _ text: String) {
        writer?.write(t: t, text: text)
        polishedCount += 1
        onCorrected(t, text)
    }
}

final class CorrectedWriter {
    private let md: FileHandle
    private let jl: FileHandle
    private var merger = MarkdownMerger()

    init?(files: SessionFiles) {
        guard let md = try? SessionStore.openForAppending(files.correctedMD, contents: Data()),
              let jl = try? SessionStore.openForAppending(files.correctedJL, contents: Data()) else { return nil }
        (self.md, self.jl) = (md, jl)
    }

    func write(t: Double, text: String) {
        if let json = try? JSONEncoder().encode(JSONLine(t: t, text: text)) {
            try? jl.write(contentsOf: json + Data("\n".utf8))
        }
        merger.add(t: t, text: text) { try? md.write(contentsOf: Data($0.utf8)) }
    }

    func finish() {
        merger.flush { try? md.write(contentsOf: Data($0.utf8)) }
        try? md.close()
        try? jl.close()
    }
}
