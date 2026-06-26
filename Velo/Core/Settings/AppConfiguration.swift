import Foundation

struct AppConfiguration {
    let twitchClientID: String
    let twitchAccessToken: String
    let twitchRefreshToken: String
    let twitchUserID: String
    let twitchChatUsername: String
    let twitchTokenExpirationDate: Date?

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        AppConfiguration(
            twitchClientID: readString("TWITCH_CLIENT_ID", bundle: bundle, environment: environment),
            twitchAccessToken: readString("TWITCH_ACCESS_TOKEN", bundle: bundle, environment: environment),
            twitchRefreshToken: readString("TWITCH_REFRESH_TOKEN", bundle: bundle, environment: environment),
            twitchUserID: readString("TWITCH_USER_ID", bundle: bundle, environment: environment),
            twitchChatUsername: readString("TWITCH_CHAT_USERNAME", bundle: bundle, environment: environment),
            twitchTokenExpirationDate: readDate("TWITCH_TOKEN_EXPIRATION_EPOCH", bundle: bundle, environment: environment)
        )
    }

    private static func readString(
        _ key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String {
        if let envValue = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !envValue.isEmpty {
            return envValue
        }

        if let infoValue = bundle.object(forInfoDictionaryKey: key) as? String {
            let trimmed = infoValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return ""
    }

    private static func readDate(
        _ key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> Date? {
        let raw = readString(key, bundle: bundle, environment: environment)
        guard !raw.isEmpty else { return nil }

        if let epoch = TimeInterval(raw) {
            return Date(timeIntervalSince1970: epoch)
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: raw)
    }
}
