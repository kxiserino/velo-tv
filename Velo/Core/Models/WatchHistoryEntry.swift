import Foundation

struct WatchHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let channelID: String
    let channelLogin: String
    let channelName: String
    let title: String
    let gameName: String
    let language: String
    let thumbnailTemplate: String
    let lastWatchedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case channelID
        case channelLogin
        case channelName
        case title
        case gameName
        case language
        case thumbnailTemplate
        case lastWatchedAt
    }

    init(stream: LiveStream, watchedAt: Date = Date()) {
        id = UUID()
        channelID = stream.channelID
        channelLogin = stream.channelLogin
        channelName = stream.channelName
        title = stream.title
        gameName = stream.gameName
        language = stream.language
        thumbnailTemplate = stream.thumbnailTemplate
        lastWatchedAt = watchedAt
    }

    func refreshing(with stream: LiveStream, watchedAt: Date = Date()) -> WatchHistoryEntry {
        WatchHistoryEntry(
            id: id,
            channelID: stream.channelID,
            channelLogin: stream.channelLogin,
            channelName: stream.channelName,
            title: stream.title,
            gameName: stream.gameName,
            language: stream.language,
            thumbnailTemplate: stream.thumbnailTemplate,
            lastWatchedAt: watchedAt
        )
    }

    var asStream: LiveStream {
        LiveStream(
            id: "history-\(channelID)",
            channelID: channelID,
            channelLogin: channelLogin,
            channelName: channelName,
            title: title,
            gameName: gameName,
            language: language,
            viewerCount: nil,
            thumbnailTemplate: thumbnailTemplate,
            startedAt: nil
        )
    }

    private init(
        id: UUID,
        channelID: String,
        channelLogin: String,
        channelName: String,
        title: String,
        gameName: String,
        language: String,
        thumbnailTemplate: String,
        lastWatchedAt: Date
    ) {
        self.id = id
        self.channelID = channelID
        self.channelLogin = channelLogin
        self.channelName = channelName
        self.title = title
        self.gameName = gameName
        self.language = language
        self.thumbnailTemplate = thumbnailTemplate
        self.lastWatchedAt = lastWatchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        channelID = try container.decode(String.self, forKey: .channelID)
        channelLogin = try container.decode(String.self, forKey: .channelLogin)
        channelName = try container.decode(String.self, forKey: .channelName)
        title = try container.decode(String.self, forKey: .title)
        gameName = try container.decode(String.self, forKey: .gameName)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        thumbnailTemplate = try container.decode(String.self, forKey: .thumbnailTemplate)
        lastWatchedAt = try container.decode(Date.self, forKey: .lastWatchedAt)
    }
}
