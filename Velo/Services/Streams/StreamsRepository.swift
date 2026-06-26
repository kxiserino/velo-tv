import Foundation

@MainActor
final class StreamsRepository {
    private let apiClient: TwitchAPIClient
    private let clientPolicy: TwitchClientPolicy
    private let sessionStore: TwitchSessionStore
    private let authSessionManager: TwitchAuthSessionManager

    init(
        apiClient: TwitchAPIClient,
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        authSessionManager: TwitchAuthSessionManager
    ) {
        self.apiClient = apiClient
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.authSessionManager = authSessionManager
    }

    func loadHomeStreams(limit: Int = 40) async throws -> [LiveStream] {
        try await apiClient.publicTopStreams(limit: limit)
    }

    func search(query: String, limit: Int = 30) async throws -> [LiveStream] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try await apiClient.publicSearchLiveChannels(query: trimmed, limit: limit)
    }

    func loadFollowedStreams(limit: Int = 30) async throws -> [LiveStream] {
        let userID = sessionStore.twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty else { throw APIError.missingUserID }

        try await authSessionManager.ensureSessionValidity()
        let credentials = try sessionStore.credentials(using: clientPolicy)
        return try await apiClient.followedStreams(credentials: credentials, userID: userID, limit: limit)
    }
}
