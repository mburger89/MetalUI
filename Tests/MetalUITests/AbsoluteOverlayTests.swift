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
/// lowered, so a production proposal frame (diagnostics off) over one traps.
/// Until stage 10 the trap named the stage that owned it (**stage 10**; at
/// `e5caefb` it named stage 2); since stage 10's `LR-FO` item 2 the entry is a
/// **permanent refusal**, and the message says so instead of naming a stage.
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
    #expect(stderr.contains("MetalUI: box.position has no proposal lowering and is refused by name "
                            + "(plan task 7, LR-FO)"),
            "aborted, but not naming box.position as a permanent refusal:\n\(stderr)")
}
