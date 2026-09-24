import Observation
import SwiftUI

@Observable
@MainActor
final class FeedPlayer {
    @ObservationIgnored var maxHistory = Metrics.maxHistoryRows
    @ObservationIgnored private var lastSeenID = 0
    @ObservationIgnored private var latestID: Int?
    @ObservationIgnored private var seeded = false
    @ObservationIgnored private var holding = false
    private(set) var history: [TranscriptLine] = []
    private(set) var active: TranscriptLine?
    private(set) var revealed = 0
    private(set) var pending: [TranscriptLine] = []
    private(set) var settled = true
    private(set) var paused = false
    var isEmpty: Bool { history.isEmpty && active == nil }

    func setPaused(_ value: Bool) {
        paused = value
        guard !value, holding else { return }
        holding = false
        advance()
    }

    func sync(_ lines: [TranscriptLine]) {
        guard let last = lines.last, last.id >= lastSeenID else { return reset(then: lines) }
        guard seeded else { return seed(lines) }
        pending.append(contentsOf: lines.filter { $0.id > lastSeenID })
        (lastSeenID, latestID) = (last.id, last.id)
        if active == nil || settled { advance() }
    }

    func step(wordCount: Int) {
        guard !paused, !settled else { return }
        guard revealed >= wordCount else { return revealed += 1 }
        settled = true
        advance()
    }

    private func advance() {
        guard !paused else { return holding = true }
        if let done = active, done.id != latestID { archive(done) }
        guard pending.isEmpty else { return play(pending.removeFirst()) }
        settled = true
    }

    private func play(_ line: TranscriptLine) {
        active = line
        revealed = 0
        settled = false
    }

    private func archive(_ line: TranscriptLine) {
        history.append(line)
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
    }

    private func seed(_ lines: [TranscriptLine]) {
        seeded = true
        history = Array(lines.dropLast().suffix(maxHistory))
        active = lines.last
        revealed = Int.max
        settled = true
        (lastSeenID, latestID) = (lines.last?.id ?? 0, lines.last?.id)
    }

    private func reset(then lines: [TranscriptLine]) {
        (history, pending, active, revealed, settled) = ([], [], nil, 0, true)
        (seeded, lastSeenID, latestID) = (lines.isEmpty, 0, nil)
        if !lines.isEmpty { seed(lines) }
    }
}

struct FeedRows: View {
    let player: FeedPlayer
    let text: (TranscriptLine) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            ForEach(rows) { line in
                LineText(text: text(line), raw: line.text, revealed: line.id == player.active?.id ? player.revealed : Int.max, current: line.id == player.active?.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: Metrics.riseOffset)), removal: .opacity))
            }
            if player.isEmpty {
                Text("Listening…").font(Metrics.bodyFont).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: Metrics.rowAnimation), value: rows.map(\.id))
    }

    private var rows: [TranscriptLine] {
        player.history + (player.active.map { [$0] } ?? [])
    }
}

struct LineText: View {
    static let correctionUnderline = Text.LineStyle(pattern: .dash, color: .blue)

    let text: String
    var raw: String?
    let revealed: Int
    let current: Bool

    var body: some View {
        Text(Self.attributed(text, revealed: revealed, corrected: WordDiff.changedWords(raw: raw ?? text, corrected: text)))
            .font(Metrics.bodyFont)
            .foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.interpolate)
            .animation(.smooth(duration: Metrics.wordAnimation), value: revealed)
            .animation(.smooth(duration: Metrics.rowAnimation), value: current)
    }

    static func attributed(_ text: String, revealed: Int, corrected: Set<Int> = []) -> AttributedString {
        var out = AttributedString()
        for (index, word) in text.split(whereSeparator: \.isWhitespace).enumerated() {
            if index > 0 { out.append(AttributedString(" ")) }
            out.append(styled(String(word), hidden: index >= max(revealed, 1), corrected: corrected.contains(index)))
        }
        return out
    }

    private static func styled(_ word: String, hidden: Bool, corrected: Bool) -> AttributedString {
        var piece = AttributedString(word)
        if hidden { piece.foregroundColor = .clear }
        if corrected && !hidden { piece.underlineStyle = correctionUnderline }
        return piece
    }
}
