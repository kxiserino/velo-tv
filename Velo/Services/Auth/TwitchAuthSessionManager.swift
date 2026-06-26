import Foundation

@MainActor
final class TwitchAuthSessionManager {
    static let requiredScopes = ["chat:read", "user:read:follows"]

    private let clientPolicy: TwitchClientPolicy
    private let sessionStore: TwitchSessionStore
    private let authService: TwitchAuthService

    init(
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        authService: TwitchAuthService
    ) {
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.authService = authService
    }

    func requestDeviceGrant() async throws -> TwitchDeviceGrant {
        try await authService.requestDeviceCode(clientID: clientPolicy.appClientID, scopes: Self.requiredScopes)
    }

    func pollDeviceGrant(deviceCode: String) async throws -> TwitchDevicePollResult {
        try await authService.pollDeviceCode(clientID: clientPolicy.appClientID, deviceCode: deviceCode)
    }

    func completeAuthorization(with token: TwitchOAuthToken) async throws -> TwitchValidatedSession {
        let session = try await authService.validateToken(token.accessToken)

        sessionStore.twitchOAuthToken = token.accessToken
        sessionStore.twitchRefreshToken = token.refreshToken ?? ""
        sessionStore.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        applyValidatedSession(session)
        return session
    }

    func ensureSessionValidity() async throws {
        let currentToken = sessionStore.cleanOAuthToken
        guard !currentToken.isEmpty else { return }

        try await refreshIfNeeded()

        let shouldValidate: Bool
        if let last = sessionStore.lastTokenValidationDate {
            shouldValidate = Date().timeIntervalSince(last) > 3600
        } else {
            shouldValidate = true
        }

        if shouldValidate {
            let validated = try await authService.validateToken(sessionStore.cleanOAuthToken)
            applyValidatedSession(validated)
        }
    }

    private func refreshIfNeeded() async throws {
        guard
            let expirationDate = sessionStore.tokenExpirationDate,
            !sessionStore.twitchRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let refreshBuffer: TimeInterval = 180
        guard expirationDate.timeIntervalSinceNow <= refreshBuffer else { return }

        let refreshed = try await authService.refreshToken(
            clientID: clientPolicy.appClientID,
            refreshToken: sessionStore.twitchRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        sessionStore.twitchOAuthToken = refreshed.accessToken
        sessionStore.twitchRefreshToken = refreshed.refreshToken ?? sessionStore.twitchRefreshToken
        sessionStore.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(refreshed.expiresIn))
        sessionStore.lastTokenValidationDate = nil
    }

    private func applyValidatedSession(_ session: TwitchValidatedSession) {
        sessionStore.lastTokenValidationDate = Date()
        sessionStore.chatUsername = session.login
        sessionStore.twitchUserID = session.userID
    }
}
