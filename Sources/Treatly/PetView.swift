import AppKit
import TreatlyCore

/// Everything the view needs to draw one frame.
struct PetFrame {
    var activity: Activity = .idle
    var facing: Facing = .right
    var carriesTreat = false
    var treatOnGround = false
    var reactionProgress = 0.0
    var bubble: String?
    var treatScale = 1.0
    var stinky = false
    var time: TimeInterval = 0
    /// Seconds since the current activity started, for animation frames.
    var activityElapsed: TimeInterval = 0
}

@MainActor
protocol PetViewDelegate: AnyObject {
    func petClicked(_ view: PetView, event: NSEvent)
    func petRightClicked(_ view: PetView)
    func petDragBegan()
    func petDragged(to screenPoint: NSPoint)
    func petDragEnded()
}

/// Draws the pet, its shadow, its treat and its speech bubble, bottom-centered.
final class PetView: NSView {
    static let size = NSSize(width: 320, height: 200)
    static let treatScale: CGFloat = 2
    static let groundPad: CGFloat = 4

    weak var delegate: PetViewDelegate?
    var art: PetArt? { didSet { needsDisplay = true } }
    var frameState = PetFrame() { didSet { needsDisplay = true } }

    /// The part of the view that should take mouse clicks, in view coordinates.
    private(set) var interactiveRect: NSRect = .zero

    private var mouseDownPoint: NSPoint?
    private var dragging = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let art, let pet = art.image(for: frameState.activity, elapsed: frameState.activityElapsed) else { return }
        let s = frameState
        let petSize = NSSize(width: CGFloat(pet.width) * art.scale, height: CGFloat(pet.height) * art.scale)
        let ground = Self.groundPad
        var petRect = NSRect(x: (bounds.width - petSize.width) / 2, y: ground - art.footPadding, width: petSize.width, height: petSize.height)

        // Sheets animate themselves; a single still frame gets faked motion.
        switch s.activity {
        case .walking where !art.isAnimated, .running where !art.isAnimated:
            petRect.origin.y += Int(s.time * 8) % 2 == 0 ? 0 : 2
        case .sleeping where !art.isAnimated:
            petRect.size.height *= 0.85
        case .held:
            petRect.origin.y += 6
        default:
            break
        }

        if s.activity != .held { drawShadow(under: petRect, art: art) }

        // Flip when the art faces the other way from where the pet is going.
        let flipped = (s.facing == .left) != art.facesLeft
        let alpha: CGFloat = s.activity == .whining && !art.isAnimated ? 0.85 : 1
        pet.draw(in: petRect, flipped: flipped, alpha: alpha)
        var hit = petRect

        if let treat = art.treat {
            let scale = Self.treatScale * CGFloat(s.treatScale)
            let size = NSSize(width: CGFloat(treat.width) * scale, height: CGFloat(treat.height) * scale)
            let facingLeft = s.facing == .left
            var treatRect: NSRect?
            if s.carriesTreat || s.activity == .eating {
                // Mouth position is in frame pixels from the top-left of a right-facing frame.
                let mouthFromLeft = art.mouth.x * art.scale
                let mouthX = facingLeft ? petRect.maxX - mouthFromLeft : petRect.minX + mouthFromLeft
                let mouthY = petRect.maxY - art.mouth.y * art.scale
                var rect = NSRect(x: mouthX - size.width / 2, y: mouthY - size.height / 2, width: size.width, height: size.height)
                if s.activity == .eating {
                    // Shrinks as it gets chewed.
                    let left = 1 - s.reactionProgress
                    rect = rect.insetBy(dx: rect.width * (1 - left) / 2, dy: rect.height * (1 - left) / 2)
                }
                treatRect = rect
            } else if s.treatOnGround || s.activity == .burying {
                let x = facingLeft ? petRect.minX - size.width + 6 : petRect.maxX - 6
                treatRect = NSRect(x: x, y: ground, width: size.width, height: size.height)
            }

            if let rect = treatRect, rect.width > 0.5 {
                if s.activity == .burying {
                    drawBurial(over: rect, progress: s.reactionProgress, treat: treat)
                } else {
                    treat.draw(in: rect, flipped: facingLeft)
                    if s.stinky { drawStink(above: rect, time: s.time) }
                }
                hit = hit.union(rect)
            }
        }

