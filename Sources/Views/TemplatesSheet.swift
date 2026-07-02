import SwiftUI

/// Templates: one-tap **layouts** that auto-arrange the elements, and **themes**
/// that set a background + finish. A fast way out of the blank canvas.
struct TemplatesSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 100), spacing: 12)] }

    var body: some View {
        SheetScaffold(titleKey: "templates.title") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("templates.layouts") {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(LayoutTemplate.allCases) { layout in
                                Button {
                                    session.applyLayout(layout)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: layout.icon)
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(Theme.grape)
                                            .frame(height: 34)
                                        Text(loc: layout.titleKey)
                                            .font(Theme.body(12)).foregroundStyle(Theme.ink)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline.opacity(0.6), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .disabled(!session.collage.hasContent)
                            }
                        }
                    }

                    section("templates.themes") {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(CollageTheme.all) { theme in
                                Button {
                                    session.applyTheme(theme)
                                } label: {
                                    VStack(spacing: 8) {
                                        themeSwatch(theme)
                                        Text(loc: theme.titleKey)
                                            .font(Theme.body(12)).foregroundStyle(Theme.ink)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
        } onDone: { dismiss() }
    }

    private func themeSwatch(_ theme: CollageTheme) -> some View {
        ZStack {
            switch theme.background {
            case .color(let c): c
            case .gradient(let a, let b):
                LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .pattern(let s, let base, let accent):
                if let img = s.image(size: CGSize(width: 120, height: 100), base: base, accent: accent) {
                    Image(platform: img).resizable().scaledToFill()
                } else { base }
            case .photo, .transparent: Theme.page
            }
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
    }

    private func section<Content: View>(_ titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc: titleKey).font(Theme.title(15)).foregroundStyle(Theme.inkDim)
            content()
        }
    }
}
