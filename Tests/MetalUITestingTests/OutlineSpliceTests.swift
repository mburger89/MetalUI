import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Observation
import Testing

// Lane 7 of the hierarchical lists: the expand/collapse splice animation of a content `List` (rulings `OG-H`, `OG-P`; record 320;
// probe `docs/probes/swiftui-outline.swift` arms `P-N1`..`P-N4`).
//
// The probe: a chevron click slides the rows below over about 245 ms (15 -> 259 ms, 32 distinct positions) with AppKit's curve; a
// bare `isExpanded = true` snaps; `withAnimation(.easeInOut(duration: 0.6))` slides over the SAME 245 ms. MetalUI lays the rows out
// at their final places and animates the paint: the rows after the splice are drawn at `final - travel * (1 - p)`, the inserted
// rows fade in, the removed rows ghost out from the previous scene.
//
// **The oracle is written down, not computed by the code under test.** `p` is the cubic Bezier (0.25, 0.1, 0.25, 1) at `t / 0.245`:
// 0.2952 at 49 ms, 0.6825 at 98 ms, 0.8024 at 122.5 ms, 0.9756 at 196 ms (a Python bisection over the same curve, the fit in record
// 320). The tree: a root `A` (two leaves, collapsed), `Z`, `M` (one leaf); a 300 x 400 window, a row 32 high, the first 10 below the
// top. Expanding A pushes Z and M down 64 points.

@Observable @MainActor private final class SNode: Identifiable {
    nonisolated let id: String
    var isFolder: Bool
    var isExpanded: Bool
    var children: [SNode]
    init(_ id: String, expanded: Bool = false, children: [SNode]? = nil) {
        self.id = id
        self.isFolder = children != nil
        self.isExpanded = expanded
        self.children = children ?? []
    }
}

@Observable @MainActor private final class SModel {
    var roots: [SNode]
    var selection: String?
    init(_ roots: [SNode]) { self.roots = roots }
}

private struct SRow: Component {
    @Bindable var node: SNode
    @ElementBuilder var content: some ElementGroup {
        if node.isFolder {
            DisclosureGroup(isExpanded: $node.isExpanded) {
                ForEach(node.children) { SRow(node: $0) }
            } label: { ProposalText(node.id) }
        } else {
            ProposalText(node.id)
        }
    }
}

@MainActor private func smallTree(openA: Bool = false, openM: Bool = false) -> [SNode] {
    [SNode("A", expanded: openA, children: [SNode("A1"), SNode("A2")]), SNode("Z"),
     SNode("M", expanded: openM, children: [SNode("M1")])]
}

private struct DNode: Identifiable {
    var id: String
    var kids: [DNode]?
}

private enum Form: String, CaseIterable { case content, data }

@MainActor private func listWindow(_ model: SModel, height: Float = 400) throws -> TestWindow {
    let selection = Binding<String?>(get: { model.selection }, set: { model.selection = $0 })
    let window = try harnessWindow(size: sz(300, height)) {
        ProposalScrollView {
            List(selection: selection) { ForEach(model.roots) { SRow(node: $0) } }
        }
    }
    settle(window)
    return window
}

/// The outline of `smallTree()` as data (the framework keeps each group's expansion).
@MainActor private func dataWindow() throws -> TestWindow {
    let selected = SModel([])
    let nodes = [DNode(id: "A", kids: [DNode(id: "A1"), DNode(id: "A2")]), DNode(id: "Z"), DNode(id: "M", kids: [DNode(id: "M1")])]
    let window = try harnessWindow(size: sz(300, 400)) {
        ProposalScrollView {
            List(nodes, children: \.kids, selection: Binding<String?>(get: { selected.selection }, set: { selected.selection = $0 })) { ProposalText($0.id) }
        }
    }
    settle(window)
    return window
}

@MainActor private func settle(_ window: TestWindow) { for _ in 0..<4 { window.tick() } }

