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
// harness (`LayoutDifferential.swift`) until stage 9, which deleted the legacy
// engine: the tests keep "lowers with no diagnostic", their element counts and
// every lowered literal, and element-by-element agreement is the deleted concept
// (ruling `LR-FE` item 2; record §51, lane 1).
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
    Box().cssWidth(px(w)).cssHeight(px(h))
}

/// Nothing was reported. (Until stage 9 this was `expectCorpusAgreement`, which
/// also required every element and whole-frame observation to agree with the
/// legacy engine's; that comparison is the deleted concept, `LR-FE` item 2.)
@MainActor
func expectCorpusNothingReported(_ r: LayoutDifferential.Report, _ arm: String,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.unlowerable.isEmpty, "\(arm): \(r.unlowerable)", sourceLocation: sourceLocation)
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
                .cssWidth(px(40)).cssHeight(px(40))
                .background(.accent)
                .cornerRadius(px(20))
            Box()
                .cssWidth(px(200))
                .cssHeight(px(12))
                .background(.surfaceSecondary)
                .cornerRadius(px(6))
        }
        .alignItems(.center)
        .padding(px(16))
        .alignItems(.center)
        .cssHeight(px(72))
        .background(.surface)
        .cornerRadius(px(14))
    }

    /// The demo's stack cluster (`demoContent()`), with its `.alignSelf(.flexStart)`
    /// dropped (stage 2). Hand-derived: the stack is its largest child, 360×128;
    /// the 160×72 card at (100, 28); the 28×28 badge at (166, 50).
    static func stackCluster() -> some ElementGroup {
        Stack(alignment: .center) {
            Box()
                .cssWidth(px(360))
                .cssHeight(px(128))
                .background(.accent)
                .cornerRadius(px(12))
            Box()
                .cssWidth(px(160))
                .cssHeight(px(72))
                .background(.surface)
                .cornerRadius(px(10))
            Box(decoration: Decoration(background: .surfaceSecondary, cornerRadius: px(14))) {
                Text("3").font(size: 13)
            }
            .cssWidth(px(28))
            .cssHeight(px(28))
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

    /// The retired `ModifierCompositionProofTests.aModifierChainIsIdenticalToHandBuiltNestedBoxes`'s
    /// chain (stage 7b's N2.2 gave it a proposal-authority twin,
    /// `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`,
    /// record §49 row 231), over a 20×10 `Box` instead of its `CountingLeaf` (a custom element,
    /// which reported `customElement.requestNode` until stage 6a made it a Dual
    /// native leaf under the proposal authority). Hand-derived: the
    /// box padded by 4 is 28×18; the frame layer 60×40 centres it at (16, 11); the
    /// outer padding makes 76×56. The row and outermost layer at (0, 0) 76×56, the
    /// frame layer (8, 8) 60×40, the `mid` layer (24, 19) 28×18, the box (28, 23).
    static func modifierChain() -> some ElementGroup {
        Row {
            Box().cssWidth(px(20)).cssHeight(px(10))
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
/// numbers its members.
private func sortedLoweredRects(_ r: LayoutDifferential.Report) -> [Bounds<Pixels>] {
    r.bounds.filter { $0.key != rootID }.values.sorted {
        ($0.origin.y.value, $0.origin.x.value, $0.size.width.value, $0.size.height.value)
            < ($1.origin.y.value, $1.origin.x.value, $1.size.width.value, $1.size.height.value)
    }
}

// MARK: - 5.1 — the corpus lowers

/// **5.1 — stage 1's exit test.** Every corpus tree lowers with **no diagnostic**
/// (and, until stage 9, agreed with the legacy engine **element by element** and in
/// every whole-frame observation — the deleted concept, `LR-FE` item 2). Per tree,
/// the element
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
///
/// **Renamed at stage 9** from
/// `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (`LR-FE`
/// item 6).
@MainActor
@Test func theStageOneCorpusLowersWithNoDiagnostic() throws {
    var trees = 0

    let chrome = LayoutDifferential.report(width: 400, height: 100) { StageOneCorpus.counterChrome() }
    // 11 since stage 8 (`LR-EZ`): the demo's three squares each gained a `.frame`
    // layer (`LR-ES`'s R1–R3), one identity level apiece (R7) — 8 + 3.
    try #require(chrome.elements == 11)
    expectCorpusNothingReported(chrome, "counter chrome")
    #expect([containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
                .map { chrome.bounds[$0] }
            == [bounds(0, 0, 260, 60), bounds(12, 12, 36, 36), bounds(60, 12, 140, 36),
                bounds(212, 12, 36, 36)])
    trees += 1

    let header = LayoutDifferential.report(width: 600, height: 200) { StageOneCorpus.demoHeader() }
    try #require(header.elements == 5)
    expectCorpusNothingReported(header, "demo header")
    let row = child(containerID, 0)
    #expect([containerID, row, child(row, 0), child(row, 1)].map { header.bounds[$0] }
            == [bounds(0, 0, 284, 72), bounds(16, 16, 252, 40), bounds(16, 16, 40, 40),
                bounds(68, 30, 200, 12)])
    trees += 1

    let cluster = LayoutDifferential.report(width: 600, height: 300) { StageOneCorpus.stackCluster() }
    try #require(cluster.elements == 6)
    expectCorpusNothingReported(cluster, "stack cluster")
    #expect([containerID, child(containerID, 0), child(containerID, 1), child(containerID, 2)]
                .map { cluster.bounds[$0] }
            == [bounds(0, 0, 360, 128), bounds(0, 0, 360, 128), bounds(100, 28, 160, 72),
                bounds(166, 50, 28, 28)])
    trees += 1

    let t5 = LayoutDifferential.report(width: 400, height: 400) { StageOneCorpus.textColumn() }
    try #require(t5.elements == 4)
    expectCorpusNothingReported(t5, "T5 text column")
    // The paragraph wraps: taller than one 13pt line, and no wider than the root.
    let paragraph = try #require(t5.bounds[child(containerID, 1)])
    #expect(paragraph.size.height > px(32) && paragraph.size.width <= px(400), "T5 paragraph \(paragraph)")
    trees += 1

    let t5b = LayoutDifferential.report(width: 400, height: 400) { StageOneCorpus.paddedTextColumn() }
    try #require(t5b.elements == 5)
    expectCorpusNothingReported(t5b, "T5b padded text column")
    #expect(t5b.bounds[child(containerID, 0)]?.origin == Point(x: px(10), y: px(10)))
    trees += 1

    let t6 = LayoutDifferential.report(width: 300, height: 200) { StageOneCorpus.paddedFrameOverText() }
    try #require(t6.elements == 5)
    expectCorpusNothingReported(t6, "T6 padded frame over text")
    #expect(t6.bounds[containerID] == bounds(0, 0, 100, 40))
    trees += 1

    let t7 = LayoutDifferential.report(width: 600, height: 200) { StageOneCorpus.nestedRows() }
    try #require(t7.elements == 9)
    expectCorpusNothingReported(t7, "T7 nested rows")
    trees += 1

    let chain = LayoutDifferential.report(width: 300, height: 200) { StageOneCorpus.modifierChain() }
    try #require(chain.elements == 6)
    expectCorpusNothingReported(chain, "modifier chain")
    let outer = child(containerID, 0)
    let frameLayer = child(outer, 0)
    let mid = child(frameLayer, 0, "mid")
    #expect([containerID, outer, frameLayer, mid, child(mid, 0)].map { chain.bounds[$0] }
            == [bounds(0, 0, 76, 56), bounds(0, 0, 76, 56), bounds(8, 8, 60, 40),
                bounds(24, 19, 28, 18), bounds(28, 23, 20, 10)])
    trees += 1

    let withBranch = LayoutDifferential.report(width: 300, height: 300) {
        StageOneCorpus.transparentGroups(flag: true)
    }
    try #require(withBranch.elements == 11)
    expectCorpusNothingReported(withBranch, "transparent groups, flag true")
    #expect(sortedLoweredRects(withBranch)
            == [bounds(0, 0, 10, 10), bounds(0, 0, 20, 72), bounds(0, 14, 10, 6), bounds(0, 24, 12, 6),
                bounds(0, 34, 14, 6), bounds(0, 44, 20, 8), bounds(0, 56, 8, 8), bounds(0, 56, 16, 8),
                bounds(10, 56, 6, 6), bounds(0, 68, 14, 4)])
    trees += 1

    let withOptional = LayoutDifferential.report(width: 300, height: 300) {
        StageOneCorpus.transparentGroups(flag: false)
    }
    try #require(withOptional.elements == 12)
    expectCorpusNothingReported(withOptional, "transparent groups, flag false")
    #expect(sortedLoweredRects(withOptional)
            == [bounds(0, 0, 12, 12), bounds(0, 0, 20, 94), bounds(0, 16, 16, 16), bounds(0, 36, 10, 6),
                bounds(0, 46, 12, 6), bounds(0, 56, 14, 6), bounds(0, 66, 20, 8), bounds(0, 78, 8, 8),
                bounds(0, 78, 16, 8), bounds(10, 78, 6, 6), bounds(0, 90, 14, 4)])
    trees += 1

    try #require(trees == 10)
}

