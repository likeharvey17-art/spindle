import AppKit
import CoreImage
import QuartzCore

/// The Mono widget: a flat, black-and-white turntable drawn from shapes, on a
/// square card with macOS widget corners. White with a black record in Light
/// mode, inverted in Dark mode, so it sits quietly on any wallpaper.
final class MonoScene: VinylScene {
    let root = CALayer()
    let size = CGSize(width: 1000, height: 1000)
    let focus = CGPoint(x: 500, y: 500)
    var deck: DeckLayer? { nil }
    private(set) var outline: CGPath?

    private let disc = CALayer()
    private let label = CALayer()
    private let ink: CGColor
    private let paper: CGColor

    /// Follows the Mac's appearance; `SPINDLE_APPEARANCE=dark|light` overrides it (snapshots).
    static var prefersDark: Bool {
        switch ProcessInfo.processInfo.environment["SPINDLE_APPEARANCE"] {
        case "dark": return true
        case "light": return false
        default: return NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    init(dark: Bool) {
        ink = dark ? Draw.color(0xF2F2F2) : Draw.color(0x111111)
        paper = dark ? Draw.color(0x161616) : Draw.color(0xFFFFFF)
        let soft = dark ? Draw.white(0.10) : Draw.black(0.08)
        root.frame = CGRect(origin: .zero, size: size)

        // Card: macOS widget corners (22 pt on a 170 pt widget).
        let radius = size.width * 22 / 170
        let path = CGPath(roundedRect: root.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        outline = path
        let card = CAShapeLayer()
        card.path = path
        card.fillColor = paper
        card.strokeColor = soft
        card.lineWidth = 3
        root.addSublayer(card)

        // Record: solid disc, a few fine rings, and one faint arc so the turning reads.
        let R: CGFloat = 335
        let center = CGPoint(x: 500, y: 500)
        disc.bounds = CGRect(x: 0, y: 0, width: R * 2, height: R * 2)
        disc.position = center
        let c = CGPoint(x: R, y: R)
        let vinyl = CAShapeLayer()
        vinyl.path = CGPath(ellipseIn: disc.bounds, transform: nil)
        vinyl.fillColor = ink
        disc.addSublayer(vinyl)
        let rings = CAShapeLayer()
        let ringPath = CGMutablePath()
        for r in [R * 0.88, R * 0.74, R * 0.6] { ringPath.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        rings.path = ringPath
        rings.fillColor = nil
        rings.strokeColor = dark ? Draw.black(0.14) : Draw.white(0.12)
        rings.lineWidth = 2.5
        disc.addSublayer(rings)
        let glint = CAShapeLayer()
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: R * 0.81, startAngle: 0.35, endAngle: 1.05, clockwise: false)
        glint.path = arc
        glint.fillColor = nil
        glint.strokeColor = dark ? Draw.black(0.18) : Draw.white(0.2)
        glint.lineWidth = 10
        glint.lineCap = .round
        disc.addSublayer(glint)

        let L: CGFloat = 118
        label.bounds = CGRect(x: 0, y: 0, width: L * 2, height: L * 2)
        label.position = c
        label.cornerRadius = L
        label.masksToBounds = true
        label.backgroundColor = paper
        label.contentsGravity = .resizeAspectFill
        disc.addSublayer(label)
        let hole = CAShapeLayer()
        hole.path = CGPath(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18), transform: nil)
        hole.fillColor = ink
        disc.addSublayer(hole)
        root.addSublayer(disc)

        // Tonearm: pivot, a straight arm and a small headshell on the outer grooves.
        // The pivot sits in the top-right corner, clear of the centred record.
        let pivot = CGPoint(x: 852, y: 846)
        let tip = CGPoint(x: center.x + R * 0.8 * cos(-0.36), y: center.y + R * 0.8 * sin(-0.36))
        let arm = CAShapeLayer()
        let armPath = CGMutablePath()
        let back = CGPoint(x: pivot.x + (pivot.x - tip.x) * 0.1, y: pivot.y + (pivot.y - tip.y) * 0.1)
        armPath.move(to: back)
        armPath.addLine(to: tip)
        let angle = atan2(tip.y - pivot.y, tip.x - pivot.x)
        var t = CGAffineTransform(translationX: tip.x, y: tip.y).rotated(by: angle)
        let headPath = CGPath(roundedRect: CGRect(x: -18, y: -20, width: 64, height: 40), cornerWidth: 8, cornerHeight: 8, transform: &t)
        // A cut line in the card's colour keeps the arm readable over the record.
        let gap = CAShapeLayer()
        let gapPath = CGMutablePath()
        gapPath.addPath(armPath)
        gapPath.addPath(headPath)
        gap.path = gapPath
        gap.fillColor = paper
        gap.strokeColor = paper
        gap.lineWidth = 30
        gap.lineCap = .round
        gap.lineJoin = .round
        root.addSublayer(gap)
        arm.path = armPath
        arm.strokeColor = ink
        arm.lineWidth = 14
        arm.lineCap = .round
        root.addSublayer(arm)
        let head = CAShapeLayer()
        head.path = headPath
        head.fillColor = ink
        root.addSublayer(head)
        let hub = CAShapeLayer()
        hub.path = CGPath(ellipseIn: CGRect(x: pivot.x - 46, y: pivot.y - 46, width: 92, height: 92), transform: nil)
        hub.fillColor = paper
        hub.strokeColor = ink
        hub.lineWidth = 12
        root.addSublayer(hub)
    }

    /// The label shows the album art in black and white.
    func setArtwork(_ art: CGImage?, animated: Bool) {
        let image = art.flatMap(MonoScene.mono)
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.45
            label.add(fade, forKey: "contents")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.contents = image
        CATransaction.commit()
    }

    func setDiscRotation(_ radians: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.transform = CATransform3DMakeRotation(-radians, 0, 0, 1)
        CATransaction.commit()
    }

    var spinningLayers: [CALayer] { [disc] }

    private static func mono(_ art: CGImage) -> CGImage? {
        let image = CIImage(cgImage: art)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.08])
        return Draw.ciContext.createCGImage(image, from: image.extent)
    }
}
