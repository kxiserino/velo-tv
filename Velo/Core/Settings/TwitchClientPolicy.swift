import Foundation

struct TwitchCredentials: Sendable {
    let clientID: String
    let oauthToken: String
}

enum TwitchAuthorizationStyle: Sendable {
    case bearer
    case oauth
}

struct TwitchClientPolicy: Sendable {
    private enum LegacyKeys {
        static let twitchClientID = "settings.twitchClientID"
    }

    static let webClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

    let appClientID: String

    init(
        configuration: AppConfiguration,
        defaults: UserDefaults = .standard
    ) {
        let configuredClientID = configuration.twitchClientID.trimmed
        let legacyClientID = defaults.string(forKey: LegacyKeys.twitchClientID)?.trimmed ?? ""
        appClientID = configuredClientID.isEmpty ? legacyClientID : configuredClientID
    }

    var canAuthorizeUser: Bool {
        !appClientID.isEmpty
    }

    var publicGraphQLHeaders: [String: String] {
        ["Client-ID": Self.webClientID]
    }

    func helixHeaders(credentials: TwitchCredentials) -> [String: String] {
        [
            "Client-ID": credentials.clientID,
            "Authorization": authorizationValue(for: credentials.oauthToken, style: .bearer)
        ]
    }

    func playbackClientIDs() -> [String] {
        if appClientID.isEmpty || appClientID == Self.webClientID {
            return [Self.webClientID]
        }

        return [Self.webClientID, appClientID]
    }

    func authorizationValue(for oauthToken: String, style: TwitchAuthorizationStyle) -> String {
        switch style {
        case .bearer:
            return "Bearer \(oauthToken)"
        case .oauth:
            return "OAuth \(oauthToken)"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
