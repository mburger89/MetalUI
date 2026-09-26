import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 2: the wheel rule that retires divergence 16
// (ruling `DD-Y`; spec tests 2.19, 2.20, 2.24 — 2.18 is the renamed
// `InputDispatchTests` test) and `ClickDispatch` (`DD-Z` item 9; 2.21, 2.22).
// **Every pointer rule here is MetalUI's own**: the probe's wheel control WH0
// and click control CK0 failed, so no SwiftUI answer is claimed.

private func wheelPx(_ v: Float) -> Pixels { Pixels(v) }
private func wheelPt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: wheelPx(x), y: wheelPx(y)) }

private func wheel(at point: Point<Pixels>) -> InputEvent {
    .scrollWheel(ScrollEvent(position: point, delta: Point(x: wheelPx(0), y: wheelPx(-37))))
}

private func column() -> Style {
    var s = Style()
    s.flexDirection = .column
    return s
}

private func row40() -> Style {
    var s = Style()
    s.size = Size(width: .auto, height: .length(.pixels(wheelPx(40))))
    return s
}

private let listID = ElementID("list")
private let scroller = GlobalElementID.child(of: nil, at: 0, name: ElementID("list"))

@MainActor
private func offset(_ window: Window, _ id: GlobalElementID) -> Double? {
    window.stateTable.peek(id, as: ScrollState.self)?.offset
}

/// **2.19.** A click target **overlaid on** a scroller but not inside it — a
/// `Stack` sibling covering a `ScrollView` — still stops the wheel (the
/// ancestry clause of `DD-Y`). Green at `27b2fcc`, where every opaque hitbox
/// stopped it. M2r (ancestry dropped: any scroller on the same layer under
/// the point takes it) must redden it.
@Test @MainActor func aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        Stack {
            ScrollView(.vertical, elementID: listID) {
                Box(style: column()) {
                    Box(style: row40()); Box(style: row40()); Box(style: row40()); Box(style: row40())
                }
            }
            Box().cssWidth(wheelPx(100)).cssHeight(wheelPx(100)).onClick {}
        }
    }
    window.drawFrameIfNeeded()
    let region = try #require(window.lastScrollRegions.first, "the scroller registers a region")
    #expect(platform.simulateInput(wheel(at: wheelPt(50, 50))), "the overlay claims the wheel")
    #expect((offset(window, region.id) ?? 0) == 0, "the overlaid sibling stops it")
}

/// **2.20.** A scrim hoisted by `Deferred` stops the wheel even when it is
/// declared **inside** the scroller's content (the layer clause of `DD-Y`:
/// `Deferred` content is on layer 1, the scroller on 0). Green at `27b2fcc`.
/// M2s (the layer clause dropped) must redden it.
@Test @MainActor func aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: column()) {
                Deferred { Box().cssWidth(wheelPx(100)).cssHeight(wheelPx(100)).onClick {} }
                Box(style: row40()); Box(style: row40()); Box(style: row40()); Box(style: row40())
            }
        }
    }
    window.drawFrameIfNeeded()
    let scrim = try #require(window.lastHitboxes.first { $0.handlers.onClick != nil && $0.layer > 0 },
                             "the scrim registers on a higher layer")
    try #require(scrim.bounds.contains(wheelPt(50, 50)), "set up: the scrim covers the point")
    #expect(platform.simulateInput(wheel(at: wheelPt(50, 50))), "the scrim claims the wheel")
    #expect((offset(window, scroller) ?? 0) == 0, "a hoisted scrim stops it")
}

