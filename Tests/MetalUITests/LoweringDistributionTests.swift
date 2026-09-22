import Foundation
import Metal
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 2, lane 5 (`docs/superpowers/specs/2026-09-17-engine-stage-2-design.md`
// §4.2 rows 1–3 and §6 lane 5; ruling LR-AJ, and LR-AL for 5.8): the two remaining
// **container** fields of a flex box lowered under the proposal layout authority —
// `justifyContent`'s three distributions, as native spacers (and, where the gap is
// non-zero, a rigid gap leaf beside them), and `flexDirection`'s two reverse cases,
// as the children's **nodes** in reverse order with the main alignment factor
// mirrored.
//
// **Red before**: every test here was run on lane 4's lowering (`9a4a130`), where a
// sized `space-*` container reports `box.justifyContent.<case>` and any reverse
// container reports `box.reverse`, so the lowered side is a 0×0 leaf; each reads red
// there by that report and by a literal mismatch, and compiles against lane 4's API
// only. 5.8 is **characterization** (green on arrival; its mutation is its
// evidence). The mutation each must redden is named in its doc comment and in spec
// §6's lane-5 table; the record names what each actually reddened.
//
// **Every legacy literal below was measured before it was written** (record §19,
// lane 5, "Legacy answers measured before any literal was written"), on a scratch
// differential dump of exactly these shapes.
//
// **An overflowing arm declares `.flexShrink(0)` on every child**: the legacy engine
// shrinks a flex item below its declared main size and SwiftUI's compression does
// not (divergence 55, `LR-AF`), which would make an overflow arm disagree for a
// reason that is not this lane's. With `flexShrink(0)` both sides keep the declared
// size and the arm sees only the distribution.
//
// Geometry is chosen so no centred offset falls on `x.5` (practices, fixture
// hazard): every free extent a centring divides is even.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let containerID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func field(_ site: LoweringSite, _ name: String) -> UnlowerableField {
    UnlowerableField(site: site, field: name)
}

/// A fixed-size childless `Box`.
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(px(w)).height(px(h))
}

