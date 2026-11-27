import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

// The fixture of record 437 (`FS-Z`): Alloy's streaming transcript in its island. A scroll viewport inset 10 pt from the island's rounded clip (so its corners
// are clear of the arcs) holds `.equatable()` rows whose own rounded clips (`BlockChrome`'s radius 8, a bubble's 10) are cut by the viewport's straight top
// edge. A row whose cut passes through a corner zone, or leaves under two radii of its body, opens its own crossing mask scope (`CM-B`, `CM-J`), at paint
// height 0: no scope is open around it, which is the regime `FS-Z` makes movable.

/// Where the viewport sits: inside the island (Alloy), inside the island with a compositing group around the viewport (the regime an outer scope makes),
/// or with no island at all.
enum MEArm: String, CaseIterable, CustomStringConvertible, Sendable {
    case island, outerScope, noIsland
    var description: String { rawValue }
}

/// What a block's icon draws: a rect, a path (every bundled symbol is one), a gradient.
enum MEIcon: String, CaseIterable, CustomStringConvertible, Sendable {
    case rect, path, gradient
    var description: String { rawValue }
}

/// A tool block: 31 pt tall, an icon, a title and two conditionals inside the clip, tinted chrome with a rounded clip.
struct MEBlock: Component, @MainActor Equatable {
    let id: Int
    let radius: Float
    let trailing: Bool
    var icon: MEIcon = .rect
    var content: some ElementGroup {
        HStack(spacing: 6) {
            switch icon {
            case .rect: Color.accent.opacity(0.6).frame(width: Pixels(12), height: Pixels(12))
            case .path: MEWedge().fill(Color.red).frame(width: Pixels(12), height: Pixels(12))
            case .gradient: Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)).frame(width: Pixels(12), height: Pixels(12))
            }   // an icon: a rect leaf (an image's texture is a new object each paint, which verify mode refuses to equate)
            Text("tool call \(id)")
            if trailing { Text("done") }
            if id.isMultiple(of: 2) { Text("+") }
        }
        .padding(Edges(top: Pixels(8), right: Pixels(10), bottom: Pixels(8), left: Pixels(10)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Pixels(31))
        .background(Color.accent.opacity(0.18 + 0.04 * Double(id % 3)))
        .cornerRadius(Pixels(radius))
    }
}

/// A user bubble: 49 pt tall, radius 10.
struct MEBubble: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        Text("user message \(id) with a few words")
            .padding(Edges(all: Pixels(12)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Pixels(49))
            .background(Color.green.opacity(0.2))
            .cornerRadius(Pixels(10))
    }
}

/// The streaming row: grows 42 pt a step through a fixed-height frame.
struct MEStream: Component, @MainActor Equatable {
    let lines: Int
    var content: some ElementGroup {
        Text("streaming \(lines)")
            .padding(Edges(all: Pixels(12)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Pixels(Float(49 + 42 * lines)), alignment: .topLeading)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(Pixels(10))
    }
}

/// The viewport's content, wrapped in the arm's chrome.
struct MEIsland<Viewport: ElementGroup>: Component {
    let arm: MEArm
    let viewport: Viewport
    var content: some ElementGroup {
        switch arm {
        case .island:
            HStack(spacing: 0) {
                Color.accent.frame(width: Pixels(4))
                VStack(spacing: 0) { viewport }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(Edges(top: Pixels(0), right: Pixels(10), bottom: Pixels(0), left: Pixels(10)))
            }.clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
        case .outerScope:
            HStack(spacing: 0) {
                Color.accent.frame(width: Pixels(4))
                VStack(spacing: 0) { viewport }.frame(maxWidth: .infinity, maxHeight: .infinity).compositingGroup().opacity(0.99).padding(Edges(top: Pixels(0), right: Pixels(10), bottom: Pixels(0), left: Pixels(10)))
            }.clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
        case .noIsland:
            VStack(spacing: 0) { viewport }
        }
    }
}

/// What row 0 of the fixed scroller is (`FS-Z` test 7): a plain block, a block holding a second rounded clip that crosses the first, or a block holding a
/// stroked shape (a path leaf, which a record cannot count one emission for).
enum MERowKind: String, CaseIterable, CustomStringConvertible, Sendable {
    case plain, nested, shape, matched, gradient, faded
    var description: String { rawValue }
}

/// The namespace of the matched-geometry arm.
let meSpace = Namespace.ID(owner: .child(of: nil, at: 91, name: nil))

/// A shape drawn as a path: its leaf is a path, which no record counts one emission for.
struct MEWedge: Shape, Equatable {
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        p.move(to: Point(x: rect.origin.x, y: rect.origin.y))
        p.addLine(to: Point(x: Pixels(rect.origin.x.value + rect.size.width.value), y: rect.origin.y))
        p.addLine(to: Point(x: rect.origin.x, y: Pixels(rect.origin.y.value + rect.size.height.value)))
        p.closeSubpath()
        return p
    }
}

