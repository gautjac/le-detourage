import SwiftUI

/// Style a cutout: pick a photo filter, a die-cut outline weight, and an outline
/// color. Edits apply live to the canvas; Cancel reverts, Done commits (one undo
/// step). Mirrors the text-editor sheet's shape.
struct CutoutStyleSheet: View {
    @Bindable var sticker: PlacedSticker
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    // Values as they were when styling began, for Cancel.
    private let original: (filter: CutoutFilter, style: StickerStyle, color: Int)
    // Small filtered previews, computed once when the sheet opens.
    @State private var thumbnails: [CutoutFilter: PlatformImage] = [:]

    init(sticker: PlacedSticker) {
        self.sticker = sticker
        self.original = (sticker.filter, sticker.style, sticker.outlineColorIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    filterSection
                    outlineSection
                    if sticker.style != .none { colorSection }
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
        .background(Theme.page)
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
        .interactiveDismissDisabled(true)
        .task { await buildThumbnails() }
    }

    private var header: some View {
        HStack {
            Button {
                sticker.filter = original.filter
                sticker.style = original.style
                sticker.outlineColorIndex = original.color
                session.finishEditingStyle(cancelled: true)
                dismiss()
            } label: {
                Text(loc: "common.cancel").font(Theme.title(16)).foregroundStyle(Theme.inkDim)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(loc: "style.title").font(Theme.display(20)).foregroundStyle(Theme.ink)
            Spacer()
            Button {
                Haptics.tap()
                session.finishEditingStyle(cancelled: false)
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

    // MARK: Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel)
            CheckerboardBackground()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(0.5)
            if let styled = sticker.styled {
                ZStack {
                    if let outline = styled.outline {
                        Image(platform: outline).resizable().scaledToFit()
                            .scaleEffect(x: styled.outlineRatio.width, y: styled.outlineRatio.height)
                    }
                    Image(platform: styled.subject).resizable().scaledToFit()
                }
                .padding(28)
                .shadow(color: Theme.stickerShadow, radius: 8, y: 4)
            }
        }
        .frame(height: 200)
    }

    // MARK: Filters

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "style.filter").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CutoutFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }

    private func filterChip(_ filter: CutoutFilter) -> some View {
        let selected = sticker.filter == filter
        return Button {
            Haptics.tap(); sticker.filter = filter
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card)
                    if let thumb = thumbnails[filter] {
                        Image(platform: thumb).resizable().scaledToFit().padding(6)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 66, height: 66)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 3 : 1))
                Text(loc: filter.titleKey)
                    .font(Theme.body(11))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkDim)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Outline weight

    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "style.outline").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            HStack(spacing: 8) {
                ForEach(StickerStyle.allCases) { style in
                    Button {
                        Haptics.tap(); sticker.style = style
                    } label: {
                        Text(loc: outlineTitleKey(style))
                            .font(Theme.title(14))
                            .foregroundStyle(sticker.style == style ? .white : Theme.inkDim)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Capsule().fill(sticker.style == style ? Theme.grape : Theme.card))
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: sticker.style == style ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func outlineTitleKey(_ style: StickerStyle) -> String {
        switch style {
        case .none:  return "outline.none"
        case .thin:  return "outline.thin"
        case .thick: return "outline.thick"
        }
    }

    // MARK: Outline color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "style.color").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            HStack(spacing: 10) {
                ForEach(CutoutStyler.outlineColors.indices, id: \.self) { i in
                    Button {
                        Haptics.tap(); sticker.outlineColorIndex = i
                    } label: {
                        Circle()
                            .fill(CutoutStyler.outlineColors[i])
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                            .overlay(Circle().stroke(Theme.accent, lineWidth: sticker.outlineColorIndex == i ? 3 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Thumbnails

    private func buildThumbnails() async {
        guard case .cutout(let image) = sticker.kind, thumbnails.isEmpty else { return }
        for filter in CutoutFilter.allCases {
            let styled = CutoutStyler.style(image, filter: filter, style: .none, outlineColorIndex: 0)
            thumbnails[filter] = styled.subject
            await Task.yield()
        }
    }
}
