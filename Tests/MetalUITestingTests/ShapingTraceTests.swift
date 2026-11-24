import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
#if canImport(Darwin)
import MetalUITestSupport
#endif

// `METALUI_TRACE_SHAPING=1` (`TS-E`, record 406), through the portable text system the harness uses: one line per frame that
// looked a shape up, its hits and misses, and each missed string with the key that made it miss. Every test turns the trace on
// through `ShapingTrace.active` and reads `ShapingTrace.sink`, never the process environment, and restores both. Counts and
// strings, never time. The CoreText system's arm is `ShapingTraceCoreTextTests` (Darwin).

@Observable @MainActor private final class Words {
    var first = "alpha beta"
    var second = "gamma"
}

private struct Pair: Component {
    let words: Words
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text(words.first).frame(width: Pixels(200), height: Pixels(20))
            Text(words.second).frame(width: Pixels(200), height: Pixels(20))
        }
    }
}

/// The lines a trace wrote (a class: the sink and the body both read it).
@MainActor private final class Sink { var lines: [String] = [] }

/// Runs `body` with the trace on and its lines collected; restores the switch, the sink and the counter after.
@MainActor private func tracing(_ body: (Sink) async throws -> Void) async rethrows -> [String] {
    let lines = Sink()
    ShapingTrace.sink = { lines.lines.append($0) }
    ShapingTrace.active = true
    ShapingTrace.described = 0
    defer { ShapingTrace.active = false; ShapingTrace.sink = nil }
    try await body(lines)
    return lines.lines
}

private func counts(_ line: String) -> (hits: Int, misses: Int)? {
    let words = line.split(separator: " ")
    guard let h = words.firstIndex(of: "hits"), let m = words.firstIndex(of: "misses"),
          let hv = Int(words[h + 1]), let mv = Int(words[m + 1]) else { return nil }
    return (hv, mv)
}

/// **1** The first frame misses every string, a redraw of unchanged text only hits, and a changed string is the one miss. The
/// line names the system and the key: font, size and wrapping width. **Mutations:** `Recorder.finish` not clearing its counts
/// (frame 2's hits include frame 1's misses); `miss` not recording the entry (the list is empty); `hit()` counting a miss.
@Test @MainActor func eachFrameReportsItsHitsMissesAndMissedStrings() async throws {
    let words = Words()
    let lines = try await tracing { lines in
        let w = try harnessWindow { Box { Pair(words: words) } }
        try await w.runUntilIdle()
        let first = lines.lines.count
        try #require(first >= 1, "the first frame wrote a line")
        w.window.setNeedsRedraw(); w.tick()
        let steady = lines.lines.count
        words.first = "alpha beta changed"
        try await w.runUntilIdle()
        try #require(lines.lines.count > steady && steady > first, "a line per frame: \(first), \(steady), \(lines.lines.count)")
    }
    // Frame 1: nothing was cached, so every lookup missed, in a window that has no hits yet.
    let one = try #require(counts(lines[0]))
    #expect(one.misses >= 2 && lines[0].contains("[portable]"), "\(lines[0])")
    #expect(lines[0].contains("\"alpha beta\"(") && lines[0].contains("\"gamma\"("), "\(lines[0])")
    // The steady redraw: all hits, no miss, no `missed:` list.
    let steadyLine = try #require(lines.first { counts($0)?.misses == 0 }, "a frame with no miss: \(lines)")
    #expect(steadyLine.hasPrefix("shaping frame ") && !steadyLine.contains("missed:"), "\(steadyLine)")
    #expect((counts(steadyLine)?.hits ?? 0) >= 2, "\(steadyLine)")
    // The changed string: it alone misses, once at the width it was measured at (200) and once at the width it is drawn at.
    let changed = try #require(lines.last { $0.contains("alpha beta changed") }, "\(lines)")
    #expect(counts(changed)?.misses == 2 && (counts(changed)?.hits ?? 0) >= 1, "\(changed)")
    #expect(changed.contains("missed: \"alpha beta changed\"(NotoSans-Regular 13 w=200), \"alpha beta changed\"(NotoSans-Regular 13 w="),
            "\(changed)")
    #expect(!changed.contains("\"gamma\"("), "the unchanged string did not miss: \(changed)")
}

