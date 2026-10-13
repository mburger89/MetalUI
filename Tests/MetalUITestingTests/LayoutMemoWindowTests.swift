import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Foundation
import Observation
import Testing

// C14 lane 1 (`IV-E`, `IV-N`): the layout memo through a real `Window`, counted in
// `FrameWork` and at the text seam. Kernel-level pins are
// `MetalUILayoutTests/LayoutMemoTests.swift`. Counts, never time.

/// True when the suite runs with `METALUI_VERIFY_LAYOUT_MEMO=1` (test 1.12): every
/// memo hit is then recomputed, which measures at the text seam again, so the pins
/// that COUNT seam measures stand aside (the recomputation is the point of the run).
let layoutMemoVerifying = ProcessInfo.processInfo.environment["METALUI_VERIFY_LAYOUT_MEMO"] == "1"

// MARK: 1.1 — the GT-A overlay, re-taken

@MainActor private func movingLabels(n: Int, model: CameraModel, counting: CountingTextSystem) throws -> TestWindow {
    try TestWindow(size: sz(800, 600), textSystem: { counting }) {
        ZStack(alignment: .topLeading) {
            GPUSurface(redraw: .onDemand, value: model.phase) { _ in }
            ForEach(Array(0..<n), id: \.self) { i in
                Text("\(i).5 mm")
                    .offset(x: Pixels(Float(i % 10) * 70 + model.phase), y: Pixels(Float(i / 10) * 20 + model.phase * 0.5))
            }
        }
    }
}

