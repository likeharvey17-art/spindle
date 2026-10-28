import AppKit
import ImageIO

/// Sizes of the desktop widget: the turntable alone, cut out along its own
/// outline, or the square Mono card. Small is as wide as a small macOS widget.
enum CardLayout {
    /// Room around the widget for its shadow, in points.
    static let margin: CGFloat = 24

    /// The widget itself on screen, in points.
    static func size(style: CardStyle, size: CardSize) -> CGSize {
        let width: CGFloat = size == .small ? 170 : size == .medium ? 260 : 364
        if style == .mono { return CGSize(width: width, height: width) }
        let aspect = WidgetPhoto.calibration(style: style)?.crop.map { $0[2] / $0[3] } ?? 1.2
        return CGSize(width: width, height: (width / aspect).rounded())
    }

    /// The widget's window: the widget plus room for its shadow.
    static func window(style: CardStyle, size: CardSize) -> CGSize {
        let s = self.size(style: style, size: size)
        return CGSize(width: s.width + margin * 2, height: s.height + margin * 2)
    }
}

/// The photos behind the widgets (Resources/Widgets): `<style>.json` names the
/// photo, the turntable's outline in it (`crop` and `corner`), and calibrates
/// its record, label and tonearm like a scene. A style without its own photo
/// yet shows the minimal one.
enum WidgetPhoto {
    private static var folder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Widgets", isDirectory: true) }

    static func calibration(style: CardStyle) -> PhotoCalibration? {
        guard let folder else { return nil }
        for name in [style.rawValue, CardStyle.minimal.rawValue] {
            let url = folder.appendingPathComponent("\(name).json")
            if let data = try? Data(contentsOf: url) {
                do { return try JSONDecoder().decode(PhotoCalibration.self, from: data) } catch {
                    NSLog("Spindle: bad widget calibration \(name).json: \(error)")
                }
            }
        }
        return nil
    }

    static func image(named name: String) -> CGImage? {
        guard let url = folder?.appendingPathComponent(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
