import SwiftUI
import CoreGraphics

/// The available pencil brush textures. Each brush turns a polyline into a set
/// of backend-agnostic draw ops (`BrushOp`), rendered identically by the live
/// SwiftUI canvas and the Core Graphics exporter. Jitter is seeded per stroke so
/// preview and export always match and never flicker.
enum Brush: Int, CaseIterable, Codable, Identifiable {
    case marker       // solid round ink
    case highlighter  // wide translucent flat
    case calligraphy  // angled nib, direction-varying width
    case pencil        // thin graphite with faint grain
    case crayon       // waxy grainy dabs
    case chalk        // dusty scattered dabs
    case spray        // airbrush scatter
    case dotted       // round dots
    case dashed       // dashes
    case neon         // glowing core + halo

    var id: Int { rawValue }
    var titleKey: String { "brush.\(self)" }
}

/// A primitive draw op in a sketch's local coordinate space. The renderer scales
/// points, widths, dashes and radii by the display scale.
enum BrushOp {
    case stroke(points: [CGPoint], width: CGFloat, cap: CGLineCap, dash: [CGFloat], color: Color, opacity: Double)
    case dot(center: CGPoint, radius: CGFloat, color: Color, opacity: Double)
    case fill(points: [CGPoint], color: Color, opacity: Double)
}

// MARK: - Deterministic jitter

/// A tiny, deterministic PRNG so textured brushes render the same every time.
struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func unit() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0x7FFF_FFFF) / CGFloat(0x7FFF_FFFF)
    }
    /// A value in -mag...mag.
    mutating func jitter(_ mag: CGFloat) -> CGFloat { (unit() * 2 - 1) * mag }
}

private func seed(for points: [CGPoint]) -> UInt64 {
    var h: UInt64 = 1469598103934665603
    for p in points {
        h = (h ^ UInt64(bitPattern: Int64(p.x.rounded()))) &* 1099511628211
        h = (h ^ UInt64(bitPattern: Int64(p.y.rounded()))) &* 1099511628211
    }
    return h
}

// MARK: - Geometry helpers

/// Walk a polyline emitting a point every `spacing` units.
private func resample(_ pts: [CGPoint], spacing: CGFloat) -> [CGPoint] {
    guard pts.count > 1, spacing > 0.1 else { return pts }
    var out: [CGPoint] = [pts[0]]
    var carry: CGFloat = 0
    for i in 1..<pts.count {
        let a = pts[i - 1], b = pts[i]
        let seg = hypot(b.x - a.x, b.y - a.y)
        guard seg > 0.0001 else { continue }
        var d = spacing - carry
        while d <= seg {
            let t = d / seg
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            d += spacing
        }
        carry = seg - (d - spacing)
    }
    return out
}

private func unitDirection(_ pts: [CGPoint], _ i: Int) -> CGPoint {
    let a = i < pts.count - 1 ? pts[i] : pts[i - 1]
    let b = i < pts.count - 1 ? pts[i + 1] : pts[i]
    let dx = b.x - a.x, dy = b.y - a.y
    let len = max(0.0001, hypot(dx, dy))
    return CGPoint(x: dx / len, y: dy / len)
}

/// A variable-width nib ribbon: thick when the stroke runs across the nib angle,
/// thin when along it.
private func calligraphyRibbon(_ pts: [CGPoint], width: CGFloat, nib: CGFloat) -> [CGPoint] {
    guard pts.count > 1 else { return [] }
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0..<pts.count {
        let dir = unitDirection(pts, i)
        let theta = atan2(dir.y, dir.x)
        let hw = width * (0.16 + 0.84 * abs(sin(theta - nib))) / 2
        let n = CGPoint(x: -dir.y, y: dir.x)
        left.append(CGPoint(x: pts[i].x + n.x * hw, y: pts[i].y + n.y * hw))
        right.append(CGPoint(x: pts[i].x - n.x * hw, y: pts[i].y - n.y * hw))
    }
    return left + right.reversed()
}

// MARK: - Brush recipes

