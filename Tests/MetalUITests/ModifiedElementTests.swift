import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Lane 2 ("`ModifiedElement`") of
// `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`: legacy
// `.padding` and `.frame` become layers of ONE flat `ModifiedElement<Base>`
// (ruling MC-A) that is observationally identical to hand-built nested `Box`es
// (ruling MC-B) and follows ruling MC-C's identity rules when a chain's layer
// count or values change at run time.
//
// Lane 1's `ModifierCompositionProofTests.swift` holds the nested-`Box` oracle
// for a flat chain (its test 4) and the phase-order, `@State` and SwiftUI-order
// proofs; this file adds what only the flat representation can get wrong: the
// inferred type, generic code over a chain, and a chain whose length changes
// without its type changing. Its instruments are copied from that file rather
// than shared, so the two files stay independent at merge.
//
// Every window test drives `drawFrameIfNeeded`, `simulateInput` and
// `simulateTick`; nothing sleeps. Red runs and mutations are recorded in each
// test's doc comment, in rulings MC-A…MC-C, and in record §10.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

@MainActor
private func click(_ platformWindow: FakePlatformWindow, at position: Point<Pixels>) {
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: position)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: position)))
}

private func centre(_ bounds: Bounds<Pixels>) -> Point<Pixels> {
    pt(bounds.origin.x.value + bounds.size.width.value / 2,
       bounds.origin.y.value + bounds.size.height.value / 2)
}

/// The root id `Frame.render` builds for an unnamed root element.
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

// MARK: - Instruments

/// What `LayerLeaf` writes down, by reference, so it survives the content
/// closure rebuilding every element each frame.
@MainActor
private final class LayerLog {
    var ids: [String: GlobalElementID] = [:]
    var bounds: [String: Bounds<Pixels>] = [:]
    var taps: [String: Int] = [:]
}

/// A reference the content closure reads, so a test can change a chain between
/// frames.
@MainActor
private final class Generation {
    var value = 0
}

