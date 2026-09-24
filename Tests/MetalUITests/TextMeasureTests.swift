import CoreText
import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

// Task 4 — the measure function, `Text`, and `newLeaf`'s first production
// caller. **Since stage 9 only the cache test is left**: the four tests of the
// CSS measure function (its three sizing modes against
// CoreText's own numbers, min-content as the longest run, a known size winning,
// a zero available extent) retired with it and with tokenizer min-content
// (`LR-FC`, `LR-FD`, record §51). A lowered `Text` measures through
// `proposalTextMeasurement` and the frame's `TextSystem`, pinned by
// `LoweringLeafTests` and `TextSystemSeamTests`.

/// Nine short words, so a 120pt column wraps it to three lines.
private let label = "The quick brown fox jumps over the lazy dog"

/// Lays `element` out in a `width × height` frame and hands back the frame and
/// the root node, so a test can read any node's resolved rect.
///
/// **Not `Frame.render`**, which does not give back the root id. It runs the
/// layout phase and the engine, which is everything a measure function
/// participates in. At `Frame`'s default authority (the four `.legacy` callers
/// stage 6b pinned, `LR-DI`, were retired at stage 7b, record §49 rows 232–235).
@MainActor
private func laidOut<E: Element>(_ element: inout E, width: Double, height: Double = 600,
                                 cache: ShapingCache = ShapingCache()) -> (Frame, LayoutNodeID) {
    let frame = Frame(contentSize: Size(width: Pixels(Float(width)), height: Pixels(Float(height))),
                      scaleFactor: 1, stateTable: StateTable(), shapingCache: cache)
    var pass = LayoutPass(frame: frame)
    let (root, _) = element.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                          pass: &pass)
    frame.computeRootLayout(root: root)
    return (frame, root)
}

// MARK: - The cache is the window's, not the frame's

/// **One shaping cache across frames, and a second frame adds no misses.**
///
/// `Frame` takes the cache the way it takes the `StateTable`: the window owns
/// it and hands the same instance to every frame. A `Frame` that constructed its
/// own would re-shape every string through CoreText on every frame — three times
/// per text item per layout, since §4.5's automatic minimum probes every item —
/// and **no other test in the repo can see it**, because a single-frame test
/// cannot tell a warm cache from a cold one.
///
/// The miss count is the only observable, which is why this test reaches into
/// `MetalUIText` with `@testable`.
@MainActor
@Test func twoFramesShareOneShapingCacheRatherThanReShapingEachFrame() {
    let cache = ShapingCache()

    var first = Column { Text(label) }.alignItems(.stretch)
    _ = laidOut(&first, width: 120, cache: cache)
    let missesAfterFirstFrame = cache.misses
    let hitsAfterFirstFrame = cache.hits

    var second = Column { Text(label) }.alignItems(.stretch)
    _ = laidOut(&second, width: 120, cache: cache)

    #expect(missesAfterFirstFrame > 0)
    #expect(cache.misses == missesAfterFirstFrame)
    #expect(cache.hits > hitsAfterFirstFrame)
}
