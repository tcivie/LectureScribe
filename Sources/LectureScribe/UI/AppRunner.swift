import AppKit
import SwiftUI

enum WindowPlacement {
    static func behavior(onTop: Bool) -> NSWindow.CollectionBehavior {
        onTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed, .fullScreenAuxiliary]
    }
}

@MainActor
final class AppRunner: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppRunner()
    static let frameName = "LectureScribeWindow"
    static let initialSize = NSSize(width: Metrics.hudWidth, height: 200)

    private let engine = TranscriptionEngine()
    private let hud = HUDState()
    private let window = AppRunner.makeWindow()
    private var statusItem: NSStatusItem?
    private lazy var transport = TransportToolbar(engine: engine, hud: hud) { [weak self] in Task { await self?.startRecording() } }

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = shared
        shared.launch()
        app.run()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard engine.isRunning else { return .terminateNow }
        Task {
            await engine.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    private func launch() {
        window.delegate = self
        window.contentView = Self.glass(around: HUDHostingView(rootView: HUDView(engine: engine, hud: hud)))
        window.toolbar = transport.toolbar
        applyOnTop(UserDefaults.standard.object(forKey: Defaults.keepOnTop) as? Bool ?? true)
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        makeStatusItem()
        engine.onStateChange = { [weak self] in self?.stateChanged() }
        window.orderFrontRegardless()
        Task { await startRecording() }
    }

    private static func makeWindow() -> NSPanel {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel]
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: initialSize), styleMask: style, backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        window.title = "LectureScribe"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }

    private static func glass(around content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.tintColor = .windowBackgroundColor.withAlphaComponent(Metrics.glassTint)
        glass.contentView = content
        return glass
    }

    func startRecording() async {
        guard !engine.isRunning else { return }
        do {
            let title = await LectureTitle.currentEventTitle() ?? defaultSessionTitle()
            try await engine.start(kind: engine.selectedKind, title: title, locale: engine.locale)
            UserDefaults.standard.setValue(engine.selectedKind.storageKey, forKey: Defaults.lastSource)
        } catch {
            Log.engine("start failed: \(error.localizedDescription)")
            engine.post(error.localizedDescription)
        }
    }

    private func showWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func applyOnTop(_ onTop: Bool) {
        window.level = onTop ? .floating : .normal
        window.collectionBehavior = WindowPlacement.behavior(onTop: onTop)
        UserDefaults.standard.setValue(onTop, forKey: Defaults.keepOnTop)
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LectureScribe")
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        statusItem = item
    }

    private func stateChanged() {
        updateStatusItem()
        transport.refresh()
    }

    private func updateStatusItem() {
        let tints: [TranscriptionEngine.State: NSColor] = [.recording: .systemRed, .paused: .systemOrange]
        statusItem?.button?.contentTintColor = tints[engine.state]
        statusItem?.button?.toolTip = "LectureScribe — \(engine.state.rawValue)"
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        guard event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true else { return toggleWindow() }
        let entries = StatusMenu.entries(state: engine.state, windowVisible: isWindowShown, onTop: window.level == .floating)
        statusItem?.menu = StatusMenu.build(entries, target: self)
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    private var isWindowShown: Bool {
        window.isVisible && !window.isMiniaturized
    }

    @objc func recordOrStop() {
        Task { engine.isRunning ? await engine.stop() : await startRecording() }
    }

    @objc func pauseOrResume() {
        Task { engine.state == .paused ? await engine.resume() : await engine.pause() }
    }

    @objc func toggleWindow() {
        isWindowShown ? window.orderOut(nil) : showWindow()
    }

    @objc func toggleOnTop() {
        applyOnTop(window.level != .floating)
    }

    @objc func showMicModes() {
        MicrophoneModes.showPicker()
    }

    @objc func revealFolder() {
        revealTranscript(engine.rawPath)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