/// Row 0 as test 7 needs it. The nested one's inner clip (radius 4, the outer's rect) crosses the outer's rounded corners wherever the row stands.
struct MEOddRow: Component, @MainActor Equatable {
    let kind: MERowKind
    let radius: Float
    let toggled: Bool
    var content: some ElementGroup {
        switch kind {
        case .plain:
            MEBlock(id: 0, radius: radius, trailing: toggled)
        case .nested:
            VStack(spacing: 0) { MEBlock(id: 0, radius: 4, trailing: toggled) }.cornerRadius(Pixels(radius))
        case .gradient:
            HStack(spacing: 6) {
                Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)).frame(width: Pixels(10), height: Pixels(10))
                Text("gradient \(toggled ? "on" : "off")")
            }
            .padding(Edges(all: Pixels(8)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Pixels(31))
            .background(Color.accent.opacity(0.2)).cornerRadius(Pixels(radius))
        case .faded:
            HStack(spacing: 6) { Text("faded \(toggled ? "on" : "off")").compositingGroup().opacity(0.9) }
                .padding(Edges(all: Pixels(8)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Pixels(31))
                .background(Color.accent.opacity(0.2)).cornerRadius(Pixels(radius))
        case .matched:
            HStack(spacing: 6) { Text("matched \(toggled ? "on" : "off")").matchedGeometryEffect(id: 1, in: meSpace) }
                .padding(Edges(all: Pixels(8)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Pixels(31))
                .background(Color.accent.opacity(0.2)).cornerRadius(Pixels(radius))
        case .shape:
            HStack(spacing: 6) {
                MEWedge().fill(Color.red).frame(width: Pixels(10), height: Pixels(10))
                Text("shape \(toggled ? "on" : "off")")
            }
            .padding(Edges(all: Pixels(8)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Pixels(31))
            .background(Color.accent.opacity(0.2)).cornerRadius(Pixels(radius))
        }
    }
}

/// A scroller of seven blocks, row 0 at the top: scrolling by `h` points leaves `h` of row 0 above the edge. The viewport is 280 pt tall and the content
/// 317, so 37 pt of scroll are available and no other row is cut by either edge below 30. `side.inputs.showExtra` toggles row 0's trailing conditional.
struct MEFixedRoot: Component {
    let side: RPSide
    let arm: MEArm
    let radius: Float
    let kind: MERowKind
    var content: some ElementGroup {
        MEIsland(arm: arm, viewport: (
            ScrollView(.vertical) {
                VStack(spacing: Pixels(10)) {
                    MEOddRow(kind: kind, radius: radius, toggled: side.inputs.showExtra).equatable()
                    ForEach(Array(1..<7), id: \.self) { k in MEBlock(id: k, radius: radius, trailing: k.isMultiple(of: 3)).equatable() }
                }
                .padding(Edges(top: Pixels(0), right: Pixels(16), bottom: Pixels(40), left: Pixels(16)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)))
            .frame(width: Pixels(360), height: Pixels(280))
    }
}

@MainActor func meFixedPair(arm: MEArm = .island, radius: Float, scale: Float, kind: MERowKind = .plain, warm: Int = 6) throws -> RPPair<some Element> {
    try RPPair(size: sz(360, 280), scale: scale, warm: warm, accessibility: false) { side in
        VStack(spacing: 0) { MEFixedRoot(side: side, arm: arm, radius: radius, kind: kind) }
    }
}

/// Scrolls both windows of the pair so that row 0 has `h` points above the edge (from where they stand: `by` more).
@MainActor func meScroll(_ pair: RPPair<some Element>, by delta: Float) async {
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: pt(150, 120), byDeltaX: 0, deltaY: -delta) }
    await rsSettle()
    pair.redraw()
}

/// The streaming transcript: Alloy's, in the island. Sixty rows (bubbles and blocks) and the streaming one, bottom-anchored.
struct MERoot: Component {
    let side: RPSide
    let arm: MEArm
    var icon: MEIcon = .rect
    var content: some ElementGroup {
        MEIsland(arm: arm, viewport: (
            ScrollViewReader { _ in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                        ForEach(Array(0..<60), id: \.self) { k in
                            if k.isMultiple(of: 3) { MEBubble(id: k).equatable() } else { MEBlock(id: k, radius: 8, trailing: k.isMultiple(of: 4), icon: icon).equatable() }
                        }
                        MEStream(lines: Int(side.inputs.offset)).equatable()
                    }.padding(Edges(top: Pixels(12), right: Pixels(16), bottom: Pixels(12), left: Pixels(16)))
                }
                .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }))
    }
}