/// A fixed-size childless `Box` the legacy engine may not shrink.
@MainActor
private func rigid(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(px(w)).height(px(h)).flexShrink(0)
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
private func expectFullAgreement(_ r: LayoutDifferential.Report, _ arm: String,
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

/// The lowered rects of `ids`, in order, for a literal comparison.
private func lowered(_ r: LayoutDifferential.Report, _ ids: [GlobalElementID]) -> [Bounds<Pixels>?] {
    ids.map { r.loweredBounds[$0] }
}

/// The proposal frame's diagnostics for `make()` inside a `width`×`height` harness root.
@MainActor
private func report<C: ElementGroup>(width: Float = 300, height: Float = 200,
                                     @ElementBuilder _ make: @MainActor () -> C) -> [UnlowerableField] {
    LayoutDifferential.render(authority: .proposal, width: width, height: height, make).unlowerableFields
}

/// A flex container with an explicit direction, gap, `justifyContent` and ONE
/// declared main size — the shape `justifyContent`'s distributions and the reverse
/// directions both need, and which no `Row`/`Column` initializer spells in one go
/// (`Row`/`Column` also write `alignItems = .center`, EP-8).
@MainActor
private func container<C: ElementGroup>(row: Bool, gap: Float = 0, justify: JustifyContent? = nil,
                                        main: Float? = nil, reverse: Bool = false,
                                        @ElementBuilder _ content: () -> C) -> Box<C> {
    var s = Style()
    s.flexDirection = row ? (reverse ? .rowReverse : .row) : (reverse ? .columnReverse : .column)
    s.alignItems = .flexStart
    s.gap = Axes(both: .pixels(px(gap)))
    s.justifyContent = justify
    if let main {
        s.size = row ? Size(width: .length(.pixels(px(main))), height: .auto)
                     : Size(width: .auto, height: .length(.pixels(px(main))))
    }
    return Box(style: s, content: content())
}

// MARK: - 5.1 — `space-between`

/// **5.1.** `justifyContent: .spaceBetween` with a declared main size lowers to a
/// native `Spacer(minLength: main gap)` between each pair of children, the lowered
/// stack's own spacing dropped to 0 (ruling LR-AJ; stage-2 probe J1, J2, J3). Three
/// 20-long children in a 200-long container, on both axes and at gap 0 and 10:
///
/// - **fitting** (200): 0, 90, 180 on both sides, whatever the gap — the surplus a
///   spacer takes is the CSS gap plus its share, so a fixed stack gap would give the
///   same fitting answer and a different overflowing one (J2 against J3);
/// - **overflowing** (50, every child `.flexShrink(0)`): the spacers collapse to
///   their minimum and the line packs from the main start — 0, 20, 40 at gap 0 and
///   0, 30, 60 at gap 10, which is CSS's `space-between` fallback to `flex-start`
///   exactly (J3).
///
/// The overflow arms are what make the minimum load-bearing: a `Spacer(minLength: 0)`
/// would read 0, 20, 40 at gap 10 as well.
///
/// Mutation that must redden it: **MJa**, the spacer's minimum 0 whatever the gap.
@MainActor
@Test func spaceBetweenLowersToSpacersAtTheGap() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
    var arms = 0
    for gap in [Float(0), 10] {
        let row = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: true, gap: gap, justify: .spaceBetween, main: 200) {
                fixed(20, 10); fixed(20, 10); fixed(20, 10)
            }
        }
        try #require(row.elements == 5, "row gap \(gap): \(row.elements)")
        expectFullAgreement(row, "row gap \(gap)")
        #expect(lowered(row, ids) == [bounds(0, 0, 200, 10), bounds(0, 0, 20, 10),
                                      bounds(90, 0, 20, 10), bounds(180, 0, 20, 10)],
                "row gap \(gap)")

        let column = LayoutDifferential.compare(width: 300, height: 300) {
            container(row: false, gap: gap, justify: .spaceBetween, main: 200) {
                fixed(10, 20); fixed(10, 20); fixed(10, 20)
            }
        }
        try #require(column.elements == 5, "column gap \(gap): \(column.elements)")
        expectFullAgreement(column, "column gap \(gap)")
        #expect(lowered(column, ids) == [bounds(0, 0, 10, 200), bounds(0, 0, 10, 20),
                                         bounds(0, 90, 10, 20), bounds(0, 180, 10, 20)],
                "column gap \(gap)")

        // Overflowing: the spacers sit at their minimum and the line starts at 0.
        let overflow = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: true, gap: gap, justify: .spaceBetween, main: 50) {
                rigid(20, 10); rigid(20, 10); rigid(20, 10)
            }
        }
        try #require(overflow.elements == 5, "overflow gap \(gap): \(overflow.elements)")
        expectFullAgreement(overflow, "overflow gap \(gap)")
        let step = 20 + gap
        #expect(lowered(overflow, ids) == [bounds(0, 0, 50, 10), bounds(0, 0, 20, 10),
                                           bounds(step, 0, 20, 10), bounds(2 * step, 0, 20, 10)],
                "overflow gap \(gap)")

        let overflowColumn = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: false, gap: gap, justify: .spaceBetween, main: 50) {
                rigid(10, 20); rigid(10, 20); rigid(10, 20)
            }
        }
        try #require(overflowColumn.elements == 5, "overflow column gap \(gap)")
        expectFullAgreement(overflowColumn, "overflow column gap \(gap)")
        #expect(lowered(overflowColumn, ids) == [bounds(0, 0, 10, 50), bounds(0, 0, 10, 20),
                                                 bounds(0, step, 10, 20), bounds(0, 2 * step, 10, 20)],
                "overflow column gap \(gap)")
        arms += 4
    }
    try #require(arms == 8)
}

// MARK: - 5.2 — `space-around` and `space-evenly`

