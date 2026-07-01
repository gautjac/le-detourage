import SwiftUI

/// The committed doodle layer, drawn over the collage when not editing. Scales
/// the reference-space strokes to the current page size.
struct DoodleLayer: View {
    let doodle: Doodle
    let referenceSize: CGSize
    let pageSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            paint(doodle.strokes, in: ctx,
                  scale: referenceSize.width > 1 ? size.width / referenceSize.width : 1)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .allowsHitTesting(false)
    }
}

/// Draw scaled strokes into a SwiftUI graphics context (shared by the layer and
/// the live editor).
func paint(_ strokes: [DoodleStroke], in ctx: GraphicsContext, scale: CGFloat) {
    for stroke in strokes where stroke.points.count > 1 {
        var path = Path()
        path.addLines(stroke.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
        ctx.stroke(path, with: .color(Doodle.color(stroke.colorIndex)),
                   style: StrokeStyle(lineWidth: max(0.5, stroke.width * scale),
                                      lineCap: .round, lineJoin: .round))
    }
}

/// The full-page freehand editor: a drawing surface over the collage plus a
/// floating tool palette. Strokes are captured in page space and converted to
/// the collage's reference space on the way out, so they scale everywhere.
/// Works identically on macOS and iOS (Apple Pencil draws through the same drag
/// gesture on iPad).
struct DoodleEditor: View {
    let pageSize: CGSize
    @Environment(Session.self) private var session

    // Working strokes and the in-progress stroke, all in page-space points.
    @State private var strokes: [DoodleStroke] = []
    @State private var current: [CGPoint] = []
    @State private var colorIndex = 0
    @State private var widthIndex = 1
    @State private var eraser = false

    private let widths: [CGFloat] = [4, 9, 18]
    private let eraseRadius: CGFloat = 16

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                paint(strokes, in: ctx, scale: 1)
                if current.count > 1 {
                    paint([DoodleStroke(points: current, colorIndex: colorIndex, width: widths[widthIndex])],
                          in: ctx, scale: 1)
                }
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .background(Color.white.opacity(0.001))   // ensure the whole page is hit-testable
            .contentShape(Rectangle())
            .gesture(drawGesture)
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .overlay(alignment: .bottom) { toolbar.padding(.bottom, 84) }
        .onAppear(perform: loadStrokes)
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
                    strokes.append(DoodleStroke(points: current, colorIndex: colorIndex,
                                                width: widths[widthIndex]))
                }
                current = []
            }
    }

    private func erase(at point: CGPoint) {
        strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - point.x, $0.y - point.y) < eraseRadius }
        }
    }

    // MARK: Reference-space conversion

    private func loadStrokes() {
        let ref = session.collage.drawingReferenceSize
        let s = ref.width > 1 ? pageSize.width / ref.width : 1
        strokes = (session.collage.doodle?.strokes ?? []).map { stroke in
            DoodleStroke(points: stroke.points.map { CGPoint(x: $0.x * s, y: $0.y * s) },
                         colorIndex: stroke.colorIndex, width: stroke.width * s)
        }
    }

    private func finish() {
        let ref = session.collage.drawingReferenceSize
        let s = pageSize.width > 1 ? ref.width / pageSize.width : 1
        let refStrokes = strokes.map { stroke in
            DoodleStroke(points: stroke.points.map { CGPoint(x: $0.x * s, y: $0.y * s) },
                         colorIndex: stroke.colorIndex, width: stroke.width * s)
        }
        session.finishDrawing(Doodle(strokes: refStrokes))
    }

    // MARK: Tool palette

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(Doodle.colors.indices, id: \.self) { i in
                    Button {
                        Haptics.tap(); eraser = false; colorIndex = i
                    } label: {
                        Circle().fill(Doodle.colors[i]).frame(width: 24, height: 24)
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
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Button { Haptics.tap(); finish() } label: {
                    Text(loc: "draw.done").font(Theme.title(15)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
            }
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
