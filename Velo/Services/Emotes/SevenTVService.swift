import Foundation

struct SevenTVService: EmoteProvider {
    private static let maxCatalogBytes = 8 * 1_024 * 1_024
    fileprivate static let allowedImageHosts: Set<String> = ["cdn.7tv.app"]

    private let httpClient: HTTPClient

    nonisolated let kind: EmoteProviderKind = .sevenTV

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchGlobalEmotes() async throws -> [ChatEmote] {
        guard let url = URL(string: "https://7tv.io/v3/emote-sets/global") else {
            throw APIError.invalidURL
        }

        let payload: SevenTVEmoteSetPayload = try await httpClient.fetchDecodable(
            SevenTVEmoteSetPayload.self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return payload.emotes.compactMap { $0.asChatEmote }
    }

    func fetchChannelEmotes(twitchUserID: String) async throws -> [ChatEmote] {
        guard let url = URL(string: "https://7tv.io/v3/users/twitch/\(twitchUserID)") else {
            throw APIError.invalidURL
        }

        let payload: SevenTVUserPayload = try await httpClient.fetchDecodable(
            SevenTVUserPayload.self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return payload.emoteSet?.emotes.compactMap { $0.asChatEmote } ?? []
    }
}

private struct SevenTVUserPayload: Decodable {
    let emoteSet: SevenTVEmoteSetPayload?

    enum CodingKeys: String, CodingKey {
        case emoteSet = "emote_set"
    }
}

private struct SevenTVEmoteSetPayload: Decodable {
    let emotes: [SevenTVEmotePayload]
}

private struct SevenTVEmotePayload: Decodable {
    let id: String
    let name: String
    let data: SevenTVEmoteDataPayload

    var asChatEmote: ChatEmote? {
        guard let url = data.host.bestURL(allowedHosts: SevenTVService.allowedImageHosts) else { return nil }

        return ChatEmote(
            id: id,
            name: name,
            provider: .sevenTV,
            imageURL: url,
            isZeroWidth: data.isZeroWidth
        )
    }
}

private struct SevenTVEmoteDataPayload: Decodable {
    private static let zeroWidthFlag = 1 << 8

    let flags: Int?
    let host: SevenTVHostPayload

    var isZeroWidth: Bool {
        ((flags ?? 0) & Self.zeroWidthFlag) != 0
    }
}

private struct SevenTVHostPayload: Decodable {
    let url: String
    let files: [SevenTVFilePayload]

    func bestURL(allowedHosts: Set<String>) -> URL? {
        guard let bestFile = preferredFile else {
            return nil
        }

        return EmoteURLPolicy.providerImageURL(
            base: url,
            pathComponent: bestFile.name,
            allowedHosts: allowedHosts
        )
    }

    private var preferredFile: SevenTVFilePayload? {
        let targetWidth = 64

        let animated = files.filter { ($0.frameCount ?? 1) > 1 }
        let still = files.filter { ($0.frameCount ?? 1) <= 1 }

        return pickBest(from: animated, targetWidth: targetWidth) ??
            pickBest(from: still, targetWidth: targetWidth)
    }

    private func pickBest(from files: [SevenTVFilePayload], targetWidth: Int) -> SevenTVFilePayload? {
        let candidates = files.filter { $0.width != nil }
        guard !candidates.isEmpty else { return nil }

        return candidates.sorted { lhs, rhs in
            let lhsRank = lhs.formatRank
            let rhsRank = rhs.formatRank
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            let lhsDistance = abs((lhs.width ?? targetWidth) - targetWidth)
            let rhsDistance = abs((rhs.width ?? targetWidth) - targetWidth)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            return (lhs.width ?? 0) < (rhs.width ?? 0)
        }
        .first
    }
}

private struct SevenTVFilePayload: Decodable {
    let name: String
    let staticName: String?
    let width: Int?
    let frameCount: Int?
    let format: String?

    enum CodingKeys: String, CodingKey {
        case name
        case staticName = "static_name"
        case width
        case frameCount = "frame_count"
        case format
    }

    var formatRank: Int {
        switch (format ?? "").uppercased() {
        case "GIF":
            return 0
        case "WEBP":
            return 1
        case "AVIF":
            return 2
        default:
            return 3
        }
    }
}
