import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// A photo effect applied to a lifted cutout. All effects run on-device via Core
/// Image and preserve the cutout's alpha so the subject stays cleanly cut out.
enum CutoutFilter: Int, CaseIterable, Codable, Identifiable {
    case none
    case noir       // high-contrast black & white
    case chrome     // punchy, saturated
    case comic      // pop-art halftone ink
    case vintage    // faded warm instant-film
    case posterize  // flat poster bands

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .none:      return "filter.none"
        case .noir:      return "filter.noir"
        case .chrome:    return "filter.chrome"
        case .comic:     return "filter.comic"
        case .vintage:   return "filter.vintage"
        case .posterize: return "filter.posterize"
        }
    }

    /// The Core Image filter name, or nil for `.none`.
    fileprivate var ciName: String? {
        switch self {
        case .none:      return nil
        case .noir:      return "CIPhotoEffectNoir"
        case .chrome:    return "CIPhotoEffectChrome"
        case .comic:     return "CIComicEffect"
        case .vintage:   return "CIPhotoEffectInstant"
        case .posterize: return "CIColorPosterize"
        }
    }
}

/// The full styled result for a cutout: the (optionally filtered) subject image,
/// plus a die-cut contour outline image and the ratio by which that outline
/// image is larger than the subject (so it can be placed with a uniform border).
struct StyledCutout {
    let subject: PlatformImage
    let outline: PlatformImage?
    /// (outlineWidth/subjectWidth, outlineHeight/subjectHeight).
    let outlineRatio: CGSize
}

/// Applies filters and generates true die-cut contour outlines for cutouts.
/// Both the live canvas and the Core Graphics exporter consume the same styled
/// images, so preview and export match exactly.
enum CutoutStyler {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The outline thickness as a fraction of the cutout's shorter edge.
    static func radiusFraction(for style: StickerStyle) -> CGFloat {
        switch style {
        case .none:  return 0
        case .thin:  return 0.03
        case .thick: return 0.065
        }
    }

    /// Curated outline colors (index 0 = classic white).
    static let outlineColors: [Color] = [
        .white, Theme.ink, Theme.coral, Theme.teal,
        Theme.marigold, Theme.grape, Theme.sky, Theme.leaf,
    ]

    static func outlineColor(_ index: Int) -> Color {
        outlineColors[min(max(0, index), outlineColors.count - 1)]
    }

    /// Produce the styled subject + contour outline for a cutout.
    static func style(_ image: PlatformImage, filter: CutoutFilter,
                      style: StickerStyle, outlineColorIndex: Int) -> StyledCutout {
        guard let cg = image.cgImageNormalized else {
            return StyledCutout(subject: image, outline: nil, outlineRatio: CGSize(width: 1, height: 1))
        }
        let subjectCG = applyFilter(cg, filter) ?? cg
        let subject = PlatformImage.from(cgImage: subjectCG)

        let fraction = radiusFraction(for: style)
        guard fraction > 0 else {
            return StyledCutout(subject: subject, outline: nil, outlineRatio: CGSize(width: 1, height: 1))
        }
        let color = outlineColor(outlineColorIndex).cg
        if let (outlineCG, ratio) = makeOutline(cg, radiusFraction: fraction, color: color) {
            return StyledCutout(subject: subject,
                                outline: PlatformImage.from(cgImage: outlineCG),
                                outlineRatio: ratio)
        }
        return StyledCutout(subject: subject, outline: nil, outlineRatio: CGSize(width: 1, height: 1))
    }

    // MARK: Filtering

    private static func applyFilter(_ cg: CGImage, _ filter: CutoutFilter) -> CGImage? {
        guard let name = filter.ciName else { return nil }
        let source = CIImage(cgImage: cg)
        guard let effect = CIFilter(name: name) else { return nil }
        effect.setValue(source, forKey: kCIInputImageKey)
        guard var output = effect.outputImage else { return nil }
        // Effects can drop or ignore alpha — re-key the original alpha back in so
        // the subject stays cut out.
        output = output.cropped(to: source.extent)
        let masked = output.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: source,
        ])
        return context.createCGImage(masked, from: source.extent)
    }

    // MARK: Die-cut outline

    /// A colored, uniform-offset contour of the cutout's alpha, on a canvas grown
    /// by the offset on every side. Returns the outline image and how much larger
    /// it is than the subject on each axis.
    private static func makeOutline(_ cg: CGImage, radiusFraction: CGFloat,
                                    color: CGColor) -> (CGImage, CGSize)? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 0, h > 0 else { return nil }
        let r = max(1, min(w, h) * radiusFraction)

        let source = CIImage(cgImage: cg)
        // Grow the alpha outward uniformly (a true morphological dilation, not a
        // scaled copy — so the border is even thickness everywhere).
        let dilated = source.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
        let inflated = source.extent.insetBy(dx: -r, dy: -r)
        let mask = dilated.cropped(to: inflated)
        let fill = CIImage(color: CIColor(cgColor: color)).cropped(to: inflated)
        let outline = fill.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        guard let outCG = context.createCGImage(outline, from: inflated) else { return nil }
        let ratio = CGSize(width: (w + 2 * r) / w, height: (h + 2 * r) / h)
        return (outCG, ratio)
    }
}
