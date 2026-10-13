# Input-method driver (`MetalUITesting`) — decisions

Rulings for item C28 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**),
requested by MetalCreator (developer-0a, 2026-10-12, gap CT-d, found planning C25's adoption; not
blocking). Prefix `IM-`. Spec: [`specs/2026-10-12-ime-driver-design.md`](specs/2026-10-12-ime-driver-design.md).
Record: `../record/102-ime-driver.md`. Branch `feat/ime-driver` from `3fce05f`. Divergence labels
reserved for this branch: 325–334 (planned: 325, 326).

SwiftUI's side: `docs/probes/swiftui-ime-composition.swift` (recorded in its header; macOS 27.0.1).
It drives a SwiftUI `TextField`/`TextEditor`'s field editor through `NSTextInputClient`. gpui's
side is recalled and rests no ruling (`EntityInputHandler::replace_and_mark_text_in_range` /
`unmark_text`: a handler the platform calls, no test driver in the crate).

**Next unused id: `IM-J`.**

## IM-A — Three verbs beside `typeText`, named for the platform calls they stand for

`setMarkedText(_:selectedRange:) -> Bool`, `commitMarkedText(_:) -> Bool` and
`cancelMarkedText() -> Bool` on `TestWindow` (`@discardableResult`), in a file of their own
(`TestWindowInputMethod.swift`), each followed by one frame (`HT-E` item 2). `setMarkedText` is
`NSTextInputClient.setMarkedText` and SDL's non-empty `TEXT_EDITING`; `commitMarkedText()` is
`unmarkText` (the marked text as it stands becomes the committed text), `commitMarkedText(_ text:)`
is `insertText` (the input method's chosen candidate replaces the marked text); `cancelMarkedText()`
is SDL's empty `TEXT_EDITING`. There is no separate `unmarkText()`: on AppKit `unmarkText` **is** a
commit (`MetalHostView.unmarkText` sends `.textInput(markedText)`), so a second spelling of it would
be a duplicate that reads as a cancel. **Why not SwiftUI's names**: SwiftUI has no in-process
input-method API; class `M` like the rest of the harness (`HT-`). `selectedRange` is a
`Range<Int>?` of **Character** offsets into the marked text (the unit of `TextComposition`, `TI-A`),
`nil` meaning a caret at its end (what AppKit input methods send for plain typing). **Cost if
wrong**: renaming a verb is a source-compatible deprecation away; the platform mapping is the
contract.

## IM-B — The driver sends the platforms' own events through `onInput`; no shortcut

Every verb is one or two `InputEvent`s delivered through `platformWindow.onInput` — the closure
`Window` installed, as every other verb (`HT-F`) — the exact events the two real platforms send:
`setMarkedText` → `.textComposition(TextComposition(text:selection:))` (AppKit
`setMarkedText`, SDL `TEXT_EDITING`); `commitMarkedText()` → `.textInput(<marked text>)` (AppKit
`unmarkText`); `commitMarkedText(_ text:)` → `.textInput(text)` (AppKit `insertText`);
`cancelMarkedText()` → `.textComposition(.none)` (SDL). `Window.editedText`, `TextEditing.compose`
and `TextEditing.insert` run unmodified; nothing in `MetalUI` is added to *reach* them. **Why the
mapping, not "one event"**: the three platform calls are three different events; collapsing them
would test a path no platform takes. **Cost if wrong**: a platform event we did not model (AppKit's
`replacementRange`, which `MetalHostView` ignores today) is not drivable; deferred (spec §9).

## IM-C — The verbs are honest about when a platform delivers them: only while text input is active

AppKit calls the client only while `textInputCaret != nil` (`MetalHostView.keyDown`, and
the host view is a live client only then, `TI-A`) and SDL drops `TEXT_EDITING` and `TEXT_INPUT`
unless `textInputCaret != nil` (`SDLPlatform`). The harness's `isTextInputActive` (`typeText`'s
gate) is the same fact; a verb called with no text field holding the caret **sends nothing and
answers `false`** — a test forgetting to focus fails at its `#expect`, not in a silently
inert composition. `HeadlessPlatformWindow` mirrors `MetalHostView.markedText`
(`public private(set) var markedText`): set by `setMarkedText`, cleared by a commit or cancel, and
**cleared silently when `setTextInputArea(nil)` arrives while non-empty** — AppKit's
`textInputCaret.didSet` discards the input context's marked text with **no event to `Window`**
(`HT-X` 1: a new platform fact owes the headless platform an honest answer in the same change).
`commitMarkedText()` with no marked text is a no-op answering `false` (AppKit's `unmarkText`
`guard`). **Cost if wrong**: a test of a non-field target cannot drive an input method — which is
what no platform allows either.

