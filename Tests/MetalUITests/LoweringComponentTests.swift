import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 3 of the engine replacement — the `Component` distribution
// lane. Design: `docs/superpowers/specs/2026-09-22-engine-stage-3-design.md`
// §3.5 and §6 lane 4; rulings `LR-BG` (amend and wrap) and `LR-BO` (this lane's
// corrections).
//
// **What the lane changes.** `ComponentModifierOp.amend` stops carrying a
// `(inout Style) -> Void` closure and carries a `Size<Dimension>` patch. The
// legacy branch writes the declared axes through `LayoutTree.setStyle` exactly
// as before; the lowered branch registers **one native frame per member** with
// the patch's declared axes, centred on each axis the patch declares and
// leading on each axis it leaves `auto`. `.wrap` (a `.padding`) lowers through
// `lowerLegacyNode` at site `component`, an ordinary one-child legacy
// container.
//
// **So this file's arms are mostly divergence pins**: the legacy amend
// OVERWRITES the member's own size (divergence 48), the lowered one FRAMES it,
// which is SwiftUI's answer — probe `swiftui-component-distribution.swift`
// arms G7/G8/G13/G14 and stage-3 probe arms W1/W2/W4/W5/W7-W9, both re-run
// 2026-09-22 and byte-identical to their headers.
//
// **The prototype's arm letters (C1…C7) are kept** as the names for each
// shape, so the design's §2.3 table, `LR-BG`'s table and these tests can be
// read against each other.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bnd(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// `DifferentialRoot`'s own id, then its content's, as the harness mints them.
private let lane4Root = GlobalElementID.child(of: nil, at: 0, name: nil)
private let lane4Box = GlobalElementID.child(of: lane4Root, at: 0, name: nil)
/// A `Component` is identity-opaque and layout-transparent: it takes the `Box`'s
/// cursor slot 0 and its members number from 0 under it.
private let lane4Component = GlobalElementID.child(of: lane4Box, at: 0, name: nil)
private let lane4MemberA = GlobalElementID.child(of: lane4Component, at: 0, name: nil)
private let lane4MemberB = GlobalElementID.child(of: lane4Component, at: 1, name: nil)
/// A sibling written after the component inside the `Box`: its x reads the
/// component's whole outer width, which no element of its own reports.
private let lane4Sibling = GlobalElementID.child(of: lane4Box, at: 1, name: nil)

/// The prototype's `Pair`: two fixed members, 30×10 and 50×10 (probe `Pair`'s
/// own `a` and `b`).
private struct Lane4Pair: Component {
    var content: some ElementGroup {
        Box().width(px(30)).height(px(10))
        Box().width(px(50)).height(px(10))
    }
}

/// The prototype's `Solo`: one fixed 30×10 member (probe `Solo`).
private struct Lane4Solo: Component {
    var content: some ElementGroup {
        Box().width(px(30)).height(px(10))
    }
}

// One member carrying one flex **item** field, for 4.6 — three structs rather
// than one with a `switch`, because a builder `switch` is an `EitherGroup` and
// its branch does NOT take the component's slot 0: every id below would be
// `nil` (read in the red-before run).

private struct Lane4GrowSolo: Component {
    var content: some ElementGroup { Box().width(px(30)).height(px(10)).flexGrow(1) }
}

private struct Lane4MarginSolo: Component {
    var content: some ElementGroup { Box().width(px(30)).height(px(10)).margin(px(4)) }
}

/// A declared width folds its own minimum in at `paddedAndSized`, so the
/// minimum is only OBSERVABLE as the parent's plan when the axis is `auto`.
private struct Lane4MinWidthSolo: Component {
    var content: some ElementGroup { Box().height(px(10)).minWidth(px(40)) }
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
private func lane4ExpectAgreement(_ r: LayoutDifferential.Report, _ arm: String,
                                  sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
    #expect(r.disagreeing.isEmpty, "\(arm): \(r.disagreeing)", sourceLocation: sourceLocation)
    #expect(r.legacyOnly.isEmpty && r.loweredOnly.isEmpty,
            "\(arm): legacyOnly \(r.legacyOnly) loweredOnly \(r.loweredOnly)", sourceLocation: sourceLocation)
    #expect(r.scenesEqual, "\(arm): scenes", sourceLocation: sourceLocation)
    #expect(r.hitboxesEqual, "\(arm): hitboxes", sourceLocation: sourceLocation)
    #expect(r.accessibilityEqual, "\(arm): accessibility", sourceLocation: sourceLocation)
    #expect(r.stateSlotsEqual, "\(arm): state slots", sourceLocation: sourceLocation)
}

