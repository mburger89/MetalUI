import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// G33 (b), ruling `HP-K`: a frame's hot maps are reserved from the previous frame's counts, so they do not regrow
// from empty every frame. Mutation: build the frame without `capacityHints:` and the second frame starts at 0.

/// A window of many buttons and taps: the frame after the first starts every hot store at (at least) the size the
/// first frame ended at, and the first frame, which has no hint, starts at zero.
@Test @MainActor func theSecondFrameReservesWhatTheFirstFrameHeld() throws {
    let (window, _) = try controlWindow(size: 800) {
        VStack { ForEach(0..<100, id: \.self) { i in
            HStack { Button("B\(i)") {}; Text("T\(i)").onTapGesture {} }
        } }
    }
    let held = window.frameCapacityHints
    #expect(held.tree.nodes > 500 && held.tree.nativeNodes > 500 && held.tree.leafKeys > 100, "\(held)")
    #expect(held.hitboxes >= 200 && held.focus.focusable >= 100 && held.loweringItems > 100 && held.elementBounds > 100, "\(held)")

    controlRedraw(window)
    let start = window.lastFrameStartCapacities
    #expect(start.tree.nodes >= held.tree.nodes, "\(start)")
    #expect(start.tree.nativeNodes >= held.tree.nativeNodes)
    #expect(start.tree.leafKeys >= held.tree.leafKeys)
    #expect(start.tree.spacingMarks >= held.tree.spacingMarks)
    #expect(start.tree.nativeParents >= held.tree.nativeParents)
    #expect(start.focus.focusable >= held.focus.focusable)
    #expect(start.focus.keyHandlers >= held.focus.keyHandlers)
    #expect(start.focus.tabOrder >= held.focus.tabOrder)
    #expect(start.hitboxes >= held.hitboxes)
    #expect(start.loweringItems >= held.loweringItems)
    #expect(start.elementBounds >= held.elementBounds)
    // Behaviour is unchanged: the same frame has the same counts.
    #expect(window.frameCapacityHints == held)
}

/// A bare `Frame` (no window, no hint) reserves nothing.
@Test @MainActor func aFrameWithNoHintStartsEmpty() {
    let frame = Frame(contentSize: Size(width: controlPx(100), height: controlPx(100)), scaleFactor: 1)
    #expect(frame.startCapacities.hitboxes == 0 && frame.startCapacities.tree.leafKeys == 0)
}
