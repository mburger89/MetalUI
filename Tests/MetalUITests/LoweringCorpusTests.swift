import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI
@testable import MetalUIDemoContent

// Plan task 7, stage 1, lane 5 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
// §6 lane 5; rulings LR-D, LR-E, LR-S, LR-AA): the stage-1 corpus — real trees,
// most of them the demo's own shapes, lowered under the proposal layout authority
// and compared with the legacy engine element by element through the differential
// harness (`LayoutDifferential.swift`).
//
// **Red before.** Lanes 2–4 did the lowering these trees need, so 5.1 and 5.3 were
// run against lane 4's tree first and are characterization: every corpus tree
// agreed on arrival except the demo header in the demo's own spelling, which
// reports `modifierLayer.alignItems.stretch` (record §18, lane 5; the corpus spells
// it lowerably, below). What proves each can fail is its mutation (spec §6's lane-5
// table; the record names what each reddened).
//
// Geometry is chosen so no centred offset falls on `x.5` (practices, fixture
// hazard): every free extent a centring divides is even.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
private let containerID = GlobalElementID.child(of: rootID, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int, _ name: String? = nil) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: name.map { ElementID($0) })
}

private let longString = "alpha bravo charlie delta echo foxtrot golf"

/// A fixed-size childless `Box` (lowered since lane 2: a 0×0 leaf in a fixed frame).
@MainActor
private func fixed(_ w: Float, _ h: Float) -> Box<EmptyGroup> {
    Box().width(px(w)).height(px(h))
}

