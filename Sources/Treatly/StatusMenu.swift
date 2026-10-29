import AppKit
import TreatlyCore

/// The paw in the menu bar. The menu is rebuilt every time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init()
        app.statusButton = item.button
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Treatly")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = app.current.map { "\(app.petName) wants: \($0.title)" } ?? "\(app.petName) has no treats"
        menu.addItem(disabled(status))
        menu.addItem(.separator())
        menu.addItem(app.actionItem("Settings…") { app in
            let button = app.statusButtonFrame
            app.openSettings(near: NSPoint(x: button.midX, y: button.minY - 660))
        })
        menu.addItem(.separator())
        addSettings(to: menu)
        menu.addItem(.separator())
        menu.addItem(Self.quitItem())
    }

    static func quitItem() -> NSMenuItem {
        NSMenuItem(title: "Quit Treatly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// The settings items, shared by the menu bar and the bowls.
    func addSettings(to menu: NSMenu) {
        let settings = app.settings
        let pets = NSMenu()
        for pack in app.packs {
            let item = app.actionItem("\(pack.name) (\(pack.treat.name))") { $0.selectPack(pack) }
            item.state = pack.id == app.pack.id ? .on : .off
            pets.addItem(item)
        }
        menu.addItem(submenu("Pet", pets))
        if !app.wardrobe.isEmpty {
            let wardrobe = NSMenu()
            let none = app.actionItem("Nothing") { $0.setWearing(nil) }
            none.state = app.wearing == nil ? .on : .off
            wardrobe.addItem(none)
            for id in app.wardrobe {
                let item = app.actionItem(Wardrobe.name(for: id)) { $0.setWearing(id) }
                item.state = app.wearing == id ? .on : .off
                wardrobe.addItem(item)
            }
            menu.addItem(submenu("Wardrobe", wardrobe))
        }
        let bowls = NSMenu()
        for style in BowlStyle.allCases {
            let item = app.actionItem(style.name) { $0.setBowlStyle(style) }
            item.state = settings.bowlStyle == style ? .on : .off
            bowls.addItem(item)
        }
        menu.addItem(submenu("Bowl", bowls))
        menu.addItem(app.actionItem("Rename \(app.petName)…") { $0.renamePet() })
        menu.addItem(.separator())

        menu.addItem(submenu(TaskSourceKind.appleReminders.displayName, remindersMenu()))

        let nag = NSMenu()
        for minutes in [5, 10, 20, 30] {
            let item = app.actionItem("Every \(minutes) min") { $0.settings.nagStepMinutes = minutes }
            item.state = settings.nagStepMinutes == minutes ? .on : .off
            nag.addItem(item)
        }
        menu.addItem(submenu("Nag Level-Up", nag))

        let sound = app.actionItem("Sound When Yelling") { $0.settings.soundOn.toggle() }
        sound.state = settings.soundOn ? .on : .off
        menu.addItem(sound)
        menu.addItem(.separator())

        menu.addItem(app.actionItem("Refresh Treats") { $0.refresh() })
        menu.addItem(app.actionItem("Open Pets Folder") { $0.openPetsFolder() })
    }

    func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func remindersMenu() -> NSMenu {
        let menu = NSMenu()
        let source = app.reminders!
        if !source.hasAccess {
            menu.addItem(app.actionItem("Grant Reminders Access…") { app in
                Task {
                    if await app.reminders.requestAccess() {
                        app.refresh()
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            })
            return menu
        }
        let enabled = app.actionItem("Use Apple Reminders") { app in
            app.settings.remindersEnabled.toggle()
            app.refresh()
        }
        enabled.state = app.settings.remindersEnabled ? .on : .off
        menu.addItem(enabled)
        addLists(of: source, to: menu)
        return menu
    }

    /// Checkable lists. Nothing selected means every list.
    private func addLists(of source: TaskSource, to menu: NSMenu) {
        let lists = source.availableLists
        guard !lists.isEmpty else { return }
        menu.addItem(.separator())
        menu.addItem(disabled("Lists"))
        let kind = source.kind
        let selected = app.settings.selectedLists(for: kind)
        let all = app.actionItem("All Lists") { $0.selectAllLists(for: kind) }
        all.state = selected.isEmpty ? .on : .off
        menu.addItem(all)
        for list in lists {
            let item = app.actionItem(list.title) { $0.toggleList(list.id, for: kind) }
            item.state = selected.contains(list.id) ? .on : .off
            menu.addItem(item)
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
