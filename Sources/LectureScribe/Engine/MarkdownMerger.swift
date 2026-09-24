struct MarkdownMerger {
    var config = MergeConfig.standard
    private var pendingText = ""
    private var pendingStart: Double?
    private var lastT = -Double.infinity

    mutating func add(t: Double, text: String, emit: (String) -> Void) {
        if pendingStart != nil, t - lastT < config.gapSeconds {
            pendingText += " " + text
        } else {
            flush(emit)
            pendingStart = t
            pendingText = text
        }
        lastT = t
    }

    mutating func flush(_ emit: (String) -> Void) {
        guard let start = pendingStart, !pendingText.isEmpty else { return }
        emit("[\(hhmmss(start))] \(pendingText)\n")
        pendingText = ""
        pendingStart = nil
    }
}
