import AppKit
import QuartzCore
import ImageIO

/// Every scene is laid out on a 2000×1300 design canvas that SceneView scales to fill the screen.
let worldSize = CGSize(width: 2000, height: 1300)

protocol VinylScene: AnyObject {
    var root: CALayer { get }
    /// The scene's canvas in design units; SceneView scales it to fill the screen.
    var size: CGSize { get }
    /// The drawn turntable, when the scene has one (photo scenes don't).
    var deck: DeckLayer? { get }
    /// Point (y-down design units) that framing zooms toward.
    var focus: CGPoint { get }
    func setArtwork(_ art: CGImage?, animated: Bool)
    /// Clockwise record rotation in radians.
    func setDiscRotation(_ radians: CGFloat)
    /// Layers that turn with the record, each with a plain z rotation.
    var spinningLayers: [CALayer] { get }
    /// Puts on the next record: the track-change animation.
    func changeRecord(to art: CGImage?)
    /// A widget's shape, in its own coordinates, for the shadow it casts.
    var outline: CGPath? { get }
}

extension VinylScene {
    func changeRecord(to art: CGImage?) { setArtwork(art, animated: true) }
    var outline: CGPath? { nil }
}

/// Optional photographic backdrops that replace the procedural ones:
/// ~/Library/Application Support/Spindle/Scenes/<name>.(png|jpg|jpeg|webp)
enum CustomBackdrop {
    static var folder: URL {
        if let dir = ProcessInfo.processInfo.environment["VINYL_SCENES_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spindle/Scenes", isDirectory: true)
    }

    /// The scenes shipped inside the app, used when the folder above has none.
    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("Scenes", isDirectory: true) }

    private static var folders: [URL] { [folder] + (bundled.map { [$0] } ?? []) }

    static func image(named name: String) -> CGImage? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for dir in folders {
            for ext in ["png", "jpg", "jpeg", "webp", "heic"] {
                let url = dir.appendingPathComponent("\(name).\(ext)")
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    return img
                }
            }
        }
        return nil
    }

    /// The calibration that goes with a scene photo, from the same place as the photo.
    static func calibration(named name: String) -> (data: Data, file: String)? {
        for dir in folders {
            let url = dir.appendingPathComponent("\(name).json")
            if let data = try? Data(contentsOf: url) { return (data, url.lastPathComponent) }
        }
        return nil
    }
}

