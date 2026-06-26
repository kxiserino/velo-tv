import Foundation

struct SevenTVService: EmoteProvider {
    private static let maxCatalogBytes = 8 * 1_024 * 1_024
    fileprivate static let allowedImageHosts: Set<String> = ["cdn.7tv.app"]
    fileprivate static let maxAnimatedFrameCount = 80

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
        guard let pathComponent = preferredPathComponent else {
            return nil
        }

        return EmoteURLPolicy.providerImageURL(
            base: url,
            pathComponent: pathComponent,
            allowedHosts: allowedHosts
        )
    }

    private var preferredPathComponent: String? {
        let targetWidth = 64

        let animated = files.filter {
            ($0.frameCount ?? 1) > 1 &&
                ($0.frameCount ?? 1) <= SevenTVService.maxAnimatedFrameCount
        }
        let still = files.filter { ($0.frameCount ?? 1) <= 1 }

        if let animatedFile = pickBestAnimated(from: animated, targetWidth: targetWidth) {
            return animatedFile.name
        }

        if let stillFile = pickBestStill(from: still, targetWidth: targetWidth) {
            return stillFile.name
        }

        return pickBestStaticFallback(targetWidth: targetWidth)
    }

    private func pickBestAnimated(from files: [SevenTVFilePayload], targetWidth: Int) -> SevenTVFilePayload? {
        pickBest(from: files.filter(\.isAnimatedGIF), targetWidth: targetWidth, rank: \.animatedFormatRank)
    }

    private func pickBestStill(from files: [SevenTVFilePayload], targetWidth: Int) -> SevenTVFilePayload? {
        pickBest(from: files, targetWidth: targetWidth, rank: \.stillFormatRank)
    }

    private func pickBestStaticFallback(targetWidth: Int) -> String? {
        let candidates = files.compactMap { file -> StaticEmoteFile? in
            guard let staticName = file.staticName, !staticName.isEmpty else { return nil }
            return StaticEmoteFile(
                name: staticName,
                width: file.width,
                format: Self.format(from: staticName) ?? file.format
            )
        }

        return pickBest(from: candidates, targetWidth: targetWidth, rank: \.formatRank)?.name
    }

    private func pickBest<File: SevenTVFileCandidate>(
        from files: [File],
        targetWidth: Int,
        rank: (File) -> Int
    ) -> File? {
        let candidates = files.filter { $0.width != nil }
        guard !candidates.isEmpty else { return nil }

        return candidates.sorted { lhs, rhs in
            let lhsRank = rank(lhs)
            let rhsRank = rank(rhs)
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

    private static func format(from path: String) -> String? {
        path.split(separator: ".").last.map(String.init)
    }
}

private protocol SevenTVFileCandidate {
    var name: String { get }
    var width: Int? { get }
}

private struct StaticEmoteFile: SevenTVFileCandidate {
    let name: String
    let width: Int?
    let format: String?

    var formatRank: Int {
        SevenTVFilePayload.stillFormatRank(for: format)
    }
}

private struct SevenTVFilePayload: Decodable, SevenTVFileCandidate {
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

    var isAnimatedGIF: Bool {
        (frameCount ?? 1) > 1 && (format ?? "").uppercased() == "GIF"
    }

    var animatedFormatRank: Int {
        switch (format ?? "").uppercased() {
        case "GIF":
            return 0
        default:
            return 1
        }
    }

    var stillFormatRank: Int {
        Self.stillFormatRank(for: format)
    }

    static func stillFormatRank(for format: String?) -> Int {
        switch (format ?? "").uppercased() {
        case "PNG":
            return 0
        case "GIF":
            return 1
        case "WEBP":
            return 2
        case "AVIF":
            return 3
        default:
            return 4
        }
    }
}
