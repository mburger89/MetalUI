import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Plan task 7, stage 6b, lane 1 (`docs/superpowers/specs/2026-09-23-engine-stage-6b-design.md`
// §8 tests 1.1–1.6; ruling `LR-DH`): `hidden()` under the proposal authority.
//
// Under the proposal authority a `display: none` node lowers **as if shown** — it
// keeps its space (stage-1 probe H1: `VStack(spacing: 0) { a20; b20.hidden(); c20 }`
// is 20×60) — and its element node joins `Frame.hiddenNodes`; paint skips a node in
// `hiddenNodes` (stage-2 probe V1: a hidden view paints nothing), its hitboxes are
// registered under the `hitTestingDisabled` scope (V3: a hidden top passes the tap
// to the view under it) and accessibility suppression reads `display == .none ∨
// hiddenNodes`. Each gate is mirrored per inner `ModifiedElement` layer (`MC-B`) and
// in `AnyElement`'s group entry, which reads `hiddenNodes` **only**, so the legacy
// path was byte-identical (1.6, retired with the legacy path at stage 9; record
// §51, lane 1 row 16).
//
// **Production frames** (no diagnostics) for 1.2–1.5, as a `Window` builds them:
// before the lane each trapped on `…display.none has no proposal lowering`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

private func child(_ parent: GlobalElementID, _ index: Int) -> GlobalElementID {
    GlobalElementID.child(of: parent, at: index, name: nil)
}

private func isFilled(_ rect: MUIRect, with token: ColorToken, in theme: Theme) -> Bool {
    let want = theme[token]
    return rect.background.h == want.h && rect.background.s == want.s
        && rect.background.l == want.l && rect.background.a == want.a
}

/// A production frame (no diagnostics), `width`×`height`, light theme, collecting
/// accessibility, rendered once.
@MainActor
private func production<E: Element>(width: Float = 100, height: Float = 100,
                                    _ element: E) -> Frame {
    var element = element
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
                      stateTable: StateTable(), theme: .light, collectsAccessibility: true)
    frame.render(&element)
    return frame
}

@MainActor
private func point(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

// MARK: - 1.1 — space (H1)

/// **1.1** (`LR-DH` item 1 and 6). `Column(gap: 0) { a; b.hidden(); c }`, each 20×20,
/// in a `DifferentialRoot`: lowered, `c` sits at y = 40 — the hidden `b` keeps its 20
/// (stage-1 probe H1, re-run 2026-09-23: `VStack(spacing:0){a20; b20.hidden(); c20}`
/// is 20×60) — where the legacy engine placed `c` at y = 20 (CSS `display: none`
/// takes no box; asserted until stage 9 deleted that engine).
/// Hidden `b`'s own origin, (0, 20), is **not** probe-backed — H1's leaf for the
/// hidden view reads (0, 0) — and is asserted as MetalUI's "as if shown" choice.
///
/// Red before: the proposal side reports `box.display.none`.
/// Mutation **M1b**: `hidden()` lowered as a 0×0 leaf — `c` at 20 under both.
@Test @MainActor func aHiddenChildKeepsItsSpaceUnderTheProposalAuthority() throws {
    let report = LayoutDifferential.report(width: 100, height: 100) {
        Column(gap: px(0)) {
            Box().cssWidth(px(20)).cssHeight(px(20))
            Box().cssWidth(px(20)).cssHeight(px(20)).hidden()
            Box().cssWidth(px(20)).cssHeight(px(20))
        }
    }
    #expect(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let column = child(rootID, 0)
    let c = child(column, 2)
    let loweredC = try #require(report.bounds[c])
    #expect(loweredC.origin.y == px(40), "lowered: the hidden b keeps its 20 (H1), got \(loweredC)")
    let loweredColumn = try #require(report.bounds[column])
    #expect(loweredColumn.size.height == px(60), "lowered column 20×60 (H1), got \(loweredColumn)")
    let loweredB = try #require(report.bounds[child(column, 1)])
    // b's origin is a MetalUI choice, not a SwiftUI answer: "as if shown" places the
    // node where it would be shown. H1's leaf record for the hidden view reads
    // `(0, 0) 20x20`, so the probe backs the 20×60 and c at y = 40, not b at (0, 20).
    #expect(loweredB == Bounds(origin: point(0, 20), size: Size(width: px(20), height: px(20))),
            "lowered b is laid out where it would be shown (MetalUI's choice), got \(loweredB)")

    // "As if shown" needs the display `hidden()` overwrote: a `Stack` is laid out as
    // a stack (its site says so), not as the flex row `display: .none` would fall to.
    func stack(hidden: Bool) -> LayoutDifferential.Report {
        LayoutDifferential.report(width: 100, height: 100) {
            let s = Stack(alignment: .bottomTrailing) {
                Box().cssWidth(px(20)).cssHeight(px(10))
                Box().cssWidth(px(10)).cssHeight(px(30))
            }
            hidden ? s.hidden() : s
        }
    }
    let shownStack = stack(hidden: false), hiddenStack = stack(hidden: true)
    #expect(hiddenStack.unlowerable.isEmpty, "\(hiddenStack.unlowerable)")
    let ids = [column, child(column, 0), child(column, 1)]
    let shownRects = ids.map { shownStack.bounds[$0] }
    try #require(shownRects == [Bounds(origin: point(0, 0), size: Size(width: px(20), height: px(30))),
                                Bounds(origin: point(0, 20), size: Size(width: px(20), height: px(10))),
                                Bounds(origin: point(10, 0), size: Size(width: px(10), height: px(30)))],
                 "control: the shown stack, \(shownRects)")
    #expect(ids.map { hiddenStack.bounds[$0] } == shownRects,
            "a hidden Stack is laid out as the shown stack, got \(ids.map { hiddenStack.bounds[$0] })")
}

