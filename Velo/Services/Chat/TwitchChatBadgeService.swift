import Foundation

@MainActor
final class TwitchChatBadgeService {
    private let httpClient: HTTPClient
    private var globalBadges: [BadgeKey: RenderableChatBadge]?
    private var channelBadgesByBroadcasterID: [String: [BadgeKey: RenderableChatBadge]] = [:]

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func prepare(channelID: String, credentials: TwitchCredentials) async {
        async let global: Void = loadGlobalBadges(credentials: credentials)
        async let channel: Void = loadChannelBadges(channelID: channelID, credentials: credentials)
        _ = await (global, channel)
    }

    func renderableBadges(
        for badges: [ChatBadge],
        channelID: String,
        credentials: TwitchCredentials
    ) async -> [RenderableChatBadge] {
        guard !badges.isEmpty else { return [] }

        if globalBadges == nil || channelBadgesByBroadcasterID[channelID] == nil {
            await prepare(channelID: channelID, credentials: credentials)
        }

        let channelBadges = channelBadgesByBroadcasterID[channelID] ?? [:]
        let globalBadges = globalBadges ?? [:]

        return badges.compactMap { badge in
            let key = BadgeKey(name: badge.name, version: badge.version)
            return channelBadges[key] ?? globalBadges[key]
        }
    }

    private func loadGlobalBadges(credentials: TwitchCredentials) async {
        guard globalBadges == nil else { return }

        do {
            globalBadges = try await fetchBadges(
                url: URL(string: "https://api.twitch.tv/helix/chat/badges/global"),
                credentials: credentials
            )
        } catch {
            globalBadges = [:]
        }
    }

    private func loadChannelBadges(channelID: String, credentials: TwitchCredentials) async {
        guard channelBadgesByBroadcasterID[channelID] == nil else { return }

        var components = URLComponents(string: "https://api.twitch.tv/helix/chat/badges")
        components?.queryItems = [
            URLQueryItem(name: "broadcaster_id", value: channelID)
        ]

        do {
            channelBadgesByBroadcasterID[channelID] = try await fetchBadges(
                url: components?.url,
                credentials: credentials
            )
        } catch {
            channelBadgesByBroadcasterID[channelID] = [:]
        }
    }

    private func fetchBadges(
        url: URL?,
        credentials: TwitchCredentials
    ) async throws -> [BadgeKey: RenderableChatBadge] {
        guard let url else { throw APIError.invalidURL }

        let payload = try await httpClient.fetchDecodable(
            TwitchBadgeEnvelope.self,
            from: url,
            headers: [
                "Client-ID": credentials.clientID,
                "Authorization": "Bearer \(credentials.oauthToken)"
            ]
        )

        var output: [BadgeKey: RenderableChatBadge] = [:]

        for set in payload.data {
            for version in set.versions {
                guard let imageURL = URL(string: version.imageURL4x ?? version.imageURL2x ?? version.imageURL1x) else {
                    continue
                }

                let key = BadgeKey(name: set.setID, version: version.id)
                output[key] = RenderableChatBadge(
                    name: set.setID,
                    version: version.id,
                    title: version.title,
                    imageURL: imageURL
                )
            }
        }

        return output
    }
}

private struct BadgeKey: Hashable, Sendable {
    let name: String
    let version: String
}

private struct TwitchBadgeEnvelope: Decodable {
    let data: [TwitchBadgeSetPayload]
}

private struct TwitchBadgeSetPayload: Decodable {
    let setID: String
    let versions: [TwitchBadgeVersionPayload]

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case versions
    }
}

private struct TwitchBadgeVersionPayload: Decodable {
    let id: String
    let imageURL1x: String
    let imageURL2x: String?
    let imageURL4x: String?
    let title: String

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL1x = "image_url_1x"
        case imageURL2x = "image_url_2x"
        case imageURL4x = "image_url_4x"
        case title
    }
}
