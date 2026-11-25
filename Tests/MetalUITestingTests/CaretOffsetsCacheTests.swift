import Foundation
import Observation
import MetalUI
import MetalUITesting
import MetalUITextSystem
import Testing

// Text fields and the caret-offsets cache (`TS-F`, record 411): what a key stroke and an idle frame ask the text system for,
// read through the shaping trace (`TS-E`), counts only. Caret placement, click-to-caret, selection and IME results are the
// existing field suites' (`TextFieldTests`, `HarnessInputTests`, `HarnessInputMethodTests`, `TextSelectionTests`), which run
// through the same cache and are unchanged.

@MainActor private final class Sink { var lines: [String] = [] }

/// `body` with the trace on; the lines it wrote. The switch, the sink and the counter are restored after.
@MainActor private func tracing(_ body: () async throws -> Void) async rethrows -> [String] {
    let sink = Sink()
    ShapingTrace.sink = { sink.lines.append($0) }
    ShapingTrace.active = true
    defer { ShapingTrace.active = false; ShapingTrace.sink = nil }
    try await body()
    return sink.lines
}

/// The caret lookups a trace's lines list, as (computed, uncached): a `(caretOffsets …)` entry after `missed:` is one
/// typeset line, and after `uncached:` a shape no cache answered.
private func caretWork(_ lines: [String]) -> (computed: Int, uncached: Int) {
    var computed = 0, uncached = 0
    for line in lines {
        let missed = line.range(of: " missed: ").map { String(line[$0.upperBound...]) } ?? ""
        let split = missed.components(separatedBy: " uncached: ")
        computed += split[0].components(separatedBy: "(caretOffsets ").count - 1
        uncached += (split.count > 1 ? split[1] : "").components(separatedBy: "(caretOffsets ").count - 1
        if !line.contains(" missed: "), let range = line.range(of: " uncached: ") {
            uncached += String(line[range.upperBound...]).components(separatedBy: "(caretOffsets ").count - 1
        }
    }
    return (computed, uncached)
}

@Observable @MainActor private final class CaretDraft { var text = "" }

private struct Composer: Component {
    let draft: CaretDraft
    var content: some ElementGroup {
        TextField("Message", text: Binding(get: { draft.text }, set: { draft.text = $0 }))
            .accessibilityIdentifier("composer").frame(width: Pixels(300), height: Pixels(28))
    }
}

/// **1** A focused field typing 20 keys asks for caret offsets once per key (the string changed once, prepaint typesets it
/// and paint reads it again) and never takes the uncached path. Before the cache it was twice a key, both uncached.
/// **Mutations:** `PortableTextSystem.caretOffsets` not storing (40 computed); the call going back to `trace.bypass` (20
/// uncached).
@Test @MainActor func aFocusedFieldTypingTwentyKeysTypesetsItsCaretLineOncePerKey() async throws {
    let draft = CaretDraft()
    let lines = try await tracing {
        let w = try harnessWindow { VStack(spacing: 0) { Composer(draft: draft) } }
        try await w.runUntilIdle()
        w.click(at: pt(200, 150))
        for key in "the quick brown fox." { w.typeText(String(key)) }
        #expect(draft.text == "the quick brown fox.")
    }
    let work = caretWork(lines)
    #expect(work.uncached == 0, "\(work)")
    #expect(work.computed == 20, "one per key: \(work)")
}

/// **2** An unfocused, empty field across 30 frames in which other text changes asks for no caret offsets at all, computed or
/// not. **Mutations:** the empty-string guard removed from `caretOffsets` (one computed); the field asking for offsets of
/// its placeholder.
@Test @MainActor func anEmptyUnfocusedFieldAsksForNoCaretOffsetsWhileOtherTextChanges() async throws {
    let draft = CaretDraft(), other = CaretDraft()
    let lines = try await tracing {
        let w = try harnessWindow {
            VStack(spacing: 0) {
                Text(other.text).frame(width: Pixels(300), height: Pixels(20))
                Composer(draft: draft)
            }
        }
        w.clearTheFirstDrawSeat()
        try await w.runUntilIdle()
        for frame in 0..<30 {
            other.text = "streamed \(frame)"
            try await w.runUntilIdle()
        }
    }
    #expect(lines.count >= 30 && lines.contains { $0.contains("streamed 29") }, "frames were traced: \(lines.count)")
    #expect(caretWork(lines) == (0, 0) && !lines.contains { $0.contains("caretOffsets") }, "\(lines.suffix(3))")
}

/// **3** A non-empty field that is not focused and not changing pays nothing per frame: its offsets were typeset when its
/// text arrived, and the frames after only hit. **Mutation:** the cache keyed on the frame.
@Test @MainActor func anIdleFieldWithTextTypesetsItsCaretLineOnceNotPerFrame() async throws {
    let draft = CaretDraft(), other = CaretDraft()
    draft.text = "already written"
    let lines = try await tracing {
        let w = try harnessWindow {
            VStack(spacing: 0) {
                Text(other.text).frame(width: Pixels(300), height: Pixels(20))
                Composer(draft: draft)
            }
        }
        w.clearTheFirstDrawSeat()
        try await w.runUntilIdle()
        for frame in 0..<10 {
            other.text = "streamed \(frame)"
            try await w.runUntilIdle()
        }
    }
    #expect(caretWork(lines).computed == 1 && caretWork(lines).uncached == 0, "\(caretWork(lines))")
}