/// Both sides' rects for one id, as literals, and — for a divergence pin — the
/// requirement that they actually differ before either is believed (practices
/// shape 15).
@MainActor
private func lane4Rects(_ r: LayoutDifferential.Report, _ arm: String, _ id: GlobalElementID,
                        legacy: Bounds<Pixels>, lowered: Bounds<Pixels>,
                        mustDiffer: Bool = true,
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
    if mustDiffer {
        try #require(legacy != lowered, "\(arm): the pin's two sides are the same literal",
                     sourceLocation: sourceLocation)
    }
    #expect(r.legacyBounds[id] == legacy,
            "\(arm) legacy: \(String(describing: r.legacyBounds[id]))", sourceLocation: sourceLocation)
    #expect(r.loweredBounds[id] == lowered,
            "\(arm) lowered: \(String(describing: r.loweredBounds[id]))", sourceLocation: sourceLocation)
}

// MARK: - 4.1 The amend frames each member where the legacy amend overwrites it

/// **Test 4.1** (`LR-BG`), a **divergence pin**. A caller's `.width(70)` on a
/// component OVERWRITES each member's own declared width under the legacy
/// authority (divergence 48, `aComponentsWidthStillOverwritesItsMembersDeclaredWidth`)
/// and FRAMES each member under the proposal one, which is SwiftUI's answer.
///
/// | arm | legacy | lowered | SwiftUI |
/// |---|---|---|---|
/// | **C1** `Pair().width(70)` | members **70**×10 at x 0 and 70 | 30 and 50 wide, centred at x **20** and **80** | probe W1 (a at 96, b at 164 in a 300pt host — each member centred in its own 70) and component-distribution G7 |
/// | **C2** `Solo().width(70)` | member **70**×10 at x 0 | 30 wide at x **20** | component-distribution G8 (a at x 20 in a 70pt outer) |
///
/// **The member rects are the assertion, not the group's outer size**: a frame
/// registered around the whole group rather than per member reads the same
/// OUTER 70 (C2) or 140 (C1) and only the members tell the two apart — which is
/// mutation **M4a**.
@MainActor
@Test func aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt() throws {
    let c1 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(c1.unlowerable.isEmpty, "C1: \(c1.unlowerable)")
    try #require(c1.elements == 4, "C1 ids: root, Box and the two members; got \(c1.elements)")
    try lane4Rects(c1, "C1 a", lane4MemberA, legacy: bnd(0, 0, 70, 10), lowered: bnd(20, 0, 30, 10))
    try lane4Rects(c1, "C1 b", lane4MemberB, legacy: bnd(70, 0, 70, 10), lowered: bnd(80, 0, 50, 10))

    let c2 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Solo().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(c2.unlowerable.isEmpty, "C2: \(c2.unlowerable)")
    try #require(c2.elements == 3, "C2 ids: root, Box and the one member; got \(c2.elements)")
    try lane4Rects(c2, "C2 a", lane4MemberA, legacy: bnd(0, 0, 70, 10), lowered: bnd(20, 0, 30, 10))
}

// MARK: - 4.2 The wrap is an ordinary one-child legacy container

