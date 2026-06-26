import Foundation

nonisolated struct TwitchDeviceGrant: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

nonisolated struct TwitchOAuthToken: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: [String]
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

nonisolated struct TwitchValidatedSession: Decodable {
    let clientID: String
    let login: String
    let userID: String
    let scopes: [String]
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case login
        case userID = "user_id"
        case scopes
        case expiresIn = "expires_in"
    }
}

enum TwitchDevicePollResult {
    case pending(retryAfter: Int)
    case slowDown
    case authorized(TwitchOAuthToken)
}

enum TwitchAuthError: LocalizedError {
    case missingClientID
    case authorizationDenied
    case deviceCodeExpired
    case invalidDeviceCode
    case invalidRefreshToken
    case invalidToken
    case network
    case malformedResponse
    case unexpectedStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Twitch login is unavailable in this build."
        case .authorizationDenied:
            return "Authorization was denied in Twitch."
        case .deviceCodeExpired:
            return "The login code expired. Start login again."
        case .invalidDeviceCode:
            return "The device code is invalid. Start login again."
        case .invalidRefreshToken:
            return "The refresh token is no longer valid. Re-authenticate."
        case .invalidToken:
            return "The Twitch access token is invalid. Re-authenticate."
        case .network:
            return "Network request failed."
        case .malformedResponse:
            return "Twitch returned an unexpected response."
        case .unexpectedStatus(let code):
            return "Twitch request failed with status \(code)."
        }
    }
}

actor TwitchAuthService {
    private struct TwitchErrorPayload: Decodable {
        let status: Int?
        let message: String
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceCode(clientID: String, scopes: [String]) async throws -> TwitchDeviceGrant {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TwitchAuthError.missingClientID
        }

        let body = [
            "client_id": clientID,
            "scopes": scopes.joined(separator: " ")
        ]

        let (data, response) = try await postForm(to: "https://id.twitch.tv/oauth2/device", body: body)
        guard response.statusCode == 200 else {
            throw parseAuthError(data: data, statusCode: response.statusCode)
        }

        do {
            return try JSONDecoder().decode(TwitchDeviceGrant.self, from: data)
        } catch {
            throw TwitchAuthError.malformedResponse
        }
    }

    func pollDeviceCode(clientID: String, deviceCode: String) async throws -> TwitchDevicePollResult {
        let body = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]

        let (data, response) = try await postForm(to: "https://id.twitch.tv/oauth2/token", body: body)

        if response.statusCode == 200 {
            do {
                let token = try JSONDecoder().decode(TwitchOAuthToken.self, from: data)
                return .authorized(token)
            } catch {
                throw TwitchAuthError.malformedResponse
            }
        }

        guard response.statusCode == 400 else {
            throw parseAuthError(data: data, statusCode: response.statusCode)
        }

        let payload = try? JSONDecoder().decode(TwitchErrorPayload.self, from: data)
        let message = payload?.message.lowercased() ?? ""

        if message.contains("authorization_pending") {
            return .pending(retryAfter: 5)
        }

        if message.contains("slow_down") {
            return .slowDown
        }

        if message.contains("access_denied") {
            throw TwitchAuthError.authorizationDenied
        }

        if message.contains("expired_token") {
            throw TwitchAuthError.deviceCodeExpired
        }

        if message.contains("invalid device code") {
            throw TwitchAuthError.invalidDeviceCode
        }

        throw TwitchAuthError.unexpectedStatus(code: response.statusCode)
    }

    func refreshToken(clientID: String, refreshToken: String) async throws -> TwitchOAuthToken {
        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        let (data, response) = try await postForm(to: "https://id.twitch.tv/oauth2/token", body: body)
        guard response.statusCode == 200 else {
            throw parseAuthError(data: data, statusCode: response.statusCode)
        }

        do {
            return try JSONDecoder().decode(TwitchOAuthToken.self, from: data)
        } catch {
            throw TwitchAuthError.malformedResponse
        }
    }

    func validateToken(_ accessToken: String) async throws -> TwitchValidatedSession {
        guard let url = URL(string: "https://id.twitch.tv/oauth2/validate") else {
            throw TwitchAuthError.network
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("OAuth \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchAuthError.network
        }

        guard httpResponse.statusCode == 200 else {
            throw parseAuthError(data: data, statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(TwitchValidatedSession.self, from: data)
        } catch {
            throw TwitchAuthError.malformedResponse
        }
    }

    private func postForm(
        to endpoint: String,
        body: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: endpoint) else {
            throw TwitchAuthError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodedForm(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchAuthError.network
        }

        return (data, httpResponse)
    }

    private func encodedForm(_ params: [String: String]) -> Data {
        let query = params.map { key, value in
            let encodedKey = formEncoded(key)
            let encodedValue = formEncoded(value)
            return "\(encodedKey)=\(encodedValue)"
        }
        .sorted()
        .joined(separator: "&")

        return Data(query.utf8)
    }

    private func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }

    private func parseAuthError(data: Data, statusCode: Int) -> Error {
        let payload = try? JSONDecoder().decode(TwitchErrorPayload.self, from: data)
        let message = payload?.message.lowercased() ?? ""

        if statusCode == 401 {
            return TwitchAuthError.invalidToken
        }

        if message.contains("invalid refresh token") {
            return TwitchAuthError.invalidRefreshToken
        }

        if message.contains("invalid access token") {
            return TwitchAuthError.invalidToken
        }

        return TwitchAuthError.unexpectedStatus(code: statusCode)
    }
}
