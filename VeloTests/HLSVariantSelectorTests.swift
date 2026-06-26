import Foundation
import Testing
@testable import Velo

@Suite("HLS variant selection")
struct HLSVariantSelectorTests {
    @Test("Chooses chunked source video variant when it has the best score")
    func choosesSourceVariant() throws {
        let baseURL = try #require(URL(string: "https://usher.ttvnw.net/api/v2/channel/hls/example.m3u8"))
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2"
        720p/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        chunked/index.m3u8
        """

        let selected = try #require(HLSVariantSelector.bestVideoVariant(in: manifest, relativeTo: baseURL))

        #expect(selected.absoluteString == "https://usher.ttvnw.net/api/v2/channel/hls/chunked/index.m3u8")
    }

    @Test("Ignores audio-only variants")
    func ignoresAudioOnlyVariants() throws {
        let baseURL = try #require(URL(string: "https://usher.ttvnw.net/api/v2/channel/hls/example.m3u8"))
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=9000000,CODECS="mp4a.40.2"
        audio-only/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=854x480,CODECS="avc1.4d401f,mp4a.40.2"
        480p/index.m3u8
        """

        let selected = try #require(HLSVariantSelector.bestVideoVariant(in: manifest, relativeTo: baseURL))

        #expect(selected.absoluteString == "https://usher.ttvnw.net/api/v2/channel/hls/480p/index.m3u8")
    }

    @Test("Resolves absolute variant URLs")
    func resolvesAbsoluteVariantURLs() throws {
        let baseURL = try #require(URL(string: "https://usher.ttvnw.net/api/v2/channel/hls/example.m3u8"))
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=854x480
        https://video-weaver.example.net/v1/playlist.m3u8
        """

        let selected = try #require(HLSVariantSelector.bestVideoVariant(in: manifest, relativeTo: baseURL))

        #expect(selected.absoluteString == "https://video-weaver.example.net/v1/playlist.m3u8")
    }

    @Test("Returns nil when no playable video variant exists")
    func returnsNilWithoutVideoVariant() throws {
        let baseURL = try #require(URL(string: "https://usher.ttvnw.net/api/v2/channel/hls/example.m3u8"))
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
        audio-only/index.m3u8
        """

        #expect(HLSVariantSelector.bestVideoVariant(in: manifest, relativeTo: baseURL) == nil)
    }
}
