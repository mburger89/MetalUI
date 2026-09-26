import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 2: `Slider(value:in:step:)` (ruling `DD-W`; spec
// tests 2.1–2.10). Helpers are `ButtonTests.swift`'s `control…`. Every
// literal below is derived before the run from the ruling's arithmetic — the
// probe's numbers (SA0–SA9) are SwiftUI's, and only its stepping rules are
// claimed, not its geometry.

@MainActor
private final class Level {
    var value: Double
    var writes: [Double] = []
    init(_ value: Double) { self.value = value }
    var binding: Binding<Double> {
        Binding(get: { self.value }, set: { self.value = $0; self.writes.append($0) })
    }
}

/// A 300-point window holding one slider in a 300×300 `Row` root, so the
/// slider is 300 wide at x = 0 (greedy) and centred vertically.
@MainActor
private func sliderWindow(_ model: Level, in range: ClosedRange<Double> = 0...10, step: Double? = nil,
                          disabled: Bool = false) throws -> (Window, FakePlatformWindow) {
    try controlWindow(size: 300) {
        let slider = step.map { Slider(value: model.binding, in: range, step: $0) }
            ?? Slider(value: model.binding, in: range)
        return controlRoot(width: 300, height: 300) { slider.disabled(disabled) }
    }
}

/// The published slider node, a client activated.
@MainActor
private func sliderNode(_ window: Window, _ platform: FakePlatformWindow) throws
    -> (key: AccessibilityNodeID, value: AccessibilityNode) {
    let tree = try controlTree(window, platform)
    let node = try #require(tree.nodes.first { $0.value.role == .slider },
                            "no slider published: \(tree.nodes.values.map(\.role))")
    return (node.key, node.value)
}

/// The 20×16 thumb's rect in the last scene.
@MainActor
private func thumbX(_ window: Window) throws -> Float {
    let rect = try #require(window.lastScene.rects.first {
        $0.bounds.size.width == 20 && $0.bounds.size.height == 16
    }, "no 20×16 thumb rect")
    return rect.bounds.origin.x
}

private func mouse(_ point: Point<Pixels>) -> MouseEvent { MouseEvent(position: point) }

/// **2.1.** Greedy on the width, 16 tall (SL0): 300×16 under a 300 proposal,
/// and 30 wide — SL0's ideal — when offered no width. M2a (height 20) must
/// redden it.
@Test @MainActor func aSliderIsGreedyOnTheWidthAndSixteenTall() throws {
    let frame = try controlRender(controlRoot(width: 300, height: 100) { Slider(value: .constant(0.5)) },
                                  width: 300, height: 100)
    let slider = try controlBounds(frame, controlID([0, 0]))
    #expect(slider.size.width.value == 300 && slider.size.height.value == 16,
            "300×16 under a 300 proposal: \(slider.size)")
    let ideal = Slider.size(proposedWidth: nil)
    #expect(ideal.width == 30 && ideal.height == 16, "30×16 at a nil width: \(ideal)")
    let infinite = Slider.size(proposedWidth: .infinity)
    #expect(infinite.width == 30, "an infinite proposal is not finite: \(infinite)")
}

/// **2.2.** With no step an adjustment moves 10% of the span (SA1: 5 → 6 on
/// 0…10; SA7: 5 → 25 on 0…200). M2b (5%) must redden it.
@Test @MainActor func anUnsteppedAdjustmentMovesTenPercentOfTheSpan() throws {
    for (range, expected) in [(0.0...10.0, 6.0), (0.0...200.0, 25.0)] {
        let model = Level(5)
        let (window, platform) = try sliderWindow(model, in: range)
        let node = try sliderNode(window, platform)
        #expect(platform.simulateAccessibilityRequest(.increment(node.key)))
        #expect(model.writes == [expected], "\(range): \(model.writes)")
    }
}

