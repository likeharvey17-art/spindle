import AppKit
import QuartzCore

/// What a SceneView shows: a whole desktop scene, or a turntable card.
enum SceneContent: Equatable {
    case room(SceneKind)
    case card(CardStyle, CardSize)
}

/// Hosts one scene, scales it to the view and spins the record. Desktop
/// scenes fill the screen; cards fit their window.
final class SceneView: NSView {
    private let world = CALayer()
    private var scene: VinylScene?
    private var content: SceneContent?
    private var builtForSize: CGSize = .zero

    private var framing: Framing = .wide
    private var artwork: CGImage?

    private var playing = false

    private var displayLink: CADisplayLink?
    private var discAngle: CGFloat = 0
    private var discVelocity: CGFloat = 0
    private var lastFrame: CFTimeInterval = 0
    /// While cruising at full speed the spin runs as a Core Animation
    /// animation in the system renderer, so the app itself does no work.
    private var cruiseStart: CFTimeInterval?
    private var cruiseAngle: CGFloat = 0
    /// A relaxed 25 rpm in radians per second (a touch slower than a real 33⅓).
    private let playSpeed: CGFloat = 2 * .pi * 25 / 60
    /// The drawn tonearm sits still on the lead-in grooves.
    private let armAngle = DeckGeometry.startAngle + (DeckGeometry.endAngle - DeckGeometry.startAngle) * 0.25
    var isOnScreen = true { didSet { if isOnScreen { updateLink() } else { stopLink() } } }

    private var isCard: Bool {
        if case .card = content { return true }
        return false
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = .black
        layer?.addSublayer(world)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Cards are dragged by their body; the desktop scene's window ignores the mouse.
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        if let content, builtForSize != bounds.size {
            build(content, animated: false)
        }
        layoutWorld(animated: false)
    }

    // MARK: Configuration

    func configure(scene kind: SceneKind, framing: Framing) {
        let framingChanged = framing != self.framing
        self.framing = framing
        if content != .room(kind) {
            build(.room(kind), animated: content != nil)
        } else if framingChanged {
            layoutWorld(animated: true)
        }
    }

    func configure(card style: CardStyle, size: CardSize) {
        guard content != .card(style, size) else { return }
        build(.card(style, size), animated: content != nil)
    }

    /// `flip` plays the track-change animation instead of a plain crossfade.
    func setArtwork(_ image: CGImage?, animated: Bool, flip: Bool = false) {
        artwork = image
        guard let scene else { return }
        guard flip else { scene.setArtwork(image, animated: animated); return }
        scene.changeRecord(to: image)
        guard playing else { return }
        // The platter dips and picks back up, as if the record was swapped.
        endCruise()
        discVelocity = min(discVelocity, playSpeed) * 0.35
        updateLink()
    }

    func setPlayback(playing: Bool, hasTrack: Bool) {
        self.playing = playing && hasTrack
        if !self.playing { endCruise() }
        updateLink()
    }

    // MARK: Building

    private func build(_ content: SceneContent, animated: Bool) {
        guard bounds.width > 0 else { self.content = content; return }
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        let next: VinylScene
        switch content {
        case .room(let kind):
            let fill = max(bounds.width / worldSize.width, bounds.height / worldSize.height)
            let objectScale = min(fill * backing * Framing.close.zoom, 3)
            let backgroundScale = min(fill * backing * 1.1, 2.2)
            if let photo = PhotoScene.load(kind) {
                next = photo
            } else {
                switch kind {
                case .turntable, .overheadNight: next = TopDownScene(scale: objectScale, backgroundScale: backgroundScale)
                case .listeningRoom: next = FrontScene(night: false, scale: objectScale, backgroundScale: backgroundScale)
                case .afterHours: next = FrontScene(night: true, scale: objectScale, backgroundScale: backgroundScale)
                }
            }
        case .card(.mono, _):
            next = MonoScene(dark: MonoScene.prefersDark)
        case .card(let style, let size):
            guard let photo = PhotoScene.loadWidget(style: style, size: size, scale: backing) else { return }
            next = photo
        }
        let wasCruising = cruiseStart != nil
        endCruise()
        next.setArtwork(artwork, animated: false)
        next.setDiscRotation(discAngle)
        next.deck?.setArmAngle(armAngle, duration: 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.6
            world.add(fade, forKey: "scene")
        }
        scene?.root.removeFromSuperlayer()
        world.bounds = CGRect(origin: .zero, size: next.size)
        world.addSublayer(next.root)
        CATransaction.commit()

        scene = next
        self.content = content
        builtForSize = bounds.size
        layoutWorld(animated: false)
        if wasCruising { beginCruise() }
    }

