import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
@testable import MetalUI

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func dim(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }

private func sized(_ w: Float, _ h: Float) -> Style {
    var s = Style()
    s.size = Size(width: dim(w), height: dim(h))
    return s
}

// `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` (divergence 11:
// an absolute box outside a `Deferred` laid out against the window but clipped
// and scrolled by an ancestor `ScrollView`) retired at stage 9: that half ran
// under the legacy authority only, which stage 9 deleted (`LR-FH` item 1, record
// §51). Its proposal
// fact — the spelling reports `box.position` and `box.inset` at its consumer —
// is `PresentationLoweringTests`' 1.5 arm "absolute in a `ScrollView`, no
// `Deferred`"; its `Deferred` escape half is `DeferredTests`'
// `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScroll` and the mask reset
// its portal tests pin.

/// **2.7** (plan task 7 stage 5, `LR-CK`, `LR-CP` item 4). An absolute box
/// **outside** a `Deferred` is removed from the proposal authority rather than
/// lowered, so a production proposal frame (diagnostics off) over one traps —
/// and the trap names the stage that owns it, **stage 10** (the stage that
/// deletes `Style.position`/`inset`). At `e5caefb` the child trapped naming
/// stage 2, so the `stage 10` assertion is red there.
@Test func anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame() async {
    let child = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var column = Style()
            column.flexDirection = .column
            var overlay = sized(22, 20)
            overlay.position = .absolute
            overlay.inset = Edges(top: dim(5), right: .auto, bottom: .auto, left: dim(5))
            var root = Box(style: column) {
                Box(style: sized(10, 10))
                Box(style: overlay)
            }
            Frame(contentSize: Size(width: px(200), height: px(100)), scaleFactor: 1).render(&root)
        }
    }
    let stderr = String(decoding: child?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("MetalUI: box.position has no proposal lowering (plan task 7, stage 10)"),
            "aborted, but not naming box.position and stage 10:\n\(stderr)")
}
