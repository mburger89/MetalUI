import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

/// Performance assertions that survive a change of machine.
///
/// **These count work rather than timing it.** Every defect these were written
/// for is a count — a tokenizer walk repeated per probe, a per-run loop, a cost
/// linear in total rows rather than visible ones — and a count fails identically
/// on a loaded CI box where a committed millisecond baseline would flake or rot.
@MainActor
struct MeasurePerformanceTests {

    /// Builds a frame over `content` and returns it, so a caller can read the
    /// counters the render just moved.
    static func render(_ content: () -> some Element,
                       size: Size<Pixels> = Size(width: Pixels(920), height: Pixels(560)),
                       states: StateTable) -> Frame {
        let frame = Frame(contentSize: size, scaleFactor: 2, stateTable: states,
                          theme: .dark)
        var root = content()
        frame.render(&root)
        return frame
    }

    @Test
    func aWarmFrameTokenizesEachDistinctStringAtMostOnce() throws {
        let states = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states)   // warm

        Shaper.resetUnbreakableRunCalls()
        _ = Self.render({ demoLikeRows(40) }, states: states)

        // 40 rows share no strings, so 40 distinct strings is the ceiling a
        // per-string memo allows. `ShapingCache.minContentWidth` memoizes the
        // tokenizer walk, so within one frame the second of the two
        // min-content probes per `Text` hits the memo instead of
        // retokenizing — one call per distinct string per frame, hence 40.
        //
        // **Both probes reach the SAME line, not two different ones**
        // (measure-performance milestone, ruling MP-B): `FlexEngine`'s §4.5
        // automatic-minimum content-suggestion probe, called once from
        // `flexBaseSize`'s content-basis pass over an ancestor and once from
        // the real positioning pass floor-clamping the item for §9.7's freeze
        // loop. It is NOT "the direct measure pass and `collectItems`' cross-
        // axis fit-content probe" — that cross-axis site is dead on this tree,
        // because the row `.width(Pixels(420))` pin below (see this file's
        // `demoLikeRows` comment) removes the auto cross size it needs to
        // fire at all. A call-stack capture confirmed this; do not restate
        // the cross-axis probe as one of the two without re-measuring.
        //
        // This reads exactly 40 rather than 0 because `Self.render` above
        // hands each call a fresh `Frame` with no `shapingCache:` argument, so
        // the two renders in this test do not share a cache — only calls
        // *within* one frame benefit from the memo here. A `Window`-threaded
        // cache, persisted across frames the way production does it, reads 0
        // (measured directly). Do not "fix" this by threading a shared cache
        // into `Self.render` to make it read 0: that also makes
        // `aListsWorkIsTheSameFor160RowsAsFor40` read `0 == 0`, which would
        // pass today before windowing exists and forever after regardless of
        // whether windowing works. The cold-cache-per-frame shape is
        // load-bearing for that assertion, and this test's own instrument —
        // a per-frame call count, not a cross-frame one — is chosen to keep
        // it that way.
        #expect(Shaper.unbreakableRunCalls <= 40)
    }

    @Test
    func aListsWorkIsTheSameFor160RowsAsFor40() throws {
        let states40 = StateTable(), states160 = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states40)
        _ = Self.render({ demoLikeRows(160) }, states: states160)

        Shaper.resetUnbreakableRunCalls()
        let f40 = Self.render({ demoLikeRows(40) }, states: states40)
        let calls40 = Shaper.unbreakableRunCalls

        Shaper.resetUnbreakableRunCalls()
        let f160 = Self.render({ demoLikeRows(160) }, states: states160)
        let calls160 = Shaper.unbreakableRunCalls

        // Equal, not merely close: with a uniform row height the window is
        // computed by division, so the same ~13 rows are built either way and
        // the extra 120 rows cost nothing at all.
        #expect(calls160 == calls40)
        // `shapingCache.storageCount` rather than `scene.glyphs.count`: the
        // row text embeds `n` ("Row i of n — …", matching the demo), so at
        // n == 160 every visible row's string is one character longer than
        // at n == 40 — a glyph-count comparison would fail by exactly one
        // glyph per visible row regardless of whether windowing works,
        // because it is sensitive to string LENGTH, not row count.
        // `storageCount` counts cache entries, one per distinct (string,
        // font, width) actually shaped — invariant to how long each string
        // is, and still ~4x apart between a correct and a disabled window.
        #expect(f160.shapingCache.storageCount == f40.shapingCache.storageCount)
    }

    // Task 7 adds `ShapingCache.entryBound`; until then this does not compile.
    // Uncomment there.
    // @Test
    // func theShapingCacheStaysUnderItsBoundAcrossAWidthSweep() throws {
    //     let states = StateTable()
    //     var last = 0
    //     for i in 0..<120 {
    //         let w = 920.0 + Double(i) * 0.5
    //         let frame = Self.render({ demoLikeRows(40) },
    //                                 size: Size(width: Pixels(Float(w)), height: Pixels(560)),
    //                                 states: states)
    //         last = frame.shapingCache.storageCount
    //     }
    //     // Today: 276 -> 739 and climbing, with no eviction path in the file.
    //     #expect(last <= ShapingCache.entryBound)
    // }
}

// `ScrollView` conforms to `Element`, not `StyledElement` (CLAUDE.md's
// declared-but-inert table), so `.width`/`.height`/`.minHeight` land on a
// wrapping `Box` — the same shape `Sources/MetalUIDemo/main.swift` uses for
// its own 40-row list. This builds through `List`, matching the demo's own
// row shape (`DemoRow` mirrors the identity a real caller's data would carry;
// `List` requires `Data.Element: Identifiable` and a bare `Range<Int>`'s
// `Int` does not conform).
//
// Each row's `.width(Pixels(420))` is pinned, matching the demo
// (`Sources/MetalUIDemo/main.swift:391-397`) rather than left `auto`. An
// auto-width row is an auto-cross item, so `collectItems`' fit-content probe
// on the cross axis recurses into §4.5's automatic minimum a THIRD time —
// three `unbreakableRuns` calls per `Text` instead of two. Measured: an A/B
// over exactly this one line moved the call count from 120 to 80 for 40
// rows, with `alignItems` (`.stretch` vs `.center`) ruled out as the cause
// first. The pin sits on the `Box` this file's own row closure contributes,
// not on anything inside `List` — `List`'s internal row wrapper has no width
// of its own, so an un-pinned `Text` here would still hit the same third
// probe. Removing this pin would silently inflate every later before/after
// ratio measured against this harness.
private struct DemoRow: Identifiable {
    let id: Int
}

@MainActor
func demoLikeRows(_ n: Int) -> some Element {
    Box {
        ScrollView(.vertical) {
            List((0..<n).map(DemoRow.init), rowHeight: Pixels(28)) { datum in
                Box {
                    Text("Row \(datum.id + 1) of \(n) — a scrollable list item")
                }
                .width(Pixels(420))
                .alignItems(.stretch)
            }
        }
    }
    .width(Pixels(420))
    .height(Pixels(370))
    .minHeight(Pixels(0))
}