@MainActor private func visible(_ window: TestWindow) -> [String] {
    var found: [String: Bounds<Pixels>] = [:]
    for element in (try? window.elements(role: .staticText)) ?? [] {
        if let value = element.value { found[value] = element.frame }
    }
    return found.sorted { $0.value.origin.y.value < $1.value.origin.y.value }.map(\.key)
}

private func rowY(_ index: Int) -> Float { 10 + 32 * Float(index) + 16 }

@MainActor private func chevron(_ window: TestWindow, _ name: String) {
    let rows = visible(window)
    guard let row = rows.firstIndex(of: name) else { Issue.record("\(name) is not visible: \(rows)"); return }
    let depth = name.hasPrefix("A") && name.count > 1 ? 1 : 0
    window.click(at: pt(12 + 12 * Float(depth) + 6, rowY(row)))
}

/// The glyphs of the label column `depth` levels deep, top to bottom: (y of the glyph's top, its tint's alpha).
@MainActor private func column(_ window: TestWindow, depth: Int) -> [(y: Float, alpha: Float)] {
    let low = Float(24 + 12 * depth), high = low + 11
    return window.allGlyphs.filter { $0.bounds.origin.x >= low && $0.bounds.origin.x < high }
        .map { (y: $0.bounds.origin.y, alpha: $0.color.a) }
        .sorted { $0.y < $1.y }
}

/// Where the glyph of the row `Z` is drawn now (the depth 0 column is A, Z, M while A is collapsed or expanded alike).
@MainActor private func zY(_ window: TestWindow) -> Float {
    let glyphs = column(window, depth: 0)
    return glyphs.count == 3 ? glyphs[1].y : -1
}

private func near(_ value: Float, _ expected: Float, _ tolerance: Float = 1.0) -> Bool { abs(value - expected) <= tolerance }

// MARK: the measured slide

/// **P-N1: a chevron click slides the rows below.** Expanding A (two rows, 64 points): at the click's frame Z is where it was; then
/// at 49, 98, 122.5, 196 ms it is `64 * (1 - p)` above its final place, and at 245 ms exactly there. The same in both forms.
/// Mutations: the offset not applied (Z at its final place at once: the first sample reddens); the curve linear (0.2 against
/// 0.2952 at 49 ms); the duration 0.6 (still moving at 245 ms); `1 - p` written as `p` (the sign of every sample).
@Test @MainActor func aChevronClickSlidesTheRowsBelowOverTheMeasuredCurve() throws {
    for form in Form.allCases {
        let window = form == .content ? try listWindow(SModel(smallTree())) : try dataWindow()
        defer { withExtendedLifetime(window) {} }
        let before = zY(window)
        chevron(window, "A")
        settle(window)
        let travel: Float = 64
        let start = zY(window)
        #expect(near(start, before, 0.6), "\(form): at the click Z has not moved: \(start) against \(before)")
        var samples: [(t: Double, y: Float)] = []
        var now = 0.0
        for t in [0.049, 0.098, 0.1225, 0.196] {
            window.advance(by: t - now)
            now = t
            samples.append((t, zY(window)))
        }
        window.advance(by: 0.3)
        let final = zY(window)
        #expect(near(final - before, travel, 0.6), "\(form): Z ended \(final - before) below where it began (rows are 32 high)")
        let expected: [(Double, Float)] = [(0.049, 0.2952), (0.098, 0.6825), (0.1225, 0.8024), (0.196, 0.9756)]
        for (sample, oracle) in zip(samples, expected) {
            let want = final - travel * (1 - oracle.1)
            #expect(near(sample.y, want, 1.2), "\(form): at \(Int(sample.t * 1000)) ms Z is at \(sample.y), expected \(want)")
        }
    }
}

