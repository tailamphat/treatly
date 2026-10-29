import AppKit
import TreatlyCore

/// User preferences. The Google client secret lives in the Keychain.
@MainActor
final class Settings {
    private let defaults = UserDefaults.standard

    var petID: String {
        get { defaults.string(forKey: "petID") ?? "shiba" }
        set { defaults.set(newValue, forKey: "petID") }
    }

    func petName(for pack: PetPack) -> String {
        (defaults.dictionary(forKey: "petNames") as? [String: String])?[pack.id] ?? pack.defaultName
    }

    func setPetName(_ name: String, for pack: PetPack) {
        var names = (defaults.dictionary(forKey: "petNames") as? [String: String]) ?? [:]
        names[pack.id] = name
        defaults.set(names, forKey: "petNames")
    }

    /// The wardrobe item each pet wears, by pack id.
    func wearing(for pack: PetPack) -> String? {
        (defaults.dictionary(forKey: "wearing") as? [String: String])?[pack.id]
    }

    func setWearing(_ item: String?, for pack: PetPack) {
        var all = (defaults.dictionary(forKey: "wearing") as? [String: String]) ?? [:]
        all[pack.id] = item
        defaults.set(all, forKey: "wearing")
    }

    var bowlStyle: BowlStyle {
        get { BowlStyle(stored: defaults.string(forKey: "bowlStyle")) }
        set { defaults.set(newValue.rawValue, forKey: "bowlStyle") }
    }

    var poopStyle: PoopStyle {
        get { PoopStyle(stored: defaults.string(forKey: "poopStyle")) }
        set { defaults.set(newValue.rawValue, forKey: "poopStyle") }
    }

    /// Off by default: yelling is a speech bubble unless you opt in.
    var soundOn: Bool {
        get { defaults.bool(forKey: "soundOn") }
        set { defaults.set(newValue, forKey: "soundOn") }
    }

    var nagStepMinutes: Int {
        get { defaults.object(forKey: "nagStepMinutes") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "nagStepMinutes") }
    }

    var remindersEnabled: Bool {
        get { defaults.object(forKey: "remindersEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "remindersEnabled") }
    }

    /// Empty means every list.
    func selectedLists(for source: TaskSourceKind) -> Set<String> {
        Set(defaults.stringArray(forKey: "lists.\(source.rawValue)") ?? [])
    }

    func setSelectedLists(_ ids: Set<String>, for source: TaskSourceKind) {
        defaults.set(Array(ids), forKey: "lists.\(source.rawValue)")
    }

    /// The client to sign in with: the user's own if set, else the built-in one.
    var googleClient: GoogleClient? {
        GoogleClient.resolve(custom: GoogleClient(id: googleClientID, secret: googleClientSecret), builtIn: builtInGoogleClient)
    }

    /// Added to Info.plist by scripts/bundle.sh for release builds.
    var builtInGoogleClient: GoogleClient? {
        GoogleClient(
            id: Bundle.main.object(forInfoDictionaryKey: "TreatlyGoogleClientID") as? String,
            secret: Bundle.main.object(forInfoDictionaryKey: "TreatlyGoogleClientSecret") as? String
        )
    }

    /// True when the user brought their own client.
    var hasCustomGoogleClient: Bool { GoogleClient(id: googleClientID, secret: googleClientSecret) != nil }

    var googleClientID: String? {
        get { defaults.string(forKey: "googleClientID") }
        set { defaults.set(newValue, forKey: "googleClientID") }
    }

    var googleClientSecret: String? {
        get { Keychain.read("google-client-secret") }
        set {
            if let newValue { Keychain.write(newValue, for: "google-client-secret") } else { Keychain.delete("google-client-secret") }
        }
    }

    /// Where the user dragged each source's bowl (window origin), if they did.
    func bowlPosition(for source: TaskSourceKind) -> NSPoint? {
        guard let xy = (defaults.dictionary(forKey: "bowlPositions") as? [String: [Double]])?[source.rawValue], xy.count == 2 else { return nil }
        return NSPoint(x: xy[0], y: xy[1])
    }

    func setBowlPosition(_ point: NSPoint, for source: TaskSourceKind) {
        var all = (defaults.dictionary(forKey: "bowlPositions") as? [String: [Double]]) ?? [:]
        all[source.rawValue] = [point.x, point.y]
        defaults.set(all, forKey: "bowlPositions")
    }

    /// Snoozed and skipped tasks, by task id.
    var hiddenUntil: [String: Date] {
        get { ((defaults.dictionary(forKey: "hiddenUntil") as? [String: Double]) ?? [:]).mapValues(Date.init(timeIntervalSince1970:)) }
        set { defaults.set(newValue.mapValues(\.timeIntervalSince1970), forKey: "hiddenUntil") }
    }
}