// MARK: - 1.2 — paint (V0/V1)

/// **1.2** (`LR-DH` item 2). A hidden `Box` with an `.accent` background and a `Text`
/// inside it paints nothing under the proposal authority — no rect of its colour and
/// no glyph — while the shown control paints both (stage-2 probes V0 and V1).
///
/// Red before: the production frame traps on `box.display.none`.
/// Mutation **M1c**: the paint skip removed from `Element.paintGroup`.
@Test @MainActor func aHiddenElementPaintsNothingUnderTheProposalAuthority() throws {
    func tree(hidden: Bool) -> some Element {
        let box = Box { Text("Hi") }.cssWidth(px(40)).cssHeight(px(40)).background(.accent)
        return Column {
            hidden ? box.hidden() : box
            Box().cssWidth(px(10)).cssHeight(px(10))
        }
    }
    let theme = Theme.light
    let shown = production(tree(hidden: false))
    try #require(shown.scene.rects.contains { isFilled($0, with: .accent, in: theme) },
                 "control: the shown box paints its accent rect")
    try #require(!shown.scene.glyphs.isEmpty, "control: the shown text paints its glyphs")

    let hidden = production(tree(hidden: true))
    #expect(!hidden.scene.rects.contains { isFilled($0, with: .accent, in: theme) },
            "a hidden element paints no rect of its colour (V1)")
    #expect(hidden.scene.glyphs.isEmpty, "nothing inside a hidden element paints, got \(hidden.scene.glyphs.count) glyphs")

    // The root arm (`LR-DP` item 2): `render` paints the root directly, not through
    // `paintGroup`, so it carries its own skip. A hidden root paints nothing.
    let root = Box { Text("Hi") }.cssWidth(px(40)).cssHeight(px(40)).background(.accent)
    let shownRoot = production(root)
    try #require(!shownRoot.scene.rects.isEmpty && !shownRoot.scene.glyphs.isEmpty, "control: the shown root paints")
    let hiddenRoot = production(root.hidden())
    #expect(hiddenRoot.scene.rects.isEmpty && hiddenRoot.scene.glyphs.isEmpty,
            "a hidden root paints nothing, got \(hiddenRoot.scene.rects.count) rects, \(hiddenRoot.scene.glyphs.count) glyphs")
}

// MARK: - 1.3 — hit testing (V2/V3)

