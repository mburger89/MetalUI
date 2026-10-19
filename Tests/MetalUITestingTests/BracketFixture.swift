import MetalUI
import MetalUITesting
import Observation

// C14b fixture (`SB-`, spec 2026-10-13-retained-subtrees-fixture.md): MetalCreator's bracket
// window, rebuilt as a MetalUI tree. 1440 x 900 at scale 2; a top bar; a 460 pt graph panel
// (header, node library, canvas of 20 nodes and 21 wires with the 160 pt cull); a 280 pt
// glass inspector; and a full-window `.onDemand` GPUSurface under all of it. No `Testing`
// import: the perf harness (`docs/probes/perf-harness`) compiles this file too.
//
// The node views are `.equatable()` on their node value plus the palette (a VALUE); the
// `.environment` arm keeps one reader of `@Environment(\.colorScheme)` and the `.environmentObject`
// arm one of `@Environment(BracketThemeStore.self)` (MetalCreator's shape): both were refused before
// C14-c (`EE-`, divergence 346) and are memoized by their readings now.

struct BracketPalette: Equatable, Sendable {
    var surface = Color(red: 0.16, green: 0.17, blue: 0.2)
    var border = Color(red: 0.35, green: 0.36, blue: 0.4)
    var text = Color(red: 0.92, green: 0.93, blue: 0.95)
    var dim = Color(red: 0.6, green: 0.62, blue: 0.68)
    var badge = Color(red: 0.2, green: 0.5, blue: 0.3)
    var accent = Color(red: 0.25, green: 0.55, blue: 0.95)
    var wire = Color(red: 0.5, green: 0.55, blue: 0.65)
}

struct BracketNodeData: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
    let inputs: Int
    let outputs: Int
    var x: Float
    var y: Float
    var rows: Int { inputs + outputs }
    static let width: Float = 168
    var height: Float { 24 + 12 + 20 * Float(rows) }
}

/// The graph model: an `@Observable` class the canvas reads, so a node drag dirties the window.
@Observable @MainActor final class BracketModel {
    static let spec: [(String, Int, Int)] = [
        ("Graph Parameter", 0, 4), ("Graph Parameter", 0, 4), ("Graph Parameter", 0, 4),
        ("Rounded Rectangle", 5, 1), ("Rectangle", 4, 1), ("Circle", 2, 1),
        ("Extrude", 4, 1), ("Extrude", 4, 1), ("Extrude", 4, 1),
        ("Grid Points", 6, 1), ("Plane", 2, 1), ("Boolean", 3, 1), ("Boolean", 3, 1),
        ("Edges By Direction", 3, 1), ("Edge Filter", 4, 1), ("Edge Set Op", 3, 1),
        ("Edges By Tag", 1, 1), ("Fillet", 2, 1), ("Chamfer", 2, 1), ("Output", 1, 1),
    ]
    static let filletIndex = 17
    var nodes: [BracketNodeData]
    /// 21 links `(from node, to node)`: the chain plus two skips.
    let links: [(Int, Int)]
    var selected = BracketModel.filletIndex
    /// The `@Observable` palette store the `.environmentObject` arm provides to each node (`EE-J`).
    @ObservationIgnored let theme = BracketThemeStore()
    /// The canvas pan: at zoom 1 with this pan 11 of 20 nodes (9...19) pass the cull.
    var panX: Float = -680
    var panY: Float = 40
    static let canvasWidth: Float = 460
    static let cullMargin: Float = 160
    private var dragStartX: Float = 0
    private var dragStartY: Float = 0
    private var dragging: Int?

    init() {
        nodes = BracketModel.spec.enumerated().map { i, s in
            BracketNodeData(id: i, title: s.0, inputs: s.1, outputs: s.2, x: Float(i) * 40, y: Float((i % 3) * 30))
        }
        links = (0..<19).map { ($0, $0 + 1) } + [(0, 3), (9, 13)]
    }

    /// The nodes the canvas builds: those whose rect meets the canvas widened by the cull margin.
    var visibleNodes: [BracketNodeData] {
        nodes.filter {
            let x = $0.x + panX
            return x + BracketNodeData.width > -Self.cullMargin && x < Self.canvasWidth + Self.cullMargin
        }
    }

