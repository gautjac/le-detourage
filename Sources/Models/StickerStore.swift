import Foundation
import SwiftData
import CoreGraphics

/// A cutout saved to the drawer (SwiftData). Holds the transparent PNG bytes of
/// a lifted subject plus a little metadata for display and sorting.
@Model
final class SavedSticker {
    /// Stable identifier used when placing copies on the canvas.
    var id: UUID
    /// Transparent PNG bytes of the lifted subject.
    @Attribute(.externalStorage) var pngData: Data
    /// When it was cut out (drawer is sorted newest-first).
    var createdAt: Date
    /// Pixel width/height of the cutout, cached so we can size placements
    /// without decoding the image.
    var pixelWidth: Double
    var pixelHeight: Double
    /// The palette accent this sticker was tagged with (index into Theme.palette),
    /// purely cosmetic for the drawer tiles.
    var accentIndex: Int

    init(id: UUID = UUID(),
         pngData: Data,
         createdAt: Date = Date(),
         pixelWidth: Double,
         pixelHeight: Double,
         accentIndex: Int = 0) {
        self.id = id
        self.pngData = pngData
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.accentIndex = accentIndex
    }

    /// Aspect ratio (width / height), clamped away from zero.
    var aspect: Double {
        guard pixelHeight > 0 else { return 1 }
        return pixelWidth / pixelHeight
    }
}
