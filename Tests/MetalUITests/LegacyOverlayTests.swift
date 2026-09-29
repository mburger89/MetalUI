import Testing
import Foundation
import Metal
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Lane 2 of plan task 7 stage 11 (spec
// `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md` §5, §7 lane 2;
// ruling `LR-FX` as amended by `LR-GA` item 3): the legacy `.overlay`.
// `OverlayModifier` takes any `ElementGroup` on either side; the one
// `.overlay(alignment:content:)` is declared on `ElementGroup`; both sides'
// nodes pass through `lowerAttachmentChildren` (`AttachmentLowering.swift`),
// which consumes and plans each record at `parentKind: .stack`, as a frame
// layer's children are planned (`LR-AZ`). Identity is `MC-P`'s, unchanged.
//
// N1.3 is the exit criterion's "overlay-primary-shape probe through the unified
// type" (`LR-FX` item 5); N1.5 and N1.7 are exit tests for the two named traps.
// Red runs and mutations are in record §54's lane-2 section.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: pt(x, y), size: Size(width: px(w), height: px(h)))
}

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: dim(w), height: dim(h))
    return s
}

/// The root id `Frame.render` builds for an unnamed root element.
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

@MainActor
private func click(_ platformWindow: FakePlatformWindow, at position: Point<Pixels>) {
    platformWindow.simulateInput(.mouseDown(MouseEvent(position: position)))
    platformWindow.simulateInput(.mouseUp(MouseEvent(position: position)))
}

/// Builds a group from a builder block, so a block with an `if` can be the
/// receiver of a modifier.
@MainActor
private func members<G: ElementGroup>(@ElementBuilder _ body: () -> G) -> G { body() }

// MARK: - Instruments

/// What the tapping leaves below write down. A reference type, because a window
/// test's content closure builds fresh element values every frame.
@MainActor
private final class TapLog {
    /// The id each name was handed in its LAST prepaint.
    var ids: [String: GlobalElementID] = [:]
    /// The bounds each name was handed in its last prepaint.
    var bounds: [String: Bounds<Pixels>] = [:]
    /// The `@State` tap count each name read in paint, cleared before every
    /// frame, so an element that was not painted reads `nil`.
    var taps: [String: Int] = [:]
}

/// The state every arm flips: `flag` is the primary's (or, for control Q, the
/// overlay's) condition; `generation` counts the flips, for control B's `.id`.
@MainActor
private final class Flip {
    var flag = true
    var generation = 0
}

/// A legacy `StyledElement` leaf with a declared pixel size, its own `@State`
/// (`$state0`), and a click handler that increments it — the overlay-primary-
/// shape probe's tally, and a primary member that logs its own id.
private struct TapLeaf: StyledElement {
    @State var taps = 0
    var name: String
    var log: TapLog
    var style: Style
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()

