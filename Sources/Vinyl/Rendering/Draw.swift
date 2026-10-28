import AppKit
import CoreImage

/// Deterministic RNG so procedural textures look identical on every launch.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func r(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range, using: &self) }
}

enum Draw {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Renders a bitmap using y-down "design" coordinates (origin top-left).
    static func image(_ size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / size.width, y: -CGFloat(h) / size.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func white(_ a: CGFloat) -> CGColor { CGColor(gray: 1, alpha: a) }
    static func black(_ a: CGFloat) -> CGColor { CGColor(gray: 0, alpha: a) }

    /// Draws an image upright inside a y-down context.
    static func upright(_ img: CGImage, in r: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    static func aspectFill(_ img: CGImage, in r: CGRect, _ ctx: CGContext) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let s = max(r.width / iw, r.height / ih)
        let size = CGSize(width: iw * s, height: ih * s)
        upright(img, in: CGRect(x: r.midX - size.width / 2, y: r.midY - size.height / 2, width: size.width, height: size.height), ctx)
    }

    static func linear(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint) {
        let g = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radial(_ ctx: CGContext, _ colors: [CGColor], _ locations: [CGFloat]? = nil, center: CGPoint, radius: CGFloat, extend: Bool = false) {
        let g = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                               options: extend ? [.drawsAfterEndLocation] : [])
    }

    static func blur(_ img: CGImage, radius: CGFloat) -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let ci = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: Double(radius)).cropped(to: extent)
        return ciContext.createCGImage(ci, from: extent) ?? img
    }

    /// A soft drop-shadow silhouette of `img`, same pixel size.
    static func silhouette(_ img: CGImage, alpha: CGFloat, blur radius: CGFloat) -> CGImage {
        let w = img.width, h = img.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: r, mask: img)
        ctx.setFillColor(black(alpha))
        ctx.fill(r)
        return blur(ctx.makeImage()!, radius: radius)
    }

    /// A wavy horizontal path, used for wood grain.
    static func wave(y: CGFloat, from x0: CGFloat, to x1: CGFloat, slope: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat, amp2: CGFloat = 0, freq2: CGFloat = 0) -> CGPath {
        let p = CGMutablePath()
        var x = x0
        p.move(to: CGPoint(x: x, y: y))
        while x <= x1 {
            x += 24
            let yy = y + (x - x0) * slope + amp * sin(x * freq + phase) + amp2 * sin(x * freq2 + phase * 1.7)
            p.addLine(to: CGPoint(x: x, y: yy))
        }
        return p
    }

    static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor, kern: CGFloat = 0, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: kern,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        var origin = p
        if centered {
            let b = str.size()
            origin = CGPoint(x: p.x - b.width / 2, y: p.y - b.height / 2)
        }
        str.draw(at: origin)
    }
}

extension NSImage {
    var cg: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