/// 1.1 — N moving `.offset` labels over a `GPUSurface` cost, per camera frame,
/// **no layout work at all**: a render effect registers no layout node, so the tree
/// is signature-identical, the root answer is one memo lookup and the placement is
/// restored (`IV-E` (M), (P)). Prediction recorded before the run (spec §8):
/// measure calls 0, cache misses 0, memo hits ≥ 1, one root hit, seam measures 0,
/// `placeGlyphs` N. The memo-off arm is the separating control: it reads the GT-A
/// baseline (N + 1 leaf measures, 2N seam measures). Mutation: `placeFromMemo`
/// returning `false` always reddens `layoutCacheMisses == 0`.
@Test(arguments: [20, 100]) @MainActor func aSteadyOffsetFrameMeasuresNothing(labels n: Int) throws {
    for memoOn in [false, true] {
        let model = CameraModel()
        let counting = CountingTextSystem(harnessTextSystem())
        let window = try movingLabels(n: n, model: model, counting: counting)
        window.window.testingLayoutMemo.isEnabled = memoOn
        for _ in 0..<2 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
        counting.reset(); window.resetFrameWork()
        let frames = 5
        for _ in 0..<frames { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
        let w = window.frameWork
        try #require(w.count == frames)
        let sum = w.dropFirst().reduce(w[0], +)
        #expect(sum.builds == frames)
        #expect(counting.places == frames * n, "paint still places every label (memoOn \(memoOn))")
        if memoOn {
            #expect(sum.layoutMeasureCalls == 0)
            #expect(sum.layoutCacheMisses == 0)
            #expect(sum.layoutMemoHits >= frames)
            #expect(sum.layoutMemoRootHits == frames)
            if !layoutMemoVerifying { #expect(counting.measures == frames * n, "paint's own measure only (GT-F)") }
        } else {
            #expect(sum.layoutMeasureCalls == frames * (n + 1))
            #expect(sum.layoutCacheMisses == frames * (n + 2))
            #expect(counting.measures == frames * 2 * n)
            #expect(sum.layoutMemoHits == 0 && sum.layoutSignatureNodes == 0)
        }
    }
}

// MARK: The branching tree of the lane-0 baseline

@Observable @MainActor final class IVMemoCell { var value = 0 }

private struct MemoLeaf: Component {
    let cell: IVMemoCell
    var content: some ElementGroup {
        Text("v\(cell.value)").frame(width: Pixels(60), height: Pixels(14))
    }
}

private struct MemoBranch<Child: Component>: Component {
    let children: [Child]
    var content: some ElementGroup {
        VStack(spacing: 0) { ForEach(Array(children.indices), id: \.self) { children[$0] } }
    }
}

@MainActor private func memoTree(levels: Int, counting: CountingTextSystem) throws -> (TestWindow, [IVMemoCell]) {
    var count = 1
    for _ in 0..<levels { count *= 3 }
    let cells = (0..<count).map { _ in IVMemoCell() }
    let window = try TestWindow(size: sz(400, 600), textSystem: { counting }) {
        VStack(spacing: 0) {
            switch levels {
            case 2: MemoBranch(children: (0..<3).map { b in
                MemoBranch(children: (0..<3).map { MemoLeaf(cell: cells[b * 3 + $0]) }) })
            case 3: MemoBranch(children: (0..<3).map { a in
                MemoBranch(children: (0..<3).map { b in
                    MemoBranch(children: (0..<3).map { MemoLeaf(cell: cells[a * 9 + b * 3 + $0]) }) }) })
            default: MemoBranch(children: (0..<3).map { a in
                MemoBranch(children: (0..<3).map { b in
                    MemoBranch(children: (0..<3).map { c in
                        MemoBranch(children: (0..<3).map { MemoLeaf(cell: cells[a * 27 + b * 9 + c * 3 + $0]) }) }) }) })
            }
        }
    }
    return (window, cells)
}

/// 1.2 — one changed leaf re-measures only its path. Hand-derived before the run
/// (the leaf is `Text.frame(60, 14)`: the frame hands its child one proposal,
/// 60 × 14, whatever it is asked, so the changed text is measured once per frame
/// and shapes once at the seam; every unchanged leaf's frame subtree is a memo
/// hit at the stack's proposals; the path is L branch stacks, the window's root
/// stack and the frame). Per changed frame: measure calls 1, seam measures 1,
/// cache misses ≤ 2·(L + 3). The memo-off arm reads the lane-0 baseline
/// (3^L measure calls, 337 misses at L = 4). Mutation: the text key's string
/// dropped from `TextLeafKey.==`/hash (the field removed) reddens measure calls
/// (the changed leaf answers stale; the size of "v10" vs "v9" differs).
@Test(arguments: [2, 3, 4]) @MainActor func oneChangedTextRemeasuresOnlyItsPath(levels: Int) throws {
    for memoOn in [false, true] {
        let counting = CountingTextSystem(harnessTextSystem())
        let (window, cells) = try memoTree(levels: levels, counting: counting)
        window.window.testingLayoutMemo.isEnabled = memoOn
        let leaves = cells.count
        for _ in 0..<2 { cells[0].value += 1; window.tick() }
        counting.reset(); window.resetFrameWork()
        let frames = 4
        for f in 0..<frames { cells[leaves - 1].value += 1 + f; window.tick() }
        let w = window.frameWork
        try #require(w.count == frames)
        let sum = w.dropFirst().reduce(w[0], +)
        if memoOn {
            #expect(sum.layoutMeasureCalls == frames, "levels \(levels)")
            if !layoutMemoVerifying { #expect(counting.measures == frames * (leaves + 1), "paint measures every leaf; layout measures one") }
            #expect(sum.layoutCacheMisses <= frames * 2 * (levels + 3), "misses \(sum.layoutCacheMisses)")
            #expect(sum.layoutMemoHits > 0)
        } else {
            #expect(sum.layoutMeasureCalls == frames * leaves)
            #expect(counting.measures == frames * 2 * leaves)
            #expect(sum.layoutMemoHits == 0)
        }
    }
}

// MARK: 1.3, 1.9, 1.10 — output equality against a memo-less window

@MainActor private final class ScriptModel {
    var texts = ["alpha", "beta gamma", "delta epsilon zeta eta", "theta"]
    var spacing: Float = 4
    var fontSize: Float = 13
    var showSection = true
    var limit: Int?
    var weight = false
}

@MainActor private func scriptWindow(_ model: ScriptModel, memo: Bool, verifies: Bool) throws -> TestWindow {
    let window = try harnessWindow(size: sz(300, 400)) {
        VStack(spacing: Pixels(model.spacing)) {
            ForEach(Array(model.texts.indices), id: \.self) { i in
                Text(model.texts[i]).font(.system(size: Double(model.fontSize))).id("t\(i)")
            }
            if model.showSection {
                HStack(spacing: 6) {
                    Text("left").id("l")
                    Divider()
                    Text("right side of the section").id("r")
                }
                Circle().frame(width: 20, height: 20)
            }
            Text("a fractional wrapping paragraph that needs several lines to fit")
                .lineLimit(model.limit).fontWeight(model.weight ? .bold : .regular).frame(width: 97.5).id("wrap")
        }
    }
    window.window.testingLayoutMemo.isEnabled = memo
    window.window.testingLayoutMemo.verifies = verifies
    return window
}

@MainActor private func snapshot(_ window: TestWindow) -> String {
    let ids = ["t0", "t1", "t2", "t3", "l", "r", "wrap"]
    let frames = ids.map { id in (try? window.frame(ofID: id)).map { "\($0)" } ?? "-" }
    return frames.joined(separator: "|") + "#\(window.scene.rects)#\(window.scene.glyphs)"
}

/// 1.3 — a memo hit equals a fresh layout bit for bit, over a 40-step script
/// (resize, text change, spacing, font size, scale factor, appearance, section
/// toggle) against a window with the memo off, the memo window running
/// `verifies` (every hit recomputed, a difference traps). Mutation: any
/// signature field omitted (1.5's arms) reddens it; recorded in record 104.
@Test @MainActor func aMemoHitEqualsAFreshLayoutBitForBit() throws {
    let a = ScriptModel(), b = ScriptModel()
    let memoWindow = try scriptWindow(a, memo: true, verifies: true)
    let plainWindow = try scriptWindow(b, memo: false, verifies: false)
    var hits = 0
    for step in 0..<40 {
        switch step % 10 {
        case 0: a.texts[step % 4] += "x"; b.texts[step % 4] += "x"
        case 1: a.spacing += 1.5; b.spacing += 1.5
        case 2: a.fontSize += 1; b.fontSize += 1
        case 3: a.showSection.toggle(); b.showSection.toggle()
        case 4:
            let size = sz(300 + Float(step), 400)
            memoWindow.resize(to: size); plainWindow.resize(to: size)
        case 5:
            let scale: Float = step % 16 == 5 ? 2 : 1
            memoWindow.setScaleFactor(scale); plainWindow.setScaleFactor(scale)
        case 6:
            let appearance: Appearance = step % 16 == 6 ? .dark : .light
            memoWindow.setAppearance(appearance); plainWindow.setAppearance(appearance)
        case 7:
            if step % 16 == 7 { a.limit = 2; b.limit = 2 } else { a.limit = nil; b.limit = nil; a.weight.toggle(); b.weight.toggle() }
        default: break   // an unchanged frame: a pure (P) hit
        }
        memoWindow.window.setNeedsRedraw(); plainWindow.window.setNeedsRedraw()
        memoWindow.tick(); plainWindow.tick()
        #expect(snapshot(memoWindow) == snapshot(plainWindow), "step \(step)")
        hits += memoWindow.lastFrameWork.layoutMemoHits + memoWindow.lastFrameWork.layoutMemoRootHits
    }
    #expect(hits > 0, "the script must exercise the memo")
}

/// 1.9 — a resize misses by proposal (the answer follows the window), and a scale
/// change does not miss: text measurement takes no scale (`IV-N`), so a 1 → 2 move
/// is a root hit. Mutation: `MeasureKey` ignoring the proposal reddens the resize
/// arm (stale answers); the text key gaining the scale factor reddens the scale
/// arm.
@Test @MainActor func aWindowResizeMissesByProposalAndAScaleChangeDoesNot() throws {
    let model = ScriptModel()
    let window = try scriptWindow(model, memo: true, verifies: false)
    let reference = try scriptWindow(ScriptModel(), memo: false, verifies: false)
    window.tick(); window.tick()
    window.resetFrameWork()
    window.resize(to: sz(210, 400)); reference.resize(to: sz(210, 400))
    #expect(window.lastFrameWork.layoutMemoRootHits == 0)
    #expect(window.lastFrameWork.layoutMeasureCalls > 0)
    #expect(snapshot(window) == snapshot(reference))
    window.tick(); window.resetFrameWork()
    window.setScaleFactor(2); reference.setScaleFactor(2)
    #expect(window.lastFrameWork.layoutMeasureCalls == 0)
    #expect(window.lastFrameWork.layoutMemoRootHits == 1)
    #expect(snapshot(window) == snapshot(reference))
}

/// 1.10 — after a (P) hit, `Text.paint`'s wrap width is a fresh run's: the
/// fractional-width paragraph shapes the same glyphs. The measured widths are
/// recorded by the rounding walk the hit still runs (`IV-N`). Mutation: skip
/// `roundNativeStoredRects` after a hit.
@Test @MainActor func aRootPlacementHitRestoresMeasuredWidths() throws {
    let window = try scriptWindow(ScriptModel(), memo: true, verifies: false)
    let reference = try scriptWindow(ScriptModel(), memo: false, verifies: false)
    window.tick(); reference.tick()
    window.window.setNeedsRedraw(); window.resetFrameWork(); window.tick()
    try #require(window.lastFrameWork.layoutMemoRootHits == 1)
    #expect(snapshot(window) == snapshot(reference))
    #expect(!window.scene.glyphs.isEmpty)
}

/// 1.11 — with no memo attached the numbers are the old ones: a cold first frame
/// (every lookup a miss, nothing stored yet) reads the same measure calls and
/// run-cache hits as a memo-off window, and `LayoutTree`-level tests (no memo) are
/// unmoved. Mutation: attach the memo in `LayoutTree.init`.
@Test @MainActor func aColdMemoCountsAsTheOldRunDid() throws {
    // The cold first frame (memo on, nothing stored), then the same tree laid out
    // again with the memo off and emptied: the old per-run behaviour.
    let window = try scriptWindow(ScriptModel(), memo: true, verifies: false)
    let cold = try #require(window.frameWork.first)
    let memo = window.window.testingLayoutMemo
    memo.removeAll(); memo.isEnabled = false
    window.resetFrameWork()
    window.window.setNeedsRedraw(); window.tick()
    let old = window.lastFrameWork
    #expect(cold.layoutMeasureCalls == old.layoutMeasureCalls)
    #expect(cold.layoutCacheHits == old.layoutCacheHits)
    #expect(cold.layoutMemoHits == 0 && cold.layoutMemoRootHits == 0)
    #expect(cold.layoutSignatureNodes > 0 && old.layoutSignatureNodes == 0)
}