private func noActions(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

private func crossfade(_ layer: CALayer, duration: CFTimeInterval = 0.45) {
    let fade = CATransition()
    fade.type = .fade
    fade.duration = duration
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(fade, forKey: "contents")
}

/// An album jacket: artwork, a faint printed-card sheen and a soft shadow.
final class SleeveLayer {
    let container = CALayer()
    private let art = CALayer()
    private let gloss = CAGradientLayer()
    private let placeholder: CGImage

    init(size: CGFloat, scale: CGFloat) {
        placeholder = Textures.placeholderArt(scale: scale)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        container.bounds = rect
        container.shadowPath = CGPath(rect: rect, transform: nil)
        container.shadowColor = .black
        art.frame = rect
        art.contentsGravity = .resizeAspectFill
        art.masksToBounds = true
        art.contents = placeholder
        art.borderColor = Draw.white(0.12)
        art.borderWidth = 1.2
        gloss.frame = rect
        gloss.colors = [Draw.white(0.10), Draw.white(0), Draw.white(0), Draw.black(0.10)]
        gloss.locations = [0, 0.35, 0.7, 1]
        gloss.startPoint = CGPoint(x: 0, y: 1)
        gloss.endPoint = CGPoint(x: 1, y: 0)
        container.addSublayer(art)
        container.addSublayer(gloss)
    }

    func setShadow(opacity: Float, radius: CGFloat, offset: CGSize) {
        container.shadowOpacity = opacity
        container.shadowRadius = radius
        container.shadowOffset = offset
    }

    func setArtwork(_ image: CGImage?, animated: Bool) {
        if animated { crossfade(art) }
        noActions { art.contents = image ?? placeholder }
    }
}

// MARK: - Turntable (top-down desk)

final class TopDownScene: VinylScene {
    let root = CALayer()
    let deckLayer: DeckLayer
    let focus = CGPoint(x: 1000, y: 690)

    private let background = CALayer()
    private let blinds = CALayer()
    private let sleeve: SleeveLayer

    init(scale: CGFloat, backgroundScale: CGFloat) {
        let H = worldSize.height
        root.frame = CGRect(origin: .zero, size: worldSize)

        background.frame = root.bounds
        background.contentsGravity = .resizeAspectFill
        background.contents = CustomBackdrop.image(named: "turntable") ?? Textures.topDownDesk(size: worldSize, scale: backgroundScale)

        sleeve = SleeveLayer(size: 690, scale: scale)
        sleeve.container.position = up(CGPoint(x: 505, y: 722), in: H)
        sleeve.container.transform = CATransform3DMakeRotation(3.2 * .pi / 180, 0, 0, 1)
        sleeve.setShadow(opacity: 0.55, radius: 22, offset: CGSize(width: 14, height: -20))

        deckLayer = DeckLayer(style: .birch, scale: scale, armShadowOffset: CGSize(width: 14, height: 20))
        deckLayer.plane.position = up(CGPoint(x: 1310, y: 670), in: H)
        deckLayer.plane.shadowPath = CGPath(roundedRect: deckLayer.plane.bounds, cornerWidth: 30, cornerHeight: 30, transform: nil)
        deckLayer.plane.shadowColor = .black
        deckLayer.plane.shadowOpacity = 0.55
        deckLayer.plane.shadowRadius = 26
        deckLayer.plane.shadowOffset = CGSize(width: 16, height: -24)
        deckLayer.armHost.position = CGPoint(x: deckLayer.plane.bounds.midX, y: deckLayer.plane.bounds.midY)
        deckLayer.plane.addSublayer(deckLayer.armHost)

        // Blind shadows lie over everything and drift as if the sun moves.
        blinds.frame = root.bounds.insetBy(dx: -80, dy: -80)
        blinds.contents = Textures.blindShadows(size: blinds.bounds.size, scale: backgroundScale * 0.5)
        let drift = CABasicAnimation(keyPath: "position.x")
        drift.byValue = 34
        drift.duration = 38
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        blinds.add(drift, forKey: "drift")

        for layer in [background, sleeve.container, deckLayer.plane, blinds] { root.addSublayer(layer) }
    }

    func setArtwork(_ art: CGImage?, animated: Bool) {
        sleeve.setArtwork(art, animated: animated)
        deckLayer.setLabel(art, animated: animated)
    }

    var size: CGSize { worldSize }
    var deck: DeckLayer? { deckLayer }
    func setDiscRotation(_ radians: CGFloat) { deckLayer.setDiscRotation(radians) }
    var spinningLayers: [CALayer] { [deckLayer.disc] }
}

// MARK: - Listening Room / After Hours (front view)

final class FrontScene: VinylScene {
    let root = CALayer()
    let deckLayer: DeckLayer
    let focus = CGPoint(x: 1000, y: 760)

    private let night: Bool
    private let background = CALayer()
    private let stage = CALayer()
    private let plinthFront = CALayer()
    private let pivotTower = CAGradientLayer()
    private let restTower = CAGradientLayer()
    private let sleeve: SleeveLayer
    private let stand = CALayer()
    private let glow = CAGradientLayer()
    /// Dims the props away from the lamp so they sit in a dark photo.
    private let shade = CAGradientLayer()

    private let perspective: CATransform3D = {
        var t = CATransform3DIdentity
        t.m34 = -1 / 2200
        return t
    }()

    init(night: Bool, scale: CGFloat, backgroundScale: CGFloat) {
        self.night = night
        let H = worldSize.height
        root.frame = CGRect(origin: .zero, size: worldSize)

        background.frame = root.bounds
        background.contentsGravity = .resizeAspectFill
        let photo = CustomBackdrop.image(named: night ? "after-hours" : "listening-room")
        background.contents = photo ?? Textures.room(night ? .night : .day, size: worldSize, scale: backgroundScale)
        // Photo backdrops put the desk's back edge lower (~74% down) than the
        // procedural room (54%), so the props move down to sit on it.
        let drop: CGFloat = photo == nil ? 0 : 175
        let lampBulb = photo == nil ? CGPoint(x: 1810, y: 470) : CGPoint(x: 1840, y: 790)

        // Props are laid out for the procedural room; for photos they shrink
        // around their base line to match the room's scale.
        stage.bounds = root.bounds
        let base = photo == nil ? CGPoint(x: 1000, y: 650) : CGPoint(x: 1000, y: 940)
        stage.anchorPoint = CGPoint(x: base.x / worldSize.width, y: 1 - base.y / H)
        stage.position = up(CGPoint(x: base.x, y: base.y + drop), in: H)
        let propScale: CGFloat = photo == nil ? 1 : 0.8
        stage.transform = CATransform3DMakeScale(propScale, propScale, 1)
        stage.sublayerTransform = perspective

        // Turntable: the top-down deck tipped back into perspective.
        deckLayer = DeckLayer(style: .cream, scale: scale, armShadowOffset: CGSize(width: 26, height: 34))
        sleeve = SleeveLayer(size: 470, scale: scale)
        let deckScale: CGFloat = 0.72
        let tilt: CGFloat = -70 * .pi / 180
        let lift: CGFloat = 60
        let deckTransform = CATransform3DConcat(CATransform3DMakeScale(deckScale, deckScale, 1), CATransform3DMakeRotation(tilt, 1, 0, 0))
        deckLayer.plane.position = up(CGPoint(x: 1015, y: 790), in: H)
        deckLayer.plane.transform = deckTransform
        deckLayer.armHost.position = deckLayer.plane.position
        deckLayer.armHost.transform = CATransform3DConcat(CATransform3DMakeTranslation(0, 0, lift), deckTransform)

        // Wooden base under the top plate.
        let nearLeft = project(CGPoint(x: 0, y: 0), z: 0, layer: deckLayer.plane)
        let nearRight = project(CGPoint(x: DeckGeometry.size.width, y: 0), z: 0, layer: deckLayer.plane)
        let baseHeight: CGFloat = 72
        let baseSize = CGSize(width: nearRight.x - nearLeft.x, height: baseHeight)
        plinthFront.frame = CGRect(x: nearLeft.x, y: nearLeft.y - baseHeight, width: baseSize.width, height: baseHeight)
        plinthFront.contents = Textures.plinthFront(size: baseSize, scale: scale)

        // Vertical posts joining the deck to the raised tonearm plane.
        let pivot = up(DeckGeometry.pivot, in: DeckGeometry.size.height)
        configureTower(pivotTower, from: project(pivot, z: 0, layer: deckLayer.plane), to: project(pivot, z: lift, layer: deckLayer.plane), width: 26)
        let rest = up(DeckGeometry.restPost, in: DeckGeometry.size.height)
        configureTower(restTower, from: project(rest, z: 0, layer: deckLayer.plane), to: project(rest, z: lift - 6, layer: deckLayer.plane), width: 9)

        // Album on a wooden stand.
        sleeve.container.position = up(CGPoint(x: 385, y: 688), in: H)
        sleeve.setShadow(opacity: night ? 0.6 : 0.45, radius: 24, offset: night ? CGSize(width: -30, height: -6) : CGSize(width: 26, height: -10))
        stand.frame = CGRect(x: 130, y: H - 970, width: 520, height: 66)
        stand.contents = Textures.stand(size: stand.bounds.size, scale: scale)
        stand.shadowColor = .black
        stand.shadowOpacity = 0.35
        stand.shadowRadius = 6
        stand.shadowOffset = CGSize(width: 0, height: -4)

        // Lamp light that breathes very slightly.
        glow.type = .radial
        glow.frame = CGRect(x: lampBulb.x - 1100, y: H - lampBulb.y - 1100, width: 2200, height: 2200)
        let glowStrength: CGFloat = photo == nil ? 1 : 0.6
        glow.colors = [Draw.color(0xFFC27A, 0.30 * glowStrength), Draw.color(0xFFA050, 0.12 * glowStrength), Draw.color(0xFFA050, 0)]
        glow.locations = [0, 0.4, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.isHidden = !night
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [1, 0.93, 0.98, 0.9, 1, 0.96, 1]
        flicker.keyTimes = [0, 0.15, 0.3, 0.5, 0.7, 0.85, 1]
        flicker.duration = 7
        flicker.repeatCount = .infinity
        glow.add(flicker, forKey: "flicker")

        shade.type = .radial
        shade.frame = CGRect(x: lampBulb.x - 1900, y: H - lampBulb.y - 1900, width: 3800, height: 3800)
        shade.colors = [Draw.black(0), Draw.black(0.2), Draw.black(0.58)]
        shade.locations = [0, 0.25, 0.6]
        shade.startPoint = CGPoint(x: 0.5, y: 0.5)
        shade.endPoint = CGPoint(x: 1, y: 1)
        shade.isHidden = !(night && photo != nil)

        for layer in [plinthFront, deckLayer.plane, restTower, pivotTower, deckLayer.armHost] { stage.addSublayer(layer) }
        stage.addSublayer(sleeve.container)
        stage.addSublayer(stand)
        for layer in [background, stage, shade, glow] { root.addSublayer(layer) }
    }

    func setArtwork(_ art: CGImage?, animated: Bool) {
        sleeve.setArtwork(art, animated: animated)
        deckLayer.setLabel(art, animated: animated)
    }

    var size: CGSize { worldSize }
    var deck: DeckLayer? { deckLayer }
    func setDiscRotation(_ radians: CGFloat) { deckLayer.setDiscRotation(radians) }
    var spinningLayers: [CALayer] { [deckLayer.disc] }

    private func configureTower(_ tower: CAGradientLayer, from bottom: CGPoint, to top: CGPoint, width: CGFloat) {
        tower.colors = [Draw.color(0x0E0E0E), Draw.color(0x4A4A4A), Draw.color(0x1A1A1A), Draw.color(0x080808)]
        tower.locations = [0, 0.35, 0.6, 1]
        tower.startPoint = CGPoint(x: 0, y: 0.5)
        tower.endPoint = CGPoint(x: 1, y: 0.5)
        tower.cornerRadius = width * 0.3
        tower.frame = CGRect(x: (bottom.x + top.x) / 2 - width / 2, y: bottom.y - width * 0.15,
                             width: width, height: max(top.y - bottom.y, 1) + width * 0.15)
    }

    /// Projects a point on a layer inside `stage` (y-up local coords, `z` along the
    /// layer's normal) to stage coordinates, including the stage perspective.
    private func project(_ p: CGPoint, z: CGFloat, layer: CALayer) -> CGPoint {
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        // sublayerTransform (the perspective) is applied about the stage's anchor point.
        let stageAnchor = CGPoint(x: stage.anchorPoint.x * stage.bounds.width, y: stage.anchorPoint.y * stage.bounds.height)
        var m = CATransform3DMakeTranslation(-anchor.x, -anchor.y, 0)
        m = CATransform3DConcat(m, layer.transform)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(layer.position.x - stageAnchor.x, layer.position.y - stageAnchor.y, 0))
        m = CATransform3DConcat(m, perspective)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(stageAnchor.x, stageAnchor.y, 0))
        let x = p.x * m.m11 + p.y * m.m21 + z * m.m31 + m.m41
        let y = p.x * m.m12 + p.y * m.m22 + z * m.m32 + m.m42
        let w = p.x * m.m14 + p.y * m.m24 + z * m.m34 + m.m44
        return CGPoint(x: x / w, y: y / w)
    }
}