/// **5.2.** `justifyContent: .spaceEvenly` with a declared main size lowers to a
/// `Spacer(minLength: 0)` at both ends and between each pair, `.spaceAround` to the
/// same with the between-spacers **doubled**, and a non-zero main gap to a **rigid
/// native leaf** of that length beside each between-spacer — never to the spacer's
/// own minimum, which SwiftUI does not distribute the same way (ruling LR-AJ;
/// stage-2 probe J4, J5, J7, J8).
///
/// Three 20-long children in a 200-long container, on both axes. Legacy and lowered,
/// measured:
///
/// | gap | evenly | around |
/// |---|---|---|
/// | 0 | 35, 90, 145 (J4) | 23, 90, 157 (J7's 23.33/156.67, cumulative-edge rounded) |
/// | 10 | 30, 90, 150 | 20, 90, 160 (J8's rigid gap leaf) |
///
/// The gap-10 arms are what distinguish the rigid leaf from `Spacer(minLength: gap)`:
/// J5 measured the latter at 53.33/126.67 where CSS puts 50/130, so a minimum there
/// would read 33⅓/90/146⅔ at gap 10 instead of 30/90/150.
///
/// Mutations that must redden it: **MJb**, around's between-spacers not doubled (its
/// arms read the evenly answer); **MJc**, the gap registered as the between-spacer's
/// minimum rather than a rigid leaf (J5; the gap-10 arms move).
@MainActor
@Test func spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
    // gap → (evenly leading offsets, around leading offsets)
    let expected: [Float: (evenly: [Float], around: [Float])] = [
        0: (evenly: [35, 90, 145], around: [23, 90, 157]),
        10: (evenly: [30, 90, 150], around: [20, 90, 160]),
    ]
    var arms = 0
    for gap in [Float(0), 10] {
        let answers = try #require(expected[gap])
        for (justify, offsets) in [(JustifyContent.spaceEvenly, answers.evenly),
                                   (.spaceAround, answers.around)] {
            let row = LayoutDifferential.compare(width: 300, height: 200) {
                container(row: true, gap: gap, justify: justify, main: 200) {
                    fixed(20, 10); fixed(20, 10); fixed(20, 10)
                }
            }
            try #require(row.elements == 5, "row \(justify) gap \(gap)")
            expectFullAgreement(row, "row \(justify) gap \(gap)")
            #expect(lowered(row, ids) == [bounds(0, 0, 200, 10)]
                    + offsets.map { bounds($0, 0, 20, 10) }, "row \(justify) gap \(gap)")

            let column = LayoutDifferential.compare(width: 300, height: 300) {
                container(row: false, gap: gap, justify: justify, main: 200) {
                    fixed(10, 20); fixed(10, 20); fixed(10, 20)
                }
            }
            try #require(column.elements == 5, "column \(justify) gap \(gap)")
            expectFullAgreement(column, "column \(justify) gap \(gap)")
            #expect(lowered(column, ids) == [bounds(0, 0, 10, 200)]
                    + offsets.map { bounds(0, $0, 10, 20) }, "column \(justify) gap \(gap)")
            arms += 2
        }
    }
    try #require(arms == 8)

    // A single child: `space-between` leaves it at the main start, `space-evenly` and
    // `space-around` centre it — the spacer pattern gives each of those for free.
    let singles: [(JustifyContent, Float)] = [(.spaceBetween, 0), (.spaceEvenly, 90), (.spaceAround, 90)]
    for (justify, x) in singles {
        let r = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: true, justify: justify, main: 200) { fixed(20, 10) }
        }
        try #require(r.elements == 3, "single \(justify)")
        expectFullAgreement(r, "single \(justify)")
        #expect(lowered(r, [containerID, child(containerID, 0)])
                == [bounds(0, 0, 200, 10), bounds(x, 0, 20, 10)], "single \(justify)")
    }
    try #require(singles.count == 3)
}

// MARK: - 5.3 — overflow

/// **5.3.** Overflowing, the spacers of all three distributions collapse to their
/// minimum and the line packs from the **main start** — on both paths.
///
/// **This arm was designed as a divergence pin and is not one** (record §19, lane 5;
/// ruling `LR-BA` item 1). SwiftUI packs overflowing spacers from the start (J9) and
/// CSS's `space-around`/`space-evenly` fall back to `center`, so the design expected
/// the legacy engine to centre. It does not: `Alignment.swift`'s `distributeMainAxis`
/// clamps its free space with `max(0, freeSpace)` for all three distributions, so a
/// negative free space distributes nothing and every case degrades to `flex-start`.
/// Measured, three rigid 20s at 40: **0, 20, 40 for `spaceBetween`, `spaceEvenly`
/// and `spaceAround` alike**, which is what the lowering answers. The legacy
/// engine's own disagreement with CSS here is pre-existing and outside this lane
/// (record §19, "For the integrator").
///
/// The `try #require` is the discriminating precondition: the content (60) must
/// overflow the container (40), or the arm would be about the fitting case 5.2
/// already covers.
///
/// Mutation that must redden it: **MJd**, the end spacers given the platform default
/// minimum (`nil`, 8) instead of 0 — which moves only the overflowing arms, since a
/// fitting spacer's share is far above 8 (recorded in place of the design's "the
/// overflow centred", which no spacer lowering can express: with spacers the stack
/// fills its frame, so the container's main alignment factor cannot move it).
@MainActor
@Test func spaceAroundAndSpaceEvenlyOverflowFromTheStartOnBothPaths() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
    var arms = 0
    for justify in [JustifyContent.spaceBetween, .spaceEvenly, .spaceAround] {
        let r = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: true, justify: justify, main: 40) {
                rigid(20, 10); rigid(20, 10); rigid(20, 10)
            }
        }
        try #require(r.elements == 5, "\(justify)")
        let box = try #require(r.legacyBounds[containerID])
        let last = try #require(r.legacyBounds[child(containerID, 2)])
        try #require(last.origin.x.value + last.size.width.value > box.size.width.value,
                     "\(justify): the line must overflow, or this is 5.2's fitting case")
        expectFullAgreement(r, "\(justify)")
        #expect(lowered(r, ids) == [bounds(0, 0, 40, 10), bounds(0, 0, 20, 10),
                                    bounds(20, 0, 20, 10), bounds(40, 0, 20, 10)], "\(justify)")
        arms += 1
    }
    try #require(arms == 3)
}

