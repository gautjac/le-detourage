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

/// The visual content of a placed element: a lifted transparent cutout, or a
/// text label. Both share the same transform (position/scale/rotation/flip),
/// z-order, shadow and gesture handling — only how they draw differs.
enum ElementKind {
    case cutout(PlatformImage)
    case text(TextContent)
    case shape(Embellishment)
    case sketch(Sketch)
}

/// The collage background choice.
enum CollageBackground: Equatable {
    case color(Color)
    case gradient(Color, Color)
    case pattern(PatternStyle, Color, Color)   // style, base, accent
    case photo               // uses `Collage.backgroundImage`
    case transparent

    /// Whether this background contributes any opaque pixels (used to decide
    /// the default export transparency toggle).
    var isTransparent: Bool {
        if case .transparent = self { return true }
        return false
    }
}

/// A single element placed on the canvas — a cutout or a text label. Position is
/// stored in **normalized canvas coordinates** (0…1 on both axes, relative to
/// the canvas's shorter edge for scale) so a collage looks the same on iPhone
/// and on a Mac window.
@Observable
final class PlacedSticker: Identifiable {
    let id: UUID
    /// Source drawer sticker id (nil for a one-off lift or a text element).
    var sourceID: UUID?
    /// What this element is — a cutout image or a text label.
    var kind: ElementKind
    /// Center position in normalized canvas space (0…1).
    var position: CGPoint
    /// Scale multiplier relative to a base size (see `baseFraction`).
    var scale: CGFloat
    /// Rotation in radians.
    var rotation: CGFloat
    /// Horizontal mirror.
    var flipped: Bool
    /// Decorative sticker border (cutouts only; text uses its own chip).
    var style: StickerStyle
    /// Photo effect applied to a cutout (cutouts only).
    var filter: CutoutFilter
    /// Die-cut outline color, an index into `CutoutStyler.outlineColors`.
    var outlineColorIndex: Int
    /// Drop shadow on/off.
    var shadow: Bool
    /// Draw order — higher is on top.
    var z: Int

    /// Aspect ratio of a cutout's source image (w/h); 1 for text.
    @ObservationIgnored private let cutoutAspect: CGFloat
    /// Lazily-encoded cutout PNG bytes, cached so autosave doesn't re-encode an
    /// unchanged cutout on every keystroke.
    @ObservationIgnored private var cachedCutoutPNG: Data?
    /// Cached styled render (filtered subject + die-cut outline), keyed by the
    /// style inputs so it's only recomputed when they change.
    @ObservationIgnored private var styledKeyCache: String?
    @ObservationIgnored private var styledCache: StyledCutout?

    /// Base on-canvas footprint as a fraction of the canvas's shorter edge,
    /// before `scale` is applied. Keeps a freshly dropped cutout a comfortable
    /// size regardless of its pixel dimensions.
    static let baseFraction: CGFloat = 0.42

    /// Designated init for a **cutout** element. Kept source-compatible with the
    /// original call sites and tests.
    init(id: UUID = UUID(),
         sourceID: UUID? = nil,
         image: PlatformImage,
         position: CGPoint = CGPoint(x: 0.5, y: 0.5),
         scale: CGFloat = 1,
         rotation: CGFloat = 0,
         flipped: Bool = false,
         style: StickerStyle = .thin,
         filter: CutoutFilter = .none,
         outlineColorIndex: Int = 0,
         shadow: Bool = true,
         z: Int = 0) {
        self.id = id
        self.sourceID = sourceID
        self.kind = .cutout(image)
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
        self.style = style
        self.filter = filter
        self.outlineColorIndex = outlineColorIndex
        self.shadow = shadow
        self.z = z
        let px = image.pixelSize
        self.cutoutAspect = px.height > 0 ? px.width / px.height : 1
    }

    /// Init for a **text** element.
    init(id: UUID = UUID(),
         text: TextContent,
         position: CGPoint = CGPoint(x: 0.5, y: 0.5),
         scale: CGFloat = 1,
         rotation: CGFloat = 0,
         flipped: Bool = false,
         shadow: Bool = true,
         z: Int = 0) {
        self.id = id
        self.sourceID = nil
        self.kind = .text(text)
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
        self.style = .none
        self.filter = .none
        self.outlineColorIndex = 0
        self.shadow = shadow
        self.z = z
        self.cutoutAspect = 1
    }