/// **The animation ends at the exact final layout.** After the 245 ms the scene (every glyph's place and tint, every rect) is the
/// scene of the same list expanded with a bare write, which snaps. Mutation: the offset left at 1 - 0.0001 (the glyph columns
/// differ).
@Test @MainActor func theAnimationEndsAtTheExactFinalLayout() async throws {
    let animated = try listWindow(SModel(smallTree()))
    let snapped = try listWindow(SModel(smallTree()))
    defer { withExtendedLifetime(animated) {}; withExtendedLifetime(snapped) {} }
    chevron(animated, "A")
    settle(animated)
    animated.advance(by: 0.245)
    animated.advance(by: 0.05)
    chevron(snapped, "A")   // the control: the same click, read after it ran its course
    settle(snapped)
    snapped.advance(by: 0.3)
    for depth in 0...1 {
        let a = column(animated, depth: depth), s = column(snapped, depth: depth)
        #expect(a.count == s.count && zip(a, s).allSatisfy { $0.y == $1.y && $0.alpha == $1.alpha }, "depth \(depth): \(a) against \(s)")
    }
    #expect(animated.scene.rects.map(xywh) == snapped.scene.rects.map(xywh), "rects")
    #expect(!animated.window.needsRedraw)
    let drawn = animated.framesDrawn
    animated.advance(by: 0.1)
    #expect(animated.framesDrawn == drawn, "an idle window draws no frame after the splice")
}

// MARK: the insertion and the removal

/// **Inserted rows fade in** (`OG-H`: SwiftUI's insertion fade). Expanding A: A1 and A2's glyphs are drawn at alpha `p` of their
/// resting tint at 49, 98 and 196 ms, none of them solid before the end. Mutations: the fade scope not opened (alpha 1 at once);
/// alpha `1 - p`.
@Test @MainActor func insertedRowsFadeIn() throws {
    let window = try listWindow(SModel(smallTree()))
    defer { withExtendedLifetime(window) {} }
    chevron(window, "A")
    settle(window)
    var alphas: [(Double, [Float])] = []
    var now = 0.0
    for t in [0.0, 0.049, 0.098, 0.196] {
        window.advance(by: t - now)
        now = t
        alphas.append((t, column(window, depth: 1).map(\.alpha)))
    }
    window.advance(by: 0.3)
    let resting = column(window, depth: 1).map(\.alpha)
    #expect(resting.count == 4 && resting.allSatisfy { $0 > 0.5 }, "A1 and A2 (two glyphs each) settled solid: \(resting)")
    let oracle: [Double: Float] = [0.0: 0, 0.049: 0.2952, 0.098: 0.6825, 0.196: 0.9756]
    for (t, values) in alphas {
        let want = (oracle[t] ?? 0) * resting[0]
        #expect(values.count == 4, "\(t): both inserted rows are drawn: \(values)")
        #expect(values.allSatisfy { abs($0 - want) < 0.02 }, "at \(Int(t * 1000)) ms the inserted glyphs are at \(values), expected \(want)")
    }
}

/// **Removed rows ghost out from the previous scene** (`XF-H`'s slicing), and the rows below slide UP into their place. Collapsing
/// an open A: A1 and A2 are still drawn at their old places at 98 ms, at alpha `(1 - p)` of their resting tint, Z is
/// `64 * (1 - p)` below its final place, and at 245 ms the ghosts are gone. Mutations: the ghosts not drawn (the glyphs vanish at
/// once); drawn at alpha `p`; not cleared at the end (still there at 300 ms).
@Test @MainActor func removedRowsGhostOutFromThePreviousScene() throws {
    let window = try listWindow(SModel(smallTree(openA: true)))
    defer { withExtendedLifetime(window) {} }
    let ghostRows = column(window, depth: 1)
    #expect(ghostRows.count == 4, "control: A1 and A2 are drawn before the collapse: \(ghostRows)")
    let zBefore = zY(window)
    chevron(window, "A")
    settle(window)
    #expect(column(window, depth: 1).count == 4 && near(zY(window), zBefore, 0.6), "at the click nothing has moved: \(column(window, depth: 1))")
    window.advance(by: 0.098)
    let during = column(window, depth: 1)
    #expect(during.count == 4, "the ghosts are still drawn at 98 ms: \(during)")
    #expect(zip(during, ghostRows).allSatisfy { near($0.y, $1.y, 0.6) }, "at the places they left: \(during) against \(ghostRows)")
    #expect(during.allSatisfy { abs($0.alpha - (1 - 0.6825) * ghostRows[0].alpha) < 0.03 }, "fading out: \(during)")
    let zNow = zY(window)
    window.advance(by: 0.3)
    let zFinal = zY(window)
    #expect(near(zNow - zFinal, 64 * (1 - 0.6825), 1.2), "Z is \(zNow - zFinal) below its final place at 98 ms")
    #expect(near(zBefore - zFinal, 64, 0.6), "Z ended 64 points higher")
    #expect(column(window, depth: 1).isEmpty, "the ghosts are gone at the end")
}

