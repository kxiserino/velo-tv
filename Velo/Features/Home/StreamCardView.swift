import SwiftUI

struct StreamCardView: View {
    let stream: LiveStream
    let isFavorite: Bool
    let footerOverride: String?
    @Environment(\.isFocused) private var isFocused

    init(stream: LiveStream, isFavorite: Bool = false, footerOverride: String? = nil) {
        self.stream = stream
        self.isFavorite = isFavorite
        self.footerOverride = footerOverride
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: stream.thumbnailURL(width: 640, height: 360)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .frame(width: VeloUI.streamCardWidth, height: VeloUI.streamCardHeight)
                .clipShape(RoundedRectangle(cornerRadius: VeloUI.cardRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)

                            Text("Live")
                                .font(.callout.weight(.bold))
                                .foregroundStyle(Color.white)
                        }

                        if let viewerCount = stream.viewerCount {
                            Text("\(viewerCount.formatted()) watching")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: VeloUI.streamBadgeHeight)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    }
                    .padding(VeloUI.cardRadius)
                    .compositingGroup()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: VeloUI.cardRadius, style: .continuous)
                        .strokeBorder(.white.opacity(isFocused ? 0.62 : 0.10), lineWidth: isFocused ? 3 : 1)
                }

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(10)
                        .background(.black.opacity(0.58), in: Circle())
                        .padding(14)
                }
            }

            Text(stream.channelName)
                .font(.title3.weight(.bold))
                .foregroundStyle(channelNameColor)
                .lineLimit(1)

            Text(stream.title)
                .font(.callout)
                .foregroundStyle(streamTitleColor)
                .lineLimit(2)

            HStack(spacing: 10) {
                if let footerOverride {
                    Text(footerOverride)
                        .foregroundStyle(metadataColor)
                } else {
                    if let viewerCount = stream.viewerCount {
                        Text("\(viewerCount.formatted()) watching")
                            .foregroundStyle(metadataColor)
                    }

                    if !stream.gameName.isEmpty {
                        Text(stream.gameName)
                            .foregroundStyle(metadataColor)
                    }
                }
            }
            .font(.callout)
        }
        .frame(width: VeloUI.streamCardWidth, alignment: .leading)
        .padding(.vertical, 8)
        .focusEffectDisabled()
        .scaleEffect(isFocused ? 1.018 : 1)
        .shadow(color: isFocused ? .black.opacity(0.40) : .clear, radius: 18, y: 10)
        .animation(VeloUI.focusAnimation, value: isFocused)
        .accessibilityElement(children: .combine)
    }

    private var streamTitleColor: Color {
        isFocused ? Color.black.opacity(0.86) : Color.white.opacity(0.72)
    }

    private var metadataColor: Color {
        isFocused ? Color.black.opacity(0.66) : Color.white.opacity(0.62)
    }

    private var channelNameColor: Color {
        isFocused ? Color.black.opacity(0.94) : Color.white
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: VeloUI.cardRadius, style: .continuous)
                .fill(.quaternary)
            Image(systemName: "video")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
