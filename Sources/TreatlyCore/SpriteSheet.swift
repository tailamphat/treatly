import Foundation

/// A PNG laid out as a grid of equally sized frames. Each animation is a run
/// of frames along one row.
public struct SpriteSheet: Codable, Equatable, Sendable {
    /// PNG file name, relative to the pack folder.
    public var image: String
    public var frameWidth: Int
    public var frameHeight: Int
    /// Points per sheet pixel on screen. Defaults to 2.
    public var scale: Double?
    /// Which way the art faces. Defaults to right.
    public var facing: String?
    /// Blank pixel rows under the feet in every frame, so the pet stands on the ground.
    public var footPadding: Int?
    /// Where the treat is held, in frame pixels from the top-left of a
    /// right-facing frame. Defaults to near the front top.
    public var mouth: [Double]?
    public var animations: [String: Animation]
    /// Wardrobe items this pack has overlays for. Item `x` is drawn from
    /// `wear-x.png`, laid out like the sheet.
    public var wardrobe: [String]?

    public init(image: String, frameWidth: Int, frameHeight: Int, scale: Double? = nil, facing: String? = nil, footPadding: Int? = nil, mouth: [Double]? = nil, animations: [String: Animation], wardrobe: [String]? = nil) {
        self.image = image
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.scale = scale
        self.facing = facing
        self.footPadding = footPadding
        self.mouth = mouth
        self.animations = animations
        self.wardrobe = wardrobe
    }

    public struct Animation: Codable, Equatable, Sendable {
        public var row: Int
        public var start: Int?
        public var count: Int
        /// Frames per second. Defaults to 8.
        public var fps: Double?
        /// Play once and hold the last frame instead of looping.
        public var once: Bool?

        public init(row: Int, start: Int? = nil, count: Int, fps: Double? = nil, once: Bool? = nil) {
            self.row = row
            self.start = start
            self.count = count
            self.fps = fps
            self.once = once
        }

        /// Frame index (within this animation) `elapsed` seconds after it started.
        public func frame(at elapsed: TimeInterval) -> Int {
            let n = Int(max(0, elapsed) * (fps ?? 8))
            return once == true ? min(n, count - 1) : n % count
        }
    }

    public var facesLeft: Bool { facing == "left" }

    public func validate() throws {
        guard frameWidth > 0, frameHeight > 0 else { throw SpriteError(description: "frame size must be positive") }
        guard animations["idle"] != nil else { throw SpriteError(description: "an 'idle' animation is required") }
        for (name, animation) in animations where animation.count < 1 || animation.row < 0 || (animation.start ?? 0) < 0 {
            throw SpriteError(description: "animation '\(name)' has an invalid row, start or count")
        }
        for item in wardrobe ?? [] where !Wardrobe.isValidID(item) {
            throw SpriteError(description: "wardrobe item '\(item)' must be lowercase letters, digits and dashes")
        }
    }

    /// Animations to try for an activity, best first. Packs only need `idle`;
    /// anything missing falls back down the list.
    public static func candidates(for activity: Activity) -> [String] {
        switch activity {
        case .idle: return ["idle"]
        case .walking: return ["walk", "idle"]
        case .running: return ["run", "walk", "idle"]
        case .sleeping: return ["sleep", "lie", "sit", "idle"]
        case .sitting: return ["sit", "idle"]
        case .yelling: return ["bark", "sit", "idle"]
        case .whining: return ["beg", "lie", "sit", "idle"]
        case .eating: return ["eat", "sit", "idle"]
        case .burying: return ["dig", "sit", "idle"]
        case .pooping: return ["poop", "sit", "idle"]
        case .held: return ["held", "idle"]
        case .tumbling: return ["fall", "sleep", "sit", "idle"]
        case .tricking: return ["trick", "bark", "idle"]
        }
    }

    public func animation(for activity: Activity) -> (name: String, animation: Animation) {
        for name in Self.candidates(for: activity) {
            if let animation = animations[name] { return (name, animation) }
        }
        return ("idle", animations["idle"]!)
    }
}
