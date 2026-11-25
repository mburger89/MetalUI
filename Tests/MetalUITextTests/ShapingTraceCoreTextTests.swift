import Foundation
import Testing
import MetalUITextSystem
@testable import MetalUIText

// `METALUI_TRACE_SHAPING=1` through `ShapingCache` and `CoreTextTextSystem` (`TS-E`, record 406): the CoreText arm of
// `ShapingTraceTests` in `MetalUITestingTests`. The switch and the sink are the package's, never the process environment.

private func font(_ size: Double) -> ResolvedFont { FontResolver.resolve(family: nil, size: size) }

@MainActor private final class Sink { var lines: [String] = [] }

@MainActor private func traced(_ body: () -> Void) -> [String] {
    let lines = Sink()
    ShapingTrace.sink = { lines.lines.append($0) }
    ShapingTrace.active = true
    defer { ShapingTrace.active = false; ShapingTrace.sink = nil }
    body()
    return lines.lines
}

/// **1** Two frames through the cache: the first misses both strings, the second (unchanged) only hits, a changed string
/// misses alone, and the same string at another size is a miss that differs only in its key. **Mutations:** `hit()` not
/// called in `shaped` (frame 2 reports 0 hits); `finish` not clearing (frame 2 reports frame 1's misses); the font left out of
/// `entry` (the two sizes read alike).
@MainActor @Test func theCoreTextCacheReportsHitsMissesAndTheKeyPerFrame() {
    let cache = ShapingCache()
    let lines = traced {
        for step in 0..<3 {
            cache.beginFrame()
            _ = cache.shaped("hello world", font: font(13), wrappingAt: 100)
            _ = cache.shaped(step == 2 ? "changed" : "second", font: font(13), wrappingAt: nil)
            if step == 2 { _ = cache.shaped("hello world", font: font(15), wrappingAt: 100) }
            cache.endFrame()
        }
    }
    #expect(lines.count == 3, "\(lines)")
    guard lines.count == 3 else { return }
    #expect(lines[0].hasPrefix("shaping frame 1: hits 0 misses 2 [coretext] missed: \"hello world\"("), "\(lines[0])")
    #expect(lines[0].contains(" 13 var=1 w=100), \"second\"(") || lines[0].contains(" 13 w=100), \"second\"(") && !lines[0].contains("uncached"), "\(lines[0])")
    #expect(lines[1] == "shaping frame 2: hits 2 misses 0 [coretext]", "\(lines[1])")
    #expect(lines[2].hasPrefix("shaping frame 3: hits 1 misses 2 [coretext] missed: \"changed\"("), "\(lines[2])")
    #expect(lines[2].contains("\"hello world\"(") && lines[2].contains(" 15 var=1 w=100)") || lines[2].contains(" 15 w=100)"), "\(lines[2])")
}

/// **2** `caretOffsets` goes through the cache (`TS-F`): the first read is a miss listed by its `(caretOffsets …)` key, the
/// second, in the next frame, a hit, and nothing is listed as `uncached:`. **Mutations:** the miss not traced in
/// `ShapingCache.caretOffsets`; `CoreTextTextSystem.caretOffsets` going back to `Shaper.caretOffsets` (the second frame
/// misses again).
@MainActor @Test func aCaretOffsetsCallIsACachedLookupTheTraceCanSee() {
    let cache = ShapingCache()
    let system = CoreTextTextSystem(cache: cache)
    let key = system.resolveFont(FontDescriptor(family: nil, size: 13))
    let lines = traced {
        for _ in 0..<2 {
            cache.beginFrame()
            _ = system.measure("typed text", font: key, wrappingAt: nil, options: TextLayoutOptions())
            _ = system.caretOffsets("typed text", font: key)
            _ = system.caretOffsets("", font: key)
            cache.endFrame()
        }
    }
    #expect(lines.count == 2, "\(lines)")
    guard lines.count == 2 else { return }
    #expect(lines[0].contains("hits 0 misses 2 [coretext]") && lines[0].contains("\"typed text\"(caretOffsets ")
            && !lines[0].contains("uncached"), "\(lines[0])")
    #expect(lines[1].contains("hits 2 misses 0 [coretext]") && !lines[1].contains("uncached"), "\(lines[1])")
}

/// **3** Off, the cache describes nothing and writes nothing. **Mutation:** the `ShapingTrace.active` guard dropped around
/// `trace.miss(ShapingTrace.entry(…))` (`described` moves).
@MainActor @Test func aCacheWithTracingOffDescribesNothing() {
    let cache = ShapingCache()
    var lines: [String] = []
    ShapingTrace.sink = { lines.append($0) }
    defer { ShapingTrace.sink = nil }
    ShapingTrace.described = 0
    for _ in 0..<3 {
        cache.beginFrame()
        _ = cache.shaped("hello", font: font(13), wrappingAt: 100)
        cache.traceBypass("never built")
        cache.endFrame()
    }
    #expect(ShapingTrace.described == 0 && lines.isEmpty && !ShapingTrace.active)
}
