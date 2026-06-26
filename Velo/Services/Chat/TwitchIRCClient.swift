import Foundation

actor TwitchIRCClient {
    enum Identity: Sendable {
        case authenticated(username: String, oauthToken: String)
        case anonymous

        var username: String {
            switch self {
            case .authenticated(let username, _):
                username
            case .anonymous:
                "justinfan\(Int.random(in: 10_000...999_999))"
            }
        }
    }

    private enum IRCError: Error {
        case reconnectRequested
        case connectionClosed
    }

    private var socket: URLSessionWebSocketTask?

    func connect(
        channelLogin: String,
        identity: Identity
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.start(
                        channelLogin: channelLogin,
                        identity: identity,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await self.disconnect()
                }
            }
        }
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func start(
        channelLogin: String,
        identity: Identity,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        disconnect()

        guard let url = URL(string: "wss://irc-ws.chat.twitch.tv:443") else {
            throw APIError.invalidURL
        }

        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        self.socket = socket

        try await sendRaw("CAP REQ :twitch.tv/tags twitch.tv/commands")

        switch identity {
        case .authenticated(let username, let oauthToken):
            try await sendRaw("PASS oauth:\(oauthToken)")
            try await sendRaw("NICK \(username)")
        case .anonymous:
            try await sendRaw("PASS SCHMOOPIIE")
            try await sendRaw("NICK \(identity.username)")
        }

        try await sendRaw("JOIN #\(channelLogin.lowercased())")

        try await receiveLoop(continuation: continuation)
    }

    private func receiveLoop(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        while !Task.isCancelled, let socket {
            let incoming = try await socket.receive()

            switch incoming {
            case .string(let text):
                let lines = text.components(separatedBy: "\r\n")
                for line in lines where !line.isEmpty {
                    let command = commandName(in: line)

                    if command == "PING" {
                        let payload = String(line.dropFirst(5))
                        try await sendRaw("PONG \(payload)")
                        continue
                    }

                    if command == "NOTICE", isAuthenticationFailure(line) {
                        throw APIError.unauthorized
                    }

                    if command == "RECONNECT" {
                        throw IRCError.reconnectRequested
                    }

                    if command == "001" {
                        continue
                    }

                    if let message = parsePrivmsg(line) {
                        continuation.yield(.message(message))
                        continue
                    }

                    if let clearEvent = parseClearMessage(line) {
                        continuation.yield(clearEvent)
                        continue
                    }

                    if let clearEvent = parseClearChat(line) {
                        continuation.yield(clearEvent)
                        continue
                    }

                    if let message = parseUsernotice(line) {
                        continuation.yield(.pinned(message))
                    }
                }
            case .data:
                continue
            @unknown default:
                continue
            }
        }

        if Task.isCancelled {
            continuation.finish()
            return
        }

        throw IRCError.connectionClosed
    }

    private func sendRaw(_ command: String) async throws {
        guard let socket else {
            throw APIError.invalidResponse
        }

        try await socket.send(.string(command))
    }

    private func commandName(in line: String) -> String? {
        var remainder = line[...]

        if remainder.first == "@" {
            guard let space = remainder.firstIndex(of: " ") else { return nil }
            remainder = remainder[remainder.index(after: space)...]
        }

        if remainder.first == ":" {
            guard let space = remainder.firstIndex(of: " ") else { return nil }
            remainder = remainder[remainder.index(after: space)...]
        }

        let commandEnd = remainder.firstIndex(of: " ") ?? remainder.endIndex
        guard commandEnd > remainder.startIndex else { return nil }
        return String(remainder[..<commandEnd]).uppercased()
    }

    private func isAuthenticationFailure(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("login authentication failed") ||
            lowercased.contains("improperly formatted auth")
    }

    private func parseUsernotice(_ line: String) -> PinnedChatMessage? {
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)

        guard
            let match = Self.usernoticeRegex.firstMatch(in: line, options: [], range: nsrange),
            let tagsRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        let tags = parseTags(String(line[tagsRange]))
        let noticeID = tags["msg-id"] ?? ""
        guard isPinnedStyleNotice(noticeID) else { return nil }

        let sender = Range(match.range(at: 2), in: line).map { String(line[$0]) }
        let messageText = Range(match.range(at: 3), in: line).map { String(line[$0]) }
        let text = firstNonEmpty(messageText, tags["system-msg"])
        guard !text.isEmpty else { return nil }

        let displayName = firstNonEmpty(tags["display-name"], sender, tags["login"], "Twitch")
        let senderLogin = firstNonEmpty(sender, tags["login"]).lowercased()

        return PinnedChatMessage(
            id: tags["id"] ?? UUID().uuidString,
            senderLogin: senderLogin.isEmpty ? nil : senderLogin,
            senderDisplayName: displayName,
            text: text,
            timestamp: timestamp(from: tags["tmi-sent-ts"]),
            colorHex: tags["color"],
            accentHex: Self.announcementColorHex(for: tags["msg-param-color"]),
            twitchEmotes: parseTwitchEmoteRanges(tags["emotes"] ?? "")
        )
    }

    private func isPinnedStyleNotice(_ noticeID: String) -> Bool {
        let lowercased = noticeID.lowercased()
        return lowercased == "announcement" ||
            lowercased.contains("pinned") ||
            lowercased.contains("pin")
    }

    private func firstNonEmpty(_ candidates: String?...) -> String {
        candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func timestamp(from milliseconds: String?) -> Date {
        guard
            let milliseconds,
            let value = Double(milliseconds)
        else {
            return Date()
        }

        return Date(timeIntervalSince1970: value / 1_000)
    }

    private func parsePrivmsg(_ line: String) -> ChatMessage? {
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)

        guard
            let match = Self.privmsgRegex.firstMatch(in: line, options: [], range: nsrange),
            let senderRange = Range(match.range(at: 2), in: line),
            let messageRange = Range(match.range(at: 3), in: line)
        else {
            return nil
        }

        let sender = String(line[senderRange])
        let text = String(line[messageRange])

        let tags: [String: String]
        if let tagsRange = Range(match.range(at: 1), in: line) {
            tags = parseTags(String(line[tagsRange]))
        } else {
            tags = [:]
        }

        let displayName = tags["display-name"]?.isEmpty == false ? tags["display-name"]! : sender
        let color = tags["color"]
        let badges = parseBadges(tags["badges"] ?? "")
        let twitchEmotes = parseTwitchEmoteRanges(tags["emotes"] ?? "")

        return ChatMessage(
            ircID: tags["id"],
            senderLogin: sender.lowercased(),
            senderDisplayName: displayName,
            text: text,
            timestamp: timestamp(from: tags["tmi-sent-ts"]),
            colorHex: color,
            badges: badges,
            twitchEmotes: twitchEmotes
        )
    }

    private func parseClearMessage(_ line: String) -> ChatEvent? {
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)

        guard
            let match = Self.clearMessageRegex.firstMatch(in: line, options: [], range: nsrange),
            let tagsRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        let tags = parseTags(String(line[tagsRange]))
        guard let id = tags["target-msg-id"], !id.isEmpty else { return nil }
        return .clearMessage(id: id)
    }

    private func parseClearChat(_ line: String) -> ChatEvent? {
        let nsrange = NSRange(line.startIndex..<line.endIndex, in: line)

        guard let match = Self.clearChatRegex.firstMatch(in: line, options: [], range: nsrange) else {
            return nil
        }

        let login = Range(match.range(at: 2), in: line)
            .map { String(line[$0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { $0.isEmpty ? nil : $0 }

        return .clearChat(login: login)
    }

    private func parseBadges(_ raw: String) -> [ChatBadge] {
        guard !raw.isEmpty else { return [] }

        return raw.split(separator: ",").compactMap { entry in
            let components = entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = components.first, !name.isEmpty else { return nil }

            return ChatBadge(
                name: String(name),
                version: components.count > 1 ? String(components[1]) : ""
            )
        }
    }

    private func parseTags(_ raw: String) -> [String: String] {
        var output: [String: String] = [:]

        for pair in raw.split(separator: ";") {
            let split = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = split.first else { continue }
            let value = split.count > 1 ? String(split[1]) : ""
            output[String(key)] = unescapeTagValue(value)
        }

        return output
    }

    private func unescapeTagValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s", with: " ")
            .replacingOccurrences(of: "\\:", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\r", with: "")
            .replacingOccurrences(of: "\\n", with: "")
    }

    private func parseTwitchEmoteRanges(_ raw: String) -> [TwitchChatEmoteRange] {
        guard !raw.isEmpty else { return [] }

        var output: [TwitchChatEmoteRange] = []

        for entry in raw.split(separator: "/") {
            let components = entry.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard components.count == 2 else { continue }

            let emoteID = String(components[0])
            let positions = components[1]

            for rangePart in positions.split(separator: ",") {
                let bounds = rangePart.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                guard bounds.count == 2 else { continue }
                guard let start = Int(bounds[0]), let end = Int(bounds[1]), end >= start else { continue }

                output.append(
                    TwitchChatEmoteRange(
                        emoteID: emoteID,
                        start: start,
                        end: end
                    )
                )
            }
        }

        return output.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }
    }

    private static let privmsgRegex = try! NSRegularExpression(
        pattern: "^(?:@([^ ]+) )?:([^!]+)![^ ]+ PRIVMSG #[^ ]+ :(.*)$",
        options: []
    )

    private static let usernoticeRegex = try! NSRegularExpression(
        pattern: "^(?:@([^ ]+) )?(?::([^! ]+)![^ ]+ |:tmi\\.twitch\\.tv )USERNOTICE #[^ ]+(?: :(.*))?$",
        options: []
    )

    private static let clearMessageRegex = try! NSRegularExpression(
        pattern: "^(?:@([^ ]+) )?:tmi\\.twitch\\.tv CLEARMSG #[^ ]+(?: :.*)?$",
        options: []
    )

    private static let clearChatRegex = try! NSRegularExpression(
        pattern: "^(?:@([^ ]+) )?:tmi\\.twitch\\.tv CLEARCHAT #[^ ]+(?: :([^ ]+))?$",
        options: []
    )

    private static func announcementColorHex(for rawColor: String?) -> String {
        switch rawColor?.uppercased() {
        case "BLUE":
            return "#1F69FF"
        case "GREEN":
            return "#00AD8E"
        case "ORANGE":
            return "#FF8700"
        case "PURPLE":
            return "#9146FF"
        case "PRIMARY":
            return "#9146FF"
        default:
            return "#9146FF"
        }
    }
}
