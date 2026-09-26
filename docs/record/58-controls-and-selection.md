# 58 — Controls and selection (plan task 10, part 2)

Branch `feat/controls-and-selection` from `27b2fcc`. Spec
`docs/superpowers/specs/2026-09-26-controls-and-selection-design.md`;
rulings `DD-Q`…`DD-AD` in `docs/superpowers/2026-09-25-data-and-scrolling-decisions.md`;
probe `docs/probes/swiftui-controls-and-selection.swift`. Written by the
lanes; the Record phase completes it.

## 1. Lane 1 — `Button`, `Toggle`, `Picker`; accessibility roles

Commits: `404e82a` (red-first over a no-op skeleton), `38808cc` (the
implementation), and the lane's docs/mutation commit after it.

### 1.1 Red-first

The skeleton gave every public spelling (`Button`, `Toggle`, `Picker`,
`PickerStyle`, `TaggedElement`, `.tag`) over bare `Box`es with no chrome,
handlers or scope, the five roles mapped to `group`, and `selectionHint`
unread. Full unfiltered run: `Test run with 1582 tests in 3 suites failed`
(1556 + 26), 25 tests red, each first issue:

| test | first failing line at the skeleton |
|---|---|
| 1.1 | `button.size.width.value == text.width.value + 24` |
| 1.2 | `button.size.width.value == text.width.value + 2 * padding` |
| 1.3 | `model.count == 1` |
| 1.4 | `window.focusedElement == id` |
| 1.5 | `window.lastFocusRegistry.isFocusable(id)` |
| 1.6 | `window.focusedElement == id` |
| 1.7 | `buttons.count == 1` |
| 1.8 | `tree.nodes.first { $0.value.role == .button }` |
| 1.9 | `indicator.size.width.value == 14 && …` |
| 1.10 | `model.writes == [true]` |
| 1.11 | `off.nodes.values.first { $0.role == .checkBox }` |
| 1.12 | `tree.nodes.first { $0.value.role == .checkBox }` |
| 1.13 | `window.lastScene.rects.first { 14×14 }` |
| 1.14 | `segments.count == 3` |
| 1.15 | `segments.count == 3` |
| 1.16 | `radios.count == 3` |
| 1.17 | `tree.nodes.first { $0.value.role == .radioGroup }` |
| 1.18 | `rows.count == 3` |
| 1.19 | `window.focusedElement == id` |
| 1.21 | `element.accessibilityRole() == appKitRole` |
| 1.22 | `published.nodes.first { $0.value.role == .incrementor }` |
| 1.23 | `node.isSelected` |
| 1.24 | `radios.count == 3` |
| D2 | `control == 1` (the button, toggle and segment arms) |
| click list | `log.names == [name]` (the button arm) |

Green at the skeleton by construction: 1.20 (the skeleton tag is
transparent) and G1.1/G1.2 (spellings only) — each pinned by its mutation
(`DD-AD` item 5). `Backends/SDL`: `theFiveControlRolesMapToAccessKit…` red
at `AccessKitSnapshot.role(.checkBox) == .checkBox`.

### 1.2 What was built

As spec §4/§5/§8 and `DD-R`, `DD-S`, `DD-T`, `DD-U`, `DD-V`, with three
changes recorded in `DD-AD`: the partial fold keeps a disabled control
(1.24 read 0 radio buttons as designed); 1.20 gained a named-content and a
`@State` arm, because M1q′ does not redden the container arm; M1c does not
redden 1.4. `OptionRow` records at site `box` (no new `LoweringSite`). Two
fixture corrections before green, neither an implementation change: 1.14's
root widened to 600 (the ≈ 411-point picker was compressed in 400), and its
row/whole tolerances set to 3 (a width rounded once, times three).
`EnvironmentValues.controlSize`'s doc comments no longer say no built-in
element reads it (`Button`'s chrome does; divergence 76 amended).

### 1.3 Counts and must-not-move

- `swift package clean`, `swift build --build-system native --build-tests`
  (0 `error:`, the one `warning:` SwiftPM's deprecation notice), unfiltered
  `swift test --build-system native --no-parallel`: **`Test run with 1582
  tests in 3 suites passed`**; `FR-J no-argument frame: succeeded=` in the
  log; `CONTROLS GUARD` lines show both guards ran (G1.1 positive true /
  control false; G1.2 menu false / control true). Guards **+2**: `grep -c canTypecheck` summed over `Tests/MetalUITests` reads 94 at `27b2fcc` and 96 now; the design's baseline of 96 was counted another way and is not re-derived here (the Record phase re-takes it).
- Default build system `swift build --build-tests`: 0 `warning:`.
- `MetalUILayout` imports only `MetalUICore`.
- `Backends/SDL` on macOS: `ReplayFixtureTests` 21, `MetalUISDLTests` 23
  (22 + 1). `metalui-portable-ax` (`swift:6.4-noble`, aarch64): 21 and 22
  (no NSAccessibility test there), passed.
- Pixels: `compare.sh <scratch> 27b2fcc 38808cc` — controls 1048576,
  1031003, 454895, 0, 1048576, 0, 544 / 216, 491221, 529, indicator rects 0;
  **all fourteen images `differing=0`, scene identical**. `Expected.swift`
  unedited.
- Real window (lock probe: no `CGSSessionScreenIsLocked` line,
  `displayAsleep main: 0`): `capture.sh <scratch> 27b2fcc 38808cc`, every
  a-vs-b 0; default and preview 27b2fcc → 38808cc **0 and 0**; control
  default vs preview 958986. A first run read `default: 102614` in the
  title-bar strip alone (bbox y 0–55) with the two windows placed at
  different frames (920×588 vs 904×578); the re-run with equal frames read 0.

### 1.4 Mutations

`DD-AD` item 5 is the table (26 rows, every test reddened named).

### 1.5 Verifier fix round

The verifier found eight mutants green at 1582 (V8, V9, V10, V12, V14, V15,
V16, V18): three copies of spec §4's caller-composition rule (Toggle's and
Picker's `onKey`, Toggle's and Button's `onClick` — only Button's `onKey` was
pinned), the option chrome's named id and the nested-tag barrier, Toggle's
Space-only key and `PickerScope.move` from no selection. Six tests were added
(1.6b, 1.10b, 1.10c, 1.19b, 1.20b, 1.20c) and 1.10 and 1.19 each gained an
arm; **1588 tests in 3 suites passed**. Each mutant, re-run in a full
unfiltered run from a copy with `git status --short` empty after, reddens
exactly one test — the rows are `DD-AD` item 5's `V` rows. Two spec sentences
were corrected to the code (`DD-AD` item 6: the picker scope is pushed in
layout only; the group is `OptionRow`). The guard baseline (96 in the design,
94 by `grep -c canTypecheck` summed over `Tests/MetalUITests` at `27b2fcc`,
96 at HEAD) is left to the Record phase.
