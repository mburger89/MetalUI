import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Plan task 13, lane 3 — transitions and the documented surface (ruling `AN-AE`
// as amended by `AN-AH`; spec
// `docs/superpowers/specs/2026-09-30-transactions-animation-design.md` §6.5,
// tests 3.1–3.18 and 3.20–3.24; guard 3.19 is `TransitionCompileGuards`).
// SwiftUI's side is `docs/probes/swiftui-transactions-animation.swift`, arms
// X0–X17c and R5–R10.
//
// **No test sleeps.** Every arm renders headless `Frame`s over one shared
// `StateTable` and one shared `AnimationStore` at chosen timestamps, the
// transaction handed to the frame that starts the change (what
// `Window.drawFrameIfNeeded` hands a build); 3.15 drives a real `Window` by
// `simulateTick(timestamp:)`. The shape of every arm: a resting frame at 0, the
// change at 0 under `linear(duration: 1)`, 0.5 half-way, 1.0 landed.
//
// The transitioning tile is a 50 × 30 accent box inside a `Stack` whose other
// child — an unpainted 200 × 100 box — fixes the container's size, so the
// tile's own size (50 × 30) and its container's (200 × 100) differ and nothing
// else moves when the tile comes and goes.

// MARK: - Harness

@MainActor
final class TransitionHarness {
    let table = StateTable()
    let store = AnimationStore()
    /// One registry across the harness's frames, as a `Window` holds one
    /// (MetalView, `MV-E` item 6) — so a surface's id continuity is exercised.
    let surfaces = SurfaceRegistry()
    var accessibility = false

    @discardableResult
    func frame<E: Element>(_ t: Double, _ animation: Animation? = nil, _ element: E,
                           side: Float = 300, scaleFactor: Float = 1) -> Frame {
        var root = element
        let frame = Frame(contentSize: Size(width: Pixels(side), height: Pixels(side)), scaleFactor: scaleFactor,
                          stateTable: table, timestamp: t, transaction: animation, animationStore: store,
                          surfaceRegistry: surfaces, collectsAccessibility: accessibility, reportsUnlowerableFields: true)
        frame.render(&root)
        #expect(frame.unlowerableFields.isEmpty, "t \(t): \(frame.unlowerableFields)")
        return frame
    }
}

private let linear1 = Animation.linear(duration: 1)

private struct TransitionRow: Identifiable { let id: String }

@MainActor private func isAccent(_ c: MUIHsla) -> Bool {
    let accent = Theme.light[.accent]
    return abs(c.h - accent.h) < 0.001 && abs(c.s - accent.s) < 0.001 && abs(c.l - accent.l) < 0.001
}

/// Every accent rect `frame` painted, in emission order.
@MainActor private func accents(_ frame: Frame) -> [MUIRect] {
    frame.scene.rects.filter { isAccent($0.background) }
}

/// The one accent rect `frame` painted, or `nil` when it painted none or several.
@MainActor private func accent(_ frame: Frame) -> MUIRect? {
    let all = accents(frame)
    return all.count == 1 ? all[0] : nil
}

private func describe(_ r: MUIRect?) -> String {
    guard let r else { return "nil" }
    return "(\(r.bounds.origin.x), \(r.bounds.origin.y), \(r.bounds.size.width)×\(r.bounds.size.height), a \(r.background.a))"
}

/// The 50 × 30 accent tile (legacy).
@MainActor private func tile(_ w: Float = 50, _ h: Float = 30) -> some StyledElement {
    Box().frame(width: Pixels(w), height: Pixels(h)).background(.accent)
}

/// The stage: a 200 × 100 container holding the tile under `if shown`, the
/// tile carrying `transition`.
@MainActor private func stage(_ shown: Bool, _ transition: AnyTransition,
                              reduceMotion: Bool = false) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if shown { tile().transition(transition) }
        }
        .environment(\.accessibilityReduceMotion, reduceMotion)
    }
}

