import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Foundation
import Observation
import Testing

// C14 lane 2 (`IV-B`…`IV-D`, `IV-L`, `IV-M`): `Component.equatable()` through a real
// `Window`, counted in `FrameWork` and at user level (`MemoStats`, lane 0's). Counts,
// never time. Tests 2.1–2.10 and 2.13 of the design spec; the typecheck guards 2.11
// are `MetalUITests/ContentMemoCompileGuards.swift`.

/// Body evaluations by kind, reset by the test. This file's own (not lane 0's `IVStats`):
/// its tests are `async`, so on a parallel run (Linux and Windows CI) they would interleave
/// with each other and with the baseline test; `MemoGate` serializes them.
@MainActor enum MemoStats {
    static var branches = 0
    static var leaves = 0
    static func reset() { branches = 0; leaves = 0 }
}

/// A FIFO gate on the main actor: every test of this file holds it from start to end, so
/// no two of them interleave at an `await` and corrupt `MemoStats`.
@MainActor enum MemoGate {
    private static var held = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []
    static func enter() async {
        if held { await withCheckedContinuation { waiters.append($0) } } else { held = true }
    }
    static func leave() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }
}

/// Whether `withObservationTracking`'s `onChange` reaches the memo synchronously: on
/// Apple platforms a test runs on the main thread; elsewhere a main-actor test does not,
/// so every change takes the one main-actor hop (`HT-I`, measured in the Linux image:
/// `Thread.isMainThread` is false in a test). The two tests that count sessions and idle
/// frames are exact only where the hop is synchronous.
let memoObservationIsSynchronous: Bool = {
    #if canImport(Darwin)
    true
    #else
    false
    #endif
}()

/// Lets the observation hop of a platform without a synchronous `onChange` land
/// before the next explicit draw (HT-I).
@MainActor private func settle() async {
    for _ in 0..<4 { await Task.yield() }
}

/// Dirties the window and draws one frame.
@MainActor private func redraw(_ window: TestWindow) {
    window.window.setNeedsRedraw()
    window.tick()
}

/// Everything the frame hands the platform, for the differential (2.9, 2.10).
@MainActor private struct Snapshot {
    let rects: Data, glyphs: Data, images: Data
    let counts: [Int]
    let tree: AccessibilityTree
    let hitboxes: [String]
    let tabOrder: [GlobalElementID]
    let bounds: [GlobalElementID: Bounds<Pixels>]

    init(_ window: TestWindow) throws {
        func bytes<T>(_ array: [T]) -> Data { array.withUnsafeBytes { Data($0) } }
        rects = bytes(window.scene.rects); glyphs = bytes(window.scene.glyphs); images = bytes(window.scene.images)
        counts = [window.scene.rects.count, window.scene.glyphs.count, window.scene.images.count]
        tree = try window.accessibilityTree
        hitboxes = window.window.testingHitboxes.map { "\($0.id)|\($0.bounds)|\($0.layer)|\($0.opaque)" }
        tabOrder = window.window.testingTabOrder
        bounds = window.window.testingElementBounds
    }

    func differences(from other: Snapshot) -> [String] {
        var out: [String] = []
        if rects != other.rects { out.append("rects") }
        if glyphs != other.glyphs { out.append("glyphs") }
        if images != other.images { out.append("images") }
        if counts != other.counts { out.append("counts \(counts) vs \(other.counts)") }
        if tree != other.tree { out.append("accessibility tree") }
        if hitboxes != other.hitboxes { out.append("hitboxes") }
        if tabOrder != other.tabOrder { out.append("tab order") }
        if bounds != other.bounds { out.append("element bounds") }
        return out
    }
}

// MARK: The branching tree of lane 0, every component `.equatable()`

private struct EqLeaf: Component, @MainActor Equatable {
    let cell: IVCell
    var memo = true
    var content: some ElementGroup {
        let _ = MemoStats.leaves += 1
        Text("v\(cell.value)").frame(width: Pixels(60), height: Pixels(14))
    }
    static func == (l: EqLeaf, r: EqLeaf) -> Bool { l.memo && r.memo && l.cell === r.cell }
}

