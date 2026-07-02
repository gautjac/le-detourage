import SwiftUI

/// Choose the collage background: a solid color, a preset gradient, a photo, or
/// transparent.
struct BackgroundPickerSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    private let gradients: [(Color, Color)] = [
        (Theme.marigold, Theme.coral),
        (Theme.teal, Theme.sky),
        (Theme.grape, Theme.bubblegum),
        (Theme.sky, Color.white),
        (Theme.leaf, Theme.marigold),
        (Theme.coral, Theme.grape),
    ]

    var body: some View {
        SheetScaffold(titleKey: "canvas.background") {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section(titleKey: "bg.color") {
                        swatchGrid(Theme.backgroundSwatches) { color in
                            session.checkpoint()
                            session.collage.background = .color(color)
                        } isSelected: { color in
                            if case .color(let c) = session.collage.background { return c == color }
                            return false
                        }
                    }

                    section(titleKey: "bg.gradient") {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(gradients.indices, id: \.self) { i in
                                let g = gradients[i]
                                Button {
                                    Haptics.tap()
                                    session.checkpoint()
                                    session.collage.background = .gradient(g.0, g.1)
                                } label: {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(LinearGradient(colors: [g.0, g.1],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 58)
                                        .overlay(selectedRing(isGradientSelected(g)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section(titleKey: "bg.pattern") {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(PatternStyle.allCases) { style in
                                Button {
                                    Haptics.tap()
                                    session.checkpoint()
                                    session.collage.background = .pattern(style, Theme.page, Theme.coral)
                                } label: {
                                    patternSwatch(style)
                                        .overlay(selectedRing(isPatternSelected(style)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    section(titleKey: "bg.finish") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FinishOverlay.allCases) { finish in
                                    let selected = session.collage.finish == finish
                                    Button {
                                        Haptics.tap()
                                        session.checkpoint()
                                        session.collage.finish = finish
                                    } label: {
                                        Text(loc: finish.titleKey)
                                            .font(Theme.body(13))
                                            .foregroundStyle(selected ? .white : Theme.inkDim)
                                            .padding(.horizontal, 13).padding(.vertical, 8)
                                            .background(Capsule().fill(selected ? Theme.grape : Theme.card))
                                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: selected ? 0 : 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section(titleKey: "bg.photo") {
                        HStack(spacing: 12) {
                            PhotoImportButton(titleKey: "bg.photo", systemImage: "photo",
                                              tint: Theme.teal, filled: false) { img in
                                session.checkpoint()
                                session.collage.backgroundImage = img
                                session.collage.background = .photo
                            }
                            Button {
                                Haptics.tap()
                                session.checkpoint()
                                session.collage.background = .transparent
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.dashed")
                                    Text(loc: "bg.transparent")
                                }
                                .font(Theme.title(15))
                                .foregroundStyle(isTransparent ? .white : Theme.grape)
                                .padding(.horizontal, 18).padding(.vertical, 11)
                                .background(Capsule().fill(isTransparent ? Theme.grape : Color.clear)
                                    .overlay(Capsule().stroke(Theme.grape, lineWidth: 2)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
        } onDone: { dismiss() }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 12)]
    }

    private var isTransparent: Bool { session.collage.background.isTransparent }

    private func isGradientSelected(_ g: (Color, Color)) -> Bool {
        if case .gradient(let a, let b) = session.collage.background { return a == g.0 && b == g.1 }
        return false
    }

    private func isPatternSelected(_ style: PatternStyle) -> Bool {
        if case .pattern(let s, _, _) = session.collage.background { return s == style }
        return false
    }

    private func patternSwatch(_ style: PatternStyle) -> some View {
        ZStack {
            if let img = style.image(size: CGSize(width: 120, height: 116),
                                     base: Theme.page, accent: Theme.coral) {
                Image(platform: img).resizable().scaledToFill()
            } else {
                Theme.page
            }
        }
        .frame(height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
    }

    private func section<Content: View>(titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc: titleKey)
                .font(Theme.title(15))
                .foregroundStyle(Theme.inkDim)
            content()
        }
    }

    private func swatchGrid(_ colors: [Color], onPick: @escaping (Color) -> Void,
                            isSelected: @escaping (Color) -> Bool) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(colors.indices, id: \.self) { i in
                let color = colors[i]
                Button {
                    Haptics.tap(); onPick(color)
                } label: {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color)
                        .frame(height: 58)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
                        .overlay(selectedRing(isSelected(color)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectedRing(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Theme.accent, lineWidth: on ? 3.5 : 0)
    }
}

/// A shared sheet chrome: a rounded header with a title and a Done button.
struct SheetScaffold<Content: View>: View {
    var titleKey: String
    @ViewBuilder var content: () -> Content
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc: titleKey)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    Haptics.tap(); onDone()
                } label: {
                    Text(loc: "common.done")
                        .font(Theme.title(16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            content()
        }
        .background(Theme.page)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520)
        #endif
    }
}
