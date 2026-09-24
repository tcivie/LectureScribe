import AVFoundation
import Foundation
import Observation
import Speech

enum Defaults {
    static let lastSource = "lastSource"
    static let locale = "locale"
    static let keepOnTop = "keepOnTop"
    static let transcriptsFolder = "transcriptsFolder"
    static let fallbackLocale = "en_US"
}

@Observable
@MainActor
final class TranscriptionEngine {
    enum State: String, Equatable {
        case idle, recording, paused
    }

    @ObservationIgnored var config = EngineConfig.standard
    @ObservationIgnored var callbacks = EngineCallbacks()
    @ObservationIgnored var onSummary: ((String) -> Void)?
    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private var pipeline: Pipeline?
    @ObservationIgnored private var source: AudioSource?
    @ObservationIgnored private var activeKind = SourceKind.system
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var clock = SessionClock()
    @ObservationIgnored private var watchdog = FeedWatchdog(limitSeconds: EngineConfig.standard.noAudioSeconds, now: Date())
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var recoveries = 0
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var reportedWriteFailure = false
    private let level = LevelBox()
    private let fedSamples = CounterBox()
    private let uiEvents = UIEventBox()

    private(set) var state: State = .idle
    var selectedKind = SourceKind.from(storageKey: UserDefaults.standard.string(forKey: Defaults.lastSource) ?? "system")
    private(set) var displayLevel: Double = 0
    private(set) var lines: [TranscriptLine] = []
    private(set) var corrected = SnippetCache()
    private(set) var lengthSeconds = 0
    private(set) var words = 0
    private(set) var sourceName = "—"
    private(set) var rawPath = ""
    private(set) var notice: Notice?
    var locale = UserDefaults.standard.string(forKey: Defaults.locale) ?? Defaults.fallbackLocale
    var isRunning: Bool { state != .idle }

    func start(kind: SourceKind, title: String, locale: String, polish: PolishMode = .proofread) async throws {
        guard state == .idle, !starting else { return }
        starting = true
        defer { starting = false }
        resetForNewSession(locale: locale)
        do {
            try await openPipeline(title: title, polish: polish)
            try await attach(kind: kind)
        } catch {
            await closePipeline()
            throw error
        }
        beginRecording()
    }

    func pause() async {
        guard state == .recording else { return }
        await source?.setPaused(true)
        setState(.paused)
    }

    func resume() async {
        guard state == .paused, await resumeSource() else { return }
        watchdog.reset(now: Date())
        setState(.recording)
    }

    func stop() async {
        guard state != .idle, let pipeline else { return }
        let summary = "✅ Saved \(pipeline.session.words) words, \(hhmmss(clock.elapsed)) → \(pipeline.session.files.rawMD.path)"
        await closePipeline()
        onSummary?(summary)
        post(summary)
    }

    func switchSource(to kind: SourceKind) async throws {
        guard state != .idle else { return }
        Log.engine("switching source to \(kind.displayName)")
        await detachSource()
        do {
            try await attach(kind: kind)
        } catch {
            setState(.paused)
            throw error
        }
        watchdog.reset(now: Date())
        setState(.recording)
    }

    func renameSession(to newTitle: String) {
        pipeline?.session.rename(to: newTitle)
        rawPath = pipeline?.session.files.rawMD.path ?? rawPath
    }

    func post(_ text: String) {
        notice = Notice(text: text)
    }

    private func resetForNewSession(locale: String) {
        self.locale = locale
        (lines, corrected, displayLevel, lengthSeconds, words) = ([], SnippetCache(), 0, 0, 0)
        clock.reset()
        tickCount = 0
        recoveries = 0
        reportedWriteFailure = false
    }

    private func openPipeline(title: String, polish: PolishMode) async throws {
        let root = transcriptsRoot
        let transcriber = try await TranscriberFactory.make(localeID: locale)
        let analyzer = await TranscriberFactory.makeAnalyzer(for: transcriber, root: root)
        let session = try SessionStore(SessionRequest(title: title, localeID: locale, polish: polish, root: root)) { [uiEvents] t, text in
            uiEvents.push(.corrected(t: t, text: text))
        }
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let sink = ConsumerSink(session: session, events: uiEvents, callbacks: callbacks, config: config)
        let consumer = Task.detached(priority: .userInitiated) {
            for try await result in transcriber.results { await sink.consume(result) }
        }
        pipeline = Pipeline(analyzer: analyzer, transcriber: transcriber, continuation: continuation, consumer: consumer, session: session)
        rawPath = session.files.rawMD.path
        try await analyzer.start(inputSequence: stream)
        await announcePolisher(session.polisher)
        Log.engine("session: \(session.files.dir.path)")
    }

    private func announcePolisher(_ polisher: Polisher) async {
        await polisher.prewarm()
        guard let reason = polisher.unavailableReason else { return }
        post("Proofreading is off: \(reason).")
    }

    private func beginRecording() {
        watchdog = FeedWatchdog(limitSeconds: config.noAudioSeconds, now: Date())
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Recording a lecture")
        startHeartbeat()
        setState(.recording)
    }

