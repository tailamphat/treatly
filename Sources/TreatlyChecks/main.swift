import Foundation
import TreatlyCore

var failures = 0
var passed = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
func task(_ id: String, due: TimeInterval? = nil, priority: Priority = .none, source: TaskSourceKind = .appleReminders) -> TaskItem {
    TaskItem(source: source, sourceID: id, title: id, dueDate: due.map { now.addingTimeInterval($0) }, priority: priority)
}

// MARK: Priority

check(Priority(eventKitValue: 1) == .high, "EventKit 1 is high")
check(Priority(eventKitValue: 5) == .medium, "EventKit 5 is medium")
check(Priority(eventKitValue: 9) == .low, "EventKit 9 is low")
check(Priority(eventKitValue: 0) == .none, "EventKit 0 is none")

// MARK: DueDate

do {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let dateOnly = DateComponents(year: 2026, month: 10, day: 29)
    let resolved = DueDate.resolve(dateOnly, calendar: cal)!
    check(cal.component(.hour, from: resolved) == 23 && cal.component(.minute, from: resolved) == 59, "date-only due resolves to end of day")
    let timed = DateComponents(year: 2026, month: 10, day: 29, hour: 9, minute: 30)
    check(cal.component(.hour, from: DueDate.resolve(timed, calendar: cal)!) == 9, "timed due keeps its hour")
    check(DueDate.resolve(nil, calendar: cal) == nil, "no components, no due date")
}

// MARK: TaskSelector

check(TaskSelector.current(from: [], now: now) == nil, "no tasks, no current task")
check(TaskSelector.current(from: [task("future", due: 3600, priority: .high), task("late", due: -60)], now: now)?.sourceID == "late", "overdue beats high priority")
check(TaskSelector.current(from: [task("late", due: -60), task("later", due: -7200)], now: now)?.sourceID == "later", "most overdue first")
check(TaskSelector.current(from: [task("low", due: 60, priority: .low), task("high", due: 7200, priority: .high)], now: now)?.sourceID == "high", "higher priority first when nothing is overdue")
check(TaskSelector.current(from: [task("undated"), task("dated", due: 7200)], now: now)?.sourceID == "dated", "dated before undated")
check(TaskSelector.current(from: [task("b"), task("a")], now: now)?.sourceID == "a", "ties break by title")
do {
    let tasks = [task("snoozed", due: -60), task("other")]
    let hidden = ["appleReminders:snoozed": now.addingTimeInterval(600)]
    check(TaskSelector.current(from: tasks, now: now, hiddenUntil: hidden)?.sourceID == "other", "hidden tasks are skipped")
    let expired = ["appleReminders:snoozed": now.addingTimeInterval(-1)]
    check(TaskSelector.current(from: tasks, now: now, hiddenUntil: expired)?.sourceID == "snoozed", "tasks come back when hiding expires")
}
check(task("x").id == "appleReminders:x", "ids carry their source")

// MARK: EscalationPolicy

do {
    let policy = EscalationPolicy(step: 600)
    func level(_ t: TaskItem?, since: TimeInterval = 0) -> EscalationLevel {
        policy.level(for: t, becameCurrentAt: now.addingTimeInterval(-since), now: now)
    }
    check(level(nil) == .calm, "no task is calm")
    check(level(task("t", due: 3600)) == .carrying, "before due: carrying")
    check(level(task("t", due: -300)) == .carrying, "just overdue: still carrying")
    check(level(task("t", due: -900)) == .dropping, "one step overdue: dropping")
    check(level(task("t", due: -1500)) == .barking, "two steps overdue: barking")
    check(level(task("t", due: -86400)) == .whining, "long overdue: whining")
    check(level(task("t"), since: 0) == .carrying, "undated starts carrying")
    check(level(task("t"), since: 1300) == .barking, "undated escalates from when it became current")
}

// MARK: PixelSprite

