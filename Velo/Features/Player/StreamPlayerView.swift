import SwiftUI
import AVKit

struct StreamPlayerView: View {
    private enum PlayerControl: Hashable {
        case playPause
        case goLive
        case favorite
        case home
    }

    let stream: LiveStream
    @ObservedObject var settings: AppSettings
    let clientPolicy: TwitchClientPolicy
    @ObservedObject var sessionStore: TwitchSessionStore
    let emoteCatalog: EmoteCatalogService
    @ObservedObject var libraryStore: LibraryStore
    let authSessionManager: TwitchAuthSessionManager
    let playbackService: TwitchPlaybackService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var playbackViewModel: PlaybackViewModel
    @State private var hasRecordedWatch = false
    @State private var controlsVisible = true
    @State private var dismissOnNextHiddenExit = false
    @State private var hideControlsTask: Task<Void, Never>?
    @FocusState private var focusedControl: PlayerControl?
    @Namespace private var playerFocusScope

    init(
        stream: LiveStream,
        settings: AppSettings,
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        emoteCatalog: EmoteCatalogService,
        chatBadgeService: TwitchChatBadgeService,
        libraryStore: LibraryStore,
        authSessionManager: TwitchAuthSessionManager,
        playbackService: TwitchPlaybackService
    ) {
        self.stream = stream
        self.settings = settings
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.emoteCatalog = emoteCatalog
        self.libraryStore = libraryStore
        self.authSessionManager = authSessionManager
        self.playbackService = playbackService

        _chatViewModel = StateObject(
            wrappedValue: ChatViewModel(
                stream: stream,
                preferences: settings,
                clientPolicy: clientPolicy,
                sessionStore: sessionStore,
                emoteCatalog: emoteCatalog,
                chatBadgeService: chatBadgeService,
                authSessionManager: authSessionManager
            )
        )

        _playbackViewModel = StateObject(
            wrappedValue: PlaybackViewModel(
                stream: stream,
                clientPolicy: clientPolicy,
                sessionStore: sessionStore,
                authSessionManager: authSessionManager,
                playbackService: playbackService
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let chatWidth = min(max(proxy.size.width * 0.28, 480), proxy.size.width * 0.34)

            HStack(alignment: .top, spacing: 0) {
                playbackSurface
                    .frame(width: max(proxy.size.width - chatWidth, 0), height: proxy.size.height)
                    .clipped()

                ChatPanelView(viewModel: chatViewModel, settings: settings)
                    .frame(width: chatWidth, height: proxy.size.height)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            async let connectChat: Void = chatViewModel.connectIfNeeded()
            async let loadPlayback: Void = playbackViewModel.loadIfNeeded()
            await loadPlayback

            if !hasRecordedWatch, playbackViewModel.state == .playing {
                libraryStore.recordWatch(stream)
                hasRecordedWatch = true
            }

            await connectChat
            showControlsTemporarily(focusPrimary: true)
        }
        .onMoveCommand { _ in
            showControlsTemporarily()
        }
        .onPlayPauseCommand {
            playbackViewModel.togglePlayPause()
            showControlsTemporarily()
        }
        .onChange(of: playbackViewModel.currentPlaybackDate) { _, playbackDate in
            chatViewModel.updatePlaybackDate(playbackDate)
        }
        .onChange(of: settings.syncChatToVideo) { _, _ in
            chatViewModel.chatSyncPreferenceDidChange()
        }
        .onExitCommand {
            handleExitCommand()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            chatViewModel.disconnect()
            playbackViewModel.stop()
        }
    }

    @ViewBuilder
    private var playbackSurface: some View {
        switch playbackViewModel.state {
        case .idle, .loading:
            ZStack {
                Color.black
                ProgressView("Loading stream")
            }

        case .playing:
            if let player = playbackViewModel.player {
                ZStack {
                    TVPlayerSurface(player: player)
                        .onAppear { player.play() }

                    if controlsVisible {
                        playerOverlayChrome
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: controlsVisible)
            } else {
                failedSurface(message: "Player was not initialized.")
            }

        case .failed(let message):
            failedSurface(message: message)
        }
    }

    private var playerOverlayChrome: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(stream.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(stream.channelName)
                        .font(.headline)
                        .foregroundStyle(Color.white)

                    if !stream.gameName.isEmpty {
                        Text(stream.gameName)
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.68))
                    }

                    if let viewers = stream.viewerCount {
                        Text("\(viewers.formatted()) watching")
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.68))
                    }

