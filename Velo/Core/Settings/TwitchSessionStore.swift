import Foundation
import Combine

@MainActor
final class TwitchSessionStore: ObservableObject {
    private enum Keys {
        static let twitchOAuthToken = "settings.twitchOAuthToken"
        static let twitchRefreshToken = "settings.twitchRefreshToken"
        static let tokenExpirationDate = "settings.tokenExpirationDate"
        static let lastTokenValidationDate = "settings.lastTokenValidationDate"
        static let twitchUserID = "settings.twitchUserID"
        static let chatUsername = "settings.chatUsername"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    @Published var twitchOAuthToken: String {
        didSet { persistSecret(twitchOAuthToken, forKey: Keys.twitchOAuthToken) }
    }

    @Published var twitchRefreshToken: String {
        didSet { persistSecret(twitchRefreshToken, forKey: Keys.twitchRefreshToken) }
    }

    @Published var tokenExpirationDate: Date? {
        didSet { defaults.set(tokenExpirationDate, forKey: Keys.tokenExpirationDate) }
    }

    @Published var lastTokenValidationDate: Date? {
        didSet { defaults.set(lastTokenValidationDate, forKey: Keys.lastTokenValidationDate) }
    }

    @Published var twitchUserID: String {
        didSet { defaults.set(twitchUserID, forKey: Keys.twitchUserID) }
    }

    @Published var chatUsername: String {
        didSet { defaults.set(chatUsername, forKey: Keys.chatUsername) }
    }

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(),
        configuration: AppConfiguration
    ) {
        self.defaults = defaults
        self.keychain = keychain

        let legacyAccessToken = defaults.string(forKey: Keys.twitchOAuthToken) ?? ""
        let legacyRefreshToken = defaults.string(forKey: Keys.twitchRefreshToken) ?? ""
        let keychainAccessToken = keychain.string(for: Keys.twitchOAuthToken)
        let keychainRefreshToken = keychain.string(for: Keys.twitchRefreshToken)
        let storedAccessToken = keychainAccessToken ?? legacyAccessToken
        let storedRefreshToken = keychainRefreshToken ?? legacyRefreshToken
        let storedUserID = defaults.string(forKey: Keys.twitchUserID) ?? ""
        let storedChatUsername = defaults.string(forKey: Keys.chatUsername) ?? ""

        twitchOAuthToken = configuration.twitchAccessToken.isEmpty ? storedAccessToken : configuration.twitchAccessToken
        twitchRefreshToken = configuration.twitchRefreshToken.isEmpty ? storedRefreshToken : configuration.twitchRefreshToken
        twitchUserID = configuration.twitchUserID.isEmpty ? storedUserID : configuration.twitchUserID
        chatUsername = configuration.twitchChatUsername.isEmpty ? storedChatUsername : configuration.twitchChatUsername
        tokenExpirationDate = configuration.twitchTokenExpirationDate ?? (defaults.object(forKey: Keys.tokenExpirationDate) as? Date)
        lastTokenValidationDate = defaults.object(forKey: Keys.lastTokenValidationDate) as? Date

        if keychainAccessToken == nil, !legacyAccessToken.isEmpty {
            keychain.set(legacyAccessToken, for: Keys.twitchOAuthToken)
        }
        if keychainRefreshToken == nil, !legacyRefreshToken.isEmpty {
            keychain.set(legacyRefreshToken, for: Keys.twitchRefreshToken)
        }
        defaults.removeObject(forKey: Keys.twitchOAuthToken)
        defaults.removeObject(forKey: Keys.twitchRefreshToken)
    }

    var cleanOAuthToken: String {
        var token = twitchOAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("oauth:") {
            token.removeFirst("oauth:".count)
        }
        if token.lowercased().hasPrefix("bearer ") {
            token.removeFirst("bearer ".count)
        }
        return token
    }

    func hasAPIAuth(using policy: TwitchClientPolicy) -> Bool {
        policy.canAuthorizeUser && !cleanOAuthToken.isEmpty
    }

    func hasChatCredentials(using policy: TwitchClientPolicy) -> Bool {
        hasAPIAuth(using: policy) && !chatUsername.trimmed.isEmpty
    }

    func hasFollowedSetup(using policy: TwitchClientPolicy) -> Bool {
        hasAPIAuth(using: policy) && !twitchUserID.trimmed.isEmpty
    }

    func credentials(using policy: TwitchClientPolicy) throws -> TwitchCredentials {
        guard let credentials = optionalCredentials(using: policy) else {
            throw APIError.missingCredentials
        }
        return credentials
    }

    func optionalCredentials(using policy: TwitchClientPolicy) -> TwitchCredentials? {
        let token = cleanOAuthToken
        guard policy.canAuthorizeUser, !token.isEmpty else { return nil }

        return TwitchCredentials(
            clientID: policy.appClientID,
            oauthToken: token
        )
    }

    func clearUserSession() {
        twitchOAuthToken = ""
        twitchRefreshToken = ""
        tokenExpirationDate = nil
        lastTokenValidationDate = nil
        twitchUserID = ""
        chatUsername = ""
    }

    private func persistSecret(_ value: String, forKey key: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keychain.delete(account: key)
        } else {
            keychain.set(value, for: key)
        }

        defaults.removeObject(forKey: key)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