private struct EqBranch<Child: Component & Equatable>: Component, @MainActor Equatable {
    let children: [Child]
    var memo = true
    var content: some ElementGroup {
        let _ = MemoStats.branches += 1
        VStack(spacing: 0) {
            ForEach(Array(children.indices), id: \.self) { children[$0].equatable() }
        }
    }
    static func == (l: EqBranch, r: EqBranch) -> Bool { l.memo && r.memo && l.children == r.children }
}

@MainActor private func eqWindow(levels: Int, counting: CountingTextSystem, memo: Bool = true) throws -> (TestWindow, [IVCell], Int) {
    var count = 1
    for _ in 0..<levels { count *= 3 }
    let cells = (0..<count).map { _ in IVCell() }
    func leaf(_ i: Int) -> EqLeaf { EqLeaf(cell: cells[i], memo: memo) }
    let window = try TestWindow(size: sz(400, 600), textSystem: { counting }) {
        VStack(spacing: 0) {
            switch levels {
            case 2: EqBranch(children: (0..<3).map { b in
                EqBranch(children: (0..<3).map { leaf(b * 3 + $0) }, memo: memo) }, memo: memo).equatable()
            case 3: EqBranch(children: (0..<3).map { a in
                EqBranch(children: (0..<3).map { b in
                    EqBranch(children: (0..<3).map { leaf(a * 9 + b * 3 + $0) }, memo: memo) }, memo: memo) }, memo: memo).equatable()
            default: EqBranch(children: (0..<3).map { a in
                EqBranch(children: (0..<3).map { b in
                    EqBranch(children: (0..<3).map { c in
                        EqBranch(children: (0..<3).map { leaf(a * 27 + b * 9 + c * 3 + $0) }, memo: memo) }, memo: memo) }, memo: memo) }, memo: memo).equatable()
            }
        }
    }
    return (window, cells, (count + (count - 1) / 2))
}

/// 2.1 — an equal component skips its content (`IV-B`). Baseline tree of lane 0
/// with every `IVBranch`/`IVLeaf` `.equatable()`, one leaf written per frame: one
/// leaf body evaluated, no branch body, one build. The memo-off arm (`==` false
/// everywhere, so the same tree takes the miss path) reads the lane-0 baseline,
/// 3^L leaf and (3^L − 1)/2 branch bodies: the separating control. Mutation: the
/// entry's `previous` stored after the comparison instead of before (the compare
/// then sees the new value against itself and the next frame's old value) —
/// reddens `contentSkips`.
@Test(arguments: [2, 3, 4]) @MainActor func anEqualComponentSkipsItsContent(levels: Int) async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    for memoOn in [false, true] {
        let counting = CountingTextSystem(harnessTextSystem())
        let (window, cells, components) = try eqWindow(levels: levels, counting: counting, memo: memoOn)
        let leaves = cells.count
        // The memo's own pin: a graft (`RK-B`) skips an unchanged occurrence's whole build recursion, nested components
        // included, so their content skips are not even visited; the graft's counts are `RetainedGraftTests`'.
        window.window.testingRetainedGraft = false
        for _ in 0..<2 { cells[0].value += 1; await settle(); redraw(window) }   // warm
        counting.reset(); MemoStats.reset(); window.resetFrameWork()
        let frames = 4
        for f in 0..<frames { cells[leaves - 1].value += 1 + f; await settle(); redraw(window) }
        let w = window.frameWork
        try #require(w.count == frames)
        let sum = w.dropFirst().reduce(w[0], +)
        #expect(sum.builds == frames)
        if memoOn {
            #expect(MemoStats.leaves == frames, "levels \(levels)")
            #expect(MemoStats.branches == 0)
            #expect(sum.contentEvaluations == frames)
            #expect(sum.contentSkips == frames * (components - 1))
            #expect(sum.contentRefusals == 0)
        } else {
            #expect(MemoStats.leaves == frames * leaves)
            #expect(MemoStats.branches == frames * ((leaves - 1) / 2))
            #expect(sum.contentEvaluations == frames * components)
            #expect(sum.contentSkips == 0)
        }
    }
}

