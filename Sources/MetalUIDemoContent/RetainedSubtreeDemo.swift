import MetalUI
import Observation
import Foundation

/// The retained-subtree demo (C14b, spec `2026-10-13-retained-subtrees-design.md` §13, rulings
/// `SB-B`…`SB-M`), reached with `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`: a small
/// bracket-shaped window, eight nodes joined by seven wires on a canvas, each node and wire an
/// `.equatable()` component. **Drag a node**: the strip above the canvas reads, for the last frame,
/// how many `.equatable()` occurrences replayed their prepaint and paint (`hits`), re-ran them
/// (`misses`) or could not be recorded (`ineligible`): all but the dragged node and its wires replay.
/// **Untick "Replay"** and the same drag reads 0 hits and draws the same pixels. The readout is the
/// last element of the tree and shows the previous frame's counts (its own frame is not over yet).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift` do not
/// move. Each part is its own function (the Windows 1 MB stack rule), built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`. The counters and the switch are package API wired
/// by `MetalUIDemo`'s `main.swift` (`Window.testingOnFrameAdopted`, `Window.testingRetainedSubtrees`);
/// a build of the content without a window shows zeros and a switch that does nothing.
@MainActor
public func retainedSubtreeDemoContent() -> some Element {
    retainedDemoRoot(strip: RetainedDemoStrip(), canvas: RetainedDemoCanvas())
}

/// One node of the graph: a title and its rows, positioned on the canvas.
struct RetainedDemoNodeData: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
    let rows: Int
    var x: Float
    var y: Float
    static let width: Float = 140
    var height: Float { 24 + 20 * Float(rows) }
}

/// The demo's state: the nodes (observed, so a drag redraws), the replay switch and the last frame's
/// counts (ignored by observation: a write at frame adoption must not dirty the window).
@MainActor
@Observable
public final class RetainedSubtreeDemoModel {
    var nodes: [RetainedDemoNodeData]
    /// Whether `.equatable()` occurrences replay.
    public var replay = true
    /// Whether `.equatable()` occurrences replay their prepaint (`RK-E`); off is paint-only replay.
    public var replayPrepaint = true
    /// The canvas pan, points: one `.offset` over every node and wire, so a pan moves each occurrence by a
    /// translation of the render effect around it and they replay translated (`RK-S`).
    public var pan: Float = 0
    /// The last adopted frame's retained-subtree counters: hits, misses, ineligible, prepaint hits, redos, translated.
    @ObservationIgnored public var counters = (hits: 0, misses: 0, ineligible: 0, prepaintHits: 0, redos: 0, translated: 0)
    /// Installed by `main.swift`: turns replay on or off in the window.
    @ObservationIgnored public var applyReplay: ((Bool) -> Void)?
    /// Installed by `main.swift`: turns prepaint replay on or off in the window.
    @ObservationIgnored public var applyPrepaintReplay: ((Bool) -> Void)?
    @ObservationIgnored private var dragStartX: Float = 0
    @ObservationIgnored private var dragStartY: Float = 0
    @ObservationIgnored private var dragging: Int?

    /// A fresh model: eight nodes in two rows. Written with loops, not closures: the demo's tree is built
    /// off the main thread by `everyProductionTreeBuildsOnAOneMegabyteThread`, where a closure formed in a
    /// `@MainActor` initialiser checks its executor.
    public init() {
        let titles = ["Plane", "Extrude", "Boolean", "Fillet", "Chamfer", "Mirror", "Shell", "Output"]
        var made: [RetainedDemoNodeData] = []
        for i in 0..<8 {
            made.append(RetainedDemoNodeData(id: i, title: titles[i], rows: 2 + i % 3,
                                             x: Float(i % 4) * 190 + 20, y: Float(i / 4) * 150 + 20))
        }
        nodes = made
        var chain: [(Int, Int)] = []
        for i in 0..<7 { chain.append((i, i + 1)) }
        links = chain
    }

    /// Puts the nodes back where they start.
    public func reset() {
        nodes = RetainedSubtreeDemoModel().nodes
        pan = 0
        dragging = nil
    }

    func drag(_ id: Int, by translation: Size<Pixels>) {
        if dragging != id { dragging = id; dragStartX = nodes[id].x; dragStartY = nodes[id].y }
        nodes[id].x = dragStartX + translation.width.value
        nodes[id].y = dragStartY + translation.height.value
    }

    func endDrag() { dragging = nil }

    func socket(_ id: Int, output: Bool) -> (x: Float, y: Float) {
        let n = nodes[id]
        return (n.x + (output ? RetainedDemoNodeData.width : 0), n.y + 24 + 10)
    }

    /// The links: a chain through all eight nodes.
    let links: [(Int, Int)]
}

/// The one model the demo and its tests share.
@MainActor public let retainedSubtreeDemoModel = RetainedSubtreeDemoModel()

