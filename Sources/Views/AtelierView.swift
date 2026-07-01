import SwiftUI
import SwiftData

/// The studio: a collage canvas plus a way to bring in new cutouts. Bringing in
/// a cutout opens the Cutout stage (import a photo → lift the subject). Lifted
/// subjects land on the canvas and are auto-saved to the drawer.
struct AtelierView: View {
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @State private var showCutout = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 900
            if wide {
                HStack(spacing: 0) {
                    CollageCanvasView()
                        .frame(maxWidth: .infinity)
                    Divider().overlay(Theme.hairline)
                    CutoutStage(onLift: handleLift)
                        .frame(width: 380)
                        .background(Theme.panel)
                }
            } else {
                CollageCanvasView()
                    .overlay(alignment: .bottomTrailing) {
                        addButton
                            .padding(.trailing, 18)
                            .padding(.bottom, 84)
                    }
                    .sheet(isPresented: $showCutout) {
                        NavigationStackCompat {
                            CutoutStage(onLift: { img in
                                handleLift(img)
                                showCutout = false
                            })
                            .background(Theme.page)
                        }
                    }
            }
        }
        .padding(.top, 8)
    }

    private var addButton: some View {
        Button {
            Haptics.tap()
            showCutout = true
        } label: {
            Image(systemName: "scissors")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Theme.accent).shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 5))
        }
        .buttonStyle(.plain)
    }

    /// A subject was lifted: place it on the canvas and persist it to the drawer.
    private func handleLift(_ image: PlatformImage) {
        session.placeOnCanvas(image)
        saveToDrawer(image)
        session.flash(L.t("lift.added"))
    }

    private func saveToDrawer(_ image: PlatformImage) {
        guard let data = image.pngData else { return }
        let px = image.pixelSize
        let accent = Int.random(in: 0..<Theme.palette.count)
        let sticker = SavedSticker(pngData: data,
                                   pixelWidth: Double(px.width),
                                   pixelHeight: Double(px.height),
                                   accentIndex: accent)
        modelContext.insert(sticker)
        try? modelContext.save()
    }
}

/// A NavigationStack on iOS; a plain container on macOS (which presents the
/// cutout inline, never in a sheet).
struct NavigationStackCompat<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        #if os(iOS)
        NavigationStack { content() }
        #else
        content()
        #endif
    }
}