/// Every whole-frame observation agrees and nothing was reported.
@MainActor
func expectCorpusAgreement(_ r: LayoutDifferential.Report, _ arm: String,
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

/// The stage-1 corpus: trees the lowering table covers, each spelled so nothing
/// in it is reported (spec 5.1). Shared with `LoweringPipelineParityTests.swift`.
@MainActor
enum StageOneCorpus {
    /// The demo's counter chrome — `CounterPanel.chrome(count:minus:plus:)`,
    /// **imported from `MetalUIDemoContent`** (ruling LR-S), not a copy — with the
    /// one field stage 1 cannot lower cleared: `CounterPanel` ends the chrome
    /// with `.alignSelf(.flexStart)`, an every-node field reported as
    /// `box.alignSelf` (stage 2; ruling LR-AA). Everything else is the demo's:
    /// the row style (gap 12, padding 12, centred), the surface decoration,
    /// `.focusBackground`, `.focusable()`, `.keyContext("Counter")`, and the two
    /// labelled, hoverable, clickable buttons over a 140×36 readout. 260×60, the
    /// buttons at x 12 and 212, the readout at 60, all at y 12 (lane 3's 3.4).
    static func counterChrome(count: Int = 0,
                              minus: @escaping @MainActor () -> Void = {},
                              plus: @escaping @MainActor () -> Void = {}) -> Box<CounterPanel.Chrome> {
        var chrome = CounterPanel.chrome(count: count, minus: minus, plus: plus)
        chrome.style.alignSelf = nil
        return chrome
    }

    /// The demo's header (`demoContent()`), lowerable: its bar's `.flexGrow(1)` is
    /// a declared width of 200 (stage 2 owns grow), the row's own `.flexGrow(1)` is
    /// dropped, and the padding layer that carries `.height(72)` also declares
    /// `.alignItems(.center)`. **In the demo's spelling that layer reports
    /// `modifierLayer.alignItems.stretch`**: `.height(72)` after `.padding` lands on
    /// the padding layer, a one-child row whose default is stretch, and a declared
    /// cross size is where CSS could show it (ruling LR-E principle 3). Nothing
    /// shows it here — the row is 40 tall either way — which is why the corpus may
    /// spell it `.center`.
    ///
    /// Hand-derived: the row is 40 + 12 + 200 = 252 × 40; the layer 252 + 32 = 284
    /// × 72; the row at (16, 16), the circle at (16, 16) 40×40, the bar at
    /// (16 + 52, 16 + 14) = (68, 30) 200×12.
    static func demoHeader() -> some ElementGroup {
        Row(gap: px(12)) {
            Box()
                .width(px(40)).height(px(40))
                .background(.accent)
                .cornerRadius(px(20))
            Box()
                .width(px(200))
                .height(px(12))
                .background(.surfaceSecondary)
                .cornerRadius(px(6))
        }
        .alignItems(.center)
        .padding(px(16))
        .alignItems(.center)
        .height(px(72))
        .background(.surface)
        .cornerRadius(px(14))
    }

    /// The demo's stack cluster (`demoContent()`), with its `.alignSelf(.flexStart)`
    /// dropped (stage 2). Hand-derived: the stack is its largest child, 360×128;
    /// the 160×72 card at (100, 28); the 28×28 badge at (166, 50).
    static func stackCluster() -> some ElementGroup {
        Stack(alignment: .center) {
            Box()
                .width(px(360))
                .height(px(128))
                .background(.accent)
                .cornerRadius(px(12))
            Box()
                .width(px(160))
                .height(px(72))
                .background(.surface)
                .cornerRadius(px(10))
            Box(decoration: Decoration(background: .surfaceSecondary, cornerRadius: px(14))) {
                Text("3").font(size: 13)
            }
            .width(px(28))
            .height(px(28))
            .alignItems(.center)
            .justifyContent(.center)
        }
    }

    /// Scratch tree T5 (record §18): a text column — a 22pt title over a paragraph
    /// that wraps inside the 400-wide root.
    static func textColumn() -> some ElementGroup {
        Column(gap: px(12)) {
            Text("Text renders").font(size: 22)
            Text("CoreText shapes this paragraph, a shelf packer places each glyph in an R8 atlas exactly once, and the fragment shader tints the coverage it samples.")
        }
    }

    /// T5b: a short text column under a `.padding(10)` layer.
    static func paddedTextColumn() -> some ElementGroup {
        Column(gap: px(12)) {
            Text("Text renders").font(size: 22)
            Text("Short line")
        }
        .padding(px(10))
    }

    /// T6: a padding layer and a frame layer over a `Box` over a `Text`.
    static func paddedFrameOverText() -> some ElementGroup {
        Box { Text("hi") }.padding(px(8)).frame(width: px(100), height: px(40))
    }

    /// T7: nested rows mixing texts and fixed boxes.
    static func nestedRows() -> some ElementGroup {
        Column(gap: px(4)) {
            Row(gap: px(8)) { Text("a"); Text("bb"); fixed(10, 30) }
            Row(gap: px(8)) { fixed(50, 5); Text("ccc") }
        }
    }

    /// `ModifierCompositionProofTests.aModifierChainIsIdenticalToHandBuiltNestedBoxes`'
    /// chain, over a 20×10 `Box` instead of its `CountingLeaf` (a custom element,
    /// which reports `customElement.requestLeaf` until stage 6a). Hand-derived: the
    /// box padded by 4 is 28×18; the frame layer 60×40 centres it at (16, 11); the
    /// outer padding makes 76×56. The row and outermost layer at (0, 0) 76×56, the
    /// frame layer (8, 8) 60×40, the `mid` layer (24, 19) 28×18, the box (28, 23).
    static func modifierChain() -> some ElementGroup {
        Row {
            Box().width(px(20)).height(px(10))
                .background(.accent).onClick {}
                .padding(px(4)).id("mid").background(.surfaceSecondary).cornerRadius(px(3))
                .frame(width: px(60), height: px(40))
                .background(.surface).cornerRadius(px(5)).onClick {}
                .padding(px(8))
                .background(.separator).cornerRadius(px(9)).onClick {}
        }
    }

    /// Transparent groups: `if`/`else` (an `EitherGroup`), a bare `if` (an
    /// optional), `for` (an `ArrayGroup`), an `EnvironmentScope`, `.disabled` over
    /// a row with a click target, and `AnyElement` — in a `.flexStart` column,
    /// gap 4. None registers a node or an id level of its own; `AnyElement`
    /// forwards its element's id.
    ///
    /// Hand-derived, `flag` true: 10×10 at y 0; the loop's 10×6, 12×6, 14×6 at y 14,
    /// 24, 34; the scoped 20×8 at 44; the disabled row (8×8, gap 2, 6×6, `.flexStart`)
    /// 16×8 at 56, its children at (0, 56) and (10, 56); the erased 14×4 at 68. The
    /// column 20×72. `flag` false: 12×12 at 0 and the optional 16×16 at 16, so the
    /// rest move down by 22 (y 36, 46, 56, 66, 78, 90) and the column is 20×94.
    static func transparentGroups(flag: Bool) -> some ElementGroup {
        Column(gap: px(4)) {
            if flag { fixed(10, 10).background(.accent) } else { fixed(12, 12) }
            if !flag { fixed(16, 16) }
            for i in 0..<3 { fixed(Float(10 + 2 * i), 6) }
            fixed(20, 8).environment(\.layoutDirection, .rightToLeft)
            Row(gap: px(2)) { fixed(8, 8).onClick {}; fixed(6, 6) }.alignItems(.flexStart).disabled(true)
            AnyElement(fixed(14, 4))
        }
        .alignItems(.flexStart)
    }
}

/// The lowered rects of every recorded element except the harness root, sorted,
/// for a literal comparison that does not depend on how a transparent group
/// numbers its members (ids are compared by the harness itself).
private func sortedLoweredRects(_ r: LayoutDifferential.Report) -> [Bounds<Pixels>] {
    r.loweredBounds.filter { $0.key != rootID }.values.sorted {
        ($0.origin.y.value, $0.origin.x.value, $0.size.width.value, $0.size.height.value)
            < ($1.origin.y.value, $1.origin.x.value, $1.size.width.value, $1.size.height.value)
    }
}

// MARK: - 5.1 — the corpus agrees

/// **5.1 — stage 1's exit test.** Every corpus tree lowers with **no diagnostic**
/// and agrees with the legacy engine **element by element** and in every
/// whole-frame observation (scene as emitted and finalized, hitboxes,
/// accessibility records with geometry, `StateTable` ids). Per tree, the element
/// count is a `try #require` derived by hand: the harness root, plus each
/// element that records bounds (every group member, every inner modifier layer):
///
/// - counter chrome: root, chrome, three boxes, three texts — **8**;
/// - demo header: root, padding layer, row, two boxes — **5**;
/// - stack cluster: root, stack, three boxes, the badge's text — **6**;
/// - T5: root, column, two texts — **4**; T5b: root, layer, column, two texts — **5**;
/// - T6: root, frame layer, padding layer, box, text — **5**;
/// - T7: root, column, two rows, `a`, `bb`, the 10×30 box, the 50×5 box, `ccc` — **9**;
/// - modifier chain: root, row, outermost layer, frame layer, `mid` layer, box — **6**;
/// - transparent groups: root, column, the branch, three loop boxes, the scoped
///   box, the row and its two boxes, the erased box — **11** with `flag` true,
///   **12** with the optional present. (On lane 4's tree these read 10 and 11:
///   `AnyElement`'s own group entry did not record its bounds — a copy of
///   `Element.prepaintGroup`'s hand-off that lane 1's log missed, record §18
///   lane 5 — so the harness could not see an erased element's rect.)
///
/// Where the geometry is not text's, the lowered rects are literals too.
///
/// Mutations that must redden it: **M5a**, the proposal-side harness root proposes
/// nil×nil (the paragraph measures unwrapped); and one mutation re-run from each
/// earlier lane (the record names them and what they reddened).
@MainActor
@Test func theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement() throws {
    var trees = 0

    let chrome = LayoutDifferential.compare(width: 400, height: 100) { StageOneCorpus.counterChrome() }
    try #require(chrome.elements == 8)
    expectCorpusAgreement(chrome, "counter chrome")
    #expect([containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
                .map { chrome.loweredBounds[$0] }
            == [bounds(0, 0, 260, 60), bounds(12, 12, 36, 36), bounds(60, 12, 140, 36),
                bounds(212, 12, 36, 36)])
    trees += 1

    let header = LayoutDifferential.compare(width: 600, height: 200) { StageOneCorpus.demoHeader() }
    try #require(header.elements == 5)
    expectCorpusAgreement(header, "demo header")
    let row = child(containerID, 0)
    #expect([containerID, row, child(row, 0), child(row, 1)].map { header.loweredBounds[$0] }
            == [bounds(0, 0, 284, 72), bounds(16, 16, 252, 40), bounds(16, 16, 40, 40),
                bounds(68, 30, 200, 12)])
    trees += 1

    let cluster = LayoutDifferential.compare(width: 600, height: 300) { StageOneCorpus.stackCluster() }
    try #require(cluster.elements == 6)
    expectCorpusAgreement(cluster, "stack cluster")
    #expect([containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
                .map { cluster.loweredBounds[$0] }
            == [bounds(0, 0, 360, 128), bounds(0, 0, 360, 128), bounds(100, 28, 160, 72),
                bounds(166, 50, 28, 28)])
    trees += 1

    let t5 = LayoutDifferential.compare(width: 400, height: 400) { StageOneCorpus.textColumn() }
    try #require(t5.elements == 4)
    expectCorpusAgreement(t5, "T5 text column")
    // The paragraph wraps: taller than one 13pt line, and no wider than the root.
    let paragraph = try #require(t5.loweredBounds[child(containerID, 1)])
    #expect(paragraph.size.height > px(32) && paragraph.size.width <= px(400), "T5 paragraph \(paragraph)")
    trees += 1

    let t5b = LayoutDifferential.compare(width: 400, height: 400) { StageOneCorpus.paddedTextColumn() }
    try #require(t5b.elements == 5)
    expectCorpusAgreement(t5b, "T5b padded text column")
    #expect(t5b.loweredBounds[child(containerID, 0)]?.origin == Point(x: px(10), y: px(10)))
    trees += 1

    let t6 = LayoutDifferential.compare(width: 300, height: 200) { StageOneCorpus.paddedFrameOverText() }
    try #require(t6.elements == 5)
    expectCorpusAgreement(t6, "T6 padded frame over text")
    #expect(t6.loweredBounds[containerID] == bounds(0, 0, 100, 40))
    trees += 1

    let t7 = LayoutDifferential.compare(width: 600, height: 200) { StageOneCorpus.nestedRows() }
    try #require(t7.elements == 9)
    expectCorpusAgreement(t7, "T7 nested rows")
    trees += 1

    let chain = LayoutDifferential.compare(width: 300, height: 200) { StageOneCorpus.modifierChain() }
    try #require(chain.elements == 6)
    expectCorpusAgreement(chain, "modifier chain")
    let outer = child(containerID, 0)
    let frameLayer = child(outer, 0)
    let mid = child(frameLayer, 0, "mid")
    #expect([containerID, outer, frameLayer, mid, child(mid, 0)].map { chain.loweredBounds[$0] }
            == [bounds(0, 0, 76, 56), bounds(0, 0, 76, 56), bounds(8, 8, 60, 40),
                bounds(24, 19, 28, 18), bounds(28, 23, 20, 10)])
    trees += 1

    let withBranch = LayoutDifferential.compare(width: 300, height: 300) {
        StageOneCorpus.transparentGroups(flag: true)
    }
    try #require(withBranch.elements == 11)
    expectCorpusAgreement(withBranch, "transparent groups, flag true")
    #expect(sortedLoweredRects(withBranch)
            == [bounds(0, 0, 10, 10), bounds(0, 0, 20, 72), bounds(0, 14, 10, 6), bounds(0, 24, 12, 6),
                bounds(0, 34, 14, 6), bounds(0, 44, 20, 8), bounds(0, 56, 8, 8), bounds(0, 56, 16, 8),
                bounds(10, 56, 6, 6), bounds(0, 68, 14, 4)])
    trees += 1

    let withOptional = LayoutDifferential.compare(width: 300, height: 300) {
        StageOneCorpus.transparentGroups(flag: false)
    }
    try #require(withOptional.elements == 12)
    expectCorpusAgreement(withOptional, "transparent groups, flag false")
    #expect(sortedLoweredRects(withOptional)
            == [bounds(0, 0, 12, 12), bounds(0, 0, 20, 94), bounds(0, 16, 16, 16), bounds(0, 36, 10, 6),
                bounds(0, 46, 12, 6), bounds(0, 56, 14, 6), bounds(0, 66, 20, 8), bounds(0, 78, 8, 8),
                bounds(0, 78, 16, 8), bounds(10, 78, 6, 6), bounds(0, 90, 14, 4)])
    trees += 1

    try #require(trees == 10)
}

