import Foundation

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let ircID: String?
    let senderLogin: String
    let senderDisplayName: String
    let text: String
    let timestamp: Date
    let colorHex: String?
    let badges: [ChatBadge]
    let twitchEmotes: [TwitchChatEmoteRange]
}

struct ChatBadge: Hashable, Identifiable {
    var id: String { "\(name)-\(version)" }
    let name: String
    let version: String

    var displayLabel: String {
        switch name {
        case "broadcaster":
            return "Broadcaster"
        case "moderator":
            return "Mod"
        case "vip":
            return "VIP"
        case "subscriber":
            return "Sub"
        case "founder":
            return "Founder"
        case "partner":
            return "Partner"
        case "premium":
            return "Prime"
        case "staff":
            return "Staff"
        case "artist-badge":
            return "Artist"
        default:
            return name
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
}

struct RenderableChatBadge: Hashable, Identifiable, Sendable {
    var id: String { "\(name)-\(version)" }
    let name: String
    let version: String
    let title: String
    let imageURL: URL
}

enum ChatEvent: Hashable {
    case message(ChatMessage)
    case pinned(PinnedChatMessage)
    case clearChat(login: String?)
    case clearMessage(id: String)
}

struct PinnedChatMessage: Identifiable, Hashable {
    let id: String
    let senderLogin: String?
    let senderDisplayName: String
    let text: String
    let timestamp: Date
    let colorHex: String?
    let accentHex: String?
    let twitchEmotes: [TwitchChatEmoteRange]
}

struct ChatEmote: Hashable, Sendable {
    enum Provider: String, Hashable, Sendable {
        case twitch = "Twitch"
        case sevenTV = "7TV"
        case bttv = "BTTV"
        case ffz = "FFZ"
    }

    let id: String
    let name: String
    let provider: Provider
    let imageURL: URL
    var isZeroWidth = false
}

enum ChatSegment: Hashable, Sendable {
    case text(String)
    case emote(ChatEmote)
}

struct TwitchChatEmoteRange: Hashable {
    let emoteID: String
    let start: Int
    let end: Int
}

struct RenderableChatMessage: Identifiable {
    let id = UUID()
    let ircID: String?
    let senderLogin: String
    let senderDisplayName: String
    let timestamp: Date
    let colorHex: String?
    let badges: [RenderableChatBadge]
    let segments: [ChatSegment]
}

struct RenderablePinnedChatMessage: Identifiable {
    let id: String
    let senderLogin: String?
    let senderDisplayName: String
    let timestamp: Date
    let colorHex: String?
    let accentHex: String?
    let segments: [ChatSegment]
}