// MARK: 2.2, 2.3 — an observed read and an own-@State write beat an equal `==`

private struct AlwaysEqualReader: Component, @MainActor Equatable {
    let cell: IVCell
    var content: some ElementGroup {
        let _ = MemoStats.leaves += 1
        Text("r\(cell.value)").frame(width: Pixels(60), height: Pixels(14))
    }
    static func == (l: AlwaysEqualReader, r: AlwaysEqualReader) -> Bool { true }
}

/// 2.2 — `==` is always true, the content reads `cell.value`, the cell changes:
/// the content re-evaluates exactly once and the drawn text is the new value (SwiftUI
/// probe O, `IV-C`). Mutation: the memo session's `onChange` made empty — stale
/// text and `leaves == 0`.
@Test @MainActor func anObservedReadBeatsAnEqualValue() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let cell = IVCell()
    let counting = CountingTextSystem(harnessTextSystem())
    let window = try TestWindow(size: sz(300, 100), textSystem: { counting }) {
        VStack(spacing: 0) { AlwaysEqualReader(cell: cell).equatable() }
    }
    _ = try window.element(label: "r0")
    for _ in 0..<3 { redraw(window) }
    MemoStats.reset()
    for _ in 0..<3 { redraw(window) }
    #expect(MemoStats.leaves == 0, "an unchanged equal component is skipped")
    cell.value = 7
    await settle()
    redraw(window)
    #expect(MemoStats.leaves == 1)
    _ = try window.element(label: "r7")
    #expect(throws: (any Error).self) { _ = try window.element(label: "r0") }
    redraw(window)
    #expect(MemoStats.leaves == 1, "and skipped again once current")
}

private struct AlwaysEqualCounter: Component, @MainActor Equatable {
    @State var n = 0
    var content: some ElementGroup {
        let _ = MemoStats.leaves += 1
        VStack(spacing: 0) {
            Text("n=\(n)").frame(width: Pixels(60), height: Pixels(14))
            Button("inc") { n += 1 }.frame(width: Pixels(60), height: Pixels(20))
        }
    }
    static func == (l: AlwaysEqualCounter, r: AlwaysEqualCounter) -> Bool { true }
}

/// 2.3 — `==` always true, a button writes the component's own `@State`: the content
/// re-evaluates and the text updates (SwiftUI probe ES, `IV-D` item 1). **2.3b** (`IV-L` item 4): the
/// button's closure was built in the evaluation of frame 1 and is invoked after five
/// skipped frames; it still writes. Mutation: the entry's recorded versions not
/// compared — the text stays `n=0`.
@Test @MainActor func anOwnStateWriteBeatsAnEqualValue() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let window = try harnessWindow { VStack(spacing: 0) { AlwaysEqualCounter().equatable() } }
    _ = try window.element(label: "n=0")
    for _ in 0..<5 { redraw(window) }
    MemoStats.reset()
    for _ in 0..<5 { redraw(window) }
    #expect(MemoStats.leaves == 0, "skipped while nothing changes")
    try window.click(window.element(label: "inc"))     // 2.3b: frame 1's closure, six frames old
    #expect(MemoStats.leaves == 1)
    _ = try window.element(label: "n=1")
    for _ in 0..<3 { redraw(window) }
    try window.click(window.element(label: "inc"))
    _ = try window.element(label: "n=2")
    #expect(MemoStats.leaves == 2)
}

// MARK: 2.4 — an unequal value re-evaluates, the subtree below still skips

@Observable @MainActor final class IVParam { var k = 0 }

