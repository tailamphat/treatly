import Foundation

/// Things a pet can wear. A pack lists the items it has art for.
public enum Wardrobe {
    /// Known items, in the order they are shown. Packs may add others.
    public static let catalogue: [(id: String, name: String)] = [
        ("party-hat", "Party Hat"),
        ("bow", "Bow"),
        ("crown", "Crown"),
        ("bandana", "Bandana"),
        ("glasses", "Sunglasses"),
        ("flower", "Flower"),
    ]

    public static func name(for id: String) -> String {
        catalogue.first { $0.id == id }?.name
            ?? id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Ids become file names (`wear-<id>.png`), so keep them simple.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    public static func fileName(for id: String) -> String { "wear-\(id).png" }

    /// The items a pack offers, catalogue order first.
    public static func items(in sheet: SpriteSheet?) -> [String] {
        let listed = (sheet?.wardrobe ?? []).filter(isValidID)
        let known = catalogue.map(\.id).filter(listed.contains)
        return known + listed.filter { !known.contains($0) }
    }
}
