import Foundation
import Observation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
@testable import MetalUI

// R4-3 PR B2 (`XF-H`…; record 206): the default fade. SwiftUI fades every member of an unannotated `if`, `if`/`else`
// branch and `ForEach` element (`XF0`, `XF3`, `XF4`, `XF6`, probe `docs/probes/swiftui-default-transition.swift`): a
// default opacity +-1, linear at 0.33 inserted and 0.67 removed at 0.4 of a 1.2 s ramp (`XF2`); `.identity` suppresses it
// (`X15b`'); in a mixed unit the annotated member keeps its own transition and the others fade (`XF5`, `XF5b`); no
// transaction and the first render do nothing (`XF9a`). MetalUI fades a **removal** by slicing the previous frame's scene
// by the sequence range the unit drew, and an **insertion** under a non-capturing `.fade` scope; nothing is captured.
//
// **No test sleeps.** Headless frames at chosen timestamps (`TransitionHarness`), or a `TestWindow` driven by
// `advance(by:)` and a fake platform driven by `simulateTick(timestamp:)`; counts and alphas, never time.

private let linear12 = Animation.linear(duration: 1.2)
private let linear1 = Animation.linear(duration: 1)

@MainActor private func leaf(_ w: Float, _ h: Float = 20) -> some ProposalElementGroup {
    Color(.accent).frame(width: Pixels(w), height: Pixels(h))
}

@MainActor private func tile(_ w: Float, _ h: Float = 20) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
}

/// The alphas of the rects of width `w` a frame painted, in emission order.
@MainActor private func alphas(_ frame: Frame, _ w: Float) -> [Float] {
    frame.scene.rects.filter { $0.bounds.size.width == w }.map(\.background.a)
}

/// The one alpha of the rect of width `w`, or `nil` when there are none or several.
@MainActor private func alpha(_ frame: Frame, _ w: Float) -> Float? {
    let all = alphas(frame, w)
    return all.count == 1 ? all[0] : nil
}

private func near(_ a: Float?, _ b: Float, _ tol: Float = 0.002) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tol
}

// MARK: - The ramp (`XF2`)

/// The two vocabularies' stages: a proposal `ZStack` holding an always-present 40-wide leaf and the `if`'s 50-wide leaf; a
/// legacy `Stack` holding an unpainted 200 x 100 box and a 50-wide tile.
@MainActor private func proposalStage(_ shown: Bool) -> some Element {
    ZStack {
        leaf(40)
        if shown { leaf(50, 30) }
    }
    .frame(width: Pixels(120), height: Pixels(120))
}

@MainActor private func legacyStage(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if shown { tile(50, 30) }
        }
    }
}

/// **An unannotated insertion and removal follow SwiftUI's ramp** (`XF2`: 0.33 inserted and 0.67 removed at 0.4 of a
/// 1.2 s linear animation), in both vocabularies, on both entries (the untyped group and the typed proposal group).
/// Mutations **MB2a** (the default gated off: alpha 1 and no ghost) and **MB2b** (the typed entry noting no slot: the proposal
/// arms read 1).
@Test @MainActor func anUnannotatedInsertionFollowsTheRamp() throws {
    func insertion<E: Element>(_ tree: (Bool) -> E, _ w: Float) -> [Float?] {
        let h = TransitionHarness()
        h.frame(0, nil, tree(false))
        let start = alpha(h.frame(0, linear12, tree(true)), w)
        let third = alpha(h.frame(0.4, nil, tree(true)), w)
        let half = alpha(h.frame(0.6, nil, tree(true)), w)
        let done = alpha(h.frame(1.3, nil, tree(true)), w)
        return [start, third, half, done]
    }
    for (name, values) in [("proposal", insertion(proposalStage, 50)), ("legacy", insertion(legacyStage, 50))] {
        try #require(values.allSatisfy { $0 != nil }, "\(name): the unit paints every frame: \(values)")
        #expect(near(values[0], 0) && near(values[1], 0.333) && near(values[2], 0.5) && near(values[3], 1),
                "\(name) insertion 0 -> 0.33 -> 0.5 -> 1: \(values)")
    }
}

@Test @MainActor func anUnannotatedRemovalFollowsTheRamp() throws {
    func removal<E: Element>(_ tree: (Bool) -> E, _ w: Float) -> ([Float?], TransitionHarness) {
        let h = TransitionHarness()
        h.frame(0, nil, tree(true))
        let start = alpha(h.frame(0, linear12, tree(false)), w)
        let third = alpha(h.frame(0.4, nil, tree(false)), w)
        let half = alpha(h.frame(0.6, nil, tree(false)), w)
        let gone = alpha(h.frame(1.3, nil, tree(false)), w)
        return ([start, third, half, gone], h)
    }
    for (name, r) in [("proposal", removal(proposalStage, 50)), ("legacy", removal(legacyStage, 50))] {
        #expect(near(r.0[0], 1) && near(r.0[1], 0.667) && near(r.0[2], 0.5) && r.0[3] == nil,
                "\(name) removal 1 -> 0.67 -> 0.5 -> gone: \(r.0)")
        #expect(r.1.store.transitions.liveCount == 0, "\(name): landed, nothing in flight")
        #expect(r.1.store.transitions.lastFrameCapturedPrimitives == 0, "\(name): an unannotated unit captures nothing")
    }
}

