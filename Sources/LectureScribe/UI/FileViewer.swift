import AppKit
import Foundation

struct MergedLine: Equatable {
    let t: Double
    let text: String
    let polished: Bool
}

func mergeTranscript(raw: String, corrected: String) -> [MergedLine] {
    let decoder = JSONDecoder()
    let decode = { (text: String) in
        text.split(whereSeparator: \.isNewline).compactMap { try? decoder.decode(JSONLine.self, from: Data($0.utf8)) }
    }
    let fixes = Dictionary(decode(corrected).map { (segmentKey($0.t), $0.text) }, uniquingKeysWith: { _, last in last })
    return decode(raw).map { entry in
        let fix = fixes[segmentKey(entry.t)]
        return MergedLine(t: entry.t, text: fix ?? entry.text, polished: fix != nil)
    }
}

@MainActor
func runFileViewer(float: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let viewer = FileViewer(float: float)
    app.delegate = viewer
    viewer.show()
    withExtendedLifetime(viewer) { app.run() }
}

@MainActor
final class FileViewer: NSObject, NSApplicationDelegate {
    static let refreshInterval = Duration.milliseconds(500)
    static let liveSeconds = 6.0
    static let bottomSlack = 20.0
    static let fontSize = 12.0
    static let initialSize = NSSize(width: 460, height: 300)

    private let window: NSWindow
    private let textView: NSTextView
    private var lastStamp: [String] = []
    private var poll: Task<Void, Never>?

    init(float: Bool) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        textView = NSTextView(frame: .zero)
        super.init()
        window.title = "LectureScribe"
        if float { window.level = .floating }
        window.contentView = makeScrollView()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func show() {
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                self?.refresh()
            }
        }
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: window.contentLayoutRect)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        textView.frame = scrollView.bounds
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.font = .monospacedSystemFont(ofSize: Self.fontSize, weight: .regular)
        scrollView.documentView = textView
        return scrollView
    }

    private func refresh() {
        guard let dir = Self.latestSession() else {
            return setPlaceholder("No session yet.\n\nStart one with the HUD, or in a terminal:\n  lecturescribe record --source system")
        }
        let files = SessionFiles(dir: dir)
        let stamp = [dir.path, Self.stamp(files.rawJL), Self.stamp(files.correctedJL)]
        guard stamp != lastStamp else { return }
        lastStamp = stamp
        let raw = (try? String(contentsOf: files.rawJL, encoding: .utf8)) ?? ""
        let corrected = (try? String(contentsOf: files.correctedJL, encoding: .utf8)) ?? ""
        render(mergeTranscript(raw: raw, corrected: corrected))
        updateTitle(dir: dir, rawFile: files.rawJL)
    }

    private static func latestSession() -> URL? {
        let latest = transcriptsRoot.appendingPathComponent("latest").path
        return (try? FileManager.default.destinationOfSymbolicLink(atPath: latest)).map { URL(fileURLWithPath: $0) }
    }

    private static func stamp(_ url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return "\(attributes?[.size] ?? 0)|\(attributes?[.modificationDate] ?? "")"
    }

    private func setPlaceholder(_ text: String) {
        lastStamp = []
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes(.secondaryLabelColor)))
    }

    private func render(_ lines: [MergedLine]) {
        let out = NSMutableAttributedString()
        for line in lines {
            out.append(NSAttributedString(string: "[\(hhmmss(line.t))] ", attributes: attributes(.tertiaryLabelColor)))
            out.append(NSAttributedString(string: line.text + "\n", attributes: attributes(line.polished ? .labelColor : .secondaryLabelColor)))
        }
        guard out.length > 0 else { return setPlaceholder("Listening…") }
        let follow = isNearBottom
        textView.textStorage?.setAttributedString(out)
        if follow { textView.scrollToEndOfDocument(nil) }
    }

    private var isNearBottom: Bool {
        guard let scrollView = textView.enclosingScrollView else { return true }
        return scrollView.contentView.bounds.maxY >= textView.frame.height - Self.bottomSlack
    }

    private func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: textView.font ?? NSFont.systemFont(ofSize: Self.fontSize), .foregroundColor: color]
    }

    private func updateTitle(dir: URL, rawFile: URL) {
        let modified = (try? FileManager.default.attributesOfItem(atPath: rawFile.path)[.modificationDate]) as? Date
        let live = modified.map { Date().timeIntervalSince($0) < Self.liveSeconds } ?? false
        window.title = "LectureScribe — \(dir.lastPathComponent)\(live ? "  ● live" : "")"
    }
}
