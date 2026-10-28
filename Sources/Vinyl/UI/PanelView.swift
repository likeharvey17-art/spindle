import AppKit
import SwiftUI

// The panel is the front of a 1970s receiver: walnut cheeks, a brushed
// champagne faceplate, a brass nameplate, an amber-lit meter, a rotary scene
// selector, bat-handle toggles and two small selector knobs. Metal parts are
// photographs cut from their own pixels; lettering is engraved.

private enum Faceplate {
    static let ink = Color(red: 0.20, green: 0.18, blue: 0.15)
    static let inkSoft = Color(red: 0.20, green: 0.18, blue: 0.15).opacity(0.78)
    static let brassInk = Color(red: 0.24, green: 0.16, blue: 0.06)
    static let meterInk = Color(red: 0.22, green: 0.12, blue: 0.04)
}

private enum Lettering {
    static func label(_ size: CGFloat) -> Font { .custom("DINCondensed-Bold", size: size) }
    static func figures(_ size: CGFloat) -> Font { .custom("DINAlternate-Bold", size: size).monospacedDigit() }
    static func name(_ size: CGFloat) -> Font { .custom("Futura-Medium", size: size) }
}

/// Bundled photographic parts (Resources/Panel).
private enum Part {
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage {
        if let hit = cache[name] { return hit }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Panel")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(size: NSSize(width: 1, height: 1))
        cache[name] = image
        return image
    }
}

/// Text cut into metal: dark fill with a one-pixel light edge below it.
private struct Engraved: View {
    let text: String
    var font: Font = Lettering.label(11)
    var tracking: CGFloat = 1.4
    var color: Color = Faceplate.ink
    var highlight: Double = 0.55

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .kerning(tracking)
            .foregroundStyle(color)
            .shadow(color: .white.opacity(highlight), radius: 0, x: 0, y: 0.8)
    }
}

/// A line cut across the faceplate.
private struct Groove: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.28)).frame(height: 0.5)
            Rectangle().fill(Color.white.opacity(0.55)).frame(height: 0.5)
        }
    }
}

