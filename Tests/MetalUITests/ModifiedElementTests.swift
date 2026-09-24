import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
import Darwin
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
///
/// **A Dual fixture since stage 6a** (record §38, spec §5 lane 3): under the
/// proposal authority it is `declaredSizeNativeLeaf` (`ElementLayoutTests`), and
/// its two R tests pass `.proposal`; under the legacy one it registers through
/// `Frame`'s internal legacy registrar, and its three P tests pass `.legacy`.
/// `observe` takes the authority as a required argument.
///
/// **Stage 7b** (record §49 §6.2) retired `aGenericWrapOverAChainIsIdenticalToTheFlatChain`
/// and added N2.1 on the proposal branch.
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
        (pass.lowersToProposal
            ? declaredSizeNativeLeaf(style, pass)
            : pass.frame.requestNode(style: style, children: []), ())
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
///
/// **Registers through `Frame`'s internal legacy registrar since stage 6a**
/// (record §38, disposition P-CSS). Nothing lays it out since stage 7b trimmed
/// `legacyModifierChainsInferOneConcreteType` (record §49 §4 row 229): only
/// its type name and its chains' layer counts are read.
private struct ChainLeaf: StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.frame.requestNode(style: style, children: []), ())
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
    /// All four corners, `topLeft, topRight, bottomRight, bottomLeft`.
    var radii: [Float]

    init(_ rect: MUIRect) {
        x = rect.bounds.origin.x
        y = rect.bounds.origin.y
        width = rect.bounds.size.width
        height = rect.bounds.size.height
        h = rect.background.h
        s = rect.background.s
        l = rect.background.l
        a = rect.background.a
        radii = [rect.cornerRadii.topLeft, rect.cornerRadii.topRight,
                 rect.cornerRadii.bottomRight, rect.cornerRadii.bottomLeft]
    }

    /// This shape with its radii zeroed, to show an oracle differs in radii alone.
    var withoutRadii: RectShape {
        var copy = self
        copy.radii = [0, 0, 0, 0]
        return copy
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
private func observe<Root: Element>(authority: LayoutAuthority,
                                    _ make: (LayerLog) -> Root) throws -> Observation {
    let log = LayerLog()
    var root = make(log)
    let table = StateTable()
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                      stateTable: table, layoutAuthority: authority)
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
///
/// The second hand-spelled duplicate of `FrameSpec.style()`'s fixed-axis rows
/// (the other is `ModifierCompositionProofTests`'), carrying plan task 4's
/// axis-named `minSize` pin for the same drift reason — see that copy's
/// comment and ruling `FR-P`.
private func frameStyle(width: Float, height: Float) -> Style {
    var style = Style()
    style.alignItems = .center
    style.justifyContent = .center
    style.justifyItems = .center
    // Every oracle frame here wraps exactly one node, so it is kept in step
    // with ruling CN-N's one-cell stack lowering (plan task 6, lane 5).
    style.display = .stack
    style.size = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
    style.minSize = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
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
/// typecheck.
///
/// Green on the skeleton, whose type was already flat; red on the nesting
/// skeleton only as a build failure ("cannot assign value of type
/// 'ModifiedElement<ModifiedElement<ChainLeaf>>' to type
/// 'ModifiedElement<ChainLeaf>'"), ruling MC-R. Mutation, run on the
/// implementation (record §10): a concrete
/// `extension ModifiedElement { func padding(_ points: Pixels) -> ModifiedElement<Self> }`
/// builds, and reddens this test (`componentChain` reads
/// `"ModifiedElement<ModifiedElement<ChainComp>>"`) and both guards in
/// `ModifiedElementCompileGuards.swift` — which is why the stored spellings
/// here, test 2's flat chain, and tests 3 and 5's run-time layer, avoid a
/// `Pixels` padding on a chain.
///
/// Pinned to the legacy authority by stage 6a (CSS-structure, record §38 §4);
/// **trimmed by stage 7b** (record §49 §4 row 229, T): the `.legacy` `Frame`
/// that rendered the stored `Row` and read `nodeCount == 4` (one node per
/// layer, the legacy tree's shape) is gone, so the test is authority-free; the
/// `Row` stays as a compile-time assertion of its stored type.
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
    let _: Row<ModifiedElement<ChainLeaf>> = Row {
        ChainLeaf().frame(width: 60).padding(Edges(all: .pixels(px(8))))
    }
}

// MARK: - 2: generic code over a chain (ruling MC-B)

/// **A `.padding` written in generic code over a chain is identical to the
/// flat chain under the proposal authority** — N2.1 of stage 7b (record §49
/// §4 row 230, spec §6 lane 2), the non-CSS fact of the retired
/// `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (ruling MC-B) re-observed
/// on the production path: same type, same layer count, and every observation
/// `observe` takes, against the same hand-built nested `Box`es (each `Box`
/// lowered by `lowerLegacyNode` at site `box`, the chain's layers by the
/// layer lowering), rendered under `.proposal`.
///
/// **Every disagreeing oracle is `try #require`d to disagree with the oracle
/// before any agreeing comparison is read** (practices shape 15): paddings
/// swapped (rects), `.id("mid")` moved to the outermost layer (leaf id, hitbox
/// ids), the frame layer's `onClick` dropped (hitbox list), the frame layer
/// omitted (layer ids, `$anim` liveness), the radii exchanged (radii alone),
/// and the inner fills reordered. **The retired test's node-count comparison
/// is not carried** (`LR-EN`; the comment at the comparisons).
///
/// Red-before (record §49 §6.2, M2.1): `_wrap` replacing the outermost layer
/// instead of appending one.
@Test @MainActor func aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority() throws {
    func flatChain(_ log: LayerLog) -> ModifiedElement<LayerLeaf> {
        LayerLeaf("leaf", log: log)
            .background(.accent).onClick {}
            .padding(4).id("mid").background(.surfaceSecondary).cornerRadius(3)
            .frame(width: 60, height: 40)
            .background(.surface).cornerRadius(5).onClick {}
            // `Edges`, not `Pixels`, for test 1's reason (a `Pixels` padding on
            // a chain would stop compiling under its mutation).
            .padding(Edges(all: .pixels(px(8))))
            .background(.separator).cornerRadius(9).onClick {}
    }
    func genericChain(_ log: LayerLog) -> ModifiedElement<LayerLeaf> {
        wrapInPadding8(
            LayerLeaf("leaf", log: log)
                .background(.accent).onClick {}
                .padding(4).id("mid").background(.surfaceSecondary).cornerRadius(3)
                .frame(width: 60, height: 40)
                .background(.surface).cornerRadius(5).onClick {}
        )
        .background(.separator).cornerRadius(9).onClick {}
    }
    let probeLog = LayerLog()
    let flatValue = flatChain(probeLog), genericValue = genericChain(probeLog)
    try #require(name(genericValue) == name(flatValue),
                 "generic \(name(genericValue)) vs flat \(name(flatValue))")
    try #require(flatValue.layerCount == 3 && genericValue.layerCount == 3,
                 "layers: flat \(flatValue.layerCount), generic \(genericValue.layerCount)")

    let flat = try observe(authority: .proposal) { log in Row { flatChain(log) } }
    let generic = try observe(authority: .proposal) { log in Row { genericChain(log) } }
    let oracle = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let paddingsSwapped = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(4), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(8), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let idMoved = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}.id("mid")
        }
    }
    let clickDropped = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let layerFewer = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: paddingStyle(4), content:
                    LayerLeaf("leaf", log: log).background(.accent).onClick {}
                ).id("mid").background(.surfaceSecondary).cornerRadius(3)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let radiiSwapped = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        LayerLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(9)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(3).onClick {}
        }
    }

    // Every disagreeing oracle first.
    try #require(paddingsSwapped.rects != oracle.rects, "the rect comparison cannot fail")
    try #require(idMoved.leafID != oracle.leafID, "the wrapped element's id comparison cannot fail")
    try #require(idMoved.hitboxes.map(\.id) != oracle.hitboxes.map(\.id),
                 "the hitbox id comparison cannot fail")
    try #require(clickDropped.hitboxes.count != oracle.hitboxes.count,
                 "the hitbox list comparison cannot fail")
    try #require(layerFewer.layerIDs != oracle.layerIDs && layerFewer.animLive != oracle.animLive,
                 "the $anim liveness comparison cannot fail")
    // No node-count comparison under the proposal authority (record §49 §6.2,
    // LR-EN): the frame layer lowers to ONE native frame, the oracle's
    // `Box(style: frameStyle(...))` — a hand spelling of the LEGACY frame's
    // CSS lowering, a one-cell `display: .stack` — to an overlay inside a fixed
    // frame (`lowerShownLegacyNode`'s stack branch), so the two native trees
    // differ by one node (7 against 8) by construction. One layer = one node is
    // the legacy tree's shape (CSS-structure), as the T row of
    // `legacyModifierChainsInferOneConcreteType` rules.
    try #require(oracle.rects.count == 4, "outer, frame, padding-4 and leaf fills; read \(oracle.rects.count)")
    try #require(radiiSwapped.rects != oracle.rects, "the corner-radius comparison cannot fail")
    try #require(radiiSwapped.rects.map(\.withoutRadii) == oracle.rects.map(\.withoutRadii),
                 "the radii-swapped oracle must differ from the oracle in radii alone")
    var innerFillsSwapped = oracle.rects
    innerFillsSwapped.swapAt(1, 2)
    try #require(innerFillsSwapped != oracle.rects, "the inner-fill order comparison cannot fail")
    try #require(oracle.animLive == [true, true, true], "every layer holds a live $anim slot")
    try #require(oracle.hitboxes.count == 3)

    for (label, chain) in [("generic", generic), ("flat", flat)] {
        #expect(chain.leafID == oracle.leafID, "\(label): leaf id \(chain.leafID) vs \(oracle.leafID)")
        #expect(chain.leafBounds == oracle.leafBounds, "\(label): leaf bounds")
        #expect(chain.hitboxes == oracle.hitboxes, "\(label): hitboxes \(chain.hitboxes) vs \(oracle.hitboxes)")
        #expect(chain.rects == oracle.rects, "\(label): rects")
        #expect(chain.layerIDs == oracle.layerIDs, "\(label): layer ids")
        #expect(chain.animLive == oracle.animLive, "\(label): $anim liveness \(chain.animLive)")
    }
}

