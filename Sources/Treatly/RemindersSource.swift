import EventKit
import Foundation
import TreatlyCore

@MainActor
final class RemindersSource: TaskSource {
    let kind = TaskSourceKind.appleReminders
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private let selectedListIDs: () -> Set<String>
    private let isEnabled: () -> Bool

    init(selectedListIDs: @escaping () -> Set<String>, isEnabled: @escaping () -> Bool) {
        self.selectedListIDs = selectedListIDs
        self.isEnabled = isEnabled
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    var accessStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    var hasAccess: Bool { accessStatus == .fullAccess }
    var isConnected: Bool { isEnabled() && hasAccess }

    /// Shows the macOS permission prompt the first time.
    func requestAccess() async -> Bool {
        guard accessStatus == .notDetermined else { return hasAccess }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    var availableLists: [(id: String, title: String)] {
        guard hasAccess else { return [] }
        return store.calendars(for: .reminder).map { ($0.calendarIdentifier, $0.title) }
    }

    func fetch() async throws -> [TaskItem] {
        guard isConnected else { return [] }
        let selected = selectedListIDs()
        let calendars = store.calendars(for: .reminder).filter { selected.isEmpty || selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder in
                    TaskItem(
                        source: .appleReminders,
                        sourceID: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        dueDate: DueDate.resolve(reminder.dueDateComponents),
                        priority: Priority(eventKitValue: reminder.priority)
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    func complete(_ task: TaskItem) async throws {
        guard let reminder = store.calendarItem(withIdentifier: task.sourceID) as? EKReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    /// Moves the due date so the snooze shows up on your other devices too.
    func snooze(_ task: TaskItem, until: Date) async throws {
        guard let reminder = store.calendarItem(withIdentifier: task.sourceID) as? EKReminder else { return }
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: until)
        try store.save(reminder, commit: true)
    }
}
