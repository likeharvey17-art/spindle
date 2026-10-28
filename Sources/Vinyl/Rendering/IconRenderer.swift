import AppKit

/// Draws the 1024px app icon: a record on a walnut tile.
enum IconRenderer {
    static func writeIcon(to url: URL) {
        let size = CGSize(width: 1024, height: 1024)
        let image = Draw.image(size, scale: 1) { ctx in
            let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
            let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
            ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: Draw.black(0.35))
            ctx.addPath(path); ctx.setFillColor(Draw.color(0x8A4A20)); ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            Draw.upright(Textures.topDownDesk(size: CGSize(width: 2000, height: 1300), scale: 0.5),
                         in: CGRect(x: -200, y: 0, width: 1580, height: 1027), ctx)
            let R: CGFloat = 330
            let c = CGPoint(x: 512, y: 512)
            ctx.setShadow(offset: CGSize(width: 10, height: 18), blur: 30, color: Draw.black(0.5))
            ctx.setFillColor(Draw.color(0x0C0C0D))
            ctx.fillEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            Draw.upright(Textures.record(scale: 1), in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), ctx)
            let L = DeckGeometry.labelRadius * R / DeckGeometry.recordRadius
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: c.x - L, y: c.y - L, width: L * 2, height: L * 2)); ctx.clip()
            Draw.radial(ctx, [Draw.color(0xF2A266), Draw.color(0xD9642C), Draw.color(0xA8441F)], [0, 0.6, 1],
                        center: CGPoint(x: c.x - 18, y: c.y - 22), radius: L * 1.1, extend: true)
            ctx.restoreGState()
            ctx.setFillColor(Draw.color(0xDADADA))
            ctx.fillEllipse(in: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
            // Sheen.
            ctx.setStrokeColor(Draw.white(0.12)); ctx.setLineWidth(40)
            ctx.addArc(center: c, radius: R * 0.7, startAngle: -2.5, endAngle: -1.9, clockwise: false); ctx.strokePath()
            ctx.addArc(center: c, radius: R * 0.7, startAngle: 0.65, endAngle: 1.25, clockwise: false); ctx.strokePath()
            ctx.restoreGState()
        }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
