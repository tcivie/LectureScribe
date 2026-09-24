import AppKit
import SwiftUI

enum PanelPlacement {
    static let dragThreshold = 3.0

    static func isDrag(from start: NSPoint, to now: NSPoint) -> Bool {
        abs(now.x - start.x) > dragThreshold || abs(now.y - start.y) > dragThreshold
    }
}

final class HUDHostingView<Content: View>: NSHostingView<Content> {
    private var pendingDrag: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        pendingDrag = event
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = pendingDrag, PanelPlacement.isDrag(from: down.locationInWindow, to: event.locationInWindow) else {
            return super.mouseDragged(with: event)
        }
        pendingDrag = nil
        window?.performDrag(with: down)
    }

    override func mouseUp(with event: NSEvent) {
        pendingDrag = nil
        super.mouseUp(with: event)
    }
}

enum StatusMenu {
    struct Entry: Equatable {
        let title: String
        let action: Selector?
        var checked = false
    }

    static func entries(state: TranscriptionEngine.State, windowVisible: Bool, onTop: Bool) -> [Entry] {
        var entries = [Entry(title: state == .idle ? "Start Recording" : "Stop and Save", action: #selector(AppRunner.recordOrStop))]
        if state != .idle {
            entries.append(Entry(title: state == .paused ? "Resume" : "Pause", action: #selector(AppRunner.pauseOrResume)))
        }
        return entries + [
            Entry(title: "", action: nil),
            Entry(title: windowVisible ? "Hide Window" : "Show Window", action: #selector(AppRunner.toggleWindow)),
            Entry(title: "Keep on Top", action: #selector(AppRunner.toggleOnTop), checked: onTop),
            Entry(title: "Microphone Mode…", action: #selector(AppRunner.showMicModes)),
            Entry(title: "Show Transcripts Folder", action: #selector(AppRunner.revealFolder)),
            Entry(title: "", action: nil),
            Entry(title: "Quit LectureScribe", action: #selector(AppRunner.quit))
        ]
    }

    @MainActor
    static func build(_ entries: [Entry], target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        entries.forEach { menu.addItem(item(for: $0, target: target)) }
        return menu
    }

    @MainActor
    private static func item(for entry: Entry, target: AnyObject) -> NSMenuItem {
        guard let action = entry.action else { return .separator() }
        let item = NSMenuItem(title: entry.title, action: action, keyEquivalent: "")
        item.target = target
        item.state = entry.checked ? .on : .off
        return item
    }
}
