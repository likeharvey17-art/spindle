import AppKit

/// Finds album art for a track: player-provided bytes, the player's own
/// AppleScript, a Spotify artwork URL, and finally the iTunes Search API.
final class ArtworkResolver {
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight = Set<String>()

    func cached(_ key: String) -> NSImage? { cache.object(forKey: key as NSString) }

    func store(_ image: NSImage, for key: String) { cache.setObject(image, forKey: key as NSString) }

    /// Calls back with the art, or nil when every source came up empty.
    func resolve(_ snapshot: PlaybackSnapshot, key: String, completion: @escaping (NSImage?) -> Void) {
        if let hit = cached(key) { completion(hit); return }
        guard !inFlight.contains(key) else { Trace.log("art: already looking for \(snapshot.title)"); return }
        Trace.log("art: looking for \(snapshot.title) (bytes \(snapshot.artworkData != nil), url \(snapshot.artworkURL != nil), from \(snapshot.bundleID ?? "?"))")
        inFlight.insert(key)

        let finish: (NSImage?) -> Void = { [weak self] image in
            guard let self else { return }
            if let image {
                Trace.log("art: found for \(snapshot.title)")
                self.inFlight.remove(key)
                self.store(image, for: key)
                completion(image)
            } else {
                self.searchITunes(snapshot) { found in
                    Trace.log("art: iTunes search for \(snapshot.title) \(found == nil ? "found nothing" : "found art")")
                    self.inFlight.remove(key)
                    if let found { self.store(found, for: key) }
                    completion(found)
                }
            }
        }

        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            finish(image)
        } else if let url = snapshot.artworkURL {
            download(url, completion: finish)
        } else if let id = snapshot.bundleID, let player = KnownPlayer(rawValue: id),
                  player == .spotify {
            // Spotify was reported by the system monitor: ask it for the artwork URL.
            ScriptRunner.shared.run("tell application id \"\(id)\" to artwork url of current track") { [weak self] result in
                guard let s = result?.stringValue, let url = URL(string: s) else { finish(nil); return }
                self?.download(url, completion: finish)
            }
        } else if let id = snapshot.bundleID, let player = KnownPlayer(rawValue: id),
                  let script = player.artworkScript, player.isRunning {
            ScriptRunner.shared.run(script) { result in
                finish(result.flatMap { NSImage(data: $0.data) })
            }
        } else {
            finish(nil)
        }
    }

    private func download(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    /// Searches the iTunes catalog: the album first, then the song, with edition
    /// notes such as "(Remastered 2009)" or "- Single" taken off, which the
    /// catalog rarely matches.
    private func searchITunes(_ s: PlaybackSnapshot, completion: @escaping (NSImage?) -> Void) {
        let artist = Self.plain(s.artist), album = Self.plain(s.album), title = Self.plain(s.title)
        var queries: [(String, String)] = []
        if !album.isEmpty { queries.append(("album", [artist, album].filter { !$0.isEmpty }.joined(separator: " "))) }
        if !title.isEmpty { queries.append(("song", [artist, title].filter { !$0.isEmpty }.joined(separator: " "))) }
        search(queries[...], completion: completion)
    }

    private func search(_ queries: ArraySlice<(String, String)>, completion: @escaping (NSImage?) -> Void) {
        guard let (entity, term) = queries.first, var comps = URLComponents(string: "https://itunes.apple.com/search") else {
            completion(nil); return
        }
        comps.queryItems = [.init(name: "term", value: term), .init(name: "entity", value: entity), .init(name: "limit", value: "1")]
        guard let url = comps.url else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (json["results"] as? [[String: Any]])?.first,
                  let small = first["artworkUrl100"] as? String,
                  let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "1200x1200bb"))
            else {
                DispatchQueue.main.async { self.search(queries.dropFirst(), completion: completion) }
                return
            }
            self.download(big, completion: completion)
        }.resume()
    }

    /// A title without edition notes: brackets mentioning a remaster, deluxe
    /// edition, featured artist and so on, and trailing "- Remastered 2011" parts.
    static func plain(_ s: String) -> String {
        let notes = "remaster|deluxe|edition|anniversary|expanded|version|bonus|mono|stereo|live|feat\\.|ft\\.|with |single|official|video|audio|lyric"
        var t = s.replacingOccurrences(of: "\\s*[(\\[][^)\\]]*(\(notes))[^)\\]]*[)\\]]", with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "\\s+-\\s+[^-]*(\(notes)).*$", with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }
}
