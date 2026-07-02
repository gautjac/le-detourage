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
    @State private var marquee: CGRect?

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
        .sheet(item: Bindable(session).cleaningCutout) { sticker in
            CleanupSheet(sticker: sticker).environment(session)
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
            // Tap outside the page to deselect.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { session.deselectAll() }

            ZStack {
                backgroundLayer(pageSize)

                // Empty-page layer: tap to deselect, drag to marquee-select.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { session.deselectAll() }
                    .gesture(marqueeGesture(pageSize: pageSize))

                ForEach(session.collage.ordered) { sticker in
                    StickerLayer(sticker: sticker, canvasSize: pageSize)
                        .environment(session)
                }

                // Finishing pass over the whole page.
                if session.collage.finish != .none {
                    FinishOverlayView(finish: session.collage.finish, pageSize: pageSize)
                        .allowsHitTesting(false)
                }

                if !session.collage.hasContent {
                    emptyOverlay
                }

                // Alignment guides while dragging.
                if !session.activeGuides.isEmpty {
                    GuidesOverlay(guides: session.activeGuides, pageSize: pageSize)
                        .allowsHitTesting(false)
                }

                // Marquee selection rectangle.
                if let m = marquee {
                    Rectangle().fill(Theme.accent.opacity(0.08))
                        .overlay(Rectangle().stroke(Theme.accent.opacity(0.7),
                                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .frame(width: m.width, height: m.height)
                        .position(x: m.midX, y: m.midY)
                        .allowsHitTesting(false)
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
            if !session.isDrawing {
                if session.isMultiSelect {
                    GroupInspector().environment(session)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let sel = session.selection {
                    StickerInspector(sticker: sel).environment(session)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: session.selectedIDs)
        .animation(.spring(duration: 0.3), value: session.collage.canvasAspect)
        .modifier(CanvasKeyCommands(session: session))
    }

    /// Marquee selection: drag on empty page area to rubber-band select the
    /// elements whose centers fall inside.
    private func marqueeGesture(pageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                  y: min(value.startLocation.y, value.location.y),
                                  width: abs(value.location.x - value.startLocation.x),
                                  height: abs(value.location.y - value.startLocation.y))
                marquee = rect
                let ids = session.collage.stickers
                    .filter { rect.contains($0.center(in: pageSize)) }
                    .map(\.id)
                session.setSelection(Set(ids))
            }
            .onEnded { _ in marquee = nil }
    }

    @ViewBuilder
    private func backgroundLayer(_ size: CGSize) -> some View {
        switch session.collage.background {
        case .color(let c):
            c
        case .gradient(let a, let b):
            LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pattern(let style, let base, let accent):
            PatternBackgroundView(style: style, base: base, accent: accent, size: size)
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

/// macOS keyboard commands for the selection: arrow-key nudge (⇧ for a bigger
/// step), delete, and ⌘C / ⌘V copy-paste. A no-op on iOS.
struct CanvasKeyCommands: ViewModifier {
    let session: Session

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard !session.selectedIDs.isEmpty else { return .ignored }
                let step: CGFloat = press.modifiers.contains(.shift) ? 0.02 : 0.004
                switch press.key {
                case .leftArrow:  session.nudge(dx: -step, dy: 0)
                case .rightArrow: session.nudge(dx: step, dy: 0)
                case .upArrow:    session.nudge(dx: 0, dy: -step)
                case .downArrow:  session.nudge(dx: 0, dy: step)
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(.delete) {
                guard !session.selectedIDs.isEmpty else { return .ignored }
                session.deleteSelection(); return .handled
            }
            .onKeyPress(keys: ["c", "v"]) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if press.key == "c" { session.copySelection(); return .handled }
                if press.key == "v" { session.pasteClipboard(); return .handled }
                return .ignored
            }
        #else
        content
        #endif
    }
}

/// A patterned background, generated to an image (cached) and shown on the page.
struct PatternBackgroundView: View {
    let style: PatternStyle
    let base: Color
    let accent: Color
    let size: CGSize
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platform: image).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height).clipped()
            } else {
                base
            }
        }
        .onAppear(perform: render)
        .onChange(of: size) { _, _ in render() }
        .onChange(of: style) { _, _ in render() }
        .onChange(of: base) { _, _ in render() }
        .onChange(of: accent) { _, _ in render() }
    }

    private func render() {
        let target = CGSize(width: size.width * 2, height: size.height * 2)
        image = style.image(size: target, base: base, accent: accent)
    }
}

/// The finishing pass (grain / vignette / light-leak / paper), generated to an
/// image (cached) and composited over the page with its blend + opacity.
struct FinishOverlayView: View {
    let finish: FinishOverlay
    let pageSize: CGSize
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(platform: image).resizable()
                    .frame(width: pageSize.width, height: pageSize.height)
                    .blendMode(finish.blend.swiftUI)
                    .opacity(finish.opacity)
            }
        }
        .onAppear(perform: render)
        .onChange(of: finish) { _, _ in render() }
        .onChange(of: pageSize) { _, _ in render() }
    }

    private func render() {
        let target = CGSize(width: pageSize.width * 2, height: pageSize.height * 2)
        image = finish.image(size: target)
    }
}

/// Draws the active alignment guides (dashed accent lines) over the page.
struct GuidesOverlay: View {
    let guides: [AlignmentGuide]
    let pageSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            for guide in guides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    path.move(to: CGPoint(x: guide.position, y: 0))
                    path.addLine(to: CGPoint(x: guide.position, y: size.height))
                case .horizontal:
                    path.move(to: CGPoint(x: 0, y: guide.position))
                    path.addLine(to: CGPoint(x: size.width, y: guide.position))
                }
                ctx.stroke(path, with: .color(Theme.accent.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
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
