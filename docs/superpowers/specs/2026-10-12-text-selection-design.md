# Text selection and caret control — design

Item C25 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested
by MetalCreator (gap CT-b in its `docs/metalui-gaps.md`, reported 2026-10-10: *a field focused
from code opens with its caret at the start of its text and nothing selected; a double click that
renames a title wants the whole title selected, a note wants its caret at the end*). Prefix `SL-`.
Decisions: [`../2026-10-12-text-selection-decisions.md`](../2026-10-12-text-selection-decisions.md).
Record: `../../record/96-text-selection.md`. Branch `feat/text-selection` from `0abce86`.
Divergence labels reserved for this branch: 265–274 (used: 265, 266).

**Amendment (lane 1, `SL-L`):** `TextSelection` and its four initialisers are `@available(macOS 15, *)` (`RangeSet`); the internal state holds the value type-erased (`ErasedSelection`, `AnyHashable`), `reconcile` takes `AnyHashable?` and `publication` returns `Range<Int>?`; `TextInputTarget.selectionSink` returns `AnyHashable`.

**Status: LANDED 2026-10-12** (record §96): lane 1 built the library, lane 2 the tests, demo and mutations; the looks (group SL) are owed to a human.

## 1. SwiftUI's answers (probe `docs/probes/swiftui-text-selection.swift`, recorded 2026-10-12)

Compiled form, one arm per process, run twice, byte-identical (49 lines); macOS 27.0.1, Swift 6.4.
The instrument is `swiftui-key-focus.swift`'s (a key window, `NSEvent`s through `NSWindow`/`NSApp.sendEvent`).
Controls: C0/C0e (no binding at all), C1/C1e (binding, nothing done), C3 (unfocused). The separating
arm of "a write is applied" is the same arm with the write left out (W1 against C2).

| Question | Answer | Arms |
|---|---|---|
| Where does a field focused from code put the caret? | **`TextField`: everything selected** (type X gives `X`, the binding reads `sel@0..5`). **`TextEditor`: caret at the end** (`helloX`, `ins@5`). | C0, C0e, C1, C1e |
| Does a binding value written before the focus survive? | `TextField`: **no** — written before, or in the same turn as, the focus it loses to the select-all (`X`). `TextEditor`: yes (`helloX`, `hXlo`, `heXllo`). | P1 P2 P4 P5 F1 F4 / P7 P8 F3 |
| Written one turn after the focus | Wins, both fields (`heXllo`, `hXo`, `hXlo`). | F2 W1 W2 W5 |
| When is a write applied? | **On the next run-loop turn**: a key in the same turn as the write still sees the old selection (`X`, the write 1..<4 unseen). | W3 against W2 |
| Written while unfocused | Kept as the binding's value; applied when the field is used (P6s); a click then replaces it. | P6, P6s |
| What the binding reads after... | typing: `ins@` after the inserted text; ← ←: collapsed; ⌘A: `sel@0..n`; click: `ins@n`; double click: the word; ⇧→: extended; delete: `ins@n`. Resigning focus writes `ins@0`. | C2 R1 R2 R3 R6 R7 R8 R9 F5 |
| nil written | Ignored: the field's own selection stays. | W4 |
| Stale or out-of-range index | **No trap.** Indices of a longer string clamp to the end (`helloX`); a text replaced from code leaves the binding stale and the next edit clamps (`hiX`); the binding is not rewritten until the user acts. | S1 S2 W6 W8 |
| `.multiSelection` | The field acts on the **first range** (`Xello`) and reads back `ins@1`. | S3 W9 |
| After undo | **Not observable**: ⌘Z synthesized through `NSApp.sendEvent` did not undo (R4, R5: text stays `X`). The undo claims are MetalUI's own (`TI-G`), not SwiftUI's. | R4 R5 |
| IME composition | Not probed (the instrument cannot compose). MetalUI's rule is its own (`SL-H`). | — |