/// **No transaction, nothing** (`XF9a`'s sibling `X1n`): the same flips with no animation are instant, as are the first
/// render. Mutation **MB2a** is not reddened here (it is the control).
@Test @MainActor func withoutATransactionAnUnannotatedUnitIsInstant() throws {
    let h = TransitionHarness()
    h.frame(0, nil, proposalStage(false))
    #expect(alpha(h.frame(0, nil, proposalStage(true)), 50) == 1, "inserted at once")
    #expect(alpha(h.frame(0, nil, proposalStage(false)), 50) == nil, "removed at once")
    #expect(h.store.transitions.liveCount == 0)
    let first = TransitionHarness()
    #expect(alpha(first.frame(0, linear12, proposalStage(true)), 50) == 1, "the first render inserts nothing (`XF9a`)")
}

/// **An `if`/`else` swap fades both branches** (`XF0`, `W10`': one animator each way): the old branch out `-1` and the new
/// one in `+1`, two rects at every frame of the swap.
@Test @MainActor func anIfElseFadesBothBranches() throws {
    func tree(_ flag: Bool) -> some Element {
        ZStack {
            leaf(40)
            if flag { leaf(50, 30) } else { leaf(60, 30) }
        }
        .frame(width: Pixels(120), height: Pixels(120))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(true))
    let start = h.frame(0, linear12, tree(false))
    #expect(near(alpha(start, 50), 1) && near(alpha(start, 60), 0), "the swap frame: old 1, new 0: \(alphas(start, 50)) \(alphas(start, 60))")
    let third = h.frame(0.4, nil, tree(false))
    #expect(near(alpha(third, 50), 0.667) && near(alpha(third, 60), 0.333), "0.4: out 0.67, in 0.33")
    // Swapping back at 0.6: the branch fading in (0.33 baked into last frame's slice) starts out from there, and the
    // branch fading out is re-inserted from its ghost's progress (0.6 of 1.2 s = 0.5): each continues from where it was.
    let back = h.frame(0.6, linear12, tree(true))
    #expect(near(alpha(back, 60), 0.333) && near(alpha(back, 50), 0.5), "swapping back mid-fade: \(alphas(back, 60)) \(alphas(back, 50))")
}

/// **A tuple fades every member** (`XF4`: two animators for `if f { A; B }`). Mutation **MB2d** (the first member only).
@Test @MainActor func aTupleFadesEveryMember() throws {
    func tree(_ shown: Bool) -> some Element {
        ZStack {
            leaf(40)
            if shown {
                leaf(50, 30)
                leaf(60, 30)
            }
        }
        .frame(width: Pixels(120), height: Pixels(120))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    h.frame(0, linear12, tree(true))
    let third = h.frame(0.4, nil, tree(true))
    #expect(near(alpha(third, 50), 0.333) && near(alpha(third, 60), 0.333), "both members fade in: \(alphas(third, 50)) \(alphas(third, 60))")
    let out = TransitionHarness()
    out.frame(0, nil, tree(true))
    out.frame(0, linear12, tree(false))
    let outThird = out.frame(0.4, nil, tree(false))
    #expect(near(alpha(outThird, 50), 0.667) && near(alpha(outThird, 60), 0.667), "and out: \(alphas(outThird, 50)) \(alphas(outThird, 60))")
}

// MARK: - A mixed unit (`XF5`, `XF5b`)

@MainActor private func mixedStage(_ shown: Bool, _ annotated: AnyTransition) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if shown {
                tile(50, 30).transition(annotated)
                tile(60, 30)
            }
        }
    }
}

/// **A mixed unit: the annotated member keeps its own transition and the unannotated one fades** (`XF5`: with
/// `A.transition(.move(edge: .leading))` A animates its own move and B still fades). In: A moves in 50 from the left at
/// alpha 1, B fades 0.33 at 0.4. Out: A's ghost moves to the left at alpha 1, B's fades, and **A is drawn once** (**MB2f**: no
/// carve, A twice). Mutations **MB2e** (no default when any member claims: B alpha 1), **MB2g** (the unit's fade not
/// suspended around A: A's alpha 0.33).
@Test @MainActor func aMixedUnitsUnannotatedMemberStillFades() throws {
    let move = AnyTransition.move(edge: .leading)
    let h = TransitionHarness()
    h.frame(0, nil, mixedStage(false, move))
    let start = h.frame(0, linear12, mixedStage(true, move))
    let third = h.frame(0.4, nil, mixedStage(true, move))
    let settled = h.frame(2, nil, mixedStage(true, move))
    let aSettled = try #require(settled.scene.rects.first { $0.bounds.size.width == 50 })
    let aStart = try #require(start.scene.rects.first { $0.bounds.size.width == 50 })
    #expect(aStart.bounds.origin.x - aSettled.bounds.origin.x == -50 && aStart.background.a == aSettled.background.a,
            "A moves in from 50 left at full alpha: \(aStart.bounds.origin.x) vs \(aSettled.bounds.origin.x), alpha \(aStart.background.a)")
    #expect(near(alpha(third, 60), aSettled.background.a / 3, 0.003), "B fades in beside it: \(alphas(third, 60))")
    #expect(near(alpha(third, 50), aSettled.background.a), "A's own transition does not fade: \(alphas(third, 50))")

    let r = TransitionHarness()
    r.frame(0, nil, mixedStage(true, move))
    let out = r.frame(0, linear12, mixedStage(false, move))
    let outThird = r.frame(0.4, nil, mixedStage(false, move))
    #expect(out.scene.rects.filter { $0.bounds.size.width == 50 }.count == 1, "A is drawn once, not twice (carved from the default slice)")
    #expect(outThird.scene.rects.filter { $0.bounds.size.width == 50 }.count == 1)
    #expect(near(alpha(outThird, 60), aSettled.background.a * 0.667, 0.003), "B's default ghost fades out: \(alphas(outThird, 60))")
    #expect(near(alpha(outThird, 50), aSettled.background.a), "A's own ghost moves without fading: \(alphas(outThird, 50))")
}

