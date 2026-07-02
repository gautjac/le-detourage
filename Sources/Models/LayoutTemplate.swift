import SwiftUI
import CoreGraphics

/// One-tap auto-arrangement of the elements into a layout. Sets normalized
/// positions (and gentle rotations/scales); the user can tweak afterward.
enum LayoutTemplate: Int, CaseIterable, Identifiable {
    case grid, row, stack, circle, scatter

    var id: Int { rawValue }
    var titleKey: String { "layout.\(self)" }
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .row: return "rectangle.split.3x1"
        case .stack: return "square.stack.3d.up"
        case .circle: return "circle.dashed"
        case .scatter: return "sparkles"
        }
    }

    func arrange(_ items: [PlacedSticker], aspect: CGFloat) {
        let n = items.count
        guard n > 0 else { return }
        var rng = SeededRNG(seed: 0x1A7 &* UInt64(n + 1))

        switch self {
        case .grid:
            let cols = max(1, Int(ceil(Double(n).squareRoot())))
            let rows = max(1, Int(ceil(Double(n) / Double(cols))))
            for (i, s) in items.enumerated() {
                let c = i % cols, r = i / cols
                s.position = CGPoint(x: (CGFloat(c) + 0.5) / CGFloat(cols) * 0.72 + 0.14,
                                     y: (CGFloat(r) + 0.5) / CGFloat(rows) * 0.72 + 0.14)
                s.rotation = 0
                s.scale = (1.5 / CGFloat(max(cols, rows))).clamped(0.3, 1.6)
            }
        case .row:
            for (i, s) in items.enumerated() {
                s.position = CGPoint(x: (CGFloat(i) + 0.5) / CGFloat(n) * 0.8 + 0.1, y: 0.5)
                s.rotation = 0
                s.scale = (1.4 / CGFloat(n)).clamped(0.3, 1.4)
            }
        case .stack:
            for (i, s) in items.enumerated() {
                let off = CGFloat(i) - CGFloat(n - 1) / 2
                s.position = CGPoint(x: 0.5 + off * 0.03, y: 0.5 + off * 0.02)
                s.rotation = rng.jitter(0.18)
            }
        case .circle:
            let xr = aspect >= 1 ? 0.3 / aspect : 0.3
            let yr = aspect < 1 ? 0.3 * aspect : 0.3
            for (i, s) in items.enumerated() {
                let a = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(n) * 2 * .pi
                s.position = CGPoint(x: 0.5 + cos(a) * xr, y: 0.5 + sin(a) * yr)
                s.rotation = 0
                s.scale = s.scale.clamped(0.3, 0.9)
            }
        case .scatter:
            for s in items {
                s.position = CGPoint(x: 0.2 + rng.unit() * 0.6, y: 0.2 + rng.unit() * 0.6)
                s.rotation = rng.jitter(0.3)
            }
        }
    }
}

/// A one-tap look: a background + a finishing overlay.
struct CollageTheme: Identifiable {
    let id: String
    let titleKey: String
    let background: CollageBackground
    let finish: FinishOverlay

    static let all: [CollageTheme] = [
        CollageTheme(id: "cream", titleKey: "theme.cream", background: .color(Theme.page), finish: .paper),
        CollageTheme(id: "sunset", titleKey: "theme.sunset",
                     background: .gradient(Theme.marigold, Theme.coral), finish: .grain),
        CollageTheme(id: "mint", titleKey: "theme.mint",
                     background: .color(Color(red: 0.82, green: 0.93, blue: 0.90)), finish: .none),
        CollageTheme(id: "night", titleKey: "theme.night", background: .color(Theme.ink), finish: .vignette),
        CollageTheme(id: "confetti", titleKey: "theme.confetti",
                     background: .pattern(.confetti, Theme.page, Theme.grape), finish: .none),
        CollageTheme(id: "dots", titleKey: "theme.dots",
                     background: .pattern(.dots, Color(red: 0.99, green: 0.85, blue: 0.87), Theme.coral), finish: .none),
        CollageTheme(id: "film", titleKey: "theme.film",
                     background: .color(Color(red: 0.15, green: 0.16, blue: 0.20)), finish: .lightLeak),
    ]
}
