# 189 - `labelsHidden()` (`LB-A`..`LB-C`)

2026-11-01, branch `feat/labels-hidden` from master `5be22a6a`; MetalFlow request (ten `Picker("", …).pickerStyle(.menu)` that could not line
up with a caption: the empty `Text(title)` and the row's 8-point gap indented them 8). Rulings:
`docs/superpowers/2026-11-01-labels-hidden-decisions.md`. Rule: `docs/rules/layout.md` ("`labelsHidden()`"). Records 186-188 are held by open PRs.

## 1. What was there

No `labelsHidden()` (only mentioned in `ColorPicker`'s comment as the answer of an empty title). Each labelled control built `Pair(Text(title), control)`
in a row with an 8-point gap (7 for `Toggle`); `ColorPicker("")` alone dropped label and gap.

## 2. The probe

`docs/probes/swiftui-labels-hidden.swift` hosts each control in an `NSHostingView` (no pixels, no screen capture) under a 100-wide `TextField` in
`VStack(alignment: .leading, spacing: 4)` and prints the leaf AppKit views' frames. Recorded output is in the file (125 lines, two runs byte-identical).
Menu picker: `Picker("Title")` x = 34.5, `Picker("")` x = **8.0**, `.labelsHidden()` x = **0.0** with either title. The same separation for segmented
(34.5 / 8 / 0), `Stepper` (34.5 / 8 / 0), `ColorPicker` (31.5 / 8 / 0), radio group (34.5 / 0), switch (34.5 / 0); checkbox ring 47.5 -> 16 wide;
`ProgressView("Title", value:)` 64 -> 48 tall hidden. **An empty title keeps the gap in SwiftUI** (`LB-A` item 2).

## 3. Design

An internal `Bool` custom environment key and `ElementGroup.labelsHidden()` (`LabelsHidden.swift`). `Picker` (all styles), `Toggle` (checkbox, switch),
`Stepper` and `ColorPicker`/`ProgressView` (already optional) hold their title in an `OptionalGroup` and pass `nil` when hidden, so the node and its gap
are gone and the slot is reserved. The title becomes the control's `axNode.label` (string titles; `Text` closure labels via `labelPlainText`).
`ColorPicker("")` now keeps the gap (corrects `LK-C` item 2). Not reached: the `.button` toggle look, custom `ToggleStyle`s, a progress view's
current-value label (divergence 1026); a non-`Text` closure label keeps no accessibility label (1025).

## 4. Source breaks

`ColorPicker("", selection:)` is 8 points wider (add `.labelsHidden()`). A title's element id gains one level (`LB-B`); `Toggle`/`Stepper` stored
properties changed (`swift package clean`). `docs/migration.md` unchanged (no API removed).

## 5. Tests

`LabelsHiddenTests.swift` (9): no space per control (eight kinds, frames read from the accessibility tree beside a `TextField`), the empty title keeps the
gap, the accessibility label survives (string and `Text` closure), a non-`Text` label publishes none (1025), reach through a container and nearest
writer, the `.button` look and a custom style keep their label (1026), a retained `.equatable()` card re-lays-out when an ancestor flips it, identity of
the options. Updated: `ColorPickerTests` 1.17 (now the gap and the hidden well), `MenuPickerTests` 5.1, `ToggleTests` 1.9 and its switch test
(`ToggleStyleTests`) for the title's extra id level.

**Counts** (2026-11-01, `feat/labels-hidden` after `swift package clean`, `--build-system native --build-tests` and an unfiltered `--no-parallel` run):
first run **4826 tests in 13 suites, 4 issues** (the four updated tests above); after their updates the same tests pass (44 of them re-run filtered);
the final unfiltered count is in the PR. `FR-J no-argument frame: succeeded=true` printed.

## 6. Mutations

Applied to the declaration named (committed first, restored with `git checkout`, `Sources` clean after each), run against `LabelsHiddenTests`.

| Mutation | Reddened |
|---|---|
| `Picker` options style always `Text(title)` | `aHiddenLabelTakesNoSpace` (segmented, radio), `anEmptyTitleStillTakesTheGap` |
| `Picker` menu style always `Text(title)` | `aHiddenLabelTakesNoSpace` (menu), `anEmptyTitleStillTakesTheGap` |
| `Toggle.hidesLabel` returning `false` | `aHiddenLabelTakesNoSpace` (checkbox, switch), `aHiddenNonTextLabelPublishesNoLabel` |
| `Toggle.hidesLabel` without the `.button` guard | `aCustomToggleStyleAndTheButtonLookKeepTheirLabel` |
| `Stepper` always `Text(title)` | `aHiddenLabelTakesNoSpace` (stepper), `anEmptyTitleStillTakesTheGap`, `labelsHiddenReachesAControl…` |
| `ColorPicker` `OptionalGroup(label)` when hidden | `aHiddenLabelTakesNoSpace` (colour) |
| `ProgressView` `shown = label` | `aHiddenLabelTakesNoSpace` (progress) |
| `Picker`/`Stepper`/`Toggle`/`ColorWell`/`ProgressView` dropping their `axNode.label` write | `aHiddenLabelIsStillTheAccessibilityLabel` (segmented, radio, checkbox, switch, stepper, progress arms; the two closure arms) |
| `ColorPicker(_:)` passing nil for an empty title | `anEmptyTitleStillTakesTheGap` (colour), `aColorPickerWithAnEmptyTitleKeepsTheGapAndLabelsHiddenDrawsTheWellAlone` |
| `retainedFingerprint` with `custom: [:]` | `anAncestorTogglingLabelsHiddenRelaysOutARetainedCard` |
| `labelsHidden()` writing `false` | `aHiddenLabelTakesNoSpace` (all eight kinds) and the rest |

Not mutated: the custom-style arm of `aCustomToggleStyleAndTheButtonLookKeepTheirLabel` (no cheap mutant of a generic label); the ColorPicker hidden gap override
turned out to be dead (a flex gap lies between nodes) and was deleted, not pinned. Tests written after the implementation, so "red before" is shown by these mutations.

## 7. Carried

Whether SwiftUI hides a custom `ToggleStyle`'s label and a progress view's current-value label; the accessibility text of a hidden non-`Text` label (1025);
human check group LB (unrun).
