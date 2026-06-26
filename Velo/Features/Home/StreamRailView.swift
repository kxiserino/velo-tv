import SwiftUI

struct StreamRailView: View {
    let streams: [LiveStream]
    @ObservedObject var libraryStore: LibraryStore
    let focusScope: Namespace.ID
    var horizontalPadding: CGFloat = VeloUI.screenHorizontalPadding
    var defaultFocusOnFirstItem = false
    var footerOverride: (LiveStream) -> String? = { _ in nil }
    let onOpenStream: (LiveStream) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 28) {
                ForEach(Array(streams.enumerated()), id: \.element.id) { index, stream in
                    Button {
                        onOpenStream(stream)
                    } label: {
                        StreamCardView(
                            stream: stream,
                            isFavorite: libraryStore.isFavorite(channelID: stream.channelID),
                            footerOverride: footerOverride(stream)
                        )
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .prefersDefaultFocus(defaultFocusOnFirstItem && index == 0, in: focusScope)
                    .accessibilityLabel("\(stream.channelName), \(stream.title)")
                    .accessibilityHint("Opens the live stream")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, horizontalPadding)
            .focusSection()
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }
}
