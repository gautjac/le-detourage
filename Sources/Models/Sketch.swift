import SwiftUI
import CoreGraphics

/// One freehand stroke: a polyline in a sketch's local space, with a color, a
/// local-space width, and a brush texture.
struct SketchStroke: Codable, Equatable {
    var points: [CGPoint]
    var colorIndex: Int
    var width: CGFloat
    var brush: Brush

    init(points: [CGPoint], colorIndex: Int, width: CGFloat, brush: Brush = .marker) {
        self.points = points
        self.colorIndex = colorIndex
        self.width = width
        self.brush = brush
    }

    enum CodingKeys: String, CodingKey { case points, colorIndex, width, brush }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([CGPoint].self, forKey: .points)
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
        width = try c.decode(CGFloat.self, forKey: .width)
        // Sketches saved before brushes existed default to the marker.
        brush = try c.decodeIfPresent(Brush.self, forKey: .brush) ?? .marker
    }
}

/// A freehand pencil drawing bundled into a single, transformable canvas element.
/// Strokes live in a local coordinate space of `size`; the element's aspect and
/// on-canvas rendering derive from it, so a sketch can be moved, scaled, rotated,
/// flipped, layered, duplicated and deleted exactly like a cutout.
struct Sketch: Codable, Equatable {
    var strokes: [SketchStroke]
    /// The local canonical size the strokes are laid out in (its aspect).
    var size: CGSize

    var isEmpty: Bool { strokes.isEmpty }
    var aspect: CGFloat { size.height > 0 ? size.width / size.height : 1 }

    /// The pen colors offered in the editor.
    static let colors: [Color] = [
        Theme.ink, Theme.coral, Theme.teal, Theme.marigold,
        Theme.grape, Theme.sky, Theme.leaf, .white,
    ]

    static func color(_ index: Int) -> Color {
        colors[min(max(0, index), colors.count - 1)]
    }

    /// Build a sketch from strokes captured in page space, tightly bounding them.
    /// Returns the sketch plus its page-space center and box size, so the caller
    /// can place it exactly where it was drawn. Nil if nothing was drawn.
    static func build(fromPageStrokes strokes: [SketchStroke]) -> (sketch: Sketch, center: CGPoint, box: CGSize)? {
        let allPoints = strokes.flatMap { $0.points }
        guard allPoints.count > 1 else { return nil }
        let maxWidth = strokes.map(\.width).max() ?? 1
        let pad = maxWidth / 2 + 2
        let minX = allPoints.map(\.x).min()! - pad
        let maxX = allPoints.map(\.x).max()! + pad
        let minY = allPoints.map(\.y).min()! - pad
        let maxY = allPoints.map(\.y).max()! + pad
        let box = CGSize(width: max(1, maxX - minX), height: max(1, maxY - minY))
        let origin = CGPoint(x: minX, y: minY)
        let local = strokes.map { stroke in
            SketchStroke(points: stroke.points.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) },
                         colorIndex: stroke.colorIndex, width: stroke.width, brush: stroke.brush)
        }
        let center = CGPoint(x: origin.x + box.width / 2, y: origin.y + box.height / 2)
        return (Sketch(strokes: local, size: box), center, box)
    }

    /// Rasterize the sketch to a transparent image of `targetSize` (for export).
    func image(size targetSize: CGSize) -> PlatformImage? {
        let w = max(1, Int(targetSize.width.rounded())), h = max(1, Int(targetSize.height.rounded()))
        let space = CGColorSpaceCreateDeviceRGB()
        guard size.width > 0, size.height > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y-down so the page-convention stroke coordinates draw upright.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        paint(strokes, in: ctx, scale: CGFloat(w) / size.width)
        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}

