import SwiftUI

/// The floating inspector for the selected cutout: style, shadow, layer order,
/// flip, scale/rotate nudges (essential on macOS where two-finger gestures are
/// awkward), duplicate and delete.
struct StickerInspector: View {
    @Bindable var sticker: PlacedSticker
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            // Style segment.
            HStack(spacing: 8) {
                ForEach(StickerStyle.allCases) { style in
                    Button {
                        Haptics.tap(); sticker.style = style
                    } label: {
                        Text(loc: style.titleKey)
                            .font(Theme.title(13))
                            .foregroundStyle(sticker.style == style ? .white : Theme.inkDim)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(sticker.style == style ? Theme.grape : Theme.panel))
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 22)
                Toggle(isOn: $sticker.shadow) {
                    Image(systemName: "shadow")
                }
                .toggleStyle(.button)
                .tint(Theme.grape)
                .font(.system(size: 15, weight: .semibold))
            }

            // Action row.
            HStack(spacing: 8) {
                inspectorButton("arrow.up.to.line", tint: Theme.teal) {
                    session.collage.bringToFront(sticker)
                }
                inspectorButton("arrow.down.to.line", tint: Theme.teal) {
                    session.collage.sendToBack(sticker)
                }
                inspectorButton("arrow.left.and.right.righttriangle.left.righttriangle.right", tint: Theme.sky) {
                    sticker.flipped.toggle()
                }
                inspectorButton("minus.magnifyingglass", tint: Theme.ink) {
                    sticker.scale = (sticker.scale * 0.88).clamped(0.15, 4.0)
                }
                inspectorButton("plus.magnifyingglass", tint: Theme.ink) {
                    sticker.scale = (sticker.scale * 1.14).clamped(0.15, 4.0)
                }
                inspectorButton("rotate.left", tint: Theme.ink) {
                    sticker.rotation -= .pi / 12
                }
                inspectorButton("rotate.right", tint: Theme.ink) {
                    sticker.rotation += .pi / 12
                }
                inspectorButton("plus.square.on.square", tint: Theme.marigold) {
                    let copy = session.collage.duplicate(sticker)
                    session.selection = copy
                }
                inspectorButton("trash", tint: Theme.coral) {
                    session.collage.remove(sticker)
                    session.selection = nil
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.card)
                .shadow(color: Theme.stickerShadow, radius: 16, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func inspectorButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.panel))
        }
        .buttonStyle(.plain)
    }
}
