# Input-method driver for `MetalUITesting` — design

Item C28 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by
MetalCreator (developer-0a, 2026-10-12, gap CT-d: found planning C25's adoption; not blocking).
Prefix `IM-`. Decisions: [`../2026-10-12-ime-driver-decisions.md`](../2026-10-12-ime-driver-decisions.md).
Record: `../../record/102-ime-driver.md`. Branch `feat/ime-driver` from `3fce05f`. Divergence labels
reserved: 325–334 (used: 325, 326). Probe: `docs/probes/swiftui-ime-composition.swift`.

**Status: LANDED 2026-10-12 (record §102).** One lane. Nothing outside `MetalUITesting`, tests and docs
changes behaviour, except `IM-I`'s conditional one-line `Window` fix.

## 1. The gap

`TestWindow` types committed text (`typeText`) and keys (`typeKey`); `send(_:)` can deliver a raw
`.textComposition`, but no named call starts, updates, commits or cancels marked text, and the
driver's contract (queries, `isTextInputActive` honesty, read-back) is absent. Consequences:
`SL-H` (a selection write is held back while composing, published after the commit, divergence 266)
cannot be exercised by a client test; a regression in how a field passes a composition into a
model's draft passes every test; what ⌘Z restores after a selection write is undocumented.

## 2. What the platforms do (inventory)

| Platform fact | Where | Driver counterpart |
|---|---|---|
| `setMarkedText(_:selectedRange:replacementRange:)` → `.textComposition(TextComposition(text, selection in Characters))`, remembers `markedText` | `AppKitPlatform.swift` `MetalHostView` | `setMarkedText` |
| `insertText` → `markedText = ""`, `.textInput(text)` | same | `commitMarkedText(_ text:)` |
| `unmarkText()` → if marked: `.textInput(markedText)` (**a commit**) | same | `commitMarkedText()` |
| `textInputCaret` becomes `nil` while marked → `markedText = ""`, `inputContext.discardMarkedText()`, **no event** | same, `textInputCaret.didSet` | `HeadlessPlatformWindow.setTextInputArea(nil)` clears its mirror, no event |
| `SDL_EVENT_TEXT_EDITING` (only if `textInputCaret != nil`) → `.textComposition(SDLKeys.composition(...))`; empty text = `.none` | `SDLPlatform.swift` | `setMarkedText` / `cancelMarkedText` |
| `Window.dispatch`: `.textComposition` → `TextEditing.compose` (state only); `.textInput` → `TextEditing.insert` + `applyEdit` | `Window.swift` | unchanged, reached by `onInput` |
| `TextEditing.keyDown`: `composition.text` non-empty ⇒ every key handled, none acts | `TextEditing.swift:136` | pinned (test 5.9) |
| `reconcile`/`publication`: composing ⇒ no apply, no publish | `TextEditing.swift` | `SL-H`, test 5.6 |
| `registerHandlers`/`TextField`: AX node `value: text` | `TextField.swift` | `IM-E`, test 5.7 |

## 3. SwiftUI's answers (probe `docs/probes/swiftui-ime-composition.swift`)

Compiled form, one arm per process, macOS 27.0.1, Swift 6.4, screen unlocked; the machine was
loaded and two arms timed out in the confirming pass (recorded in the header, honestly). SwiftUI has
no test driver; the probe calls the focused field editor's `NSTextInputClient` as an input method
does. Controls: C0 (at rest); the separating arm of every "while marked" reading is C0.

| Question | Answer | Arms |
|---|---|---|
| Is the text binding written while marked? | **No**; once, at the commit | A Ae B W / U I |
| Is the field editor's AX value the marked text? | **It includes it** (`'ni'`, `'helloni'`); the SwiftUI element's own value is not reachable (`ax=[]`) | A Ae |
| Is the selection binding published while marked? | **Yes, in the editor's coordinates** (`ins@2`, then `OUT-OF-RANGE`); a `TextEditor` wrote nothing | A B / Ae |
| A selection written from code while marked | **Applied at once**; the commit overwrites it | W WU |
| The commit | `unmarkText` and `insertText` write the text once and the selection after it | U I |
| Cancel | not observable through `discardMarkedText` on a field editor; the SDL form leaves the model untouched | D D2 |
| Undo | not observable by the instrument (as `swiftui-text-selection.swift` R4/R5) | Zs |

Rulings: `IM-E` (AX, divergence 325), `IM-G` (selection write, divergence 326), `IM-F` (cancel).

## 4. Public API (`Sources/MetalUITesting/TestWindowInputMethod.swift`, new)

```swift
extension TestWindow {
    /// Marked text of an input method, as `NSTextInputClient.setMarkedText` / SDL's TEXT_EDITING.
    @discardableResult
    public func setMarkedText(_ text: String, selectedRange: Range<Int>? = nil) -> Bool
    /// `unmarkText`: the marked text becomes the committed text.
    @discardableResult public func commitMarkedText() -> Bool
    /// `insertText`: `text` replaces the marked text and is committed.
    @discardableResult public func commitMarkedText(_ text: String) -> Bool
    /// SDL's empty TEXT_EDITING: the composition ends, nothing is committed.
    @discardableResult public func cancelMarkedText() -> Bool
    /// The focused field's marked text, `""` when none.
    public var markedText: String { get }
    /// Its selection within the marked text (Character offsets), `nil` when none.
    public var markedSelection: Range<Int>? { get }
}
extension HeadlessPlatformWindow {   // additive, HeadlessPlatformWindow.swift
    /// The input method's current marked text (AppKit's `MetalHostView.markedText`).
    public private(set) var markedText: String
}
```
`selectedRange == nil` is a caret at the end of the marked text; a range is clamped to the text.
Each verb: guard `isTextInputActive` (else `false`, nothing sent), send the event(s) of `IM-B`
through `send(_:)`, then `tick()`; answers `true`. Backends: the verbs are platform-neutral (they
send the event both platforms produce), so **no `Backends/SDL` or AppKit change and no Linux
image run** is needed; `MetalUITesting` is portable, and the new tests are platform-neutral
(no AppKit import; `TextSystem` from the existing `harnessWindow` helper).

`MetalUI` gains one `package` member in `TestingHooks.swift`:
`Window.testingComposition: TextComposition?` (the focused text target's `editState.composition`,
`nil` when none or empty). Plain-import guard arm **3.4** in `Tests/MetalUITests/TestHarnessCompileGuards.swift`
(an external module cannot spell it); mutation: `package` → `public` reddens it.

No new `PlatformWindow`/`Platform`/`WindowRenderer` requirement (so no migration note beyond the
record's), no shader, no pixel: 0 px against `3fce05f` in all fourteen images is expected and
checked.

## 5. Tests (`Tests/MetalUITestingTests/HarnessInputMethodTests.swift`, new, platform-neutral)

Model: a plain class with `text`, `selection`, a write log and `redraw`, as `SelModel` in
`HarnessTextSelectionTests.swift` (reuse it if internal to the module; else a local twin). Every
literal is derived before the run ("hello" is 5 Characters). **Red before** for tests 5.1–5.10
is the missing API (compile error), so each is **also** red against a *stub* that returns `true`
and does nothing; the mutations below are the real separating arms.

| # | Test | Asserts | Mutation that must redden it |
|---|---|---|---|
| 5.1 | `aMarkedTextIsInTheFieldNotInTheBinding` | after `setMarkedText("ni")` on a focused field with "hello": `markedText == "ni"`, `markedSelection == 2..<2`, model text "hello", **0** text writes; an update to "ni hao" still 0 writes | `setMarkedText` sends `.textInput(text)` instead of `.textComposition` (text written) |
| 5.2 | `commitMarkedTextCommitsTheMarkedTextOnce` | `commitMarkedText()` → text "helloni", exactly 1 write, `markedText == ""`, platform mirror `""` | commit forgets to clear `Window`'s composition (`TextEditing.insert`'s `composition = .none` removed) — reddens via `markedText` |
| 5.3 | `commitMarkedTextWithACandidateReplacesTheMarkedText` | marked "ni" then `commitMarkedText("你")` → "hello你", 1 write | verb sends the marked text instead of the argument |
| 5.4 | `cancelMarkedTextRestoresTheFieldAndWritesNothing` | field "hello world" with "world" selected; `setMarkedText("ni")`; cancel → text unchanged, selection still 6..<11, 0 writes, `markedText == ""` (IM-F) | cancel sends `.textInput("")` (a commit that deletes the selection) |
| 5.5 | `aSelectionRangeInTheMarkedTextIsKept` | `setMarkedText("ni hao", selectedRange: 3..<6)` → `markedSelection == 3..<6`; clamped for 10..<20 → 6..<6 | range ignored (always end) |
| 5.6 | `aSelectionWrittenWhileComposingIsHeldBackAndSupersededByTheCommit` | selection binding: `ins@5`; compose "ni"; model writes `span(0,1)` + `redraw`, tick; the log gains **no** publish and the field's caret is not 0..<1 (`markedSelection` still 2..<2); after commit `published.last == 7..<7` (caret after "helloni") and the held write is gone from the field; control: same write with no composition applies (`published` unchanged, selection 0..<1) | `reconcile`'s `guard state.composition.text.isEmpty` removed (`TextEditing.swift`, the guard after the `nil`-binding one); (red: 5.6, `aWriteDuringCompositionIsHeldBackAndTheMarkedTextStays`, `reconcileIsHeldBackWhileComposing`); `publication`'s same guard removed is **not** caught by 5.6 (the held write leaves the selection equal to the reported one, so `publication` answers `nil` regardless) and reddens only `publicationIsNilWhenNothingChangedOrWhileComposing` (branch checker) |
| 5.7 | `theFieldsAccessibilityValueIsTheCommittedTextWhileComposing` | `focusedElement?.value == "hello"` before, during (`"ni"` marked, and after update) and `"helloni"` after commit | AX node built from the displayed (spliced) string |
| 5.8 | `typingWhileComposingBelongsToTheInputMethod` | `typeKey(.leftArrow)` and `typeKey(.delete)` while marked change neither text nor `markedSelection` | the `composition.text.isEmpty` early return in `TextEditing.keyDown` (line 136) removed |
| 5.9 | `anInputMethodCannotBeDrivenWithoutAFocusedField` | no field focused: each verb answers `false`, `markedText == ""`, no event reaches `Window` (text unchanged); a click focuses, then `setMarkedText` answers `true` | `isTextInputActive` guard removed |
| 5.10 | `theHeadlessPlatformDropsMarkedTextWhenTheCaretGoes` | mirror `markedText` non-empty while composing; `setTextInputArea(nil)` → `""` and no event | `setTextInputArea` does not clear the mirror |
| 5.11 | `aCompositionDoesNotSurviveItsFieldLosingFocus` (`IM-I`) | compose "ni" in field A, focus B from code, refocus A: `markedText == ""` and the model's text is "hello"; **measured first** (may be red on arrival: the fix is `IM-I`'s) | the fix removed (or, if green on arrival, the platform-clear path removed) |
| 5.12 | `aCompositionIntoATextFieldsBindingReachesTheModelsDraft` | a `Binding<String>` draft model with `didSet` log: the draft sees **only** committed text, once per commit; a two-step "n", "ni", commit "你" gives the single write "hello你"; guard against a regression in how a field hands a composition to a model | `Window.dispatch .textComposition` also calls `applyEdit` |
| 5.13 | `aTextEditorComposesLikeAField` | 5.1/5.2 on a `TextEditor`, multi-line text, caret mid-text: marked text spliced at the caret (`markedSelection` in marked coordinates), commit inserts at the caret | the `display` splice in `TextField.swift` (lines 254–261) puts a `TextEditor`'s marked text at the end of the text instead of at the caret (`IM-J` 1: the earlier newline mutation was the code as it stands, not a mutant) |
| 5.14 | `theUndoContractAfterASelectionWrite` (`IM-H`) | cases (1)–(4) of `IM-H`, measured; **expected values written from the measurement** into the test and into `SL-O` and `docs/testing.md` | `reconcile` stops clearing `openGroup` (4.17's mutation) and `recording` keeps the old selection — both |
| 5.15 | `aCommitOfOneGraphemeContinuesTheTypingGroupAndALongerOneDoesNot` (`IM-H` (5)) | type "a", compose "你" commit, ⌘Z → "" (one step); type "a", compose "你好" commit, ⌘Z → "a" | `insert`'s `inserted.count == 1` kind rule changed |
| 3.4 | `theCompositionHookIsUnreachableFromAPlainImport` | typecheck guard | `package` → `public` |

Existing tests that must stay green unedited: `HarnessTextSelectionTests` (all), `TestingRecipeTests`,
`DemoFrameDeterminismTests`, the harness typecheck guards 3.1–3.3, `TextInput*` tests. Counts move
by +16 tests (15 + the guard) — the lane re-measures (`swift package clean`, native, unfiltered, one
summary line; `FR-J no-argument frame: succeeded=`).

Mutation protocol per `docs/practices/verifying-tests-can-fail.md`: commit first, restore from a
copy, full unfiltered suite, `git status --short` after each, name each reddened test, record the
spelling mutated. A mutation that reddens nothing is the finding.

## 6. Documentation

* `docs/testing.md`: a recipe **"Driving an input method"** (the exact code of test 5.1+5.2+5.6,
  run by `TestingRecipeTests`-style test `theInputMethodRecipeRuns`, so it cannot rot), a table
  mapping each verb to the platform call it stands for, and **"Undo after a selection write"**
  (the measured `IM-H` contract), and a sentence: during composition `TestElement.value` is the
  committed text.
* `docs/superpowers/2026-10-12-text-selection-decisions.md`: ruling **`SL-O`** (the measured undo
  contract; a one-line amendment to `SL-H`: "SwiftUI evidence: `IM-G`"); its "next unused" → `SL-P`.
* `docs/divergences.md`: rows **325** (AX value excludes marked text; vs AppKit's field editor,
  `IM-E`, pin `theFieldsAccessibilityValueIsTheCommittedTextWhileComposing`) and **326** (selection
  binding held, not published, during composition; SwiftUI publishes editor-coordinate offsets and
  applies at once, `IM-G`, pin 5.6). The header's count and next-label line are the merge's.
* Inventory: `closeout-inventory-map.tsv` — add `TestWindowInputMethod` to the line-540 filename
  alternation (or a row of its own, class `M`, family `test-harness-host`, rulings
  `IM-A IM-B IM-C IM-D`), then `zsh docs/probes/closeout-inventory-check.sh`,
  `closeout-undocumented.sh` print nothing and re-record the census with
  `closeout-public-api.sh` (+7 public declarations: 4 functions (`commitMarkedText` counted per overload), 2
  properties on `TestWindow`, 1 on `HeadlessPlatformWindow`; `IM-J` 2).
* Record `docs/record/102-ime-driver.md`, CLAUDE.md/AGENTS.md rule, `README`/`api-overview`
  ("Record" phase, not this one): a two-sentence `HT-` rule: the input-method verbs send the
  platforms' own events and answer `false` with no focused field.

## 7. Demo expectation

None. No demo section, no `METALUI_*_DEMO` root: the driver is test-side. The fourteen offscreen
images are 0 px against `3fce05f` (`docs/probes/demo-pixels/compare.sh <scratch> 3fce05f HEAD`);
`DemoFrameDeterminismTests` `Expected.swift` unedited.

## 8. Human-checks additions (`docs/verification/human-checks.md`, new group `IM`, not run — an agent cannot)

* **IM-1** VoiceOver on a `TextField` while a Pinyin/Kana candidate is marked: the field is not
  re-announced per keystroke; the IM announces its candidates (`IM-E`).
* **IM-2** A real input method on macOS (Pinyin, Kana) and on SDL (IBus/fcitx or Windows IME):
  the marked text is underlined at the caret, a commit writes once, Escape cancels and leaves a
  selected word intact (`IM-F`); the harness's events are the ones the platforms send (`IM-B`),
  but only a person confirms the candidate window sits at the caret.
* **IM-3** Cancel over a selection on AppKit's own `NSTextField` for comparison with `IM-F`.

## 9. Deferred (named, with a reason)

| Item | Reason | Owner |
|---|---|---|
| `replacementRange` of `setMarkedText`/`insertText` (re-marking earlier text) | `MetalHostView` ignores it today; nothing to drive | none |
| Attributed marked text (clause segmentation, underline styles) | `validAttributesForMarkedText` is `[]`; MetalUI draws one underline | none |
| Candidate-window position read-back (`firstRect`) | `textInputAreas.last` already public; the platform call is AppKit-only | none |
| The AX value including marked text | ruled `IM-E`; additive if a human check says otherwise | human check IM-1 |
| Marked text containing a line break in a `TextEditor` (`compose` applies `singleLine` to every composition, today's behaviour; no input method sends one) | not a regression, nothing to drive | none (`IM-J` 1) |
| Cancel via AppKit `discardMarkedText` as a distinct event | AppKit sends none; the caret-nil path (5.10/5.11) is its honest form | none |

## 10. Lanes

**One lane** (`feat/ime-driver`). Files, all disjoint from the parallel branches' except one
additive hunk: `Sources/MetalUITesting/TestWindowInputMethod.swift` (new),
`Sources/MetalUITesting/HeadlessPlatformWindow.swift` (+ `markedText` mirror and a
clear in `setTextInputArea` — C27 also touches this file: keep the hunk additive and rebase),
`Sources/MetalUI/TestingHooks.swift` (+ the hook), `Sources/MetalUI/Window.swift` (**only** `IM-I`'s
conditional clear in the focus-change path), `Tests/MetalUITestingTests/HarnessInputMethodTests.swift`
(new), `Tests/MetalUITests/TestHarnessCompileGuards.swift` (arm 3.4), `docs/testing.md`,
`docs/divergences.md` (325, 326), the SL decisions doc (`SL-O`), the inventory map.
Order: (1) write 5.11 and 5.14 first as measurements (they decide `IM-H` and `IM-I`); (2) the
verbs and mirror; (3) 5.1–5.10, 5.12, 5.13, 5.15; (4) guard 3.4; (5) mutations; (6) docs; (7) the
full gates of the brief (native + default build 0 `warning:`, census, pixel compare,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, a `swift:6.4-noble` build of the portable
targets — `MetalUITesting` is portable). Cost: ~3 hours of agent time, no Backends/SDL run
(untouched).
