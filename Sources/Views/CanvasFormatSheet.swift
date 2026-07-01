import SwiftUI

/// A canvas size preset — an aspect ratio with a friendly name and use-case.
struct CanvasFormat: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let aspect: CGFloat        // width / height
    let ratioLabel: String

    /// The standard social-media set.
    static let all: [CanvasFormat] = [
        CanvasFormat(id: "square",    titleKey: "format.square",    subtitleKey: "format.square.sub",    aspect: 1,           ratioLabel: "1:1"),
        CanvasFormat(id: "portrait",  titleKey: "format.portrait",  subtitleKey: "format.portrait.sub",  aspect: 4.0 / 5.0,   ratioLabel: "4:5"),
        CanvasFormat(id: "story",     titleKey: "format.story",     subtitleKey: "format.story.sub",     aspect: 9.0 / 16.0,  ratioLabel: "9:16"),
        CanvasFormat(id: "landscape", titleKey: "format.landscape", subtitleKey: "format.landscape.sub", aspect: 16.0 / 9.0,  ratioLabel: "16:9"),
        CanvasFormat(id: "wide",      titleKey: "format.wide",      subtitleKey: "format.wide.sub",      aspect: 1.91,        ratioLabel: "1.91:1"),
        CanvasFormat(id: "pin",       titleKey: "format.pin",       subtitleKey: "format.pin.sub",       aspect: 2.0 / 3.0,   ratioLabel: "2:3"),
    ]

    static func matching(_ aspect: CGFloat) -> CanvasFormat? {
        all.first { abs($0.aspect - aspect) < 0.02 }
    }
}

/// Pick the work-area size. Selecting a format reshapes the page; placed
/// elements keep their normalized positions and reflow.
struct CanvasFormatSheet: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 150), spacing: 14)] }

    var body: some View {
        SheetScaffold(titleKey: "format.title") {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(CanvasFormat.all) { format in
                        card(format)
                    }
                }
                .padding(20)
            }
        } onDone: { dismiss() }
    }

    private func card(_ format: CanvasFormat) -> some View {
        let selected = abs(session.collage.canvasAspect - format.aspect) < 0.02
        return Button {
            session.setCanvasAspect(format.aspect)
            dismiss()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.accent.opacity(0.15) : Theme.panel)
                        .frame(width: 66, height: 66)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Theme.accent : Theme.inkFaint)
                        .frame(width: preview(format).width, height: preview(format).height)
                }
                .frame(height: 74)

                VStack(spacing: 2) {
                    Text(loc: format.titleKey).font(Theme.title(15)).foregroundStyle(Theme.ink)
                    Text(format.ratioLabel).font(Theme.mono(12)).foregroundStyle(Theme.inkDim)
                    Text(loc: format.subtitleKey).font(Theme.body(11)).foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? Theme.accent : Theme.hairline.opacity(0.6), lineWidth: selected ? 2.5 : 1))
            .shadow(color: Theme.stickerShadow, radius: 5, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// The mini page preview, the format's aspect fitted into a ~54pt box.
    private func preview(_ format: CanvasFormat) -> CGSize {
        let box: CGFloat = 54
        return format.aspect >= 1 ? CGSize(width: box, height: box / format.aspect)
                                  : CGSize(width: box * format.aspect, height: box)
    }
}
