import AppKit
import SwiftUI
import Metal
import QuartzCore

/// `Spindle --snapshot <turntable|listeningRoom|afterHours> <out.png> [wide|mid|close]`
/// renders a scene offscreen with sample artwork, mid-song, for visual checks.
enum DebugSnapshot {
    /// `Spindle --panel <out.png>` renders the settings panel.
    static func panel(to path: String) {
        let host = NSHostingView(rootView: PanelView(nowPlaying: .shared, settings: .shared))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("panel \(host.fittingSize)")
    }

    /// `Spindle --panel-click <x> <y>` clicks the panel at a point (from its
    /// top-left) in an offscreen window and reports whether "Hide on pause"
    /// changed, then restores it.
    static func panelClick(x: CGFloat, y: CGFloat) {
        let settings = AppSettings.shared
        let before = settings.hideOnPause
        let host: NSView
        if ProcessInfo.processInfo.environment["SPINDLE_TEST_PLAIN"] != nil {
            let plain = NSHostingView(rootView: Button("toggle") { settings.hideOnPause.toggle() }.frame(width: 404, height: 779))
            plain.frame.size = NSSize(width: 404, height: 779)
            host = plain
        } else {
            let panel = NSHostingView(rootView: PanelView(nowPlaying: .shared, settings: settings))
            panel.frame.size = panel.fittingSize
            host = panel
        }
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: host.frame.width, height: host.frame.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.level = .floating
        window.alphaValue = 0.01
        window.orderFrontRegardless()
        window.makeKey()
        let point = NSPoint(x: x, y: host.frame.height - y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let after = settings.hideOnPause
                print("hideOnPause before \(before) after \(after) -> \(before != after ? "CLICK WORKED" : "NO CHANGE")")
                settings.hideOnPause = before
                exit(0)
            }
        }
        NSApp.run()
    }

    /// `Spindle --panel-test`: clicks every control in turn, reports which
    /// setting each click changed, then restores the original settings.
    /// Run with SPINDLE_SAFE_TEST=1 so Clear desk / At login have no side effects.
    static func panelTest() {
        let s = AppSettings.shared
        func state() -> [String: String] {
            ["scene": s.scene.rawValue, "framing": s.framing.rawValue, "source": s.player.rawValue,
             "desktop": "\(s.desktopArtwork)", "hideOnPause": "\(s.hideOnPause)", "clearDesk": "\(s.hideDesktopClutter)",
             "webAudio": "\(s.includeOtherApps)", "atLogin": "\(s.launchAtLogin)",
             "widget": "\(s.cardEnabled)", "widgetSize": s.cardSize.rawValue, "widgetStyle": s.cardStyle.rawValue]
        }
        let original = (s.scene, s.framing, s.player, s.desktopArtwork, s.hideOnPause, s.hideDesktopClutter, s.includeOtherApps, s.launchAtLogin)
        let extras = (s.cardEnabled, s.cardSize, s.cardStyle)
        let host = NSHostingView(rootView: PanelView(nowPlaying: .shared, settings: s))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: host.frame.width, height: host.frame.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.level = .floating
        window.alphaValue = 0.01
        window.orderFrontRegardless()
        window.makeKey()
        let raw = ProcessInfo.processInfo.environment["SPINDLE_TEST_POINTS"] ?? ""
        let points: [(String, CGFloat, CGFloat)] = raw.split(separator: ";").compactMap { item in
            let f = item.split(separator: ",")
            guard f.count == 3, let x = Double(f[1]), let y = Double(f[2]) else { return nil }
            return (String(f[0]), CGFloat(x), CGFloat(y))
        }
        func click(_ i: Int) {
            guard i < points.count else {
                (s.scene, s.framing, s.player, s.desktopArtwork, s.hideOnPause, s.hideDesktopClutter, s.includeOtherApps, s.launchAtLogin) = original
                (s.cardEnabled, s.cardSize, s.cardStyle) = extras
                exit(0)
            }
            let (name, x, y) = points[i]
            let before = state()
            let p = NSPoint(x: x, y: host.frame.height - y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    NSApp.postEvent(e, atStart: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let after = state()
                let changed = after.keys.sorted().filter { before[$0] != after[$0] }.map { "\($0): \(before[$0]!) -> \(after[$0]!)" }
                print("\(name): " + (changed.isEmpty ? "NO CHANGE" : changed.joined(separator: ", ")))
                click(i + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { click(0) }
        NSApp.run()
    }

    static func run(_ args: [String]) {
        guard args.count >= 2, let kind = SceneKind(rawValue: args[0]) else {
            print("usage: --snapshot <scene> <out.png> [framing]")
            return
        }
        let framing = args.count > 2 ? Framing(rawValue: args[2]) ?? .wide : .wide
        let size = CGSize(width: 1512, height: 982)
        let view = SceneView(frame: NSRect(origin: .zero, size: size))
        view.configure(scene: kind, framing: framing)
        view.layoutSubtreeIfNeeded()
        view.setArtwork(sampleArt(hue: 0.02), animated: false)
        view.setPlayback(playing: true, hasTrack: true)
        if let angle = ProcessInfo.processInfo.environment["VINYL_SNAPSHOT_ANGLE"].flatMap(Double.init) {
            view.poseRecord(at: CGFloat(angle))
        }
        view.isOnScreen = false
        render(view, size: size, background: CGColor(gray: 0.2, alpha: 1), to: args[1])
    }

    /// `Spindle --card <hifi|minimal> <small|medium|large> <out.png>` renders a
    /// desktop card offscreen on a neutral backdrop.
    static func card(_ args: [String]) {
        guard args.count >= 3, let style = CardStyle(rawValue: args[0]), let cardSize = CardSize(rawValue: args[1]) else {
            print("usage: --card <hifi|minimal> <small|medium|large> <out.png>")
            return
        }
        let size = CardLayout.window(style: style, size: cardSize)
        let view = SceneView(frame: NSRect(origin: .zero, size: size))
        view.layer?.backgroundColor = .clear
        view.configure(card: style, size: cardSize)
        view.layoutSubtreeIfNeeded()
        view.setArtwork(sampleArt(hue: 0.58), animated: false)
        view.setPlayback(playing: true, hasTrack: true)
        view.isOnScreen = false
        render(view, size: size, background: Draw.color(0x6E7B86), to: args[2])
    }

    private static func render(_ view: SceneView, size: CGSize, background: CGColor, to path: String) {
        guard let layer = view.layer, let device = MTLCreateSystemDefaultDevice() else { return }
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { return }

        // Render the view's layer at 2x inside a wrapper root.
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        root.position = CGPoint(x: w / 2, y: h / 2)
        root.backgroundColor = background
        layer.removeFromSuperlayer()
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        root.addSublayer(layer)

        guard let queue = device.makeCommandQueue() else { return }
        let renderer = CARenderer(mtlTexture: texture, options: [
            kCARendererColorSpace as String: Draw.colorSpace,
            kCARendererMetalCommandQueue as String: queue,
        ])
        renderer.layer = root
        renderer.bounds = root.bounds
        CATransaction.flush()
        // Render well after the arm/label animations have settled.
        renderer.beginFrame(atTime: CACurrentMediaTime() + 4, timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The queue is serial: once this empty buffer completes, the render has too.
        let fence = queue.makeCommandBuffer()
        fence?.commit()
        fence?.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        texture.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: Draw.colorSpace, bitmapInfo: info.rawValue),
              let raw = ctx.makeImage() else { return }
        // Metal textures are top-left origin; flip rows so the PNG matches the screen.
        let image = Draw.image(CGSize(width: w, height: h), scale: 1) { c in
            c.draw(raw, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    private static func sampleArt(hue: CGFloat) -> CGImage {
        Draw.image(CGSize(width: 600, height: 600), scale: 1) { ctx in
            let a = NSColor(hue: hue, saturation: 0.75, brightness: 0.85, alpha: 1).cgColor
            let b = NSColor(hue: hue + 0.12, saturation: 0.6, brightness: 0.35, alpha: 1).cgColor
            Draw.linear(ctx, [a, b], from: .zero, to: CGPoint(x: 600, y: 600))
            ctx.setFillColor(NSColor(hue: hue + 0.5, saturation: 0.5, brightness: 0.95, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: 170, y: 150, width: 260, height: 260))
            Draw.text("SAMPLE", at: CGPoint(x: 300, y: 500), size: 60, weight: .heavy, color: .white, kern: 6, centered: true)
        }
    }
}
