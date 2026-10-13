# 102 — The input-method driver for `MetalUITesting` (`IM-`)

Branch `feat/ime-driver` from `3fce05f` (C25 §96). **Not a plan task**: item C28 of the gpui-gap
priority list (user request 2026-10-02), requested by MetalCreator (gap CT-d, found planning C25's
adoption; not blocking). Spec `docs/superpowers/specs/2026-10-12-ime-driver-design.md`; rulings
`IM-A`…`IM-J` in `docs/superpowers/2026-10-12-ime-driver-decisions.md`; probe
`docs/probes/swiftui-ime-composition.swift`; `SL-O` appended to the text-selection decisions.
Divergence labels reserved 325–334; **325 and 326 are used**.

## §1 What landed

- **Verbs** (`TestWindowInputMethod.swift`): `setMarkedText(_:selectedRange:)`, `commitMarkedText()`
  (AppKit's `unmarkText`), `commitMarkedText(_:)` (`insertText`), `cancelMarkedText()` (SDL's empty
  `TEXT_EDITING`), read-backs `markedText` / `markedSelection`. They send the platforms' own
  `InputEvent`s through `onInput`, so `Window.editedText`, `TextEditing.compose` and `insert` run
  unmodified (`IM-B`); with no text field holding the caret they send nothing and answer `false`
  (`IM-C`).
- **Honest fake**: `HeadlessPlatformWindow.markedText` mirrors `MetalHostView.markedText`, cleared by a
  delivered commit and by `setTextInputArea(nil)` (`IM-C`).
- **Hook**: `Window.testingComposition` (`package`, `TestingHooks.swift`), pinned unreachable by
  plain-import guard 3.4 (`IM-D`).
- **AX**: the field's value is the committed text while composing (`IM-E`, divergence 325). **Selection
  write while composing**: held back, superseded by the commit (`IM-G`, divergence 326).
- **`IM-I`**: measured red on arrival. `Window.focusedElement` gained a `didSet` that drops the
  composition of the text field that lost focus (the only `Window.swift` change). **Migration note**:
  no API change; a field refocused after an abandoned composition no longer shows stale marked text.
- **Docs**: `docs/testing.md` "Recipe: driving an input method" (run by `theInputMethodRecipeRuns`) and
  "Undo after a selection write" (`SL-O`, measured: it matched the code reading).

## §2 Verification

Fifteen tests (5.1–5.15) plus the recipe test and guard 3.4. The first full run found two real
failures: `IM-I` (implemented as above) and test 5.7's last assertion, which was wrong (the last
marked text was `ni hao`, so the commit makes `helloni hao`); the assertion was corrected, the
implementation was right. Mutations are recorded in the lane's final report.

## §3 Deferred

Per spec §9: `replacementRange`, attributed marked text, candidate-window read-back, marked text
containing a line break in a `TextEditor`. Human checks IM-1…IM-3 are owed.
