import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktop: DesktopController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let nowPlaying = NowPlayingCenter.shared
        let settings = AppSettings.shared
        nowPlaying.start()
        desktop = DesktopController(nowPlaying: nowPlaying, settings: settings)
        menuBar = MenuBarController(nowPlaying: nowPlaying, settings: settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NowPlayingCenter.shared.stop()
    }
}
