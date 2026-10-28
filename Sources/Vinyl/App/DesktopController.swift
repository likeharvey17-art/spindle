import AppKit
import Combine

/// A borderless window pinned to the desktop layer: above the wallpaper,
/// below desktop icons and every app window, invisible to clicks.
final class DesktopWindow: NSWindow {
    let sceneView: SceneView

    init(screen: NSScreen) {
        sceneView = SceneView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = sceneView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopController {
    private let nowPlaying: NowPlayingCenter
    private let settings: AppSettings
    private var windows: [DesktopWindow] = []
    private var card: CardWindow?
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    private var lastTrackKey: String?
    /// The track whose art is on the record now, so a new one plays the flip.
    private var shownArtKey: String?
    private var visible = true

    /// Every scene on screen: one per display, plus the card.
    private var sceneViews: [SceneView] { windows.map(\.sceneView) + (card.map { [$0.sceneView] } ?? []) }

    init(nowPlaying: NowPlayingCenter, settings: AppSettings) {
        self.nowPlaying = nowPlaying
        self.settings = settings
        rebuildWindows()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        // The Mono widget follows Light/Dark mode.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(appearanceChanged),
                                                            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        // Settings → scene look.
        Publishers.CombineLatest(settings.$scene, settings.$framing)
            .receive(on: RunLoop.main)
            .sink { [weak self] scene, framing in
                self?.windows.forEach { $0.sceneView.configure(scene: scene, framing: framing) }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(settings.$cardEnabled, settings.$cardSize, settings.$cardStyle)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in DispatchQueue.main.async { self?.rebuildCard() } }
            .store(in: &cancellables)

        Publishers.CombineLatest3(settings.$desktopArtwork, settings.$hideOnPause, nowPlaying.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateVisibility() }
            .store(in: &cancellables)

        // Now playing → scene content.
        nowPlaying.$artwork
            .receive(on: RunLoop.main)
            .sink { [weak self] image in
                guard let self else { return }
                let key = self.nowPlaying.track?.key
                // Fade only when the record actually changes, not on the first draw.
                let animated = self.lastTrackKey != nil
                self.lastTrackKey = key
                // A new track's art arriving swaps the record over.
                let flip = image != nil && self.shownArtKey != nil && key != self.shownArtKey
                if image != nil { self.shownArtKey = key }
                let cg = image?.cg
                self.sceneViews.forEach { $0.setArtwork(cg, animated: animated, flip: flip) }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(nowPlaying.$isPlaying, nowPlaying.$track)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.pushPlayback() }
            }
            .store(in: &cancellables)

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.nowPlaying.isPlaying else { return }
            self.pushPlayback()
        }
        progressTimer?.tolerance = 0.1
    }

    private func pushPlayback() {
        let hasTrack = nowPlaying.track != nil
        // SPINDLE_FORCE_SPIN keeps the record turning, for performance measurements.
        let forced = ProcessInfo.processInfo.environment["SPINDLE_FORCE_SPIN"] != nil
        sceneViews.forEach { $0.setPlayback(playing: nowPlaying.isPlaying || forced, hasTrack: hasTrack || forced) }
    }

    private func updateVisibility() {
        let paused = settings.hideOnPause && !nowPlaying.isPlaying
        if let card {
            let showCard = settings.cardEnabled && !paused
            if card.alphaValue != (showCard ? 1 : 0) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.8
                    card.animator().alphaValue = showCard ? 1 : 0
                }
            }
            card.ignoresMouseEvents = !showCard
            card.sceneView.isOnScreen = showCard
        }
        let show = settings.desktopArtwork && !paused
        guard show != visible || windows.contains(where: { $0.alphaValue != (show ? 1 : 0) }) else { return }
        visible = show
        for w in windows {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.8
                w.animator().alphaValue = show ? 1 : 0
            }
            w.sceneView.isOnScreen = show && w.occlusionState.contains(.visible)
        }
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    @objc private func wake() {
        // Display configuration can settle after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.rebuildWindows() }
    }

    @objc private func appearanceChanged() {
        guard settings.cardEnabled, settings.cardStyle == .mono else { return }
        // The new appearance is in effect a moment after the notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.rebuildCard() }
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let w = note.object as? DesktopWindow else { return }
        w.sceneView.isOnScreen = visible && w.occlusionState.contains(.visible)
    }

    private func rebuildWindows() {
        for w in windows {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: w)
            w.orderOut(nil)
            w.close()
        }
        windows = NSScreen.screens.map { DesktopWindow(screen: $0) }
        let cgArt = nowPlaying.artwork?.cg
        for w in windows {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: w)
            w.alphaValue = visible ? 1 : 0
            w.sceneView.configure(scene: settings.scene, framing: settings.framing)
            w.sceneView.setArtwork(cgArt, animated: false)
            w.orderFrontRegardless()
            w.sceneView.layoutSubtreeIfNeeded()
        }
        rebuildCard()
    }

    /// Puts up (or takes down) the desktop card at the chosen size and style.
    private func rebuildCard() {
        card?.orderOut(nil)
        card?.close()
        card = nil
        if settings.cardEnabled {
            let w = CardWindow(style: settings.cardStyle, size: settings.cardSize)
            w.sceneView.setArtwork(nowPlaying.artwork?.cg, animated: false)
            w.alphaValue = 0
            w.orderFrontRegardless()
            w.sceneView.layoutSubtreeIfNeeded()
            card = w
        }
        pushPlayback()
        updateVisibility()
    }
}
