import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIRender
@testable import MetalUI

// Lane 1 ("proofs, and the overlay fix") of
// `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`, plan
// task 3's four open proofs measured on the wrappers as they stand:
//
// - `OverlayModifier` gives its primary and its overlay distinct identities
//   (ruling MC-E, as revised by MC-P), tests 1-3 and 9, and a key an overlay
//   declines still bubbles through the overlay-side id to its holder, test 11;
// - a modifier chain is observationally identical to hand-built nested `Box`es
//   (ruling MC-B), test 4 — the oracle lane 2's `ModifiedElement` must match;
// - `@State` survives frames under a legacy and a proposal modifier chain
//   (ruling MC-D), tests 5-6;
// - every wrapper delegates each phase exactly once, outer layers first
//   (ruling MC-F), tests 7-8;
// - modifier order changes size and placement as SwiftUI does (ruling MC-L's
//   order row, probe `docs/probes/swiftui-modifier-order.swift`), test 10.
//
// Every window test drives `drawFrameIfNeeded` and `simulateInput`; nothing
// sleeps. Each test's red run or mutation is recorded in its own doc comment
// and in the rulings' Mutations lines.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

@MainActor
private func click(_ platformWindow: FakePlatformWindow, at position: Point<Pixels>) {
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: position)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: position)))
}

@MainActor
private func movePointer(_ platformWindow: FakePlatformWindow, to position: Point<Pixels>) {
    platformWindow.simulateInput(.mouseMoved(MouseEvent(position: position)))
}

private func centre(_ bounds: Bounds<Pixels>) -> Point<Pixels> {
    pt(bounds.origin.x.value + bounds.size.width.value / 2,
       bounds.origin.y.value + bounds.size.height.value / 2)
}

/// The root id `Frame.render` builds for an unnamed root element.
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

/// Builds a group from a builder block, so a block with an `if` can be the
/// receiver of a modifier (test 9).
@MainActor
private func group<G: ElementGroup>(@ElementBuilder _ body: () -> G) -> G { body() }

// MARK: - Instruments

/// What the counting elements below write down.
///
/// A reference type because every window test's content closure builds fresh
/// element values each frame; only what the closure captured by reference
/// survives a frame (`InputDispatchTests`' `ClickLog` has the same reason).
@MainActor
private final class CompositionLog {
    var layout: [String: Int] = [:]
    var prepaint: [String: Int] = [:]
    var paint: [String: Int] = [:]
    /// The id each name was handed in its LAST prepaint.
    var ids: [String: GlobalElementID] = [:]
    /// The bounds each name was handed in its last prepaint.
    var bounds: [String: Bounds<Pixels>] = [:]
    /// The `@State` value (or a component's displayed value) read in paint.
    var taps: [String: Int] = [:]
    /// The same value read during LAYOUT, by `CountingProposalLeaf` only.
    ///
    /// **Separate from `taps` because an element's `@State` is bound again
    /// before prepaint and paint** (`Element.prepaintGroup`/`paintGroup`'s
    /// re-bind), so a paint-time read and a handler registered in prepaint work
    /// even if the group entry never bound the element: measured in lane 3,
    /// `ProposalElement`'s typed default bypassing `enteringGroupMember` left
    /// test 6 green on `taps` alone. Only a layout-time read depends on the
    /// entry's bind (ruling MC-H).
    var layoutTaps: [String: Int] = [:]
    /// Phase and handler events, in the order they happened.
    var events: [String] = []

    /// `[requestLayout, prepaint, paint]` call counts for `name`.
    func counts(_ name: String) -> [Int] {
        [layout[name, default: 0], prepaint[name, default: 0], paint[name, default: 0]]
    }
}

