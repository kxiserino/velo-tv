import Foundation

struct FFZService: EmoteProvider {
    private static let maxCatalogBytes = 1_024 * 1_024
    fileprivate static let allowedImageHosts: Set<String> = ["cdn.frankerfacez.com"]

    private let httpClient: HTTPClient

    nonisolated let kind: EmoteProviderKind = .ffz

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchGlobalEmotes() async throws -> [ChatEmote] {
        guard let url = URL(string: "https://api.frankerfacez.com/v1/set/global") else {
            throw APIError.invalidURL
        }

        let payload: FFZPayload = try await httpClient.fetchDecodable(
            FFZPayload.self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return payload.allEmotes
    }

    func fetchChannelEmotes(twitchUserID: String) async throws -> [ChatEmote] {
        guard let url = URL(string: "https://api.frankerfacez.com/v1/room/id/\(twitchUserID)") else {
            throw APIError.invalidURL
        }

        let payload: FFZPayload = try await httpClient.fetchDecodable(
            FFZPayload.self,
            from: url,
            maxBodyBytes: Self.maxCatalogBytes
        )
        return payload.allEmotes
    }
}

private struct FFZPayload: Decodable {
    let sets: [String: FFZSetPayload]

    var allEmotes: [ChatEmote] {
        sets.values.flatMap { set in
            set.emoticons.compactMap { emote in
                guard let imageURL = emote.bestURL(allowedHosts: FFZService.allowedImageHosts) else { return nil }
                return ChatEmote(
                    id: "ffz-\(emote.id)",
                    name: emote.name,
                    provider: .ffz,
                    imageURL: imageURL
                )
            }
        }
    }
}

private struct FFZSetPayload: Decodable {
    let emoticons: [FFZEmotePayload]
}

private struct FFZEmotePayload: Decodable {
    let id: Int
    let name: String
    let urls: [String: String]

    func bestURL(allowedHosts: Set<String>) -> URL? {
        let preferredKeys = ["2", "1", "3", "4"]
        let preferredValue = preferredKeys.compactMap { urls[$0] }.first

        let value: String?
        if let preferredValue {
            value = preferredValue
        } else {
            value = urls
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .first?
                .value
        }
        guard let value else {
            return nil
        }

        return EmoteURLPolicy.providerImageURL(from: value, allowedHosts: allowedHosts)
    }
}
