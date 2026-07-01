import XCTest
import CoreGraphics
@testable import LeDetourage

final class LeDetourageTests: XCTestCase {

    // MARK: Sample image

    func testSampleImageRenders() {
        let img = SampleImage.make(width: 400, height: 500)
        XCTAssertNotNil(img)
        let px = img!.pixelSize
        XCTAssertEqual(px.width, 400, accuracy: 1)
        XCTAssertEqual(px.height, 500, accuracy: 1)
    }

    // MARK: Placed sticker transform math

    func testRenderSizeHonorsBaseFractionAndAspect() {
        // A 2:1 (wide) cutout.
        let cg = solidCutout(width: 200, height: 100)
        let s = PlacedSticker(image: PlatformImage.from(cgImage: cg))
        let canvas = CGSize(width: 1000, height: 1000)
        let size = s.renderSize(in: canvas)
        // Shorter edge 1000 * 0.42 = 420 along the longer (width) dimension.
        XCTAssertEqual(size.width, 420, accuracy: 1)
        XCTAssertEqual(size.height, 210, accuracy: 1)
    }

    func testRenderSizeTallCutout() {
        let cg = solidCutout(width: 100, height: 200) // aspect 0.5
        let s = PlacedSticker(image: PlatformImage.from(cgImage: cg))
        let size = s.renderSize(in: CGSize(width: 800, height: 800))
        // Base sizes the longer (height) dimension: 800*0.42 = 336 tall.
        XCTAssertEqual(size.height, 336, accuracy: 1)
        XCTAssertEqual(size.width, 168, accuracy: 1)
    }

    func testScaleAffectsRenderSize() {
        let cg = solidCutout(width: 100, height: 100)
        let s = PlacedSticker(image: PlatformImage.from(cgImage: cg))
        s.scale = 2
        let size = s.renderSize(in: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(size.width, 840, accuracy: 1)
    }

    func testCenterMapsNormalizedToPoints() {
        let cg = solidCutout(width: 50, height: 50)
        let s = PlacedSticker(image: PlatformImage.from(cgImage: cg),
                              position: CGPoint(x: 0.25, y: 0.75))
        let c = s.center(in: CGSize(width: 400, height: 800))
        XCTAssertEqual(c.x, 100, accuracy: 0.1)
        XCTAssertEqual(c.y, 600, accuracy: 0.1)
    }

    // MARK: Collage layering

    func testAddAssignsIncreasingZ() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let b = collage.add(image: dummy())
        let c = collage.add(image: dummy())
        XCTAssertLessThan(a.z, b.z)
        XCTAssertLessThan(b.z, c.z)
        XCTAssertEqual(collage.ordered.map(\.id), [a.id, b.id, c.id])
    }

    func testBringToFrontAndSendToBack() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        let b = collage.add(image: dummy())
        let c = collage.add(image: dummy())
        collage.bringToFront(a)
        XCTAssertEqual(collage.ordered.last?.id, a.id)
        collage.sendToBack(a)
        XCTAssertEqual(collage.ordered.first?.id, a.id)
        // b and c untouched relative to each other.
        XCTAssertLessThan(b.z, c.z)
    }

    func testDuplicateCopiesTransformAndOffsets() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        a.scale = 1.7
        a.rotation = 0.5
        a.flipped = true
        a.style = .thick
        a.position = CGPoint(x: 0.4, y: 0.4)
        let copy = collage.duplicate(a)
        XCTAssertEqual(copy.scale, a.scale)
        XCTAssertEqual(copy.rotation, a.rotation)
        XCTAssertEqual(copy.flipped, a.flipped)
        XCTAssertEqual(copy.style, a.style)
        XCTAssertGreaterThan(copy.position.x, a.position.x) // offset so it's visible
        XCTAssertGreaterThan(copy.z, a.z)                   // on top
        XCTAssertEqual(collage.stickers.count, 2)
    }

    func testRemoveAndClear() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        _ = collage.add(image: dummy())
        collage.remove(a)
        XCTAssertEqual(collage.stickers.count, 1)
        collage.clear()
        XCTAssertTrue(collage.isEmpty)
    }

    func testNormalizeZRaisesNextZ() {
        let collage = Collage()
        let a = collage.add(image: dummy())
        a.z = 42
        collage.normalizeZ()
        let b = collage.add(image: dummy())
        XCTAssertGreaterThan(b.z, 42)
    }

    // MARK: Sticker style geometry

    func testStyleOutlineWidths() {
        XCTAssertEqual(StickerStyle.none.outlineWidth, 0)
        XCTAssertLessThan(StickerStyle.thin.outlineWidth, StickerStyle.thick.outlineWidth)
    }

    // MARK: Background transparency flag

    func testBackgroundTransparency() {
        XCTAssertTrue(CollageBackground.transparent.isTransparent)
        XCTAssertFalse(CollageBackground.color(.white).isTransparent)
        XCTAssertFalse(CollageBackground.gradient(.white, .black).isTransparent)
        XCTAssertFalse(CollageBackground.photo.isTransparent)
    }

    // MARK: Alpha bounds (fallback crop)

    func testAlphaBoundsFindsSubjectRect() {
        // A 100x100 transparent image with an opaque 20x20 block at (30,40).
        let w = 100, h = 100
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 40..<60 {
            for x in 30..<50 {
                let i = (y * w + x) * 4
                pixels[i] = 255; pixels[i+1] = 0; pixels[i+2] = 0; pixels[i+3] = 255
            }
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        let bounds = SubjectMasker.alphaBounds(of: cg)
        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds!.origin.x, 30, accuracy: 0.5)
        XCTAssertEqual(bounds!.origin.y, 40, accuracy: 0.5)
        XCTAssertEqual(bounds!.width, 20, accuracy: 0.5)
        XCTAssertEqual(bounds!.height, 20, accuracy: 0.5)
    }

    func testAlphaBoundsNilForFullyTransparent() {
        let w = 20, h = 20
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        XCTAssertNil(SubjectMasker.alphaBounds(of: cg))
    }

    // MARK: Collage renderer

    func testRendererProducesImageAtExpectedAspect() {
        let collage = Collage()
        collage.canvasAspect = 1.0
        collage.add(image: dummy())
        let out = CollageRenderer.render(collage, transparentBackground: false)
        XCTAssertNotNil(out)
        let px = out!.pixelSize
        XCTAssertEqual(px.width, px.height, accuracy: 2) // square
        XCTAssertEqual(px.width, CollageRenderer.exportLongEdge, accuracy: 2)
    }

    func testRendererWideAspect() {
        let collage = Collage()
        collage.canvasAspect = 1.5
        collage.add(image: dummy())
        let out = CollageRenderer.render(collage, transparentBackground: true)!
        let px = out.pixelSize
        XCTAssertGreaterThan(px.width, px.height)
        XCTAssertEqual(px.width, CollageRenderer.exportLongEdge, accuracy: 2)
    }

    func testClampedHelper() {
        XCTAssertEqual((5.0).clamped(0, 3), 3)
        XCTAssertEqual((-1.0).clamped(0, 3), 0)
        XCTAssertEqual((2.0).clamped(0, 3), 2)
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
