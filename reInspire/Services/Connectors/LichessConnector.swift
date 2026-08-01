import Foundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "LichessConnector")

/// Reads finished games from the public Lichess API by username.
final class LichessConnector {
    private static let usernameKey = "lichess_connector_username_v1"
    private let session = URLSession.shared
    private let userAgent = "reInspire/1.0 (https://thechallenges.app)"

    var username: String? { UserDefaults.standard.string(forKey: Self.usernameKey) }
    var isConnected: Bool { username?.isEmpty == false }

    func connect(username raw: String) async throws {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://lichess.org/api/user/\(encoded)") else {
            throw ConnectorError.notConfigured(String(localized: "Введите имя пользователя Lichess"))
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.server(String(localized: "Нет ответа от Lichess")) }
        guard http.statusCode == 200 else { throw ConnectorError.notConfigured(String(localized: "Пользователь Lichess не найден")) }
        UserDefaults.standard.set(name, forKey: Self.usernameKey)
    }

    func disconnect() { UserDefaults.standard.removeObject(forKey: Self.usernameKey) }

    func gamesToday() async -> Int {
        guard let name = username,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let since = Int(start.timeIntervalSince1970 * 1_000)
        let until = Int(Date().timeIntervalSince1970 * 1_000)
        guard let url = URL(string: "https://lichess.org/api/games/user/\(encoded)?since=\(since)&until=\(until)&max=100&moves=false&clocks=false&evals=false&opening=false") else { return 0 }
        var request = URLRequest(url: url)
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 0 }
            let text = String(decoding: data, as: UTF8.self)
            return text.split(whereSeparator: \.isNewline).count
        } catch {
            logger.error("gamesToday failed: \(error)")
            return 0
        }
    }
}