private struct RetainedDemoNode: Component, @MainActor Equatable {
    let node: RetainedDemoNodeData
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(node.title).font(size: 12).frame(width: Pixels(RetainedDemoNodeData.width - 16), height: Pixels(24),
                                                      alignment: .leading)
                ForEach(Array(0..<node.rows), id: \.self) { row in
                    Text("input \(row)").font(size: 11).foregroundColor(.secondary)
                        .frame(width: Pixels(RetainedDemoNodeData.width - 16), height: Pixels(20), alignment: .leading)
                }
            }
            .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
            .frame(width: Pixels(RetainedDemoNodeData.width), height: Pixels(node.height))
            .background(.surface, in: RoundedRectangle(cornerRadius: Pixels(8)))
            .clipShape(RoundedRectangle(cornerRadius: Pixels(8)))
            .overlay { RoundedRectangle(cornerRadius: Pixels(8)).stroke(Color.accent, lineWidth: Pixels(1)) }
        }
    }
}

private struct RetainedDemoWire: Component, @MainActor Equatable {
    let fromX: Float, fromY: Float, toX: Float, toY: Float
    var content: some ElementGroup {
        let control = max(30, abs(toX - fromX) * 0.5)
        let pad = control + 4
        let minX = min(fromX, toX) - pad, minY = min(fromY, toY) - pad
        RetainedDemoWireShape(from: Point(x: Pixels(fromX - minX), y: Pixels(fromY - minY)),
                              to: Point(x: Pixels(toX - minX), y: Pixels(toY - minY)), control: control)
            .stroke(Color.accent, lineWidth: Pixels(2))
            .frame(width: Pixels(abs(toX - fromX) + 2 * pad), height: Pixels(abs(toY - fromY) + 2 * pad))
            .offset(x: Pixels(minX), y: Pixels(minY))
    }
}

private struct RetainedDemoWireShape: Shape, Equatable {
    var from: Point<Pixels>
    var to: Point<Pixels>
    var control: Float
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        p.move(to: from)
        p.addCurve(to: to, control1: Point(x: Pixels(from.x.value + control), y: from.y),
                   control2: Point(x: Pixels(to.x.value - control), y: to.y))
        return p
    }
}

/// The canvas: the wires, then the nodes with their drag gestures.
struct RetainedDemoCanvas: Component {
    var content: some ElementGroup {
        let model = retainedSubtreeDemoModel
        let pan = Pixels(model.pan)
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.links.indices), id: \.self) { i in
                let (a, b) = model.links[i]
                let s = model.socket(a, output: true), t = model.socket(b, output: false)
                RetainedDemoWire(fromX: s.x, fromY: s.y, toX: t.x, toY: t.y).equatable()
            }
            ForEach(model.nodes) { n in
                ZStack(alignment: .topLeading) {
                    RetainedDemoNode(node: n).equatable()
                }
                .offset(x: Pixels(n.x), y: Pixels(n.y))
                .gesture(DragGesture(minimumDistance: Pixels(0))
                    .onChanged { v in retainedSubtreeDemoModel.drag(n.id, by: v.translation) }
                    .onEnded { _ in retainedSubtreeDemoModel.endDrag() })
            }
        }
        .offset(x: pan, y: Pixels(0))
        .frame(width: Pixels(800), height: Pixels(340), alignment: .topLeading)
        .clipped()
    }
}

/// The counts strip and the replay switch; the last element of the tree.
struct RetainedDemoStrip: Component {
    var content: some ElementGroup {
        let model = retainedSubtreeDemoModel
        HStack(spacing: 24) {
            Toggle("Replay", isOn: Binding(get: { model.replay },
                                           set: { model.replay = $0; model.applyReplay?($0) }))
            Toggle("Prepaint", isOn: Binding(get: { model.replayPrepaint },
                                             set: { model.replayPrepaint = $0; model.applyPrepaintReplay?($0) }))
            Text("hits \(model.counters.hits)").font(size: 12)
            Text("misses \(model.counters.misses)").font(size: 12)
            Text("ineligible \(model.counters.ineligible)").font(size: 12)
            retainedDemoPrepaintReadout(model)
            Text("(the last frame; drag a node, or the pan)").font(size: 11).foregroundColor(.secondary)
        }
    }
}

/// The prepaint half of the readout and the pan slider, its own function (the Windows 1 MB stack rule).
@MainActor
private func retainedDemoPrepaintReadout(_ model: RetainedSubtreeDemoModel) -> some ElementGroup {
    HStack(spacing: 12) {
        Text("prepaint \(model.counters.prepaintHits)").font(size: 12)
        Text("redos \(model.counters.redos)").font(size: 12)
        Text("translated \(model.counters.translated)").font(size: 12)
        Slider(value: Binding(get: { Double(model.pan) }, set: { model.pan = Float($0) }), in: 0...120)
            .frame(width: Pixels(120))
    }
}

@MainActor
private func retainedDemoHeader() -> some Element {
    Text("Retained subtrees — drag a node: all but it and its wires replay their prepaint and paint; drag the pan: all replay translated")
        .font(size: 13)
}

@MainActor
private func retainedDemoRoot(strip: some ElementGroup, canvas: some ElementGroup) -> some Element {
    VStack(spacing: 12) {
        retainedDemoHeader()
        strip
        canvas
    }
    .padding(Edges(all: Pixels(24)))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}
