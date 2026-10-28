import Foundation
import Combine
import ServiceManagement

enum SceneKind: String, CaseIterable, Identifiable {
    case listeningRoom, afterHours, turntable, overheadNight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listeningRoom: return "Golden Hour"
        case .afterHours: return "Lamplight"
        case .turntable: return "Overhead"
        case .overheadNight: return "Midnight"
        }
    }
}

/// The desktop card's size.
enum CardSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { String(rawValue.prefix(1)).uppercased() }
}

/// The desktop card's look.
enum CardStyle: String, CaseIterable, Identifiable {
    case goldenHour, lamplight, overhead, midnight, minimal, mono

    var id: String { rawValue }
    var title: String {
        switch self {
        case .goldenHour: return "Golden"
        case .lamplight: return "Lamp"
        case .overhead: return "Overhead"
        case .midnight: return "Midnight"
        case .minimal: return "Minimal"
        case .mono: return "Mono"
        }
    }
}

enum Framing: String, CaseIterable, Identifiable {
    case wide, mid, close

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var zoom: CGFloat {
        switch self {
        case .wide: return 1.0
        case .mid: return 1.16
        case .close: return 1.34
        }
    }
}

enum PlayerChoice: String, CaseIterable, Identifiable {
    case automatic, spotify, appleMusic, swinsian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .swinsian: return "Swinsian"
        }
    }

    var player: KnownPlayer? {
        switch self {
        case .automatic: return nil
        case .spotify: return .spotify
        case .appleMusic: return .music
        case .swinsian: return .swinsian
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var scene: SceneKind { didSet { defaults.set(scene.rawValue, forKey: "scene") } }
    @Published var framing: Framing { didSet { defaults.set(framing.rawValue, forKey: "framing") } }
    @Published var desktopArtwork: Bool { didSet { defaults.set(desktopArtwork, forKey: "desktopArtwork") } }
    @Published var hideOnPause: Bool { didSet { defaults.set(hideOnPause, forKey: "hideOnPause") } }
    @Published var includeOtherApps: Bool { didSet { defaults.set(includeOtherApps, forKey: "includeOtherApps") } }
    @Published var player: PlayerChoice { didSet { defaults.set(player.rawValue, forKey: "player") } }
    /// A small turntable card on the desktop, dragged wherever the user likes.
    @Published var cardEnabled: Bool { didSet { defaults.set(cardEnabled, forKey: "cardEnabled") } }
    @Published var cardSize: CardSize { didSet { defaults.set(cardSize.rawValue, forKey: "cardSize") } }
    @Published var cardStyle: CardStyle { didSet { defaults.set(cardStyle.rawValue, forKey: "cardStyle") } }
    /// Hides Finder's desktop icons and desktop widgets so only the scene shows.
    @Published var hideDesktopClutter: Bool {
        didSet { if hideDesktopClutter != oldValue { DesktopClutter.setHidden(hideDesktopClutter) } }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !syncingLoginItem else { return }
            applyLaunchAtLogin()
        }
    }

    private var syncingLoginItem = false

    private init() {
        scene = SceneKind(rawValue: defaults.string(forKey: "scene") ?? "") ?? .turntable
        framing = Framing(rawValue: defaults.string(forKey: "framing") ?? "") ?? .wide
        desktopArtwork = defaults.object(forKey: "desktopArtwork") as? Bool ?? true
        hideOnPause = defaults.object(forKey: "hideOnPause") as? Bool ?? false
        includeOtherApps = defaults.object(forKey: "includeOtherApps") as? Bool ?? true
        player = PlayerChoice(rawValue: defaults.string(forKey: "player") ?? "") ?? .automatic
        cardEnabled = defaults.object(forKey: "cardEnabled") as? Bool ?? false
        cardSize = CardSize(rawValue: defaults.string(forKey: "cardSize") ?? "") ?? .medium
        cardStyle = CardStyle(rawValue: defaults.string(forKey: "cardStyle") ?? "") ?? .minimal
        hideDesktopClutter = DesktopClutter.isHidden
        launchAtLogin = LoginAgent.isInstalled
    }

    private func applyLaunchAtLogin() {
        if ProcessInfo.processInfo.environment["SPINDLE_SAFE_TEST"] != nil { return }
        if !LoginAgent.set(enabled: launchAtLogin) {
            syncingLoginItem = true
            launchAtLogin = LoginAgent.isInstalled
            syncingLoginItem = false
        }
    }
}

/// Opens Spindle at login through a per-user launch agent. (SMAppService
/// refuses ad-hoc-signed apps, reporting `.notFound`, so it can't be used.)
enum LoginAgent {
    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.tryphonbrooks.spindle.plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Returns whether the change took effect.
    static func set(enabled: Bool) -> Bool {
        if !enabled {
            try? FileManager.default.removeItem(at: url)
            return !isInstalled
        }
        let agent: [String: Any] = [
            "Label": "com.tryphonbrooks.spindle",
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
        ]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Spindle: could not add login item: \(error.localizedDescription)")
            return false
        }
    }
}

/// Desktop icons and widgets are macOS's own settings: Finder's `CreateDesktop`
/// and the window manager's widget visibility. Finder and WindowManager are
/// restarted (launchd brings them straight back) so the change shows at once.
enum DesktopClutter {
    static var isHidden: Bool {
        (UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool) == false
    }

    static func setHidden(_ hidden: Bool) {
        if ProcessInfo.processInfo.environment["SPINDLE_SAFE_TEST"] != nil { return }
        DispatchQueue.global(qos: .userInitiated).async {
            run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hidden ? "false" : "true"])
            run("/usr/bin/defaults", ["write", "com.apple.WindowManager", "StandardHideWidgets", "-bool", hidden ? "true" : "false"])
            run("/usr/bin/defaults", ["write", "com.apple.WindowManager", "StageManagerHideWidgets", "-bool", hidden ? "true" : "false"])
            run("/usr/bin/killall", ["Finder"])
            run("/usr/bin/killall", ["WindowManager"])
        }
    }

    private static func run(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
