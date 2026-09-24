import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class HUDState {
    var showPicker = false
}

typealias RecordAction = () -> Void

@MainActor
final class TransportToolbar: NSObject, NSToolbarDelegate {
    static let primary = NSToolbarItem.Identifier("primary")
    static let stop = NSToolbarItem.Identifier("stop")
    static let source = NSToolbarItem.Identifier("source")

    lazy var toolbar = makeToolbar()
    private let engine: TranscriptionEngine
    private let hud: HUDState
    private let record: RecordAction
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

    init(engine: TranscriptionEngine, hud: HUDState, record: @escaping RecordAction) {
        self.engine = engine
        self.hud = hud
        self.record = record
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "LectureScribeToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.primary, Self.stop, .flexibleSpace, Self.source]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = id == Self.source ? makeSourceItem() : makeButtonItem(id)
        items[id] = item
        refresh()
        return item
    }

    func refresh() {
        let look = TransportLook(state: engine.state)
        configure(items[Self.primary], symbol: look.primarySymbol, label: look.primaryLabel, enabled: true)
        configure(items[Self.stop], symbol: "stop.fill", label: "Stop and Save", enabled: look.stopEnabled)
    }

    private func makeButtonItem(_ id: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.isBordered = true
        item.autovalidates = false
        item.target = self
        item.action = id == Self.primary ? #selector(primaryPressed) : #selector(stopPressed)
        return item
    }

    private func makeSourceItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.source)
        item.label = "Source"
        item.toolTip = "Audio source — click to choose another"
        item.view = NSHostingView(rootView: SourceToolbarButton(engine: engine, hud: hud))
        return item
    }

    private func configure(_ item: NSToolbarItem?, symbol: String, label: String, enabled: Bool) {
        guard let item else { return }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.isEnabled = enabled
    }

    @objc private func primaryPressed() {
        switch engine.state {
        case .idle: record()
        case .recording: Task { await engine.pause() }
        case .paused: Task { await engine.resume() }
        }
    }

    @objc private func stopPressed() {
        Task { await engine.stop() }
    }
}

struct TransportLook: Equatable {
    let primarySymbol: String
    let primaryLabel: String
    let stopEnabled: Bool

    init(state: TranscriptionEngine.State) {
        switch state {
        case .idle: (primarySymbol, primaryLabel) = ("record.circle", "Record")
        case .recording: (primarySymbol, primaryLabel) = ("pause.fill", "Pause")
        case .paused: (primarySymbol, primaryLabel) = ("play.fill", "Resume")
        }
        stopEnabled = state != .idle
    }
}

struct SourceToolbarButton: View {
    let engine: TranscriptionEngine
    let hud: HUDState

    var body: some View {
        Button { hud.showPicker.toggle() } label: {
            HStack(spacing: 6) {
                LiveLevelBars(engine: engine, height: 14)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.borderless)
        .help("Source: \(engine.isRunning ? engine.sourceName : engine.selectedKind.displayName) — click to choose another")
        .accessibilityLabel("Choose audio source")
    }
}
