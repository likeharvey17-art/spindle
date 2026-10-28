import AppKit

/// Turntable deck geometry in deck-local design units (y-down, origin top-left).
enum DeckGeometry {
    static let size = CGSize(width: 930, height: 830)
    static let center = CGPoint(x: 390, y: 410)
    static let recordRadius: CGFloat = 340
    static let labelRadius: CGFloat = 108
    static let platterRadius: CGFloat = 352
    static let pivot = CGPoint(x: 800, y: 170)
    static let armLength: CGFloat = 360
    static let knob = CGPoint(x: 800, y: 682)
    static let restAngle: CGFloat = 91
    static let restPost = CGPoint(x: 795, y: 440)

    /// Arm angle (degrees, clockwise from +x in y-down space) that puts the
    /// stylus `r` units from the spindle.
    static func armAngle(forRadius r: CGFloat) -> CGFloat {
        let dx = center.x - pivot.x, dy = center.y - pivot.y
        let d = hypot(dx, dy)
        let phi = atan2(dy, dx)
        let cosDelta = (armLength * armLength + d * d - r * r) / (2 * armLength * d)
        let delta = acos(min(max(cosDelta, -1), 1))
        return (phi - delta) * 180 / .pi
    }

    static let startAngle = armAngle(forRadius: recordRadius * 0.955)
    static let endAngle = armAngle(forRadius: labelRadius + 42)

    // Tonearm bitmap: pivot sits at `armOrigin` inside an `armSize` image.
    static let armOrigin = CGPoint(x: 124, y: 72)
    static var armSize: CGSize { CGSize(width: armLength + 170, height: 144) }
}

enum DeckStyle {
    case birch   // top-down scene: light maple/birch plinth
    case cream   // front scenes: cream lacquer top plate
}

enum Textures {
    // MARK: Desks & rooms

