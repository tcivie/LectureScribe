import AppKit
import Foundation
import Speech

struct Args: Equatable {
    var sub = ""
    var source: String?
    var device: String?
    var locale: String?
    var title: String?
    var duration: String?
    var noPolish = false
    var float = false
    var help = false
    var unknown: [String] = []

    static let valueFlags: [String: WritableKeyPath<Args, String?>] = [
        "--source": \.source, "--device": \.device, "--locale": \.locale, "--title": \.title, "--duration": \.duration
    ]
    static let boolFlags: [String: WritableKeyPath<Args, Bool>] = [
        "--no-polish": \.noPolish, "--float": \.float, "--help": \.help, "-h": \.help
    ]

    static func parse(_ tokens: [String]) -> Args {
        var args = Args()
        var rest = ArraySlice(tokens)
        if let first = rest.first, !first.hasPrefix("-") {
            args.sub = first == "app" ? "" : first
            rest = rest.dropFirst()
        }
        while let token = rest.popFirst() { args.absorb(token, from: &rest) }
        return args
    }

    private mutating func absorb(_ token: String, from rest: inout ArraySlice<String>) {
        if let flag = Self.boolFlags[token] { return self[keyPath: flag] = true }
        guard let field = Self.valueFlags[token] else { return unknown.append(token) }
        self[keyPath: field] = rest.popFirst()
    }

    var durationSeconds: Double? {
        duration.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }
}

enum ExitCode {
    static let usage: Int32 = 2
}

enum HeadlessConfig {
    static let pollInterval = Duration.milliseconds(200)
    static let partialColumns = 90
}

let usageText = """
Usage:
  lecturescribe [app]                      — floating glass HUD (per-source meters + live transcript)
  lecturescribe record [options]           — headless recording, prints the transcript
  lecturescribe view [--float]             — read-only live viewer of the newest session
  lecturescribe devices                    — list audio devices
  lecturescribe locales                    — list supported on-device languages

record options:
  --source mic|system|device:NAME   input source (interactive menu if omitted)
  --locale en_US                    on-device language
  --title "…"                       session title
  --duration SEC                    stop after N seconds
  --no-polish                       disable the Apple Intelligence autocorrect pass
"""

func parseSourceKind(_ raw: String) -> SourceKind? {
    let lowered = raw.lowercased()
    if ["1", "system", "safari"].contains(lowered) { return .system }
    if ["2", "mic", "microphone"].contains(lowered) { return .microphone }
    guard lowered.hasPrefix(SourceKind.devicePrefix) else { return nil }
    let name = String(raw.dropFirst(SourceKind.devicePrefix.count))
    return name.isEmpty ? nil : .device(name: name)
}

@MainActor
func runCommand(_ args: Args) async throws {
    guard !args.help else { return print(usageText) }
    args.unknown.forEach { print("⚠️ ignoring unknown option \($0)") }
    switch args.sub {
    case "devices", "audiodump": AudioDumper.dump()
    case "locales": await listLocales()
    case "record": try await runHeadlessRecord(args)
    case "view": runFileViewer(float: args.float)
    case "": AppRunner.run()
    default:
        print(usageText)
        exit(ExitCode.usage)
    }
}

@MainActor
private func listLocales() async {
    let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    for id in await SpeechTranscriber.supportedLocales.map(\.identifier).sorted() {
        print("\(installed.contains(id) ? "✅" : "⬇️ ")  \(id)")
    }
}

private func requestedSource(_ args: Args) -> SourceKind? {
    if let source = args.source { return parseSourceKind(source) }
    if let device = args.device, !device.isEmpty { return .device(name: device) }
    return isatty(STDIN_FILENO) != 0 ? askForSource() : nil
}

private func askForSource() -> SourceKind {
    print("🎙 Input source:")
    print("  1) Safari / system audio — transcribe whatever plays on this Mac (headphones OK)")
    print("  2) Microphone — transcribe the room")
    print("  3) Other input device")
    print("Select [1]: ", terminator: "")
    let line = (readLine() ?? "1").trimmingCharacters(in: .whitespaces)
    guard line == "3" else { return parseSourceKind(line) ?? .system }
    CoreAudioDevices.inputs().forEach { print($0.name) }
    print("Device name contains: ", terminator: "")
    return .device(name: readLine() ?? "")
}

@MainActor
private func runHeadlessRecord(_ args: Args) async throws {
    guard let kind = requestedSource(args) else {
        print("❌ Pass --source mic | system | device:NAME when running non-interactively")
        exit(ExitCode.usage)
    }
    let engine = TranscriptionEngine()
    engine.callbacks = headlessCallbacks(tty: isatty(STDOUT_FILENO) != 0)
    engine.onSummary = { print($0) }
    let (stop, signals) = installStopSignals()
    let polish: PolishMode = args.noPolish ? .off : .proofread
    try await engine.start(kind: kind, title: args.title ?? defaultSessionTitle(), locale: args.locale ?? engine.locale, polish: polish)
    print("🔴 Recording — Ctrl-C to stop")
    await waitForStop(engine, flag: stop, deadline: args.durationSeconds.map { Date().addingTimeInterval($0) })
    await engine.stop()
    withExtendedLifetime(signals) { exit(0) }
}

private func headlessCallbacks(tty: Bool) -> EngineCallbacks {
    EngineCallbacks(
        onLine: { t, text in print("[\(hhmmss(t))] \(text)") },
        onPartial: tty ? { text in print("\r\(text.prefix(HeadlessConfig.partialColumns))   ", terminator: "") } : nil
    )
}

private func installStopSignals() -> (Flag, [DispatchSourceSignal]) {
    let flag = Flag()
    let sources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { flag.raise() }
        source.resume()
        return source
    }
    return (flag, sources)
}

@MainActor
private func waitForStop(_ engine: TranscriptionEngine, flag: Flag, deadline: Date?) async {
    while engine.isRunning, !flag.isRaised, deadline.map({ Date() < $0 }) ?? true {
        try? await Task.sleep(for: HeadlessConfig.pollInterval)
    }
}
