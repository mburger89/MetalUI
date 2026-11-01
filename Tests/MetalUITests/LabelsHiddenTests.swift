import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUITextSystem
import MetalUIText
@testable import MetalUILayout
@testable import MetalUI

// Round 3 item LB (`LB-A`): `labelsHidden()`. SwiftUI's answers are the probe's arms
// (`docs/probes/swiftui-labels-hidden.swift`): under `labelsHidden()` the control's own view starts at the
// container's leading edge (`P3`, `S2`, `R2`, `T2`, `E2`, `C2`), and an empty title WITHOUT it keeps the gap
// (`P2` x = 8, `S3`, `E3`, `C3`). Every frame here is read from the published accessibility tree, in the same
// `VStack(alignment: .leading)` as a `TextField` whose x is the reference.

private enum LBControl: CaseIterable {
    case menuPicker, segmentedPicker, radioPicker, checkbox, switchToggle, stepper, colorPicker, progress

    /// The role of the node that carries the control's own frame.
    var role: AccessibilityRole {
        switch self {
        case .menuPicker: .popUpButton
        case .segmentedPicker, .radioPicker: .radioGroup
        case .checkbox, .switchToggle: .checkBox
        case .stepper: .incrementor
        case .colorPicker: .colorWell
        case .progress: .progressIndicator
        }
    }
    /// The gap between the label and the control (0 where the title sits above).
    var gap: Float {
        switch self {
        case .menuPicker, .segmentedPicker, .radioPicker, .stepper, .colorPicker: 8
        case .checkbox, .switchToggle: 7
        case .progress: 0
        }
    }
}

@MainActor private func lbControl(_ kind: LBControl, title: String = "Title") -> AnyElement {
    switch kind {
    case .menuPicker:
        AnyElement(Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu))
    case .segmentedPicker:
        AnyElement(Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
            .pickerStyle(.segmented))
    case .radioPicker:
        AnyElement(Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
            .pickerStyle(.radioGroup))
    case .checkbox: AnyElement(Toggle(title, isOn: .constant(true)).toggleStyle(.checkbox))
    case .switchToggle: AnyElement(Toggle(title, isOn: .constant(true)).toggleStyle(.switch))
    case .stepper: AnyElement(Stepper(title, value: .constant(1)))
    case .colorPicker: AnyElement(ColorPicker(title, selection: .constant(Color.red)))
    case .progress: AnyElement(ProgressView(title, value: 0.5))
    }
}

/// The control's own frame and the reference field's, from the published tree.
@MainActor private func lbFrames<G: ElementGroup>(_ kind: LBControl, @ElementBuilder _ build: @escaping () -> G) throws
    -> (field: Bounds<Pixels>, control: Bounds<Pixels>, node: AccessibilityNode) {
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("field", text: .constant("")).frame(width: Pixels(100))
                build()
            }
        }
    }
    let tree = try controlTree(window, platform)
    let field = try #require(tree.nodes.first { $0.value.role == .textField }, "no text field")
    let controls = tree.nodes.filter { $0.value.role == kind.role }
    try #require(controls.count == 1, "\(kind): one \(kind.role) node: \(tree.nodes.values.map(\.role))")
    let control = controls.first!
    return (try #require(tree.geometry[field.key]?.frame), try #require(tree.geometry[control.key]?.frame),
            control.value)
}

/// **1.** A hidden label takes no space: the control's own frame starts at the field's x and is the shown frame
/// less the label and its gap (menu picker: the button itself, `P3`). Mutation: the `Picker` keeping the title in
/// layout when hidden (reddens the three picker arms), `Toggle.hidesLabel` returning false (the toggle arms),
/// `Stepper`'s `wrapped = … ? nil :` always `Text(title)` (stepper), `ColorPicker`'s `hidden ? nil : label` (colour).
@Test @MainActor func aHiddenLabelTakesNoSpace() throws {
    for kind in LBControl.allCases {
        let shown = try lbFrames(kind) { lbControl(kind) }
        let hidden = try lbFrames(kind) { lbControl(kind).labelsHidden() }
        let text = try controlTextSize("Title")
        #expect(hidden.control.origin.x == hidden.field.origin.x, "\(kind): starts at the field's x: \(hidden.control)")
        if kind == .progress {
            #expect((shown.control.origin.y.value - shown.field.origin.y.value)
                    - (hidden.control.origin.y.value - hidden.field.origin.y.value) == text.height.value,
                    "\(kind): the title row above the bar is gone: shown \(shown.control), hidden \(hidden.control)")
        } else if kind == .menuPicker || kind == .colorPicker {
            // The node is the button/well alone: the shown one starts after the label.
            #expect(shown.control.origin.x.value == shown.field.origin.x.value + text.width.value + kind.gap,
                    "\(kind): shown control after label and gap: \(shown.control)")
            #expect(abs(hidden.control.size.width.value - shown.control.size.width.value) <= 1,
                    "\(kind): the control itself is unchanged (to rounding): \(shown.control) vs \(hidden.control)")
        } else {
            #expect(hidden.control.size.width.value == shown.control.size.width.value - text.width.value - kind.gap,
                    "\(kind): width is the shown one less label \(text.width.value) and gap \(kind.gap): shown \(shown.control.size.width.value), hidden \(hidden.control.size.width.value)")
        }
    }
}