/// One insertion: rest (absent) at 0, the change at 0 under `linear(1)`, 0.5,
/// 1.0, and a settled frame at 2.0 whose tile is the reference.
@MainActor private func insertion(_ transition: AnyTransition, reduceMotion: Bool = false,
                                  animation: Animation? = linear1, scaleFactor: Float = 1)
    -> (start: MUIRect?, mid: MUIRect?, end: MUIRect?, settled: MUIRect?) {
    let h = TransitionHarness()
    let sf = scaleFactor
    h.frame(0, nil, stage(false, transition, reduceMotion: reduceMotion), scaleFactor: sf)
    let start = accent(h.frame(0, animation, stage(true, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let mid = accent(h.frame(0.5, nil, stage(true, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let end = accent(h.frame(1.0, nil, stage(true, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let settled = accent(h.frame(2.0, nil, stage(true, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    return (start, mid, end, settled)
}

/// One removal: rest (present) at 0 — its tile the reference — the change at 0
/// under `linear(1)`, 0.5, and 1.0; each removal frame's accent rects (the
/// ghost's, if any).
@MainActor private func removal(_ transition: AnyTransition, reduceMotion: Bool = false,
                                animation: Animation? = linear1, scaleFactor: Float = 1)
    -> (rest: MUIRect?, start: [MUIRect], mid: [MUIRect], end: [MUIRect]) {
    let h = TransitionHarness()
    let sf = scaleFactor
    let rest = accent(h.frame(0, nil, stage(true, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let start = accents(h.frame(0, animation, stage(false, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let mid = accents(h.frame(0.5, nil, stage(false, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    let end = accents(h.frame(1.0, nil, stage(false, transition, reduceMotion: reduceMotion), scaleFactor: sf))
    return (rest, start, mid, end)
}

/// `r`'s origin relative to `reference`'s.
private func offset(_ r: MUIRect?, from reference: MUIRect?) -> (Float, Float)? {
    guard let r, let reference else { return nil }
    return (r.bounds.origin.x - reference.bounds.origin.x, r.bounds.origin.y - reference.bounds.origin.y)
}

private func same(_ a: MUIRect?, _ b: MUIRect?) -> Bool {
    guard let a, let b else { return false }
    return a.bounds.origin.x == b.bounds.origin.x && a.bounds.origin.y == b.bounds.origin.y
        && a.bounds.size.width == b.bounds.size.width && a.bounds.size.height == b.bounds.size.height
}

// MARK: - 3.1 (X1 insert)

/// **3.1 (X1).** `.transition(.opacity)` on an `if`'s content, inserted under
/// `linear(1)`: alpha 0 on the frame that starts it, ½ half-way, 1 landed —
/// always at its final place. Red before: does not compile. Mutation **M3.1**:
/// skip insertion.
@Test @MainActor func anOpacityTransitionFadesAnInsertedElementIn() throws {
    let r = insertion(.opacity)
    try #require(r.settled != nil, "set up: the settled frame paints the tile")
    #expect(r.start?.background.a == 0 && r.mid?.background.a == 0.5 && r.end?.background.a == 1,
            "X1: alpha 0 → ½ → 1; got \(describe(r.start)), \(describe(r.mid)), \(describe(r.end))")
    #expect(same(r.start, r.settled) && same(r.mid, r.settled),
            "an opacity insertion paints at the final place: \(describe(r.start)) vs \(describe(r.settled))")
}

// MARK: - 3.2 (X1 remove)

/// **3.2 (X1).** The same tile removed: on the frame that removes it a GHOST
/// paints at its last place at alpha 1, ½ half-way, and nothing at 1.0. The
/// ghost registers **no hitbox and no accessibility node** (the tile carries an
/// `onClick` and a label, so the live tile has both). Red before: does not
/// compile. Mutations **M3.2a**: capture nothing (no ghost); **M3.2b**:
/// register the ghost's hitbox.
@Test @MainActor func anOpacityTransitionFadesARemovedElementOut() throws {
    let h = TransitionHarness()
    h.accessibility = true
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown {
                    tile().onClick {}.accessibilityLabel("tile").transition(.opacity)
                }
            }
        }
    }
    let restFrame = h.frame(0, nil, tree(true))
    let rest = accent(restFrame)
    try #require(rest != nil, "set up: the live tile paints")
    func hasTileHitbox(_ f: Frame) -> Bool {
        f.hitboxes.contains { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 }
    }
    func hasTileNode(_ f: Frame) -> Bool {
        f.axNodes.values.contains { $0.label == "tile" } || f.axEmissions.contains { $0.declared.label == "tile" }
    }
    try #require(hasTileHitbox(restFrame) && hasTileNode(restFrame),
                 "set up: the live tile has a hitbox and an accessibility node, or their absence below proves nothing")

    let startFrame = h.frame(0, linear1, tree(false))
    let midFrame = h.frame(0.5, nil, tree(false))
    let endFrame = h.frame(1.0, nil, tree(false))
    let start = accents(startFrame), mid = accents(midFrame)
    #expect(start.count == 1 && same(start.first, rest) && start.first?.background.a == 1,
            "the removing frame paints the ghost at its last place, alpha 1: \(start.map(describe))")
    #expect(mid.count == 1 && same(mid.first, rest) && mid.first?.background.a == 0.5,
            "half-way the ghost is at alpha ½: \(mid.map(describe))")
    #expect(accents(endFrame).isEmpty, "landed: the ghost is gone: \(accents(endFrame).map(describe))")
    for (label, f) in [("start", startFrame), ("mid", midFrame)] {
        #expect(!hasTileHitbox(f), "\(label): a ghost registers no hitbox")
        #expect(!hasTileNode(f), "\(label): a ghost publishes no accessibility node")
    }
}

// MARK: - 3.3 (X2, X3, X3t, X3b)

/// **3.3.** `.move(edge:)` offsets by the element's OWN size (50 × 30), not its
/// container's (200 × 100): inserting from leading starts 50 left (−25 half-way),
/// from trailing 50 right, from the top 30 up (−15 half-way); removing to the
/// top ends 30 up (−15 half-way), to the bottom 30 down. Red before: does not
/// compile. Mutation **M3.3**: use the container's size.
@Test @MainActor func aMoveTransitionOffsetsByTheElementsOwnSize() throws {
    let leading = insertion(.move(edge: .leading))
    #expect(offset(leading.start, from: leading.settled).map { [$0.0, $0.1] } == [-50, 0]
                && offset(leading.mid, from: leading.settled).map { [$0.0, $0.1] } == [-25, 0],
            "X2 insert: from 50 left; got \(String(describing: offset(leading.start, from: leading.settled))), \(String(describing: offset(leading.mid, from: leading.settled)))")
    let trailing = insertion(.move(edge: .trailing))
    #expect(offset(trailing.mid, from: trailing.settled).map { [$0.0, $0.1] } == [25, 0],
            "X3 insert: from 50 right; got \(String(describing: offset(trailing.mid, from: trailing.settled)))")
    let top = insertion(.move(edge: .top))
    #expect(offset(top.mid, from: top.settled).map { [$0.0, $0.1] } == [0, -15],
            "X3t insert: from 30 up; got \(String(describing: offset(top.mid, from: top.settled)))")
    #expect(top.mid?.background.a == 1, "a move does not fade")

    let topOut = removal(.move(edge: .top))
    #expect(offset(topOut.start.first, from: topOut.rest).map { [$0.0, $0.1] } == [0, 0]
                && offset(topOut.mid.first, from: topOut.rest).map { [$0.0, $0.1] } == [0, -15],
            "X3t remove: toward 30 up; got \(topOut.start.map(describe)), \(topOut.mid.map(describe))")
    let bottomOut = removal(.move(edge: .bottom))
    #expect(offset(bottomOut.mid.first, from: bottomOut.rest).map { [$0.0, $0.1] } == [0, 15],
            "X3b remove: toward 30 down; got \(bottomOut.mid.map(describe))")
    #expect(topOut.end.isEmpty && bottomOut.end.isEmpty, "landed: both ghosts gone")
}

// MARK: - 3.4 (X5)

/// **3.4 (X5).** `.slide` enters from leading and leaves toward trailing:
/// inserting reads −25 half-way, removing +25. Red before: does not compile.
/// Mutation **M3.4**: remove toward leading.
@Test @MainActor func aSlideTransitionEntersLeadingAndLeavesTrailing() throws {
    let inserted = insertion(.slide)
    #expect(offset(inserted.mid, from: inserted.settled).map { [$0.0, $0.1] } == [-25, 0],
            "X5 insert: from leading; got \(String(describing: offset(inserted.mid, from: inserted.settled)))")
    let removed = removal(.slide)
    #expect(offset(removed.mid.first, from: removed.rest).map { [$0.0, $0.1] } == [25, 0],
            "X5 remove: toward trailing; got \(removed.mid.map(describe))")
}

// MARK: - 3.5 (X9, X10)

/// **3.5.** `.offset(x: 30, y: 5)` inserts from (30, 5): (15, 2.5) half-way
/// (X9). `.push(from: .leading)` inserts from leading AND fades in (alpha ½,
/// −25 half-way) and removes toward trailing fading out (alpha ½, +25) (X10).
/// Red before: does not compile. Mutation **M3.5**: drop `.push`'s opacity.
@Test @MainActor func offsetAndPushTransitions() throws {
    let offsetIn = insertion(.offset(x: Pixels(30), y: Pixels(5)))
    #expect(offset(offsetIn.mid, from: offsetIn.settled).map { [$0.0, $0.1] } == [15, 2.5],
            "X9: half-way at (15, 2.5); got \(String(describing: offset(offsetIn.mid, from: offsetIn.settled)))")
    let pushIn = insertion(.push(from: .leading))
    #expect(offset(pushIn.mid, from: pushIn.settled).map { [$0.0, $0.1] } == [-25, 0]
                && pushIn.mid?.background.a == 0.5,
            "X10 insert: from leading, fading in; got \(describe(pushIn.mid)) vs \(describe(pushIn.settled))")
    let pushOut = removal(.push(from: .leading))
    #expect(offset(pushOut.mid.first, from: pushOut.rest).map { [$0.0, $0.1] } == [25, 0]
                && pushOut.mid.first?.background.a == 0.5,
            "X10 remove: toward trailing, fading out; got \(pushOut.mid.map(describe))")
}

// MARK: - 3.6 (X6)

/// **3.6 (X6).** `.asymmetric(insertion: .opacity, removal: .move(edge:
/// .trailing))`: the insertion fades in place (alpha ½, no offset); the removal
/// moves without fading (+25, alpha 1). Red before: does not compile. Mutation
/// **M3.6**: swap insertion and removal.
@Test @MainActor func anAsymmetricTransitionUsesEachSide() throws {
    let t = AnyTransition.asymmetric(insertion: .opacity, removal: .move(edge: .trailing))
    let inserted = insertion(t)
    #expect(inserted.mid?.background.a == 0.5 && same(inserted.mid, inserted.settled),
            "insertion side: a fade in place; got \(describe(inserted.mid)) vs \(describe(inserted.settled))")
    let removed = removal(t)
    #expect(offset(removed.mid.first, from: removed.rest).map { [$0.0, $0.1] } == [25, 0]
                && removed.mid.first?.background.a == 1,
            "removal side: a move, no fade; got \(removed.mid.map(describe))")
}

// MARK: - 3.7 (X8)

/// **3.7 (X8).** `.opacity.combined(with: .move(edge: .bottom))` applies both:
/// half-way alpha ½ AND 15 down. Red before: does not compile. Mutation
/// **M3.7**: keep only the first.
@Test @MainActor func aCombinedTransitionAppliesBoth() throws {
    let r = insertion(.opacity.combined(with: .move(edge: .bottom)))
    #expect(r.mid?.background.a == 0.5 && offset(r.mid, from: r.settled).map { [$0.0, $0.1] } == [0, 15],
            "X8: alpha ½ and 15 down; got \(describe(r.mid)) vs \(describe(r.settled))")
}

