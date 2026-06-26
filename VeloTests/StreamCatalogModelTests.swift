import Foundation
import Testing
@testable import Velo

@Suite("Stream catalog shaping")
struct StreamCatalogModelTests {
    @Test("Preserves followed favorites discover history rail priority")
    func defaultRailPriority() {
        let followed = stream(channelID: "followed", channelName: "Beta", viewers: 50)
        let favorite = stream(channelID: "favorite", channelName: "Alpha", viewers: 80)
        let discover = stream(channelID: "discover", channelName: "Gamma", viewers: 120)
        let history = stream(channelID: "history", channelName: "Delta", viewers: nil)

        let withFollowed = model(
            followed: [followed],
            top: [favorite, discover],
            favorites: ["favorite"],
            history: [history]
        )
        let withFavorites = model(top: [favorite, discover], favorites: ["favorite"], history: [history])
        let withDiscover = model(top: [discover], history: [history])
        let withHistory = model(history: [history])

        #expect(withFollowed.defaultRail == .followed)
        #expect(withFavorites.defaultRail == .favorites)
        #expect(withDiscover.defaultRail == .discover)
        #expect(withHistory.defaultRail == .history)
    }

    @Test("Applies search game language and sort filters")
    func filtersAndSortsStreams() {
        let newest = stream(
            channelID: "newest",
            channelName: "Zeta",
            title: "Swift code",
            gameName: "Software",
            language: "en",
            viewers: 10,
            startedAt: Date(timeIntervalSince1970: 200)
        )
        let oldest = stream(
            channelID: "oldest",
            channelName: "Alpha",
            title: "Swift craft",
            gameName: "Software",
            language: "en",
            viewers: 100,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let otherGame = stream(
            channelID: "other",
            channelName: "Other",
            title: "Swift code",
            gameName: "Games",
            language: "en",
            viewers: 200
        )
        let otherLanguage = stream(
            channelID: "language",
            channelName: "Lang",
            title: "Swift code",
            gameName: "Software",
            language: "fr",
            viewers: 300
        )

        let catalog = model(
            top: [oldest, newest, otherGame, otherLanguage],
            filters: StreamCatalogFilters(
                searchText: "swift",
                selectedGame: "Software",
                selectedLanguage: "en",
                selectedSort: .recentlyStarted
            )
        )

        #expect(catalog.filteredTop.map(\.channelID) == ["newest", "oldest"])
        #expect(catalog.activeFilterCount == 3)
        #expect(catalog.hasActiveFilters)
    }

    @Test("Derives empty and login-related state from inputs")
    func derivesEmptyState() {
        let empty = model()
        let filteredOut = model(
            top: [stream(channelID: "one", gameName: "Games")],
            filters: StreamCatalogFilters(
                searchText: "",
                selectedGame: "Software",
                selectedLanguage: StreamCatalogModel.allLanguages,
                selectedSort: .viewersDescending
            )
        )

        #expect(!empty.hasAnyRawRail)
        #expect(!empty.hasAnyFilteredRail)
        #expect(filteredOut.hasAnyRawRail)
        #expect(!filteredOut.hasAnyFilteredRail)
    }

    private func model(
        followed: [LiveStream] = [],
        top: [LiveStream] = [],
        favorites: Set<String> = [],
        history: [LiveStream] = [],
        filters: StreamCatalogFilters = StreamCatalogFilters(
            searchText: "",
            selectedGame: StreamCatalogModel.allGames,
            selectedLanguage: StreamCatalogModel.allLanguages,
            selectedSort: .viewersDescending
        )
    ) -> StreamCatalogModel {
        StreamCatalogModel.make(
            followedStreams: followed,
            topStreams: top,
            favoriteChannelIDs: favorites,
            historyStreams: history,
            filters: filters
        )
    }

    private func stream(
        channelID: String,
        channelName: String = "Channel",
        title: String = "Live stream",
        gameName: String = "Games",
        language: String = "en",
        viewers: Int? = 10,
        startedAt: Date? = nil
    ) -> LiveStream {
        LiveStream(
            id: "stream-\(channelID)",
            channelID: channelID,
            channelLogin: channelID,
            channelName: channelName,
            title: title,
            gameName: gameName,
            language: language,
            viewerCount: viewers,
            thumbnailTemplate: "https://example.com/thumb.jpg",
            startedAt: startedAt
        )
    }
}
