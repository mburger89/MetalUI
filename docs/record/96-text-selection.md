# 96 — Text selection and caret control, `TextSelection` and the `selection:` bindings

Branch `feat/text-selection` from `0abce86` (C15 §92). **Not a plan task**: item C25 of the
gpui-gap priority list, user request 2026-10-02, requested by MetalCreator (gap CT-b in its
`docs/metalui-gaps.md`, reported 2026-10-10: a field focused from code opens with its caret at the
start; a double click that renames a title wants the whole title selected, a note wants its caret at
the end). Spec `docs/superpowers/specs/2026-10-12-text-selection-design.md`; rulings `SL-A`…`SL-N` in
the new decisions doc `docs/superpowers/2026-10-12-text-selection-decisions.md` (next unused `SL-O`);
probe `docs/probes/swiftui-text-selection.swift` (arms C, P, R, W, F, S; run twice, byte-identical).
Parallel branches: `feat/input-followups` (§93), `feat/backdrop-blur` (§94), `fix/foreach-identity`
(§95). Divergence labels reserved 265–274; **265 and 266 are used**.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human**
(`docs/verification/human-checks.md` group SL). Two lanes: lane 1 the library (`SL-A`…`SL-M`),
lane 2 the harness tests, the guards, the demo and the mutations (`SL-N`).

## §1 What landed

- **API** (SwiftUI's, macOS 15 like `RangeSet`, `SL-L`): `TextSelection` (`indices`, `isInsertion`,
  `init(range:)`, `init(insertionPoint:)`, `init(ranges:)`), `TextField(_:text:selection:)` and
  `TextEditor(_:text:selection:)` over `Binding<TextSelection?>`, plus the controlled spellings
  (`selection:` value and `onSelectionChange:`). No `selectAll()` hook (`SL-A`).
