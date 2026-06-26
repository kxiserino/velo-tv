import Foundation

nonisolated enum EmoteURLPolicy {
    static func providerImageURL(from rawValue: String, allowedHosts: Set<String>) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
        guard let url = URL(string: normalized) else { return nil }
        return isSafeRemoteImageURL(url, allowedHosts: allowedHosts) ? url : nil
    }

    static func providerImageURL(base rawBase: String, pathComponent: String, allowedHosts: Set<String>) -> URL? {
        guard let baseURL = providerImageURL(from: rawBase, allowedHosts: allowedHosts) else { return nil }
        let url = baseURL.appendingPathComponent(pathComponent)
        return isSafeRemoteImageURL(url, allowedHosts: allowedHosts) ? url : nil
    }

    static func isSafeRemoteImageURL(_ url: URL, allowedHosts: Set<String>? = nil) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return false }
        guard !isBlockedHost(host) else { return false }

        if let allowedHosts {
            return allowedHosts.contains { allowedHost in
                let normalized = allowedHost.lowercased()
                return host == normalized || host.hasSuffix(".\(normalized)")
            }
        }

        return true
    }

    static func preservesOriginalHost(originalURL: URL, response: URLResponse) -> Bool {
        guard let finalURL = response.url else { return true }
        guard isSafeRemoteImageURL(finalURL) else { return false }
        return originalURL.host(percentEncoded: false)?.lowercased() ==
            finalURL.host(percentEncoded: false)?.lowercased()
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }

        if isBlockedIPv4(host) || isBlockedIPv6(host) {
            return true
        }

        return false
    }

    private static func isBlockedIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch octets[0] {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(octets[1])
        case 169:
            return octets[1] == 254
        case 172:
            return (16...31).contains(octets[1])
        case 192:
            return octets[1] == 168
        case 224...255:
            return true
        default:
            return false
        }
    }

    private static func isBlockedIPv6(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        return normalized == "::" ||
            normalized == "::1" ||
            normalized.hasPrefix("0:0:0:0:0:0:0:1") ||
            normalized.hasPrefix("fe80:") ||
            normalized.hasPrefix("fc") ||
            normalized.hasPrefix("fd")
    }
}
