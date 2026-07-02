import SwiftUI

/// Export the collage as a PNG, with an optional transparent background. Shows a
/// live preview of the flattened result before saving/sharing.
struct ExportSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var transparent = false
    @State private var preview: PlatformImage?
    @State private var rendering = false
    @State private var animateAmount: CGFloat = 0.7
    @State private var makingGIF = false
    @State private var animFrames: [PlatformImage] = []
    @State private var frameTask: Task<Void, Never>?

    var body: some View {
        SheetScaffold(titleKey: "export.title") {
            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.card)
                        .shadow(color: Theme.stickerShadow, radius: 10, y: 5)
                    if transparent {
                        CheckerboardBackground()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(8)
                    }
                    if animFrames.count > 1 {
                        // Live looping preview of the animation (a flipbook of the
                        // pre-rendered loop frames).
                        TimelineView(.periodic(from: .now, by: 1.0 / AnimatedExporter.fps)) { timeline in
                            let idx = Int(timeline.date.timeIntervalSinceReferenceDate
                                          * AnimatedExporter.fps) % animFrames.count
                            Image(platform: animFrames[idx])
                                .resizable().scaledToFit()
                                .padding(8)
                        }
                    } else if let preview {
                        Image(platform: preview)
                            .resizable().scaledToFit()
                            .padding(8)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxHeight: 340)
                .padding(.horizontal, 20)

                Toggle(isOn: $transparent) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.dashed")
                        Text(loc: "export.transparent")
                    }
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 24)
                .onChange(of: transparent) { _, _ in regenerate(); renderPreviewFrames() }

                actions
                    .disabled(rendering || preview == nil)

                animateSection

                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        } onDone: { dismiss() }
        .onAppear { regenerate(); renderPreviewFrames() }
        .onDisappear { frameTask?.cancel() }
    }

    /// Turn the collage into a gently-wobbling looping GIF.
    private var animateSection: some View {
        VStack(spacing: 12) {
            Divider().padding(.horizontal, 24)
            HStack(spacing: 10) {
                Image(systemName: "wand.and.rays").foregroundStyle(Theme.grape)
                Text(loc: "export.animate").font(Theme.title(15)).foregroundStyle(Theme.ink)
                Slider(value: $animateAmount, in: 0.2...1)
                    .tint(Theme.grape)
                    .onChange(of: animateAmount) { _, _ in renderPreviewFrames() }
            }
            .padding(.horizontal, 24)

            PillButton(titleKey: "export.gif", systemImage: "sparkles", tint: Theme.grape) {
                exportGIF()
            }
            .disabled(rendering || preview == nil || makingGIF)
            .overlay { if makingGIF { ProgressView().controlSize(.small) } }
        }
    }

    @ViewBuilder
    private var actions: some View {
        #if os(macOS)
        HStack(spacing: 12) {
            PillButton(titleKey: "export.save", systemImage: "square.and.arrow.down.fill",
                       tint: Theme.accent, filled: false) { saveNow() }
            PillButton(titleKey: "export.share", systemImage: "square.and.arrow.up.fill",
                       tint: Theme.accent) { shareNow() }
        }
        #else
        PillButton(titleKey: "export.share", systemImage: "square.and.arrow.up.fill",
                   tint: Theme.accent) { shareNow() }
        #endif
    }

    /// Render the loop frames for the live preview (debounced, lower-res).
    private func renderPreviewFrames() {
        frameTask?.cancel()
        let amount = animateAmount
        let t = transparent
        frameTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await Task.yield()
            let cgs = AnimatedExporter.frames(for: session.collage, amount: amount,
                                              transparentBackground: t, longEdge: 480)
            if !Task.isCancelled {
                animFrames = cgs.map { PlatformImage.from(cgImage: $0) }
            }
        }
    }

    private func regenerate() {
        rendering = true
        let t = transparent
        // Render on the main actor (the collage is main-actor state). A yield
        // lets the sheet's progress spinner paint first; the 2K flatten is quick.
        Task { @MainActor in
            await Task.yield()
            let img = CollageRenderer.render(session.collage, transparentBackground: t)
            self.preview = img
            self.rendering = false
        }
    }

    private func saveNow() {
        guard let image = flatten() else { return }
        Exporter.save(image, suggestedName: "collage-detourage")
        Haptics.success()
    }

    private func shareNow() {
        guard let image = flatten() else { return }
        Exporter.share(image, suggestedName: "collage-detourage")
        Haptics.success()
    }

    private func flatten() -> PlatformImage? {
        preview ?? CollageRenderer.render(session.collage, transparentBackground: transparent)
    }

    private func exportGIF() {
        makingGIF = true
        let t = transparent
        let amount = animateAmount
        // Render on the main actor (the collage is main-actor state); a yield lets
        // the spinner paint before the frames are flattened.
        Task { @MainActor in
            await Task.yield()
            let data = AnimatedExporter.makeGIF(for: session.collage, amount: amount,
                                                transparentBackground: t)
            makingGIF = false
            guard let data else { return }
            Exporter.shareFile(data, suggestedName: "collage-detourage", ext: "gif")
            Haptics.success()
        }
    }
}