check(RGBA(hex: "#FF0000") == RGBA(hex: "FF0000FF"), "hex with and without alpha")
check(RGBA(hex: "#XYZ") == nil, "bad hex rejected")
do {
    let ragged = PixelSprite(palette: ["a": "#000000"], rows: ["aa", "a"])
    check((try? ragged.validate()) == nil, "ragged rows rejected")
    let unknown = PixelSprite(palette: ["a": "#000000"], rows: ["ab"])
    check((try? unknown.validate()) == nil, "unknown palette char rejected")
    let ok = PixelSprite(palette: ["a": "#000000"], rows: [".a"])
    check((try? ok.validate()) != nil, "valid sprite accepted")
    check(ok.grid()[0][0] == nil && ok.grid()[0][1] != nil, "grid maps . to transparent")
}

// MARK: PhraseFormatter

check(PhraseFormatter.format("{name}: {task}!", task: "Ship it", name: "Mochi") == "Mochi: Ship it!", "phrase placeholders")

// MARK: Bundled pet packs

do {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let result = PetPackLoader.load(from: [repo.appendingPathComponent("Pets")])
    check(result.errors.isEmpty, "bundled packs load cleanly: \(result.errors)")
    let ids = Set(result.packs.map(\.id))
    check(ids == ["shiba", "golden", "husky", "chihuahua", "orange-tabby", "black-cat", "sheep", "kong"], "all eight bundled packs present, got \(ids)")
    for pack in result.packs {
        let folder = pack.folder!
        if let image = pack.treat.image {
            check(FileManager.default.fileExists(atPath: folder.appendingPathComponent(image).path), "\(pack.id) treat image exists")
        }
        if let sheet = pack.sheet {
            check(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sheet.image).path), "\(pack.id) sheet image exists")
        }
    }
}

// MARK: Pack file safety

check(PetPack.isPlainFileName("sheet.png"), "plain file name allowed")
check(!PetPack.isPlainFileName("../../secret.png"), "parent paths rejected")
check(!PetPack.isPlainFileName("/etc/x.png"), "absolute paths rejected")
check(!PetPack.isPlainFileName(".hidden.png"), "hidden files rejected")

// MARK: SpriteSheet

do {
    let walk = SpriteSheet.Animation(row: 1, count: 4, fps: 4)
    check(walk.frame(at: 0) == 0 && walk.frame(at: 0.5) == 2 && walk.frame(at: 1.1) == 0, "looping animation wraps")
    let once = SpriteSheet.Animation(row: 0, count: 3, fps: 10, once: true)
    check(once.frame(at: 5) == 2, "play-once animation holds the last frame")
    let sheet = SpriteSheet(image: "s.png", frameWidth: 10, frameHeight: 10, animations: ["idle": .init(row: 0, count: 1), "sit": .init(row: 1, count: 1)])
    check(sheet.animation(for: .yelling).name == "sit", "missing bark falls back to sit")
    check(sheet.animation(for: .walking).name == "idle", "missing walk falls back to idle")
    let noIdle = SpriteSheet(image: "s.png", frameWidth: 10, frameHeight: 10, animations: ["walk": .init(row: 0, count: 1)])
    check((try? noIdle.validate()) == nil, "a sheet needs an idle animation")
}

// MARK: Personality