## IM-D — Read-backs are the Window's truth, through one `package` hook

`TestWindow.markedText: String` (empty when none) and `markedSelection: Range<Int>?` read the
**focused field's `TextEditState.composition`** through one new `package` member of `Window`
(`testingComposition`, in `TestingHooks.swift`, guard arm 3.4: a plain import cannot spell it) —
**not** the headless platform's mirror, which only the commit needs: a test asserts what
`Window` believes, and a bypass (an event that reaches the platform mirror but not the state) would
otherwise read green. `markedText` is `""` when nothing is focused or the focused element is not
a text target. **Cost if wrong**: a second source of truth drifting from the first is the failure the
choice avoids; the mirror is private to the verbs.

## IM-E — The accessibility value during composition is the committed text (divergence 325)

A focused `TextField`'s published AX node (`registerHandlers` / `TextField.swift`: `value: text`)
keeps **the committed text**; marked text is not in `TestElement.value` or the AX tree, and
`focusedElement?.value` pins that. **Evidence**: SwiftUI's text binding is unwritten while marked
(probe A, Ae, B, W) and MetalUI's AX value is its binding's text, so the two agree on the model.
AppKit's *field editor* answers differently — its accessibility value includes the marked text
(probe A `editorAX='ni'`, Ae `'helloni'`); the SwiftUI element's own AX value cannot be read by
the probe's instrument (`ax=[]`), so no claim is made about it. **Why committed text**:
(1) an AX value that changed on every composition update would make a screen reader re-announce
the field at each keystroke of the candidate; (2) the system input method announces its own
candidates and marked text, and the field repeating them doubles the speech; (3) the node mirrors the
binding, which a client test asserts. **Cost if wrong**: a VoiceOver user composing hears the
candidates from the IM but the field does not state the marked text itself; the fix is one
spliced string in the node, additive. Divergence 325; human check IM-1 (VoiceOver while composing —
an agent cannot, `IX-AE`). Pinned by `theFieldsAccessibilityValueIsTheCommittedTextWhileComposing`.

## IM-F — Cancel leaves the text and the selection untouched; a composition over a selection replaces it only at its commit

`TextEditing.compose` keeps `selection` and the display splices marked text over it
(`TextField.swift` `display`); `cancel` drops the composition, so the replaced selection is
**restored in the display and in the state**; `commit` is `TextEditing.insert`, which replaces
the selection. **Evidence**: MetalUI's existing rule (`TI-A`, `compose`'s doc comment); the SwiftUI
probe cannot confirm either half (D cannot cancel; D2's editor shows `''` while the text binding
still reads `hello`, an instrument artefact — no claim). The test "cancel restores" pins this with
a selected word. **Cost if wrong**: if AppKit's field in fact deletes the selection at the first
marked text and cancel leaves it deleted, MetalUI differs (a divergence, one label of the range);
the choice that never loses text was made on purpose.

## IM-G — Selection write while composing: SL-H end to end, and SwiftUI differs (divergence 326)

