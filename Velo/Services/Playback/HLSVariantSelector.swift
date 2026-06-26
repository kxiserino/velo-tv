import Foundation

enum HLSVariantSelector {
    static func bestVideoVariant(in manifest: String, relativeTo baseURL: URL) -> URL? {
        let rawLines = manifest
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var variants: [(isSource: Bool, score: Int, url: URL)] = []

        for index in rawLines.indices {
            let line = rawLines[index]
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            guard index + 1 < rawLines.count else { continue }

            let uriLine = rawLines[index + 1]
            guard !uriLine.hasPrefix("#") else { continue }
            guard let variantURL = URL(string: uriLine, relativeTo: baseURL)?.absoluteURL else { continue }

            let upper = line.uppercased()
            let hasResolution = upper.contains("RESOLUTION=")
            let hasVideoGroup = upper.contains("VIDEO=")
            let isAudioOnly = upper.contains("CODECS=\"MP4A") &&
                !upper.contains("AVC1") &&
                !upper.contains("HVC1") &&
                !upper.contains("HEV1")

            if isAudioOnly || (!hasResolution && !hasVideoGroup) {
                continue
            }

            let lowerURL = variantURL.absoluteString.lowercased()
            let isSource = lowerURL.contains("chunked")
            var score = 0
            if isSource { score += 10_000 }
            if let bandwidth = extractIntegerAttribute(named: "BANDWIDTH", from: line) {
                score += bandwidth
            }

            variants.append((isSource: isSource, score: score, url: variantURL))
        }

        guard !variants.isEmpty else { return nil }
        return variants.max(by: { $0.score < $1.score })?.url
    }

    private static func extractIntegerAttribute(named name: String, from streamInfoLine: String) -> Int? {
        guard let range = streamInfoLine.range(of: "\(name)=") else { return nil }
        let suffix = streamInfoLine[range.upperBound...]
        let valuePart = suffix.prefix { $0 != "," }
        return Int(valuePart)
    }
}
