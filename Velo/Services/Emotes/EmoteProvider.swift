import Foundation

enum EmoteProviderKind: String, CaseIterable, Sendable {
    case sevenTV
    case bttv
    case ffz
}

protocol EmoteProvider: Sendable {
    nonisolated var kind: EmoteProviderKind { get }

    func fetchGlobalEmotes() async throws -> [ChatEmote]
    func fetchChannelEmotes(twitchUserID: String) async throws -> [ChatEmote]
}
