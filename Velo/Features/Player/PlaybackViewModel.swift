import Foundation
import Combine
import AVKit
import CoreMedia

@MainActor
final class PlaybackViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var latencyLabel = "Latency --"
    @Published private(set) var authorizationMode: PlaybackAuthorizationMode?
    @Published private(set) var currentPlaybackDate: Date?

    private let stream: LiveStream
    private let clientPolicy: TwitchClientPolicy
    private let sessionStore: TwitchSessionStore
    private let authSessionManager: TwitchAuthSessionManager
    private let playbackService: TwitchPlaybackService
    private let preferredForwardBufferDuration: TimeInterval = 0.8
    private let targetLiveLatency: TimeInterval = 7
    private let maxLiveLatency: TimeInterval = 9
    private let liveEdgeOffset = CMTime(seconds: 6.5, preferredTimescale: 600)
    private var startupNudgeTask: Task<Void, Never>?
    private var latencyTask: Task<Void, Never>?
    private var lastLatencyCorrection = Date.distantPast
    private var isSeekingLatencyTarget = false

    init(
        stream: LiveStream,
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        authSessionManager: TwitchAuthSessionManager,
        playbackService: TwitchPlaybackService
    ) {
        self.stream = stream
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.authSessionManager = authSessionManager
        self.playbackService = playbackService
    }

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await reload()
    }

    func reload() async {
        startupNudgeTask?.cancel()
        latencyTask?.cancel()
        latencyLabel = "Latency --"
        authorizationMode = nil
        currentPlaybackDate = nil
        lastLatencyCorrection = .distantPast
        isSeekingLatencyTarget = false
        state = .loading

        do {
            // Playback can proceed anonymously; session refresh failures should not block video startup.
            try? await authSessionManager.ensureSessionValidity()
            let credentials = sessionStore.optionalCredentials(using: clientPolicy)

            let playback = try await playbackService.livePlaybackURL(
                channelLogin: stream.channelLogin,
                credentials: credentials
            )

            let item = AVPlayerItem(url: playback.url)
            item.preferredForwardBufferDuration = preferredForwardBufferDuration
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: targetLiveLatency, preferredTimescale: 600)

            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.play()

            self.player = player
            authorizationMode = playback.authorizationMode
            isPlaying = true
            state = .playing
            scheduleStartupNudge()
            startLatencyUpdates()
        } catch {
            player?.pause()
            player = nil
            isPlaying = false
            latencyLabel = "Latency --"
            authorizationMode = nil
            currentPlaybackDate = nil
            state = .failed(error.localizedDescription)
        }
    }

    func togglePlayPause() {
        guard let player else { return }

        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func jumpToLive() {
        guard
            let player,
            let item = player.currentItem
        else {
            return
        }

        if seekToTargetDate(item: item, player: player) {
            return
        }

        guard let range = item.seekableTimeRanges.last?.timeRangeValue else { return }
        let liveEdge = CMTimeAdd(range.start, range.duration)
        let target = CMTimeCompare(range.duration, liveEdgeOffset) > 0
            ? CMTimeSubtract(liveEdge, liveEdgeOffset)
            : range.start

        player.seek(
            to: target,
            toleranceBefore: CMTime(seconds: 0.25, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.25, preferredTimescale: 600)
        )
        player.play()
        isPlaying = true
    }

    func stop() {
        startupNudgeTask?.cancel()
        startupNudgeTask = nil
        latencyTask?.cancel()
        latencyTask = nil
        player?.pause()
        isPlaying = false
        latencyLabel = "Latency --"
        authorizationMode = nil
        currentPlaybackDate = nil
        isSeekingLatencyTarget = false
    }

    private func scheduleStartupNudge() {
        startupNudgeTask?.cancel()
        startupNudgeTask = Task { @MainActor in
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }

                if canSeekToLiveEdge {
                    jumpToLive()
                    return
                }

                player?.play()
            }
        }
    }

    private var canSeekToLiveEdge: Bool {
        guard
            let range = player?.currentItem?.seekableTimeRanges.last?.timeRangeValue,
            range.duration.seconds.isFinite,
            range.duration.seconds > 0
        else {
            return false
        }

        return true
    }

    private func startLatencyUpdates() {
        latencyTask?.cancel()
        latencyTask = Task { @MainActor in
            while !Task.isCancelled {
                let latency = updateLatencyLabel()
                correctLatencyIfNeeded(latency)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @discardableResult
    private func updateLatencyLabel() -> TimeInterval? {
        guard
            let currentDate = player?.currentItem?.currentDate(),
            currentDate.timeIntervalSince1970 > 0
        else {
            latencyLabel = "Latency --"
            currentPlaybackDate = nil
            return nil
        }

        currentPlaybackDate = currentDate
        let latency = max(0, Date().timeIntervalSince(currentDate))
        if latency < 10 {
            latencyLabel = String(format: "Latency %.1fs", latency)
        } else {
            latencyLabel = "Latency \(Int(latency.rounded()))s"
        }

        return latency
    }

    private func correctLatencyIfNeeded(_ latency: TimeInterval?) {
        guard
            let latency,
            latency > maxLiveLatency,
            let player,
            let item = player.currentItem,
            item.status == .readyToPlay,
            !isSeekingLatencyTarget
        else {
            return
        }

        guard Date().timeIntervalSince(lastLatencyCorrection) > 2 else { return }

        let correction = latency - targetLiveLatency
        guard correction > 0.75 else { return }

        if seekToTargetDate(item: item, player: player) {
            return
        }

        let currentTime = player.currentTime()
        let target = CMTimeAdd(
            currentTime,
            CMTime(seconds: correction, preferredTimescale: 600)
        )

        if let range = item.seekableTimeRanges.last?.timeRangeValue {
            let liveTarget = CMTimeSubtract(
                CMTimeAdd(range.start, range.duration),
                liveEdgeOffset
            )
            let clampedTarget = CMTimeMinimum(target, liveTarget)
            seekToLatencyTarget(clampedTarget, player: player)
        } else {
            seekToLatencyTarget(target, player: player)
        }
    }

    private func seekToTargetDate(item: AVPlayerItem, player: AVPlayer) -> Bool {
        let targetDate = Date().addingTimeInterval(-targetLiveLatency)
        guard
            let currentDate = item.currentDate(),
            abs(currentDate.timeIntervalSince(targetDate)) > 0.75
        else {
            return false
        }

        isSeekingLatencyTarget = true
        lastLatencyCorrection = Date()
        item.seek(to: targetDate) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSeekingLatencyTarget = false
                self?.player?.play()
                self?.isPlaying = true
            }
        }
        player.play()
        isPlaying = true
        return true
    }

    private func seekToLatencyTarget(_ target: CMTime, player: AVPlayer) {
        isSeekingLatencyTarget = true
        lastLatencyCorrection = Date()
        player.seek(
            to: target,
            toleranceBefore: CMTime(seconds: 0.25, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.25, preferredTimescale: 600)
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSeekingLatencyTarget = false
                self?.player?.play()
                self?.isPlaying = true
            }
        }
        player.play()
        isPlaying = true
    }
}
