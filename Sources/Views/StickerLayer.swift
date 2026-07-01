import SwiftUI

/// A single placed cutout on the canvas: rendered with its optional white paper
/// border and drop shadow, and interactive — drag to move, pinch to scale,
/// rotate with two fingers (or the inspector on macOS). Tapping selects it.
struct StickerLayer: View {
    @Bindable var sticker: PlacedSticker
    let canvasSize: CGSize
    @Environment(Session.self) private var session

    // In-flight gesture deltas layered on top of the committed transform.
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero

    private var isSelected: Bool { session.selection?.id == sticker.id }

    var body: some View {
        let size = sticker.renderSize(in: canvasSize)
        let center = sticker.center(in: canvasSize)

        stickerBody(size: size)
            .scaleEffect(pinch)
            .rotationEffect(twist)
            .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
            .overlay(alignment: .topLeading) {
                if isSelected {
                    selectionOutline(size: size, center: center)
                        .allowsHitTesting(false)
                }
            }
            .gesture(dragGesture(center: center))
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotateGesture)
            .onTapGesture {
                Haptics.tap()
                session.selection = sticker
                session.collage.bringToFront(sticker)
            }
    }

    @ViewBuilder
    private func stickerBody(size: CGSize) -> some View {
        let image = Image(platform: sticker.image)
            .resizable()
            .scaledToFit()
            .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)

        ZStack {
            if sticker.style != .none {
                // White paper border: an enlarged white silhouette behind the
                // cutout, produced by masking a white rect with the cutout alpha.
                let ow = sticker.style.outlineWidth
                Rectangle()
                    .fill(Color.white)
                    .frame(width: size.width + ow * 2, height: size.height + ow * 2)
                    .mask(
                        Image(platform: sticker.image)
                            .resizable().scaledToFit()
                            .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
                            .frame(width: size.width + ow * 2, height: size.height + ow * 2)
                    )
            }
            image.frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: sticker.shadow ? Theme.stickerShadow : .clear,
                radius: 9, x: 0, y: 6)
    }

    private func selectionOutline(size: CGSize, center: CGPoint) -> some View {
        let ow = sticker.style.outlineWidth
        let w = size.width + ow * 2 + 14
        let h = size.height + ow * 2 + 14
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
            .frame(width: w, height: h)
            .scaleEffect(pinch)
            .rotationEffect(twist)
            .position(x: center.x + dragOffset.width, y: center.y + dragOffset.height)
    }

    // MARK: Gestures

    private func dragGesture(center: CGPoint) -> some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onChanged { _ in
                if session.selection?.id != sticker.id {
                    session.selection = sticker
                }
            }
            .onEnded { value in
                let newCenter = CGPoint(x: center.x + value.translation.width,
                                        y: center.y + value.translation.height)
                sticker.position = CGPoint(
                    x: (newCenter.x / max(1, canvasSize.width)).clamped(-0.1, 1.1),
                    y: (newCenter.y / max(1, canvasSize.height)).clamped(-0.1, 1.1))
                session.collage.bringToFront(sticker)
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                sticker.scale = (sticker.scale * value.magnification).clamped(0.15, 4.0)
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .updating($twist) { value, state, _ in
                state = value.rotation
            }
            .onEnded { value in
                sticker.rotation += CGFloat(value.rotation.radians)
            }
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
