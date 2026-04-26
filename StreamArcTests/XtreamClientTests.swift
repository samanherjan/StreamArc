import Testing
import Foundation
@testable import StreamArc

@Suite("XtreamClient Tests")
struct XtreamClientTests {

    // A URLSession that returns a fixed response without hitting the network.
    static func mockSession(json: Any, statusCode: Int = 200) -> URLSession {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: statusCode,
                                           httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        return URLSession(configuration: config)
    }

    @Test("Parses live categories from API response")
    func parsesLiveCategories() async throws {
        let json: [[String: Any]] = [
            ["category_id": "1", "category_name": "News"],
            ["category_id": "2", "category_name": "Sports"]
        ]
        let session = Self.mockSession(json: json)
        let client = XtreamClient(
            config: .init(baseURL: "http://test.com", username: "user", password: "pass"),
            session: session
        )
        let cats = try await client.liveCategories()
        #expect(cats.count == 2)
        #expect(cats.first?.categoryName == "News")
    }

    @Test("Parses VOD streams from API response")
    func parsesVODStreams() async throws {
        let json: [[String: Any]] = [
            ["stream_id": 101, "name": "Inception", "stream_icon": "http://img.com/inception.jpg",
             "category_id": "3", "container_extension": "mp4"],
            ["stream_id": 102, "name": "Interstellar", "stream_icon": "",
             "category_id": "3", "container_extension": "mkv"]
        ]
        let session = Self.mockSession(json: json)
        let client = XtreamClient(
            config: .init(baseURL: "http://test.com", username: "user", password: "pass"),
            session: session
        )
        let streams = try await client.vodStreams()
        #expect(streams.count == 2)
        #expect(streams.first?.name == "Inception")
        #expect(streams.first?.streamId == 101)
    }

    @Test("asVODItems builds correct stream URL")
    func vodStreamURL() async throws {
        let json: [[String: Any]] = [
            ["stream_id": 42, "name": "Test Movie", "container_extension": "mp4",
             "category_id": "1", "stream_icon": nil as Any? as Any]
        ]
        let session = Self.mockSession(json: json)
        let client = XtreamClient(
            config: .init(baseURL: "http://test.com:8080", username: "myuser", password: "mypass"),
            session: session
        )
        let items = try await client.asVODItems()
        #expect(items.first?.streamURL == "http://test.com:8080/movie/myuser/mypass/42.mp4")
    }

    @Test("Parses series categories")
    func parsesSeriesCategories() async throws {
        let json: [[String: Any]] = [
            ["category_id": "10", "category_name": "Drama"],
            ["category_id": "11", "category_name": "Comedy"]
        ]
        let session = Self.mockSession(json: json)
        let client = XtreamClient(
            config: .init(baseURL: "http://test.com", username: "user", password: "pass"),
            session: session
        )
        let cats = try await client.seriesCategories()
        #expect(cats.count == 2)
        #expect(cats[1].categoryName == "Comedy")
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
