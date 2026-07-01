import SwiftUI
import CoreGraphics

/// How an embellishment is painted.
enum EmblemDraw {
    case fill
    case stroke(CGFloat)   // line width as a fraction of the shape's shorter edge
}

/// The scrapbook embellishment shapes: little vector stickers (hearts, stars,
/// banners, arrows, washi tape…) drawn from the same `Path` in the live canvas
/// and the exporter, so they scale crisply and match everywhere.
enum EmblemShape: Int, CaseIterable, Codable, Identifiable {
    case heart, star, sparkle, burst, banner, speech, arrow, squiggle, ring, tape

    var id: Int { rawValue }

    /// Nominal width/height ratio, so each shape gets a natural default footprint.
    var aspect: CGFloat {
        switch self {
        case .heart:    return 1.05
        case .star:     return 1.0
        case .sparkle:  return 1.0
        case .burst:    return 1.0
        case .banner:   return 2.4
        case .speech:   return 1.25
        case .arrow:    return 2.0
        case .squiggle: return 3.0
        case .ring:     return 1.0
        case .tape:     return 3.2
        }
    }

    var draw: EmblemDraw {
        switch self {
        case .arrow:    return .stroke(0.10)
        case .squiggle: return .stroke(0.11)
        case .ring:     return .stroke(0.11)
        default:        return .fill
        }
    }

    var titleKey: String { "emblem.\(self)" }

    /// The stroke width in points for a given rendered size (0 for filled shapes).
    func strokeWidth(in size: CGSize) -> CGFloat {
        if case .stroke(let f) = draw { return max(1, min(size.width, size.height) * f) }
        return 0
    }

    /// The final path to paint, already inset so strokes don't clip.
    func renderPath(in size: CGSize) -> Path {
        let inset = strokeWidth(in: size) / 2
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        return path(in: rect)
    }

    // MARK: Geometry (y-down / SwiftUI coordinates)

    func path(in r: CGRect) -> Path {
        switch self {
        case .heart:    return heart(in: r)
        case .star:     return polarStar(in: r, points: 5, inner: 0.42)
        case .sparkle:  return polarStar(in: r, points: 4, inner: 0.26)
        case .burst:    return polarStar(in: r, points: 12, inner: 0.74)
        case .banner:   return banner(in: r)
        case .speech:   return speech(in: r)
        case .arrow:    return arrow(in: r)
        case .squiggle: return squiggle(in: r)
        case .ring:     return Path(ellipseIn: r)
        case .tape:     return Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
        }
    }

    private func heart(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY + h * 0.30))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.30),
                   control1: CGPoint(x: r.midX - w * 0.10, y: r.minY),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.05))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.55),
                   control2: CGPoint(x: r.midX - w * 0.28, y: r.minY + h * 0.72))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.30),
                   control1: CGPoint(x: r.midX + w * 0.28, y: r.minY + h * 0.72),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.55))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY + h * 0.30),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.05),
                   control2: CGPoint(x: r.midX + w * 0.10, y: r.minY))
        p.closeSubpath()
        return p
    }

    private func polarStar(in r: CGRect, points: Int, inner: CGFloat) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) / 2
        let innerR = outer * inner
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : innerR
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(points)
            let pt = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func banner(in r: CGRect) -> Path {
        let notch = r.width * 0.08
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - notch, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + notch, y: r.midY))
        p.closeSubpath()
        return p
    }

    private func speech(in r: CGRect) -> Path {
        let bodyH = r.height * 0.78
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: bodyH)
        var p = Path(roundedRect: body, cornerRadius: bodyH * 0.28)
        p.move(to: CGPoint(x: r.minX + r.width * 0.24, y: r.minY + bodyH - 1))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.18, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + bodyH - 1))
        p.closeSubpath()
        return p
    }

    private func arrow(in r: CGRect) -> Path {
        let midY = r.midY
        let tip = CGPoint(x: r.maxX, y: midY)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: midY))
        p.addLine(to: tip)
        p.move(to: CGPoint(x: tip.x - r.width * 0.14, y: midY - r.height * 0.26))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - r.width * 0.14, y: midY + r.height * 0.26))
        return p
    }

    private func squiggle(in r: CGRect) -> Path {
        var p = Path()
        let steps = 48
        let amp = r.height * 0.42
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = r.minX + t * r.width
            let y = r.midY + sin(t * .pi * 3) * amp
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// A placed embellishment: a shape plus its color.
struct Embellishment: Equatable, Codable {
    var shape: EmblemShape
    var colorIndex: Int

    init(shape: EmblemShape = .heart, colorIndex: Int = 0) {
        self.shape = shape
        self.colorIndex = colorIndex
    }

    /// The scrapbook palette for embellishments.
    static let colors: [Color] = [
        Theme.coral, Theme.teal, Theme.marigold, Theme.grape,
        Theme.sky, Theme.leaf, Theme.bubblegum, Theme.ink, .white,
    ]

    var color: Color { Self.colors[min(max(0, colorIndex), Self.colors.count - 1)] }

    /// Washi tape reads as translucent; everything else is solid.
    var fillOpacity: Double { shape == .tape ? 0.82 : 1.0 }

    /// Rasterize the embellishment to a transparent image (for the exporter).
    func image(size: CGSize) -> PlatformImage? {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Flip to y-down so the shared y-down path geometry draws upright.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        let pixelSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        let path = shape.renderPath(in: pixelSize).cgPath
        let cgColor = color.opacity(fillOpacity).cg
        ctx.addPath(path)
        switch shape.draw {
        case .fill:
            ctx.setFillColor(cgColor)
            ctx.fillPath()
        case .stroke:
            ctx.setStrokeColor(cgColor)
            ctx.setLineWidth(shape.strokeWidth(in: pixelSize))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}
