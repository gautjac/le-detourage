import SwiftUI

/// A little vector embellishment drawn at a fitted size — reused in the picker
/// grid and anywhere a shape needs a preview.
struct EmblemGlyph: View {
    let shape: EmblemShape
    let color: Color
    var box: CGFloat = 46

    var body: some View {
        let size = fitted(aspect: shape.aspect, in: box)
        let path = shape.renderPath(in: size)
        Group {
            switch shape.draw {
            case .fill:
                path.fill(color.opacity(shape == .tape ? 0.82 : 1))
            case .stroke:
                path.stroke(color, style: StrokeStyle(lineWidth: shape.strokeWidth(in: size),
                                                      lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func fitted(aspect: CGFloat, in box: CGFloat) -> CGSize {
        aspect >= 1 ? CGSize(width: box, height: box / aspect)
                    : CGSize(width: box * aspect, height: box)
    }
}

/// Pick a scrapbook embellishment: choose a color, then tap a shape to drop it
/// on the canvas.
struct EmbellishmentPicker: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var colorIndex = 0

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 78), spacing: 14)] }

    var body: some View {
        SheetScaffold(titleKey: "emblem.title") {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    colorSection
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(EmblemShape.allCases) { shape in
                            tile(shape)
                        }
                    }
                }
                .padding(20)
            }
        } onDone: { dismiss() }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc: "emblem.color").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
            HStack(spacing: 10) {
                ForEach(Embellishment.colors.indices, id: \.self) { i in
                    Button {
                        Haptics.tap(); colorIndex = i
                    } label: {
                        Circle().fill(Embellishment.colors[i])
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                            .overlay(Circle().stroke(Theme.accent, lineWidth: colorIndex == i ? 3 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tile(_ shape: EmblemShape) -> some View {
        Button {
            session.addEmbellishment(shape, colorIndex: colorIndex)
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
                EmblemGlyph(shape: shape, color: Embellishment.colors[colorIndex], box: 46)
            }
            .frame(height: 80)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline.opacity(0.6), lineWidth: 1))
            .shadow(color: Theme.stickerShadow, radius: 5, y: 3)
        }
        .buttonStyle(.plain)
    }
}