// MARK: - 5.2 — the known disagreements, each with its probe arm

/// **5.2.** Every disagreement stage 1 knows of on an otherwise lowerable tree is
/// pinned **with its probe arm**, as literal rects on both sides and a
/// `try #require` that the two sides differ (so a mutant making them agree cannot
/// pass by accident):
///
/// - **text hug** — `Column { Text(long) }.width(60)` (scratch tree T8): the legacy
///   text fills the column's 60 (CSS fit-content); the lowered text answers its
///   widest line wrapped at 60 — computed here from a fresh `ShapingCache` (44 on
///   the design machine) — centred by the column at x = (60 − w) / 2. SwiftUI hugs
///   too (stage-1 probe T2: 45 at 60) and centres (T7). Divergence owned by stage 2;
/// - **`Stack` fit-content** — `Column { Stack { Text(long) } }.width(60)`: legacy
///   60; lowered the widest line (divergence 53, stack-algorithms **A5**: a
///   `ZStack` offers its proposal);
/// - **flexible frame** — `Column { 20×20.frame(minWidth: 40, maxWidth: 80) }.width(100)`:
///   legacy clamps to 40 at x 30; lowered greedy 80 at x 10 (frame probe **D**
///   control; `FR-E`, divergence 35);
/// - **row overflow** — `Row { 80×20; 80×20 }.width(100)`: legacy shrinks both to 50;
///   lowered 80 and 80 from x 0 (stack-algorithms **G9**, **X13**; divergence 55,
///   ruling LR-I).
///
/// No arm reports a field: each disagreement is an answer, not a gap.
///
/// Mutation that must redden it: **M5b**, a probe-backed branch reverted — M2f, the
/// lowered text answers the proposed width (the first two arms agree).
@MainActor
@Test func theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm() throws {
    let cache = ShapingCache()
    let widest = Float(cache.shaped(longString, font: cache.resolveFont(family: nil, size: 13),
                                    wrappingAt: 60).widestLine.rounded())
    var arms = 0

    // Text hug (T8; stage-1 probe T2/T7).
    let hug = LayoutDifferential.compare(width: 300, height: 400) {
        Column { Text(longString) }.width(px(60))
    }
    try #require(hug.elements == 3)
    #expect(hug.unlowerable.isEmpty, "\(hug.unlowerable)")
    let hugText = child(containerID, 0)
    let hugLegacy = try #require(hug.legacyBounds[hugText])
    let hugLowered = try #require(hug.loweredBounds[hugText])
    try #require(hugLegacy != hugLowered)
    #expect(hug.legacyBounds[containerID] == bounds(0, 0, 60, hugLegacy.size.height.value))
    #expect(hug.loweredBounds[containerID] == hug.legacyBounds[containerID])
    #expect(hugLegacy == bounds(0, 0, 60, hugLegacy.size.height.value))
    #expect(hugLowered == bounds((60 - widest) / 2, 0, widest, hugLegacy.size.height.value))
    arms += 1

    // Stack fit-content (divergence 53; stack-algorithms A5).
    let fit = LayoutDifferential.compare(width: 200, height: 300) {
        Column { Stack { Text(longString) } }.width(px(60))
    }
    try #require(fit.elements == 4)
    #expect(fit.unlowerable.isEmpty, "\(fit.unlowerable)")
    let fitText = child(child(containerID, 0), 0)
    let fitLegacy = try #require(fit.legacyBounds[fitText])
    let fitLowered = try #require(fit.loweredBounds[fitText])
    try #require(fitLegacy != fitLowered)
    #expect(fitLegacy == bounds(0, 0, 60, fitLegacy.size.height.value))
    #expect(fitLowered == bounds((60 - widest) / 2, 0, widest, fitLegacy.size.height.value))
    arms += 1

    // Flexible frame (frame probe D control; FR-E, divergence 35).
    let frameID = child(containerID, 0)
    let flexible = LayoutDifferential.compare(width: 200, height: 200) {
        Column { fixed(20, 20).frame(minWidth: px(40), maxWidth: px(80)) }.width(px(100))
    }
    try #require(flexible.elements == 4)
    #expect(flexible.unlowerable.isEmpty, "\(flexible.unlowerable)")
    try #require(flexible.legacyBounds[frameID] != flexible.loweredBounds[frameID])
    #expect(flexible.legacyBounds[frameID] == bounds(30, 0, 40, 20))
    #expect(flexible.loweredBounds[frameID] == bounds(10, 0, 80, 20))
    #expect(flexible.legacyBounds[child(frameID, 0)] == bounds(40, 0, 20, 20))
    #expect(flexible.loweredBounds[child(frameID, 0)] == bounds(40, 0, 20, 20))
    arms += 1

    // Row overflow (stack-algorithms G9, X13; divergence 55, LR-I).
    let overflow = LayoutDifferential.compare(width: 200, height: 100) {
        Row { fixed(80, 20); fixed(80, 20) }.width(px(100))
    }
    try #require(overflow.elements == 4)
    #expect(overflow.unlowerable.isEmpty, "\(overflow.unlowerable)")
    let a = child(containerID, 0), b = child(containerID, 1)
    try #require(overflow.legacyBounds[a] != overflow.loweredBounds[a])
    #expect([a, b].map { overflow.legacyBounds[$0] } == [bounds(0, 0, 50, 20), bounds(50, 0, 50, 20)])
    #expect([a, b].map { overflow.loweredBounds[$0] } == [bounds(0, 0, 80, 20), bounds(80, 0, 80, 20)])
    arms += 1

    try #require(arms == 4)
}