// MARK: - 5.4 — a spacer beside a grower

/// **5.4.** A spacer is served after every other child (its priority is −∞, ruling
/// CN-C), so a growing sibling takes all the surplus and the spacer takes nothing —
/// SwiftUI's answer (J6) and CSS's (a `space-between` line with no free space left).
/// `Row { a20.flexGrow(1); b20 }.width(200).justifyContent(.spaceBetween)`: a's item
/// frame is 180 wide at 0 and b sits at 180, on both sides.
///
/// Mutation that must redden it: **MJe**, each spacer wrapped in a
/// `layoutPriority(0)` node, which makes it compete with the grower for the surplus.
@MainActor
@Test func aSpacerBesideAGrowingChildTakesNothing() throws {
    let r = LayoutDifferential.compare(width: 300, height: 200) {
        container(row: true, justify: .spaceBetween, main: 200) {
            fixed(20, 10).flexGrow(1); fixed(20, 10)
        }
    }
    try #require(r.elements == 4)
    expectFullAgreement(r, "spacer beside a grower")
    #expect(lowered(r, [containerID, child(containerID, 0), child(containerID, 1)])
            == [bounds(0, 0, 200, 10), bounds(0, 0, 180, 10), bounds(180, 0, 20, 10)])
}

// MARK: - 5.5, 5.6 — reverse directions