        if let text = s.bubble, !text.isEmpty {
            hit = hit.union(drawBubble(text, above: petRect))
        }
        interactiveRect = hit.insetBy(dx: -4, dy: -4)
    }

    private func drawShadow(under petRect: NSRect, art: PetArt) {
        let width = petRect.width * 0.7
        let shadow = NSRect(x: petRect.midX - width / 2, y: Self.groundPad - 3, width: width, height: 6)
        NSColor(white: 0, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: shadow).fill()
    }

    private func drawStink(above rect: NSRect, time: TimeInterval) {
        NSColor(calibratedRed: 0.45, green: 0.75, blue: 0.3, alpha: 0.85).setFill()
        for i in 0..<3 {
            let wobble = CGFloat(sin(time * 4 + Double(i) * 2)) * 3
            let x = rect.minX + rect.width * CGFloat(i + 1) / 4 + wobble
            let y = rect.maxY + 3 + CGFloat(i % 2) * 5
            NSBezierPath(rect: NSRect(x: x, y: y, width: 3, height: 3)).fill()
        }
    }

    private func drawBurial(over rect: NSRect, progress: Double, treat: SpriteImage) {
        // The treat sinks while a dirt mound grows over it.
        let sunk = rect.offsetBy(dx: 0, dy: -rect.height * CGFloat(progress))
        NSGraphicsContext.current?.cgContext.clip(to: NSRect(x: 0, y: Self.groundPad, width: bounds.width, height: bounds.height))
        treat.draw(in: sunk)
        NSGraphicsContext.current?.cgContext.resetClip()
        let moundHeight = 4 + 10 * CGFloat(progress)
        let mound = NSRect(x: rect.minX - 4, y: Self.groundPad - 2, width: rect.width + 8, height: moundHeight)
        NSColor(calibratedRed: 0.45, green: 0.3, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: mound).fill()
    }

    private func drawBubble(_ text: String, above petRect: NSRect) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let maxWidth = bounds.width - 24
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: 80), options: [.usesLineFragmentOrigin], attributes: attributes
        ).size
        let padding: CGFloat = 8
        let width = min(maxWidth, ceil(textSize.width)) + padding * 2
        let height = ceil(textSize.height) + padding * 2
        let x = min(max(4, petRect.midX - width / 2), bounds.width - width - 4)
        let bubble = NSRect(x: x, y: petRect.maxY + 10, width: width, height: height)

        let path = NSBezierPath(roundedRect: bubble, xRadius: 10, yRadius: 10)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: petRect.midX - 6, y: bubble.minY + 1))
        tail.line(to: NSPoint(x: petRect.midX, y: bubble.minY - 8))
        tail.line(to: NSPoint(x: petRect.midX + 6, y: bubble.minY + 1))
        NSColor.white.setFill()
        path.fill()
        tail.fill()
        NSColor(white: 0.15, alpha: 1).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        (text as NSString).draw(
            with: bubble.insetBy(dx: padding, dy: padding), options: [.usesLineFragmentOrigin], attributes: attributes
        )
        return bubble
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = NSEvent.mouseLocation
        if !dragging && hypot(point.x - start.x, point.y - start.y) > 4 {
            dragging = true
            delegate?.petDragBegan()
        }
        if dragging { delegate?.petDragged(to: point) }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.petRightClicked(self)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            delegate?.petDragEnded()
        } else {
            delegate?.petClicked(self, event: event)
        }
        mouseDownPoint = nil
        dragging = false
    }
}
