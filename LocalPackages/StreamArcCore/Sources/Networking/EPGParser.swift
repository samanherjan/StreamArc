import Foundation

// Parses XMLTV-formatted EPG XML into EPGProgram arrays.
// Handles both plain and gzip-compressed feeds.
public struct EPGParser {

    public static func parse(data: Data) throws -> [EPGProgram] {
        let xmlData = isGzip(data) ? try decompress(data) : data
        let parser = XMLParser(data: xmlData)
        let delegate = EPGXMLDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? EPGError.parseFailed
        }
        return delegate.programs
    }

    public static func parse(url: URL) async throws -> [EPGProgram] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parse(data: data)
    }

    // MARK: - Gzip

    private static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == 0x1F && data[1] == 0x8B
    }

    private static func decompress(_ data: Data) throws -> Data {
        // Uses zlib raw inflate via NSData bridging on Apple platforms
        var decompressed = Data()
        let bufferSize = 65_536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws in
            guard let ptr = raw.bindMemory(to: UInt8.self).baseAddress else { throw EPGError.decompressionFailed }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer(mutating: ptr)
            stream.avail_in = uInt(data.count)
            // windowBits = 47 means auto-detect gzip/zlib
            guard inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw EPGError.decompressionFailed
            }
            defer { inflateEnd(&stream) }
            var status: Int32 = Z_OK
            repeat {
                let produced: Int = buffer.withUnsafeMutableBufferPointer { ptr in
                    stream.next_out = ptr.baseAddress
                    stream.avail_out = uInt(bufferSize)
                    status = inflate(&stream, Z_SYNC_FLUSH)
                    return bufferSize - Int(stream.avail_out)
                }
                decompressed.append(contentsOf: buffer.prefix(produced))
            } while status == Z_OK
            guard status == Z_STREAM_END else { throw EPGError.decompressionFailed }
        }
        return decompressed
    }
}

// MARK: - XML delegate

private final class EPGXMLDelegate: NSObject, XMLParserDelegate {

    var programs: [EPGProgram] = []

    private var currentProgramChannelId: String?
    private var currentProgramStart: Date?
    private var currentProgramStop: Date?
    private var currentTitle: String?
    private var currentDesc: String?
    private var parsingTitle = false
    private var parsingDesc  = false

    // XMLTV date format: YYYYMMddHHmmss ±HHMM
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMddHHmmss Z"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "programme":
            currentProgramChannelId = attributes["channel"]
            currentProgramStart = attributes["start"].flatMap { dateFormatter.date(from: $0) }
            currentProgramStop  = attributes["stop"].flatMap  { dateFormatter.date(from: $0) }
            currentTitle = nil
            currentDesc  = nil
        case "title":
            parsingTitle = true
        case "desc":
            parsingDesc = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if parsingTitle { currentTitle = (currentTitle ?? "") + string }
        if parsingDesc  { currentDesc  = (currentDesc  ?? "") + string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "title": parsingTitle = false
        case "desc":  parsingDesc  = false
        case "programme":
            if let channelId = currentProgramChannelId,
               let start = currentProgramStart,
               let stop = currentProgramStop,
               let title = currentTitle {
                programs.append(EPGProgram(
                    channelId: channelId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: start,
                    endDate: stop,
                    description: currentDesc?.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        default: break
        }
    }
}

// MARK: - Errors

public enum EPGError: Error {
    case parseFailed
    case decompressionFailed
}

// zlib symbols — available on all Apple platforms via libz
import zlib
