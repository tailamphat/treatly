import AppKit
import TreatlyCore

/// A poop left behind after the pet eats a treat. It ignores the mouse and
/// fades out at the end of its life.
final class PoopView: NSView {
    static let scale: CGFloat = 2
    private static var cache: [PoopStyle: SpriteImage] = [:]

    static func art(for style: PoopStyle) -> SpriteImage? {
        if let art = cache[style] { return art }
        guard let name = style.artName, let url = Bundle.main.resourceURL?.appendingPathComponent("Art/\(name).png"),
              let art = SpriteImage(contentsOf: url) else { return nil }
        cache[style] = art
        return art
    }

    static func size(for art: SpriteImage) -> NSSize {
        NSSize(width: CGFloat(art.width) * scale, height: CGFloat(art.height) * scale + 2)
    }

    let art: SpriteImage

    init(art: SpriteImage) {
        self.art = art
        super.init(frame: NSRect(origin: .zero, size: Self.size(for: art)))
    }

    required init?(coder: NSCoder) { nil }

    var opacity: CGFloat = 1 { didSet { if opacity != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: 2, width: CGFloat(art.width) * Self.scale, height: CGFloat(art.height) * Self.scale)
        NSColor(white: 0, alpha: 0.15 * opacity).setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: 0, width: rect.width - 6, height: 5)).fill()
        art.draw(in: rect, alpha: opacity)
    }
}
