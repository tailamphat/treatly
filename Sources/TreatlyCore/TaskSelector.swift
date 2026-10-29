import Foundation

/// Picks the one task the pet goes after.
public enum TaskSelector {
    /// Order: overdue first (most overdue first), then higher priority, then
    /// earliest due date (undated last), then title. Tasks hidden until a
    /// time in the future (snoozed or skipped) are left out.
    public static func current(from tasks: [TaskItem], now: Date, hiddenUntil: [String: Date] = [:]) -> TaskItem? {
        tasks
            .filter { task in (hiddenUntil[task.id].map { $0 <= now }) ?? true }
            .min { a, b in isBefore(a, b, now: now) }
    }

    static func isBefore(_ a: TaskItem, _ b: TaskItem, now: Date) -> Bool {
        let aOver = a.isOverdue(at: now), bOver = b.isOverdue(at: now)
        if aOver != bOver { return aOver }
        if aOver, let ad = a.dueDate, let bd = b.dueDate, ad != bd { return ad < bd }
        if a.priority != b.priority { return a.priority > b.priority }
        switch (a.dueDate, b.dueDate) {
        case let (ad?, bd?) where ad != bd: return ad < bd
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.title.localizedCompare(b.title) == .orderedAscending
        }
    }
}
