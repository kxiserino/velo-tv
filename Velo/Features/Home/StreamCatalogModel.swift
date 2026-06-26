import Foundation

enum StreamSortOption: String, CaseIterable, Hashable {
    case viewersDescending = "Viewers"
    case recentlyStarted = "Recently Started"
    case channelName = "Channel A-Z"
    case title = "Title A-Z"

    var title: String { rawValue }
}

enum StreamRailKind: Hashable {
    case followed
    case favorites
    case discover
    case history
    case none
}

struct StreamCatalogFilters: Equatable {
    var searchText: String
    var selectedGame: String
    var selectedLanguage: String
    var selectedSort: StreamSortOption
}

struct StreamCatalogModel {
    static let allGames = "All Games"
    static let allLanguages = "All Languages"

    let allLiveStreams: [LiveStream]
    let favoriteLiveStreams: [LiveStream]
    let filteredFollowed: [LiveStream]
    let filteredFavorites: [LiveStream]
    let filteredTop: [LiveStream]
    let filteredHistory: [LiveStream]
    let availableGames: [String]
    let availableLanguages: [String]
    let activeFilterCount: Int

    var hasAnyRawRail: Bool {
        !allFollowedStreams.isEmpty ||
        !favoriteLiveStreams.isEmpty ||
        !allTopStreams.isEmpty ||
        !allHistoryStreams.isEmpty
    }

    var hasAnyFilteredRail: Bool {
        !filteredFollowed.isEmpty ||
        !filteredFavorites.isEmpty ||
        !filteredTop.isEmpty ||
        !filteredHistory.isEmpty
    }

    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    var defaultRail: StreamRailKind {
        if !filteredFollowed.isEmpty { return .followed }
        if !filteredFavorites.isEmpty { return .favorites }
        if !filteredTop.isEmpty { return .discover }
        if !filteredHistory.isEmpty { return .history }
        return .none
    }

    private let allFollowedStreams: [LiveStream]
    private let allTopStreams: [LiveStream]
    private let allHistoryStreams: [LiveStream]

    static func make(
        followedStreams: [LiveStream],
        topStreams: [LiveStream],
        favoriteChannelIDs: Set<String>,
        historyStreams: [LiveStream],
        filters: StreamCatalogFilters
    ) -> StreamCatalogModel {
        let allLiveStreams = deduplicatedLiveStreams(followedStreams: followedStreams, topStreams: topStreams)
        let favoriteLiveStreams = allLiveStreams
            .filter { favoriteChannelIDs.contains($0.channelID) }
            .sorted { ($0.viewerCount ?? 0) > ($1.viewerCount ?? 0) }

        return StreamCatalogModel(
            allLiveStreams: allLiveStreams,
            favoriteLiveStreams: favoriteLiveStreams,
            filteredFollowed: filteredAndSorted(followedStreams, filters: filters),
            filteredFavorites: filteredAndSorted(favoriteLiveStreams, filters: filters),
            filteredTop: filteredAndSorted(topStreams, filters: filters),
            filteredHistory: filteredAndSorted(historyStreams, filters: filters, applySort: false),
            availableGames: availableGames(in: allLiveStreams),
            availableLanguages: availableLanguages(in: allLiveStreams),
            activeFilterCount: activeFilterCount(for: filters),
            allFollowedStreams: followedStreams,
            allTopStreams: topStreams,
            allHistoryStreams: historyStreams
        )
    }

    static func deduplicatedLiveStreams(
        followedStreams: [LiveStream],
        topStreams: [LiveStream]
    ) -> [LiveStream] {
        var deduplicated: [String: LiveStream] = [:]

        for stream in followedStreams + topStreams {
            let existing = deduplicated[stream.channelID]
            if existing == nil || (stream.viewerCount ?? 0) > (existing?.viewerCount ?? 0) {
                deduplicated[stream.channelID] = stream
            }
        }

        return deduplicated.values.sorted {
            ($0.viewerCount ?? 0) > ($1.viewerCount ?? 0)
        }
    }

    static func filteredAndSorted(
        _ streams: [LiveStream],
        filters: StreamCatalogFilters,
        applySort: Bool = true
    ) -> [LiveStream] {
        let query = filters.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var filtered = streams.filter { stream in
            if filters.selectedGame != Self.allGames && stream.gameName != filters.selectedGame {
                return false
            }

            if filters.selectedLanguage != Self.allLanguages &&
                stream.language.lowercased() != filters.selectedLanguage.lowercased() {
                return false
            }

            guard !query.isEmpty else { return true }
            return stream.channelName.localizedStandardContains(query) ||
                stream.title.localizedStandardContains(query) ||
                stream.gameName.localizedStandardContains(query)
        }

        guard applySort else { return filtered }

        switch filters.selectedSort {
        case .viewersDescending:
            filtered.sort { ($0.viewerCount ?? 0) > ($1.viewerCount ?? 0) }
        case .recentlyStarted:
            filtered.sort { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
        case .channelName:
            filtered.sort { $0.channelName.localizedCaseInsensitiveCompare($1.channelName) == .orderedAscending }
        case .title:
            filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        return filtered
    }

    private static func availableGames(in streams: [LiveStream]) -> [String] {
        let games = Set(streams.map(\.gameName).filter { !$0.isEmpty })
        return [Self.allGames] + games.sorted()
    }

    private static func availableLanguages(in streams: [LiveStream]) -> [String] {
        let languages = Set(streams.map { $0.language.lowercased() }.filter { !$0.isEmpty })
        return [Self.allLanguages] + languages.sorted()
    }

    private static func activeFilterCount(for filters: StreamCatalogFilters) -> Int {
        [
            filters.selectedGame != Self.allGames,
            filters.selectedLanguage != Self.allLanguages,
            filters.selectedSort != .viewersDescending
        ].filter { $0 }.count
    }
}
