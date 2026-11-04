import Foundation
import Observation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// R4-3 PR B1 (`XF-F`, `XF-G`; record 205): where a removal ghost is drawn, and what an empty one does.
//
// SwiftUI drops a leaver to the **bottom of its own container's run** (`XF10`, `XF2zb`, `XF2zc`, probe
// `docs/probes/swiftui-default-transition.swift`): `ZStack { blue; if red }` removal reads `[background, ghost, blue]`,
// with a third always-present leaf `[background, ghost, blue, green]`, a `VStack` with red first `[ghost, blue]`, nested
// `[background, blue, ghost, yellow, green]`; annotated and unannotated alike; insertion stays in place (`XF10d`).
// MetalUI drew every ghost after the root (above everything). Each leaf below is a `Color` of its own width, so a scene's
// rect widths read as the order: background 120, red (the transitioning leaf) 50, blue 40, yellow 30, green 20.
//
// **No test sleeps.** Headless frames at chosen timestamps (`TransitionHarness`), or a `TestWindow` driven by
// `advance(by:)`; counts and orders, never time.

private let linear1 = Animation.linear(duration: 1)

@MainActor private func leaf(_ w: Float, _ h: Float) -> some ProposalElementGroup {
    Color(.accent).frame(width: Pixels(w), height: Pixels(h))
}

/// The widths of the rects a frame painted, in emission order: the order of the leaves.
@MainActor private func order(_ frame: Frame) -> [Int] {
    frame.scene.rects.map { Int($0.bounds.size.width) }
}

/// The 120-point backdrop every order test draws first.
@MainActor private func onBackdrop<C: ProposalElementGroup & Element>(_ content: C) -> some Element {
    content.frame(width: Pixels(120), height: Pixels(120)).background(Color(.separator))
}

/// One removal on `tree`: the order at rest (present), at the frame that starts the removal under `linear(1)`, and half-way.
/// Also returns the harness for the counters.
@MainActor private func removal<E: Element>(_ tree: (Bool) -> E)
    -> (rest: [Int], start: [Int], mid: [Int], harness: TransitionHarness) {
    let h = TransitionHarness()
    let rest = order(h.frame(0, nil, tree(true)))
    let start = order(h.frame(0, linear1, tree(false)))
    let mid = order(h.frame(0.5, nil, tree(false)))
    return (rest, start, mid, h)
}

// MARK: - The position (`XF10`, `XF2zb`, `XF2zc`)

/// **A ghost above a sibling drops below it** (`XF10b`: `ZStack { blue; if red }`, `[background, ghost, blue]`). Mutations
/// **MB1a** (the ghost drawn after the root, as before) and **MB1b** (drawn in place) both read `[120, 40, 50]`.
@Test @MainActor func aGhostAboveASiblingDropsBelowIt() throws {
    let r = removal { shown in
        onBackdrop(ZStack {
            leaf(40, 20)
            if shown { leaf(50, 30).transition(.opacity) }
        })
    }
    try #require(r.rest == [120, 40, 50], "at rest red is above blue: \(r.rest)")
    #expect(r.start == [120, 50, 40], "the ghost is the first thing in the container's run: \(r.start)")
    #expect(r.mid == [120, 50, 40], "and stays there as it fades: \(r.mid)")
    #expect(r.harness.store.transitions.lastFrameUnanchoredGhosts == 0)
}

/// **A ghost below a sibling stays below it** (`XF10a`). The control: the container-first rule and the in-place rule
/// agree here, so only a draw after the root (**MB1a**, `[120, 40, 50]`) reddens it.
@Test @MainActor func aGhostBelowASiblingStaysBelowIt() throws {
    let r = removal { shown in
        onBackdrop(ZStack {
            if shown { leaf(50, 30).transition(.opacity) }
            leaf(40, 20)
        })
    }
    try #require(r.rest == [120, 50, 40], "at rest red is below blue: \(r.rest)")
    #expect(r.start == [120, 50, 40], "\(r.start)")
    #expect(r.mid == [120, 50, 40], "\(r.mid)")
}

