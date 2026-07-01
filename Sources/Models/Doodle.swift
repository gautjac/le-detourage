import SwiftUI
import CoreGraphics

/// One freehand stroke: a polyline in the collage's fixed reference space, with
/// a color and a reference-space width, so it scales to any window and export.
struct DoodleStroke: Codable, Equatable {
    var points: [CGPoint]
    var colorIndex: Int
    var width: CGFloat
}

/// The freehand doodle layer: an ordered set of strokes. A plain Codable value
/// so it snapshots for undo and serializes with the rest of the document — no
/// platform drawing framework required (PencilKit's canvas isn't on native
/// macOS), and Apple Pencil still draws through the drag gesture on iPad.
struct Doodle: Codable, Equatable {
    var strokes: [DoodleStroke] = []

    var isEmpty: Bool { strokes.isEmpty }

    /// The pen colors offered in the editor.
    static let colors: [Color] = [
        Theme.ink, Theme.coral, Theme.teal, Theme.marigold,
        Theme.grape, Theme.sky, Theme.leaf, .white,
    ]

    static func color(_ index: Int) -> Color {
        colors[min(max(0, index), colors.count - 1)]
    }

    /// Flatten the doodle into a Core Graphics context sized `targetSize`,
    /// scaling from the reference space. Used by the exporter.
    func draw(in ctx: CGContext, targetSize: CGSize, referenceSize: CGSize) {
        guard referenceSize.width > 1 else { return }
        let scale = targetSize.width / referenceSize.width
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where stroke.points.count > 1 {
            ctx.setStrokeColor(Doodle.color(stroke.colorIndex).cg)
            ctx.setLineWidth(max(0.5, stroke.width * scale))
            let scaled = stroke.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
            ctx.addLines(between: scaled)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