/// **5.5.** `.rowReverse` and `.columnReverse` lower to the children's **nodes** in
/// reverse order with `justifyContent`'s main factor mirrored — `flexStart` → 1
/// (trailing), `flexEnd` → 0, `center` unchanged — which is SwiftUI's spelling for
/// `row-reverse` (stage-2 probe R1: reversed children in a `.trailing` frame).
///
/// A 200-long container at gap 0 and 10. `first` is the child declared first, which a
/// reverse container puts at the main **end**. The row's children are 20 and 30 long
/// (10 tall), the column's 10 and 30 long (20 and 10 wide) — **the two tables are
/// different** and reusing the row's for the column was the one correction this arm
/// needed after the implementation landed (record §19, lane 5). Legacy, measured
/// before the literals were written:
///
/// | justify | row, gap 0 | row, gap 10 | column, gap 0 | column, gap 10 |
/// |---|---|---|---|---|
/// | `nil` / `.flexStart` | 180, 150 | 180, 140 | 190, 160 | 190, 150 |
/// | `.center` | 105, 75 | 110, 70 | 110, 80 | 115, 75 |
/// | `.flexEnd` | 30, 0 | 40, 0 | 30, 0 | 40, 0 |
/// | `.spaceBetween` | 180, 0 | 180, 0 | 190, 0 | 190, 0 |
///
/// The `.spaceBetween` arms are where the reversal and lane 5's spacer pattern meet:
/// reversing the whole node list carries the spacers with it.
///
/// Mutations that must redden it: **MJf**, the node order not reversed; **MJg**, the
/// main factor not mirrored (the `nil`, `.flexStart`, `.flexEnd` arms).
@MainActor
@Test func aReverseContainerPlacesItsChildrenFromTheMainEnd() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1)]
    // justify, gap → the row's (first, second) leading offsets, then the column's.
    let expected: [(justify: JustifyContent?, gap: Float,
                    row: (first: Float, second: Float), column: (first: Float, second: Float))] = [
        (nil, 0, (180, 150), (190, 160)), (nil, 10, (180, 140), (190, 150)),
        (.flexStart, 0, (180, 150), (190, 160)), (.flexStart, 10, (180, 140), (190, 150)),
        (.center, 0, (105, 75), (110, 80)), (.center, 10, (110, 70), (115, 75)),
        (.flexEnd, 0, (30, 0), (30, 0)), (.flexEnd, 10, (40, 0), (40, 0)),
        (.spaceBetween, 0, (180, 0), (190, 0)), (.spaceBetween, 10, (180, 0), (190, 0)),
    ]
    var arms = 0
    for arm in expected {
        let name = "\(String(describing: arm.justify)) gap \(arm.gap)"
        let row = LayoutDifferential.compare(width: 300, height: 200) {
            container(row: true, gap: arm.gap, justify: arm.justify, main: 200, reverse: true) {
                fixed(20, 10); fixed(30, 10)
            }
        }
        try #require(row.elements == 4, "row \(name)")
        expectFullAgreement(row, "row \(name)")
        #expect(lowered(row, ids) == [bounds(0, 0, 200, 10), bounds(arm.row.first, 0, 20, 10),
                                      bounds(arm.row.second, 0, 30, 10)], "row \(name)")

        let column = LayoutDifferential.compare(width: 300, height: 300) {
            container(row: false, gap: arm.gap, justify: arm.justify, main: 200, reverse: true) {
                fixed(20, 10); fixed(10, 30)
            }
        }
        try #require(column.elements == 4, "column \(name)")
        expectFullAgreement(column, "column \(name)")
        #expect(lowered(column, ids) == [bounds(0, 0, 20, 200), bounds(0, arm.column.first, 20, 10),
                                         bounds(0, arm.column.second, 10, 30)], "column \(name)")
        arms += 2
    }
    try #require(arms == 20)

    // The forward control the mirroring is read against: the same `.flexEnd` row,
    // not reversed, puts the FIRST child at 140 and the second at 170.
    let forward = LayoutDifferential.compare(width: 300, height: 200) {
        container(row: true, gap: 10, justify: .flexEnd, main: 200) { fixed(20, 10); fixed(30, 10) }
    }
    expectFullAgreement(forward, "forward flexEnd control")
    #expect(lowered(forward, ids) == [bounds(0, 0, 200, 10), bounds(140, 0, 20, 10),
                                      bounds(170, 0, 30, 10)], "forward flexEnd control")
}

/// **5.6.** A reverse container overflows toward its main **start** — the left edge
/// of a `rowReverse`, the top of a `columnReverse` — as SwiftUI's reversed children
/// in a trailing frame do (R2). Two `.flexShrink(0)` 80s in a 100-long container: the
/// first child at 20 and the second at −60, measured on both paths.
///
/// Mutation that must redden it: **MJg**, the main factor not mirrored (the line
/// would overflow toward the trailing edge instead).
@MainActor
@Test func aReverseContainerOverflowsTowardItsMainStart() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1)]
    let row = LayoutDifferential.compare(width: 300, height: 200) {
        container(row: true, main: 100, reverse: true) { rigid(80, 10); rigid(80, 10) }
    }
    try #require(row.elements == 4)
    expectFullAgreement(row, "rowReverse overflow")
    #expect(lowered(row, ids) == [bounds(0, 0, 100, 10), bounds(20, 0, 80, 10),
                                  bounds(-60, 0, 80, 10)])

    let column = LayoutDifferential.compare(width: 300, height: 300) {
        container(row: false, main: 100, reverse: true) { rigid(10, 80); rigid(10, 80) }
    }
    try #require(column.elements == 4)
    expectFullAgreement(column, "columnReverse overflow")
    #expect(lowered(column, ids) == [bounds(0, 0, 10, 100), bounds(0, 20, 10, 80),
                                     bounds(0, -60, 10, 80)])
}

/// The item shapes 5.7's three children take, so that the three item plans a
/// reverse container builds differ from one another: a grower (the item frame W
/// greedy on the main axis), a plain fixed child (no wrapper), and a child floored
/// by a `minWidth` (W with a minimum). An `alignSelf` would have been the obvious
/// third, and is not usable here: in a row with no declared cross size a greedy
/// alignment frame hugs where the legacy line places at its end, which is lane 1's
/// own divergence (1.6, probe X7) and would make the forward control disagree —
/// measured, not assumed (record §19, lane 5).
private enum DistributionRole { case grower, plain, floored }