// MARK: - 3.8 (X7)

/// **3.8 (X7).** `.identity` is instant both ways: the inserting frame paints
/// the tile at alpha 1 in place, the removing frame paints nothing. Red before:
/// does not compile. Mutation **M3.8**: treat identity as opacity.
@Test @MainActor func anIdentityTransitionIsInstant() throws {
    let inserted = insertion(.identity)
    #expect(inserted.start?.background.a == 1 && same(inserted.start, inserted.settled),
            "X7 insert: instant; got \(describe(inserted.start))")
    let removed = removal(.identity)
    #expect(removed.start.isEmpty, "X7 remove: instant; got \(removed.start.map(describe))")
}

// MARK: - 3.9 (X1n)

/// **3.9 (X1n).** `.transition(.opacity)` with no transaction is instant both
/// ways. Red before: does not compile. Mutation **M3.9**: default the animation.
@Test @MainActor func aTransitionWithoutATransactionIsInstant() throws {
    let inserted = insertion(.opacity, animation: nil)
    #expect(inserted.start?.background.a == 1, "X1n insert: instant; got \(describe(inserted.start))")
    let removed = removal(.opacity, animation: nil)
    #expect(removed.start.isEmpty, "X1n remove: instant; got \(removed.start.map(describe))")
}

// MARK: - 3.10 (X11, X12)

/// **3.10 (X11, X12).** A `ForEach` whose elements carry `.transition(.opacity)`:
/// the element [1, 2] → [1, 2, 3] adds fades in (alpha ½ half-way) while the
/// others stay at 1; the element [1, 2, 3] → [1, 3] drops leaves a ghost at its
/// last place (alpha ½ half-way) while element 3 moves up AT ONCE (divergence
/// 96's X00 half — SwiftUI slides it, −10). Elements are 10 × (10·i) tiles, so
/// each is told apart by its height. Red before: does not compile. Mutation
/// **M3.10**: skip the loop's insertion noting.
@Test @MainActor func forEachInsertionAndRemovalTransition() throws {
    func tree(_ items: [Int]) -> some Element {
        Column {
            ForEach(items, id: \.self) { i in tile(10, Float(10 * i)).transition(.opacity) }
        }
    }
    func tall(_ f: Frame, _ i: Int) -> [MUIRect] { accents(f).filter { $0.bounds.size.height == Float(10 * i) } }

    let h = TransitionHarness()
    h.frame(0, nil, tree([1, 2]))
    h.frame(0, linear1, tree([1, 2, 3]))
    let mid = h.frame(0.5, nil, tree([1, 2, 3]))
    #expect(tall(mid, 3).first?.background.a == 0.5, "X11: the added element fades in: \(tall(mid, 3).map(describe))")
    #expect(tall(mid, 1).first?.background.a == 1 && tall(mid, 2).first?.background.a == 1,
            "the elements already there do not fade")

    let r = TransitionHarness()
    let rest = r.frame(0, nil, tree([1, 2, 3]))
    let two = tall(rest, 2).first
    let threeBefore = tall(rest, 3).first
    let removing = r.frame(0, linear1, tree([1, 3]))
    let removingMid = r.frame(0.5, nil, tree([1, 3]))
    #expect(tall(removingMid, 2).count == 1 && same(tall(removingMid, 2).first, two)
                && tall(removingMid, 2).first?.background.a == 0.5,
            "X12: the dropped element's ghost fades at its last place: \(tall(removingMid, 2).map(describe))")
    if let before = threeBefore, let after = tall(removing, 3).first {
        #expect(after.bounds.origin.y < before.bounds.origin.y,
                "divergence 96: the next element moves at once on the removing frame (\(before.bounds.origin.y) → \(after.bounds.origin.y))")
    } else {
        Issue.record("element 3 did not paint")
    }
}

// MARK: - 3.11 (X13, X14)

/// **3.11 (X13, X14).** A transition runs on the transaction in effect AT ITS
/// CONDITIONAL, not at the group: `.animation(linear(1), value: flag)` on the
/// container animates the insertion with no root transaction (X13); a
/// `.transaction { $0.animation = nil }` written outside `.transition` INSIDE
/// the `if` does not stop it (X14). Red before: does not compile. Mutation
/// **M3.11**: read the transaction at the group — the X14 arm.
@Test @MainActor func aTransitionUsesTheTransactionAtItsConditional() throws {
    func x13(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().transition(.opacity) }
            }
            .animation(linear1, value: shown)
        }
    }
    let a = TransitionHarness()
    a.frame(0, nil, x13(false))
    a.frame(0, nil, x13(true))
    let x13mid = accent(a.frame(0.5, nil, x13(true)))
    #expect(x13mid?.background.a == 0.5, "X13: `.animation(_:value:)` on the container animates it; got \(describe(x13mid))")

    func x14(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().transition(.opacity).transaction { $0.animation = nil } }
            }
        }
    }
    let b = TransitionHarness()
    b.frame(0, nil, x14(false))
    b.frame(0, linear1, x14(true))
    let x14mid = accent(b.frame(0.5, nil, x14(true)))
    #expect(x14mid?.background.a == 0.5,
            "X14: a `.transaction` inside the `if` does not stop the conditional's transition; got \(describe(x14mid))")
}

// MARK: - 3.12 (X15, X15b)

/// **3.12 (X15, X15b).** Only the outermost group of inserted content
/// transitions: a `.transition` on a tile NESTED inside the inserted `Column`
/// is inert (X15 — the tile paints at alpha 1 on the inserting frame, MetalUI
/// having no default fade, divergence 98); with `.identity` on the inserted
/// column and `.move` on the nested tile, nothing moves (X15b). Red before:
/// does not compile. Mutation **M3.12**: let every group inside inserted
/// content transition.
@Test @MainActor func aNestedTransitionIsInert() throws {
    func x15(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { Column { tile().transition(.opacity) } }
            }
        }
    }
    let a = TransitionHarness()
    a.frame(0, nil, x15(false))
    let x15start = accent(a.frame(0, linear1, x15(true)))
    #expect(x15start?.background.a == 1, "X15: the nested transition is inert; got \(describe(x15start))")

    func x15b(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { Column { tile().transition(.move(edge: .leading)) }.transition(.identity) }
            }
        }
    }
    let b = TransitionHarness()
    b.frame(0, nil, x15b(false))
    let start = accent(b.frame(0, linear1, x15b(true)))
    let mid = accent(b.frame(0.5, nil, x15b(true)))
    let settled = accent(b.frame(2, nil, x15b(true)))
    #expect(same(start, settled) && same(mid, settled),
            "X15b: nothing moves; got \(describe(start)), \(describe(mid)) vs \(describe(settled))")
}

// MARK: - 3.13 (X0; divergence 98)