    /// Warm orange veneer desk seen from above.
    static func topDownDesk(size: CGSize, scale: CGFloat) -> CGImage {
        Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(11)
            Draw.linear(ctx, [Draw.color(0xC4701F), Draw.color(0xB25B19), Draw.color(0xC86F22), Draw.color(0xA9531A)],
                        [0, 0.35, 0.7, 1], from: .zero, to: CGPoint(x: size.width, y: size.height))
            ctx.setLineCap(.round)
            // Broad colour bands.
            for _ in 0..<80 {
                let dark = rng.r(0...1) < 0.55
                ctx.setStrokeColor(dark ? Draw.color(0x6A2E08, rng.r(0.05...0.12)) : Draw.color(0xF0A048, rng.r(0.04...0.10)))
                ctx.setLineWidth(rng.r(14...70))
                ctx.addPath(Draw.wave(y: rng.r(-200...size.height + 100), from: -60, to: size.width + 60, slope: 0.06,
                                      amp: rng.r(4...22), freq: rng.r(0.002...0.006), phase: rng.r(0...6), amp2: rng.r(2...10), freq2: rng.r(0.008...0.02)))
                ctx.strokePath()
            }
            // Fine grain.
            for _ in 0..<1100 {
                let dark = rng.r(0...1) < 0.75
                ctx.setStrokeColor(dark ? Draw.color(0x4E1F03, rng.r(0.04...0.16)) : Draw.color(0xFFC07A, rng.r(0.03...0.09)))
                ctx.setLineWidth(rng.r(0.6...2.6))
                let x0 = rng.r(-200...size.width)
                ctx.addPath(Draw.wave(y: rng.r(-200...size.height + 100), from: x0, to: x0 + rng.r(300...1600), slope: 0.06,
                                      amp: rng.r(2...14), freq: rng.r(0.002...0.008), phase: rng.r(0...6), amp2: rng.r(1...4), freq2: rng.r(0.01...0.03)))
                ctx.strokePath()
            }
            // Pores.
            for _ in 0..<5000 {
                let x = rng.r(0...size.width), y = rng.r(0...size.height)
                ctx.setFillColor(Draw.color(0x3E1702, rng.r(0.05...0.18)))
                ctx.fill(CGRect(x: x, y: y + x * 0.06, width: rng.r(2...7), height: 0.9))
            }
            // Soft light pooling in the middle, darker edges.
            Draw.radial(ctx, [Draw.color(0xFFC27A, 0.20), Draw.color(0xFFC27A, 0)], center: CGPoint(x: size.width * 0.55, y: size.height * 0.45), radius: size.width * 0.6)
            Draw.radial(ctx, [Draw.black(0), Draw.black(0), Draw.black(0.38)], [0, 0.55, 1], center: CGPoint(x: size.width / 2, y: size.height / 2), radius: size.width * 0.72, extend: true)
        }
    }

    /// Venetian-blind shadows falling across the top-down desk.
    static func blindShadows(size: CGSize, scale: CGFloat) -> CGImage {
        let raw = Draw.image(size, scale: scale) { ctx in
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: -22 * .pi / 180)
            ctx.translateBy(x: -size.width, y: -size.height)
            ctx.setFillColor(Draw.black(0.40))
            var x: CGFloat = 80
            var i = 0
            while x < size.width * 2.2 {
                let w: CGFloat = i % 3 == 1 ? 150 : 115
                ctx.fill(CGRect(x: x, y: -200, width: w, height: size.height * 2.6))
                x += 440 + CGFloat(i % 2) * 30
                i += 1
            }
            ctx.restoreGState()
            // A darker window-frame shadow in the lower left corner.
            ctx.setFillColor(Draw.black(0.30))
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: size.height * 0.55))
            p.addLine(to: CGPoint(x: size.width * 0.12, y: size.height))
            p.addLine(to: CGPoint(x: 0, y: size.height))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.fillPath()
        }
        return Draw.blur(raw, radius: 16 * scale)
    }

    enum Room { case day, night }

    /// Wall, picture, desk and lamp for the front-facing scenes.
    static func room(_ room: Room, size: CGSize, scale: CGFloat) -> CGImage {
        let deskTop: CGFloat = 700
        let night = room == .night
        return Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(night ? 23 : 17)

            // Wall.
            Draw.linear(ctx, night ? [Draw.color(0x7A5236), Draw.color(0x5E3B24)] : [Draw.color(0xEDE2CF), Draw.color(0xD8C5A8)],
                        from: .zero, to: CGPoint(x: 0, y: deskTop))
            for _ in 0..<9000 {
                ctx.setFillColor(rng.r(0...1) < 0.5 ? Draw.black(rng.r(0.01...0.035)) : Draw.white(rng.r(0.01...0.04)))
                ctx.fill(CGRect(x: rng.r(0...size.width), y: rng.r(0...deskTop), width: rng.r(1...3), height: rng.r(1...3)))
            }
            if night {
                Draw.radial(ctx, [Draw.color(0xFFB868, 0.85), Draw.color(0xE08A4A, 0.45), Draw.color(0xE08A4A, 0)], [0, 0.35, 1],
                            center: CGPoint(x: 1810, y: 470), radius: 1350)
                Draw.radial(ctx, [Draw.color(0xFF9C55, 0.45), Draw.color(0xFF9C55, 0)], center: CGPoint(x: 80, y: 640), radius: 760)
            } else {
                Draw.radial(ctx, [Draw.color(0xFFF6E2, 0.55), Draw.color(0xFFF6E2, 0)], center: CGPoint(x: 260, y: 120), radius: 1200)
            }

            // Picture frame, cut off by the top of the screen.
            let frame = CGRect(x: 1000, y: -40, width: 540, height: 340)
            if night {
                // Warm backlight halo.
                let halo = Draw.image(size, scale: 0.25) { h in
                    h.setFillColor(Draw.color(0xFF9445, 0.9))
                    h.fill(frame.insetBy(dx: -10, dy: -10))
                }
                Draw.upright(Draw.blur(halo, radius: 14), in: CGRect(origin: .zero, size: size), ctx)
            } else {
                ctx.setShadow(offset: CGSize(width: 14, height: 18), blur: 30, color: Draw.black(0.35))
            }
            ctx.setFillColor(Draw.color(0x3A2416))
            ctx.fill(frame)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addRect(frame); ctx.clip()
            Draw.linear(ctx, [Draw.color(0x4C2F1C), Draw.color(0x2A170B)], from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.maxX, y: frame.maxY))
            ctx.restoreGState()
            let mat = frame.insetBy(dx: 22, dy: 22)
            ctx.setFillColor(night ? Draw.color(0xD9C3A2) : Draw.color(0xF0E7D8))
            ctx.fill(mat)
            let art = mat.insetBy(dx: 46, dy: 46)
            Draw.upright(painting(size: art.size, scale: scale), in: art, ctx)
            ctx.setStrokeColor(Draw.black(0.25))
            ctx.setLineWidth(2)
            ctx.stroke(art)

            // Desk top.
            let desk = CGRect(x: 0, y: deskTop, width: size.width, height: size.height - deskTop)
            ctx.saveGState()
            ctx.addRect(desk); ctx.clip()
            Draw.linear(ctx, night ? [Draw.color(0x6A3315), Draw.color(0x3E1B08)] : [Draw.color(0x985427), Draw.color(0x6E3716)],
                        from: CGPoint(x: 0, y: deskTop), to: CGPoint(x: 0, y: size.height))
            ctx.setLineCap(.round)
            for _ in 0..<520 {
                let t = pow(rng.r(0...1), 1.35)
                let y = deskTop + t * (size.height - deskTop + 40)
                let dark = rng.r(0...1) < 0.7
                ctx.setStrokeColor(dark ? Draw.color(0x2E1203, rng.r(0.06...0.20)) : Draw.color(0xE7A066, rng.r(0.03...0.10)))
                ctx.setLineWidth(rng.r(0.6...2.2) * (0.5 + t))
                let x0 = rng.r(-300...size.width)
                ctx.addPath(Draw.wave(y: y, from: x0, to: x0 + rng.r(400...1800), slope: 0.004,
                                      amp: rng.r(0.5...4) * (0.4 + t), freq: rng.r(0.002...0.006), phase: rng.r(0...6)))
                ctx.strokePath()
            }
            if night {
                Draw.radial(ctx, [Draw.color(0xFFB36B, 0.55), Draw.color(0xFFB36B, 0)], center: CGPoint(x: 1780, y: 780), radius: 700)
                Draw.radial(ctx, [Draw.color(0xFF9C55, 0.25), Draw.color(0xFF9C55, 0)], center: CGPoint(x: 200, y: 760), radius: 600)
            } else {
                Draw.radial(ctx, [Draw.color(0xFFE2B8, 0.30), Draw.color(0xFFE2B8, 0)], center: CGPoint(x: 600, y: 760), radius: 900)
            }
            ctx.restoreGState()

            // Desk/wall seam.
            Draw.linear(ctx, [Draw.black(0), Draw.black(night ? 0.35 : 0.22)], from: CGPoint(x: 0, y: deskTop - 40), to: CGPoint(x: 0, y: deskTop))
            ctx.setFillColor(night ? Draw.color(0xD08A50, 0.55) : Draw.color(0xD9A06C, 0.7))
            ctx.fill(CGRect(x: 0, y: deskTop, width: size.width, height: 2.5))

            // Contact shadows for the props that sit on the desk.
            let shadows = Draw.image(size, scale: 0.25) { s in
                s.setFillColor(Draw.black(night ? 0.75 : 0.6))
                s.fillEllipse(in: CGRect(x: 150, y: 948, width: 520, height: 34))      // album stand
                s.fillEllipse(in: CGRect(x: 690, y: 952, width: 680, height: 46))      // turntable
                s.fillEllipse(in: CGRect(x: 1715, y: 744, width: 190, height: 30))     // lamp base
                s.setFillColor(Draw.black(night ? 0.45 : 0.35))
                s.fill(CGRect(x: night ? 120 : 620, y: 930, width: 560, height: 40))   // cast shadow
            }
            Draw.upright(Draw.blur(shadows, radius: 5), in: CGRect(origin: .zero, size: size), ctx)

            // Lamp.
            drawLamp(ctx, lit: night)

            // Window light streaks on the day wall.
            if !night {
                let light = Draw.image(size, scale: 0.5) { l in
                    l.saveGState()
                    let clip = CGMutablePath()
                    clip.move(to: CGPoint(x: -100, y: 40)); clip.addLine(to: CGPoint(x: 820, y: -60))
                    clip.addLine(to: CGPoint(x: 1060, y: 640)); clip.addLine(to: CGPoint(x: -100, y: 690))
                    clip.closeSubpath()
                    l.addPath(clip); l.clip()
                    l.translateBy(x: 400, y: 300); l.rotate(by: -0.30); l.translateBy(x: -400, y: -300)
                    l.setFillColor(Draw.color(0xFFF4DC, 0.55))
                    var y: CGFloat = -300
                    while y < 1000 { l.fill(CGRect(x: -400, y: y, width: 1900, height: 30)); y += 50 }
                    l.restoreGState()
                }
                Draw.upright(Draw.blur(light, radius: 3), in: CGRect(origin: .zero, size: size), ctx)
            }

            // Vignette.
            Draw.radial(ctx, [Draw.black(0), Draw.black(0), Draw.black(night ? 0.55 : 0.25)], [0, 0.5, 1],
                        center: CGPoint(x: size.width * (night ? 0.62 : 0.45), y: size.height * 0.5), radius: size.width * 0.75, extend: true)
        }
    }

    private static func drawLamp(_ ctx: CGContext, lit: Bool) {
        let cx: CGFloat = 1810, top: CGFloat = 335, bottom: CGFloat = 650, half: CGFloat = 122
        // Base and stem.
        let base = CGMutablePath()
        base.move(to: CGPoint(x: cx - 18, y: 690))
        base.addCurve(to: CGPoint(x: cx - 82, y: 748), control1: CGPoint(x: cx - 22, y: 720), control2: CGPoint(x: cx - 80, y: 725))
        base.addLine(to: CGPoint(x: cx + 82, y: 748))
        base.addCurve(to: CGPoint(x: cx + 18, y: 690), control1: CGPoint(x: cx + 80, y: 725), control2: CGPoint(x: cx + 22, y: 720))
        base.closeSubpath()
        ctx.saveGState()
        ctx.addPath(base); ctx.addRect(CGRect(x: cx - 12, y: bottom - 8, width: 24, height: 60)); ctx.clip()
        Draw.linear(ctx, lit ? [Draw.color(0x4A3210), Draw.color(0xE8C07A), Draw.color(0x8A6326), Draw.color(0x3A2508)]
                             : [Draw.color(0x4A3A20), Draw.color(0xB89A62), Draw.color(0x7A6236), Draw.color(0x3A2C14)],
                    [0, 0.42, 0.6, 1], from: CGPoint(x: cx - 82, y: 0), to: CGPoint(x: cx + 82, y: 0))
        ctx.restoreGState()
        ctx.setFillColor(Draw.black(0.25))
        ctx.fillEllipse(in: CGRect(x: cx - 82, y: 742, width: 164, height: 12))

        // Cord.
        ctx.setStrokeColor(Draw.color(0x1A120C))
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: cx + 70, y: 745))
        ctx.addCurve(to: CGPoint(x: 2010, y: 712), control1: CGPoint(x: cx + 140, y: 750), control2: CGPoint(x: 1960, y: 712))
        ctx.strokePath()

        // Ribbed glass dome.
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: cx - half * 0.86, y: bottom))
        dome.addCurve(to: CGPoint(x: cx - half, y: top + 120), control1: CGPoint(x: cx - half * 1.02, y: bottom - 80), control2: CGPoint(x: cx - half * 1.06, y: top + 190))
        dome.addCurve(to: CGPoint(x: cx + half, y: top + 120), control1: CGPoint(x: cx - half * 0.9, y: top - 40), control2: CGPoint(x: cx + half * 0.9, y: top - 40))
        dome.addCurve(to: CGPoint(x: cx + half * 0.86, y: bottom), control1: CGPoint(x: cx + half * 1.06, y: top + 190), control2: CGPoint(x: cx + half * 1.02, y: bottom - 80))
        dome.addQuadCurve(to: CGPoint(x: cx - half * 0.86, y: bottom), control: CGPoint(x: cx, y: bottom + 22))
        dome.closeSubpath()
        ctx.saveGState()
        ctx.addPath(dome); ctx.clip()
        if lit {
            Draw.radial(ctx, [Draw.color(0xFFF7E0), Draw.color(0xFFD493), Draw.color(0xF0A85A), Draw.color(0xC9783A)], [0, 0.25, 0.65, 1],
                        center: CGPoint(x: cx, y: top + 175), radius: 230, extend: true)
        } else {
            Draw.linear(ctx, [Draw.color(0xEFE6D6, 0.95), Draw.color(0xD8CCB6, 0.95), Draw.color(0xBFAF96, 0.95)],
                        from: CGPoint(x: cx - half, y: 0), to: CGPoint(x: cx + half, y: 0))
        }
        // Ribs.
        for i in -9...9 {
            let x = cx + CGFloat(i) * half / 9.5
            ctx.setStrokeColor(lit ? Draw.color(0xA45A20, 0.28) : Draw.black(0.10))
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: cx + (x - cx) * 0.5, y: top - 10))
            ctx.addQuadCurve(to: CGPoint(x: x * 0.98 + cx * 0.02, y: bottom + 10), control: CGPoint(x: cx + (x - cx) * 1.18, y: top + 140))
            ctx.strokePath()
        }
        if lit {
            Draw.radial(ctx, [Draw.white(0.95), Draw.color(0xFFE9B8, 0.6), Draw.color(0xFFE9B8, 0)], [0, 0.3, 1],
                        center: CGPoint(x: cx, y: top + 165), radius: 70)
        }
        ctx.restoreGState()
        ctx.setStrokeColor(lit ? Draw.color(0xFFE2B0, 0.6) : Draw.white(0.5))
        ctx.setLineWidth(2)
        ctx.addPath(dome)
        ctx.strokePath()
    }

    /// A small dark still-life for the framed picture.
    static func painting(size: CGSize, scale: CGFloat) -> CGImage {
        let img = Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(5)
            Draw.linear(ctx, [Draw.color(0x221C15), Draw.color(0x14100B)], from: .zero, to: CGPoint(x: 0, y: size.height))
            let palette: [UInt32] = [0x7A2E2A, 0xB5683C, 0xC9A35A, 0x4F5D3A, 0x8B4F6B, 0xE2C9A0, 0x9C3B2F, 0x6E7A48]
            let c = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
            for _ in 0..<70 {
                let a = rng.r(0...(2 * .pi)), d = rng.r(0...1) * min(size.width, size.height) * 0.42
                let p = CGPoint(x: c.x + cos(a) * d * 1.3, y: c.y + sin(a) * d * 0.8)
                let r = rng.r(5...26)
                ctx.setFillColor(Draw.color(palette[Int(rng.r(0...7.99))], rng.r(0.5...0.9)))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2 * rng.r(0.7...1.1)))
            }
            for _ in 0..<40 {
                ctx.setStrokeColor(Draw.color(0x3E5A2C, 0.6))
                ctx.setLineWidth(rng.r(1...3))
                let p = CGPoint(x: c.x + rng.r(-120...120), y: c.y + rng.r(-60...80))
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + rng.r(-40...40), y: p.y + rng.r(-50...50)))
                ctx.strokePath()
            }
            Draw.radial(ctx, [Draw.black(0), Draw.black(0.6)], center: c, radius: max(size.width, size.height) * 0.7, extend: true)
        }
        return Draw.blur(img, radius: 1.2 * scale)
    }

    // MARK: Turntable parts

    static func plinth(style: DeckStyle, scale: CGFloat) -> CGImage {
        let size = DeckGeometry.size
        let c = DeckGeometry.center
        return Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(31)
            let body = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 30, cornerHeight: 30, transform: nil)
            ctx.addPath(body); ctx.clip()
            switch style {
            case .birch:
                Draw.linear(ctx, [Draw.color(0xEAE3D6), Draw.color(0xDCD2C1), Draw.color(0xCFC3AF)], [0, 0.55, 1],
                            from: .zero, to: CGPoint(x: size.width, y: size.height))
                ctx.setLineCap(.round)
                for _ in 0..<420 {
                    ctx.setStrokeColor(rng.r(0...1) < 0.7 ? Draw.color(0x8A7552, rng.r(0.03...0.10)) : Draw.white(rng.r(0.05...0.15)))
                    ctx.setLineWidth(rng.r(0.5...1.8))
                    let x = rng.r(-20...size.width + 20)
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: x, y: -10))
                    var y: CGFloat = -10
                    let drift = rng.r(-0.04...0.04), wob = rng.r(0.5...3), f = rng.r(0.004...0.02)
                    while y < size.height + 10 { y += 20; p.addLine(to: CGPoint(x: x + y * drift + wob * sin(y * f), y: y)) }
                    ctx.addPath(p); ctx.strokePath()
                }
            case .cream:
                Draw.linear(ctx, [Draw.color(0xF1EBDF), Draw.color(0xE2D9C8)], from: .zero, to: CGPoint(x: 0, y: size.height))
                for _ in 0..<6000 {
                    ctx.setFillColor(Draw.black(rng.r(0.01...0.03)))
                    ctx.fill(CGRect(x: rng.r(0...size.width), y: rng.r(0...size.height), width: 1.5, height: 1.5))
                }
            }
            // Bevel.
            ctx.setStrokeColor(Draw.white(0.65)); ctx.setLineWidth(3)
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5), cornerWidth: 29, cornerHeight: 29, transform: nil))
            ctx.strokePath()
            Draw.linear(ctx, [Draw.black(0), Draw.black(0.10)], from: CGPoint(x: 0, y: size.height * 0.6), to: CGPoint(x: 0, y: size.height))

            // Platter well shadow and platter rim.
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 26, color: Draw.black(0.45))
            ctx.setFillColor(Draw.color(0x2A2A2A))
            let pr = DeckGeometry.platterRadius
            ctx.fillEllipse(in: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2)); ctx.clip()
            Draw.linear(ctx, [Draw.color(0xC9C9C9), Draw.color(0x6A6A6A), Draw.color(0xB0B0B0), Draw.color(0x4A4A4A)], [0, 0.35, 0.6, 1],
                        from: CGPoint(x: c.x - pr, y: c.y - pr), to: CGPoint(x: c.x + pr, y: c.y + pr))
            ctx.restoreGState()

            // Tonearm base plate and rest post.
            let pv = DeckGeometry.pivot
            ctx.setShadow(offset: CGSize(width: 3, height: 5), blur: 10, color: Draw.black(0.35))
            ctx.setFillColor(Draw.color(0x1C1C1C))
            ctx.fillEllipse(in: CGRect(x: pv.x - 48, y: pv.y - 48, width: 96, height: 96))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(Draw.white(0.10)); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: pv.x - 46, y: pv.y - 46, width: 92, height: 92))
            let rp = DeckGeometry.restPost
            ctx.setShadow(offset: CGSize(width: 2, height: 4), blur: 6, color: Draw.black(0.4))
            ctx.setFillColor(Draw.color(0x222222))
            ctx.fillEllipse(in: CGRect(x: rp.x - 11, y: rp.y - 11, width: 22, height: 22))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setFillColor(Draw.color(0x4A4A4A))
            ctx.fillEllipse(in: CGRect(x: rp.x - 5, y: rp.y - 5, width: 10, height: 10))

            // Speed knob.
            let k = DeckGeometry.knob
            ctx.setShadow(offset: CGSize(width: 4, height: 8), blur: 14, color: Draw.black(0.45))
            ctx.setFillColor(Draw.color(0x5A381E))
            ctx.fillEllipse(in: CGRect(x: k.x - 44, y: k.y - 44, width: 88, height: 88))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: k.x - 44, y: k.y - 44, width: 88, height: 88)); ctx.clip()
            Draw.radial(ctx, [Draw.color(0xA97A4E), Draw.color(0x7A4E2A), Draw.color(0x4A2C14)], [0, 0.55, 1],
                        center: CGPoint(x: k.x - 14, y: k.y - 16), radius: 70)
            ctx.restoreGState()
            ctx.setStrokeColor(Draw.color(0xF2E6D2, 0.75)); ctx.setLineWidth(3); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: k.x - 12, y: k.y - 30)); ctx.addLine(to: CGPoint(x: k.x - 4, y: k.y - 18)); ctx.strokePath()
            let labelColor = NSColor(white: 0.35, alpha: 0.8)
            Draw.text("33", at: CGPoint(x: k.x - 46, y: k.y - 62), size: 13, weight: .medium, color: labelColor, centered: true)
            Draw.text("45", at: CGPoint(x: k.x + 46, y: k.y - 62), size: 13, weight: .medium, color: labelColor, centered: true)

            // Badge.
            let badge = CGRect(x: 36, y: 768, width: 152, height: 36)
            ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: Draw.black(0.3))
            ctx.setFillColor(Draw.color(0x2C2B29))
            ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            Draw.text("SPINDLE", at: CGPoint(x: badge.midX, y: badge.midY), size: 14, weight: .semibold,
                      color: NSColor(white: 0.85, alpha: 0.9), kern: 5, centered: true)
        }
    }

    /// The disc without its label: grooves, track gaps, dust and edge.
    static func record(scale: CGFloat) -> CGImage {
        let R = DeckGeometry.recordRadius, L = DeckGeometry.labelRadius
        let size = CGSize(width: R * 2, height: R * 2)
        let c = CGPoint(x: R, y: R)
        return Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(77)
            ctx.addEllipse(in: CGRect(origin: .zero, size: size)); ctx.clip()
            ctx.setFillColor(Draw.color(0x0C0C0D))
            ctx.fill(CGRect(origin: .zero, size: size))
            // Grooves.
            var r = L + 16
            while r < R - 7 {
                ctx.setStrokeColor(rng.r(0...1) < 0.5 ? Draw.white(rng.r(0.012...0.045)) : Draw.black(rng.r(0.2...0.5)))
                ctx.setLineWidth(rng.r(0.35...0.8))
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                r += rng.r(0.9...1.6)
            }
            // Track gaps.
            for gap in [0.93, 0.80, 0.69, 0.58, 0.49] as [CGFloat] {
                let gr = L + 16 + (R - L - 24) * gap
                ctx.setStrokeColor(Draw.color(0x050505)); ctx.setLineWidth(3.5)
                ctx.strokeEllipse(in: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2))
                ctx.setStrokeColor(Draw.white(0.07)); ctx.setLineWidth(0.8)
                ctx.strokeEllipse(in: CGRect(x: c.x - gr - 2.2, y: c.y - gr - 2.2, width: gr * 2 + 4.4, height: gr * 2 + 4.4))
            }
            // Partial arcs: uneven groove reflections that make the spin readable.
            for _ in 0..<170 {
                let ar = rng.r((L + 18)...(R - 9))
                let start = rng.r(0...(2 * .pi)), sweep = rng.r(0.2...1.6)
                ctx.setStrokeColor(Draw.white(rng.r(0.025...0.075)))
                ctx.setLineWidth(rng.r(0.6...2.2))
                ctx.addArc(center: c, radius: ar, startAngle: start, endAngle: start + sweep, clockwise: false)
                ctx.strokePath()
            }
            // Dead wax near the label.
            ctx.setStrokeColor(Draw.color(0x161616)); ctx.setLineWidth(16)
            ctx.strokeEllipse(in: CGRect(x: c.x - L - 8, y: c.y - L - 8, width: (L + 8) * 2, height: (L + 8) * 2))
            ctx.setStrokeColor(Draw.white(0.06)); ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: c.x - L - 15, y: c.y - L - 15, width: (L + 15) * 2, height: (L + 15) * 2))
            // Dust.
            for _ in 0..<90 {
                let a = rng.r(0...(2 * .pi)), d = rng.r(L...(R - 4))
                let s = rng.r(0.5...1.4)
                ctx.setFillColor(Draw.white(rng.r(0.12...0.4)))
                ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * d, y: c.y + sin(a) * d, width: s, height: s))
            }
            // Edge.
            ctx.setStrokeColor(Draw.color(0x2A2A2A)); ctx.setLineWidth(5)
            ctx.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: R * 2 - 5, height: R * 2 - 5))
            ctx.setStrokeColor(Draw.white(0.10)); ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: 5.5, y: 5.5, width: R * 2 - 11, height: R * 2 - 11))
        }
    }

    /// Wear for an old LP jacket, laid over the album art: ring wear from the
    /// record inside, scuffed edges and corners, a crease, paper grain and a
    /// slight warm fade. Transparent where the print is untouched.
    static func sleeveWear(size side: CGFloat = 1000) -> CGImage {
        let size = CGSize(width: side, height: side)
        let k = side / 1000
        let c = CGPoint(x: side / 2, y: side / 2)
        // Ring wear is soft, so it is drawn separately and blurred.
        let ring = Draw.image(size, scale: 1) { ctx in
            var rng = SeededRNG(203)
            let r = side * 0.452
            let (p1, p2, p3) = (rng.r(0...6), rng.r(0...6), rng.r(0...6))
            var a: CGFloat = 0
            ctx.setLineCap(.butt)
            // Smoothly varying strength, strongest where the jacket was handled most.
            while a < 2 * .pi {
                let strength = 0.06 + 0.05 * sin(2 * a + p1) + 0.03 * sin(5 * a + p2)
                ctx.setStrokeColor(Draw.white(max(0, strength)))
                ctx.setLineWidth((16 + 6 * sin(3 * a + p3)) * k)
                ctx.addArc(center: c, radius: r, startAngle: a, endAngle: a + 0.012, clockwise: false)
                ctx.strokePath()
                a += 0.01
            }
            // Hint of the label's ring nearer the centre.
            ctx.setStrokeColor(Draw.white(0.07))
            ctx.setLineWidth(8 * k)
            ctx.strokeEllipse(in: CGRect(x: c.x - side * 0.16, y: c.y - side * 0.16, width: side * 0.32, height: side * 0.32))
        }
        let softRing = Draw.blur(ring, radius: 13 * k)

        return Draw.image(size, scale: 1) { ctx in
            var rng = SeededRNG(317)
            // Faded, slightly yellowed print.
            ctx.setFillColor(Draw.color(0xF3E6CC, 0.10))
            ctx.fill(CGRect(origin: .zero, size: size))
            Draw.upright(softRing, in: CGRect(origin: .zero, size: size), ctx)

            // Scuffs along the edges, heavier toward the corners.
            ctx.setLineCap(.round)
            for _ in 0..<700 {
                let edge = Int(rng.r(0...3.999))
                let t = rng.r(0...side), depth = pow(rng.r(0...1), 2.2) * 26 * k
                let p: CGPoint
                switch edge {
                case 0: p = CGPoint(x: t, y: depth)
                case 1: p = CGPoint(x: side - depth, y: t)
                case 2: p = CGPoint(x: t, y: side - depth)
                default: p = CGPoint(x: depth, y: t)
                }
                let len = rng.r(2...14) * k
                let horizontal = edge % 2 == 0
                ctx.setStrokeColor(Draw.white(rng.r(0.08...0.38)))
                ctx.setLineWidth(rng.r(0.8...2.4) * k)
                ctx.move(to: p)
                ctx.addLine(to: CGPoint(x: p.x + (horizontal ? len : rng.r(-2...2) * k), y: p.y + (horizontal ? rng.r(-2...2) * k : len)))
                ctx.strokePath()
            }
            for corner in [CGPoint.zero, CGPoint(x: side, y: 0), CGPoint(x: side, y: side), CGPoint(x: 0, y: side)] {
                Draw.radial(ctx, [Draw.white(0.32), Draw.white(0.10), Draw.white(0)], [0, 0.35, 1], center: corner, radius: 70 * k)
            }
            // Outer edge worn through to the card.
            ctx.setStrokeColor(Draw.white(0.22))
            ctx.setLineWidth(3 * k)
            ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 1.5 * k, dy: 1.5 * k))

            // A soft crease across one corner.
            let crease = CGMutablePath()
            crease.move(to: CGPoint(x: side * 0.70, y: 0))
            crease.addQuadCurve(to: CGPoint(x: side, y: side * 0.24), control: CGPoint(x: side * 0.86, y: side * 0.13))
            ctx.addPath(crease)
            ctx.setStrokeColor(Draw.white(0.16)); ctx.setLineWidth(2 * k); ctx.strokePath()
            ctx.saveGState(); ctx.translateBy(x: 1.5 * k, y: 1.5 * k)
            ctx.addPath(crease)
            ctx.setStrokeColor(Draw.black(0.10)); ctx.setLineWidth(1.5 * k); ctx.strokePath()
            ctx.restoreGState()

            // Faint stains.
            for _ in 0..<3 {
                let p = CGPoint(x: rng.r(0.15...0.85) * side, y: rng.r(0.15...0.85) * side)
                Draw.radial(ctx, [Draw.color(0x7A5A2A, 0.07), Draw.color(0x7A5A2A, 0)], center: p, radius: rng.r(40...110) * k)
            }

            // Paper grain and fibres.
            for _ in 0..<14000 {
                let s = rng.r(0.8...2.0) * k
                ctx.setFillColor(rng.r(0...1) < 0.5 ? Draw.white(rng.r(0.03...0.09)) : Draw.black(rng.r(0.03...0.08)))
                ctx.fill(CGRect(x: rng.r(0...side), y: rng.r(0...side), width: s, height: s))
            }
            for _ in 0..<160 {
                let p = CGPoint(x: rng.r(0...side), y: rng.r(0...side))
                let a = rng.r(0...(2 * .pi)), l = rng.r(4...16) * k
                ctx.setStrokeColor(Draw.white(rng.r(0.04...0.10)))
                ctx.setLineWidth(0.8 * k)
                ctx.move(to: p); ctx.addLine(to: CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)); ctx.strokePath()
            }
        }
    }

    /// Light-only detail for a photographed record: uneven groove glints and
    /// dust on transparent, meant to be screened over the photo and spun.
    /// `soft` is for records seen at a steep angle, where fine lines would be
    /// squashed below a pixel and shimmer as they turn: it keeps only broad,
    /// blurred bands.
    static func grooveGlints(labelRatio: CGFloat, scale: CGFloat, soft: Bool = false) -> CGImage {
        let R: CGFloat = 340
        let L = R * labelRatio
        let c = CGPoint(x: R, y: R)
        let image = Draw.image(CGSize(width: R * 2, height: R * 2), scale: scale) { ctx in
            var rng = SeededRNG(91)
            ctx.setLineCap(.round)
            // Broad, soft pressing variations: the main cue that the disc turns.
            for _ in 0..<(soft ? 10 : 14) {
                let ar = rng.r((L + 30)...(R - 14))
                let start = rng.r(0...(2 * .pi)), sweep = rng.r(0.5...1.4)
                ctx.setStrokeColor(Draw.white(soft ? rng.r(0.05...0.09) : rng.r(0.04...0.08)))
                ctx.setLineWidth(soft ? rng.r(16...32) : rng.r(8...22))
                ctx.addArc(center: c, radius: ar, startAngle: start, endAngle: start + sweep, clockwise: false)
                ctx.strokePath()
            }
            // Groove glints.
            for _ in 0..<(soft ? 40 : 260) {
                let ar = rng.r((L + 18)...(R - 6))
                let start = rng.r(0...(2 * .pi)), sweep = rng.r(0.15...1.1)
                ctx.setStrokeColor(Draw.white(soft ? rng.r(0.03...0.06) : rng.r(0.04...0.13)))
                ctx.setLineWidth(soft ? rng.r(4...8) : rng.r(0.6...2.0))
                ctx.addArc(center: c, radius: ar, startAngle: start, endAngle: start + sweep, clockwise: false)
                ctx.strokePath()
            }
            guard !soft else { return }
            // Dust and specks.
            for _ in 0..<140 {
                let a = rng.r(0...(2 * .pi)), d = rng.r((L + 12)...(R - 4))
                let s = rng.r(0.8...2.6)
                ctx.setFillColor(Draw.white(rng.r(0.18...0.55)))
                ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * d - s / 2, y: c.y + sin(a) * d - s / 2, width: s, height: s))
            }
        }
        return soft ? Draw.blur(image, radius: 3 * scale) : image
    }

    /// Circular centre label printed from the album artwork.
    static func label(art: CGImage?, scale: CGFloat) -> CGImage {
        let L = DeckGeometry.labelRadius
        let size = CGSize(width: L * 2, height: L * 2)
        return Draw.image(size, scale: scale) { ctx in
            ctx.addEllipse(in: CGRect(origin: .zero, size: size)); ctx.clip()
            if let art {
                Draw.aspectFill(art, in: CGRect(origin: .zero, size: size), ctx)
            } else {
                Draw.upright(placeholderArt(scale: scale * 0.5), in: CGRect(origin: .zero, size: size), ctx)
            }
            Draw.radial(ctx, [Draw.black(0), Draw.black(0), Draw.black(0.35)], [0, 0.8, 1], center: CGPoint(x: L, y: L), radius: L)
            ctx.setStrokeColor(Draw.black(0.5)); ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: 1, y: 1, width: L * 2 - 2, height: L * 2 - 2))
        }
    }

    static func spindle(scale: CGFloat) -> CGImage {
        Draw.image(CGSize(width: 24, height: 24), scale: scale) { ctx in
            ctx.setShadow(offset: CGSize(width: 1.5, height: 2), blur: 2, color: Draw.black(0.6))
            ctx.setFillColor(Draw.color(0x9A9A9A))
            ctx.fillEllipse(in: CGRect(x: 5, y: 5, width: 13, height: 13))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            Draw.radial(ctx, [Draw.white(0.95), Draw.white(0)], center: CGPoint(x: 10, y: 9.5), radius: 5)
        }
    }

    static func tonearm(scale: CGFloat) -> CGImage {
        let L = DeckGeometry.armLength
        let o = DeckGeometry.armOrigin
        return Draw.image(DeckGeometry.armSize, scale: scale) { ctx in
            ctx.translateBy(x: o.x, y: o.y)
            let headAngle: CGFloat = 24 * .pi / 180
            let headLen: CGFloat = 76
            let e = CGPoint(x: L - headLen * cos(headAngle), y: -headLen * sin(headAngle))

            func chrome(_ path: CGPath, from: CGPoint, to: CGPoint) {
                ctx.saveGState()
                ctx.addPath(path); ctx.clip()
                Draw.linear(ctx, [Draw.color(0x8E8E8E), Draw.color(0xFAFAFA), Draw.color(0xC4C4C4), Draw.color(0x6A6A6A)], [0, 0.35, 0.6, 1], from: from, to: to)
                ctx.restoreGState()
            }

            // Counterweight and rear stub.
            let stub = CGPath(roundedRect: CGRect(x: -60, y: -6, width: 60, height: 12), cornerWidth: 4, cornerHeight: 4, transform: nil)
            chrome(stub, from: CGPoint(x: 0, y: -6), to: CGPoint(x: 0, y: 6))
            let weight = CGPath(roundedRect: CGRect(x: -116, y: -25, width: 62, height: 50), cornerWidth: 10, cornerHeight: 10, transform: nil)
            chrome(weight, from: CGPoint(x: 0, y: -25), to: CGPoint(x: 0, y: 25))
            ctx.setStrokeColor(Draw.black(0.35)); ctx.setLineWidth(1.5)
            for x in [-104, -66] as [CGFloat] { ctx.move(to: CGPoint(x: x, y: -24)); ctx.addLine(to: CGPoint(x: x, y: 24)) }
            ctx.strokePath()

            // Arm tube.
            let tube = CGMutablePath()
            tube.move(to: CGPoint(x: 10, y: 0))
            tube.addQuadCurve(to: e, control: CGPoint(x: e.x * 0.6, y: 2))
            let stroked = tube.copy(strokingWithWidth: 11, lineCap: .round, lineJoin: .round, miterLimit: 1)
            let len = hypot(e.x, e.y)
            let n = CGVector(dx: -e.y / len * 6, dy: e.x / len * 6)
            chrome(stroked, from: CGPoint(x: e.x / 2 - n.dx, y: e.y / 2 - n.dy), to: CGPoint(x: e.x / 2 + n.dx, y: e.y / 2 + n.dy))

            // Headshell.
            ctx.saveGState()
            ctx.translateBy(x: e.x, y: e.y)
            ctx.rotate(by: headAngle)
            let shell = CGPath(roundedRect: CGRect(x: -6, y: -18, width: headLen + 12, height: 36), cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.setFillColor(Draw.color(0x2A2A2A)); ctx.addPath(shell); ctx.fillPath()
            ctx.setFillColor(Draw.white(0.55))
            for col in 0..<7 { for row in 0..<3 {
                ctx.fillEllipse(in: CGRect(x: 6 + CGFloat(col) * 8.5, y: -10 + CGFloat(row) * 9, width: 3.6, height: 3.6))
            } }
            ctx.setFillColor(Draw.color(0xC4532E))
            ctx.fill(CGRect(x: headLen - 2, y: -12, width: 10, height: 24))
            // Finger lift.
            ctx.setStrokeColor(Draw.color(0xD8D8D8)); ctx.setLineWidth(3.5); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 20, y: -18)); ctx.addLine(to: CGPoint(x: 34, y: -40)); ctx.strokePath()
            ctx.restoreGState()

            // Pivot hub.
            ctx.setFillColor(Draw.color(0x121212))
            ctx.fillEllipse(in: CGRect(x: -32, y: -32, width: 64, height: 64))
            ctx.setStrokeColor(Draw.color(0x5A5A5A)); ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: -22, y: -22, width: 44, height: 44))
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: -13, y: -13, width: 26, height: 26)); ctx.clip()
            Draw.linear(ctx, [Draw.white(1), Draw.color(0xB8B8B8)], from: CGPoint(x: -13, y: -13), to: CGPoint(x: 13, y: 13))
            ctx.restoreGState()
            ctx.setFillColor(Draw.color(0x2A2A2A))
            ctx.fillEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        }
    }

    // MARK: Front-scene props

    static func plinthFront(size: CGSize, scale: CGFloat) -> CGImage {
        Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(41)
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.clip()
            Draw.linear(ctx, [Draw.color(0x8A5A32), Draw.color(0x6A4022), Draw.color(0x4A2A14)], [0, 0.4, 1], from: .zero, to: CGPoint(x: 0, y: size.height))
            for _ in 0..<120 {
                ctx.setStrokeColor(Draw.color(0x2A1406, rng.r(0.08...0.25))); ctx.setLineWidth(rng.r(0.6...1.6))
                let x0 = rng.r(-100...size.width)
                ctx.addPath(Draw.wave(y: rng.r(0...size.height), from: x0, to: x0 + rng.r(100...500), slope: 0, amp: rng.r(0.3...1.5), freq: 0.02, phase: rng.r(0...6)))
                ctx.strokePath()
            }
            ctx.setFillColor(Draw.color(0xF6EBD8, 0.5)); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: 2))
            Draw.text("SPINDLE", at: CGPoint(x: size.width * 0.3, y: size.height * 0.55), size: size.height * 0.24, weight: .medium,
                      color: NSColor(red: 0.2, green: 0.1, blue: 0.04, alpha: 0.35), kern: size.height * 0.08, centered: true)
        }
    }

    static func stand(size: CGSize, scale: CGFloat) -> CGImage {
        Draw.image(size, scale: scale) { ctx in
            var rng = SeededRNG(53)
            let topH = size.height * 0.32
            Draw.linear(ctx, [Draw.color(0xC99A62), Draw.color(0xA97A46)], from: .zero, to: CGPoint(x: 0, y: topH))
            ctx.setFillColor(Draw.color(0x3A2210, 0.7))
            ctx.fill(CGRect(x: 10, y: topH * 0.35, width: size.width - 20, height: topH * 0.3))
            let front = CGRect(x: 0, y: topH, width: size.width, height: size.height - topH)
            ctx.saveGState(); ctx.addRect(front); ctx.clip()
            Draw.linear(ctx, [Draw.color(0x9A6838), Draw.color(0x6E4420)], from: CGPoint(x: 0, y: front.minY), to: CGPoint(x: 0, y: front.maxY))
            for _ in 0..<60 {
                ctx.setStrokeColor(Draw.color(0x3A1E08, rng.r(0.08...0.22))); ctx.setLineWidth(rng.r(0.5...1.4))
                let x0 = rng.r(-100...size.width)
                ctx.addPath(Draw.wave(y: rng.r(front.minY...front.maxY), from: x0, to: x0 + rng.r(100...400), slope: 0, amp: 0.8, freq: 0.03, phase: rng.r(0...6)))
                ctx.strokePath()
            }
            ctx.restoreGState()
            ctx.setFillColor(Draw.white(0.35)); ctx.fill(CGRect(x: 0, y: topH, width: size.width, height: 1.5))
        }
    }

    /// Shown before anything has played: a dark sleeve with gold rings.
    static func placeholderArt(scale: CGFloat) -> CGImage {
        let size = CGSize(width: 600, height: 600)
        return Draw.image(size, scale: scale) { ctx in
            Draw.linear(ctx, [Draw.color(0x2A2420), Draw.color(0x141110)], from: .zero, to: CGPoint(x: 600, y: 600))
            ctx.setStrokeColor(Draw.color(0xC9A35A, 0.35))
            for i in 0..<9 {
                let r = 60 + CGFloat(i) * 26
                ctx.setLineWidth(i % 3 == 0 ? 2 : 0.8)
                ctx.strokeEllipse(in: CGRect(x: 300 - r, y: 300 - r, width: r * 2, height: r * 2))
            }
        }
    }
}
