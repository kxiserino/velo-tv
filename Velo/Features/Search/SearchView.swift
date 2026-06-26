import SwiftUI

struct SearchView: View {
    @ObservedObject private var container: AppContainer
    private let resetToken: Int
    private let onOpenStream: (LiveStream) -> Void
    @StateObject private var viewModel: SearchViewModel
    @AppStorage("search.recentQueries") private var recentQueriesStorage = ""
    @Namespace private var searchFocusScope

    init(
        container: AppContainer,
        resetToken: Int = 0,
        onOpenStream: @escaping (LiveStream) -> Void = { _ in }
    ) {
        self.container = container
        self.resetToken = resetToken
        self.onOpenStream = onOpenStream
        _viewModel = StateObject(wrappedValue: SearchViewModel(repository: container.streamsRepository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VeloUI.sectionSpacing) {
            Text("Search")
                .font(.largeTitle.weight(.bold))

            InlineSearchField(
                placeholder: "Search live channels",
                text: $viewModel.query
            )
            .onSubmit {
                submitSearch()
            }
            .onChange(of: viewModel.query) { _, _ in
                viewModel.scheduleSearch()
            }

            if !recentQueries.isEmpty {
                recentSearches
            }

            content
        }
        .padding(.horizontal, VeloUI.screenHorizontalPadding)
        .padding(.top, VeloUI.screenTopPadding)
        .padding(.bottom, VeloUI.screenBottomPadding)
        .id(resetToken)
        .focusScope(searchFocusScope)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            if recentQueries.isEmpty {
                ContentUnavailableView(
                    "Find a stream",
                    systemImage: "magnifyingglass",
                    description: Text("Search by channel, game, or stream title.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        case .searching:
            if viewModel.results.isEmpty {
                ProgressView("Searching")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsRail(isRefreshing: true)
            }
        case .failed(let message):
            VStack(spacing: 18) {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }

                Button {
                    submitSearch()
                } label: {
                    VeloActionButtonLabel(
                        title: "Retry",
                        systemImage: "arrow.clockwise",
                        isProminent: true
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .prefersDefaultFocus(true, in: searchFocusScope)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewModel.results.isEmpty {
                ContentUnavailableView(
                    "No live results",
                    systemImage: "video.slash",
                    description: Text("Try another channel or game keyword.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsRail(isRefreshing: false)
            }
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: VeloUI.groupSpacing) {
            Text("Recent searches")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(recentQueries, id: \.self) { query in
                        Button {
                            viewModel.query = query
                            submitSearch()
                        } label: {
                            VeloChipLabel(
                                title: query,
                                systemImage: "clock.arrow.circlepath"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Searches live streams for \(query)")
                    }
                }
                .padding(.vertical, 4)
                .focusSection()
            }
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
        }
    }

    private func resultsRail(isRefreshing: Bool) -> some View {
        VStack(alignment: .leading, spacing: VeloUI.groupSpacing) {
            HStack(spacing: 16) {
                Text("Results")
                    .font(.title2.weight(.semibold))

                if isRefreshing {
                    ProgressView()
                        .controlSize(.regular)
                }

                Spacer()

                Text("\(viewModel.results.count) live")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            StreamRailView(
                streams: viewModel.results,
                libraryStore: container.libraryStore,
                focusScope: searchFocusScope,
                horizontalPadding: 0,
                defaultFocusOnFirstItem: true,
                onOpenStream: onOpenStream
            )
        }
    }

    private var recentQueries: [String] {
        recentQueriesStorage
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func submitSearch() {
        saveRecentQuery(viewModel.query)
        Task { await viewModel.search() }
    }

    private func saveRecentQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let updated = ([trimmed] + recentQueries.filter { $0.localizedCaseInsensitiveCompare(trimmed) != .orderedSame })
            .prefix(8)

        recentQueriesStorage = updated.joined(separator: "\n")
    }
}