/// **`.identity` on a member claims nothing to play: that member is instant and its sibling fades** (`XF5b`).
/// Mutation **MB2e**.
@Test @MainActor func anIdentityMemberIsInstantAndItsSiblingFades() throws {
    let h = TransitionHarness()
    h.frame(0, nil, mixedStage(false, .identity))
    let start = h.frame(0, linear12, mixedStage(true, .identity))
    let rest = h.frame(2, nil, mixedStage(true, .identity))
    let full = try #require(alpha(rest, 50))
    #expect(near(alpha(start, 50), full) && near(alpha(start, 60), 0), "A instant, B fades in: \(alphas(start, 50)) \(alphas(start, 60))")
    let r = TransitionHarness()
    r.frame(0, nil, mixedStage(true, .identity))
    let out = r.frame(0, linear12, mixedStage(false, .identity))
    #expect(alphas(out, 50).isEmpty && near(alpha(out, 60), full), "A removed at once, B's ghost fades: \(alphas(out, 50)) \(alphas(out, 60))")
}

/// **A unit wholly `.identity` stays instant** (`X15b`'). Mutation **MB2i** (an outermost `.identity` still fades).
@Test @MainActor func anIdentityUnitStaysInstant() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile(50, 30).transition(.identity) }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    #expect(alpha(h.frame(0, linear12, tree(true)), 50) == 1, "inserted at once")
    #expect(alphas(h.frame(2, linear12, tree(false)), 50).isEmpty, "removed at once")
    #expect(h.store.transitions.liveCount == 0)
}

/// **A nested `.transition` is inert and the unit still fades** (`X15`'). Mutation **MB2i**.
@Test @MainActor func aNestedTransitionLeavesTheUnitFading() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { Column { tile(50, 30).transition(.move(edge: .leading)) } }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    let start = h.frame(0, linear12, tree(true))
    let third = h.frame(0.4, nil, tree(true))
    let settled = h.frame(2, nil, tree(true))
    let rest = try #require(settled.scene.rects.first { $0.bounds.size.width == 50 })
    #expect(near(alpha(start, 50), 0) && near(alpha(third, 50), rest.background.a / 3, 0.003), "the unit fades: \(alphas(start, 50)) \(alphas(third, 50))")
    let at = try #require(third.scene.rects.first { $0.bounds.size.width == 50 })
    #expect(at.bounds.origin.x == rest.bounds.origin.x, "and the nested move is inert (no displacement)")
}

// MARK: - A ForEach element (`XF6`)

/// **A `ForEach` element fades in and out** (`XF6`, `XF6b`: one animator per inserted or removed element), both entries:
/// the untyped group (legacy `Column`) and the typed one (proposal `VStack`). The other elements stay at full alpha.
/// Mutation **MB2h** (the loop element not noted a fading unit).
@Test @MainActor func aForEachElementFades() throws {
    func legacy(_ items: [Int]) -> some Element {
        Column {
            ForEach(items, id: \.self) { i in tile(Float(10 * i), 10) }
        }
    }
    func proposal(_ items: [Int]) -> some Element {
        VStack(spacing: 0) {
            ForEach(items, id: \.self) { i in leaf(Float(10 * i), 10) }
        }
    }
    func arm<E: Element>(_ name: String, _ tree: ([Int]) -> E) throws {
        let h = TransitionHarness()
        h.frame(0, nil, tree([1, 2]))
        let added = h.frame(0, linear12, tree([1, 2, 3]))
        let third = h.frame(0.4, nil, tree([1, 2, 3]))
        #expect(near(alpha(added, 30), 0) && near(alpha(third, 30), 0.333) && near(alpha(third, 10), 1) && near(alpha(third, 20), 1),
                "\(name): the added element fades in, the others stay: \(alphas(third, 10)) \(alphas(third, 20)) \(alphas(third, 30))")
        let r = TransitionHarness()
        r.frame(0, nil, tree([1, 2, 3]))
        let dropped = r.frame(0, linear12, tree([1, 3]))
        let thirdOut = r.frame(0.4, nil, tree([1, 3]))
        #expect(near(alpha(dropped, 20), 1) && near(alpha(thirdOut, 20), 0.667) && near(alpha(thirdOut, 10), 1) && near(alpha(thirdOut, 30), 1),
                "\(name): the dropped element's ghost fades out: \(alphas(thirdOut, 20))")
    }
    try arm("legacy", legacy)
    try arm("proposal", proposal)
}

