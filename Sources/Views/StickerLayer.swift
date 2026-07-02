import SwiftUI
import Foundation

/// A single placed element on the canvas — a cutout (with its optional white
/// paper border and drop shadow) or a text label. Interactive: drag the body to
/// move; when selected, direct-manipulation handles on the frame rotate, scale,
/// and re-layer it (two-finger pinch/rotate still work too). Tapping selects;
/// double-tapping a text label opens the editor.
struct StickerLayer: View {
    @Bindable var sticker: PlacedSticker
    let canvasSize: CGSize
    @Environment(Session.self) private var session

    // In-flight two-finger gesture deltas layered on the committed transform.
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero
    // Live drag translation (a @State, not @GestureState, so snapping can adjust
    // it); zero when not dragging.
    @State private var dragOffset: CGSize = .zero

    // Handle-drag start references (nil when idle).
    @State private var scaleStart: (scale: CGFloat, dist: CGFloat)?
    @State private var rotating = false

    private var isSelected: Bool { session.selection?.id == sticker.id }

    /// The element's live on-canvas rotation (committed + transient two-finger).
    private var liveAngle: Angle { Angle(radians: sticker.rotation) + twist }

    var body: some View {
        let size = sticker.renderSize(in: canvasSize)
        let center = sticker.center(in: canvasSize)

        ZStack {
            stickerBody(size: size)
                .rotationEffect(liveAngle)
                .scaleEffect(pinch)
                .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
                .gesture(dragGesture(center: center, size: size))
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(rotateGesture)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if sticker.isText { session.editText(sticker) }
                    }
                )
                .onTapGesture {
                    Haptics.tap()
                    session.selection = sticker
                }