/// **2.** An empty title without `labelsHidden()` keeps the gap, as SwiftUI does (`P2` x = 8, `S3`, `E3`, `C3`,
/// `T3`): the empty label still sits in the row. Corrects `LK-C` item 2 for `ColorPicker`. Mutation: the
/// `Picker`/`Stepper` dropping an empty title, or `ColorPicker.init(_:…)` passing nil for it.
@Test @MainActor func anEmptyTitleStillTakesTheGap() throws {
    for kind in [LBControl.menuPicker, .segmentedPicker, .stepper, .colorPicker] {
        let empty = try lbFrames(kind) { lbControl(kind, title: "") }
        let hiddenEmpty = try lbFrames(kind) { lbControl(kind, title: "").labelsHidden() }
        if kind == .segmentedPicker || kind == .stepper {
            #expect(empty.control.size.width.value - hiddenEmpty.control.size.width.value == 8,
                    "\(kind): the gap remains: \(empty.control) vs \(hiddenEmpty.control)")
        } else {
            #expect(empty.control.origin.x.value - empty.field.origin.x.value == 8, "\(kind): x = 8: \(empty.control)")
            #expect(hiddenEmpty.control.origin.x == hiddenEmpty.field.origin.x, "\(kind): hidden is flush")
        }
    }
}

/// **3.** The label is still the accessibility label (SwiftUI keeps it for VoiceOver): shown and hidden publish the
/// same one, for a string title and for a closure label that is a `Text`. Mutation: dropping `axNode.label =` in
/// `Picker.prepaint`, `Stepper.prepaint`, `Toggle.composedHandlers`, `ColorWell.prepaint` or `ProgressView`'s
/// `title ??` (each reddens its own arm).
@Test @MainActor func aHiddenLabelIsStillTheAccessibilityLabel() throws {
    for kind in LBControl.allCases {
        let shown = try lbFrames(kind) { lbControl(kind) }
        let hidden = try lbFrames(kind) { lbControl(kind).labelsHidden() }
        if kind != .colorPicker {   // the shown colour well is unlabelled: its label is a sibling text (`C1`)
            #expect(shown.node.label == "Title", "\(kind) set up: shown label \(String(describing: shown.node.label))")
        }
        #expect(hidden.node.label == "Title", "\(kind) hidden label \(String(describing: hidden.node.label))")
    }
    let toggle = try lbFrames(.checkbox) { Toggle(isOn: .constant(true)) { Text("Closure") }.labelsHidden() }
    #expect(toggle.node.label == "Closure", "a Text-labelled closure toggle: \(String(describing: toggle.node.label))")
    let colour = try lbFrames(.colorPicker) { ColorPicker(selection: .constant(Color.red)) { Text("Closure") }.labelsHidden() }
    #expect(colour.node.label == "Closure")
}

/// **4.** A label that is not a `Text` has no text to keep: hidden it publishes no label (divergence 1025).
/// Mutation: none beyond `labelPlainText` — this pins the carried gap, so a fix reddens it on purpose.
@Test @MainActor func aHiddenNonTextLabelPublishesNoLabel() throws {
    let toggle = try lbFrames(.checkbox) {
        Toggle(isOn: .constant(true)) { HStack { Text("a"); Text("b") } }.labelsHidden()
    }
    #expect(toggle.node.label == nil, "no text to keep: \(String(describing: toggle.node.label))")
}

/// **5.** The modifier is an environment write: it reaches a control through containers, the nearest writer wins,
/// and a caller's own `accessibilityLabel` outranks the kept title. Mutation: `labelsHidden()` writing `false`
/// (reddens 1), writing only on the direct child (this arm: the control sits in a `Column`).
@Test @MainActor func labelsHiddenReachesAControlThroughAContainerAndTheNearestWriterWins() throws {
    let through = try lbFrames(.stepper) { VStack { Stepper("Title", value: .constant(1)) }.labelsHidden() }
    #expect(through.control.origin.x == through.field.origin.x && through.control.size.width.value == 20,
            "the stepper is 20 wide, label gone: \(through.control)")
    let toggled = try lbFrames(.stepper) {
        VStack { Stepper("Title", value: .constant(1)).environment(\.labelsHidden, false) }.labelsHidden()
    }
    #expect(toggled.control.size.width.value > 20, "the inner writer shows the label again: \(toggled.control)")
    let own = try lbFrames(.stepper) { Stepper("Title", value: .constant(1)).accessibilityLabel("Own").labelsHidden() }
    #expect(own.node.label == "Own", "a declared label wins over the kept title: \(String(describing: own.node.label))")
}

