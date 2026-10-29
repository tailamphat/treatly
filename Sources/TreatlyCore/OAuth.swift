import CryptoKit
import Foundation

/// Helpers for the Google OAuth loopback flow (RFC 8252) with PKCE (RFC 7636).
public enum OAuth {
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return base64URL(Data(bytes))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Query parameters from an HTTP request line like
    /// `GET /?code=abc&state=xyz HTTP/1.1`. nil if it is not a GET.
    public static func callbackParameters(requestLine: String) -> [String: String]? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return nil }
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] { params[item.name] = item.value ?? "" }
        return params
    }

    /// `application/x-www-form-urlencoded` body.
    public static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}

public enum GoogleTasksDate {
    /// Google Tasks stores only the date of `due` ("2026-10-29T00:00:00.000Z");
    /// the time is always midnight UTC and means nothing. Keep the calendar date.
    public static func components(fromDue due: String?) -> DateComponents? {
        guard let due, due.count >= 10 else { return nil }
        let parts = due.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}
