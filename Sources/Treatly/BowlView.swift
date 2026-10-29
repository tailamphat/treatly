import AppKit
import TreatlyCore

@MainActor
protocol BowlViewDelegate: AnyObject {
    func bowlClicked(_ view: BowlView, event: NSEvent)
    func bowlRightClicked(_ view: BowlView)
    func bowlDragged(_ view: BowlView, to origin: NSPoint)
    func bowlDropped(_ view: BowlView)
}

/// What a pet keeps its treats in. Chosen by the pet pack.
enum ContainerStyle: String {
    /// A ceramic bowl; treats pile up inside.
    case bowl
    /// A banana tree; treats hang under the crown.
    case tree

    init(pack: PetPack) {
        self = ContainerStyle(rawValue: pack.container ?? "") ?? .bowl
    }

    var viewSize: NSSize {
        switch self {
        case .bowl: return NSSize(width: 74, height: 50)
        case .tree: return NSSize(width: 104, height: 136)
        }
    }
}

/// One source's treats sitting on the ground, with a count badge.
final class BowlView: NSView {
    weak var delegate: BowlViewDelegate?
    let source: TaskSourceKind
    let style: ContainerStyle
    var treat: SpriteImage? { didSet { needsDisplay = true } }
    var treatCount = 0 {
        didSet {
            guard treatCount != oldValue else { return }
            toolTip = "\(source.displayName): \(treatCount) treats"
            needsDisplay = true
        }
    }

    /// Bowls are drawn at the pets' scale.
    private var scale: CGFloat { style == .bowl ? 2.5 : 2 }
    private let back: SpriteImage?
    private let front: SpriteImage?

    init(source: TaskSourceKind, style: ContainerStyle) {
        self.source = source
        self.style = style
        switch style {
        case .bowl:
            back = Self.art("bowl-\(source.rawValue)-back")
            front = Self.art("bowl-\(source.rawValue)")
        case .tree:
            back = Self.art("tree-\(source.rawValue)")
            front = nil
        }
        super.init(frame: NSRect(origin: .zero, size: style.viewSize))
        toolTip = source.displayName
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Container art lives in the app bundle's Resources/Art.
    private static func art(_ name: String) -> SpriteImage? {
        Bundle.main.resourceURL.flatMap { SpriteImage(contentsOf: $0.appendingPathComponent("Art/\(name).png")) }
    }

    private var badgeColor: NSColor {
        switch source {
        case .appleReminders: return NSColor(calibratedRed: 0.93, green: 0.48, blue: 0.13, alpha: 1)
        case .googleTasks: return NSColor(calibratedRed: 0.17, green: 0.4, blue: 0.8, alpha: 1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let back else { return }
        let s = scale
        let size = NSSize(width: CGFloat(back.width) * s, height: CGFloat(back.height) * s)
        let art = NSRect(x: (bounds.width - size.width) / 2, y: 3, width: size.width, height: size.height)
        /// Converts art pixels (top-left origin) to view points.
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: art.minX + x * s, y: art.maxY - y * s) }

        let shadowWidth = style == .bowl ? art.width - 8 : art.width * 0.45
        NSColor(white: 0, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: art.midX - shadowWidth / 2 - (style == .tree ? 8 : 0), y: 0, width: shadowWidth, height: 6)).fill()
        back.draw(in: art)

        if let treat {
            switch style {
            case .bowl:
                // Treats pile up inside; the front rim covers their bottoms.
                let pile: [(CGFloat, CGFloat, Bool)] = [(10, 4.5, false), (18, 4.5, true), (14, 3.5, false), (7, 3.5, true), (21, 3.5, false)]
                let t = NSSize(width: CGFloat(treat.width) * 1.2, height: CGFloat(treat.height) * 1.2)
                for (x, y, flip) in pile.prefix(min(treatCount, pile.count)) {
                    let c = point(x, y)
                    treat.draw(in: NSRect(x: c.x - t.width / 2, y: c.y - t.height / 2, width: t.width, height: t.height), flipped: flip)
                }
            case .tree:
                // Hanging bunch under the crown.
                let hangs: [(CGFloat, CGFloat)] = [(21, 21), (28, 21), (24, 24), (18, 25), (31, 25), (25, 28)]
                let t = NSSize(width: CGFloat(treat.width), height: CGFloat(treat.height))
                for (i, (x, y)) in hangs.prefix(min(treatCount, hangs.count)).enumerated() {
                    let c = point(x, y)
                    treat.draw(in: NSRect(x: c.x - t.width / 2, y: c.y - t.height / 2, width: t.width, height: t.height), flipped: i % 2 == 1)
                }
            }
        }
        front?.draw(in: art)
        drawBadge(at: NSPoint(x: art.maxX - 6, y: style == .bowl ? art.maxY - 2 : point(0, 46).y))
    }

    private func drawBadge(at center: NSPoint) {
        let label = "\(treatCount)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let text = label.size(withAttributes: attributes)
        let width = max(18, text.width + 10)
        let rect = NSRect(x: min(center.x - width / 2, bounds.width - width - 1), y: center.y - 8, width: width, height: 16)
        let pill = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        badgeColor.setFill()
        pill.fill()
        NSColor.white.setStroke()
        pill.lineWidth = 1.5
        pill.stroke()
        label.draw(at: NSPoint(x: rect.midX - text.width / 2, y: rect.midY - text.height / 2), withAttributes: attributes)
    }

    // MARK: Mouse: click for the menu, drag to move it anywhere.

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var dragging = false

    override func rightMouseDown(with event: NSEvent) {
        delegate?.bowlRightClicked(self)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = (NSEvent.mouseLocation, window?.frame.origin ?? .zero)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - start.mouse.x, dy = mouse.y - start.mouse.y
        if !dragging && hypot(dx, dy) > 4 { dragging = true }
        if dragging { delegate?.bowlDragged(self, to: NSPoint(x: start.origin.x + dx, y: start.origin.y + dy)) }
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            delegate?.bowlDropped(self)
        } else {
            delegate?.bowlClicked(self, event: event)
        }
        dragStart = nil
        dragging = false
    }
}