struct PanelView: View {
    @ObservedObject var nowPlaying: NowPlayingCenter
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            cheek
            faceplate
                .background(
                    Image(nsImage: Part.image("faceplate"))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                )
                .clipped()
            cheek
        }
        .frame(width: 404)
        .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 60)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(red: 0.16, green: 0.10, blue: 0.06))
        .preferredColorScheme(.light)
    }

    private var cheek: some View {
        Image(nsImage: Part.image("walnut"))
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 16)
            .clipped()
            .overlay(LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
            // Clipping only hides the overflow of the scaled-up wood; without this
            // the invisible remainder would sit over the faceplate and eat clicks.
            .allowsHitTesting(false)
    }

    private var faceplate: some View {
        VStack(spacing: 7) {
            header
            Meter(nowPlaying: nowPlaying)
            Groove()
            SceneSelector(selection: $settings.scene)
                .opacity(settings.desktopArtwork ? 1 : 0.45)
                .help(settings.desktopArtwork ? "" : "The scene is off — flip Desktop on")
            Groove()
            toggles
            Groove()
            extras
            Groove()
            HStack(alignment: .bottom, spacing: 0) {
                VStack(spacing: 2) {
                    SlideSwitch(title: "Framing", options: Framing.allCases.map { ($0, $0.title) },
                                selection: $settings.framing)
                    Engraved(text: "Framing", font: Lettering.label(10), tracking: 2.4, color: Faceplate.ink)
                }
                .frame(maxWidth: .infinity)
                .opacity(settings.desktopArtwork ? 1 : 0.45)
                Rectangle().fill(Color.black.opacity(0.25)).frame(width: 0.5, height: 84)
                    .overlay(Rectangle().fill(Color.white.opacity(0.5)).frame(width: 0.5).offset(x: 0.75))
                VStack(spacing: 2) {
                    RotaryKnob(title: "Source",
                               options: PlayerChoice.allCases.map { ($0, $0 == .automatic ? "Auto" : $0 == .appleMusic ? "Music" : $0.title) },
                               selection: $settings.player, knobSize: 50, spread: 168, labelSize: 9.5, extraWidth: 16)
                    Engraved(text: "Source", font: Lettering.label(10), tracking: 2.4, color: Faceplate.ink)
                }
                .frame(maxWidth: .infinity)
            }
            HStack {
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Engraved(text: "Power off", font: Lettering.label(11), tracking: 2)
                }
                .buttonStyle(.plain)
                .pointingCursor()
                .help("Quit Spindle")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(alignment: .center) {
            ZStack {
                Image(nsImage: Part.image("plate"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                Engraved(text: "Spindle", font: Lettering.name(15), tracking: 6, color: Faceplate.brassInk, highlight: 0.45)
                    .offset(y: 1)
            }
            .frame(width: 196, height: 43)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1.5)
            Spacer()
            HStack(spacing: 8) {
                Engraved(text: nowPlaying.isPlaying ? "Playing" : "Standby", font: Lettering.label(11), tracking: 1.6)
                Image(nsImage: Part.image("lamp"))
                    .resizable()
                    .frame(width: 24, height: 24)
                    .saturation(nowPlaying.isPlaying ? 1 : 0)
                    // Unlit: dark glass behind the chrome bezel.
                    .overlay(Circle().fill(Color.black.opacity(nowPlaying.isPlaying ? 0 : 0.6)).padding(4))
                    .shadow(color: Color.orange.opacity(nowPlaying.isPlaying ? 0.55 : 0), radius: 6, x: 0, y: 0)
                    .animation(.easeOut(duration: 0.5), value: nowPlaying.isPlaying)
                    .accessibilityLabel(nowPlaying.isPlaying ? "Playing" : "Standby")
            }
        }
    }

    private var toggles: some View {
        HStack(alignment: .top, spacing: 0) {
            BatToggle(title: "Desktop", isOn: $settings.desktopArtwork, help: "Show the scene on the desktop")
            BatToggle(title: "Hide on pause", isOn: $settings.hideOnPause, help: "Fade the scene out while paused")
                .opacity(settings.desktopArtwork ? 1 : 0.5)
            BatToggle(title: "Clear desk", isOn: $settings.hideDesktopClutter, help: "Hide desktop icons and widgets")
            BatToggle(title: "Web audio", isOn: $settings.includeOtherApps, help: "Follow browsers and other apps",
                      note: settings.player == .automatic ? nil : "Auto only")
                .opacity(settings.player == .automatic ? 1 : 0.5)
                .disabled(settings.player != .automatic)
            BatToggle(title: "At login", isOn: $settings.launchAtLogin, help: "Open Spindle at login")
        }
    }

    /// The desktop widget, with its size and look.
    private var extras: some View {
        HStack(alignment: .bottom, spacing: 0) {
            BatToggle(title: "Widget", isOn: $settings.cardEnabled, help: "A small turntable you can drag anywhere on the desktop")
                .frame(width: 64)
            Group {
                VStack(spacing: 2) {
                    SlideSwitch(title: "Widget size", options: CardSize.allCases.map { ($0, $0.title) },
                                selection: $settings.cardSize, width: 70)
                    Engraved(text: "Size", font: Lettering.label(10), tracking: 2.4)
                }
                .frame(width: 100)
                VStack(spacing: 2) {
                    RotaryKnob(title: "Widget style", options: CardStyle.allCases.map { ($0, $0.title) },
                               selection: $settings.cardStyle, knobSize: 46, spread: 244, labelSize: 9.5, extraWidth: 14)
                    Engraved(text: "Style", font: Lettering.label(10), tracking: 2.4)
                }
                .frame(maxWidth: .infinity)
            }
            .opacity(settings.cardEnabled ? 1 : 0.45)
        }
    }
}

// MARK: - Meter

/// The amber-lit window: album art and track, with a VU needle that swings
/// with the loudness of whatever the Mac is playing.
private struct Meter: View {
    @ObservedObject var nowPlaying: NowPlayingCenter
    @StateObject private var meter = AudioMeter()

    var body: some View {
        ZStack {
            Image(nsImage: Part.image("meter"))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .allowsHitTesting(false)
            VStack(spacing: 4) {
                HStack(alignment: .top, spacing: 12) {
                    art
                        .frame(width: 58, height: 58)
                        .overlay(Rectangle().stroke(Faceplate.meterInk.opacity(0.55), lineWidth: 1))
                        .shadow(color: Faceplate.meterInk.opacity(0.35), radius: 2, x: 0, y: 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(nowPlaying.track?.title ?? "No signal")
                            .font(Lettering.name(14))
                            .foregroundStyle(Faceplate.meterInk)
                            .lineLimit(2)
                        Text((nowPlaying.track?.artist ?? "Play something on your Mac").uppercased())
                            .font(Lettering.label(11))
                            .kerning(1)
                            .foregroundStyle(Faceplate.meterInk.opacity(0.72))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                VUScale(level: meter.level)
                    .frame(height: 52)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 22)
        }
        .frame(height: 166)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.4), value: nowPlaying.track?.key)
    }

    @ViewBuilder private var art: some View {
        if let image = nowPlaying.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
        } else {
            ZStack {
                Faceplate.meterInk.opacity(0.85)
                Circle().stroke(Color(red: 0.99, green: 0.86, blue: 0.6).opacity(0.35), lineWidth: 1).padding(9)
                Circle().fill(Color(red: 0.99, green: 0.86, blue: 0.6).opacity(0.5)).frame(width: 6, height: 6)
            }
        }
    }
}