/// **Test 4.2** (`LR-BG`). `.padding` on a component already WRAPS each member
/// in a real legacy node (`OM-D`, `MC-A`), so its lowering is
/// `lowerLegacyNode(style, declared: style, children: [current], site:
/// .component)` — the container lowering entire — and the two authorities
/// **agree** in every observation. Prototype arm **C3**; component-distribution
/// probe **G2** (`Pair().padding(8)` measures 120×26, each member padded, and
/// each member keeps its own 30 and 50).
///
/// Mutation **M4b**: the wrap registered as a bare native padding instead of
/// through `lowerLegacyNode` — the member's own item record stops being
/// consumed and the stretch the legacy padding node performs disappears.
@MainActor
@Test func aComponentsPaddingLowersAsAnOrdinaryOneChildContainer() throws {
    let c3 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().padding(px(8)) }.width(px(300)).height(px(40))
    }
    lane4ExpectAgreement(c3, "C3")
    try #require(c3.elements == 4, "C3 ids: root, Box and the two members; got \(c3.elements)")
    try lane4Rects(c3, "C3 a", lane4MemberA, legacy: bnd(8, 8, 30, 10), lowered: bnd(8, 8, 30, 10),
                   mustDiffer: false)
    try lane4Rects(c3, "C3 b", lane4MemberB, legacy: bnd(54, 8, 50, 10), lowered: bnd(54, 8, 50, 10),
                   mustDiffer: false)
}

// MARK: - 4.3 The amend frame is centred only on the axis it declares

/// **Test 4.3** (`LR-BG`), a **divergence pin** and the pin for §2.3's
/// correction. The amend frame's alignment is **per axis**: `.center`'s factor
/// on an axis the patch declares, `0` on an axis it leaves `auto`. The same
/// value is recorded as the item's `contentAlignment`, which is what the
/// parent's own item frame reads — so recording `.center` unconditionally
/// moves a width-only amend's members on the HEIGHT axis as well, which is a
/// second, undesigned divergence.
///
/// | arm | legacy | lowered |
/// |---|---|---|
/// | **C7** `Pair().height(20)` | members 30×**20** and 50×**20** at y 0 | 30×**10** and 50×**10** at y **5**, x unmoved |
/// | **C1** `Pair().width(70)` (4.1's fixture, read here for its y) | y 0 | y **0** — the undeclared axis does not move |
/// | control `Pair().width(70).height(20)` | members 70×20 at x 0/70, y 0 | 30×10 at (**20**, **5**) and 50×10 at (**80**, **5**) — both axes centred |
///
/// The ground is the **legacy agreement** the undeclared axis must preserve.
/// Stage-3 probe arms **W7/W8/W9** show the single-axis frame is real and
/// aligns on the axis it declares (`.top` puts both members at y 30, `.bottom`
/// at y 60, against the W0 control's y 45), and **W2/W5** show the undeclared
/// axis passes through at the child's own size; SwiftUI has no observable
/// answer for how such a frame would align on an axis with no free space, so
/// those arms are the consistency check rather than the source (`LR-BG` as
/// amended).
///
/// Mutation **M4c**: the alignment recorded as `.center` unconditionally —
/// C1's members move to y **15**, the exact value the prototype read.
@MainActor
@Test func aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares() throws {
    let c7 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().height(px(20)) }.width(px(300)).height(px(40))
    }
    #expect(c7.unlowerable.isEmpty, "C7: \(c7.unlowerable)")
    try lane4Rects(c7, "C7 a", lane4MemberA, legacy: bnd(0, 0, 30, 20), lowered: bnd(0, 5, 30, 10))
    try lane4Rects(c7, "C7 b", lane4MemberB, legacy: bnd(30, 0, 50, 20), lowered: bnd(30, 5, 50, 10))

    // C1 again, for the axis the patch leaves `auto`: the members stay at y 0.
    let c1 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(c1.loweredBounds[lane4MemberA]?.origin.y == Pixels(0),
            "C1 a lowered y: \(String(describing: c1.loweredBounds[lane4MemberA]))")
    #expect(c1.loweredBounds[lane4MemberB]?.origin.y == Pixels(0),
            "C1 b lowered y: \(String(describing: c1.loweredBounds[lane4MemberB]))")

    // The control: both axes declared, so both are centred — two amends, two
    // nested frames, one per axis.
    let both = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().width(px(70)).height(px(20)) }.width(px(300)).height(px(40))
    }
    #expect(both.unlowerable.isEmpty, "control: \(both.unlowerable)")
    try lane4Rects(both, "control a", lane4MemberA, legacy: bnd(0, 0, 70, 20), lowered: bnd(20, 5, 30, 10))
    try lane4Rects(both, "control b", lane4MemberB, legacy: bnd(70, 0, 70, 20), lowered: bnd(80, 5, 50, 10))
}