/// **A leaf above the ghost stays above it** (`XF2zb`, `[background, ghost, blue, green]`). **MB1a** reads
/// `[120, 40, 20, 50]`, drawn in place **(MB1b)** `[120, 40, 50, 20]`.
@Test @MainActor func aThirdLeafStaysAboveTheGhost() throws {
    let r = removal { shown in
        onBackdrop(ZStack {
            leaf(40, 20)
            if shown { leaf(50, 30).transition(.opacity) }
            leaf(20, 5)
        })
    }
    try #require(r.rest == [120, 40, 50, 20], "\(r.rest)")
    #expect(r.start == [120, 50, 40, 20], "\(r.start)")
    #expect(r.mid == [120, 50, 40, 20], "\(r.mid)")
}

/// **A nested ghost is first in its OWN container, not the outermost's** (`XF2zc`:
/// `onWhite { blue; ZStack { if red; yellow }; green }` reads `[background, blue, ghost, yellow, green]`). A two-layer
/// chain: the inner stack and the outer one both contain the ghost's position, and only the nearer is the container.
/// Mutations **MB1c** (the outermost ancestor: `[120, 50, 30, 40, 20]`) and **MB1a** (`[120, 30, 40, 20, 50]`).
@Test @MainActor func aNestedGhostIsFirstInItsOwnContainer() throws {
    let r = removal { shown in
        onBackdrop(ZStack {
            leaf(30, 10)
            ZStack {
                if shown { leaf(50, 30).transition(.opacity) }
                leaf(40, 20)
            }
            leaf(20, 5)
        })
    }
    try #require(r.rest == [120, 30, 50, 40, 20], "\(r.rest)")
    #expect(r.start == [120, 30, 50, 40, 20], "\(r.start)")
    #expect(r.mid == [120, 30, 50, 40, 20], "\(r.mid)")
    #expect(r.harness.store.transitions.lastFrameUnanchoredGhosts == 0)
}

/// **A stack's first member leaves first** (`XF2z`: a `VStack` with red first reads `[ghost, blue]`). **MB1a** reads
/// `[40, 50]`.
@Test @MainActor func aVStackGhostIsFirst() throws {
    let r = removal { shown in
        VStack {
            if shown { leaf(50, 30).transition(.opacity) }
            leaf(40, 20)
        }
    }
    try #require(r.rest == [50, 40], "\(r.rest)")
    #expect(r.start == [50, 40], "\(r.start)")
    #expect(r.mid == [50, 40], "\(r.mid)")
}

/// A VStack with the leaver last drops it to the front: the separating arm of the stack case (`[ghost, blue]` from
/// `[blue, red]`), where in place and container-first differ.
@Test @MainActor func aVStackGhostLastMovesToTheFront() throws {
    let r = removal { shown in
        VStack {
            leaf(40, 20)
            if shown { leaf(50, 30).transition(.opacity) }
        }
    }
    try #require(r.rest == [40, 50], "\(r.rest)")
    #expect(r.start == [50, 40], "\(r.start)")
    #expect(r.mid == [50, 40], "\(r.mid)")
}

/// **A ghost is drawn above its container's own fill and below its content** (legacy `Stack` fill, proposal `.background`).
/// Legacy: fill 120, ghost 50, content 40. Mutation **MB1d** (the hook in `paintGroup` for a styled element too) draws the
/// ghost under the fill: `[50, 120, 40]`.
@Test @MainActor func aGhostSitsAboveItsContainersOwnFill() throws {
    func tile(_ w: Float, _ h: Float) -> some StyledElement {
        Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
    }
    let legacy = removal { shown in
        Stack {
            if shown { tile(50, 30).transition(.opacity) }
            tile(40, 20)
        }
        .frame(width: Pixels(120), height: Pixels(120)).background(.separator)
    }
    try #require(legacy.rest == [120, 50, 40], "legacy at rest: \(legacy.rest)")
    #expect(legacy.start == [120, 50, 40], "the Stack's own fill is below its ghost: \(legacy.start)")
    #expect(legacy.mid == [120, 50, 40], "\(legacy.mid)")
    #expect(legacy.harness.store.transitions.lastFrameUnanchoredGhosts == 0)

    // The proposal `.background` is a separate layer outside the stack: also below the ghost (the first test's `120`).
    let proposal = removal { shown in
        onBackdrop(ZStack {
            leaf(40, 20)
            if shown { leaf(50, 30).transition(.opacity) }
        })
    }
    #expect(proposal.start.first == 120 && proposal.start.dropFirst().first == 50, "\(proposal.start)")
}

