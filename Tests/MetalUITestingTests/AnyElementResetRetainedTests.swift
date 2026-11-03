import Foundation
import MetalUI
import MetalUITesting
import Observation
import Testing

// `ER-A` over the retained paths (record 201): an `AnyElement` swap inside an `.equatable()` occurrence, a graft and an
// inner memo. Two windows over one builder: `on` retains (record, ledger, graft), `off` retains nothing; each has its
// own model. The counts are not read under `METALUI_VERIFY_RETAINED=1` (a replayed frame is built twice there); the
// scene and value comparisons still are, so verify mode traps a wrong graft.

private let erVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

@Observable @MainActor final class ERModel {
    var flag = false
    var w = 0
}

// The instruments declare their stored properties in one order (`w`, `n`): the `@State` slot is named by position.
struct ERRetA: Component {
    let w: Int
    @State var n: Int
    init(w: Int) { self.w = w; _n = State(wrappedValue: 10) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent).onChange(of: w) { n = 11 }
    }
}
struct ERRetB: Component {
    let w: Int
    @State var n: Int
    init(w: Int) { self.w = w; _n = State(wrappedValue: 20) }
    var content: some ElementGroup {
        Box().frame(width: Pixels(Float(n)), height: Pixels(20)).background(.accent).onChange(of: w) { n = 21 }
    }
}

/// An `.equatable()` card whose `==` ignores the model, which its content reads (an observed read): the swap reaches
/// it as an observed change, never as a changed value.
struct ERRetCard: Component, @MainActor Equatable {
    let model: ERModel
    let tag: Int
    var content: some ElementGroup {
        model.flag ? AnyElement(Stack { ERRetB(w: model.w) }) : AnyElement(Stack { ERRetA(w: model.w) })
    }
    static func == (l: ERRetCard, r: ERRetCard) -> Bool { l.tag == r.tag }
}

@MainActor private func erPair() throws -> (on: TestWindow, off: TestWindow, onModel: ERModel, offModel: ERModel) {
    func make(_ model: ERModel) throws -> TestWindow {
        try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
            VStack(spacing: 0) { ERRetCard(model: model, tag: 1).equatable() }
        }
    }
    let onModel = ERModel(), offModel = ERModel()
    let on = try make(onModel), off = try make(offModel)
    off.window.testingRetainedSubtrees = false
    return (on, off, onModel, offModel)
}

@MainActor private func erStep(_ pair: (on: TestWindow, off: TestWindow, onModel: ERModel, offModel: ERModel),
                               _ change: (ERModel) -> Void = { _ in }) {
    change(pair.onModel); change(pair.offModel)
    for w in [pair.on, pair.off] { w.window.setNeedsRedraw(); w.tick() }
}

@MainActor private func erWidths(_ window: TestWindow) -> [Float] {
    window.scene.rects.filter { $0.bounds.size.height == 20 }.map { $0.bounds.size.width }
}

@MainActor private func erAgree(_ pair: (on: TestWindow, off: TestWindow, onModel: ERModel, offModel: ERModel),
                                _ step: String) throws {
    let differences = try RPSnapshot(pair.on, accessibility: false).differences(from: RPSnapshot(pair.off, accessibility: false))
    #expect(differences.isEmpty, "after \(step): \(differences)")
    #expect(erWidths(pair.on) == erWidths(pair.off), "widths after \(step): \(erWidths(pair.on)) vs \(erWidths(pair.off))")
}

/// **A swap under an `.equatable()` parent draws the new type** (`ER-A`): the card's `==` is equal, its content reads
/// the model, and the observed flip rebuilds it (the occurrence must not graft or replay the old type). The retention-off
/// window is the oracle at every step. Mutation: `!entry.observedChange` removed from `graftRecord` (the flip grafts the
/// stale A).
@Test @MainActor func aSwapUnderAnEquatableParentDrawsTheNewType() throws {
    let pair = try erPair()
    for _ in 0..<4 { erStep(pair) }
    try erAgree(pair, "the settled frames")
    #expect(erWidths(pair.on) == [10])
    if !rsVerifying { #expect(pair.on.lastFrameWork.retainedGrafts == 1, "set up: the occurrence is grafted") }
    erStep(pair) { $0.flag = true }
    #expect(erWidths(pair.on) == [20], "B draws its own seed: \(erWidths(pair.on))")
    try erAgree(pair, "the flip")
    if !rsVerifying {
        #expect(pair.on.lastFrameWork.contentEvaluations >= 1, "the observed change evaluated the content: \(pair.on.lastFrameWork.contentEvaluations)")
    }
    for _ in 0..<4 { erStep(pair) }
    try erAgree(pair, "B settled")
    erStep(pair) { $0.flag = false }
    #expect(erWidths(pair.on) == [10], "A is fresh on the way back: \(erWidths(pair.on))")
    try erAgree(pair, "the flip back")
}

/// **A grafted position still resets when it swaps** (`ER-A`, the one link that needs its own test): while the occurrence
/// grafts, the build journal's `.named(T, 0)` replay is what keeps the position's previous name for the next real swap,
/// so a written A (11) that is grafted for several frames, swapped to B and swapped back reads 10. Without the replay the
/// swap finds no previous name, departs nothing and A comes back with its 11. Mutation: `case .named` in
/// `Frame.reapply` made a no-op.
@Test @MainActor func aGraftedPositionStillResetsWhenItSwaps() throws {
    let pair = try erPair()
    for _ in 0..<3 { erStep(pair) }
    erStep(pair) { $0.w = 1 }                       // A writes 11 (the card's observed read of `w` rebuilds it)
    for _ in 0..<5 { erStep(pair) }
    try #require(erWidths(pair.on) == [11], "set up: A is written: \(erWidths(pair.on))")
    if !rsVerifying { try #require(pair.on.lastFrameWork.retainedGrafts == 1, "set up: the written occurrence is grafted") }
    erStep(pair) { $0.flag = true }
    #expect(erWidths(pair.on) == [20], "B: \(erWidths(pair.on))")
    erStep(pair) { $0.flag = false }
    #expect(erWidths(pair.on) == [10], "A reads its seed, not the 11 it left with: \(erWidths(pair.on))")
    try erAgree(pair, "the swap back")
}

// MARK: An inner memo

/// An `.equatable()` child with its own value.
struct ERInner: Component, @MainActor Equatable {
    let k: Int
    var content: some ElementGroup {
        Box().frame(width: Pixels(30), height: Pixels(20)).background(.accent)
    }
    static func == (l: ERInner, r: ERInner) -> Bool { l.k == r.k }
}

@MainActor private func innerWindow(_ model: ERModel, swapType: Bool) throws -> TestWindow {
    try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) {
            if swapType {
                model.flag ? AnyElement(Row { ERInner(k: 1).equatable() }) : AnyElement(Stack { ERInner(k: 1).equatable() })
            } else {
                // The same wrapped type from two expressions: only the stack's frame differs.
                model.flag ? AnyElement(Stack { ERInner(k: 1).equatable() }.frame(width: Pixels(80), height: Pixels(20)))
                           : AnyElement(Stack { ERInner(k: 1).equatable() }.frame(width: Pixels(60), height: Pixels(20)))
            }
        }
    }
}

