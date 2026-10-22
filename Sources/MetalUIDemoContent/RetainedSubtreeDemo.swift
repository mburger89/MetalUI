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
    /// Whether an unchanged `.equatable()` occurrence skips its build recursion (`RK-B`); off, prepaint and paint replay as at
    /// lane 1's tree. Needs ``replayPrepaint`` (a graft's prepaint is a replay).
    public var skipBuild = true
    /// The canvas pan, points: one `.offset` over every node and wire, so a pan moves each occurrence by a
    /// translation of the render effect around it and they replay translated (`RK-S`).
    public var pan: Float = 0
    /// The last adopted frame's retained-subtree counters: hits, misses, ineligible, prepaint hits, redos, translated.
    @ObservationIgnored public var counters = (hits: 0, misses: 0, ineligible: 0, prepaintHits: 0, redos: 0, translated: 0)
    /// Installed by `main.swift`: turns replay on or off in the window.
    @ObservationIgnored public var applyReplay: ((Bool) -> Void)?
    /// Installed by `main.swift`: turns prepaint replay on or off in the window.
    @ObservationIgnored public var applyPrepaintReplay: ((Bool) -> Void)?
    /// Installed by `main.swift`: turns the build skip on or off in the window.
    @ObservationIgnored public var applySkipBuild: ((Bool) -> Void)?
    /// The last adopted frame's grafts and the element requests they stood for (`RK-B`).
    @ObservationIgnored public var grafts = (count: 0, skippedRequests: 0)
    /// The last adopted frame's ineligible occurrences by reason, as text (`RW-M`); empty when none.
    @ObservationIgnored public var reasons = ""
    /// The last adopted frame's refused translations by reason, as text (`FS-F`); empty when none.
    @ObservationIgnored public var translationRefusals = ""
    /// The shift-and-scroll section's header height, points (`FS-D`): every card below it moves with it.
    public var shiftHeader: Float = 10
    /// The zoom section's scale (`RZ-A`): one `.scaleEffect` over a row of `.equatable()` cards.
    public var zoom: Double = 1
    /// The geometry card's deliveries (`RG-A`): how many times its `onGeometryChange` action ran, and the last size it read.
    /// Observed, written only from the action (which runs after a build, on a change).
    var geometryReports = 0
    var geometryLast = ""
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
        shiftHeader = 10
        zoom = 1
        geometryReports = 0
        geometryLast = ""
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
            Toggle("Skip build", isOn: Binding(get: { model.skipBuild },
                                               set: { model.skipBuild = $0; model.applySkipBuild?($0) }))
            Text("hits \(model.counters.hits)").font(size: 12)
            Text("misses \(model.counters.misses)").font(size: 12)
            Text("ineligible \(model.counters.ineligible)").font(size: 12)
            retainedDemoPrepaintReadout(model)
            Text("reasons \(model.reasons.isEmpty ? "none" : model.reasons)").font(size: 12)
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
        Text("grafted \(model.grafts.count) (\(model.grafts.skippedRequests) requests)").font(size: 12)
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
        RetainedDemoPanel().equatable()
        RetainedDemoShift()
        RetainedDemoGeometry()
        RetainedDemoZoom()
    }
    .padding(Edges(all: Pixels(24)))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

/// The panel strip (`RW-`, C14b-3): a text field, a scrolling list and a picker in one `.equatable()` component whose value
/// never changes. Dragging a node leaves it a replayed hit (its state is read, not rewritten); typing in the field, scrolling
/// the list or holding focus is a counted miss with a correct result. In steady state the strip reads 0 ineligible.
struct RetainedDemoPanel: Component, @MainActor Equatable {
    @State var query = ""
    @State var mode = 0
    static func == (l: RetainedDemoPanel, r: RetainedDemoPanel) -> Bool { true }
    var content: some ElementGroup {
        retainedDemoPanelBody(query: $query, mode: $mode)
    }
}

struct RetainedDemoPanelRow: Identifiable { let id: Int }

