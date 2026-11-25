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
    #expect(held.sceneRects > 50 && held.sceneGlyphs > 300, "the scene's counts (`HP-L`): \(held)")
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
    // `HP-L`: the scene's rect and glyph arrays start at the last frame's count. Mutation: no `scene.reserveCapacity` in `Frame.init`.
    #expect(start.sceneRects >= held.sceneRects && start.sceneGlyphs >= held.sceneGlyphs, "\(start)")
    // Behaviour is unchanged: the same frame has the same counts.
    #expect(window.frameCapacityHints == held)
}

/// A bare `Frame` (no window, no hint) reserves nothing.
@Test @MainActor func aFrameWithNoHintStartsEmpty() {
    let frame = Frame(contentSize: Size(width: controlPx(100), height: controlPx(100)), scaleFactor: 1)
    #expect(frame.startCapacities.hitboxes == 0 && frame.startCapacities.tree.leafKeys == 0)
    #expect(frame.startCapacities.sceneGlyphs == 0 && frame.startCapacities.sceneRects == 0)
}

/// G51 (record 420): the n-th composite or mask scope of a frame opens with the room the n-th of the last frame filled, so a scope that
/// collects a viewport of glyphs is not grown by doubling. Mutation: no `scopeCaptureHints = capacityHints.scopeCaptures` in `Frame.init`.
@Test @MainActor func theSecondFrameReservesWhatTheFirstFramesScopeCollected() throws {
    let (window, _) = try controlWindow(size: 800) {
        VStack { ForEach(0..<40, id: \.self) { i in Text("row \(i) with some words so that it has glyphs to collect") } }
            .compositingGroup().opacity(0.9)
    }
    let held = window.frameCapacityHints
    #expect((held.scopeCaptures.first ?? 0) > 500, "the group's collected primitives: \(held.scopeCaptures)")
    controlRedraw(window)
    #expect(window.lastFrameStartCapacities.scopeCaptures == held.scopeCaptures, "\(window.lastFrameStartCapacities.scopeCaptures)")
    #expect(held.scopeCaptures.count <= FrameCapacityHints.maxScopeHints)
}
