import MetalUI
import MetalUITesting
import Observation
import Testing

// Sift gap G14 (record 393): a write to an `@Observable` property that only a memoized (`.equatable()`) component's
// body reads rebuilds that subtree and nothing above it. Every count is a body counter; frame work is summed after
// `runUntilIdle` (off Darwin a dirty mark hops through a Task).

@Observable @MainActor private final class MbModel { var version = 0; var other = 0 }
@MainActor private final class MbCounts: @MainActor Equatable {
    var top = 0, middle = 0, memo = 0, sibling = 0
    static func == (a: MbCounts, b: MbCounts) -> Bool { a === b }
}

private struct MbMemo: Component, @MainActor Equatable {
    let model: MbModel
    let counts: MbCounts
    static func == (a: MbMemo, b: MbMemo) -> Bool { a.model === b.model }
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = { counts.memo += 1 }()
        Text("v\(model.version)")
    }
}

private struct MbSibling: Component, @MainActor Equatable {
    let counts: MbCounts
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = { counts.sibling += 1 }()
        Text("sibling")
    }
}

/// Parents above the memo. Plain unless written `.equatable()`, as Sift's `RelationDetailView` and `GridView`.
private struct MbMiddle: Component, @MainActor Equatable {
    let model: MbModel
    let counts: MbCounts
    static func == (a: MbMiddle, b: MbMiddle) -> Bool { a.model === b.model }
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = { counts.middle += 1 }()
        VStack(spacing: 0) {
            MbMemo(model: model, counts: counts).equatable()
            MbSibling(counts: counts).equatable()
        }
    }
}

private struct MbTop: Component, @MainActor Equatable {
    let model: MbModel
    let counts: MbCounts
    let memoizedMiddle: Bool
    static func == (a: MbTop, b: MbTop) -> Bool { a.model === b.model && a.memoizedMiddle == b.memoizedMiddle }
    var content: some ElementGroup {
        // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
        let _ = { counts.top += 1 }()
        if memoizedMiddle {
            MbMiddle(model: model, counts: counts).equatable()
        } else {
            MbMiddle(model: model, counts: counts)
        }
    }
}

@MainActor private func mbRun(memoizedParents: Bool, counts: MbCounts, model: MbModel,
                              write: @MainActor () -> Void) async throws -> (top: Int, middle: Int, memo: Int, sibling: Int, frames: Int) {
    let w = try harnessWindow {
        Column {
            if memoizedParents { MbTop(model: model, counts: counts, memoizedMiddle: true).equatable() }
            else { MbTop(model: model, counts: counts, memoizedMiddle: false) }
        }
    }
    try await w.runUntilIdle()
    #expect(counts.top >= 1 && counts.middle >= 1 && counts.memo >= 1 && counts.sibling >= 1, "the first build ran everything")
    let b = (counts.top, counts.middle, counts.memo, counts.sibling)
    w.resetFrameWork()
    write()
    try await w.runUntilIdle()
    let frames = w.frameWork.count
    let delta = (counts.top - b.0, counts.middle - b.1, counts.memo - b.2, counts.sibling - b.3, frames)
    // Not vacuous, and a settled window asks for nothing more.
    w.resetFrameWork()
    try await w.runUntilIdle()
    #expect(w.frameWork.isEmpty, "the window drew \(w.frameWork.count) more frames")
    return delta
}

/// **M1** (`IV-S`, divergence 243) A write read only inside an `.equatable()` body rebuilds that body once and, because
/// the frame re-evaluates every plain component above it, each plain ancestor once; a memoized sibling not at all.
/// Mutation: `ContentMemoStore`'s per-memo handler not dirtying the window (the reader stays stale, `memo == 0`).
@Test @MainActor func aWriteReadOnlyBelowAMemoBoundaryCostsThatSubtreeAndOneBuildOfEachPlainAncestor() async throws {
    let model = MbModel(), counts = MbCounts()
    let d = try await mbRun(memoizedParents: false, counts: counts, model: model) { model.version += 1 }
    #expect(d.memo == 1, "the reader rebuilt \(d.memo) times")
    // One frame on Darwin; off Darwin the dirty mark hops through a Task and a write sometimes takes a second frame (`IV-Q`, record 395),
    // which rebuilds every plain component again and the memoized reader not at all. So: once per frame.
    #if canImport(Darwin)
    #expect(d.frames == 1)
    #endif
    #expect(d.frames >= 1 && d.top == d.frames && d.middle == d.frames, "plain ancestors rebuilt \(d.top), \(d.middle) times in \(d.frames) frames")
    #expect(d.sibling == 0, "the memoized sibling rebuilt \(d.sibling) times")
}

/// **M2** Ancestors written `.equatable()` (the remedy `IV-S` names) cost nothing: only the reader rebuilds. Mutation: the
/// memo's `==` replaced by `false` in `MbTop` (the ancestors rebuild again).
@Test @MainActor func memoizedAncestorsAboveAMemoBoundaryAreNotRebuiltByItsWrite() async throws {
    let model = MbModel(), counts = MbCounts()
    let d = try await mbRun(memoizedParents: true, counts: counts, model: model) { model.version += 1 }
    #expect(d.memo == 1, "the reader rebuilt \(d.memo) times")
    #expect(d.frames >= 1 && d.top == 0 && d.middle == 0 && d.sibling == 0, "ancestors \(d.top), \(d.middle), sibling \(d.sibling)")
}

