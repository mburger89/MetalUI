# 102 — The input-method driver for `MetalUITesting` (`IM-`, C28)

Branch `feat/ime-driver` from `3fce05f` (C25 §96), merged with master `ff8a1ea` (§100 continuing press
cancel; no conflict, number 102 still free; §98, §99 and §101 are parallel branches). **Not a plan task**:
item C28 of the gpui-gap priority list (user request 2026-10-02), requested by MetalCreator
(developer-0a, 2026-10-12, gap CT-d, found planning C25's adoption; not blocking). Spec
`docs/superpowers/specs/2026-10-12-ime-driver-design.md`; rulings `IM-A`…`IM-J` in
`docs/superpowers/2026-10-12-ime-driver-decisions.md` (next unused `IM-K`); probe
`docs/probes/swiftui-ime-composition.swift`; `SL-O` appended to the text-selection decisions (next
`SL-P`). Divergence labels reserved 325–334; **325 and 326 are used**.

**Status: LANDED.** One lane, a design session and a critic (`IM-J`) before it, red first, verified `ok`.

## §1 What landed

- **Verbs** (`Sources/MetalUITesting/TestWindowInputMethod.swift`): `setMarkedText(_:selectedRange:)`
  (`NSTextInputClient.setMarkedText`, SDL's non-empty `TEXT_EDITING`), `commitMarkedText()` (AppKit's
  `unmarkText`, which **is** a commit), `commitMarkedText(_:)` (`insertText`), `cancelMarkedText()` (SDL's
  empty `TEXT_EDITING`), read-backs `markedText` / `markedSelection`. Each sends the platforms' own
  `InputEvent` through `onInput`, so `Window.editedText`, `TextEditing.compose` and `insert` run unmodified
  (`IM-B`, never a test-only shortcut); with no text field holding the caret they send nothing and answer
  `false` (`IM-C`). Seven public declarations, class `M`.
- **Honest fake**: `HeadlessPlatformWindow.markedText` mirrors `MetalHostView.markedText`, cleared by a
  delivered commit and by `setTextInputArea(nil)` (`IM-C`, `HT-X` 1).
- **Hook**: `Window.testingComposition` (`package`, `TestingHooks.swift`), pinned unreachable by plain-import
  guard 3.4 (`IM-D`).
- **Accessibility**: the field's AX value is the committed text while composing (`IM-E`, divergence 325;
  AppKit's field editor includes the marked text, the SwiftUI element's own value is unprobed). **Selection
  write while composing** is held back and superseded by the commit's publish (`IM-G`, `SL-H`, divergence
  326; SwiftUI publishes during composition and applies a write at once).
- **`IM-I`**: measured **red on arrival**. `Window.focusedElement` gained a `didSet` that drops the
  composition of the text field that lost focus (the only `Window.swift` change). **Migration note**: no API
  change; a field refocused after an abandoned composition no longer shows stale marked text
  (`docs/migration.md`, a behaviour-change row).
- **Docs**: `docs/testing.md` "Recipe: driving an input method" (run by `theInputMethodRecipeRuns`) and
  "Undo after a selection write" (`SL-O`, measured: it matched the code reading — a write ends the open typing
  group, ⌘Z removes only the text typed after it and restores the written selection; a one-grapheme commit
  continues a group, a longer one is its own step).

## §2 Tests and guards (per file)

- `Tests/MetalUITestingTests/HarnessInputMethodTests.swift`: `aMarkedTextIsInTheFieldNotInTheBinding`,
  `commitMarkedTextCommitsTheMarkedTextOnce`, `commitMarkedTextWithACandidateReplacesTheMarkedText`,
  `cancelMarkedTextRestoresTheFieldAndWritesNothing`, `aSelectionRangeInTheMarkedTextIsKept`,
  `aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit` (SL-H end to end),
  `theFieldsAccessibilityValueIsTheCommittedTextWhileComposing`, `typingWhileComposingBelongsToTheInputMethod`,
  `anInputMethodCannotBeDrivenWithoutAFocusedField`, `theHeadlessPlatformDropsMarkedTextWhenTheCaretGoes`,
  `aCompositionDoesNotSurviveItsFieldLosingFocus` (`IM-I`),
  `aCompositionIntoATextFieldsBindingReachesTheModelsDraft`, `aTextEditorComposesLikeAField`,
  `theUndoContractAfterASelectionWrite`, `aCommitOfOneGraphemeContinuesTheTypingGroupAndALongerOneDoesNot`,
  and `theInputMethodRecipeRuns` (the recipe of `docs/testing.md`, executed). 16 tests.
