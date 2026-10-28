import AppKit

/// One reading of "what is playing right now", from any source.
struct PlaybackSnapshot {
    var bundleID: String?
    var title: String
    var artist: String
    var album: String
    var duration: Double?
    /// Elapsed seconds at `elapsedAt`, advancing at `rate` (0 when paused).
    var elapsed: Double?
    var elapsedAt: Date
    var rate: Double
    var isPlaying: Bool
    var artworkData: Data?
    var artworkURL: URL?
}

/// Players with full AppleScript support: exact artwork and playback position.
enum KnownPlayer: String, CaseIterable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
    case swinsian = "com.swinsian.Swinsian"

    var bundleID: String { rawValue }

    var name: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        case .swinsian: return "Swinsian"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Returns "stopped", or state␟title␟artist␟album␟duration␟position[␟artworkURL].
    var stateScript: String {
        let track: String
        switch self {
        case .spotify:
            track = """
            return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (((duration of t) / 1000) as string) & sep & (player position as string) & sep & (artwork url of t)
            """
        case .music, .swinsian:
            track = """
            return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & (player position as string)
            """
        }
        return """
        tell application id "\(bundleID)"
            try
                set sep to (ASCII character 31)
                set s to (player state as string)
                if s is "stopped" then return "stopped"
                set t to current track
                \(track)
            on error
                return "stopped"
            end try
        end tell
        """
    }

    /// Script returning raw artwork bytes, for players that expose them directly.
    var artworkScript: String? {
        switch self {
        case .spotify: return nil
        case .music: return "tell application id \"\(bundleID)\" to get raw data of artwork 1 of current track"
        case .swinsian: return "tell application id \"\(bundleID)\" to get album art of current track"
        }
    }

    static func parseState(_ raw: String, player: KnownPlayer) -> PlaybackSnapshot? {
        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count >= 6, parts[0] != "stopped" else { return nil }
        func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
        let playing = parts[0] == "playing"
        let artURL = parts.count > 6 ? URL(string: parts[6]) : nil
        return PlaybackSnapshot(
            bundleID: player.bundleID,
            title: parts[1], artist: parts[2], album: parts[3],
            duration: number(parts[4]),
            elapsed: number(parts[5]),
            elapsedAt: Date(),
            rate: playing ? 1 : 0,
            isPlaying: playing,
            artworkData: nil,
            artworkURL: artURL
        )
    }
}

/// Runs AppleScript off the main thread, one script at a time.
final class ScriptRunner {
    static let shared = ScriptRunner()

    private let queue = DispatchQueue(label: "vinyl.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    func run(_ source: String, completion: @escaping (NSAppleEventDescriptor?) -> Void) {
        queue.async {
            let script: NSAppleScript
            if let cached = self.compiled[source] {
                script = cached
            } else if let fresh = NSAppleScript(source: source) {
                self.compiled[source] = fresh
                script = fresh
            } else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            DispatchQueue.main.async { completion(error == nil ? result : nil) }
        }
    }
}
