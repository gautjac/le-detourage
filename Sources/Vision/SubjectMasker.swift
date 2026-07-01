import Foundation
import Vision
import CoreImage
import CoreGraphics

/// Shared, always-available subject extraction built on Vision's foreground
/// instance mask (`VNGenerateForegroundInstanceMaskRequest`). This is the
/// fallback path used on macOS where VisionKit's press-and-lift interaction
/// isn't offered, and anywhere `ImageAnalysisInteraction` can't produce a
/// subject — so a cutout can always be made.
///
/// The result is a tightly-cropped, transparent-background `PlatformImage`
/// containing just the subject pixels.
enum SubjectMasker {

    /// Errors that stop a cut-out.
    enum MaskError: Error { case noSubject, badImage }

    /// A shared Core Image context. Software rendering keeps it robust on the
    /// simulator and headless test hosts.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Extract the most prominent subject(s) from an image and return them as a
    /// cropped, transparent cutout. Runs off the main actor.
    static func lift(from image: PlatformImage) async throws -> PlatformImage {
        guard let cg = image.cgImageNormalized else { throw MaskError.badImage }
        return try await lift(fromCGImage: cg)
    }

    static func lift(fromCGImage cg: CGImage) async throws -> PlatformImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try synchronousLift(cg: cg)
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The synchronous core, exposed for testing.
    static func synchronousLift(cg: CGImage) throws -> PlatformImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first,
              !result.allInstances.isEmpty else {
            throw MaskError.noSubject
        }

        // Composite ALL detected instances into one mask so multi-subject photos
        // (e.g. two people) come out as a single rich cutout.
        let maskedBuffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: true)

        let ci = CIImage(cvPixelBuffer: maskedBuffer)
        let extent = ci.extent
        guard extent.width >= 1, extent.height >= 1,
              let outCG = ciContext.createCGImage(ci, from: extent) else {
            throw MaskError.noSubject
        }
        return PlatformImage.from(cgImage: outCG)
    }

    /// Trim fully-transparent margins from an already-transparent cutout and
    /// return a tightly-cropped copy. Used to clean up VisionKit lifts too.
    /// Returns the original if it's already tight or fully opaque.
    static func trimTransparentMargins(_ image: PlatformImage) -> PlatformImage {
        guard let cg = image.cgImageNormalized else { return image }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0,
              let ci = Optional(CIImage(cgImage: cg)) else { return image }
        // Use Core Image to find the non-transparent bounds via the alpha channel.
        // Fall back to the original if anything is off.
        let context = ciContext
        guard let data = context.pngRepresentation(of: ci,
                                                    format: .RGBA8,
                                                    colorSpace: CGColorSpaceCreateDeviceRGB()),
              let src = PlatformImage(data: data)?.cgImageNormalized else {
            return image
        }
        guard let bounds = alphaBounds(of: src) else { return image }
        // Already tight?
        if bounds.origin.x == 0, bounds.origin.y == 0,
           Int(bounds.width) == w, Int(bounds.height) == h {
            return image
        }
        guard let cropped = src.cropping(to: bounds) else { return image }
        return PlatformImage.from(cgImage: cropped)
    }

    /// The bounding box of non-transparent pixels in a CGImage, or nil if the
    /// image is fully transparent. Exposed for testing.
    static func alphaBounds(of cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: h * bytesPerRow)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &pixels, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: space, bitmapInfo: info) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowBase = y * bytesPerRow
            for x in 0..<w {
                let a = pixels[rowBase + x * bytesPerPixel + 3]
                if a > 12 { // ignore near-transparent fringe
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // CGImage origin is top-left for cropping.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