/// A legacy `StyledElement` leaf with a declared pixel size, its own `@State`,
/// a default click handler that increments it, and a hover fill in
/// `.textPrimary` — a token no chain in this file uses as a layer colour.
///
/// `taps` is declared FIRST so its slot is `$state0` (the slot's ordinal is the
/// property's `Mirror` index, `State.swift`).
///
/// **A Dual fixture since stage 6a** (record §38, spec §5 lane 3): under the
/// proposal authority it is `declaredSizeNativeLeaf` (`ElementLayoutTests`), and
/// its three R tests pass `.proposal`; under the legacy one it registers through
/// `Frame`'s internal legacy registrar, and its two P tests pass `.legacy`.
/// `observe` takes the authority as a required argument.
private struct CountingLeaf: StyledElement {
    @State var taps = 0
    var name: String
    var log: CompositionLog
    var style: Style
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    init(_ name: String, log: CompositionLog, width: Float = 20, height: Float = 20) {
        self.name = name
        self.log = log
        var style = Style()
        style.size = Size(width: .length(.pixels(px(width))), height: .length(.pixels(px(height))))
        self.style = style
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout[name, default: 0] += 1
        log.events.append("layout \(name)")
        return (pass.lowersToProposal
            ? declaredSizeNativeLeaf(style, pass)
            : pass.frame.requestNode(style: style, children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.prepaint[name, default: 0] += 1
        log.events.append("prepaint \(name)")
        log.ids[name] = id
        log.bounds[name] = bounds
        var registered = handlers
        if registered.onClick == nil {
            let state = _taps                 // shares the class box; see `State.swift`
            registered.onClick = { state.wrappedValue += 1 }
        }
        pass.registerHandlers(registered, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        log.paint[name, default: 0] += 1
        log.events.append("paint \(name)")
        log.taps[name] = taps
        if let token = decoration.background {
            pass.fill(bounds, color: pass.theme[token])
        }
        if pass.isHovered(id) {
            pass.fill(bounds, color: pass.theme[.textPrimary])
        }
    }
}

/// The proposal-path counterpart of `CountingLeaf`: a fixed-size native leaf
/// with the same `@State`, handler, log and hover fill. `action` replaces the
/// default handler and `displayed` replaces the logged value, so a `Component`
/// can route its OWN `@State` through this leaf.
private struct CountingProposalLeaf: ProposalElement {
    @State var taps = 0
    var name: String
    var log: CompositionLog
    var width: Double
    var height: Double
    var action: (@MainActor () -> Void)?
    var displayed: Int?

    init(_ name: String, log: CompositionLog, width: Double = 20, height: Double = 20,
         action: (@MainActor () -> Void)? = nil, displayed: Int? = nil) {
        self.name = name
        self.log = log
        self.width = width
        self.height = height
        self.action = action
        self.displayed = displayed
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.layout[name, default: 0] += 1
        log.events.append("layout \(name)")
        log.layoutTaps[name] = displayed ?? taps
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.prepaint[name, default: 0] += 1
        log.events.append("prepaint \(name)")
        log.ids[name] = id
        log.bounds[name] = bounds
        var handlers = Handlers()
        if let action {
            handlers.onClick = action
        } else {
            let state = _taps
            handlers.onClick = { state.wrappedValue += 1 }
        }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        log.paint[name, default: 0] += 1
        log.events.append("paint \(name)")
        log.taps[name] = displayed ?? taps
        if pass.isHovered(id) {
            pass.fill(bounds, color: pass.theme[.textPrimary])
        }
    }
}

/// A proposal `Component` (the `Toggle` precedent in
/// `NativeBoundaryIntegrationTests.swift`) holding its OWN `@State`; its one
/// content leaf increments the component's state and logs it.
private struct CountingProposalComponent: Component, ProposalElementGroup {
    @State var taps = 0
    var name: String
    var log: CompositionLog

    var content: some ProposalElementGroup {
        let state = _taps
        return CountingProposalLeaf(name, log: log, action: { state.wrappedValue += 1 },
                                    displayed: taps)
    }
}

/// A `Component` whose content is empty: it consumes one index and
/// contributes zero nodes (ruling MC-E's counterexample, test 9).
private struct EmptyProposalComponent: Component, ProposalElementGroup {
    var content: EmptyGroup { EmptyGroup() }
}

/// A legacy `Component` over one `CountingLeaf`, so its distributing
/// `.padding` (`StyledComponent`) can carry an arm in test 7.
private struct LegacyCountingComponent: Component {
    var log: CompositionLog
    var content: some ElementGroup { CountingLeaf("x", log: log) }
}

@MainActor
private final class Flag {
    var value = true
}

/// Whether `rect` was filled with `token` out of `theme`, component-wise
/// (`MUIHsla` is a C struct with no `Equatable`).
private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l && rect.background.a == want.a
}

// MARK: - 1-3: the overlay's identity (ruling MC-E as revised by MC-P)

/// **The overlay and its primary are two identities, and the overlay numbers
/// from 0 under an overlay-side id no cursor can produce.** `Frame` only.
///
/// The primary sits at `.child(of: modifier, at: 0)`; the overlay at
/// `.child(of: .child(of: modifier, at: -1), at: 0)` (ruling MC-P). The second
/// arm's primary is an `HStack` of two leaves and the overlay's id is the same
/// shape: nothing about the primary enters it.
///
/// Red before the first fix, measured (record §10): with the overlay's cursor
/// starting at its own 0 under the modifier's id, the first arm's two ids
/// compare equal. Red under MC-E's threaded cursor (`6ff2d31`), measured
/// (record §10): the overlay reads `.positional(1)` directly under the
/// modifier in both arms.
@Test @MainActor func theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities() throws {
    do {
        let log = CompositionLog()
        var root = ZStack {
            CountingProposalLeaf("primary", log: log, width: 60, height: 60)
                .overlay(alignment: .topLeading) {
                    CountingProposalLeaf("overlay", log: log, width: 10, height: 10)
                }
        }
        Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        let primary = try #require(log.ids["primary"])
        let overlay = try #require(log.ids["overlay"])
        let modifier = try #require(primary.parent)
        #expect(primary != overlay, "the primary and the overlay share one identity")
        #expect(primary == GlobalElementID.child(of: modifier, at: 0, name: nil))
        #expect(overlay == GlobalElementID.child(of: GlobalElementID.child(of: modifier, at: -1, name: nil),
                                                 at: 0, name: nil),
                "the overlay must number from 0 under the overlay-side id; got \(overlay.component) under \(String(describing: overlay.parent?.component))")
    }
    do {
        let log = CompositionLog()
        var root = ZStack {
            HStack {
                CountingProposalLeaf("a", log: log)
                CountingProposalLeaf("b", log: log)
            }
            .overlay(alignment: .topLeading) {
                CountingProposalLeaf("overlay", log: log, width: 10, height: 10)
            }
        }
        Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        let a = try #require(log.ids["a"])
        let overlay = try #require(log.ids["overlay"])
        let modifier = try #require(a.parent?.parent)
        #expect(overlay == GlobalElementID.child(of: GlobalElementID.child(of: modifier, at: -1, name: nil),
                                                 at: 0, name: nil),
                "the overlay's id must not depend on the primary; got \(overlay.component) under \(String(describing: overlay.parent?.component))")
    }
}

/// **A tap on the primary writes only the primary's `@State`.** Real `Window`,
/// 100×100: the `ZStack` centres the 60×60 primary at (20, 20), and the 10×10
/// overlay sits at its top-leading corner, so (70, 70) is the primary alone and
/// (25, 25) is the overlay, which registers later and ranks above it.
///
/// Red before the fix, measured (record §10): with one shared id there is one
/// `$state0` slot, so the overlay, never clicked, read the primary's 3.
@Test @MainActor func aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack {
            CountingProposalLeaf("primary", log: log, width: 60, height: 60)
                .overlay(alignment: .topLeading) {
                    CountingProposalLeaf("overlay", log: log, width: 10, height: 10)
                }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.bounds["primary"] == Bounds(origin: pt(20, 20), size: Size(width: px(60), height: px(60))))
    try #require(log.bounds["overlay"] == Bounds(origin: pt(20, 20), size: Size(width: px(10), height: px(10))))

    for _ in 0..<3 {
        click(platformWindow, at: pt(70, 70))
        window.drawFrameIfNeeded()
    }
    #expect(log.taps["primary"] == 3, "three clicks on the primary; read \(String(describing: log.taps["primary"]))")
    #expect(log.taps["overlay"] == 0,
            "the overlay was never clicked; read \(String(describing: log.taps["overlay"]))")

    click(platformWindow, at: pt(25, 25))
    window.drawFrameIfNeeded()
    #expect(log.taps["primary"] == 3, "a click on the overlay reached the primary")
    #expect(log.taps["overlay"] == 1, "one click on the overlay; read \(String(describing: log.taps["overlay"]))")
}

/// **Hovering the primary hovers only the primary.** Same geometry as test 2.
/// Each counting leaf fills its own bounds in `.textPrimary` when
/// `pass.isHovered(id)`, so the fills' widths say who believed itself hovered.
///
/// Red before the fix, measured (record §10): at (70, 70) two fills, `[60, 10]`
/// — the overlay drew its hover affordance with the pointer 40pt away.
@Test @MainActor func hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack {
            CountingProposalLeaf("primary", log: log, width: 60, height: 60)
                .overlay(alignment: .topLeading) {
                    CountingProposalLeaf("overlay", log: log, width: 10, height: 10)
                }
        }
    }
    window.drawFrameIfNeeded()

    func hoverFillWidths() -> [Float] {
        window.lastScene.rects.filter { isFilled($0, with: .textPrimary, in: window.theme) }
            .map { $0.bounds.size.width }
    }
    #expect(hoverFillWidths() == [], "no pointer event yet, so nothing is hovered")

    movePointer(platformWindow, to: pt(70, 70))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(hoverFillWidths() == [60], "pointer over the primary only; fills \(hoverFillWidths())")

    movePointer(platformWindow, to: pt(25, 25))
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(hoverFillWidths() == [10], "pointer over the overlay, which ranks above; fills \(hoverFillWidths())")
}

