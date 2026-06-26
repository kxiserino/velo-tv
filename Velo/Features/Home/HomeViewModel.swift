import Foundation
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var homeError: String?
    @Published private(set) var topStreams: [LiveStream] = []
    @Published private(set) var followedStreams: [LiveStream] = []
    @Published private(set) var followedError: String?

    private let repository: StreamsRepository
    private var loadedFollowedSessionKey: String?

    init(repository: StreamsRepository) {
        self.repository = repository
    }

    func loadIfNeeded(followedSessionKey: String?) async {
        guard topStreams.isEmpty && followedStreams.isEmpty else { return }
        await reload(followedSessionKey: followedSessionKey)
    }

    func reload(followedSessionKey: String?) async {
        isLoading = true
        homeError = nil

        do {
            topStreams = try await repository.loadHomeStreams()
        } catch {
            homeError = error.localizedDescription
            topStreams = []
        }

        await syncFollowedStreams(for: followedSessionKey, force: true)
        isLoading = false
    }

    func syncFollowedStreams(for sessionKey: String?, force: Bool = false) async {
        guard let sessionKey else {
            loadedFollowedSessionKey = nil
            followedError = nil
            followedStreams = []
            return
        }

        guard force || loadedFollowedSessionKey != sessionKey else { return }

        followedError = nil

        do {
            followedStreams = try await repository.loadFollowedStreams()
        } catch APIError.missingUserID {
            followedStreams = []
            loadedFollowedSessionKey = nil
        } catch {
            followedError = error.localizedDescription
            followedStreams = []
        }

        loadedFollowedSessionKey = sessionKey
    }
}
