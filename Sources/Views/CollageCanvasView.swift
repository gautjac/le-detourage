import SwiftUI

/// The collage canvas: an editable scrapbook page. Placed cutouts can be
/// dragged, pinched/scaled, rotated, layered and styled. A background picker and
/// export sit in the toolbar; a per-sticker inspector floats when one is
/// selected.
struct CollageCanvasView: View {
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @State private var showBackground = false
    @State private var showExport = false
    @State private var showGallery = false
    @State private var showEmblems = false
    @State private var showFormat = false
    @State private var confirmClear = false
    @State private var confirmNew = false

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
        .sheet(isPresented: $showGallery) {
            GallerySheet().environment(session)
        }
        .sheet(isPresented: $showEmblems) {
            EmbellishmentPicker().environment(session)
        }
        .sheet(isPresented: $showFormat) {
            CanvasFormatSheet().environment(session)
        }
        .sheet(item: Bindable(session).editingText) { sticker in
            TextEditorSheet(sticker: sticker).environment(session)
        }
        .sheet(item: Bindable(session).editingStyle) { sticker in
            CutoutStyleSheet(sticker: sticker).environment(session)
        }
        .confirmationDialog(L.t("canvas.clear.confirm"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("canvas.clear"), role: .destructive) {
                session.checkpoint()
                session.collage.clear()
                session.selection = nil
            }
            Button(L.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L.t("canvas.new.confirm"), isPresented: $confirmNew, titleVisibility: .visible) {
            Button(L.t("canvas.new"), role: .destructive) { session.newCollage() }
            Button(L.t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(session.currentTitle.isEmpty ? L.t("canvas.title") : session.currentTitle)
                .font(Theme.display(22))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)

            toolButton("arrow.uturn.backward", enabled: session.history.canUndo) { session.undo() }
                .keyboardShortcut("z", modifiers: .command)
            toolButton("arrow.uturn.forward", enabled: session.history.canRedo) { session.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])

            toolButton("textformat", tint: Theme.grape) { session.addText() }
            toolButton("sparkles", tint: Theme.marigold) { showEmblems = true }
            toolButton("scribble", tint: Theme.leaf) { session.startDrawing() }

            Menu {
                Button { showFormat = true } label: {
                    Label(L.t("format.title"), systemImage: "aspectratio")
                }
                Button { showBackground = true } label: {
                    Label(L.t("canvas.background"), systemImage: "paintpalette")
                }
                Button {
                    _ = session.saveToGallery(context: modelContext)
                } label: {
                    Label(L.t("gallery.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(!session.collage.hasContent)
                Button { showGallery = true } label: {
                    Label(L.t("gallery.open"), systemImage: "photo.stack")
                }
                Divider()
                Button {
                    if session.collage.isEmpty { session.newCollage() } else { confirmNew = true }
                } label: {
                    Label(L.t("canvas.new"), systemImage: "doc.badge.plus")
                }
                Button(role: .destructive) {
                    if session.collage.hasContent { confirmClear = true }
                } label: {
                    Label(L.t("canvas.clear"), systemImage: "trash")
                }
            } label: {
                toolButtonLabel("ellipsis", tint: Theme.inkDim, enabled: true)
            }
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                Haptics.tap()
                if session.collage.hasContent { showExport = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text(loc: "canvas.export")
                }
                .font(Theme.title(14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(session.collage.hasContent ? Theme.accent : Theme.inkFaint))
            }
            .buttonStyle(.plain)
            .disabled(!session.collage.hasContent)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// A compact circular toolbar button with an enabled/disabled state.
    private func toolButton(_ icon: String, tint: Color = Theme.ink, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            toolButtonLabel(icon, tint: tint, enabled: enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toolButtonLabel(_ icon: String, tint: Color, enabled: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(enabled ? tint : Theme.inkFaint.opacity(0.5))
            .frame(width: 40, height: 40)
            .background(Circle().fill(Theme.card).shadow(color: Theme.stickerShadow, radius: 4, y: 2))
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

                if !session.collage.hasContent {
                    emptyOverlay
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .coordinateSpace(.named("page"))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.stickerShadow, radius: 16, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.card, lineWidth: 6)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if session.isDrawing {
                DoodleEditor(pageSize: pageSize).environment(session)
            }
        }
        .overlay(alignment: .bottom) {
            if let sel = session.selection, !session.isDrawing {
                StickerInspector(sticker: sel).environment(session)
                    // Clear the floating Studio/Drawer tab bar (same clearance the
                    // iOS add-button uses) so the action row isn't hidden behind it.
                    .padding(.bottom, 84)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: session.selection?.id)
        .animation(.spring(duration: 0.3), value: session.collage.canvasAspect)
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
