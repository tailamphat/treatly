import Foundation

/// One bowl per connected task source, sitting on the ground. It holds that
/// source's treats; the pet fetches the current treat from its bowl.
public struct Bowl: Equatable, Sendable {
    public var source: TaskSourceKind
    public var x: Double
    public var treatCount: Int
}

public enum BowlLayout {
    /// Bowls sit near the left and right ends of the ground, in source order.
    /// One bowl goes on the left.
    public static func bowls(for sources: [TaskSourceKind], tasks: [TaskItem], bounds: ClosedRange<Double>, inset: Double = 60) -> [Bowl] {
        let left = bounds.lowerBound + inset, right = bounds.upperBound - inset
        let ordered = TaskSourceKind.allCases.filter(sources.contains)
        return ordered.enumerated().map { i, source in
            let x: Double
            if ordered.count == 1 {
                x = left
            } else {
                x = left + (right - left) * Double(i) / Double(ordered.count - 1)
            }
            return Bowl(source: source, x: x, treatCount: tasks.filter { $0.source == source }.count)
        }
    }
}
