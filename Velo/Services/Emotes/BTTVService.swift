import Foundation

struct BTTVService: EmoteProvider {
    private static let maxCatalogBytes = 1_024 * 1_024

    private let httpClient: HTTPClient

    nonisolated let kind: EmoteProviderKind = .bttv

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchGlobalEmotes() async throws -> [ChatEmote] {
        guard let url = URL(string: "https://api.betterttv.net/3/cached/emotes/global") else {
            throw APIError.invalidURL
        }

        let payload: [BTTVEmotePayload] = try await httpClient.fetchDecodable(
            [BTTVEmotePayload].self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return payload.compactMap(\.asChatEmote)
    }

    func fetchChannelEmotes(twitchUserID: String) async throws -> [ChatEmote] {
        guard let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(twitchUserID)") else {
            throw APIError.invalidURL
        }

        let payload: BTTVUserPayload = try await httpClient.fetchDecodable(
            BTTVUserPayload.self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return (payload.channelEmotes + payload.sharedEmotes).compactMap(\.asChatEmote)
    }
}

private struct BTTVUserPayload: Decodable {
    let channelEmotes: [BTTVEmotePayload]
    let sharedEmotes: [BTTVEmotePayload]

    enum CodingKeys: String, CodingKey {
        case channelEmotes = "channelEmotes"
        case sharedEmotes = "sharedEmotes"
    }
}

private struct BTTVEmotePayload: Decodable {
    let id: String
    let code: String

    var asChatEmote: ChatEmote? {
        guard let imageURL = URL(string: "https://cdn.betterttv.net/emote/\(id)/2x") else {
            return nil
        }

        return ChatEmote(
            id: "bttv-\(id)",
            name: code,
            provider: .bttv,
            imageURL: imageURL
        )
    }
}
