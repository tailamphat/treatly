import Foundation

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double

    /// Accepts "#RRGGBB" or "#RRGGBBAA".
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let full = s.count == 6 ? (v << 8) | 0xFF : v
        r = Double((full >> 24) & 0xFF) / 255
        g = Double((full >> 16) & 0xFF) / 255
        b = Double((full >> 8) & 0xFF) / 255
        a = Double(full & 0xFF) / 255
    }
}

public struct SpriteError: Error, CustomStringConvertible {
    public var description: String
}

/// Pixel art written as text: one character per pixel, "." is transparent,
/// every other character is looked up in `palette`.
public struct PixelSprite: Codable, Equatable, Sendable {
    public var palette: [String: String]
    public var rows: [String]

    public init(palette: [String: String], rows: [String]) {
        self.palette = palette
        self.rows = rows
    }

    public var width: Int { rows.first?.count ?? 0 }
    public var height: Int { rows.count }

    public func validate() throws {
        guard !rows.isEmpty, width > 0 else { throw SpriteError(description: "sprite has no pixels") }
        for (i, row) in rows.enumerated() {
            if row.count != width {
                throw SpriteError(description: "row \(i) is \(row.count) wide, expected \(width)")
            }
            for ch in row where ch != "." {
                guard let hex = palette[String(ch)] else {
                    throw SpriteError(description: "row \(i) uses '\(ch)', which is not in the palette")
                }
                guard RGBA(hex: hex) != nil else {
                    throw SpriteError(description: "palette '\(ch)' has invalid color \(hex)")
                }
            }
        }
    }

    /// Colors indexed [y][x], with y = 0 at the top. nil is transparent.
    public func grid() -> [[RGBA?]] {
        let colors = palette.compactMapValues(RGBA.init(hex:))
        return rows.map { row in row.map { ch in ch == "." ? nil : colors[String(ch)] } }
    }
}