/// The panel's body, its own function (the Windows 1 MB stack rule).
@MainActor @ElementBuilder
private func retainedDemoPanelBody(query: Binding<String>, mode: Binding<Int>) -> some ElementGroup {
    HStack(spacing: 16) {
        Text("Panel (retained):").font(size: 12)
        TextField("Search", text: query).frame(width: Pixels(160))
        ScrollView(.vertical) {
            List(retainedDemoPanelRows(), rowHeight: Pixels(20)) { row in Text("Operation \(row.id)").font(size: 12) }
        }
        .frame(width: Pixels(200), height: Pixels(60))
        Picker("Mode", selection: mode) {
            Text("Model").tag(0)
            Text("Sketch").tag(1)
        }
    }
}

@MainActor private func retainedDemoPanelRows() -> [RetainedDemoPanelRow] {
    var rows: [RetainedDemoPanelRow] = []
    for i in 0..<30 { rows.append(RetainedDemoPanelRow(id: i)) }
    return rows
}

/// The shift-and-scroll section (`FS-D`, C14-d): a scroller of `.equatable()` cards under a header that the buttons grow and
/// shrink by 4 points. **Press +**: every card below moves down by the same layout delta and the strip reads `translated 24`
/// (or the visible count) with the element requests of a still frame; **wheel the list**: the scroll offset moves and it reads
/// the same. On a display whose scale makes the move a fraction of a device pixel the strip reads the refusal by name
/// (`fractionalTranslation`, `inexactTranslation`) and the requests of an ordinary frame. With an accessibility client active
/// the prepaint is not replayed moved (`accessibilityRecords`), the paint is.
struct RetainedDemoShift: Component {
    var content: some ElementGroup {
        retainedDemoShiftBody(retainedSubtreeDemoModel)
    }
}

/// One card of the section: a swatch and a label, value-equal for ever.
private struct RetainedDemoShiftCard: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        HStack(spacing: 6) {
            Color.accent.frame(width: Pixels(10), height: Pixels(10))
            Text("Card \(id)").font(size: 12)
        }
        .frame(width: Pixels(200), height: Pixels(20), alignment: .leading)
    }
}

/// The section's body, its own function (the Windows 1 MB stack rule).
@MainActor @ElementBuilder
private func retainedDemoShiftBody(_ model: RetainedSubtreeDemoModel) -> some ElementGroup {
    VStack(spacing: 4) {
        HStack(spacing: 12) {
            Text("Shift and scroll — header").font(size: 12)
            Button("+4") { model.shiftHeader = min(model.shiftHeader + 4, 60) }
            Button("−4") { model.shiftHeader = max(model.shiftHeader - 4, 0) }
            Text("translated \(model.counters.translated)").font(size: 12)
            Text("refused \(model.translationRefusals.isEmpty ? "none" : model.translationRefusals)").font(size: 12)
        }
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                Color.clear.frame(height: Pixels(model.shiftHeader))
                ForEach(Array(0..<24), id: \.self) { RetainedDemoShiftCard(id: $0).equatable() }
            }
        }
        .frame(width: Pixels(260), height: Pixels(100))
    }
}

/// The geometry card (`RG-A`, C14-f): an `.equatable()` card under an `.onGeometryChange` reader. **Drag a node**: the strip's
/// prepaint count includes this card, which replays its prepaint and re-notes its size into the lifecycle store, so the
/// reader reports nothing until the window is resized (`reports` stays put; `ineligible` stays 0). Before C14-f the reader tainted
/// the card's ledger and it counted ineligible every frame.
struct RetainedDemoGeometry: Component {
    var content: some ElementGroup {
        retainedDemoGeometryBody(retainedSubtreeDemoModel)
    }
}

