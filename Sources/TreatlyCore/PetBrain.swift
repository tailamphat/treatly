import Foundation

public protocol RandomSource {
    /// A value in 0..<1.
    mutating func next() -> Double
}

public struct SystemRandom: RandomSource {
    public init() {}
    public mutating func next() -> Double { Double.random(in: 0..<1) }
}

/// Deterministic, for checks.
public struct SeededRandom: RandomSource {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

public enum Activity: Equatable, Sendable {
    case idle, walking, sleeping
    /// At your window with the treat dropped in front of it.
    case sitting, yelling, whining
    /// Short reactions after Done / Snooze. Eating is followed by pooping.
    case eating, burying, pooping
    /// Being dragged by the mouse.
    case held
}

public enum Facing: Sendable { case left, right }

/// Where the pet is and what it is doing. It wanders left and right at its
/// current height (wherever it was put down) and walks straight to a bowl,
/// wherever the bowl is.
public struct PetBrain {
    public private(set) var x: Double
    public private(set) var y: Double
    public private(set) var facing: Facing = .right
    public private(set) var activity: Activity = .idle
    public private(set) var level: EscalationLevel = .calm
    public var walkSpeed: Double
    public var sleepiness: Double

    public static let reactionDuration: TimeInterval = 1.6
    public static let poopDuration: TimeInterval = 1.2

    private var timer: TimeInterval = 0
    private var wanderTarget: Double?
    /// Set while it walks to a bowl to take out the next treat.
    private var fetchTarget: (x: Double, y: Double)?

    public init(x: Double, y: Double, walkSpeed: Double, sleepiness: Double) {
        self.x = x
        self.y = y
        self.walkSpeed = walkSpeed
        self.sleepiness = sleepiness
    }

    /// 0 at the start of a reaction, 1 at the end.
    public var reactionProgress: Double {
        guard activity == .eating || activity == .burying else { return 0 }
        return 1 - max(0, timer) / Self.reactionDuration
    }

    public var isFetching: Bool { fetchTarget != nil }

    /// The treat is in its mouth.
    public var carriesTreat: Bool {
        level > .calm && fetchTarget == nil && [.idle, .walking, .held].contains(activity)
    }

    /// The treat is on the ground in front of it.
    public var treatOnGround: Bool {
        [.sitting, .yelling, .whining].contains(activity)
    }

    public mutating func update<R: RandomSource>(dt: TimeInterval, level: EscalationLevel, bounds: ClosedRange<Double>, focusX: Double, random: inout R) {
        switch activity {
        case .held:
            return
        case .eating, .burying, .pooping:
            timer -= dt
            guard timer <= 0 else { return }
            if activity == .eating {
                // What goes in must come out.
                activity = .pooping
                timer = Self.poopDuration
            } else {
                rest(for: 0.8)
            }
            return
        default:
            break
        }

        self.level = level
        if let target = fetchTarget {
            if level == .calm {
                fetchTarget = nil
            } else if walk(toward: target.x, target.y, dt: dt) {
                fetchTarget = nil
                rest(for: 0.6)
            }
            return
        }
        if level >= .dropping {
            if walk(toward: min(max(focusX, bounds.lowerBound), bounds.upperBound), y, dt: dt) {
                activity = level == .dropping ? .sitting : level == .barking ? .yelling : .whining
            }
            return
        }

        switch activity {
        case .walking:
            if let target = wanderTarget, walk(toward: target, y, dt: dt) {
                wanderTarget = nil
                rest(for: 1.5 + random.next() * 3)
            }
        case .sleeping:
            timer -= dt
            if level > .calm || timer <= 0 { rest(for: 0.5) }
        case .idle:
            timer -= dt
            guard timer <= 0 else { break }
            if level == .calm && random.next() < sleepiness {
                activity = .sleeping
                timer = 8 + random.next() * 12
            } else {
                let span = bounds.upperBound - bounds.lowerBound
                wanderTarget = bounds.lowerBound + random.next() * span
                activity = .walking
            }
        default:
            // Coming down from a higher level (e.g. after a snooze).
            rest(for: 0.5)
        }
    }

    /// Walk to the bowl at (`x`, `y`) and take out the next treat.
    public mutating func fetch(fromBowlAtX x: Double, y: Double) {
        fetchTarget = (x, y)
        wanderTarget = nil
        if ![.eating, .burying, .pooping, .held].contains(activity) { activity = .walking }
    }

    public mutating func celebrate() { react(.eating) }
    public mutating func bury() { react(.burying) }

    public mutating func pickUp() {
        activity = .held
        wanderTarget = nil
        fetchTarget = nil
    }

    public mutating func drag(toX x: Double, y: Double) {
        guard activity == .held else { return }
        if x != self.x { facing = x > self.x ? .right : .left }
        self.x = x
        self.y = y
    }

    public mutating func putDown() {
        guard activity == .held else { return }
        rest(for: 0.8)
    }

    private mutating func react(_ reaction: Activity) {
        activity = reaction
        timer = Self.reactionDuration
        wanderTarget = nil
    }

    private mutating func rest(for seconds: TimeInterval) {
        activity = .idle
        timer = seconds
    }

    /// Moves in a straight line. Returns true once it has arrived.
    private mutating func walk(toward tx: Double, _ ty: Double, dt: TimeInterval) -> Bool {
        let dx = tx - x, dy = ty - y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 1 { return true }
        activity = .walking
        if abs(dx) >= 1 { facing = dx > 0 ? .right : .left }
        let step = min(distance, walkSpeed * dt)
        x += dx / distance * step
        y += dy / distance * step
        return distance - step < 1
    }
}
