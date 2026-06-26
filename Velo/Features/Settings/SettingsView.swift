import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let clientPolicy: TwitchClientPolicy
    @ObservedObject var sessionStore: TwitchSessionStore
    @ObservedObject var libraryStore: LibraryStore
    private let resetToken: Int
    @StateObject private var authViewModel: SettingsAuthViewModel
    @State private var verificationOpenFailed = false
    @Environment(\.openURL) private var openURL
    @Namespace private var settingsFocusScope

    init(
        settings: AppSettings,
        clientPolicy: TwitchClientPolicy,
        sessionStore: TwitchSessionStore,
        libraryStore: LibraryStore,
        sessionManager: TwitchAuthSessionManager,
        resetToken: Int = 0
    ) {
        self.settings = settings
        self.clientPolicy = clientPolicy
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.resetToken = resetToken
        _authViewModel = StateObject(wrappedValue: SettingsAuthViewModel(sessionManager: sessionManager))
    }

    private var canStartLogin: Bool {
        clientPolicy.canAuthorizeUser
    }

    private var isLinked: Bool {
        sessionStore.hasAPIAuth(using: clientPolicy) &&
        !sessionStore.twitchUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sessionStore.chatUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Twitch Account") {
                accountSection
            }

            Section("Emotes") {
                Toggle("7TV", isOn: $settings.enableSevenTV)
                Toggle("BetterTTV", isOn: $settings.enableBTTV)
                Toggle("FrankerFaceZ", isOn: $settings.enableFFZ)
            }

            Section("Chat") {
                Toggle("Show timestamps", isOn: $settings.showChatTimestamp)
                Toggle("Compact chat", isOn: $settings.compactChat)
                Toggle("Sync chat to video", isOn: $settings.syncChatToVideo)
            }
        }
        .id(resetToken)
        .focusScope(settingsFocusScope)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(isLinked ? sessionStore.chatUsername : "Not logged in")
                            .font(.title3.weight(.semibold))

                        accountStatusLabel
                    }

                    Text(isLinked ? "Followed channels and chat identity are enabled." : "Adds followed channels and your chat identity.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 24)

                accountActions
            }
            .padding(.vertical, 8)

            accountAuthorizationState
        }
    }

    @ViewBuilder
    private var accountStatusLabel: some View {
        if isLinked {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Optional", systemImage: "person.crop.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accountActions: some View {
        switch authViewModel.status {
        case .requestingCode, .authorizing:
            ProgressView()
                .controlSize(.large)

        case .waitingForAuthorization:
            EmptyView()

        case .linked:
            Button {
                startLogin(clearingExistingUser: true)
            } label: {
                Label("Switch Account", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

        case .failed:
            Button {
                startLogin()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStartLogin)

        case .idle:
            if isLinked {
                Button {
                    startLogin(clearingExistingUser: true)
                } label: {
                    Label("Switch Account", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    startLogin()
                } label: {
                    Label(canStartLogin ? "Log in with Twitch" : "Login Unavailable", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStartLogin)
            }
        }
    }

    @ViewBuilder
    private var accountAuthorizationState: some View {
        switch authViewModel.status {
        case .idle:
            if isLinked {
                logoutButton
            } else if !canStartLogin {
                AccountNotice(
                    title: "Twitch login unavailable in this build.",
                    symbol: "exclamationmark.triangle"
                )
            }

        case .requestingCode:
            AccountNotice(title: "Requesting login code", symbol: "clock")

        case .waitingForAuthorization(let grant):
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Go to \(activationSiteDisplayText(for: grant.verificationURI)) and enter")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text(grant.userCode)
                            .font(.system(size: 54, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 76)
                            .background(
                                RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                    }

                    Spacer(minLength: 24)

                    Button {
                        if let url = URL(string: grant.verificationURI) {
                            openURL(url) { accepted in
                                verificationOpenFailed = !accepted
                            }
                        } else {
                            verificationOpenFailed = true
                        }
                    } label: {
                        Label("Open Twitch", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 16) {
                    Button {
                        authViewModel.retryPolling()
                    } label: {
                        Label("Retry Polling", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if verificationOpenFailed {
                        Text("Open the URL on your phone or computer.")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 8)

        case .authorizing:
            AccountNotice(title: "Finalizing Twitch session", symbol: "checkmark.seal")

        case .linked:
            logoutButton

        case .failed(let message):
            AccountNotice(title: message, symbol: "exclamationmark.triangle", tint: .orange)
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            clearLocalUserSession()
            authViewModel.resetToIdle()
        } label: {
            VeloActionButtonLabel(
                title: "Log Out",
                systemImage: "rectangle.portrait.and.arrow.right",
                tint: .white
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private func startLogin(clearingExistingUser: Bool = false) {
        verificationOpenFailed = false
        if clearingExistingUser {
            clearLocalUserSession()
            authViewModel.resetToIdle()
        }
        Task { await authViewModel.startDeviceLogin() }
    }

    private func clearLocalUserSession() {
        sessionStore.clearUserSession()
        libraryStore.clearWatchHistory()
    }

    private func activationSiteDisplayText(for verificationURI: String) -> String {
        guard let url = URL(string: verificationURI), let host = url.host else {
            return "twitch.tv/activate"
        }

        let displayHost = host.replacingOccurrences(of: "www.", with: "")
        let path = url.path.isEmpty ? "/activate" : url.path
        return "\(displayHost)\(path)"
    }
}

private struct AccountNotice: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.vertical, 10)
    }
}
