import SwiftUI
import UniformTypeIdentifiers
import PhotosUI   // PhotosPicker is available on macOS 13+ as well as iOS

/// A platform-appropriate "import a photo" control: the system Photos picker on
/// iOS; on macOS a menu offering the Photos library picker (primary) or a file
/// browser. Hands back a decoded `PlatformImage`.
struct PhotoImportButton: View {
    var titleKey: String = "import.photo"
    var systemImage: String = "photo.badge.plus.fill"
    var tint: Color = Theme.accent
    var filled: Bool = true
    var onImage: (PlatformImage) -> Void

    #if os(iOS)
    @State private var item: PhotosPickerItem?
    var body: some View {
        // The label is passed as a static image so the picker's Sendable label
        // closure captures no main-actor state, then styled with the shared
        // decoration modifier.
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            LabelBody(titleKey: titleKey, systemImage: systemImage, tint: tint, filled: filled)
        }
        .onChange(of: item) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let img = PlatformImage(data: data) {
                    await MainActor.run { onImage(img) }
                }
            }
        }
    }
    #else
    @State private var item: PhotosPickerItem?
    @State private var showPhotos = false
    @State private var showFiles = false
    var body: some View {
        Menu {
            Button {
                showPhotos = true
            } label: {
                Label(L.t("import.photos"), systemImage: "photo.on.rectangle.angled")
            }
            Button {
                showFiles = true
            } label: {
                Label(L.t("import.files"), systemImage: "folder")
            }
        } label: {
            LabelBody(titleKey: titleKey, systemImage: systemImage, tint: tint, filled: filled)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Omit `photoLibrary: .shared()` so macOS uses the privacy-preserving
        // out-of-process picker — no photo-library entitlement or prompt needed.
        .photosPicker(isPresented: $showPhotos, selection: $item, matching: .images)
        .onChange(of: item) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let img = PlatformImage(data: data) {
                    await MainActor.run { onImage(img) }
                }
            }
        }
        .fileImporter(isPresented: $showFiles,
                      allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let img = PlatformImage(data: data) {
                onImage(img)
            }
        }
    }
    #endif

    /// The pill label, factored into its own `View` so it can be used inside the
    /// PhotosPicker's Sendable label closure without capturing main-actor state.
    private struct LabelBody: View {
        var titleKey: String
        var systemImage: String
        var tint: Color
        var filled: Bool
        var body: some View {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                Text(loc: titleKey)
            }
            .font(Theme.title(16))
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .foregroundStyle(filled ? Color.white : tint)
            .background(
                Capsule().fill(filled ? tint : Color.clear)
                    .overlay(Capsule().stroke(tint, lineWidth: filled ? 0 : 2))
            )
            .shadow(color: filled ? tint.opacity(0.35) : .clear, radius: 8, y: 4)
        }
    }
}

/// The signature pill button in the collage palette.
struct PillButton: View {
    var titleKey: String
    var systemImage: String?
    var tint: Color = Theme.accent
    var filled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(loc: titleKey)
            }
            .font(Theme.title(15))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .foregroundStyle(filled ? Color.white : tint)
            .background(
                Capsule().fill(filled ? tint : Theme.panel)
                    .overlay(Capsule().stroke(filled ? Color.clear : tint.opacity(0.5), lineWidth: 1.5))
            )
        }
        .buttonStyle(.plain)
    }
}

/// A round icon button used in canvas inspectors.
struct RoundIconButton: View {
    var systemImage: String
    var tint: Color = Theme.ink
    var background: Color = Theme.card
    var action: () -> Void
    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(background).shadow(color: Theme.stickerShadow, radius: 5, y: 2))
        }
        .buttonStyle(.plain)
    }
}

/// A transient toast overlay.
struct ToastView: View {
    let message: String
    var body: some View {
        Text(message)
            .font(Theme.title(14))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Capsule().fill(Theme.ink.opacity(0.92)))
            .shadow(color: Theme.stickerShadow, radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// A dashed "torn edge" divider used in headers.
struct TornDivider: View {
    var color: Color = Theme.hairline
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 2)
            .mask(
                HStack(spacing: 4) {
                    ForEach(0..<60, id: \.self) { _ in
                        Rectangle().frame(width: 6)
                    }
                }
            )
    }
}