do {
    let json = #"{"walkSpeed": 80, "sleepiness": 0.1, "energy": 0.7, "rest": [0.5, 1.5], "nagSeconds": 25, "patience": 0.6}"#
    let p = try! JSONDecoder().decode(PetPack.Personality.self, from: Data(json.utf8))
    check(p.temperament.energy == 0.7 && p.temperament.rest == 0.5...1.5 && p.temperament.nagDuration == 25, "personality fields map to temperament")
    let minimal = try! JSONDecoder().decode(PetPack.Personality.self, from: Data(#"{"walkSpeed": 50, "sleepiness": 0.2}"#.utf8))
    check(abs(minimal.temperament.runSpeed - 110) < 0.001 && minimal.temperament.patience == 1, "missing personality fields get defaults")
}

// MARK: Bowls

do {
    let tasks = [task("a"), task("b")]
    let bowls = BowlLayout.bowls(for: [.appleReminders], tasks: tasks, bounds: 0...1000)
    check(bowls.map(\.source) == [.appleReminders], "one bowl for Reminders")
    check(bowls.map(\.x) == [60], "a single bowl sits on the left, inset from the end")
    check(bowls.map(\.treatCount) == [2], "the bowl counts its treats")
    check(BowlLayout.bowls(for: [], tasks: tasks, bounds: 0...1000).isEmpty, "no sources, no bowls")
}

// MARK: PetBrain

do {
    var rng = SeededRandom(seed: 1)
    var brain = PetBrain(x: 100, y: 0, temperament: Temperament(walkSpeed: 100, sleepiness: 0))
    for _ in 0..<200 { brain.update(dt: 0.05, level: .dropping, bounds: 0...1000, focusX: 500, random: &rng) }
    check(abs(brain.x - 500) < 1 && brain.activity == .sitting, "dropping: walks to focus and sits")
    check(brain.treatOnGround && !brain.carriesTreat, "dropping: treat on the ground")

    brain.update(dt: 0.05, level: .barking, bounds: 0...1000, focusX: 500, random: &rng)
    check(brain.activity == .yelling, "barking: yells once there")

    brain.celebrate()
    check(brain.activity == .eating, "celebrate starts eating")
    for _ in 0..<34 { brain.update(dt: 0.05, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(brain.activity == .pooping, "eating is followed by pooping")
    for _ in 0..<26 { brain.update(dt: 0.05, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(brain.activity != .pooping && brain.activity != .eating, "pooping ends, back to normal")
    brain.bury()
    for _ in 0..<34 { brain.update(dt: 0.05, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(brain.activity != .pooping, "burying is not followed by pooping")

    var sleepy = PetBrain(x: 100, y: 0, temperament: Temperament(walkSpeed: 100, sleepiness: 1))
    for _ in 0..<5 { sleepy.update(dt: 0.5, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(sleepy.activity == .sleeping, "calm and sleepy: naps")
    sleepy.update(dt: 0.05, level: .carrying, bounds: 0...1000, focusX: 500, random: &rng)
    check(sleepy.activity == .idle, "a new task wakes it up")

    var fetcher = PetBrain(x: 500, y: 0, temperament: Temperament(walkSpeed: 100, sleepiness: 0))
    fetcher.fetch(fromBowlAtX: 60, y: 300)
    fetcher.update(dt: 0.05, level: .carrying, bounds: 0...1000, focusX: 500, random: &rng)
    check(!fetcher.carriesTreat && fetcher.facing == .left, "fetching: heads to the bowl empty-mouthed")
    check(fetcher.activity == .running, "fetching: runs to the bowl")
    for _ in 0..<400 where fetcher.isFetching { fetcher.update(dt: 0.05, level: .carrying, bounds: 0...1000, focusX: 500, random: &rng) }
    check(!fetcher.isFetching && fetcher.carriesTreat, "fetching: carries the treat after reaching the bowl")
    check(abs(fetcher.x - 60) < 1 && abs(fetcher.y - 300) < 1, "fetching: walks to the bowl wherever it is")
    for _ in 0..<100 { fetcher.update(dt: 0.05, level: .carrying, bounds: 0...1000, focusX: 500, random: &rng) }
    check(abs(fetcher.y - 300) < 0.001, "wandering keeps its height")

    var held = PetBrain(x: 100, y: 0, temperament: Temperament(walkSpeed: 100, sleepiness: 0))
    held.pickUp()
    held.drag(toX: 300, y: 400)
    held.update(dt: 1, level: .whining, bounds: 0...1000, focusX: 900, random: &rng)
    check(held.x == 300 && held.activity == .held, "held: ignores escalation and stays put")
    held.putDown()
    check(held.activity == .idle && held.y == 400, "put down: stays where it was dropped")
    for _ in 0..<200 { held.update(dt: 0.05, level: .dropping, bounds: 0...1000, focusX: 500, random: &rng) }
    check(held.activity == .sitting && held.y == 400, "dropping: walks to focus at its own height")

    // Nagging comes in bursts, then it roams, then it comes back.
    var nagger = PetBrain(x: 500, y: 0, temperament: Temperament(walkSpeed: 100, sleepiness: 0, nagDuration: 5, patience: 0.1))
    for _ in 0..<40 { nagger.update(dt: 0.1, level: .whining, bounds: 0...1000, focusX: 500, random: &rng) }
    check(nagger.nagging && nagger.activity == .whining, "whining: starts with a nagging burst")
    for _ in 0..<15 { nagger.update(dt: 0.1, level: .whining, bounds: 0...1000, focusX: 500, random: &rng) }
    check(!nagger.nagging && nagger.activity != .whining, "after the burst it takes a break instead of sitting forever")
    for _ in 0..<40 { nagger.update(dt: 0.1, level: .whining, bounds: 0...1000, focusX: 500, random: &rng) }
    check(nagger.nagging, "after the break it nags again")
    check(PetBrain(x: 0, y: 0, temperament: Temperament(walkSpeed: 1, patience: 2)).breakDuration(at: .whining) == 60, "patience stretches the breaks")

    // Personalities differ.
    var zoomy = PetBrain(x: 500, y: 0, temperament: Temperament(walkSpeed: 100, energy: 1, sleepiness: 0, rest: 0...0.1))
    for _ in 0..<3 { zoomy.update(dt: 0.1, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(zoomy.activity == .running, "an energetic pet runs when it wanders")
    var lazy = PetBrain(x: 500, y: 0, temperament: Temperament(walkSpeed: 100, energy: 0, sleepiness: 0, rest: 0...0.1))
    for _ in 0..<3 { lazy.update(dt: 0.1, level: .calm, bounds: 0...1000, focusX: 500, random: &rng) }
    check(lazy.activity == .walking, "a calm pet walks when it wanders")
}

// MARK: Poop

check(PoopStyle(stored: nil) == .cute && PoopStyle(stored: "nope") == .cute, "poop style defaults to cute")
check(PoopStyle(stored: "rainbow") == .rainbow, "stored poop style is read back")
check(PoopStyle.off.artName == nil && PoopStyle.golden.artName == "poop-golden", "poop art names")
do {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for style in PoopStyle.allCases {
        guard let name = style.artName else { continue }
        check(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Resources/Art/\(name).png").path), "\(name).png exists")
    }
}

// MARK: Bowl styles

check(BowlStyle(stored: nil) == .classic && BowlStyle(stored: "nope") == .classic, "bowl style defaults to classic")
check(BowlStyle(stored: "tub") == .tub, "stored bowl style is read back")
do {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for style in BowlStyle.allCases {
        for source in TaskSourceKind.allCases {
            let names = style.artNames(for: source)
            for name in [names.back, names.front] {
                check(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Resources/Art/\(name).png").path), "\(name).png exists")
            }
        }
    }
}

// MARK: Wardrobe

do {
    check(Wardrobe.isValidID("party-hat") && !Wardrobe.isValidID("../hat") && !Wardrobe.isValidID("Hat") && !Wardrobe.isValidID(""), "wardrobe ids are simple")
    check(Wardrobe.fileName(for: "bow") == "wear-bow.png", "wardrobe file name")
    check(Wardrobe.name(for: "glasses") == "Sunglasses" && Wardrobe.name(for: "top-hat") == "Top Hat", "wardrobe display names")
    let idle = ["idle": SpriteSheet.Animation(row: 0, count: 1)]
    let sheet = SpriteSheet(image: "s.png", frameWidth: 8, frameHeight: 8, animations: idle, wardrobe: ["top-hat", "crown", "bow"])
    check(Wardrobe.items(in: sheet) == ["bow", "crown", "top-hat"], "wardrobe in catalogue order, extras last")
    check((try? sheet.validate()) != nil, "valid wardrobe accepted")
    let bad = SpriteSheet(image: "s.png", frameWidth: 8, frameHeight: 8, animations: idle, wardrobe: ["../../x"])
    check((try? bad.validate()) == nil, "path-like wardrobe id rejected")
    check(Wardrobe.items(in: nil).isEmpty, "no sheet, no wardrobe")
}

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