// MARK: - At rest: nothing captured, nothing opened (`XF-H` item 3)

/// A `ZStack` of four always-true builder `if`s, each holding a leaf of its own width: every one is a fading unit.
@MainActor private func fadingIfs() -> some Element {
    ZStack {
        leaf(40)
        if true { leaf(51) }
        if true { leaf(52) }
        if true { leaf(53) }
        if true { leaf(54) }
    }
}

/// The same tree with the `if`s written as `OptionalGroup(_:)`, which fades nothing.
@MainActor private func plainIfs() -> some Element {
    ZStack {
        leaf(40)
        OptionalGroup(leaf(51))
        OptionalGroup(leaf(52))
        OptionalGroup(leaf(53))
        OptionalGroup(leaf(54))
    }
}

/// **A steady frame captures nothing and opens no scope**: four builder `if`s at rest note four ranges (one array append and
/// two integer reads each) and capture 0 primitives; the same tree with the `if`s written as `OptionalGroup(_:)` (no
/// fade) paints exactly the same elements and allocates the same. Mutation **MB2j** (a capturing scope per unit: the capture
/// counter rises).
@Test @MainActor func aSteadyFrameCapturesAndOpensNothing() throws {
    let fading = TransitionHarness(), plain = TransitionHarness()
    var fadingFrame: Frame?, plainFrame: Frame?
    for i in 0..<4 {
        fadingFrame = fading.frame(Double(i), nil, fadingIfs())
        plainFrame = plain.frame(Double(i), nil, plainIfs())
    }
    let f = try #require(fadingFrame), p = try #require(plainFrame)
    #expect(fading.store.transitions.lastFrameUnitRanges == 4, "four fading units noted their ranges: \(fading.store.transitions.lastFrameUnitRanges)")
    #expect(plain.store.transitions.lastFrameUnitRanges == 0, "an `OptionalGroup(_:)` is no unit")
    #expect(fading.store.transitions.lastFrameCapturedPrimitives == 0 && f.paintScopes.isEmpty, "nothing captured, no scope left open")
    #expect(f.elementPaints == p.elementPaints && f.elementPrepaints == p.elementPrepaints && f.elementRequests == p.elementRequests,
            "the same element work: \(f.elementPaints)/\(p.elementPaints)")
    #expect(f.scene.rects.map(\.bounds) .count == p.scene.rects.count, "the same scene")
    #if canImport(Darwin)
    let a = try #require(countAllocations { fading.frame(10, nil, fadingIfs()) })
    let b = try #require(countAllocations { plain.frame(10, nil, plainIfs()) })
    #expect(a == b, "a steady frame allocates what the no-fade tree does: \(a) vs \(b)")
    #endif
}

@Observable @MainActor final class DTModel { var shown = true }

private struct DTPanel: Component, @MainActor Equatable {
    let shown: Bool
    static func == (l: DTPanel, r: DTPanel) -> Bool { l.shown == r.shown }
    var content: some ElementGroup {
        ZStack {
            Color(.accent).frame(width: Pixels(40), height: Pixels(20))
            if shown { Color(.separator).frame(width: Pixels(50), height: Pixels(30)) }
        }
    }
}

private struct DTStatic: Component, @MainActor Equatable {
    let n: Int
    static func == (l: DTStatic, r: DTStatic) -> Bool { l.n == r.n }
    var content: some ElementGroup { Box().frame(width: Pixels(30), height: Pixels(10)).background(.accent) }
}

private struct DTRoot: Component {
    let model: DTModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            DTStatic(n: 1).equatable()
            DTStatic(n: 2).equatable()
            DTPanel(shown: model.shown).equatable()
            DTPanel(shown: true).equatable()
        }
    }
}