    init(_ name: String, log: TapLog, width: Float, height: Float) {
        self.name = name
        self.log = log
        self.style = sized(width, height)
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (declaredSizeNativeLeaf(style, pass), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.ids[name] = id
        log.bounds[name] = bounds
        var registered = handlers
        let state = _taps
        registered.onClick = { state.wrappedValue += 1 }
        pass.registerHandlers(registered, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        log.taps[name] = taps
    }
}

/// A fixed-size proposal leaf that logs its id, for the proposal primary (L4).
private struct ProposalProbe: ProposalElement {
    var name: String
    var log: TapLog
    var width: Double
    var height: Double

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.ids[name] = id
        log.bounds[name] = bounds
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// A legacy `Component` whose content is empty: it consumes one index and
/// contributes zero nodes (ruling MC-E's counterexample).
private struct EmptyComponent: Component {
    var content: EmptyGroup { EmptyGroup() }
}

/// A legacy `Component` with two members, so its node count is 2.
private struct TwoMembers: Component {
    var content: some ElementGroup {
        Box(style: sized(10, 10))
        Box(style: sized(10, 10))
    }
}

// MARK: - N1.3: the overlay-primary-shape probe through the unified type

/// One step's reading of an arm.
private struct Reading: Equatable, CustomStringConvertible {
    /// The component of the tapped element's id (`nil` if it was not prepainted).
    var tallyComponent: PathComponent?
    /// Whether the tally sits at `MC-P`'s id, `.child(.child(modifier, -1), 0)`.
    var tallyAtOverlaySide: Bool
    /// The tally's `@State`, read in paint (`nil`: not painted this frame).
    var taps: Int?
    /// The primary's trailing member's own component — the in-arm positive
    /// control: the flip must move it (`nil` for arms without one).
    var primary: PathComponent?

    var description: String {
        "tally \(String(describing: tallyComponent)) atSide=\(tallyAtOverlaySide) "
            + "taps \(String(describing: taps)) primary \(String(describing: primary))"
    }
}

/// Opens `make` in a real `Window` at `flip.flag == true`, taps the element
/// named `tapped` three times, then reads it at three steps — `true`, `false`,
/// `true` — bumping `flip.generation` at each flip. The overlay modifier is the
/// window's root, so its id is `rootID`.
///
/// Pre-flights the same tree at both flag values under diagnostics, `try
/// #require`-ing an empty report, because the window traps where the frame
/// reports (CLAUDE.md, practices).
@MainActor
private func readings<Root: Element>(tapping tapped: String, primary: String?,
                                     _ make: @escaping @MainActor (Flip, TapLog) -> Root) throws -> [Reading] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for flag in [true, false] {
        let flip = Flip()
        flip.flag = flag
        var root = make(flip, TapLog())
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                          reportsUnlowerableFields: true)
        frame.render(&root)
        try #require(frame.unlowerableFields.isEmpty, "flag \(flag): \(frame.unlowerableFields)")
    }
    let log = TapLog()
    let flip = Flip()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 100) { make(flip, log) }
    func draw() {
        log.taps.removeAll()
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    let overlaySide = GlobalElementID.child(of: rootID, at: -1, name: nil)
    func reading() -> Reading {
        let id = log.taps[tapped] == nil ? nil : log.ids[tapped]
        return Reading(tallyComponent: id?.component, tallyAtOverlaySide: id == child(overlaySide, 0),
                       taps: log.taps[tapped], primary: primary.flatMap { log.ids[$0]?.component })
    }
    draw()
    let target = try #require(log.bounds[tapped], "\(tapped) was never prepainted")
    let centre = pt(target.origin.x.value + 3, target.origin.y.value + 3)
    for _ in 0..<3 {
        click(platformWindow, at: centre)
        draw()
    }
    let first = reading()
    flip.flag = false
    flip.generation += 1
    draw()
    let second = reading()
    flip.flag = true
    flip.generation += 1
    draw()
    return [first, second, reading()]
}

/// **N1.3 (exit) — a legacy overlay keeps its overlay's state through a flip
/// of its primary's shape** (ruling `LR-FX` items 2 and 5; `MC-P`). The
/// overlay-primary-shape probe's arms
/// (`docs/probes/swiftui-overlay-primary-shape.swift`: SwiftUI keeps an
/// overlay's state through P1–P5, and resets it under B and Q), run over
/// primaries of every kind the unified type can hand an overlay:
///
/// - **L1** `Box { if flag { x }; p }` — a legacy container primary;
/// - **L2** `Box { if flag { EmptyComponent() }; p }`;
/// - **L3** L1 `.padding(Pixels(2))` — a legacy `ModifiedContent` primary;
/// - **L4** `ZStack { if flag { Rectangle }; p }.padding(e)` — a proposal
///   `ModifiedContent` primary under a legacy overlay;
/// - **L5** `members { if flag { EmptyComponent() }; p }` — a legacy **group**
///   primary, the probe's P2 and MC-E's counterexample: one node either way,
///   two indices or one. *Added by lane 2* (`LR-GC` item 3): L1–L4 are single
///   elements, which consume one index whatever their shape, so only a group
///   primary can move a threaded cursor (M1c′).
///
/// Each arm's overlay is a stateful tally tapped three times and then read at
/// `true`, `false`, `true`: it must sit at `.child(.child(root, -1), 0)` and
/// read 3 taps at every step. **In-arm control:** the primary's trailing
/// member `p` reads `.positional(1)` at all three steps. Until plan task 8 it
/// read `.positional(1)`, `.positional(0)`, `.positional(1)` — the flip moved an
/// index inside the primary; since `ID-B` an `if` takes one slot whether or not
/// it has content, so no builder content moves an index at run time any more and
/// "a flip of the primary's shape" is a flip of its node count (L1, L3, L4) or
/// of an index-less member (L2, L5). The overlay's own path is what M1c and
/// M1c′ still redden (T row, record §55 §6).
///
/// **Controls** (the probe's A, B, P5, Q): **A** no flip in the primary —
/// kept; **B** the tally inside `Box { tally }.id("g\(generation)")` — reset at
/// every flip (3, 0, 0), which proves the instrument sees a reset; **P5** a
/// tally inside the primary's own conditional, tapped — present (3), absent
/// (`nil`: not painted), present again reading **0**, SwiftUI's new state (it
/// read 3 until plan task 8's `ID-C` reset content an evaluated `if` removes;
/// divergence 18 retired); **Q** the overlay's own `if`/`else` — reset at the
/// `else` (0) and again on return (0; the first branch's 3 came back before
/// `ID-C`). The
/// discriminating step is the second: at it no retained state can stand in.
///
/// Red before: does not compile at `56275c5` (`.overlay` is on
/// `ProposalElementGroup`, which no legacy primary is). Mutations (record §54):
/// **M1c** the overlay side under `.child(of: id, at: 0)` (every arm's
/// `tallyAtOverlaySide`); **M1c′** one cursor threaded through primary and
/// overlay (L5's second step reads 0 taps at `.positional(1)`).
@Test @MainActor func aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape() throws {
    func tally(_ log: TapLog) -> TapLeaf { TapLeaf("o", log: log, width: 10, height: 10) }
    let kept = { (primary: Bool) -> [Reading] in
        // `ID-B`: the trailing member keeps `.positional(1)` through the flip.
        let p: [PathComponent?] = primary ? [.positional(1), .positional(1), .positional(1)] : [nil, nil, nil]
        return p.map { Reading(tallyComponent: .positional(0), tallyAtOverlaySide: true, taps: 3, primary: $0) }
    }

    let l1 = try readings(tapping: "o", primary: "p") { flip, log in
        Box(style: sized(60, 60)) {
            if flip.flag { Box(style: sized(20, 20)) }
            TapLeaf("p", log: log, width: 20, height: 20)
        }
        .overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(l1 == kept(true), "L1 Box { if; p }: \(l1)")

    let l2 = try readings(tapping: "o", primary: "p") { flip, log in
        Box(style: sized(60, 60)) {
            if flip.flag { EmptyComponent() }
            TapLeaf("p", log: log, width: 20, height: 20)
        }
        .overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(l2 == kept(true), "L2 Box { if EmptyComponent; p }: \(l2)")

    let l3 = try readings(tapping: "o", primary: "p") { flip, log in
        Box(style: sized(60, 60)) {
            if flip.flag { Box(style: sized(20, 20)) }
            TapLeaf("p", log: log, width: 20, height: 20)
        }
        .padding(px(2))
        .overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(l3 == kept(true), "L3 L1.padding(2): \(l3)")

    let l4 = try readings(tapping: "o", primary: "p") { flip, log in
        ZStack {
            if flip.flag { Rectangle(width: px(20), height: px(20)) }
            ProposalProbe(name: "p", log: log, width: 60, height: 60)
        }
        .padding(Edges(all: px(2)))
        .overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(l4 == kept(true), "L4 ZStack { if; p }.padding(e): \(l4)")

    let l5 = try readings(tapping: "o", primary: "p") { flip, log in
        members {
            if flip.flag { EmptyComponent() }
            TapLeaf("p", log: log, width: 60, height: 60)
        }
        .overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(l5 == kept(true), "L5 group { if EmptyComponent; p }: \(l5)")

    // Control A: nothing in the primary flips.
    let a = try readings(tapping: "o", primary: nil) { _, log in
        TapLeaf("p", log: log, width: 60, height: 60).overlay(alignment: .topLeading) { tally(log) }
    }
    #expect(a == kept(false), "control A: \(a)")

    // Control B: the overlay's identity changes every generation — reset.
    let b = try readings(tapping: "o", primary: nil) { flip, log in
        TapLeaf("p", log: log, width: 60, height: 60).overlay(alignment: .topLeading) {
            Box { tally(log) }.id("g\(flip.generation)")
        }
    }
    #expect(b.map(\.taps) == [3, 0, 0], "control B must reset at every flip: \(b)")

    // Control P5: a tally inside the primary's own conditional.
    let p5 = try readings(tapping: "q", primary: nil) { flip, log in
        Box(style: sized(60, 60)) {
            if flip.flag { TapLeaf("q", log: log, width: 20, height: 20) }
            TapLeaf("p", log: log, width: 20, height: 20)
        }
        .overlay(alignment: .bottomTrailing) { tally(log) }
    }
    #expect(p5.map(\.taps) == [3, nil, 0], "control P5 (present, absent, fresh — ID-C): \(p5)")

    // Control Q: the overlay's own `if`/`else` — each branch its own identity.
    let q = try readings(tapping: "o", primary: nil) { flip, log in
        TapLeaf("p", log: log, width: 60, height: 60).overlay(alignment: .topLeading) {
            if flip.flag { tally(log) } else { tally(log) }
        }
    }
    #expect(q.map(\.taps) == [3, 0, 0], "control Q (reset at the else and on return — ID-C): \(q)")
}

// MARK: - N1.4: the records are consumed as a frame layer's are

/// **N1.4 — a legacy overlay consumes its primary's and its overlay's records
/// as a frame layer does** (ruling `LR-FX` item 3; `LR-AZ`). In a 200×100
/// `Row`, a 30×20 `Box` primary declaring `flexGrow(1)`, overlaid
/// `.topLeading` by a 10×10 `Box` declaring `margin(5)`, then a 10×10 sibling.
/// Under diagnostics the report is empty; the grow and the margin are dropped:
///
/// - the primary keeps its 30×20 (grown it would be 190 wide), centred on the
///   row's cross axis (`EP-8`): (0, 40);
/// - the overlay sits at the primary's origin, (0, 40) 10×10 — with its margin
///   it would be inset to (5, 45);
/// - the sibling follows the primary, at (30, 45).
///
/// Derived by hand before the run from `LR-AZ`'s drop rule and the row's
/// centring. The attachment node carries no record of its own, so the row gives
/// it an empty plan (a proposal element's, record §23 X2).
///
/// Red before: does not compile at `56275c5`. Mutations (record §54): **M1e**
/// the primary's record not consumed (`box.flexGrow.unconsumed`); **M1e′** the
/// overlay side's not consumed (`box.margin.unconsumed`).
@Test @MainActor func aLegacyOverlayConsumesItsPrimarysAndOverlaysRecordsAsAFrameLayerDoes() throws {
    var root = Row {
        Box(style: sized(30, 20)).flexGrow(1)
            .overlay(alignment: .topLeading) { Box(style: sized(10, 10)).margin(px(5)) }
        Box(style: sized(10, 10))
    }.cssWidth(px(200)).cssHeight(px(100))
    let frame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&root)
    #expect(frame.unlowerableFields.isEmpty, "report: \(frame.unlowerableFields)")
    let overlayModifier = child(rootID, 0)
    let primary = child(overlayModifier, 0)
    let overlay = child(GlobalElementID.child(of: overlayModifier, at: -1, name: nil), 0)
    let sibling = child(rootID, 1)
    #expect(frame.elementBounds[primary] == bounds(0, 40, 30, 20),
            "primary \(String(describing: frame.elementBounds[primary]))")
    #expect(frame.elementBounds[overlay] == bounds(0, 40, 10, 10),
            "overlay \(String(describing: frame.elementBounds[overlay]))")
    #expect(frame.elementBounds[sibling] == bounds(30, 45, 10, 10),
            "sibling \(String(describing: frame.elementBounds[sibling]))")
}

// MARK: - N1.5 and N1.7: the named traps

/// **N1.5 (exit) — an overlay on a presentation traps naming its primary
/// count** (ruling `LR-FX` item 4). A `Deferred` over absolute content is a
/// presentation root (stage 5, `LR-CH`); its in-flow placeholder is dropped by
/// `lowerAttachmentChildren` as every lowered container drops it, which leaves
/// the attachment zero primary nodes, and the existing precondition traps with
/// `requires one primary node, got 0` — a named answer where the alternative is
/// an overlay proposed 0×0 at an in-flow point nobody sees.
///
/// Red before: does not compile at `56275c5`. Mutation (record §54): **M1f** the
/// primary not passed through `droppingPresentations`.
@Test func anOverlayOnAPresentationTrapsNamingItsPrimaryCount() async {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var absolute = sized(20, 20)
            absolute.position = .absolute
            absolute.inset = Edges(top: dim(5), right: .auto, bottom: .auto, left: dim(5))
            var root = Box(style: sized(100, 100)) {
                Deferred { Box(style: absolute) }.overlay { Box(style: sized(10, 10)) }
            }
            Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("requires one primary node, got 0"),
            "aborted, but not naming the zero primary count:\n\(stderr)")
}

/// **N1.7 (exit) — a legacy overlay on a two-member `Component` traps naming
/// its primary count** (ruling `LR-FX` item 4 as amended by `LR-GA` item 3). A
/// multi-member `Component` hands the attachment two nodes; SwiftUI distributes
/// a `Group`'s overlay per member, which is plan task 8's `Group` semantics.
/// Until then the trap is the named answer, the one the proposal path already
/// gives a multi-node primary.
///
/// Red before: does not compile at `56275c5`. Mutation (record §54): **M1j** the
/// precondition relaxed to `primary.count >= 1` (the child exits 0).
@Test func aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount() async {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = Box(style: sized(100, 100)) {
                TwoMembers().overlay { Box(style: sized(10, 10)) }
            }
            Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("requires one primary node, got 2"),
            "aborted, but not naming the two-node primary count:\n\(stderr)")
}

