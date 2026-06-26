import SwiftUI

struct HomeView: View {
    @ObservedObject private var container: AppContainer
    @ObservedObject private var sessionStore: TwitchSessionStore
    private let resetToken: Int
    private let onOpenStream: (LiveStream) -> Void
    @StateObject private var viewModel: HomeViewModel

    @State private var searchText = ""
    @State private var selectedGame = StreamCatalogModel.allGames
    @State private var selectedLanguage = StreamCatalogModel.allLanguages
    @State private var selectedSort: StreamSortOption = .viewersDescending
    @Namespace private var homeFocusScope

    init(
        container: AppContainer,
        resetToken: Int = 0,
        onOpenStream: @escaping (LiveStream) -> Void = { _ in }
    ) {
        self.container = container
        self.sessionStore = container.sessionStore
        self.resetToken = resetToken
        self.onOpenStream = onOpenStream
        _viewModel = StateObject(wrappedValue: HomeViewModel(repository: container.streamsRepository))
    }

    private var catalog: StreamCatalogModel {
        StreamCatalogModel.make(
            followedStreams: viewModel.followedStreams,
            topStreams: viewModel.topStreams,
            favoriteChannelIDs: container.libraryStore.favoriteChannelIDs,
            historyStreams: container.libraryStore.recentHistoryStreams,
            filters: filters
        )
    }