// MARK: - 2b: `.id` on a chain's outermost layer (ruling MC-C)

/// **`.id(_:)` written after a chain's LAST wrapper names the outermost layer,
/// exactly as it names the outermost of hand-built nested `Box`es** — the name
/// record §01's "name the trailing sibling" remedy puts on a sibling that
/// happens to be a modifier chain. The chain follows an unnamed sibling in a
/// `Row`, as a trailing sibling would.
///
/// Test 2 names an INNER layer only, so before this test the outermost name was
/// seen by one incidental reader: the verifier's V9 (`ModifiedElement.elementID`'s
/// getter returning `nil`) reddened only
/// `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, whose arm
/// happens to look the chain up by name. The disagreeing oracle — the same
/// nested `Box`es with the outermost name dropped, which is what V9 produces —
/// is `try #require`d to differ first. Mutation runs in record §10.
@Test @MainActor func anIDAfterAChainsLastWrapperNamesTheOutermostLayer() throws {
    func chain(_ log: LayerLog) -> ModifiedElement<LayerLeaf> {
        LayerLeaf("leaf", log: log).onClick {}
            .padding(4).onClick {}
            .padding(Edges(all: .pixels(px(8)))).onClick {}
            .id("outer")
    }
    func nested(_ log: LayerLog, named: Bool) -> Box<Box<LayerLeaf>> {
        let outer = Box(style: paddingStyle(8), content:
            Box(style: paddingStyle(4), content:
                LayerLeaf("leaf", log: log).onClick {}
            ).onClick {}
        ).onClick {}
        return named ? outer.id("outer") : outer
    }
    let probe = chain(LayerLog())
    try #require(probe.layerCount == 2 && probe.outermost.elementID == ElementID("outer"),
                 "layers \(probe.layerCount), outermost name \(String(describing: probe.outermost.elementID))")

    let flat = try observe(authority: .proposal) { log in Row { LayerLeaf("sibling", log: log); chain(log) } }
    let oracle = try observe(authority: .proposal) { log in Row { LayerLeaf("sibling", log: log); nested(log, named: true) } }
    let unnamed = try observe(authority: .proposal) { log in Row { LayerLeaf("sibling", log: log); nested(log, named: false) } }

    try #require(unnamed.leafID != oracle.leafID, "the leaf id comparison cannot fail")
    try #require(unnamed.layerIDs != oracle.layerIDs, "the layer id comparison cannot fail")
    try #require(unnamed.hitboxes.map(\.id) != oracle.hitboxes.map(\.id),
                 "the hitbox id comparison cannot fail")
    try #require(oracle.layerIDs.count == 2 && oracle.layerIDs[1].component == .named(ElementID("outer")),
                 "the oracle's outermost layer carries the name; read \(oracle.layerIDs.map(\.component))")

    #expect(flat.leafID == oracle.leafID, "leaf id under \(flat.layerIDs.map(\.component)) vs \(oracle.layerIDs.map(\.component))")
    #expect(flat.layerIDs == oracle.layerIDs, "layer ids \(flat.layerIDs.map(\.component)) vs \(oracle.layerIDs.map(\.component))")
    #expect(flat.hitboxes == oracle.hitboxes, "hitboxes \(flat.hitboxes) vs \(oracle.hitboxes)")
    #expect(flat.animLive == oracle.animLive, "$anim liveness \(flat.animLive) vs \(oracle.animLive)")
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
/// whatever the layer count: it read 3 (record §10). The same mutation on the
/// implementation reddens it again.
@Test @MainActor func addingALayerAtRunTimeResetsTheWrappedElementsState() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = LayerLog()
    let generation = Generation()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100, layoutAuthority: .proposal) {
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
/// Green on the skeleton. Mutation (record §10): an unnamed inner layer named by
/// its style, `ElementID("\(inner[k].style.padding)")`, reads 0 here.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): the `Row` root declares the 100×100 window's
/// extent on its two auto axes — what `CS-I` gave the legacy root, now spelled
/// — so the readings hold on both authorities; identity is unchanged (sizing
/// adds no layer).
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
        .width(px(100)).height(px(100))
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
/// settled (predicted by reading, then measured exactly so on the
/// implementation, record §10). `P`'s `$anim` slot is live at both generations; `P/0`'s is not live at
/// generation 0 (it is the leaf's id, and the leaf never animates) and is at
/// generation 1. The leaf's three taps reset (test 3's half).
///
/// Red on the skeleton, which registers one layer: x read 4, 6, 8 (record
/// §10). Mutation: the outermost layer's id keyed on the layer count
/// (`elementID ?? ElementID("\(layerCount)")`) snaps, and the betweenness
/// `#require` fails; so does moving `setNeedsRedraw()` out of the
/// `withAnimation` body (the instrument's check).
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): the `Row` root declares the 100×100 window's
/// extent on its two auto axes — what `CS-I` gave the legacy root, now spelled
/// — so the readings hold on both authorities; identity is unchanged (sizing
/// adds no layer).
@Test @MainActor func aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = LayerLog()
    let generation = Generation()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100,
                                                      startsDisplayLink: true) {
        Row { growableChain(log, adding: generation.value > 0) }
            .width(px(100)).height(px(100))
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

// MARK: - MC-K: allocations at 1, 2 and 3 layers

private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// `MALLOC_LOG_TYPE_ALLOCATE` from libmalloc.
private let mallocLogTypeAllocate: UInt32 = 2

nonisolated(unsafe) private var allocationsSeen = 0
nonisolated(unsafe) private var countedThread: pthread_t?
nonisolated(unsafe) private var chainedLogger: MallocLogger?

/// Runs inside malloc on every thread; must not allocate.
nonisolated(unsafe) private let countingLogger: MallocLogger = { type, a1, a2, a3, result, skip in
    if type & mallocLogTypeAllocate != 0,
       let thread = countedThread, pthread_equal(thread, pthread_self()) != 0 {
        allocationsSeen += 1
    }
    chainedLogger?(type, a1, a2, a3, result, skip)
}

/// `FreezeLoopAllocationTests.swift`'s counter, copied (the two test targets
/// could not share a private helper): heap allocations `body` makes on the
/// calling thread, through libmalloc's `malloc_logger` hook. Stage 7b's lane 1
/// deleted that file (record §49 §4), so this is now the suite's only copy and
/// its only `malloc_logger` installer.
private func countAllocations(_ body: () -> Void) throws -> Int {
    let symbol = try #require(
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger"),
        "libmalloc no longer exports malloc_logger: replace this instrument, do not skip it")
    let slot = symbol.assumingMemoryBound(to: MallocLogger?.self)

    _ = countingLogger
    _ = mallocLogTypeAllocate
    chainedLogger = slot.pointee
    allocationsSeen = 0
    countedThread = pthread_self()

    slot.pointee = countingLogger
    body()
    slot.pointee = chainedLogger

    countedThread = nil
    return allocationsSeen
}

