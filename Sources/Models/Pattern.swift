import SwiftUI
import CoreGraphics

/// A repeating background pattern, generated to an image (shared by the live
/// canvas and the exporter) from a base color + an accent color.
enum PatternStyle: Int, CaseIterable, Codable, Identifiable {
    case dots, grid, stripes, checker, confetti

    var id: Int { rawValue }
    var titleKey: String { "pattern.\(self)" }

    /// Render the pattern filling `size`.
    func image(size: CGSize, base: Color, accent: Color) -> PlatformImage? {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let W = CGFloat(w), H = CGFloat(h)
        ctx.setFillColor(base.cg)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(accent.cg)
        ctx.setStrokeColor(accent.cg)

        // Tile size relative to the shorter edge so patterns look consistent.
        let unit = min(W, H) / 16

        switch self {
        case .dots:
            let r = unit * 0.22, step = unit
            var y = step / 2
            while y < H { var x = step / 2; while x < W {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)); x += step }; y += step }
        case .grid:
            ctx.setLineWidth(max(1, unit * 0.06))
            var x = unit; while x < W { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)); x += unit }
            var y = unit; while y < H { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); y += unit }
            ctx.strokePath()
        case .stripes:
            ctx.setLineWidth(unit * 0.5)
            ctx.setLineCap(.square)
            var d = -H; while d < W { ctx.move(to: CGPoint(x: d, y: 0)); ctx.addLine(to: CGPoint(x: d + H, y: H)); d += unit * 1.6 }
            ctx.strokePath()
        case .checker:
            let s = unit * 1.4
            var row = 0; var y = CGFloat(0)
            while y < H { var col = 0; var x = CGFloat(0); while x < W {
                if (row + col) % 2 == 0 { ctx.fill(CGRect(x: x, y: y, width: s, height: s)) }; x += s; col += 1 }; y += s; row += 1 }
        case .confetti:
            var rng = SeededRNG(seed: 0xC0FFEE)
            let count = Int((W * H) / (unit * unit * 3))
            for _ in 0..<count {
                let x = rng.unit() * W, y = rng.unit() * H, r = unit * (0.12 + rng.unit() * 0.16)
                ctx.saveGState()
                ctx.translateBy(x: x, y: y); ctx.rotate(by: rng.unit() * .pi)
                ctx.fill(CGRect(x: -r, y: -r * 0.4, width: r * 2, height: r * 0.8))
                ctx.restoreGState()
            }
        }
        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}
