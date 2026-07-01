import SwiftUI
import Observation

/// How a placed cutout is decorated to read as a sticker.
enum StickerStyle: String, CaseIterable, Identifiable, Codable {
    case none          // raw cutout, no border
    case thin          // white paper border (classic sticker)
    case thick         // fat white border
    var id: String { rawValue }

    /// The outline thickness in points, at the cutout's placed scale = 1.
    var outlineWidth: CGFloat {
        switch self {
        case .none: return 0
        case .thin: return 8
        case .thick: return 18
        }
    }

    var titleKey: String {
        switch self {
        case .none: return "sticker.none"
        case .thin: return "sticker.outline.white"
        case .thick: return "sticker.outline.thick"
        }
    }
}

/// The collage background choice.
enum CollageBackground: Equatable {
    case color(Color)
    case gradient(Color, Color)
    case photo               // uses `Collage.backgroundImage`
    case transparent

    /// Whether this background contributes any opaque pixels (used to decide
    /// the default export transparency toggle).
    var isTransparent: Bool {
        if case .transparent = self { return true }
        return false
    }
}

/// A single cutout placed on the canvas. Position is stored in **normalized
/// canvas coordinates** (0…1 on both axes, relative to the canvas's shorter
/// edge for scale) so a collage looks the same on iPhone and on a Mac window.
@Observable
final class PlacedSticker: Identifiable {
    let id: UUID
    /// Source drawer sticker id (nil for a one-off lift not yet saved).
    var sourceID: UUID?
    /// The transparent PNG of the cutout.
    var image: PlatformImage
    /// Center position in normalized canvas space (0…1).
    var position: CGPoint
    /// Scale multiplier relative to a base size (see `baseFraction`).
    var scale: CGFloat
    /// Rotation in radians.
    var rotation: CGFloat
    /// Horizontal mirror.
    var flipped: Bool
    /// Decorative sticker border.
    var style: StickerStyle
    /// Drop shadow on/off.
    var shadow: Bool
    /// Draw order — higher is on top.
    var z: Int
    /// Aspect ratio of the source image (w/h).
    let aspect: CGFloat

    /// Base on-canvas footprint as a fraction of the canvas's shorter edge,
    /// before `scale` is applied. Keeps a freshly dropped cutout a comfortable
    /// size regardless of its pixel dimensions.
    static let baseFraction: CGFloat = 0.42

    init(id: UUID = UUID(),
         sourceID: UUID? = nil,
         image: PlatformImage,
         position: CGPoint = CGPoint(x: 0.5, y: 0.5),
         scale: CGFloat = 1,
         rotation: CGFloat = 0,
         flipped: Bool = false,
         style: StickerStyle = .thin,
         shadow: Bool = true,
         z: Int = 0) {
        self.id = id
        self.sourceID = sourceID
        self.image = image
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
        self.style = style
        self.shadow = shadow
        self.z = z
        let px = image.pixelSize
        self.aspect = px.height > 0 ? px.width / px.height : 1
    }

    /// The on-screen size (points) of this cutout for a given canvas size,
    /// honoring aspect ratio, the base fraction, and the user scale.
    func renderSize(in canvas: CGSize) -> CGSize {
        let shorter = min(canvas.width, canvas.height)
        let base = shorter * Self.baseFraction * scale
        // `base` sizes the longer image dimension so wide and tall cutouts feel
        // similarly prominent.
        if aspect >= 1 {
            return CGSize(width: base, height: base / aspect)
        } else {
            return CGSize(width: base * aspect, height: base)
        }
    }

    /// Center point in canvas points.
    func center(in canvas: CGSize) -> CGPoint {
        CGPoint(x: position.x * canvas.width, y: position.y * canvas.height)
    }
}

/// The full collage document: an ordered set of placed cutouts plus a
/// background. Owns the layering/z-order operations and the export math.
@Observable
final class Collage {
    var stickers: [PlacedSticker] = []
    var background: CollageBackground = .color(Theme.page)
    var backgroundImage: PlatformImage?
    /// The canvas aspect ratio (width / height). Square by default; picks up the
    /// device on iPhone but stays authoritative for export dimensions.
    var canvasAspect: CGFloat = 1.0

    private var nextZ: Int = 0

    /// Stickers sorted back-to-front for rendering.
    var ordered: [PlacedSticker] {
        stickers.sorted { $0.z < $1.z }
    }

    var isEmpty: Bool { stickers.isEmpty }

    // MARK: Mutations

    @discardableResult
    func add(image: PlatformImage, sourceID: UUID? = nil,
             at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> PlacedSticker {
        let s = PlacedSticker(sourceID: sourceID, image: image, position: position, z: nextZ)
        nextZ += 1
        // Gentle random flourish so successive drops don't perfectly stack.
        s.rotation = CGFloat.random(in: -0.12...0.12)
        stickers.append(s)
        return s
    }

    func remove(_ sticker: PlacedSticker) {
        stickers.removeAll { $0.id == sticker.id }
    }

    @discardableResult
    func duplicate(_ sticker: PlacedSticker) -> PlacedSticker {
        let copy = PlacedSticker(sourceID: sticker.sourceID,
                                 image: sticker.image,
                                 position: CGPoint(x: min(1, sticker.position.x + 0.06),
                                                   y: min(1, sticker.position.y + 0.06)),
                                 scale: sticker.scale,
                                 rotation: sticker.rotation,
                                 flipped: sticker.flipped,
                                 style: sticker.style,
                                 shadow: sticker.shadow,
                                 z: nextZ)
        nextZ += 1
        stickers.append(copy)
        return copy
    }

    func bringToFront(_ sticker: PlacedSticker) {
        sticker.z = nextZ
        nextZ += 1
    }

    func sendToBack(_ sticker: PlacedSticker) {
        let minZ = (stickers.map { $0.z }.min() ?? 0)
        sticker.z = minZ - 1
    }

    func clear() {
        stickers.removeAll()
        nextZ = 0
    }

    /// Raise `nextZ` above any imported z-values (used after loading).
    func normalizeZ() {
        nextZ = (stickers.map { $0.z }.max() ?? -1) + 1
    }
}
