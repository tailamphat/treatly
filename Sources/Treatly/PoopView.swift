import AppKit

/// A poop left behind after the pet eats a treat. It ignores the mouse and
/// fades out at the end of its life.
final class PoopView: NSView {
    static let art: SpriteImage? = Bundle.main.resourceURL.flatMap {
        SpriteImage(contentsOf: $0.appendingPathComponent("Art/poop.png"))
    }
    static let scale: CGFloat = 2
    static var size: NSSize {
        guard let art else { return NSSize(width: 32, height: 26) }
        return NSSize(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale + 2)
    }

    var opacity: CGFloat = 1 { didSet { if opacity != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        guard let art = Self.art else { return }
        let rect = NSRect(x: 0, y: 2, width: CGFloat(art.width) * Self.scale, height: CGFloat(art.height) * Self.scale)
        NSColor(white: 0, alpha: 0.15 * opacity).setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 0, width: rect.width - 6, height: 5)).fill()
        art.draw(in: rect, alpha: opacity)
    }
}