private struct LBLabelOnlyStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// **4b.** What the modifier does not reach (divergence 1026): the `.button` look and a custom `ToggleStyle`
/// draw their label hidden or shown — the same width either way. Mutation: `hidesLabel` dropping its
/// `look != .button` guard (the button arm), `requestCustomLayout` reading `box.content.second.wrapped`
/// instead of `label` (the custom arm).
@Test @MainActor func aCustomToggleStyleAndTheButtonLookKeepTheirLabel() throws {
    func width<G: ElementGroup>(@ElementBuilder _ build: @escaping () -> G) throws -> Float {
        try lbFrames(.checkbox, build).control.size.width.value
    }
    let button = try width { Toggle("Title", isOn: .constant(true)).toggleStyle(.button) }
    let buttonHidden = try width { Toggle("Title", isOn: .constant(true)).toggleStyle(.button).labelsHidden() }
    #expect(button == buttonHidden && button > 30, "the button look keeps its label: \(button) vs \(buttonHidden)")
    let custom = try width { Toggle("Title", isOn: .constant(true)).toggleStyle(LBLabelOnlyStyle()) }
    let customHidden = try width { Toggle("Title", isOn: .constant(true)).toggleStyle(LBLabelOnlyStyle()).labelsHidden() }
    #expect(custom == customHidden && custom > 20, "a custom style draws configuration.label: \(custom) vs \(customHidden)")
}

// MARK: - Retained subtrees (`EE-F`, `LB-A` item 4)

private struct LBCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Picker("Title", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu)
    }
    static func == (l: LBCard, r: LBCard) -> Bool { true }
}

@MainActor private final class LBModel { var hidden = false }

/// **6.** An ancestor toggling `labelsHidden` re-lays-out a retained (`.equatable()`) occurrence: the card is
/// equal to itself every frame, so only the environment fingerprint can tell it to rebuild. The card must have
/// been retained (a graft record exists) before the flip, or the arm proves nothing. Mutation:
/// `EnvironmentValues.retainedFingerprint` building `custom` as `[:]`.
@Test @MainActor func anAncestorTogglingLabelsHiddenRelaysOutARetainedCard() throws {
    let model = LBModel()
    let (window, platform) = try controlWindow {
        controlRoot(width: 400, height: 400) { VStack(spacing: 0) { LBCard().equatable().environment(\.labelsHidden, model.hidden) } }
    }
    for _ in 0..<5 { controlRedraw(window) }
    func buttonX() throws -> Float {
        let tree = try controlTree(window, platform)
        let button = try #require(tree.nodes.first { $0.value.role == .popUpButton })
        return try #require(tree.geometry[button.key]?.frame).origin.x.value
    }
    var records = 0
    window.testingStoredGraftRecords { _ in records += 1 }
    try #require(records >= 1, "set up: the card was retained before the flip")
    let shown = try buttonX()
    #expect(shown > 8, "set up: the title sits before the button: x = \(shown)")
    model.hidden = true
    for _ in 0..<3 { controlRedraw(window) }
    #expect(try buttonX() == 0, "hidden: the button is flush left, not the retained x = \(shown)")
    model.hidden = false
    for _ in 0..<3 { controlRedraw(window) }
    #expect(try buttonX() == shown, "shown again")
}

/// **7.** The slot stays reserved: a control's `@State`-bearing content keeps its identity when the label hides
/// (the option content numbers from the same index). Pinned by the picker's options keeping their ids.
/// Mutation: `OptionalGroup` replaced by a conditional that renumbers.
@Test @MainActor func hidingTheLabelKeepsTheOptionsIdentity() throws {
    func ids(hidden: Bool) throws -> Set<GlobalElementID> {
        let frame = try controlRender(controlRoot {
            Picker("Title", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
                .pickerStyle(.radioGroup).environment(\.labelsHidden, hidden)
        })
        return Set(frame.elementBounds.keys)
    }
    let shown = try ids(hidden: false), hidden = try ids(hidden: true)
    let options = controlID([0, 0, 1])
    #expect(shown.contains(options) && hidden.contains(options), "the options box is child 1 either way")
}

// MARK: - Compile guard

/// **8.** The SwiftUI spelling compiles on a control and on a container (a `Component`'s content too).
@Test @MainActor func theSwiftUISpellingTypechecks() {
    _ = Picker("", selection: .constant(1)) { Text("A").tag(1) }.pickerStyle(.menu).labelsHidden()
    _ = VStack { Toggle("t", isOn: .constant(true)) }.labelsHidden()
}
