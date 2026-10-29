import AppKit
import SwiftUI
import TreatlyCore

/// Bridges the app to SwiftUI. The app pokes it about once a second while the
/// page is open, and after anything the page changes.
@MainActor
final class SettingsModel: ObservableObject {
    unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
    }

    func poke() { objectWillChange.send() }

    /// Runs an app action, then refreshes the page.
    func run(_ action: (AppDelegate) -> Void) {
        action(app)
        poke()
    }
}

/// A floating panel that can take keyboard focus (for renaming the pet).
final class SettingsPanel: NSPanel {
    let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: SettingsView(model: model))
    }

    override var canBecomeKey: Bool { true }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    private var app: AppDelegate { model.app }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                currentTreat
                section("Bowls") { bowls }
                section("Behaviour") { behaviour }
                section("Pets") { petGrid }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 20)
        }
        .frame(width: 360, height: 620)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            PetPreview(pack: app.pack)
                .frame(width: 64, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: Binding(get: { app.petName }, set: { name in model.run { $0.setPetName(name) } }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                Text("\(app.pack.name) · loves \(Self.plural(app.pack.treat.name))")
                    .foregroundStyle(.secondary)
                Text(mood)
                    .font(.callout)
                    .foregroundStyle(moodColor)
            }
            Spacer(minLength: 0)
        }
    }

    /// "bone" -> "bones", "banana" -> "bananas", but "fish" stays "fish".
    static func plural(_ word: String) -> String {
        ["fish", "sheep", "deer"].contains(word.lowercased()) ? word : word + "s"
    }

    private var mood: String {
        switch app.level {
        case .calm: return "Relaxed, no treats waiting"
        case .carrying: return "Carrying a \(app.pack.treat.name)"
        case .dropping: return "Waiting for you"
        case .barking: return "Getting loud"
        case .whining: return "Sad, ignored for a while"
        }
    }

    private var moodColor: Color {
        switch app.level {
        case .calm, .carrying: return .green
        case .dropping: return .orange
        case .barking, .whining: return .red
        }
    }

    // MARK: Current treat

    @ViewBuilder
    private var currentTreat: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = app.current {
                Text("\(app.petName) wants")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(task.source.displayName)
                    if let due = task.dueDate {
                        Text("·")
                        Text(task.isOverdue(at: Date()) ? "overdue since" : "due")
                        Text(due, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(task.isOverdue(at: Date()) ? .red : .secondary)
                HStack {
                    Button("Done") { model.run { $0.completeCurrent() } }
                        .keyboardShortcut(.defaultAction)
                    Button("Snooze 10m") { model.run { $0.snoozeCurrent(for: 10 * 60) } }
                    Button("1h") { model.run { $0.snoozeCurrent(for: 60 * 60) } }
                    Button("Next") { model.run { $0.skipCurrent() } }
                }
                .controlSize(.small)
            } else {
                Text("No treats right now. Enjoy the quiet.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
    }

    // MARK: Bowls

    private var bowls: some View {
        VStack(spacing: 12) {
            bowlRow(app.reminders, color: .orange) {
                if !app.reminders.hasAccess {
                    Button("Grant Access") {
                        Task { @MainActor in
                            if await app.reminders.requestAccess() {
                                app.refresh()
                            } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                                NSWorkspace.shared.open(url)
                            }
                            model.poke()
                        }
                    }
                } else {
                    Toggle("On", isOn: Binding(get: { app.settings.remindersEnabled }, set: { on in
                        model.run { $0.settings.remindersEnabled = on; $0.refresh() }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }
            bowlRow(app.google, color: .blue) {
                if app.google.isConnected {
                    Button("Disconnect") { model.run { $0.disconnectGoogle() } }
                } else {
                    Button("Connect") { model.run { $0.connectGoogle() } }
                }
            }
        }
    }

    private func bowlRow<Trailing: View>(_ source: TaskSource, color: Color, @ViewBuilder trailing: () -> Trailing) -> some View {
        let count = app.tasks.filter { $0.source == source.kind }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(source.kind.displayName).fontWeight(.medium)
                Spacer()
                Text("\(count) \(count == 1 ? "treat" : "treats")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                trailing()
                    .controlSize(.small)
            }
            if source.isConnected, !source.availableLists.isEmpty {
                listMenu(for: source)
                    .padding(.leading, 18)
            }
        }
    }

    private func listMenu(for source: TaskSource) -> some View {
        let kind = source.kind
        let selected = app.settings.selectedLists(for: kind)
        let label = selected.isEmpty ? "All lists" : source.availableLists.filter { selected.contains($0.id) }.map(\.title).joined(separator: ", ")
        return Menu {
            Button {
                model.run { $0.selectAllLists(for: kind) }
            } label: {
                if selected.isEmpty { Label("All Lists", systemImage: "checkmark") } else { Text("All Lists") }
            }
            Divider()
            ForEach(source.availableLists, id: \.id) { list in
                Button {
                    model.run { $0.toggleList(list.id, for: kind) }
                } label: {
                    if selected.contains(list.id) { Label(list.title, systemImage: "checkmark") } else { Text(list.title) }
                }
            }
        } label: {
            Text("Lists: \(label)").lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
    }

    // MARK: Behaviour

    private var behaviour: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nag a bit louder every")
                    .font(.callout)
                Picker("Nag level-up", selection: Binding(get: { app.settings.nagStepMinutes }, set: { minutes in
                    model.run { $0.settings.nagStepMinutes = minutes }
                })) {
                    ForEach([5, 10, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Toggle("Sound when yelling", isOn: Binding(get: { app.settings.soundOn }, set: { on in
                model.run { $0.settings.soundOn = on }
            }))
            .toggleStyle(.switch)
        }
    }

    // MARK: Pets

    private var petGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(app.packs) { pack in
                let selected = pack.id == app.pack.id
                Button {
                    model.run { $0.selectPack(pack) }
                } label: {
                    VStack(spacing: 4) {
                        PetPreview(pack: pack)
                            .frame(height: 44)
                        Text(app.settings.petName(for: pack))
                            .font(.caption.weight(selected ? .bold : .regular))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(selected ? 0.12 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pack.name)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Refresh") { model.run { $0.refresh() } }
            Button("Pets Folder") { model.run { $0.openPetsFolder() } }
            Spacer()
            Button("Quit Treatly") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// The pet's first idle frame, crisp and scaled to fit.
struct PetPreview: View {
    let pack: PetPack

    var body: some View {
        if let image = PetArt(pack: pack)?.image(for: .idle, elapsed: 0)?.image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(.secondary)
        }
    }
}