/// **3.13 (X0) — pinned WRONG ON PURPOSE (divergence 98).** SwiftUI cross-fades
/// an unannotated insertion and removal (X0); MetalUI has no default
/// transition: under `linear(1)` the tile appears at alpha 1 and vanishes at
/// once, and nothing is captured. Green before for its scene half (today's
/// answer); the capture counter does not compile before lane 3. Mutation
/// **M3.13**: give an unannotated conditional's content a default `.opacity`
/// transition (`AN-AH` item 6).
@Test @MainActor func anUnannotatedInsertionAndRemovalAreInstant() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile() }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    let start = accent(h.frame(0, linear1, tree(true)))
    #expect(start?.background.a == 1, "divergence 98: an unannotated insertion is instant; got \(describe(start))")
    h.frame(0.5, nil, tree(true))
    #expect(h.store.transitions.lastFrameCapturedPrimitives == 0, "an unannotated conditional captures nothing")
    let removing = h.frame(1, linear1, tree(false))
    #expect(accents(removing).isEmpty, "divergence 98: an unannotated removal is instant; got \(accents(removing).map(describe))")
    #expect(h.store.transitions.liveCount == 0, "nothing in flight")
}

// MARK: - 3.14 (R5…, R10)

/// **3.14 (R5, R5r, R5s, R5l, R5o, R5p, R5a, R5c, R5i; R10).** Under Reduce
/// Motion every transition but `.identity` is an opacity cross-fade on the same
/// animation: half-way alpha ½ at the FINAL place and size, never offset or
/// scaled — `.move` inserting and removing, `.scale`, `.slide`, `.offset`,
/// `.push`, `.asymmetric`, `.combined`; `.identity` stays instant. R10: the same
/// `.move` and `.scale` with the reader false offset and scale again. Red
/// before: does not compile. Mutations **M3.14a**: no substitution; **M3.14b**:
/// substitute `.identity` too.
@Test @MainActor func underReduceMotionEveryTransitionButIdentityIsAnOpacityFade() throws {
    let cases: [(String, AnyTransition)] = [
        ("move", .move(edge: .leading)), ("scale", .scale), ("slide", .slide),
        ("offset", .offset(x: Pixels(30), y: Pixels(5))), ("push", .push(from: .leading)),
        ("asymmetric", .asymmetric(insertion: .move(edge: .top), removal: .scale)),
        ("combined", .opacity.combined(with: .move(edge: .bottom))),
    ]
    for (name, t) in cases {
        let r = insertion(t, reduceMotion: true)
        #expect(r.mid?.background.a == 0.5 && same(r.mid, r.settled),
                "R5 \(name) insert: a fade in place; got \(describe(r.mid)) vs \(describe(r.settled))")
    }
    let moveOut = removal(.move(edge: .leading), reduceMotion: true)
    #expect(moveOut.mid.count == 1 && same(moveOut.mid.first, moveOut.rest) && moveOut.mid.first?.background.a == 0.5,
            "R5r move remove: a fade in place; got \(moveOut.mid.map(describe))")
    let identity = insertion(.identity, reduceMotion: true)
    #expect(identity.start?.background.a == 1, "R5i: identity stays instant; got \(describe(identity.start))")
    let identityOut = removal(.identity, reduceMotion: true)
    #expect(identityOut.start.isEmpty, "R5i: identity removal stays instant")

    // R10: the reader false — the same spellings move and scale again.
    let moveControl = insertion(.move(edge: .leading))
    #expect(offset(moveControl.mid, from: moveControl.settled).map { [$0.0, $0.1] } == [-25, 0],
            "R10: without Reduce Motion `.move` offsets; got \(describe(moveControl.mid))")
    let scaleControl = insertion(.scale)
    #expect(scaleControl.mid?.bounds.size.width == 25, "R10: without Reduce Motion `.scale` scales; got \(describe(scaleControl.mid))")
}

// MARK: - 3.15

/// **3.15.** Through a real `Window`: an insertion and a removal each keep the
/// display link awake until they land (`hasActiveAnimations`), then leave
/// nothing in flight, and the link pauses. Red before: does not compile.
/// Mutation **M3.15**: omit `noteActiveAnimation()`.
@Test @MainActor func aTransitionKeepsTheDisplayLinkAwakeThenLeavesNothing() throws {
    let model = TransitionModel()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 300, startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if model.shown { tile().transition(.opacity) }
            }
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(!window.hasActiveAnimations, "set up: nothing live at rest")
    withAnimation(.linear(duration: 1)) { model.shown = true }
    platform.simulateTick(timestamp: 100.1)
    #expect(window.hasActiveAnimations, "the inserting frame is live")
    platform.simulateTick(timestamp: 100.6)
    #expect(window.hasActiveAnimations, "the insertion half-way is live")
    platform.simulateTick(timestamp: 101.2)
    #expect(!window.hasActiveAnimations && window.animationStore.transitions.liveCount == 0,
            "the insertion landed: nothing live")

    withAnimation(.linear(duration: 1)) { model.shown = false }
    platform.simulateTick(timestamp: 102)
    #expect(window.hasActiveAnimations, "the removing frame is live (its ghost)")
    platform.simulateTick(timestamp: 102.5)
    #expect(window.hasActiveAnimations && window.lastScene.rects.contains { isAccent($0.background) },
            "the ghost half-way is live and painted")
    platform.simulateTick(timestamp: 103.1)
    #expect(!window.hasActiveAnimations && window.animationStore.transitions.liveCount == 0,
            "the removal landed: nothing live, no ghost left")
    platform.simulateTick(timestamp: 103.2)
    #expect(platform.pauseCalls.last == true, "the display link pauses once both have landed")
}

@Observable @MainActor final class TransitionModel {
    var shown = false
}

// MARK: - 3.16

/// **3.16.** A tree without `.transition` captures nothing: `demoContent()`
/// through a real `Window` reads 0 captured primitives. A fixture with one
/// transitioning 50 × 30 tile beside an unannotated sibling captures exactly
/// the tile's one rect. Red before: does not compile. Mutation **M3.16**:
/// capture at every element.
@Test @MainActor func aTreeWithoutTransitionsCapturesNothing() throws {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 900, startsDisplayLink: true) { demoContent() }
    platform.simulateTick(timestamp: 1)
    try #require(!window.lastScene.rects.isEmpty, "set up: the demo painted")
    #expect(window.animationStore.transitions.lastFrameCapturedPrimitives == 0,
            "the demo has no `.transition`, so it captures nothing: \(window.animationStore.transitions.lastFrameCapturedPrimitives)")

    let h = TransitionHarness()
    let f = h.frame(0, nil, Column {
        Box().frame(width: Pixels(20), height: Pixels(20)).background(.surface)
        if true { tile().transition(.opacity) }
    })
    try #require(f.scene.rects.count == 2, "set up: the fixture paints two rects, got \(f.scene.rects.count)")
    #expect(h.store.transitions.lastFrameCapturedPrimitives == 1,
            "exactly the transitioning group's one rect is captured: \(h.store.transitions.lastFrameCapturedPrimitives)")
}

// MARK: - 3.17