/// A printed VU scale (−20 … +3, red above 0) and a needle pivoting from below.
private struct VUScale: View {
    let level: Double
    private let marks: [(Double, String)] = [(0, "20"), (0.25, "10"), (0.45, "5"), (0.62, "3"), (0.74, "1"), (0.8, "0"), (0.9, "+1"), (1, "+3")]

    var body: some View {
        Canvas { ctx, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height + 168)
            let radius: CGFloat = 206
            let sweep = 0.42
            func point(_ f: Double, _ r: CGFloat) -> CGPoint {
                let a = -Double.pi / 2 + (f - 0.5) * 2 * sweep
                return CGPoint(x: pivot.x + CGFloat(cos(a)) * r, y: pivot.y + CGFloat(sin(a)) * r)
            }
            func arc(_ from: Double, _ to: Double, _ r: CGFloat) -> Path {
                var p = Path()
                p.addArc(center: pivot, radius: r, startAngle: .radians(-Double.pi / 2 + (from - 0.5) * 2 * sweep),
                         endAngle: .radians(-Double.pi / 2 + (to - 0.5) * 2 * sweep), clockwise: false)
                return p
            }
            let ink = Faceplate.meterInk
            let red = Color(red: 0.72, green: 0.16, blue: 0.08)
            ctx.stroke(arc(0, 0.8, radius), with: .color(ink.opacity(0.8)), lineWidth: 1)
            ctx.stroke(arc(0.8, 1, radius + 1.5), with: .color(red.opacity(0.9)), lineWidth: 4)
            for i in 0...24 {
                let f = Double(i) / 24
                let major = i % 4 == 0
                var tick = Path()
                tick.move(to: point(f, radius))
                tick.addLine(to: point(f, radius - (major ? 8 : 4.5)))
                ctx.stroke(tick, with: .color((f > 0.8 ? red : ink).opacity(major ? 0.9 : 0.6)), lineWidth: major ? 1.2 : 0.7)
            }
            for (f, label) in marks {
                ctx.draw(Text(label).font(Lettering.figures(8.5)).foregroundColor((f > 0.8 ? red : ink).opacity(0.85)),
                         at: point(f, radius + 9))
            }
            ctx.draw(Text("VU").font(Lettering.label(12)).foregroundColor(ink.opacity(0.75)),
                     at: CGPoint(x: size.width / 2, y: size.height - 8))
            var needle = Path()
            needle.move(to: point(level, 60))
            needle.addLine(to: point(level, radius + 4))
            ctx.stroke(needle, with: .color(Color.black.opacity(0.18)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            ctx.stroke(needle, with: .color(Color(white: 0.08)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}

// MARK: - Rotary knobs

/// A detented rotary selector. Labels and position dots sit on the same circle
/// the pointer sweeps, so it visibly points at the selection. Click the knob's
/// left or right half to step, drag sideways to turn, use arrow keys when
/// focused, or click a label directly. No wrap-around.
private struct RotaryKnob<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var knobSize: CGFloat
    var spread: Double
    var labelSize: CGFloat
    /// Room beside the knob for the outermost labels.
    var extraWidth: CGFloat = 46
    @State private var dragSteps = 0
    @FocusState private var focused: Bool

    private var index: Int { options.firstIndex { $0.0 == selection } ?? 0 }
    private var dotRadius: CGFloat { knobSize / 2 + 9 }
    private var labelRadius: CGFloat { knobSize / 2 + 16 }

    var body: some View {
        ZStack {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let a = angle(i) * .pi / 180
                let ux = CGFloat(sin(a)), uy = CGFloat(-cos(a))
                let selected = i == index
                // Lit amber dot for the selection, a cut dot for the rest.
                Circle()
                    .fill(selected ? Color(red: 1, green: 0.62, blue: 0.2) : Faceplate.ink.opacity(0.45))
                    .frame(width: selected ? 5 : 3.5, height: selected ? 5 : 3.5)
                    .shadow(color: selected ? Color.orange.opacity(0.8) : .clear, radius: 3)
                    .offset(x: ux * dotRadius, y: uy * dotRadius)
                // Inner edge on the pointer's ray: push out by half the label's extent.
                let halfWidth = CGFloat(option.1.count) * labelSize * 0.31 + 2
                Button { set(i) } label: {
                    Engraved(text: option.1, font: Lettering.label(labelSize), tracking: 1,
                             color: selected ? Faceplate.ink : Faceplate.inkSoft)
                        .fixedSize()
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingCursor()
                .accessibilityLabel("\(title), \(option.1)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .offset(x: ux * (labelRadius + halfWidth * abs(ux)), y: uy * (labelRadius + 6 * abs(uy)))
            }
            knob
        }
        .frame(width: knobSize + 2 * (labelRadius + extraWidth), height: knobSize / 2 + labelRadius + 16 + knobSize / 2 + 6, alignment: .center)
        .offset(y: labelRadius / 2)
    }

    private var knob: some View {
        Image(nsImage: Part.image("knob"))
            .resizable()
            .frame(width: knobSize, height: knobSize)
            .rotationEffect(.degrees(angle(index)))
            .shadow(color: .black.opacity(0.45), radius: knobSize * 0.05, x: 0, y: knobSize * 0.04)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let steps = Int((value.translation.width / 22).rounded(.towardZero))
                        if steps != dragSteps { step(steps - dragSteps); dragSteps = steps }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) < 4 && abs(value.translation.height) < 4 {
                            step(value.startLocation.x < knobSize / 2 ? -1 : 1)
                        }
                        dragSteps = 0
                    }
            )
            .pointingCursor()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(options[index].1)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
    }

    private func angle(_ i: Int) -> Double {
        guard options.count > 1 else { return 0 }
        return -spread / 2 + spread * Double(i) / Double(options.count - 1)
    }

    private func step(_ delta: Int) { set(min(max(index + delta, 0), options.count - 1)) }

    private func set(_ i: Int) {
        guard i != index else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { selection = options[i].0 }
    }
}

/// A detented slide switch: a recessed slot with a knurled chrome slider and
/// its positions engraved above. Click a position or the slot, or drag.
private struct SlideSwitch<Value: Hashable>: View {
    let title: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var width: CGFloat = 132
    private let thumb = CGSize(width: 28, height: 20)
    @State private var dragStart: Int?
    @FocusState private var focused: Bool

    private var index: Int { options.firstIndex { $0.0 == selection } ?? 0 }
    private var travel: CGFloat { width - thumb.width }

    private func x(_ i: Int) -> CGFloat {
        options.count > 1 ? -travel / 2 + travel * CGFloat(i) / CGFloat(options.count - 1) : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    let selected = i == index
                    Button { set(i) } label: {
                        VStack(spacing: 4) {
                            Engraved(text: option.1, font: Lettering.label(9.5), tracking: 1,
                                     color: selected ? Faceplate.ink : Faceplate.inkSoft)
                                .fixedSize()
                            Circle()
                                .fill(selected ? Color(red: 1, green: 0.62, blue: 0.2) : Faceplate.ink.opacity(0.45))
                                .frame(width: selected ? 5 : 3.5, height: selected ? 5 : 3.5)
                                .shadow(color: selected ? Color.orange.opacity(0.8) : .clear, radius: 3)
                        }
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingCursor()
                    .accessibilityLabel("\(title), \(option.1)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .offset(x: x(i))
                }
            }
            .frame(width: width + 24, height: 26)

            ZStack {
                // Recessed slot cut into the faceplate.
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: 10)
                    .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 0.5).offset(y: 0.75))
                // Knurled chrome slider.
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.62), Color(white: 0.88), Color(white: 0.48)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        HStack(spacing: 2.5) {
                            ForEach(0..<6, id: \.self) { _ in
                                Rectangle().fill(Color.black.opacity(0.28)).frame(width: 1)
                            }
                        }
                        .padding(.vertical, 4)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                    .frame(width: thumb.width, height: thumb.height)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1.5)
                    .offset(x: x(index))
            }
            .frame(width: width, height: thumb.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Snap to the detent nearest the pointer.
                        let local = value.location.x - width / 2
                        let i = Int(((local + travel / 2) / travel * CGFloat(options.count - 1)).rounded())
                        set(min(max(i, 0), options.count - 1))
                    }
            )
            .pointingCursor()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { set(max(index - 1, 0)); return .handled }
            .onKeyPress(.rightArrow) { set(min(index + 1, options.count - 1)); return .handled }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(options[index].1)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(min(index + 1, options.count - 1))
                case .decrement: set(max(index - 1, 0))
                @unknown default: break
                }
            }
        }
        .padding(.bottom, 14)
    }

    private func set(_ i: Int) {
        guard i != index else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { selection = options[i].0 }
    }
}

