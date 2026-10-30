import Foundation

/// A pet you can pick: its look, its treat, how it moves and what it says.
/// Loaded from `<pack>/pet.json`.
public struct PetPack: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var species: String
    public var defaultName: String
    public var treat: Treat
    /// Animated PNG sprite sheet. Preferred over `sprite` when present.
    public var sheet: SpriteSheet?
    /// Single-frame text pixel art, for quick hand-made packs.
    public var sprite: PixelSprite?
    public var personality: Personality
    public var phrases: Phrases
    /// A macOS system sound name (e.g. "Funk"), played on yelling when sound is on.
    public var sound: String?
    /// What the treats are kept in: "bowl" (default), "tree" or "bamboo".
    public var container: String?
    /// Who drew the art and under which license; shown in the app's About list.
    public var credit: String?
    /// The folder the pack was loaded from; images are resolved against it.
    public var folder: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, species, defaultName, treat, sheet, sprite, personality, phrases, sound, container, credit
    }

    public struct Treat: Codable, Equatable, Sendable {
        public var name: String
        /// A PNG in the pack folder, or `sprite`.
        public var image: String?
        public var sprite: PixelSprite?
    }

    /// How the animal behaves. Only `walkSpeed` and `sleepiness` are required.
    public struct Personality: Codable, Equatable, Sendable {
        /// Points per second.
        public var walkSpeed: Double
        /// Chance (0...1) of napping when it stops.
        public var sleepiness: Double
        /// Points per second when running. Defaults to 2.2x walking.
        public var runSpeed: Double?
        /// Chance (0...1) that a stroll becomes a run. Defaults to 0.15.
        public var energy: Double?
        /// [min, max] seconds it stands around between moves. Defaults to [1.5, 4.5].
        public var rest: [Double]?
        /// Seconds per nagging burst. Defaults to 20.
        public var nagSeconds: Double?
        /// Scales the breaks between bursts; above 1 is more patient. Defaults to 1.
        public var patience: Double?

        public var temperament: Temperament {
            let r = rest ?? []
            let restRange = r.count == 2 && r[0] <= r[1] ? r[0]...r[1] : 1.5...4.5
            return Temperament(walkSpeed: walkSpeed, runSpeed: runSpeed, energy: energy ?? 0.15, sleepiness: sleepiness,
                               rest: restRange, nagDuration: nagSeconds ?? 20, patience: patience ?? 1)
        }
    }

    /// Templates may use {task} and {name}.
    public struct Phrases: Codable, Equatable, Sendable {
        public var carry: [String]
        public var drop: [String]
        public var yell: [String]
        public var whine: [String]
        public var happy: [String]
        public var bury: [String]
    }

    public func validate() throws {
        guard sheet != nil || sprite != nil else { throw SpriteError(description: "\(id) needs a 'sheet' or a 'sprite'") }
        // Packs come from strangers; keep their files inside the pack folder.
        for file in [sheet?.image, treat.image].compactMap({ $0 }) where !Self.isPlainFileName(file) {
            throw SpriteError(description: "\(id) image '\(file)' must be a file name inside the pack folder")
        }
        guard treat.image != nil || treat.sprite != nil else { throw SpriteError(description: "\(id) treat needs an 'image' or a 'sprite'") }
        do { try sheet?.validate() } catch { throw SpriteError(description: "\(id) sheet: \(error)") }
        do { try sprite?.validate() } catch { throw SpriteError(description: "\(id) sprite: \(error)") }
        do { try treat.sprite?.validate() } catch { throw SpriteError(description: "\(id) treat: \(error)") }
        let p = phrases
        for (key, list) in [("carry", p.carry), ("drop", p.drop), ("yell", p.yell), ("whine", p.whine), ("happy", p.happy), ("bury", p.bury)] where list.isEmpty {
            throw SpriteError(description: "\(id) has no '\(key)' phrases")
        }
    }
}

extension PetPack {
    /// A bare file name: no folders, no "..", not hidden.
    public static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }
}

public enum PhraseFormatter {
    public static func format(_ template: String, task: String, name: String) -> String {
        template
            .replacingOccurrences(of: "{task}", with: task)
            .replacingOccurrences(of: "{name}", with: name)
    }
}

public enum PetPackLoader {
    /// Loads every `*/pet.json` under the given directories. Later directories
    /// override earlier ones by id, so user packs can replace built-in ones.
    public static func load(from directories: [URL]) -> (packs: [PetPack], errors: [String]) {
        var byID: [String: PetPack] = [:]
        var errors: [String] = []
        let fm = FileManager.default
        for dir in directories {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for entry in entries {
                let file = entry.appendingPathComponent("pet.json")
                guard fm.fileExists(atPath: file.path) else { continue }
                do {
                    var pack = try JSONDecoder().decode(PetPack.self, from: Data(contentsOf: file))
                    pack.folder = entry
                    try pack.validate()
                    byID[pack.id] = pack
                } catch {
                    errors.append("\(file.path): \(error)")
                }
            }
        }
        return (byID.values.sorted { $0.name < $1.name }, errors)
    }
}
