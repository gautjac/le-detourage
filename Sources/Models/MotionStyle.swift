import SwiftUI
import CoreGraphics

/// A looping animation style for the "living collage" export. Each maps a
/// normalized loop time `t` (0…1) and an element index to a per-element
/// `FrameTransform`. Every style uses sin/cos of `2πt`, so the last frame flows
/// seamlessly back into the first.
enum MotionStyle: Int, CaseIterable, Codable, Identifiable {
    case wobble, float, spin, pop, drift, sway, parallax

    var id: Int { rawValue }
    var titleKey: String { "motion.\(self)" }

    func transform(index i: Int, t: CGFloat, amount a: CGFloat) -> CollageRenderer.FrameTransform {
        let phase = CGFloat(i) * 0.7
        let w = 2 * CGFloat.pi
        switch self {
        case .wobble:
            return .init(dx: sin(t * w + phase * 1.7) * 0.008 * a,
                         dy: cos(t * w + phase * 1.3) * 0.012 * a,
                         dRot: sin(t * w + phase) * 0.06 * a,
                         scale: 1 + sin(t * w + phase * 0.6) * 0.03 * a)
        case .float:
            return .init(dx: 0, dy: sin(t * w + phase) * 0.022 * a,
                         dRot: sin(t * w + phase) * 0.02 * a,
                         scale: 1 + sin(t * w + phase) * 0.015 * a)
        case .spin:
            return .init(dRot: sin(t * w + phase) * 0.22 * a)
        case .pop:
            let p = (sin(t * w + phase) + 1) / 2
            return .init(scale: 1 + p * 0.16 * a)
        case .drift:
            return .init(dx: sin(t * w + phase) * 0.03 * a,
                         dy: cos(t * w + phase) * 0.02 * a,
                         dRot: sin(t * w + phase) * 0.04 * a)
        case .sway:
            return .init(dRot: sin(t * w) * 0.10 * a)          // all sway together
        case .parallax:
            let depth = 1 + CGFloat(i) * 0.35
            return .init(dx: sin(t * w) * 0.018 * a * depth,
                         dy: cos(t * w) * 0.006 * a * depth)
        }
    }
}
