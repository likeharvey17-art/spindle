import AppKit
import ImageIO
import QuartzCore
import CoreImage

extension SceneKind {
    /// File name (without extension) of the scene's photo and calibration.
    var photoName: String {
        switch self {
        case .turntable: return "turntable"
        case .overheadNight: return "overhead-night"
        case .listeningRoom: return "listening-room"
        case .afterHours: return "after-hours"
        }
    }
}

/// Where the blank surfaces sit in a scene photo, in photo pixels (y-down).
/// Stored next to the photo as `<scene>.json`.
struct PhotoCalibration: Decodable {
    struct Ellipse: Decodable {
        let cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat
        let angle: CGFloat?

        func scaled(by k: CGFloat) -> Ellipse {
            Ellipse(cx: cx * k, cy: cy * k, rx: rx * k, ry: ry * k, angle: angle)
        }
    }
    /// Album sleeve corners: top-left, top-right, bottom-right, bottom-left.
    let sleeve: [[CGFloat]]?
    let label: Ellipse
    /// The record's playing surface, for the spinning groove reflections.
    let record: Ellipse?
    /// Outline of the tonearm where it crosses the record; kept clear of effects.
    let arm: [[CGFloat]]?
    let focus: [CGFloat]?
    /// Width of the image the coordinates were measured on, so a resized
    /// (e.g. upscaled) photo keeps working.
    let width: CGFloat?
    /// Widgets only: the photo file, the part of it shown (x, y, width,
    /// height) and, for the player, the corner radius of its outline.
    var image: String? = nil
    var crop: [CGFloat]? = nil
    var corner: CGFloat? = nil

    /// Scales every coordinate by `k`, then moves it by `-shift`.
    func scaled(by k: CGFloat, shift: CGPoint = .zero) -> PhotoCalibration {
        guard k != 1 || shift != .zero else { return self }
        let points = { (q: [[CGFloat]]) in q.map { [$0[0] * k - shift.x, $0[1] * k - shift.y] } }
        var label = label.scaled(by: k), record = record?.scaled(by: k)
        label = PhotoCalibration.Ellipse(cx: label.cx - shift.x, cy: label.cy - shift.y, rx: label.rx, ry: label.ry, angle: label.angle)
        record = record.map { PhotoCalibration.Ellipse(cx: $0.cx - shift.x, cy: $0.cy - shift.y, rx: $0.rx, ry: $0.ry, angle: $0.angle) }
        return PhotoCalibration(
            sleeve: sleeve.map(points),
            label: label,
            record: record,
            arm: arm.map(points),
            focus: focus.map { [$0[0] * k - shift.x, $0[1] * k - shift.y] },
            width: width.map { $0 * k },
            image: image,
            crop: crop.map { [$0[0] * k - shift.x, $0[1] * k - shift.y, $0[2] * k, $0[3] * k] },
            corner: corner.map { $0 * k })
    }
}

/// A photoreal scene: the photo stays put and only the album art is laid onto
/// its blank sleeve and label, re-lit with the photo's own light, while the
/// label and the record's groove reflections turn.
final class PhotoScene: VinylScene {
    let root = CALayer()
    let size: CGSize
    let focus: CGPoint
    var deck: DeckLayer? { nil }

    private let photo: CGImage
    private let sleeveArt = CALayer()
    private let labelArt = CALayer()
    private let grooves = CALayer()
    private let sleeveWear = CALayer()
    private let labelSquash: CGFloat
    private let tilt: CGFloat
    /// Pixel sizes the art is resampled to, so it is exactly as sharp as the photo around it.
    private var sleeveSide: CGFloat = 512
    private var labelSide: CGFloat = 256
    private let softGrooves: Bool

    static func load(_ kind: SceneKind) -> PhotoScene? {
        if let scene = load(name: kind.photoName, grade: nil) { return scene }
        // Midnight falls back to the Overhead photo, graded to night.
        if kind == .overheadNight { return load(name: SceneKind.turntable.photoName, grade: nightGrade) }
        return nil
    }

    private static func load(name: String, grade: ((CGImage) -> CGImage)?) -> PhotoScene? {
        guard let raw = CustomBackdrop.image(named: name),
              let (data, file) = CustomBackdrop.calibration(named: name) else { return nil }
        let photo = grade.map { $0(enhance(raw)) } ?? enhance(raw)
        do {
            let cal = try JSONDecoder().decode(PhotoCalibration.self, from: data)
            let k = cal.width.map { CGFloat(photo.width) / $0 } ?? 1
            return PhotoScene(photo: photo, calibration: cal.scaled(by: k))
        } catch {
            NSLog("Spindle: bad calibration \(file): \(error)")
            return nil
        }
    }

