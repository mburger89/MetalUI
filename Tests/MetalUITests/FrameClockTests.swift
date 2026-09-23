import Testing
import Metal
import MetalUICore
@testable import MetalUI

/// A leaf element that calls `pass.requestAnotherFrame()` during paint, so a
/// test can drive the "an animation is still running" path without any real
/// animator existing yet.
private struct RequestingBox: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID? = ElementID("requesting")
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        // A native leaf since stage 6a (record §38, disposition R); `style` is
        // never set by any caller, so the leaf answers `Style()`'s 0×0.
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {
        pass.requestAnotherFrame()
    }
}

/// A leaf element that records `pass.timestamp` into a shared box during
/// paint, so a test can inspect what every element in a frame saw without any
/// other side channel back out of `paint`.
private struct TimestampRecorder: Element, StyledElement {
    @MainActor final class Seen { var values: [Double] = [] }

    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    // `StyledElement`'s fourth requirement. This probe registers no click
    // target — nothing calls `registerHandlers` — so it stays at the empty set.
    var handlers: Handlers = Handlers()
    let seen: Seen

    func requestLayout(_ id: GlobalElementID,
                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutNodeID) {
        // A native leaf since stage 6a (record §38, disposition R); `style` is
        // never set by any caller, so the leaf answers `Style()`'s 0×0.
        let node = pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }.layoutNodeID
        return (node, node)
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                  layout: inout LayoutNodeID, pass: inout PrepaintPass) {}

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
               layout: inout LayoutNodeID, prepaint: inout Void, pass: inout PaintPass) {
        seen.values.append(pass.timestamp)
    }
}

/// An element that asks for another frame keeps the window dirty, so the
/// display link is not paused and a fade can run to completion.
///
/// Without this, a time-based animation stops the instant the last input event
/// stops arriving — the window goes clean, `drawFrameIfNeeded` pauses the link,
/// and the indicator freezes half-faded on screen.
///
/// **What a wrong implementation this catches**: `Window` ignoring
/// `frame.wantsAnotherFrame` after render — the exact mutation recorded in the
/// task report. Without the honouring line, this is the only test in the suite
/// that reddens.
@Test @MainActor func anElementThatRequestsAnotherFrameKeepsTheWindowDirty() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, startsDisplayLink: true) {
        RequestingBox()
    }

    platformWindow.simulateTick(timestamp: 1)

    #expect(window.needsRedraw)
}

/// An element that does NOT ask leaves the window clean — the differential,
/// without which the test above passes on a window that is always dirty.
///
/// **What this catches**: a `Window` that marks itself dirty unconditionally
/// after every render regardless of `wantsAnotherFrame` — which would make the
/// idle guarantee (spec §4.4, an M4 exit criterion) silently false while the
/// test above stayed green for the wrong reason.
@Test @MainActor func anElementThatAsksForNothingLeavesTheWindowClean() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platformWindow) = try makeFakeWindow(device: device, startsDisplayLink: true) {
        Box()
    }

    platformWindow.simulateTick(timestamp: 1)

    #expect(!window.needsRedraw)
}

/// The frame's timestamp is the display link's, not a wall clock read at an
/// arbitrary point — two elements in one frame must see the same instant.
///
/// **What this catches**: `Frame.timestamp` being read fresh per element (a
/// per-element `CACurrentMediaTime()`-shaped read) rather than fixed once per
/// frame. Asserting only that the two values are equal would also pass a
/// broken implementation that hands every element `0` — so this asserts the
/// shared value is also the one the tick supplied, and the timestamp is
/// non-zero, per the practices doc's rule against a coincidental pass.
@Test @MainActor func everyElementInOneFrameSeesTheSameTimestamp() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let seen = TimestampRecorder.Seen()
    // The `Window` binding is kept, not discarded with `_`: `Window.init`
    // hands the fake's `startDisplayLink` a `[weak self]` closure, so a
    // discarded window is deallocated immediately and `simulateTick` below
    // fires into a nil `self` — no render, no recorded timestamps, and a test
    // that fails fast for a reason unrelated to what it claims to check.
    let (window, platformWindow) = try makeFakeWindow(device: device, startsDisplayLink: true,
                                                      layoutAuthority: .proposal) {
        Row {
            TimestampRecorder(elementID: ElementID("a"), seen: seen)
            TimestampRecorder(elementID: ElementID("b"), seen: seen)
        }
    }

    let tick = 12345.6789
    platformWindow.simulateTick(timestamp: tick)

    try #require(window.framesDrawn == 1)
    // A count a later expression indexes on: `try #require`, not `#expect`,
    // per the practices doc — a wrong count here must stop the test rather
    // than crash it out of the run with no summary line.
    try #require(seen.values.count == 2)
    #expect(seen.values[0] != 0)
    #expect(seen.values[0] == tick)
    #expect(seen.values[1] == tick)
}