/// **3.17.** A `List` row whose content holds a `.transition(.opacity)`ed `if`
/// scrolled OUT of its window under `linear(1)` runs no removal transition: the
/// row is not evaluated (`TB-AH`), so nothing is removed and no ghost exists.
/// Red before: does not compile. Mutation **M3.17**: ghost any group not
/// produced this frame.
@Test @MainActor func aListRowScrolledOutOfItsWindowRunsNoRemovalTransition() throws {
    let h = TransitionHarness()
    let data = (0..<12).map { TransitionRow(id: "row\($0)") }
    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data, rowHeight: Pixels(20)) { item in
            Box { if true { tile(10, 10).transition(.opacity) } }
        }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    func render(_ t: Double, _ animation: Animation?, offset: Double?) {
        if let offset {
            let current = h.table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            h.table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                  viewportExtent: current.viewportExtent))
        }
        Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1, stateTable: h.table,
              timestamp: t, transaction: animation, animationStore: h.store).render(&tree)
    }
    render(0, nil, offset: nil)
    render(0, nil, offset: 0)
    render(0, nil, offset: 0)
    try #require(h.store.transitions.lastFrameCapturedPrimitives > 0, "set up: the windowed rows' groups capture")
    render(0, linear1, offset: 160)     // rows 0–2 leave the window
    render(0.2, linear1, offset: 160)
    #expect(h.store.transitions.ghostCount == 0,
            "a row scrolled out of its window is not a removal: \(h.store.transitions.ghostCount) ghosts")
}

// MARK: - 3.18

/// **3.18.** An inserting element is hit-tested at its FINAL place: half-way
/// through a `.move(edge: .leading)` insertion the tile paints 25 left of its
/// place while its hitbox sits exactly at the place. Red before: does not
/// compile. Mutation **M3.18**: translate its hitboxes.
@Test @MainActor func anInsertingElementIsHitTestedAtItsFinalPlace() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().onClick {}.transition(.move(edge: .leading)) }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    h.frame(0, linear1, tree(true))
    let mid = h.frame(0.5, nil, tree(true))
    let settled = accent(h.frame(2, nil, tree(true)))
    let painted = accent(mid)
    let hitbox = mid.hitboxes.first { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 }
    try #require(settled != nil && painted != nil && hitbox != nil, "set up: tile, painted and hitbox")
    #expect(offset(painted, from: settled).map { [$0.0, $0.1] } == [-25, 0], "the paint is mid-flight: \(describe(painted))")
    #expect(hitbox.map { $0.bounds.origin.x.value } == settled.map { $0.bounds.origin.x }
                && hitbox.map { $0.bounds.origin.y.value } == settled.map { $0.bounds.origin.y },
            "the hitbox is at the final place: \(String(describing: hitbox?.bounds)) vs \(describe(settled))")
}

// MARK: - 3.20 (`AN-AH` item 4)

/// **3.20.** `TransitionGroup` takes NO identity level: adding `.transition`
/// around a `@State`-holding element keeps its state and its id — a legacy
/// counter in a `Column` (the untyped entry) and a proposal counter in an
/// `HStack` (the typed entry) each read 3 after two frames without and one with.
/// Red before: does not compile. Mutations **M3.20a**: give the group an
/// identity level (the legacy arm); **M3.20b**: the same in the typed entry
/// only (the proposal arm).
@Test @MainActor func aTransitionTakesNoIdentityLevel() throws {
    let reads = ConditionalReads()
    let table = StateTable()
    var ids: [GlobalElementID?] = []
    for withTransition in [false, false, true] {
        if withTransition {
            var tree = Column { ConditionalCounter("c", reads).transition(.opacity) }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1, stateTable: table).render(&tree)
        } else {
            var tree = Column { ConditionalCounter("c", reads) }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1, stateTable: table).render(&tree)
        }
        ids.append(reads.ids["c"])
    }
    #expect(reads.values["c"] == 3, "legacy: adding `.transition` keeps the counter's state; read \(String(describing: reads.values["c"]))")
    #expect(ids[2] == ids[0], "legacy: and its id")

    let preads = ConditionalReads()
    let ptable = StateTable()
    var pids: [GlobalElementID?] = []
    for withTransition in [false, false, true] {
        if withTransition {
            var tree = HStack { ProposalConditionalCounter("p", preads).transition(.opacity) }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1, stateTable: ptable).render(&tree)
        } else {
            var tree = HStack { ProposalConditionalCounter("p", preads) }
            Frame(contentSize: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1, stateTable: ptable).render(&tree)
        }
        pids.append(preads.ids["p"])
    }
    #expect(preads.values["p"] == 3, "proposal: adding `.transition` keeps the counter's state; read \(String(describing: preads.values["p"]))")
    #expect(pids[2] == pids[0], "proposal: and its id")
}

// MARK: - 3.21

/// **3.21.** A removal during an insertion starts its ghost from the
/// insertion's CURRENT progress (MetalUI's own rule, unprobed): an `.opacity`
/// insertion under `linear(1)` removed half-way (alpha ½) starts its ghost at
/// ½ and reads ¼ half-way through the removal's own `linear(1)`, gone at its
/// end. Red before: does not compile. Mutation **M3.21**: restart the ghost
/// from the removal's start value.
@Test @MainActor func aRemovalDuringAnInsertionStartsFromItsCurrentProgress() throws {
    let h = TransitionHarness()
    h.frame(0, nil, stage(false, .opacity))
    h.frame(0, linear1, stage(true, .opacity))
    let halfIn = accent(h.frame(0.5, nil, stage(true, .opacity)))
    try #require(halfIn?.background.a == 0.5, "set up: half-way in, got \(describe(halfIn))")
    let start = accents(h.frame(0.5, linear1, stage(false, .opacity)))
    let mid = accents(h.frame(1.0, nil, stage(false, .opacity)))
    let end = accents(h.frame(1.5, nil, stage(false, .opacity)))
    #expect(start.first?.background.a == 0.5 && mid.first?.background.a == 0.25 && end.isEmpty,
            "the ghost continues from ½: ½ → ¼ → gone; got \(start.map(describe)), \(mid.map(describe)), \(end.map(describe))")
}

// MARK: - 3.22 (X17, X17c)

/// **3.22 (X17, X17c; `AN-AH` item 2).** Content present in the FIRST render —
/// under a `.transaction` that forces an animation — runs no insertion (X17);
/// nor does content under a newly evaluated parent (an inner `if` inserted with
/// its outer one), nor a `List` row's `.transition`ed `if` scrolled INTO its
/// window. X17c separates: the same tree with the flag turned on after it
/// appeared fades in. Red before: does not compile. Mutation **M3.22**: treat
/// "not produced last frame" as an insertion without the evaluated-last-frame
/// check — the frame-0 and `List` arms.
@Test @MainActor func contentInTheFirstRenderOrANewlyEvaluatedParentIsNotInserted() throws {
    func x17(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().transition(.opacity) }
            }
            .transaction { $0.animation = linear1 }
        }
    }
    let first = TransitionHarness()
    let x17start = accent(first.frame(0, nil, x17(true)))
    #expect(x17start?.background.a == 1, "X17: the first render inserts nothing; got \(describe(x17start))")

    let control = TransitionHarness()
    control.frame(0, nil, x17(false))
    control.frame(0, nil, x17(true))
    let x17c = accent(control.frame(0.5, nil, x17(true)))
    #expect(x17c?.background.a == 0.5, "X17c: turned on after appearing, it fades in; got \(describe(x17c))")

    func nested(_ outer: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if outer { Column { if true { tile().transition(.opacity) } } }
            }
        }
    }
    let n = TransitionHarness()
    n.frame(0, nil, nested(false))
    let nestedStart = accent(n.frame(0, linear1, nested(true)))
    #expect(nestedStart?.background.a == 1, "an inner `if` inserted with its parent is not an insertion; got \(describe(nestedStart))")

    // The `List` arm: rows 6–8 enter the window; their `if` is newly evaluated.
    let l = TransitionHarness()
    let data = (0..<12).map { TransitionRow(id: "row\($0)") }
    var list = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data, rowHeight: Pixels(20)) { item in
            Box { if true { tile(10, 10).transition(.opacity) } }
        }
        .transaction { $0.animation = linear1 }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    func render(_ t: Double, offset: Double?) -> Frame {
        if let offset {
            let current = l.table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            l.table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                  viewportExtent: current.viewportExtent))
        }
        let f = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1, stateTable: l.table,
                      timestamp: t, animationStore: l.store)
        f.render(&list)
        return f
    }
    _ = render(0, offset: nil)
    _ = render(0, offset: 0)
    _ = render(0, offset: 0)
    _ = render(0, offset: 120)
    let scrolled = render(0.1, offset: 120)
    let tiles = accents(scrolled)
    try #require(!tiles.isEmpty, "set up: the scrolled window paints its rows' tiles")
    #expect(tiles.allSatisfy { $0.background.a == 1 },
            "a row entering its window is not an insertion: \(tiles.map(describe))")
}

