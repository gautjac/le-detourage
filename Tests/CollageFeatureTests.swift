import XCTest
import CoreGraphics
@testable import LeDetourage

/// Tests for the save/undo/text feature set: text elements, the Codable
/// document round-trip, snapshot/restore, the undo history, and thumbnails.
final class CollageFeatureTests: XCTestCase {

    // MARK: Text elements

    func testAddTextAppendsAboveCutouts() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let t = collage.addText(TextContent(string: "Coucou"))
        XCTAssertTrue(t.isText)
        XCTAssertNil(t.image)
        XCTAssertGreaterThan(t.z, a.z)
        XCTAssertEqual(collage.ordered.map(\.id), [a.id, t.id])
    }

    func testTextElementRenderSizeIsPositive() {
        let collage = Collage()
        let t = collage.addText(TextContent(string: "Bonjour", font: .rounded))
        let size = t.renderSize(in: CGSize(width: 1000, height: 1000))
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        // A longer string is wider at the same scale.
        let long = collage.addText(TextContent(string: "Bonjour tout le monde"))
        XCTAssertGreaterThan(long.renderSize(in: CGSize(width: 1000, height: 1000)).width,
                             size.width)
    }

    func testTextContentCodableRoundTrip() throws {
        let tc = TextContent(string: "x", font: .mono, colorIndex: 5, chip: true, chipColorIndex: 2)
        let data = try JSONEncoder().encode(tc)
        let back = try JSONDecoder().decode(TextContent.self, from: data)
        XCTAssertEqual(back, tc)
    }

    func testTextRasterizesToImage() {
        let content = TextContent(string: "Salut", chip: true)
        let size = CGSize(width: 300, height: 120)
        let img = TextRendering.image(content, size: size, fontSize: 48)
        let px = try! XCTUnwrap(img).pixelSize
        // The bitmap may come back at the display backing scale (crisper text that
        // is later downsampled into the fixed export canvas); assert it is a
        // positive, correctly-proportioned image rather than an exact pixel count.
        XCTAssertGreaterThan(px.width, 0)
        XCTAssertGreaterThan(px.height, 0)
        XCTAssertEqual(px.width / px.height, size.width / size.height, accuracy: 0.05)
    }

    // MARK: Document round-trip

    func testCollageDocumentRoundTripPreservesCutoutAndText() throws {
        let collage = Collage()
        collage.canvasAspect = 1.2
        collage.background = .gradient(.white, .black)

        let cut = collage.add(image: dummy())
        cut.position = CGPoint(x: 0.3, y: 0.4)
        cut.scale = 1.5
        cut.style = .thick
        cut.flipped = true

        let txt = collage.addText(TextContent(string: "Bonjour", font: .serif,
                                              colorIndex: 2, chip: true, chipColorIndex: 3))
        txt.rotation = 0.2

        let data = try JSONEncoder().encode(collage.document)
        let decoded = try JSONDecoder().decode(CollageDocument.self, from: data)
        let restored = Collage()
        restored.load(document: decoded)

        XCTAssertEqual(restored.stickers.count, 2)
        XCTAssertEqual(restored.canvasAspect, 1.2, accuracy: 0.0001)
        if case .gradient = restored.background {} else { XCTFail("background not restored") }

        let text = try XCTUnwrap(restored.stickers.first { $0.isText })
        XCTAssertEqual(text.text?.string, "Bonjour")
        XCTAssertEqual(text.text?.font, .serif)
        XCTAssertEqual(text.text?.chip, true)
        XCTAssertEqual(text.rotation, 0.2, accuracy: 0.0001)

        let cutout = try XCTUnwrap(restored.stickers.first { !$0.isText })
        XCTAssertNotNil(cutout.image)
        XCTAssertEqual(cutout.style, .thick)
        XCTAssertTrue(cutout.flipped)
        XCTAssertEqual(cutout.scale, 1.5, accuracy: 0.0001)
        XCTAssertEqual(cutout.position.x, 0.3, accuracy: 0.0001)
    }

    func testDocumentPreservesLayerOrder() throws {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let b = collage.add(image: dummy())
        collage.sendToBack(b)   // b now under a
        let data = try JSONEncoder().encode(collage.document)
        let decoded = try JSONDecoder().decode(CollageDocument.self, from: data)
        let restored = Collage()
        restored.load(document: decoded)
        XCTAssertEqual(restored.ordered.first?.id, b.id)
        XCTAssertEqual(restored.ordered.last?.id, a.id)
    }

    // MARK: Snapshot / restore

    func testSnapshotRestoreReproducesState() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        a.position = CGPoint(x: 0.2, y: 0.2)
        a.scale = 1.3
        let snap = collage.snapshot()

        // Mutate heavily.
        a.position = CGPoint(x: 0.9, y: 0.9)
        a.scale = 2
        collage.add(image: dummy())
        XCTAssertEqual(collage.stickers.count, 2)

        collage.restore(snap)
        XCTAssertEqual(collage.stickers.count, 1)
        let r = collage.stickers[0]
        XCTAssertEqual(r.id, a.id)
        XCTAssertEqual(r.position.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(r.scale, 1.3, accuracy: 0.0001)
    }

    func testRestoreKeepsAddingAboveRestoredElements() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let snap = collage.snapshot()
        collage.add(image: dummy())
        collage.restore(snap)
        // nextZ must be re-based so a new add lands on top of the restored one.
        let c = collage.add(image: dummy())
        XCTAssertGreaterThan(c.z, a.z)
    }

    // MARK: History

    @MainActor
    func testHistoryUndoRedoCycle() {
        let history = CollageHistory()
        let collage = Collage()
        let a = collage.add(image: dummy())
        a.scale = 1

        XCTAssertFalse(history.canUndo)
        history.record(collage.snapshot())   // capture-before
        a.scale = 2
        XCTAssertTrue(history.canUndo)

        let prev = history.undo(current: collage.snapshot())
        XCTAssertNotNil(prev)
        collage.restore(prev!)
        XCTAssertEqual(collage.stickers[0].scale, 1, accuracy: 0.0001)
        XCTAssertTrue(history.canRedo)

        let next = history.redo(current: collage.snapshot())
        XCTAssertNotNil(next)
        collage.restore(next!)
        XCTAssertEqual(collage.stickers[0].scale, 2, accuracy: 0.0001)
    }

    @MainActor
    func testHistoryDiscardLast() {
        let history = CollageHistory()
        let collage = Collage()
        collage.add(image: dummy())
        history.record(collage.snapshot())
        XCTAssertTrue(history.canUndo)
        history.discardLast()
        XCTAssertFalse(history.canUndo)
    }

    @MainActor
    func testRecordClearsRedo() {
        let history = CollageHistory()
        let collage = Collage()
        collage.add(image: dummy())
        history.record(collage.snapshot())
        _ = history.undo(current: collage.snapshot())
        XCTAssertTrue(history.canRedo)
        history.record(collage.snapshot())  // a new edit forks the timeline
        XCTAssertFalse(history.canRedo)
    }

    // MARK: Cutout styling (filters + die-cut outline)

    func testFilterPreservesSubjectSize() {
        let img = PlatformImage.from(cgImage: solidCutout(width: 120, height: 80))
        let styled = CutoutStyler.style(img, filter: .noir, style: .none, outlineColorIndex: 0)
        XCTAssertNil(styled.outline)                       // no outline for .none
        XCTAssertEqual(styled.subject.pixelSize.width, 120, accuracy: 2)
        XCTAssertEqual(styled.subject.pixelSize.height, 80, accuracy: 2)
    }

    func testDieCutOutlineIsLargerThanSubject() {
        let img = PlatformImage.from(cgImage: solidCutout(width: 120, height: 120))
        let styled = CutoutStyler.style(img, filter: .none, style: .thick, outlineColorIndex: 2)
        let outline = try! XCTUnwrap(styled.outline)
        XCTAssertGreaterThan(outline.pixelSize.width, styled.subject.pixelSize.width)
        XCTAssertGreaterThan(styled.outlineRatio.width, 1)
        XCTAssertGreaterThan(styled.outlineRatio.height, 1)
    }

    func testStyledCacheInvalidatesWhenStyleChanges() {
        let s = PlacedSticker(image: PlatformImage.from(cgImage: solidCutout(width: 100, height: 100)),
                              style: .none)
        XCTAssertNil(s.styled?.outline)
        s.style = .thick
        XCTAssertNotNil(s.styled?.outline)   // recomputed with an outline
    }

    func testDocumentRoundTripPreservesFilterAndOutlineColor() throws {
        let collage = Collage()
        let c = collage.add(image: dummy())
        c.filter = .comic
        c.style = .thick
        c.outlineColorIndex = 4
        let data = try JSONEncoder().encode(collage.document)
        let decoded = try JSONDecoder().decode(CollageDocument.self, from: data)
        let restored = Collage()
        restored.load(document: decoded)
        let el = try XCTUnwrap(restored.stickers.first)
        XCTAssertEqual(el.filter, .comic)
        XCTAssertEqual(el.style, .thick)
        XCTAssertEqual(el.outlineColorIndex, 4)
    }

    /// A document written before filters/outline-color existed must still decode
    /// (otherwise an old autosave draft would be silently dropped on launch).
    func testDocumentDecodesWhenFilterFieldsMissing() throws {
        let collage = Collage()
        let c = collage.add(image: dummy())
        c.filter = .comic
        c.outlineColorIndex = 4
        let data = try JSONEncoder().encode(collage.document)

        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var elements = obj["elements"] as! [[String: Any]]
        elements[0].removeValue(forKey: "filter")
        elements[0].removeValue(forKey: "outlineColorIndex")
        obj["elements"] = elements
        let stripped = try JSONSerialization.data(withJSONObject: obj)

        let decoded = try JSONDecoder().decode(CollageDocument.self, from: stripped)
        let restored = Collage()
        restored.load(document: decoded)
        XCTAssertEqual(restored.stickers.count, 1)
        XCTAssertEqual(restored.stickers[0].filter, .none)        // safely defaulted
        XCTAssertEqual(restored.stickers[0].outlineColorIndex, 0)
    }

    // MARK: Embellishments

    func testAddShapeAppendsEmbellishment() {
        let collage = Collage()
        let s = collage.addShape(Embellishment(shape: .star, colorIndex: 2))
        XCTAssertTrue(s.isShape)
        XCTAssertNil(s.image)
        XCTAssertNil(s.text)
        XCTAssertEqual(s.embellishment?.shape, .star)
        XCTAssertEqual(s.embellishment?.colorIndex, 2)
    }

    func testEveryEmblemRastersToImage() {
        for shape in EmblemShape.allCases {
            let emblem = Embellishment(shape: shape, colorIndex: 0)
            let img = emblem.image(size: CGSize(width: 100, height: 100))
            XCTAssertNotNil(img, "\(shape) failed to render")
        }
    }

    func testWideEmblemRenderSizeIsWide() {
        let collage = Collage()
        let banner = collage.addShape(Embellishment(shape: .banner))
        let size = banner.renderSize(in: CGSize(width: 1000, height: 1000))
        XCTAssertGreaterThan(size.width, size.height)   // banner aspect > 1
    }

    func testEmblemDocumentRoundTrip() throws {
        let collage = Collage()
        let s = collage.addShape(Embellishment(shape: .squiggle, colorIndex: 5))
        s.rotation = 0.3
        let data = try JSONEncoder().encode(collage.document)
        let decoded = try JSONDecoder().decode(CollageDocument.self, from: data)
        let restored = Collage()
        restored.load(document: decoded)
        let el = try XCTUnwrap(restored.stickers.first)
        XCTAssertTrue(el.isShape)
        XCTAssertEqual(el.embellishment?.shape, .squiggle)
        XCTAssertEqual(el.embellishment?.colorIndex, 5)
        XCTAssertEqual(el.rotation, 0.3, accuracy: 0.0001)
    }

    func testMixedDocumentRoundTrip() throws {
        // A collage with all three kinds survives a round-trip intact.
        let collage = Collage()
        collage.add(image: dummy())
        collage.addText(TextContent(string: "Hi"))
        collage.addShape(Embellishment(shape: .heart))
        let data = try JSONEncoder().encode(collage.document)
        let restored = Collage()
        restored.load(document: try JSONDecoder().decode(CollageDocument.self, from: data))
        XCTAssertEqual(restored.stickers.count, 3)
        XCTAssertEqual(restored.stickers.filter { $0.isShape }.count, 1)
        XCTAssertEqual(restored.stickers.filter { $0.isText }.count, 1)
        XCTAssertEqual(restored.stickers.filter { $0.image != nil }.count, 1)
    }

    // MARK: Sketch elements (freehand pencil → transformable element)

    private func sampleSketch() -> Sketch {
        Sketch(strokes: [SketchStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 80)],
                                      colorIndex: 2, width: 6)],
               size: CGSize(width: 120, height: 100))
    }

    func testAddSketchIsAnElement() {
        let collage = Collage()
        let s = collage.addSketch(sampleSketch(), scale: 1.4)
        XCTAssertTrue(s.isSketch)
        XCTAssertNil(s.image)
        XCTAssertNil(s.embellishment)
        XCTAssertEqual(s.sketch, sampleSketch())
        XCTAssertTrue(collage.hasContent)
    }

    func testSketchElementRenderSizeUsesAspect() {
        let collage = Collage()
        let s = collage.addSketch(sampleSketch())   // 120x100 → aspect 1.2 (wide)
        let size = s.renderSize(in: CGSize(width: 1000, height: 1000))
        XCTAssertGreaterThan(size.width, size.height)
    }

    func testSketchBuildTightlyBoundsPageStrokes() {
        let page = [SketchStroke(points: [CGPoint(x: 100, y: 100), CGPoint(x: 180, y: 140)],
                                 colorIndex: 0, width: 8)]
        let built = try! XCTUnwrap(Sketch.build(fromPageStrokes: page))
        // pad = width/2 + 2 = 6 on every side.
        XCTAssertEqual(built.box.width, 80 + 12, accuracy: 1)
        XCTAssertEqual(built.box.height, 40 + 12, accuracy: 1)
        XCTAssertEqual(built.center.x, 140, accuracy: 1)
        XCTAssertEqual(built.center.y, 120, accuracy: 1)
        // Strokes are re-based into local space (min corner → the pad offset).
        XCTAssertEqual(built.sketch.strokes[0].points[0].x, 6, accuracy: 1)
        XCTAssertEqual(built.sketch.strokes[0].points[0].y, 6, accuracy: 1)
    }

    func testSketchBuildReturnsNilForNothing() {
        XCTAssertNil(Sketch.build(fromPageStrokes: []))
    }

    func testSketchRastersToImage() {
        let img = sampleSketch().image(size: CGSize(width: 120, height: 100))
        XCTAssertNotNil(img)
    }

    func testSketchRoundTripsThroughDocument() throws {
        let collage = Collage()
        let s = collage.addSketch(sampleSketch(), at: CGPoint(x: 0.3, y: 0.6), scale: 1.4)
        s.rotation = 0.25
        let data = try JSONEncoder().encode(collage.document)
        let restored = Collage()
        restored.load(document: try JSONDecoder().decode(CollageDocument.self, from: data))
        let el = try XCTUnwrap(restored.stickers.first)
        XCTAssertTrue(el.isSketch)
        XCTAssertEqual(el.sketch, sampleSketch())
        XCTAssertEqual(el.scale, 1.4, accuracy: 0.0001)
        XCTAssertEqual(el.rotation, 0.25, accuracy: 0.0001)
    }

    // MARK: Brush textures

    func testBrushCatalogHasTen() {
        XCTAssertEqual(Brush.allCases.count, 10)
    }

    func testEveryBrushProducesOps() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 90, y: 0)]
        for brush in Brush.allCases {
            let ops = brushOps(brush: brush, points: pts, width: 8, color: .red)
            XCTAssertFalse(ops.isEmpty, "\(brush) produced no ops")
        }
    }

    func testSeededRNGIsDeterministic() {
        var a = SeededRNG(seed: 123), b = SeededRNG(seed: 123)
        XCTAssertEqual(a.unit(), b.unit(), accuracy: 0.0)
        XCTAssertEqual(a.unit(), b.unit(), accuracy: 0.0)
    }

    func testTexturedBrushIsDeterministic() {
        // The same stroke must expand to the same jittered dabs every time, so
        // the live preview and the export match.
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 90, y: 0)]
        let a = brushOps(brush: .crayon, points: pts, width: 8, color: .red)
        let b = brushOps(brush: .crayon, points: pts, width: 8, color: .red)
        XCTAssertEqual(a.count, b.count)
        XCTAssertEqual(firstDotX(a), firstDotX(b))
    }

    func testStrokeBrushRoundTrips() throws {
        let stroke = SketchStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)],
                                  colorIndex: 3, width: 5, brush: .neon)
        let decoded = try JSONDecoder().decode(SketchStroke.self, from: JSONEncoder().encode(stroke))
        XCTAssertEqual(decoded.brush, .neon)
    }

    func testStrokeDecodesWithoutBrushField() throws {
        // Sketches saved before brushes existed default to the marker.
        let stroke = SketchStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)],
                                  colorIndex: 0, width: 5, brush: .neon)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stroke)) as! [String: Any]
        obj.removeValue(forKey: "brush")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(SketchStroke.self, from: stripped)
        XCTAssertEqual(decoded.brush, .marker)
    }

    private func firstDotX(_ ops: [BrushOp]) -> CGFloat {
        for op in ops { if case let .dot(center, _, _, _) = op { return center.x } }
        return .nan
    }

    // MARK: Snapping

    func testSnapsToCanvasCenter() {
        let canvas = CGSize(width: 1000, height: 1000)
        let size = CGSize(width: 100, height: 100)
        // 503 is within 8pt of the center (500) → snaps.
        let r = Snapping.snap(center: CGPoint(x: 503, y: 700), size: size, canvas: canvas, others: [])
        XCTAssertEqual(r.center.x, 500, accuracy: 0.001)
        XCTAssertTrue(r.guides.contains(AlignmentGuide(axis: .vertical, position: 500)))
    }

    func testSnapsFlushToCanvasEdge() {
        let canvas = CGSize(width: 1000, height: 1000)
        let size = CGSize(width: 200, height: 200)
        // Center near x=100 → element left edge near 0 → flush-left snap (center→100).
        let r = Snapping.snap(center: CGPoint(x: 104, y: 500), size: size, canvas: canvas, others: [])
        XCTAssertEqual(r.center.x, 100, accuracy: 0.001)    // half of width
        XCTAssertTrue(r.guides.contains(AlignmentGuide(axis: .vertical, position: 0)))
    }

    func testSnapsToNeighborCenter() {
        let canvas = CGSize(width: 1000, height: 1000)
        let size = CGSize(width: 80, height: 80)
        let neighbor = Snapping.Neighbor(center: CGPoint(x: 300, y: 620), size: CGSize(width: 80, height: 80))
        let r = Snapping.snap(center: CGPoint(x: 305, y: 616), size: size, canvas: canvas, others: [neighbor])
        XCTAssertEqual(r.center.x, 300, accuracy: 0.001)
        XCTAssertEqual(r.center.y, 620, accuracy: 0.001)
    }

    func testNoSnapWhenFar() {
        let canvas = CGSize(width: 1000, height: 1000)
        let size = CGSize(width: 100, height: 100)
        let r = Snapping.snap(center: CGPoint(x: 320, y: 660), size: size, canvas: canvas, others: [])
        XCTAssertEqual(r.center.x, 320, accuracy: 0.001)
        XCTAssertEqual(r.center.y, 660, accuracy: 0.001)
        XCTAssertTrue(r.guides.isEmpty)
    }

    // MARK: Patterns & finish overlays

    func testEveryPatternRenders() {
        for style in PatternStyle.allCases {
            XCTAssertNotNil(style.image(size: CGSize(width: 200, height: 150),
                                        base: .white, accent: .red), "\(style)")
        }
    }

    func testFinishOverlaysRender() {
        for f in FinishOverlay.allCases where f != .none {
            XCTAssertNotNil(f.image(size: CGSize(width: 200, height: 150)), "\(f)")
        }
        XCTAssertNil(FinishOverlay.none.image(size: CGSize(width: 100, height: 100)))
    }

    func testPatternAndFinishRoundTripThroughDocument() throws {
        let c = Collage()
        c.background = .pattern(.confetti, Theme.page, Theme.coral)
        c.finish = .vignette
        c.add(image: dummy())
        let c2 = Collage()
        c2.load(document: try JSONDecoder().decode(CollageDocument.self,
                                                   from: try JSONEncoder().encode(c.document)))
        if case .pattern(let s, _, _) = c2.background { XCTAssertEqual(s, .confetti) }
        else { XCTFail("pattern not restored") }
        XCTAssertEqual(c2.finish, .vignette)
    }

    // MARK: Cutout cleanup

    private func opaqueImage(_ w: Int, _ h: Int) -> PlatformImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return PlatformImage.from(cgImage: ctx.makeImage()!)
    }

    private func transparentPixelCount(_ image: PlatformImage) -> Int {
        let cg = image.cgImageNormalized!
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return stride(from: 3, to: px.count, by: 4).reduce(0) { px[$1] < 10 ? $0 + 1 : $0 }
    }

    func testEraseClearsSomePixels() {
        let img = opaqueImage(100, 100)
        XCTAssertEqual(transparentPixelCount(img), 0)
        let erased = CutoutCleanup.erase(img, points: [CGPoint(x: 50, y: 50)], radiusPx: 14)!
        XCTAssertEqual(erased.pixelSize.width, 100, accuracy: 1)
        let cleared = transparentPixelCount(erased)
        XCTAssertGreaterThan(cleared, 0)           // erased a hole
        XCTAssertLessThan(cleared, 100 * 100)      // but not everything
    }

    func testFeatherKeepsSize() {
        let f = CutoutCleanup.feather(opaqueImage(80, 60))!
        XCTAssertEqual(f.pixelSize.width, 80, accuracy: 1)
        XCTAssertEqual(f.pixelSize.height, 60, accuracy: 1)
    }

    func testReplaceCutoutSwapsImage() {
        let sticker = PlacedSticker(image: opaqueImage(50, 50), style: .thick)
        let newImage = opaqueImage(50, 50)
        sticker.replaceCutout(newImage)
        XCTAssertTrue(sticker.image === newImage)
        XCTAssertNotNil(sticker.styled?.outline)   // still a styled cutout after swap
    }

    // MARK: Animated export

    func testAllMotionStylesLoopSeamlessly() {
        for style in MotionStyle.allCases {
            let f0 = style.transform(index: 3, t: 0, amount: 1)
            let f1 = style.transform(index: 3, t: 1, amount: 1)
            XCTAssertEqual(f0.dx, f1.dx, accuracy: 0.0001, "\(style) dx")
            XCTAssertEqual(f0.dy, f1.dy, accuracy: 0.0001, "\(style) dy")
            XCTAssertEqual(f0.dRot, f1.dRot, accuracy: 0.0001, "\(style) dRot")
            XCTAssertEqual(f0.scale, f1.scale, accuracy: 0.0001, "\(style) scale")
        }
    }

    func testMotionAmountZeroIsIdentity() {
        let f = MotionStyle.wobble.transform(index: 1, t: 0.3, amount: 0)
        XCTAssertEqual(f.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dRot, 0, accuracy: 0.0001)
        XCTAssertEqual(f.scale, 1, accuracy: 0.0001)
    }

    func testMotionRoundTripsThroughDocument() throws {
        let c = Collage(); c.motion = .parallax; c.add(image: dummy())
        let c2 = Collage()
        c2.load(document: try JSONDecoder().decode(CollageDocument.self,
                                                   from: try JSONEncoder().encode(c.document)))
        XCTAssertEqual(c2.motion, .parallax)
    }

    @MainActor
    func testMakesAnimatedGIFData() {
        let collage = Collage(); collage.canvasAspect = 1
        collage.add(image: dummy())
        collage.addText(TextContent(string: "Hi"))
        let data = AnimatedExporter.makeGIF(for: collage, amount: 0.7, style: .float,
                                            transparentBackground: false)
        XCTAssertNotNil(data)
        XCTAssertEqual(Array(data!.prefix(3)), Array("GIF".utf8))   // GIF magic header
    }

    @MainActor
    func testMakesMP4File() async {
        let collage = Collage(); collage.canvasAspect = 1
        collage.add(image: dummy())
        let url = await AnimatedExporter.makeMP4(for: collage, amount: 0.7, style: .wobble)
        XCTAssertNotNil(url)
        if let url {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 0)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Multi-select / group ops

    func testGroupAlignCenterH() {
        let c = Collage(); c.canvasAspect = 1
        let a = c.add(image: dummy()); a.position = CGPoint(x: 0.2, y: 0.5)
        let b = c.add(image: dummy()); b.position = CGPoint(x: 0.8, y: 0.5)
        c.align([a.id, b.id], .centerH)
        XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.0001)
    }

    func testGroupScaleAroundCentroid() {
        let c = Collage(); c.canvasAspect = 1
        let a = c.add(image: dummy()); a.position = CGPoint(x: 0.4, y: 0.5); a.scale = 1
        let b = c.add(image: dummy()); b.position = CGPoint(x: 0.6, y: 0.5); b.scale = 1
        c.scaleSelected([a.id, b.id], by: 2)
        XCTAssertEqual(a.position.x, 0.3, accuracy: 0.0001)   // centroid 0.5, doubled offset
        XCTAssertEqual(b.position.x, 0.7, accuracy: 0.0001)
        XCTAssertEqual(a.scale, 2, accuracy: 0.0001)
    }

    func testDuplicateSelectedReturnsFreshIDs() {
        let c = Collage()
        let a = c.add(image: dummy()); let b = c.add(image: dummy())
        let copies = c.duplicateSelected([a.id, b.id])
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(c.stickers.count, 4)
        XCTAssertFalse(copies.contains(a.id))
    }

    func testRemoveSelected() {
        let c = Collage()
        let a = c.add(image: dummy()); let b = c.add(image: dummy()); c.add(image: dummy())
        c.removeSelected([a.id, b.id])
        XCTAssertEqual(c.stickers.count, 1)
    }

    func testAddElementFromDTO() {
        let c = Collage()
        let a = c.add(image: dummy()); a.filter = .noir
        let dto = c.document.elements.first!
        let c2 = Collage()
        let added = c2.addElement(from: dto)
        XCTAssertNotNil(added)
        XCTAssertEqual(c2.stickers.count, 1)
        XCTAssertEqual(added?.filter, .noir)
    }

    @MainActor
    func testSelectionSetterSyncsWithSet() {
        let session = Session()
        let a = session.collage.add(image: dummy())
        session.selection = a
        XCTAssertEqual(session.selectedIDs, [a.id])
        XCTAssertEqual(session.selection?.id, a.id)
        session.selectedIDs = [a.id, UUID()]
        XCTAssertNil(session.selection)      // multiple selected → no single selection
        XCTAssertTrue(session.isMultiSelect)
    }

    // MARK: Canvas formats

    func testCanvasFormatMatching() {
        XCTAssertEqual(CanvasFormat.matching(1.0)?.id, "square")
        XCTAssertEqual(CanvasFormat.matching(9.0 / 16.0)?.id, "story")
        XCTAssertEqual(CanvasFormat.matching(16.0 / 9.0)?.id, "landscape")
        XCTAssertNil(CanvasFormat.matching(3.14))
    }

    @MainActor
    func testSetCanvasAspectIsUndoable() {
        let session = Session()
        session.collage.canvasAspect = 1
        session.setCanvasAspect(1.5)
        XCTAssertEqual(session.collage.canvasAspect, 1.5, accuracy: 0.0001)
        session.undo()
        XCTAssertEqual(session.collage.canvasAspect, 1, accuracy: 0.0001)
    }

    // MARK: Step-wise layering (handles)

    func testMoveForwardAndBackwardStepByOne() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let b = collage.add(image: dummy())
        let c = collage.add(image: dummy())
        XCTAssertEqual(collage.ordered.map(\.id), [a.id, b.id, c.id])

        collage.moveForward(a)      // a ↔ b
        XCTAssertEqual(collage.ordered.map(\.id), [b.id, a.id, c.id])

        collage.moveBackward(c)     // c ↔ a
        XCTAssertEqual(collage.ordered.map(\.id), [b.id, c.id, a.id])

        // The top can't move further forward; the bottom can't move further back.
        let top = collage.ordered.last!
        collage.moveForward(top)
        XCTAssertEqual(collage.ordered.last?.id, top.id)
        let bottom = collage.ordered.first!
        collage.moveBackward(bottom)
        XCTAssertEqual(collage.ordered.first?.id, bottom.id)
    }

    // MARK: Thumbnails

    func testThumbnailHonorsLongEdge() {
        let collage = Collage()
        collage.canvasAspect = 1
        collage.add(image: dummy())
        let out = CollageRenderer.render(collage, transparentBackground: false, longEdge: 256)
        XCTAssertNotNil(out)
        XCTAssertEqual(out!.pixelSize.width, 256, accuracy: 2)
    }

    func testRendererComposesTextElements() {
        let collage = Collage()
        collage.canvasAspect = 1
        collage.addText(TextContent(string: "Allô", chip: true))
        let out = CollageRenderer.render(collage, transparentBackground: true, longEdge: 512)
        XCTAssertNotNil(out)
        XCTAssertEqual(out!.pixelSize.width, 512, accuracy: 2)
    }

    // MARK: Helpers

    private func solidCutout(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func dummy() -> PlatformImage {
        PlatformImage.from(cgImage: solidCutout(width: 60, height: 60))
    }
}