// MARK: - 4: the hand-built nested-Box oracle (ruling MC-B)

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
    /// The leaf's ancestors below the root `Row`, innermost first — one per
    /// layer.
    var layerIDs: [GlobalElementID]
    /// `StateTable.isLive(animRetentionSlot(for:))` per `layerIDs` entry.
    var animLive: [Bool]
}

@MainActor
private func observe<Root: Element>(authority: LayoutAuthority,
                                    _ make: (CompositionLog) -> Root) throws -> Observation {
    let log = CompositionLog()
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

/// `Box`'s three phases, copied, **minus its `animated(_:_:for:pass:)` call** —
/// the disagreeing oracle for test 4's `$anim` observation at an equal layer
/// count (critic round 2, finding 6). A layer count that differs already
/// changes `animLive`'s length; only this wrapper shows that the comparison sees
/// ONE inner layer that skipped the helper, lane 2's likeliest bug.
///
/// **A Dual fixture since stage 7b** (record §49 §6.2, N2.2): under the
/// proposal authority it lowers through `lowerLegacyNode` at site `box`, as
/// `Box` does, still without the `animated` call; under the legacy one it
/// registers through `Frame`'s internal legacy registrar (stage 6a, P-CSS).
private struct BoxWithoutAnimated<Content: ElementGroup>: StyledElement {
    var style: Style
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    var content: Content

    init(style: Style, content: Content) {
        self.style = style
        self.content = content
    }

    struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        // `Box.requestLayout` calls `animated(style, decoration, for: id, pass:)` here.
        let node = pass.lowersToProposal
            ? pass.lowerLegacyNode(style, declared: style, children: children, site: .box)
            : pass.frame.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        pass.registerHandlers(handlers, at: bounds, id: id)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        if let color = animatedBackground(decoration, for: id, pass: &pass) {
            pass.fill(bounds, color: color, cornerRadii: Corners(all: decoration.cornerRadius))
        }
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// The frame layer's style — `FrameModifier.init`'s until lane 2 deleted that
/// type, `ElementGroup.frame`'s layer since — written out independently of it.
///
/// **A drift obligation, not a redness one** (frame-sizing ruling `FR-P`).
/// Plan task 4's lane 2 gave `FrameSpec.style()` the axis-named `minSize` pin
/// that keeps a fixed frame from shrinking, and running each candidate lowering
/// over the whole suite showed that nothing here moves either way. This oracle
/// is a hand-spelled duplicate of the lowering, and the suite has demonstrated
/// it will not tell you when the two diverge, so it is kept in step by hand, in
/// the same commit as the lowering changes.
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

/// **A modifier chain is observationally identical to hand-built nested
/// `Box`es** — ruling MC-B's oracle, written before lane 2's `ModifiedElement`
/// exists, so that lane 2 staying green is the migration proof.
///
/// The chain carries three layers around the leaf (padding 4 named `"mid"`, a
/// 60×40 frame, padding 8), four backgrounds and three click handlers. **Two
/// INNER layers fill** (padding 4 `.surfaceSecondary` r3, the frame `.surface`
/// r5) and the outermost fills `.separator` r9, so the order of inner fills and
/// each inner layer's own radius are both observable; `RectShape` compares all
/// four corner radii (lane 2's verifier round: before it, with one inner fill
/// and no radii, mutations N3 and N8 below left the whole suite green). The oracle is one
/// `Box(style:decoration:content:)` per layer with the same style, and the
/// layer's own `Self`-returning modifiers applied to that `Box`. **The oracle
/// side never runs a modifier-wrapper's code** (`.padding`/`.frame`), so a
/// mutation to the wrapper cannot move it (practices shape 12).
///
/// **One disagreeing oracle per observation** (practices shape 15), each
/// `try #require`d to differ from the oracle before the real comparison:
///
/// - rects: paddings 4 and 8 swapped;
/// - the wrapped element's id and the hitbox ids: `.id("mid")` moved from the
///   padding-4 layer (the one it follows in the chain, ruling MC-C) to the
///   outermost padding-8 layer;
/// - the hitbox list: the frame layer's `onClick` dropped;
/// - `$anim` liveness and node count: the frame layer omitted;
/// - `$anim` liveness at an EQUAL layer count: the frame layer built as a
///   `BoxWithoutAnimated`, which must read `[true, false, true]` against the
///   oracle's `[true, true, true]` (critic round 2, finding 6: the layer-fewer
///   oracle differs only in length, so it never showed the comparison can see
///   one dead slot);
/// - corner radii: padding 4's radius and the outermost's exchanged, required
///   to differ and to be EQUAL once radii are zeroed;
/// - inner fill order: the oracle's rects with the two inner fills exchanged.
///
/// Green on arrival. Mutation (lane 1, on `FrameModifier` at `2571d4a`, record
/// §10): `FrameModifier.prepaint` registering its handlers after its content.
/// Lane 2's mutations of `ModifiedElement`, each reddening this test (record
/// §10): `_wrap` replacing instead of appending; content under the outermost
/// id; inner layers skipping `animated` or `registerHandlers`; inner layers
/// taking the outermost id; `.id` on the wrong layer; layers registered
/// innermost-first or after their contents; fills after the content; content
/// painted once per inner layer; layer styles minted outermost-first; and,
/// since the verifier round, the inner paint loop run innermost-first (N8) and
/// an inner fill given the outermost layer's radius (N3), each 3 issues across
/// this test and lane 2's test 2.
///
/// **What it cannot see:** a cursor offset beneath the named padding-4 layer.
/// A name replaces the index, so `FrameModifier`'s content cursor starting at
/// 1 leaves every id here unchanged and this test green; the unnamed chain in
/// `stateSurvivesFramesUnderALegacyModifierChain` reddens (ruling MC-O item 6).
///
/// Pinned to the legacy authority by stage 6a (CSS-structure, record §38 §4).
@Test @MainActor func aModifierChainIsIdenticalToHandBuiltNestedBoxes() throws {
    let chain = try observe(authority: .legacy) { log in
        Row {
            CountingLeaf("leaf", log: log)
                .background(.accent).onClick {}
                .padding(4).id("mid").background(.surfaceSecondary).cornerRadius(3)
                .frame(width: 60, height: 40)
                .background(.surface).cornerRadius(5).onClick {}
                .padding(8)
                .background(.separator).cornerRadius(9).onClick {}
        }
    }
    let oracle = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let paddingsSwapped = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(4), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(8), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let idMoved = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}.id("mid")
        }
    }
    let clickDropped = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let animSkipped = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                BoxWithoutAnimated(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let layerFewer = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: paddingStyle(4), content:
                    CountingLeaf("leaf", log: log).background(.accent).onClick {}
                ).id("mid").background(.surfaceSecondary).cornerRadius(3)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }

    // The radii-swapped oracle: the padding-4 layer's radius and the outermost
    // layer's exchanged, every other declaration unchanged.
    let radiiSwapped = try observe(authority: .legacy) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(9)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(3).onClick {}
        }
    }

    // Each disagreeing oracle must differ in the observation it is named for.
    try #require(paddingsSwapped.rects != oracle.rects, "the rect comparison cannot fail")
    try #require(idMoved.leafID != oracle.leafID, "the wrapped element's id comparison cannot fail")
    try #require(idMoved.hitboxes.map(\.id) != oracle.hitboxes.map(\.id),
                 "the hitbox id comparison cannot fail")
    try #require(clickDropped.hitboxes.count != oracle.hitboxes.count,
                 "the hitbox list comparison cannot fail")
    try #require(layerFewer.layerIDs != oracle.layerIDs && layerFewer.animLive != oracle.animLive,
                 "the $anim liveness comparison cannot fail")
    try #require(layerFewer.nodeCount != oracle.nodeCount, "the node count comparison cannot fail")
    try #require(animSkipped.layerIDs == oracle.layerIDs, "the equal-count oracle must keep every layer id")
    try #require(animSkipped.animLive == [true, false, true],
                 "a layer that skips animated() must read dead at its own depth; read \(animSkipped.animLive)")
    // Inner layers' corner radii and the order of their fills. The chain has
    // TWO inner layers with backgrounds (padding 4, the frame), each with a
    // radius unlike the outermost's, so a fill painted with the outermost
    // layer's radius, or the inner fills emitted innermost-first, both move
    // `rects`.
    try #require(oracle.rects.count == 4, "outer, frame, padding-4 and leaf fills; read \(oracle.rects.count)")
    try #require(radiiSwapped.rects != oracle.rects, "the corner-radius comparison cannot fail")
    try #require(radiiSwapped.rects.map(\.withoutRadii) == oracle.rects.map(\.withoutRadii),
                 "the radii-swapped oracle must differ from the oracle in radii alone")
    var innerFillsSwapped = oracle.rects
    innerFillsSwapped.swapAt(1, 2)
    try #require(innerFillsSwapped != oracle.rects, "the inner-fill order comparison cannot fail")
    // And the oracle itself has the shape the comparison is about.
    try #require(oracle.animLive == [true, true, true], "every layer holds a live $anim slot")
    try #require(oracle.hitboxes.count == 3)

    #expect(chain.leafID == oracle.leafID, "leaf id \(chain.leafID) vs \(oracle.leafID)")
    #expect(chain.leafBounds == oracle.leafBounds)
    #expect(chain.hitboxes == oracle.hitboxes, "hitboxes \(chain.hitboxes) vs \(oracle.hitboxes)")
    #expect(chain.rects == oracle.rects)
    #expect(chain.nodeCount == oracle.nodeCount)
    #expect(chain.layerIDs == oracle.layerIDs)
    #expect(chain.animLive == oracle.animLive)
}

