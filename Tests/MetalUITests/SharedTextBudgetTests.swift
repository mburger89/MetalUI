#if canImport(CoreText)
import Foundation
import MetalUI
import MetalUITesting
import MetalUITextSystem
import Testing
@testable import MetalUIText

// One window, one text system: the shaping cache's budget bounds the stale entries and never the working set (`TS-G`, record
// 421). Counts only, never time. The first version of the budget (`TS-F`, record 411) was sized from each view alone, and a
// window showing a table, a transcript, a code view and a composer together has a live set none of them has by itself.

private struct TableRows: RandomAccessCollection {
    var startIndex: Int { 0 }
    var endIndex: Int { 1_000_000 }
    subscript(position: Int) -> Row { Row(id: position) }
    struct Row: Identifiable, Hashable { let id: Int }
}

@MainActor private final class Streaming { var reply = "" }

private struct Transcript: Component {
    let streaming: Streaming
    @State var draft = ""
    var content: some ElementGroup {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<60, id: \.self) { i in Text("Message \(i): the quick brown fox jumps over the lazy dog, line after line.") }
                    Text(streaming.reply)
                }
            }
            TextField("Message", text: $draft).accessibilityIdentifier("composer").frame(height: Pixels(28))
        }
    }
}

private struct Window: Component {
    let streaming: Streaming
    var content: some ElementGroup {
        HStack(spacing: 0) {
            Table(TableRows()) {
                TableColumnForEach(0..<8) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(90)) }
            }.tableRowHeight(Pixels(24)).frame(width: Pixels(760))
            Transcript(streaming: streaming).frame(width: Pixels(500))
        }
    }
}

/// **1** A window whose live set is several times the budget (a 1M-row table and a 60-message transcript with a streaming
/// reply and a composer, under a budget of 64 entries) misses only what changed once it is warm: typing 25 keys while a reply
/// streams re-shapes the new word and the typed line, and nothing the previous frame already shaped. Under the first version
/// the cache held 64 of the several hundred entries and re-shaped the rest every frame (273 a frame at twice this window's size in the
/// measurement of record 421). **Mutation:** `bound` offering every entry for eviction (`protectedFrom` at `currentGeneration + 1`).
@Test @MainActor func aWindowWhoseLiveSetIsOverTheBudgetStopsMissingOnceWarm() async throws {
    let streaming = Streaming()
    let cache = ShapingCache(entryLimit: 64, costLimit: 192 * 1024)
    let w = try TestWindow(size: Size(width: Pixels(1300), height: Pixels(700)), recordsLayout: false,
                           textSystem: { CoreTextTextSystem(cache: cache) }) { VStack(spacing: 0) { Window(streaming: streaming) } }
    try await w.runUntilIdle()
    w.click(at: Point(x: Pixels(1000), y: Pixels(686)))
    try await w.runUntilIdle()
    var word = 0
    func frame(_ key: String) async throws {
        word += 1
        streaming.reply += "word\(word) "
        w.typeText(key)
        try await w.runUntilIdle()
        w.resetFrameWork()
    }
    for _ in 0..<10 { try await frame("a") }
    #expect(cache.liveSet().entries > 4 * 64, "the live set is well over the budget: \(cache.liveSet())")
    let before = cache.misses + cache.caretMisses
    let evicted = cache.evictionCount
    for _ in 0..<25 { try await frame("b") }
    let perFrame = Double(cache.misses + cache.caretMisses - before) / 25
    #expect(perFrame <= 4, "\(perFrame) misses a frame: the new word at its widths and the typed line, as measured")
    #expect(cache.evictionCount - evicted <= 4 * 25, "only stale entries (the streamed reply's earlier lengths) go: \(cache.evictionCount - evicted)")
    withExtendedLifetime(w) {}
}
#endif