/// **1.3** (`LR-DH` item 2). `Stack { under.onClick; top.onClick.hidden() }`, both
/// 40×40 and centred: a click at the centre reaches `under` (stage-2 probe V3); the
/// control, `top` unhidden, reaches `top` (V2).
///
/// Red before: the production frame traps on `box.display.none`.
/// Mutation **M1d**: the `hitTestingDisabled` scope removed from `Element.prepaintGroup`.
@Test @MainActor func aHiddenClickTargetPassesTheClickToWhatIsUnderIt() throws {
    func tree(hidden: Bool) -> some Element {
        let top = Box().cssWidth(px(40)).cssHeight(px(40)).onClick {}
        return Stack {
            Box().cssWidth(px(40)).cssHeight(px(40)).onClick {}
            hidden ? top.hidden() : top
        }.cssWidth(px(100)).cssHeight(px(100))
    }
    let under = child(rootID, 0), top = child(rootID, 1)
    let shown = production(tree(hidden: false))
    let shownHit = try #require(topmostOpaqueHitbox(in: shown.hitboxes, at: point(50, 50)))
    try #require(shown.hitboxes[shownHit].id == top, "control: the unhidden top takes the click (V2)")

    let hidden = production(tree(hidden: true))
    let hit = try #require(topmostOpaqueHitbox(in: hidden.hitboxes, at: point(50, 50)))
    #expect(hidden.hitboxes[hit].id == under, "a hidden top passes the click to what is under it (V3)")
    #expect(!hidden.hitboxes.contains { $0.id == top }, "a hidden element registers no pointer hitbox")

    // The root arm (`LR-DP` item 2): `render` prepaints the root directly, so it
    // carries its own pointer-disable scope. A hidden clickable root holding a
    // clickable child registers no pointer hitbox at all.
    let root = Box { Box().cssWidth(px(20)).cssHeight(px(20)).onClick {} }.cssWidth(px(40)).cssHeight(px(40)).onClick {}
    try #require(production(root).hitboxes.count == 2, "control: the shown root and its child register")
    let hiddenRoot = production(root.hidden())
    #expect(hiddenRoot.hitboxes.isEmpty, "a hidden root registers no pointer hitbox, got \(hiddenRoot.hitboxes.count)")
}

// MARK: - 1.4 — per ModifiedElement layer (MC-B)

/// **1.4** (`LR-DH` item 4). One `ModifiedElement` with two `.padding` layers: the
/// INNER layer decorated, clickable and hidden, the OUTER layer decorated and
/// clickable (`MC-C`'s order: the outer layer takes the element's slot, the inner is
/// `positional(0)` under it, the content numbers from 0 under the inner). Under the
/// proposal authority the outer layer paints and takes the click; the hidden layer
/// and everything inside it paint nothing and take none. The control, the inner
/// layer unhidden, paints all three fills and gives the click to the content.
///
/// Red before: the production frame traps on `modifierLayer.display.none`.
/// Mutation **M1e**: `ModifiedElement`'s per-layer paint skip and hitbox scope removed.
@Test @MainActor func aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer() throws {
    func tree(hidden: Bool) -> some Element {
        let content = Box().cssWidth(px(10)).cssHeight(px(10)).background(.accent).onClick {}
        let inner = content.padding(px(4)).background(.surfaceSecondary).onClick {}
        return Row {
            (hidden ? inner.hidden() : inner).padding(px(4)).background(.separator).onClick {}
        }.cssWidth(px(100)).cssHeight(px(100))
    }
    let theme = Theme.light
    try #require(Set([theme[.accent], theme[.surfaceSecondary], theme[.separator]].map { "\($0)" }).count == 3,
                 "the three fills must be told apart")
    // The chain is 26×26 at the row's leading edge, centred vertically: (0, 37);
    // the content 10×10 at (8, 45). (13, 50) is inside all three.
    let outer = child(rootID, 0)
    let innerLayer = child(outer, 0)
    let content = child(innerLayer, 0)

    let shown = production(tree(hidden: false))
    for token in [ColorToken.accent, .surfaceSecondary, .separator] {
        try #require(shown.scene.rects.contains { isFilled($0, with: token, in: theme) },
                     "control: \(token) is painted")
    }
    let shownHit = try #require(topmostOpaqueHitbox(in: shown.hitboxes, at: point(13, 50)))
    try #require(shown.hitboxes[shownHit].id == content, "control: the content takes the click")

    let hidden = production(tree(hidden: true))
    #expect(hidden.scene.rects.contains { isFilled($0, with: .separator, in: theme) },
            "the outer layer still paints")
    #expect(!hidden.scene.rects.contains { isFilled($0, with: .surfaceSecondary, in: theme) },
            "the hidden inner layer paints nothing")
    #expect(!hidden.scene.rects.contains { isFilled($0, with: .accent, in: theme) },
            "nothing inside the hidden layer paints")
    let hit = try #require(topmostOpaqueHitbox(in: hidden.hitboxes, at: point(13, 50)))
    #expect(hidden.hitboxes[hit].id == outer, "the outer layer takes the click")
    #expect(!hidden.hitboxes.contains { $0.id == innerLayer || $0.id == content },
            "the hidden layer and its content register no pointer hitbox")
}

