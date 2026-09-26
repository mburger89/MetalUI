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

## 2. Lane 2 — `Slider`, `Stepper`; value tracking, the wheel rule, `ClickDispatch`

Commits: `1411e31` (red-first over a no-op skeleton), `05d5e7b` (the
implementation), and the lane's docs/mutation commit after it.

### 2.1 Red-first

The skeleton gave `Slider` and `Stepper` their public spellings (a 0×0 leaf
at site `box`; a bare row), `ValueStepping` empty, `ClickDispatch` declared
and never set, `Handlers.valueTrack` declared and unread, and
`LoweringSite.slider`. Full unfiltered run: `Test run with 1612 tests in 3
suites failed` (1588 + 24), 24 tests red, each first issue:

| test | first failing line at the skeleton |
|---|---|
| 2.1 | `slider.size.width.value == 300 && slider.size.height.value == 16` |
| 2.2, 2.3, 2.5, 2.8, 2.9 | `platform.publishedAccessibilityTrees.last` (nothing published) |
| 2.4 | `window.lastScene.rects.first { 20×16 }` |
| 2.6 | `bounds.origin.x.value == 0 && bounds.size.width.value == 300` |
| 2.7 | `window.focusedElement == id` |
| 2.10 | `expected exit status ".failure", but ".exitCode(EXIT_SUCCESS)"` |
| 2.11 | `control.size.width.value == 20 && control.size.height.value == 24` |
| 2.12, 2.14, 2.15, 2.23 | `source.bounds[id]` (no halves) |
| 2.13, 2.16 | `tree.nodes.first { $0.value.role == .incrementor }` |
| 2.17 | `window.focusedElement == stepperID` |
| 2.18 | `try offsetAfterAWheel(at: pt(20, 20)) == 37` (read 0) |
| 2.21 | `log.modifiers == [.command]` |
| 2.22 | `window.focusedElement == target` |
| 2.24 | `offset(window, scroller) == 37` (read 0) |
| D2 | `control == 1` (the slider and stepper-half arms) |
| legacy sites | `arm.entries == arm.expected` (the `Slider` arm) |

Green at the skeleton by construction: 2.19 and 2.20 (they pin clauses the
base already has — every opaque hitbox stopped the wheel), G2.1 (spellings
only) and the owner table (a pure function of the field) — each pinned by
its mutation (`DD-AE`).

### 2.2 What was built

As spec §4–§6 and `DD-W`, `DD-X`, `DD-Y`, `DD-Z` item 9, with the choices
`DD-AE` records: the owner table's `slider` rows (241 → 265), an
accessibility press through the same `Window.runClick` as a click (so it
honours a focus request too), the slider's published value clamped — as
SwiftUI's is, measured by SA5/SA6 (`value 10` for 15, `value 0` for −3; an
earlier wording here and in `DD-AE` item 3 called it unmeasured, corrected
by `DD-AF` item 3), 2.1's
nil-width arm read from `Slider.size(proposedWidth:)`, and two fixture
corrections before green (2.18's arms in fresh windows; 2.24 presses before
the wheel, since the wheel scrolls the field out of its viewport). The
comments citing divergence 16 as live were updated, comment-only (`Box`,
`Passes`, `Handlers`, `Window`, `FocusTests` ×2 — the second no longer calls
the neighbouring test its differential and names
`focusabilityAndKeyHandlingRegisterNoPointerHitbox` as the mechanism pin —
and `DemoContent` ×3).

### 2.3 Counts and must-not-move

- `swift package clean`, `swift build --build-system native --build-tests`
  (0 `error:`, the one `warning:` SwiftPM's deprecation notice), unfiltered
  `swift test --build-system native --no-parallel`: **`Test run with 1612
  tests in 3 suites passed`** (1588 + 24); `FR-J no-argument frame:
  succeeded=` in the log; `SLIDER STEPPER GUARD G2.1 positive:
  succeeded=true`, `control: succeeded=false`. Guards **+1** (G2.1).
- Default build system `swift build --build-tests`: 0 `warning:`.
- `MetalUILayout` imports only `MetalUICore`.
- `Backends/SDL` on macOS: `ReplayFixtureTests` 21, `MetalUISDLTests` 23,
  passed (its three `warning:` lines are the pre-existing SDL link/pkg-config
  notices). `metalui-portable-ax` (`swift:6.4-noble`, aarch64), from a `git
  archive` of the implementation: 21 and 22, passed.
- `everyProductionTreeBuildsOnAOneMegabyteThread` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in the full run.
- Pixels: `compare.sh <scratch> 27b2fcc 05d5e7b` — controls 1048576,
  1031003, 454895, 0, 1048576, 0, 544 / 216, 491221, 529, indicator rects 0;
  **all fourteen images `differing=0`, scene identical**. `Expected.swift`
  unedited.
- Real window (lock probe: no `CGSSessionScreenIsLocked` line,
  `displayAsleep main: 0`): `capture.sh <scratch> 27b2fcc 05d5e7b`, every
  a-vs-b 0; default and preview 27b2fcc → 05d5e7b **0 and 0**; control
  default vs preview 958986.
- State retention, `List` windowing, `Deferred`, animation: untouched by the
  lane's sources (no id path moves; no reserved name). Hit testing moves by
  `DD-Y` and `valueTrack` only; the two `TextField` answers are 2.24's.

### 2.4 Mutations

`DD-AE` is the table (26 rows, every test reddened named; `git status
--short` empty after each); the fix round's 14 rows are `DD-AF` (§2.5).

### 2.5 Verifier fix round

The verifier found eleven mutants green at 1612 (V1, V2, V4b, V5, V6, V7,
V13, V14, V15, and the stepper's `onKey` and declared-value copies by the
same shape): the caller-composition copies of spec §4 in `Slider` and
`Stepper`, the pointer formula's `clamp01` (2.6's step hid it), the scroll
offset in `ValueTrackTarget.minX`, the published clamped value, `DD-Y`'s
"nearest", the press's focus request and `allowsHitTesting(false)` on the
track. Nine tests were added (2.6b, 2.6c, 2.7b, 2.8b, 2.9b, 2.16b, 2.17b,
2.19b, 2.22b) and 2.4 gained its published-value line; **1621 tests in 3
suites passed**. Each mutant (14 rows, `DD-AF`), re-run in a full unfiltered
run from a copy with `git status --short` empty after, reddens exactly one
test. No `Sources/` line moved, so §2.3's pixel, capture, SDL and container
readings stand.

**Changed answers** (spec §10's 2.18 sentence; no test is retired by lane 2):

| old name | new name | arm | at `27b2fcc` | now | ruling |
|---|---|---|---|---|---|
| `aClickTargetInsideAScrollViewSwallowsTheWheel` | `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller` | the wheel over the button | 0 | 37 | `DD-Y` (divergence 16 retired) |
| (same) | (same) | the wheel off the button | 37 | 37, unchanged | — |

### 2.6 Owed

A human look at the pointer rules (a slider press and drag, stepper halves,
the wheel over a button and over a single-line field inside a scroller) —
the probe's click and wheel controls failed, so none is SwiftUI-measured;
lane 3's controls demo is where a human sees them (record §03 at the Record
phase).