    /// Init for a **sketch** (freehand pencil) element.
    init(id: UUID = UUID(),
         sketch: Sketch,
         position: CGPoint = CGPoint(x: 0.5, y: 0.5),
         scale: CGFloat = 1,
         rotation: CGFloat = 0,
         flipped: Bool = false,
         shadow: Bool = true,
         z: Int = 0) {
        self.id = id
        self.sourceID = nil
        self.kind = .sketch(sketch)
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
        self.style = .none
        self.filter = .none
        self.outlineColorIndex = 0
        self.shadow = shadow
        self.z = z
        self.cutoutAspect = sketch.aspect
    }

    /// Init for an **embellishment** (shape) element.
    init(id: UUID = UUID(),
         shape: Embellishment,
         position: CGPoint = CGPoint(x: 0.5, y: 0.5),
         scale: CGFloat = 1,
         rotation: CGFloat = 0,
         flipped: Bool = false,
         shadow: Bool = true,
         z: Int = 0) {
        self.id = id
        self.sourceID = nil
        self.kind = .shape(shape)
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.flipped = flipped
        self.style = .none
        self.filter = .none
        self.outlineColorIndex = 0
        self.shadow = shadow
        self.z = z
        self.cutoutAspect = shape.shape.aspect
    }

    // MARK: Kind accessors

    var isText: Bool { if case .text = kind { return true }; return false }
    var isShape: Bool { if case .shape = kind { return true }; return false }
    var isSketch: Bool { if case .sketch = kind { return true }; return false }

    /// The embellishment, or nil. Setting it replaces the kind.
    var embellishment: Embellishment? {
        get { if case .shape(let e) = kind { return e }; return nil }
        set { if let value = newValue { kind = .shape(value) } }
    }

    /// The sketch, or nil.
    var sketch: Sketch? {
        if case .sketch(let s) = kind { return s }
        return nil
    }

    /// The cutout image, or nil for a text element.
    var image: PlatformImage? {
        if case .cutout(let img) = kind { return img }
        return nil
    }

    /// The text content, or nil for a cutout. Setting it replaces the kind.
    var text: TextContent? {
        get { if case .text(let t) = kind { return t }; return nil }
        set { if let value = newValue { kind = .text(value) } }
    }

    /// Replace a cutout's pixels (e.g. after edge cleanup), keeping its
    /// transform. Same pixel dimensions are expected, so the aspect is unchanged.
    func replaceCutout(_ image: PlatformImage) {
        guard case .cutout = kind else { return }
        kind = .cutout(image)
        cachedCutoutPNG = nil
        styledKeyCache = nil
        styledCache = nil
    }

    /// The styled render of a cutout (filtered subject + die-cut outline),
    /// computed on demand and cached until the style inputs change. Nil for text.
    var styled: StyledCutout? {
        guard case .cutout(let image) = kind else { return nil }
        let key = "\(filter.rawValue)|\(style.rawValue)|\(outlineColorIndex)"
        if key != styledKeyCache || styledCache == nil {
            styledCache = CutoutStyler.style(image, filter: filter, style: style,
                                             outlineColorIndex: outlineColorIndex)
            styledKeyCache = key
        }
        return styledCache
    }

    /// The cutout's encoded PNG bytes (cached), or nil for text.
    var cutoutPNGData: Data? {
        guard case .cutout(let img) = kind else { return nil }
        if let cached = cachedCutoutPNG { return cached }
        let data = img.pngData
        cachedCutoutPNG = data
        return data
    }

    // MARK: Layout

    /// The on-screen size (points) of this element for a given canvas size.
    func renderSize(in canvas: CGSize) -> CGSize {
        switch kind {
        case .cutout, .shape, .sketch:
            // Cutouts, embellishments and sketches all size the longer dimension
            // to a fraction of the shorter canvas edge (`cutoutAspect` holds each
            // one's aspect), so wide and tall elements feel similarly prominent.
            let shorter = min(canvas.width, canvas.height)
            let base = shorter * Self.baseFraction * scale
            if cutoutAspect >= 1 {
                return CGSize(width: base, height: base / cutoutAspect)
            } else {
                return CGSize(width: base * cutoutAspect, height: base)
            }
        case .text(let content):
            return TextRendering.measure(content, in: canvas, scale: scale)
        }
    }