/// **A modifier chain is observationally identical to hand-built nested
/// `Box`es under the proposal authority** — N2.2 of stage 7b (record §49 §4
/// row 231, spec §6 lane 2): ruling MC-B's oracle, the retired
/// `aModifierChainIsIdenticalToHandBuiltNestedBoxes`'s chain and nested `Box`es
/// unchanged, rendered under `.proposal`, so the chain's layers go through the
/// layer lowering and each oracle `Box` through `lowerLegacyNode` at site
/// `box` (`BoxWithoutAnimated` too, made Dual for this test).
///
/// **Every disagreeing oracle — paddings swapped, `.id` moved, a click
/// dropped, a layer fewer, a layer that skips `animated` at an equal count,
/// the radii exchanged, the inner fills reordered — is `try #require`d to
/// disagree with the oracle before the chain is compared with it** (practices
/// shape 15). **The retired test's node-count comparison is not carried**
/// (`LR-EN`; the comment at the comparisons).
///
/// Red-before (record §49 §6.2, M2.2): `ModifiedElement`'s inner paint loop
/// run innermost-first (the retired test's N8).
@Test @MainActor func aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority() throws {
    let chain = try observe(authority: .proposal) { log in
        Row {
            CountingLeaf("leaf", log: log)
                .background(.accent).onClick {}
                .padding(4).id("mid").background(.surfaceSecondary).cornerRadius(3)
                .frame(width: 60, height: 40)
                .background(.surface).cornerRadius(5).onClick {}
                .padding(8)
                .background(.separator).cornerRadius(9).onClick {}
        }
    }
    let oracle = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
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
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
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
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
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
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let animSkipped = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                BoxWithoutAnimated(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(3)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }
    let layerFewer = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: paddingStyle(4), content:
                    CountingLeaf("leaf", log: log).background(.accent).onClick {}
                ).id("mid").background(.surfaceSecondary).cornerRadius(3)
            ).background(.separator).cornerRadius(9).onClick {}
        }
    }

    // The radii-swapped oracle: the padding-4 layer's radius and the outermost
    // layer's exchanged, every other declaration unchanged.
    let radiiSwapped = try observe(authority: .proposal) { log in
        Row {
            Box(style: paddingStyle(8), content:
                Box(style: frameStyle(width: 60, height: 40), content:
                    Box(style: paddingStyle(4), content:
                        CountingLeaf("leaf", log: log).background(.accent).onClick {}
                    ).id("mid").background(.surfaceSecondary).cornerRadius(9)
                ).background(.surface).cornerRadius(5).onClick {}
            ).background(.separator).cornerRadius(3).onClick {}
        }
    }

    // Each disagreeing oracle must differ in the observation it is named for.
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
    try #require(animSkipped.layerIDs == oracle.layerIDs, "the equal-count oracle must keep every layer id")
    try #require(animSkipped.animLive == [true, false, true],
                 "a layer that skips animated() must read dead at its own depth; read \(animSkipped.animLive)")
    // Inner layers' corner radii and the order of their fills. The chain has
    // TWO inner layers with backgrounds (padding 4, the frame), each with a
    // radius unlike the outermost's, so a fill painted with the outermost
    // layer's radius, or the inner fills emitted innermost-first, both move
    // `rects`.
    try #require(oracle.rects.count == 4, "outer, frame, padding-4 and leaf fills; read \(oracle.rects.count)")
    try #require(radiiSwapped.rects != oracle.rects, "the corner-radius comparison cannot fail")
    try #require(radiiSwapped.rects.map(\.withoutRadii) == oracle.rects.map(\.withoutRadii),
                 "the radii-swapped oracle must differ from the oracle in radii alone")
    var innerFillsSwapped = oracle.rects
    innerFillsSwapped.swapAt(1, 2)
    try #require(innerFillsSwapped != oracle.rects, "the inner-fill order comparison cannot fail")
    // And the oracle itself has the shape the comparison is about.
    try #require(oracle.animLive == [true, true, true], "every layer holds a live $anim slot")
    try #require(oracle.hitboxes.count == 3)

    #expect(chain.leafID == oracle.leafID, "leaf id \(chain.leafID) vs \(oracle.leafID)")
    #expect(chain.leafBounds == oracle.leafBounds)
    #expect(chain.hitboxes == oracle.hitboxes, "hitboxes \(chain.hitboxes) vs \(oracle.hitboxes)")
    #expect(chain.rects == oracle.rects)
    #expect(chain.layerIDs == oracle.layerIDs)
    #expect(chain.animLive == oracle.animLive)
}

