import Foundation

actor EmoteCatalogService {
    typealias PrefetchEmotes = @Sendable ([URL], Int) async -> Void

    private static let maxEmotesPerProviderScope = 1_500
    private static let maxMergedEmotes = 2_500
    private static let maxEmoteNameLength = 64
    private static let maxEmoteIDLength = 128

    private enum ProviderScope: Sendable {
        case global
        case channel(twitchUserID: String)
    }

    private let providers: [any EmoteProvider]
    private let prefetchEmotes: PrefetchEmotes

    private var mergedByName: [String: ChatEmote] = [:]
    private var globalCacheBySourceKey: [String: [ChatEmote]] = [:]
    private var channelCacheByKey: [String: [ChatEmote]] = [:]

    init(
        sevenTV: SevenTVService,
        bttv: BTTVService,
        ffz: FFZService,
        prefetchEmotes: @escaping PrefetchEmotes = { urls, maxCount in
            await EmoteImagePipeline.shared.prefetch(urls: urls, maxCount: maxCount)
        }
    ) {
        self.providers = [sevenTV, bttv, ffz]
        self.prefetchEmotes = prefetchEmotes
    }

    init(
        providers: [any EmoteProvider],
        prefetchEmotes: @escaping PrefetchEmotes = { urls, maxCount in
            await EmoteImagePipeline.shared.prefetch(urls: urls, maxCount: maxCount)
        }
    ) {
        self.providers = providers
        self.prefetchEmotes = prefetchEmotes
    }

    func prepare(
        twitchChannelID: String,
        includeSevenTV: Bool,
        includeBTTV: Bool,
        includeFFZ: Bool
    ) async {
        let enabledProviders = providers.filter { provider in
            switch provider.kind {
            case .sevenTV:
                return includeSevenTV
            case .bttv:
                return includeBTTV
            case .ffz:
                return includeFFZ
            }
        }
        let sourceKey = enabledProviders.map(\.kind.rawValue).sorted().joined(separator: "|")
        let channelKey = "\(twitchChannelID)|\(sourceKey)"

        let globalEmotes: [ChatEmote]
        if let cached = globalCacheBySourceKey[sourceKey] {
            globalEmotes = cached
        } else {
            let loaded = await loadGlobalEmotes(
                from: enabledProviders
            )
            globalCacheBySourceKey[sourceKey] = loaded
            globalEmotes = loaded
        }

        let channelEmotes: [ChatEmote]
        if let cached = channelCacheByKey[channelKey] {
            channelEmotes = cached
        } else {
            let loaded = await loadChannelEmotes(
                twitchChannelID: twitchChannelID,
                from: enabledProviders
            )
            channelCacheByKey[channelKey] = loaded
            channelEmotes = loaded
        }

        var merged: [String: ChatEmote] = [:]

        // Channel emotes override globals when names collide.
        for emote in globalEmotes.prefix(Self.maxMergedEmotes) {
            merged[emote.name] = emote
        }

        for emote in channelEmotes.prefix(Self.maxMergedEmotes) {
            guard merged.count < Self.maxMergedEmotes || merged[emote.name] != nil else { break }
            merged[emote.name] = emote
        }

        mergedByName = merged

        let warmupURLs = Array(Set(merged.values.map(\.imageURL))).prefix(160)
        let prefetchEmotes = prefetchEmotes
        Task.detached(priority: .utility) {
            await prefetchEmotes(Array(warmupURLs), 160)
        }
    }

    func tokenize(_ text: String, twitchEmotes: [TwitchChatEmoteRange] = []) -> [ChatSegment] {
        if twitchEmotes.isEmpty {
            return tokenizeByName(text)
        }

        let content = text as NSString
        let length = content.length
        let sortedRanges = twitchEmotes.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        var segments: [ChatSegment] = []
        var cursor = 0

        for emoteRange in sortedRanges {
            guard emoteRange.start >= cursor else { continue }
            guard emoteRange.start < length else { continue }
            guard emoteRange.end < length else { continue }

            if emoteRange.start > cursor {
                let prefixText = content.substring(with: NSRange(location: cursor, length: emoteRange.start - cursor))
                segments.append(contentsOf: tokenizeByName(prefixText))
            }

            let tokenLength = emoteRange.end - emoteRange.start + 1
            let emoteName = content.substring(with: NSRange(location: emoteRange.start, length: tokenLength))

            if let url = URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/\(emoteRange.emoteID)/default/dark/2.0") {
                let emote = ChatEmote(
                    id: "twitch-\(emoteRange.emoteID)-\(emoteRange.start)-\(emoteRange.end)",
                    name: emoteName,
                    provider: .twitch,
                    imageURL: url
                )
                segments.append(.emote(emote))
            } else {
                segments.append(.text(emoteName))
            }

            cursor = emoteRange.end + 1
        }

        if cursor < length {
            let suffix = content.substring(with: NSRange(location: cursor, length: length - cursor))
            segments.append(contentsOf: tokenizeByName(suffix))
        }

        return segments.isEmpty ? [.text(text)] : segments
    }

    private func tokenizeByName(_ text: String) -> [ChatSegment] {
        guard !text.isEmpty else { return [] }
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !tokens.isEmpty else { return [.text(text)] }

        var segments: [ChatSegment] = []

        for index in tokens.indices {
            let token = String(tokens[index])
            if let emote = mergedByName[token] {
                segments.append(.emote(emote))
            } else {
                segments.append(.text(token))
            }

            if index != tokens.index(before: tokens.endIndex) {
                segments.append(.text(" "))
            }
        }

        return segments
    }

    private func loadGlobalEmotes(
        from providers: [any EmoteProvider]
    ) async -> [ChatEmote] {
        await loadEmotes(from: providers, scope: .global)
    }

    private func loadChannelEmotes(
        twitchChannelID: String,
        from providers: [any EmoteProvider]
    ) async -> [ChatEmote] {
        await loadEmotes(from: providers, scope: .channel(twitchUserID: twitchChannelID))
    }

    private func loadEmotes(
        from providers: [any EmoteProvider],
        scope: ProviderScope
    ) async -> [ChatEmote] {
        var outputByProvider = Array(repeating: [ChatEmote](), count: providers.count)

        await withTaskGroup(of: (Int, [ChatEmote]).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    do {
                        let emotes: [ChatEmote]
                        switch scope {
                        case .global:
                            emotes = try await provider.fetchGlobalEmotes()
                        case .channel(let twitchUserID):
                            emotes = try await provider.fetchChannelEmotes(twitchUserID: twitchUserID)
                        }
                        return (index, Self.capped(emotes))
                    } catch {
                        return (index, [])
                    }
                }
            }

            for await (index, emotes) in group {
                outputByProvider[index] = emotes
            }
        }

        let output = outputByProvider.flatMap { $0 }
        return Array(output.prefix(Self.maxMergedEmotes))
    }

    nonisolated private static func capped(_ emotes: [ChatEmote]) -> [ChatEmote] {
        Array(
            emotes
                .lazy
                .filter { emote in
                    !emote.name.isEmpty &&
                    emote.name.count <= Self.maxEmoteNameLength &&
                    emote.id.count <= Self.maxEmoteIDLength &&
                    EmoteURLPolicy.isSafeRemoteImageURL(emote.imageURL)
                }
                .prefix(Self.maxEmotesPerProviderScope)
        )
    }
}