/// A `Component` is not a container, and neither is the conditional's slot (`XF-F` item 1): the ghost is first in the
/// `ZStack`'s run, not in the component's. Mutation **MB1e** (a component records its bounds, so it is the nearest
/// ancestor): the ghost is drawn at the component's place or not at its anchor, never `[120, 50, 40, 20]`.
private struct GPLeaver: Component {
    let shown: Bool
    var content: some ProposalElementGroup {
        if shown { leaf(50, 30).transition(.opacity) }
    }
}

@Test @MainActor func aComponentAndASlotAreNotContainers() throws {
    let r = removal { shown in
        onBackdrop(ZStack {
            leaf(40, 20)
            GPLeaver(shown: shown)
            leaf(20, 5)
        })
    }
    try #require(r.rest == [120, 40, 50, 20], "\(r.rest)")
    #expect(r.start == [120, 50, 40, 20], "the ZStack is the container: \(r.start)")
    #expect(r.mid == [120, 50, 40, 20], "\(r.mid)")
    #expect(r.harness.store.transitions.lastFrameUnanchoredGhosts == 0, "and the ghost is anchored")
}

/// **An erased container is a container** (`AnyElement`'s group entry records its bounds like `Element`'s, so its position is
/// the anchor of a ghost inside the wrapped element). Legacy vocabulary, where `AnyElement` is a group member. Mutation
/// **MB1k** (the hook removed from `AnyElement`'s `paintGroup`): the ghost is unanchored and drawn last, `[40, 30, 20, 50]`.
@Test @MainActor func anErasedContainersGhostIsAnchoredAtItsEntry() throws {
    func tile(_ w: Float, _ h: Float) -> some StyledElement {
        Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
    }
    let r = removal { shown in
        Stack {
            tile(40, 20)
            AnyElement(Stack {
                tile(30, 10)
                if shown { tile(50, 30).transition(.opacity) }
            })
            tile(20, 5)
        }
    }
    try #require(r.rest == [40, 30, 50, 20], "\(r.rest)")
    #expect(r.start == [40, 50, 30, 20], "the ghost is first in the erased container's run: \(r.start)")
    #expect(r.mid == [40, 50, 30, 20], "\(r.mid)")
    #expect(r.harness.store.transitions.lastFrameUnanchoredGhosts == 0)
}

// MARK: - Insertion stays in place (`XF10d`)

/// **An insertion is not moved** (`XF10d`): a leaf above its sibling enters above it, a leaf below enters below. Nothing
/// touches an insertion's paint (a control for the whole change: no mutation site).
@Test @MainActor func anInsertionStaysInPlace() throws {
    func tree(_ above: Bool, _ shown: Bool) -> some Element {
        onBackdrop(ZStack {
            if !above, shown { leaf(50, 30).transition(.opacity) }
            leaf(40, 20)
            if above, shown { leaf(50, 30).transition(.opacity) }
        })
    }
    for above in [true, false] {
        let h = TransitionHarness()
        h.frame(0, nil, tree(above, false))
        h.frame(0, linear1, tree(above, true))
        let mid = order(h.frame(0.5, nil, tree(above, true)))
        #expect(mid == (above ? [120, 40, 50] : [120, 50, 40]), "red \(above ? "above" : "below") blue: \(mid)")
    }
}

// MARK: - The counter has a separating arm

/// `lastFrameUnanchoredGhosts` is 0 in every tree above and counts a ghost no hook reached: a hidden container paints
/// nothing and reaches no hook, so its ghost (here empty: nothing was ever drawn in it) is drawn after the root.
@Test @MainActor func aHiddenContainersGhostIsCountedUnanchored() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(100), height: Pixels(50))
                if shown { Box().frame(width: Pixels(50), height: Pixels(30)).background(.accent).transition(.opacity) }
            }
            .hidden()
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(true))
    h.frame(0, linear1, tree(false))
    #expect(h.store.transitions.ghostCount == 1, "set up: a ghost")
    #expect(h.store.transitions.lastFrameUnanchoredGhosts == 1, "no hook was reached")
}

