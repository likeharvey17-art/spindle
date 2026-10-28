import Foundation

/// Reads the system-wide Now Playing item (what Control Center shows) for any app.
///
/// MediaRemote only answers Apple-signed processes, so the query runs inside a
/// long-lived `osascript` (JavaScript for Automation) that streams JSON lines.
final class MediaRemoteMonitor {
    var onSnapshot: ((PlaybackSnapshot?) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var stopped = false

    func start() {
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    private func launch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", Self.script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, !self.stopped else { return }
                self.buffer.removeAll()
                self.launch()
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("Vinyl: could not start Now Playing monitor: \(error)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            onSnapshot?(Self.snapshot(from: object))
        }
    }

    private static func snapshot(from o: [String: Any]) -> PlaybackSnapshot? {
        let title = o["title"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        let rate = o["rate"] as? Double ?? 0
        let playing = o["playing"] as? Bool ?? (rate > 0)
        var elapsedAt = Date()
        if let ts = o["ts"] as? Double, ts > 0 { elapsedAt = Date(timeIntervalSince1970: ts) }
        var bundle = o["bundle"] as? String
        if let parent = o["parent"] as? String, !parent.isEmpty { bundle = parent }
        return PlaybackSnapshot(
            bundleID: bundle,
            title: title,
            artist: o["artist"] as? String ?? "",
            album: o["album"] as? String ?? "",
            duration: (o["duration"] as? Double).flatMap { $0 > 0 ? $0 : nil },
            elapsed: o["elapsed"] as? Double,
            elapsedAt: elapsedAt,
            rate: playing ? max(rate, 1) : 0,
            isPlaying: playing,
            artworkData: (o["art"] as? String).flatMap { Data(base64Encoded: $0) },
            artworkURL: nil
        )
    }

    // Polls twice a second, emits only on change (plus a heartbeat), and exits
    // after ~10 minutes so JXA memory never accumulates; Swift relaunches it.
    private static let script = #"""
    ObjC.import('Foundation');
    $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
    const R = $.NSClassFromString('MRNowPlayingRequest');
    const out = $.NSFileHandle.fileHandleWithStandardOutput;
    function emit(o) { out.writeData($(JSON.stringify(o) + '\n').dataUsingEncoding($.NSUTF8StringEncoding)); }
    function nil(v) { return v === undefined || v === null || (v.isNil && v.isNil()); }
    function str(v) { if (nil(v)) return ''; const u = ObjC.unwrap(v); return (u === undefined || u === null) ? '' : String(u); }
    function num(v) { if (nil(v)) return null; const u = ObjC.unwrap(v); const n = Number(u); return isNaN(n) ? null : n; }
    const K = 'kMRMediaRemoteNowPlayingInfo';
    let last = '', artKey = '', artDone = false, artTries = 0, quiet = 0;
    for (let i = 0; i < 1200; i++) {
      const o = {};
      let item = null;
      try {
        item = R.localNowPlayingItem;
        o.playing = !!R.localIsPlaying;
        try { const c = R.localNowPlayingPlayerPath.client; o.bundle = str(c.bundleIdentifier); try { o.parent = str(c.parentApplicationBundleIdentifier); } catch (e) {} } catch (e) {}
        const info = nil(item) ? null : item.nowPlayingInfo;
        if (!nil(info)) {
          o.title = str(info.objectForKey(K + 'Title'));
          o.artist = str(info.objectForKey(K + 'Artist'));
          o.album = str(info.objectForKey(K + 'Album'));
          o.duration = num(info.objectForKey(K + 'Duration'));
          o.elapsed = num(info.objectForKey(K + 'ElapsedTime'));
          o.rate = num(info.objectForKey(K + 'PlaybackRate'));
          const ts = info.objectForKey(K + 'Timestamp');
          if (!nil(ts)) o.ts = ts.timeIntervalSince1970;
        }
      } catch (e) { o.error = String(e); }
      const tk = [o.title, o.artist, o.album].join('|');
      if (tk !== artKey) { artKey = tk; artDone = false; artTries = 0; }
      let force = false;
      if (!artDone && artTries < 40 && o.title) {
        artTries++;
        try {
          const aw = item.artwork;
          if (!nil(aw)) { const d = aw.imageData; if (!nil(d) && d.length > 0) { o.art = ObjC.unwrap(d.base64EncodedStringWithOptions(0)); artDone = true; force = true; } }
        } catch (e) {}
      }
      const key = JSON.stringify([o.bundle, o.parent, o.title, o.artist, o.album, o.playing, o.rate, o.duration, o.elapsed]);
      quiet++;
      if (force || key !== last || quiet >= 20) { emit(o); last = key; quiet = 0; }
      delay(0.5);
    }
    """#
}