// MARK: - 3.23

/// **3.23.** Every recording copy notes its evaluation and transaction: an
/// `.opacity` insertion reads alpha ½ half-way through each of the eight —
/// `OptionalGroup` and `EitherGroup` untyped (in a `Column`) and typed (in an
/// `HStack`), `ArrayGroup` untyped and typed (a `for` loop growing), `ForEach`'s
/// untyped and typed entries (its data growing). Red before: does not compile.
/// Mutation **M3.23**: skip the note in the typed `ArrayGroup` — exactly its arm.
@Test @MainActor func everyConditionalSiteRecordsItsTransaction() throws {
    func run<E: Element>(_ name: String, _ tree: (Bool) -> E) {
        let h = TransitionHarness()
        h.frame(0, nil, tree(false))
        h.frame(0, linear1, tree(true))
        let mid = h.frame(0.5, nil, tree(true))
        let faded = accents(mid).filter { $0.background.a == 0.5 }
        #expect(faded.count == 1, "\(name): one tile half-faded, got \(accents(mid).map(describe))")
    }
    func proposalTile() -> some ProposalElementGroup {
        Rectangle(width: Pixels(50), height: Pixels(30)).background(.accent)
    }
    run("OptionalGroup untyped") { on in Column { if on { tile().transition(.opacity) } } }
    run("OptionalGroup typed") { on in HStack { if on { proposalTile().transition(.opacity) } } }
    run("EitherGroup untyped") { on in
        Column { if on { tile().transition(.opacity) } else { Box().frame(width: Pixels(5), height: Pixels(5)) } }
    }
    run("EitherGroup typed") { on in
        HStack { if on { proposalTile().transition(.opacity) } else { Rectangle(width: Pixels(5), height: Pixels(5)) } }
    }
    func untypedLoop(_ on: Bool) -> some Element {
        let items: [Int] = on ? [1, 2] : [1]
        return Column {
            for i in items {
                Box().frame(width: Pixels(10), height: Pixels(Float(10 * i))).background(.accent).transition(.opacity)
            }
        }
    }
    func typedLoop(_ on: Bool) -> some Element {
        let items: [Int] = on ? [1, 2] : [1]
        return HStack {
            for i in items { Rectangle(width: Pixels(10), height: Pixels(Float(10 * i))).background(.accent).transition(.opacity) }
        }
    }
    run("ArrayGroup untyped", untypedLoop)
    run("ArrayGroup typed", typedLoop)
    run("ForEach untyped") { on in
        Column { ForEach(on ? [1, 2] : [1], id: \.self) { i in tile(10, Float(10 * i)).transition(.opacity) } }
    }
    run("ForEach typed") { on in
        HStack { ForEach(on ? [1, 2] : [1], id: \.self) { i in Rectangle(width: Pixels(10), height: Pixels(Float(10 * i))).background(.accent).transition(.opacity) } }
    }
}

// MARK: - 3.24 (X4, X4a)

/// **3.24 (X4, X4a; `AN-AH` item 1).** `.scale` post-transforms what the group
/// emits: half-way through a `.scale` insertion the 50 × 30 tile paints 25 × 15
/// about its CENTRE, and its glyph child paints at half its landed size about
/// the same point; `.scale(scale: 0.5, anchor: .topLeading)` reads 37.5 × 22.5
/// at its top-left corner. A clip in effect at the group's entry (the outer
/// `.clipped()` container) stays as it is; a clip set INSIDE the group (the
/// tile's own `.clipped()`) scales with its content. Hitboxes are not scaled.
/// Red before: does not compile. Mutations **M3.24a**: scale about the
/// container's rect; **M3.24b**: scale the entry clip too.
@Test @MainActor func aScaleTransitionScalesTheGroupsPrimitivesAboutItsAnchor() throws {
    func tree(_ shown: Bool, _ t: AnyTransition) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown {
                    Stack { Text("M") }
                        .frame(width: Pixels(50), height: Pixels(30)).background(.accent)
                        .onClick {}.transition(t)
                }
            }
            .frame(width: Pixels(200), height: Pixels(100)).clipped()
        }
    }
    func tileRect(_ f: Frame) -> MUIRect? { f.scene.rects.first { isAccent($0.background) } }

    let h = TransitionHarness()
    h.frame(0, nil, tree(false, .scale))
    h.frame(0, linear1, tree(true, .scale))
    let midFrame = h.frame(0.5, nil, tree(true, .scale))
    let settledFrame = h.frame(2, nil, tree(true, .scale))
    let mid = tileRect(midFrame), settled = tileRect(settledFrame)
    try #require(mid != nil && settled != nil, "set up: the tile paints")
    if let mid, let settled {
        let cx: Float = settled.bounds.origin.x + 25
        let cy: Float = settled.bounds.origin.y + 15
        let sized: Bool = mid.bounds.size.width == 25 && mid.bounds.size.height == 15
        let centred: Bool = mid.bounds.origin.x == cx - 12.5 && mid.bounds.origin.y == cy - 7.5
        #expect(sized && centred,
                "X4: half-way the tile is 25 × 15 about its centre; got \(describe(mid)) vs \(describe(settled))")
        let maskKept: Bool = mid.contentMask.size.width == settled.contentMask.size.width
            && mid.contentMask.origin.x == settled.contentMask.origin.x
        #expect(maskKept,
                "the entry clip (the outer container's) is not scaled: \(String(describing: mid.contentMask)) vs \(String(describing: settled.contentMask))")
    }
    let glyphMid = midFrame.scene.glyphs.first, glyphSettled = settledFrame.scene.glyphs.first
    try #require(glyphMid != nil && glyphSettled != nil, "set up: the glyph child paints")
    if let g = glyphMid, let s = glyphSettled, let settled {
        let cx: Float = settled.bounds.origin.x + 25
        let cy: Float = settled.bounds.origin.y + 15
        let halfSize: Bool = abs(g.bounds.size.width - s.bounds.size.width / 2) < 0.001
        let expectedX: Float = cx + (s.bounds.origin.x - cx) / 2
        let expectedY: Float = cy + (s.bounds.origin.y - cy) / 2
        let aboutCentre: Bool = abs(g.bounds.origin.x - expectedX) < 0.001 && abs(g.bounds.origin.y - expectedY) < 0.001
        #expect(halfSize && aboutCentre,
                "the glyph scales ½ about the same centre: \(String(describing: g.bounds)) vs \(String(describing: s.bounds))")
        #expect(g.atlasBounds.size.width == s.atlasBounds.size.width, "the glyph resamples the same atlas slot")
    }
    #expect(midFrame.hitboxes.contains { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 },
            "the hitbox is not scaled")

    // The inner clip: the tile's own `.clipped()` scales with its content.
    func clippedTree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown {
                    Stack { tile(80, 10) }.frame(width: Pixels(50), height: Pixels(30)).clipped().transition(.scale)
                }
            }
        }
    }
    let c = TransitionHarness()
    c.frame(0, nil, clippedTree(false))
    c.frame(0, linear1, clippedTree(true))
    let clipMid = accent(c.frame(0.5, nil, clippedTree(true)))
    let clipSettled = accent(c.frame(2, nil, clippedTree(true)))
    if let m = clipMid, let s = clipSettled {
        let maskScaled: Bool = m.contentMask.size.width == s.contentMask.size.width / 2
            && m.contentMask.size.height == s.contentMask.size.height / 2
        #expect(maskScaled,
                "a clip set inside the group scales with it: \(String(describing: m.contentMask)) vs \(String(describing: s.contentMask))")
    } else {
        Issue.record("the clipped tile did not paint: \(describe(clipMid)), \(describe(clipSettled))")
    }

    // X4a: 0.5 at the top-leading corner, half-way → 0.75.
    let a = TransitionHarness()
    let anchored = AnyTransition.scale(scale: 0.5, anchor: .topLeading)
    a.frame(0, nil, tree(false, anchored))
    a.frame(0, linear1, tree(true, anchored))
    let aMid = tileRect(a.frame(0.5, nil, tree(true, anchored)))
    let aSettled = tileRect(a.frame(2, nil, tree(true, anchored)))
    #expect(aMid?.bounds.size.width == 37.5 && aMid?.bounds.size.height == 22.5
                && aMid?.bounds.origin.x == aSettled?.bounds.origin.x && aMid?.bounds.origin.y == aSettled?.bounds.origin.y,
            "X4a: 37.5 × 22.5 at the top-left corner; got \(describe(aMid)) vs \(describe(aSettled))")
}

