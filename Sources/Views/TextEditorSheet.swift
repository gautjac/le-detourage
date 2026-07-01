import SwiftUI

/// Compose or edit a text label: type the words, pick a lettering style, a color,
/// and an optional paper chip. Edits apply live to the canvas underneath; Cancel
/// reverts, Done commits (as a single undo step).
struct TextEditorSheet: View {
    @Bindable var sticker: PlacedSticker
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The content as it was when editing began, for Cancel.
    private let original: TextContent
    @State private var draft: TextContent
    @FocusState private var focused: Bool

    init(sticker: PlacedSticker) {
        self.sticker = sticker
        let start = sticker.text ?? TextContent()
        self.original = start
        self._draft = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    field
                    fontSection
                    colorSection
                    chipSection
                    Spacer(minLength: 8)
                }
                .padding(20)
            }
        }
        .background(Theme.page)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onChange(of: draft) { _, newValue in
            sticker.text = newValue          // live update on the canvas
        }
        .onAppear { focused = true }
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        HStack {
            Button {
                sticker.text = original                 // revert live edits
                session.finishEditingText(cancelled: true)
                dismiss()
            } label: {
                Text(loc: "common.cancel")
                    .font(Theme.title(16)).foregroundStyle(Theme.inkDim)
            }
            .buttonStyle(.plain)

            Spacer()
            Text(loc: "text.title")
                .font(Theme.display(20)).foregroundStyle(Theme.ink)
            Spacer()

            Button {
                Haptics.tap(); commit()
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

    // MARK: Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panel)
            CheckerboardBackground()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .opacity(0.5)
            Text(draft.displayString)
                .font(.system(size: 34, weight: draft.font.weight, design: draft.font.design))
                .foregroundStyle(draft.color)
                .multilineTextAlignment(.center)
                .padding(.horizontal, draft.chip ? 18 : 6)
                .padding(.vertical, draft.chip ? 12 : 4)
                .background(
                    Group {
                        if draft.chip {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(draft.chipColor)
                        }
                    }
                )
                .padding(20)
        }
        .frame(height: 130)
    }

    // MARK: Field

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc: "text.label")
                .font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            TextField(L.t("text.placeholder"), text: $draft.string, axis: .vertical)
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .focused($focused)
                .textFieldStyle(.plain)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    // MARK: Font

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "text.font").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            HStack(spacing: 10) {
                ForEach(ScrapFont.allCases) { font in
                    Button {
                        Haptics.tap(); draft.font = font
                    } label: {
                        Text("Aa")
                            .font(.system(size: 22, weight: font.weight, design: font.design))
                            .foregroundStyle(draft.font == font ? .white : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(draft.font == font ? Theme.grape : Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(Theme.hairline, lineWidth: draft.font == font ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Text color

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "text.color").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            swatchRow(TextContent.colors, selected: draft.colorIndex) { i in
                Haptics.tap(); draft.colorIndex = i
            }
        }
    }

    // MARK: Chip

    private var chipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $draft.chip.animation(.easeInOut(duration: 0.2))) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.roundedtop")
                    Text(loc: "text.chip")
                }
                .font(Theme.title(15)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.grape)

            if draft.chip {
                swatchRow(TextContent.chipColors, selected: draft.chipColorIndex) { i in
                    Haptics.tap(); draft.chipColorIndex = i
                }
            }
        }
    }

    private func swatchRow(_ colors: [Color], selected: Int, onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { i in
                Button { onPick(i) } label: {
                    Circle()
                        .fill(colors[i])
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                        .overlay(Circle().stroke(Theme.accent, lineWidth: selected == i ? 3 : 0).padding(-3))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    private func commit() {
        sticker.text = draft
        session.finishEditingText(cancelled: false)
        dismiss()
    }
}