/// A clickable, labelled, `@State`-holding leaf: a `Component`, so it has a
/// `$state0` slot of its own under an id the reversal must not move.
private struct DistributionCounter: Component {
    var role: DistributionRole
    var size: Float
    var tall: Float
    @State var taps = 0

    var content: some ElementGroup {
        let box = Box()
            .height(Pixels(tall))
            .background(.accent)
            .onClick { taps += 1 }
            .accessibilityLabel("c\(Int(size))")
        switch role {
        case .grower: return AnyElement(box.width(Pixels(size)).flexGrow(1))
        case .plain: return AnyElement(box.width(Pixels(size)))
        case .floored: return AnyElement(box.minWidth(Pixels(size)))
        }
    }
}

/// **5.7.** Reversing reverses the **nodes** and nothing else: the children's
/// `GlobalElementID`s, their `@State` slots, the paint order the scene records, the
/// hitbox order and the accessibility order are the ones declaration order gives, on
/// both paths. Three clickable, labelled `@State` components in a 300-wide
/// `rowReverse` row — a 20-wide grower 10 tall, a plain 30×20 and a 40-floored 30
/// tall — so each child's item plan differs from its siblings'.
///
/// Measured, legacy and lowered: the grower takes the 210 surplus and is 230 wide;
/// reversed it sits at 70, the plain child at 40 and the floored one at 0; forward
/// they are at 0, 230 and 260. The row is 300×30 either way.
///
/// Mutation that must redden it: **MJh**, the reversal applied to the children
/// **before** they are wrapped, so each child is paired with a sibling's item plan
/// and its bounds alias points at the wrong wrapper.
@MainActor
@Test func reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder() throws {
    @MainActor func interactiveRow(reverse: Bool) -> some ElementGroup {
        container(row: true, main: 300, reverse: reverse) {
            DistributionCounter(role: .grower, size: 20, tall: 10)
            DistributionCounter(role: .plain, size: 30, tall: 20)
            DistributionCounter(role: .floored, size: 40, tall: 30)
        }
    }
    // Five: the harness root, the row, and the three components' boxes — a
    // `Component` contributes no layout node, so it records no bounds of its own,
    // and the boxes hang off the components' ids (identity-opaque).
    let boxes = (0..<3).map { child(child(containerID, $0), 0) }

    let reversed = LayoutDifferential.compare(width: 400, height: 200) { interactiveRow(reverse: true) }
    try #require(reversed.elements == 5, "\(reversed.elements)")
    expectFullAgreement(reversed, "reverse row of interactive children")
    #expect(lowered(reversed, [containerID] + boxes)
            == [bounds(0, 0, 300, 30), bounds(70, 0, 230, 10), bounds(40, 0, 30, 20),
                bounds(0, 0, 40, 30)],
            "\(lowered(reversed, boxes))")

    // The forward control: the same three, declaration order left to right.
    let forward = LayoutDifferential.compare(width: 400, height: 200) { interactiveRow(reverse: false) }
    try #require(forward.elements == 5)
    expectFullAgreement(forward, "forward control")
    #expect(lowered(forward, [containerID] + boxes)
            == [bounds(0, 0, 300, 30), bounds(0, 0, 230, 10), bounds(230, 0, 30, 20),
                bounds(260, 0, 40, 30)],
            "\(lowered(forward, boxes))")
}

// MARK: - 5.8 — the declared gap, not the stack default