// MARK: - A redo puts the draw state back (`RK-M`)

/// A frame abandoned for a redo is built again: a ghost the abandoned attempt drew at its container is drawn again by the
/// rebuild. **MB1j** (the restored ghosts omit the draw mark and anchor, `rollbackBuild` without `ghosts = saved.ghosts`)
/// leaves the mark set and the rebuild draws nothing at the anchor.
@Test @MainActor func aRedoReturnsAnchors() throws {
    func tree(_ shown: Bool) -> some Element {
        onBackdrop(ZStack {
            leaf(40, 20)
            if shown { leaf(50, 30).transition(.opacity) }
        })
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(true))
    let f = h.frame(0, linear1, tree(false))
    let store = h.store.transitions
    try #require(store.ghostCount == 1 && store.hasAnchoredGhosts, "set up: an anchored ghost")
    let anchor = try #require(store.ghostAnchors.first ?? nil)
    let saved = store.checkpoint()
    let before = f.scene.rects.count
    store.paintGhosts(anchoredAt: anchor, frame: f)
    try #require(f.scene.rects.count == before + 1, "the abandoned attempt drew the ghost at its anchor")
    store.paintGhosts(anchoredAt: anchor, frame: f)
    try #require(f.scene.rects.count == before + 1, "set up: a ghost is drawn once per attempt")
    store.rollbackBuild(saved)
    store.paintGhosts(anchoredAt: anchor, frame: f)
    #expect(f.scene.rects.count == before + 2, "the rebuild draws it again at the restored anchor")
    #expect(store.ghostAnchors.first ?? nil == anchor, "and the anchor is the restored one")
}

// MARK: - Retention (`XF-F` item 5)

@Observable @MainActor final class GPModel {
    var shown = true
}

private struct GPPanel: Component, @MainActor Equatable {
    let shown: Bool
    static func == (l: GPPanel, r: GPPanel) -> Bool { l.shown == r.shown }
    var content: some ElementGroup {
        ZStack {
            Color(.accent).frame(width: Pixels(40), height: Pixels(20))
            if shown { Color(.separator).frame(width: Pixels(50), height: Pixels(30)).transition(.opacity) }
        }
    }
}

private struct GPStatic: Component, @MainActor Equatable {
    let n: Int
    static func == (l: GPStatic, r: GPStatic) -> Bool { l.n == r.n }
    var content: some ElementGroup { Box().frame(width: Pixels(30), height: Pixels(10)).background(.accent) }
}

private struct GPRoot: Component {
    let model: GPModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            GPStatic(n: 1).equatable()
            GPStatic(n: 2).equatable()
            GPPanel(shown: model.shown).equatable()
        }
    }
}