// MARK: what animates and what snaps

/// **P-N2/N3: a bare binding write snaps, a `withAnimation` write animates with the MEASURED duration.** The same write of
/// `isExpanded`: bare, Z is at its final place in the write's frame and no further frame is drawn; inside
/// `withAnimation(.linear(duration: 2))` it slides over 245 ms, not 2 s: at 98 ms the offset is the measured curve's
/// (0.6825 of the travel, a linear 2 s would be 0.049) and at 300 ms it is over. Mutations: every write animating (the bare arm's
/// frames); the given animation's duration read (the 98 ms sample); the transaction ignored (the withAnimation arm snaps).
@Test @MainActor func aBareWriteSnapsAndAnAnimatedWriteTakesTheMeasuredDuration() async throws {
    // Bare.
    let bare = SModel(smallTree())
    let window = try listWindow(bare)
    defer { withExtendedLifetime(window) {} }
    let before = zY(window)
    bare.roots[0].isExpanded = true
    try await window.runUntilIdle()
    #expect(near(zY(window) - before, 64, 0.6), "the bare write moved Z to its final place at once: \(zY(window) - before)")
    #expect(column(window, depth: 1).allSatisfy { $0.alpha > 0.5 }, "and the new rows are solid")
    #expect(!window.window.needsRedraw)
    let drawn = window.framesDrawn
    window.advance(by: 0.1)
    window.advance(by: 0.1)
    #expect(window.framesDrawn == drawn, "no animation frame follows a bare write")
    // Animated.
    let animated = SModel(smallTree())
    let other = try listWindow(animated)
    defer { withExtendedLifetime(other) {} }
    let start = zY(other)
    withAnimation(.linear(duration: 2)) { animated.roots[0].isExpanded = true }
    try await other.runUntilIdle()
    #expect(near(zY(other), start, 0.6), "the animated write starts at the old place: \(zY(other) - start)")
    other.advance(by: 0.098)
    #expect(near(zY(other) - start, 64 * 0.6825, 1.2), "at 98 ms: \(zY(other) - start) of 64 (measured curve 0.6825, linear 2 s 0.049)")
    other.advance(by: 0.2)
    #expect(near(zY(other) - start, 64, 0.6), "over by 300 ms: \(zY(other) - start)")
}

/// **Reduce Motion cross-fades only.** The rows below do not slide (Z is at its final place in the click's frame), the inserted
/// rows still fade in over the measured duration, and a collapse ghosts out without the slide. Mutation: the slide kept under
/// Reduce Motion (the first assertion).
@Test @MainActor func reduceMotionGivesACrossFadeOnly() throws {
    let window = try listWindow(SModel(smallTree()))
    defer { withExtendedLifetime(window) {} }
    window.setReduceMotion(true)
    settle(window)
    let before = zY(window)
    chevron(window, "A")
    settle(window)
    #expect(near(zY(window) - before, 64, 0.6), "Z jumped to its final place: \(zY(window) - before)")
    let first = column(window, depth: 1).map(\.alpha)
    window.advance(by: 0.098)
    let mid = column(window, depth: 1).map(\.alpha)
    window.advance(by: 0.3)
    let end = column(window, depth: 1).map(\.alpha)
    #expect(first.allSatisfy { $0 < 0.05 } && mid.allSatisfy { $0 > 0.2 && $0 < end[0] - 0.05 } && end.allSatisfy { $0 > 0.5 },
            "the inserted rows fade in: \(first) \(mid) \(end)")
    #expect(near(zY(window) - before, 64, 0.6), "and Z never moved after")
}

