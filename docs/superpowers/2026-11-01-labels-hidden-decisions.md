# `labelsHidden()` — decisions (prefix `LB-`)

Rulings for the MetalFlow request of 2026-11-01: `Picker("", selection:)` with `.pickerStyle(.menu)` still indented 8 points
(an empty `Text(title)` plus the row's 8-point gap), so it could not line up with a caption above it. Branch `feat/labels-hidden` from
master `5be22a6a`. Code: `Sources/MetalUI/LabelsHidden.swift` (new), `Picker.swift`, `Toggle.swift`, `Stepper.swift`, `ColorPicker.swift`,
`ProgressView.swift` (and the two `Toggle`-label readers in `Toolbar.swift` and `MenuContent.swift`). Probe: `docs/probes/swiftui-labels-hidden.swift`.
Tests: `LabelsHiddenTests.swift`. **Next unused: `LB-D`.** Divergences 1025 and 1026 (reserved 1025–1034; 1027–1034 unused).

SwiftUI's declaration (`SwiftUI.swiftinterface`, macOS 27.2 SDK): `extension View { nonisolated public func labelsHidden() -> some View }`.

## LB-A: the design

1. **`labelsHidden()` is an `ElementGroup` modifier writing an internal `Bool` environment key** (`LabelsHiddenKey`; SwiftUI's key is private too,
   `View.labelsHidden()` is the only public spelling). It is spelled like `toggleStyle(_:)`/`controlSize(_:)` (an `EnvironmentScope`), the
   nearest writer wins (`.environment(\.labelsHidden, false)` shows labels again below it) and it reaches a control through any container.
   A custom key, so the value is an `EnvironmentReading.of(true)` and a retained subtree's fingerprint sees it (`EE-F`): no fingerprint field.
2. **An empty title without the modifier keeps the gap** (probe `P2`/`S3`/`E3`/`C3`: the control starts at x = 8, `P1`'s 34.5 less the
   label's own width; `T3`: a `Toggle("")` is 21 wide against `T2`'s 16). MetalUI's `Picker("")`, `Stepper("")` and `Toggle("")` already did;
   **`ColorPicker("")` did not** (it dropped label and gap, claimed to be `labelsHidden()`'s answer, `LK-C` item 2) and now keeps the 8: that
   behaviour was `labelsHidden()`'s, not the empty title's, and the probe separates them. A caller who relied on `ColorPicker("")` being the well
   alone adds `.labelsHidden()`.
3. **A hidden label is removed from layout, not shrunk.** Each labelled control puts its title in an `OptionalGroup` slot and passes `nil`:
   no node, no gap (a flex gap applies between nodes), and the slot stays reserved, so the control's other children keep their identity
   hidden or shown. The label stays the control's accessibility label (SwiftUI keeps it for VoiceOver): a string title is set on the control's
   own node (`Picker` group, `Stepper`, `ProgressView`'s indicator; a menu picker's pop-up already carried it), a closure label only when it is
   exactly a `Text` (`labelPlainText`: `Toggle`, `ColorPicker`'s well, `ProgressView`'s indicator). A caller's own `accessibilityLabel` wins.
   Any other closure label content has no text to keep (divergence 1025).
4. **Layout when hidden**, read from the published accessibility tree in a `VStack(alignment: .leading)` beside a `TextField`: the menu
   picker's button, the colour well, the segmented/radio group, the stepper, the toggle and the progress bar start at the field's x; the
   segmented/radio group, stepper and toggle are the shown width less the label's width and the gap (8; 7 for a toggle); a progress view is
   one label row (16) shorter (probe `G2`: 64 → 48).
5. **Coverage.** `Picker` in every style (segmented, the automatic style = segmented, radio group = inline, menu), `Toggle` in the checkbox
   and switch looks, `Stepper`, `ColorPicker`, `ProgressView`'s title (probe `G1`/`G2` measured it). **Not reached** (divergence 1026): the
   `.button` toggle look (its label is the whole control), a custom `ToggleStyle` (it draws `configuration.label` itself; whether SwiftUI hides
   that one is unmeasured), `ProgressView`'s current-value label (unmeasured), `Slider` and `TextField` (no separate label in MetalUI) and
   toolbar/menu items (they have no label row).

## LB-B: identity

`OptionalGroup` wraps its content under a slot of its own, so a title's id gained one level (`[0, 0, 0]` → `[0, 0, 0, 0]` for a `Picker`'s
`Text`, a `Toggle`'s label, a `Stepper`'s title); the other children, which number after the reserved slot, did not move. Three existing tests
that named those paths were updated. A `@State` inside a `Toggle`'s closure label starts afresh once, on the upgrade, and is stable after.

## LB-C: carried

Whether SwiftUI's `labelsHidden()` reaches a custom `ToggleStyle`'s label and a `ProgressView`'s current-value label (probe both; divergence
1026); a non-`Text` hidden label's accessibility text (divergence 1025: it needs the label's text without laying it out, e.g. a layout-free
accessibility walk); `Gauge`, `LabeledContent` and `DatePicker` do not exist in MetalUI.
