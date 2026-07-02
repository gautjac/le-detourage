import SwiftUI
import CoreGraphics

/// An alignment guide shown while dragging: a full-span line at `position` in
/// page space, either vertical (a constant x) or horizontal (a constant y).
struct AlignmentGuide: Equatable {
    enum Axis { case vertical, horizontal }
    let axis: Axis
    let position: CGFloat
}

/// Pure snapping math for the canvas: given a proposed element center, snap it to
/// the canvas center, the canvas edges (element flush), and other elements'
/// centers — returning the adjusted center plus the guide lines to draw.
enum Snapping {
    /// Snap tolerance in page points.
    static let threshold: CGFloat = 8

    struct Result: Equatable {
        var center: CGPoint
        var guides: [AlignmentGuide]
    }

    struct Neighbor { var center: CGPoint; var size: CGSize }

    /// A snap candidate: the element-center value that lands the snap, and the
    /// guide line to draw for it.
    private struct Candidate { let snappedCenter: CGFloat; let guide: CGFloat }

    static func snap(center: CGPoint, size: CGSize, canvas: CGSize,
                     others: [Neighbor]) -> Result {
        var result = center
        var guides: [AlignmentGuide] = []

        if let best = nearest(center.x, candidatesX(size: size, canvas: canvas, others: others)) {
            result.x = best.snappedCenter
            guides.append(AlignmentGuide(axis: .vertical, position: best.guide))
        }
        if let best = nearest(center.y, candidatesY(size: size, canvas: canvas, others: others)) {
            result.y = best.snappedCenter
            guides.append(AlignmentGuide(axis: .horizontal, position: best.guide))
        }
        return Result(center: result, guides: guides)
    }

    // MARK: Candidates

    private static func candidatesX(size: CGSize, canvas: CGSize, others: [Neighbor]) -> [Candidate] {
        let half = size.width / 2
        var c: [Candidate] = [
            Candidate(snappedCenter: canvas.width / 2, guide: canvas.width / 2),   // canvas center
            Candidate(snappedCenter: half, guide: 0),                              // flush left
            Candidate(snappedCenter: canvas.width - half, guide: canvas.width),    // flush right
        ]
        for n in others {
            c.append(Candidate(snappedCenter: n.center.x, guide: n.center.x))      // center align
        }
        return c
    }

    private static func candidatesY(size: CGSize, canvas: CGSize, others: [Neighbor]) -> [Candidate] {
        let half = size.height / 2
        var c: [Candidate] = [
            Candidate(snappedCenter: canvas.height / 2, guide: canvas.height / 2),
            Candidate(snappedCenter: half, guide: 0),
            Candidate(snappedCenter: canvas.height - half, guide: canvas.height),
        ]
        for n in others {
            c.append(Candidate(snappedCenter: n.center.y, guide: n.center.y))
        }
        return c
    }

    private static func nearest(_ value: CGFloat, _ candidates: [Candidate]) -> Candidate? {
        candidates
            .filter { abs($0.snappedCenter - value) <= threshold }
            .min { abs($0.snappedCenter - value) < abs($1.snappedCenter - value) }
    }
}
