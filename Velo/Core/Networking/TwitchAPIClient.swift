import Foundation

struct TwitchAPIClient {
    private let httpClient: HTTPClient
    private let clientPolicy: TwitchClientPolicy

    init(httpClient: HTTPClient, clientPolicy: TwitchClientPolicy) {
        self.httpClient = httpClient
        self.clientPolicy = clientPolicy
    }

    func publicTopStreams(limit: Int) async throws -> [LiveStream] {
        let clampedLimit = min(max(limit, 1), 30)
        let payload: PublicTopStreamsData = try await postGraphQL(
            operationName: "VeloTopStreams",
            variables: PublicTopStreamsVariables(limit: clampedLimit),
            query: """
            query VeloTopStreams($limit: Int!) {
              streams(first: $limit) {
                edges {
                  node {
                    id
                    title
                    viewersCount
                    language
                    broadcaster {
                      id
                      login
                      displayName
                    }
                    game {
                      name
                    }
                    previewImageURL(width: 640, height: 360)
                    createdAt
                  }
                }
              }
            }
            """
        )

        return payload.streams?.edges.compactMap { $0.node?.asLiveStream } ?? []
    }

    func publicSearchLiveChannels(query: String, limit: Int) async throws -> [LiveStream] {
        let payload: PublicSearchStreamsData = try await postGraphQL(
            operationName: "VeloSearchStreams",
            variables: PublicSearchStreamsVariables(query: query),
            query: """
            query VeloSearchStreams($query: String!) {
              searchFor(userQuery: $query, platform: "web") {
                channels {
                  edges {
                    item {
                      ... on User {
                        id
                        login
                        displayName
                        stream {
                          id
                          title
                          viewersCount
                          language
                          game {
                            name
                          }
                          previewImageURL(width: 640, height: 360)
                          createdAt
                        }
                      }
                    }
                  }
                }
              }
            }
            """
        )

        let streams = payload.searchFor?.channels?.edges.compactMap { $0.item.asLiveStream } ?? []
        return Array(streams.prefix(limit))
    }

    func followedStreams(
        credentials: TwitchCredentials,
        userID: String,
        limit: Int
    ) async throws -> [LiveStream] {
        var components = URLComponents(string: "https://api.twitch.tv/helix/streams/followed")
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: userID),
            URLQueryItem(name: "first", value: String(limit))
        ]

        guard let url = components?.url else { throw APIError.invalidURL }

        let payload: TwitchDataEnvelope<TwitchStreamPayload> = try await httpClient.fetchDecodable(
            TwitchDataEnvelope<TwitchStreamPayload>.self,
            from: url,
            headers: clientPolicy.helixHeaders(credentials: credentials),
            decoder: twitchDecoder
        )

        return payload.data.map { $0.asLiveStream }
    }

    private func postGraphQL<Variables: Encodable, Payload: Decodable>(
        operationName: String,
        variables: Variables,
        query: String
    ) async throws -> Payload {
        guard let url = URL(string: "https://gql.twitch.tv/gql") else {
            throw APIError.invalidURL
        }

        let body = GraphQLRequestBody(
            operationName: operationName,
            variables: variables,
            query: query
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        clientPolicy.publicGraphQLHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await httpClient.session.data(for: request)
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

        let envelope: GraphQLResponse<Payload>
        do {
            envelope = try twitchDecoder.decode(GraphQLResponse<Payload>.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }

        if let message = envelope.errors?.first?.message {
            throw APIError.serviceUnavailable(message)
        }

        guard let payload = envelope.data else {
            throw APIError.decodingFailed
        }

        return payload
    }

    private var twitchDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct TwitchDataEnvelope<T: Decodable>: Decodable {
    let data: [T]
}

private struct GraphQLRequestBody<Variables: Encodable>: Encodable {
    let operationName: String
    let variables: Variables
    let query: String
}

private struct GraphQLResponse<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private struct PublicTopStreamsVariables: Encodable {
    let limit: Int
}

private struct PublicSearchStreamsVariables: Encodable {
    let query: String
}

private struct PublicTopStreamsData: Decodable {
    let streams: PublicStreamConnection?
}

private struct PublicStreamConnection: Decodable {
    let edges: [PublicStreamEdge]
}

private struct PublicStreamEdge: Decodable {
    let node: PublicStreamPayload?
}

private struct PublicStreamPayload: Decodable {
    let id: String
    let title: String?
    let viewersCount: Int?
    let language: String?
    let broadcaster: PublicBroadcasterPayload?
    let game: PublicGamePayload?
    let previewImageURL: String?
    let createdAt: Date?

    var asLiveStream: LiveStream? {
        guard
            let broadcaster,
            let channelID = broadcaster.id,
            let channelLogin = broadcaster.login,
            let channelName = broadcaster.displayName
        else {
            return nil
        }

        return LiveStream(
            id: id,
            channelID: channelID,
            channelLogin: channelLogin,
            channelName: channelName,
            title: title ?? "",
            gameName: game?.name ?? "",
            language: language?.lowercased() ?? "",
            viewerCount: viewersCount,
            thumbnailTemplate: previewImageURL ?? "",
            startedAt: createdAt
        )
    }
}

private struct PublicBroadcasterPayload: Decodable {
    let id: String?
    let login: String?
    let displayName: String?
}

private struct PublicGamePayload: Decodable {
    let name: String
}

private struct PublicSearchStreamsData: Decodable {
    let searchFor: PublicSearchPayload?
}

private struct PublicSearchPayload: Decodable {
    let channels: PublicSearchChannelConnection?
}

private struct PublicSearchChannelConnection: Decodable {
    let edges: [PublicSearchChannelEdge]
}

private struct PublicSearchChannelEdge: Decodable {
    let item: PublicSearchChannelPayload
}

private struct PublicSearchChannelPayload: Decodable {
    let id: String?
    let login: String?
    let displayName: String?
    let stream: PublicSearchStreamPayload?

    var asLiveStream: LiveStream? {
        guard
            let id,
            let login,
            let displayName,
            let stream
        else {
            return nil
        }

        return LiveStream(
            id: stream.id,
            channelID: id,
            channelLogin: login,
            channelName: displayName,
            title: stream.title ?? "",
            gameName: stream.game?.name ?? "",
            language: stream.language?.lowercased() ?? "",
            viewerCount: stream.viewersCount,
            thumbnailTemplate: stream.previewImageURL ?? "",
            startedAt: stream.createdAt
        )
    }
}

private struct PublicSearchStreamPayload: Decodable {
    let id: String
    let title: String?
    let viewersCount: Int?
    let language: String?
    let game: PublicGamePayload?
    let previewImageURL: String?
    let createdAt: Date?
}

private struct TwitchStreamPayload: Decodable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let gameName: String
    let language: String
    let title: String
    let viewerCount: Int
    let thumbnailURL: String
    let startedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case gameName = "game_name"
        case language
        case title
        case viewerCount = "viewer_count"
        case thumbnailURL = "thumbnail_url"
        case startedAt = "started_at"
    }

    var asLiveStream: LiveStream {
        LiveStream(
            id: id,
            channelID: userID,
            channelLogin: userLogin,
            channelName: userName,
            title: title,
            gameName: gameName,
            language: language,
            viewerCount: viewerCount,
            thumbnailTemplate: thumbnailURL,
            startedAt: startedAt
        )
    }
}