// MARK: - N1.6: the proposal overlay is unmoved

/// **N1.6 — a proposal overlay registers exactly the nodes it did before
/// unification** (a must-not-move pin, green on both sides by design). `ZStack
/// { Rectangle(40×30).padding(4).overlay { Rectangle(10×10) }.opacity(0.5) }`
/// in a 200×160 frame: **5 nodes, native work 3/4/8, six recorded bounds**,
/// and two emitted rects — the primary's fill at (80, 65) 40×30 and the
/// overlay's at (95, 75) 10×10, both at alpha 0.5. Every literal was taken at
/// `47c0d98` (a scratch test in the demo-pixel harness's export of that commit,
/// deleted), before stage 11 touched a file.
///
/// A proposal node carries no `LoweredItem`, so `lowerAttachmentChildren`
/// hands it an empty plan and registers it unwrapped. Mutation (record §54):
/// **M1g** a record-less child wrapped in a frame (the node count and the work).
@Test @MainActor func aProposalOverlayRegistersExactlyTheNodesItDidBeforeUnification() {
    var root = ZStack {
        Rectangle(width: px(40), height: px(30), color: .surface)
            .padding(Edges(all: px(4)))
            .overlay { Rectangle(width: px(10), height: px(10), color: .accent) }
            .opacity(0.5)
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(160)), scaleFactor: 1,
                      recordsElementBounds: true)
    frame.render(&root)
    let work = frame.tree.lastNativeLayoutWork
    #expect(frame.tree.nodeCount == 5, "nodes \(frame.tree.nodeCount)")
    let counters: [Int] = [work.measureCalls, work.cacheHits, work.cacheMisses]
    #expect(counters == [3, 4, 8], "work \(counters)")
    #expect(frame.elementBounds.count == 6, "bounds \(frame.elementBounds)")
    let rects: [[Float]] = frame.finalizedScene().rects.map {
        [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height, $0.background.a]
    }
    let expected: [[Float]] = [[80, 65, 40, 30, 0.5], [95, 75, 10, 10, 0.5]]
    #expect(rects == expected, "rects \(rects)")
}