    /// `softGrooves` blurs the spinning glints, for small widgets where fine
    /// detail would read as specks.
    private init(photo: CGImage, calibration cal: PhotoCalibration, softGrooves: Bool = false) {
        self.softGrooves = softGrooves
        self.photo = photo
        size = CGSize(width: photo.width, height: photo.height)
        focus = cal.focus.map { CGPoint(x: $0[0], y: $0[1]) } ?? CGPoint(x: size.width / 2, y: size.height / 2)
        labelSquash = cal.label.ry / cal.label.rx
        tilt = (cal.label.angle ?? 0) * .pi / 180
        root.frame = CGRect(origin: .zero, size: size)

        let background = CALayer()
        background.frame = root.bounds
        background.contents = photo
        root.addSublayer(background)

        labelSide = cal.label.rx * 2
        if let sleeve = cal.sleeve {
            let sleeveQuad = sleeve.map { CGPoint(x: $0[0], y: $0[1]) }
            sleeveSide = zip(sleeveQuad, sleeveQuad.dropFirst() + [sleeveQuad[0]]).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 512
            addQuad(sleeveQuad, art: sleeveArt)
        }
        if let record = cal.record {
            addGrooves(record: record, label: cal.label, arm: cal.arm?.map { CGPoint(x: $0[0], y: $0[1]) } ?? [])
        }
        addLabel(cal.label)
        setArtwork(nil, animated: false)
    }

    /// A desktop widget: the turntable from a widget photo at the size it is
    /// shown, cut out along its own rounded outline.
    static func loadWidget(style: CardStyle, size: CardSize, scale: CGFloat) -> PhotoScene? {
        guard let spec = WidgetPhoto.calibration(style: style),
              let name = spec.image, let raw = WidgetPhoto.image(named: name) else { return nil }
        let k = spec.width.map { CGFloat(raw.width) / $0 } ?? 1
        let full = spec.scaled(by: k)
        let c = full.crop ?? [0, 0, CGFloat(raw.width), CGFloat(raw.height)]
        let crop = CGRect(x: c[0], y: c[1], width: c[2], height: c[3]).integral
        let points = CardLayout.size(style: style, size: size)
        let s = min(1, points.width * scale / crop.width)
        let out = CGSize(width: (crop.width * s).rounded(), height: (crop.height * s).rounded())
        guard let part = raw.cropping(to: crop) else { return nil }
        let photo = Draw.image(out, scale: 1) { ctx in Draw.upright(part, in: CGRect(origin: .zero, size: out), ctx) }
        let scene = PhotoScene(photo: photo, calibration: full.scaled(by: s, shift: CGPoint(x: crop.minX * s, y: crop.minY * s)), softGrooves: true)
        let radius = (full.corner ?? 0) * s
        let outline = CGPath(roundedRect: scene.root.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let mask = CAShapeLayer()
        mask.path = outline
        scene.root.mask = mask
        scene.outline = outline
        return scene
    }

    /// The widget's shape, for its shadow.
    private(set) var outline: CGPath?

    // MARK: VinylScene

    /// With no art the blank sleeve and label in the photo simply show through.
    func setArtwork(_ art: CGImage?, animated: Bool) {
        swap(sleeveArt, to: art.map { resample($0, side: sleeveSide) }, animated: animated)
        swap(labelArt, to: art.map { resample($0, side: labelSide) }, animated: animated)
    }

    /// The old record slides out of the jacket's frame as the new one slides in,
    /// and the label changes over.
    func changeRecord(to art: CGImage?) {
        guard let art, let current = sleeveArt.contents else { setArtwork(art, animated: true); return }
        let side = sleeveArt.bounds.width
        let incoming = resample(art, side: sleeveSide)
        func card(_ contents: Any, at x: CGFloat) -> CALayer {
            let layer = CALayer()
            layer.frame = sleeveArt.bounds.offsetBy(dx: x, dy: 0)
            layer.contents = contents
            layer.contentsGravity = .resizeAspectFill
            sleeveArt.insertSublayer(layer, below: sleeveWear)
            return layer
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sleeveArt.contents = nil
        let leaving = card(current, at: 0)
        let arriving = card(incoming, at: -side)
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self?.sleeveArt.contents = incoming
            leaving.removeFromSuperlayer()
            arriving.removeFromSuperlayer()
            CATransaction.commit()
        }
        slide(leaving, by: side, duration: 0.5, delay: 0, timing: .easeIn)
        slide(arriving, by: side, duration: 0.6, delay: 0.25, timing: .easeOut)
        CATransaction.commit()
        swap(labelArt, to: resample(art, side: labelSide), animated: true)
    }

    private func slide(_ layer: CALayer, by dx: CGFloat, duration: CFTimeInterval, delay: CFTimeInterval, timing: CAMediaTimingFunctionName) {
        let from = layer.position.x
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = from
        move.toValue = from + dx
        move.duration = duration
        move.beginTime = CACurrentMediaTime() + delay
        move.fillMode = .backwards
        move.timingFunction = CAMediaTimingFunction(name: timing)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position.x = from + dx
        CATransaction.commit()
        layer.add(move, forKey: "slide")
    }

    func setDiscRotation(_ radians: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        labelArt.transform = CATransform3DMakeRotation(-radians, 0, 0, 1)
        grooves.transform = CATransform3DMakeRotation(-radians, 0, 0, 1)
        CATransaction.commit()
    }

    // MARK: Building

    private func swap(_ layer: CALayer, to image: CGImage?, animated: Bool) {
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.5
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "contents")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = image
        if layer === sleeveArt { sleeveWear.isHidden = image == nil }
        CATransaction.commit()
    }