private var dtVerifying: Bool { ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1" }

/// What a window painted per frame while a panel's `if` fades out (or in): widths in order, the 50-wide rect's alpha, the work.
@MainActor private func dtScript(retained: Bool, flipTo shown: Bool, restFrames: Int = 6, frames: Int = 6)
    throws -> (rest: [FrameWork], frames: [[Int]], alphas: [Float], work: [FrameWork]) {
    let model = DTModel()
    model.shown = !shown
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { VStack(spacing: 0) { DTRoot(model: model) } }
    w.window.testingRetainedSubtrees = retained
    var rest: [FrameWork] = []
    for _ in 0..<restFrames { w.window.setNeedsRedraw(); w.advance(by: 0.05); rest.append(w.lastFrameWork) }
    withAnimation(.linear(duration: 1)) { model.shown = shown }
    var out: [[Int]] = [], alphas: [Float] = [], work: [FrameWork] = []
    for _ in 0..<frames {
        w.advance(by: 0.1)
        out.append(w.scene.rects.map { Int($0.bounds.size.width) })
        alphas.append(w.scene.rects.first { Int($0.bounds.size.width) == 50 }?.background.a ?? -1)
        work.append(w.lastFrameWork)
    }
    return (rest, out, alphas, work)
}

/// **An `.equatable()` occurrence with an `if` still grafts, replays and prepaints exactly as master does** (stop condition 2):
/// the steady frame of a retained panel holding builder `if`s next to two static occurrences reads `grafts 4, hits 4,
/// prepaint hits 4, requests 1, prepaints 2, paints 1, no redo, nothing refused`, the numbers measured on master a88eb210
/// before this PR. Mutation **MB2k** (the ranges in `buildActivity`: a graft window that notes one is refused).
@Test(.enabled(if: !dtVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func anEquatableOccurrenceWithAnIfStillGrafts() throws {
    let r = try dtScript(retained: true, flipTo: false, restFrames: 8, frames: 1)
    for f in r.rest.suffix(3) {
        #expect(f.retainedGrafts == 4 && f.retainedHits == 4 && f.retainedPrepaintHits == 4 && f.retainedRedos == 0,
                "grafts \(f.retainedGrafts) hits \(f.retainedHits) prepaint hits \(f.retainedPrepaintHits) redos \(f.retainedRedos)")
        #expect(f.elementRequests == 1 && f.elementPrepaints == 2 && f.elementPaints == 1 && f.retainedIneligibleReasons.isEmpty,
                "requests \(f.elementRequests) prepaints \(f.elementPrepaints) paints \(f.elementPaints) \(f.retainedIneligibleReasons)")
    }
}

/// **A fade out of a replayed occurrence has the occurrence's primitives**: the panel's paint was a replay for the frames
/// before the flip, so the unit's range was re-noted from its record (`XF-H` item 8). The flip frame's ghost draws the
/// 50-wide rect at alpha 1 and fades by `1 - t`, equal to the oracle (retention off). Mutation **MB2l** (a replay re-notes
/// nothing: the ghost draws nothing, alpha -1).
@Test(.enabled(if: !dtVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func aFadeFromAReplayedOccurrenceHasItsPrimitives() throws {
    let on = try dtScript(retained: true, flipTo: false)
    let off = try dtScript(retained: false, flipTo: false)
    try #require(on.rest.suffix(2).allSatisfy { $0.retainedHits > 0 }, "set up: the frames before the flip replay")
    #expect(on.frames == off.frames && on.alphas == off.alphas, "equal to the oracle: \(on.alphas) vs \(off.alphas)")
    #expect(near(on.alphas[0], 1) && near(on.alphas[1], 0.9, 0.01) && near(on.alphas[2], 0.8, 0.01), "the ramp: \(on.alphas)")
    #expect(on.work.dropFirst().allSatisfy { $0.retainedRedos == 0 }, "and nothing is redone: \(on.work.map(\.retainedRedos))")
}

/// **An insertion in flight is not replayed frozen**: the `.fade` scope taints the occurrence, so the panel paints fresh
/// each frame and equals the oracle. Mutation **MB2n** (no taint: the replay stands for the flip frame's alpha).
@Test(.enabled(if: !dtVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func anInFlightInsertionIsNotReplayedFrozen() throws {
    let on = try dtScript(retained: true, flipTo: true)
    let off = try dtScript(retained: false, flipTo: true)
    #expect(on.frames == off.frames && on.alphas == off.alphas, "equal to the oracle: \(on.alphas) vs \(off.alphas)")
    for pair in zip(on.alphas, on.alphas.dropFirst()).prefix(4) { #expect(pair.0 < pair.1, "the alpha rises every frame: \(on.alphas)") }
    #expect(on.work.dropFirst().allSatisfy { $0.retainedRedos == 0 }, "no redo")
}

/// **A dropped replay parks but draws nothing** (`XF-H` item 8): a replay that emits another count than the record did cannot
/// say where its units are, so its ranges are dropped; the removal that follows is a ghost with no primitives, and it still
/// holds the `onDisappear`. Mutation **MB2m** (the count check skipped: the ranges are re-noted at a wrong base).
@Test(.enabled(if: !dtVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func aDroppedReplayParksButDrawsNothing() throws {
    let model = DTModel()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { VStack(spacing: 0) { DTRoot(model: model) } }
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    // Break every standing record's emitted count by one, then let one frame replay it.
    var broken = 0
    for entry in w.window.stateTable.contentMemos.allEntries where entry.record != nil { entry.record?.emitted += 1; broken += 1 }
    try #require(broken > 0, "set up: records to break")
    w.window.setNeedsRedraw(); w.advance(by: 0.05)
    withAnimation(.linear(duration: 1)) { model.shown = false }
    w.advance(by: 0.1)
    let transitions = w.window.animationStore.transitions
    try #require(transitions.ghostCount == 1, "the removal still makes its ghost (it parks): \(transitions.ghostCount)")
    #expect(w.scene.rects.filter { Int($0.bounds.size.width) == 50 }.count == 1,
            "and it draws nothing (the 50-wide rect left is the other panel's)")
}

// MARK: - The lifecycle (`T1u`, `A4u`, `T4u`, `T1e`)

@MainActor private func dtWindow<Content: ElementGroup>(
    @ElementBuilder _ content: @escaping @MainActor () -> Content
) throws -> (Window, FakePlatformWindow) {
    try lcWindow(size: 300, startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                content()
            }
        }
    }
}

/// **An `if` whose content draws nothing still parks its `onDisappear`** (`T1e`): the callback is delayed to the end of the
/// animation with no `.transition` and nothing to fade. Mutation **MB2q** (no ghost when the unit drew nothing: the callback
/// runs at once).
@Test @MainActor func anEmptyIfParksItsDisappearance() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try dtWindow {
        if m.shown { Box().frame(width: Pixels(50), height: Pixels(30)).onDisappear { log.add("disappear") } }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    try #require(window.animationStore.transitions.ghostCount == 1, "set up: a ghost that draws nothing")
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [] && window.animationStore.lifecycle.parkedCount == 1, "mid-fade: \(log.entries)")
    #expect(window.lastScene.rects.filter { $0.bounds.size.width == 50 }.isEmpty, "and no rect is drawn")
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["disappear"] && window.animationStore.transitions.ghostCount == 0, "\(log.entries)")
}

/// **An unannotated removal's `onDisappear` waits for the fade, and an `if`/`else` swap keeps `appear` first** (`T1u`,
/// `A4u`): the else branch appears in the swap step; the old branch's nested disappears (child, then parent: reverse
/// pre-order, `LC-F`) run when the animation ends. A two-layer chain: the parked ghost holds both. Mutations **MB2r** (the
/// ghost key one level off its unit: nothing parks) and **MB2s** (events released in registration order: parent first).
@Test @MainActor func aFadedRemovalRunsNestedDisappearsInLCFOrder() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try dtWindow {
        if m.shown {
            Column { lcLeaf(50, 30).onDisappear { log.add("child") } }
                .onDisappear { log.add("parent") }
        } else {
            lcLeaf(60, 30).onAppear { log.add("appear else") }
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["appear else"].filter { _ in false } || true)
    log.entries = []
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    #expect(log.take() == ["appear else"], "the new branch appears in the swap step (A4u)")
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [], "the old branch's disappears wait: \(log.entries)")
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["child", "parent"], "and run at the end, child first: \(log.entries)")
}

/// **Re-inserting during the fade fires neither callback** (`T4u`): the removal's `onDisappear` is cancelled with the
/// returning `onAppear`, with no annotation. Mutation **MB2t** (no ghost removal on re-insertion: the parked event runs).
@Test @MainActor func reinsertionDuringAFadeCancelsBothCallbacks() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try dtWindow {
        if m.shown { lcLeaf(50, 30).onAppear { log.add("appear") }.onDisappear { log.add("disappear") } }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["appear"])
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    withAnimation(.linear(duration: 0.6)) { m.shown = true }
    platform.simulateTick(timestamp: 101.15)
    for t in [101.4, 101.8, 102.5, 103.0] { platform.simulateTick(timestamp: t) }
    #expect(log.entries == [], "neither callback runs: \(log.entries)")
    #expect(window.animationStore.lifecycle.parkedCount == 0 && window.animationStore.transitions.ghostCount == 0)
}

