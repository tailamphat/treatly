import Foundation

/// How the bowls look. Every style has the same shape, so treats sit in
/// the same place. Art is drawn by scripts/art/chibi.py.
public enum BowlStyle: String, CaseIterable, Sendable {
    case classic, steel, ceramic, puppy, tub

    public var name: String {
        switch self {
        case .classic: return "Classic"
        case .steel: return "Steel"
        case .ceramic: return "Ceramic"
        case .puppy: return "Puppy"
        case .tub: return "Country Tub"
        }
    }

    /// Art file names in Resources/Art for one source's bowl.
    public func artNames(for source: TaskSourceKind) -> (back: String, front: String) {
        ("bowl-\(rawValue)-\(source.rawValue)-back", "bowl-\(rawValue)-\(source.rawValue)")
    }

    /// Unknown or missing values fall back to classic.
    public init(stored: String?) {
        self = stored.flatMap(BowlStyle.init(rawValue:)) ?? .classic
    }
}
