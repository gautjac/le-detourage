import SwiftUI
import CoreGraphics

// MARK: - In-memory snapshot (undo/redo)

/// A cheap, by-value capture of a collage for the undo history. Images are held
/// by reference (they never mutate once placed), so a snapshot is essentially a
/// list of transforms — fast to take on every gesture end.
struct CollageSnapshot {
    struct Element {
        let id: UUID
        let sourceID: UUID?
        let kind: ElementKind
        let position: CGPoint
        let scale: CGFloat
        let rotation: CGFloat
        let flipped: Bool
        let style: StickerStyle
        let filter: CutoutFilter
        let outlineColorIndex: Int
        let shadow: Bool
        let z: Int
    }
    var elements: [Element]
    var background: CollageBackground
    var backgroundImage: PlatformImage?
    var canvasAspect: CGFloat
    var nextZ: Int
}

// MARK: - Codable document (disk / gallery)

/// A serializable RGBA color, so backgrounds and (indirectly) any color state
/// survive to disk without depending on `Color`'s non-Codable-ness.
struct RGBAColor: Codable, Equatable {
    var r, g, b, a: Double
    init(_ color: Color) {
        let (r, g, b, a) = color.rgbaComponents
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// The persisted form of a collage background.
enum BackgroundDTO: Codable {
    case color(RGBAColor)
    case gradient(RGBAColor, RGBAColor)
    case photo
    case transparent

    init(_ bg: CollageBackground) {
        switch bg {
        case .color(let c):        self = .color(RGBAColor(c))
        case .gradient(let a, let b): self = .gradient(RGBAColor(a), RGBAColor(b))
        case .photo:               self = .photo
        case .transparent:         self = .transparent
        }
    }

    var background: CollageBackground {
        switch self {
        case .color(let c):        return .color(c.color)
        case .gradient(let a, let b): return .gradient(a.color, b.color)
        case .photo:               return .photo
        case .transparent:         return .transparent
        }
    }
}

/// The persisted form of one placed element. Cutouts carry their PNG bytes so a
/// saved collage is fully self-contained; text carries its content value.
struct ElementDTO: Codable {
    var id: UUID
    var sourceID: UUID?
    var pngData: Data?
    var text: TextContent?
    var shape: Embellishment?
    var sketch: Sketch?
    var position: CGPoint
    var scale: CGFloat
    var rotation: CGFloat
    var flipped: Bool
    var style: StickerStyle
    // Optional so documents written before filters/outline-color existed still
    // decode (a lost autosave draft would silently drop the whole collage).
    var filter: CutoutFilter?
    var outlineColorIndex: Int?
    var shadow: Bool
    var z: Int
}

/// A fully self-contained, versioned, Codable snapshot of a collage document —
/// used both for the always-on autosave file and for saved gallery collages.
struct CollageDocument: Codable {
    var version: Int
    var elements: [ElementDTO]
    var background: BackgroundDTO
    var backgroundImagePNG: Data?
    var canvasAspect: CGFloat

    init(version: Int = 1,
         elements: [ElementDTO] = [],
         background: BackgroundDTO = .color(RGBAColor(Theme.page)),
         backgroundImagePNG: Data? = nil,
         canvasAspect: CGFloat = 1.0) {
        self.version = version
        self.elements = elements
        self.background = background
        self.backgroundImagePNG = backgroundImagePNG
        self.canvasAspect = canvasAspect
    }
}

extension Collage {
    /// Encode the live collage to a self-contained, serializable document.
    var document: CollageDocument {
        let elements: [ElementDTO] = ordered.map { s in
            ElementDTO(
                id: s.id, sourceID: s.sourceID,
                pngData: s.cutoutPNGData,
                text: s.text,
                shape: s.embellishment,
                sketch: s.sketch,
                position: s.position, scale: s.scale, rotation: s.rotation,
                flipped: s.flipped, style: s.style, filter: s.filter,
                outlineColorIndex: s.outlineColorIndex, shadow: s.shadow, z: s.z)
        }
        return CollageDocument(
            elements: elements,
            background: BackgroundDTO(background),
            backgroundImagePNG: {
                if case .photo = background { return backgroundImage?.pngData }
                return nil
            }(),
            canvasAspect: canvasAspect)
    }

    /// Replace the live collage's contents with a decoded document.
    func load(document: CollageDocument) {
        var rebuilt: [PlacedSticker] = []
        for e in document.elements {
            if let sketchContent = e.sketch {
                let s = PlacedSticker(id: e.id, sketch: sketchContent, position: e.position,
                                      scale: e.scale, rotation: e.rotation,
                                      flipped: e.flipped, shadow: e.shadow, z: e.z)
                rebuilt.append(s)
            } else if let embellishment = e.shape {
                let s = PlacedSticker(id: e.id, shape: embellishment, position: e.position,
                                      scale: e.scale, rotation: e.rotation,
                                      flipped: e.flipped, shadow: e.shadow, z: e.z)
                rebuilt.append(s)
            } else if let content = e.text {
                let s = PlacedSticker(id: e.id, text: content, position: e.position,
                                      scale: e.scale, rotation: e.rotation,
                                      flipped: e.flipped, shadow: e.shadow, z: e.z)
                rebuilt.append(s)
            } else if let data = e.pngData, let img = PlatformImage(data: data) {
                let s = PlacedSticker(id: e.id, sourceID: e.sourceID, image: img,
                                      position: e.position, scale: e.scale, rotation: e.rotation,
                                      flipped: e.flipped, style: e.style,
                                      filter: e.filter ?? .none,
                                      outlineColorIndex: e.outlineColorIndex ?? 0,
                                      shadow: e.shadow, z: e.z)
                rebuilt.append(s)
            }
        }
        stickers = rebuilt
        background = document.background.background
        if case .photo = background, let data = document.backgroundImagePNG {
            backgroundImage = PlatformImage(data: data)
        } else {
            backgroundImage = nil
        }
        canvasAspect = document.canvasAspect
        normalizeZ()
    }
}

// MARK: - Color ↔ components bridge

extension Color {
    /// Resolve to sRGB (r,g,b,a) in 0…1, robust to grayscale color spaces.
    var rgbaComponents: (Double, Double, Double, Double) {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent))
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (Double(r), Double(g), Double(b), Double(a))
        }
        var white: CGFloat = 0
        if UIColor(self).getWhite(&white, alpha: &a) {
            return (Double(white), Double(white), Double(white), Double(a))
        }
        return (0, 0, 0, 1)
        #endif
    }
}