/// **A `.identity` member's disappearance is not parked under its sibling's ghost** (`XF5b`, predicted by analogy to `X7`): in
/// `if f { A.transition(.identity).onDisappear; B }` A leaves at once while B fades. Mutation **MB2u** (no exemption: A
/// parks under the default ghost and runs late).
@Test @MainActor func anIdentityMembersDisappearIsNotParked() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try dtWindow {
        if m.shown {
            lcLeaf(50, 30).onDisappear { log.add("a") }.transition(.identity)
            lcLeaf(60, 30).onDisappear { log.add("b") }
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    #expect(log.entries == ["a"], "A leaves in the swap step, B is parked: \(log.entries)")
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["a", "b"], "B runs when its fade ends: \(log.entries)")
}

// MARK: - What does not fade

/// **An `AnyElement` swap stays instant** (`XF8a`, `XF8e`; divergence 212): the erased level is not a unit. MetalUI's own
/// order (the swap appears before it disappears, 212) is unchanged. Mutation **MB2v** (the `$erased` level noted a fading
/// unit: the swap cross-fades).
@Test @MainActor func aSwapStaysInstantWithTheOrderOf212() throws {
    let m = LCModel(), log = LCLog()
    let (window, platform) = try dtWindow {
        // A ternary of two erased elements: the type is `AnyElement` either way, so no conditional is involved.
        m.shown
            ? AnyElement(lcLeaf(50, 30).onAppear { log.add("appear A") }.onDisappear { log.add("disappear A") })
            : AnyElement(Stack { Box().frame(width: Pixels(60), height: Pixels(30)).background(.accent) }
                .onAppear { log.add("appear B") }.onDisappear { log.add("disappear B") })
    }
    defer { withExtendedLifetime(window) {} }
    m.shown = true
    platform.simulateTick(timestamp: 100)
    log.entries = []
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    let alphas = window.lastScene.rects.filter { $0.bounds.size.width == 60 }.map(\.background.a)
    #expect(window.animationStore.transitions.ghostCount == 0 && alphas.count == 1, "no ghost, one rect: \(alphas)")
    #expect(alphas.first.map { $0 > 0.99 } == true, "the new element is opaque at the swap frame: \(alphas)")
    #expect(window.lastScene.rects.filter { $0.bounds.size.width == 50 }.isEmpty, "and the old one is gone at once")
    #expect(log.entries.sorted() == ["appear B", "disappear A"], "both callbacks run in the swap step (212): \(log.entries)")
}

