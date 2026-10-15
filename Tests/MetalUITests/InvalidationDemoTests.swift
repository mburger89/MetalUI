import Foundation
import Testing
import MetalUI
import MetalUITesting
@testable import MetalUIDemoContent

// The content-memo demo (`METALUI_INVALIDATION_DEMO=1`, spec §9, rulings `IV-B`…`IV-D`)
// under the harness: after warm-up, one bump of one cell evaluates 1 getter in the
// `.equatable()` tree and 121 (81 leaves + 40 branches) in the same tree with `==`
// always false. Mutation: `EquatableComponent` evaluating every getter (the stub of
// lane 2's red-first commit) reads 121 / 121.

// The readout is built from this build's own counters, so a frame verify mode builds twice (`RK-N`) shows two different
// readouts by design: the pin is not verify mode's to read.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] != "1",
               "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice: the demo's readout of its own build counters differs between the two"))
@MainActor func theInvalidationDemoEvaluatesOneGetterToTheOtherTreesHundredAndTwentyOne() throws {
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(560)),
                                content: invalidationDemoContent)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    invalidationDemoModel.cells[5].value += 1
    window.window.setNeedsRedraw(); window.tick()
    // The readout is the last element of the tree and snapshots its own build's counts.
    #expect(invalidationDemoModel.shown == [1, 121])
}
