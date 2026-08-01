import Foundation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "GitHubConnector")

/// Reads public GitHub activity by username. Private repository activity needs
/// a future GitHub App integration and is deliberately not inferred here.
final class GitHubConnector {
    private static let usernameKey = "github_connector_username_v1"
    private let session = URLSession.shared
    private let userAgent = "reInspire/1.0 (https://thechallenges.app)"

    var username: String? { UserDefaults.standard.string(forKey: Self.usernameKey) }
    var isConnected: Bool { username?.isEmpty == false }

    func connect(username raw: String) async throws {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/users/\(encoded)") else {
            throw ConnectorError.notConfigured(String(localized: "Введите имя пользователя GitHub"))
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConnectorError.server(String(localized: "Нет ответа от GitHub")) }
        guard http.statusCode == 200 else { throw ConnectorError.notConfigured(String(localized: "Пользователь GitHub не найден")) }
        UserDefaults.standard.set(name, forKey: Self.usernameKey)
    }

    func disconnect() { UserDefaults.standard.removeObject(forKey: Self.usernameKey) }

    func commitsToday() async -> Int {
        guard let name = username,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.github.com/users/\(encoded)/events/public?per_page=100") else { return 0 }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 0 }
            let events = try JSONDecoder.github.decode([Event].self, from: data)
            let start = Calendar.current.startOfDay(for: Date())
            return events.reduce(into: 0) { count, event in
                guard event.type == "PushEvent", event.createdAt >= start else { return }
                count += event.payload?.size ?? 0
            }
        } catch {
            logger.error("commitsToday failed: \(error)")
            return 0
        }
    }

    private struct Event: Decodable {
        let type: String
        let createdAt: Date
        let payload: Payload?
        enum CodingKeys: String, CodingKey { case type, payload; case createdAt = "created_at" }
    }

    private struct Payload: Decodable { let size: Int? }
}

private extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
