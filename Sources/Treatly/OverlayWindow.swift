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

/// The area the pet and bowls live in: the visible frame (above the Dock,
/// below the menu bar) of the menu bar display. `y` is the bottom edge, where
/// things start out. (`NSScreen.main` follows keyboard focus, which would make
/// the pet jump between displays.)
struct Ground {
    var minX: Double
    var maxX: Double
    var y: Double
    var maxY: Double

    static func current() -> Ground {
        let frame = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        return Ground(minX: frame.minX, maxX: frame.maxX, y: frame.minY, maxY: frame.maxY)
    }

    var walkBounds: ClosedRange<Double> { (minX + 50)...(maxX - 50) }

    /// Keeps a window of `size` with its origin at `origin` on screen.
    func clamp(_ origin: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(x: min(max(origin.x, minX), maxX - size.width), y: min(max(origin.y, y), maxY - size.height))
    }
}
