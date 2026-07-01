import SwiftUI

/// Export the collage as a PNG, with an optional transparent background. Shows a
/// live preview of the flattened result before saving/sharing.
struct ExportSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var transparent = false
    @State private var preview: PlatformImage?
    @State private var rendering = false

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
                    if let preview {
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
                .onChange(of: transparent) { _, _ in regenerate() }

                actions
                    .disabled(rendering || preview == nil)

                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        } onDone: { dismiss() }
        .onAppear { regenerate() }
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
}
