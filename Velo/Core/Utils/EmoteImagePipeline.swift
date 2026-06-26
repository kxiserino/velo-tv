import Foundation
import ImageIO
import UIKit

actor EmoteImagePipeline {
    static let shared = EmoteImagePipeline()

    private static let maxImageBytes = 4 * 1_024 * 1_024
    private static let maxPixelDimension = 512
    private static let maxPixelCount = 512 * 512
    private static let maxAnimatedFrameCount = 80
    private static let maxDecodedBytes = 24 * 1_024 * 1_024

    private let session: URLSession
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 120 * 1_024 * 1_024,
            diskCapacity: 320 * 1_024 * 1_024
        )

        session = URLSession(configuration: config, delegate: EmoteImageRedirectGuard(), delegateQueue: nil)
        cache.countLimit = 800
        cache.totalCostLimit = 80 * 1_024 * 1_024
    }

    func image(for url: URL) async -> UIImage? {
        guard EmoteURLPolicy.isSafeRemoteImageURL(url) else { return nil }

        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let keyString = key as String
        if let existing = inFlight[keyString] {
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return nil
                }

                guard Self.isValidImageResponse(response, originalURL: url, byteCount: data.count) else {
                    return nil
                }

                return Self.decodeImage(from: data)
            } catch {
                return nil
            }
        }

        inFlight[keyString] = task
        let decoded = await task.value
        inFlight[keyString] = nil

        if let decoded {
            cache.setObject(decoded, forKey: key, cost: Self.estimatedCost(of: decoded))
        }

        return decoded
    }

    func prefetch(urls: [URL], maxCount: Int = 120) async {
        let unique = Array(Set(urls)).prefix(maxCount)
        for url in unique {
            _ = await image(for: url)
        }
    }

    nonisolated private static func decodeImage(from data: Data) -> UIImage? {
        guard data.count <= maxImageBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        guard let dimensions = imageDimensions(for: source) else {
            return nil
        }

        guard dimensions.width <= maxPixelDimension,
              dimensions.height <= maxPixelDimension,
              dimensions.width * dimensions.height <= maxPixelCount
        else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount <= maxAnimatedFrameCount else { return nil }
        guard dimensions.width * dimensions.height * max(frameCount, 1) * 4 <= maxDecodedBytes else {
            return nil
        }

        guard frameCount > 1 else {
            return UIImage(data: data)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var totalDuration: TimeInterval = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            frames.append(UIImage(cgImage: cgImage))
            totalDuration += max(0.02, frameDuration(for: source, at: index))
        }

        guard !frames.isEmpty else {
            return UIImage(data: data)
        }

        return UIImage.animatedImage(with: frames, duration: max(totalDuration, 0.08))
    }

    nonisolated private static func isValidImageResponse(
        _ response: URLResponse,
        originalURL: URL,
        byteCount: Int
    ) -> Bool {
        guard byteCount <= maxImageBytes else { return false }
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else { return false }
        return EmoteURLPolicy.preservesOriginalHost(originalURL: originalURL, response: response)
    }

    nonisolated private static func imageDimensions(for source: CGImageSource) -> (width: Int, height: Int)? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        else {
            return nil
        }

        return (width, height)
    }

    nonisolated private static func estimatedCost(of image: UIImage) -> Int {
        let frames = image.images ?? [image]
        return frames.reduce(0) { total, frame in
            guard let cgImage = frame.cgImage else {
                return total
            }

            return total + (cgImage.bytesPerRow * cgImage.height)
        }
    }

    nonisolated private static func frameDuration(for source: CGImageSource, at index: Int) -> TimeInterval {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        else {
            return 0.1
        }

        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let value = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, value > 0 {
                return value
            }

            if let value = gif[kCGImagePropertyGIFDelayTime] as? Double, value > 0 {
                return value
            }
        }

        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let value = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double, value > 0 {
                return value
            }

            if let value = png[kCGImagePropertyAPNGDelayTime] as? Double, value > 0 {
                return value
            }
        }

        return 0.1
    }
}

private final class EmoteImageRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard
            let originalURL = task.originalRequest?.url,
            let redirectURL = request.url,
            EmoteURLPolicy.isSafeRemoteImageURL(redirectURL),
            originalURL.host(percentEncoded: false)?.lowercased() ==
                redirectURL.host(percentEncoded: false)?.lowercased()
        else {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}