    /// Center point in canvas points.
    func center(in canvas: CGSize) -> CGPoint {
        CGPoint(x: position.x * canvas.width, y: position.y * canvas.height)
    }
}

/// The full collage document: an ordered set of placed elements plus a
/// background. Owns the layering/z-order operations and the export math.
@Observable
final class Collage {
    var stickers: [PlacedSticker] = []
    var background: CollageBackground = .color(Theme.page)
    var backgroundImage: PlatformImage?
    /// The canvas aspect ratio (width / height). Square by default; picks up the
    /// device on iPhone but stays authoritative for export dimensions.
    var canvasAspect: CGFloat = 1.0
    /// The animation style used by the GIF/MP4 "living collage" export.
    var motion: MotionStyle = .wobble
    /// A finishing pass (grain / vignette / light-leak / paper) over everything.
    var finish: FinishOverlay = .none

    @ObservationIgnored private var nextZ: Int = 0

    /// Stickers sorted back-to-front for rendering.
    var ordered: [PlacedSticker] {
        stickers.sorted { $0.z < $1.z }
    }

    var isEmpty: Bool { stickers.isEmpty }

    /// Whether there is anything to show/export.
    var hasContent: Bool { !stickers.isEmpty }

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

    @discardableResult
    func addText(_ content: TextContent,
                 at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> PlacedSticker {
        let s = PlacedSticker(text: content, position: position, z: nextZ)
        nextZ += 1
        stickers.append(s)
        return s
    }

    @discardableResult
    func addShape(_ embellishment: Embellishment,
                  at position: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> PlacedSticker {
        let s = PlacedSticker(shape: embellishment, position: position, z: nextZ)
        nextZ += 1
        s.rotation = CGFloat.random(in: -0.14...0.14)
        stickers.append(s)
        return s
    }

    @discardableResult
    func addSketch(_ sketch: Sketch, at position: CGPoint = CGPoint(x: 0.5, y: 0.5),
                   scale: CGFloat = 1) -> PlacedSticker {
        let s = PlacedSticker(sketch: sketch, position: position, scale: scale, z: nextZ)
        nextZ += 1
        stickers.append(s)
        return s
    }

    func remove(_ sticker: PlacedSticker) {
        stickers.removeAll { $0.id == sticker.id }
    }

    /// Rebuild a placed element from a decoded DTO (keeps its own z).
    func makeSticker(from e: ElementDTO) -> PlacedSticker? {
        if let sketchContent = e.sketch {
            return PlacedSticker(id: e.id, sketch: sketchContent, position: e.position,
                                 scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                 shadow: e.shadow, z: e.z)
        }
        if let embellishment = e.shape {
            return PlacedSticker(id: e.id, shape: embellishment, position: e.position,
                                 scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                 shadow: e.shadow, z: e.z)
        }
        if let content = e.text {
            return PlacedSticker(id: e.id, text: content, position: e.position,
                                 scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                 shadow: e.shadow, z: e.z)
        }
        if let data = e.pngData, let img = PlatformImage(data: data) {
            return PlacedSticker(id: e.id, sourceID: e.sourceID, image: img,
                                 position: e.position, scale: e.scale, rotation: e.rotation,
                                 flipped: e.flipped, style: e.style, filter: e.filter ?? .none,
                                 outlineColorIndex: e.outlineColorIndex ?? 0, shadow: e.shadow, z: e.z)
        }
        return nil
    }

    /// Add a single element from a DTO on top of the stack (used by paste).
    @discardableResult
    func addElement(from e: ElementDTO) -> PlacedSticker? {
        guard let s = makeSticker(from: e) else { return nil }
        s.z = nextZ
        nextZ += 1
        stickers.append(s)
        return s
    }

    @discardableResult
    func duplicate(_ sticker: PlacedSticker) -> PlacedSticker {
        let copy: PlacedSticker
        let offset = CGPoint(x: min(1, sticker.position.x + 0.06),
                             y: min(1, sticker.position.y + 0.06))
        switch sticker.kind {
        case .cutout(let img):
            copy = PlacedSticker(sourceID: sticker.sourceID, image: img, position: offset,
                                 scale: sticker.scale, rotation: sticker.rotation,
                                 flipped: sticker.flipped, style: sticker.style,
                                 filter: sticker.filter, outlineColorIndex: sticker.outlineColorIndex,
                                 shadow: sticker.shadow, z: nextZ)
        case .text(let content):
            copy = PlacedSticker(text: content, position: offset, scale: sticker.scale,
                                 rotation: sticker.rotation, flipped: sticker.flipped,
                                 shadow: sticker.shadow, z: nextZ)
        case .shape(let embellishment):
            copy = PlacedSticker(shape: embellishment, position: offset, scale: sticker.scale,
                                 rotation: sticker.rotation, flipped: sticker.flipped,
                                 shadow: sticker.shadow, z: nextZ)
        case .sketch(let sketchContent):
            copy = PlacedSticker(sketch: sketchContent, position: offset, scale: sticker.scale,
                                 rotation: sticker.rotation, flipped: sticker.flipped,
                                 shadow: sticker.shadow, z: nextZ)
        }
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

    /// Move one step up the stack, swapping z with the element directly above.
    func moveForward(_ sticker: PlacedSticker) {
        let sorted = ordered
        guard let i = sorted.firstIndex(where: { $0.id == sticker.id }), i < sorted.count - 1 else { return }
        let above = sorted[i + 1]
        let z = sticker.z; sticker.z = above.z; above.z = z
    }

    /// Move one step down the stack, swapping z with the element directly below.
    func moveBackward(_ sticker: PlacedSticker) {
        let sorted = ordered
        guard let i = sorted.firstIndex(where: { $0.id == sticker.id }), i > 0 else { return }
        let below = sorted[i - 1]
        let z = sticker.z; sticker.z = below.z; below.z = z
    }

    func clear() {
        stickers.removeAll()
        nextZ = 0
    }

    /// Raise `nextZ` above any imported z-values (used after loading).
    func normalizeZ() {
        nextZ = (stickers.map { $0.z }.max() ?? -1) + 1
    }

    // MARK: Snapshot (undo/redo)

    /// Capture the full document state by value (images kept by reference — they
    /// are immutable once placed), for the undo history.
    func snapshot() -> CollageSnapshot {
        CollageSnapshot(
            elements: stickers.map { s in
                CollageSnapshot.Element(
                    id: s.id, sourceID: s.sourceID, kind: s.kind,
                    position: s.position, scale: s.scale, rotation: s.rotation,
                    flipped: s.flipped, style: s.style, filter: s.filter,
                    outlineColorIndex: s.outlineColorIndex, shadow: s.shadow, z: s.z)
            },
            background: background,
            backgroundImage: backgroundImage,
            canvasAspect: canvasAspect,
            motion: motion,
            finish: finish,
            nextZ: nextZ)
    }

    /// Restore the document to a previously captured snapshot, rebuilding fresh
    /// element instances (callers re-map any selection by id).
    func restore(_ snapshot: CollageSnapshot) {
        stickers = snapshot.elements.map { e in
            let s: PlacedSticker
            switch e.kind {
            case .cutout(let img):
                s = PlacedSticker(id: e.id, sourceID: e.sourceID, image: img,
                                  position: e.position, scale: e.scale, rotation: e.rotation,
                                  flipped: e.flipped, style: e.style, filter: e.filter,
                                  outlineColorIndex: e.outlineColorIndex, shadow: e.shadow, z: e.z)
            case .text(let content):
                s = PlacedSticker(id: e.id, text: content, position: e.position,
                                  scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                  shadow: e.shadow, z: e.z)
            case .shape(let embellishment):
                s = PlacedSticker(id: e.id, shape: embellishment, position: e.position,
                                  scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                  shadow: e.shadow, z: e.z)
            case .sketch(let sketchContent):
                s = PlacedSticker(id: e.id, sketch: sketchContent, position: e.position,
                                  scale: e.scale, rotation: e.rotation, flipped: e.flipped,
                                  shadow: e.shadow, z: e.z)
            }
            return s
        }
        background = snapshot.background
        backgroundImage = snapshot.backgroundImage
        canvasAspect = snapshot.canvasAspect
        motion = snapshot.motion
        finish = snapshot.finish
        nextZ = snapshot.nextZ
    }
}