            if isSelected {
                selectionOverlay(size: size, center: center)
            }
        }
    }

    @ViewBuilder
    private func stickerBody(size: CGSize) -> some View {
        switch sticker.kind {
        case .cutout(let image):
            cutoutBody(image: image, size: size)
        case .text(let content):
            textBody(content: content, size: size)
        case .shape(let embellishment):
            shapeBody(embellishment, size: size)
        case .sketch(let sketchContent):
            sketchBody(sketchContent, size: size)
        }
    }

    // MARK: Sketch body

    @ViewBuilder
    private func sketchBody(_ sketch: Sketch, size: CGSize) -> some View {
        let scale = sketch.size.width > 0 ? size.width / sketch.size.width : 1
        Canvas { ctx, _ in
            paint(sketch.strokes, in: ctx, scale: scale)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
        .shadow(color: sticker.shadow ? Theme.stickerShadow : .clear, radius: 7, x: 0, y: 4)
    }

    // MARK: Embellishment body

    @ViewBuilder
    private func shapeBody(_ emblem: Embellishment, size: CGSize) -> some View {
        let path = emblem.shape.renderPath(in: size)
        Group {
            switch emblem.shape.draw {
            case .fill:
                path.fill(emblem.color.opacity(emblem.fillOpacity))
            case .stroke:
                path.stroke(emblem.color,
                            style: StrokeStyle(lineWidth: emblem.shape.strokeWidth(in: size),
                                               lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
        .shadow(color: sticker.shadow ? Theme.stickerShadow : .clear, radius: 7, x: 0, y: 4)
    }

    // MARK: Cutout body

    @ViewBuilder
    private func cutoutBody(image: PlatformImage, size: CGSize) -> some View {
        let styled = sticker.styled
        let subject = styled?.subject ?? image
        let flip: CGFloat = sticker.flipped ? -1 : 1

        ZStack {
            // A true die-cut contour outline sits behind the subject.
            if let outline = styled?.outline, let ratio = styled?.outlineRatio {
                Image(platform: outline)
                    .resizable()
                    .frame(width: size.width * ratio.width, height: size.height * ratio.height)
                    .scaleEffect(x: flip, y: 1)
            }
            Image(platform: subject)
                .resizable().scaledToFit()
                .frame(width: size.width, height: size.height)
                .scaleEffect(x: flip, y: 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: sticker.shadow ? Theme.stickerShadow : .clear,
                radius: 9, x: 0, y: 6)
    }

    // MARK: Text body

    @ViewBuilder
    private func textBody(content: TextContent, size: CGSize) -> some View {
        let fontSize = TextRendering.fontSize(in: canvasSize, scale: sticker.scale)
        let pad = TextRendering.padding(chip: content.chip, fontSize: fontSize)

        Text(content.displayString)
            .font(.system(size: fontSize, weight: content.font.weight, design: content.font.design))
            .foregroundStyle(content.color)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, pad.h)
            .padding(.vertical, pad.v)
            .background(
                Group {
                    if content.chip {
                        RoundedRectangle(cornerRadius: TextRendering.chipCornerRadius(fontSize: fontSize),
                                         style: .continuous)
                            .fill(content.chipColor)
                    }
                }
            )
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
            .shadow(color: sticker.shadow ? Theme.stickerShadow : .clear, radius: 8, x: 0, y: 5)
    }

    // MARK: Selection frame + handles

    private func selectionOverlay(size: CGSize, center: CGPoint) -> some View {
        let framePad = sticker.style.outlineWidth + 8
        let fw = size.width + framePad * 2
        let fh = size.height + framePad * 2
        let handleR: CGFloat = 11
        let stem: CGFloat = 28
        let vMargin = stem + handleR + 4
        let hMargin = handleR + 4
        let containerW = fw + hMargin * 2
        let containerH = fh + vMargin * 2

        // Corner + knob positions in the container's coordinate space.
        let right = hMargin + fw
        let top = vMargin, bottom = vMargin + fh
        let midX = hMargin + fw / 2
        let knob = CGPoint(x: midX, y: top - stem)
        // Counter-rotate glyphs so they stay upright regardless of element angle.
        let counter = Angle(radians: -sticker.rotation) - twist

        return ZStack {
            // Frame outline (non-interactive).
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .frame(width: fw, height: fh)
                .position(x: containerW / 2, y: containerH / 2)
                .allowsHitTesting(false)

            // Rotate stem (non-interactive).
            Path { p in
                p.move(to: CGPoint(x: midX, y: top))
                p.addLine(to: knob)
            }
            .stroke(Theme.accent, lineWidth: 2)
            .allowsHitTesting(false)

            // Rotate knob.
            handle(icon: "arrow.trianglehead.clockwise", tint: Theme.accent, counter: counter)
                .position(knob)
                .gesture(rotateHandleGesture(center: center))

            // Scale handles (bottom-right and top-right corners).
            handle(icon: "arrow.up.left.and.arrow.down.right", tint: Theme.teal, counter: counter)
                .position(x: right, y: bottom)
                .gesture(scaleHandleGesture(center: center))
            handle(icon: "arrow.up.left.and.arrow.down.right", tint: Theme.teal, counter: counter)
                .position(x: right, y: top)
                .gesture(scaleHandleGesture(center: center))

            // Layer ordering lives in the always-visible inspector (reliable even
            // when the element's corners are off-screen), not on the frame.
        }
        .frame(width: containerW, height: containerH)
        .rotationEffect(liveAngle)
        .scaleEffect(pinch)
        .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
    }

    /// A round handle knob with an upright glyph.
    private func handle(icon: String, tint: Color, counter: Angle) -> some View {
        ZStack {
            Circle()
                .fill(Theme.card)
                .overlay(Circle().stroke(tint, lineWidth: 2))
                .shadow(color: Theme.stickerShadow, radius: 3, y: 1)
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
                .rotationEffect(counter)
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }

    // MARK: Handle gestures (locations resolved in the page's coordinate space)

    private func rotateHandleGesture(center: CGPoint) -> some Gesture {
        DragGesture(coordinateSpace: .named("page"))
            .onChanged { value in
                if !rotating { session.checkpoint(); rotating = true }
                let angle = atan2(value.location.y - center.y, value.location.x - center.x)
                sticker.rotation = angle + .pi / 2
            }
            .onEnded { _ in rotating = false }
    }

    private func scaleHandleGesture(center: CGPoint) -> some Gesture {
        DragGesture(coordinateSpace: .named("page"))
            .onChanged { value in
                let dist = hypot(value.location.x - center.x, value.location.y - center.y)
                if scaleStart == nil {
                    session.checkpoint()
                    scaleStart = (sticker.scale, max(1, dist))
                }
                guard let start = scaleStart else { return }
                sticker.scale = (start.scale * dist / start.dist).clamped(0.15, 4.0)
            }
            .onEnded { _ in scaleStart = nil }
    }

    // MARK: Body gestures

    private func dragGesture(center: CGPoint, size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if session.selection?.id != sticker.id {
                    session.selection = sticker
                }
                let raw = CGPoint(x: center.x + value.translation.width,
                                  y: center.y + value.translation.height)
                let result = snapResult(for: raw, size: size)
                dragOffset = CGSize(width: result.center.x - center.x,
                                    height: result.center.y - center.y)
                session.activeGuides = result.guides
            }
            .onEnded { _ in
                session.checkpoint()
                let snapped = CGPoint(x: center.x + dragOffset.width,
                                      y: center.y + dragOffset.height)
                sticker.position = CGPoint(
                    x: (snapped.x / max(1, canvasSize.width)).clamped(-0.1, 1.1),
                    y: (snapped.y / max(1, canvasSize.height)).clamped(-0.1, 1.1))
                dragOffset = .zero
                session.activeGuides = []
                // Moving an element leaves its layer order untouched — use the
                // inspector's arrange row to reorder deliberately.
            }
    }

    /// Snap a proposed center against the canvas and the other elements.
    private func snapResult(for raw: CGPoint, size: CGSize) -> Snapping.Result {
        let others = session.collage.stickers
            .filter { $0.id != sticker.id }
            .map { Snapping.Neighbor(center: $0.center(in: canvasSize),
                                     size: $0.renderSize(in: canvasSize)) }
        return Snapping.snap(center: raw, size: size, canvas: canvasSize, others: others)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                session.checkpoint()
                sticker.scale = (sticker.scale * value.magnification).clamped(0.15, 4.0)
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .updating($twist) { value, state, _ in
                state = value.rotation
            }
            .onEnded { value in
                session.checkpoint()
                sticker.rotation += CGFloat(value.rotation.radians)
            }
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