// MARK: - 5-6: `@State` across chained modifiers (ruling MC-D)

/// **A leaf's `@State` survives frames under a three-modifier legacy chain,
/// and each modifier is its own identity level with its own `$anim` slot.**
///
/// The leaf and its two nearest ancestors (padding 4, the frame) are each
/// `.positional(0)` under the next one out; the third (padding 8) takes the
/// `Row`'s index 0.
///
/// Green on arrival. Mutation (lane 1, at `6ff2d31`, record §10): `FrameModifier`'s
/// content cursor starting at 1. Lane 2 (record §10): `ModifiedElement`'s
/// content laid out under the outermost id, and inner layers skipping
/// `animated`, each redden it.
@Test @MainActor func stateSurvivesFramesUnderALegacyModifierChain() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100, layoutAuthority: .proposal) {
        Row {
            CountingLeaf("leaf", log: log).padding(4).frame(width: 60, height: 40).padding(8)
        }
    }
    window.drawFrameIfNeeded()
    let bounds = try #require(log.bounds["leaf"])
    for _ in 0..<3 {
        click(platformWindow, at: centre(bounds))
        window.drawFrameIfNeeded()
    }
    for _ in 0..<2 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    #expect(log.taps["leaf"] == 3, "read \(String(describing: log.taps["leaf"]))")

    let leaf = try #require(log.ids["leaf"])
    let padding4 = try #require(leaf.parent)
    let frame = try #require(padding4.parent)
    let padding8 = try #require(frame.parent)
    #expect(leaf.component == .positional(0))
    #expect(padding4.component == .positional(0), "padding 4 under the frame: \(padding4.component)")
    #expect(frame.component == .positional(0), "the frame under padding 8: \(frame.component)")
    #expect(padding8 == GlobalElementID.child(of: rootID, at: 0, name: nil))
    for (label, id) in [("padding 4", padding4), ("frame", frame), ("padding 8", padding8)] {
        #expect(window.stateTable.isLive(animRetentionSlot(for: id)), "\(label) has no live $anim slot")
    }
}

/// **`@State` survives frames under a proposal modifier chain inside a proposal
/// container, beside an unmodified sibling and a stateful `Component`.**
///
/// Inside an `HStack` so the container's group entry is the one exercised
/// (ruling MC-D): lane 3's typed defaults bind state and advance the cursor
/// through ruling MC-H's helper, and this test is those mutations' target.
///
/// **Each value is read twice, in paint and during layout** (`taps` and
/// `layoutTaps`). An element's `@State` is re-bound before prepaint and paint,
/// so only the layout-time read depends on the group entry's bind: with paint
/// alone, `ProposalElement`'s typed default bypassing the helper left the whole
/// suite green (lane 3, ruling MC-H).
///
/// Green on arrival. Mutation (today's code, record §10): `ModifiedContent`'s
/// content cursor starting at 1. Lane 3's `MC-H` mutations, each whole suite at
/// `b320ee7`: the helper's bind deleted reads `layoutTaps` a 0, and c 0 in both
/// (legacy `@State` tests redden too); `ProposalElement`'s typed default
/// bypassing the helper reads `layoutTaps` a 0 alone; `Component`'s reads c 0
/// in both; the helper's `cursor += 1` deleted reads b 2 in both.
@Test @MainActor func stateSurvivesFramesUnderAProposalModifierChain() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 140) {
        HStack {
            CountingProposalLeaf("a", log: log)
                .padding(Edges(all: px(5)))
                .frame(width: 40, height: 40)
                .background(.surface)
            CountingProposalLeaf("b", log: log)
            CountingProposalComponent(name: "c", log: log)
        }
    }
    window.drawFrameIfNeeded()
    let a = try #require(log.bounds["a"])
    let c = try #require(log.bounds["c"])
    for _ in 0..<3 {
        click(platformWindow, at: centre(a))
        window.drawFrameIfNeeded()
    }
    for _ in 0..<2 {
        click(platformWindow, at: centre(c))
        window.drawFrameIfNeeded()
    }
    for _ in 0..<2 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    #expect(log.taps["a"] == 3, "a read \(String(describing: log.taps["a"]))")
    #expect(log.taps["b"] == 0, "b read \(String(describing: log.taps["b"]))")
    #expect(log.taps["c"] == 2, "c read \(String(describing: log.taps["c"]))")
    // The same values read during layout, which only the group entry's bind can
    // serve (`CompositionLog.layoutTaps`).
    #expect(log.layoutTaps["a"] == 3, "a read \(String(describing: log.layoutTaps["a"])) during layout")
    #expect(log.layoutTaps["b"] == 0, "b read \(String(describing: log.layoutTaps["b"])) during layout")
    #expect(log.layoutTaps["c"] == 2, "c read \(String(describing: log.layoutTaps["c"])) during layout")

    let leaf = try #require(log.ids["a"])
    let padding = try #require(leaf.parent)
    let frame = try #require(padding.parent)
    let background = try #require(frame.parent)
    #expect(leaf.component == .positional(0))
    #expect(padding.component == .positional(0), "the padding under the frame: \(padding.component)")
    #expect(frame.component == .positional(0), "the frame under the background: \(frame.component)")
    #expect(background == GlobalElementID.child(of: rootID, at: 0, name: nil))
}

// MARK: - 7-8: once-per-phase delegation, outer layers first (ruling MC-F)

