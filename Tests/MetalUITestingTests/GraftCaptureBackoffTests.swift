@testable import MetalUI
import Foundation
import MetalUITesting
import Testing

// `RK-AG` (record 407): a graft record is made at the end of the frame, and only for an occurrence whose paint and prepaint left
// records, the only kind a later frame can graft from. A scrolling table inside nested `.equatable()` occurrences, and a focused
// text field inside them, left a record on every frame that the next frame could not use: the capture copied the table's whole
// subtree once per ancestor. Counts, never time; read after `runUntilIdle` (off Darwin a dirty mark hops through a Task) and summed
// over `frameWork`.

/// One `.equatable()` boundary around `inner`, whose value never changes.
private struct Shell<Inner: Component & Equatable>: Component, @MainActor Equatable {
    let inner: Inner
    var content: some ElementGroup { inner.equatable() }
    static func == (l: Shell, r: Shell) -> Bool { true }
}

private struct BigTable: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Table(CountingRows(1_000_000)) {
            TableColumnForEach(0..<20) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
        }
        .tableRowHeight(Pixels(24))
        .frame(width: Pixels(800), height: Pixels(600))
    }
    static func == (l: BigTable, r: BigTable) -> Bool { true }
}

private struct Typer: Component, @MainActor Equatable {
    @State var text = ""
    var content: some ElementGroup {
        TextField("name", text: $text).frame(width: Pixels(200), height: Pixels(24))
    }
    static func == (l: Typer, r: Typer) -> Bool { true }
}

/// Five occurrences: the outer one, three shells and the table's own.
@MainActor private func nestedTable() throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) { Shell(inner: Shell(inner: Shell(inner: Shell(inner: BigTable())))).equatable() }
    }
}

@MainActor private func nestedTyper() throws -> TestWindow {
    try harnessWindow(size: sz(400, 200)) {
        VStack(spacing: Pixels(0)) {
            Shell(inner: Shell(inner: Shell(inner: Shell(inner: Typer())))).equatable()
            TextField("other", text: Binding(get: { "" }, set: { _ in })).frame(width: Pixels(200), height: Pixels(24))
        }
    }
}

private let centre = Point(x: Pixels(400), y: Pixels(300))

@MainActor private func total(_ w: TestWindow) -> FrameWork { w.frameWork.reduce(FrameWork(), +) }

/// What a frame's work comes to, without the fields this milestone adds: the ones a test compares with master's.
private struct Today: Equatable, CustomStringConvertible {
    var requests: Int, hits: Int, grafts: Int, skippedRequests: Int, misses: Int
    init(requests: Int, hits: Int, grafts: Int, skippedRequests: Int, misses: Int) {
        self.requests = requests; self.hits = hits; self.grafts = grafts; self.skippedRequests = skippedRequests; self.misses = misses
    }
    init(_ f: FrameWork) {
        requests = f.elementRequests; hits = f.retainedHits; grafts = f.retainedGrafts
        skippedRequests = f.retainedSkippedRequests; misses = f.retainedMisses
    }
    var description: String { "requests \(requests) hits \(hits) grafts \(grafts) skippedRequests \(skippedRequests) misses \(misses)" }
}

/// A settled window: one frame per scroll step, then the pointer leaves and the clock runs out the scroll indicator's fade.
@MainActor private func scrolledTable(steps: Int) async throws -> (TestWindow, FrameWork) {
    let w = try nestedTable()
    try await w.runUntilIdle()
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    for _ in 0..<steps {
        w.scroll(at: centre, byDeltaX: 0, deltaY: -48)
        try await w.runUntilIdle()
    }
    return (w, total(w))
}

/// **1** A scrolling table inside five `.equatable()` occurrences leaves no graft record on any frame: each step's paint is
/// ineligible (the scroll indicator's animation and the scroll write), so no later frame can graft from what the build made, and
/// the copy of the table's rows is not made. Master copied them 30 times (5 occurrences x 6 steps). The frame's own work does not
/// move: 3384 requests, no hit. **Mutation:** `flushPendingGrafts` capturing whatever the entry holds (`captures` reads 30).
@Test @MainActor func aScrollingTableInsideNestedEquatablesCopiesNoRows() async throws {
    let (_, f) = try await scrolledTable(steps: 6)
    #expect(f.retainedGraftCaptures == 0 && f.retainedGraftCapturesSkipped == 30,
            "captures \(f.retainedGraftCaptures), skipped \(f.retainedGraftCapturesSkipped)")
    #expect(Today(f) == Today(requests: 3384, hits: 0, grafts: 0, skippedRequests: 0, misses: 0), "\(Today(f))")
}