// MARK: - 5.3 = stage 2's 2.15 — the whole demo's census, and every disagreement with its cause

/// A text of width `width` centred in `extent` at absolute `x`, as the frame rounds
/// it: cumulative edges (`Rounding.swift`), so x is `round(x₀)` and the width
/// `round(x₀ + width) − round(x₀)`.
private func centredRounded(at x: Float, in extent: Float, width: Double) -> (x: Float, width: Float) {
    let x0 = Double(x) + (Double(extent) - width) / 2
    return (Float(x0.rounded()), Float((x0 + width).rounded() - x0.rounded()))
}

/// **2.15 — stage 2's exit test** (spec §7, ruling LR-AN as amended; stage 1's 5.3,
/// rewritten in stage 2's lane 2). `demoContent()`, **imported from
/// `MetalUIDemoContent`** (ruling LR-S), at 920×560 in the harness root under
/// diagnostics, animation off.
///
/// **Re-derived once, from a finished stage, by stage 4's lane 5** (`LR-CG`).
/// The site check went in lane 2 and this test was left red across lanes 3 and 4
/// deliberately, so the census is taken once against the whole stage rather than
/// patched three times (spec §6 lane 5, §4.2(c)). What moved: the report loses
/// `list.noLowering`, the `ScrollView` and the `List` stop being 0 wide, and the
/// **2 000 legacy-only row ids become disagreeing** — 29 disagreements become
/// **2 029**, and `legacyOnly` 2 000 becomes **0**. Nothing else moved.
///
/// **1. The report, exactly.** Modal off: `[]`; modal on:
/// `[stack.position, stack.inset]`. Since stage 3's lane 2
/// (`LR-BB`) `scrollView.noLowering` is gone from both, and **nothing replaces
/// it**: the demo's scroller declares no field the lowering cannot take, its
/// content node's record is left unconsumed with every item field at its default,
/// and `flexShrink: 0` is deliberately not carried onto it. No stage-2 field and
/// no `…unconsumed` entry either: every item field the demo declares lowers
/// (grow, stretch, `alignSelf`, the scroller box's zero basis and minimum, the
/// `List` spacer's `flexShrink(0)` on a declared height).
///
/// **2. Every disagreement, with its cause** (modal off: 2035 ids, 6 agreeing — the
/// harness root, the header's layer, row, avatar and bar, the hairline — **2029**
/// disagreeing, **0** legacy-only, 0 lowered-only; of the 2029, 29 are the chrome
/// enumerated by literal below and 2 000 are the `List`'s 500 rows, four ids
/// apiece, asserted by the formula in part **2b**). Rects no text
/// reaches are literals; rects a text reaches are derived below from the shaping
/// cache (`LR-F`): lowered text sizes from `proposalTextMeasurement` at the widths
/// this test derives (648 for the main column, 168 for the sidebar), legacy ones from
/// the same cache at 756 and 60 — and at `nil` for the legacy main column's
/// intrinsic height, which CSS takes from its items' max-content contributions (the
/// paragraph one line tall; which is why the legacy column is 278 tall and its
/// paragraph overflows it).
///
/// | cause | probe arm | isolating pin | rows (legacy → lowered) |
/// |---|---|---|---|
/// | **R** the harness root offers its proposal (divergence 53) and the demo's greedy column fills it | stack-algorithms A5; stage-2 X4, X18 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`, 1.7, 2.10 | outer padding layer 920×439 → 920×560; outer column 888×407 → 888×528; body row 888×310 → 888×431; the sidebar's and main pane's layers' and the main column's heights; the scroller `Box`'s height 0 → 73 |
/// | **55** a declared 196 sidebar is served first where CSS shrinks it to 88 | F5; stack-algorithms G9, G4r | 2.9 | sidebar layer 88 → 196 wide; its column, "Library" and the four bars 60 → 168 wide; main-pane layer x 116 → 224, 788 → 680 wide; main column 756 → 648; every main-pane descendant x + 108; "Text renders" 756 → 648 wide; the paragraph 756×48 → 648×64; the scroller `Box` y 439 → 455 |
/// | **X9** a stretched single-child container does not stretch its child (`LR-AC`) | X9 | 1.3 | the sidebar column 282 → 160 tall |
/// | **3** the lowered viewport fills its proposal (`LR-BC`) | stage-3 V1–V4; A7, A10, A11 | stage 3, lane 2 | the `ScrollView` 420×0 → 420×**73**, the 73 being cause **R**'s own 73 arriving one level deeper (the scroller `Box`'s new height) |
/// | **4** the `List` lowers to a windowed `ProposalLayout` (`LR-BQ`, `LR-BR`) | — | stage 4 lanes 2–3, `ListLoweringTests` | the `List` 420×14000 → 420×14000, at the viewport's origin, and its 500 rows' 2 000 ids. **Both widths are now 420, where they were 0 on the lowered side until this stage**: the layout answers the widest realized row, so the viewport's non-scrolling axis — its content's answer (`CN-M`) — is no longer an empty content's 0 |
///
/// **The `List`'s windowing spacer left this census in stage 4's lane 1**
/// (`LR-BS`): it used to be a `Box` ELEMENT at `child(child(scroll, 0), 0)` and
/// so recorded a `Frame.elementBounds` row of its own (420×0 → 0×0, the
/// thirtieth disagreement); it is now a bare legacy node, which records none.
/// The counts moved by exactly one in each place — 2036 → 2035 ids and 30 → 29
/// disagreements, 2042 → 2041 and 36 → 35 with the modal on — and nothing else
/// in the census moved, which is the measurement that says the demotion changed
/// bookkeeping rather than geometry.
///
/// **Measured first against the prediction** (prototype P3 and scratch R2, record
/// §21): identical in both modal states, every pair (record §21, lane 2).
///
/// **2b. The 500 rows, four ids apiece, by formula** (stage 4, lane 5). Each row
/// contributes the `List`'s own row `Box`, the demo row's `.padding` layer, the
/// inner `Box` and its `Text`. Three causes and one sub-pixel tail, and **no new
/// cause**:
///
/// - **55** puts every row 108pt right (240 against 132) and **55** again, through
///   the taller wrapped paragraph above it, puts it 16pt lower
///   (`loweredScrollerY` 455 against `legacyScrollerY` 439). Row *i* sits at
///   `scrollerY + 28i` on both sides: `index × rowHeight`, which is what the
///   windowed layout places against.
/// - **X9** collapses the inner `Box` from 28 to **16** tall — a stretched
///   single-child container does not stretch its child (`LR-AC`), so where CSS
///   stretches it to the row height the lowering lets it hug its `Text`. The
///   `Text` therefore sits at the row's top on the lowered side and 6pt down
///   (`(28 − 16) / 2`) on the legacy one, which is the `.alignItems(.center)`
///   the demo's row declares.
/// - **the sub-pixel tail of 55**, and it is why 42 of the 500 texts differ in
///   WIDTH by one point. The lowered sidebar is served its declared 196 exactly,
///   so every lowered row text starts at the integer x = 252 and cumulative-edge
///   rounding gives `round(natural)`. The legacy sidebar is flex-shrunk (`SZ-L`)
///   to a width a hair under 88, so the legacy text starts at `144 − d` and the
///   same rounding gives `floor(natural)` for exactly those rows whose natural
///   width has a fraction in `[0.5, 0.5 + d)`. The test solves for `d` from the
///   500 rows and asserts the bracket: **`d ∈ (0.0615234375, 0.076171875]`**,
///   measured, and the bracket being non-empty is the statement that ONE
///   fractional origin explains all 500 — a row wrong for any other reason would
///   empty it. 210 of the 500 have a fraction at or above 0.5 and only 42 floor,
///   so this is not "the legacy engine floors".
///
/// **3. Modal on**: 2041 ids, 6 agreeing, **2035** disagreeing — the 29 chrome
/// rows and the 2 000 row ids above (the `List` one index later, after the
/// `Deferred`) plus the modal's six
/// ids (the `Deferred`, its `Stack`, the card's padding layer, its column and two
/// texts), which are stage 5's (`position`, `inset`) and asserted by id only.
/// **The modal no longer moves any lowered rect in the scroll subtree.** It did
/// until this stage: with one child the single-child stretch elision (`LR-AC`)
/// left the `List` unstretched and 0 wide, and adding the `Deferred` as a second
/// child stretched both to 420. The `List` now measures 420 by itself — its
/// widest realized row — so the two modal states agree and the override table
/// that carried the difference is gone.
///
/// Mutations that must redden it: **M1a** (stretch not aliased), **M2a** (grow on the
/// cross axis), **M1d** (the elision removed: the X9 row moves), **M2k** (cause R's
/// rows move), **M1m′** (only if the demo reaches a `noLowering` site's records —
/// recorded either way), **M5c′** (the `flexGrow.weights` check always reporting);
/// and, from stage 3's lane 2, **M2a** (the viewport a plain native leaf: the 73
/// collapses) and **M2d** (`flexShrink: 0` carried onto the lowered content style:
/// `scrollView.flexShrink.unconsumed` joins the report).
@MainActor
@Test func theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn() throws {
    func entry(_ site: LoweringSite, _ field: String) -> UnlowerableField {
        UnlowerableField(site: site, field: field)
    }
    demoModel.animationDemoActive = false
    demoModel.showModal = false
    let report = LayoutDifferential.compare(width: 920, height: 560) { demoContent() }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    try #require(report.elements == 2035, "\(report.elements)")
    #expect(report.agreeing.count == 6 && report.legacyOnly.isEmpty && report.loweredOnly.isEmpty,
            "agreeing \(report.agreeing.count) legacyOnly \(report.legacyOnly.count) loweredOnly \(report.loweredOnly.count)")

    // Ids.
    let outerLayer = child(rootID, 0), outerColumn = child(outerLayer, 0)
    let headerLayer = child(outerColumn, 0), headerRow = child(headerLayer, 0)
    let hairline = child(outerColumn, 1), body = child(outerColumn, 2)
    let sidebarLayer = child(body, 0), sidebar = child(sidebarLayer, 0)
    let mainLayer = child(body, 1), main = child(mainLayer, 0)
    let cluster = child(main, 0), badge = child(cluster, 2)
    let counter = child(main, 1, "counter")
    let scrollerBox = child(main, 4), scroll = child(scrollerBox, 0)

    // Text, from the shaping cache.
    let cache = ShapingCache()
    let f13 = cache.resolveFont(family: nil, size: 13), f22 = cache.resolveFont(family: nil, size: 22)
    func legacyHeight(_ s: String, _ font: ResolvedFont, _ width: Double?) -> Float {
        Float(cache.shaped(s, font: font, wrappingAt: width).totalHeight.rounded())
    }
    func loweredHeight(_ s: String, _ font: ResolvedFont, _ width: Double) -> Float {
        Float(proposalTextMeasurement(s, font: font, cache: cache,
                                      proposal: ProposedSize(width: width, height: nil)).size.height.rounded())
    }
    func natural(_ s: String, _ font: ResolvedFont) -> Double { cache.shaped(s, font: font, wrappingAt: nil).widestLine }

    // Legacy heights (CSS): the main column's intrinsic height is its items' max-content
    // contributions — cluster 128, chrome 60, the two texts one line each, the scroller 0 —
    // plus four gaps of 12; the body row is that column's padded height; the outer layer
    // pads the header, the hairline and the body.
    let legacyMain = 128 + 60 + legacyHeight("Text renders", f22, nil) + legacyHeight(demoParagraph, f13, nil) + 4 * 12
    let legacyBody = 16 + legacyMain + 16
    let legacyOuter = 16 + 72 + 12 + 1 + 12 + legacyBody + 16
    let legacyRenders = legacyHeight("Text renders", f22, 756), legacyParagraph = legacyHeight(demoParagraph, f13, 756)
    let legacyParagraphY = 129 + 128 + 12 + 60 + 12 + legacyRenders + 12
    let legacyScrollerY = legacyParagraphY + legacyParagraph + 12
    // Lowered: the root's 560 (cause R) and the 196 sidebar (cause 55).
    let loweredBody: Float = 560 - 16 - 72 - 12 - 1 - 12 - 16
    let loweredMain = loweredBody - 32
    let loweredRenders = loweredHeight("Text renders", f22, 648), loweredParagraph = loweredHeight(demoParagraph, f13, 648)
    let loweredParagraphY = 129 + 128 + 12 + 60 + 12 + loweredRenders + 12
    let loweredScrollerY = loweredParagraphY + loweredParagraph + 12
    let library = loweredHeight("Library", f13, 168)
    try #require(legacyHeight("Library", f13, 60) == library)

    typealias Row = (id: GlobalElementID, legacy: Bounds<Pixels>, lowered: Bounds<Pixels>)
    func shifted(_ id: GlobalElementID, _ b: Bounds<Pixels>) -> Row {
        (id, b, Bounds(origin: Point(x: b.origin.x + px(108), y: b.origin.y), size: b.size))
    }
    func centredText(_ id: GlobalElementID, _ s: String, _ font: ResolvedFont, x: Float, y: Float,
                     extent: Float, lineHeight: Float) -> Row {
        let t = centredRounded(at: x, in: extent, width: natural(s, font))
        return shifted(id, bounds(t.x, y + (extent - lineHeight) / 2, t.width, lineHeight))
    }
    var expected: [Row] = [
        // R
        (outerLayer, bounds(0, 0, 920, legacyOuter), bounds(0, 0, 920, 560)),
        (outerColumn, bounds(16, 16, 888, legacyOuter - 32), bounds(16, 16, 888, 528)),
        (body, bounds(16, 113, 888, legacyBody), bounds(16, 113, 888, loweredBody)),
        // 55 (and R, X9)
        (sidebarLayer, bounds(16, 113, 88, legacyBody), bounds(16, 113, 196, loweredBody)),
        (sidebar, bounds(30, 127, 60, legacyBody - 28), bounds(30, 127, 168, library + 4 * 26 + 4 * 10)),
        (child(sidebar, 0), bounds(30, 127, 60, library), bounds(30, 127, 168, library)),
    ]
    for bar in 1...4 {
        let y = 127 + library + 10 + Float(bar - 1) * 36
        expected.append((child(sidebar, bar), bounds(30, y, 60, 26), bounds(30, y, 168, 26)))
    }
    expected += [
        (mainLayer, bounds(116, 113, 788, legacyBody), bounds(224, 113, 680, loweredBody)),
        (main, bounds(132, 129, 756, legacyMain), bounds(240, 129, 648, loweredMain)),
        shifted(cluster, bounds(132, 129, 360, 128)),
        shifted(child(cluster, 0), bounds(132, 129, 360, 128)),
        shifted(child(cluster, 1), bounds(232, 157, 160, 72)),
        shifted(badge, bounds(298, 179, 28, 28)),
        centredText(child(badge, 0), "3", f13, x: 298, y: 179, extent: 28, lineHeight: 16),
        shifted(counter, bounds(132, 269, 260, 60)),
        shifted(child(counter, 0), bounds(144, 281, 36, 36)),
        centredText(child(child(counter, 0), 0), "-", f22, x: 144, y: 281, extent: 36, lineHeight: 26),
        shifted(child(counter, 1), bounds(192, 281, 140, 36)),
        shifted(child(child(counter, 1), 0), {
            let t = centredRounded(at: 192, in: 140, width: natural("Count 0", f22))
            return bounds(t.x, 286, t.width, 26)
        }()),
        shifted(child(counter, 2), bounds(344, 281, 36, 36)),
        centredText(child(child(counter, 2), 0), "+", f22, x: 344, y: 281, extent: 36, lineHeight: 26),
        (child(main, 2), bounds(132, 341, 756, legacyRenders), bounds(240, 341, 648, loweredRenders)),
        (child(main, 3), bounds(132, legacyParagraphY, 756, legacyParagraph),
         bounds(240, loweredParagraphY, 648, loweredParagraph)),
        (scrollerBox, bounds(132, legacyScrollerY, 420, 0),
         bounds(240, loweredScrollerY, 420, 129 + loweredMain - loweredScrollerY)),
        // 3 (the lowered viewport, stage 3 lane 2) and 4 (the windowed `List`,
        // stage 4 lane 2). The viewport takes the scroller `Box`'s own height and
        // its subtree moves to its origin; **both widths are 420 since stage 4**,
        // where they were 0 — the `List` answers its widest realized row, so the
        // viewport's non-scrolling axis (`CN-M`) is no longer an empty content's 0.
        (scroll, bounds(132, legacyScrollerY, 420, 0),
         bounds(240, loweredScrollerY, 420, 129 + loweredMain - loweredScrollerY)),
        (child(scroll, 0), bounds(132, legacyScrollerY, 420, 14000),
         bounds(240, loweredScrollerY, 420, 14000)),
    ]
    try #require(expected.count == 29)
    // The predictions the derivations must reproduce (P3, R2; record §21).
    #expect([legacyOuter, legacyBody, legacyRenders, legacyParagraph, legacyScrollerY,
             loweredRenders, loweredParagraph, loweredScrollerY, library] == [439, 310, 26, 48, 439, 26, 64, 455, 16])

    let agreeingExpected: Set<GlobalElementID> = [rootID, headerLayer, headerRow, child(headerRow, 0),
                                                  child(headerRow, 1), hairline]
    #expect(Set(report.agreeing) == agreeingExpected)
    let disagreeing = Dictionary(uniqueKeysWithValues: report.disagreeing.map { ($0.id, ($0.legacy, $0.lowered)) })
    try #require(report.disagreeing.count == 2029, "\(report.disagreeing.count)")
    for row in expected {
        let got = disagreeing[row.id]
        #expect(got?.0 == row.legacy && got?.1 == row.lowered,
                "\(row.id): expected \(row.legacy) → \(row.lowered), got \(String(describing: got))")
    }

    // 2b. The 500 rows, four ids apiece. See part 2b of the doc comment: causes
    // 55 (x + 108, y + 16), X9 (the inner Box 28 → 16 tall) and 55's sub-pixel
    // tail (42 of the 500 texts one point narrower on the legacy side).
    let rowIDs = try rowCensus(list: child(scroll, 0), pairs: disagreeing, cache: cache, f13: f13,
                               legacyTop: legacyScrollerY, loweredTop: 455)
    try #require(rowIDs.count == 2000, "\(rowIDs.count)")
    // Nothing is left over: the 29 chrome rows and the 2 000 row ids are the
    // whole of `disagreeing`, so no disagreement escapes a named cause.
    let namedIDs = Set(expected.map(\.id)).union(rowIDs)
    #expect(Set(disagreeing.keys) == namedIDs,
            "unattributed: \(Set(disagreeing.keys).subtracting(namedIDs).count)")

    // 3. Modal on.
    demoModel.showModal = true
    defer { demoModel.showModal = false }
    let modal = LayoutDifferential.compare(width: 920, height: 560) { demoContent() }
    // Stage 5, lane 1 (`LR-CH`, `LR-CI`): the modal is a presentation root and
    // lowers, so the report that read `[stack.position, stack.inset]` is empty.
    #expect(modal.unlowerable.isEmpty, "\(modal.unlowerable)")
    try #require(modal.elements == 2041, "\(modal.elements)")
    #expect(Set(modal.agreeing) == agreeingExpected)
    try #require(modal.disagreeing.count == 2035, "\(modal.disagreeing.count)")
    let modalPairs = Dictionary(uniqueKeysWithValues: modal.disagreeing.map { ($0.id, ($0.legacy, $0.lowered)) })
    let deferred = child(scroll, 0), stack = child(deferred, 0), card = child(stack, 0), column = child(card, 0)
    for id in [deferred, stack, card, column, child(column, 0), child(column, 1)] {
        #expect(modalPairs[id] != nil, "modal id \(id)")
    }
    // **No lowered rect in the scroll subtree moves with the modal on any more,
    // and the override table that carried the difference is gone** (stage 4, lane
    // 5). Until this stage the single-child stretch elision (`LR-AC`) left the
    // `List` unstretched and 0 wide with one child, and the `Deferred` arriving as
    // a second child stretched the `List` and the viewport to 420. The `List` now
    // answers 420 by itself — its widest realized row — so both modal states read
    // the same pair, and the `List`'s own rows are laid out identically.
    for row in expected {
        // The `List` sits one index later, after the `Deferred`.
        let id = row.id == child(scroll, 0) ? child(scroll, 1) : row.id
        let got = modalPairs[id]
        #expect(got?.0 == row.legacy && got?.1 == row.lowered,
                "modal \(id): expected \(row.legacy) → \(row.lowered), got \(String(describing: got))")
    }
    let modalRowIDs = try rowCensus(list: child(scroll, 1), pairs: modalPairs, cache: cache, f13: f13,
                                    legacyTop: legacyScrollerY, loweredTop: 455)
    let modalNamed = Set(expected.map { $0.id == child(scroll, 0) ? child(scroll, 1) : $0.id })
        .union(modalRowIDs)
        .union([deferred, stack, card, column, child(column, 0), child(column, 1)])
    #expect(Set(modalPairs.keys) == modalNamed,
            "modal unattributed: \(Set(modalPairs.keys).subtracting(modalNamed).count)")
}