// MARK: - Fix round: the rich tile (every primitive kind a transition touches)

/// A 4 × 4 opaque white bitmap for the rich tile's image.
private let transitionBitmap = ImageBitmap(width: 4, height: 4, rgba: [UInt8](repeating: 255, count: 64))

/// The 50 × 30 accent tile carrying every primitive kind `AnyTransition`'s doc
/// comment names: a glyph, an image, a 4-point `separator` border and a
/// 6-point corner radius on its accent rect.
@MainActor private func richTile() -> some StyledElement {
    Stack {
        Text("M")
        Image(decorative: transitionBitmap, scale: 1)
    }
    .frame(width: Pixels(50), height: Pixels(30)).background(.accent)
    .border(.separator, width: Pixels(4)).cornerRadius(Pixels(6))
}

@MainActor private func richStage(_ shown: Bool, _ transition: AnyTransition) -> some Element {
    Column {
        Stack {
            Box().frame(width: Pixels(200), height: Pixels(100))
            if shown { richTile().transition(transition) }
        }
    }
}

/// One rich frame's primitives of interest.
private struct RichPaint {
    var tile: MUIRect?
    var border: MUIRect?
    var glyphs: [MUIGlyph]
    var images: [MUIImage]
}

/// The one rect `frame` painted with a border, or `nil` when it painted none or several.
@MainActor private func border(_ f: Frame) -> MUIRect? {
    let all = f.scene.rects.filter { $0.borderWidths.top > 0 }
    return all.count == 1 ? all[0] : nil
}

private func sameBounds(_ a: MUIBounds, _ b: MUIBounds) -> Bool {
    a.origin.x == b.origin.x && a.origin.y == b.origin.y && a.size.width == b.size.width && a.size.height == b.size.height
}

@MainActor private func richPaint(_ f: Frame) -> RichPaint {
    RichPaint(tile: accent(f), border: border(f), glyphs: f.scene.glyphs, images: f.scene.images)
}

// MARK: - 3.25

/// **3.25 (fix round, V1, V2, V3, V13).** `.opacity` multiplies EVERY
/// primitive's alpha, not only a rect's background: half-way through an
/// insertion of the rich tile its glyph's colour alpha, its image's opacity and
/// its border colour's alpha are each half their settled value. A removal's
/// ghost replays the content's last painted primitives of EVERY kind: half-way
/// through the removal the ghost still paints the glyph and the image, at half
/// alpha, at their last place. Mutations **V1** (a glyph does not fade), **V2**
/// (an image does not fade), **V3** (a border colour does not fade), **V13** (a
/// ghost captures only rects).
@Test @MainActor func anOpacityTransitionFadesEveryPrimitiveKindAndTheGhostReplaysThemAll() throws {
    let h = TransitionHarness()
    h.frame(0, nil, richStage(false, .opacity))
    h.frame(0, linear1, richStage(true, .opacity))
    let mid = richPaint(h.frame(0.5, nil, richStage(true, .opacity)))
    let settled = richPaint(h.frame(2, nil, richStage(true, .opacity)))
    try #require(settled.tile != nil && settled.border != nil && settled.glyphs.count == 1 && settled.images.count == 1,
                 "set up: the settled tile paints its fill, its border, one glyph and one image: \(describe(settled.tile)), \(describe(settled.border)), \(settled.glyphs.count), \(settled.images.count)")
    let settledGlyphA = settled.glyphs[0].color.a, settledImageA = settled.images[0].opacity
    let settledBorderA = settled.border!.borderColor.a
    try #require(settledGlyphA > 0 && settledImageA > 0 && settledBorderA > 0,
                 "set up: every settled alpha is non-zero, or halving proves nothing: \(settledGlyphA), \(settledImageA), \(settledBorderA)")
    #expect(mid.glyphs.count == 1 && mid.glyphs.first?.color.a == settledGlyphA / 2,
            "V1: the glyph fades with the group: \(mid.glyphs.map(\.color.a)) vs \(settledGlyphA)")
    #expect(mid.images.count == 1 && mid.images.first?.opacity == settledImageA / 2,
            "V2: the image fades with the group: \(mid.images.map(\.opacity)) vs \(settledImageA)")
    #expect(mid.border?.borderColor.a == settledBorderA / 2,
            "V3: the border colour fades with the group: \(String(describing: mid.border?.borderColor.a)) vs \(settledBorderA)")

    // Removal: the ghost replays the glyph and the image too.
    let r = TransitionHarness()
    let rest = richPaint(r.frame(0, nil, richStage(true, .opacity)))
    try #require(rest.glyphs.count == 1 && rest.images.count == 1, "set up: the live tile paints its glyph and image")
    r.frame(0, linear1, richStage(false, .opacity))
    let ghost = richPaint(r.frame(0.5, nil, richStage(false, .opacity)))
    #expect(ghost.glyphs.count == 1 && ghost.glyphs.first.map { sameBounds($0.bounds, rest.glyphs[0].bounds) } == true
                && ghost.glyphs.first?.color.a == rest.glyphs[0].color.a / 2,
            "V13: the ghost paints the glyph at its last place, half faded: \(ghost.glyphs.map { ($0.bounds, $0.color.a) })")
    #expect(ghost.images.count == 1 && ghost.images.first.map { sameBounds($0.bounds, rest.images[0].bounds) } == true
                && ghost.images.first?.opacity == rest.images[0].opacity / 2,
            "V13: the ghost paints the image at its last place, half faded: \(ghost.images.map { ($0.bounds, $0.opacity) })")
    #expect(ghost.border?.borderColor.a == rest.border.map { $0.borderColor.a / 2 },
            "the ghost's border colour fades too: \(String(describing: ghost.border?.borderColor.a))")
}

// MARK: - 3.26

