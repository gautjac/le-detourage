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