private struct EqMid: Component, @MainActor Equatable {
    let k: Int
    let cells: [IVCell]
    static func == (l: EqMid, r: EqMid) -> Bool { l.k == r.k && l.cells.elementsEqual(r.cells, by: ===) }
    var content: some ElementGroup {
        let _ = MemoStats.branches += 1
        VStack(spacing: 0) {
            Text("k\(k)").frame(width: Pixels(60), height: Pixels(14))
            ForEach(Array(cells.indices), id: \.self) { EqLeaf(cell: cells[$0]).equatable() }
        }
    }
}

private struct ParamHolder: Component {
    let param: IVParam
    let cells: [IVCell]
    var content: some ElementGroup {
        EqMid(k: param.k, cells: cells).equatable()
    }
}

/// 2.4 — the control: an input differs, the component re-evaluates, the three leaves
/// below it still skip. Mutation: `==` replaced by `true` in the entry check —
/// reddens `branches == 1` (the changed input is ignored) and the text.
@Test @MainActor func anUnequalValueReEvaluates() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let param = IVParam()
    let cells = (0..<3).map { _ in IVCell() }
    let window = try harnessWindow { VStack(spacing: 0) { ParamHolder(param: param, cells: cells) } }
    for _ in 0..<2 { redraw(window) }
    MemoStats.reset(); window.resetFrameWork()
    redraw(window)
    #expect(MemoStats.branches == 0 && MemoStats.leaves == 0)
    param.k = 3
    await settle()
    redraw(window)
    #expect(MemoStats.branches == 1)
    #expect(MemoStats.leaves == 0, "the leaves are equal and skip")
    let w = window.lastFrameWork
    #expect(w.contentEvaluations == 1 && w.contentSkips == 3)
    _ = try window.element(label: "k3")
}

// MARK: 2.5 — what stays refused (C14-c: an `@Environment` of a comparable value no longer is)

// C14-c (`EE-H`) split the old test 2.5, which pinned `@Environment` and `@FocusState` as refused together: a reader of a
// comparable `@Environment` value is memoized by its reading now (`EnvironmentEpochWindowTests` W1–W4, W6, W7); what
// remains refused is pinned there too — `aReaderOfAFunctionKeyIsRefusedAndStillEvaluates` (W5, an uncomparable
// reading) and what remains refused is an uncomparable reading, divergence 346's remainder; `@FocusState` was memoized by C14-i (`RZ-I`, `aFocusStateComponentIsSkippedWhileFocusIsUnchanged`).

// MARK: 2.6 — a skipped subtree keeps its state and its identity

private struct StatefulCounter: Component {
    @State var count = 0
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("c\(count)").frame(width: Pixels(60), height: Pixels(14))
            Button("bump") { count += 1 }.frame(width: Pixels(60), height: Pixels(20))
        }
    }
}

private struct Panel: Component, @MainActor Equatable {
    let show: Bool
    var elementID: ElementID? { ElementID("panel") }
    var content: some ElementGroup {
        let _ = MemoStats.branches += 1
        VStack(spacing: 0) {
            if show { StatefulCounter() }
            Text("panel").frame(width: Pixels(60), height: Pixels(14))
        }
    }
}

private struct PanelHolder: Component {
    let param: IVParam
    var content: some ElementGroup {
        Panel(show: param.k % 2 == 0).equatable()
    }
}

/// 2.6 — descendants' `@State` survives six skipped frames; an `if` inside a
/// *re-evaluated* content that flips resets the counter on return (`ID-C`); the
/// component's name keeps its identity. Mutation: `noteNamed` skipped on a hit
/// (the memo's hit path not calling `enterComponent`) — the departed-name sweep
/// resets the counter on a skipped frame.
@Test @MainActor func aSkippedSubtreeKeepsItsStateAndItsIdentity() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let param = IVParam()
    let window = try harnessWindow { VStack(spacing: 0) { PanelHolder(param: param) } }
    try window.click(window.element(label: "bump"))
    try window.click(window.element(label: "bump"))
    _ = try window.element(label: "c2")
    MemoStats.reset()
    for _ in 0..<6 { redraw(window) }
    #expect(MemoStats.branches == 0, "the panel was skipped throughout")
    _ = try window.element(label: "c2")
    param.k = 1                      // show = false: re-evaluated, the counter's slot is absent
    await settle(); redraw(window)
    #expect(MemoStats.branches == 1)
    #expect(throws: (any Error).self) { _ = try window.element(label: "c2") }
    param.k = 2                      // show = true again: the counter returns fresh (ID-C)
    await settle(); redraw(window)
    _ = try window.element(label: "c0")
}