/// A legacy `StyledElement` leaf with a declared pixel size, its own `@State`
/// (declared FIRST, so its slot is `$state0`) and a default click handler that
/// increments it. Lane 1's `CountingLeaf`, without the phase counters.
private struct LayerLeaf: StyledElement {
    @State var taps = 0
    var name: String
    var log: LayerLog
    var style: Style
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    init(_ name: String, log: LayerLog, width: Float = 20, height: Float = 20) {
        self.name = name
        self.log = log
        var style = Style()
        style.size = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
        self.style = style
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNode(style: style, children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.ids[name] = id
        log.bounds[name] = bounds
        var registered = handlers
        if registered.onClick == nil {
            let state = _taps
            registered.onClick = { state.wrappedValue += 1 }
        }
        pass.registerHandlers(registered, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        log.taps[name] = taps
        if let token = decoration.background {
            pass.fill(bounds, color: pass.theme[token])
        }
    }
}

/// The smallest legacy `StyledElement`, for the type-name tests: its name is
/// what `String(describing:)` prints.
private struct ChainLeaf: StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNode(style: style, children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// A `Component` that never mentions `LayerBase` or `_wrap`.
private struct ChainComp: Component {
    var content: some ElementGroup { ChainLeaf() }
}

/// An external generic `ElementGroup` that never mentions `LayerBase` or
/// `_wrap`, forwarding to one member.
private struct ChainGroup<Member: ElementGroup>: ElementGroup {
    var member: Member
    init(_ member: Member) { self.member = member }

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Member.GroupLayout) {
        member.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    mutating func prepaintGroup(layout: inout Member.GroupLayout,
                                pass: inout PrepaintPass) -> Member.GroupPrepaint {
        member.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paintGroup(layout: inout Member.GroupLayout, prepaint: inout Member.GroupPrepaint,
                             pass: inout PaintPass) {
        member.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

private func name<T>(_ value: T) -> String { String(describing: type(of: value)) }

// MARK: - The oracle's observations (lane 1 test 4's, copied)

private struct HitboxShape: Equatable, CustomStringConvertible {
    var id: GlobalElementID
    var bounds: Bounds<Pixels>
    var description: String { "\(id.component)@\(bounds.origin.x.value),\(bounds.origin.y.value) \(bounds.size.width.value)x\(bounds.size.height.value)" }
}

private struct RectShape: Equatable {
    var x: Float, y: Float, width: Float, height: Float
    var h: Float, s: Float, l: Float, a: Float

    init(_ rect: MUIRect) {
        x = rect.bounds.origin.x
        y = rect.bounds.origin.y
        width = rect.bounds.size.width
        height = rect.bounds.size.height
        h = rect.background.h
        s = rect.background.s
        l = rect.background.l
        a = rect.background.a
    }
}

/// Everything ruling MC-B compares, from one rendered frame.
private struct Observation: Equatable {
    var leafID: GlobalElementID
    var leafBounds: Bounds<Pixels>
    var hitboxes: [HitboxShape]
    var rects: [RectShape]
    var nodeCount: Int
    /// The leaf's ancestors below the root `Row`, innermost first.
    var layerIDs: [GlobalElementID]
    var animLive: [Bool]
}

@MainActor
private func observe<Root: Element>(_ make: (LayerLog) -> Root) throws -> Observation {
    let log = LayerLog()
    var root = make(log)
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                      stateTable: table)
    frame.render(&root)
    let leafID = try #require(log.ids["leaf"])
    let leafBounds = try #require(log.bounds["leaf"])
    var layerIDs: [GlobalElementID] = []
    var cursor = leafID.parent
    while let id = cursor, id != rootID {
        layerIDs.append(id)
        cursor = id.parent
    }
    return Observation(
        leafID: leafID, leafBounds: leafBounds,
        hitboxes: frame.hitboxes.map { HitboxShape(id: $0.id, bounds: $0.bounds) },
        rects: frame.scene.rects.map(RectShape.init),
        nodeCount: frame.tree.nodeCount,
        layerIDs: layerIDs,
        animLive: layerIDs.map { table.isLive(animRetentionSlot(for: $0)) })
}

private func paddingStyle(_ points: Float) -> Style {
    var style = Style()
    style.padding = Edges(all: .pixels(px(points)))
    return style
}

/// The frame layer's style, written out independently of `ModifiedElement`.
private func frameStyle(width: Float, height: Float) -> Style {
    var style = Style()
    style.alignItems = .center
    style.justifyContent = .center
    style.size = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
    return style
}

/// A `.padding(8)` written in generic code: dispatch goes through the `_wrap`
/// requirement, so over a chain it APPENDS a layer (ruling MC-A).
@MainActor
private func wrapInPadding8<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> {
    t.padding(8)
}

// MARK: - 1: one inferred type (ruling MC-A)

/// **A legacy modifier chain infers ONE concrete type, `ModifiedElement<Base>`,
/// and no ordinary modifier path introduces `AnyElement`** — the superseded
/// typed-modifier spec's "explicit `AnyElement` remains opt-in" proof (ruling
/// MC-L's table).
///
/// Three receivers, none of which mentions `LayerBase` or `_wrap`: a leaf, a
/// `Component` (whose `.frame` then `.padding(4)` reaches `ModifiedElement`'s
/// own `padding`), and an external generic group. The stored spellings
/// typecheck, and the stored `Row`'s layers still register one node each.
///
/// Mutation (record §10): a concrete
/// `extension ModifiedElement { func padding(_ points: Pixels) -> ModifiedElement<Self> }`
/// nests the component chain at run time with the build still succeeding —
/// which is why the stored spellings here, and tests 3 and 5's run-time layer,
/// avoid a `Pixels` padding on a chain.
@Test @MainActor func legacyModifierChainsInferOneConcreteType() throws {
    let leafChain = ChainLeaf().padding(4).frame(width: 60).padding(Edges(all: .pixels(px(8)))).width(70)
    let componentChain = ChainComp().frame(width: 60).padding(4)
    let groupChain = ChainGroup(ChainLeaf()).frame(width: 30)

    #expect(name(leafChain) == "ModifiedElement<ChainLeaf>", "leaf chain: \(name(leafChain))")
    #expect(name(componentChain) == "ModifiedElement<ChainComp>", "component chain: \(name(componentChain))")
    #expect(name(groupChain) == "ModifiedElement<ChainGroup<ChainLeaf>>", "group chain: \(name(groupChain))")
    for chain in [name(leafChain), name(componentChain), name(groupChain)] {
        #expect(!chain.contains("AnyElement"), "an ordinary modifier path introduced AnyElement: \(chain)")
    }
    #expect(leafChain.layerCount == 3 && componentChain.layerCount == 2 && groupChain.layerCount == 1,
            "layers \(leafChain.layerCount), \(componentChain.layerCount), \(groupChain.layerCount)")
    #expect(leafChain.style.size.width == .length(.pixels(70)),
            "a Self-returning modifier after a wrapper configures the outermost layer")

    let stored: ModifiedElement<ChainLeaf> = ChainLeaf().padding(4).frame(width: 60)
    #expect(stored.layerCount == 2)
    var row: Row<ModifiedElement<ChainLeaf>> = Row {
        ChainLeaf().frame(width: 60).padding(Edges(all: .pixels(px(8))))
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
    frame.render(&row)
    #expect(frame.tree.nodeCount == 4, "the row, two layers and the leaf; got \(frame.tree.nodeCount)")
}

// MARK: - 2: generic code over a chain (ruling MC-B)

/// **A `.padding` written in generic code over a chain is identical to the
/// flat chain** — same type, same layer count, and every observation lane 1's
/// oracle test compares, against the same hand-built nested `Box`es, each with
/// its own disagreeing oracle `try #require`d first (practices shape 15).
///
/// The chain is lane 1 test 4's with its `.padding(8)` moved into
/// `wrapInPadding8`, whose return type is `ModifiedElement<T.LayerBase>`.
///
/// Red on the skeleton (record §10). Mutation: `ModifiedElement._wrap`
/// replacing its outermost layer instead of appending one.
@Test @MainActor func aGenericWrapOverAChainIsIdenticalToTheFlatChain() throws {
    func flatChain(_ log: LayerLog) -> ModifiedElement<LayerLeaf> {
        LayerLeaf("leaf", log: log)
            .background(.accent).onClick {}
            .padding(4).id("mid")
            .frame(width: 60, height: 40)
            .background(.surface).onClick {}
            .padding(8)
            .background(.separator).onClick {}
    }
    func genericChain(_ log: LayerLog) -> ModifiedElement<LayerLeaf> {
        wrapInPadding8(
            LayerLeaf("leaf", log: log)
                .background(.accent).onClick {}
                .padding(4).id("mid")
                .frame(width: 60, height: 40)
                .background(.surface).onClick {}
        )
        .background(.separator).onClick {}
    }
    let probeLog = LayerLog()
    let flatValue = flatChain(probeLog), genericValue = genericChain(probeLog)
    try #require(name(genericValue) == name(flatValue),
                 "generic \(name(genericValue)) vs flat \(name(flatValue))")
    try #require(flatValue.layerCount == 3 && genericValue.layerCount == 3,
                 "layers: flat \(flatValue.layerCount), generic \(genericValue.layerCount)")

    let flat = try observe { log in Row { flatChain(log) } }
    let generic = try observe { log in Row { genericChain(log) } }
    let oracle = try observe { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid")
                ).background(.surface).onClick {}
            ).background(.separator).onClick {}
        }
    }
    let paddingsSwapped = try observe { log in
        Row {
            Box(style: paddingStyle(4), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(8), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid")
                ).background(.surface).onClick {}
            ).background(.separator).onClick {}
        }
    }
    let idMoved = try observe { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    )
                ).background(.surface).onClick {}
            ).background(.separator).onClick {}.id("mid")
        }
    }
    let clickDropped = try observe { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid")
                ).background(.surface)
            ).background(.separator).onClick {}
        }
    }
    let layerFewer = try observe { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: paddingStyle(4), content:
                    LayerLeaf("leaf", log: log).background(.accent).onClick {}
                ).id("mid")
            ).background(.separator).onClick {}
        }
    }

    try #require(paddingsSwapped.rects != oracle.rects, "the rect comparison cannot fail")
    try #require(idMoved.leafID != oracle.leafID, "the wrapped element's id comparison cannot fail")
    try #require(idMoved.hitboxes.map(\.id) != oracle.hitboxes.map(\.id),
                 "the hitbox id comparison cannot fail")
    try #require(clickDropped.hitboxes.count != oracle.hitboxes.count,
                 "the hitbox list comparison cannot fail")
    try #require(layerFewer.layerIDs != oracle.layerIDs && layerFewer.animLive != oracle.animLive,
                 "the $anim liveness comparison cannot fail")
    try #require(layerFewer.nodeCount != oracle.nodeCount, "the node count comparison cannot fail")
    try #require(oracle.animLive == [true, true, true], "every layer holds a live $anim slot")
    try #require(oracle.hitboxes.count == 3)

    for (label, chain) in [("generic", generic), ("flat", flat)] {
        #expect(chain.leafID == oracle.leafID, "\(label): leaf id \(chain.leafID) vs \(oracle.leafID)")
        #expect(chain.leafBounds == oracle.leafBounds, "\(label): leaf bounds")
        #expect(chain.hitboxes == oracle.hitboxes, "\(label): hitboxes \(chain.hitboxes) vs \(oracle.hitboxes)")
        #expect(chain.rects == oracle.rects, "\(label): rects")
        #expect(chain.nodeCount == oracle.nodeCount, "\(label): nodes \(chain.nodeCount) vs \(oracle.nodeCount)")
        #expect(chain.layerIDs == oracle.layerIDs, "\(label): layer ids")
        #expect(chain.animLive == oracle.animLive, "\(label): $anim liveness \(chain.animLive)")
    }
}

