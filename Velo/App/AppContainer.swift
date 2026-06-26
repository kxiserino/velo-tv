import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettings
    let twitchPolicy: TwitchClientPolicy
    let sessionStore: TwitchSessionStore
    let authService: TwitchAuthService
    let authSessionManager: TwitchAuthSessionManager
    let streamsRepository: StreamsRepository
    let emoteCatalog: EmoteCatalogService
    let chatBadgeService: TwitchChatBadgeService
    let libraryStore: LibraryStore
    let playbackService: TwitchPlaybackService

    init(
        settings: AppSettings,
        twitchPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        authService: TwitchAuthService,
        authSessionManager: TwitchAuthSessionManager,
        streamsRepository: StreamsRepository,
        emoteCatalog: EmoteCatalogService,
        chatBadgeService: TwitchChatBadgeService,
        libraryStore: LibraryStore,
        playbackService: TwitchPlaybackService
    ) {
        self.settings = settings
        self.twitchPolicy = twitchPolicy
        self.sessionStore = sessionStore
        self.authService = authService
        self.authSessionManager = authSessionManager
        self.streamsRepository = streamsRepository
        self.emoteCatalog = emoteCatalog
        self.chatBadgeService = chatBadgeService
        self.libraryStore = libraryStore
        self.playbackService = playbackService
    }

    static func live() -> AppContainer {
        let configuration = AppConfiguration.load()
        let settings = AppSettings()
        let twitchPolicy = TwitchClientPolicy(configuration: configuration)
        let sessionStore = TwitchSessionStore(configuration: configuration)
        let authService = TwitchAuthService()
        let authSessionManager = TwitchAuthSessionManager(
            clientPolicy: twitchPolicy,
            sessionStore: sessionStore,
            authService: authService
        )
        let httpClient = HTTPClient()
        let twitchAPIClient = TwitchAPIClient(httpClient: httpClient, clientPolicy: twitchPolicy)
        let streamsRepository = StreamsRepository(
            apiClient: twitchAPIClient,
            clientPolicy: twitchPolicy,
            sessionStore: sessionStore,
            authSessionManager: authSessionManager
        )
        let sevenTV = SevenTVService(httpClient: httpClient)
        let bttv = BTTVService(httpClient: httpClient)
        let ffz = FFZService(httpClient: httpClient)
        let emoteCatalog = EmoteCatalogService(sevenTV: sevenTV, bttv: bttv, ffz: ffz)
        let chatBadgeService = TwitchChatBadgeService(httpClient: httpClient)
        let libraryStore = LibraryStore()
        let playbackService = TwitchPlaybackService(clientPolicy: twitchPolicy)

        return AppContainer(
            settings: settings,
            twitchPolicy: twitchPolicy,
            sessionStore: sessionStore,
            authService: authService,
            authSessionManager: authSessionManager,
            streamsRepository: streamsRepository,
            emoteCatalog: emoteCatalog,
            chatBadgeService: chatBadgeService,
            libraryStore: libraryStore,
            playbackService: playbackService
        )
    }
}