// MARK: - 5.2 — the known disagreements, each with its probe arm

/// **5.2.** Every disagreement stage 1 knew of on an otherwise lowerable tree is
/// pinned **with its probe arm**. Until stage 9 each was literal rects on both
/// sides and a `try #require` that the two differed; since then each is the
/// lowered literal with a separating `try #require` of its own where the arm has
/// one (the widest wrapped line narrower than the 60 offered):
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
///
/// **Renamed at stage 9** from `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm`
/// (`LR-FE` item 6).
@MainActor
@Test func theStageOneCorpusPinsEachSwiftUIAnswerWithItsProbeArm() throws {
    let cache = ShapingCache()
    let shaped60 = cache.shaped(longString, font: cache.resolveFont(family: nil, size: 13), wrappingAt: 60)
    let widest = Float(shaped60.widestLine.rounded())
    let height60 = Float(shaped60.totalHeight.rounded())
    try #require(widest < 60, "the widest line must be narrower than the 60 offered: \(widest)")
    var arms = 0

    // Text hug (T8; stage-1 probe T2/T7).
    let hug = LayoutDifferential.report(width: 300, height: 400) {
        Column { Text(longString) }.cssWidth(px(60))
    }
    try #require(hug.elements == 3)
    #expect(hug.unlowerable.isEmpty, "\(hug.unlowerable)")
    let hugText = child(containerID, 0)
    let hugLowered = try #require(hug.bounds[hugText])
    #expect(hug.bounds[containerID] == bounds(0, 0, 60, height60))
    #expect(hugLowered == bounds((60 - widest) / 2, 0, widest, height60))
    arms += 1

    // Stack fit-content (divergence 53; stack-algorithms A5).
    let fit = LayoutDifferential.report(width: 200, height: 300) {
        Column { Stack { Text(longString) } }.cssWidth(px(60))
    }
    try #require(fit.elements == 4)
    #expect(fit.unlowerable.isEmpty, "\(fit.unlowerable)")
    let fitText = child(child(containerID, 0), 0)
    let fitLowered = try #require(fit.bounds[fitText])
    #expect(fitLowered == bounds((60 - widest) / 2, 0, widest, height60))
    arms += 1

    // Flexible frame (frame probe D control; FR-E, divergence 35).
    let frameID = child(containerID, 0)
    let flexible = LayoutDifferential.report(width: 200, height: 200) {
        Column { fixed(20, 20).frame(minWidth: px(40), maxWidth: px(80)) }.cssWidth(px(100))
    }
    try #require(flexible.elements == 4)
    #expect(flexible.unlowerable.isEmpty, "\(flexible.unlowerable)")
    #expect(flexible.bounds[frameID] == bounds(10, 0, 80, 20))
    #expect(flexible.bounds[child(frameID, 0)] == bounds(40, 0, 20, 20))
    arms += 1

    // Row overflow (stack-algorithms G9, X13; divergence 55, LR-I).
    let overflow = LayoutDifferential.report(width: 200, height: 100) {
        Row { fixed(80, 20); fixed(80, 20) }.cssWidth(px(100))
    }
    try #require(overflow.elements == 4)
    #expect(overflow.unlowerable.isEmpty, "\(overflow.unlowerable)")
    let a = child(containerID, 0), b = child(containerID, 1)
    #expect([a, b].map { overflow.bounds[$0] } == [bounds(0, 0, 80, 20), bounds(80, 0, 80, 20)])
    arms += 1

    try #require(arms == 4)
}