// MARK: - 3-5: a chain whose length or values change at run time (ruling MC-C)

/// `LayerLeaf().padding(4)`, with a padding-8 layer added when `adding`. One
/// type either way (ruling MC-A). The added layer is spelled with `Edges`, so
/// this still compiles under test 1's mutation (a concrete `Pixels` padding on
/// `ModifiedElement` that nests).
@MainActor
private func growableChain(_ log: LayerLog, adding: Bool) -> ModifiedElement<LayerLeaf> {
    var chain = LayerLeaf("leaf", log: log).padding(4)
    if adding { chain = chain.padding(Edges(all: .pixels(px(8)))) }
    return chain
}

/// **Adding a layer at run time resets the wrapped element's `@State`.** The
/// content moves one level deeper (`P/0/0` from `P/0`), which is the structural
/// reason SwiftUI's D1/D3 arms reset (ruling MC-C: argued, not measured, since
/// SwiftUI cannot express one type whose chain changes length).
///
/// Red on the skeleton, which lays the content out under the outermost id
/// whatever the layer count (record §10). Mutation: the same.
@Test @MainActor func addingALayerAtRunTimeResetsTheWrappedElementsState() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = LayerLog()
    let generation = Generation()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row { growableChain(log, adding: generation.value > 0) }
    }
    window.drawFrameIfNeeded()
    let bounds = try #require(log.bounds["leaf"])
    for _ in 0..<3 {
        click(platformWindow, at: centre(bounds))
        window.drawFrameIfNeeded()
    }
    try #require(log.taps["leaf"] == 3, "set up: three clicks; read \(String(describing: log.taps["leaf"]))")
    let before = try #require(log.ids["leaf"])

    generation.value = 1
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let after = try #require(log.ids["leaf"])
    #expect(after.parent?.parent == before.parent,
            "the content must move one level deeper: \(before) then \(after)")
    #expect(log.taps["leaf"] == 0,
            "a layer added at run time must reset the wrapped element; read \(String(describing: log.taps["leaf"]))")
}

