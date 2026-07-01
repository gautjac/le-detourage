import Foundation
import CoreGraphics
import SwiftUI

/// Flattens a `Collage` to a single high-resolution PNG. Renders directly with
/// Core Graphics (not a SwiftUI snapshot) so the export is deterministic,
/// off-screen, and identical on iOS and macOS.
enum CollageRenderer {

    /// The exported longer-edge resolution in pixels.
    static let exportLongEdge: CGFloat = 2048

    /// Render the collage to a PNG-backed `PlatformImage`.
    /// - Parameters:
    ///   - collage: the document to flatten.
    ///   - transparentBackground: when true, the chosen background is skipped and
    ///     the canvas is left transparent (stickers only).
    ///   - longEdge: the longer-edge output resolution in pixels (defaults to the
    ///     full 2K export; smaller values render gallery thumbnails).
    static func render(_ collage: Collage, transparentBackground: Bool,
                       longEdge: CGFloat = exportLongEdge) -> PlatformImage? {
        let aspect = max(0.2, collage.canvasAspect)
        let (pw, ph): (Int, Int)
        if aspect >= 1 {
            pw = Int(longEdge)
            ph = Int(longEdge / aspect)
        } else {
            ph = Int(longEdge)
            pw = Int(longEdge * aspect)
        }
        guard pw > 0, ph > 0 else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8,
                                  bytesPerRow: pw * 4, space: space, bitmapInfo: info) else {
            return nil
        }

        // CoreGraphics is y-up; our normalized positions are y-down (SwiftUI).
        // Flip the context so we can compose in screen coordinates directly.
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: 1, y: -1)

        let canvas = CGSize(width: pw, height: ph)

        if !transparentBackground {
            drawBackground(collage.background, image: collage.backgroundImage,
                           in: ctx, canvas: canvas)
        }

        for sticker in collage.ordered {
            drawSticker(sticker, in: ctx, canvas: canvas)
        }

        // The freehand doodle layer flattens on top of everything.
        collage.doodle?.draw(in: ctx, targetSize: canvas, referenceSize: collage.drawingReferenceSize)

        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }

    private static func drawBackground(_ bg: CollageBackground, image: PlatformImage?,
                                       in ctx: CGContext, canvas: CGSize) {
        let rect = CGRect(origin: .zero, size: canvas)
        switch bg {
        case .transparent:
            break
        case .color(let c):
            ctx.setFillColor(c.cg)
            ctx.fill(rect)
        case .gradient(let a, let b):
            let space = CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: space,
                                     colors: [a.cg, b.cg] as CFArray, locations: [0, 1]) {
                ctx.saveGState()
                ctx.addRect(rect); ctx.clip()
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: canvas.height),
                                       end: CGPoint(x: canvas.width, y: 0), options: [])
                ctx.restoreGState()
            }
        case .photo:
            if let img = image, let cg = img.cgImageNormalized {
                // Aspect-fill the photo into the canvas.
                let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
                let scale = max(canvas.width / iw, canvas.height / ih)
                let dw = iw * scale, dh = ih * scale
                let dx = (canvas.width - dw) / 2, dy = (canvas.height - dh) / 2
                ctx.saveGState()
                // Undo the y-flip locally so the photo isn't drawn upside-down.
                ctx.translateBy(x: 0, y: canvas.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cg, in: CGRect(x: dx, y: canvas.height - dy - dh, width: dw, height: dh))
                ctx.restoreGState()
            } else {
                ctx.setFillColor(Theme.page.cg)
                ctx.fill(rect)
            }
        }
    }

    private static func drawSticker(_ s: PlacedSticker, in ctx: CGContext, canvas: CGSize) {
        let size = s.renderSize(in: canvas)
        guard size.width >= 1, size.height >= 1 else { return }

        // Resolve the element to bitmaps. Cutouts contribute a filtered subject
        // plus an optional die-cut contour outline; text is rasterized (chip +
        // glyphs). Everything then flows through the same shadow / rotation /
        // flip compositing below, so preview and export match.
        let subjectCG: CGImage?
        var outline: (cg: CGImage, size: CGSize)?
        switch s.kind {
        case .cutout(let img):
            let styled = s.styled
            subjectCG = (styled?.subject ?? img).cgImageNormalized
            if let outlineImg = styled?.outline, let ratio = styled?.outlineRatio,
               let outlineCG = outlineImg.cgImageNormalized {
                outline = (outlineCG, CGSize(width: size.width * ratio.width,
                                             height: size.height * ratio.height))
            }
        case .text(let content):
            let fontSize = TextRendering.fontSize(in: canvas, scale: s.scale)
            subjectCG = TextRendering.image(content, size: size, fontSize: fontSize)?.cgImageNormalized
        case .shape(let embellishment):
            subjectCG = embellishment.image(size: size)?.cgImageNormalized
        }
        guard let subject = subjectCG else { return }
        let center = s.center(in: canvas)

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: s.rotation)
        if s.flipped { ctx.scaleBy(x: -1, y: 1) }

        if s.shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -min(canvas.width, canvas.height) * 0.012),
                          blur: min(canvas.width, canvas.height) * 0.02,
                          color: CGColor(red: 0.15, green: 0.10, blue: 0.08, alpha: 0.35))
        }

        // The die-cut outline sits behind and carries the shadow; clear the
        // shadow before the subject so it isn't drawn twice.
        if let outline {
            drawCentered(outline.cg, size: outline.size, in: ctx)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        drawCentered(subject, size: size, in: ctx)

        ctx.restoreGState()
    }

    /// Draw a CGImage centered on the current origin, undoing the context's
    /// global y-flip locally so the bitmap renders upright.
    private static func drawCentered(_ cg: CGImage, size: CGSize, in ctx: CGContext) {
        ctx.saveGState()
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2,
                          width: size.width, height: size.height)
        ctx.translateBy(x: 0, y: rect.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        let upright = CGRect(x: rect.origin.x, y: -rect.origin.y - size.height,
                             width: size.width, height: size.height)
        ctx.draw(cg, in: upright)
        ctx.restoreGState()
    }
}

extension Color {
    /// A `CGColor` for this SwiftUI color, resolved through the platform bridge.
    var cg: CGColor {
        #if os(macOS)
        return NSColor(self).cgColor
        #else
        return UIColor(self).cgColor
        #endif
    }
}
