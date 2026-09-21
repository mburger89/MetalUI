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

// MARK: - 5.3 — the whole demo's census

/// **5.3 — stage 2's entry.** `demoContent()`, **imported from `MetalUIDemoContent`**
/// (ruling LR-S), one frame at 920×560 inside the harness root under diagnostics
/// (modal and animation off): the multiset of `(site, field)` it reports, as a
/// literal measured by this lane on lane 4's tree, each entry annotated with the
/// element that reports it and its owning stage (spec §4.1).
///
/// Registration is post-order, so a container reports after its children, and a
/// reported element returns one 0×0 leaf (its own subtree is still registered).
/// Measured order:
///
/// | # | entry | element | stage |
/// |---|---|---|---|
/// | 1 | `box.flexGrow` | the header's bar, `.flexGrow(1)` | 2 |
/// | 2 | `box.flexGrow` | the header `Row`, `.flexGrow(1)` | 2 |
/// | 3 | `modifierLayer.alignItems.stretch` | the header's padding layer, `.height(72)` | 2 |
/// | 4, 5 | `box.alignItems.stretch`, `box.flexGrow` | the sidebar `Column` | 2 |
/// | 6 | `stack.alignSelf` | the stack cluster, `.alignSelf(.flexStart)` | 2 |
/// | 7 | `box.alignSelf` | `CounterPanel`'s chrome | 2 |
/// | 8 | `list.noLowering` | the `List`, checked before it builds its `Box` | 4 |
/// | 9 | `box.flexShrink` | the `List`'s zero-row `Box` (diagnostics only) | 2 (4 replaces it) |
/// | 10 | `scrollView.noLowering` | the `ScrollView` | 3 |
/// | 11–13 | `box.minSize`, `box.flexGrow`, `box.flexBasis` | the `Box` around the scroller | 2 |
/// | 14, 15 | `box.alignItems.stretch`, `box.flexGrow` | the main pane's `Column` | 2 |
/// | 16 | `modifierLayer.flexGrow` | the main pane's padding layer | 2 |
/// | 17, 18 | `box.alignItems.stretch`, `box.flexGrow` | the body `Row` | 2 |
/// | 19, 20 | `box.alignItems.stretch`, `box.flexGrow` | the outer `Column` | 2 |
///
/// **Not the design's census** (spec §2.7 item 2, scratch P2's 8 084 stretches):
/// P2 built the `List`'s 500 rows, and lane 1's `List` check reports before any row
/// exists. The modal is off, so `Deferred`, `position` and `inset` do not appear
/// (stage 5). Nothing but sites 8 and 10 is site-level: every other entry names a
/// field stage 2 owns — which is what stage 2's exit test rewrites this literal to.
///
/// Mutation that must redden it: **M5c**, two-child stretch made lowerable (the
/// `alignItems.stretch` count moves).
@MainActor
@Test func theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn() throws {
    demoModel.showModal = false
    demoModel.animationDemoActive = false
    let report = LayoutDifferential.compare(width: 920, height: 560) { demoContent() }
    try #require(report.unlowerable.count == 20, "\(report.unlowerable)")

    func entry(_ site: LoweringSite, _ field: String) -> UnlowerableField {
        UnlowerableField(site: site, field: field)
    }
    let expected: [UnlowerableField: Int] = [
        entry(.box, "flexGrow"): 7,                       // stage 2
        entry(.box, "alignItems.stretch"): 4,             // stage 2
        entry(.modifierLayer, "alignItems.stretch"): 1,   // stage 2
        entry(.modifierLayer, "flexGrow"): 1,             // stage 2
        entry(.stack, "alignSelf"): 1,                    // stage 2
        entry(.box, "alignSelf"): 1,                      // stage 2
        entry(.box, "flexShrink"): 1,                     // stage 2 (the List's zero-row Box; stage 4 replaces it)
        entry(.box, "minSize"): 1,                        // stage 2
        entry(.box, "flexBasis"): 1,                      // stage 2
        entry(.list, "noLowering"): 1,                    // stage 4
        entry(.scrollView, "noLowering"): 1,              // stage 3
    ]
    let measured = report.unlowerable.reduce(into: [UnlowerableField: Int]()) { $0[$1, default: 0] += 1 }
    #expect(measured == expected)
    // The List reports before its zero-row Box does, and before the ScrollView.
    let list = try #require(report.unlowerable.firstIndex(of: entry(.list, "noLowering")))
    let scroll = try #require(report.unlowerable.firstIndex(of: entry(.scrollView, "noLowering")))
    #expect(list < scroll && report.unlowerable[list + 1] == entry(.box, "flexShrink"))
}
