import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case live
        case failed(String)

        var displayLabel: String {
            switch self {
            case .idle:
                return "Idle"
            case .connecting:
                return "Connecting"
            case .live:
                return "Live chat"
            case .failed:
                return "Disconnected"
            }
        }
    }

    @Published private(set) var messages: [RenderableChatMessage] = []
    @Published private(set) var pinnedMessage: RenderablePinnedChatMessage?
    @Published private(set) var connectionState: ConnectionState = .idle

    private let stream: LiveStream
    private let preferences: AppSettings
    private let clientPolicy: TwitchClientPolicy
    private let sessionStore: TwitchSessionStore
    private let emoteCatalog: EmoteCatalogService
    private let chatBadgeService: TwitchChatBadgeService
    private let authSessionManager: TwitchAuthSessionManager
    private let ircClient = TwitchIRCClient()

    private var consumeTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pendingMessages: [RenderableChatMessage] = []
    private var currentPlaybackDate: Date?
    private var isConnected = false
    private var connectionGeneration = 0
    private let maxVisibleMessages = 160
    private let minReconnectDelayNs: UInt64 = 1_500_000_000
    private let maxReconnectDelayNs: UInt64 = 10_000_000_000
    private let syncedChatTolerance: TimeInterval = 0.35

    init(
        stream: LiveStream,
        preferences: AppSettings,
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        emoteCatalog: EmoteCatalogService,
        chatBadgeService: TwitchChatBadgeService,
        authSessionManager: TwitchAuthSessionManager
    ) {
        self.stream = stream
        self.preferences = preferences
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.emoteCatalog = emoteCatalog
        self.chatBadgeService = chatBadgeService
        self.authSessionManager = authSessionManager
    }

    deinit {
        consumeTask?.cancel()
        flushTask?.cancel()
        let ircClient = ircClient
        Task {
            await ircClient.disconnect()
        }
    }

    func connectIfNeeded() async {
        guard !isConnected else { return }
        isConnected = true
        connectionGeneration += 1
        let generation = connectionGeneration
        connectionState = .connecting

        await emoteCatalog.prepare(
            twitchChannelID: stream.channelID,
            includeSevenTV: preferences.enableSevenTV,
            includeBTTV: preferences.enableBTTV,
            includeFFZ: preferences.enableFFZ
        )

        guard !Task.isCancelled, isConnected, generation == connectionGeneration else { return }

        if sessionStore.hasChatCredentials(using: clientPolicy) {
            do {
                try await authSessionManager.ensureSessionValidity()
            } catch {
                connectionState = .failed(error.localizedDescription)
                isConnected = false
                return
            }

            guard !Task.isCancelled, isConnected, generation == connectionGeneration else { return }
            if let credentials = sessionStore.optionalCredentials(using: clientPolicy) {
                await chatBadgeService.prepare(
                    channelID: stream.channelID,
                    credentials: credentials
                )
            }
        }

        guard !Task.isCancelled, isConnected, generation == connectionGeneration else { return }
        await startLiveChat(generation: generation)
    }

    func disconnect() {
        consumeTask?.cancel()
        consumeTask = nil
        flushTask?.cancel()
        flushTask = nil
        pendingMessages.removeAll()
        currentPlaybackDate = nil
        isConnected = false
        connectionGeneration += 1
        connectionState = .idle
        pinnedMessage = nil

        Task {
            await ircClient.disconnect()
        }
    }

    func updatePlaybackDate(_ playbackDate: Date?) {
        currentPlaybackDate = playbackDate
        guard preferences.syncChatToVideo else { return }
        scheduleFlush(after: 0)
    }

    func chatSyncPreferenceDidChange() {
        flushTask?.cancel()
        flushTask = nil
        scheduleFlush(after: 0)
    }

    private func startLiveChat(generation: Int) async {
        consumeTask?.cancel()
        consumeTask = Task {
            var reconnectDelay = minReconnectDelayNs

            while !Task.isCancelled, isConnected, generation == connectionGeneration {
                let streamHandle = await ircClient.connect(
                    channelLogin: stream.channelLogin,
                    identity: chatIdentity
                )

                connectionState = .live
                var receivedAnyMessage = false

                do {
                    for try await event in streamHandle {
                        await handle(event)
                        receivedAnyMessage = true
                        reconnectDelay = minReconnectDelayNs
                    }
                } catch {
                    connectionState = .failed(error.localizedDescription)
                    if let apiError = error as? APIError, case .unauthorized = apiError {
                        isConnected = false
                        return
                    }
                }

                guard !Task.isCancelled, isConnected, generation == connectionGeneration else { return }
                connectionState = .connecting

                if receivedAnyMessage {
                    reconnectDelay = minReconnectDelayNs
                }

                try? await Task.sleep(nanoseconds: reconnectDelay)
                reconnectDelay = min(reconnectDelay * 2, maxReconnectDelayNs)
            }
        }
    }

    private func handle(_ event: ChatEvent) async {
        switch event {
        case .message(let message):
            await append(message)
        case .pinned(let message):
            await pin(message)
        case .clearMessage(let id):
            clearMessage(id: id)
        case .clearChat(let login):
            clearChat(login: login)
        }
    }

    private func pin(_ message: PinnedChatMessage) async {
        let segments = await emoteCatalog.tokenize(
            message.text,
            twitchEmotes: message.twitchEmotes
        )

        let renderable = RenderablePinnedChatMessage(
            id: message.id,
            senderLogin: message.senderLogin,
            senderDisplayName: message.senderDisplayName,
            timestamp: message.timestamp,
            colorHex: message.colorHex,
            accentHex: message.accentHex,
            segments: segments
        )

        prefetchEmotes(in: segments)
        pinnedMessage = renderable
    }

    private func append(_ message: ChatMessage) async {
        async let tokenizedSegments = emoteCatalog.tokenize(
            message.text,
            twitchEmotes: message.twitchEmotes
        )

        let segments = await tokenizedSegments
        let badges = await renderableBadges(for: message.badges)

        let renderable = RenderableChatMessage(
            ircID: message.ircID,
            senderLogin: message.senderLogin,
            senderDisplayName: message.senderDisplayName,
            timestamp: message.timestamp,
            colorHex: message.colorHex,
            badges: badges,
            segments: segments
        )

        prefetchEmotes(in: segments)
        enqueue(renderable)
    }

    private var chatIdentity: TwitchIRCClient.Identity {
        guard sessionStore.hasChatCredentials(using: clientPolicy) else { return .anonymous }

        return .authenticated(
            username: sessionStore.chatUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            oauthToken: sessionStore.cleanOAuthToken
        )
    }

    private func renderableBadges(for badges: [ChatBadge]) async -> [RenderableChatBadge] {
        guard let credentials = sessionStore.optionalCredentials(using: clientPolicy) else { return [] }

        return await chatBadgeService.renderableBadges(
            for: badges,
            channelID: stream.channelID,
            credentials: credentials
        )
    }

    private func enqueue(_ message: RenderableChatMessage) {
        pendingMessages.append(message)
        scheduleFlush(after: preferences.syncChatToVideo ? 0 : 0.09)
    }

    private func scheduleFlush(after delay: TimeInterval) {
        guard flushTask == nil else { return }

        flushTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            flushTask = nil
            flushPendingMessages()
        }
    }

    private func clearMessage(id: String) {
        pendingMessages.removeAll { $0.ircID == id }
        messages.removeAll { $0.ircID == id }
        if pinnedMessage?.id == id {
            pinnedMessage = nil
        }
    }

    private func clearChat(login: String?) {
        guard let login else {
            pendingMessages.removeAll(keepingCapacity: true)
            messages.removeAll(keepingCapacity: true)
            pinnedMessage = nil
            return
        }

        pendingMessages.removeAll { $0.senderLogin == login }
        messages.removeAll { $0.senderLogin == login }
        if pinnedMessage?.senderLogin == login {
            pinnedMessage = nil
        }
    }

    private func flushPendingMessages() {
        guard !pendingMessages.isEmpty else { return }

        let readyMessages: [RenderableChatMessage]

        if preferences.syncChatToVideo {
            guard let currentPlaybackDate else {
                scheduleFlush(after: 0.25)
                return
            }

            let visibleUntil = currentPlaybackDate.addingTimeInterval(syncedChatTolerance)
            readyMessages = pendingMessages.filter { $0.timestamp <= visibleUntil }
            pendingMessages.removeAll { $0.timestamp <= visibleUntil }
        } else {
            readyMessages = pendingMessages
            pendingMessages.removeAll(keepingCapacity: true)
        }

        guard !readyMessages.isEmpty else {
            scheduleFlush(after: 0.25)
            return
        }

        messages.append(contentsOf: readyMessages)

        if messages.count > maxVisibleMessages {
            messages.removeFirst(messages.count - maxVisibleMessages)
        }

        if !pendingMessages.isEmpty {
            scheduleFlush(after: 0.25)
        }
    }

    private func prefetchEmotes(in segments: [ChatSegment]) {
        let emoteURLs = segments.compactMap { segment -> URL? in
            guard case .emote(let emote) = segment else { return nil }
            return emote.imageURL
        }

        if !emoteURLs.isEmpty {
            Task.detached(priority: .utility) {
                await EmoteImagePipeline.shared.prefetch(urls: emoteURLs, maxCount: 24)
            }
        }
    }
}
