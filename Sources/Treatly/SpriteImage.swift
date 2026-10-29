import AppKit
import ImageIO
import TreatlyCore

/// A crisp bitmap drawn scaled up without smoothing.
struct SpriteImage {
    let image: CGImage
    var width: Int { image.width }
    var height: Int { image.height }

    init(_ image: CGImage) {
        self.image = image
    }

    /// Renders text pixel art into a bitmap.
    init?(_ sprite: PixelSprite) {
        let grid = sprite.grid()
        let width = sprite.width, height = sprite.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        for (y, row) in grid.enumerated() {
            for (x, pixel) in row.enumerated() {
                guard let pixel else { continue }
                context.setFillColor(CGColor(red: pixel.r, green: pixel.g, blue: pixel.b, alpha: pixel.a))
                // Bitmap origin is bottom-left; sprite rows start at the top.
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
            }
        }
        guard let image = context.makeImage() else { return nil }
        self.image = image
    }

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.image = image
    }

    /// The frame at column `col`, row `row` of a grid of `size` frames.
    func frame(col: Int, row: Int, size: (w: Int, h: Int)) -> SpriteImage? {
        image.cropping(to: CGRect(x: col * size.w, y: row * size.h, width: size.w, height: size.h)).map(SpriteImage.init)
    }

    func draw(in rect: CGRect, flipped: Bool = false, alpha: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.setAlpha(alpha)
        if flipped {
            context.translateBy(x: rect.maxX + rect.minX, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        context.draw(image, in: rect)
        context.restoreGState()
    }
}

/// A pack's look: animated sheet frames, or a single text sprite.
struct PetArt {
    /// Points per art pixel.
    let scale: CGFloat
    let frameSize: (w: Int, h: Int)
    let facesLeft: Bool
    /// Points of blank space under the feet, to sink the pet onto the ground.
    let footPadding: CGFloat
    /// Treat position in frame pixels, top-left origin, right-facing.
    let mouth: CGPoint
    /// True when there are real animations; otherwise the view fakes motion.
    let isAnimated: Bool
    let treat: SpriteImage?

    private let sheet: SpriteSheet?
    private let frames: [String: [SpriteImage]]
    private let still: SpriteImage?

    init?(pack: PetPack) {
        let folder = pack.folder
        if let treatImage = pack.treat.image, let folder {
            treat = SpriteImage(contentsOf: folder.appendingPathComponent(treatImage))
        } else {
            treat = pack.treat.sprite.flatMap(SpriteImage.init)
        }

        if let sheet = pack.sheet, let folder, let image = SpriteImage(contentsOf: folder.appendingPathComponent(sheet.image)) {
            let size = (sheet.frameWidth, sheet.frameHeight)
            var frames: [String: [SpriteImage]] = [:]
            for (name, animation) in sheet.animations {
                let start = animation.start ?? 0
                frames[name] = (start..<start + animation.count).compactMap { image.frame(col: $0, row: animation.row, size: size) }
            }
            self.sheet = sheet
            self.frames = frames
            still = nil
            scale = CGFloat(sheet.scale ?? 2)
            frameSize = size
            facesLeft = sheet.facesLeft
            footPadding = CGFloat(sheet.footPadding ?? 0) * scale
            let m = sheet.mouth ?? [Double(sheet.frameWidth) * 0.85, Double(sheet.frameHeight) * 0.4]
            mouth = CGPoint(x: m[0], y: m[1])
            isAnimated = true
        } else if let sprite = pack.sprite, let image = SpriteImage(sprite) {
            sheet = nil
            frames = [:]
            still = image
            scale = 4
            frameSize = (image.width, image.height)
            facesLeft = false
            footPadding = 0
            mouth = CGPoint(x: Double(image.width) * 0.9, y: Double(image.height) * 0.45)
            isAnimated = false
        } else {
            return nil
        }
    }

    var pointSize: NSSize { NSSize(width: CGFloat(frameSize.w) * scale, height: CGFloat(frameSize.h) * scale) }

    func image(for activity: Activity, elapsed: TimeInterval) -> SpriteImage? {
        if let still { return still }
        guard let sheet else { return nil }
        let (name, animation) = sheet.animation(for: activity)
        guard let list = frames[name], !list.isEmpty else { return nil }
        return list[min(animation.frame(at: elapsed), list.count - 1)]
    }
}