    private func closePipeline() async {
        stopHeartbeat()
        await detachSource()
        if let pipeline { await finish(pipeline) }
        pipeline = nil
        activity.map(ProcessInfo.processInfo.endActivity)
        activity = nil
        setState(.idle)
    }

    private func finish(_ pipeline: Pipeline) async {
        pipeline.continuation.finish()
        let analyzer = pipeline.analyzer
        _ = try? await withDeadline(seconds: config.finalizeSeconds) { try await analyzer.finalizeAndFinishThroughEndOfInput() }
        await analyzer.cancelAndFinishNow()
        let consumer = pipeline.consumer
        _ = try? await withDeadline(seconds: config.finalizeSeconds) { try await consumer.value }
        consumer.cancel()
        await pipeline.session.polisher.flush()
        pipeline.session.writeStatus(state: "stopped", lengthSeconds: clock.elapsed)
        pipeline.session.finish()
    }

    private func setState(_ newState: State) {
        state = newState
        if newState != .idle { pipeline?.session.writeStatus(state: newState.rawValue, lengthSeconds: clock.elapsed) }
        onStateChange?()
    }

    private func attach(kind: SourceKind) async throws {
        guard let pipeline else { throw EngineError.notRunning }
        let (newSource, format) = try await SourceFactory.make(kind: kind, transcriber: pipeline.transcriber)
        let feed = AnalyzerFeed(continuation: pipeline.continuation, samples: fedSamples, level: level)
        try await feed.connect(newSource, format: format, transcriber: pipeline.transcriber)
        newSource.onStopped = { [weak self] error in
            Task { @MainActor in self?.captureFailed(error) }
        }
        try await SourceFactory.begin(newSource)
        (source, activeKind, sourceName) = (newSource, kind, newSource.name)
        Log.engine("source '\(newSource.name)' capturing (mic mode: \(MicrophoneModes.activeName))")
    }

    private func detachSource() async {
        guard let current = source else { return }
        source = nil
        await current.stop()
    }

    private func resumeSource() async -> Bool {
        guard source == nil else {
            await source?.setPaused(false)
            return true
        }
        do {
            try await attach(kind: activeKind)
            return true
        } catch {
            post(error.localizedDescription)
            return false
        }
    }

    private func captureFailed(_ error: Error) {
        guard state != .idle else { return }
        Log.engine("capture stopped: \(error.localizedDescription)")
        Task { await recover(from: error) }
    }

    private func recover(from error: Error) async {
        await detachSource()
        setState(.paused)
        recoveries += 1
        guard recoveries <= config.maxRecoveries, (try? await attach(kind: activeKind)) != nil else {
            return post("Capture stopped: \(error.localizedDescription). Pick another source to continue.")
        }
        watchdog.reset(now: Date())
        setState(.recording)
    }

    private func startHeartbeat() {
        let interval = Duration.seconds(config.tickSeconds)
        let tolerance = Duration.seconds(config.tickToleranceSeconds)
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: interval, tolerance: tolerance)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func tick() {
        let now = Date()
        applyEvents(uiEvents.drain())
        decayLevel()
        clock.advance(to: now, running: state == .recording)
        assign(\.lengthSeconds, Int(clock.elapsed))
        checkFeed(now: now)
        tickCount += 1
        if tickCount % config.statusEveryTicks == 0 { periodic() }
    }

    private func applyEvents(_ events: [UIEvent]) {
        guard !events.isEmpty else { return }
        let finals = events.compactMap { event -> TranscriptLine? in
            if case .final(let line) = event { return line }
            return nil
        }
        events.forEach { if case .corrected(let t, let text) = $0 { corrected.record(t: t, text: text) } }
        guard !finals.isEmpty else { return }
        lines.append(contentsOf: finals)
        if lines.count > config.keptLines { lines.removeFirst(lines.count - config.keptLines) }
    }

    private func decayLevel() {
        let next = max(Double(level.load()), displayLevel * config.levelDecay)
        let steps = config.levelSteps
        assign(\.displayLevel, next >= config.levelEpsilon ? quantized(next, steps: steps) : 0)
    }

    private func checkFeed(now: Date) {
        switch watchdog.observe(count: fedSamples.load(), now: now, active: state == .recording) {
        case .stalled?:
            Log.engine("WATCHDOG: no buffers from '\(sourceName)' for \(Int(config.noAudioSeconds)) s")
            post("No audio arriving from \(sourceName). If the level stays flat while audio plays, pick another source.")
        case .recovered?:
            Log.engine("audio flowing again from '\(sourceName)'")
        case nil:
            break
        }
    }

    private func periodic() {
        guard let pipeline, state != .idle else { return }
        pipeline.session.writeStatus(state: state.rawValue, lengthSeconds: clock.elapsed)
        assign(\.words, pipeline.session.words)
        let polisher = pipeline.session.polisher
        Task { await polisher.tick() }
        Log.engine("audio: samples=\(fedSamples.load()) level=\(String(format: "%.2f", level.load())) words=\(words)")
        guard let failure = pipeline.session.writeFailure, !reportedWriteFailure else { return }
        reportedWriteFailure = true
        post("Cannot write the transcript: \(failure). Is the drive still connected?")
    }

    private func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<TranscriptionEngine, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