private var gpVerifying: Bool { ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1" }

/// What a window painted per frame while a panel's ghost fades: the widths in order and the ghost's alpha (the 50-wide rect).
@MainActor private func gpScript(retained: Bool) throws -> (frames: [[Int]], alphas: [Float], work: [FrameWork]) {
    let model = GPModel()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { VStack(spacing: 0) { GPRoot(model: model) } }
    w.window.testingRetainedSubtrees = retained
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    withAnimation(.linear(duration: 1)) { model.shown = false }
    var frames: [[Int]] = [], alphas: [Float] = [], work: [FrameWork] = []
    for _ in 0..<6 {
        w.advance(by: 0.1)
        frames.append(w.scene.rects.map { Int($0.bounds.size.width) })
        alphas.append(w.scene.rects.first { Int($0.bounds.size.width) == 50 }?.background.a ?? -1)
        work.append(w.lastFrameWork)
    }
    return (frames, alphas, work)
}

/// **A ghost drawn inside a retained occurrence is not replayed frozen.** The panel's paint cannot record while its ghost
/// lives (`ghostInRun`), so its replay never stands in for a frame whose ghost has moved: the ghost's alpha changes on
/// every frame and equals the oracle's (retention off). The siblings still graft, and **no frame is redone**. Mutation
/// **MB1g** (no taint): the panel records the flip frame's paint without the ghost, and the next frame replays it, so the
/// ghost is missing (alpha -1) or frozen.
@Test(.enabled(if: !gpVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts are not its to read"))
@MainActor func aGhostInARetainedOccurrenceIsNotReplayedFrozen() throws {
    let on = try gpScript(retained: true)
    let off = try gpScript(retained: false)
    #expect(on.frames == off.frames, "equal to the oracle: \(on.frames) vs \(off.frames)")
    #expect(on.alphas == off.alphas, "\(on.alphas) vs \(off.alphas)")
    for pair in zip(on.alphas, on.alphas.dropFirst()).prefix(4) {
        #expect(pair.0 > pair.1 && pair.1 >= 0, "the ghost moves every frame: \(on.alphas)")
    }
    // The cost while a ghost lives (stop condition 2 of the plan): the panel builds, prepaints and paints fresh each frame and
    // is counted ineligible by name; its siblings graft; nothing is redone.
    for f in on.work.dropFirst(2) {   // the flip frame and the next one (the siblings' first replay) build everything
        #expect(f.retainedRedos == 0, "no redo: \(f.retainedRedos)")
        #expect(f.retainedIneligibleReasons["ghostInRun", default: 0] == 1, "\(f.retainedIneligibleReasons)")
        #expect(f.retainedGrafts == 2, "the two static siblings still graft: \(f.retainedGrafts)")
    }
}

/// **A ghost's container is found with prepaint replay running around it** (`XF-F` item 2): the siblings' prepaints replay
/// in the frames the ghost lives, and in the frame that starts it the ancestors are seen (the anchor is resolved, the
/// ghost is first in its container, none is unanchored). Mutation **MB1h** (resolving before prepaint, when no id has been
/// seen): every ghost is unanchored and drawn last.
@Test @MainActor func aGhostsAncestorsAreSeenUnderPrepaintReplay() throws {
    let model = GPModel()
    let w = try TestWindow(size: Size(width: Pixels(200), height: Pixels(200))) { VStack(spacing: 0) { GPRoot(model: model) } }
    for _ in 0..<6 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    withAnimation(.linear(duration: 1)) { model.shown = false }
    w.advance(by: 0.1)
    let transitions = w.window.animationStore.transitions
    try #require(transitions.ghostCount == 1, "set up: a ghost")
    #expect(transitions.hasAnchoredGhosts, "anchored")
    #expect(transitions.lastFrameUnanchoredGhosts == 0, "\(transitions.lastFrameUnanchoredGhosts)")
    let widths = w.scene.rects.map { Int($0.bounds.size.width) }
    #expect(widths.firstIndex(of: 50) == (widths.firstIndex(of: 40) ?? 0) - 1, "ghost, then blue: \(widths)")
    w.advance(by: 0.1)
    w.advance(by: 0.1)
    #expect(w.lastFrameWork.retainedPrepaintHits > 0, "the siblings' prepaints replay while the ghost lives: \(w.lastFrameWork.retainedPrepaintHits)")
    #expect(transitions.lastFrameUnanchoredGhosts == 0)
}

// MARK: - Empty content parks (`XF-G`, `T1e2`)

/// **An annotated removal of content that draws nothing still holds its `onDisappear`** (`T1e2`): SwiftUI delays the
/// callback to the end of the animation, with or without drawing. MetalUI skipped the ghost for an empty capture, so the
/// callback ran at once. Mutation **MB1i** (the guard `!previous.captures.isEmpty` restored): `disappear` at mid-fade.
@Test @MainActor func anEmptyAnnotatedRemovalParksItsDisappearance() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try lcWindow(size: 300, startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if m.shown { Box().frame(width: Pixels(50), height: Pixels(30)).onDisappear { log.add("disappear") }.transition(.opacity) }
            }
        }
    }
    defer { withExtendedLifetime(window) {} }
    platform.simulateTick(timestamp: 100)
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    try #require(window.animationStore.transitions.ghostCount == 1, "set up: a ghost with nothing to draw")
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [], "mid-fade: \(log.entries)")
    #expect(window.animationStore.lifecycle.parkedCount == 1)
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["disappear"], "\(log.entries)")
    #expect(window.animationStore.transitions.ghostCount == 0)
}