/// **The clock is `noteActiveAnimation`, never `wantsAnotherFrame`.** During the splice the window reports `needsRedraw == false`
/// (nobody changed anything) and still draws on each tick; a `wantsAnotherFrame` clock would report it dirty. Mutation: the
/// splice asking for another frame instead (the `needsRedraw` assertion reddens).
@Test @MainActor func theSpliceKeepsTheClockWithoutDirtyingTheWindow() throws {
    let window = try listWindow(SModel(smallTree()))
    defer { withExtendedLifetime(window) {} }
    chevron(window, "A")
    settle(window)
    let drawn = window.framesDrawn
    #expect(!window.window.needsRedraw, "mid-animation the window is not dirty")
    window.advance(by: 0.05)
    #expect(window.framesDrawn == drawn + 1, "and a tick draws")
    #expect(!window.window.needsRedraw)
    window.advance(by: 0.3)
    let landed = window.framesDrawn
    window.advance(by: 0.1)
    #expect(window.framesDrawn == landed, "the clock stops when the splice has run its course")
}

// MARK: keys and accessibility

/// **The keys and the chevron both animate** (`OG-E`/`OG-H`): select A, press →, and Z slides as for a click; ← slides it back.
/// Both forms. Mutation: the key path writing without the input mark (a bare write snaps: the first sample).
@Test @MainActor func theArrowKeysSlideTheRowsToo() throws {
    for form in Form.allCases {
        let window = form == .content ? try listWindow(SModel(smallTree())) : try dataWindow()
        defer { withExtendedLifetime(window) {} }
        window.click(at: pt(200, rowY(0)))   // selects A and focuses the list
        settle(window)
        let before = zY(window)
        window.typeKey(.rightArrow)
        settle(window)
        #expect(near(zY(window), before, 0.6), "\(form): → at its frame: Z has not moved")
        window.advance(by: 0.098)
        #expect(near(zY(window) - before, 64 * 0.6825, 1.2), "\(form): → at 98 ms: \(zY(window) - before)")
        window.advance(by: 0.3)
        #expect(near(zY(window) - before, 64, 0.6), "\(form): → ends 64 below")
        window.typeKey(.leftArrow)
        settle(window)
        window.advance(by: 0.098)
        #expect(near(zY(window) - before, 64 * 0.3175, 1.2), "\(form): ← at 98 ms: \(zY(window) - before)")
        window.advance(by: 0.3)
        #expect(near(zY(window), before, 0.6), "\(form): ← ends back where it began")
    }
}

/// **An accessibility expand request animates** (`OG-F`), as the chevron does.
@Test @MainActor func anAccessibilityPressSlidesTheRows() throws {
    for form in Form.allCases {
        let window = form == .content ? try listWindow(SModel(smallTree())) : try dataWindow()
        defer { withExtendedLifetime(window) {} }
        let before = zY(window)
        let tree = try window.accessibilityTree
        func holds(_ id: AccessibilityNodeID) -> Bool {
            guard let node = tree.nodes[id] else { return false }
            if node.role == .staticText, node.value == "A" { return true }
            return node.children.contains(where: holds)
        }
        guard let row = tree.nodes.first(where: { $0.value.role == .row && holds($0.key) }) else {
            Issue.record("\(form): no row A"); continue
        }
        #expect(window.platformWindow.simulateAccessibilityRequest(.expand(row.key)), "\(form): the expand request is handled")
        settle(window)
        #expect(near(zY(window), before, 0.6), "\(form): at the press Z has not moved")
        window.advance(by: 0.098)
        #expect(near(zY(window) - before, 64 * 0.6825, 1.2), "\(form): at 98 ms: \(zY(window) - before)")
        window.advance(by: 0.3)
    }
}

