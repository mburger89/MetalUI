import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 2 (`SB-AD`, `SB-O`): the subtree placement memo through a real `Window`, on the bracket
// window's node drag. Kernel pins are `MetalUILayoutTests/SubtreePlacementTests.swift`. Counts and
// values, never time. The retained switch (`testingRetainedSubtrees`) is also the placement marks'
// switch, so `retained: false` is the memo-off arm of every differential here.

/// Prediction recorded before the first run (spec §10): of the 32 `.equatable()` occurrences on
/// the fixture's drag frame, only the dragged node and the two wires whose end it carries move or
/// resize; every other marked root stands where it stood with an equal proposal, so most of the
/// 29 unmoved ones restore: "at least 15". **The first run read 11 and the prediction was wrong**: 11
/// of the 20 nodes are on screen (the canvas cull), ten of them unmoved, and the library `List`
/// (`WindowedRowsLayout`, not `Hashable`), the inspector (`Slider`, an unkeyed leaf) and the top bar
/// have no signature. The count is now a literal, with the layout lookups it removes (1258 memo
/// hits -> 362 and 366 cache hits -> 331 against `theBracketNodeDragRebuildsTheWholeWindow`).
@Test(arguments: [BracketArm.value, BracketArm.panels]) @MainActor
func aDragFrameRestoresTheUnmovedOccurrencesPlacement(arm: BracketArm) throws {
    let on = try bracketDragFrames(arm: arm, steps: 20, retained: true).frames
    let off = try bracketDragFrames(arm: arm, steps: 20, retained: false).frames
    try #require(on.count == 21 && off.count == 21)
    let f = on[on.count / 2], g = off[off.count / 2]
    #expect(g.layoutSubtreeHits == 0, "no marks, no restores")
    #expect(f.layoutSubtreeHits == 11)
    #expect(f.layoutMemoHits == 362 && g.layoutMemoHits == 1258)
    #expect(f.layoutCacheHits == 331 && g.layoutCacheHits == 366)
    #expect(f.layoutMeasureCalls == 52 && f.layoutCacheMisses == 217 && f.layoutMemoMisses == 55)
    #expect(f.layoutMemoRootHits == 0)
}

@MainActor private struct PlacementSnapshot {
    let rects: Data, glyphs: Data, images: Data
    let tree: AccessibilityTree
    let hitboxes: [String]
    let bounds: [GlobalElementID: Bounds<Pixels>]

    init(_ window: TestWindow) throws {
        func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
        rects = bytes(window.scene.rects); glyphs = bytes(window.scene.glyphs); images = bytes(window.scene.images)
        tree = try window.accessibilityTree
        hitboxes = window.window.testingHitboxes.map { "\($0.id)|\($0.bounds)|\($0.layer)|\($0.opaque)" }
        bounds = window.window.testingElementBounds
    }

    func matches(_ other: PlacementSnapshot) -> Bool {
        rects == other.rects && glyphs == other.glyphs && images == other.images && tree == other.tree
            && hitboxes == other.hitboxes && bounds == other.bounds
    }
}

/// A restored placement is a fresh placement: the drag, one step at a time, in a window that marks and
/// restores and one that does not, equal in the scene, the accessibility tree, the hitboxes and every
/// element's bounds after each step, bit for bit. The restore counter proves the arm restores.
/// **Red before:** the restore counter reads 0. **Mutation:** the placement key built with the
/// origin zeroed (a moved node restores at the old place) reddens the bounds comparison.
@Test(arguments: [BracketArm.value, BracketArm.panels]) @MainActor
func aRestoredDragEqualsAFreshOneAtEveryStep(arm: BracketArm) throws {
    func make() throws -> TestWindow {
        let (window, _) = try bracketWindow(arm: arm, textSystem: harnessTextSystem)
        window.window.testingRecordsElementBounds = true
        for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
        return window
    }
    let on = try make(), off = try make()
    off.window.testingRetainedSubtrees = false
    var restores = 0
    for step in 0..<12 {
        let from = Point(x: Pixels(20 + 2 * Float(step)), y: Pixels(400))
        let to = Point(x: Pixels(22 + 2 * Float(step)), y: Pixels(400))
        on.drag(from: from, to: to, steps: 1)
        off.drag(from: from, to: to, steps: 1)
        restores += on.frameWork.map(\.layoutSubtreeHits).reduce(0, +)
        on.resetFrameWork(); off.resetFrameWork()
        #expect(try PlacementSnapshot(on).matches(PlacementSnapshot(off)), "step \(step)")
    }
    #expect(restores > 0)
}

// MARK: Keyed leaves the placement memo needs

@MainActor private func steadyFrames(_ makeRoot: @escaping @MainActor () -> some Element) throws -> FrameWork {
    let window = try TestWindow(size: sz(300, 200), textSystem: harnessTextSystem) { makeRoot() }
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    return window.frameWork.dropFirst().reduce(window.frameWork[0], +)
}

/// `Color` used as a view and an empty legacy container are keyed leaves (`SB-AD`: the fixture's nodes
/// hold both, and one unkeyed leaf makes every ancestor unmatchable). A steady frame of a tree holding
/// one restores the whole placement from the root memo (three frames, three root hits).
/// **Red before:** 0 root hits. **Mutation:** `ColorLeafKey` removed from `Color`'s registration
/// reddens the first arm, `EmptyContainerLeafKey` removed from the empty-container lowering the second.
@Test @MainActor func aColorAndAnEmptyContainerKeepTheirAncestorsMatchable() throws {
    let color = try steadyFrames { VStack { Color.clear.frame(width: Pixels(50), height: Pixels(20)); Text("a") } }
    #expect(color.layoutMemoRootHits == 3)
    let empty = try steadyFrames { VStack { Column {}; Text("a") } }
    #expect(empty.layoutMemoRootHits == 3)
}
