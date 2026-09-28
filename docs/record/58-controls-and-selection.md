# 58 — Controls and selection (plan task 10, part 2)

Branch `feat/controls-and-selection` from `27b2fcc`. Spec
`docs/superpowers/specs/2026-09-26-controls-and-selection-design.md`;
rulings `DD-Q`…`DD-AG` in `docs/superpowers/2026-09-25-data-and-scrolling-decisions.md`;
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

## 3. Lane 3 — `List(selection:)`, `ForEach` over a `Binding`, the controls demo

Commits: `ede7b71` (red-first over a no-op skeleton), `4eb808f` (the
implementation), `f1f9683` (3.8's caller-`onKey` arm), `0bfb915` (3.20b,
`DD-AG` item 1), and the lane's docs/mutation commit after it.

### 3.1 Red-first

The skeleton gave `List(_:selection:rowHeight:row:)` (both), `ForEach` over a
`Binding<C>` and `ForEachBindingSlot`, and `controlsDemoContent()` their
public spellings over today's behaviour (the selection stored and unread; each
slot's binding a constant; the demo a bare `Column`), and added the new tree
to `everyProductionTreeBuildsOnAOneMegabyteThread`. Full unfiltered run at
`ede7b71`: `Test run with 1643 tests in 3 suites failed` (1621 + 22), 20
tests red. Re-taken filtered from `ede7b71`'s sources and tests (the lane-3
files and the stack budget, 24 tests): each first issue —