// MARK: - 4.4 Order is observable under both authorities

/// **Test 4.4** (`LR-BG`, `OM-E`). `ops` is applied in the order the modifiers
/// were written, with a "current node" an amend frames and a wrap replaces, so
/// `.padding(4).width(70)` and `.width(70).padding(4)` are different trees
/// under **both** authorities.
///
/// | arm | legacy | lowered | SwiftUI |
/// |---|---|---|---|
/// | **C4** `.padding(4).width(70)` | members at x **4** and **74** (the 4pt inset inside a 70-wide wrapper) | x **20** and **80** | component-distribution **G13**: `Pair().padding(4).frame(w: 70)` puts a at x **20** |
/// | **C5** `.width(70).padding(4)` | members **70** wide at x **4** and **82** | 30 wide at x **24**, 50 wide at x **92** | component-distribution **G14**: `Pair().frame(w: 70).padding(4)` puts a at x **24** |
///
/// Mutation **M4d**: `ops` applied in reverse — C4 and C5 swap answers.
@MainActor
@Test func theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities() throws {
    let c4 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().padding(px(4)).width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(c4.unlowerable.isEmpty, "C4: \(c4.unlowerable)")
    try lane4Rects(c4, "C4 a", lane4MemberA, legacy: bnd(4, 4, 30, 10), lowered: bnd(20, 4, 30, 10))
    try lane4Rects(c4, "C4 b", lane4MemberB, legacy: bnd(74, 4, 50, 10), lowered: bnd(80, 4, 50, 10))

    let c5 = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4Pair().width(px(70)).padding(px(4)) }.width(px(300)).height(px(40))
    }
    #expect(c5.unlowerable.isEmpty, "C5: \(c5.unlowerable)")
    try lane4Rects(c5, "C5 a", lane4MemberA, legacy: bnd(4, 4, 70, 10), lowered: bnd(24, 4, 30, 10))
    try lane4Rects(c5, "C5 b", lane4MemberB, legacy: bnd(82, 4, 70, 10), lowered: bnd(92, 4, 50, 10))
}

// MARK: - 4.5 Chained amends compose the same way under both authorities

/// **Test 4.5** (`LR-BG`, `OM-E`). The payload change — a closure becoming a
/// `Size<Dimension>` — is internal, so it is pinned by BEHAVIOUR rather than by
/// a typecheck guard: two amends must stay two ops on both paths.
///
/// - `.width(70).height(20)` is **two** ops and lowers to **two nested frames**,
///   one per axis; the legacy branch writes the two axes of one `Style`.
/// - `.width(70).width(90)` leaves the **later** one standing (`OM-E`): the
///   legacy assignment overwrites, and the lowered outer frame is 90 around an
///   inner 70.
///
/// **The outer width is read through a sibling written after the component**,
/// because the amend frames are not elements and report no bounds of their own:
/// the 5×5 `Box` after the component sits at the sum of the members' outer
/// widths. Both arms read the **same** sibling x under both authorities — 140
/// and 180 — while the member rects differ, which is the whole of divergence
/// 48 in one fixture.
///
/// Mutation **M4e**: the two amends collapsed into one frame — the
/// `.width(70).width(90)` arm keeps the earlier 70 and the sibling moves to 140.
@MainActor
@Test func chainedComponentAmendsComposeTheSameWayUnderBothAuthorities() throws {
    let twoAxes = LayoutDifferential.compare(width: 400, height: 100) {
        Box {
            Lane4Pair().width(px(70)).height(px(20))
            Box().width(px(5)).height(px(5))
        }.width(px(300)).height(px(40))
    }
    #expect(twoAxes.unlowerable.isEmpty, "two axes: \(twoAxes.unlowerable)")
    try #require(twoAxes.elements == 5,
                 "two axes ids: root, Box, two members, the sibling; got \(twoAxes.elements)")
    try lane4Rects(twoAxes, "two axes sibling", lane4Sibling,
                   legacy: bnd(140, 0, 5, 5), lowered: bnd(140, 0, 5, 5), mustDiffer: false)
    try lane4Rects(twoAxes, "two axes a", lane4MemberA, legacy: bnd(0, 0, 70, 20), lowered: bnd(20, 5, 30, 10))

    let twice = LayoutDifferential.compare(width: 400, height: 100) {
        Box {
            Lane4Pair().width(px(70)).width(px(90))
            Box().width(px(5)).height(px(5))
        }.width(px(300)).height(px(40))
    }
    #expect(twice.unlowerable.isEmpty, "twice: \(twice.unlowerable)")
    try lane4Rects(twice, "twice sibling", lane4Sibling,
                   legacy: bnd(180, 0, 5, 5), lowered: bnd(180, 0, 5, 5), mustDiffer: false)
    try lane4Rects(twice, "twice a", lane4MemberA, legacy: bnd(0, 0, 90, 10), lowered: bnd(30, 0, 30, 10))
    try lane4Rects(twice, "twice b", lane4MemberB, legacy: bnd(90, 0, 90, 10), lowered: bnd(110, 0, 50, 10))
}