/// **Every modifier wrapper delegates each phase to its content exactly once.**
///
/// One arm per wrapper and per distinct code path in its phases, each rendering
/// one frame around a counting leaf named `"x"` and reading
/// `[requestLayout, prepaint, paint]`. The control arm, two counting leaves in
/// a `Row`, reads `[2, 2, 2]`, so an instrument counting per type rather than
/// per call cannot pass (practices shape 15). Counts are `try #require`d
/// before being indexed (shape 13).
///
/// Green on arrival. Mutations (today's code, record §10), each run
/// separately: `ModifiedContent.prepaint`'s `allowsHitTesting` branch calling
/// `prepaintGroup` twice; its `clip` paint branch losing its `else`;
/// `OverlayModifier.paint` skipping `overlay.paintGroup`;
/// `FrameModifier.prepaint` calling its content twice (lane 1, before lane 2
/// deleted that type). Lane 2 (record §10): `ModifiedElement.paint` painting
/// its content once per inner layer reads `[1, 1, 3]` on the chain arm.
@Test @MainActor func everyModifierWrapperDelegatesEachPhaseExactlyOnce() throws {
    func counts<Root: Element>(_ make: (CompositionLog) -> Root) throws -> [Int] {
        let log = CompositionLog()
        var root = make(log)
        Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1, layoutAuthority: .proposal).render(&root)
        let counts = log.counts("x")
        try #require(counts.count == 3)
        return counts
    }
    func once<Root: Element>(_ label: String, _ make: (CompositionLog) -> Root) throws {
        let read = try counts(make)
        #expect(read == [1, 1, 1], "\(label): [layout, prepaint, paint] = \(read)")
    }

    let control = try counts { log in
        Row {
            CountingLeaf("x", log: log)
            CountingLeaf("x", log: log)
        }
    }
    try #require(control == [2, 2, 2], "the instrument cannot read 2: \(control)")

    // Legacy wrappers.
    try once("legacy padding") { log in Row { CountingLeaf("x", log: log).padding(4) } }
    try once("legacy frame") { log in Row { CountingLeaf("x", log: log).frame(width: 60, height: 40) } }
    try once("legacy three-modifier chain") { log in
        Row { CountingLeaf("x", log: log).padding(4).frame(width: 60, height: 40).padding(8) }
    }
    try once("component's distributing padding") { log in
        Row { LegacyCountingComponent(log: log).padding(4) }
    }

    // Proposal `ModifiedContent`, one arm per distinct code path.
    try once("frame") { log in HStack { CountingProposalLeaf("x", log: log).frame(width: 30, height: 30) } }
    try once("flexibleFrame") { log in
        HStack { CountingProposalLeaf("x", log: log).frame(minWidth: 10, maxWidth: 50) }
    }
    try once("padding") { log in HStack { CountingProposalLeaf("x", log: log).padding(Edges(all: px(2))) } }
    try once("fixedSize") { log in HStack { CountingProposalLeaf("x", log: log).fixedSize() } }
    try once("aspectRatio") { log in HStack { CountingProposalLeaf("x", log: log).aspectRatio(1) } }
    try once("layoutPriority") { log in HStack { CountingProposalLeaf("x", log: log).layoutPriority(1) } }
    try once("background") { log in HStack { CountingProposalLeaf("x", log: log).background(.surface) } }
    try once("border") { log in HStack { CountingProposalLeaf("x", log: log).border(.accent, width: 1) } }
    try once("opacity") { log in HStack { CountingProposalLeaf("x", log: log).opacity(0.5) } }
    try once("clip") { log in HStack { CountingProposalLeaf("x", log: log).clip() } }
    try once("allowsHitTesting(true)") { log in
        HStack { CountingProposalLeaf("x", log: log).allowsHitTesting(true) }
    }
    try once("allowsHitTesting(false)") { log in
        HStack { CountingProposalLeaf("x", log: log).allowsHitTesting(false) }
    }

    try once("onTap") { log in HStack { CountingProposalLeaf("x", log: log).onTap {} } }

    try once("overlay, primary side") { log in
        ZStack { CountingProposalLeaf("x", log: log).overlay { Rectangle(width: 5, height: 5) } }
    }
    try once("overlay, overlay side") { log in
        ZStack { Rectangle(width: 30, height: 30).overlay { CountingProposalLeaf("x", log: log) } }
    }

    // `EnvironmentScope`, one arm per path (the environment track's `EV-W`
    // item 1, added at integration). Mutation: the typed
    // `requestProposalGroupLayout` calling its content twice reads
    // `[2, 1, 1]` on the proposal arm (record §13).
    try once("EnvironmentScope, legacy") { log in
        Row { CountingLeaf("x", log: log).environment(\.layoutDirection, .rightToLeft) }
    }
    try once("EnvironmentScope, proposal") { log in
        HStack { CountingProposalLeaf("x", log: log).environment(\.layoutDirection, .rightToLeft) }
    }

    // The grid (stage G's lane 4): a `Grid` is an element and a `GridRow` and a
    // `GridCellModifier` are groups, and all three hand each phase to their
    // content exactly once. Mutation: `Grid.prepaint` or `Grid.paint` calling
    // its content twice reads `[1, 2, 1]` / `[1, 1, 2]` on the Grid arm.
    try once("Grid") { log in Grid { GridRow { CountingProposalLeaf("x", log: log) } } }
    try once("GridRow, outside a Grid") { log in
        HStack { GridRow { CountingProposalLeaf("x", log: log) } }
    }
    try once("GridCellModifier") { log in
        Grid { GridRow { CountingProposalLeaf("x", log: log).gridCellAnchor(.top) } }
    }

    // The builder wrappers.
    try once("ProposalFrame") { log in
        HStack { ProposalFrame(width: 30, height: 30) { CountingProposalLeaf("x", log: log) } }
    }
    try once("Padding") { log in HStack { Padding(Edges(all: px(2))) { CountingProposalLeaf("x", log: log) } } }
    try once("Background") { log in HStack { Background(.surface) { CountingProposalLeaf("x", log: log) } } }
    try once("FixedSize") { log in HStack { FixedSize { CountingProposalLeaf("x", log: log) } } }
}

/// **A chain registers and paints its outer layer before its content.**
///
/// `leaf.background(.accent).onClick(inner).padding(4).background(.surface).onClick(outer)`:
/// the padding layer's hitbox is registered before the leaf's, so the leaf's
/// ranks above it; `.surface` is emitted before `.accent`, so the leaf paints
/// over its padding; a click in the padding ring runs `outer` and a click in
/// the leaf runs `inner`.
///
/// Green on arrival. Mutation (lane 1, when `.padding` was a `Box`, record
/// §10): `Box.prepaint` registering its handlers after its content. Lane 2
/// (record §10), on `ModifiedElement`: a layer registering after everything
/// inside it, and separately a layer's fill emitted after the content, each
/// redden it. Its chain has ONE padding layer, so reversing the order of
/// several layers is invisible here and is test 4's.
@Test @MainActor func aModifierChainRegistersAndPaintsOuterLayersFirst() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100, layoutAuthority: .proposal) {
        Row {
            CountingLeaf("leaf", log: log)
                .background(.accent).onClick { log.events.append("inner") }
                .padding(4)
                .background(.surface).onClick { log.events.append("outer") }
        }
    }
    window.drawFrameIfNeeded()
    let leaf = try #require(log.ids["leaf"])
    let padding = try #require(leaf.parent)
    #expect(window.lastHitboxes.map(\.id) == [padding, leaf],
            "hitbox order \(window.lastHitboxes.map(\.id.component))")

    let rects = window.lastScene.rects
    let surface = try #require(rects.firstIndex { isFilled($0, with: .surface, in: window.theme) })
    let accent = try #require(rects.firstIndex { isFilled($0, with: .accent, in: window.theme) })
    #expect(surface < accent, "the padding layer's background must be emitted first")

    let bounds = try #require(log.bounds["leaf"])
    log.events.removeAll()
    click(platformWindow, at: pt(bounds.origin.x.value - 2, bounds.origin.y.value + 10))
    #expect(log.events == ["outer"], "a click in the padding ring ran \(log.events)")
    log.events.removeAll()
    click(platformWindow, at: centre(bounds))
    #expect(log.events == ["inner"], "a click inside the leaf ran \(log.events)")
}

