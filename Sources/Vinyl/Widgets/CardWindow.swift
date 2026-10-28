import AppKit

/// The desktop card's window: above the wallpaper scene and the desktop icons,
/// below every app window. Drag it anywhere; it remembers where it was left.
final class CardWindow: NSPanel {
    let sceneView: SceneView
    private static let originKey = "cardOrigin"

    init(style: CardStyle, size: CardSize) {
        let frame = Self.initialFrame(for: CardLayout.window(style: style, size: size))
        sceneView = SceneView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        sceneView.layer?.backgroundColor = .clear
        sceneView.layer?.masksToBounds = false
        contentView = sceneView
        sceneView.configure(card: style, size: size)
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func moved() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.originKey)
    }

    /// Where it was last left, if that is still on a screen; otherwise the top
    /// right of the main screen.
    private static func initialFrame(for s: CGSize) -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        var origin = NSPoint(x: visible.maxX - s.width - 24, y: visible.maxY - s.height - 24)
        if let saved = UserDefaults.standard.string(forKey: originKey) {
            let p = NSPointFromString(saved)
            let middle = NSPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(middle) }) { origin = p }
        }
        return NSRect(origin: origin, size: s)
    }
}
