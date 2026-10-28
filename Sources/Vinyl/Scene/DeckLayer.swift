import AppKit
import QuartzCore

/// Converts a y-down design point into y-up layer coordinates.
@inline(__always) func up(_ p: CGPoint, in height: CGFloat) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }

/// The turntable's top plate with a spinning record, a fixed light sheen and
/// a tonearm. Built flat in deck-local space; scenes place or tilt `plane`.
final class DeckLayer {
    let plane = CALayer()
    let disc = CALayer()
    let label = CALayer()
    let sheen = CAGradientLayer()
    let spindle = CALayer()
    let armShadow = CALayer()
    /// Holds the tonearm. Scenes add it to `plane` (top-down) or lift it into
    /// its own plane above the deck (front views).
    let armHost = CALayer()
    let arm = CALayer()

    private(set) var armAngle: CGFloat = DeckGeometry.restAngle
    private let scale: CGFloat

    init(style: DeckStyle, scale: CGFloat, armShadowOffset: CGSize) {
        self.scale = scale
        let size = DeckGeometry.size
        let h = size.height
        let R = DeckGeometry.recordRadius
        let L = DeckGeometry.labelRadius
        let center = up(DeckGeometry.center, in: h)

        plane.bounds = CGRect(origin: .zero, size: size)
        plane.contents = Textures.plinth(style: style, scale: scale)

        disc.bounds = CGRect(x: 0, y: 0, width: R * 2, height: R * 2)
        disc.position = center
        disc.contents = Textures.record(scale: scale)

        label.bounds = CGRect(x: 0, y: 0, width: L * 2, height: L * 2)
        label.position = CGPoint(x: R, y: R)
        label.contents = Textures.label(art: nil, scale: scale)
        disc.addSublayer(label)

        // Reflections stay put while the record turns underneath them.
        sheen.type = .conic
        sheen.bounds = disc.bounds
        sheen.position = center
        sheen.startPoint = CGPoint(x: 0.5, y: 0.5)
        sheen.endPoint = CGPoint(x: 0.15, y: 0.85)
        let clear = Draw.white(0), hi = Draw.white(0.16), mid = Draw.white(0.05)
        sheen.colors = [clear, mid, hi, mid, clear, clear, mid, hi, mid, clear, clear]
        sheen.locations = [0, 0.03, 0.07, 0.11, 0.16, 0.5, 0.53, 0.57, 0.61, 0.66, 1]
        let ring = CAShapeLayer()
        let ringPath = CGMutablePath()
        ringPath.addEllipse(in: disc.bounds.insetBy(dx: 4, dy: 4))
        ringPath.addEllipse(in: disc.bounds.insetBy(dx: R - L - 12, dy: R - L - 12))
        ring.path = ringPath
        ring.fillRule = .evenOdd
        sheen.mask = ring

        spindle.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        spindle.position = center
        spindle.contents = Textures.spindle(scale: scale)

        let armImage = Textures.tonearm(scale: scale)
        let armSize = DeckGeometry.armSize
        let anchor = CGPoint(x: DeckGeometry.armOrigin.x / armSize.width, y: 1 - DeckGeometry.armOrigin.y / armSize.height)
        let pivot = up(DeckGeometry.pivot, in: h)

        arm.bounds = CGRect(origin: .zero, size: armSize)
        arm.anchorPoint = anchor
        arm.position = pivot
        arm.contents = armImage

        armShadow.bounds = arm.bounds
        armShadow.anchorPoint = anchor
        armShadow.position = CGPoint(x: pivot.x + armShadowOffset.width, y: pivot.y - armShadowOffset.height)
        armShadow.contents = Draw.silhouette(armImage, alpha: 0.6, blur: 7 * scale)

        armHost.bounds = plane.bounds
        armHost.addSublayer(arm)

        for layer in [disc, sheen, spindle, armShadow] { plane.addSublayer(layer) }
        setArmAngle(DeckGeometry.restAngle, duration: 0)
    }

    func setArmAngle(_ degrees: CGFloat, duration: CFTimeInterval, timing: CAMediaTimingFunctionName = .easeInEaseOut) {
        armAngle = degrees
        let t = CATransform3DMakeRotation(-degrees * .pi / 180, 0, 0, 1)
        CATransaction.begin()
        if duration <= 0 {
            CATransaction.setDisableActions(true)
        } else {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: timing))
        }
        arm.transform = t
        armShadow.transform = t
        CATransaction.commit()
    }

    /// Clockwise rotation of the record, in radians.
    func setDiscRotation(_ radians: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.transform = CATransform3DMakeRotation(-radians, 0, 0, 1)
        CATransaction.commit()
    }

    func setLabel(_ art: CGImage?, animated: Bool) {
        let image = Textures.label(art: art, scale: scale)
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
}
