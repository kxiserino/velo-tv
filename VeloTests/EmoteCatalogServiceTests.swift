import Foundation
import Testing
@testable import Velo

@Suite("Emote catalog")
struct EmoteCatalogServiceTests {
    @Test("Does not call disabled providers")
    func disabledProvidersAreNotCalled() async {
        let enabledProbe = ProviderProbe()
        let disabledProbe = ProviderProbe()
        let catalog = EmoteCatalogService(
            providers: [
                MockEmoteProvider(kind: .sevenTV, probe: enabledProbe, global: [Self.emote(id: "enabled", name: "Enabled")]),
                MockEmoteProvider(kind: .bttv, probe: disabledProbe, global: [Self.emote(id: "disabled", name: "Disabled")])
            ],
            prefetchEmotes: { _, _ in }
        )

        await catalog.prepare(
            twitchChannelID: "channel",
            includeSevenTV: true,
            includeBTTV: false,
            includeFFZ: false
        )

        #expect(await enabledProbe.globalCalls == 1)
        #expect(await enabledProbe.channelCalls == 1)
        #expect(await disabledProbe.globalCalls == 0)
        #expect(await disabledProbe.channelCalls == 0)
    }

    @Test("Merges enabled providers and lets channel emotes override globals")
    func channelOverridesGlobalByName() async throws {
        let catalog = EmoteCatalogService(
            providers: [
                MockEmoteProvider(
                    kind: .sevenTV,
                    global: [Self.emote(id: "global-kappa", name: "Kappa"), Self.emote(id: "global-wave", name: "Wave")],
                    channel: [Self.emote(id: "channel-kappa", name: "Kappa")]
                ),
                MockEmoteProvider(
                    kind: .ffz,
                    global: [Self.emote(id: "global-pop", name: "Pop")]
                )
            ],
            prefetchEmotes: { _, _ in }
        )

        await catalog.prepare(
            twitchChannelID: "channel",
            includeSevenTV: true,
            includeBTTV: false,
            includeFFZ: true
        )

        let segments = await catalog.tokenize("Kappa Wave Pop")

        let emotes = segments.compactMap { segment -> ChatEmote? in
            guard case .emote(let emote) = segment else { return nil }
            return emote
        }

        #expect(emotes.map { $0.id } == ["channel-kappa", "global-wave", "global-pop"])
    }

    @Test("Filters unsafe URLs and oversized emote metadata")
    func filtersUnsafeAndOversizedEmotes() async {
        let catalog = EmoteCatalogService(
            providers: [
                MockEmoteProvider(
                    kind: .sevenTV,
                    global: [
                        Self.emote(id: "safe", name: "Safe"),
                        Self.emote(id: "unsafe", name: "Unsafe", url: URL(string: "http://localhost/emote.png")!),
                        Self.emote(id: String(repeating: "x", count: 129), name: "TooLong")
                    ]
                )
            ],
            prefetchEmotes: { _, _ in }
        )

        await catalog.prepare(
            twitchChannelID: "channel",
            includeSevenTV: true,
            includeBTTV: false,
            includeFFZ: false
        )

        let segments = await catalog.tokenize("Safe Unsafe TooLong")
        let emoteNames = segments.compactMap { segment -> String? in
            guard case .emote(let emote) = segment else { return nil }
            return emote.name
        }

        #expect(emoteNames == ["Safe"])
    }

    @Test("Preserves zero-width emote metadata")
    func preservesZeroWidthEmoteMetadata() async {
        let catalog = EmoteCatalogService(
            providers: [
                MockEmoteProvider(
                    kind: .sevenTV,
                    global: [
                        Self.emote(id: "base", name: "Base"),
                        Self.emote(id: "overlay", name: "Overlay", isZeroWidth: true)
                    ]
                )
            ],
            prefetchEmotes: { _, _ in }
        )

        await catalog.prepare(
            twitchChannelID: "channel",
            includeSevenTV: true,
            includeBTTV: false,
            includeFFZ: false
        )

        let segments = await catalog.tokenize("Base Overlay")
        let emotes = segments.compactMap { segment -> ChatEmote? in
            guard case .emote(let emote) = segment else { return nil }
            return emote
        }

        #expect(emotes.map(\.name) == ["Base", "Overlay"])
        #expect(emotes.map(\.isZeroWidth) == [false, true])
    }

    @Test("Keeps large 7TV-style channel catalogs")
    func keepsLargeChannelEmoteCatalogs() async {
        let channelEmotes = (0..<420).map { index in
            Self.emote(id: "channel-\(index)", name: "SevenTV\(index)")
        }
        let catalog = EmoteCatalogService(
            providers: [
                MockEmoteProvider(kind: .sevenTV, channel: channelEmotes)
            ],
            prefetchEmotes: { _, _ in }
        )

        await catalog.prepare(
            twitchChannelID: "channel",
            includeSevenTV: true,
            includeBTTV: false,
            includeFFZ: false
        )

        let segments = await catalog.tokenize("SevenTV399")
        let emotes = segments.compactMap { segment -> ChatEmote? in
            guard case .emote(let emote) = segment else { return nil }
            return emote
        }

        #expect(emotes.map(\.name) == ["SevenTV399"])
    }

    private actor ProviderProbe {
        private(set) var globalCalls = 0
        private(set) var channelCalls = 0

        func recordGlobalCall() {
            globalCalls += 1
        }

        func recordChannelCall() {
            channelCalls += 1
        }
    }

    private struct MockEmoteProvider: EmoteProvider {
        nonisolated let kind: EmoteProviderKind
        let probe: ProviderProbe?
        let global: [ChatEmote]
        let channel: [ChatEmote]

        init(
            kind: EmoteProviderKind,
            probe: ProviderProbe? = nil,
            global: [ChatEmote] = [],
            channel: [ChatEmote] = []
        ) {
            self.kind = kind
            self.probe = probe
            self.global = global
            self.channel = channel
        }

        func fetchGlobalEmotes() async throws -> [ChatEmote] {
            await probe?.recordGlobalCall()
            return global
        }

        func fetchChannelEmotes(twitchUserID: String) async throws -> [ChatEmote] {
            await probe?.recordChannelCall()
            return channel
        }
    }

    private static func emote(
        id: String,
        name: String,
        url: URL = URL(string: "https://example.com/emote.png")!,
        isZeroWidth: Bool = false
    ) -> ChatEmote {
        ChatEmote(id: id, name: name, provider: .sevenTV, imageURL: url, isZeroWidth: isZeroWidth)
    }
}