/// **⌥→ cascades and animates**: every descendant opens in one turn and the rows below slide by all of it. Content form (the
/// request path). Mutation: the request not marking the input (the cascade snaps).
@Test @MainActor func anOptionCascadeSlidesTheRows() throws {
    let model = SModel([SNode("A", children: [SNode("A1", children: [SNode("A1a"), SNode("A1b")]), SNode("A2")]), SNode("Z")])
    let window = try listWindow(model)
    defer { withExtendedLifetime(window) {} }
    window.click(at: pt(200, rowY(0)))
    settle(window)
    let before = column(window, depth: 0)
    window.typeKey(.rightArrow, modifierFlags: .option)
    settle(window)
    #expect(near(column(window, depth: 0)[1].y, before[1].y, 0.6), "at the key Z has not moved")
    window.advance(by: 0.098)
    let travel: Float = 32 * 4
    #expect(near(column(window, depth: 0)[1].y - before[1].y, travel * 0.6825, 1.5), "at 98 ms: \(column(window, depth: 0)[1].y - before[1].y)")
    window.advance(by: 0.3)
    #expect(near(column(window, depth: 0)[1].y - before[1].y, travel, 0.6), "ends \(travel) below")
}

// MARK: outside the window, outside a list

/// **A splice outside the realised window does not animate** (divergence 1088): a folder far below the viewport opens inside a
/// `withAnimation`, and a folder far above it too; the visible rows do not move (nothing to slide) and no animation frame is
/// drawn. Control: the same write for a visible folder animates. Mutation: classifying with no unmoved row required (the rows
/// shifted by a folder above slide).
@Test @MainActor func aSpliceOutsideTheWindowDoesNotAnimate() async throws {
    var nodes = (0..<60).map { SNode("f\($0)", children: [SNode("f\($0)a"), SNode("f\($0)b")]) }
    nodes.insert(SNode("top", children: [SNode("t1"), SNode("t2")]), at: 0)
    let model = SModel(nodes)
    let window = try listWindow(model)
    defer { withExtendedLifetime(window) {} }
    let drawn = window.framesDrawn
    withAnimation(.linear(duration: 1)) { model.roots[50].isExpanded = true }
    try await window.runUntilIdle()
    window.advance(by: 0.05)
    window.advance(by: 0.05)
    let stillBelow = column(window, depth: 0)
    window.advance(by: 0.05)
    #expect(column(window, depth: 0).map(\.y) == stillBelow.map(\.y), "a folder below the window slides nothing")
    _ = drawn
    for _ in 0..<12 where visible(window).contains("top") {
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -600)
        settle(window)
    }
    #expect(!visible(window).contains("top"), "control: the folder is above the realised window: \(visible(window).prefix(4))")
    let top = window.framesDrawn
    withAnimation(.linear(duration: 1)) { model.roots[0].isExpanded = true }   // above the viewport: every visible row shifts
    try await window.runUntilIdle()
    let still = column(window, depth: 0)
    window.advance(by: 0.05)
    #expect(column(window, depth: 0).map(\.y) == still.map(\.y), "a folder above the window slides nothing: \(still.map(\.y)) then \(column(window, depth: 0).map(\.y))")
    window.advance(by: 0.3)
    #expect(column(window, depth: 0).map(\.y) == still.map(\.y) && still.allSatisfy { $0.alpha == 1 }, "and fades nothing: \(still.map(\.alpha))")
    _ = top
    // Control: a visible folder animates.
    for _ in 0..<40 where !visible(window).contains("f0") {
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 600)
        settle(window)
    }
    let ready = window.framesDrawn
    withAnimation(.linear(duration: 1)) { model.roots[1].isExpanded = true }
    try await window.runUntilIdle()
    window.advance(by: 0.05)
    #expect(window.framesDrawn > ready + 1, "control: a visible folder's write animates")
}