/// **2** A focused text field inside five occurrences: the pointer, press and focus rule leaves no paint record on any key, so no
/// record is copied; six keys, 30 builds of an occurrence, no capture, and the requests are what master made (24, the other field's included). **Mutation:** as 1.
@Test @MainActor func aFocusedTextFieldInsideNestedEquatablesCopiesNoRows() async throws {
    let w = try nestedTyper()
    try await w.runUntilIdle()
    w.typeKey(.tab)
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    for _ in 0..<6 { w.typeText("a"); try await w.runUntilIdle() }
    let f = total(w)
    #expect(f.retainedGraftCaptures == 0 && f.retainedGraftCapturesSkipped == 30,
            "captures \(f.retainedGraftCaptures), skipped \(f.retainedGraftCapturesSkipped)")
    #expect(Today(f) == Today(requests: 24, hits: 0, grafts: 0, skippedRequests: 0, misses: 30), "\(Today(f))")
}

/// **3** The first frame after the scrolling stops copies again, so the frame after it grafts as it does without the rule: scroll
/// six steps, the pointer leaves, the indicator's fade runs out (that frame builds and copies five rows), and the next frame is one
/// graft that stands for the 564 requests of the build, in every frame after. **Mutation:** `flushPendingGrafts` never capturing
/// (the frames after the scroll then rebuild, `grafts` reads 0 and `requests` 564); capturing always leaves 1 and 2 red.
@Test @MainActor func theFirstFrameAfterScrollingStopsCopiesAndTheNextOneGrafts() async throws {
    let (w, _) = try await scrolledTable(steps: 6)
    w.exitPointer()
    w.resetFrameWork()
    w.advance(by: 1)
    let first = total(w)
    #expect(first.retainedGraftCaptures == 5 && first.retainedGraftCapturesSkipped == 0,
            "captures \(first.retainedGraftCaptures), skipped \(first.retainedGraftCapturesSkipped)")
    #expect(Today(first) == Today(requests: 564, hits: 0, grafts: 0, skippedRequests: 0, misses: 5), "\(Today(first))")
    for _ in 0..<3 {
        w.resetFrameWork()
        w.window.setNeedsRedraw(); w.tick()
        let f = total(w)
        #expect(Today(f) == Today(requests: 0, hits: 1, grafts: 1, skippedRequests: 564, misses: 0), "\(Today(f))")
        #expect(f.retainedGraftCaptures == 0, "a grafted frame builds nothing to copy: \(f.retainedGraftCaptures)")
    }
}

/// **4** The same for typing: while the field holds focus no record is copied; the key that moves focus out of the chain leaves
/// paint records, the frame after builds and copies, and the one after grafts. **Mutation:** as 3.
@Test @MainActor func theFirstFrameAfterTypingStopsCopiesAndTheNextOneGrafts() async throws {
    let w = try nestedTyper()
    try await w.runUntilIdle()
    w.typeKey(.tab)
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    for _ in 0..<3 { w.typeText("a"); try await w.runUntilIdle() }
    w.typeKey(.tab)   // to the second field, outside every occurrence
    try await w.runUntilIdle()
    // The frame the focus leaves in still paints under it; the next builds and copies; the one after grafts.
    let expected: [(Today, Int, Int)] = [
        (Today(requests: 4, hits: 0, grafts: 0, skippedRequests: 0, misses: 5), 0, 5),
        (Today(requests: 4, hits: 0, grafts: 0, skippedRequests: 0, misses: 5), 5, 0),
        (Today(requests: 2, hits: 1, grafts: 1, skippedRequests: 2, misses: 0), 0, 0),
        (Today(requests: 2, hits: 1, grafts: 1, skippedRequests: 2, misses: 0), 0, 0),
    ]
    for (index, want) in expected.enumerated() {
        w.resetFrameWork()
        w.window.setNeedsRedraw(); w.tick()
        let f = total(w)
        #expect(Today(f) == want.0, "frame \(index): \(Today(f))")
        #expect(f.retainedGraftCaptures == want.1 && f.retainedGraftCapturesSkipped == want.2,
                "frame \(index): captures \(f.retainedGraftCaptures), skipped \(f.retainedGraftCapturesSkipped)")
    }
}
