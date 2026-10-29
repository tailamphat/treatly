import AppKit
import TreatlyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    private(set) var packs: [PetPack] = []
    private(set) var pack: PetPack!

    private(set) var reminders: RemindersSource!
    var sources: [TaskSource] { [reminders] }

    /// Every incomplete task from every connected source.
    private(set) var tasks: [TaskItem] = []
    /// Chosen from a bowl; beats the automatic pick while it exists.
    private var pinnedTaskID: String?
    private(set) var current: TaskItem?
    private(set) var level: EscalationLevel = .calm
    private var settingsPanel: SettingsPanel?
    weak var statusButton: NSStatusBarButton?
    var statusButtonFrame: NSRect { statusButton?.window?.frame ?? .zero }
    private var lastSettingsPoke = 0
    private var becameCurrentAt = Date()

    private var brain: PetBrain!
    private var random = SystemRandom()
    private var lastTick = Date()
    private var bubbleKey = ""
    private var bubbleText: String?
    /// Done/Snooze clear the current task; reactions still name it.
    private var lastTaskTitle = ""
    private var lastActivity: Activity = .idle
    private var activityStart = Date()

    private var petWindow: OverlayWindow!
    private var petView: PetView!
    private var bowlWindows: [TaskSourceKind: (window: OverlayWindow, view: BowlView)] = [:]
    private var statusMenu: StatusMenu!
    private var poops: [(window: OverlayWindow, view: PoopView, expires: Date)] = []
    private var refreshing = false

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadPacks()

        reminders = RemindersSource(
            selectedListIDs: { [settings] in settings.selectedLists(for: .appleReminders) },
            isEnabled: { [settings] in settings.remindersEnabled }
        )
        for source in sources { source.onChange = { [weak self] in self?.refresh() } }

        let ground = Ground.current()
        brain = PetBrain(x: (ground.minX + ground.maxX) / 2, y: ground.y, temperament: pack.personality.temperament)

        petView = PetView(frame: NSRect(origin: .zero, size: PetView.size))
        petView.delegate = self
        petWindow = OverlayWindow(size: PetView.size)
        petWindow.contentView = petView
        applyPack()
        petWindow.orderFrontRegardless()

        statusMenu = StatusMenu(app: self)

        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Reminders pushes changes; this is a periodic catch-up.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutBowls() }
        }

        Task {
            _ = await reminders.requestAccess()
            refresh()
        }
        // Demo mode: another process can post this to press "Done".
        if ProcessInfo.processInfo.environment["TREATLY_DEMO"] != nil {
            DistributedNotificationCenter.default().addObserver(forName: .init("io.github.treatly.demo.done"), object: nil, queue: .main) { [weak self] _ in
                // Only ever fake tasks: any local process can post this.
                MainActor.assumeIsolated {
                    guard let self, self.current?.sourceID.hasPrefix("demo") == true else { return }
                    self.completeCurrent()
                }
            }
            DistributedNotificationCenter.default().addObserver(forName: .init("io.github.treatly.demo.settings"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.openSettings(near: NSPoint(x: 900, y: 200)) }
            }
        }
    }

    private func loadPacks() {
        var dirs: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Pets") { dirs.append(bundled) }
        if let dev = ProcessInfo.processInfo.environment["TREATLY_PETS_DIR"] { dirs.append(URL(fileURLWithPath: dev)) }
        dirs.append(Self.userPetsFolder)
        let result = PetPackLoader.load(from: dirs)
        for error in result.errors { NSLog("Treatly: skipped pet pack: %@", error) }
        packs = result.packs
        guard let chosen = packs.first(where: { $0.id == settings.petID }) ?? packs.first else {
            fatalError("No pet packs found. Run the app from Treatly.app or set TREATLY_PETS_DIR.")
        }
        pack = chosen
    }

    static var userPetsFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Treatly/Pets")
    }

    func setBowlStyle(_ style: BowlStyle) {
        settings.bowlStyle = style
        rebuildBowls()
    }

    private func rebuildBowls() {
        for (_, bowl) in bowlWindows { bowl.window.orderOut(nil) }
        bowlWindows = [:]
        layoutBowls()
    }

    private func applyPack() {
        petView.art = PetArt(pack: pack)
        petView.wearing = wearing
        brain.temperament = pack.personality.temperament
        bubbleKey = ""
        // Each pet brings its own containers (bowls, banana trees...).
        rebuildBowls()
    }

    var petName: String { settings.petName(for: pack) }

    var wearing: String? { settings.wearing(for: pack) }

    /// Wardrobe items the current pet has art for.
    var wardrobe: [String] { petView.art?.wardrobe ?? [] }

    func setWearing(_ item: String?) {
        settings.setWearing(item, for: pack)
        petView.wearing = item
    }

    func selectPack(_ newPack: PetPack) {
        pack = newPack
        settings.petID = newPack.id
        applyPack()
    }

    // MARK: Tasks

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            var all: [TaskItem] = []
            for source in sources where source.isConnected {
                do {
                    all += try await source.fetch()
                } catch {
                    NSLog("Treatly: %@ refresh failed: %@", source.kind.displayName, error.localizedDescription)
                    // Keep showing what we had rather than emptying the bowl.
                    all += tasks.filter { $0.source == source.kind }
                }
            }
            // Dev aid for screenshots: TREATLY_DEMO=1 adds fake tasks.
            if ProcessInfo.processInfo.environment["TREATLY_DEMO"] != nil {
                all += Self.demoTasks
            }
            tasks = all
            refreshing = false
            layoutBowls()
        }
    }

    private static let demoTasks: [TaskItem] = [
        TaskItem(source: .appleReminders, sourceID: "demo1", title: "Write the report", dueDate: Date().addingTimeInterval(-1500), priority: .high),
        TaskItem(source: .appleReminders, sourceID: "demo2", title: "Call the dentist"),
        TaskItem(source: .appleReminders, sourceID: "demo3", title: "Water the plants"),
        TaskItem(source: .appleReminders, sourceID: "demo4", title: "Review PR"),
    ]

    private func pickCurrent(now: Date) -> TaskItem? {
        let hidden = settings.hiddenUntil
        if let pinned = pinnedTaskID, let task = tasks.first(where: { $0.id == pinned }), (hidden[pinned] ?? .distantPast) <= now {
            return task
        }
        pinnedTaskID = nil
        return TaskSelector.current(from: tasks, now: now, hiddenUntil: hidden)
    }

    func pin(_ task: TaskItem) {
        pinnedTaskID = task.id
        var hidden = settings.hiddenUntil
        hidden[task.id] = nil
        settings.hiddenUntil = hidden
    }

    func completeCurrent() {
        guard let task = current, let source = source(for: task) else { return }
        brain.celebrate()
        playSound()
        tasks.removeAll { $0.id == task.id }
        layoutBowls()
        Task {
            do { try await source.complete(task) } catch { show(error) }
            refresh()
        }
    }

    func snoozeCurrent(for interval: TimeInterval) {
        guard let task = current, let source = source(for: task) else { return }
        brain.bury()
        let until = Date().addingTimeInterval(interval)
        hide(task, until: until)
        Task {
            do { try await source.snooze(task, until: until) } catch { show(error) }
        }
    }

    /// Skip to another treat for a while without changing the task.
    func skipCurrent() {
        guard let task = current else { return }
        hide(task, until: Date().addingTimeInterval(30 * 60))
    }

    private func hide(_ task: TaskItem, until: Date) {
        if pinnedTaskID == task.id { pinnedTaskID = nil }
        var hidden = settings.hiddenUntil.filter { $0.value > Date() }
        hidden[task.id] = until
        settings.hiddenUntil = hidden
    }

    private func source(for task: TaskItem) -> TaskSource? {
        sources.first { $0.kind == task.source }
    }

    func setPetName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.setPetName(trimmed, for: pack)
        bubbleKey = ""
    }

    func selectAllLists(for kind: TaskSourceKind) {
        settings.setSelectedLists([], for: kind)
        refresh()
    }

    func toggleList(_ id: String, for kind: TaskSourceKind) {
        var ids = settings.selectedLists(for: kind)
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        settings.setSelectedLists(ids, for: kind)
        refresh()
    }

    func openPetsFolder() {
        let folder = Self.userPetsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// The settings page, opened by right-clicking the pet or a bowl.
    func openSettings(near point: NSPoint) {
        let panel = settingsPanel ?? SettingsPanel(model: SettingsModel(app: self))
        settingsPanel = panel
        panel.model.poke()
        let size = panel.frame.size
        let ground = Ground.current()
        let origin = NSPoint(x: point.x - size.width / 2, y: point.y + 20)
        panel.setFrameOrigin(ground.clamp(origin, size: size))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func renamePet() {
        let alert = NSAlert()
        alert.messageText = "Name your \(pack.name)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = petName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { settings.setPetName(name, for: pack) }
        bubbleKey = ""
    }

    private func show(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Treatly"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Bowls

    private func layoutBowls() {
        let ground = Ground.current()
        // A source gets a bowl when connected, or when it has tasks (demo mode).
        let connected = sources.filter { source in source.isConnected || tasks.contains { $0.source == source.kind } }.map(\.kind)
        let bowls = BowlLayout.bowls(for: connected, tasks: tasks, bounds: ground.minX...ground.maxX)

        for kind in TaskSourceKind.allCases where !connected.contains(kind) {
            bowlWindows[kind]?.window.orderOut(nil)
        }
        for bowl in bowls {
            let entry = bowlWindows[bowl.source] ?? makeBowlWindow(for: bowl.source)
            entry.view.treatCount = bowl.treatCount
            // Dragged bowls stay where they were put; others start on the ground.
            let size = entry.view.bounds.size
            let origin = settings.bowlPosition(for: bowl.source) ?? NSPoint(x: bowl.x - size.width / 2, y: ground.y)
            entry.window.setFrameOrigin(ground.clamp(origin, size: size))
            entry.window.orderFrontRegardless()
        }
        // Keep the pet in front of its bowls.
        petWindow.orderFrontRegardless()
    }

    private func makeBowlWindow(for source: TaskSourceKind) -> (window: OverlayWindow, view: BowlView) {
        let view = BowlView(source: source, style: ContainerStyle(pack: pack), bowlStyle: settings.bowlStyle)
        view.delegate = self
        view.treat = petView.art?.treat
        let window = OverlayWindow(size: view.bounds.size)
        window.contentView = view
        bowlWindows[source] = (window, view)
        return (window, view)
    }

    // MARK: Frame loop

    private func tick() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastTick), 0.1)
        lastTick = now
        let ground = Ground.current()

        let next = pickCurrent(now: now)
        if next?.id != current?.id {
            becameCurrentAt = now
            if let next, let bowl = bowlWindows[next.source]?.window.frame, bowlWindows[next.source]?.window.isVisible == true {
                brain.fetch(fromBowlAtX: bowl.midX, y: bowl.minY)
            }
        }
        current = next

        let policy = EscalationPolicy(step: TimeInterval(settings.nagStepMinutes * 60))
        level = policy.level(for: current, becameCurrentAt: becameCurrentAt, now: now)
        // Keep an open settings page roughly live without redrawing it every frame.
        if let panel = settingsPanel, panel.isVisible, Int(now.timeIntervalSince1970) != lastSettingsPoke {
            lastSettingsPoke = Int(now.timeIntervalSince1970)
            panel.model.poke()
        }
        let focusX = (ground.minX + ground.maxX) / 2
        brain.update(dt: dt, level: level, bounds: ground.walkBounds, focusX: focusX, random: &random)

        if brain.activity != lastActivity {
            if brain.activity == .yelling || brain.activity == .whining { playSound() }
            if brain.activity == .pooping { dropPoop(now: now) }
            lastActivity = brain.activity
            activityStart = now
        }

        agePoops(now: now)

        var frame = PetFrame()
        frame.activity = brain.activity
        frame.facing = brain.facing
        frame.carriesTreat = brain.carriesTreat
        frame.treatOnGround = brain.treatOnGround
        frame.reactionProgress = brain.reactionProgress
        frame.time = now.timeIntervalSinceReferenceDate
        frame.activityElapsed = now.timeIntervalSince(activityStart)
        if let current {
            frame.treatScale = current.priority == .high ? 1.4 : current.priority == .medium ? 1.15 : 1
            frame.stinky = current.isOverdue(at: now)
        }
        frame.bubble = bubble(now: now)
        petView.frameState = frame
        petView.toolTip = current.map { "\(pack.treat.name.capitalized): \($0.title)" }

        let origin = NSPoint(x: brain.x - PetView.size.width / 2, y: brain.y)
        if petWindow.frame.origin != origin { petWindow.setFrameOrigin(origin) }

        // Only catch the mouse over the pet itself, so the rest of the window
        // never blocks clicks meant for other apps.
        let hit = petView.interactiveRect.offsetBy(dx: origin.x, dy: origin.y)
        petWindow.ignoresMouseEvents = brain.activity != .held && !hit.contains(NSEvent.mouseLocation)
    }

    /// Leaves a poop behind the pet for 10 to 15 seconds, unless poop is off.
    private func dropPoop(now: Date) {
        guard let art = PoopView.art(for: settings.poopStyle) else { return }
        let size = PoopView.size(for: art)
        let behind = (petView.art?.pointSize.width ?? 80) * 0.4
        let x = brain.facing == .right ? brain.x - behind : brain.x + behind
        let view = PoopView(art: art)
        let window = OverlayWindow(size: size)
        window.contentView = view
        window.ignoresMouseEvents = true
        window.setFrameOrigin(Ground.current().clamp(NSPoint(x: x - size.width / 2, y: brain.y + PetView.groundPad - 2), size: size))
        window.orderFrontRegardless()
        petWindow.orderFrontRegardless()
        poops.append((window, view, now.addingTimeInterval(.random(in: 10...15))))
    }

    /// Fades poops out over their last second and a half, then removes them.
    private func agePoops(now: Date) {
        poops.removeAll { poop in
            let left = poop.expires.timeIntervalSince(now)
            if left <= 0 {
                poop.window.orderOut(nil)
                return true
            }
            poop.view.opacity = CGFloat(min(1, left / 1.5))
            return false
        }
    }

    /// Picks a phrase when the situation changes, then keeps it steady.
    private func bubble(now: Date) -> String? {
        let p = pack.phrases
        let list: [String]?
        switch brain.activity {
        case .eating: list = p.happy
        case .burying: list = p.bury
        case .pooping: list = ["*plop*"]
        case .sitting: list = p.drop
        case .yelling: list = p.yell
        case .whining: list = p.whine
        case .sleeping: list = ["z z z"]
        case .held: list = ["Wheee!"]
        case .idle, .walking, .running:
            // While carrying, flash the task now and then.
            let showing = brain.carriesTreat && Int(now.timeIntervalSince(becameCurrentAt)) % 30 < 5
            list = showing ? p.carry : nil
        }
        let key = "\(brain.activity)|\(current?.id ?? "")|\(list != nil)"
        if key != bubbleKey {
            bubbleKey = key
            if let current { lastTaskTitle = current.title }
            bubbleText = list?.randomElement().map { PhraseFormatter.format($0, task: lastTaskTitle, name: petName) }
        }
        return bubbleText
    }

    private func playSound() {
        guard settings.soundOn, let name = pack.sound else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

// MARK: - Pet interaction

extension AppDelegate: PetViewDelegate {
    func petClicked(_ view: PetView, event: NSEvent) {
        let menu = NSMenu()
        if let current {
            let header = NSMenuItem(title: "\(pack.treat.name.capitalized): \(current.title)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
            menu.addItem(actionItem("Done (\(petName) eats it)") { $0.completeCurrent() })
            menu.addItem(actionItem("Snooze 10 min") { $0.snoozeCurrent(for: 10 * 60) })
            menu.addItem(actionItem("Snooze 1 hour") { $0.snoozeCurrent(for: 60 * 60) })
            menu.addItem(actionItem("Next treat") { $0.skipCurrent() })
        } else {
            let header = NSMenuItem(title: "No treats right now", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func petRightClicked(_ view: PetView) {
        openSettings(near: NSEvent.mouseLocation)
    }

    func petDragBegan() {
        brain.pickUp()
    }

    /// The pet stays wherever it is dropped; it doesn't fall back to the ground.
    func petDragged(to screenPoint: NSPoint) {
        let ground = Ground.current()
        let x = min(max(screenPoint.x, ground.walkBounds.lowerBound), ground.walkBounds.upperBound)
        let y = min(max(screenPoint.y - 30, ground.y), ground.maxY - PetView.size.height)
        brain.drag(toX: x, y: y)
    }

    func petDragEnded() {
        brain.putDown()
    }

    func actionItem(_ title: String, _ action: @escaping (AppDelegate) -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title) { [weak self] in if let self { action(self) } }
        return item
    }
}

extension AppDelegate: BowlViewDelegate {
    func bowlRightClicked(_ view: BowlView) {
        openSettings(near: NSEvent.mouseLocation)
    }

    func bowlDragged(_ view: BowlView, to origin: NSPoint) {
        guard let window = view.window else { return }
        window.setFrameOrigin(Ground.current().clamp(origin, size: window.frame.size))
    }

    func bowlDropped(_ view: BowlView) {
        guard let window = view.window else { return }
        settings.setBowlPosition(window.frame.origin, for: view.source)
        // Head for the bowl's new spot if the pet was on its way.
        if brain.isFetching { brain.fetch(fromBowlAtX: window.frame.midX, y: window.frame.minY) }
    }

    func bowlClicked(_ view: BowlView, event: NSEvent) {
        let menu = NSMenu()
        let header = NSMenuItem(title: view.source.displayName, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let mine = tasks.filter { $0.source == view.source }
        if mine.isEmpty {
            let empty = NSMenuItem(title: "Empty bowl", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        for task in mine.sorted(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }) {
            let due = task.dueDate.map { " (\(formatter.string(from: $0)))" } ?? ""
            let item = actionItem(task.title + due) { $0.pin(task) }
            item.state = task.id == current?.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenu()
        statusMenu.addSettings(to: settings)
        menu.addItem(statusMenu.submenu("Settings", settings))
        menu.addItem(StatusMenu.quitItem())
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
