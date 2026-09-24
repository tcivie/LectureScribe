import AppKit
import SwiftUI

enum Metrics {
    static let hudWidth = 360.0
    static let transcriptHeight = 96.0
    static let maxHistoryRows = 100
    static let historyLineLimit = 4
    static let typingPace = Duration.milliseconds(90)
    static let pickerRefresh = Duration.milliseconds(100)
    static let toastDuration = Duration.seconds(6)
    static let copiedDuration = Duration.milliseconds(1500)
    static let bodyFont = Font.system(size: 13)
    static let rowSpacing = 4.0
    static let rowAnimation = 0.7
    static let wordAnimation = 0.4
    static let riseOffset = 14.0
    static let panelAnimation = 0.25
    static let cardCorner = 12.0
    static let footerHeight = 16.0
    static let toolbarInset = 30.0
    static let fadeHeight = 22.0
    static let glassTint = 0.55
}

struct HUDView: View {
    let engine: TranscriptionEngine
    let hud: HUDState

    @State private var player = FeedPlayer()
    @State private var toast: Notice?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            if hud.showPicker {
                SourcePicker(engine: engine, close: { hud.showPicker = false }).transition(.move(edge: .top).combined(with: .opacity))
            }
            transcriptArea
            PathRow(engine: engine).opacity(hovering ? 1 : 0).frame(height: Metrics.footerHeight)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Metrics.panelAnimation), value: hovering)
        .frame(minWidth: Metrics.hudWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: Metrics.panelAnimation), value: hud.showPicker)
        .overlay(alignment: .bottom) { ToastView(notice: toast) }
        .animation(.easeOut(duration: Metrics.panelAnimation), value: toast)
        .contextMenu { HUDMenu(engine: engine) }
        .modifier(HUDBindings(engine: engine, player: player, toast: $toast))
    }

    private var transcriptArea: some View {
        TranscriptScroll(player: player) { engine.corrected.text(for: $0.t) ?? $0.text }
        .frame(minHeight: Metrics.transcriptHeight, maxHeight: .infinity)
        .task(id: player.active?.id) { await play() }
        .accessibilityLabel("Live transcript")
    }

    private func play() async {
        while !player.settled, !Task.isCancelled {
            try? await Task.sleep(for: Metrics.typingPace)
            let words = player.active.map { (engine.corrected.text(for: $0.t) ?? $0.text).split(whereSeparator: \.isWhitespace).count }
            player.step(wordCount: words ?? 0)
        }
    }
}

struct HUDBindings: ViewModifier {
    let engine: TranscriptionEngine
    let player: FeedPlayer
    @Binding var toast: Notice?

    func body(content: Content) -> some View {
        content
            .onAppear { player.sync(engine.lines) }
            .onChange(of: engine.lines.last?.id) { player.sync(engine.lines) }
            .onChange(of: engine.state, initial: true) { player.setPaused(engine.state != .recording) }
            .onChange(of: engine.notice) { toast = engine.notice }
            .task(id: toast?.id) { await expireToast() }
    }

    private func expireToast() async {
        guard toast != nil else { return }
        try? await Task.sleep(for: Metrics.toastDuration)
        guard !Task.isCancelled else { return }
        toast = nil
    }
}

struct ToastView: View {
    let notice: Notice?

    var body: some View {
        if let notice {
            Text(notice.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

struct HUDMenu: View {
    let engine: TranscriptionEngine

    var body: some View {
        Button("Copy transcript path") { copyToPasteboard(engine.rawPath) }.disabled(engine.rawPath.isEmpty)
        Button("Reveal transcript in Finder") { revealTranscript(engine.rawPath) }
        Divider()
        Button("Quit LectureScribe") { NSApp.terminate(nil) }
    }
}

func copyToPasteboard(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func revealTranscript(_ rawPath: String) {
    if rawPath.isEmpty {
        NSWorkspace.shared.open(transcriptsRoot)
    } else {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: rawPath)])
    }
}