gpui's side, where SwiftUI has no answer to *how a platform-neutral editor exposes its
selection*: its text-input seam is `EntityInputHandler` (`selected_text_range`,
`replace_text_in_range`, `marked_text_range`), read by the platform, and an editor entity changes
its own selection by method (`select_all`, `change_selections`). There is **no binding**; the
caller holds the entity. This was recalled, not re-read in this session; nothing here rests on it.
SwiftUI's binding is the design authority (`EP-5`); gpui informs only the *echo-free* rule
(`SL-B`): the platform reads, the owner writes, and a value that equals what was last
reported is not a new instruction.

## 2. Public API

SwiftUI's spellings, macOS 15's. `Sources/MetalUI/TextSelection.swift` (new, stdlib only, portable;
`RangeSet` is the standard library's since Swift 6).

```swift
public struct TextSelection: Equatable, Hashable, Sendable {
    public enum Indices: Equatable, Hashable, Sendable {
        case selection(Range<String.Index>)
        case multiSelection(RangeSet<String.Index>)
    }
    public var indices: Indices
    public var isInsertion: Bool { get }              // a single empty range
    public init(range: Range<String.Index>)
    public init(insertionPoint: String.Index)
    public init(ranges: RangeSet<String.Index>)
}

extension TextField {
    public init(_ placeholder: String, text: Binding<String>, selection: Binding<TextSelection?>)
    public init(_ placeholder: String, text: String, selection: TextSelection?,
                onChange: @escaping @MainActor (String) -> Void,
                onSelectionChange: @escaping @MainActor (TextSelection) -> Void)
}
extension TextEditor {
    public init(_ placeholder: String = "", text: Binding<String>, selection: Binding<TextSelection?>)
    public init(_ placeholder: String, text: String, selection: TextSelection?,
                onChange: @escaping @MainActor (String) -> Void,
                onSelectionChange: @escaping @MainActor (TextSelection) -> Void)
}
```

(`TextEditor`'s existing initialisers fix the placeholder spelling; lane 1 reads them and matches.)
No `axis:` (a `TextField` is one line). **No `selectAll()` / caret-on-focus hook** (`SL-A` item 3):
the binding carries both use cases, and a second spelling would be a second path to the same state.

Usage (the two requested cases):

```swift
// double click renames: the whole title selected on the first frame
model.selection = TextSelection(range: title.startIndex..<title.endIndex); model.renaming = true
TextField("Title", text: $model.title, selection: $model.selection).focused($focus)
// a note opens with the caret at the end
model.noteSelection = TextSelection(insertionPoint: note.endIndex)
TextEditor(text: $model.note, selection: $model.noteSelection)
```

Semantics, in one paragraph. The field's selection is its own state (`TextEditState`, per `TI-B`),
unchanged. With a binding, the field (a) **publishes** its selection to the binding after each
input that changed it, and (b) **applies** the binding to its own state when the binding holds a
value the field did not itself publish. A published value is remembered, so the next frame's read
of it is not a new instruction (no echo, no flip of a backward selection's anchor). A `nil`
binding is "the field's own", never an instruction. Offsets are Characters; `String.Index`
conversion clamps and rounds down to a Character boundary. Without a binding nothing runs.

**Not changed (named so nothing is silently assumed):** a field focused from code keeps its caret
where it was (position 0 on first use; divergence 265) — `TextField` does not select all on code
focus as SwiftUI's does (`SL-C`). Nothing is written to the binding by focus or resign (divergence 266).

## 3. Implementation

All internal; **no new `PlatformWindow`/`Platform`/`WindowRenderer` requirement, no
`Backends/SDL` change, no shader change, no `Handlers` member** (`TextInputTarget` already hangs
off `Handlers.textInput`; it is internal and gains one optional field).

1. **`TextSelection.swift`** (new): the type above, plus internal
   `static func offsets(of: TextSelection, in text: String) -> Range<Int>?` (nil for `.multiSelection` with
   no ranges; the *first* range otherwise; both ends clamped to `startIndex...endIndex` then
   `text.distance(from:startIndex, to:)`, which rounds an unaligned index down) and
   `init(offsets: Range<Int>, in text: String)` (an empty range is `init(insertionPoint:)`).
   An internal static counter `TextSelection.conversionCount` (debug-readable by `@testable` tests)
   counts `offsets(of:in:)` calls — the work counter test 4.19 reads (`SL-J`).
2. **`TextEditing.swift`**: `TextEditState` gains `seenBinding: TextSelection?` and
   `reported: Range<Int>?`. A pure `TextEditing.reconcile(binding: TextSelection?, text: String,
   state: inout TextEditState) -> Bool`:
   ```
   guard binding != nil else { seenBinding = nil; return false }       // nil is never an instruction (W4)
   guard state.composition.text.isEmpty else { return false }          // held back (SL-H)
   guard binding != state.seenBinding else { return false }            // O(1): the steady frame
   seenBinding = binding
   let r = offsets(of: binding, in: text) (clamped to text.count)
   if r != state.selection { anchor = r.lowerBound; head = r.upperBound
                              history.openGroup = nil; goalX = nil; revealsCaret = true }
   reported = r; return true
   ```
   It never touches `history.undo`, `redo` or `lastText` (`SL-I`). Plus a pure
   `TextEditing.publication(state:text:) -> TextSelection?` (nil while composing or when
   `state.selection == state.reported`).
   `TextInputTarget` gains `selectionSink: (@MainActor (Range<Int>, String) -> TextSelection)?` —
   writes the binding and returns the value it wrote.
3. **`TextField.swift` / `TextEditor.swift`**: stored `selection: TextSelection?` and
   `onSelectionChange: (@MainActor (TextSelection) -> Void)?`; the Binding initialisers forward to
   the controlled ones (`DD-E`'s pattern); `prepaint` calls `reconcile` on the field's state
   **before** `geometry(...)` reads it (the same phase-time state write the scroll already makes,
   `TI-E`: it converges in one frame and writes nothing after) and, if the field has a sink, sets
   `reported = state.selection` when it is nil (the baseline); the target built in `prepaint` carries
   `selectionSink = { range, text in let s = TextSelection(offsets: range, in: text); onSelectionChange(s); return s }`.
   Caret positions still come from `TextSystem.caretOffsets` (`TI-E`); the binding only moves
   `anchor`/`head`, never an x.
4. **`Window.swift`** (the only shared-file edit; about 25 lines, kept to two sites for the merge with
   `feat/input-followups`): first line of the `platformWindow.onInput` closure after its `guard`:
   `defer { self.publishFocusedSelection() }`; and one private method next to `setEditState`:
   ```
   private func publishFocusedSelection() {
       guard let id = focusedElement, let target = lastFocusRegistry.textTarget(for: id),
             let sink = target.selectionSink else { return }
       let text = currentText(id, target)                       // composes two edits between frames
       var state = editState(id)
       guard let range = TextEditing.publication(state: state, text: text) else { return }
       state.reported = range
       let written = StateDispatch.dispatching(to: id) { sink(range, text) }   // ID-F; input, never a phase
       state.seenBinding = written; setEditState(id, state)
   }
   ```
   Every selection-changing input — press, drag, key, ⌘A, Tab traversal, `.textInput`, undo and
   redo, the AppKit Edit menu's keys — arrives through that one closure, so one `defer` covers all
   (a press that focuses a field reads the new focus in the `defer`). No SDL file is involved: text
   input on SDL reaches the same closure.
5. **Accessibility, rich text, chrome, hit testing, identity**: untouched (`AXNode` gains no field;
   a selected-range accessibility value is deferred, §8).

## 4. Tests (every one named; each owes a measured red-before, and the mutation that must redden it)

Files (new): `Tests/MetalUITests/TextSelectionTests.swift` (4.1–4.9: pure and `Window`),
`Tests/MetalUITestingTests/HarnessTextSelectionTests.swift` (4.10–4.22: the end-to-end ones, through
`TestWindow`, real `Window`, no sleeps; the model is a plain class with `setNeedsRedraw()`),
`Tests/MetalUITests/TextSelectionCompileGuards.swift` (G1–G3). *Red before* for all of them: the API
does not exist, so a test is first measured red by the compile error; the **behavioural** red the
implementer must record is the mutation column. Mutations are run on a committed tree, restored from
a copy, full unfiltered suite, `git status --short` after each, every reddened test named.

| # | Test | Claims | Mutation that must redden it |
|---|---|---|---|
| 4.1 | `aTextSelectionHasSwiftUIsThreeShapes` | `init(range:)` is `.selection`, not insertion; `init(insertionPoint:)` is an empty `.selection`, `isInsertion`; `init(ranges:)` is `.multiSelection`; equality by indices | `isInsertion` returns `false` |
| 4.2 | `offsetsClampAndRoundDownToACharacterBoundary` | indices of a longer string clamp to `text.count`; a UTF-16 index inside a family emoji reads as the Character's start; empty text | drop the clamp (`min`) |
| 4.3 | `aMultiSelectionActsOnItsFirstRange` | ranges (3..<4, 0..<1) read 0..<1 | take `.last` |
| 4.4 | `aRangeBecomesAnInsertionPointWhenEmptyAndASelectionOtherwise` | `init(offsets:in:)` | always `.selection` |
| 4.5 | `reconcileAppliesAValueTheFieldDidNotPublish` | pure: new value moves `anchor`/`head`, sets `reported`, ends the open undo group | `binding != seenBinding` inverted |
| 4.6 | `reconcileIgnoresNilAndForgetsTheSeenValue` | nil moves nothing; nil then the earlier value applies again | treat nil as "select nothing" |
| 4.7 | `reconcileIsHeldBackWhileComposing` | composition non-empty: nothing moves, `seenBinding` unchanged | delete the composition guard |
| 4.8 | `reconcileNeverTouchesTheUndoStacks` | `undo`, `redo`, `lastText` equal before and after | assign `history = TextEditHistory()` |
| 4.9 | `publicationIsNilWhenNothingChangedOrWhileComposing` | the echo-free rule's pure half | return the selection unconditionally |
| 4.10 | `aTitleOpensWithItsWholeTextSelectedAndTypingReplacesIt` | **use case 1.** Mount with the binding already whole-range and `.focused` from `onAppear`; `typeText("New")` gives `New` (control: the same without a binding gives `Newhello`, today's measured `Xhello`) | skip `reconcile` in `TextField.prepaint` |
| 4.11 | `aNoteOpensWithTheCaretAtItsEndAndAppends` | **use case 2.** `TextEditor`, `insertionPoint: endIndex`, typing appends; the same text with a trailing line, caret on the last line | skip `reconcile` in `TextEditor.prepaint` |
| 4.12 | `aWriteFromACodePathMovesTheCaretOnTheNextFrame` | focused field, a `Button` click writes `insertion@2`, the frame that click draws applies it, `typeText("X")` gives `heXllo`; the same frame's earlier key (no frame between) still sees the old caret (SwiftUI's W3, pinned as divergence-free) | invert the comparison |
| 4.13 | `theFieldPublishesAfterTypingClickDoubleClickShiftArrowSelectAllAndDelete` (`@Test(arguments:)`, one arm each) | the binding reads `ins@`, `ins@n`, the word, the extended range, `0..<n`, `ins@n` — SwiftUI's R-arms | delete the `defer` in `onInput` (all arms red) |
| 4.14 | `tabbingIntoAFieldPublishesItsSelectAll` | `dispatchFocusTraversal`'s select-all reaches the binding | publish only in `dispatchTextInput` |
| 4.15 | `aPublishedValueIsNotAppliedBackAndWritesOnce` | count of binding writes per input is 1 and a following idle frame writes 0 | do not store `seenBinding` after publishing |
| 4.16 | `aBackwardSelectionKeepsItsDirectionAcrossTheEcho` | ⇧← twice then ⇧← again extends leftward (anchor stays right) | apply even when the range equals the state's (drop `r != state.selection`) |
| 4.17 | `aSelectionWriteDoesNotCorruptUndoAndEndsTheTypingGroup` | type `a`, write the same caret, type `b`, one ⌘Z removes only `b`; two ⌘Z restore the original; redo replays; a second case: write then undo of an earlier group still undoes | (a) clear the history in `reconcile`; (b) do not clear `openGroup` (the first reddens the second ⌘Z, the second the one-⌘Z claim) |
| 4.18 | `twoEditsBetweenFramesPublishAgainstTheEditedText` | `window.send` a cut then a paste with no frame between: the binding reads the offset in the *edited* text | publish with `target.text` instead of `currentText` |
| 4.19 | `aSteadyFrameWithABindingConvertsNothing` | `TextSelection.conversionCount` unchanged across 5 idle frames; and a no-binding field leaves `selectionSink` nil (no publish call) | compare converted ranges each frame instead of `TextSelection` values |
| 4.20 | `aStaleSelectionNeitherTrapsNorIsRewritten` | indices of a longer string: field clamps (typing appends), the binding is not written before the edit | remove the clamp |
| 4.21 | `aBoundSelectionIsKeptWhileTheFieldIsNotFocused` | set while unfocused, then focused from code later: the first typed text replaces the range (SwiftUI's P6s/F2 in the order MetalUI honours) | apply only when focused |
| 4.22 | `aWriteDuringCompositionIsHeldBackAndTheMarkedTextStays` | `.textComposition`, write the binding, frame: the marked range unchanged; commit; the commit's publish wins (`SL-H`) | delete the composition guard |
| 4.23 | `aTextAndASelectionWrittenInOneHandlerApplyAgainstTheNewText` | rename: `text = new; selection = whole(new)` in one handler selects the new text | convert against the *previous* frame's text |
| 4.24 | `aTextEditorPublishesAcrossLinesAndRevealsAWrittenCaret` | Down publishes the second line's offset; a write at the end of a long text scrolls (`scrollY > 0` read through the caret rect of the target the frame registered) | do not set `revealsCaret` |
| 4.25 | existing suites unmoved | `TextFieldTests`, `TextEditorTests`, `TextEditingTests`, the fourteen images 0 px, `DemoFrameDeterminismTests` Expected.swift unedited | — |

Typecheck guards (each mutated red once, recorded):
**G1** `textSelectionIsSwiftUIsShape` (`typecheck`: `TextSelection(range:)`, `(insertionPoint:)`,
`(ranges:)`, a `switch` over `.indices`, `isInsertion`; mutation: rename `isInsertion`);
**G2** `theSelectionInitialisersAreSwiftUIs` (`typecheck`: both fields over `State<TextSelection?>`
projected values, plus the *separating arm* — a `Binding<TextSelection>` (non-optional) does **not**
compile; mutation: make the parameter non-optional, the separating arm turns red);
**G3** `theSelectionInternalsAreUnreachableFromAnExternalModule` (`typecheckFile`, plain import, `SA-P`:
`TextSelection.conversionCount`, `init(offsets:in:)`, `TextInputTarget.selectionSink`,
`TextEditState.seenBinding` are not spellable; mutation: make `conversionCount` public).

Measured wherever a number is claimed: 4.10's control, 4.12's one-frame claim and 4.15's write
counts are literals derived before the run. The expected total is 3363 + 25 tests (4.1–4.24 plus the
arguments count as one `@Test` each, the harness tests ≈ 14) and 213 + 3 guards; lane 2 records the
measured counts, not these.

**Demo** (METALUI_TEXT_INPUT_DEMO=1, its own function passed to the generic composer — the Windows
1 MB stack rule): a "Selection" section with (i) a title row — double click selects the whole
title (a readout `selection 0..<n`), Esc cancels; (ii) a note editor "Open note" button that
writes `insertionPoint: endIndex` and focuses; (iii) three buttons "Select all", "Caret to start",
"Caret to end" writing the binding. Expectation: the fourteen offscreen default-demo images are
**unchanged (0 px)** — the section is gated by the env var; `everyProductionTreeBuildsOnAOneMegabyteThread`
green. No demo capture is taken (screen locked at design time; the lock probe decides at lane 2).

**Human-checks additions** (Record phase writes them in `docs/verification/human-checks.md`, group
**SL**, not run — an agent cannot): SL-1 the demo's double click highlights the whole title in the
accent wash and typing replaces it; SL-2 the note opens with the caret at its end and the end in view;
SL-3 with a Japanese input method, composing in the title while "Caret to start" is pressed leaves the
marked text in place and the commit lands where the composition began; SL-4 click, arrows and ⇧-arrows
update the readout; SL-5 the same demo section on Linux (SDL) and Windows; SL-6 undo after a
programmatic caret move undoes the typing, not the move.

## 5. Documents (Record phase)

`docs/record/96-text-selection.md` and its row in `docs/record/README.md`; `CLAUDE.md`/`AGENTS.md`
(`SL-` in the prefix list with its decisions doc and next id, a two-sentence rule under Text input,
counts, divergences header: 265, 266 added, next label settled by the merge); `docs/api-overview.md`;
`docs/migration.md` (no new requirement: "none — additive"); `docs/divergences.md` (265, 266 and the
sections in record §04); `docs/verification/human-checks.md` (group SL); the closeout map
(`family text-selection`, class `A` for `TextSelection` and the two Binding initialisers with probe
`swiftui-text-selection.swift`, arms `C P R W F S`, divergences 265 266, rulings `SL-A…`; `M` rows for
the two controlled initialisers) and `closeout-public-api.sh` re-recorded; `README.md` feature line.

## 6. Lanes (two; disjoint files; A then B)

**Lane 1 — library** (Opus). `Sources/MetalUI/TextSelection.swift` (new), `TextEditing.swift`,
`TextField.swift`, `TextEditor.swift`, `Window.swift` (the two sites of §3.4), the inventory map and
census, doc comments on every new public declaration. Gate: `swift build` 0 warnings both build
systems; existing text suites green; 4.1–4.9 written with it (pure tests live with the code they pin).
**Lane 2 — tests, demo, mutations** (Opus for mutations). 4.10–4.25 and G1–G3 (new files), the demo
section (`Sources/MetalUIDemoContent/DemoContent.swift`, a new function), the mutations of §4 and the
three guard mutations, the full native run (read the one summary line and `FR-J no-argument frame:
succeeded=`), the fourteen-image compare, the Linux image (`swift:6.4-noble`: `RangeSet` and the harness
tests build and pass there), the lock probe for the demo capture. Lane 2 edits no lane-1 file except to
fix a defect a mutation or test found, recorded as a ruling.

## 7. What must not move

Identity and state retention (the seven slots: `seenBinding`/`reported` live inside the existing
`TextEditState` slot; no eighth); hit testing; accessibility (`AXNode` and both bridges untouched);
animation; focus (`focus(_:)`, Tab, click-focus rules and the code-focus caret: unchanged, divergence
265); `List` windowing; `Deferred`; text input (key table, IME, `editedText`, undo `TI-G`); rich text;
field chrome `MD-`. Pixels: 0 px, fourteen images. `MetalUILayout` imports only `MetalUICore`;
`MetalUIScene` only `MetalUIShaderTypes`; `Backends/SDL` untouched (its tests are not required; the
Linux image builds root). A field with no `selection:` runs no new code beyond one `nil` check in
`prepaint`.

## 8. Deferred (named, with reason and owner)

- **Select-all on code focus for `TextField` / caret-at-end for `TextEditor`** (SwiftUI's defaults,
  C0/C0e): not built — it changes focus behaviour for every existing app and sits in the "must not
  move" set; the binding gives the apps the control they asked for. Divergence 265. Owner: none;
  reopen if MetalCreator reports the default as a gap.
- **Writing the binding at code focus and at resign** (SwiftUI's `sel@0..n`, `ins@0`): not built; same
  reason; divergence 266. An app that needs the caret reads it after the first input.
- **`axis:`** (`TextField` multi-line): MetalUI's `TextEditor` is the multi-line field. Owner: none.
- **A selected-range accessibility value** (`AXNode` field, both bridges, `AB-`): a new field owes a
  row on both bridges and VoiceOver cannot be run by an agent (`IX-AE`). Owner: none.
- **Multi-range selection** in the field itself: SwiftUI acts on the first range (S3, W9) and so do we;
  true multi-caret editing is not offered by either.
- **Undo observed against SwiftUI** (R4/R5): the instrument cannot synthesize it; MetalUI's undo rule
  is its own and pinned by 4.17, not claimed as SwiftUI's.
