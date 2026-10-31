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
    case idle, walking, running, sleeping
    /// At your window with the treat dropped in front of it.
    case sitting, yelling, whining
    /// Short reactions after Done / Snooze. Eating is followed by pooping.
    case eating, burying, pooping
    /// Being dragged by the mouse.
    case held
    /// Tripped over its own feet while walking; gets up and carries on.
    case tumbling
    /// Showing off its special move, just for fun.
    case tricking
    /// Hanging from its tree and swinging, for fun.
    case swinging
    /// Sitting and bobbing along while the Mac plays music.
    case listening
}

public enum Facing: Sendable { case left, right }

/// How much get-up-and-go the pet has, set by the app from the Mac's battery.
public enum Energy: Equatable, Sendable {
    case normal
    /// Walks at half speed, never runs, naps twice as often.
    case tired
    /// Dozes most of the time and nags in short bursts.
    case sleepy

    public static let tiredBelow = 30
    public static let sleepyBelow = 10

    /// `percent` is nil on a Mac without a battery. Plugged in always means normal.
    public init(batteryPercent percent: Int?, charging: Bool) {
        guard let percent, !charging else { self = .normal; return }
        self = percent <= Self.sleepyBelow ? .sleepy : percent <= Self.tiredBelow ? .tired : .normal
    }
}

/// How a particular animal behaves. Every pet pack sets its own.
public struct Temperament: Equatable, Sendable {
    /// Points per second.
    public var walkSpeed: Double
    public var runSpeed: Double
    /// Chance (0...1) that a stroll turns into a run.
    public var energy: Double
    /// Chance (0...1) of a nap when it stops; much lower while it has a task.
    public var sleepiness: Double
    /// How long it stands around between moves, in seconds.
    public var rest: ClosedRange<Double>
    /// How long one nagging burst lasts.
    public var nagDuration: TimeInterval
    /// Scales the breaks between nagging bursts (above 1 = more patient).
    public var patience: Double
    /// Trips per minute of walking; running trips twice as often.
    public var clumsiness: Double
    /// Chance (0...1) of showing off a trick when it stops.
    public var playfulness: Double
    /// Chance (0...1) that, with nothing to do, it goes to swing on its tree.
    public var climbing: Double

    public init(walkSpeed: Double, runSpeed: Double? = nil, energy: Double = 0.15, sleepiness: Double = 0.25,
                rest: ClosedRange<Double> = 1.5...4.5, nagDuration: TimeInterval = 20, patience: Double = 1,
                clumsiness: Double = 0, playfulness: Double = 0, climbing: Double = 0) {
        self.walkSpeed = walkSpeed
        self.runSpeed = runSpeed ?? walkSpeed * 2.2
        self.energy = energy
        self.sleepiness = sleepiness
        self.rest = rest
        self.nagDuration = nagDuration
        self.patience = patience
        self.clumsiness = clumsiness
        self.playfulness = playfulness
        self.climbing = climbing
    }
}

/// Where the pet is and what it is doing. It wanders at its current height
/// (wherever it was put down), runs to bowls, and once a task is overdue it
/// nags in bursts with roaming breaks in between, so it never just sits there.
public struct PetBrain {
    public private(set) var x: Double
    public private(set) var y: Double
    public private(set) var facing: Facing = .right
    public private(set) var activity: Activity = .idle
    public private(set) var level: EscalationLevel = .calm
    public var temperament: Temperament

    public static let reactionDuration: TimeInterval = 1.6
    public static let poopDuration: TimeInterval = 1.2
    public static let tumbleDuration: TimeInterval = 1.6
    public static let trickDuration: TimeInterval = 4
    public static let swingDuration: TimeInterval = 5

