import SwiftUI

/// The floating inspector shown when multiple elements are selected: align,
/// scale/rotate the group around its center, layer, duplicate and delete — plus
/// a count badge. Always on-screen, so it works regardless of where the elements
/// sit on the canvas.
struct GroupInspector: View {
    @Environment(Session.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("\(session.selectedIDs.count)")
                    .font(Theme.mono(13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.grape))
                alignRow
            }
            HStack(spacing: 8) {
                transformRow
                Divider().frame(height: 22)
                layerRow
                Divider().frame(height: 22)
                actionRow
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

    private var alignRow: some View {
        HStack(spacing: 6) {
            btn("align.horizontal.left", Theme.teal) { session.align(.left) }
            btn("align.horizontal.center", Theme.teal) { session.align(.centerH) }
            btn("align.horizontal.right", Theme.teal) { session.align(.right) }
            btn("align.vertical.top", Theme.sky) { session.align(.top) }
            btn("align.vertical.center", Theme.sky) { session.align(.centerV) }
            btn("align.vertical.bottom", Theme.sky) { session.align(.bottom) }
        }
    }

    private var transformRow: some View {
        HStack(spacing: 6) {
            btn("minus.magnifyingglass", Theme.ink) { session.groupScale(0.9) }
            btn("plus.magnifyingglass", Theme.ink) { session.groupScale(1.1) }
            btn("rotate.left", Theme.ink) { session.groupRotate(-.pi / 12) }
            btn("rotate.right", Theme.ink) { session.groupRotate(.pi / 12) }
        }
    }

    private var layerRow: some View {
        HStack(spacing: 6) {
            btn("arrow.up.to.line", Theme.teal) { session.groupBringToFront() }
            btn("arrow.down.to.line", Theme.teal) { session.groupSendToBack() }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            btn("plus.square.on.square", Theme.marigold) { session.duplicateSelection() }
            btn("trash", Theme.coral) { session.deleteSelection() }
        }
    }

    private func btn(_ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.panel))
        }
        .buttonStyle(.plain)
    }
}