    private var filters: StreamCatalogFilters {
        StreamCatalogFilters(
            searchText: searchText,
            selectedGame: selectedGame,
            selectedLanguage: selectedLanguage,
            selectedSort: selectedSort
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && !catalog.hasAnyRawRail {
                ProgressView("Loading streams")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !catalog.hasAnyRawRail, let homeError = viewModel.homeError {
                ContentUnavailableView {
                    Label("Could not load streams", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(homeError)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.reload(followedSessionKey: followedSessionKey) }
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        filterControls

                        if let homeError = viewModel.homeError {
                            VeloStatusCard(
                                title: "Top streams unavailable",
                                message: homeError,
                                symbol: "exclamationmark.triangle"
                            )
                            .padding(.horizontal, VeloUI.screenHorizontalPadding)
                        }

                        if !sessionStore.twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           let followedError = viewModel.followedError {
                            VeloStatusCard(
                                title: "Followed streams unavailable",
                                message: followedError,
                                symbol: "person.crop.circle.badge.exclamationmark"
                            )
                            .padding(.horizontal, VeloUI.screenHorizontalPadding)
                        }

                        if !catalog.filteredFollowed.isEmpty {
                            StreamRailSection(title: "Followed Live", subtitle: "Channels you follow currently on air") {
                                rail(for: catalog.filteredFollowed, defaultFocus: catalog.defaultRail == .followed)
                            }
                        }

                        if !catalog.filteredFavorites.isEmpty {
                            StreamRailSection(title: "Favorites Live", subtitle: "Pinned channels currently live") {
                                rail(for: catalog.filteredFavorites, defaultFocus: catalog.defaultRail == .favorites)
                            }
                        } else if !container.libraryStore.favoriteChannelIDs.isEmpty {
                            VeloStatusCard(
                                title: "Favorites",
                                message: "None of your favorite channels match the current filters.",
                                symbol: "star"
                            )
                            .padding(.horizontal, VeloUI.screenHorizontalPadding)
                        }

                        if !catalog.filteredTop.isEmpty {
                            StreamRailSection(title: "Discover", subtitle: "Top live streams") {
                                rail(for: catalog.filteredTop, defaultFocus: catalog.defaultRail == .discover)
                            }
                        }

                        if !catalog.filteredHistory.isEmpty {
                            StreamRailSection(title: "Watch History", subtitle: "Jump back into recently watched channels") {
                                rail(
                                    for: catalog.filteredHistory,
                                    footerOverride: { historyFooter(for: $0.channelID) },
                                    defaultFocus: catalog.defaultRail == .history
                                )
                            }
                        }

                        if sessionStore.twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VeloStatusCard(
                                title: "Optional Twitch login",
                                message: "Log in from Settings to add followed channels.",
                                symbol: "person.2"
                            )
                            .padding(.horizontal, VeloUI.screenHorizontalPadding)
                        }

                        if !catalog.hasAnyFilteredRail {
                            VeloStatusCard(
                                title: "No results",
                                message: "No streams match your current search/filter settings.",
                                symbol: "line.3.horizontal.decrease.circle"
                            )
                            .padding(.horizontal, VeloUI.screenHorizontalPadding)
                        }
                    }
                    .padding(.top, VeloUI.screenTopPadding)
                    .padding(.bottom, VeloUI.screenBottomPadding)
                }
            }
        }
        .id(resetToken)
        .focusScope(homeFocusScope)
        .task(id: followedSessionKey) {
            await viewModel.loadIfNeeded(followedSessionKey: followedSessionKey)
            await viewModel.syncFollowedStreams(for: followedSessionKey)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var followedSessionKey: String? {
        guard sessionStore.hasFollowedSetup(using: container.twitchPolicy) else { return nil }

        let userID = sessionStore.twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        return userID.isEmpty ? nil : userID
    }

    private var header: some View {
        Text("Live on Twitch")
            .font(.largeTitle.weight(.bold))
            .padding(.horizontal, VeloUI.screenHorizontalPadding)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                InlineSearchField(
                    placeholder: "Search channels, titles, and games",
                    text: $searchText
                )

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .frame(width: VeloUI.controlHeight, height: VeloUI.controlHeight)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Clear search")
                }

                Menu {
                    Section("Game") {
                        ForEach(catalog.availableGames, id: \.self) { game in
                            Button {
                                selectedGame = game
                            } label: {
                                if selectedGame == game {
                                    Label(game, systemImage: "checkmark")
                                } else {
                                    Text(game)
                                }
                            }
                        }
                    }

                    Section("Language") {
                        ForEach(catalog.availableLanguages, id: \.self) { language in
                            Button {
                                selectedLanguage = language
                            } label: {
                                if selectedLanguage == language {
                                    Label(languageLabel(language), systemImage: "checkmark")
                                } else {
                                    Text(languageLabel(language))
                                }
                            }
                        }
                    }

                    Section("Sort") {
                        ForEach(StreamSortOption.allCases, id: \.self) { option in
                            Button {
                                selectedSort = option
                            } label: {
                                if selectedSort == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    }
                } label: {
                    FilterMenuLabel(
                        title: catalog.hasActiveFilters ? "\(catalog.activeFilterCount) filters" : "Filters",
                        isActive: catalog.hasActiveFilters
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Shows game, language, and sort filters")
            }
            .focusSection()
        }
        .padding(.horizontal, VeloUI.screenHorizontalPadding)
    }

    @ViewBuilder
    private func rail(
        for streams: [LiveStream],
        footerOverride: @escaping (LiveStream) -> String? = { _ in nil },
        defaultFocus: Bool = false
    ) -> some View {
        StreamRailView(
            streams: streams,
            libraryStore: container.libraryStore,
            focusScope: homeFocusScope,
            defaultFocusOnFirstItem: defaultFocus,
            footerOverride: footerOverride,
            onOpenStream: onOpenStream
        )
    }

    private func languageLabel(_ code: String) -> String {
        guard code != StreamCatalogModel.allLanguages else { return code }
        let lower = code.lowercased()
        return Locale.current.localizedString(forLanguageCode: lower) ?? lower.uppercased()
    }

    private func historyFooter(for channelID: String) -> String {
        guard let match = container.libraryStore.watchHistory.first(where: { $0.channelID == channelID }) else {
            return "Recently watched"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Watched \(formatter.localizedString(for: match.lastWatchedAt, relativeTo: Date()))"
    }
}

private struct FilterMenuLabel: View {
    let title: String
    let isActive: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Label(title, systemImage: "line.3.horizontal.decrease.circle")
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .animation(VeloUI.focusAnimation, value: isFocused)
            .animation(VeloUI.focusAnimation, value: isActive)
    }

    private var foregroundColor: Color {
        if isFocused { return .black }
        return isActive ? .accentColor : Color.white.opacity(0.86)
    }
}

private struct StreamRailSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, VeloUI.screenHorizontalPadding)

            content
        }
    }
}