/// **Changing a layer's VALUES keeps the wrapped element's `@State`** — SwiftUI
/// arms C and D2 (ruling MC-C). A layer's values are not part of its identity.
///
/// The leaf's x is `try #require`d to move, so the value change is shown to
/// reach layout rather than assumed.
///
/// Green on the skeleton. Mutation (record §10): an unnamed layer named by its
/// style, `ElementID("\(style.padding)")`.
@Test @MainActor func changingALayersValueKeepsTheWrappedElementsState() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = LayerLog()
    let generation = Generation()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        Row {
            LayerLeaf("leaf", log: log)
                .padding(generation.value == 0 ? 4 : 12)
                .frame(width: generation.value == 0 ? 60 : 80, height: 40)
        }
    }
    window.drawFrameIfNeeded()
    let bounds = try #require(log.bounds["leaf"])
    for _ in 0..<3 {
        click(platformWindow, at: centre(bounds))
        window.drawFrameIfNeeded()
    }
    try #require(log.taps["leaf"] == 3, "set up: three clicks; read \(String(describing: log.taps["leaf"]))")

    generation.value = 1
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let moved = try #require(log.bounds["leaf"])
    try #require(moved.origin.x != bounds.origin.x, "set up: the new values must reach layout")
    #expect(log.taps["leaf"] == 3,
            "a change of layer values must keep the wrapped element's state; read \(String(describing: log.taps["leaf"]))")
}