/// The demo `List`'s 500 rows, four ids apiece, asserted by formula against
/// `pairs` — part **2b** of `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`'s
/// doc comment, which is where the three causes and the sub-pixel tail are
/// argued. Returns the 2 000 ids it covered, so the caller can assert that
/// nothing in the report escapes a named cause.
///
/// **A row's four ids** are the `List`'s own row `Box` (named
/// `String(describing: datum.id)` one level under the `List`), the demo row's
/// `.padding` layer at `child(at: 0)` below it, the inner `Box` below that and
/// its `Text`.
@MainActor
private func rowCensus(list: GlobalElementID,
                       pairs: [GlobalElementID: (Bounds<Pixels>, Bounds<Pixels>)],
                       cache: ShapingCache, f13: ResolvedFont,
                       legacyTop: Float, loweredTop: Float) throws -> Set<GlobalElementID> {
    var covered = Set<GlobalElementID>()
    // The fractions that decide the sub-pixel tail, collected so the bracket on
    // the legacy origin's deficit can be asserted afterwards.
    var flooredFractions: [Double] = [], roundedFractionsAtOrAboveHalf: [Double] = []

    for i in 0..<500 {
        let rowBox = child(list, 0, "\(i)")
        let layer = child(rowBox, 0), inner = child(layer, 0), text = child(inner, 0)
        covered.formUnion([rowBox, layer, inner, text])
        let ly = legacyTop + 28 * Float(i), py = loweredTop + 28 * Float(i)

        // The row `Box` and the `.padding` layer: cause 55 twice over, nothing else.
        for id in [rowBox, layer] {
            let got = pairs[id]
            #expect(got?.0 == bounds(132, ly, 420, 28) && got?.1 == bounds(240, py, 420, 28),
                    "row \(i) wrapper \(id): \(String(describing: got))")
        }
        // The inner `Box`: X9 collapses it from the stretched 28 to its content's 16.
        let innerGot = pairs[inner]
        #expect(innerGot?.0 == bounds(144, ly, 396, 28) && innerGot?.1 == bounds(252, py, 396, 16),
                "row \(i) inner: \(String(describing: innerGot))")

        // The `Text`. Its x, y and height are exact on both sides; its WIDTH is
        // `round(natural)` on the lowered side (an integer origin) and either that
        // or `floor(natural)` on the legacy one (an origin `d` below the integer).
        let natural = cache.shaped("Row \(i + 1) of 500 — a scrollable list item",
                                   font: f13, wrappingAt: nil).widestLine
        let fraction = natural - natural.rounded(.down)
        let textGot = try #require(pairs[text], "row \(i) text")
        #expect(textGot.0.origin == Point(x: px(144), y: px(ly + 6)) && textGot.0.size.height == px(16),
                "row \(i) legacy text: \(textGot.0)")
        #expect(textGot.1 == bounds(252, py, Float(natural.rounded()), 16),
                "row \(i) lowered text: \(textGot.1)")
        if textGot.0.size.width == px(Float(natural.rounded(.down))), fraction >= 0.5 {
            flooredFractions.append(fraction)
        } else {
            #expect(textGot.0.size.width == px(Float(natural.rounded())),
                    "row \(i) legacy text width: \(textGot.0.size.width) for \(natural)")
            if fraction >= 0.5 { roundedFractionsAtOrAboveHalf.append(fraction) }
        }
    }

    // **One fractional legacy origin explains all 500.** `d` is the amount by
    // which the flex-shrunk sidebar (`SZ-L`) leaves the legacy main pane short of
    // the integer, and the rows that floor are exactly those whose natural width
    // has a fraction in `[0.5, 0.5 + d)`. A row that floored for any other reason
    // would push `lower` past `upper` and empty the bracket.
    try #require(flooredFractions.count == 42, "\(flooredFractions.count)")
    try #require(roundedFractionsAtOrAboveHalf.count == 168, "\(roundedFractionsAtOrAboveHalf.count)")
    let lower = (flooredFractions.max() ?? 0) - 0.5
    let upper = (roundedFractionsAtOrAboveHalf.min() ?? 0.5) - 0.5
    #expect(lower < upper, "no single legacy origin explains the 500 rows: (\(lower), \(upper)]")
    #expect(lower == 0.0615234375 && upper == 0.076171875, "d bracket moved: (\(lower), \(upper)]")
    return covered
}
