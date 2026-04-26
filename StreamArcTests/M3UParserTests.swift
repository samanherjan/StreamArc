import Testing
@testable import StreamArc

@Suite("M3UParser Tests")
struct M3UParserTests {

    static let sampleM3U = """
    #EXTM3U x-tvg-url="http://epg.example.com/guide.xml"
    #EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One" tvg-logo="http://logo.example.com/bbc1.png" group-title="UK News",BBC One HD
    http://stream.example.com/bbc1.ts
    #EXTINF:-1 tvg-id="cnn" tvg-name="CNN" tvg-logo="" group-title="News",CNN International
    https://stream.example.com/cnn.m3u8
    #EXTINF:-1 tvg-name="The Dark Knight" tvg-logo="http://img.example.com/dk.jpg" group-title="VOD Movies",The Dark Knight (2008)
    http://vod.example.com/darkknight.mp4
    #EXTINF:-1 tvg-name="Breaking Bad" group-title="VOD Series",Breaking Bad S01E01
    http://vod.example.com/bb_s01e01.mp4
    """

    @Test("Parses channel count correctly")
    func channelCount() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.count == 2)
    }

    @Test("Parses VOD item count correctly")
    func vodCount() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.vodItems.count == 2)
    }

    @Test("Extracts channel name from tvg-name attribute")
    func channelName() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.first?.name == "BBC One")
    }

    @Test("Extracts channel EPG ID from tvg-id")
    func channelEpgId() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.first?.epgId == "bbc1.uk")
    }

    @Test("Extracts channel logo URL")
    func channelLogo() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.first?.logoURL == "http://logo.example.com/bbc1.png")
    }

    @Test("Extracts channel group-title")
    func channelGroup() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.first?.groupTitle == "UK News")
    }

    @Test("Extracts channel stream URL")
    func channelStreamURL() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        #expect(result.channels.first?.streamURL == "http://stream.example.com/bbc1.ts")
    }

    @Test("Classifies VOD Movies correctly")
    func vodMovieType() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        let movie = result.vodItems.first(where: { $0.title.contains("Dark Knight") })
        #expect(movie?.type == .movie)
    }

    @Test("Classifies VOD Series correctly")
    func vodSeriesType() {
        let result = M3UParser.parse(content: Self.sampleM3U)
        let series = result.vodItems.first(where: { $0.title.contains("Breaking Bad") })
        #expect(series?.type == .series)
    }

    @Test("Returns empty result for non-M3U content")
    func invalidContent() {
        let result = M3UParser.parse(content: "Not an M3U file")
        #expect(result.channels.isEmpty)
        #expect(result.vodItems.isEmpty)
    }

    @Test("Handles empty playlist gracefully")
    func emptyPlaylist() {
        let result = M3UParser.parse(content: "#EXTM3U\n")
        #expect(result.channels.isEmpty)
        #expect(result.vodItems.isEmpty)
    }

    @Test("Falls back to title after comma when tvg-name is missing")
    func titleFallback() {
        let m3u = "#EXTM3U\n#EXTINF:-1 group-title=\"News\",My Fallback Channel\nhttp://stream.example.com/test.ts\n"
        let result = M3UParser.parse(content: m3u)
        #expect(result.channels.first?.name == "My Fallback Channel")
    }
}