/// Allocates exactly `count` distinct, non-empty buffers, for calibration.
@inline(never)
private func allocateBuffers(_ count: Int) -> Int {
    var total = 0
    for i in 0..<count {
        let buffer = ContiguousArray<Double>(repeating: Double(i), count: 16 + i)
        total &+= buffer.count
    }
    return total
}

private let allocationChains = 500

@MainActor @inline(never)
private func buildNested(_ layers: Int, _ id: GlobalElementID, _ pass: inout LayoutPass) {
    switch layers {
    case 1:
        var e = Box(style: paddingStyle(1), content: Box())
        _ = e.requestLayout(id, pass: &pass)
    case 2:
        var e = Box(style: paddingStyle(2), content: Box(style: paddingStyle(1), content: Box()))
        _ = e.requestLayout(id, pass: &pass)
    default:
        var e = Box(style: paddingStyle(3), content:
            Box(style: paddingStyle(2), content: Box(style: paddingStyle(1), content: Box())))
        _ = e.requestLayout(id, pass: &pass)
    }
}

@MainActor @inline(never)
private func buildFlat(_ layers: Int, _ id: GlobalElementID, _ pass: inout LayoutPass) {
    let e1 = Edges<Length>(all: .pixels(px(1)))
    let e2 = Edges<Length>(all: .pixels(px(2)))
    let e3 = Edges<Length>(all: .pixels(px(3)))
    switch layers {
    case 1:
        var e = Box().padding(e1)
        _ = e.requestLayout(id, pass: &pass)
    case 2:
        var e = Box().padding(e1).padding(e2)
        _ = e.requestLayout(id, pass: &pass)
    default:
        var e = Box().padding(e1).padding(e2).padding(e3)
        _ = e.requestLayout(id, pass: &pass)
    }
}