    private var timer: TimeInterval = 0
    private var wanderTarget: Double?
    private var wanderRunning = false
    /// Set while it goes to a bowl to take out the next treat.
    private var fetchTarget: (x: Double, y: Double)?
    /// Where it can swing for fun (next to its tree), kept up to date by the app.
    public var playground: (x: Double, y: Double)?
    /// Set while it heads to the playground.
    private var playTarget: (x: Double, y: Double)?
    /// Set by the app while the Mac is playing music; the pet sits and listens along.
    public var musicPlaying = false
    /// Set by the app from the battery; a low battery makes the pet tired, then sleepy.
    public var energy: Energy = .normal
    /// Nagging comes in bursts: `nagging` flips when `nagClock` runs out.
    public private(set) var nagging = false
    private var nagClock: TimeInterval = 0

    public init(x: Double, y: Double, temperament: Temperament) {
        self.x = x
        self.y = y
        self.temperament = temperament
    }

    /// Seconds of roaming between nagging bursts; shorter the more overdue.
    public func breakDuration(at level: EscalationLevel) -> TimeInterval {
        let base: TimeInterval
        switch level {
        case .calm, .carrying: return .infinity
        case .dropping: base = 60
        case .barking: base = 45
        case .whining: base = 30
        }
        return base * temperament.patience
    }

    public var isFetching: Bool { fetchTarget != nil }

    /// 0 at the start of a reaction, 1 at the end.
    public var reactionProgress: Double {
        guard activity == .eating || activity == .burying else { return 0 }
        return 1 - max(0, timer) / Self.reactionDuration
    }

    /// The treat is in its mouth.
    public var carriesTreat: Bool {
        level > .calm && fetchTarget == nil && [.idle, .walking, .running, .held, .tricking, .listening].contains(activity)
    }

    /// The treat is on the ground in front of it (also when it tripped while carrying it).
    public var treatOnGround: Bool {
        [.sitting, .yelling, .whining].contains(activity) || activity == .tumbling && level > .calm && fetchTarget == nil
    }