/// **2** A string over 40 characters is cut with `…`, a newline is escaped, and more than 20 misses list 20 and `+K more`.
/// **Mutations:** `maxCharacters` 41; the escape of `\n` removed; the list cap removed.
@Test @MainActor func missedStringsAreTruncatedEscapedAndCapped() {
    let long = String(repeating: "x", count: 60)
    #expect(ShapingTrace.quoted(long) == "\"" + String(repeating: "x", count: 40) + "…\"")
    #expect(ShapingTrace.quoted("a\nb\t\"c\"\\") == "\"a\\nb\\t\\\"c\\\"\\\\\"")
    #expect(ShapingTrace.quoted("exactly forty characters long, exactly") == "\"exactly forty characters long, exactly\"")
    var lines: [String] = []
    ShapingTrace.sink = { lines.append($0) }
    defer { ShapingTrace.sink = nil }
    var recorder = ShapingTrace.Recorder()
    for i in 0..<25 { recorder.miss("\"s\(i)\"(f)") }
    recorder.hit()
    recorder.finish(frame: 7, system: "test")
    #expect(lines.count == 1)
    let line = lines[0]
    #expect(line.hasPrefix("shaping frame 7: hits 1 misses 25 [test] missed: \"s0\"(f), "), "\(line)")
    #expect(line.contains("\"s19\"(f), +5 more") && !line.contains("\"s20\""), "\(line)")
    // A frame with nothing looked up writes nothing, and the counts are cleared after a line.
    recorder.finish(frame: 8, system: "test")
    #expect(lines.count == 1 && recorder.hits == 0 && recorder.misses == 0)
}

/// **3** The key says why a string re-shapes: the same string at another width or size is a second miss that differs only in
/// its key. **Mutation:** `describe(width:options:)` dropping the width.
@Test @MainActor func twoMissesOfOneStringShowTheKeyThatDiffers() async throws {
    let words = Words()
    let lines = try await tracing { _ in
        let w = try harnessWindow { Box { Pair(words: words) } }
        try await w.runUntilIdle()
    }
    let key = ShapingTrace.entry("hello", font: try #require(font(size: 13)), width: 120, options: TextLayoutOptions())
    let other = ShapingTrace.entry("hello", font: try #require(font(size: 14)), width: nil,
                                   options: TextLayoutOptions(maxLines: 2, truncation: .middle, alignment: .center))
    #expect(key.hasSuffix(" 13 w=120)") && key.hasPrefix("\"hello\"("), "\(key)")
    #expect(other.hasSuffix(" 14 lines=2 trunc=middle align=center)"), "\(other)")
    #expect(!lines.isEmpty)
}

@MainActor private func font(size: Double) -> FontKey? {
    harnessTextSystem().resolveFont(FontDescriptor(family: nil, size: size))
}

/// **4** Off, nothing is described: steady frames, a changed string and a keystroke build no description (`described` stays 0)
/// and write no line, and the frame's counted work equals the traced frame's. On Darwin the traced steady frame allocates more
/// than the untraced one (the control: the counter is sensitive). **Mutations:** `quoted` or `entry` built outside the
/// `if ShapingTrace.active` guard in a cache (`described` moves); the off path appending to the recorder.
@Test @MainActor func aWindowWithTracingOffBuildsNothingAndCostsTheSameWork() async throws {
    func work(_ on: Bool) async throws -> (work: FrameWork, described: Int, lines: Int, allocations: Int?) {
        let words = Words()
        var lines: [String] = []
        ShapingTrace.sink = { lines.append($0) }
        ShapingTrace.active = on
        ShapingTrace.described = 0
        defer { ShapingTrace.active = false; ShapingTrace.sink = nil }
        let w = try harnessWindow { Box { Pair(words: words) } }
        try await w.runUntilIdle()
        for i in 0..<3 { words.second = "gamma \(i)"; try await w.runUntilIdle() }
        w.window.setNeedsRedraw(); w.tick()
        w.resetFrameWork()
        w.window.setNeedsRedraw(); w.tick()
        let total = w.frameWork.reduce(FrameWork(), +)
        var allocations: Int?
        #if canImport(Darwin)
        allocations = countAllocations { w.window.setNeedsRedraw(); w.tick() }
        #endif
        return (total, ShapingTrace.described, lines.count, allocations)
    }
    let off = try await work(false)
    let on = try await work(true)
    #expect(off.described == 0 && off.lines == 0, "off built \(off.described) descriptions, wrote \(off.lines) lines")
    #expect(on.described > 0 && on.lines > 0, "control: on built \(on.described) descriptions, wrote \(on.lines) lines")
    #expect(off.work == on.work, "the frame's counted work does not depend on the trace: \(off.work) vs \(on.work)")
    #expect(off.work.elementRequests > 0, "control: the frame did work")
    if let a = off.allocations, let b = on.allocations { #expect(a < b, "off \(a) allocations vs on \(b)") }
}
