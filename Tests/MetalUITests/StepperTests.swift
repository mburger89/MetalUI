import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 10, part 2, lane 2: `Stepper` (ruling `DD-X`; spec tests 2.11–2.17
// and 2.23). Helpers are `ButtonTests.swift`'s `control…`. The stepper sits at
// `[0, 0]`: its title at `[0, 0, 0]`, its 20×24 control at `[0, 0, 1]`, the
// increment half at `[0, 0, 1, 0]` and the decrement half at `[0, 0, 1, 1]`.

@MainActor
private final class Count {
    var value: Int
    var writes: [Int] = []
    init(_ value: Int) { self.value = value }
    var binding: Binding<Int> {
        Binding(get: { self.value }, set: { self.value = $0; self.writes.append($0) })
    }
}

private let stepperID = controlID([0, 0])
private let upID = controlID([0, 0, 1, 0])
private let downID = controlID([0, 0, 1, 1])

@MainActor
private func stepperWindow<S: ElementGroup>(_ make: @escaping @MainActor () -> S) throws -> (Window, FakePlatformWindow) {
    try controlWindow { controlRoot { make() } }
}

@MainActor
private func tap(_ window: Window, _ platform: FakePlatformWindow, _ id: GlobalElementID) throws {
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    controlRedraw(window)
}

@MainActor
private func incrementor(_ window: Window, _ platform: FakePlatformWindow) throws
    -> (key: AccessibilityNodeID, value: AccessibilityNode) {
    let tree = try controlTree(window, platform)
    let node = try #require(tree.nodes.first { $0.value.role == .incrementor },
                            "no incrementor published: \(tree.nodes.values.map(\.role))")
    return (node.key, node.value)
}

/// **2.11.** The title, 8 points, then a 20×24 control (ST0): `textW + 28` ×
/// `max(textH, 24)`; with an empty title the 8 stays, 28×24. M2k (gap 6) must
/// redden it.
@Test @MainActor func aStepperIsItsTitleEightPointsAndATwentyByTwentyFourControl() throws {
    let text = try controlTextSize("Qty")
    let frame = try controlRender(controlRoot { Stepper("Qty", value: .constant(1), in: 0...5) })
    let stepper = try controlBounds(frame, stepperID)
    let control = try controlBounds(frame, controlID([0, 0, 1]))
    #expect(control.size.width.value == 20 && control.size.height.value == 24, "20×24: \(control.size)")
    #expect(stepper.size.width.value == text.width.value + 28, "textW + 8 + 20: \(stepper.size.width.value)")
    #expect(stepper.size.height.value == max(text.height.value, 24), "\(stepper.size.height.value)")
    #expect(try controlBounds(frame, upID).size.height.value == 12, "two 12-point halves")
    #expect(try controlBounds(frame, downID).size.height.value == 12)

    let empty = try controlRender(controlRoot { Stepper("", value: .constant(1), in: 0...5) })
    let bare = try controlBounds(empty, stepperID)
    #expect(bare.size.width.value == 28 && bare.size.height.value == 24, "empty title: \(bare.size)")
}

/// **2.12.** A step clamps into the range, and writes nothing when the value
/// would not move (STA1: at 3 of 0…3, + writes nothing; STA2: at 0, − writes
/// nothing; STA3, step 2: 2 + → 3, 1 − → 0) — through the halves and through
/// accessibility requests. M2l (an unchanged value written) must redden it.
@Test @MainActor func aStepperClampsIntoItsRangeAndWritesNothingWhenTheValueWouldNotMove() throws {
    let top = Count(3)
    let (window, platform) = try stepperWindow { Stepper("Qty", value: top.binding, in: 0...3) }
    try tap(window, platform, upID)
    let node = try incrementor(window, platform)
    platform.simulateAccessibilityRequest(.increment(node.key))
    #expect(top.writes.isEmpty, "STA1: \(top.writes)")
    top.value = 0
    try tap(window, platform, downID)
    platform.simulateAccessibilityRequest(.decrement(node.key))
    #expect(top.writes.isEmpty, "STA2: \(top.writes)")

    let stepped = Count(2)
    let (w2, p2) = try stepperWindow { Stepper("Qty", value: stepped.binding, in: 0...3, step: 2) }
    try tap(w2, p2, upID)
    #expect(stepped.writes == [3], "STA3: 2 + 2 clamps to 3: \(stepped.writes)")
    stepped.value = 1
    let n2 = try incrementor(w2, p2)
    p2.simulateAccessibilityRequest(.decrement(n2.key))
    #expect(stepped.writes == [3, 0], "STA3: 1 − 2 clamps to 0: \(stepped.writes)")
}

/// **2.13.** An out-of-range value is shown and stepped from clamped (STA4:
/// 5 on 0…3 shows 3; + writes 3; from 5 again, − writes 2). M2m (stepping
/// from the raw value) must redden it — its − reads 3.
@Test @MainActor func anOutOfRangeStepperStepsFromItsClampedValue() throws {
    let model = Count(5)
    let (window, platform) = try stepperWindow { Stepper("Qty", value: model.binding, in: 0...3) }
    let node = try incrementor(window, platform)
    #expect(node.value.value == "3", "shows the clamped value: \(node.value.value ?? "nil")")
    try tap(window, platform, upID)
    #expect(model.writes == [3], "+ from 5 writes 3: \(model.writes)")
    model.value = 5
    try tap(window, platform, downID)
    #expect(model.writes == [3, 2], "− from 5 steps from 3: \(model.writes)")
}

