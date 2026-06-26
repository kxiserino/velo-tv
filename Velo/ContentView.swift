import SwiftUI

private enum AppTab: String, CaseIterable, Hashable {
    case home
    case search
    case settings

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject var container: AppContainer
    @AppStorage("app.selectedTab") private var selectedTabRawValue = AppTab.home.rawValue
    @State private var homeResetToken = 0
    @State private var searchResetToken = 0
    @State private var settingsResetToken = 0
    @State private var activeStream: LiveStream?

    var body: some View {
        TabView(selection: tabSelectionBinding) {
            Tab("Home", systemImage: AppTab.home.systemImage, value: AppTab.home) {
                tabBackground {
                    HomeView(
                        container: container,
                        resetToken: homeResetToken,
                        onOpenStream: { stream in
                            activeStream = stream
                        }
                    )
                }
            }

            Tab("Search", systemImage: AppTab.search.systemImage, value: AppTab.search) {
                tabBackground {
                    SearchView(
                        container: container,
                        resetToken: searchResetToken,
                        onOpenStream: { stream in
                            activeStream = stream
                        }
                    )
                }
            }

            Tab("Settings", systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                tabBackground {
                    SettingsView(
                        settings: container.settings,
                        clientPolicy: container.twitchPolicy,
                        sessionStore: container.sessionStore,
                        libraryStore: container.libraryStore,
                        sessionManager: container.authSessionManager,
                        resetToken: settingsResetToken
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarVisibility(.visible, for: .tabBar)
        .fullScreenCover(item: $activeStream) { stream in
            StreamPlayerView(
                stream: stream,
                settings: container.settings,
                clientPolicy: container.twitchPolicy,
                sessionStore: container.sessionStore,
                emoteCatalog: container.emoteCatalog,
                chatBadgeService: container.chatBadgeService,
                libraryStore: container.libraryStore,
                authSessionManager: container.authSessionManager,
                playbackService: container.playbackService
            )
        }
    }

    private var selectedTab: AppTab {
        AppTab(rawValue: selectedTabRawValue) ?? .home
    }

    private var tabSelectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: selectTab
        )
    }

    private func selectTab(_ tab: AppTab) {
        if tab == selectedTab {
            switch tab {
            case .home:
                homeResetToken += 1
            case .search:
                searchResetToken += 1
            case .settings:
                settingsResetToken += 1
            }
        } else {
            selectedTabRawValue = tab.rawValue
        }
    }

    private func tabBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            VeloBackground()
            content()
        }
    }
}
