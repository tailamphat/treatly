import Foundation

/// Where a task came from. Ids are only unique within one source.
public enum TaskSourceKind: String, Codable, Sendable, CaseIterable {
    case appleReminders
    case googleTasks
}

public enum Priority: Int, Comparable, Codable, Sendable {
    case none = 0, low, medium, high

    /// EventKit priority: 0 none, 1-4 high, 5 medium, 6-9 low.
    public init(eventKitValue value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A todo from any source. The pet sees it as a treat.
public struct TaskItem: Equatable, Hashable, Sendable {
    public var source: TaskSourceKind
    public var sourceID: String
    public var title: String
    public var dueDate: Date?
    public var priority: Priority

    public init(source: TaskSourceKind, sourceID: String, title: String, dueDate: Date? = nil, priority: Priority = .none) {
        self.source = source
        self.sourceID = sourceID
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
    }

    /// Unique across sources.
    public var id: String { "\(source.rawValue):\(sourceID)" }

    public func isOverdue(at now: Date) -> Bool {
        guard let dueDate else { return false }
        return dueDate < now
    }
}

public enum DueDate {
    /// Date-only due dates (no hour) mean "by the end of that day", so a task
    /// due today is not overdue at midnight.
    public static func resolve(_ components: DateComponents?, calendar: Calendar = .current) -> Date? {
        guard let components, let start = calendar.date(from: components) else { return nil }
        if components.hour == nil {
            let startOfDay = calendar.startOfDay(for: start)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)
        }
        return start
    }
}
