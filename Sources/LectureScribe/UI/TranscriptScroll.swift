import SwiftUI

struct TranscriptScroll: View {
    static let liveThresholdLines = 3.0
    static let lineHeight = 20.0

    let player: FeedPlayer
    let text: (TranscriptLine) -> String
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var following = true

    var body: some View {
        ScrollView {
            FeedRows(player: player, text: text)
                .frame(minHeight: Metrics.transcriptHeight, alignment: .bottomLeading)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self, of: Self.isAtBottom) { _, atBottom in following = atBottom }
        .onChange(of: player.active?.id) { followIfLive() }
        .onChange(of: player.revealed) { followIfLive() }
        .mask { topFade }
        .overlay(alignment: .bottomTrailing) { liveButton }
    }

    private var topFade: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Metrics.toolbarInset)
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Metrics.fadeHeight)
            Color.black
        }
        .ignoresSafeArea()
    }

    static func isAtBottom(_ geometry: ScrollGeometry) -> Bool {
        isNearBottom(distance: geometry.contentSize.height - geometry.visibleRect.maxY)
    }

    static func isNearBottom(distance: Double) -> Bool {
        distance < liveThresholdLines * lineHeight
    }

    private func followIfLive() {
        guard following else { return }
        position.scrollTo(edge: .bottom)
    }

    @ViewBuilder private var liveButton: some View {
        if !following {
            Button { jumpToLive() } label: {
                Label("Live", systemImage: "arrow.down").font(.caption.weight(.semibold))
            }
            .buttonStyle(.glass)
            .transition(.opacity)
            .help("Jump back to the newest line")
        }
    }

    private func jumpToLive() {
        following = true
        withAnimation(.smooth(duration: Metrics.rowAnimation)) { position.scrollTo(edge: .bottom) }
    }
}