/// **A same-type rebuild keeps an inner memo** (`ER-A`): the wrapped type is unchanged, so the `.equatable()` child
/// inside still finds its entry and is skipped when the outer rebuilds. Mutation: the level keyed by a per-instance
/// counter (the entry is new every build and the child evaluates).
@Test(.enabled(if: !rsVerifying, erVerifyingNote)) @MainActor func aSameTypeRebuildKeepsItsInnerRecord() throws {
    let model = ERModel()
    let window = try innerWindow(model, swapType: false)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    model.flag = true
    window.window.setNeedsRedraw(); window.tick()
    let f = window.lastFrameWork
    #expect(f.contentEvaluations == 0 && f.contentSkips >= 1, "the inner child is skipped: evaluations \(f.contentEvaluations), skips \(f.contentSkips)")
}

/// **A swapped-back `.equatable()` child starts cold** (`ER-A`): the old level's memo entries were untouched while B
/// was in place and `endFrame` removed them, so the way back evaluates the child (no replay of a record made under the
/// old level). Mutation: `ContentMemoStore.endFrame` keeps untouched entries.
@Test(.enabled(if: !rsVerifying, erVerifyingNote)) @MainActor func aSwappedBackEquatableChildStartsCold() throws {
    let model = ERModel()
    let window = try innerWindow(model, swapType: true)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    model.flag = true
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.lastFrameWork.contentEvaluations == 1, "B's child is new: \(window.lastFrameWork.contentEvaluations)")
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    model.flag = false
    window.window.setNeedsRedraw(); window.tick()
    let f = window.lastFrameWork
    #expect(f.contentEvaluations == 1 && f.contentSkips == 0, "A's child is evaluated again, not replayed: evaluations \(f.contentEvaluations), skips \(f.contentSkips)")
}

// MARK: The layout memo

/// **An equal-shape swap with different text draws B** (`ER-A`, `IV-J`): `Stack { Text("ab") }` swapped for
/// `Row { Text("cd") }` lays out to the same shape, so the layout memo may hit, and the frame must still draw B's glyphs:
/// the swapping window's scene equals a window that showed B from the start. Run under `METALUI_VERIFY_LAYOUT_MEMO=1`
/// as well (it recomputes every hit and traps). Mutation: a keyed text leaf dropping its text from the key.
@Test @MainActor func anEqualShapeSwapDrawsTheNewTypesText() throws {
    func make(_ model: ERModel) throws -> TestWindow {
        try TestWindow(size: sz(200, 100), textSystem: harnessTextSystem) {
            VStack(spacing: 0) {
                model.flag ? AnyElement(Row { Text("cd").frame(width: Pixels(40), height: Pixels(20)) })
                           : AnyElement(Stack { Text("ab").frame(width: Pixels(40), height: Pixels(20)) })
            }
        }
    }
    func glyphs(_ w: TestWindow) -> Data { w.scene.glyphs.withUnsafeBytes { Data($0) } }
    let swapping = ERModel(), direct = ERModel()
    direct.flag = true
    let a = try make(swapping), b = try make(direct)
    for _ in 0..<3 { a.window.setNeedsRedraw(); a.tick(); b.window.setNeedsRedraw(); b.tick() }
    let before = glyphs(a)
    #expect(before != glyphs(b), "set up: the two texts draw differently")
    swapping.flag = true
    a.window.setNeedsRedraw(); a.tick()
    #expect(glyphs(a) == glyphs(b), "the swap draws B's glyphs")
    #expect(glyphs(a) != before)
}