// MARK: - N1.8–N1.11: the attachment lowering's report path, its parent style, its presentation drop

/// **N1.8 — each side of a legacy overlay reports its unlowerable fields by
/// name** (ruling `LR-GD` item 1; `lowerAttachmentChildren`'s item 2). In a
/// 100×100 `Box`, an absolute 10×10 `Box` — outside any `Deferred` — overlaid by
/// a `Box` whose width is `auto` with a px `maxWidth` of 50 and a height of 10.
/// Under diagnostics the report names both, primary side first, each at the
/// child's own site: `box.position` (an absolute box outside a `Deferred` is a
/// permanent refusal, `LR-FO`) and `box.maxSize` (a maximum on an `auto` axis,
/// which is not greedy, `LR-AB`). Derived before the run from the plan's
/// rules at `parentKind: .stack`, which drop only the flex item fields.
///
/// The report block in `lowerAttachmentChildren` is a third copy of the
/// `dropLast` / `unlowerable(last)` pattern (`LegacyLowering.swift`,
/// `ListRows.swift`), so it is pinned here on its own. Mutation (record §54
/// §8.3): **V5** the `guard fields.isEmpty` inverted to `if false, !fields.isEmpty`
/// (the report reads `[]`).
@Test @MainActor func eachSideOfALegacyOverlayReportsItsUnlowerableFieldsByName() {
    var absolute = sized(10, 10)
    absolute.position = .absolute
    var capped = Style()
    capped.size = Size(width: .auto, height: dim(10))
    capped.maxSize = Size(width: dim(50), height: .auto)
    var root = Box(style: sized(100, 100)) {
        Box(style: absolute).overlay { Box(style: capped) }
    }
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true)
    frame.render(&root)
    #expect(frame.unlowerableFields.map(\.description) == ["box.position", "box.maxSize"],
            "report: \(frame.unlowerableFields)")
}

