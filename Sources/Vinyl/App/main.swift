import AppKit
import ServiceManagement

// `Spindle --render-icon <out.png>` renders the app icon and exits (used by build.sh).
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-icon" {
    IconRenderer.writeIcon(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--snapshot" {
    _ = NSApplication.shared
    DebugSnapshot.run(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--card" {
    _ = NSApplication.shared
    DebugSnapshot.card(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--login-status" {
    let status = SMAppService.mainApp.status
    print("login item status:", status == .enabled ? "enabled" : status == .requiresApproval ? "requiresApproval" : status == .notRegistered ? "notRegistered" : status == .notFound ? "notFound" : "unknown")
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--popover-test" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = MenuBarController(nowPlaying: .shared, settings: .shared)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { controller.debugCycle(3) }
    app.run()
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--panel-test" {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    DebugSnapshot.panelTest()
}

if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--panel-click" {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    DebugSnapshot.panelClick(x: CGFloat(Double(CommandLine.arguments[2]) ?? 0), y: CGFloat(Double(CommandLine.arguments[3]) ?? 0))
    exit(0)
}

if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--meter-test" {
    // Prints the VU needle level for a few seconds (needs audio capture permission).
    _ = NSApplication.shared
    let meter = AudioMeter()
    meter.start()
    var ticks = 0
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        ticks += 1
        print(String(format: "available=%@ level=%.2f", meter.available ? "yes" : "no", meter.level))
        if ticks >= 12 { meter.stop(); exit(0) }
    }
    RunLoop.main.run()
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--panel" {
    _ = NSApplication.shared
    DebugSnapshot.panel(to: CommandLine.arguments[2])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