    func drag(_ id: Int, translation: Size<Pixels>) {
        
        if dragging != id { dragging = id; dragStartX = nodes[id].x; dragStartY = nodes[id].y; selected = id }
        nodes[id].x = dragStartX + translation.width.value
        nodes[id].y = dragStartY + translation.height.value
    }
    func endDrag() { dragging = nil }

    /// A socket's centre in canvas space: inputs on the left edge, outputs on the right.
    func socket(node: Int, output: Bool) -> (x: Float, y: Float) {
        let n = nodes[node]
        let row = output ? n.inputs : 0
        return (n.x + panX + (output ? BracketNodeData.width : 0), n.y + panY + 24 + 12 + 20 * Float(row) + 10)
    }
}

// MARK: The node

@MainActor @ElementBuilder
func bracketNodeBody(_ n: BracketNodeData, _ p: BracketPalette, selected: Bool) -> some ElementGroup {
    ZStack(alignment: .topLeading) {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(n.title).foregroundColor(p.text)
                Spacer()
                Text("ok").foregroundColor(p.text).help("status")
                    .padding(Pixels(3))
                    .background(p.badge, in: Capsule())
            }
            .frame(height: Pixels(24))
            Spacer().frame(height: Pixels(12))
            ForEach(Array(0..<n.rows), id: \.self) { r in
                if r < n.inputs {
                    HStack(spacing: 4) {
                        Text("in \(r)").foregroundColor(p.dim)
                        Spacer()
                        Text("\(r * 3)").foregroundColor(p.text)
                    }
                    .frame(height: Pixels(20))
                } else {
                    HStack(spacing: 4) {
                        Spacer()
                        Text("out \(r - n.inputs)").foregroundColor(p.dim)
                    }
                    .frame(height: Pixels(20))
                }
            }
        }
        .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
        .frame(width: Pixels(BracketNodeData.width), height: Pixels(n.height))
        .background(p.surface, in: RoundedRectangle(cornerRadius: Pixels(8)))
        .clipShape(RoundedRectangle(cornerRadius: Pixels(8)))
        .overlay { RoundedRectangle(cornerRadius: Pixels(8)).stroke(selected ? p.accent : p.border, lineWidth: Pixels(selected ? 2 : 1)) }
        .opacity(0.98)
        .keyframeAnimator(initialValue: 0.0, trigger: 0) { content, x in
            content.offset(x: Pixels(Float(x)))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(4, duration: 0.05)
                LinearKeyframe(0, duration: 0.05)
            }
        }
        // The sockets: Color.clear plus one ZStack per dot (a circle fill and a circle border).
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(0..<n.rows), id: \.self) { r in
                ZStack {
                    Circle().fill(r < n.inputs ? p.accent : p.dim)
                    Circle().stroke(p.border, lineWidth: Pixels(1))
                }
                .frame(width: Pixels(8), height: Pixels(8))
                .offset(x: Pixels(r < n.inputs ? -4 : BracketNodeData.width - 4), y: Pixels(24 + 12 + 20 * Float(r) + 6))
            }
        }
        .frame(width: Pixels(BracketNodeData.width), height: Pixels(n.height))
    }
}

/// The value arm: palette and node are values, so `.equatable()` skips the getter.
struct BracketNodeView: Component, @MainActor Equatable {
    let node: BracketNodeData
    let palette: BracketPalette
    let selected: Bool
    var content: some ElementGroup {
        let _ = BracketStats.nodeBodies += 1
        bracketNodeBody(node, palette, selected: selected)
    }
}

/// The environment arm: the scheme comes from `@Environment`. Before C14-c `.equatable()` refused it
/// (divergence 346), so the getter ran every frame; now it is memoized by its reading (`EE-A`).
struct BracketEnvNodeView: Component, @MainActor Equatable {
    let node: BracketNodeData
    let selected: Bool
    @Environment(\.colorScheme) var scheme
    static func == (l: BracketEnvNodeView, r: BracketEnvNodeView) -> Bool { l.node == r.node && l.selected == r.selected }
    var content: some ElementGroup {
        let _ = BracketStats.nodeBodies += 1
        bracketNodeBody(node, scheme == .dark ? BracketPalette() : BracketPalette(), selected: selected)
    }
}

