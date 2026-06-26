import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let enableSevenTV = "settings.enableSevenTV"
        static let enableBTTV = "settings.enableBTTV"
        static let enableFFZ = "settings.enableFFZ"
        static let showChatTimestamp = "settings.showChatTimestamp"
        static let compactChat = "settings.compactChat"
        static let syncChatToVideo = "settings.syncChatToVideo"
    }

    private let defaults: UserDefaults

    @Published var enableSevenTV: Bool {
        didSet { defaults.set(enableSevenTV, forKey: Keys.enableSevenTV) }
    }

    @Published var enableBTTV: Bool {
        didSet { defaults.set(enableBTTV, forKey: Keys.enableBTTV) }
    }

    @Published var enableFFZ: Bool {
        didSet { defaults.set(enableFFZ, forKey: Keys.enableFFZ) }
    }

    @Published var showChatTimestamp: Bool {
        didSet { defaults.set(showChatTimestamp, forKey: Keys.showChatTimestamp) }
    }

    @Published var compactChat: Bool {
        didSet { defaults.set(compactChat, forKey: Keys.compactChat) }
    }

    @Published var syncChatToVideo: Bool {
        didSet { defaults.set(syncChatToVideo, forKey: Keys.syncChatToVideo) }
    }

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults

        enableSevenTV = defaults.bool(forKey: Keys.enableSevenTV, defaultValue: true)
        enableBTTV = defaults.bool(forKey: Keys.enableBTTV, defaultValue: true)
        enableFFZ = defaults.bool(forKey: Keys.enableFFZ, defaultValue: true)
        showChatTimestamp = defaults.bool(forKey: Keys.showChatTimestamp, defaultValue: true)
        compactChat = defaults.bool(forKey: Keys.compactChat, defaultValue: false)
        syncChatToVideo = defaults.bool(forKey: Keys.syncChatToVideo, defaultValue: false)
    }
}

private extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard object(forKey: key) != nil else {
            return defaultValue
        }
        return bool(forKey: key)
    }
}