/// The reader's card: value-equal for ever, so its prepaint replays.
private struct RetainedDemoGeometryCard: Component, @MainActor Equatable {
    let model: RetainedSubtreeDemoModel
    static func == (l: RetainedDemoGeometryCard, r: RetainedDemoGeometryCard) -> Bool { l.model === r.model }
    var content: some ElementGroup {
        Color.accent.frame(width: Pixels(120), height: Pixels(16))
            .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { size in
                model.geometryReports += 1
                model.geometryLast = "\(Int(size.width.value))x\(Int(size.height.value))"
            }
    }
}

/// The section's body, its own function (the Windows 1 MB stack rule).
@MainActor @ElementBuilder
private func retainedDemoGeometryBody(_ model: RetainedSubtreeDemoModel) -> some ElementGroup {
    HStack(spacing: 12) {
        Text("Geometry reader (retained)").font(size: 12)
        RetainedDemoGeometryCard(model: model).equatable()
        Text("reports \(model.geometryReports)").font(size: 12)
        Text("size \(model.geometryLast.isEmpty ? "-" : model.geometryLast)").font(size: 12)
    }
}

/// The zoom section (`RZ-A`, C14-i): ten `.equatable()` cards (text, a swatch, a stroked curve) under one `.scaleEffect` driven by
/// a slider. **Drag the slider**: the cards replay their paint and prepaint under the new scale and graft (the strip's `grafted`
/// rises, `redos` stays 0, the element requests of a frame stay those of a still one); the picture is the same with "Replay"
/// off. A curve is re-rastered at each new scale by the ordinary cache. Before C14-i every step read `effectNotTranslation`
/// and rebuilt all ten cards.
struct RetainedDemoZoom: Component {
    var content: some ElementGroup {
        retainedDemoZoomBody(retainedSubtreeDemoModel)
    }
}

/// One card of the section: value-equal for ever.
private struct RetainedDemoZoomCard: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("Zoom \(id)").font(size: 11).frame(width: Pixels(54), height: Pixels(14))
            Color.accent.frame(width: Pixels(54), height: Pixels(10))
            RetainedDemoZoomCurve().stroke(Color.accent, lineWidth: Pixels(2)).frame(width: Pixels(54), height: Pixels(18))
        }
    }
}

private struct RetainedDemoZoomCurve: Shape {
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        let w = rect.size.width.value, h = rect.size.height.value
        p.move(to: Point(x: Pixels(2), y: Pixels(h - 2)))
        p.addCurve(to: Point(x: Pixels(w - 2), y: Pixels(2)), control1: Point(x: Pixels(w * 0.5), y: Pixels(h)),
                   control2: Point(x: Pixels(w * 0.5), y: Pixels(0)))
        return p
    }
}

/// The section's row, its own function (the Windows 1 MB stack rule).
@MainActor @ElementBuilder
private func retainedDemoZoomRow(_ model: RetainedSubtreeDemoModel) -> some ElementGroup {
    HStack(alignment: .top, spacing: 4) {
        ForEach(Array(0..<10), id: \.self) { RetainedDemoZoomCard(id: $0).equatable() }
    }
}

/// The section's body, its own function (the Windows 1 MB stack rule).
@MainActor @ElementBuilder
private func retainedDemoZoomBody(_ model: RetainedSubtreeDemoModel) -> some ElementGroup {
    VStack(spacing: 4) {
        HStack(spacing: 12) {
            Text("Zoom (one scaleEffect)").font(size: 12)
            Slider(value: Binding(get: { model.zoom }, set: { model.zoom = $0 }), in: 0.5...2).frame(width: Pixels(160))
            Text("x\(Int(model.zoom * 100))%").font(size: 12)
            Text("grafted \(model.grafts.count)").font(size: 12)
            Text("redos \(model.counters.redos)").font(size: 12)
            Text("refused \(model.translationRefusals.isEmpty ? "none" : model.translationRefusals)").font(size: 12)
        }
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) { retainedDemoZoomRow(model) }
                .scaleEffect(model.zoom, anchor: .topLeading)
                .offset(x: Pixels(8), y: Pixels(4))
        }
        .frame(width: Pixels(760), height: Pixels(80), alignment: .topLeading)
        .clipped()
    }
}