// MARK: 2.7, 2.8 — sessions are bounded; the window sentinel does not flush a memo

private struct Ticker: Component, @MainActor Equatable {
    let n: Int
    var content: some ElementGroup {
        let _ = MemoStats.leaves += 1
        Text("t\(n)").frame(width: Pixels(60), height: Pixels(14))
    }
}

private struct TickerHolder: Component {
    let param: IVParam
    var content: some ElementGroup {
        if param.k >= 0 { Ticker(n: param.k).equatable() }
    }
}

private struct SwitchHolder: Component {
    let param: IVParam
    let on: IVCell
    var content: some ElementGroup {
        if on.value == 0 { Ticker(n: param.k).equatable() }
    }
}

/// 2.7 — sessions never exceed live entries. A component that re-evaluates every
/// frame for 200 frames, then 200 skipped frames: armed sessions <= live entries
/// throughout; removing the component returns both to 0 after one frame. And
/// (`IV-L` item 5) the window goes idle after the last re-evaluating frame: the
/// token write inside the whole-frame session must not re-dirty it. Mutation:
/// the serial check dropped in the memo's `onChange` — the flush callbacks dirty
/// the window every frame and `runUntilIdle()` throws.
@Test(.enabled(if: memoObservationIsSynchronous, "the armed count and the idle window are exact only where onChange is synchronous")) @MainActor func sessionsNeverExceedLiveEntries() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let param = IVParam()
    let on = IVCell()
    let window = try harnessWindow { VStack(spacing: 0) { SwitchHolder(param: param, on: on) } }
    let memos = window.window.testingContentMemos
    for _ in 0..<200 {
        param.k += 1
        await settle(); redraw(window)
        try #require(memos.armedSessions <= memos.entryCount)
    }
    try await window.runUntilIdle()
    #expect(memos.entryCount == 1 && memos.armedSessions == 1)
    MemoStats.reset()
    for _ in 0..<200 { redraw(window) }
    #expect(MemoStats.leaves == 0)
    #expect(memos.armedSessions <= memos.entryCount && memos.entryCount == 1)
    on.value = 1                     // the component leaves the tree
    await settle(); redraw(window)
    #expect(memos.entryCount == 0 && memos.armedSessions == 0)
}

private struct NeverEqual: Component, @MainActor Equatable {
    var content: some ElementGroup {
        let _ = MemoStats.leaves += 1
        Text("never").frame(width: Pixels(60), height: Pixels(14))
    }
    static func == (l: NeverEqual, r: NeverEqual) -> Bool { false }
}

/// 2.7b (`IV-L` item 5) — a component that re-evaluates every frame lets the window go
/// idle: the token write before each re-evaluation retires the previous session
/// without dirtying the window. The unequal-value arm of 2.7 changes its input only on
/// frames the test draws, so it cannot see this; here nothing but the frame itself
/// causes the re-evaluation. Mutation: the serial check dropped in the memo's
/// `onChange` — every miss's token write fires the previous session as a real change,
/// the window is dirtied from inside its own build and `runUntilIdle()` throws.
@Test(.enabled(if: memoObservationIsSynchronous, "the idle window is exact only where onChange is synchronous")) @MainActor func aComponentThatReEvaluatesEveryFrameLetsTheWindowIdle() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let window = try harnessWindow { VStack(spacing: 0) { NeverEqual().equatable() } }
    for _ in 0..<5 { redraw(window) }
    MemoStats.reset()
    try await window.runUntilIdle()
    let frames = window.framesDrawn
    redraw(window); redraw(window)
    #expect(MemoStats.leaves == 2, "it did re-evaluate on both forced frames")
    try await window.runUntilIdle()
    #expect(window.framesDrawn == frames + 2, "and nothing but the two forced frames was drawn")
}