/// **A layer added at run time is ADOPTED by the new outermost layer** — a
/// candidate divergence with no SwiftUI analogue (ruling MC-C).
///
/// Generation 0 is `.padding(4)`; generation 1, flipped inside
/// `withAnimation(.linear(duration: 1))`, is `.padding(4).padding(8)`. The
/// outermost id `P` stays the row's index 0, so the padding-8 layer inherits
/// `P`'s `$anim` baseline of 4 and slides 4 → 8, while the new inner padding-4
/// layer at `P/0` has no baseline and snaps. The leaf's x therefore reads the
/// sum: 4 + 4 = **8** at t = 0, 4 + 6 = **10** at t = 0.5, 4 + 8 = **12**
/// settled (predicted by reading; the measured values are recorded in record
/// §10). `P`'s `$anim` slot is live at both generations; `P/0`'s is not live at
/// generation 0 (it is the leaf's id, and the leaf never animates) and is at
/// generation 1. The leaf's three taps reset (test 3's half).
///
/// Red on the skeleton, which registers one layer (record §10). Mutation: the
/// outermost layer's id keyed on the layer count.
@Test @MainActor func aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = LayerLog()
    let generation = Generation()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100,
                                                      startsDisplayLink: true) {
        Row { growableChain(log, adding: generation.value > 0) }
    }
    let p = GlobalElementID.child(of: rootID, at: 0, name: nil)
    let p0 = GlobalElementID.child(of: p, at: 0, name: nil)
    func x() -> Float? { log.bounds["leaf"]?.origin.x.value }

    platformWindow.simulateTick(timestamp: 100)
    try #require(x() == 4, "set up: one padding-4 layer; x \(String(describing: x()))")
    let bounds = try #require(log.bounds["leaf"])
    for _ in 0..<3 {
        click(platformWindow, at: centre(bounds))
        window.setNeedsRedraw()
        platformWindow.simulateTick(timestamp: 100)
    }
    try #require(log.taps["leaf"] == 3, "set up: three clicks")
    let pLiveAtZero = window.stateTable.isLive(animRetentionSlot(for: p))
    let p0LiveAtZero = window.stateTable.isLive(animRetentionSlot(for: p0))

    withAnimation(.linear(duration: 1)) {
        generation.value = 1
        window.setNeedsRedraw()
    }
    platformWindow.simulateTick(timestamp: 101)
    let atStart = x()
    let pLiveAtOne = window.stateTable.isLive(animRetentionSlot(for: p))
    let p0LiveAtOne = window.stateTable.isLive(animRetentionSlot(for: p0))
    platformWindow.simulateTick(timestamp: 101.5)
    let halfway = x()
    platformWindow.simulateTick(timestamp: 102.5)
    let settled = x()

    // The instrument's check (ruling MC-Q finding 4), before any value is
    // pinned: a SNAP reads the settled value at t = 0 and at t = 0.5, so it
    // cannot pass this. `withAnimation` rolls its parked transaction back when
    // its body requested no redraw (`Animation.swift`'s `defer`), which is why
    // the write and `setNeedsRedraw()` are both inside the body above.
    let start = try #require(atStart), mid = try #require(halfway), end = try #require(settled)
    try #require(min(start, end) < mid && mid < max(start, end),
                 "set up: the t = 0.5 reading must lie strictly between t = 0 and settled; read \(start), \(mid), \(end)")

    #expect(atStart == 8, "t = 0: the adopted outer layer starts from P's old baseline; x \(String(describing: atStart))")
    #expect(halfway == 10, "t = 0.5: x \(String(describing: halfway))")
    #expect(settled == 12, "settled: x \(String(describing: settled))")
    #expect(pLiveAtZero && pLiveAtOne, "P's $anim slot: \(pLiveAtZero), \(pLiveAtOne)")
    #expect(!p0LiveAtZero && p0LiveAtOne, "P/0's $anim slot: \(p0LiveAtZero), \(p0LiveAtOne)")
    #expect(log.taps["leaf"] == 0, "the wrapped element resets; read \(String(describing: log.taps["leaf"]))")
}
