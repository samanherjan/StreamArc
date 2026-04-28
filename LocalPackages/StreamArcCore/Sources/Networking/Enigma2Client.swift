import Foundation

// Enigma2 / E2 box HTTP API client.
// Reads bouquets and services from the Enigma2 web interface (port 80 by default).
// Stream URLs are constructed using the Enigma2 streaming port (8001).
public actor Enigma2Client {

    public struct Config: Sendable {
        public let baseURL: String  // e.g. "http://192.168.1.100"
        public let port: Int        // default 80

        public init(baseURL: String, port: Int = 80) {
            self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.port = port
        }

        fileprivate var apiBase: String {
            port == 80 ? "\(baseURL)/api" : "\(baseURL):\(port)/api"
        }

        fileprivate var streamBase: String {
            "\(baseURL):8001"
        }
    }

    private let config: Config
    private let session: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Bouquets

    public func bouquets() async throws -> [E2Bouquet] {
        let data = try await get("\(config.apiBase)/bouquets")
        let response = try JSONDecoder().decode(E2BouquetResponse.self, from: data)
        return response.bouquets
    }

    // MARK: - Services in a bouquet

    public func services(bouquetRef: String) async throws -> [Channel] {
        let encoded = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        let data = try await get("\(config.apiBase)/getservices?sRef=\(encoded)")
        let response = try JSONDecoder().decode(E2ServiceResponse.self, from: data)
        return response.services.compactMap { svc -> Channel? in
            guard let ref = svc.serviceReference, !ref.isEmpty,
                  let name = svc.serviceName else { return nil }
            let streamURL = "\(config.streamBase)/\(ref)"
            return Channel(id: ref, name: name, streamURL: streamURL)
        }
    }

    // MARK: - EPG now

    public func epgNow() async throws -> [EPGProgram] {
        let data = try await get("\(config.apiBase)/epgnow")
        let response = try JSONDecoder().decode(E2EPGResponse.self, from: data)
        return response.events.compactMap { event -> EPGProgram? in
            guard let ref = event.serviceReference,
                  let title = event.eventTitle,
                  let begin = event.eventStart,
                  let duration = event.eventDuration else { return nil }
            let start = Date(timeIntervalSince1970: TimeInterval(begin))
            let end = Date(timeIntervalSince1970: TimeInterval(begin + duration))
            return EPGProgram(
                channelId: ref,
                title: title,
                startDate: start,
                endDate: end,
                description: event.eventDescription
            )
        }
    }

    // MARK: - Networking

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return data
    }
}

// MARK: - Enigma2 API types

struct E2BouquetResponse: Decodable {
    let bouquets: [E2Bouquet]

    enum CodingKeys: String, CodingKey {
        case bouquets = "bouquets"
    }
}

public struct E2Bouquet: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String

    enum CodingKeys: String, CodingKey {
        case id   = "bouquet_ref"
        case name = "bouquet_name"
    }
}

struct E2ServiceResponse: Decodable {
    let services: [E2Service]
}

struct E2Service: Decodable {
    let serviceReference: String?
    let serviceName: String?

    enum CodingKeys: String, CodingKey {
        case serviceReference = "servicereference"
        case serviceName      = "servicename"
    }
}

struct E2EPGResponse: Decodable {
    let events: [E2EPGEvent]
}

struct E2EPGEvent: Decodable {
    let serviceReference: String?
    let eventTitle: String?
    let eventStart: Int?
    let eventDuration: Int?
    let eventDescription: String?

    enum CodingKeys: String, CodingKey {
        case serviceReference = "sref"
        case eventTitle       = "title"
        case eventStart       = "begin_timestamp"
        case eventDuration    = "duration_sec"
        case eventDescription = "longdesc"
    }
}
