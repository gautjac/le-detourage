import SwiftUI
import SwiftData

/// The Tiroir: a grid of saved cutouts. Tap one to paste it onto the collage;
/// long-press (or the context menu) to export it as a standalone sticker or
/// delete it.
struct DrawerView: View {
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedSticker.createdAt, order: .reverse) private var stickers: [SavedSticker]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 14)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TornDivider().padding(.horizontal, 20).padding(.bottom, 8)

            if stickers.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(stickers) { sticker in
                            StickerTile(sticker: sticker)
                                .onTapGesture { paste(sticker) }
                                .contextMenu { menu(for: sticker) }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(loc: "drawer.title")
                .font(Theme.display(24))
                .foregroundStyle(Theme.ink)
            Spacer()
            if !stickers.isEmpty {
                Text("\(stickers.count) \(L.t("drawer.count"))")
                    .font(Theme.mono(13))
                    .foregroundStyle(Theme.inkDim)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.panel))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 52))
                .foregroundStyle(Theme.inkFaint)
            Text(loc: "drawer.empty")
                .font(Theme.body(15))
                .foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            PillButton(titleKey: "tab.atelier", systemImage: "scissors", tint: Theme.teal) {
                session.tab = .atelier
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func menu(for sticker: SavedSticker) -> some View {
        Button {
            paste(sticker)
        } label: {
            Label(L.t("drawer.use"), systemImage: "plus.rectangle.on.rectangle")
        }
        Button {
            share(sticker)
        } label: {
            Label(L.t("drawer.share"), systemImage: "square.and.arrow.up")
        }
        Button {
            export(sticker)
        } label: {
            Label(L.t("drawer.export"), systemImage: "square.and.arrow.down")
        }
        Button(role: .destructive) {
            delete(sticker)
        } label: {
            Label(L.t("drawer.delete"), systemImage: "trash")
        }
    }

    private func paste(_ sticker: SavedSticker) {
        guard let img = PlatformImage(data: sticker.pngData) else { return }
        session.placeOnCanvas(img, sourceID: sticker.id)
        session.tab = .atelier
        session.flash(L.t("lift.added"))
    }

    private func export(_ sticker: SavedSticker) {
        guard let img = PlatformImage(data: sticker.pngData) else { return }
        Exporter.save(img, suggestedName: "autocollant-detourage")
        session.flash(L.t("export.sticker"))
    }

    private func share(_ sticker: SavedSticker) {
        guard let img = PlatformImage(data: sticker.pngData) else { return }
        Exporter.share(img, suggestedName: "autocollant-detourage")
    }

    private func delete(_ sticker: SavedSticker) {
        modelContext.delete(sticker)
        try? modelContext.save()
    }
}

/// A single drawer tile showing a cutout on a colored paper card.
struct StickerTile: View {
    let sticker: SavedSticker
    @State private var image: PlatformImage?

    var body: some View {
        let accent = Theme.palette[min(sticker.accentIndex, Theme.palette.count - 1)]
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.16))
            if let image {
                Image(platform: image)
                    .resizable().scaledToFit()
                    .padding(14)
                    .shadow(color: Theme.stickerShadow, radius: 5, y: 3)
            } else {
                ProgressView()
            }
        }
        .frame(height: 130)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.4), lineWidth: 1.5))
        .shadow(color: Theme.stickerShadow, radius: 8, y: 4)
        .task {
            if image == nil { image = PlatformImage(data: sticker.pngData) }
        }
    }
}
