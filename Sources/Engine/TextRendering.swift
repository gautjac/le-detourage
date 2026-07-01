import SwiftUI
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Sizes and rasterizes collage text. The measurement here drives both the live
/// SwiftUI layout (so the selection box and hit area line up) and the Core
/// Graphics exporter (which rasterizes the text to a transparent image and then
/// composes it exactly like a lifted cutout — same shadow/rotation/flip path).
enum TextRendering {

    /// Default on-canvas text height as a fraction of the canvas's shorter edge,
    /// before the element's user scale is applied.
    static let baseFraction: CGFloat = 0.15

    /// The point size a text element renders at for a given canvas and scale.
    static func fontSize(in canvas: CGSize, scale: CGFloat) -> CGFloat {
        max(6, min(canvas.width, canvas.height) * baseFraction * scale)
    }

    /// Padding around the glyphs, in points, relative to the font size. Matched
    /// exactly by the live SwiftUI body so preview == export.
    static func padding(chip: Bool, fontSize: CGFloat) -> (h: CGFloat, v: CGFloat) {
        chip ? (fontSize * 0.42, fontSize * 0.26) : (fontSize * 0.10, fontSize * 0.05)
    }

    /// The corner radius of the paper chip behind the text.
    static func chipCornerRadius(fontSize: CGFloat) -> CGFloat { fontSize * 0.34 }

    /// Build a real platform font carrying the chosen system design (rounded /
    /// serif / monospaced / default) at the given size.
    static func platformFont(_ font: ScrapFont, size: CGFloat) -> PlatformFont {
        let base = PlatformFont.systemFont(ofSize: size, weight: font.platformWeight)
        if let descriptor = base.fontDescriptor.withDesign(font.platformDesign) {
            #if os(macOS)
            if let f = NSFont(descriptor: descriptor, size: size) { return f }
            #else
            return UIFont(descriptor: descriptor, size: size)
            #endif
        }
        return base
    }

    /// The tight bounds of the (possibly multi-line) glyphs at a font size.
    private static func glyphSize(_ content: TextContent, fontSize: CGFloat) -> CGSize {
        let font = platformFont(content.font, size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let attr = NSAttributedString(string: content.displayString, attributes: attributes)
        let bounds = attr.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                         height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// The full on-canvas footprint of a text element (glyphs + padding).
    static func measure(_ content: TextContent, in canvas: CGSize, scale: CGFloat) -> CGSize {
        let fs = fontSize(in: canvas, scale: scale)
        let glyph = glyphSize(content, fontSize: fs)
        let pad = padding(chip: content.chip, fontSize: fs)
        return CGSize(width: max(1, glyph.width + pad.h * 2),
                      height: max(1, glyph.height + pad.v * 2))
    }

    /// Rasterize a text element (chip + glyphs) to a transparent image of the
    /// given point size. Used only by the exporter / thumbnailer; the live canvas
    /// draws vector text via SwiftUI.
    static func image(_ content: TextContent, size: CGSize, fontSize: CGFloat) -> PlatformImage? {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        let font = platformFont(content.font, size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let radius = chipCornerRadius(fontSize: fontSize)
        let drawChip = content.chip

        #if os(macOS)
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocusFlipped(true)
        if drawChip {
            NSColor(content.chipColor).setFill()
            let path = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h),
                                    xRadius: radius, yRadius: radius)
            path.fill()
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor(content.color),
        ]
        let attr = NSAttributedString(string: content.displayString, attributes: attributes)
        let textSize = attr.size()
        let rect = NSRect(x: 0, y: (CGFloat(h) - textSize.height) / 2,
                          width: CGFloat(w), height: textSize.height)
        attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        img.unlockFocus()
        return img
        #else
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        return renderer.image { _ in
            if drawChip {
                UIColor(content.chipColor).setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                             cornerRadius: radius).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .paragraphStyle: paragraph, .foregroundColor: UIColor(content.color),
            ]
            let attr = NSAttributedString(string: content.displayString, attributes: attributes)
            let textSize = attr.size()
            let rect = CGRect(x: 0, y: (CGFloat(h) - textSize.height) / 2,
                              width: CGFloat(w), height: textSize.height)
            attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        #endif
    }
}
