import Foundation

struct LiveStream: Identifiable, Hashable {
    let id: String
    let channelID: String
    let channelLogin: String
    let channelName: String
    let title: String
    let gameName: String
    let language: String
    let viewerCount: Int?
    let thumbnailTemplate: String
    let startedAt: Date?

    func thumbnailURL(width: Int, height: Int) -> URL? {
        let template = thumbnailTemplate
            .replacingOccurrences(of: "{width}", with: String(width))
            .replacingOccurrences(of: "{height}", with: String(height))

        return URL(string: template)
    }
}
