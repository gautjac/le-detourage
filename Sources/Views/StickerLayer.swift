import SwiftUI

/// A single placed element on the canvas — a cutout (with its optional white
/// paper border and drop shadow) or a text label. Interactive: drag to move,
/// pinch to scale, rotate with two fingers (or the inspector on macOS). Tapping
/// selects it; double-tapping a text label opens the editor.
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
            .simultaneousGesture(
                // Double-tap a text label to edit it.
                TapGesture(count: 2).onEnded {
                    if sticker.isText { session.editText(sticker) }
                }
            )
            .onTapGesture {
                Haptics.tap()
                session.selection = sticker
            }
    }

    @ViewBuilder
    private func stickerBody(size: CGSize) -> some View {
        switch sticker.kind {
        case .cutout(let image):
            cutoutBody(image: image, size: size)
        case .text(let content):
            textBody(content: content, size: size)
        }
    }

    // MARK: Cutout body

    @ViewBuilder
    private func cutoutBody(image: PlatformImage, size: CGSize) -> some View {
        let base = Image(platform: image)
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
                        Image(platform: image)
                            .resizable().scaledToFit()
                            .scaleEffect(x: sticker.flipped ? -1 : 1, y: 1)
                            .frame(width: size.width + ow * 2, height: size.height + ow * 2)
                    )
            }
            base.frame(width: size.width, height: size.height)
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

    // MARK: Selection

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
                session.checkpoint()
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
