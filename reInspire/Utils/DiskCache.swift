import Foundation
import os.log

/// Lightweight Codable disk cache living in the Caches directory.
///
/// Used for instant cold-start rendering: a screen paints the last-known data
/// immediately (no spinner / skeleton on a warm cache), then refreshes from the
/// network and rewrites the cache. It is intentionally NOT a source of truth --
/// the server stays authoritative, the cache is just an optimistic head-start.
///
/// Encoding uses ISO-8601 dates on both ends so round-trips are stable
/// regardless of how Supabase decodes the same models off the wire.
enum DiskCache {
    private static let logger = Logger(subsystem: "com.reinspire", category: "DiskCache")

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("reInspireCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe + ".json")
    }

    /// Persist a value. Best-effort: failures are logged, never thrown -- a
    /// cache miss next launch is harmless.
    static func save<T: Encodable>(_ value: T, key: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(for: key), options: .atomic)
        } catch {
            logger.error("save(\(key, privacy: .public)) failed: \(error)")
        }
    }

    /// Read a value, or nil on a miss / decode failure (e.g. a model changed
    /// shape since it was written).
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("load(\(key, privacy: .public)) failed: \(error)")
            return nil
        }
    }

    static func remove(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}