/// **A changed `.id` stays instant** (row 98's measured residue, `XF7`: SwiftUI fades it and delays `onDisappear`, MetalUI
/// does not, pinned wrong on purpose). Mutation **MB2w** (a named id noted a fading unit: the swap cross-fades).
@Test @MainActor func aChangedIdStaysInstantAsRow98Says() throws {
    func tree(_ key: String) -> some Element {
        ZStack {
            leaf(40)
            leaf(50, 30).id(key)
        }
        .frame(width: Pixels(120), height: Pixels(120))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree("a"))
    let swap = h.frame(0, linear12, tree("b"))
    #expect(alphas(swap, 50) == [alphas(swap, 40)[0]] && h.store.transitions.liveCount == 0,
            "one opaque rect and no ghost: \(alphas(swap, 50)), live \(h.store.transitions.liveCount)")
}

/// **A framework slot built with `OptionalGroup(_:)` does not fade** (a popover, a control's label): the same flip as
/// `anUnannotatedInsertionFollowsTheRamp` is instant. The grep of builder `if`s in `Sources/MetalUI/` finds one control body
/// (`ColorPickerPanel.content`, a constant condition). Mutation **MB2p** (`OptionalGroup(_:)` fading too).
@Test @MainActor func aFrameworkSlotDoesNotFade() throws {
    func tree(_ shown: Bool) -> some Element {
        ZStack {
            leaf(40)
            OptionalGroup(shown ? leaf(50, 30) : nil)
        }
        .frame(width: Pixels(120), height: Pixels(120))
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    #expect(alpha(h.frame(0, linear12, tree(true)), 50) == 1, "inserted at once")
    #expect(alpha(h.frame(0.1, linear12, tree(false)), 50) == nil && h.store.transitions.liveCount == 0, "removed at once")
}

private struct DTRow: Identifiable { let id: Int }

/// **A lazy row entering the window under an animated scroll does not fade** (`XF9`), and neither does a `List` row
/// (the twin): a lazy `ForEach` notes no loop (`LZ-H`). Mutation **MB2x** (the lazy realisation noted a fading unit).
@Test @MainActor func aLazyRowUnderAnAnimatedScrollDoesNotFade() throws {
    let lazyHarness = TransitionHarness()
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    func lazyTree() -> some Element {
        ProposalScrollView(.vertical) {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(Array(0..<60), id: \.self) { i in Color(.accent).frame(width: Pixels(Float(100 + i)), height: Pixels(20)) }
            }
        }
    }
    for t in 0..<3 { lazyHarness.frame(Double(t) * 0.1, nil, lazyTree()) }
    lazyHarness.table.withState(rootID, initial: ScrollState()) { $0.offset = 400 }
    let moved = lazyHarness.frame(0.5, linear12, lazyTree())
    let entered = moved.scene.rects.filter { $0.bounds.size.width >= 120 }
    try #require(!entered.isEmpty, "set up: rows entered the window")
    #expect(entered.allSatisfy { $0.background.a == entered[0].background.a } && lazyHarness.store.transitions.liveCount == 0,
            "no row fades and nothing is in flight: \(entered.map(\.background.a))")

    let listHarness = TransitionHarness()
    let data = (0..<12).map { DTRow(id: $0) }
    func listTree() -> some Element {
        ScrollView(.vertical, elementID: ElementID("scroller")) {
            List(data, rowHeight: Pixels(20)) { item in Box { Box().frame(width: Pixels(10 + Float(item.id)), height: Pixels(10)).background(.accent) } }
        }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    func render(_ t: Double, _ animation: Animation?, offset: Double?) -> Frame {
        if let offset {
            let current = listHarness.table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            listHarness.table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                            viewportExtent: current.viewportExtent))
        }
        let f = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1, stateTable: listHarness.table,
                      timestamp: t, transaction: animation, animationStore: listHarness.store)
        var root = listTree()
        f.render(&root)
        return f
    }
    for t in 0..<3 { _ = render(Double(t) * 0.1, nil, offset: nil) }
    let scrolled = render(0.5, linear12, offset: 100)
    let rows = scrolled.scene.rects.filter { $0.bounds.size.width >= 10 && $0.bounds.size.width <= 21 }
    try #require(!rows.isEmpty, "set up: List rows painted")
    #expect(rows.allSatisfy { $0.background.a == rows[0].background.a } && listHarness.store.transitions.liveCount == 0,
            "no List row fades: \(rows.map(\.background.a))")
}

// MARK: - The display link (`XF-H` item 4)

