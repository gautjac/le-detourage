import SwiftUI
import CoreGraphics

#if os(macOS)
import AppKit
/// The platform's bitmap image type (AppKit on macOS).
typealias PlatformImage = NSImage
/// The platform's font type (AppKit on macOS).
typealias PlatformFont = NSFont
/// The platform's color type (AppKit on macOS).
typealias PlatformColor = NSColor
#else
import UIKit
/// The platform's bitmap image type (UIKit on iOS).
typealias PlatformImage = UIImage
/// The platform's font type (UIKit on iOS).
typealias PlatformFont = UIFont
/// The platform's color type (UIKit on iOS).
typealias PlatformColor = UIColor
#endif

extension Image {
    /// Build a SwiftUI `Image` from a `PlatformImage`, bridging UIKit/AppKit so
    /// the views stay identical across the universal app.
    init(platform image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }

    /// Build from raw encoded image bytes (PNG/JPEG). Returns nil if undecodable.
    init?(platformData data: Data) {
        guard let image = PlatformImage(data: data) else { return nil }
        self.init(platform: image)
    }
}

extension PlatformImage {
    /// The backing `CGImage`, normalized so downstream pixel work sees an
    /// upright bitmap regardless of EXIF orientation.
    var cgImageNormalized: CGImage? {
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let upright = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return upright.cgImage
        #endif
    }

    /// Pixel dimensions of the underlying bitmap (not point size).
    var pixelSize: CGSize {
        if let cg = cgImageNormalized {
            return CGSize(width: cg.width, height: cg.height)
        }
        return size
    }

    /// Wrap a `CGImage` as a `PlatformImage`.
    static func from(cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    /// Encode as PNG bytes for persistence / export (preserves alpha).
    var pngData: Data? {
        #if os(macOS)
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return pngData()
        #endif
    }
}

// MARK: - Cross-platform haptic tap (a no-op on macOS)

@MainActor
enum Haptics {
    static func tap() {
        #if os(iOS)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        #endif
    }
}