- **Semantics**: the field publishes its selection after each input that moved it (one `defer` in
  `Window`'s `onInput`) and applies, in `prepaint`, a binding value it did not publish; a published
  value is remembered (`seenBinding`) so there is no echo and a backward selection keeps its anchor
  (`SL-B`). Nil is never an instruction (`SL-E`); a write is applied on the next frame, focused or not
  (`SL-D`); stale, out-of-range and multi-range values clamp or act on the first range (`SL-G`); a
  write during IME composition is held back (`SL-H`); a write ends the typing group and touches no
  undo stack (`SL-I`); conversions are counted (`SL-J`). `TextInputTarget`'s two closures are class
  boxes, so `Handlers` stays 488 bytes (`SL-M`).
- **Divergences** 265 (a field focused from code keeps its stored caret) and 266 (the binding is
  written after input only, not at focus or resign).
- **Demo** `METALUI_SELECTION_DEMO=1` (`SL-N`): its own root, not a section of the text-input demo,
  whose three fields two existing suites pin.

## §2 SwiftUI's side (probe, 2026-10-12)

A `TextField` focused from code selects everything, a `TextEditor` puts its caret at the end; a
binding written before the focus loses to the select-all in the field and survives in the editor; a
write is applied on the next run-loop turn; nil is ignored; a stale or out-of-range index clamps
with no trap; `.multiSelection` acts on the first range. Undo is not observable (the instrument
cannot synthesize it): MetalUI's undo claims are its own (`TI-G`). Full table: spec §1.

## §3 Tests (lane 2)

`Tests/MetalUITestingTests/HarnessTextSelectionTests.swift` (4.10–4.14, 4.16–4.18, 4.20–4.24),
`HarnessTextSelectionWorkTests.swift` (4.15, 4.19: `@testable`, they read `TextSelection.conversionCount`),
`Tests/MetalUITests/TextSelectionCompileGuards.swift` (G1–G3), `SelectionDemoTests.swift`; lane 1's
`TextSelectionTests.swift` (4.1–4.9) and `TextSelectionWiringTests.swift`.

**Red first.** Lane 1 built the library before lane 2 wrote the harness tests, so they were **green
on arrival**; their red is the mutation table below, the instrument the practice names. Two defects
the mutations found in lane 2's own code are fixed: a test helper and the demo's readout trapped on a
stale index instead of reading it (M12; commits `25d3c50`, `0d3ef42`).

## §4 Mutations (committed tree, restored from a copy, full unfiltered native suite, `git status --short` empty after each)

Baseline on `880962a`: **3395 tests in 3 suites**, 5 issues, the five `AppKitPresentationTests` sheet
issues of a locked screen (`CI-AF`), nothing else. Each mutation was applied once to the spelling
named; "reddened" lists the tests (the five sheet issues are in every run and omitted).

| Mutation (file) | Reddened |
|---|---|
| M1 `isInsertion` returns `false` (`TextSelection`) | `aTextSelectionHasSwiftUIsThreeShapes`, `aRangeBecomesAnInsertionPointWhenEmptyAndASelectionOtherwise` |
| M2 drop the end clamp in `offsets(of:in:)` | **trap** `String index is out of bounds` in `aStaleSelectionNeitherTrapsNorIsRewritten`; the run truncates with no summary line (red by crash) |
| M3 `ranges.first` to `.last` | `aMultiSelectionActsOnItsFirstRange` |
| M4 `init(offsets:in:)` always `.selection` | **none: an equivalent mutant**, `TextSelection(insertionPoint:)` is the empty `.selection` (4.4's claim is the empty-range equality) |
| M5 invert `binding != seenBinding` (`reconcile`) | 15: 4.5, 4.6, 4.7, 4.8, 4.10, 4.11, 4.12, 4.15, 4.17, 4.20, 4.21, 4.23, the wiring whole-selection and editor tests, the demo test |
| M6 nil selects nothing | `reconcileIgnoresNilAndForgetsTheSeenValue` |
| M7 delete the composition guard | `reconcileIsHeldBackWhileComposing`, `aWriteDuringCompositionIsHeldBackAndTheMarkedTextStays` |
| M8 reset the history in `reconcile` | `reconcileNeverTouchesTheUndoStacks`, `aSelectionWriteDoesNotCorruptUndoAndEndsTheTypingGroup` |
| M9 `publication` returns the selection unconditionally | `publicationIsNilWhenNothingChangedOrWhileComposing`, `aPublishedValueIsNotAppliedBackAndWritesOnce`, `aTextAndASelectionWrittenInOneHandlerApplyAgainstTheNewText`, `aWriteFromACodePathMovesTheCaretOnTheNextFrame` |
| M10 skip `reconcile` in `TextField.prepaint` | 4.10, 4.12, 4.17, 4.20, 4.21, 4.23, the wiring whole-selection test, the demo test |
| M11 skip `reconcile` in `TextEditor.prepaint` | 4.11 and the wiring editor test, the demo test (4.24 stays green: a caret left at 0 is in view) |
| M12 delete the `defer` in `onInput` | 4.10, 4.11, 4.12, 4.13 (all six arms), 4.14, 4.15, 4.16, 4.17, 4.18, 4.22, 4.24, the wiring pair, the demo test |
| M13 Tab skipped on `keyDown` only | **none**: the `keyUp` publishes the traversal's select-all (a flawed spelling, kept in the record) |
| M13b Tab skipped on `keyDown` and `keyUp` | `tabbingIntoAFieldPublishesItsSelectAll` |
| M14 do not store `seenBinding` after publishing | `aPublishedValueIsNotAppliedBackAndWritesOnce` (only its conversion arm: the equal-range guard hides it from every write count, `SL-N`) |
| M15 apply even when the range equals the state's | `aBackwardSelectionKeepsItsDirectionAcrossTheEcho` |
| M16 do not end `openGroup` | `aSelectionWriteDoesNotCorruptUndoAndEndsTheTypingGroup`, `reconcileAppliesAValueTheFieldDidNotPublish`, `reconcileNeverTouchesTheUndoStacks` |
| M17 publish with `target.text` | `twoEditsBetweenFramesPublishAgainstTheEditedText`, both note/editor tests (4.11 and the wiring one), the wiring click test |
| M18 drop the `seenBinding` guard | `aPublishedValueIsNotAppliedBackAndWritesOnce`, `aSteadyFrameWithABindingConvertsNothing`, `reconcileAppliesAValueTheFieldDidNotPublish` |
| M19 apply only when focused | `aBoundSelectionIsKeptWhileTheFieldIsNotFocused` |
| M21 convert against the field's last-edited text | **none** at first (no edit, no `lastText`); 4.23 now types first, then `aTextAndASelectionWrittenInOneHandlerApplyAgainstTheNewText` |
| M22 do not set `revealsCaret` | `aTextEditorPublishesAcrossLinesAndRevealsAWrittenCaret`, `reconcileAppliesAValueTheFieldDidNotPublish` |
| G1 `isInsertion` internal | `textSelectionIsSwiftUIsShape` |
| G2 a public `Binding<TextSelection>` overload | `theSelectionInitialisersAreSwiftUIs` (the separating arm) |
| G3 `conversionCount` public | `theSelectionInternalsAreUnreachableFromAnExternalModule` |

(The 4.1–4.9 rows are lane 1's pure tests, mutated by lane 2 as the spec asked.)

## §5 Verification (head after this record)

- **macOS, `--build-system native`, unfiltered `--no-parallel`**: **3395 tests in 3 suites** (master's
  3363 + 32), the five sheet issues of a locked screen and nothing else, the
  `FR-J no-argument frame: succeeded=true` line present, 0 `error:`, the only `warning:` SwiftPM's
  deprecation notice. Guards: master's 208 + 3 (G1–G3, each mutated red once, §4).
  `swift build --build-tests` (default build system): 0 `warning:`.
- **`swift:6.4-noble`, root package** (`metalui-portable`, volume `metalui-root-build-text-selection`):
  0 `warning:`, 0 `error:`; `MetalUITestingTests` 93 (72 + 21) + 9 + 40 + 21 + 199 + 78 + 22, all passed.
- **Fourteen images**, `compare.sh <scratch> 0abce86 HEAD`: see §6. `Expected.swift` unedited.
- **`Backends/SDL`** untouched; not re-run. `closeout-inventory-check.sh` and
  `closeout-undocumented.sh` print nothing.
- **Screen locked** at lane 2 (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no demo
  capture was taken.

## §6 Fourteen-image comparison

`docs/probes/demo-pixels/compare.sh <scratch> 0abce86 HEAD` (HEAD `0d3ef42`): all fourteen images
`differing=0`, scene identical; the controls read as recorded (light vs dark 1048576, default vs modal
1031003, f0 vs f3 0, chrome pair 0, distinct 544 and 216). `DemoFrameDeterminismTests`' `Expected.swift` is
unedited; Linux/Windows CI confirm on push.

## §7 Deferred (spec §8, unchanged)

Select-all on code focus and caret-at-end defaults (divergence 265); writing the binding at focus and
resign (266); `axis:`; a selected-range accessibility value; multi-caret editing; undo observed against
SwiftUI. Human checks SL1–SL6 are unrun.