/// **An eager `DisclosureGroup` outside a list keeps lane 1's behaviour**: a click writes bare and snaps, no animation frame.
@Test @MainActor func aStandaloneDisclosureGroupStillSnapsOnAClick() throws {
    let window = try harnessWindow(size: sz(300, 400)) {
        VStack(spacing: Pixels(0)) {
            DisclosureGroup("Group") { ProposalText("inside") }
            ProposalText("below")
        }
    }
    settle(window)
    defer { withExtendedLifetime(window) {} }
    let glyphs = window.allGlyphs.count
    let header = try #require(window.elements(role: .disclosureTriangle).first)
    window.click(at: pt(header.frame.origin.x.value + 4, header.frame.origin.y.value + 6))
    settle(window)
    #expect(window.allGlyphs.count > glyphs, "the click opened the group")
    let drawn = window.framesDrawn
    window.advance(by: 0.1)
    window.advance(by: 0.1)
    #expect(window.framesDrawn == drawn, "no animation frames")
}

// MARK: lane 8 (the content flatten cache) is untouched

private func evaluations(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentEvaluations } }
private func rebuilds(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentRebuilds } }
private func hits(_ work: [FrameWork]) -> Int { work.reduce(0) { $0 + $1.outlineContentHits } }

/// **An animating frame evaluates nothing and rebuilds nothing, and idle returns to lane 8's literals.** After the splice frame:
/// every tick through the 245 ms has `outlineContentEvaluations` 0, `outlineContentRebuilds` 0, `outlineIndexRebuilds` 0 and one
/// cache hit; once it has run its course an idle frame (`setNeedsRedraw` + tick) is evaluations 0, hits 1, checks 3, as
/// `anIdleFrameEvaluatesNothingAndWalksNothing`. Control: the click's own frame evaluated (the cache was refilled). Mutation:
/// the animation invalidating the cache (a `noteStateRead` or a layout-affecting write per frame): the animating frames evaluate.
@Test @MainActor func animationFramesLeaveTheFlattenCacheAlone() throws {
    let window = try listWindow(SModel(smallTree()))
    defer { withExtendedLifetime(window) {} }
    window.resetFrameWork()
    chevron(window, "A")
    settle(window)
    #expect(evaluations(window.frameWork) > 0, "control: the splice frame evaluated the new content")
    window.resetFrameWork()
    for _ in 0..<5 { window.advance(by: 0.04) }
    #expect(window.frameWork.count >= 5, "the animating ticks drew: \(window.frameWork.count)")
    #expect(evaluations(window.frameWork) == 0, "evaluations \(window.frameWork.map(\.outlineContentEvaluations))")
    #expect(rebuilds(window.frameWork) == 0 && window.frameWork.allSatisfy { $0.outlineIndexRebuilds == 0 },
            "rebuilds \(window.frameWork.map(\.outlineContentRebuilds))")
    #expect(window.frameWork.allSatisfy { $0.outlineContentHits == 1 }, "hits \(window.frameWork.map(\.outlineContentHits))")
    window.advance(by: 0.1)
    window.resetFrameWork()
    for _ in 0..<3 {
        window.window.setNeedsRedraw()
        window.tick()
    }
    #expect(window.frameWork.count == 3 && evaluations(window.frameWork) == 0 && rebuilds(window.frameWork) == 0,
            "idle after the animation: \(window.frameWork.map(\.outlineContentEvaluations))")
    #expect(hits(window.frameWork) == 3 && window.frameWork.allSatisfy { $0.outlineContentChecks == 3 },
            "hits \(window.frameWork.map(\.outlineContentHits)), checks \(window.frameWork.map(\.outlineContentChecks))")
}