                    Text(playbackViewModel.latencyLabel)
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .monospacedDigit()

                    if let authorizationMode = playbackViewModel.authorizationMode {
                        PlaybackAuthorizationIndicator(mode: authorizationMode)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VeloUI.screenHorizontalPadding)
            .padding(.top, 36)
            .padding(.bottom, 22)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button {
                    playbackViewModel.togglePlayPause()
                    showControlsTemporarily(focusPrimary: true)
                } label: {
                    Label(
                        playbackViewModel.isPlaying ? "Pause" : "Play",
                        systemImage: playbackViewModel.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .focused($focusedControl, equals: .playPause)
                .prefersDefaultFocus(true, in: playerFocusScope)

                Button {
                    playbackViewModel.jumpToLive()
                    showControlsTemporarily(focusPrimary: false)
                } label: {
                    Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedControl, equals: .goLive)

                Button {
                    libraryStore.toggleFavorite(for: stream)
                    showControlsTemporarily(focusPrimary: false)
                } label: {
                    Label(
                        libraryStore.isFavorite(channelID: stream.channelID) ? "Favorited" : "Favorite",
                        systemImage: libraryStore.isFavorite(channelID: stream.channelID) ? "star.fill" : "star"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(libraryStore.isFavorite(channelID: stream.channelID) ? .yellow : .accentColor)
                .focused($focusedControl, equals: .favorite)

                Button {
                    dismiss()
                } label: {
                    Label("Home", systemImage: "house")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .focused($focusedControl, equals: .home)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, VeloUI.screenHorizontalPadding)
            .padding(.bottom, VeloUI.screenBottomPadding)
            .padding(.top, 46)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .focusScope(playerFocusScope)
            .focusSection()
        }
    }

    private func failedSurface(message: String) -> some View {
        ZStack {
            Color.black

            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.orange)

                Text("Playback Failed")
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)

                Button {
                    Task { await playbackViewModel.reload() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
        }
    }

    private func handleExitCommand() {
        if !controlsVisible {
            if dismissOnNextHiddenExit {
                dismiss()
            } else {
                showControlsTemporarily(focusPrimary: true)
            }
            return
        }

        if let focusedControl, focusedControl != .playPause {
            self.focusedControl = .playPause
            showControlsTemporarily(focusPrimary: true)
            return
        }

        hideControls(armedForDismiss: true)
    }

    private func showControlsTemporarily(focusPrimary: Bool = false) {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        dismissOnNextHiddenExit = false

        if focusPrimary {
            focusedControl = .playPause
        }

        hideControlsTask?.cancel()

        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    hideControls(armedForDismiss: false)
                }
            }
        }
    }

    private func hideControls(armedForDismiss: Bool) {
        hideControlsTask?.cancel()
        dismissOnNextHiddenExit = armedForDismiss
        focusedControl = nil

        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = false
        }
    }
}

private struct PlaybackAuthorizationIndicator: View {
    let mode: PlaybackAuthorizationMode

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.32), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .accessibilityLabel(accessibilityLabel)
    }

    private var systemImage: String {
        switch mode {
        case .authenticated:
            return "person.fill"
        case .anonymousFallback:
            return "person.crop.circle.badge.exclamationmark"
        case .anonymous:
            return "person.crop.circle"
        }
    }

    private var tint: Color {
        switch mode {
        case .authenticated:
            return .green
        case .anonymousFallback:
            return .orange
        case .anonymous:
            return Color.white.opacity(0.58)
        }
    }

    private var accessibilityLabel: String {
        switch mode {
        case .authenticated:
            return "Authenticated playback"
        case .anonymousFallback:
            return "Anonymous fallback playback"
        case .anonymous:
            return "Anonymous playback"
        }
    }
}

private struct TVPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.player = player
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }
}
