import SwiftUI

/// The collage canvas: an editable scrapbook page. Placed cutouts can be
/// dragged, pinched/scaled, rotated, layered and styled. A background picker and
/// export sit in the toolbar; a per-sticker inspector floats when one is
/// selected.
struct CollageCanvasView: View {
    @Environment(Session.self) private var session
    @State private var showBackground = false
    @State private var showExport = false
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            GeometryReader { geo in
                canvas(size: geo.size)
            }
        }
        .sheet(isPresented: $showBackground) {
            BackgroundPickerSheet().environment(session)
        }
        .sheet(isPresented: $showExport) {
            ExportSheet().environment(session)
        }
        .confirmationDialog(L.t("canvas.clear.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("canvas.clear"), role: .destructive) {
                session.collage.clear()
                session.selection = nil
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(loc: "canvas.title")
                .font(Theme.display(24))
                .foregroundStyle(Theme.ink)
            Spacer()
            RoundIconButton(systemImage: "paintpalette.fill", tint: Theme.grape) {
                showBackground = true
            }
            RoundIconButton(systemImage: "trash", tint: Theme.inkDim) {
                if !session.collage.isEmpty { confirmClear = true }
            }
            Button {
                Haptics.tap()
                if !session.collage.isEmpty { showExport = true }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text(loc: "canvas.export")
                }
                .font(Theme.title(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(session.collage.isEmpty ? Theme.inkFaint : Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(session.collage.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Canvas

    private func canvas(size: CGSize) -> some View {
        // Compute the page rect: a centered, rounded scrapbook page that keeps
        // the collage's aspect ratio.
        let inset: CGFloat = 20
        let avail = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
        let aspect = session.collage.canvasAspect
        let pageSize = fit(aspect: aspect, in: avail)

        return ZStack {
            // Tap empty space to deselect.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { session.selection = nil }

            ZStack {
                backgroundLayer(pageSize)

                ForEach(session.collage.ordered) { sticker in
                    StickerLayer(sticker: sticker, canvasSize: pageSize)
                        .environment(session)
                }

                if session.collage.isEmpty {
                    emptyOverlay
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.stickerShadow, radius: 16, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.card, lineWidth: 6)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let sel = session.selection {
                StickerInspector(sticker: sel).environment(session)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: session.selection?.id)
        .onAppear {
            // Match the canvas aspect to the available area the first time so the
            // page fills the space nicely.
            if session.collage.isEmpty {
                session.collage.canvasAspect = clampAspect(avail.width / max(1, avail.height))
            }
        }
    }

    @ViewBuilder
    private func backgroundLayer(_ size: CGSize) -> some View {
        switch session.collage.background {
        case .color(let c):
            c
        case .gradient(let a, let b):
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .transparent:
            CheckerboardBackground()
        case .photo:
            if let img = session.collage.backgroundImage {
                Image(platform: img).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            } else {
                Theme.page
            }
        }
    }

    private var emptyOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: "scissors.badge.ellipsis")
                .font(.system(size: 46))
                .foregroundStyle(Theme.inkFaint)
            Text(loc: "canvas.empty")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    // MARK: Layout helpers

    private func fit(aspect: CGFloat, in avail: CGSize) -> CGSize {
        guard avail.width > 0, avail.height > 0 else { return CGSize(width: 300, height: 300) }
        var w = avail.width
        var h = w / aspect
        if h > avail.height {
            h = avail.height
            w = h * aspect
        }
        return CGSize(width: w, height: h)
    }

    private func clampAspect(_ a: CGFloat) -> CGFloat {
        min(1.6, max(0.6, a))
    }
}

/// A subtle checkerboard shown when the background is transparent.
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 18
            let cols = Int(size.width / s) + 1
            let rows = Int(size.height / s) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c) % 2 == 0 {
                        let rect = CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)
                        ctx.fill(Path(rect), with: .color(Theme.hairline.opacity(0.35)))
                    }
                }
            }
        }
        .background(Color.white)
    }
}
