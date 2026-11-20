import SwiftUI

struct ConversationBoardLayout {
    let board: CGRect
    let size: Int

    init(in bounds: CGSize, size: Int) {
        let side = max(0, min(bounds.width, bounds.height - 52))
        board = CGRect(x: (bounds.width - side) / 2, y: 0, width: side, height: side)
        self.size = size
    }

    var step: CGFloat { board.width / CGFloat(size) }
    var radius: CGFloat { step * 0.39 }

    func center(_ point: ConversationBoardPosition) -> CGPoint {
        CGPoint(x: board.minX + (CGFloat(point.column) + 0.5) * step,
                y: (CGFloat(point.row) + 0.5) * step)
    }

    func intersection(at point: CGPoint) -> ConversationBoardPosition? {
        guard step > 0, board.contains(point) else { return nil }
        let result = ConversationBoardPosition(row: Int(point.y / step), column: Int((point.x - board.minX) / step))
        return result.fits(size: size) ? result : nil
    }
}

struct ConversationBoardCanvas: View {
    let snapshot: ConversationBoardSnapshot
    let interactive: Bool
    let pendingPosition: ConversationBoardPosition?
    let place: (ConversationBoardPosition) -> Void
    @GestureState private var dragPoint: CGPoint?
    @State private var accessibleRow = 0
    @State private var accessibleColumn = 0

    private let coordinateSpace = "conversationBoardCanvas"
    private var size: Int { snapshot.scene.size }
    private var palette: ConversationBoardScene.Palette { snapshot.scene.palette }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.aspectRatio(1, contentMode: .fit)
            Color.clear.frame(height: 52)
        }
        .frame(maxWidth: 372)
        .overlay {
            GeometryReader { proxy in
                let layout = ConversationBoardLayout(in: proxy.size, size: size)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in draw(context, layout: layout) }
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in propose(tap.location, layout: layout) },
                                 including: interactive ? .all : .none)
                    if let color = snapshot.seat {
                        Circle()
                            .fill(stone(color))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.24)))
                            .frame(width: 38, height: 38)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                            .opacity(interactive ? 1 : 0.35)
                            .position(x: proxy.size.width / 2, y: layout.board.maxY + 26)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 3, coordinateSpace: .named(coordinateSpace))
                                    .updating($dragPoint) { value, state, transaction in
                                        transaction.disablesAnimations = true
                                        state = value.location
                                    }
                                    .onEnded { value in propose(value.location, layout: layout) },
                                including: interactive ? .all : .none
                            )
                            .allowsHitTesting(interactive)
                            .accessibilityIdentifier("assistant.board.piece")
                    }
                }
                .coordinateSpace(name: coordinateSpace)
            }
        }
        .accessibilityIdentifier("assistant.board.canvas")
        .accessibilityRepresentation {
            Text("五子棋棋盘，\(size) 行 \(size) 列，已落子 \(snapshot.pieces.count) 枚")
            if let last = snapshot.pieces.last {
                Text("上一手 \(last.color.title)，第 \(last.row + 1) 行，第 \(last.column + 1) 列")
            }
            if interactive {
                Stepper("第 \(accessibleRow + 1) 行", value: $accessibleRow, in: 0...(size - 1))
                Stepper("第 \(accessibleColumn + 1) 列", value: $accessibleColumn, in: 0...(size - 1))
                let point = ConversationBoardPosition(row: accessibleRow, column: accessibleColumn)
                Button("在此落子") { place(point) }.disabled(!snapshot.allows(point))
            }
        }
    }

    private func propose(_ location: CGPoint, layout: ConversationBoardLayout) {
        guard interactive, let point = layout.intersection(at: location), snapshot.allows(point) else { return }
        place(point)
    }

    private func draw(_ context: GraphicsContext, layout: ConversationBoardLayout) {
        guard layout.step > 0 else { return }
        context.fill(Path(roundedRect: layout.board, cornerRadius: 12), with: .color(hex(palette.board)))
        let grid = Path { path in
            for index in 0..<size {
                path.move(to: layout.center(.init(row: index, column: 0)))
                path.addLine(to: layout.center(.init(row: index, column: size - 1)))
                path.move(to: layout.center(.init(row: 0, column: index)))
                path.addLine(to: layout.center(.init(row: size - 1, column: index)))
            }
        }
        context.stroke(grid, with: .color(hex(palette.grid)), lineWidth: 1)
        let black = hex(palette.black), white = hex(palette.white)
        func fill(_ seat: ConversationBoardSnapshot.Seat) -> Color { seat == .black ? black : white }
        for piece in snapshot.pieces {
            context.fill(circle(at: layout.center(piece.position), radius: layout.radius), with: .color(fill(piece.color)))
        }
        if let last = snapshot.pieces.last {
            let center = layout.center(last.position)
            context.fill(circle(at: center, radius: max(1.5, layout.radius * 0.22)),
                         with: .color(fill(last.color == .black ? .white : .black)))
        }
        let dragged = dragPoint.flatMap(layout.intersection(at:))
        if let point = pendingPosition ?? dragged, let color = snapshot.seat, snapshot.allows(point) {
            context.fill(circle(at: layout.center(point), radius: layout.radius), with: .color(fill(color).opacity(0.55)))
        }
    }

    private func stone(_ color: ConversationBoardSnapshot.Seat) -> Color { hex(color == .black ? palette.black : palette.white) }
    private func hex(_ value: String) -> Color {
        let rgb = ConversationBoardScene.Palette.rgb(value) ?? 0
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    private func circle(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