/// 2.8 — a skipped component survives 50 forced redraws (the per-frame sentinel
/// flush of the window's own session) without re-evaluating. Mutation: the memo
/// session reading `redrawSentinel.tick` — every forced redraw fires it.
@Test @MainActor func aMemoSessionIsNotFlushedByTheWindowSentinel() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let param = IVParam()
    let window = try harnessWindow { VStack(spacing: 0) { TickerHolder(param: param) } }
    for _ in 0..<2 { redraw(window) }
    MemoStats.reset()
    for _ in 0..<50 { redraw(window) }
    #expect(MemoStats.leaves == 0)
    #expect(window.window.testingContentMemos.entryCount == 1)
}

// MARK: 2.9 — the differential

private final class DiffModel { var logs: [String] = [] }

private struct DiffCounter: Component, @MainActor Equatable {
    var memo: Bool
    @State var count = 0
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("count \(count)").frame(width: Pixels(80), height: Pixels(14))
            Button("up") { count += 1 }.frame(width: Pixels(40), height: Pixels(18))
                .background(Color.accent)
        }
    }
    static func == (l: DiffCounter, r: DiffCounter) -> Bool { l.memo && r.memo }
}

private struct DiffCell: Component, @MainActor Equatable {
    let cell: IVCell
    var memo: Bool
    var content: some ElementGroup {
        HStack(spacing: 4) {
            Text("cell \(cell.value)").frame(width: Pixels(70), height: Pixels(14))
            Box().frame(width: Pixels(Float(10 + cell.value % 5 * 6)), height: Pixels(8)).background(.accent)
                .offset(x: Pixels(Float(cell.value % 3)))
                .opacity(cell.value % 2 == 0 ? 1 : 0.5)
        }
    }
    static func == (l: DiffCell, r: DiffCell) -> Bool { l.memo && r.memo && l.cell === r.cell }
}

private struct DiffGroup: Component, @MainActor Equatable {
    let cells: [IVCell]
    var memo: Bool
    var content: some ElementGroup {
        VStack(spacing: 2) {
            DiffCounter(memo: memo).equatable()
            ForEach(Array(cells.indices), id: \.self) { DiffCell(cell: cells[$0], memo: memo).equatable() }
        }
    }
    static func == (l: DiffGroup, r: DiffGroup) -> Bool { l.memo && r.memo && l.cells.elementsEqual(r.cells, by: ===) }
}

private struct DiffRoot {
    let window: TestWindow
    let cells: [IVCell]
}

@MainActor private func diffWindow(memo: Bool) throws -> DiffRoot {
    let cells = (0..<6).map { _ in IVCell() }
    let window = try harnessWindow(size: sz(300, 400)) {
        VStack(spacing: 6) {
            DiffGroup(cells: Array(cells[0..<3]), memo: memo).equatable()
            DiffGroup(cells: Array(cells[3..<6]), memo: memo).equatable()
        }
    }
    return DiffRoot(window: window, cells: cells)
}

