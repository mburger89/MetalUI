import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// C10 lane 1: `Slider(value:in:[step:]onEditingChanged:)` (rulings `LK-B`,
// `LK-Q`; spec `2026-10-08-controls-looks-design.md` §3.1, §4.1). SwiftUI's
// order is probe `S1` (`docs/probes/swiftui-controls-looks.swift`): `editing
// true | set … | editing false`, one pair per gesture; `S2` a press with no
// drag; `S4` an accessibility adjust a whole edit; `S5` an outside write and
// `S7` a disabled press call nothing. The edges (a lost release, a slider that
// left the tree, a claimed release, a close) are MetalUI's pairing invariant
// (`LK-B` item 5, `LK-Q`). Helpers are `ButtonTests.swift`'s `control…`.
//
// Footing: a 300-point window, the slider 300 wide at x = 0 over 0…10, so a
// press at x writes `clamp01((x − 10) / 280) × 10` (`SliderTests` 2.6): x 150
// → 5, x 38 → 1, x 290 → 10. Every literal below is that arithmetic.

@MainActor
private final class EditLog {
    var value: Double
    var log: [String] = []
    var shown = true
    var disabled = false
    var alertShown = false
    var raisesAlertOnWrite = false
    init(_ value: Double = 0) { self.value = value }

    var binding: Binding<Double> {
        Binding(get: { self.value }, set: {
            self.value = $0
            self.log.append("set \(Self.format($0))")
            if self.raisesAlertOnWrite { self.alertShown = true }
        })
    }
    var alertBinding: Binding<Bool> {
        Binding(get: { self.alertShown }, set: { self.alertShown = $0 })
    }
    func editing(_ editing: Bool) { log.append("editing \(editing)") }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

/// A 300-point window over one slider (shown while `model.shown`, disabled
/// while `model.disabled`) in a 300×300 `Row` root.
@MainActor
private func editingWindow(_ model: EditLog, step: Double? = nil)
    throws -> (Window, FakePlatformWindow) {
    try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            if model.shown {
                (step.map { Slider(value: model.binding, in: 0...10, step: $0, onEditingChanged: model.editing) }
                    ?? Slider(value: model.binding, in: 0...10, onEditingChanged: model.editing))
                    .disabled(model.disabled)
            }
        }
    }
}

/// The slider's 300×16 box in the last frame.
@MainActor
private func sliderBox(_ window: Window) throws -> (id: GlobalElementID, bounds: Bounds<Pixels>) {
    let found = window.lastElementBounds.filter { $0.value.size.width.value == 300 && $0.value.size.height.value == 16 }
    let entry = try #require(found.first, "no 300×16 slider box: \(window.lastElementBounds.values.map(\.size))")
    return (entry.key, entry.value)
}

@MainActor
private func at(_ window: Window, x: Float) throws -> MouseEvent {
    let box = try sliderBox(window).bounds
    return MouseEvent(position: Point(x: controlPx(x), y: controlPx(box.origin.y.value + 8)))
}

/// **1.1.** A press calls `onEditingChanged(true)` before the press's write
/// (S1). Mutation: call `onEditingChanged(true)` after `track(toWindowX:)`.
@Test @MainActor func aSliderPressCallsEditingTrueBeforeItsFirstWrite() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    #expect(model.log == ["editing true", "set 5"], "\(model.log)")
}

/// **1.2.** Two drags write again, and the release calls `false` after the
/// last write (S1's order). Mutation: drop the release end.
@Test @MainActor func aSliderReleaseCallsEditingFalseAfterTheLastWrite() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    platform.simulateInput(.mouseDragged(try at(window, x: 38)))
    platform.simulateInput(.mouseDragged(try at(window, x: 290)))
    platform.simulateInput(.mouseUp(try at(window, x: 290)))
    #expect(model.log == ["editing true", "set 5", "set 1", "set 10", "editing false"], "\(model.log)")
}

/// **1.3.** A press with no drag is `true`, the write, `false` (S2).
/// Mutation: skip the write on a press.
@Test @MainActor func aPressWithNoDragIsTrueWriteFalse() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    platform.simulateInput(.mouseUp(try at(window, x: 150)))
    #expect(model.log == ["editing true", "set 5", "editing false"], "\(model.log)")
}