/// An `@Observable` palette store (MetalCreator's `ThemeStore`): the `.environmentObject` arm reads
/// `palette` through `@Environment(BracketThemeStore.self)`; `other` is a property no node reads.
@Observable @MainActor final class BracketThemeStore {
    var palette = BracketPalette()
    var other = 0
}

/// The environment-object arm: the palette comes from an `@Observable` object in the environment.
struct BracketObjNodeView: Component, @MainActor Equatable {
    let node: BracketNodeData
    let selected: Bool
    @Environment(BracketThemeStore.self) var store
    static func == (l: BracketObjNodeView, r: BracketObjNodeView) -> Bool { l.node == r.node && l.selected == r.selected }
    var content: some ElementGroup {
        let _ = BracketStats.nodeBodies += 1
        bracketNodeBody(node, store.palette, selected: selected)
    }
}

@MainActor enum BracketStats {
    static var nodeBodies = 0
    static var wireBodies = 0
    static func reset() { nodeBodies = 0; wireBodies = 0 }
}

// MARK: Wires

struct BracketWireShape: Shape, Equatable {
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

struct BracketWireView: Component, @MainActor Equatable {
    let fromX: Float, fromY: Float, toX: Float, toY: Float
    let color: Color
    var content: some ElementGroup {
        let _ = BracketStats.wireBodies += 1
        let control = max(40, abs(toX - fromX) * 0.5)
        let pad: Float = control + 4
        let minX = min(fromX, toX) - pad, minY = min(fromY, toY) - pad
        let w = abs(toX - fromX) + 2 * pad, h = abs(toY - fromY) + 2 * pad
        BracketWireShape(from: Point(x: Pixels(fromX - minX), y: Pixels(fromY - minY)),
                         to: Point(x: Pixels(toX - minX), y: Pixels(toY - minY)), control: control)
            .stroke(color, lineWidth: Pixels(2))
            .frame(width: Pixels(w), height: Pixels(h))
            .offset(x: Pixels(minX), y: Pixels(minY))
    }
}

// MARK: The canvas

/// `.value`: nodes and wires `.equatable()`, the palette a value. `.environment`: nodes read
/// `@Environment(\.colorScheme)`; `.environmentObject`: nodes read an `@Observable` store through
/// `@Environment(Type.self)` (both memoized by their readings since C14-c, `EE-J`).
/// `.panels`: `.value` plus every panel `.equatable()`.
enum BracketArm { case value, environment, panels, environmentObject }

struct BracketCanvas: Component {
    let model: BracketModel
    let palette: BracketPalette
    let arm: BracketArm
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.links.indices), id: \.self) { i in
                let (a, b) = model.links[i]
                let s = model.socket(node: a, output: true), t = model.socket(node: b, output: false)
                BracketWireView(fromX: s.x, fromY: s.y, toX: t.x, toY: t.y, color: palette.wire).equatable()
            }
            ForEach(model.visibleNodes) { n in
                ZStack(alignment: .topLeading) {
                    switch arm {
                    case .value, .panels:
                        BracketNodeView(node: n, palette: palette, selected: model.selected == n.id).equatable()
                    case .environment:
                        BracketEnvNodeView(node: n, selected: model.selected == n.id).equatable()
                    case .environmentObject:
                        BracketObjNodeView(node: n, selected: model.selected == n.id).equatable()
                            .environment(model.theme)
                    }
                }
                .offset(x: Pixels(n.x + model.panX), y: Pixels(n.y + model.panY))
                .gesture(DragGesture(minimumDistance: Pixels(0))
                    .onChanged { [model] v in model.drag(n.id, translation: v.translation) }
                    .onEnded { [model] _ in model.endDrag() })
            }
        }
        .frame(width: Pixels(BracketModel.canvasWidth), height: Pixels(560), alignment: .topLeading)
        .clipped()
    }
}

