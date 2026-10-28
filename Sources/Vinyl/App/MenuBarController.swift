import AppKit
import SwiftUI

/// Menu bar icon that opens the Spindle panel. The app has no Dock icon.
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let nowPlaying: NowPlayingCenter
    private let settings: AppSettings

    init(nowPlaying: NowPlayingCenter, settings: AppSettings) {
        self.nowPlaying = nowPlaying
        self.settings = settings
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Spindle")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggle(_:))
        }
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .aqua)
        popover.delegate = self
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // A fresh panel every time, sized exactly before showing: a reused one
        // could come back out of step with the popover and show cut off.
        let host = FirstClickHostingView(rootView: PanelView(nowPlaying: nowPlaying, settings: settings))
        // Measure with SwiftUI's own sizing, then lock it so nothing re-sizes mid-show.
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        let controller = NSViewController()
        controller.view = host
        controller.preferredContentSize = size
        popover.contentViewController = controller
        popover.contentSize = size
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Opens and closes the popover a few times, printing panel vs window size
    /// each time (`Spindle --popover-test`).
    func debugCycle(_ remaining: Int) {
        guard remaining > 0, let button = statusItem.button else { exit(0) }
        toggle(button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let host = self.popover.contentViewController?.view
            let window = host?.window
            print("open #\(4 - remaining): panel \(host?.frame.size ?? .zero) window content \(window?.contentView?.frame.size ?? .zero) shown \(self.popover.isShown) icon at \(button.window?.frame ?? .zero) visible \(self.statusItem.isVisible)")
            self.popover.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.debugCycle(remaining - 1) }
        }
    }

    /// Drop the panel once closed, so nothing (the VU meter included) lingers.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

/// Lets the very first click in the panel act on a control instead of only
/// activating the (menu-bar) app.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
