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
        // per-string memo allows. Today this is 80: two min-content probes
        // per `Text`, each tokenizing in full — two rather than three
        // because each row's `Box` in `demoLikeRows` pins `.width(Pixels(420))`,
        // matching the demo. Drop that pin and the count rises to 120, because
        // an auto-width row is an auto-cross item and `collectItems`' fit-content
        // probe recurses into §4.5's automatic minimum a third time.
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
        #expect(f160.scene.glyphs.count == f40.scene.glyphs.count)
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
// its own 40-row list.
//
// Each row's `.width(Pixels(420))` is pinned, matching the demo
// (`Sources/MetalUIDemo/main.swift:391-397`) rather than left `auto`. An
// auto-width row is an auto-cross item, so `collectItems`' fit-content probe
// on the cross axis recurses into §4.5's automatic minimum a THIRD time —
// three `unbreakableRuns` calls per `Text` instead of two. Measured, not
// assumed: an A/B over exactly this one line moved the call count from 120
// to 80 for 40 rows, with `alignItems` (`.stretch` vs `.center`) ruled out as
// the cause first. Removing this pin would silently inflate every later
// task's before/after ratio.
@MainActor
func demoLikeRows(_ n: Int) -> some Element {
    Box {
        ScrollView(.vertical) {
            for i in 0..<n {
                Box {
                    Text("Row \(i + 1) of \(n) — a scrollable list item")
                }
                .height(Pixels(28))
                .width(Pixels(420))
                .alignItems(.stretch)
            }
        }
    }
    .width(Pixels(420))
    .height(Pixels(370))
    .minHeight(Pixels(0))
}
