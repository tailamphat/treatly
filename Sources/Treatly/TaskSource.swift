import Foundation
import TreatlyCore

/// A place todos come from. Each connected source gets its own bowl.
@MainActor
protocol TaskSource: AnyObject {
    var kind: TaskSourceKind { get }
    var isConnected: Bool { get }
    /// Called when the source knows its tasks changed.
    var onChange: (() -> Void)? { get set }
    /// The lists the user can choose from (id, title).
    var availableLists: [(id: String, title: String)] { get }

    func fetch() async throws -> [TaskItem]
    func complete(_ task: TaskItem) async throws
    /// Called after the pet buries the treat. The app also hides the task
    /// locally until `until`, so this only needs to sync it if the source can.
    func snooze(_ task: TaskItem, until: Date) async throws
}

extension TaskSourceKind {
    var displayName: String {
        switch self {
        case .appleReminders: return "Apple Reminders"
        case .googleTasks: return "Google Tasks"
        }
    }

    var shortName: String {
        switch self {
        case .appleReminders: return "Reminders"
        case .googleTasks: return "Google"
        }
    }
}