    public mutating func update<R: RandomSource>(dt: TimeInterval, level: EscalationLevel, bounds: ClosedRange<Double>, random: inout R) {
        switch activity {
        case .held:
            return
        case .tumbling:
            timer -= dt
            if timer <= 0 { rest(for: 0.3) }
            return
        case .walking, .running:
            // Clumsy pets trip now and then. Only clumsy ones draw a random number.
            guard temperament.clumsiness > 0 else { break }
            let perSecond = temperament.clumsiness / 60 * (activity == .running ? 2 : 1)
            if random.next() < perSecond * dt {
                activity = .tumbling
                timer = Self.tumbleDuration
                return
            }
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

        let rising = level > self.level
        self.level = level
        updateNagging(dt: dt, rising: rising)

        if let target = fetchTarget {
            if level == .calm {
                fetchTarget = nil
            } else if move(toward: target.x, target.y, running: true, dt: dt) {
                fetchTarget = nil
                rest(for: 0.6)
            }
            return
        }

        if let target = playTarget {
            if level > .carrying {
                playTarget = nil
            } else if move(toward: target.x, target.y, running: false, dt: dt) {
                playTarget = nil
                activity = .swinging
                facing = .right
                timer = Self.swingDuration
            }
            return
        }

        if nagging {
            // Nags wherever it happens to be, so it shows up all over the screen, not just the middle.
            if move(toward: min(max(x, bounds.lowerBound), bounds.upperBound), y, running: true, dt: dt) {
                activity = level == .dropping ? .sitting : level == .barking ? .yelling : .whining
            }
            return
        }

        // Music on: stop wherever it is and listen along. Music off: back to normal.
        if musicPlaying {
            if activity != .listening { activity = .listening; wanderTarget = nil }
            return
        } else if activity == .listening {
            rest(for: 0.8)
            return
        }

        switch activity {
        case .walking, .running:
            if let target = wanderTarget {
                if move(toward: target, y, running: wanderRunning, dt: dt) {
                    wanderTarget = nil
                    rest(for: pick(temperament.rest, &random))
                }
            } else {
                rest(for: 0.3)
            }
        case .sleeping, .tricking, .swinging:
            timer -= dt
            if rising || timer <= 0 { rest(for: 0.5) }
        case .idle:
            timer -= dt
            guard timer <= 0 else { break }
            // Naps are rarer with a task to look after.
            var napChance = level == .calm ? temperament.sleepiness : temperament.sleepiness * 0.3
            if energy == .tired { napChance = min(1, napChance * 2) }
            if energy == .sleepy { napChance = 0.85 }
            if random.next() < napChance {
                activity = .sleeping
                timer = level == .calm ? 8 + random.next() * 12 : 4 + random.next() * 6
                if energy == .sleepy { timer *= 2 }
            } else if energy != .normal {
                // Too tired for tricks or swinging: just a slow stroll.
                let span = bounds.upperBound - bounds.lowerBound
                wanderTarget = bounds.lowerBound + random.next() * span
                wanderRunning = false
                activity = .walking
            } else if temperament.playfulness > 0, random.next() < temperament.playfulness {
                // Only playful pets draw this number, so other pets behave exactly as before.
                activity = .tricking
                timer = Self.trickDuration
            } else if level <= .carrying, temperament.climbing > 0, let spot = playground, random.next() < temperament.climbing {
                // Off to play on its tree (also with a task that isn't due yet; nagging comes first).
                playTarget = spot
                activity = .walking
            } else {
                let span = bounds.upperBound - bounds.lowerBound
                wanderTarget = bounds.lowerBound + random.next() * span
                wanderRunning = random.next() < temperament.energy
                activity = wanderRunning ? .running : .walking
            }
        default:
            // Back from a nagging burst or a snooze.
            rest(for: 0.5)
        }
    }

    /// Starts a burst right away when things get worse, then alternates
    /// bursts and breaks.
    private mutating func updateNagging(dt: TimeInterval, rising: Bool) {
        guard level >= .dropping else {
            nagging = false
            nagClock = 0
            return
        }
        if rising {
            nagging = true
            nagClock = 0
            return
        }
        nagClock += dt
        let burst = energy == .sleepy ? temperament.nagDuration / 2 : temperament.nagDuration
        if nagging, nagClock >= burst {
            nagging = false
            nagClock = 0
            rest(for: 0.5)
        } else if !nagging, nagClock >= breakDuration(at: level) {
            nagging = true
            nagClock = 0
        }
    }

    /// Run to the bowl at (`x`, `y`) and take out the next treat.
    public mutating func fetch(fromBowlAtX x: Double, y: Double) {
        fetchTarget = (x, y)
        wanderTarget = nil
        playTarget = nil
        if ![.eating, .burying, .pooping, .held].contains(activity) { activity = .running }
    }

    public mutating func celebrate() { react(.eating) }
    public mutating func bury() { react(.burying) }

    public mutating func pickUp() {
        activity = .held
        wanderTarget = nil
        fetchTarget = nil
        playTarget = nil
    }

    public mutating func drag(toX x: Double, y: Double) {
        guard activity == .held else { return }
        if x != self.x { facing = x > self.x ? .right : .left }
        self.x = x
        self.y = y
    }

    /// Moves it without changing what it is doing, e.g. back onto a display.
    public mutating func place(x: Double, y: Double) {
        self.x = x
        self.y = y
        wanderTarget = nil
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

    private func pick<R: RandomSource>(_ range: ClosedRange<Double>, _ random: inout R) -> Double {
        range.lowerBound + random.next() * (range.upperBound - range.lowerBound)
    }

    /// Moves in a straight line. Returns true once it has arrived.
    private mutating func move(toward tx: Double, _ ty: Double, running: Bool, dt: TimeInterval) -> Bool {
        let dx = tx - x, dy = ty - y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < 1 { return true }
        // A tired pet never runs and drags its feet.
        let running = running && energy == .normal
        activity = running ? .running : .walking
        if abs(dx) >= 1 { facing = dx > 0 ? .right : .left }
        let speed = running ? temperament.runSpeed : energy == .normal ? temperament.walkSpeed : temperament.walkSpeed / 2
        let step = min(distance, speed * dt)
        x += dx / distance * step
        y += dy / distance * step
        return distance - step < 1
    }
}