/// **2.3.** A stepped adjustment moves one step and lands on the grid
/// `lower + k·step`, rounding half up (SA3: 5 +2 → 8, then → 10, −2 → 8), and
/// never past the last grid point inside the bounds (SA4: 9 +3 → 9 on 0…10).
/// M2c (round half down) and M2c′ (no last-grid-point clamp) must redden it.
@Test @MainActor func aSteppedAdjustmentLandsOnTheGridRoundingHalfUpAndNeverPastTheLastPoint() throws {
    let model = Level(5)
    let (window, platform) = try sliderWindow(model, step: 2)
    let node = try sliderNode(window, platform)
    platform.simulateAccessibilityRequest(.increment(node.key))
    platform.simulateAccessibilityRequest(.increment(node.key))
    platform.simulateAccessibilityRequest(.decrement(node.key))
    #expect(model.writes == [8, 10, 8], "SA3: \(model.writes)")

    let last = Level(9)
    let (lastWindow, lastPlatform) = try sliderWindow(last, step: 3)
    let lastNode = try sliderNode(lastWindow, lastPlatform)
    lastPlatform.simulateAccessibilityRequest(.increment(lastNode.key))
    #expect(last.writes == [9], "SA4: 12 is past the last grid point, 9: \(last.writes)")
}

/// **2.4.** An out-of-range value is drawn clamped and written only when
/// adjusted (SA5, SA6): 15 on 0…10 puts the thumb at the maximum
/// (`minX + W − 20` = 280), writes nothing over two frames, and a decrement
/// starts from 10 → 9. M2d (the clamp written back in `prepaint`) must redden it.
@Test @MainActor func anOutOfRangeValueIsDrawnClampedAndWrittenOnlyWhenAdjusted() throws {
    let model = Level(15)
    let (window, platform) = try sliderWindow(model)
    controlRedraw(window)
    controlRedraw(window)
    #expect(model.writes.isEmpty, "no write on appear: \(model.writes)")
    #expect(try thumbX(window) == 280, "the thumb at the maximum")
    let node = try sliderNode(window, platform)
    platform.simulateAccessibilityRequest(.decrement(node.key))
    #expect(model.writes == [9], "SA5: \(model.writes)")
}

/// **2.5.** An adjustment at the maximum still writes (SA2: `value set 10.0`).
/// M2e (an unchanged value not written) must redden it.
@Test @MainActor func anAdjustmentAtTheMaximumStillWrites() throws {
    let model = Level(10)
    let (window, platform) = try sliderWindow(model)
    let node = try sliderNode(window, platform)
    #expect(platform.simulateAccessibilityRequest(.increment(node.key)))
    #expect(model.writes == [10], "one write of the unchanged maximum: \(model.writes)")
}

/// **2.6.** A press writes the value under the pointer — `lower +
/// clamp01((x − minX − 10) / (W − 20))·span`, onto the grid — and a drag
/// writes again (MetalUI's rule; CK0 failed). On 0…10 step 2 over W = 300:
/// x 150 → 5 → 6 (half up); x 94 → 3 → 4; x 400 → past the end → 10. The press
/// does not focus. M2f (`mouseDragged` not dispatched to `valueTrack`) must
/// redden it.
@Test @MainActor func aPressOnTheSliderSetsTheValueUnderThePointerAndADragFollows() throws {
    let model = Level(0)
    let (window, platform) = try sliderWindow(model, step: 2)
    let bounds = try controlBounds(window.lastFrameBounds(), controlID([0, 0]))
    try #require(bounds.origin.x.value == 0 && bounds.size.width.value == 300, "set up: \(bounds)")
    let y = bounds.origin.y.value + 8
    platform.simulateInput(.mouseDown(mouse(Point(x: controlPx(150), y: controlPx(y)))))
    #expect(model.writes == [6], "the press: \(model.writes)")
    platform.simulateInput(.mouseDragged(mouse(Point(x: controlPx(94), y: controlPx(y)))))
    platform.simulateInput(.mouseDragged(mouse(Point(x: controlPx(400), y: controlPx(y + 50)))))
    platform.simulateInput(.mouseUp(mouse(Point(x: controlPx(400), y: controlPx(y + 50)))))
    #expect(model.writes == [6, 4, 10], "the drag follows, clamped past the end: \(model.writes)")
    #expect(window.focusedElement == nil, "a press does not focus a slider")
}

