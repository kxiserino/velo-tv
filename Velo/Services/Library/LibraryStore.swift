import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    private enum Keys {
        static let favoriteChannelIDs = "library.favoriteChannelIDs"
        static let watchHistory = "library.watchHistory"
    }

    @Published private(set) var favoriteChannelIDs: Set<String>
    @Published private(set) var watchHistory: [WatchHistoryEntry]

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let favorites = defaults.array(forKey: Keys.favoriteChannelIDs) as? [String] ?? []
        favoriteChannelIDs = Set(favorites)

        if let historyData = defaults.data(forKey: Keys.watchHistory),
           let decoded = try? decoder.decode([WatchHistoryEntry].self, from: historyData) {
            watchHistory = decoded
                .sorted(by: { $0.lastWatchedAt > $1.lastWatchedAt })
        } else {
            watchHistory = []
        }
    }

    func toggleFavorite(for stream: LiveStream) {
        if favoriteChannelIDs.contains(stream.channelID) {
            favoriteChannelIDs.remove(stream.channelID)
        } else {
            favoriteChannelIDs.insert(stream.channelID)
        }

        persistFavorites()
    }

    func isFavorite(channelID: String) -> Bool {
        favoriteChannelIDs.contains(channelID)
    }

    func recordWatch(_ stream: LiveStream) {
        if let existingIndex = watchHistory.firstIndex(where: { $0.channelID == stream.channelID }) {
            watchHistory[existingIndex] = watchHistory[existingIndex].refreshing(with: stream)
        } else {
            watchHistory.append(WatchHistoryEntry(stream: stream))
        }

        watchHistory.sort(by: { $0.lastWatchedAt > $1.lastWatchedAt })
        if watchHistory.count > 100 {
            watchHistory.removeLast(watchHistory.count - 100)
        }

        persistHistory()
    }

    func clearWatchHistory() {
        watchHistory.removeAll(keepingCapacity: false)
        defaults.removeObject(forKey: Keys.watchHistory)
    }

    var recentHistoryStreams: [LiveStream] {
        watchHistory.prefix(20).map(\.asStream)
    }

    private func persistFavorites() {
        defaults.set(Array(favoriteChannelIDs), forKey: Keys.favoriteChannelIDs)
    }

    private func persistHistory() {
        if let data = try? encoder.encode(watchHistory) {
            defaults.set(data, forKey: Keys.watchHistory)
        }
    }
}
