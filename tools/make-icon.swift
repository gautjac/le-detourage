// Renders the Le Détourage app icon master PNG.
// Usage: swift make-icon.swift <output.png>
//
// Identity: a bright scrapbook / cut-and-paste atelier. A stack of torn-paper
// cutouts with sticker drop-shadows on a warm cream ground, and a pair of
// scissors — the gesture of détourage (cutting the subject out).
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Warm cream ground.
ctx.setFillColor(rgb(0.965, 0.933, 0.898))
ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// A faint grid of ledger dots for the scrapbook-page feel.
ctx.setFillColor(rgb(0.90, 0.86, 0.80))
let spacing = 72.0
var yy = 44.0
while yy < Double(S) {
    var xx = 44.0
    while xx < Double(S) {
        ctx.fillEllipse(in: CGRect(x: xx - 4, y: yy - 4, width: 8, height: 8))
        xx += spacing
    }
    yy += spacing
}

// A torn-paper cutout: an irregular rounded blob with a jagged deckle edge,
// drawn with a soft drop-shadow so it reads as a sticker peeled onto the page.
func tornCutout(center: CGPoint, radius: Double, fill: CGColor, seed: UInt64, rot: Double) {
    var rng = SplitMix64(seed: seed)
    let n = 26
    var pts: [CGPoint] = []
    for i in 0..<n {
        let a = (Double(i) / Double(n)) * 2 * .pi + rot
        // Torn edge: radius wobbles.
        let wob = 1.0 + (rng.nextUnit() - 0.5) * 0.20
        let rr = radius * wob
        pts.append(CGPoint(x: center.x + cos(a) * rr, y: center.y + sin(a) * rr))
    }
    let path = CGMutablePath()
    path.move(to: pts[0])
    for p in pts.dropFirst() { path.addLine(to: p) }
    path.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                  color: rgb(0.15, 0.10, 0.08, 0.34))
    // White paper backing (the sticker's border), then the color face.
    ctx.addPath(path)
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Inner colored face, slightly inset for a paper-border look.
    let inset = CGMutablePath()
    var ipts: [CGPoint] = []
    for p in pts {
        let dx = p.x - center.x, dy = p.y - center.y
        let d = max(0.0001, hypot(dx, dy))
        let k = (d - 22) / d
        ipts.append(CGPoint(x: center.x + dx * k, y: center.y + dy * k))
    }
    inset.move(to: ipts[0])
    for p in ipts.dropFirst() { inset.addLine(to: p) }
    inset.closeSubpath()
    ctx.addPath(inset)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

// Simple deterministic RNG so the torn edges are stable across renders.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

// Three overlapping cutouts in the bright collage palette.
tornCutout(center: CGPoint(x: 388, y: 420), radius: 250,
           fill: rgb(0.16, 0.66, 0.62), seed: 7, rot: 0.2)          // teal
tornCutout(center: CGPoint(x: 636, y: 560), radius: 232,
           fill: rgb(0.98, 0.78, 0.22), seed: 21, rot: 1.1)         // marigold
tornCutout(center: CGPoint(x: 560, y: 360), radius: 210,
           fill: rgb(0.945, 0.298, 0.361), seed: 42, rot: 2.3)      // coral/red

// Scissors — the gesture of cutting the subject out. Two blades + two bows.
ctx.saveGState()
ctx.translateBy(x: 726, y: 300)
ctx.rotate(by: -0.5)
ctx.setStrokeColor(rgb(0.15, 0.13, 0.12))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
// Blades crossing.
ctx.move(to: CGPoint(x: -120, y: -140)); ctx.addLine(to: CGPoint(x: 40, y: 40))
ctx.move(to: CGPoint(x: 120, y: -140)); ctx.addLine(to: CGPoint(x: -40, y: 40))
ctx.strokePath()
// Bows (finger holes).
ctx.setLineWidth(26)
ctx.strokeEllipse(in: CGRect(x: -96, y: 40, width: 84, height: 84))
ctx.strokeEllipse(in: CGRect(x: 16, y: 40, width: 84, height: 84))
// Pivot.
ctx.setFillColor(rgb(0.15, 0.13, 0.12))
ctx.fillEllipse(in: CGRect(x: -14, y: -14, width: 28, height: 28))
ctx.restoreGState()

// A dashed "cut here" line arcing across the lower-left — the détourage path.
ctx.saveGState()
ctx.setStrokeColor(rgb(0.15, 0.13, 0.12, 0.55))
ctx.setLineWidth(10)
ctx.setLineDash(phase: 0, lengths: [26, 20])
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: 300, y: 520), radius: 300,
           startAngle: 0.6, endAngle: 2.1, clockwise: false)
ctx.strokePath()
ctx.restoreGState()

guard let img = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
