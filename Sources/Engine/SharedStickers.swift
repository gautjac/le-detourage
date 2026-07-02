import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Mirrors the drawer's cutouts into a shared App Group container so the iMessage
/// sticker extension can present them. A no-op where no app group is available
/// (e.g. macOS), so callers don't need to branch.
enum SharedStickers {
    static let appGroupID = "group.com.jac.LeDetourage"

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Stickers", isDirectory: true)
    }

    /// Replace the shared folder with the current drawer cutouts (downscaled to a
    /// sticker-friendly size). Safe to call off the main actor.
    static func sync(_ items: [(id: UUID, data: Data)]) {
        guard let dir = directory else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for existing in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: existing)
        }
        for item in items {
            guard let png = stickerPNG(from: item.data) else { continue }
            let url = dir.appendingPathComponent(item.id.uuidString).appendingPathExtension("png")
            try? png.write(to: url)
        }
    }

    /// Downscale a cutout PNG to Messages' recommended sticker size, preserving
    /// alpha, and keep it well under the size limit.
    static func stickerPNG(from data: Data, maxEdge: CGFloat = 512) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return data }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return data }
        return out as Data
    }
}