/// **5.8. Characterization** (green on arrival; ruling LR-AL). A lowered `Row` or
/// `Column` hands its native stack the declared main-axis gap **explicitly**, 0
/// included — never `nil`, which is SwiftUI's per-pair platform default of 8
/// (stack-algorithms probe S). `Style.gap` defaults to `.pixels(0)` and cannot say
/// "unset", so a lowered `Row { a; b }` could not tell a caller's `gap: 0` from the
/// initializer's default; closing divergence 52 means changing `Row`/`Column`'s
/// public default, which is stage 8's (`LR-AL`).
///
/// `Row { 20×10; 20×10 }` is 40×10 and `Column { 10×20; 10×20 }` 10×40 on both
/// sides; the `gap: 8` controls are 48 and 48, so the two spellings are
/// distinguishable and the arm is not vacuous (practices shape 15).
///
/// Mutation that must redden it: **MJi**, the lowered stack given `spacing: nil`
/// when the gap is 0.
@MainActor
@Test func aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault() throws {
    let ids = [containerID, child(containerID, 0), child(containerID, 1)]

    let row = LayoutDifferential.compare(width: 300, height: 200) {
        Row { fixed(20, 10); fixed(20, 10) }
    }
    let spacedRow = LayoutDifferential.compare(width: 300, height: 200) {
        Row(gap: px(8)) { fixed(20, 10); fixed(20, 10) }
    }
    try #require(row.loweredBounds[containerID] != spacedRow.loweredBounds[containerID],
                 "gap 0 and gap 8 must differ, or this arm cannot see the stack default")
    expectFullAgreement(row, "Row gap 0")
    expectFullAgreement(spacedRow, "Row gap 8")
    #expect(lowered(row, ids) == [bounds(0, 0, 40, 10), bounds(0, 0, 20, 10), bounds(20, 0, 20, 10)])
    #expect(lowered(spacedRow, ids) == [bounds(0, 0, 48, 10), bounds(0, 0, 20, 10),
                                        bounds(28, 0, 20, 10)])

    let column = LayoutDifferential.compare(width: 300, height: 200) {
        Column { fixed(10, 20); fixed(10, 20) }
    }
    let spacedColumn = LayoutDifferential.compare(width: 300, height: 200) {
        Column(gap: px(8)) { fixed(10, 20); fixed(10, 20) }
    }
    try #require(column.loweredBounds[containerID] != spacedColumn.loweredBounds[containerID],
                 "gap 0 and gap 8 must differ")
    expectFullAgreement(column, "Column gap 0")
    expectFullAgreement(spacedColumn, "Column gap 8")
    #expect(lowered(column, ids) == [bounds(0, 0, 10, 40), bounds(0, 0, 10, 20), bounds(0, 20, 10, 20)])
    #expect(lowered(spacedColumn, ids) == [bounds(0, 0, 10, 48), bounds(0, 0, 10, 20),
                                           bounds(0, 28, 10, 20)])
}

// MARK: - 5.9 — a reverse container its parent grows

/// **5.9.** A reverse container whose parent grows it places its children from the
/// main end of its **item frame** W, because the mirrored main factor is the
/// container's recorded content alignment, which W is aligned by (ruling LR-AB item
/// 2, LR-AJ). `Row { <rowReverse.flexGrow(1)>; 40 }.width(300)`: the inner row's
/// rect is 260 wide at 0, its first child at 240 and its second at 210, and the
/// sibling at 260 — measured on both paths.
///
/// **Its `spaceBetween` variant still reports** `box.justifyContent.spaceBetween` at
/// the inner row's site (`LR-AR`): the inner row has no declared main size, so it
/// registers its stack before it knows its parent will grow it, and the spacers
/// cannot be planned. The `reverse` entry is gone from that report, which is what
/// this lane moved.
///
/// Mutation that must redden it: **MJg**, the main factor not mirrored (the grown
/// arm's children pack from the leading edge of W).
@MainActor
@Test func aGrownReverseContainerPlacesFromTheMainEndOfItsItemFrame() throws {
    let inner = child(containerID, 0)
    let ids = [containerID, inner, child(inner, 0), child(inner, 1), child(containerID, 1)]
    let grown = LayoutDifferential.compare(width: 300, height: 200) {
        container(row: true, main: 300) {
            container(row: true, reverse: true) { fixed(20, 10); fixed(30, 10) }.flexGrow(1)
            fixed(40, 10)
        }
    }
    try #require(grown.elements == 6, "\(grown.elements)")
    expectFullAgreement(grown, "grown reverse container")
    #expect(lowered(grown, ids) == [bounds(0, 0, 300, 10), bounds(0, 0, 260, 10),
                                    bounds(240, 0, 20, 10), bounds(210, 0, 30, 10),
                                    bounds(260, 0, 40, 10)])

    let distributed = report(width: 300, height: 200) {
        container(row: true, main: 300) {
            container(row: true, justify: .spaceBetween, reverse: true) { fixed(20, 10); fixed(30, 10) }
                .flexGrow(1)
            fixed(40, 10)
        }
    }
    #expect(distributed == [field(.box, "justifyContent.spaceBetween")], "\(distributed)")
}
