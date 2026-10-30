import MetalUI
import MetalUITesting
import Testing

// `SE-`: a segmented `Picker` publishes one radio-button element per segment, found and
// clicked by identifier. Plain imports, so the fixtures spell what an app writes.

private enum Mode: String, Hashable { case alpha, beta, gamma }

/// A segmented picker whose first segment declares its own identifier on its `Text`; the
/// others take `"mode.<tag>"` from the picker's.
private struct ModePicker: Component {
    @State var mode = Mode.beta
    let style: PickerStyle
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Alpha").accessibilityIdentifier("custom-alpha").tag(Mode.alpha)
                Text("Beta").tag(Mode.beta)
                Text("Gamma").tag(Mode.gamma)
            }
            .pickerStyle(style)
            .accessibilityIdentifier("mode")
            Text("mode is \(mode.rawValue)")
        }
    }
}

/// A picker with no identifier of its own and none on its content.
private struct AnonymousPicker: Component {
    @State var mode = Mode.beta
    var content: some ElementGroup {
        Picker("Mode", selection: $mode) {
            Text("Alpha").tag(Mode.alpha)
            Text("Beta").tag(Mode.beta)
        }
    }
}

/// SE-A 1. Per segment: role, label, selected state, value and a non-empty frame, beneath a
/// group that keeps the picker's own label and identifier. Mutations SE-M1 (the segment's
/// `.radioButton` axNode made `.generic`) and SE-M7 (value always "0") redden it.
@Test(arguments: [PickerStyle.segmented, PickerStyle.radioGroup]) @MainActor
func eachSegmentIsARadioButtonElementUnderTheGroup(style: PickerStyle) throws {
    let window = try harnessWindow { VStack(spacing: 0) { ModePicker(style: style) } }
    let group = try window.element(identifier: "mode")
    #expect(group.role == .radioGroup)
    #expect(group.label == "Mode")
    let segments = try window.elements(role: .radioButton)
    try #require(segments.count == 3)
    #expect(group.children == segments.map(\.id))
    #expect(segments.map(\.label) == ["Alpha", "Beta", "Gamma"])
    #expect(segments.map(\.isSelected) == [false, true, false])
    #expect(segments.map(\.value) == ["0", "1", "0"])
    #expect(segments.allSatisfy { $0.frame.size.width.value > 0 && $0.frame.size.height.value > 0 })
    // Segments run along x, radio rows down y.
    let along = segments.map { style == .segmented ? $0.frame.origin.x.value : $0.frame.origin.y.value }
    #expect(along[0] < along[1] && along[1] < along[2], "distinct rects in order: \(along)")
}

/// SE-A 2. An identifier declared inside the segment's content is the segment's. Mutation
/// SE-M2 (the radio-button fold of the content's identifier removed) reddens it.
@Test @MainActor func aSegmentTakesTheIdentifierItsContentDeclared() throws {
    let window = try harnessWindow { VStack(spacing: 0) { ModePicker(style: .segmented) } }
    let alpha = try window.element(identifier: "custom-alpha")
    #expect(alpha.role == .radioButton)
    #expect(alpha.label == "Alpha")
}

/// SE-A 3. Without one, a segment's identifier is `"<picker identifier>.<tag>"`, and an
/// explicit one beats it. Mutation SE-M3 (the derivation removed) reddens it; SE-M4 (derived
/// wins over a content identifier) reddens `aSegmentTakesTheIdentifierItsContentDeclared`.
@Test @MainActor func aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag() throws {
    let window = try harnessWindow { VStack(spacing: 0) { ModePicker(style: .segmented) } }
    let beta = try window.element(identifier: "mode.beta")
    #expect(beta.role == .radioButton)
    #expect(beta.label == "Beta")
    #expect(try window.element(identifier: "mode.gamma").label == "Gamma")
    #expect(throws: (any Error).self) { try window.element(identifier: "mode.alpha") }
}

/// SE-A 4. No identifier on the picker or the content publishes none.
@Test @MainActor func aPickerWithoutAnIdentifierDerivesNone() throws {
    let window = try harnessWindow { VStack(spacing: 0) { AnonymousPicker() } }
    let segments = try window.elements(role: .radioButton)
    try #require(segments.count == 2)
    #expect(segments.allSatisfy { $0.identifier == nil })
}

/// SE-A 5. What MetalFlow wants: find a segment by identifier, click it, and the selection
/// changes. Mutation SE-M5 (the radio-button `onClick` write removed) reddens it.
@Test(arguments: [PickerStyle.segmented, PickerStyle.radioGroup]) @MainActor
func clickingASegmentFoundByIdentifierSelectsIt(style: PickerStyle) throws {
    let window = try harnessWindow { VStack(spacing: 0) { ModePicker(style: style) } }
    try window.click(try window.element(identifier: "mode.gamma"))
    window.tick()
    #expect(try window.element(label: "mode is gamma").role == .staticText)
    #expect(try window.element(identifier: "mode.gamma").isSelected)
    #expect(try window.element(identifier: "mode.beta").isSelected == false)
    try window.click(try window.element(identifier: "custom-alpha"))
    window.tick()
    #expect(try window.element(label: "mode is alpha").role == .staticText)
}

/// SE-A 6. The press action a screen reader performs selects the segment as a click does.
/// Mutation SE-M5 (the `onClick` write removed) reddens it too.
@Test @MainActor func pressingASegmentElementSelectsIt() throws {
    let window = try harnessWindow { VStack(spacing: 0) { ModePicker(style: .segmented) } }
    let gamma = try window.element(identifier: "mode.gamma")
    #expect(try window.performAccessibilityAction(.press, on: gamma))
    window.tick()
    #expect(try window.element(label: "mode is gamma").role == .staticText)
}
