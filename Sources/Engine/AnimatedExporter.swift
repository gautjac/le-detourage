import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import CoreVideo

/// Drives a collage's per-element animation for a chosen `MotionStyle`.
struct CollageAnimator {
    var style: MotionStyle
    /// 0 = still, 1 = lively.
    var amount: CGFloat

    func transform(index i: Int, t: CGFloat) -> CollageRenderer.FrameTransform {
        style.transform(index: i, t: t, amount: amount)
    }
}

/// Renders a collage to a looping animated GIF or an MP4.
enum AnimatedExporter {
    /// Number of frames in one loop and the playback rate.
    static let frameCount = 18
    static let fps: Double = 12
    /// GIFs stay modest in size; render at a lower resolution than the PNG export.
    static let gifLongEdge: CGFloat = 720

    /// Render one loop's frames (main-actor: the collage is main-actor state).
    @MainActor
    static func frames(for collage: Collage, amount: CGFloat, style: MotionStyle,
                       transparentBackground: Bool, longEdge: CGFloat = gifLongEdge) -> [CGImage] {
        let animator = CollageAnimator(style: style, amount: amount)
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
    static func makeGIF(for collage: Collage, amount: CGFloat, style: MotionStyle,
                        transparentBackground: Bool) -> Data? {
        gif(from: frames(for: collage, amount: amount, style: style,
                         transparentBackground: transparentBackground))
    }

    // MARK: MP4

    /// Render the collage to a looping MP4 written to a temp file (opaque — video
    /// has no alpha). Loops the frame set a few times for a reel-length clip.
    @MainActor
    static func makeMP4(for collage: Collage, amount: CGFloat, style: MotionStyle) async -> URL? {
        let cgs = frames(for: collage, amount: amount, style: style, transparentBackground: false)
        return await encodeMP4(frames: cgs, loops: 3)
    }

    private static func encodeMP4(frames: [CGImage], loops: Int) async -> URL? {
        guard let first = frames.first else { return nil }
        let w = (first.width / 2) * 2, h = (first.height / 2) * 2   // H.264 needs even dims
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("collage-detourage-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return nil }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w, AVVideoHeightKey: h,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
            ])
        guard writer.canAdd(input) else { return nil }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let total = frames.count * max(1, loops)
        for k in 0..<total {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            guard let buffer = pixelBuffer(from: frames[k % frames.count], width: w, height: h,
                                           pool: adaptor.pixelBufferPool) else { continue }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(k), timescale: Int32(fps)))
        }
        input.markAsFinished()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
        return writer.status == .completed ? url : nil
    }

    private static func pixelBuffer(from cg: CGImage, width w: Int, height h: Int,
                                    pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        } else {
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32ARGB,
                                [kCVPixelBufferCGImageCompatibilityKey: true,
                                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        }
        guard let buffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        // Flip so the video's top-left origin matches the CGImage.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buffer
    }
}