/// 2.9 — the differential (`IV-J`): the same tree with and without skipping (`==`
/// false everywhere is the unmemoized evaluation), twelve scripted writes (cell
/// writes singly and together, a state click, quiet frames, a resize): after every
/// frame the scene's rect, glyph and image arrays (byte for byte), the accessibility
/// tree, the hitbox list, the Tab order and the element bounds are equal. The memoized
/// side must also have skipped, or the test proves nothing. Mutation: the pristine
/// content copy taken after `requestGroupLayout` instead of before (stale layout
/// state leaks into the retained value) — reddens an equality.
@Test @MainActor func aMemoizedSubtreeDrawsTheSceneOfAnUnmemoizedOne() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let a = try diffWindow(memo: true)
    let b = try diffWindow(memo: false)
    var skipped = 0
    func compare(_ step: String) throws {
        let differences = try Snapshot(a.window).differences(from: Snapshot(b.window))
        #expect(differences.isEmpty, "after \(step): \(differences)")
        skipped += a.window.lastFrameWork.contentSkips
    }
    try compare("the first frame")
    let script: [(String, (DiffRoot) throws -> Void)] = [
        ("cell 0", { $0.cells[0].value += 1 }),
        ("cell 5", { $0.cells[5].value += 3 }),
        ("cells 1 and 4 together", { $0.cells[1].value += 1; $0.cells[4].value += 2 }),
        ("a quiet frame", { _ in }),
        ("a click", { try $0.window.click($0.window.elements(role: .button)[0]) }),
        ("cell 2", { $0.cells[2].value += 1 }),
        ("a second click", { try $0.window.click($0.window.elements(role: .button)[1]) }),
        ("a resize", { $0.window.resize(to: sz(260, 420)) }),
        ("cell 3 twice", { $0.cells[3].value += 1; $0.cells[3].value += 1 }),
        ("a quiet frame again", { _ in }),
        ("every cell", { r in r.cells.forEach { $0.value += 1 } }),
        ("cell 0 back", { $0.cells[0].value -= 2 }),
    ]
    for (name, step) in script {
        try step(a); try step(b)
        await settle()
        redraw(a.window); redraw(b.window)
        try compare(name)
    }
    #expect(skipped > 0, "the memoized side skipped nothing: the differential would prove nothing")
    #expect(b.window.lastFrameWork.contentSkips == 0)
}

// MARK: 2.10 — lifecycle, animation and List inside a memoized component

@MainActor private final class LifeLog { var appear = 0, disappear = 0, tasks = 0 }

private struct LifeItem: Component, @MainActor Equatable {
    let log: LifeLog
    let flag: Bool
    var memo: Bool
    @State var taps = 0
    var content: some ElementGroup {
        VStack(spacing: 0) {
            if flag {
                Text("life").frame(width: Pixels(50), height: Pixels(14))
                    .onAppear { log.appear += 1 }
                    .onDisappear { log.disappear += 1 }
                    .task { log.tasks += 1 }
            }
            Text("taps \(taps)").frame(width: Pixels(60), height: Pixels(14))
                .onClick { taps += 1 }
            Box().frame(width: Pixels(40), height: Pixels(10)).background(.accent)
                .opacity(flag ? 1 : 0.2)
                .animation(.linear(duration: 1), value: flag)
        }
    }
    static func == (l: LifeItem, r: LifeItem) -> Bool { l.memo && r.memo && l.flag == r.flag && l.log === r.log }
}

private struct ListRowData: Identifiable { let id: Int }

private struct ListPane: Component, @MainActor Equatable {
    var memo: Bool
    var content: some ElementGroup {
        ScrollView {
            List((0..<40).map(ListRowData.init), rowHeight: Pixels(20)) { row in
                StatefulCounter().frame(width: Pixels(80), height: Pixels(20)).id("\(row.id)")
            }
        }
    }
    static func == (l: ListPane, r: ListPane) -> Bool { l.memo && r.memo }
}

private struct LifeHolder: Component {
    let param: IVParam
    let log: LifeLog
    let memo: Bool
    var content: some ElementGroup {
        VStack(spacing: 0) {
            LifeItem(log: log, flag: param.k % 2 == 0, memo: memo).equatable()
            LifeItem(log: log, flag: true, memo: memo).equatable()   // a same-typed sibling with its own @State
            ListPane(memo: memo).equatable().frame(width: Pixels(100), height: Pixels(100))
        }
    }
}

