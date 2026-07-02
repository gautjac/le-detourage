import Foundation
import CoreGraphics
import CoreImage

/// On-device edge cleanup for a lifted cutout: manual erasing (paint away stray
/// bits) and edge feathering. Operates on the cutout's pixels and preserves its
/// dimensions, so the placed element's size/aspect stay put.
enum CutoutCleanup {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Erase along a stroke (points in the image's top-left pixel space) by
    /// clearing alpha with a round brush of `radiusPx`.
    static func erase(_ image: PlatformImage, points: [CGPoint], radiusPx: CGFloat) -> PlatformImage? {
        guard let cg = image.cgImageNormalized, !points.isEmpty else { return image }
        let w = cg.width, h = cg.height
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))   // upright (y-up)

        // Convert top-left points to the context's y-up space and clear alpha.
        let pts = points.map { CGPoint(x: $0.x, y: CGFloat(h) - $0.y) }
        ctx.setBlendMode(.clear)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(radiusPx * 2)
        for p in pts {
            ctx.fillEllipse(in: CGRect(x: p.x - radiusPx, y: p.y - radiusPx,
                                       width: radiusPx * 2, height: radiusPx * 2))
        }
        if pts.count > 1 {
            ctx.addLines(between: pts)
            ctx.strokePath()
        }
        guard let out = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: out)
    }

    /// Soften the cutout's edges with a small Gaussian blur (feather).
    static func feather(_ image: PlatformImage, radius: CGFloat = 1.6) -> PlatformImage? {
        guard let cg = image.cgImageNormalized else { return image }
        let source = CIImage(cgImage: cg)
        let blurred = source.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: source.extent)
        guard let out = ciContext.createCGImage(blurred, from: source.extent) else { return nil }
        return PlatformImage.from(cgImage: out)
    }
}