/// **M3** A write nobody reads draws no frame and rebuilds nothing.
@Test @MainActor func aWriteNobodyReadsRebuildsNothing() async throws {
    let model = MbModel(), counts = MbCounts()
    let d = try await mbRun(memoizedParents: false, counts: counts, model: model) { model.other += 1 }
    #expect(d.frames == 0 && d.top == 0 && d.middle == 0 && d.memo == 0 && d.sibling == 0)
}

// MARK: - The first sibling redraw beside a settled memoized subtree (Sift's Linux observation)

@Observable @MainActor private final class MbTyped { var text = "" }

private struct MbHeavy: Component, @MainActor Equatable {
    static func == (a: MbHeavy, b: MbHeavy) -> Bool { true }
    var content: some ElementGroup {
        VStack(spacing: 0) { for i in 0..<8 { Text("row \(i)") } }
    }
}

/// Heavy, and reads an `@Observable` of its own (Sift's `GridTable` reads `pagesVersion`).
private struct MbObsHeavy: Component, @MainActor Equatable {
    let model: MbModel
    static func == (a: MbObsHeavy, b: MbObsHeavy) -> Bool { a.model === b.model }
    var content: some ElementGroup {
        VStack(spacing: 0) { for i in 0..<8 { Text("row \(i) v\(model.version)") } }
    }
}

private struct MbBar: Component {
    let typed: MbTyped
    var content: some ElementGroup { Text("typed \(typed.text)") }
}

/// **M4** After a window settles, the first redraw caused by a sibling's write costs what the second costs: the memoized
/// subtree is replayed, not re-requested. Sift saw the first one re-request every element on Linux only. Every count is read
/// after `runUntilIdle` and summed over `frameWork` (off Darwin a dirty mark hops through a Task).
@Test(arguments: [false, true]) @MainActor func theFirstSiblingRedrawBesideASettledMemoReplaysAsTheSecondDoes(readsModel: Bool) async throws {
    let typed = MbTyped(), model = MbModel()
    let w = try harnessWindow { Column { MbBar(typed: typed); if readsModel { MbObsHeavy(model: model).equatable() } else { MbHeavy().equatable() } } }
    try await w.runUntilIdle()
    func redraw(_ s: String) async throws -> Int {
        w.resetFrameWork()
        typed.text += s
        try await w.runUntilIdle()
        let all = w.frameWork.reduce(FrameWork(), +)
        #expect(all.builds > 0, "the sibling redrew")
        return all.elementRequests
    }
    let first = try await redraw("a"), second = try await redraw("b"), third = try await redraw("c")
    print("MB sibling readsModel=\(readsModel) first/second/third elementRequests: \(first) \(second) \(third)")
    #expect(second == third, "the steady redraw is stable: \(second) then \(third)")
    #expect(first == second, "the first redraw requested \(first) elements, the second \(second)")
}

private struct MbTable: Component, @MainActor Equatable {
    static func == (a: MbTable, b: MbTable) -> Bool { true }
    var content: some ElementGroup {
        Table(CountingRows(1_000)) {
            TableColumnForEach(0..<6) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(80)) }
        }
        .tableRowHeight(Pixels(24))
        .frame(width: Pixels(500), height: Pixels(300))
    }
}

private struct MbField: Component {
    let typed: MbTyped
    var content: some ElementGroup {
        TextField("search", text: Binding(get: { typed.text }, set: { typed.text = $0 }))
            .accessibilityIdentifier("mb.field").frame(width: Pixels(120), height: Pixels(24))
    }
}

/// **M5** Sift's own shape: a focused text field beside a settled memoized subtree, typing. The first keystroke's frame costs what
/// the later ones cost (Sift saw the first one re-request every element on Linux only).
@Test(arguments: [false, true]) @MainActor func theFirstKeystrokeBesideASettledMemoCostsAsTheLaterOnesDo(table: Bool) async throws {
    let typed = MbTyped()
    let w = try harnessWindow(size: sz(600, 400)) {
        Column { MbField(typed: typed); if table { MbTable().equatable() } else { MbHeavy().equatable() } }
    }
    try await w.runUntilIdle()
    try w.click(try w.element(identifier: "mb.field"))
    try await w.runUntilIdle()
    var costs: [Int] = []
    for ch in ["a", "b", "c", "d"] {
        w.resetFrameWork()
        w.typeText(ch)
        try await w.runUntilIdle()
        let all = w.frameWork.reduce(FrameWork(), +)
        #expect(all.builds > 0, "the keystroke redrew")
        costs.append(all.elementRequests)
    }
    print("MB keystroke table=\(table) elementRequests: \(costs)")
    #expect(typed.text == "abcd")
    #expect(Set(costs).count == 1, "element requests per keystroke: \(costs)")
}
