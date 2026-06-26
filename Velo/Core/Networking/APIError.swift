import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(code: Int)
    case decodingFailed
    case missingCredentials
    case missingUserID
    case serviceUnavailable(String)
    case playbackUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The request URL was invalid."
        case .invalidResponse:
            return "The service returned an invalid response."
        case .unauthorized:
            return "Authentication failed. Check your Twitch token and client ID."
        case .serverError(let code):
            return "The server returned status code \(code)."
        case .decodingFailed:
            return "The response could not be decoded."
        case .missingCredentials:
            return "Add your Twitch credentials in Settings to continue."
        case .missingUserID:
            return "Add your Twitch user ID in Settings to load followed channels."
        case .serviceUnavailable(let reason):
            return "Twitch is unavailable: \(reason)"
        case .playbackUnavailable(let reason):
            return "Playback is unavailable: \(reason)"
        }
    }
}