@MainActor func mePair(arm: MEArm = .island, scale: Float, accessibility: Bool = false, warm: Int = 8, icon: MEIcon = .rect) throws -> RPPair<some Element> {
    try RPPair(size: sz(1100, 840), scale: scale, warm: warm, accessibility: accessibility) { side in VStack(spacing: 0) { MERoot(side: side, arm: arm, icon: icon) } }
}

/// One streamed step on both sides, settled, one frame each; the retaining window's frames of the step.
@MainActor func meStep(_ pair: RPPair<some Element>) async -> [FrameWork] {
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.on.resetFrameWork()
    await rsSettle()
    pair.redraw()
    return pair.on.frameWork
}

/// The allocations `body` made where they can be counted (Darwin's malloc zones, as `ScrollOffsetPixelSnapTests`); elsewhere `body` runs and the answer is 0,
/// so the ceilings hold and a test's other assertions still run.
@MainActor func meCountAllocations(_ body: () -> Void) -> Int {
    #if canImport(Darwin)
    return countAllocations(body) ?? 0
    #else
    body()
    return 0
    #endif
}

/// ``meStep`` with the retaining window's allocations of its draw counted (the off window draws first, outside the count).
@MainActor func meStepCounted(_ pair: RPPair<some Element>) async -> (frames: [FrameWork], allocations: Int) {
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.on.resetFrameWork()
    await rsSettle()
    pair.off.window.setNeedsRedraw(); pair.off.tick()
    let allocations = meCountAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() }
    pair.frames.append(pair.on.lastFrameWork)
    return (pair.on.frameWork, allocations)
}

// MARK: The deep snapshot

/// A scene whole, recursing into its groups (`FS-Z`): the rects, glyphs and images byte for byte, and for each group its quad, its filter, its mask scene and
/// its content scene in turn. `RPSnapshot` reads the top level only, and under an island the whole transcript is one group quad. Glyph atlas origins are
/// zeroed under verify mode, as `RPSnapshot` does.
@MainActor func meDeepSnapshot(_ scene: Scene) -> [Data] {
    var out: [Data] = []
    func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
    func walk(_ s: Scene, _ path: String) {
        var glyphs = s.glyphs
        if rsVerifying { for i in glyphs.indices { glyphs[i].atlasBounds.origin = MUIPoint(x: 0, y: 0) } }
        out.append(Data("\(path) counts \(s.rects.count) \(s.glyphs.count) \(s.images.count) \(s.groups.count) \(s.surfaces.count) \(s.backdrops.count)".utf8))
        out.append(bytes(s.rects)); out.append(bytes(glyphs)); out.append(bytes(s.images))
        out.append(bytes(s.groups)); out.append(bytes(s.surfaces)); out.append(bytes(s.backdrops))
        out.append(Data(String(describing: s.groupFilters).utf8))
        for (index, group) in s.groupScenes.enumerated() { walk(group, path + "/g\(index)") }
        for (index, mask) in s.groupMasks.enumerated() {
            if let mask { walk(mask, path + "/m\(index)") } else { out.append(Data("\(path)/m\(index) none".utf8)) }
        }
    }
    walk(scene, "")
    return out
}

/// What differs between two deep snapshots, or `nil`.
func meDeepDifference(_ a: [Data], _ b: [Data]) -> String? {
    if a.count != b.count { return "snapshot shape \(a.count) vs \(b.count)" }
    for (index, pair) in zip(a, b).enumerated() where pair.0 != pair.1 {
        let text = String(data: pair.0, encoding: .utf8).map { $0.count < 120 ? $0 : "" } ?? ""
        return "part \(index) \(text)"
    }
    return nil
}

/// Both windows' deep snapshots, compared.
@MainActor func meCompareDeep(_ pair: RPPair<some Element>, _ step: String) {
    let difference = meDeepDifference(meDeepSnapshot(pair.on.scene), meDeepSnapshot(pair.off.scene))
    #expect(difference == nil, "deep scene after \(step): \(difference ?? "")")
}

/// 300 empty builder units (`ForEach`) and then three rounded rows, all under one `.equatable()` occurrence: more unit ranges before a painted clip than its
/// `rangesBefore` byte holds (`FS-Z`).
struct MEMany: Component, @MainActor Equatable {
    let removed: Int
    var content: some ElementGroup {
        VStack(spacing: 0) {
            ForEach(Array(0..<300).filter { $0 != removed }, id: \.self) { _ in Color.clear.frame(width: Pixels(1), height: Pixels(0)) }
            ForEach(Array(0..<3), id: \.self) { k in MEBlock(id: k, radius: 8, trailing: false) }
        }
    }
}

@MainActor func meManyPair() throws -> RPPair<some Element> {
    try RPPair(size: sz(200, 400), scale: 1, warm: 3, accessibility: false) { side in
        VStack(spacing: 0) { MEMany(removed: side.inputs.showExtra ? 5 : -1).equatable() }
    }
}
