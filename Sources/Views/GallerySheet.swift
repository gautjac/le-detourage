import SwiftUI
import SwiftData

/// The gallery of saved collages ("les Pages"): a grid of thumbnails. Tap to
/// open one into the working canvas; long-press / context-menu to rename,
/// duplicate, export, or delete. A "Save current" action banks the live canvas.
struct GallerySheet: View {
    @Environment(Session.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedCollage.updatedAt, order: .reverse) private var pages: [SavedCollage]

    @State private var renaming: SavedCollage?
    @State private var renameText: String = ""

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 16)] }

    var body: some View {
        VStack(spacing: 0) {
            header
            TornDivider().padding(.horizontal, 20).padding(.bottom, 8)

            if pages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(pages) { page in
                            PageTile(page: page, isCurrent: page.id == session.currentCollageID)
                                .onTapGesture { open(page) }
                                .contextMenu { menu(for: page) }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Theme.page)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
        .alert(L.t("gallery.rename"), isPresented: renamingBinding) {
            TextField(L.t("gallery.untitled"), text: $renameText)
            Button(L.t("common.done")) { commitRename() }
            Button(L.t("common.cancel"), role: .cancel) { renaming = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(loc: "gallery.title")
                .font(Theme.display(24)).foregroundStyle(Theme.ink)
            Spacer()
            if !session.collage.isEmpty {
                Button {
                    _ = session.saveToGallery(context: modelContext)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text(loc: "gallery.save")
                    }
                    .font(Theme.title(14)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.teal))
                }
                .buttonStyle(.plain)
            }
            Button {
                Haptics.tap(); dismiss()
            } label: {
                Text(loc: "common.done")
                    .font(Theme.title(16)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 52)).foregroundStyle(Theme.inkFaint)
            Text(loc: "gallery.empty")
                .font(Theme.body(15)).foregroundStyle(Theme.inkDim)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            if !session.collage.isEmpty {
                PillButton(titleKey: "gallery.save", systemImage: "square.and.arrow.down.fill", tint: Theme.teal) {
                    _ = session.saveToGallery(context: modelContext)
                }
            }
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func menu(for page: SavedCollage) -> some View {
        Button { open(page) } label: { Label(L.t("gallery.open"), systemImage: "folder") }
        Button { beginRename(page) } label: { Label(L.t("gallery.rename"), systemImage: "pencil") }
        Button { duplicate(page) } label: { Label(L.t("gallery.duplicate"), systemImage: "plus.square.on.square") }
        Button { export(page) } label: { Label(L.t("gallery.export"), systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive) { delete(page) } label: { Label(L.t("gallery.delete"), systemImage: "trash") }
    }

    // MARK: Actions

    private func open(_ page: SavedCollage) {
        session.open(page)
        dismiss()
    }

    private func beginRename(_ page: SavedCollage) {
        renameText = page.title
        renaming = page
    }

    private func commitRename() {
        guard let page = renaming else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            page.title = trimmed
            page.updatedAt = Date()
            if session.currentCollageID == page.id { session.currentTitle = trimmed }
            try? modelContext.save()
        }
        renaming = nil
    }

    private func duplicate(_ page: SavedCollage) {
        let copy = SavedCollage(title: page.title + " ✦",
                                thumbnailData: page.thumbnailData,
                                documentData: page.documentData)
        modelContext.insert(copy)
        try? modelContext.save()
    }

    private func export(_ page: SavedCollage) {
        let collage = Collage()
        collage.load(document: page.document)
        guard let image = CollageRenderer.render(collage, transparentBackground: false) else { return }
        Exporter.exportPNG(image, suggestedName: "collage-detourage")
        session.flash(L.t("export.collage"))
    }

    private func delete(_ page: SavedCollage) {
        if session.currentCollageID == page.id { session.currentCollageID = nil }
        modelContext.delete(page)
        try? modelContext.save()
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}

/// A gallery tile: the collage thumbnail on a paper card, with its title and a
/// "current" marker.
struct PageTile: View {
    let page: SavedCollage
    let isCurrent: Bool
    @State private var image: PlatformImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
                if let image {
                    Image(platform: image)
                        .resizable().scaledToFit().padding(8)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isCurrent ? Theme.accent : Theme.hairline.opacity(0.6),
                            lineWidth: isCurrent ? 3 : 1)
            )
            .shadow(color: Theme.stickerShadow, radius: 8, y: 4)

            Text(page.title)
                .font(Theme.title(14)).foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .task {
            if image == nil { image = PlatformImage(data: page.thumbnailData) }
        }
    }
}