// MARK: - 9: the overlay's identity is independent of its primary's shape (ruling MC-P)

/// **An overlay's identity does not depend on how many indices its primary
/// consumed**, as SwiftUI's does not (`docs/probes/swiftui-overlay-primary-shape.swift`,
/// arms P1-P5 against controls A, B and Q: the overlay keeps its state through
/// a flip of its primary's shape).
///
/// The primary is `{ if flag { EmptyProposalComponent() }; CountingProposalLeaf("p") }`:
/// one node either way, but two indices or one, since an empty `Component`
/// consumes an index and contributes no node (ruling MC-E's counterexample).
///
/// **In-test positive control, the probe's P5:** the primary leaf `p`'s id
/// component must read `.positional(1)`, `.positional(0)`, `.positional(1)` —
/// proof the flip really moved an index inside the primary. The overlay's
/// readings are then pinned unchanged across the three steps: `.positional(0)`
/// under the `-1` overlay-side id, 3 taps, its `$state0` slot live.
///
/// Red under ruling MC-E's threaded cursor (`6ff2d31`, restored as a mutation,
/// record §10): the overlay reads index 2 with 3 taps, then index 1 with 0
/// taps, then index 2 with 3 taps (retained below the sweep threshold,
/// divergence 18) — the reading lane 1 first pinned as the trailing-sibling
/// rule, which SwiftUI does not have.
@Test @MainActor func anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let flag = Flag()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack(alignment: .topLeading) {
            group {
                if flag.value { EmptyProposalComponent() }
                CountingProposalLeaf("p", log: log, width: 60, height: 60)
            }
            .overlay(alignment: .topLeading) {
                CountingProposalLeaf("o", log: log, width: 10, height: 10)
            }
        }
    }
    window.drawFrameIfNeeded()
    // The 60×60 root is centred at (20, 20) since plan task 6's CN-J.
    try #require(log.bounds["o"] == Bounds(origin: pt(20, 20), size: Size(width: px(10), height: px(10))))
    let modifier = try #require(log.ids["p"]?.parent)
    let overlayID = GlobalElementID.child(of: GlobalElementID.child(of: modifier, at: -1, name: nil),
                                          at: 0, name: nil)
    let overlaySlot = GlobalElementID.child(of: overlayID, at: 0, name: ElementID("$state0"))

    struct Reading: Equatable {
        var primary: PathComponent?
        /// The overlay's own component, then its parent's — printable, unlike
        /// a `GlobalElementID`.
        var overlayPath: [PathComponent?]
        var overlayIsExpectedID: Bool
        var taps: Int?
        var overlayLive: Bool
    }
    func reading() -> Reading {
        let o = log.ids["o"]
        return Reading(primary: log.ids["p"]?.component, overlayPath: [o?.component, o?.parent?.component],
                       overlayIsExpectedID: o == overlayID, taps: log.taps["o"],
                       overlayLive: window.stateTable.isLive(overlaySlot))
    }

    for _ in 0..<3 {
        click(platformWindow, at: pt(25, 25))
        window.drawFrameIfNeeded()
    }
    let first = reading()

    flag.value = false
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let second = reading()

    flag.value = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    let third = reading()

    // The control: the flip moved the primary leaf's index.
    try #require([first.primary, second.primary, third.primary] == [.positional(1), .positional(0), .positional(1)],
                 "the primary's shape did not flip: \([first.primary, second.primary, third.primary])")

    let kept = Reading(primary: nil, overlayPath: [.positional(0), .positional(-1)], overlayIsExpectedID: true,
                       taps: 3, overlayLive: true)
    func overlayHalf(_ r: Reading) -> Reading {
        var half = r
        half.primary = nil
        return half
    }
    #expect(overlayHalf(first) == kept, "\(first)")
    #expect(overlayHalf(second) == kept, "\(second)")
    #expect(overlayHalf(third) == kept, "\(third)")
}

// MARK: - 10: modifier order against SwiftUI (ruling MC-L)

private struct Placement: Equatable, CustomStringConvertible {
    var width: Float, height: Float, x: Float, y: Float
    var description: String { "\(width)x\(height) at (\(x), \(y))" }
}

