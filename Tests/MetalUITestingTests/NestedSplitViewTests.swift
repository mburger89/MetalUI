import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Nested `HSplitView` / `VSplitView` to arbitrary depth inside one clipped island (Alloy's editor-group tree), through the
// public harness. Leaves are `Color`s with a distinct alpha (0.11, 0.12, ...) so a leaf's presented rect is found by its
// alpha. A nested split view must be wrapped in a flexible `.frame(maxWidth: .infinity, maxHeight: .infinity)` to take
// its share of the parent's axis: bare, it answers min 0 and ideal = max = the sum of its panes' ideals (see
// `aBareNestedSplitViewStretchesLikeSwiftUIs`).

private typealias Frame = (x: Float, y: Float, w: Float, h: Float)

/// The leaf rects by tag (alpha 0.11 -> 11, ...), in window points.
@MainActor private func leaves(_ w: TestWindow) -> [Int: Frame] {
    var out: [Int: Frame] = [:]
    for r in w.scene.rects where r.background.a > 0.1 && r.background.a < 0.3 {
        let tag = Int((r.background.a * 100).rounded())
        out[tag] = (r.bounds.origin.x, r.bounds.origin.y, r.bounds.size.width, r.bounds.size.height)
    }
    return out
}

private func overlap(_ a: Frame, _ b: Frame) -> Float {
    let dx = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
    let dy = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
    return dx > 0 && dy > 0 ? dx * dy : 0
}

private func same(_ a: Frame, _ b: Frame) -> Bool { a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h }

private let minPane: Float = 30

@MainActor private func leaf(_ tag: Int) -> some ElementGroup {
    Color.red.opacity(Double(tag) / 100)
        .frame(minWidth: Pixels(minPane), maxWidth: .infinity, minHeight: Pixels(minPane), maxHeight: .infinity)
}

private extension ElementGroup {
    /// A nested split view's pane: flexible on both axes, the shape every nested split needs.
    @MainActor func flexible() -> some ElementGroup {
        frame(minWidth: Pixels(minPane), maxWidth: .infinity, minHeight: Pixels(minPane), maxHeight: .infinity)
    }
    @MainActor func island() -> some ElementGroup {
        VStack(spacing: 0) { self }.background { Color.blue }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Depth 5, alternating: H0 { V1 { A(11); H2 { B(12); V3 { C(13); H4 { D(14); E(15) } } } }; V5 { F(16); G(17) } }.
/// Window-level dividers: H0 between V1 and V5; V1 between A and H2; H2 between B and V3; V3 between C and H4; H4 between D and E.
@inline(never) @MainActor private func editorTree(names: Bool = false, store: (any SplitViewAutosaveStore)? = nil) -> some ElementGroup {
    return HSplitView {
        VSplitView {
            leaf(11)
            HSplitView {
                leaf(12)
                VSplitView {
                    leaf(13)
                    HSplitView {
                        leaf(14)
                        leaf(15)
                    }
                    .flexible()
                }
                .flexible()
            }
            .flexible()
        }
        .flexible()
        VSplitView {
            leaf(16)
            leaf(17)
        }
        .flexible()
    }
    .island()
}

@MainActor private func editorWindow() throws -> TestWindow {
    try harnessWindow(size: sz(640, 480)) { VStack(spacing: 0) { editorTree() } }
}

private let allLeaves = Array(11...17)

/// 1 -- depth 5 inside a clipped island: every leaf is placed with room for its minimum, the leaves tile the island
/// (no overlap, nothing outside it, only the 1-point dividers uncovered) and the first frame draws.
/// Mutation: `SplitLayout.placeSubviews` places every pane at the split's origin (overlap); the pane limits probe
/// ignores nested minimums (leaf below `minPane`).
@Test @MainActor func aDepthFiveNestOfSplitViewsInAClippedIslandLaysOutAndTiles() throws {
    let w = try editorWindow()
    #expect(w.framesDrawn >= 1)
    let f = leaves(w)
    #expect(f.keys.sorted() == allLeaves, "\(f.keys.sorted())")
    for t in allLeaves {
        let r = try #require(f[t])
        #expect(r.w >= minPane && r.h >= minPane, "leaf \(t) \(r)")
        #expect(r.x >= 0 && r.y >= 0 && r.x + r.w <= 640 && r.y + r.h <= 480, "leaf \(t) outside the island \(r)")
    }
    for a in allLeaves { for b in allLeaves where a < b {
        #expect(overlap(f[a]!, f[b]!) == 0, "leaves \(a) and \(b) overlap: \(f[a]!) \(f[b]!)")
    } }
    let covered = allLeaves.reduce(Float(0)) { $0 + f[$1]!.w * f[$1]!.h }
    let island: Float = 640 * 480
    #expect(covered <= island && covered > island * 0.97, "leaves cover \(covered) of \(island)")
    // The island itself is the clipped background, and the frames after the first stay the same.
    let before = leaves(w)
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    for t in allLeaves { #expect(same(before[t]!, leaves(w)[t]!), "leaf \(t) moved on a redraw") }
}

private func dividerPoint(between a: Frame, and b: Frame, vertical: Bool) -> Point<Pixels> {
    vertical ? pt(a.x + a.w + 0.5, a.y + a.h / 2) : pt(a.x + a.w / 2, a.y + a.h + 0.5)
}

/// 2a -- the innermost divider (D | E) resizes D and E only: every other leaf's frame is bit-identical, D and E
/// trade width and keep their height. Mutation: `dragged` is applied to the outermost split's snapshot.
@Test @MainActor func draggingTheInnermostDividerResizesOnlyItsTwoPanes() throws {
    let w = try editorWindow()
    let before = leaves(w)
    w.drag(from: dividerPoint(between: before[14]!, and: before[15]!, vertical: true), to: pt(before[14]!.x + before[14]!.w + 20.5, before[14]!.y + 10))
    let after = leaves(w)
    #expect(after[14]!.w == before[14]!.w + 20 && after[15]!.w == before[15]!.w - 20, "\(before[14]!) -> \(after[14]!), \(before[15]!) -> \(after[15]!)")
    #expect(after[14]!.h == before[14]!.h && after[15]!.h == before[15]!.h)
    for t in allLeaves where t != 14 && t != 15 { #expect(same(before[t]!, after[t]!), "leaf \(t) moved: \(before[t]!) -> \(after[t]!)") }
}

/// 2b -- every inner divider, one by one, moves only the panes of its own split: the two neighbours' main-axis sizes
/// change, and no leaf outside that split's region moves. Mutation: a divider's drag writes its parent's `SplitModel`.
@Test @MainActor func everyInnerDividerResizesOnlyItsOwnSplit() throws {
    // (left pane tag, right/below pane tag, vertical divider?, tags allowed to change)
    let cases: [(Int, Int, Bool, Set<Int>)] = [
        (11, 12, false, [11, 12, 13, 14, 15]),   // V1: A above H2 {B, V3 {C, H4 {D, E}}}
        (12, 13, true, [12, 13, 14, 15]),        // H2: B beside V3
        (13, 14, false, [13, 14, 15]),           // V3: C above H4
        (14, 15, true, [14, 15]),                // H4: D beside E
    ]
    for (a, b, vertical, moving) in cases {
        let w = try editorWindow()
        let before = leaves(w)
        let from = dividerPoint(between: before[a]!, and: before[b]!, vertical: vertical)
        let to = vertical ? pt(Float(from.x.value) + 12, Float(from.y.value)) : pt(Float(from.x.value), Float(from.y.value) + 12)
        w.drag(from: from, to: to)
        let after = leaves(w)
        let moved = Set(allLeaves.filter { !same(before[$0]!, after[$0]!) })
        #expect(!moved.isEmpty, "divider \(a)|\(b) did not move anything")
        #expect(moved.isSubset(of: moving), "divider \(a)|\(b) moved leaves outside its split: \(moved.subtracting(moving))")
        #expect(after[a]!.w >= minPane && after[a]!.h >= minPane && after[b]!.w >= minPane && after[b]!.h >= minPane)
    }
}

/// 2c -- the outermost divider (V1 | V5) gives the width to the other side: V1's leaves grow by the drag, V5's
/// shrink by it, no height changes anywhere, nothing falls below its minimum and the leaves still tile.
/// Assertion of the current rule: the inner splits' remembered sizes are re-solved for the new width (the
/// flexible pane, the last of each split, absorbs the change) rather than scaled proportionally.
@Test @MainActor func draggingTheOutermostDividerMovesWholeSubtrees() throws {
    let w = try editorWindow()
    let before = leaves(w)
    w.drag(from: dividerPoint(between: before[11]!, and: before[16]!, vertical: true), to: pt(before[11]!.x + before[11]!.w + 40.5, 240))
    let after = leaves(w)
    #expect(after[11]!.w == before[11]!.w + 40, "\(before[11]!) -> \(after[11]!)")
    #expect(after[16]!.w == before[16]!.w - 40 && after[17]!.w == before[17]!.w - 40)
    for t in allLeaves { #expect(after[t]!.h == before[t]!.h, "leaf \(t) changed height") }
    for t in allLeaves { #expect(after[t]!.w >= minPane && after[t]!.h >= minPane, "leaf \(t) \(after[t]!)") }
    for a in allLeaves { for b in allLeaves where a < b { #expect(overlap(after[a]!, after[b]!) == 0, "\(a) \(b)") } }
    // The deep leaves are in V1's region, to the left of the divider.
    for t in 11...15 { #expect(after[t]!.x + after[t]!.w <= after[16]!.x, "leaf \(t) crosses the outer divider") }
}

/// 2d -- dragging the outermost divider past every limit stops at the minima: no negative or zero size, the far
/// side stops at its minimum. Mutation: `dragged` drops the clamp.
@Test @MainActor func aDragOfTheOutermostDividerStopsAtTheMinima() throws {
    let w = try editorWindow()
    let before = leaves(w)
    let y: Float = 240
    w.drag(from: dividerPoint(between: before[11]!, and: before[16]!, vertical: true), to: pt(639, y))
    var after = leaves(w)
    #expect(after[16]!.w == minPane && after[17]!.w == minPane, "\(after[16]!)")
    for t in allLeaves { #expect(after[t]!.w >= minPane && after[t]!.h >= minPane, "leaf \(t) \(after[t]!)") }
    w.drag(from: pt(after[16]!.x - 0.5, y), to: pt(0, y))
    after = leaves(w)
    for t in allLeaves { #expect(after[t]!.w >= minPane && after[t]!.h >= minPane, "leaf \(t) \(after[t]!)") }
    #expect(after[11]!.w >= minPane)
}

/// 3 -- at the point where an inner divider (V1's A | H2, a row divider) meets the outer divider (V1 | V5), the
/// outer one wins: dividers register after their panes, so a split's own dividers rank above everything inside
/// its panes, including the inner split's divider. Deterministic: two fresh windows give the same result, and the
/// pointer shows the outer divider's column-resize. Mutation: the hit area collapsed to 0 reddens it; swapping the paint or prepaint
/// order of panes and dividers does not (hit order is not that order), so the priority itself is pinned by outcome only.
@Test @MainActor func atACrossingTheOuterDividerWinsDeterministically() throws {
    var results: [[Frame]] = []
    for _ in 0..<2 {
        let w = try editorWindow()
        let before = leaves(w)
        let crossing = pt(before[11]!.x + before[11]!.w + 0.5, before[11]!.y + before[11]!.h + 0.5)
        w.hover(at: crossing)
        #expect(w.pointerStyle == .columnResize, "\(String(describing: w.pointerStyle))")
        w.drag(from: crossing, to: pt(Float(crossing.x.value) + 25, Float(crossing.y.value) + 25))
        let after = leaves(w)
        #expect(after[11]!.w == before[11]!.w + 25, "the outer divider moved: \(before[11]!) -> \(after[11]!)")
        #expect(after[11]!.h == before[11]!.h, "the inner divider did not move")
        results.append(allLeaves.map { after[$0]! })
    }
    #expect(zip(results[0], results[1]).allSatisfy { same($0, $1) })
}

/// 4 -- autosave per nested split view: three named levels store under their own names, each with the sizes of its
/// own panes; a reopened window restores all three; sibling splits of the same shape without a name keep their own
/// state (dragging one leaves the other). Distinct names never collide; the same name on two levels is the
/// caller's collision (they would write one entry), so Alloy names each split.
@Test @MainActor func nestedSplitViewsAutosaveUnderTheirOwnNames() throws {
    let store = NestedMemoryStore()
    @inline(never) @MainActor func tree() -> some ElementGroup {
        HSplitView {
            VSplitView {
                leaf(11)
                HSplitView { leaf(12); leaf(13) }.splitViewAutosaveName("inner-h", store: store).flexible()
            }.splitViewAutosaveName("left-v", store: store).flexible()
            leaf(14).flexible()
        }.splitViewAutosaveName("outer-h", store: store).island()
    }
    let w = try harnessWindow(size: sz(640, 480)) { VStack(spacing: 0) { tree() } }
    let before = leaves(w)
    w.drag(from: dividerPoint(between: before[12]!, and: before[13]!, vertical: true), to: pt(before[12]!.x + before[12]!.w + 10.5, before[12]!.y + 5))
    w.drag(from: dividerPoint(between: before[11]!, and: before[12]!, vertical: false), to: pt(before[11]!.x + 5, before[11]!.y + before[11]!.h + 15.5))
    w.drag(from: dividerPoint(between: before[11]!, and: before[14]!, vertical: true), to: pt(before[11]!.x + before[11]!.w + 20.5, 400))
    #expect(Set(store.saved.keys) == ["inner-h", "left-v", "outer-h"], "\(store.saved.keys.sorted())")
    #expect(store.saved.values.allSatisfy { $0.count == 2 }, "\(store.saved)")
    #expect(store.writes == 3, "one write per drag, each to its own name: \(store.writes)")
    let moved = leaves(w)
    let reopened = try harnessWindow(size: sz(640, 480)) { VStack(spacing: 0) { tree() } }
    for t in 11...14 { #expect(same(leaves(reopened)[t]!, moved[t]!), "leaf \(t) not restored: \(leaves(reopened)[t]!) vs \(moved[t]!)") }
}

@MainActor private final class NestedMemoryStore: SplitViewAutosaveStore {
    var saved: [String: [Double]] = [:]
    var writes = 0
    func paneSizes(forName name: String) -> [Double]? { saved[name] }
    func setPaneSizes(_ sizes: [Double], forName name: String) { saved[name] = sizes; writes += 1 }
}

/// 4b -- two sibling splits of the same shape and no name hold separate state: V1 | V5 each have a row divider;
/// dragging V5's moves F and G and leaves V1 alone. Mutation: the model keyed by shape instead of identity.
@Test @MainActor func siblingNestedSplitViewsKeepSeparateState() throws {
    let w = try editorWindow()
    let before = leaves(w)
    w.drag(from: dividerPoint(between: before[16]!, and: before[17]!, vertical: false), to: pt(before[16]!.x + 5, before[16]!.y + before[16]!.h + 30.5))
    let after = leaves(w)
    #expect(after[16]!.h == before[16]!.h + 30 && after[17]!.h == before[17]!.h - 30)
    for t in 11...15 { #expect(same(before[t]!, after[t]!), "leaf \(t) moved with its sibling's divider") }
}

/// 5 -- Alloy's report: three sibling islands, each clipped, in one HSplitView in one body. Draws the first frame
/// and the redraws, three panes tile the window, and a divider drag resizes them.
@inline(never) @MainActor private func threeIslands() -> some ElementGroup {
    HSplitView {
        leaf(11).island().flexible()
        leaf(12).island().flexible()
        leaf(13).island().flexible()
    }
}

@Test @MainActor func threeSiblingClippedIslandsInOneSplitViewRender() throws {
    let w = try harnessWindow(size: sz(600, 300)) { VStack(spacing: 0) { threeIslands() } }
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
    #expect(w.framesDrawn >= 1)
    let f = leaves(w)
    #expect(f.keys.sorted() == [11, 12, 13], "\(f.keys.sorted())")
    #expect(f.values.allSatisfy { $0.w > 0 && $0.h == 300 })
    #expect(f.values.reduce(0) { $0 + $1.w } == 598, "two 1-point dividers: \(f)")
    w.drag(from: dividerPoint(between: f[11]!, and: f[12]!, vertical: true), to: pt(f[11]!.x + f[11]!.w + 20.5, 150))
    let after = leaves(w)
    #expect(after[11]!.w == f[11]!.w + 20 && after[12]!.w == f[12]!.w - 20 && after[13]!.w == f[13]!.w)
}

// MARK: - The finding: a bare nested split view is rigid

@inline(never) @MainActor private func bareNest() -> some ElementGroup {
    HSplitView {
        VSplitView { leafBare(11); leafBare(12) }
        leafBare(13)
    }
}
@MainActor private func leafBare(_ tag: Int) -> some ElementGroup { Color.red.opacity(Double(tag) / 100) }

/// A `VSplitView` that is a pane of an `HSplitView` should stretch like any flexible pane (SwiftUI's does); here it
/// stays at its ideal width (10, the `Color` ideal) while the plain pane takes the rest, because
/// `SplitLayout.sizeThatFits` answers a sum of ideals for a non-finite proposal on its main axis and the widest
/// child's ideal on its cross axis, so the pane's maximum equals its ideal. Pinned as a known issue; remove the
/// `withKnownIssue` when `SplitLayout` answers min/ideal/max from its panes.
@Test @MainActor func aBareNestedSplitViewStretchesLikeSwiftUIs() throws {
    let w = try harnessWindow(size: sz(600, 400)) { VStack(spacing: 0) { bareNest() } }
    let f = leaves(w)
    withKnownIssue("SplitLayout answers max == ideal for a nested split view (no flexible width/height)") {
        #expect(f[11]!.w > 100, "nested split pane width \(f[11]!.w) of 600")
    }
    // What does hold: it is still laid out, at its ideal size, without overlap.
    #expect(f[11]!.w == 10 && f[13]!.x > f[11]!.x + f[11]!.w)
}
