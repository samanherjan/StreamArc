import StreamArcCore
import Testing
import Foundation
@testable import StreamArc

@Suite("EPGParser Tests")
struct EPGParserTests {

    static let sampleXMLTV = """
    <?xml version="1.0" encoding="UTF-8"?>
    <tv>
      <channel id="bbc1.uk">
        <display-name>BBC One</display-name>
      </channel>
      <channel id="cnn">
        <display-name>CNN</display-name>
      </channel>
      <programme start="20240101120000 +0000" stop="20240101130000 +0000" channel="bbc1.uk">
        <title lang="en">BBC News at One</title>
        <desc lang="en">The lunchtime news bulletin.</desc>
      </programme>
      <programme start="20240101130000 +0000" stop="20240101140000 +0000" channel="bbc1.uk">
        <title lang="en">Doctors</title>
      </programme>
      <programme start="20240101120000 +0000" stop="20240101121500 +0000" channel="cnn">
        <title lang="en">CNN Newsroom</title>
      </programme>
    </tv>
    """

    @Test("Parses correct total program count")
    func programCount() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        #expect(programs.count == 3)
    }

    @Test("Assigns correct channel ID")
    func channelId() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        let bbcPrograms = programs.filter { $0.channelId == "bbc1.uk" }
        #expect(bbcPrograms.count == 2)
    }

    @Test("Parses programme title correctly")
    func programTitle() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        let bbc = programs.first(where: { $0.channelId == "bbc1.uk" })
        #expect(bbc?.title == "BBC News at One")
    }

    @Test("Parses programme description")
    func programDescription() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        let bbc = programs.first(where: { $0.channelId == "bbc1.uk" })
        #expect(bbc?.description == "The lunchtime news bulletin.")
    }

    @Test("Parses start and end dates correctly")
    func programDates() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        let bbc = programs.first(where: { $0.channelId == "bbc1.uk" })!
        let duration = bbc.endDate.timeIntervalSince(bbc.startDate)
        #expect(duration == 3600)  // 1 hour
    }

    @Test("isCurrentlyAiring returns false for past programs")
    func pastProgramNotAiring() throws {
        let data = Self.sampleXMLTV.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        // All test programs are in the past (2024-01-01)
        #expect(programs.allSatisfy { !$0.isCurrentlyAiring })
    }

    @Test("Handles empty XMLTV gracefully")
    func emptyXMLTV() throws {
        let empty = "<?xml version=\"1.0\"?><tv></tv>"
        let data = empty.data(using: .utf8)!
        let programs = try EPGParser.parse(data: data)
        #expect(programs.isEmpty)
    }
}
