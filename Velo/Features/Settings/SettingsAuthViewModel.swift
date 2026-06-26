import Foundation
import Combine

@MainActor
final class SettingsAuthViewModel: ObservableObject {
    enum Status {
        case idle
        case requestingCode
        case waitingForAuthorization(TwitchDeviceGrant)
        case authorizing
        case linked(String)
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .requestingCode, .authorizing:
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var status: Status = .idle

    private let sessionManager: TwitchAuthSessionManager
    private var pollTask: Task<Void, Never>?

    init(sessionManager: TwitchAuthSessionManager) {
        self.sessionManager = sessionManager
    }

    deinit {
        pollTask?.cancel()
    }

    func startDeviceLogin() async {
        pollTask?.cancel()
        status = .requestingCode

        do {
            let grant = try await sessionManager.requestDeviceGrant()
            status = .waitingForAuthorization(grant)
            startPolling(grant)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func retryPolling() {
        guard case .waitingForAuthorization(let grant) = status else { return }
        pollTask?.cancel()
        startPolling(grant)
    }

    func resetToIdle() {
        pollTask?.cancel()
        status = .idle
    }

    private func startPolling(_ grant: TwitchDeviceGrant) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            let timeoutDate = Date().addingTimeInterval(TimeInterval(grant.expiresIn))

            while !Task.isCancelled, Date() < timeoutDate {
                do {
                    let result = try await sessionManager.pollDeviceGrant(deviceCode: grant.deviceCode)

                    switch result {
                    case .pending(let retryAfter):
                        try await Task.sleep(nanoseconds: UInt64(max(retryAfter, grant.interval)) * 1_000_000_000)
                    case .slowDown:
                        try await Task.sleep(nanoseconds: UInt64(grant.interval + 5) * 1_000_000_000)
                    case .authorized(let token):
                        status = .authorizing
                        let session = try await sessionManager.completeAuthorization(with: token)
                        status = .linked(session.login)
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    status = .failed(error.localizedDescription)
                    return
                }
            }

            status = .failed("Login code expired. Start again.")
        }
    }
}