/// **N1.9 (exit) — a production frame traps on an overlay side's unlowerable
/// field** (ruling `LR-GD` item 1). N1.8's overlay side alone — a 10×10 primary
/// overlaid by the `auto`-width, `maxWidth: 50` box — in a production frame
/// (diagnostics off): the child aborts naming `box.maxSize`, where the
/// alternative is the side laid out in flow as though the maximum were not
/// there. Mutation (record §54 §8.3): **V5** (the child exits 0).
@Test func aProductionFrameTrapsOnAnOverlaySidesUnlowerableField() async {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var capped = Style()
            capped.size = Size(width: .auto, height: dim(10))
            capped.maxSize = Size(width: dim(50), height: .auto)
            var root = Box(style: sized(100, 100)) {
                Box(style: sized(10, 10)).overlay { Box(style: capped) }
            }
            Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("MetalUI: box.maxSize has no proposal lowering"),
            "aborted, but not naming box.maxSize:\n\(stderr)")
}

/// **N1.10 — a multi-view legacy overlay stretches none of its views**
/// (ruling `LR-GC` item 5(a), pinned by `LR-GD` item 2). A 40×30 `Box`
/// overlaid `.topLeading` by two views: `a`, 10 wide with an `auto` height,
/// and `b`, an `auto` width and 10 tall. `lowerAttachmentChildren` plans them
/// against a `.center`/`.center` parent, so neither is stretched on its `auto`
/// axis: `a` is 10×0 and `b` 0×10. The overlay's views form one stack whose
/// size is their union, 10×10, aligned `.topLeading` in the primary at (0, 0),
/// each view centred in the union: `a` at (0, 5), `b` at (5, 0) — relative to
/// the primary's origin, so the enclosing `Box`'s placement of the primary does
/// not enter the literals. Derived before the run. A stretching (default)
/// parent style would make `a` 10×30 and `b` 40×10, a 40×30 union.
///
/// Mutation (record §54 §8.3): **V2** `parent.justifyItems = .center` and
/// `parent.alignItems = .center` deleted (both rects move; no report either
/// way).
@Test @MainActor func aMultiViewLegacyOverlayStretchesNoneOfItsViews() throws {
    var tall = Style()
    tall.size = Size(width: dim(10), height: .auto)
    var wide = Style()
    wide.size = Size(width: .auto, height: dim(10))
    var root = Box(style: sized(100, 100)) {
        Box(style: sized(40, 30)).overlay(alignment: .topLeading) {
            Box(style: tall)
            Box(style: wide)
        }
    }
    let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&root)
    #expect(frame.unlowerableFields.isEmpty, "report: \(frame.unlowerableFields)")
    let overlayModifier = child(rootID, 0)
    let overlaySide = GlobalElementID.child(of: overlayModifier, at: -1, name: nil)
    let primary = try #require(frame.elementBounds[child(overlayModifier, 0)])
    func relative(_ id: GlobalElementID) -> [Float]? {
        frame.elementBounds[id].map {
            [$0.origin.x.value - primary.origin.x.value, $0.origin.y.value - primary.origin.y.value,
             $0.size.width.value, $0.size.height.value]
        }
    }
    #expect(relative(child(overlaySide, 0)) == [0, 5, 10, 0],
            "a \(String(describing: relative(child(overlaySide, 0))))")
    #expect(relative(child(overlaySide, 1)) == [5, 0, 0, 10],
            "b \(String(describing: relative(child(overlaySide, 1))))")
}

