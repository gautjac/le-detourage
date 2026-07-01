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