    /// Desktop scenes fill the view, zooming toward the scene's focus point for
    /// Mid/Close framing; cards fit inside it.
    private func layoutWorld(animated: Bool) {
        guard bounds.width > 0, let scene else { return }
        let size = scene.size
        let room = isCard ? bounds.insetBy(dx: CardLayout.margin, dy: CardLayout.margin).size : bounds.size
        let base = isCard ? min(room.width / size.width, room.height / size.height)
                          : max(room.width / size.width, room.height / size.height)
        // A widget casts a soft shadow onto the desktop.
        world.shadowPath = scene.outline
        world.shadowColor = .black
        world.shadowOpacity = scene.outline == nil ? 0 : 0.32
        world.shadowRadius = 9 / base
        world.shadowOffset = CGSize(width: 0, height: -4 / base)
        let f = up(scene.focus, in: size.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.anchorPoint = CGPoint(x: f.x / size.width, y: f.y / size.height)
        // Put the focus point where a centred fill would show it; zooming then
        // scales around that point, so the screen stays covered.
        world.position = CGPoint(x: center.x + (f.x - size.width / 2) * base,
                                 y: center.y + (f.y - size.height / 2) * base)
        CATransaction.commit()

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.7)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0, 0.1, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        let s = base * (isCard ? 1 : framing.zoom)
        world.transform = CATransform3DMakeScale(s, s, 1)
        CATransaction.commit()
    }

    // MARK: Spinning

    /// Poses the record at a fixed angle (offscreen snapshots only).
    func poseRecord(at radians: CGFloat) {
        endCruise()
        discAngle = radians
        scene?.setDiscRotation(radians)
    }

    private func updateLink() {
        if cruiseStart == nil, (playing || discVelocity > 0), isOnScreen {
            startLink()
        }
    }

    private func startLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = 0
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? 1.0 / 60 : min(now - lastFrame, 0.1)
        lastFrame = now
        // Platter spins up quickly and coasts down slowly, like a real belt drive.
        let target: CGFloat = playing ? playSpeed : 0
        let tau: CGFloat = playing ? 0.55 : 1.1
        discVelocity += (target - discVelocity) * (1 - exp(-CGFloat(dt) / tau))
        if !playing && discVelocity < 0.03 { discVelocity = 0 }
        if playing && playSpeed - discVelocity < playSpeed * 0.003 {
            discVelocity = playSpeed
            beginCruise()
            return
        }
        discAngle = (discAngle + discVelocity * CGFloat(dt)).truncatingRemainder(dividingBy: 2 * .pi)
        scene?.setDiscRotation(discAngle)
        if !playing && discVelocity == 0 { stopLink() }
    }

    /// Hands the steady spin to Core Animation and stops the frame timer.
    private func beginCruise() {
        guard let scene, cruiseStart == nil else { return }
        stopLink()
        cruiseAngle = discAngle
        cruiseStart = CACurrentMediaTime()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = -cruiseAngle
        spin.toValue = -cruiseAngle - 2 * .pi
        spin.duration = CFTimeInterval(2 * .pi / playSpeed)
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        for layer in scene.spinningLayers { layer.add(spin, forKey: "cruise") }
    }

    /// Takes the spin back at its exact current angle (to pause or rebuild).
    private func endCruise() {
        guard let start = cruiseStart else { return }
        cruiseStart = nil
        discAngle = (cruiseAngle + CGFloat(CACurrentMediaTime() - start) * playSpeed).truncatingRemainder(dividingBy: 2 * .pi)
        scene?.spinningLayers.forEach { $0.removeAnimation(forKey: "cruise") }
        scene?.setDiscRotation(discAngle)
    }
}