`SL-H` had no SwiftUI evidence. It has now (probe A, B, W, WU): SwiftUI's `TextField` **publishes the
selection binding during composition, in the field editor's coordinates** (`ins@2` for `ni`,
then `OUT-OF-RANGE` for `ni hao`), and **applies a selection written from code at once** (W:
`sel@0..1`, the marked text stays); the commit then overwrites the write (WU: `ins@2`). MetalUI
**holds the write back and publishes nothing** until the commit, whose publish supersedes it
(`SL-H`, `reconcile`/`publication`). The end states agree (binding after the commit = the caret
after the committed text); they differ **during** the composition. **Kept, with a label**: publishing a
marked-text offset into a binding the app reads as a position in its own text (as SwiftUI's
`OUT-OF-RANGE` shows) is a defect a port should not inherit, and applying a write would move the
marked text (`SL-H`). Divergence 326. Pinned end to end by
`aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit` (the test `SL-H` could not have).
**Cost if wrong**: an app that reads the selection mid-composition to place a popup sees the
pre-composition caret instead of SwiftUI's offset junk; the app that wrote mid-composition loses
the write, as `SL-H` ruled.

## IM-H — The undo contract after a selection write is measured through the harness and pinned (appends `SL-O`)

Code reading predicts (the lane **measures before writing it down**, and a measurement that differs
replaces the prediction here): `reconcile` sets `history.openGroup = nil` and nothing else
(`SL-I`), so after `type "a","b"` → selection write → `type "c"`:
(1) **⌘Z removes only "c"** and the field restores the selection that **snapshot** held — the
caret as it was *before "c" was typed*, i.e. the **written** selection (the snapshot is taken in
`recording` from `before.anchor/head`, which `reconcile` had already moved) — and publishes it;
(2) a second ⌘Z removes "ab"; (3) with **no** write between, ⌘Z removes "abc" in one step (the
control, 4.17's); (4) a write that **equals** the field's own selection ends nothing (`reconcile`
only resets `openGroup` inside `r != selection`); (5) a selection write **while composing** is held,
so it ends no group, and the commit's `insert` starts or continues per its own rule: a commit of
**one grapheme continues** an open typing group (`inserted.count == 1 ? .typing : .other`,
`TextEditing.insert`), a commit of several (or of a one-grapheme candidate after a selection
write or a selected range) is **its own undo step**. (5)'s one-grapheme-continues clause is a
consequence, not a design: a CJK candidate is one grapheme and joins "typed" Latin text before it.
**Not changed** (text input is in the must-not-move set; no SwiftUI reading — the instrument cannot
undo, `swiftui-text-selection.swift` R4/R5, probe Zs); the contract is documented and pinned.
`docs/testing.md` states it; the lane appends the measured result to the `SL-` decisions doc as
**`SL-O`** and moves that doc's "next unused" line to `SL-P`. **Cost if wrong**: documenting a
prediction as fact; the lane's tests are the measurement and are red-before.

## IM-I — A composition does not survive its field losing focus (measure first; fix named if confirmed)

AppKit discards the input context's marked text when `textInputCaret` becomes `nil` and sends
`Window` **nothing** (IM-C). `Window` clears `composition` only in `press` and Tab's select-all
(`TextEditing.swift`, `Window.swift`), so a composition left by a focus change from code — or a
click on another control — may remain in the field's `TextEditState`, drawn underlined again when
the field is next focused. The lane writes
`aCompositionDoesNotSurviveItsFieldLosingFocus` **first**: if it is red on arrival, the fix is
`Window` dropping `composition` when the focused element changes (one line in the focus-change
path), named here as the ruling that authorises touching focus/text input, with a migration note
in the record (no public API changes; a field refocused after an abandoned composition shows no
stale marked text). If it is green on arrival (the platform's own caret-nil path already clears),
the test stays as the pin. **Cost if wrong**: low; an abandoned composition's stale underline
is the current worst case.
