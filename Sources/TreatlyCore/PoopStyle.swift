import Foundation

/// What the pet leaves behind after a treat.
public enum PoopStyle: String, CaseIterable, Sendable {
    case cute, classic, golden, rainbow
    /// No poop at all.
    case off

    public var name: String {
        switch self {
        case .cute: return "Cute"
        case .classic: return "Classic"
        case .golden: return "Golden"
        case .rainbow: return "Rainbow"
        case .off: return "Off"
        }
    }

    /// Art file name in Resources/Art, or nil for `off`.
    public var artName: String? { self == .off ? nil : "poop-\(rawValue)" }

    /// Unknown or missing values fall back to cute.
    public init(stored: String?) {
        self = stored.flatMap(PoopStyle.init(rawValue:)) ?? .cute
    }
}
