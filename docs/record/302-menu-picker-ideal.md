# 302 - A menu `Picker` at its ideal, one line (`BY-N`)

Branch `fix/menu-picker-capsule` from master `990e074b`. Alloy composer pills bug, class M, no divergence label. Ruling `BY-N` in `docs/superpowers/2026-10-31-styles-decisions.md`.

**Symptom.** A menu `Picker` with `.buttonBorderShape(.capsule)` beside a capsule `Menu` in Alloy's composer drew about 32 against the menu's 22, its value top left and the chevron bottom right. In the harness: 98 x 36 against 24, the chevron 9 points lower, at row widths 234 to 440 (the `.automatic` shape drew the same: the shape was never the cause).

**Root causes.** (1) `Picker.requestMenuLayout` laid the title and button as a plain legacy row; a lone labelled picker proposed 200 (ideal 152.2) came out 98 wide, the label row's chevron compressed. (2) The ` ⌄` text wrapped under the value whenever the button was narrower than title plus chevron.

**Fix.** The menu style uses `PickerTitleRow` (the segmented picker's title row, `SR-G`) so a proposal at or above the ideal gives exactly the ideal; the chevron in `PickerMenuLabel` is `lineLimit(1)`. The `Picker.menu` pins at 0 and 50 (67 and 67 x 64) hold. Before and after: lone 160/200/300 frame 98 x 36 (160, 200) to 109 x 24; beside a Menu 98 x 36 to 98 x 24 at 234 (still narrower than ideal) and 109 x 24 from about 400.

**What remains.** Beside a `Menu` in an `HStack` narrower than about 312 the picker is offered half the width (the least flexible child goes first: 106 to 152.2 against the Menu's 24 to 73.5), so it is narrower than its ideal, one line, as SwiftUI's algorithm on its measured flexibilities does. `.fixedSize()` on the picker gives the ideal at every width.

**Tests** (`Tests/MetalUITestingTests/ButtonBorderShapeTests.swift`): `aMenuPickerBesideAMenuIsOneLineAndAsTallAsTheMenu` (capsule and automatic, widths 200 to 1000: equal height, chevron on the value's line) and `aMenuPickerGivenItsIdealWidthIsExactlyItsIdeal`. On the old code the pair records 29 issues; with only the title row 19; with only the line limit 2.