/// **2.7.** Focused, → and ↑ increment and ← and ↓ decrement by the
/// accessibility step (`DD-T`): 5 → 6 → 7 → 6 → 5 on 0…10. M2g (↑/↓
/// unhandled) must redden it.
@Test @MainActor func aFocusedSliderAdjustsByTheAccessibilityStepOnTheArrows() throws {
    let model = Level(5)
    let (window, platform) = try sliderWindow(model)
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a slider takes focus")
    for key in [TextEditing.rightArrow, TextEditing.upArrow, TextEditing.leftArrow, TextEditing.downArrow] {
        platform.simulateInput(controlKey(key))
    }
    #expect(model.writes == [6, 7, 6, 5], "\(model.writes)")
}

/// **2.8.** Published as an adjustable `.slider` with its value printed
/// without a trailing `.0` (SA0 reads `5`), no label, `.increment` and
/// `.decrement`, and no `.press`. M2h (the adjustment handler not registered)
/// must redden it.
@Test @MainActor func aSliderPublishesAnAdjustableSliderWithItsValue() throws {
    let model = Level(5)
    let (window, platform) = try sliderWindow(model)
    let node = try sliderNode(window, platform).value
    #expect(node.value == "5", "value \(node.value ?? "nil")")
    #expect(node.label == nil, "no label (SA0)")
    #expect(node.actions == [.increment, .decrement], "actions \(node.actions)")
    #expect(node.isEnabled && node.isFocusable)
}

/// **2.9.** Disabled: a press, a drag, the arrows and an adjustment write
/// nothing, and the slider publishes disabled (SA9). M2i (the track's hitbox
/// inserted through `pass.insertHitbox` directly, bypassing the gate) must
/// redden it.
@Test @MainActor func aDisabledSliderNeitherTracksNorAdjustsAndPublishesDisabled() throws {
    let model = Level(5)
    let (window, platform) = try sliderWindow(model, disabled: true)
    let id = controlID([0, 0])
    let bounds = try controlBounds(window.lastFrameBounds(), id)
    let y = bounds.origin.y.value + 8
    platform.simulateInput(.mouseDown(mouse(Point(x: controlPx(50), y: controlPx(y)))))
    platform.simulateInput(.mouseDragged(mouse(Point(x: controlPx(250), y: controlPx(y)))))
    platform.simulateInput(.mouseUp(mouse(Point(x: controlPx(250), y: controlPx(y)))))
    window.focus(id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    let node = try sliderNode(window, platform)
    platform.simulateAccessibilityRequest(.increment(node.key))
    #expect(model.writes.isEmpty, "nothing written while disabled: \(model.writes)")
    #expect(node.value.isEnabled == false, "published disabled")
}

/// **2.10** (exit test). A step that is not finite and positive, or bounds
/// that are not finite, trap (`DD-W` item 7, `SA-J`): each would make the
/// thumb's position non-finite. Equal bounds do not trap (the control arm).
/// M2j (the precondition removed) must redden it.
@Test @MainActor func aSliderTrapsOnANonPositiveStepOrNonFiniteBounds() async throws {
    await #expect(processExitsWith: .failure) {
        await MainActor.run { _ = Slider(value: .constant(0.5), in: 0.0...1.0, step: 0) }
    }
    await #expect(processExitsWith: .failure) {
        await MainActor.run { _ = Slider(value: .constant(0.5), in: 0.0...1.0, step: -1) }
    }
    await #expect(processExitsWith: .failure) {
        await MainActor.run { _ = Slider(value: .constant(0.5), in: 0.0...Double.infinity) }
    }
    await #expect(processExitsWith: .success) {
        await MainActor.run { _ = Slider(value: .constant(1.0), in: 1.0...1.0, step: 0.5) }
    }
}
