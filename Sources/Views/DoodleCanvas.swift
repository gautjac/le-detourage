import SwiftUI

/// The full-page freehand editor. Strokes are captured in page space; on Done
/// they're bundled into a single `Sketch` element placed exactly where they were
/// drawn — so the drawing becomes a normal, transformable canvas element (move /
/// scale / rotate / layer via the selection handles). Works identically on macOS
/// and iOS (Apple Pencil draws through the same drag gesture on iPad).
struct DoodleEditor: View {
    let pageSize: CGSize
    @Environment(Session.self) private var session

    @State private var strokes: [SketchStroke] = []
    @State private var current: [CGPoint] = []
    @State private var colorIndex = 0
    @State private var widthIndex = 1
    @State private var brush: Brush = .marker
    @State private var eraser = false

    private let widths: [CGFloat] = [4, 9, 18]
    private let eraseRadius: CGFloat = 16

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                paint(strokes, in: ctx, scale: 1)
                if current.count > 1 {
                    paint([SketchStroke(points: current, colorIndex: colorIndex,
                                        width: widths[widthIndex], brush: brush)],
                          in: ctx, scale: 1)
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white.opacity(0.001))   // make the whole page hit-testable
            .contentShape(Rectangle())
            .gesture(drawGesture)
        }
        // Fill the window and center the page-sized canvas, so the floating
        // toolbar can size to its own content instead of being squeezed to the
        // (possibly narrow) page width.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { toolbar.padding(.bottom, 84) }
    }

    // MARK: Drawing

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if eraser {
                    erase(at: value.location)
                } else {
                    current.append(value.location)
                }
            }
            .onEnded { _ in
                if !eraser, current.count > 1 {
                    strokes.append(SketchStroke(points: current, colorIndex: colorIndex,
                                                width: widths[widthIndex], brush: brush))
                }
                current = []
            }
    }

    private func erase(at point: CGPoint) {
        strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) < eraseRadius }
        }
    }

    private func finish() {
        guard let built = Sketch.build(fromPageStrokes: strokes) else {
            session.cancelDrawing()
            return
        }
        let pageShorter = min(pageSize.width, pageSize.height)
        let boxLong = max(built.box.width, built.box.height)
        let scale = boxLong / max(1, pageShorter * PlacedSticker.baseFraction)
        let position = CGPoint(x: built.center.x / pageSize.width,
                               y: built.center.y / pageSize.height)
        session.placeSketch(built.sketch, position: position, scale: scale)
    }

    // MARK: Tool palette

    private var toolbar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Brush.allCases) { b in
                        Button {
                            Haptics.tap(); eraser = false; brush = b
                        } label: {
                            BrushSwatch(brush: b, color: Sketch.color(colorIndex))
                                .frame(width: 46, height: 28)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.panel))
                                .overlay(RoundedRectangle(cornerRadius: 9)
                                    .stroke((brush == b && !eraser) ? Theme.accent : Theme.hairline,
                                            lineWidth: (brush == b && !eraser) ? 2.5 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
            .frame(maxWidth: 330)

            HStack(spacing: 7) {
                ForEach(Sketch.colors.indices, id: \.self) { i in
                    Button {
                        Haptics.tap(); eraser = false; colorIndex = i
                    } label: {
                        Circle().fill(Sketch.colors[i]).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                            .overlay(Circle().stroke(Theme.accent, lineWidth: (!eraser && colorIndex == i) ? 3 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                ForEach(widths.indices, id: \.self) { i in
                    Button {
                        Haptics.tap(); eraser = false; widthIndex = i
                    } label: {
                        Circle().fill(Theme.ink)
                            .frame(width: 6 + CGFloat(i) * 6, height: 6 + CGFloat(i) * 6)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill((!eraser && widthIndex == i) ? Theme.panel : .clear))
                    }
                    .buttonStyle(.plain)
                }
                toolIcon("eraser", active: eraser) { eraser = true }
                toolIcon("arrow.uturn.backward", active: false) { if !strokes.isEmpty { strokes.removeLast() } }
                toolIcon("trash", active: false) { strokes = [] }

                Divider().frame(height: 26)

                Button { Haptics.tap(); session.cancelDrawing() } label: {
                    Text(loc: "common.cancel").font(Theme.title(14)).foregroundStyle(Theme.inkDim)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Button { Haptics.tap(); finish() } label: {
                    Text(loc: "draw.done").font(Theme.title(15)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(strokes.isEmpty)
            }
            .fixedSize()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card)
            .shadow(color: Theme.stickerShadow, radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func toolIcon(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(active ? Theme.grape : Theme.panel))
        }
        .buttonStyle(.plain)
    }
}

/// A self-illustrating brush chip: a short sample stroke rendered with the brush,
/// so the picker previews exactly what the brush looks like.
struct BrushSwatch: View {
    let brush: Brush
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let pts = stride(from: 0.12, through: 0.88, by: 0.06).map { t -> CGPoint in
                CGPoint(x: size.width * t, y: size.height * (0.5 + 0.34 * sin(t * .pi * 2)))
            }
            renderBrush(brushOps(brush: brush, points: pts, width: 5, color: color), in: ctx, scale: 1)
        }
    }
}