/// **2.14.** With no range there is no clamp (STA5: 1 → 2 → 1 → 0 → −1). M2n
/// (an unbounded stepper clamped at 0) must redden it.
@Test @MainActor func anUnboundedStepperDoesNotClamp() throws {
    let model = Count(1)
    let (window, platform) = try stepperWindow { Stepper("Qty", value: model.binding) }
    try tap(window, platform, upID)
    try tap(window, platform, downID)
    try tap(window, platform, downID)
    try tap(window, platform, downID)
    #expect(model.writes == [2, 1, 0, -1], "\(model.writes)")
}

/// **2.15.** The closure initialiser runs each closure on its direction; a
/// nil one makes that direction do nothing and its half no click target
/// (STA6). M2o (a nil `onDecrement` falling back to `onIncrement`) must redden it.
@Test @MainActor func aClosureStepperRunsItsClosuresAndANilOneDisablesItsDirection() throws {
    let model = ControlModel()
    let (window, platform) = try stepperWindow {
        Stepper("S", onIncrement: { model.count += 1 }, onDecrement: nil)
    }
    #expect(!window.lastHitboxes.contains { $0.id == downID }, "a nil direction's half is no click target")
    try tap(window, platform, upID)
    #expect(model.count == 1, "the increment closure ran once")
    try tap(window, platform, downID)
    window.focus(stepperID)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == stepperID)
    platform.simulateInput(controlKey(TextEditing.downArrow))
    let node = try incrementor(window, platform)
    platform.simulateAccessibilityRequest(.decrement(node.key))
    #expect(model.count == 1, "the nil direction did nothing: \(model.count)")
    #expect(node.value.value == nil, "no value for the closure initialiser")

    let down = ControlModel()
    let (w2, p2) = try stepperWindow {
        Stepper("S", onIncrement: nil, onDecrement: { down.count -= 1 })
    }
    try tap(w2, p2, upID)
    try tap(w2, p2, downID)
    #expect(down.count == -1, "only the decrement ran: \(down.count)")
}

/// **2.16.** Published as an `.incrementor` labelled by its title (the partial
/// fold, divergence 82), valued by its value, with two `.button` children
/// (STA0). Lane 1's M1n (the partial fold removed), re-run on this lane's head,
/// must redden it.
@Test @MainActor func aStepperPublishesALabelledIncrementorWithTwoArrowButtons() throws {
    let model = Count(1)
    let (window, platform) = try stepperWindow { Stepper("Qty", value: model.binding, in: 0...5) }
    let node = try incrementor(window, platform)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    #expect(node.value.label == "Qty", "label \(node.value.label ?? "nil")")
    #expect(node.value.value == "1", "value \(node.value.value ?? "nil")")
    #expect(node.value.actions.contains(.increment) && node.value.actions.contains(.decrement))
    let children = node.value.children.compactMap { tree.nodes[$0] }
    #expect(children.count == 2 && children.allSatisfy { $0.role == .button },
            "two arrow buttons: \(children.map(\.role))")
    #expect(!tree.nodes.values.contains { $0.role == .staticText && $0.label == "Qty" },
            "the title is the label, not a sibling")
}

/// **2.17.** Focused, ↑ increments and ↓ decrements (`DD-T`). M2p (↑/↓
/// swapped) must redden it.
@Test @MainActor func aFocusedStepperStepsOnTheUpAndDownArrows() throws {
    let model = Count(1)
    let (window, platform) = try stepperWindow { Stepper("Qty", value: model.binding, in: 0...5) }
    window.focus(stepperID)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == stepperID, "a stepper takes focus")
    platform.simulateInput(controlKey(TextEditing.upArrow))
    platform.simulateInput(controlKey(TextEditing.downArrow))
    platform.simulateInput(controlKey(TextEditing.downArrow))
    #expect(model.writes == [2, 1, 0], "\(model.writes)")
}

/// **2.23.** Disabled: the halves, a focused ↑/↓ and increment/decrement
/// requests write nothing, and the incrementor publishes disabled (STA7;
/// `DD-AC` item 7). M1g (the central gate), re-run on this arm, must redden it.
@Test @MainActor func aDisabledStepperStepsNothingAndPublishesDisabled() throws {
    let model = Count(1)
    let (window, platform) = try stepperWindow {
        Stepper("Qty", value: model.binding, in: 0...5).disabled(true)
    }
    try tap(window, platform, upID)
    try tap(window, platform, downID)
    window.focus(stepperID)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(TextEditing.upArrow))
    platform.simulateInput(controlKey(TextEditing.downArrow))
    let node = try incrementor(window, platform)
    platform.simulateAccessibilityRequest(.increment(node.key))
    platform.simulateAccessibilityRequest(.decrement(node.key))
    #expect(model.writes.isEmpty, "nothing written while disabled: \(model.writes)")
    #expect(node.value.isEnabled == false, "published disabled")
}
