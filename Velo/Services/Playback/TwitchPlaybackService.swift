import Foundation

enum PlaybackAuthorizationMode: Equatable {
    case authenticated
    case anonymousFallback
    case anonymous
}

struct LivePlaybackResponse {
    let url: URL
    let authorizationMode: PlaybackAuthorizationMode
}

struct TwitchPlaybackService {
    private struct GQLRequestBody: Encodable {
        let operationName: String
        let query: String
        let variables: Variables

        struct Variables: Encodable {
            let isLive: Bool
            let login: String
            let isVod: Bool
            let vodID: String
            let playerType: String
        }
    }

    private struct GQLResponse: Decodable {
        let data: PlaybackData?
        let errors: [GQLError]?
    }

    private struct PlaybackData: Decodable {
        let streamPlaybackAccessToken: PlaybackToken?
    }

    private struct PlaybackToken: Decodable {
        let value: String
        let signature: String
    }

    private struct PlaybackTokenEnvelope {
        let clientID: String
        let token: PlaybackToken
    }

    private struct GQLError: Decodable {
        let message: String
    }

    private struct UsherErrorEntry: Decodable {
        let error: String?
        let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorCode = "error_code"
        }
    }

    private enum AuthStyle: String {
        case none
        case bearer
        case oauth

        var label: String {
            switch self {
            case .none: return "none"
            case .bearer: return "bearer"
            case .oauth: return "oauth"
            }
        }

        var authorizationStyle: TwitchAuthorizationStyle? {
            switch self {
            case .none:
                return nil
            case .bearer:
                return .bearer
            case .oauth:
                return .oauth
            }
        }
    }

    private let session: URLSession
    private let clientPolicy: TwitchClientPolicy

    init(session: URLSession = .shared, clientPolicy: TwitchClientPolicy) {
        self.session = session
        self.clientPolicy = clientPolicy
    }

    func livePlaybackURL(
        channelLogin: String,
        credentials: TwitchCredentials?
    ) async throws -> LivePlaybackResponse {
        let normalizedChannel = channelLogin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedChannel.isEmpty else {
            throw APIError.playbackUnavailable("Channel login is missing.")
        }

        let cleanedToken = credentials?.oauthToken.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasCredentials = credentials != nil && !cleanedToken.isEmpty
        let authStyles: [AuthStyle] = hasCredentials
            ? [.oauth, .bearer, .none]
            : [.none]

        var errors: [String] = []

        for authStyle in authStyles {
            for gqlClientID in clientPolicy.playbackClientIDs() {
                do {
                    let playbackToken = try await requestPlaybackToken(
                        channelLogin: normalizedChannel,
                        clientID: gqlClientID,
                        credentials: credentials,
                        authStyle: authStyle
                    )

                    let masterURL = try buildHLSURL(
                        channelLogin: normalizedChannel,
                        clientID: playbackToken.clientID,
                        token: playbackToken
                    )

                    let playableURL = try await resolvePlayableURL(from: masterURL)
                    return LivePlaybackResponse(
                        url: playableURL,
                        authorizationMode: authorizationMode(for: authStyle, hasCredentials: hasCredentials)
                    )
                } catch {
                    errors.append("Playback[\(authStyle.label),\(gqlClientID)]: \(error.localizedDescription)")
                }
            }
        }

        throw APIError.playbackUnavailable(failureSummary(from: errors))
    }

    private func authorizationMode(
        for authStyle: AuthStyle,
        hasCredentials: Bool
    ) -> PlaybackAuthorizationMode {
        switch authStyle {
        case .oauth, .bearer:
            return .authenticated
        case .none:
            return hasCredentials ? .anonymousFallback : .anonymous
        }
    }

    private func buildHLSURL(
        channelLogin: String,
        clientID: String,
        token: PlaybackTokenEnvelope
    ) throws -> URL {
        var components = URLComponents(string: "https://usher.ttvnw.net/api/v2/channel/hls/\(channelLogin).m3u8")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "token", value: token.token.value),
            URLQueryItem(name: "sig", value: token.token.signature),
            URLQueryItem(name: "platform", value: "web"),
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "false"),
            URLQueryItem(name: "playlist_include_framerate", value: "true"),
            URLQueryItem(name: "supported_codecs", value: "h264"),
            URLQueryItem(name: "player", value: "twitchweb"),
            URLQueryItem(name: "type", value: "any"),
            URLQueryItem(name: "p", value: String(Int.random(in: 100_000...999_999)))
        ]

        guard let url = components?.url else { throw APIError.invalidURL }
        return url
    }

    private func requestPlaybackToken(
        channelLogin: String,
        clientID: String,
        credentials: TwitchCredentials?,
        authStyle: AuthStyle
    ) async throws -> PlaybackTokenEnvelope {
        guard let url = URL(string: "https://gql.twitch.tv/gql") else {
            throw APIError.invalidURL
        }

        let body = GQLRequestBody(
            operationName: "PlaybackAccessToken_Template",
            query: "query PlaybackAccessToken_Template($isLive: Boolean!, $login: String!, $isVod: Boolean!, $vodID: ID!, $playerType: String!) { streamPlaybackAccessToken(channelName: $login, params: {platform: \"web\", playerBackend: \"mediaplayer\", playerType: $playerType}) @include(if: $isLive) { value signature __typename } videoPlaybackAccessToken(id: $vodID, params: {platform: \"web\", playerBackend: \"mediaplayer\", playerType: $playerType}) @include(if: $isVod) { value signature __typename } }",
            variables: .init(
                isLive: true,
                login: channelLogin,
                isVod: false,
                vodID: "",
                playerType: "site"
            )
        )

        let encodedBody: Data
        do {
            encodedBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = encodedBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue(UUID().uuidString.replacingOccurrences(of: "-", with: ""), forHTTPHeaderField: "X-Device-Id")

        if let credentials,
           let authorizationStyle = authStyle.authorizationStyle {
            request.setValue(
                clientPolicy.authorizationValue(for: credentials.oauthToken, style: authorizationStyle),
                forHTTPHeaderField: "Authorization"
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.playbackUnavailable(
                "Token request failed with HTTP \(httpResponse.statusCode). \(responseSnippet(from: data))"
            )
        }

        let payload: GQLResponse
        do {
            payload = try JSONDecoder().decode(GQLResponse.self, from: data)
        } catch {
            throw APIError.playbackUnavailable("Token response decoding failed.")
        }

        if let errorMessage = payload.errors?.first?.message {
            throw APIError.playbackUnavailable(errorMessage)
        }

        guard let token = payload.data?.streamPlaybackAccessToken else {
            throw APIError.playbackUnavailable("Twitch did not return a playback token.")
        }

        return PlaybackTokenEnvelope(clientID: clientID, token: token)
    }

    private func resolvePlayableURL(from masterURL: URL) async throws -> URL {
        var request = URLRequest(url: masterURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let usherError = parseUsherError(from: data) {
                throw APIError.playbackUnavailable("Usher HTTP \(httpResponse.statusCode): \(usherError)")
            }

            throw APIError.playbackUnavailable(
                "Usher HTTP \(httpResponse.statusCode). \(responseSnippet(from: data))"
            )
        }

        if let manifestPrefix = String(data: data.prefix(128), encoding: .utf8), manifestPrefix.contains("#EXTM3U") {
            if let manifest = String(data: data, encoding: .utf8),
               let bestVariant = HLSVariantSelector.bestVideoVariant(in: manifest, relativeTo: masterURL) {
                return bestVariant
            }

            return masterURL
        }

        if let usherError = parseUsherError(from: data) {
            throw APIError.playbackUnavailable("Usher error: \(usherError)")
        }

        throw APIError.playbackUnavailable("Usher returned an unexpected playlist response.")
    }

    private func parseUsherError(from data: Data) -> String? {
        if let entries = try? JSONDecoder().decode([UsherErrorEntry].self, from: data), let first = entries.first {
            return [first.errorCode, first.error]
                .compactMap { $0 }
                .joined(separator: " - ")
        }

        if let entry = try? JSONDecoder().decode(UsherErrorEntry.self, from: data) {
            let message = [entry.errorCode, entry.error]
                .compactMap { $0 }
                .joined(separator: " - ")
            return message.isEmpty ? nil : message
        }

        return nil
    }

    private func responseSnippet(from data: Data) -> String {
        guard let raw = String(data: data.prefix(220), encoding: .utf8) else {
            return "No response body."
        }

        let oneLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return oneLine.isEmpty ? "No response body." : oneLine
    }

    private func failureSummary(from errors: [String]) -> String {
        guard !errors.isEmpty else {
            return "Unable to resolve a valid Twitch playback URL."
        }

        let maxItems = 4
        let visible = errors.prefix(maxItems).joined(separator: " | ")
        let remaining = errors.count - min(errors.count, maxItems)

        if remaining > 0 {
            return "\(visible) | +\(remaining) more attempts failed."
        }

        return visible
    }
}