/// 2.10 — lifecycle (`onAppear`/`onDisappear`/`task` counts), an animated opacity
/// (stepped on the simulated clock), a windowed `List` row's retention (`TB-AH`),
/// and two same-typed siblings with separate `@State`: identical to the same tree
/// with skipping off, frame by frame (scene bytes, accessibility tree) and in the
/// logs. Mutation: the entry keyed by the component's type alone, ignoring its id —
/// the two `LifeItem` siblings share one entry, so a tap on one shows in both and
/// the differential stays equal but the quiet frames evaluate the siblings against each other's entry and `contentEvaluations` reads above 0 (`IV-M`, `IV-P`).
@Test @MainActor func lifecycleAnimationAndListInsideAMemoizedComponent() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    func make(memo: Bool) throws -> (TestWindow, IVParam, LifeLog) {
        let param = IVParam(), log = LifeLog()
        let window = try harnessWindow(size: sz(300, 300)) { VStack(spacing: 0) { LifeHolder(param: param, log: log, memo: memo) } }
        return (window, param, log)
    }
    let (wa, pa, la) = try make(memo: true)
    let (wb, pb, lb) = try make(memo: false)
    func compare(_ step: String) throws {
        #expect(try Snapshot(wa).differences(from: Snapshot(wb)).isEmpty, "after \(step)")
        let (x, y): ([Int], [Int]) = ([la.appear, la.disappear, la.tasks], [lb.appear, lb.disappear, lb.tasks])
        #expect(x == y, "logs after \(step)")
    }
    try compare("the first frame")
    for step in 0..<3 {
        for (w, p) in [(wa, pa), (wb, pb)] { p.k += 1; _ = w }
        await settle()
        for w in [wa, wb] { redraw(w) }
        for w in [wa, wb] { w.advance(by: 0.3) }
        try compare("flip \(step)")
    }
    for w in [wa, wb] { try w.click(w.elements(where: { $0.label == "taps 0" })[0]) }
    for w in [wa, wb] { redraw(w); w.advance(by: 0.6) }
    try compare("a tap on the first item")
    for w in [wa, wb] { w.scroll(at: pt(50, 220), byDeltaX: 0, deltaY: -60) }
    for w in [wa, wb] { redraw(w) }
    try compare("a list scroll")
    // Quiet frames after the taps: the two same-typed siblings (separate `@State`, one
    // tapped) each keep their own entry, so nothing is evaluated (IV-P: a type-only key
    // cannot go stale, it thrashes — this count is what sees it).
    for w in [wa] { w.resetFrameWork() }
    for _ in 0..<3 { redraw(wa) }
    let quiet = wa.frameWork.dropFirst().reduce(wa.frameWork[0], +)
    #expect(quiet.contentEvaluations == 0 && quiet.contentSkips > 0, "evaluations \(quiet.contentEvaluations) skips \(quiet.contentSkips)")
}

// MARK: 2.13 — an off-main write

@Observable final class BackgroundCell: @unchecked Sendable { var value = 0 }

private struct BackgroundReader: Component, @MainActor Equatable {
    let cell: BackgroundCell
    var content: some ElementGroup {
        Text("b\(cell.value)").frame(width: Pixels(60), height: Pixels(14))
    }
    static func == (l: BackgroundReader, r: BackgroundReader) -> Bool { true }
}

/// 2.13 — a write from another thread reaches a skipped memo within one frame at
/// most (RX-K's limitation, pinned as it stands, `IV-C` item 5): after the hop and
/// one redraw the new value is drawn.
@Test @MainActor func aBackgroundThreadWriteDirtiesAMemoWithinOneFrame() async throws {
    await MemoGate.enter(); defer { MemoGate.leave() }
    let cell = BackgroundCell()
    let window = try TestWindow(size: sz(300, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 0) { BackgroundReader(cell: cell).equatable() }
    }
    for _ in 0..<3 { redraw(window) }
    await Task.detached { cell.value = 9 }.value
    await settle()
    redraw(window)
    _ = try window.element(label: "b9")
}
