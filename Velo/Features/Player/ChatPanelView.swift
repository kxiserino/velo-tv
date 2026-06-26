import SwiftUI
import Combine
import UIKit

struct ChatPanelView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var settings: AppSettings
    @State private var scrollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let pinnedMessage = viewModel.pinnedMessage {
                PinnedChatMessageView(
                    message: pinnedMessage,
                    compact: settings.compactChat
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: settings.compactChat ? 6 : 10) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageRow(message: message, settings: settings)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.messages.last?.id) { _, _ in
                    scheduleScroll(with: proxy)
                }
                .onDisappear {
                    scrollTask?.cancel()
                    scrollTask = nil
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.pinnedMessage?.id)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("Chat")
                .font(.title3.weight(.semibold))

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 8, height: 8)

                Text(viewModel.connectionState.displayLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .idle:
            return .secondary
        case .connecting:
            return .yellow
        case .live:
            return .green
        case .failed:
            return .orange
        }
    }

    private func scheduleScroll(with proxy: ScrollViewProxy) {
        guard let lastID = viewModel.messages.last?.id else { return }

        scrollTask?.cancel()
        scrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct PinnedChatMessageView: View {
    let message: RenderablePinnedChatMessage
    let compact: Bool

    private var accentColor: Color {
        if let hex = message.accentHex, let color = Color(hex: hex) {
            return color
        }
        return Color(hex: "#9146FF") ?? .purple
    }

    private var senderColor: Color {
        if let hex = message.colorHex, let color = Color(hex: hex) {
            return color
        }
        return .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            HStack(spacing: 7) {
                Image(systemName: "pin.fill")
                    .font(.callout.weight(.bold))

                Text("Pinned")
                    .font(.callout.weight(.bold))

                Spacer(minLength: 8)

                Text(message.timestamp, style: .time)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                Text(message.senderDisplayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(senderColor)
                    .lineLimit(1)

                ChatSegmentsView(
                    segments: message.segments,
                    font: compact ? .callout : .body,
                    emoteHeight: compact ? 24 : 28,
                    tokenSpacing: compact ? 6 : 8,
                    lineSpacing: compact ? 5 : 7
                )
            }
        }
        .padding(.vertical, compact ? 10 : 12)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)
                .clipShape(.rect(cornerRadius: 2))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChatMessageRow: View {
    let message: RenderableChatMessage
    @ObservedObject var settings: AppSettings

    private var senderColor: Color {
        if let hex = message.colorHex, let color = Color(hex: hex) {
            return color
        }
        return .primary
    }

    var body: some View {
        ChatTokenWrapLayout(
            spacing: settings.compactChat ? 7 : 9,
            lineSpacing: settings.compactChat ? 6 : 8
        ) {
            ForEach(message.badges.prefix(4)) { badge in
                ChatBadgeImageView(
                    badge: badge,
                    side: settings.compactChat ? 18 : 20
                )
            }

            Text("\(message.senderDisplayName):")
                .font(.callout.weight(.semibold))
                .foregroundStyle(senderColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)

            ForEach(Array(ChatSegmentsView.normalized(message.segments).enumerated()), id: \.offset) { _, token in
                ChatSegmentTokenView(
                    token: token,
                    font: settings.compactChat ? .callout : .body,
                    emoteHeight: settings.compactChat ? 25 : 30
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, settings.compactChat ? 2 : 4)
    }
}

private struct ChatBadgeImageView: View {
    let badge: RenderableChatBadge
    let side: CGFloat
    @StateObject private var loader: EmoteImageLoader

    init(badge: RenderableChatBadge, side: CGFloat) {
        self.badge = badge
        self.side = side
        _loader = StateObject(wrappedValue: EmoteImageLoader(url: badge.imageURL))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .fixedSize()
        .onAppear {
            loader.loadIfNeeded()
        }
        .accessibilityLabel(badge.title)
    }
}

private enum ChatRenderableToken {
    case text(String)
    case emote(ChatEmote, overlays: [ChatEmote])
}

private struct ChatSegmentsView: View {
    let segments: [ChatSegment]
    let font: Font
    let emoteHeight: CGFloat
    let tokenSpacing: CGFloat
    let lineSpacing: CGFloat

    var body: some View {
        ChatTokenWrapLayout(spacing: tokenSpacing, lineSpacing: lineSpacing) {
            ForEach(Array(Self.normalized(segments).enumerated()), id: \.offset) { _, token in
                ChatSegmentTokenView(
                    token: token,
                    font: font,
                    emoteHeight: emoteHeight
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func normalized(_ segments: [ChatSegment]) -> [ChatRenderableToken] {
        var tokens: [ChatRenderableToken] = []

        for segment in segments {
            switch segment {
            case .emote(let emote):
                if emote.isZeroWidth,
                   let lastToken = tokens.last,
                   case .emote(let base, let overlays) = lastToken {
                    tokens[tokens.count - 1] = .emote(base, overlays: overlays + [emote])
                } else {
                    tokens.append(.emote(emote, overlays: []))
                }
            case .text(let text):
                tokens.append(contentsOf: text
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .map { .text($0) })
            }
        }

        return tokens
    }
}

private struct ChatSegmentTokenView: View {
    let token: ChatRenderableToken
    let font: Font
    let emoteHeight: CGFloat

    var body: some View {
        switch token {
        case .text(let text):
            Text(text)
                .font(font)
                .fixedSize(horizontal: true, vertical: true)
        case .emote(let emote, let overlays):
            EmoteStackView(
                emote: emote,
                overlays: overlays,
                height: emoteHeight
            )
        }
    }
}

private struct EmoteStackView: View {
    let emote: ChatEmote
    let overlays: [ChatEmote]
    let height: CGFloat

    var body: some View {
        EmoteImageView(emote: emote, height: height)
            .overlay {
                ForEach(overlays, id: \.id) { overlay in
                    EmoteImageView(
                        emote: overlay,
                        height: height,
                        reservesSpace: false,
                        showsPlaceholder: false
                    )
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        ([emote.name] + overlays.map(\.name)).joined(separator: " ")
    }
}

private struct EmoteImageView: View {
    let emote: ChatEmote
    let height: CGFloat
    let reservesSpace: Bool
    let showsPlaceholder: Bool
    @StateObject private var loader: EmoteImageLoader

    init(
        emote: ChatEmote,
        height: CGFloat,
        reservesSpace: Bool = true,
        showsPlaceholder: Bool = true
    ) {
        self.emote = emote
        self.height = height
        self.reservesSpace = reservesSpace
        self.showsPlaceholder = showsPlaceholder
        _loader = StateObject(wrappedValue: EmoteImageLoader(url: emote.imageURL))
    }

    var body: some View {
        let imageSize = loader.image?.size ?? CGSize(width: height, height: height)
        let aspectRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        let displayWidth = height * min(max(aspectRatio, 1), 2.8)

        Group {
            if let image = loader.image {
                AnimatedUIImageView(image: image)
            } else if showsPlaceholder {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            } else {
                Color.clear
            }
        }
        .frame(width: displayWidth, height: height)
        .padding(.horizontal, reservesSpace ? 4 : 0)
        .padding(.vertical, reservesSpace ? 2 : 0)
        .frame(
            width: displayWidth + (reservesSpace ? 8 : 0),
            height: height + (reservesSpace ? 4 : 0)
        )
        .onAppear {
            loader.loadIfNeeded()
        }
    }
}

@MainActor
private final class EmoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private let url: URL
    private var loadTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    deinit {
        loadTask?.cancel()
    }

    func loadIfNeeded() {
        guard image == nil else { return }
        guard loadTask == nil else { return }

        loadTask = Task {
            let loaded = await EmoteImagePipeline.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
            loadTask = nil
        }
    }
}

private struct AnimatedUIImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if imageView.image !== image {
            imageView.stopAnimating()
            imageView.image = image
        }

        if image.images != nil {
            imageView.startAnimating()
        } else {
            imageView.stopAnimating()
        }
    }
}

private struct ChatTokenWrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat = 4, lineSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 640

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            let requiredWidth = x == 0 ? size.width : x + spacing + size.width
            if x > 0, requiredWidth > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            x = x == 0 ? size.width : x + spacing + size.width
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var line: [(index: Subviews.Index, size: CGSize, x: CGFloat)] = []
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        func flushLine(advance: Bool) {
            for item in line {
                let centeredY = y + max(0, (lineHeight - item.size.height) / 2)
                subviews[item.index].place(
                    at: CGPoint(x: item.x, y: centeredY),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }

            line.removeAll(keepingCapacity: true)
            x = bounds.minX

            if advance {
                y += lineHeight + lineSpacing
            }

            lineHeight = 0
        }

        for index in subviews.indices {
            let subview = subviews[index]
            let size = subview.sizeThatFits(.unspecified)
            let originX = line.isEmpty ? bounds.minX : x + spacing
            let nextX = originX + size.width

            if !line.isEmpty, nextX > bounds.maxX {
                flushLine(advance: true)
            }

            let placedX = line.isEmpty ? bounds.minX : x + spacing
            line.append((index: index, size: size, x: placedX))
            x = placedX + size.width
            lineHeight = max(lineHeight, size.height)
        }

        flushLine(advance: false)
    }
}
