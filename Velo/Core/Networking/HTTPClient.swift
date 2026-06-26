import Foundation

struct HTTPClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDecodable<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder(),
        maxBodyBytes: Int = 2 * 1_024 * 1_024
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.serverError(code: httpResponse.statusCode)
        }

        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let expectedBytes = Int(contentLength.trimmingCharacters(in: .whitespacesAndNewlines)),
           expectedBytes > maxBodyBytes {
            throw APIError.invalidResponse
        }

        guard data.count <= maxBodyBytes else {
            throw APIError.invalidResponse
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }
}
