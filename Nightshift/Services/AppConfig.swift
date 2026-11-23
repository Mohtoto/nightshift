import Foundation
import Supabase

enum AppConfig {
    static let mode: BackendMode = {
        guard let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return .local
        }
        let rawURL = (plist["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (plist["anonKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasURL = !rawURL.isEmpty
        let hasKey = !key.isEmpty
        if !hasURL && !hasKey { return .local }
        guard hasURL, hasKey, let supabaseURL = URL(string: rawURL), supabaseURL.scheme == "https", supabaseURL.host != nil else {
            return .invalid("SupabaseConfig.plist needs both an https project URL and an anon key.")
        }
        guard key.count > 20, !key.hasPrefix("your-") else {
            return .invalid("The Supabase anon key in SupabaseConfig.plist looks incomplete.")
        }
        return .supabase
    }()

    static var supabase: (url: URL, key: String)? {
        guard case .supabase = mode,
              let url = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let rawURL = plist["url"] as? String,
              let key = plist["anonKey"] as? String,
              let supabaseURL = URL(string: rawURL) else { return nil }
        return (supabaseURL, key)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            if let date = JSONCoding.isoDate(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: value)
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeClient() -> SupabaseClient? {
        guard let config = supabase else { return nil }
        let options = SupabaseClientOptions(
            db: .init(encoder: makeEncoder(), decoder: makeDecoder()),
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
        return SupabaseClient(supabaseURL: config.url, supabaseKey: config.key, options: options)
    }
}

enum Backend {
    static func makeRepository() -> any NightshiftRepository {
        if let client = AppConfig.makeClient() {
            return SupabaseRepository(client: client)
        }
        return LocalRepository.makeDefault()
    }
}