    /// Square-crops and scales album art to the size it occupies in the photo.
    private func resample(_ image: CGImage, side: CGFloat) -> CGImage {
        let px = max(32, (side * 1.15).rounded())
        return Draw.image(CGSize(width: px, height: px), scale: 1) { ctx in
            Draw.aspectFill(image, in: CGRect(x: 0, y: 0, width: px, height: px), ctx)
        }
    }

    /// Turns a daylight photo into a lamp-lit night: darker, warmer, with a
    /// pool of light from the top right and darkened edges.
    static func nightGrade(_ photo: CGImage) -> CGImage {
        let w = CGFloat(photo.width), h = CGFloat(photo.height)
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        var image = CIImage(cgImage: photo)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.86, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.62, w: 0),
            ])
        let pool = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: w * 0.86, y: h * 0.88),
            "inputRadius0": w * 0.04,
            "inputRadius1": w * 0.78,
            "inputColor0": CIColor(red: 1, green: 0.93, blue: 0.8),
            "inputColor1": CIColor(red: 0.32, green: 0.3, blue: 0.3),
        ])?.outputImage?.cropped(to: extent)
        if let pool {
            image = image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: pool])
        }
        image = image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.9, kCIInputRadiusKey: 1.6])
        return Draw.ciContext.createCGImage(image.cropped(to: extent), from: extent) ?? photo
    }

    /// Low-resolution photos are upscaled 2× with Lanczos and gently sharpened
    /// so they hold up full-screen on a Retina display.
    private static func enhance(_ photo: CGImage) -> CGImage {
        guard photo.width < 2400 else { return photo }
        let input = CIImage(cgImage: photo)
        let scaled = input.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 2.0, kCIInputAspectRatioKey: 1.0])
        let sharp = scaled.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 2.2, kCIInputIntensityKey: 0.55])
        let extent = CGRect(x: 0, y: 0, width: photo.width * 2, height: photo.height * 2)
        return Draw.ciContext.createCGImage(sharp.cropped(to: extent), from: extent) ?? photo
    }

    /// Lays `art` over a quadrilateral in the photo and multiplies the photo's
    /// lighting back over it.
    private func addQuad(_ quad: [CGPoint], art: CALayer) {
        let box = boundingBox(quad).insetBy(dx: -2, dy: -2).integral
        let mask = maskImage(box: box) { ctx in
            ctx.setFillColor(.white)
            ctx.addPath(path(quad, in: box)); ctx.fillPath()
        }
        let group = makeGroup(box: box, mask: mask, relight: true)

        let side: CGFloat = 1000
        art.anchorPoint = .zero
        art.position = .zero
        art.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        art.contentsGravity = .resizeAspectFill
        art.masksToBounds = true
        // Quad corners in the group's y-up space: BL, BR, TR, TL ↔ art (0,0), (s,0), (s,s), (0,s).
        let local = quad.map { CGPoint(x: $0.x - box.minX, y: box.maxY - $0.y) }
        art.transform = homography(from: side, to: [local[3], local[2], local[1], local[0]])
        // Age the jacket: the wear rides on the art, under the photo's lighting.
        sleeveWear.frame = art.bounds
        sleeveWear.contents = Textures.sleeveWear()
        art.addSublayer(sleeveWear)
        group.insertSublayer(art, at: 0)
    }

    private func addLabel(_ e: PhotoCalibration.Ellipse) {
        let box = ellipseBox(e)
        let mask = maskImage(box: box) { ctx in
            ctx.setFillColor(.white)
            ctx.addPath(ellipsePath(e, in: box)); ctx.fillPath()
        }
        let group = makeGroup(box: box, mask: mask, relight: true)
        let flat = flattenedDisc(radius: e.rx, center: CGPoint(x: e.cx - box.minX, y: box.maxY - e.cy))
        labelArt.frame = flat.bounds
        labelArt.contentsGravity = .resizeAspectFill
        labelArt.minificationFilter = .trilinear
        labelArt.cornerRadius = e.rx
        labelArt.masksToBounds = true
        flat.addSublayer(labelArt)
        group.insertSublayer(flat, at: 0)
    }

    /// Faint arcs and dust that turn with the record, screened over the photo so
    /// the vinyl itself visibly spins while the photo's own reflections stay put.
    private func addGrooves(record r: PhotoCalibration.Ellipse, label: PhotoCalibration.Ellipse, arm: [CGPoint]) {
        let box = ellipseBox(r)
        let mask = maskImage(box: box) { ctx in
            ctx.setFillColor(.white)
            ctx.addPath(ellipsePath(r, in: box)); ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addPath(ellipsePath(label, in: box, grow: 1.08)); ctx.fillPath()
            if arm.count > 2 { ctx.addPath(path(arm, in: box)); ctx.fillPath() }
        }
        // The photo's own glare on the vinyl can't turn with the record, so it
        // is pressed down to the vinyl's base tone; only the spinning glints move.
        let calm = CALayer()
        calm.frame = CGRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height)
        calm.contents = deglaredImage(box: box, mask: mask)
        let calmMask = CALayer()
        calmMask.frame = calm.bounds
        calmMask.contents = mask
        calm.mask = calmMask
        root.addSublayer(calm)

        let group = makeGroup(box: box, mask: mask, relight: false)
        group.compositingFilter = "screenBlendMode"

        let detail = min(3, max(1, 700 / r.rx))
        let flat = flattenedDisc(radius: r.rx, center: CGPoint(x: r.cx - box.minX, y: box.maxY - r.cy))
        grooves.frame = flat.bounds
        // Seen at a steep angle the disc is squashed, so fine detail would shimmer.
        let steep = softGrooves || r.ry / r.rx < 0.6
        grooves.contents = Textures.grooveGlints(labelRatio: label.rx / r.rx, scale: detail * r.rx / 340, soft: steep)
        // Mipmapped minification keeps the squashed texture smooth as it turns.
        grooves.minificationFilter = .trilinear
        flat.addSublayer(grooves)
        group.addSublayer(flat)
    }

    /// A disc-sized layer flattened into the photo's ellipse. Its child spins
    /// with a plain rotation, which Core Animation can run on its own.
    private func flattenedDisc(radius: CGFloat, center: CGPoint) -> CALayer {
        let flat = CALayer()
        flat.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        flat.position = center
        flat.transform = CATransform3DConcat(CATransform3DMakeScale(1, labelSquash, 1), CATransform3DMakeRotation(-tilt, 0, 0, 1))
        return flat
    }

    var spinningLayers: [CALayer] { [labelArt, grooves] }

    /// A clipped group at `box`. With `relight`, a multiply layer carries the
    /// photo's light and shadow from that (blank white) surface onto the art.
    private func makeGroup(box: CGRect, mask: CGImage, relight: Bool) -> CALayer {
        let group = CALayer()
        group.frame = CGRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height)
        let maskLayer = CALayer()
        maskLayer.frame = group.bounds
        maskLayer.contents = mask
        group.mask = maskLayer

        if relight {
            let light = CALayer()
            light.frame = group.bounds
            light.contents = lightImage(box: box, mask: mask)
            light.compositingFilter = "multiplyBlendMode"
            group.addSublayer(light)
        }

        root.addSublayer(group)
        return group
    }

    // MARK: Geometry helpers

    private func boundingBox(_ pts: [CGPoint]) -> CGRect {
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    private func ellipseBox(_ e: PhotoCalibration.Ellipse) -> CGRect {
        CGRect(x: e.cx - e.rx, y: e.cy - e.rx, width: e.rx * 2, height: e.rx * 2).insetBy(dx: -2, dy: -2).integral
    }

    private func path(_ pts: [CGPoint], in box: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.x - box.minX, y: $0.y - box.minY) })
        p.closeSubpath()
        return p
    }

    private func ellipsePath(_ e: PhotoCalibration.Ellipse, in box: CGRect, grow: CGFloat = 1) -> CGPath {
        var t = CGAffineTransform(translationX: e.cx - box.minX, y: e.cy - box.minY).rotated(by: tilt)
        return CGPath(ellipseIn: CGRect(x: -e.rx * grow, y: -e.ry * grow, width: e.rx * 2 * grow, height: e.ry * 2 * grow), transform: &t)
    }

    /// Alpha mask for `box`, drawn in y-down photo coordinates.
    private func maskImage(box: CGRect, draw: (CGContext) -> Void) -> CGImage {
        Draw.image(box.size, scale: 1, draw)
    }

    /// The photo inside `box`, brightened so its whitest part becomes pure
    /// white: multiplying art by this keeps the photo's shading and tint.
    private func lightImage(box: CGRect, mask: CGImage) -> CGImage? {
        let w = Int(box.width), h = Int(box.height)
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var mk = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let pc = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Draw.colorSpace, bitmapInfo: info),
              let mc = CGContext(data: &mk, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Draw.colorSpace, bitmapInfo: info)
        else { return nil }
        // Both bitmaps hold the box with row 0 at the top.
        pc.draw(photo, in: CGRect(x: -box.minX, y: box.maxY - size.height, width: size.width, height: size.height))
        mc.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lum: [Int] = []
        lum.reserveCapacity(w * h / 4)
        for i in stride(from: 0, to: w * h * 4, by: 16) where mk[i + 3] > 200 {
            lum.append((Int(px[i]) * 2 + Int(px[i + 1]) * 5 + Int(px[i + 2])) / 8)
        }
        guard !lum.isEmpty else { return nil }
        lum.sort()
        let ref = max(Double(lum[min(lum.count - 1, Int(Double(lum.count) * 0.97))]), 40)
        // A white card reflects ~90%, so allow only that much boost: dark
        // scenes stay dark instead of being lifted to full white.
        let gain = min(255.0 / ref, 1.12)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            for c in 0..<3 { px[i + c] = UInt8(min(255, Double(px[i + c]) * gain)) }
            px[i + 3] = 255
        }
        return pc.makeImage()
    }

    /// The photo inside `box` with its highlights compressed toward the vinyl's
    /// median tone, keeping a quarter of their strength so grooves still read.
    private func deglaredImage(box: CGRect, mask: CGImage) -> CGImage? {
        let w = Int(box.width), h = Int(box.height)
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var mk = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let pc = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Draw.colorSpace, bitmapInfo: info),
              let mc = CGContext(data: &mk, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: Draw.colorSpace, bitmapInfo: info)
        else { return nil }
        pc.draw(photo, in: CGRect(x: -box.minX, y: box.maxY - size.height, width: size.width, height: size.height))
        mc.draw(mask, in: CGRect(x: 0, y: 0, width: w, height: h))

        func lum(_ i: Int) -> Double { (Double(px[i]) * 2 + Double(px[i + 1]) * 5 + Double(px[i + 2])) / 8 }
        var samples: [Double] = []
        samples.reserveCapacity(w * h / 4)
        for i in stride(from: 0, to: w * h * 4, by: 16) where mk[i + 3] > 200 { samples.append(lum(i)) }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        let base = max(samples[samples.count / 2], 1)
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let l = lum(i)
            guard l > base else { continue }
            let target = base + (l - base) * 0.25
            let k = target / l
            for c in 0..<3 { px[i + c] = UInt8(Double(px[i + c]) * k) }
        }
        return pc.makeImage()
    }

    /// Projective transform mapping a `side`×`side` layer (anchor at origin) onto
    /// four points given in layer order (0,0), (s,0), (s,s), (0,s).
    private func homography(from side: CGFloat, to q: [CGPoint]) -> CATransform3D {
        let (x0, y0, x1, y1, x2, y2, x3, y3) = (q[0].x, q[0].y, q[1].x, q[1].y, q[2].x, q[2].y, q[3].x, q[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        let den = dx1 * dy2 - dx2 * dy1
        let g = den == 0 ? 0 : (dx3 * dy2 - dx2 * dy3) / den
        let h = den == 0 ? 0 : (dx1 * dy3 - dx3 * dy1) / den
        let a = x1 - x0 + g * x1, b = x3 - x0 + h * x3, c = x0
        let d = y1 - y0 + g * y1, e = y3 - y0 + h * y3, f = y0
        var t = CATransform3DIdentity
        t.m11 = a / side; t.m21 = b / side; t.m41 = c
        t.m12 = d / side; t.m22 = e / side; t.m42 = f
        t.m14 = g / side; t.m24 = h / side; t.m44 = 1
        return t
    }
}