/// Allocations for 500 frame-builds (construction AND `requestLayout`) of one
/// arm, in a fresh `Frame` warmed with 1500 builds of the same arm, every build
/// under the same id so the `$anim` slots are overwritten rather than grown.
@MainActor
private func chainAllocations(_ build: (Int, GlobalElementID, inout LayoutPass) -> Void,
                              layers: Int) throws -> Int {
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                      stateTable: StateTable())
    var pass = LayoutPass(frame: frame)
    let id = GlobalElementID.child(of: nil, at: 0, name: nil)
    for _ in 0..<(3 * allocationChains) { build(layers, id, &pass) }
    return try countAllocations {
        for _ in 0..<allocationChains { build(layers, id, &pass) }
    }
}

/// **A modifier chain allocates a bounded amount over hand-built nested
/// `Box`es, per frame build, at 1, 2 and 3 layers** (ruling MC-K).
///
/// Each arm counts 500 builds — construction AND `requestLayout`, since a
/// content closure rebuilds the chain every frame — of `Box().padding(…)`
/// chains against `Box(style:content:)` nested to the same depth with the same
/// styles, each in a fresh `Frame` warmed with 1500 builds of the same arm.
///
/// Measured on this lane's implementation, swift.org Swift 6.3.3, debug test
/// build, per 500 builds (record §10): nested 17 002 / 27 001 / 37 004, flat
/// 17 002 / 28 501 / 39 504 — per chain +0, +3, +5, which is exactly the
/// design model's difference (`LayerAllocationModel.swift`). The bounds are
/// those measured differences.
///
/// **Mutations, each reddening its arm** (MC-K's Mutations line, record §10):
/// a `requestLayout`-local array holding every layer (`inner + [outermost]`)
/// reddens the one-layer arm (18 002 against 17 002), and the other two as
/// well (+2 per chain each); one extra array per `requestLayout` over the
/// inner layers (`let _ = inner.map { $0.style }`) reddens the two- and
/// three-layer arms (3 000 and 5 000 over nested) and not the one-layer arm,
/// whose `inner` is empty.
///
/// **A hazard this added, measured — gone since stage 7b deleted
/// `FreezeLoopAllocationTests.swift` (record §49 §4), the other installer:**
/// this file and `FreezeLoopAllocationTests.swift` each installed libmalloc's process-wide
/// `malloc_logger` hook. Run CONCURRENTLY — `swift test` without
/// `--no-parallel`, filtered to the two — the freeze-loop test's calibration
/// `#require` failed once. The whole suite passed in parallel mode once as
/// well, so the collision is a scheduling race, not a certainty. CLAUDE.md's
/// command runs `--no-parallel`, where the two cannot overlap.
///
/// **On a swiftlang toolchain the strict half is not checked**, as in
/// `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`: a bare index loop
/// allocates per element there, and this function's layer loops would read as
/// the toolchain's cost. The log says so (`MC-K-ALLOC: … NOT CHECKED`).
@Test @MainActor func aModifierChainAllocatesABoundedAmountOverNestedBoxes() throws {
    let calibration = try countAllocations { _ = allocateBuffers(16) }
    try #require(calibration >= 16,
                 "the allocation counter saw \(calibration) of 16 buffers; nothing it reports can be trusted")

    let items = Array(repeating: 1.0, count: 67)
    var sum = 0.0
    _ = try countAllocations { for i in items.indices { sum += items[i] } }
    let loopFloor = try countAllocations { for i in items.indices { sum += items[i] } }
    _ = sum

    var nested: [Int] = [], flat: [Int] = []
    for layers in 1...3 {
        nested.append(try chainAllocations(buildNested, layers: layers))
        flat.append(try chainAllocations(buildFlat, layers: layers))
    }
    let readings = "per \(allocationChains) builds, layers 1/2/3: nested \(nested), flat \(flat)"
    print("MC-K-ALLOC: \(readings); calibration \(calibration); loop floor \(loopFloor)")

    // The instrument must see this function's allocations at all: a deeper
    // nested tree costs more on every toolchain.
    try #require(nested[2] > nested[1] && nested[1] > nested[0],
                 "the counter cannot see a deeper tree's allocations: \(readings)")

    #expect(flat[0] <= nested[0], "a one-layer chain must allocate no more than one Box: \(readings)")
    if loopFloor == 0 {
        #expect(flat[1] - nested[1] <= 3 * allocationChains,
                "a two-layer chain may cost at most 3 allocations over nested boxes: \(readings)")
        #expect(flat[2] - nested[2] <= 5 * allocationChains,
                "a three-layer chain may cost at most 5 allocations over nested boxes: \(readings)")
    } else {
        print("""
            MC-K-ALLOC: two- and three-layer bounds NOT CHECKED on this toolchain — a bare \
            index loop allocates \(loopFloor) over 67 items. \(readings). Run a swift.org \
            toolchain for the strict half.
            """)
    }
}