/// **2.24.** A single-line `TextField` inside a `ScrollView` passes the wheel
/// over itself to its scroller (`DD-AC` item 3: it is a pointer target through
/// `Handlers.textInput`, and `DD-Y` moves its answer, 0 → 37), and a press on
/// it still focuses it. Red at `27b2fcc` (it read 0). M2q (the rule reverted)
/// and M2v (the `textInput` target excluded from the ancestor walk) must
/// redden it.
@Test @MainActor func aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 100) {
        ScrollView(.vertical, elementID: listID) {
            Box(style: column()) {
                TextField("Name", text: "hello", onChange: { _ in })
                Box(style: row40()); Box(style: row40()); Box(style: row40())
            }
        }
    }
    window.drawFrameIfNeeded()
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field registers")
    let centre = controlCentre(field.bounds)
    // The press first: after the wheel the field scrolls out of the viewport.
    platform.simulateInput(.mouseDown(MouseEvent(position: centre)))
    platform.simulateInput(.mouseUp(MouseEvent(position: centre)))
    #expect(window.focusedElement == field.id, "a press still focuses the field")
    window.drawFrameIfNeeded()
    #expect(platform.simulateInput(wheel(at: centre)), "the scroller claims the wheel")
    #expect(offset(window, scroller) == 37, "the wheel over the focused field reached its scroller")
}

@MainActor
private final class FocusTarget {
    var id: GlobalElementID
    init(_ id: GlobalElementID) { self.id = id }
}

@MainActor
private final class ClickLog {
    var modifiers: [Modifiers] = []
}

/// **2.21.** While an `onClick` runs from a mouse click, `ClickDispatch.modifiers`
/// holds the completing mouse-up's modifiers; after it, and for an
/// accessibility `.press`, it is `[]` (`DD-Z` item 9). M2t (`modifiers` not
/// reset) must redden it.
@Test @MainActor func aClickHandlerSeesItsClicksModifiersAndOnlyDuringTheClick() throws {
    let log = ClickLog()
    let (window, platform) = try controlWindow {
        controlRoot {
            Box().cssWidth(controlPx(40)).cssHeight(controlPx(40)).onClick { log.modifiers.append(ClickDispatch.modifiers) }
        }
    }
    let point = controlCentre(try controlBounds(window.lastFrameBounds(), controlID([0, 0])))
    platform.simulateInput(.mouseDown(MouseEvent(position: point, modifiers: .command)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point, modifiers: .command)))
    #expect(log.modifiers == [.command], "the handler read the mouse-up's ⌘: \(log.modifiers)")
    #expect(ClickDispatch.modifiers == [], "reset after the handler returns")
    let tree = try controlTree(window, platform)
    let button = try #require(tree.nodes.first { $0.value.role == .button }, "the click target publishes a button")
    #expect(platform.simulateAccessibilityRequest(.press(button.key)))
    #expect(log.modifiers == [.command, []], "a press carries no modifiers: \(log.modifiers)")
}

/// **2.22.** A click handler may set `ClickDispatch.focusRequest`, which the
/// window honours through `focus(_:)` after the handler returns, and clears; a
/// request naming a non-focusable id is cleared at the frame boundary, as any
/// `focus(_:)` of one is (`DD-Z` items 5 and 9). M2u (the request ignored)
/// must redden it.
@Test @MainActor func aClickHandlersFocusRequestIsHonouredAfterItReturns() throws {
    let target = controlID([0, 1])
    let plain = controlID([0, 2])
    let request = FocusTarget(target)
    let (window, platform) = try controlWindow {
        controlRoot {
            Box().cssWidth(controlPx(40)).cssHeight(controlPx(40)).onClick { ClickDispatch.focusRequest = request.id }
            Box().cssWidth(controlPx(40)).cssHeight(controlPx(40)).focusable()
            Box().cssWidth(controlPx(40)).cssHeight(controlPx(40))
        }
    }
    let point = controlCentre(try controlBounds(window.lastFrameBounds(), controlID([0, 0])))
    controlClick(platform, at: point)
    #expect(window.focusedElement == target, "the request was honoured: \(String(describing: window.focusedElement))")
    #expect(ClickDispatch.focusRequest == nil, "and cleared")
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == target, "a focusable target keeps focus across the frame")

    request.id = plain
    controlClick(platform, at: point)
    #expect(window.focusedElement == plain, "honoured as any focus(_:) is")
    window.drawFrameIfNeeded()
    #expect(window.focusedElement == nil, "a non-focusable id is cleared at the frame boundary")
}