/// Expand one stroke into draw ops for its brush (all in local space).
func brushOps(brush: Brush, points: [CGPoint], width w: CGFloat, color: Color) -> [BrushOp] {
    guard points.count > 1 else { return [] }
    var rng = SeededRNG(seed: seed(for: points))

    switch brush {
    case .marker:
        return [.stroke(points: points, width: w, cap: .round, dash: [], color: color, opacity: 1)]

    case .highlighter:
        return [.stroke(points: points, width: w * 1.9, cap: .square, dash: [], color: color, opacity: 0.30)]

    case .calligraphy:
        return [.fill(points: calligraphyRibbon(points, width: w * 1.5, nib: .pi / 4), color: color, opacity: 1)]

    case .pencil:
        var ops: [BrushOp] = [.stroke(points: points, width: w * 0.7, cap: .round, dash: [], color: color, opacity: 0.7)]
        for p in resample(points, spacing: w * 0.5) {
            ops.append(.dot(center: CGPoint(x: p.x + rng.jitter(w * 0.3), y: p.y + rng.jitter(w * 0.3)),
                            radius: w * 0.16, color: color, opacity: 0.22))
        }
        return ops

    case .crayon:
        var ops: [BrushOp] = [.stroke(points: points, width: w * 0.8, cap: .round, dash: [], color: color, opacity: 0.22)]
        for p in resample(points, spacing: w * 0.42) {
            for _ in 0..<2 {
                ops.append(.dot(center: CGPoint(x: p.x + rng.jitter(w * 0.34), y: p.y + rng.jitter(w * 0.34)),
                                radius: w * (0.28 + rng.unit() * 0.16),
                                color: color, opacity: 0.35 + Double(rng.unit()) * 0.35))
            }
        }
        return ops

    case .chalk:
        var ops: [BrushOp] = []
        for p in resample(points, spacing: w * 0.5) {
            for _ in 0..<4 {
                ops.append(.dot(center: CGPoint(x: p.x + rng.jitter(w * 0.6), y: p.y + rng.jitter(w * 0.55)),
                                radius: w * 0.2, color: color, opacity: 0.28))
            }
        }
        return ops

    case .spray:
        var ops: [BrushOp] = []
        for p in resample(points, spacing: w * 0.7) {
            for _ in 0..<10 {
                let ang = rng.unit() * .pi * 2, rad = rng.unit() * w * 0.9
                ops.append(.dot(center: CGPoint(x: p.x + cos(ang) * rad, y: p.y + sin(ang) * rad),
                                radius: w * 0.09, color: color, opacity: 0.5))
            }
        }
        return ops

    case .dotted:
        return [.stroke(points: points, width: w, cap: .round, dash: [0.1, w * 1.9], color: color, opacity: 1)]

    case .dashed:
        return [.stroke(points: points, width: w, cap: .round, dash: [w * 2.0, w * 1.5], color: color, opacity: 1)]

    case .neon:
        return [
            .stroke(points: points, width: w * 3.0, cap: .round, dash: [], color: color, opacity: 0.10),
            .stroke(points: points, width: w * 1.9, cap: .round, dash: [], color: color, opacity: 0.16),
            .stroke(points: points, width: w, cap: .round, dash: [], color: color, opacity: 1),
        ]
    }
}

// MARK: - Renderers

/// Render brush ops into a SwiftUI graphics context, scaling from local space.
func renderBrush(_ ops: [BrushOp], in ctx: GraphicsContext, scale: CGFloat) {
    for op in ops {
        switch op {
        case let .stroke(points, width, cap, dash, color, opacity):
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            ctx.stroke(path, with: .color(color.opacity(opacity)),
                       style: StrokeStyle(lineWidth: max(0.5, width * scale), lineCap: cap,
                                          lineJoin: .round, dash: dash.map { $0 * scale }))
        case let .dot(center, radius, color, opacity):
            let r = max(0.4, radius * scale)
            let rect = CGRect(x: center.x * scale - r, y: center.y * scale - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
        case let .fill(points, color, opacity):
            var path = Path()
            path.addLines(points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(opacity)))
        }
    }
}

/// Paint a set of strokes (each with its own brush) into a SwiftUI context.
func paint(_ strokes: [SketchStroke], in ctx: GraphicsContext, scale: CGFloat) {
    for s in strokes {
        renderBrush(brushOps(brush: s.brush, points: s.points, width: s.width,
                             color: Sketch.color(s.colorIndex)), in: ctx, scale: scale)
    }
}

/// Paint a set of strokes into a Core Graphics context (the exporter).
func paint(_ strokes: [SketchStroke], in ctx: CGContext, scale: CGFloat) {
    for s in strokes {
        renderBrush(brushOps(brush: s.brush, points: s.points, width: s.width,
                             color: Sketch.color(s.colorIndex)), in: ctx, scale: scale)
    }
}

/// Render brush ops into a Core Graphics context (the exporter), scaling from
/// local space.
func renderBrush(_ ops: [BrushOp], in ctx: CGContext, scale: CGFloat) {
    ctx.setLineJoin(.round)
    for op in ops {
        switch op {
        case let .stroke(points, width, cap, dash, color, opacity):
            ctx.setLineCap(cap)
            ctx.setLineWidth(max(0.5, width * scale))
            ctx.setStrokeColor(color.cg.copy(alpha: CGFloat(opacity)) ?? color.cg)
            ctx.setLineDash(phase: 0, lengths: dash.map { $0 * scale })
            ctx.addLines(between: points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            ctx.strokePath()
        case let .dot(center, radius, color, opacity):
            let r = max(0.4, radius * scale)
            ctx.setFillColor(color.cg.copy(alpha: CGFloat(opacity)) ?? color.cg)
            ctx.fillEllipse(in: CGRect(x: center.x * scale - r, y: center.y * scale - r, width: r * 2, height: r * 2))
        case let .fill(points, color, opacity):
            ctx.setFillColor(color.cg.copy(alpha: CGFloat(opacity)) ?? color.cg)
            ctx.addLines(between: points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            ctx.closePath()
            ctx.fillPath()
        }
    }
    ctx.setLineDash(phase: 0, lengths: [])
}
