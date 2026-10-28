import AppKit
import Combine

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double?

    var key: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }
    var artworkKey: String { album.isEmpty ? key : "\(artist)\u{1F}\(album)" }
}

/// Merges the system Now Playing feed with direct player scripting and
/// publishes one coherent "what's on the turntable" state.
final class NowPlayingCenter: ObservableObject {
    static let shared = NowPlayingCenter()

    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var playerBundleID: String?
    /// A player macOS won't let Spindle read (Automation permission missing).
    @Published private(set) var blockedPlayer: KnownPlayer?

    private var elapsed: Double?
    private var elapsedAt = Date()
    private var rate: Double = 0

    private let monitor = MediaRemoteMonitor()
    private let resolver = ArtworkResolver()
    private let settings = AppSettings.shared
    private var latestSystem: PlaybackSnapshot?
    private var systemSeen = false
    private var pollTimer: Timer?
    private var pollInFlight = false
    private var tick = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: Lifecycle

    func start() {
        ScriptRunner.shared.onPermission = { [weak self] player, allowed in
            guard let self else { return }
            if !allowed, self.blockedPlayer != player { self.blockedPlayer = player }
            if allowed, self.blockedPlayer == player { self.blockedPlayer = nil }
        }
        monitor.onSnapshot = { [weak self] snapshot in self?.systemUpdate(snapshot) }
        monitor.start()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pollIfNeeded() }
        pollTimer?.tolerance = 0.2

        // Instant updates from players that broadcast changes.
        let names = [
            "com.spotify.client.PlaybackStateChanged",
            "com.apple.Music.playerInfo",
            "com.swinsian.Swinsian-Track-Playing",
            "com.swinsian.Swinsian-Track-Paused",
            "com.swinsian.Swinsian-Track-Stopped",
        ]
        for name in names {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(playerBroadcast), name: Notification.Name(name), object: nil)
        }

        settings.$player.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.reevaluate() }
        }.store(in: &cancellables)
        settings.$includeOtherApps.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.reevaluate() }
        }.store(in: &cancellables)
    }

    func stop() {
        monitor.stop()
        pollTimer?.invalidate()
    }

    // MARK: Position

    func position(at date: Date = Date()) -> Double? {
        guard let elapsed else { return nil }
        let p = elapsed + date.timeIntervalSince(elapsedAt) * rate
        if let d = track?.duration { return min(max(p, 0), d) }
        return max(p, 0)
    }

    var progress: Double? {
        guard let d = track?.duration, d > 0, let p = position() else { return nil }
        return min(max(p / d, 0), 1)
    }

    // MARK: Sources

    private var forcedPlayer: KnownPlayer? { settings.player.player }

    private func systemUpdate(_ snapshot: PlaybackSnapshot?) {
        systemSeen = true
        latestSystem = snapshot
        guard forcedPlayer == nil else { return }
        if let s = snapshot, accepts(s) {
            apply(s)
        } else if snapshot == nil {
            // Nothing in Now Playing: fall back to polling scriptable players.
            pollIfNeeded(force: true)
        }
    }

    private func accepts(_ s: PlaybackSnapshot) -> Bool {
        if let id = s.bundleID, KnownPlayer(rawValue: id) != nil { return true }
        return settings.includeOtherApps
    }

    private func reevaluate() {
        if let forced = forcedPlayer {
            poll(forced)
        } else if let s = latestSystem, accepts(s) {
            apply(s)
        } else {
            pollIfNeeded(force: true)
        }
    }

    @objc private func playerBroadcast(_ note: Notification) {
        let name = note.name.rawValue
        let player: KnownPlayer = name.hasPrefix("com.spotify") ? .spotify : name.hasPrefix("com.apple.Music") ? .music : .swinsian
        if let forced = forcedPlayer, forced != player { return }
        // Let the system feed catch up first, then confirm with the player itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.poll(player) }
    }

    private func pollIfNeeded(force: Bool = false) {
        tick += 1
        if let forced = forcedPlayer {
            poll(forced)
            return
        }
        // Automatic mode leans on the system feed; poll players only when it is empty.
        let systemHasTrack = latestSystem.map(accepts) ?? false
        // Players broadcast changes instantly, so this slow poll is only a safety net.
        guard !systemHasTrack, systemSeen || tick > 3, force || tick % 10 == 0 else { return }
        for player in KnownPlayer.allCases where player.isRunning {
            poll(player)
            return
        }
        if latestSystem == nil, track != nil, isPlaying { setPlaying(false) }
    }

    /// Ask a scriptable player for its full state.
    private func poll(_ player: KnownPlayer) {
        guard player.isRunning else {
            if forcedPlayer == player, isPlaying { setPlaying(false) }
            return
        }
        guard !pollInFlight else { return }
        pollInFlight = true
        ScriptRunner.shared.run(player.stateScript) { [weak self] result in
            guard let self else { return }
            self.pollInFlight = false
            guard let raw = result?.stringValue else { return }
            guard let snapshot = KnownPlayer.parseState(raw, player: player) else {
                if self.playerBundleID == player.bundleID || self.forcedPlayer == player { self.setPlaying(false) }
                return
            }
            // In automatic mode a paused player must not override a playing system source.
            if self.forcedPlayer == nil, let sys = self.latestSystem, self.accepts(sys), sys.isPlaying,
               sys.bundleID != player.bundleID { return }
            self.apply(snapshot)
        }
    }

    // MARK: State

    private func apply(_ s: PlaybackSnapshot) {
        let incoming = Track(title: s.title, artist: s.artist, album: s.album, duration: s.duration)
        if incoming.key != track?.key {
            track = incoming
            artwork = resolver.cached(incoming.artworkKey)
            Trace.log("track: \(incoming.title) / \(incoming.album) from \(s.bundleID ?? "?"), cached art \(artwork != nil)")
            requestArtwork(for: s, track: incoming)
        } else {
            if incoming.duration != nil, incoming.duration != track?.duration { track = incoming }
            if let data = s.artworkData, let image = NSImage(data: data) {
                // Exact art from the player wins over a search result.
                resolver.store(image, for: incoming.artworkKey)
                artwork = image
            } else if artwork == nil {
                requestArtwork(for: s, track: incoming)
            }
        }
        if playerBundleID != s.bundleID { playerBundleID = s.bundleID }
        elapsed = s.elapsed
        elapsedAt = s.elapsedAt
        rate = s.rate
        if isPlaying != s.isPlaying { isPlaying = s.isPlaying }
    }

    /// Looks up the art, trying again a little later if nothing turned up
    /// (players often have no art yet in the first moment of a new track).
    private func requestArtwork(for s: PlaybackSnapshot, track: Track, attempt: Int = 0) {
        resolver.resolve(s, key: track.artworkKey) { [weak self] image in
            guard let self, self.track?.artworkKey == track.artworkKey else {
                Trace.log("art: dropped art for \(track.title), now on \(self?.track?.title ?? "nothing")")
                return
            }
            if let image {
                self.artwork = image
            } else if attempt < 3 {
                let wait: Double = [1.5, 4, 10][attempt]
                Trace.log("art: none for \(track.title) yet, trying again in \(wait)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    guard let self, self.artwork == nil, self.track?.artworkKey == track.artworkKey else { return }
                    self.requestArtwork(for: s, track: track, attempt: attempt + 1)
                }
            }
        }
    }

    private func setPlaying(_ playing: Bool) {
        if let p = position() { elapsed = p; elapsedAt = Date() }
        rate = playing ? 1 : 0
        if isPlaying != playing { isPlaying = playing }
    }
}
