import Foundation

/// Minimal JSON value used to carry arbitrary column updates through the
/// offline mutation queue (a `[String: JSONValue]` is both Codable for disk
/// persistence and Encodable as a PostgREST update body). Dates are stored as
/// ISO-8601 strings so they round-trip identically on the wire.
enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case intArray([Int])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode([Int].self) {
            self = .intArray(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v):   try c.encode(v)
        case .int(let v):      try c.encode(v)
        case .double(let v):   try c.encode(v)
        case .bool(let v):     try c.encode(v)
        case .intArray(let v): try c.encode(v)
        case .null:            try c.encodeNil()
        }
    }

    /// ISO-8601 string for a date column, or `.null` when the date is absent
    /// (so an update can explicitly clear a deadline / reminder).
    static func date(_ date: Date?) -> JSONValue {
        guard let date else { return .null }
        return .string(ISO8601DateFormatter().string(from: date))
    }
}