// MARK: - 1.5 — through AnyElement

/// **1.5** (`LR-DH` item 4). A hidden, clickable, decorated, accessibility-declaring
/// `Box` erased through `AnyElement`, over a clickable `Box` in a `Stack`: under the
/// proposal authority it paints nothing, passes the click to what is under it and
/// publishes no record. `AnyElement`'s group entry is a copy of `Element`'s default,
/// not a caller of it, so each gate needs its own mirror. The control is the same
/// tree unhidden.
///
/// Red before: the production frame traps on `box.display.none`.
/// Mutation **M1f**: `AnyElement`'s entry gates removed.
@Test @MainActor func aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority() throws {
    func tree(hidden: Bool) -> some Element {
        let top = Box().cssWidth(px(40)).cssHeight(px(40)).background(.accent).onClick {}
            .handling { $0.axNode = AXNode(label: "top") }
        return Stack {
            Box().cssWidth(px(40)).cssHeight(px(40)).onClick {}
            AnyElement(hidden ? top.hidden() : top)
        }.cssWidth(px(100)).cssHeight(px(100))
    }
    let theme = Theme.light
    let under = child(rootID, 0), top = child(rootID, 1)

    let shown = production(tree(hidden: false))
    try #require(shown.scene.rects.contains { isFilled($0, with: .accent, in: theme) }, "control: paints")
    let shownHit = try #require(topmostOpaqueHitbox(in: shown.hitboxes, at: point(50, 50)))
    try #require(shown.hitboxes[shownHit].id == top, "control: the erased top takes the click")
    try #require(shown.axEmissions.contains { $0.id == top }, "control: the erased top records")

    let hidden = production(tree(hidden: true))
    #expect(!hidden.scene.rects.contains { isFilled($0, with: .accent, in: theme) }, "paint skipped")
    let hit = try #require(topmostOpaqueHitbox(in: hidden.hitboxes, at: point(50, 50)))
    #expect(hidden.hitboxes[hit].id == under, "the click passes to what is under it")
    #expect(!hidden.axEmissions.contains { $0.id == top }, "a hidden erased element records nothing")
    #expect(hidden.axNodes.values.contains { $0.label == "top" },
            "control: the hidden element still prepaints and emits its declared node")
}

// MARK: - 1.9 — a hidden Text (the leaf site)

/// **1.9** (`LR-DH` item 2, `LR-DP`). A `Text` hidden directly — `lowerLegacyLeaf`'s
/// hidden branch, not `lowerLegacyNode` or the frame-layer branch that 1.2–1.5 reach —
/// paints no glyph, registers no pointer hitbox, publishes no accessibility record and
/// its node is in `hiddenNodes`, under the proposal authority in a production frame.
/// The control, the same `Text` shown, paints, registers and records, and leaves
/// `hiddenNodes` empty. A hidden `Text` is the case `Box.hidden()`'s doc calls wrong
/// under the legacy authority.
///
/// Mutation **VH**: `frame.hiddenNodes.insert(node)` dropped from `lowerLegacyLeaf`'s
/// hidden branch — the leaf lays out as shown but none of the gates see it.
@Test @MainActor func aHiddenTextIsHiddenUnderTheProposalAuthority() throws {
    func tree(hidden: Bool) -> some Element {
        let text = Text("Hi").onClick {}
        return Column {
            hidden ? text.hidden() : text
            Box().cssWidth(px(10)).cssHeight(px(10))
        }
    }
    let textID = child(rootID, 0)
    let shown = production(tree(hidden: false))
    try #require(!shown.scene.glyphs.isEmpty, "control: the shown text paints its glyphs")
    try #require(shown.hitboxes.contains { $0.id == textID }, "control: the shown text registers a hitbox")
    try #require(shown.axEmissions.contains { $0.id == textID }, "control: the shown text records")
    try #require(shown.hiddenNodes.isEmpty, "control: nothing is hidden")

    let hidden = production(tree(hidden: true))
    #expect(hidden.hiddenNodes.count == 1, "the hidden text's node joins hiddenNodes, got \(hidden.hiddenNodes.count)")
    #expect(hidden.scene.glyphs.isEmpty, "a hidden text paints no glyph, got \(hidden.scene.glyphs.count)")
    #expect(!hidden.hitboxes.contains { $0.id == textID }, "a hidden text registers no pointer hitbox")
    #expect(!hidden.axEmissions.contains { $0.id == textID }, "a hidden text publishes no record")
}