// MARK: - 5.3 = stage 2's 2.15 — the whole demo's census, and every disagreement with its cause

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
/// **1. The report, exactly.** Modal off: `[]`; modal on: `[]` since stage 5's
/// lane 1 (`LR-CH`: the modal is a presentation root and lowers), where it read
/// `[stack.position, stack.inset]`. Since stage 3's lane 2
/// (`LR-BB`) `scrollView.noLowering` is gone from both, and **nothing replaces
/// it**: the demo's scroller declares no field the lowering cannot take, its
/// content node's record is left unconsumed with every item field at its default,
/// and `flexShrink: 0` is deliberately not carried onto it. No stage-2 field and
/// no `…unconsumed` entry either: every item field the demo declares lowers
/// (grow, stretch, `alignSelf`, the scroller box's zero basis and minimum, the
/// `List` spacer's `flexShrink(0)` on a declared height).
///
/// **Re-derived by stage 8's lane 1** (`LR-EZ`; record §50, lane 1). Stage 8
/// converts the demo to `.frame` by the recipe (`LR-ES`), and production's
/// answer — the proposal side, read by the fourteen-image comparison at 0 px
/// against `85217e3` — does not move. **The legacy side does, and this census is
/// the one test that reads it**: a `.frame` layer is the same kind of box on both
/// engines, so the legacy engine now serves the sidebar its 196 (divergence 55's
/// flex-shrink has nothing to shrink) and most of the tree agrees, while two
/// legacy-frame answers `FR-E`/`FR-O` recorded and stage 7b retired the pins of
/// (record §49 rows 195–206) now reach the demo. Each converted element also
/// gained an identity level (R7): 2035 ids became **3053**. The census went
/// from 6 agreeing / 2029 disagreeing to **3031 / 22**, and the 500 rows' 2 000
/// disagreements (part 2b until this stage, with `rowCensus` and the sub-pixel
/// bracket on the legacy sidebar's shrunk origin) all agree now and are gone.
///
/// **2. Every disagreement, with its cause** (modal off: 3053 ids, **3031**
/// agreeing, **22** disagreeing, 0 legacy-only, 0 lowered-only), each asserted
/// by literal below, and the 22 are the whole of the report's disagreements:
///
/// | cause | rows (legacy → lowered) |
/// |---|---|
/// | **R** the harness root offers its proposal (divergence 53), unchanged | the lowered heights: outer layer 560, outer column 528, body 431, the sidebar's and main pane's layers 431, the main column 399, the scroller box 73 |
/// | **O** `FR-O`: on the legacy engine a single-axis infinite maximum is inert (the frame's `Style` carries no row for it) where the lowering's frame is greedy | the header bar's outer frame 0 → 804 wide; the scroller box's greedy frame hugs the `List`'s 14 000 (`demoRowCount × rowHeight`) on the legacy side, so the scroller box, its greedy frame, its `Box` and the `ScrollView` read 420×14000 → 420×73 and every ancestor's legacy height carries the 14 000: main column 128 + 60 + 26 + 16 + 14000 + 4 × 12 = 14278, body 14310, outer column 14407, outer layer 14439 |
/// | **53f** divergence 53 at a frame layer: the legacy frame is a one-cell stack (`CN-N`) that offers its child fit-content and centres it (`.center`, or `.top`'s horizontal centre); the lowered frame offers its proposal | the header's padding layer 84 wide (16 + the row's 40 + 12 + O's 0 bar + 16) centred in 888 at x 418 → 888 at 16, and so its row (52 → 856), the avatar's frame and the avatar's `Box` 402 pt right; the sidebar's padding layer 70 wide (14 + "Library"'s 42 + 14) centred in 196 at x 79 → 196 at 16, and so its column, "Library" and the four bars' frames 42 → 168 wide, 63 pt right |
///
/// Every other rect agrees, including every text in the main pane (both sides
/// now wrap the paragraph at 648) and all 3 000 row ids. Rects a text reaches are
/// derived from the shaping cache (`LR-F`): the legacy main column from its items'
/// max-content contributions, the lowered one from the root's 560.
///
/// **3. Modal on**: 3060 ids, **3033** agreeing (the `Deferred` and the scrim
/// `Stack` agree, 920×560 at the origin, as before), **27** disagreeing — the 22
/// above and five of the modal's: the card's frame layer, its padding layer, its
/// column and the column's two texts, by one cause, **C**, unchanged from stage
/// 5: the legacy column's height is its items' max-content contributions (the
/// paragraph one line tall), where the lowering measures the paragraph at the
/// column's 320. The card is 40 taller than its column and centred in the window
/// by the scrim `Stack`, so it sits (lowered − legacy) / 2 higher on the lowered
/// side. (Four of the modal's ids disagreed before stage 8; the card's new
/// `.frame` layer is the fifth.)
///
/// **Collapsed at stage 9** (record §51, lane 1; `LR-FE` item 2): the legacy
/// engine is gone, so the census keeps its report, its id counts (3053 and 3060),
/// the 22 rows' and the modal's five rows' **lowered** literals and the `Deferred`
/// and scrim at 920×560, and loses the agreeing count, the legacy literals and the
/// "nothing is left over" check — which read the legacy side, and whose job
/// (catching an element no literal names moving) the demo's byte-for-byte pin
/// `theDemoFrameMatchesTheValuesRecordedOnMacOS` and the fourteen images do now.
///
/// Mutation that must redden it, re-run by stage 8's lane 1: **M-EZa** (the
/// lowered frame layer's infinite maximum passed as `nil` — the greedy frame not
/// greedy: cause O's lowered side collapses). Four of the mutations earlier stages
/// named for the pre-stage-8 census were **re-run against this one by lane 1's
/// review round** (record §50 §9): stage 5's M1c (the presentation's W alias
/// deleted) and M1d (the placeholder's alias deleted) and stage 3's M2a (the
/// viewport a plain native leaf) each still redden this test, among others;
/// stage 3's M2d (`flexShrink: 0` on the declared scroll content) traps at
/// `theDemoFrameMatchesTheValuesRecordedOnMacOS` and truncates the run, as it
/// did at stage 3. Stage 2's M1a, M2a, M1d, M2k, M1m′ and M5c′ were not re-run;
/// each is recorded where it was taken (record §21).
@MainActor
@Test func theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn() throws {
    func entry(_ site: LoweringSite, _ field: String) -> UnlowerableField {
        UnlowerableField(site: site, field: field)
    }
    demoModel.animationDemoActive = false
    demoModel.showModal = false
    let report = LayoutDifferential.report(width: 920, height: 560) { demoContent() }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    // 3053 since stage 8 (`LR-EZ`): each converted element gained one identity
    // level per `.frame` layer (`LR-ES`'s R7) — 2035 + 1018, where 1018 = 500
    // list rows × 2 (the row's `.frame(height:)` and `.frame(width:)`, where the
    // old spelling wrote both on the element and its padding layer) + 18 (the
    // avatar 1, the bar 2, the header 1, the hairline 1, the sidebar's four rows
    // 4 and its own width 1, the counter's three squares 3, the stack's three
    // children 3, the scroller box 2).
    try #require(report.elements == 3053, "\(report.elements)")

    // Ids. Every `.frame` layer is an identity level (`LR-ES`'s R7): the frame
    // takes the element's slot and the element moves one level down.
    let outerLayer = child(rootID, 0), outerColumn = child(outerLayer, 0)
    let headerFrame = child(outerColumn, 0), headerPad = child(headerFrame, 0), headerRow = child(headerPad, 0)
    let avatar = child(headerRow, 0), avatarBox = child(avatar, 0), bar = child(headerRow, 1)
    let body = child(outerColumn, 2)
    let sidebarFrame = child(body, 0), sidebarPad = child(sidebarFrame, 0), sidebar = child(sidebarPad, 0)
    let mainLayer = child(body, 1), main = child(mainLayer, 0)
    let scrollerFrame = child(main, 4), scrollerGreedy = child(scrollerFrame, 0)
    let scrollerBox = child(scrollerGreedy, 0), scroll = child(scrollerBox, 0)

    // Text, from the shaping cache.
    let cache = ShapingCache()
    let f13 = cache.resolveFont(family: nil, size: 13), f22 = cache.resolveFont(family: nil, size: 22)
    func shapedHeight(_ s: String, _ font: ResolvedFont, _ width: Double?) -> Float {
        Float(cache.shaped(s, font: font, wrappingAt: width).totalHeight.rounded())
    }
    func loweredHeight(_ s: String, _ font: ResolvedFont, _ width: Double) -> Float {
        Float(proposalTextMeasurement(s, font: font, cache: cache,
                                      proposal: ProposedSize(width: width, height: nil)).size.height.rounded())
    }
    func natural(_ s: String, _ font: ResolvedFont) -> Double { cache.shaped(s, font: font, wrappingAt: nil).widestLine }

    // The main column wraps its texts at 648 (the sidebar is 196).
    let renders = loweredHeight("Text renders", f22, 648), paragraph = loweredHeight(demoParagraph, f13, 648)
    try #require(shapedHeight("Text renders", f22, 648) == renders && shapedHeight(demoParagraph, f13, 648) == paragraph)
    let scrollerY = 129 + 128 + 12 + 60 + 12 + renders + 12 + paragraph + 12
    // The root's 560 (cause R).
    let loweredBody: Float = 560 - 16 - 72 - 12 - 1 - 12 - 16
    let loweredMain = loweredBody - 32
    let library = loweredHeight("Library", f13, 168)
    let libraryWidth = Float(natural("Library", f13).rounded())
    try #require(shapedHeight("Library", f13, nil) == library)
    let sidebarHeight = library + 4 * 26 + 4 * 10

    // Stage 9 (`LR-FE` item 2): each row is the lowered literal the census always
    // carried; its legacy half (the table above) went with the legacy engine.
    typealias Row = (id: GlobalElementID, lowered: Bounds<Pixels>)
    var expected: [Row] = [
        // R and O
        (outerLayer, bounds(0, 0, 920, 560)),
        (outerColumn, bounds(16, 16, 888, 528)),
        (body, bounds(16, 113, 888, loweredBody)),
        (sidebarFrame, bounds(16, 113, 196, loweredBody)),
        (mainLayer, bounds(224, 113, 680, loweredBody)),
        (main, bounds(240, 129, 648, loweredMain)),
        // 53f
        (headerPad, bounds(16, 16, 888, 72)),
        (headerRow, bounds(32, 32, 856, 40)),
        (avatar, bounds(32, 32, 40, 40)),
        (avatarBox, bounds(52, 52, 0, 0)),
        (bar, bounds(84, 46, 804, 12)),
        (sidebarPad, bounds(16, 113, 196, sidebarHeight + 28)),
        (sidebar, bounds(30, 127, 168, sidebarHeight)),
        (child(sidebar, 0), bounds(30, 127, 168, library)),
    ]
    for row in 1...4 {
        let y = 127 + library + 10 + Float(row - 1) * 36
        expected.append((child(sidebar, row), bounds(30, y, 168, 26)))
    }
    // O (and R): the scroller.
    for id in [scrollerFrame, scrollerGreedy, scrollerBox, scroll] {
        expected.append((id, bounds(240, scrollerY, 420, 129 + loweredMain - scrollerY)))
    }
    try #require(expected.count == 22)
    // The predictions the derivations must reproduce (record §50, lane 1).
    #expect([renders, paragraph, scrollerY, library, libraryWidth] == [26, 64, 455, 16, 42])

    for row in expected {
        #expect(report.bounds[row.id] == row.lowered,
                "\(row.id): expected \(row.lowered), got \(String(describing: report.bounds[row.id]))")
    }

    // 3. Modal on.
    demoModel.showModal = true
    defer { demoModel.showModal = false }
    let modal = LayoutDifferential.report(width: 920, height: 560) { demoContent() }
    // Stage 5, lane 1 (`LR-CH`, `LR-CI`): the modal is a presentation root and
    // lowers, so the report that read `[stack.position, stack.inset]` is empty.
    #expect(modal.unlowerable.isEmpty, "\(modal.unlowerable)")
    try #require(modal.elements == 3060, "\(modal.elements)")
    let deferred = child(scroll, 0), stack = child(deferred, 0)
    let card = child(stack, 0), cardPad = child(card, 0), column = child(cardPad, 0)
    // The `Deferred` and its scrim `Stack` — 920×560 at the origin (stage 5, lane
    // 1; the agreement with the legacy engine that carried this until stage 9 is
    // a literal since).
    #expect(modal.bounds[deferred] == bounds(0, 0, 920, 560), "\(String(describing: modal.bounds[deferred]))")
    #expect(modal.bounds[stack] == bounds(0, 0, 920, 560), "\(String(describing: modal.bounds[stack]))")
    // **Cause C** (stage 5): the lowering measures the modal's paragraph at the
    // column's 320 (two lines).
    let modalParagraph = "Declared inside the list, painted over it, and clipped by the window "
        + "rather than by the scroller."
    let loweredColumn = loweredHeight("Modal", f22, 320) + 8 + loweredHeight(modalParagraph, f13, 320)
    let paragraphHeight = shapedHeight(modalParagraph, f13, 320)
    try #require(loweredHeight(modalParagraph, f13, 320) == paragraphHeight)
    #expect([loweredColumn, paragraphHeight] == [66, 32])
    let loweredCardY = (560 - (loweredColumn + 40)) / 2
    let modalRows: [Row] = [
        (card, bounds(280, loweredCardY, 360, loweredColumn + 40)),
        (cardPad, bounds(280, loweredCardY, 360, loweredColumn + 40)),
        (column, bounds(300, loweredCardY + 20, 320, loweredColumn)),
        (child(column, 0), bounds(300, loweredCardY + 20, 320, 26)),
        (child(column, 1), bounds(300, loweredCardY + 20 + 26 + 8, 320, paragraphHeight)),
    ]
    for row in modalRows + expected {
        #expect(modal.bounds[row.id] == row.lowered,
                "modal \(row.id): expected \(row.lowered), got \(String(describing: modal.bounds[row.id]))")
    }
}