/// The big scene knob with a monitor showing the chosen scene.
private struct SceneSelector: View {
    @Binding var selection: SceneKind

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            RotaryKnob(title: "Scene", options: SceneKind.allCases.map { ($0, $0.title) }, selection: $selection,
                       knobSize: 92, spread: 150, labelSize: 10.5, extraWidth: 12)
            VStack(spacing: 8) {
                Image(nsImage: SceneThumbnails.image(for: selection))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 54)
                    .clipped()
                    .id(selection)
                    .transition(.opacity)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.5), lineWidth: 0.5).offset(y: 0.75))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1.5)
                    .accessibilityLabel("Scene preview, \(selection.title)")
                Engraved(text: "Scene", font: Lettering.label(10), tracking: 2.4, color: Faceplate.ink)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Switches and small knobs

/// A chrome bat-handle toggle: lever up is on.
private struct BatToggle: View {
    let title: String
    @Binding var isOn: Bool
    let help: String
    /// Engraved under the switch, e.g. why it is disabled.
    var note: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Engraved(text: title, font: Lettering.label(10), tracking: 1)
                .multilineTextAlignment(.center)
                .frame(height: 24, alignment: .bottom)
            Button { isOn.toggle() } label: {
                Image(nsImage: Part.image(isOn ? "toggle-up" : "toggle-down"))
                    .resizable()
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.35), radius: 2.5, x: 0, y: 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .pointingCursor()
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            Engraved(text: note ?? " ", font: Lettering.label(8.5), tracking: 1, color: Faceplate.ink)
                .opacity(note == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Scene previews: the scene's own photo when there is one, else the drawn version.
enum SceneThumbnails {
    private static var cache: [SceneKind: NSImage] = [:]

    static func image(for kind: SceneKind) -> NSImage {
        if let hit = cache[kind] { return hit }
        let image: NSImage
        let ownPhoto = CustomBackdrop.image(named: kind.photoName)
        let nightFallback = kind == .overheadNight && ownPhoto == nil
        if let photo = ownPhoto ?? (nightFallback ? CustomBackdrop.image(named: SceneKind.turntable.photoName) : nil) {
            let w = 360.0, h = w * Double(photo.height) / Double(photo.width)
            var small = Draw.image(CGSize(width: w, height: h), scale: 1) { ctx in
                Draw.upright(photo, in: CGRect(x: 0, y: 0, width: w, height: h), ctx)
            }
            if nightFallback { small = PhotoScene.nightGrade(small) }
            image = NSImage(cgImage: small, size: NSSize(width: w, height: h))
        } else {
            image = drawn(kind)
        }
        cache[kind] = image
        return image
    }

    private static func drawn(_ kind: SceneKind) -> NSImage {
        let scale: CGFloat = 0.13
        let cg = Draw.image(worldSize, scale: scale) { ctx in
            switch kind {
            case .turntable, .overheadNight:
                Draw.upright(Textures.topDownDesk(size: worldSize, scale: scale), in: CGRect(origin: .zero, size: worldSize), ctx)
                let deck = CGRect(x: 845, y: 255, width: DeckGeometry.size.width, height: DeckGeometry.size.height)
                Draw.upright(Textures.plinth(style: .birch, scale: scale), in: deck, ctx)
                let R = DeckGeometry.recordRadius
                let c = CGPoint(x: deck.minX + DeckGeometry.center.x, y: deck.minY + DeckGeometry.center.y)
                Draw.upright(Textures.record(scale: scale), in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), ctx)
            case .listeningRoom, .afterHours:
                Draw.upright(Textures.room(kind == .afterHours ? .night : .day, size: worldSize, scale: scale), in: CGRect(origin: .zero, size: worldSize), ctx)
            }
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

private extension View {
    /// The pointing-hand cursor over anything clickable on the faceplate.
    func pointingCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
