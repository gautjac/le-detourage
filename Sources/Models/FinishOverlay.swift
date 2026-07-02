import SwiftUI
import CoreGraphics

/// The blend used to composite a finishing overlay, mapped to both backends.
enum OverlayBlend {
    case normal, softLight, screen, multiply
    var cg: CGBlendMode {
        switch self {
        case .normal: return .normal
        case .softLight: return .softLight
        case .screen: return .screen
        case .multiply: return .multiply
        }
    }
    var swiftUI: BlendMode {
        switch self {
        case .normal: return .normal
        case .softLight: return .softLight
        case .screen: return .screen
        case .multiply: return .multiply
        }
    }
}

/// A finishing pass composited over the whole collage — film grain, vignette,
/// light-leak or paper texture. The same generated image + blend + opacity drive
/// the live canvas and the exporter, so preview matches export.
enum FinishOverlay: Int, CaseIterable, Codable, Identifiable {
    case none, grain, vignette, lightLeak, paper

    var id: Int { rawValue }
    var titleKey: String { "finish.\(self)" }

    var blend: OverlayBlend {
        switch self {
        case .none, .vignette: return .normal
        case .grain, .paper: return .softLight
        case .lightLeak: return .screen
        }
    }

    var opacity: Double {
        switch self {
        case .none: return 0
        case .grain: return 0.55
        case .vignette: return 0.7
        case .lightLeak: return 0.7
        case .paper: return 0.45
        }
    }

    /// Generate the overlay image at `size`. Nil for `.none`.
    func image(size: CGSize) -> PlatformImage? {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        switch self {
        case .none:
            return nil
        case .grain:
            return noise(w: min(w, 700), h: min(h, 700), tint: (128, 128, 128), spread: 46)
        case .paper:
            return noise(w: min(w, 500), h: min(h, 500), tint: (150, 142, 128), spread: 20)
        case .vignette:
            return vignette(w: w, h: h)
        case .lightLeak:
            return lightLeak(w: w, h: h)
        }
    }

    // MARK: Generators

    private func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private func noise(w: Int, h: Int, tint: (Int, Int, Int), spread: Int) -> PlatformImage? {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var rng = SeededRNG(seed: UInt64(rawValue + 1) &* 0x9E3779B97F4A7C15)
        for i in 0..<(w * h) {
            let n = Int(rng.unit() * CGFloat(spread * 2)) - spread
            func clamp(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v + n))) }
            pixels[i * 4] = clamp(tint.0)
            pixels[i * 4 + 1] = clamp(tint.1)
            pixels[i * 4 + 2] = clamp(tint.2)
            pixels[i * 4 + 3] = 255
        }
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }

    private func vignette(w: Int, h: Int) -> PlatformImage? {
        guard let ctx = context(w, h) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [CGColor(colorSpace: space, components: [0, 0, 0, 0])!,
                      CGColor(colorSpace: space, components: [0, 0, 0, 1])!] as CFArray
        guard let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0.55, 1]) else { return nil }
        let c = CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        let r = hypot(CGFloat(w), CGFloat(h)) / 2
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r,
                               options: .drawsAfterEndLocation)
        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }

    private func lightLeak(w: Int, h: Int) -> PlatformImage? {
        guard let ctx = context(w, h) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let warm = [CGColor(colorSpace: space, components: [1.0, 0.72, 0.42, 1])!,
                    CGColor(colorSpace: space, components: [1.0, 0.4, 0.5, 0])!] as CFArray
        guard let grad = CGGradient(colorsSpace: space, colors: warm, locations: [0, 1]) else { return nil }
        let c = CGPoint(x: CGFloat(w) * 0.85, y: CGFloat(h) * 0.9)   // top-right corner (y-up)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: hypot(CGFloat(w), CGFloat(h)) * 0.7, options: [])
        guard let cg = ctx.makeImage() else { return nil }
        return PlatformImage.from(cgImage: cg)
    }
}