// MARK: The rest of the window

struct BracketTopBar: Component, @MainActor Equatable {
    @State var mode = 0
    static func == (l: BracketTopBar, r: BracketTopBar) -> Bool { true }
    var content: some ElementGroup {
        HStack(spacing: 8) {
            Text("Bracket")
            Picker("Mode", selection: $mode) {
                Text("Model").tag(0)
                Text("Sketch").tag(1)
            }
            Button("Undo") {}
            Button("Redo") {}
            Menu("File") { Button("New") {}; Button("Open") {} }
            Spacer()
        }
        .frame(height: Pixels(36))
    }
}

struct BracketLibraryRow: Identifiable { let id: Int }

struct BracketGraphPanel: Component, @MainActor Equatable {
    let model: BracketModel
    let palette: BracketPalette
    let arm: BracketArm
    @State var query = ""
    static func == (l: BracketGraphPanel, r: BracketGraphPanel) -> Bool { l.model === r.model && l.palette == r.palette && l.arm == r.arm }
    var content: some ElementGroup {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Project > Bracket")
                ForEach(Array(0..<7), id: \.self) { i in Button("B\(i)") {} }
            }
            .frame(height: Pixels(32))
            VStack(spacing: 4) {
                Text("Node library")
                TextField("Search", text: $query)
                ScrollView(.vertical) {
                    List((0..<40).map(BracketLibraryRow.init), rowHeight: Pixels(22)) { r in Text("Operation \(r.id)") }
                }
                .frame(height: Pixels(150))
            }
            .frame(height: Pixels(220))
            BracketCanvas(model: model, palette: palette, arm: arm)
        }
        .frame(width: Pixels(BracketModel.canvasWidth))
    }
}

struct BracketInspector: Component, @MainActor Equatable {
    static func == (l: BracketInspector, r: BracketInspector) -> Bool { true }
    @State var on = true
    @State var a = 0.3
    @State var b = 0.6
    @State var c = 0.1
    @State var d = 0.9
    var content: some ElementGroup {
        VStack(spacing: 8) {
            HStack(spacing: 4) { Text("Fillet"); Spacer(); Text("selected") }
            ForEach(Array(0..<3), id: \.self) { s in
                VStack(spacing: 4) {
                    Text("Section \(s)")
                    Slider(value: $a, in: 0...1)
                    Slider(value: $b, in: 0...1)
                    Toggle("Enabled", isOn: $on)
                    Text("summary \(s)")
                    Button("Apply") {}
                }
            }
            Slider(value: $c, in: 0...1)
            Slider(value: $d, in: 0...1)
        }
        .padding(Edges(all: Pixels(12)))
        .frame(width: Pixels(280))
        .background(.regularMaterial)
    }
}

@MainActor final class BracketViewport { var token = 0 }

struct BracketWindow: Component {
    let model: BracketModel
    let viewport: BracketViewport
    let arm: BracketArm
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            GPUSurface(redraw: .onDemand, value: viewport.token) { _ in }
            VStack(spacing: 0) {
                if arm == .panels {
                    BracketTopBar().equatable()
                    HStack(spacing: 0) {
                        BracketGraphPanel(model: model, palette: BracketPalette(), arm: arm).equatable()
                        Spacer()
                        BracketInspector().equatable()
                    }
                } else {
                    BracketTopBar()
                    HStack(spacing: 0) {
                        BracketGraphPanel(model: model, palette: BracketPalette(), arm: arm)
                        Spacer()
                        BracketInspector()
                    }
                }
            }
        }
        .frame(width: Pixels(1440), height: Pixels(900), alignment: .topLeading)
    }
}

/// The fixture window's size (points); it is drawn at scale 2.
let bracketWindowSize = Size(width: Pixels(1440), height: Pixels(900))

/// The fixture's root: the window component in a stack (a `Component` is not an `Element`).
@MainActor func bracketRoot(arm: BracketArm, model: BracketModel, viewport: BracketViewport) -> some Element {
    VStack(spacing: 0) { BracketWindow(model: model, viewport: viewport, arm: arm) }
}
