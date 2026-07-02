import SwiftUI

/// Edge cleanup for a cutout: paint with the eraser to remove stray bits, feather
/// the edge, undo, or reset. Applies live to a working copy; Done commits it as a
/// single undo step.
struct CleanupSheet: View {
    let sticker: PlacedSticker
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    private let original: PlatformImage
    @State private var history: [PlatformImage]
    @State private var current: [CGPoint] = []
    @State private var brush: CGFloat = 24

    init(sticker: PlacedSticker) {
        self.sticker = sticker
        let img = sticker.image ?? PlatformImage()
        self.original = img
        self._history = State(initialValue: [img])
    }

    private var working: PlatformImage { history.last ?? original }

    var body: some View {
        VStack(spacing: 0) {
            header
            editor
            controls
        }
        .background(Theme.page)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        HStack {
            Button {
                session.finishCleanup(sticker, image: nil)
                dismiss()
            } label: {
                Text(loc: "common.cancel").font(Theme.title(16)).foregroundStyle(Theme.inkDim)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(loc: "cleanup.title").font(Theme.display(20)).foregroundStyle(Theme.ink)
            Spacer()
            Button {
                Haptics.tap()
                session.finishCleanup(sticker, image: history.count > 1 ? working : nil)
                dismiss()
            } label: {
                Text(loc: "common.done").font(Theme.title(16)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    // MARK: Editor

    private var editor: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            ZStack {
                CheckerboardBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Image(platform: working)
                    .resizable().scaledToFit()
                Canvas { ctx, _ in
                    // Live eraser preview.
                    guard current.count > 0 else { return }
                    var path = Path()
                    path.addLines(current)
                    ctx.stroke(path, with: .color(Theme.coral.opacity(0.35)),
                               style: StrokeStyle(lineWidth: brush * 2, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { current.append($0.location) }
                    .onEnded { _ in commitStroke(layout) }
            )
        }
        .padding(16)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eraser").foregroundStyle(Theme.inkDim)
                Slider(value: $brush, in: 10...48).tint(Theme.grape)
            }
            HStack(spacing: 10) {
                pill("wand.and.stars", "cleanup.feather") {
                    if let f = CutoutCleanup.feather(working) { history.append(f) }
                }
                pill("arrow.uturn.backward", "cleanup.undo") {
                    if history.count > 1 { history.removeLast() }
                }
                pill("arrow.counterclockwise", "cleanup.reset") {
                    history = [original]
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func pill(_ icon: String, _ titleKey: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(loc: titleKey)
            }
            .font(Theme.title(14)).foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Coordinate mapping

    private struct Layout { let origin: CGPoint; let scale: CGFloat }

    private func layout(in size: CGSize) -> Layout {
        let p = working.pixelSize
        guard p.width > 0, p.height > 0 else { return Layout(origin: .zero, scale: 1) }
        let scale = min(size.width / p.width, size.height / p.height)
        let disp = CGSize(width: p.width * scale, height: p.height * scale)
        return Layout(origin: CGPoint(x: (size.width - disp.width) / 2, y: (size.height - disp.height) / 2),
                      scale: scale)
    }

    private func commitStroke(_ layout: Layout) {
        defer { current = [] }
        guard layout.scale > 0, !current.isEmpty else { return }
        let imagePoints = current.map {
            CGPoint(x: ($0.x - layout.origin.x) / layout.scale,
                    y: ($0.y - layout.origin.y) / layout.scale)
        }
        if let erased = CutoutCleanup.erase(working, points: imagePoints, radiusPx: brush / layout.scale) {
            history.append(erased)
        }
    }
}
