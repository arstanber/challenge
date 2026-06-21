import Foundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "ChessConnector")

/// Chess.com connector. Their public API needs no OAuth -- games are read by
/// username straight from the client. We store the username and count games
/// finished today (the user's local day).
final class ChessConnector {
    private static let usernameKey = "chess_connector_username_v1"
    private let session = URLSession.shared

    /// Chess.com asks API clients to send a User-Agent identifying the app.
    private let userAgent = "reInspire/1.0 (https://thechallenges.app)"

    var username: String? {
        UserDefaults.standard.string(forKey: Self.usernameKey)
    }

    var isConnected: Bool { username?.isEmpty == false }

    /// Validates the username against the public profile endpoint and stores it.
    func connect(username raw: String) async throws {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty,
              let url = URL(string: "https://api.chess.com/pub/player/\(name)") else {
            throw ConnectorError.notConfigured(AppLanguage.current == "ru" ? "Введите имя пользователя Chess.com" : "Enter your Chess.com username")
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.server(AppLanguage.current == "ru" ? "Нет ответа" : "No response") }
        guard http.statusCode == 200 else {
            throw ConnectorError.notConfigured(AppLanguage.current == "ru" ? "Пользователь Chess.com не найден" : "Chess.com user not found")
        }
        UserDefaults.standard.set(name, forKey: Self.usernameKey)
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
    }

    /// Number of games that finished today (local day) for the stored username.
    func gamesToday() async -> Int {
        guard let name = username, !name.isEmpty else { return 0 }
        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let monthStr = String(format: "%02d", month)
        guard let url = URL(string: "https://api.chess.com/pub/player/\(name)/games/\(year)/\(monthStr)") else {
            return 0
        }
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: req)
            struct Archive: Decodable { let games: [Game] }
            struct Game: Decodable { let endTime: Int?
                enum CodingKeys: String, CodingKey { case endTime = "end_time" } }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            let startOfDay = cal.startOfDay(for: now)
            return archive.games.filter { game in
                guard let end = game.endTime else { return false }
                return Date(timeIntervalSince1970: TimeInterval(end)) >= startOfDay
            }.count
        } catch {
            logger.error("chess gamesToday failed: \(error)")
            return 0
        }
    }
}