/// **1.4.** A disabled slider's press, drag and release call nothing (S7: the
/// track rides the gated hitbox). Mutation: register `valueTrack` outside the
/// disabled gate.
@Test @MainActor func aDisabledSliderPressCallsNothing() throws {
    let model = EditLog()
    model.disabled = true
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    platform.simulateInput(.mouseDragged(try at(window, x: 38)))
    platform.simulateInput(.mouseUp(try at(window, x: 38)))
    #expect(model.log.isEmpty, "\(model.log)")
}

/// **1.5.** A binding write from outside calls nothing, over two frames (S5).
/// Mutation: call `onEditingChanged` from `paint` on a value change.
@Test @MainActor func anOutsideBindingWriteCallsNothing() throws {
    let model = EditLog(2)
    let (window, _) = try editingWindow(model)
    model.value = 7
    controlRedraw(window)
    controlRedraw(window)
    #expect(model.log.isEmpty, "\(model.log)")
}

/// **1.6.** An accessibility increment is a whole edit: `true`, the write,
/// `false` (S4: 5 → 6 on 0…10, 10% of the span). Mutation: drop the pair
/// around the adjust closure's write.
@Test @MainActor func anAccessibilityIncrementIsAWholeEdit() throws {
    let model = EditLog(5)
    let (window, platform) = try editingWindow(model)
    let tree = try controlTree(window, platform)
    let node = try #require(tree.nodes.first { $0.value.role == .slider }, "no slider published")
    #expect(platform.simulateAccessibilityRequest(.increment(node.key)))
    #expect(model.log == ["editing true", "set 6", "editing false"], "\(model.log)")
}

/// **1.7.** An arrow key on a focused slider is a whole edit (MetalUI's rule
/// by analogy with S4; SwiftUI's slider takes no arrow, `KY7`). Mutation: the
/// same, keyboard branch.
@Test @MainActor func anArrowKeyIsAWholeEdit() throws {
    let model = EditLog(5)
    let (window, platform) = try editingWindow(model)
    let id = try sliderBox(window).id
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "the slider takes focus")
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    #expect(model.log == ["editing true", "set 6", "editing false"], "\(model.log)")
}

/// **1.8.** A release after the slider left the tree still ends the edit
/// (`LK-B` item 5). Mutation: look the callback up in `lastHitboxes` at the
/// release.
@Test @MainActor func aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    let up = try at(window, x: 150)
    platform.simulateInput(.mouseDown(up))
    model.shown = false
    controlRedraw(window)
    try #require(!window.lastElementBounds.values.contains { $0.size.width.value == 300 && $0.size.height.value == 16 },
                 "set up: the slider left the tree")
    platform.simulateInput(.mouseUp(up))
    #expect(model.log == ["editing true", "set 5", "editing false"], "\(model.log)")
}

/// **1.9.** A release after the slider was disabled mid-drag still ends the
/// edit (`LK-B` item 5). Mutation: the same lookup.
@Test @MainActor func aReleaseAfterTheSliderWasDisabledStillEndsTheEdit() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    model.disabled = true
    controlRedraw(window)
    platform.simulateInput(.mouseUp(try at(window, x: 150)))
    #expect(model.log == ["editing true", "set 5", "editing false"], "\(model.log)")
}

/// **1.10.** Closing the window mid-drag counts as the release (`LK-B` item
/// 5): `runDisappearancesForClose`, which `App`'s `onClose` calls, ends the
/// edit once. Mutation: drop the close-path call.
@Test @MainActor func closingTheWindowMidDragEndsTheEdit() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    window.runDisappearancesForClose()
    window.runDisappearancesForClose()
    #expect(model.log == ["editing true", "set 5", "editing false"], "\(model.log)")
}

