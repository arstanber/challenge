import Foundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "YouTubeConnector")

/// Counts public uploads through YouTube's channel Atom feed. A channel ID is
/// used instead of a handle so the connector needs no API key or OAuth secret.
final class YouTubeConnector {
    private static let channelIDKey = "youtube_connector_channel_id_v1"
    private let session = URLSession.shared

    var channelID: String? { UserDefaults.standard.string(forKey: Self.channelIDKey) }
    var isConnected: Bool { channelID?.isEmpty == false }

    func connect(channelID raw: String) async throws {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("UC"), value.count == 24,
              let url = feedURL(channelID: value) else {
            throw ConnectorError.notConfigured(String(localized: "Введите корректный ID YouTube-канала, начинающийся с UC"))
        }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              String(decoding: data, as: UTF8.self).contains("<feed") else {
            throw ConnectorError.notConfigured(String(localized: "YouTube-канал не найден"))
        }
        UserDefaults.standard.set(value, forKey: Self.channelIDKey)
    }

    func disconnect() { UserDefaults.standard.removeObject(forKey: Self.channelIDKey) }

    func uploadsToday() async -> Int {
        guard let channelID, let url = feedURL(channelID: channelID) else { return 0 }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 0 }
            let parser = YouTubeFeedParser(data: data)
            let published = parser.parse()
            let start = Calendar.current.startOfDay(for: Date())
            return published.filter { $0 >= start }.count
        } catch {
            logger.error("uploadsToday failed: \(error)")
            return 0
        }
    }

    private func feedURL(channelID: String) -> URL? {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")
    }
}

private final class YouTubeFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var currentElement = ""
    private var buffer = ""
    private var dates: [Date] = []
    private var isInsideEntry = false

    init(data: Data) { self.data = data }

    func parse() -> [Date] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return dates
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "entry" { isInsideEntry = true }
        if elementName == "published", isInsideEntry { buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "published", isInsideEntry { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "published", isInsideEntry, let date = ISO8601DateFormatter().date(from: buffer.trimmingCharacters(in: .whitespacesAndNewlines)) {
            dates.append(date)
        }
        if elementName == "entry" { isInsideEntry = false }
        currentElement = ""
    }
}