/// **3.26 (fix round, V11, V12).** `.scale` scales a rect's corner radii and
/// border widths with its bounds: half-way through a `.scale` insertion (scale
/// ½) the rich tile's 6-point radii read 3 and its 4-point border widths 2, on
/// every corner and edge. Mutations **V11** (radii not scaled), **V12** (border
/// widths not scaled).
@Test @MainActor func aScaleTransitionScalesCornerRadiiAndBorderWidths() throws {
    let h = TransitionHarness()
    h.frame(0, nil, richStage(false, .scale))
    h.frame(0, linear1, richStage(true, .scale))
    let midFrame = h.frame(0.5, nil, richStage(true, .scale))
    let settledFrame = h.frame(2, nil, richStage(true, .scale))
    let (m, s) = (try #require(accent(midFrame)), try #require(accent(settledFrame)))
    let (mb, sb) = (try #require(border(midFrame)), try #require(border(settledFrame)))
    try #require(s.cornerRadii.topLeft == 6 && sb.borderWidths.top == 4,
                 "set up: the settled tile has 6-point radii and 4-point borders: \(s.cornerRadii), \(sb.borderWidths)")
    #expect(m.bounds.size.width == 25, "set up: half-way the tile is scaled ½: \(describe(m))")
    let radii = [m.cornerRadii.topLeft, m.cornerRadii.topRight, m.cornerRadii.bottomRight, m.cornerRadii.bottomLeft]
    #expect(radii == [3, 3, 3, 3], "V11: the corner radii scale ½: \(radii)")
    let widths = [mb.borderWidths.top, mb.borderWidths.right, mb.borderWidths.bottom, mb.borderWidths.left]
    #expect(widths == [2, 2, 2, 2], "V12: the border widths scale ½: \(widths)")
}

// MARK: - 3.27

/// **3.27 (fix round, V4).** At scale factor 2 a transition's displacement is in
/// device pixels: `.offset(x: 30, y: 5)`'s point offset is (60, 10) device
/// pixels, so half-way through an insertion the tile sits
/// (30, 5) px from its settled place, and a removal half-way reads the same;
/// `.move(edge: .leading)`'s own-size displacement (50 pt = 100 px) reads −50 px
/// half-way. Mutation **V4** (`x * scaleFactor` → `x`, likewise y) halves the
/// offset arms.
@Test @MainActor func aTransitionsDisplacementIsInDevicePixelsAtScaleFactorTwo() throws {
    let offsetIn = insertion(.offset(x: Pixels(30), y: Pixels(5)), scaleFactor: 2)
    try #require(offsetIn.settled?.bounds.size.width == 100, "set up: the tile is 100 px wide at 2x: \(describe(offsetIn.settled))")
    #expect(offset(offsetIn.mid, from: offsetIn.settled).map { [$0.0, $0.1] } == [30, 5],
            "V4: (30, 5) pt is (60, 10) px, half-way (30, 5) px; got \(String(describing: offset(offsetIn.mid, from: offsetIn.settled)))")
    let offsetOut = removal(.offset(x: Pixels(30), y: Pixels(5)), scaleFactor: 2)
    #expect(offset(offsetOut.mid.first, from: offsetOut.rest).map { [$0.0, $0.1] } == [30, 5],
            "V4: the removal's ghost half-way at (30, 5) px; got \(offsetOut.mid.map(describe))")
    let moveIn = insertion(.move(edge: .leading), scaleFactor: 2)
    #expect(offset(moveIn.mid, from: moveIn.settled).map { [$0.0, $0.1] } == [-50, 0],
            "`.move` at 2x: 100 px own width, half-way −50 px; got \(String(describing: offset(moveIn.mid, from: moveIn.settled)))")
}

// MARK: - 3.28

/// **3.28 (fix round, V5; the mirror of 3.21).** An insertion during a removal
/// starts from the ghost's CURRENT progress (MetalUI's own rule, unprobed): an
/// `.opacity` removal under `linear(1)` re-inserted half-way (ghost alpha ½)
/// paints the live tile at ½ — not 0 — with the ghost gone, ¾ half-way through
/// the insertion's own `linear(1)`, and 1 at its end. Mutation **V5**
/// (`let from: Double = 1`).
@Test @MainActor func anInsertionDuringARemovalStartsFromTheGhostsProgress() throws {
    let h = TransitionHarness()
    h.frame(0, nil, stage(true, .opacity))
    h.frame(0, linear1, stage(false, .opacity))
    let halfOut = accents(h.frame(0.5, nil, stage(false, .opacity)))
    try #require(halfOut.count == 1 && halfOut[0].background.a == 0.5, "set up: the ghost half-way out, got \(halfOut.map(describe))")
    let start = accents(h.frame(0.5, linear1, stage(true, .opacity)))
    let mid = accents(h.frame(1.0, nil, stage(true, .opacity)))
    let end = accents(h.frame(1.5, nil, stage(true, .opacity)))
    #expect(start.count == 1 && start.first?.background.a == 0.5,
            "the insertion continues from the ghost's ½, and the ghost is gone: \(start.map(describe))")
    #expect(mid.count == 1 && mid.first?.background.a == 0.75 && end.count == 1 && end.first?.background.a == 1,
            "½ → ¾ → 1; got \(mid.map(describe)), \(end.map(describe))")
}

// MARK: - 3.29

/// **3.29 (fix round, V8; `AN-AK` item 4).** Of two `.transition`s stacked at
/// one position the OUTER applies (MetalUI's choice, unprobed):
/// `tile().transition(.opacity).transition(.move(edge: .leading))` inserts by
/// moving from leading (−25 half-way) at alpha 1 — no fade. Mutation **V8**
/// (drop `claim`'s `records[key] == nil` guard, so the inner claims last).
@Test @MainActor func theOuterOfTwoStackedTransitionsApplies() throws {
    func tree(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().transition(.opacity).transition(.move(edge: .leading)) }
            }
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(false))
    h.frame(0, linear1, tree(true))
    let mid = accent(h.frame(0.5, nil, tree(true)))
    let settled = accent(h.frame(2, nil, tree(true)))
    try #require(settled != nil, "set up: the settled tile paints")
    #expect(offset(mid, from: settled).map { [$0.0, $0.1] } == [-25, 0] && mid?.background.a == 1,
            "the outer `.move` applies and the inner `.opacity` does not: \(describe(mid)) vs \(describe(settled))")
}

// MARK: - 3.30

/// **3.30 (fix round; `AN-AK` item 9).** `.id(_:)` written OUTSIDE `.transition`
/// on an `if`'s content makes the transition inert — documented as unsupported
/// on `AnyTransition`: `IdentifiedGroup` numbers its content under the named
/// id, so the `TransitionGroup`'s parent is no longer the conditional's unit.
/// Pinned so that a change to it is seen: the insertion is instant (alpha 1 on
/// its first frame), while the same tile with `.id` INSIDE `.transition` fades.
@Test @MainActor func anIDWrittenOutsideTheTransitionMakesItInert() throws {
    func outside(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().transition(.opacity).id("x") }
            }
        }
    }
    func inside(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                if shown { tile().id("x").transition(.opacity) }
            }
        }
    }
    let o = TransitionHarness()
    o.frame(0, nil, outside(false))
    let outsideStart = accent(o.frame(0, linear1, outside(true)))
    let i = TransitionHarness()
    i.frame(0, nil, inside(false))
    let insideStart = accent(i.frame(0, linear1, inside(true)))
    #expect(insideStart?.background.a == 0, "control: `.id` inside `.transition` fades from 0; got \(describe(insideStart))")
    #expect(outsideStart?.background.a == 1, "`.id` outside `.transition`: inert, instant; got \(describe(outsideStart))")
}