/// **1.11** (`LK-Q`). The press's write raises an `.alert`, which the fake
/// declines (SDL's answer), so the window draws it and holds it modal: it
/// claims the release. The edit still ends — the end runs right after the
/// pointer state, ahead of every claiming stage. Mutation: end the edit in
/// `dispatchValueTrack`'s `.mouseUp` case (the first design's spelling).
@Test @MainActor func aReleaseClaimedByTheDrawnAlertStillEndsTheEdit() throws {
    let model = EditLog()
    model.raisesAlertOnWrite = true
    let (window, platform) = try controlWindow(size: 300) {
        controlRoot(width: 300, height: 300) {
            Slider(value: model.binding, in: 0...10, onEditingChanged: model.editing)
                .alert("Refused", isPresented: model.alertBinding) {
                    Button("OK") {}
                }
        }
    }
    platform.presentsAlertsNatively = false
    let press = try at(window, x: 150)
    platform.simulateInput(.mouseDown(press))
    window.drawFrameIfNeeded()
    controlRedraw(window)
    try #require(window.drawnAlert != nil, "set up: the alert is drawn and modal")
    platform.simulateInput(.mouseUp(press))
    #expect(model.log == ["editing true", "set 5", "editing false"], "\(model.log)")
}

/// **1.12** (`LK-Q`). A second press with no release between (a lost release)
/// ends the first edit before it begins its own. Mutation: overwrite
/// `editingTrack` without ending it.
@Test @MainActor func aSecondPressWithoutAReleaseEndsTheFirstEdit() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    platform.simulateInput(.mouseDown(try at(window, x: 38)))
    #expect(model.log == ["editing true", "set 5", "editing false", "editing true", "set 1"], "\(model.log)")
}

/// **1.13** (`LK-Q` item 2). The end claims nothing: the release continues
/// to the stages as at `cd84b0c` and, unclaimed by any, reaches the window's
/// own `onInput`, whose answer is the hook's. (The ruling's observer, an
/// `onTapGesture` ancestor, cannot see the release on either side: the
/// slider's press is claimed by its own stage, so no arena forms — the
/// window's `onInput` is the observer that can.) Mutation: return `true`
/// from the end.
@Test @MainActor func theReleaseIsNotClaimedByTheSlider() throws {
    let model = EditLog()
    let (window, platform) = try editingWindow(model)
    var releases = 0
    window.onInput = { event in
        if case .mouseUp = event { releases += 1 }
        return false
    }
    platform.simulateInput(.mouseDown(try at(window, x: 150)))
    let claimed = platform.simulateInput(.mouseUp(try at(window, x: 150)))
    #expect(model.log.last == "editing false", "\(model.log)")
    #expect(releases == 1, "the release reached the window's onInput \(releases) times")
    #expect(!claimed, "nothing claimed the release")
}

/// A component holding an edit counter in `@State`: every `onEditingChanged`
/// call adds one.
private struct EditCounter: Component {
    @State var edits = 0
    @State var value = 0.0
    var content: some ElementGroup {
        Column {
            Slider(value: $value, in: 0...10, onEditingChanged: { _ in edits += 1 }).frame(width: Pixels(300))
            Text("edits \(edits)")
        }
    }
}

/// **1.14** (`ID-F`). One component value placed twice: a press and release on
/// the FIRST occurrence's slider count both calls into that occurrence's
/// `@State` — under `StateDispatch` to the pressed slider — and not into the
/// last-bound second occurrence. Mutation: run the calls outside
/// `StateDispatch`.
@Test @MainActor func theEditingCallbacksRunUnderTheSlidersDispatch() throws {
    let (window, platform) = try controlWindow(size: 300) {
        let counter = EditCounter()
        return Column { counter; counter }.cssWidth(controlPx(300)).cssHeight(controlPx(300))
    }
    let sliders = window.lastHitboxes.filter { $0.handlers.valueTrack != nil }
    try #require(sliders.count == 2, "each occurrence registers its own slider, got \(sliders.count)")
    let first = sliders.min { $0.bounds.origin.y.value < $1.bounds.origin.y.value }!
    let point = Point(x: controlPx(150), y: controlPx(first.bounds.origin.y.value + 8))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    let tree = try controlTree(window, platform)
    // Top to bottom, by each text node's published frame.
    let texts = tree.nodes.filter { $0.value.value?.hasPrefix("edits ") == true }
        .sorted { (tree.geometry[$0.key]?.frame.origin.y.value ?? 0) < (tree.geometry[$1.key]?.frame.origin.y.value ?? 0) }
        .compactMap(\.value.value)
    #expect(texts == ["edits 2", "edits 0"], "the first (upper) occurrence counts both calls: \(texts)")
}