| test | first failing line at the skeleton |
|---|---|
| 3.1–3.5 | `window.lastHitboxes.first { $0.id == row && $0.handlers.onClick != nil }` (rows are not click targets) |
| 3.6, 3.7, 3.8, 3.12 | `window.focusedElement == list` (the list takes no focus) |
| 3.9 | `singleRows.filter { $0.value.isSelected }.map(\.key) == [2]` |
| 3.10 | `rowNodes(tree)[4]?.isSelected == true` |
| 3.11 | `rows.count == 5` (an unbounded list published no rows) |
| 3.13 | `window.lastHitboxes.contains { $0.id == rowID(list, 1) && $0.handlers.onClick != nil }` |
| 3.14 | `rowRects.count == 1` (no row fill) |
| 3.15 | `added.count == 2` |
| 3.16 | `row3.value.actions.contains(.press)` |
| 3.17 | `tasks.items.map(\.done) == [false, true, false]` |
| 3.18 | `tasks.items[1].done && tasks.writes == 1` |
| 3.19 | `roles.contains(role)` |
| 3.20 | `buttons.count == 5` (line 557; its message is interleaved with SwiftPM's notice in the log), then `buttons.filter(\.isSelected).map { $0.label ?? "" } == ["Row 2"]` |

Green at the skeleton by construction: 3.21 (a skeleton with no data scan
touches only realised rows) and G3.1 (spellings only) — pinned by M3r and
MG3.1′ (`DD-AG`); the two stack-budget tests (the demo's bare tree builds).

### 3.2 What was built

As spec §7 and `DD-Z`, `DD-AA`, `DD-AC` items 1, 2, 4, 6 and 10: the
selection read once per frame and asked one `==`/`contains` per realised
row; a selected row's `Box` takes `.accent` (one `$anim-color` slot per
selected realised row, `2n + 6 + s`) and the internal selection hint (no
`$ax`); a row click selects, toggles (⌘ on Apple, ctrl elsewhere) or selects
the range from the anchor, and focuses the list through
`ClickDispatch.focusRequest`; the focused list's ↑/↓ (⇧ to extend) move the
lead after a caller's own `onKey` declines, the lead and anchor stored in
`ListOrigin` through `withState` from input only (no new reserved name), and
a move enqueues `ListLeadReveal(list:row:)` on the `DD-G` queue scoped to the
list's parent, which only that list matches; the lead's index, its
re-derivation and every range are computed in the handlers. `ForEach($items)`
hands each element its own binding, with `DD-AG` item 2's stale rule.
`controlsDemoContent()` (`Sources/MetalUIDemoContent/ControlsDemo.swift`)
behind `METALUI_CONTROLS_DEMO=1`. Past the design: `DD-AG` item 1 (the
scroller's first frame keeps AB-X rule 1, a clause M3t found unpinned; 3.20b
added) and item 3 (a pre-existing optional-`@State` bug, deferred).

### 3.3 Counts and must-not-move

- `swift package clean`, `swift build --build-system native --build-tests`
  (0 `error:`, the one `warning:` SwiftPM's deprecation notice), unfiltered
  `swift test --build-system native --no-parallel`: **`Test run with 1643
  tests in 3 suites passed`** (1621 + 22; the spec's 1628 did not carry the
  two fix rounds' 15, `DD-AG` item 4); `FR-J no-argument frame: succeeded=`
  in the log; `SELECTION GUARD G3.1 positive: succeeded=true`, `control:
  succeeded=false`. Guards **+1** (G3.1).
- Default build system `swift build --build-tests`: 0 `warning:`, 0 `error:`.
- `MetalUILayout` imports only `MetalUICore`.
- `everyProductionTreeBuildsOnAOneMegabyteThread` (now building
  `controlsDemoContent()` too) and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in the full run.
- Gated `aListsWorkIsTheSameFor100kRowsAsFor500`
  (`METALUI_RUN_100K_LIST_TEST=1`): passed (40.4 s).
- Native depth through a real `Window` (`DD-AG` item 5): `Button` 6,
  `Toggle` 5, `Slider` 3, `Stepper` 10, `Picker` segmented 10, `.radioGroup`
  7, `List(selection:)` in a `ScrollView` 13; the controls demo **15** (at
  most 40, `maxDepth` 72).
- `Backends/SDL` on macOS (`PKG_CONFIG_PATH=.accesskit`):
  `ReplayFixtureTests` 21, `MetalUISDLTests` 23, passed.
  `metalui-portable-ax` (`swift:6.4-noble`, aarch64), from a `git archive`
  of `f1f9683`: `Backends/SDL` 21 and 22 passed; the root package builds with
  0 `error:`/`warning:` and runs `MetalUILayoutTests` + `MetalUICoreTests` +
  `MetalUICrossPlatformTests` **188 + 22 + 10**, unmoved.
- Pixels: `compare.sh <scratch> 27b2fcc f1f9683` — controls 1048576,
  1031003, 454895, 0, 1048576, 0, 544 / 216, 491221, 529, indicator rects 0;
  **all fourteen images `differing=0`, scene identical**. `Expected.swift`
  unedited.
- Real window (lock probe 2026-09-28 08:19 PDT: no `CGSSessionScreenIsLocked`
  line, `displayAsleep main: 0`): `capture.sh <scratch> 27b2fcc f1f9683`,
  every a-vs-b 0; default and preview 27b2fcc → f1f9683 **0 and 0**; control
  default vs preview 958986.
- State retention: no id path of an existing element moves;
  `theSevenRetentionSlotsAreMutuallyDistinct` unmoved; `TB-AH` unmoved for a
  list without `selection:` and moved by exactly `s` colour slots with one
  (3.15). `List` windowing, `Deferred`, animation, `TextField`/`TextEditor`
  untouched; hit testing and focus move only by the rows' click targets and
  the list's focusability.

### 3.4 Mutations

28 rows in `DD-AG`, each a full unfiltered run with `git status --short`
empty after. One finding: M3t (item 1's clause) was green over the whole
suite and is now pinned by 3.20b. MG3.1 (the `Set` initialiser internal)
does not build because the demo calls it from another module; MG3.1′ (the
single-selection initialiser internal) reddens G3.1 alone.

### 3.4b Verifier fix round (`DD-AH`)

The verifier's V3–V6 were each green over the whole 1643-test suite at
`2dcb05e`: the lead and anchor surviving the scroller's origin write (every
⇧ test ran unbounded, where no origin is written), the reveal's
`reveal.list == id` conjunct, and the two multi-selection no-write guards.
Five arms of existing tests (`7c478d6`: 3.1b, 3.3b, 3.7b, 3.7c, 3.12c; no
test added, **1643** unchanged) pin them; re-run on `7c478d6`, V3 reddens
3.3 and 3.7, V4 3.12, V5 3.1, V6 3.7 — each a full unfiltered run,
`git status --short` empty after. `DD-AC` item 2's "pinned by" sentence
carries an erratum. The optional-`@State` finding (`DD-AG` item 3) stays
unfixed in the lane; `DD-AH` item 4 makes its disposition a condition of
ticking task 10.

### 3.5 Owed

- The human look at the controls demo (`METALUI_CONTROLS_DEMO=1 swift run
  MetalUIDemo`): every control by pointer and keys, the list's ⌘/⇧ clicks and
  arrows, the reveal, the wheel over a row — the pointer rules no SwiftUI
  probe measured (§2.6).
- `DD-AG` item 3's optional-`@State` bug: a ruling and a test, owner chosen
  by the Record phase.

## 4. This phase's independent close

Re-took, at `87e3f9c` (HEAD), everything the lanes measured, from a clean
tree (`swift package clean` first):

- **Build**: `swift build --build-system native --build-tests` — 0 `error:`,
  the one `warning:` SwiftPM's deprecation notice.
- **Suite**: unfiltered `swift test --build-system native --no-parallel` →
  **`Test run with 1643 tests in 3 suites passed`** (95.2s). The log carries
  `FR-J no-argument frame: succeeded=` and the three new guard lines
  (`CONTROLS GUARD`, `SLIDER STEPPER GUARD`, `SELECTION GUARD`);
  `everyProductionTreeBuildsOnAOneMegabyteThread` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` both passed in this run.
- **Guards, and lane 1's issue 5 resolved**: `grep -c canTypecheck` summed
  over `Tests/MetalUITests` alone reads 94 at `27b2fcc` and 98 now — the
  reading lane 1's verdict flagged as disagreeing with the design's "96". It
  disagrees because it is the wrong sum: this file's own "Guards" bullet
  defines the count across **two** targets (`Tests/MetalUITests` and
  `Tests/MetalUICoreTests/UnitSafetyTests.swift`), discounting one comment
  hit in the latter. Summed the canonical way: **96** at `27b2fcc` (97 raw
  across the 23 named files, minus `UnitSafetyTests`' one comment) and
  **100** now (101 raw across the 26 named files — the three new guard files
  add 4 — minus the same one comment). The design's own arithmetic, "96 + 4 =
  100" (spec line 495), was correct throughout; lane 1's "94, not 96" is
  retracted, not the design's baseline. New files:
  `ControlsCompileGuards.swift` (2, whole-file), `SliderStepperCompileGuards.swift`
  (1, whole-file), `SelectionCompileGuards.swift` (1, whole-file) — all four
  `typecheckFile`, none `typecheck`.
- **Goldens**: 0 (unmoved — stage 7a; `find Tests/MetalUILayoutTests -name
  "*.json" | wc -l` reads 0).
- **`MetalUILayout` imports only `MetalUICore`**: `grep -h '^import'
  Sources/MetalUILayout/*.swift | sort -u` reads exactly `import MetalUICore`.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 27b2fcc HEAD` —
  the five non-zero controls read as recorded by every lane (default vs
  modal light 1031003, default vs animation light 454895, prod default vs
  modal 491221, distinct default-light-f0 544, distinct prod-default-light
  529; f0-vs-f3, chrome-legacy-vs-proposal and the indicator-rects control all
  0 as they must) — **all fourteen images `differing=0`, scene identical**.
  No source this task touched is on the ordinary demo's tree (the controls
  demo is a separate, gated tree, `METALUI_CONTROLS_DEMO=1`).
  `Tests/MetalUICrossPlatformTests/Expected.swift` unedited.
- **Real-window capture**: the lock probe (`docs/probes/appkit-screen-lock-state.swift`)
  read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at this
  phase's own close — locked, as at every lane's own check — so
  `docs/probes/window-capture/capture.sh` was not run; the offscreen
  fourteen-image comparison above stands in for the ordinary demo, and says
  nothing about the controls demo, which it never renders (record §03 below).
- **`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit swift test`, macOS,
  fetched fresh with `scripts/fetch-accesskit.py`): `ReplayFixtureTests` 21,
  `MetalUISDLTests` 23 (22 + 1, `theFiveControlRolesMapToAccessKitWithToggledAndNumericValues`)
  — both passed, matching every lane's own reading.
- **`swift:6.4-noble` container** (root package, source mounted read-only):
  `swift build` — 0 `error:`, 0 `warning:`; unfiltered
  `MetalUILayoutTests`/`MetalUICoreTests`/`MetalUICrossPlatformTests` —
  **188 + 22 + 10**, unmoved, all passed.
- **`metalui-portable-ax` container** (Linux aarch64, `Backends/SDL`):
  `swift build` — 0 `error:`, 0 `warning:`; `ReplayFixtureTests` 21,
  `MetalUISDLTests` 22 (no NSAccessibility test there) — both passed.

Nothing above moved from the lanes' own readings, except the guard-count
correction, which corrects a reading, not a fact: the true total (100) was
never in question, only which grep produced it.

## 5. `DD-AG` item 3 disposed of: divergence 85, ruling `DD-AI`

Ruling `DD-AI` (appended to the decisions doc) makes the choice `DD-AH` item
4 deferred: the optional-`@State` bug (`StateTable.peek`/`State.wrappedValue`
casts an absent entry to an optional `Value` as a present `.some(nil)` before
the `?? initialValue` fallback runs, so `@State var picked: Int? = 2` reads
`nil` until its first write) is **not fixed on this branch**. It is added to
record §04 as **divergence 85**, kept, owner **plan task 15** (closeout): a
fix is one line in `StateTable.peek` or `State.wrappedValue` (distinguish an
absent entry from a present `nil`), but it changes the observable behaviour
of every optional `@State` with a non-`nil` default across the whole
framework, which wants its own ruling, a red-first test and a migration
note — a scope a docs-phase edit should not absorb un-reviewed. This
disposition, not a source fix, is what `DD-AH` item 4 required before task
10 could be ticked; it is met here. The controls demo keeps its `Set`
workaround (record §58 §3.2).

## 6. Divergences (record §04): 16 retires; 76 amended again; 80–85 added

**16 retires** (`DD-Y`): a click target inside a `ScrollView` no longer
swallows the wheel over itself — it passes to the nearest ancestor hitbox on
the same layer that registered a scroll region; an overlay sibling and a
`Deferred`-hoisted scrim still stop it. The label joins the never-reused
list. **76 is amended again, not retired** (`DD-R` item 4): `Button`'s
automatic chrome now reads `controlSize`; every other consumer (`Text`'s
default font, every other control's metrics) is still nobody's. **Added**:
80 (control keys work whether or not SwiftUI's Full Keyboard Access setting
would allow it there — unmeasured, `DD-T` item 3), 81 (the automatic
`Picker` is segmented, not SwiftUI's pop-up menu, `DD-V` item 4), 82 (the
accessibility partial fold's accessible name where SwiftUI publishes a
sibling static text; also a missing `AXValueIndicator` child and two arrow
buttons AppKit reads DISABLED while enabled, `DD-U` items 3 and 9), 83 (a
selection client presses a row; `AXSelected`/`AXSelectedRows` write nothing,
`DD-Z` item 8), 84 (a `List` stays virtualized, uniform-row and data-driven
rather than SwiftUI's greedy self-scrolling one, `DD-AB` item 3), 85 (the
optional-`@State` bug above, `DD-AI`). Live count **56 → 61**: one retires,
six are added.

## 7. Declared but inert (record §05): `controlSize`'s row narrowed

`Button`'s chrome reading `controlSize` (`DD-R` item 4) narrows that row from
"reaches no built-in element" to "reaches `Button`'s chrome only" — the
inline example list is left as is (the same pattern stage 10 used for
`margin: .auto`'s narrowing), and the dated section says so. No row is added
or deleted: `controlActiveState` and `displayScale` are read by nothing this
task built.

## 8. Human verification (record §03): the controls demo and its pointer/AX looks

The lock probe read locked at every lane's own check and again at this
phase's close (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`), so
`capture.sh` never ran, and neither did SwiftUI's own click/wheel controls in
either probe session (CK0, WH0 failed both times, as part 1's W0 did). The
controls demo is a new look, not a reopening of the five still-owed rows
from earlier tasks (it builds a tree the ordinary demo never does, so the
fourteen-image offscreen comparison says nothing about it). **Owed**: the
controls demo on screen and by VoiceOver, and specifically the pointer rules
(§2.6, §3.5 above) and the two accessibility shapes divergence 82 names.

## 9. Task 10, clause by clause: every clause closed

Per `DD-AB` item 1, the box is ticked only if every clause of the plan's task
10 text is closed, with the rest re-owned by name:

| clause | disposition |
|---|---|
| `ForEach`/identified-data semantics | built, part 1 (`DD-B`) |
| bindings | built, part 1 (`DD-D`) and this part (`ForEach(_: Binding<C>)`, `DD-AA`) |
| common controls | built, this part (`DD-R`, `DD-S`, `DD-V`, `DD-W`, `DD-X`) |
| selection | built, this part (`DD-Z`) |
| rework `List`/`ScrollView` limitations that blank or destroy state | closed: divergence 14 retired (part 1, `DD-F`), divergence 13 amended kept (part 1), divergence 16 retired (this part, `DD-Y`) |
| retain virtualization as an internal choice | kept by ruling (divergence 84, `DD-AB` item 3) |
| scroll position | built, part 1 (`DD-G`) |
| indicators | built, part 1 (`DD-H`) |
| programmatic scrolling | built, part 1 (`scrollTo(_:anchor:)`, `DD-G`) |
| the task-9 note: the deprecated `Binding` alias deleted with a SwiftUI `Binding` | done, part 1 (`DD-D` item 6) |
| the task-9 note: wheel scrolling under `.disabled` (`EV-Q`'s item) | ruled, part 1 (`DD-I` item 3): MetalUI's disabled `ScrollView` keeps scrolling, pinned; SwiftUI unmeasured, a human look owed (record §03). Part 2's `DD-Y` does not move it — a disabled click target registers no hitbox, so the wheel reaches the scroller directly, as before (these two rows added by the branch checker, §11) |

Every item `DD-J`/`DD-Q` re-owned away from task 10 — `List`'s own greedy
answer and non-uniform rows (divergence 84, owner none), divergence 32 and
accessibility scrolling to unrealised rows (plan task 12), two-axis
scrolling and divergence 54 (kept, owner none), `scrollPosition(id:)` (not
built, additive), styles and gesture composition (plan task 12) — is **not**
a clause of the task's own text (`DD-AB` items 3–8), so none of it blocks the
tick. **Task 10 is ticked.**

## 10. Status

Spec `docs/superpowers/specs/2026-09-26-controls-and-selection-design.md`:
**DELIVERED**. Decisions doc: **DESIGNED, CRITICISED, REVISED, AND
DELIVERED**; next unused ruling id **`DD-AJ`**. Plan task 10's checkbox is
**ticked** — both parts close every clause of the task's text (§9 above).


## 11. The adversarial branch check (`27b2fcc..c9a741e`)

Taken 2026-09-28 in this worktree at `c9a741e`, independently of every
reading above.

- **Suite**: `swift package clean`, then `swift build --build-system native
  --build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation
  notice) and unfiltered `swift test --build-system native --no-parallel` →
  **`Test run with 1643 tests in 3 suites passed after 96.288 seconds`**; the
  log carries `FR-J no-argument frame: succeeded=` and the four new guards'
  positive and control lines (G1.1, G1.2, G2.1, G3.1, each control
  disagreeing with its positive). `swift build --build-tests` under the
  default build system: 0 `error:`, 0 `warning:`. Goldens 0; `grep -c
  canTypecheck` over all of `Tests/` reads 102 raw (the 101 of §4 plus
  `Typecheck.swift`'s declaration), so 100 guards the canonical way;
  `MetalUILayout` imports only `MetalUICore`; `cmp CLAUDE.md AGENTS.md`
  clean. Green in that run, by name: `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `focusabilityAndKeyHandlingRegisterNoPointerHitbox`,
  `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`,
  `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS`,
  `everyProductionTreeBuildsOnAOneMegabyteThread` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.
- **`List` virtualization**: `METALUI_RUN_100K_LIST_TEST=1 swift test
  --build-system native --filter aListsWorkIsTheSameFor100kRowsAsFor500` —
  passed (28.8 s).
- **Pixels**: `compare.sh <scratch> 27b2fcc HEAD` — every control as recorded
  in §4, **all fourteen `differing=0`, scene identical**.
- **Real window**: the lock probe read `CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1` (10:25 PDT) — `capture.sh` not run.
- **`Backends/SDL`** (macOS, AccessKit fetched fresh into
  `Backends/SDL/.accesskit`): 21 + 23 passed. **`swift:6.4-noble`** (root
  package from `git archive HEAD`): `swift build --build-tests` 0
  `error:`/`warning:`; `MetalUILayoutTests`/`MetalUICoreTests`/
  `MetalUICrossPlatformTests` **188 + 22 + 10** passed (the last includes the
  closing check).
- **Every test name (107) and ruling id cited in the branch's doc diff
  resolves** (`DD-AJ` only as "next unused"; `DD-3` only as the typo
  example).

**Two mutations of this check's own design**, each committed state restored
from a copy, full unfiltered suite, `git status --short` clean after:

| Mutation | Change (spelling applied) | Reddens |
|---|---|---|
| MX1 | `declaration.selectionHint = false` deleted from `Frame.registerHandlers` (the hint no longer stripped before the declaration test, so a selected row declares a node) | `aSelectionHintPublishesSelectedAndWritesNoAXSlot`, `aSelectableListAddsOneColourSlotPerSelectedRowAndNoAXSlot` (5 issues) |
| MX2 | `dispatchValueTrack`'s press resolves `lastHitboxes.lastIndex(where: valueTrack != nil && bounds.contains(point))` instead of `topmostOpaqueHitbox(in:at:)` — a second, unranked copy of hit resolution | **none** (1643 passed) |

**MX2 is a finding, not a broken instrument**: a scratch test (a `Slider`
under an opaque `onClick` `Box` sibling in a `Stack`, covering it) read value
**5** under the mutant and **0** on the committed source, so the mutant
differs and no retained test sees it. The committed code is correct —
`dispatchValueTrack` does use the one ranking — but that it does is
unpinned: a slider covered by an opaque sibling, or by a `Deferred` scrim,
taking no press is asserted by nothing. **Non-blocking**; owed as one test
(the scratch test's shape) by whoever next touches `dispatchValueTrack`.

**2026-09-28, MX2 pinned** (`test/covered-slider` from `3aa44e5`): new test
`aPressOnASliderCoveredByAnOpaqueClickTargetRunsTheClickAndWritesNothing`
(`SliderTests.swift`, 2.6c — a `Slider` under an opaque `onClick` `Box`
sibling in a `Stack`, pressed at a point `try #require`d inside both) is
green on the committed source. MX2 re-applied with the spelling in the table
above, full unfiltered `swift test --build-system native --no-parallel`:
**reddens `aPressOnASliderCoveredByAnOpaqueClickTargetRunsTheClickAndWritesNothing`**
(1 issue, `model.writes` read `[5.0]`; its `cover.count == 1` arm held —
the click still reaches the box on mouse-up, so only the value arm sees
MX2); `Test run with 1644 tests in 3 suites failed … with 1 issue`. Restored
from a copy, `git status --short` clean of `Sources/`. On the restored
source: `Test run with 1644 tests in 3 suites passed`, FR-J line present,
0 `error:`; `swift build --build-tests` 0 `warning:`.

**Doc defects found and fixed in this commit**:

1. Records §03, §04 and §05 had **no** 2026-09-28 task-10-part-2 section,
   though `CLAUDE.md`, §6–§8 above and `c9a741e`'s message all cite them —
   written now from §6–§8, the rulings and the tests they name (§04 moves
   56 → 61 live, 16 joining the never-reused list).
2. `CLAUDE.md` said "**No test retired, none renamed**" for this task; one
   retained test was renamed with its answer changed
   (`aClickTargetInsideAScrollViewSwallowsTheWheel` →
   `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`, §2.5's own
   row) — corrected.
3. `CLAUDE.md`'s "`Handlers` has nine members" (the Controls paragraph
   beside it says `valueTrack` is the tenth) and "Hit testing"'s "`onClick`
   alone makes an opaque pointer target" (stale since `TI-B` and now
   `valueTrack`) — corrected, and the `DD-Y` wheel rule added to "Hit
   testing".
4. `DD-W` item 8 says a `Slider`'s thumb snapping was "added to CLAUDE.md's
   snaps list by the Record phase"; it was not — added.
5. §9's clause table omitted the two items the plan's task-9 note assigns to
   task 10 (the alias deletion, wheel scrolling under `.disabled`) — rows
   added; both were disposed of by part 1, so the tick stands.

**Verdict**: task 10's box stays ticked — the plan text's four sentences and
its task-9 note are each closed by part 1 or part 2 (§9), every re-owned
item named. No code defect found; **merge**.
