import AppKit
import SwiftUI

struct LevelBars: View {
    static let weights: [Double] = [0.55, 0.8, 1.0, 0.8, 0.55]
    static let stubHeight = 6.0
    static let barWidth = 3.5
    static let minOpacity = 0.45

    let level: Double
    var barCount = 5
    var height: CGFloat = 18
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule().fill(tint.opacity(opacity(index))).frame(width: Self.barWidth, height: barHeight(index))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }

    private func opacity(_ index: Int) -> Double {
        Self.minOpacity + (1 - Self.minOpacity) * Double(index) / Double(max(1, barCount - 1))
    }

    private func barHeight(_ index: Int) -> CGFloat {
        CGFloat(Self.stubHeight + level * Self.weights[index % Self.weights.count] * (height - Self.stubHeight))
    }
}

struct LiveLevelBars: View {
    let engine: TranscriptionEngine
    var barCount = 5
    var height: CGFloat = 16
    var tint: Color = .accentColor

    var body: some View {
        LevelBars(level: engine.state == .recording ? engine.displayLevel : 0, barCount: barCount, height: height, tint: tint)
    }
}

struct SourcePicker: View {
    let engine: TranscriptionEngine
    let close: () -> Void
    @State private var entries: [InputLevelMonitor.Entry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sources").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 8)
            ForEach(entries, id: \.kind.storageKey) { entry in
                SourceRow(entry: entry, selected: entry.kind == engine.selectedKind) { select(entry.kind) }
            }
            if engine.selectedKind != .system { MicModeRow() }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(.quinary, in: .rect(cornerRadius: Metrics.cardCorner))
        .task { await meter() }
    }

    private func meter() async {
        let monitor = InputLevelMonitor.shared
        monitor.start()
        while !Task.isCancelled {
            entries = monitor.snapshot()
            try? await Task.sleep(for: Metrics.pickerRefresh)
        }
        monitor.stop()
    }

    private func select(_ kind: SourceKind) {
        engine.selectedKind = kind
        UserDefaults.standard.setValue(kind.storageKey, forKey: Defaults.lastSource)
        close()
        guard engine.isRunning else { return }
        Task { await apply(kind) }
    }

    private func apply(_ kind: SourceKind) async {
        do {
            try await engine.switchSource(to: kind)
        } catch {
            engine.post(error.localizedDescription)
        }
    }
}

struct MicModeRow: View {
    @State private var mode = MicrophoneModes.activeName

    var body: some View {
        Button { MicrophoneModes.showPicker() } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 16)
                Text("Mic Mode: \(mode)").font(.system(size: 12))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .help("Voice Isolation cuts room noise. Wide Spectrum keeps a distant lecturer and the whole room.")
        .task { await track() }
    }

    private func track() async {
        while !Task.isCancelled {
            mode = MicrophoneModes.activeName
            try? await Task.sleep(for: Metrics.pickerRefresh)
        }
    }
}

struct SourceRow: View {
    let entry: InputLevelMonitor.Entry
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                Image(systemName: entry.kind.symbolName).font(.system(size: 12)).foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)).frame(width: 16)
                Text(entry.kind.displayName).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 8)
                LevelBars(level: Double(entry.level), barCount: 4, height: 14, tint: .secondary).frame(width: 22)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 7))
        .accessibilityLabel(entry.kind.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PathRow: View {
    let engine: TranscriptionEngine
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 6) {
            copyButton
            ElapsedLabel(engine: engine)
            if justCopied {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
            }
            Button { revealTranscript(engine.rawPath) } label: {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 24, height: 20).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal transcript in Finder")
            RecordingDot(state: engine.state)
        }
        .task(id: justCopied) { await clearCopied() }
    }

    private var copyButton: some View {
        Button { copy() } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 9))
                Text(shortPath).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
            }
            .foregroundStyle(.tertiary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(engine.rawPath.isEmpty)
        .help("Click to copy the transcript path")
        .accessibilityLabel("Copy transcript path")
    }

    private var shortPath: String {
        guard !engine.rawPath.isEmpty else { return "no session yet" }
        return "…/" + engine.rawPath.split(separator: "/").suffix(2).joined(separator: "/")
    }

    private func copy() {
        copyToPasteboard(engine.rawPath)
        justCopied = true
    }

    private func clearCopied() async {
        guard justCopied else { return }
        try? await Task.sleep(for: Metrics.copiedDuration)
        justCopied = false
    }
}

struct ElapsedLabel: View {
    let engine: TranscriptionEngine

    var body: some View {
        Text(hhmmss(Double(engine.lengthSeconds)))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(engine.isRunning ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .help("Session length")
            .accessibilityLabel("Session length \(hhmmss(Double(engine.lengthSeconds)))")
    }
}

struct RecordingDot: View {
    let state: TranscriptionEngine.State

    var body: some View {
        Image(systemName: state == .recording ? "circle.fill" : "circle")
            .font(.system(size: 7))
            .foregroundStyle(state == .recording ? Color.red : .secondary)
            .help(state.rawValue.capitalized)
            .accessibilityLabel(state.rawValue.capitalized)
    }
}