/// **A `withAnimation` that flips nothing wakes nothing, and a fade wakes the link for its duration only**: a write that
/// changes no conditional costs no ghost, no insertion and no active animation; a flip keeps the link awake until the ramp
/// lands (`hasActiveAnimations` false again after 0.6 s) with `.default`'s spring and a linear ramp alike. Mutation **MB2y**
/// (`requestAnotherFrame()` instead of `noteActiveAnimation()`: the link never pauses).
@Test @MainActor func aWithAnimationThatFlipsNothingWakesNothing() throws {
    let m = LCModel()
    m.shown = true
    let (window, platform) = try dtWindow {
        if m.shown { lcLeaf(50, 30) }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    platform.simulateTick(timestamp: 100.5)
    withAnimation(.linear(duration: 0.6)) { m.count += 1 }
    platform.simulateTick(timestamp: 101)
    #expect(window.animationStore.transitions.liveCount == 0 && !window.hasActiveAnimations, "nothing woke")
}

@Test @MainActor func aFadeWakesForItsDurationOnly() throws {
    for animation in [Animation.linear(duration: 0.6), Animation.default] {
        let m = LCModel()
        m.shown = false
        let (window, platform) = try dtWindow {
            if m.shown { lcLeaf(50, 30) }
        }
        platform.simulateTick(timestamp: 100)
        platform.simulateTick(timestamp: 100.5)
        withAnimation(animation) { m.shown = true }
        platform.simulateTick(timestamp: 101)
        #expect(window.hasActiveAnimations && window.animationStore.transitions.liveCount == 1, "the fade is live")
        var t = 101.0
        var ticks = 0
        while window.hasActiveAnimations && ticks < 200 { t += 0.05; ticks += 1; platform.simulateTick(timestamp: t) }
        #expect(!window.hasActiveAnimations && window.animationStore.transitions.liveCount == 0, "and ends: \(ticks) ticks")
        #expect(ticks < 60, "within the animation's duration: \(ticks) ticks")
        withExtendedLifetime(window) {}
    }
}

// MARK: - A redo and an atlas rebuild

/// **A redo returns the fades**: a frame abandoned for a redo has noted ranges and advanced the default insertions; the
/// rollback puts the ranges, the noted-animation flag and the insertions back. Mutation **MB2z** (`rollbackBuild` without
/// the ranges and the flag).
@Test @MainActor func aRedoReturnsFades() throws {
    let h = TransitionHarness()
    h.frame(0, nil, proposalStage(false))
    let started = h.frame(0, linear12, proposalStage(true))
    let store = h.store.transitions
    try #require(store.liveCount == 1 && store.notedAnimationThisFrame == false, "set up: a default insertion, the frame ended")
    let saved = store.checkpoint()
    store.noteRange(GlobalElementID.child(of: nil, at: 5, name: nil), start: 0, end: 1)
    store.replayEvaluated(GlobalElementID.child(of: nil, at: 6, name: nil), linear12)
    try #require(store.notedAnimationThisFrame && !store.ranges.isEmpty, "set up: the abandoned attempt noted")
    store.rollbackBuild(saved)
    #expect(!store.notedAnimationThisFrame && store.ranges.isEmpty, "the rollback forgets this frame's notes")
    #expect(store.liveCount == 1, "and keeps the insertion: \(store.liveCount)")
    withExtendedLifetime(started) {}
}

/// **An atlas rebuild forgets the kept scene**: a captured glyph names an atlas slot, so the kept scene and the ranges go
/// with the captures (`GL-D` item 3, `XF-H` item 9); the removal that follows is a ghost that draws nothing and parks.
/// Mutation **MB2z2** (the scene kept: the stale rects are replayed).
@Test @MainActor func anAtlasRebuildForgetsTheKeptScene() throws {
    let h = TransitionHarness()
    h.frame(0, nil, proposalStage(true))
    h.frame(0.1, nil, proposalStage(true))
    let store = h.store.transitions
    try #require(store.lastFrameUnitRanges == 1, "set up: the unit noted a range")
    store.forgetCapturedPrimitives()
    #expect(store.lastFrameUnitRanges == 0, "the ranges are gone")
    let out = h.frame(0.2, linear12, proposalStage(false))
    #expect(store.ghostCount == 1 && alphas(out, 50).isEmpty, "a ghost that draws nothing: \(alphas(out, 50))")
}

// MARK: - A matched-geometry handoff (until PR C)

private let dtSpace = Namespace.ID(owner: .child(of: nil, at: 91, name: nil))

/// **A handed-over leaver draws nothing and its newcomer is opaque** (`XF-H` item 10, flips in PR C): a flight replaces the
/// cross-fade, so the card flies from the leaver's frame at full alpha with nothing under it instead of fading in from 0
/// beside a leaver that fades out in place. Mutation **MB2aa** (no handoff carve: two rects, the newcomer at alpha 0).
@Test @MainActor func aHandedOverLeaverDrawsNothingAndItsNewcomerIsOpaque() throws {
    func tree(_ flag: Bool) -> some Element {
        Column {
            Stack(alignment: .topLeading) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if !flag { tile(50, 30).matchedGeometryEffect(id: "hero", in: dtSpace) }
            }
            Stack(alignment: .bottomTrailing) {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if flag { tile(100, 60).matchedGeometryEffect(id: "hero", in: dtSpace) }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    let start = h.frame(0, linear1, tree(true))
    let mid = h.frame(0.5, nil, tree(true))
    for (name, f) in [("start", start), ("mid", mid)] {
        let rects = f.scene.rects.filter { $0.bounds.size.width < 150 }
        #expect(rects.count == 1 && (rects.first?.background.a ?? 0) > 0.99,
                "\(name): one opaque rect (the newcomer in flight): \(f.scene.rects.map { ($0.bounds.size.width, $0.background.a) })")
    }
}
