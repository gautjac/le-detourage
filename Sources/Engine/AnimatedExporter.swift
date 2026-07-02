import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Gives each element a gentle, phase-offset wobble so a static collage becomes a
/// looping "living" animation. Deterministic in `t` (0…1 over one loop) so the
/// last frame flows back into the first.
struct CollageAnimator {
    /// 0 = still, 1 = lively.
    var amount: CGFloat

    func transform(index i: Int, t: CGFloat) -> CollageRenderer.FrameTransform {
        let phase = CGFloat(i) * 0.7
        let w = 2 * CGFloat.pi
        return CollageRenderer.FrameTransform(
            dx: sin(t * w * 0.5 + phase) * 0.008 * amount,
            dy: cos(t * w + phase * 1.3) * 0.012 * amount,
            dRot: sin(t * w + phase) * 0.06 * amount,
            scale: 1 + sin(t * w + phase * 0.6) * 0.03 * amount)
    }
}

/// Renders a collage to a looping animated GIF.
enum AnimatedExporter {
    /// Number of frames in one loop and the playback rate.
    static let frameCount = 18
    static let fps: Double = 12
    /// GIFs stay modest in size; render at a lower resolution than the PNG export.
    static let longEdge: CGFloat = 720

    /// Render one loop's frames (main-actor: the collage is main-actor state).
    @MainActor
    static func frames(for collage: Collage, amount: CGFloat,
                       transparentBackground: Bool) -> [CGImage] {
        let animator = CollageAnimator(amount: amount)
        var out: [CGImage] = []
        for i in 0..<frameCount {
            let t = CGFloat(i) / CGFloat(frameCount)
            if let img = CollageRenderer.render(collage, transparentBackground: transparentBackground,
                                                longEdge: longEdge,
                                                transformProvider: { animator.transform(index: $0, t: t) }),
               let cg = img.cgImageNormalized {
                out.append(cg)
            }
        }
        return out
    }

    /// Assemble frames into a looping GIF.
    static func gif(from frames: [CGImage]) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }

        let fileProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFLoopCount as String: 0]]   // loop forever
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)

        let frameProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFUnclampedDelayTime as String: 1.0 / fps]]
        for frame in frames {
            CGImageDestinationAddImage(dest, frame, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Render + assemble a looping GIF in one call.
    @MainActor
    static func makeGIF(for collage: Collage, amount: CGFloat,
                        transparentBackground: Bool) -> Data? {
        gif(from: frames(for: collage, amount: amount, transparentBackground: transparentBackground))
    }
}