/// **N1.11 — an overlay-side `Deferred` presents against the window and leaves
/// no placeholder in the overlay** (ruling `LR-GD` item 3; replaces the spec's
/// undefined `N3.1` citation in §5). A 40×30 `Box` root overlaid by a
/// `Deferred` over an absolute 10×10 box inset (5, 5), in a 200×100 frame. The
/// presented box reads (5, 5) 10×10 — the window's corner, not the primary's
/// (the primary is centred, `CN-J`, at (80, 35)). The node count is **7**:
/// measured at `0e4e853` and taken as the literal, not derived (the lane-2
/// verifier's 9 was the same overlay inside an enclosing `Box`) — its content
/// is the placeholder's absence, which the mutant turns into **8** (one 0×0
/// leaf in the overlay stack). The rect is unchanged under the mutant; only
/// the count sees the drop.
///
/// Mutation (record §54 §8.3): **V4** the overlay side skips
/// `droppingPresentations` while the primary still drops.
@Test @MainActor func anOverlaySideDeferredPresentsAgainstTheWindowAndLeavesNoPlaceholder() {
    var absolute = sized(10, 10)
    absolute.position = .absolute
    absolute.inset = Edges(top: dim(5), right: .auto, bottom: .auto, left: dim(5))
    var root = Box(style: sized(40, 30)).overlay { Deferred { Box(style: absolute) } }
    let frame = Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1,
                      reportsUnlowerableFields: true, recordsElementBounds: true)
    frame.render(&root)
    #expect(frame.unlowerableFields.isEmpty, "report: \(frame.unlowerableFields)")
    let deferred = child(GlobalElementID.child(of: rootID, at: -1, name: nil), 0)
    let presented = child(deferred, 0)
    #expect(frame.elementBounds[presented] == bounds(5, 5, 10, 10),
            "presented \(String(describing: frame.elementBounds[presented]))")
    #expect(frame.elementBounds[child(rootID, 0)] == bounds(80, 35, 40, 30),
            "primary \(String(describing: frame.elementBounds[child(rootID, 0)]))")
    #expect(frame.tree.nodeCount == 7, "nodes \(frame.tree.nodeCount)")
}