// MARK: - 4.6 The amend consumes and plans the member's own record

/// **Test 4.6** (`LR-BG` as amended by critic round 1 finding 8, and `LR-BO`).
/// `loweredComponentFrame` **consumes** the member's `LoweredItem` and plans it
/// through `planLegacyItems` exactly as `lowerLegacyLayer`'s single-node arm
/// does. Without the consume, `reportUnconsumedLoweredItems` emits
/// `<site>.<field>.unconsumed` for every non-default item field on the member's
/// record — and in a **production** frame every report is a trap, so
/// `MyComponent().width(70)` over a member declaring `.flexGrow(1)` would work
/// under the legacy authority and **abort** under the proposal one at stage 6b.
/// That is a crash, not a divergence, which is why all three arms require an
/// EMPTY report.
///
/// **What the planning does and does not do** (`LR-BO`, correcting the design's
/// "the field is applied"): the parent kind is `.stack`, as a frame's is
/// everywhere else in the lowering, and a stack parent **ignores** a child's
/// `flexGrow` and `margin` (`LR-AZ`, `MC-Q` finding 7). So those two arms are
/// consumed and DROPPED — visible as a rect disagreement, never as a report —
/// while the `minWidth` arm is genuinely planned into the item frame W. The
/// third arm exists because mutation **M4g** (consume but do not plan) cannot
/// redden either of the design's two.
///
/// Mutations: **M4f** the member's record not consumed (the `…unconsumed`
/// entries appear, at the MEMBER's site — `box`, not `component`); **M4g**
/// consumed but not planned (the `minWidth` arm's member loses its 40pt floor).
@MainActor
@Test func anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned() throws {
    let grow = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4GrowSolo().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(grow.unlowerable.isEmpty, "flexGrow: \(grow.unlowerable)")
    try lane4Rects(grow, "flexGrow", lane4MemberA, legacy: bnd(0, 0, 300, 10), lowered: bnd(20, 0, 30, 10))

    let margin = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4MarginSolo().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(margin.unlowerable.isEmpty, "margin: \(margin.unlowerable)")
    try lane4Rects(margin, "margin", lane4MemberA, legacy: bnd(4, 4, 70, 10), lowered: bnd(20, 0, 30, 10))

    // The planned arm: an `auto` width with a declared minimum, which only the
    // parent's item frame W can apply.
    let minimum = LayoutDifferential.compare(width: 400, height: 100) {
        Box { Lane4MinWidthSolo().width(px(70)) }.width(px(300)).height(px(40))
    }
    #expect(minimum.unlowerable.isEmpty, "minWidth: \(minimum.unlowerable)")
    try lane4Rects(minimum, "minWidth", lane4MemberA, legacy: bnd(0, 0, 70, 10), lowered: bnd(15, 0, 40, 10))
}