- `Tests/MetalUITests/TestHarnessCompileGuards.swift`: guard **3.4** `theCompositionHookIsUnreachableFromAPlainImport`
  (control: `TestWindow.markedText` is public). +1 guard.

## §3 Probe and red runs

`docs/probes/swiftui-ime-composition.swift` (arms C0 control, A, Ae, B, U, I, D, W, WU, Z; readings in its
header, macOS 27.0.1, screen unlocked, one arm per process). The machine was loaded: two arms timed out in the
confirming pass and arm Z hangs in its undo step (a probe defect, not a finding), recorded in the header. The
critic's confound (`IM-J` item 3) is stated there too.

Red first (`9274b423`): the tests failed to compile against the absent verbs (`setMarkedText`,
`commitMarkedText`, `cancelMarkedText`, `markedText`). The first full run found two real failures: `IM-I`
(`aCompositionDoesNotSurviveItsFieldLosingFocus`, fixed as above) and the AX test's last assertion, which was wrong (the last marked text was `ni hao`, so the
commit makes `helloni hao`); the assertion was corrected, the implementation was right.

## §4 Mutations (unfiltered suite, restored from a copy, `git status --short` clean after each)

| mutation | reddened |
|---|---|
| `Window.focusedElement` `didSet` (`IM-I`): the composition-clear statement replaced with `_ = old` | `aCompositionDoesNotSurviveItsFieldLosingFocus` |
| TextField's AX node `value` built from `geometry.display` (marked text spliced) instead of the committed `text` | `theFieldsAccessibilityValueIsTheCommittedTextWhileComposing` (its lines 144 and 146), `theInputMethodRecipeRuns` (line 374) |
| (branch checker, 3530-test unfiltered runs, restored from a copy) `TextEditing.reconcile`: the `composition.text.isEmpty` guard removed | `aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit` (3 issues), `aWriteDuringCompositionIsHeldBackAndTheMarkedTextStays` (2), `reconcileIsHeldBackWhileComposing` (4); 9 issues |
| (branch checker) `TextEditing.publication`: the `composition.text.isEmpty` guard removed | only `publicationIsNilWhenNothingChangedOrWhileComposing`; 5.6 does **not** redden (the held write leaves the selection equal to the reported one) — its comment was corrected |

The lane's two were expected. The lane's own earlier mutations (the `display` splice that replaced the critic's non-mutant
test, `IM-J` item 1) are in the lane report.

## §5 Verification

`swift package clean`, native build, unfiltered `swift test --build-system native --no-parallel` on the merged
tree: see the counts bullet of `CLAUDE.md` (3530 tests, `FR-J no-argument frame: succeeded=true`, 0 `error:`,
the only `warning:` SwiftPM's deprecation notice). Census 3446 → 3453 (+7); the inventory map's
`test-harness-inspection` row gained `TestWindowInputMethod`; `closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing. The lane ran on `7e3fedc4` (3521 tests, then 3504 + 17). Not re-run
by the lane and not claimed: the default-build-system warnings, the Linux image, the fourteen-image pixel
comparison (no renderer, layout or paint source changed; the only `Sources/MetalUI` edits are
`Window.focusedElement`'s `didSet` and the `package` hook) — to be taken at the merge.

## §6 Hazards

- A new `PlatformWindow` requirement would owe `HeadlessPlatformWindow` an honest answer; none was added.
- `Window.focusedElement`'s `didSet` runs on every focus change: keep it to one dictionary lookup (`IM-I`).
- Text-input rules unmoved: caret positions only from `TextSystem.caretOffsets`, undo valid only for the text
  its last edit produced (`TI-`).

## §7 Deferred (owners)

`replacementRange`, attributed marked text, candidate-window read-back, marked text containing a line break in a
`TextEditor` (spec §9; owner: the first client that needs one). Human checks **IM1…IM3** (`human-checks.md`
group IM, record 03) are owed; an agent cannot run a real input method or VoiceOver.
