import SwiftUI
import CoreGraphics

/// Alignment edges for a multi-selection.
enum AlignEdge { case left, centerH, right, top, centerV, bottom }

/// Group operations over a set of selected elements. All math runs in a
/// canonical space derived from the canvas aspect, so positions (which are
/// normalized 0…1) and sizes stay proportional regardless of the live window.
extension Collage {

    private func groupCanvas() -> CGSize { CGSize(width: max(0.2, canvasAspect), height: 1) }

    func selected(_ ids: Set<UUID>) -> [PlacedSticker] {
        ordered.filter { ids.contains($0.id) }
    }

    /// A selected element's center and half-size in the canonical group space.
    private struct Frame { let s: PlacedSticker; let center: CGPoint; let half: CGSize }

    private func frames(_ ids: Set<UUID>, _ canvas: CGSize) -> [Frame] {
        selected(ids).map { s in
            let size = s.renderSize(in: canvas)
            return Frame(s: s,
                         center: CGPoint(x: s.position.x * canvas.width, y: s.position.y * canvas.height),
                         half: CGSize(width: size.width / 2, height: size.height / 2))
        }
    }

    // MARK: Align

    func align(_ ids: Set<UUID>, _ edge: AlignEdge) {
        let canvas = groupCanvas()
        let f = frames(ids, canvas)
        guard f.count > 1 else { return }
        switch edge {
        case .left:
            let m = f.map { $0.center.x - $0.half.width }.min()!
            f.forEach { $0.s.position.x = (m + $0.half.width) / canvas.width }
        case .right:
            let m = f.map { $0.center.x + $0.half.width }.max()!
            f.forEach { $0.s.position.x = (m - $0.half.width) / canvas.width }
        case .centerH:
            let lo = f.map { $0.center.x - $0.half.width }.min()!
            let hi = f.map { $0.center.x + $0.half.width }.max()!
            f.forEach { $0.s.position.x = (lo + hi) / 2 / canvas.width }
        case .top:
            let m = f.map { $0.center.y - $0.half.height }.min()!
            f.forEach { $0.s.position.y = (m + $0.half.height) / canvas.height }
        case .bottom:
            let m = f.map { $0.center.y + $0.half.height }.max()!
            f.forEach { $0.s.position.y = (m - $0.half.height) / canvas.height }
        case .centerV:
            let lo = f.map { $0.center.y - $0.half.height }.min()!
            let hi = f.map { $0.center.y + $0.half.height }.max()!
            f.forEach { $0.s.position.y = (lo + hi) / 2 / canvas.height }
        }
    }

    // MARK: Scale / rotate around the group centroid

    private func centroid(_ ids: Set<UUID>, _ canvas: CGSize) -> CGPoint {
        let items = selected(ids)
        let cs = items.map { CGPoint(x: $0.position.x * canvas.width, y: $0.position.y * canvas.height) }
        let n = CGFloat(max(1, cs.count))
        return CGPoint(x: cs.map(\.x).reduce(0, +) / n, y: cs.map(\.y).reduce(0, +) / n)
    }

    func scaleSelected(_ ids: Set<UUID>, by factor: CGFloat) {
        let canvas = groupCanvas()
        let c = centroid(ids, canvas)
        for s in selected(ids) {
            let p = CGPoint(x: s.position.x * canvas.width, y: s.position.y * canvas.height)
            let np = CGPoint(x: c.x + (p.x - c.x) * factor, y: c.y + (p.y - c.y) * factor)
            s.position = CGPoint(x: np.x / canvas.width, y: np.y / canvas.height)
            s.scale = (s.scale * factor).clamped(0.15, 4.0)
        }
    }

    func rotateSelected(_ ids: Set<UUID>, by delta: CGFloat) {
        let canvas = groupCanvas()
        let c = centroid(ids, canvas)
        for s in selected(ids) {
            let p = CGPoint(x: s.position.x * canvas.width - c.x, y: s.position.y * canvas.height - c.y)
            let rp = CGPoint(x: p.x * cos(delta) - p.y * sin(delta), y: p.x * sin(delta) + p.y * cos(delta))
            s.position = CGPoint(x: (c.x + rp.x) / canvas.width, y: (c.y + rp.y) / canvas.height)
            s.rotation += delta
        }
    }

    // MARK: Layer / duplicate / delete

    func bringSelectedToFront(_ ids: Set<UUID>) {
        for s in selected(ids) { bringToFront(s) }
    }

    func sendSelectedToBack(_ ids: Set<UUID>) {
        for s in selected(ids).reversed() { sendToBack(s) }
    }

    @discardableResult
    func duplicateSelected(_ ids: Set<UUID>) -> Set<UUID> {
        Set(selected(ids).map { duplicate($0).id })
    }

    func removeSelected(_ ids: Set<UUID>) {
        stickers.removeAll { ids.contains($0.id) }
    }
}
