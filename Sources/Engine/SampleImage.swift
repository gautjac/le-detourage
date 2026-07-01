import Foundation
import CoreGraphics
import CoreText

/// A bundled sample photo so lift → collage → export is fully demoable in the
/// Simulator with no photo library. It renders a clear, high-contrast subject —
/// a friendly rounded character (a "petit monstre" mascot) — over a soft
/// gradient sky. The strong foreground/background separation gives both
/// VisionKit subject-lift and the Vision foreground-mask fallback something
/// unambiguous to grab.
enum SampleImage {
    static func make(width w: Int = 1200, height h: Int = 1500) -> PlatformImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info.rawValue)
        else { return nil }

        let W = Double(w), H = Double(h)

        // Soft vertical sky gradient background.
        let bgSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(colorSpace: bgSpace, components: [0.72, 0.86, 0.97, 1])!,
            CGColor(colorSpace: bgSpace, components: [0.90, 0.94, 0.86, 1])!,
        ] as CFArray
        if let grad = CGGradient(colorsSpace: bgSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H),
                                   end: CGPoint(x: 0, y: 0), options: [])
        }

        // A pale sun disc, up and to the left, for atmosphere (stays background).
        ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.82, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: W * 0.10, y: H * 0.78, width: W * 0.22, height: W * 0.22))

        // ---- The subject: a rounded teal mascot, high contrast to the sky. ----
        let cx = W * 0.52
        let bodyBottom = H * 0.10
        let bodyTop = H * 0.62
        let bodyW = W * 0.46
        let bodyH = bodyTop - bodyBottom

        func fill(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: a))
        }

        // Drop shadow blob under the body for grounding.
        fill(0.10, 0.14, 0.16, 0.18)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.52, y: bodyBottom - H * 0.02,
                                   width: bodyW * 1.04, height: H * 0.06))

        // Body — a rounded capsule.
        fill(0.16, 0.66, 0.62)
        let bodyRect = CGRect(x: cx - bodyW / 2, y: bodyBottom, width: bodyW, height: bodyH)
        let body = CGPath(roundedRect: bodyRect, cornerWidth: bodyW * 0.5,
                          cornerHeight: bodyW * 0.5, transform: nil)
        ctx.addPath(body); ctx.fillPath()

        // Belly patch.
        fill(0.86, 0.95, 0.93)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.28, y: bodyBottom + bodyH * 0.10,
                                   width: bodyW * 0.56, height: bodyH * 0.42))

        // Two little feet.
        fill(0.12, 0.52, 0.49)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.30, y: bodyBottom - H * 0.008,
                                   width: bodyW * 0.24, height: H * 0.03))
        ctx.fillEllipse(in: CGRect(x: cx + bodyW * 0.06, y: bodyBottom - H * 0.008,
                                   width: bodyW * 0.24, height: H * 0.03))

        // Two arms.
        fill(0.16, 0.66, 0.62)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.60, y: bodyBottom + bodyH * 0.40,
                                   width: bodyW * 0.22, height: bodyH * 0.30))
        ctx.fillEllipse(in: CGRect(x: cx + bodyW * 0.38, y: bodyBottom + bodyH * 0.40,
                                   width: bodyW * 0.22, height: bodyH * 0.30))

        // Eyes.
        let eyeY = bodyBottom + bodyH * 0.70
        fill(1, 1, 1)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.22, y: eyeY, width: bodyW * 0.18, height: bodyW * 0.18))
        ctx.fillEllipse(in: CGRect(x: cx + bodyW * 0.04, y: eyeY, width: bodyW * 0.18, height: bodyW * 0.18))
        fill(0.10, 0.12, 0.14)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.16, y: eyeY + bodyW * 0.03, width: bodyW * 0.08, height: bodyW * 0.08))
        ctx.fillEllipse(in: CGRect(x: cx + bodyW * 0.10, y: eyeY + bodyW * 0.03, width: bodyW * 0.08, height: bodyW * 0.08))

        // A single top horn/antenna with a coral tip — silhouette interest.
        fill(0.16, 0.66, 0.62)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.04, y: bodyTop - bodyH * 0.02,
                                   width: bodyW * 0.10, height: bodyH * 0.14))
        fill(0.945, 0.298, 0.361)
        ctx.fillEllipse(in: CGRect(x: cx - bodyW * 0.055, y: bodyTop + bodyH * 0.08,
                                   width: bodyW * 0.13, height: bodyW * 0.13))

        // A smile.
        ctx.setStrokeColor(CGColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1))
        ctx.setLineWidth(W * 0.012)
        ctx.setLineCap(.round)
        let mouthY = bodyBottom + bodyH * 0.56
        ctx.addArc(center: CGPoint(x: cx - bodyW * 0.02, y: mouthY + bodyW * 0.10),
                   radius: bodyW * 0.14, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        ctx.strokePath()

        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}