/// **Modifier order changes size and placement as SwiftUI does**, for a
/// fixed-size leaf. Expected numbers are SwiftUI's, from
/// `docs/probes/swiftui-modifier-order.swift` (arms K0-K2, O1-O4, recorded in
/// its header).
///
/// The outer width is read as the x of a 1pt sibling after the chain in a
/// `Row`, the outer height as the y of one in a `Column`, both
/// `.alignItems(.flexStart)`; the leaf's origin is its prepaint bounds in the
/// `Row`. O1/O2 and O3/O4 hold the same modifiers in different orders and are
/// `try #require`d to disagree first, so an instrument blind to order cannot
/// pass.
///
/// **Scope, and only this scope** (critic round 2, finding 7): a fixed 20×20
/// leaf, BOTH frame axes given, every frame at least as large as its content,
/// under an unconstrained `.flexStart` parent. NOT covered, and by reading the
/// legacy frame node stretches or shrinks where a SwiftUI frame stays fixed:
/// a nil axis (`.frame(width: 60)`), a frame smaller than its content, a frame
/// under a stretching `Box` parent (EP-8), a frame in a shrinking row (SZ-L).
/// Those are plan task 4's (legacy `.frame` semantics), not proven here.
///
/// Green, as measured by the design review's deleted scratch test. Mutation
/// (lane 1, on `FrameModifier` at `2571d4a`, record §10): `FrameModifier.init`
/// dropping `justifyContent = .center`. Lane 2 (record §10): `ModifiedElement`
/// minting its layer styles outermost-first swaps O1 and O2.
///
/// Pinned to the legacy authority by stage 6a (CE+RP, record §38 §4); unpinned
/// by stage 6b (`LR-DG`, R-fill): the `Row` and `Column` roots declare the
/// 200×200 frame's extent on their two auto axes — what `CS-I` gave the legacy
/// root, now spelled — and the test reads both authorities.
@Test @MainActor func modifierOrderChangesSizeAndPlacementAsSwiftUIDoes() throws {
    for authority in [LayoutAuthority.legacy, .proposal] {
        func place<Chain: Element>(_ chain: (CompositionLog) -> Chain) throws -> Placement {
            let size = Size(width: px(200), height: px(200))
            let rowLog = CompositionLog()
            var row = Row {
                chain(rowLog)
                CountingLeaf("probe", log: rowLog, width: 1, height: 1)
            }.alignItems(.flexStart).width(px(200)).height(px(200))
            Frame(contentSize: size, scaleFactor: 1, layoutAuthority: authority).render(&row)
            let columnLog = CompositionLog()
            var column = Column {
                chain(columnLog)
                CountingLeaf("probe", log: columnLog, width: 1, height: 1)
            }.alignItems(.flexStart).width(px(200)).height(px(200))
            Frame(contentSize: size, scaleFactor: 1, layoutAuthority: authority).render(&column)
            let leaf = try #require(rowLog.bounds["leaf"])
            return Placement(width: try #require(rowLog.bounds["probe"]).origin.x.value,
                             height: try #require(columnLog.bounds["probe"]).origin.y.value,
                             x: leaf.origin.x.value, y: leaf.origin.y.value)
        }

        let k0 = try place { CountingLeaf("leaf", log: $0) }
        let k1 = try place { CountingLeaf("leaf", log: $0).padding(8) }
        let k2 = try place { CountingLeaf("leaf", log: $0).padding(16) }
        let o1 = try place { CountingLeaf("leaf", log: $0).padding(8).frame(width: 60, height: 60) }
        let o2 = try place { CountingLeaf("leaf", log: $0).frame(width: 60, height: 60).padding(8) }
        let o3 = try place { CountingLeaf("leaf", log: $0).padding(4).frame(width: 40, height: 40).padding(8) }
        let o4 = try place { CountingLeaf("leaf", log: $0).frame(width: 40, height: 40).padding(4).padding(8) }

        try #require(o1 != o2, "the instrument cannot see order: O1 \(o1), O2 \(o2)")
        try #require(o3 != o4, "the instrument cannot see order: O3 \(o3), O4 \(o4)")

        #expect(k0 == Placement(width: 20, height: 20, x: 0, y: 0), "K0 \(k0), \(authority)")
        #expect(k1 == Placement(width: 36, height: 36, x: 8, y: 8), "K1 \(k1), \(authority)")
        #expect(k2 == Placement(width: 52, height: 52, x: 16, y: 16), "K2 \(k2), \(authority)")
        #expect(o1 == Placement(width: 60, height: 60, x: 20, y: 20), "O1 \(o1), \(authority)")
        #expect(o2 == Placement(width: 76, height: 76, x: 28, y: 28), "O2 \(o2), \(authority)")
        #expect(o3 == Placement(width: 56, height: 56, x: 18, y: 18), "O3 \(o3), \(authority)")
        #expect(o4 == Placement(width: 64, height: 64, x: 22, y: 22), "O4 \(o4), \(authority)")
    }
}

// MARK: - 11: a key the overlay declines bubbles to its holder (ruling MC-P)

/// A proposal wrapper that contributes no layout node (`OnTapModifier`'s shape)
/// and registers `isFocusable` and an `onKey` that claims only `claims`,
/// writing every keystroke it sees into `log.events`.
private struct KeyHandling<Content: ProposalElementGroup>: ProposalElement {
    var name: String
    var log: CompositionLog
    var focusable: Bool
    var claims: String
    var content: Content

    init(_ name: String, log: CompositionLog, focusable: Bool = false, claims: String,
         @ElementBuilder content: () -> Content) {
        self.name = name
        self.log = log
        self.focusable = focusable
        self.claims = claims
        self.content = content()
    }

    struct Layout { var content: Content.GroupLayout }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        precondition(children.count == 1, "KeyHandling wraps one native node")
        return (children[0], Layout(content: contentLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Content.GroupPrepaint {
        log.ids[name] = id
        var handlers = Handlers()
        handlers.isFocusable = focusable
        let (log, name, claims) = (log, name, claims)
        handlers.onKey = { key in
            log.events.append("\(name) saw \(key.characters)")
            return key.characters == claims
        }
        pass.registerHandlers(handlers, at: bounds, id: id)
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// **A focused overlay that declines a key hands it to the element holding the
/// overlay**, through the synthetic `.child(of: modifier, at: -1)` ancestor
/// that no element is produced at (ruling MC-P). Real `Window`, `Window.focus`,
/// a confirming frame, then `keyDown` through `simulateInput`.
///
/// `focusChain(from:)` walks `GlobalElementID.parent` and `dispatchKey` skips a
/// level with no registered handler, so the overlay-side id is skipped, not a
/// dead end. Asserted: the overlay claims `o` and nothing above it sees it;
/// `x` is seen by the overlay, then by the holder, which claims it, and the
/// focus is still the overlay after both frames.
///
/// Green on arrival (a coverage gap the lane-1 verifier named, not a defect).
/// Mutation, measured (record §10): numbering the overlay under
/// `.child(of: nil, at: -1)` — an overlay-side id detached from the modifier —
/// reddens this test's holder assertion.
@Test @MainActor func aKeyAFocusedOverlayDeclinesBubblesThroughTheOverlaySideIDToItsHolder() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = CompositionLog()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) {
        ZStack {
            KeyHandling("holder", log: log, claims: "x") {
                CountingProposalLeaf("primary", log: log, width: 60, height: 60)
                    .overlay(alignment: .topLeading) {
                        KeyHandling("overlay", log: log, focusable: true, claims: "o") {
                            CountingProposalLeaf("overlayLeaf", log: log, width: 10, height: 10)
                        }
                    }
            }
        }
    }
    window.drawFrameIfNeeded()
    let holder = try #require(log.ids["holder"])
    let overlay = try #require(log.ids["overlay"])
    #expect(overlay.parent?.parent?.parent == holder,
                 "the overlay-side id must sit under the modifier, which sits under the holder")

    window.focus(overlay)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == overlay)

    func key(_ c: String) -> InputEvent {
        .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], timestamp: 0))
    }
    log.events.removeAll()
    platformWindow.simulateInput(key("o"))
    window.drawFrameIfNeeded()
    #expect(log.events.filter { $0.contains(" saw ") } == ["overlay saw o"], "the overlay claims o; events \(log.events)")

    log.events.removeAll()
    platformWindow.simulateInput(key("x"))
    window.drawFrameIfNeeded()
    #expect(log.events.filter { $0.contains(" saw ") } == ["overlay saw x", "holder saw x"],
            "an unclaimed key must bubble past the overlay-side id to the holder; events \(log.events)")
    #expect(window.focusedElement == overlay, "focus moved off the overlay")
}
