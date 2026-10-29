import Foundation

/// How hard the pet is nagging about the current task.
public enum EscalationLevel: Int, Comparable, Sendable {
    /// No task: the pet just lives its life.
    case calm
    /// Trots around with the treat in its mouth.
    case carrying
    /// Drops the treat in front of you and stares.
    case dropping
    /// Yells the task title.
    case barking
    /// Lies down and whines.
    case whining

    public static func < (lhs: EscalationLevel, rhs: EscalationLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct EscalationPolicy: Sendable {
    /// Time spent at each level before moving up.
    public var step: TimeInterval

    public init(step: TimeInterval = 10 * 60) {
        self.step = step
    }

    /// The clock starts at the due date, or when the task became current if it
    /// has none. Before that the pet only carries the treat.
    public func level(for task: TaskItem?, becameCurrentAt: Date, now: Date) -> EscalationLevel {
        guard let task else { return .calm }
        let elapsed = now.timeIntervalSince(task.dueDate ?? becameCurrentAt)
        guard elapsed >= step else { return .carrying }
        switch Int(elapsed / step) {
        case 1: return .dropping
        case 2: return .barking
        default: return .whining
        }
    }
}
