import SwiftUI

/// The floating inspector for the selected element. Cutouts get style + shadow;
/// text gets an Edit button + shadow. Both share the action row (layer order,
/// flip, scale/rotate nudges — essential on macOS where two-finger gestures are
/// awkward — duplicate, delete). Every action records an undo checkpoint first.
struct StickerInspector: View {
    @Bindable var sticker: PlacedSticker
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            topRow
            actionRow
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

    // MARK: Top row — kind-specific

    @ViewBuilder
    private var topRow: some View {
        HStack(spacing: 8) {
            switch sticker.kind {
            case .text:
                pillButton("textformat", "text.edit") { session.editText(sticker) }
                Divider().frame(height: 22)
            case .cutout:
                pillButton("wand.and.stars", "style.effects") { session.editStyle(sticker) }
                Divider().frame(height: 22)
            case .shape(let emblem):
                shapeColorStrip(emblem)
                Divider().frame(height: 22)
            case .sketch:
                EmptyView()   // sketches carry their own per-stroke colors
            }
            Button {
                edit { sticker.shadow.toggle() }
            } label: {
                Image(systemName: "shadow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(sticker.shadow ? .white : Theme.inkDim)
                    .frame(width: 38, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(sticker.shadow ? Theme.grape : Theme.panel))
            }
            .buttonStyle(.plain)
        }
    }

    private func pillButton(_ icon: String, _ titleKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(loc: titleKey)
            }
            .font(Theme.title(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Theme.grape))
        }
        .buttonStyle(.plain)
    }

    /// A compact color strip for recoloring an embellishment.
    private func shapeColorStrip(_ emblem: Embellishment) -> some View {
        HStack(spacing: 6) {
            ForEach(Embellishment.colors.indices, id: \.self) { i in
                Button {
                    edit { sticker.embellishment = Embellishment(shape: emblem.shape, colorIndex: i) }
                } label: {
                    Circle()
                        .fill(Embellishment.colors[i])
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: emblem.colorIndex == i ? 2.5 : 0).padding(-2.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Action row — shared
    //
    // Scale, rotate and re-layer live on the on-canvas selection handles now;
    // this row keeps the actions that aren't a direct spatial manipulation.

    private var actionRow: some View {
        HStack(spacing: 8) {
            inspectorButton("arrow.left.and.right.righttriangle.left.righttriangle.right", tint: Theme.sky) {
                edit { sticker.flipped.toggle() }
            }
            inspectorButton("plus.square.on.square", tint: Theme.marigold) {
                session.checkpoint()
                let copy = session.collage.duplicate(sticker)
                session.selection = copy
            }
            inspectorButton("trash", tint: Theme.coral) {
                session.checkpoint()
                session.collage.remove(sticker)
                session.selection = nil
            }
        }
    }

    /// Record a checkpoint, run a mutation, and give haptic feedback.
    private func edit(_ block: () -> Void) {
        session.checkpoint()
        Haptics.tap()
        block()
    }

    private func inspectorButton(_ icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.panel))
        }
        .buttonStyle(.plain)
    }
}
