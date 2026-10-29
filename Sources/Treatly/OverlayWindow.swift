import AppKit

/// A transparent, borderless window that floats above other apps on every Space.
final class OverlayWindow: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The area the pet and bowls live in on one display: its visible frame
/// (above the Dock, below the menu bar). `y` is the bottom edge, where things
/// start out. Things belong to whichever display they were put on.
struct Ground {
    var minX: Double
    var maxX: Double
    var y: Double
    var maxY: Double

    init(_ frame: NSRect) {
        minX = frame.minX
        maxX = frame.maxX
        y = frame.minY
        maxY = frame.maxY
    }

    /// The menu bar display, where things start out. (`NSScreen.main` follows
    /// keyboard focus, which would make the pet jump between displays.)
    static func current() -> Ground {
        Ground((NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero)
    }

    /// The display under `point`, or the nearest one if it is off every
    /// display (say, one was unplugged).
    static func containing(_ point: NSPoint) -> Ground {
        let screens = NSScreen.screens
        if let screen = screens.first(where: { $0.frame.contains(point) }) {
            return Ground(screen.visibleFrame)
        }
        func distance(_ frame: NSRect) -> Double {
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            return dx * dx + dy * dy
        }
        return screens.min { distance($0.frame) < distance($1.frame) }.map { Ground($0.visibleFrame) } ?? current()
    }

    /// True when `point` is anywhere on a display, menu bar and Dock included.
    static func isOnAnyDisplay(_ point: NSPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(point) }
    }

    var walkBounds: ClosedRange<Double> { (minX + 50)...(maxX - 50) }

    /// Keeps a window of `size` with its origin at `origin` on screen.
    func clamp(_ origin: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(x: min(max(origin.x, minX), maxX - size.width), y: min(max(origin.y, y), maxY - size.height))
    }
}
