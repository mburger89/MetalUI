# Text selection and caret control — decisions

Rulings for item C25 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), requested by MetalCreator (gap CT-b). Prefix `SL-`. Spec:
[`specs/2026-10-12-text-selection-design.md`](specs/2026-10-12-text-selection-design.md). Record:
`../record/96-text-selection.md`. Branch `feat/text-selection` from `0abce86`. Divergence labels
reserved for this branch: 265–274.

SwiftUI's side: `docs/probes/swiftui-text-selection.swift` (arms C, P, R, W, F, S; run twice,
byte-identical; recorded in its header). gpui's side, where SwiftUI has nothing, is recalled
(`EntityInputHandler`, no binding) and rests no ruling.

**Next unused id: `SL-R`.**

## SL-A — The API is SwiftUI's `TextSelection` and `selection:` initialisers; no `selectAll()` hook

`TextSelection` (own portable type: `indices`, `isInsertion`, `init(range:)`,
`init(insertionPoint:)`, `init(ranges:)`), `TextField(_:text:selection:)` and
`TextEditor(text:selection:)` over `Binding<TextSelection?>`, plus the controlled spellings
(`selection:` value and `onSelectionChange:`) beside the existing controlled initialisers (`DD-E`'s
pattern). **Evidence**: the probe compiles all of them against macOS 15's SwiftUI; the Binding
shape carries both requested cases (a whole title, a caret at the end) and also reading back.
**Why not the fallback `selectAll()`/caret-on-focus**: it is a second path to the same state and
cannot read; the binding made the fallback unnecessary (the question the item asked). **Cost if
wrong**: an app wanting a one-shot `selectAll()` writes `TextSelection(range: whole)` — one line;
adding a method later is additive.

## SL-B — The binding is two-way and echo-free: publish after input, apply what the field did not publish

The field publishes its selection after each input that changed it (one `defer` in `Window`'s
`onInput`), remembering the value it wrote (`seenBinding`) and the range (`reported`); in `prepaint`
it applies the binding only when it differs from `seenBinding` (`TextSelection ==`, O(1)). A
published value is therefore never re-applied, a backward selection keeps its anchor (a
`TextSelection` carries no direction), and a steady frame converts nothing. **Evidence**: R-arms
give what the binding reads after each input; gpui's platform-reads/owner-writes split informs the
echo rule only. **Alternatives rejected**: applying every frame (converts `String.Index` to offsets
each frame, flips anchors, fights the user's input); writing the binding from `prepaint` (a phase-time
write, silently stale, `@State` rule). **Cost if wrong**: a write equal to the last published value
is a no-op by construction — an app that re-writes the *same* value after the user moved away gets
the move (it differs from the last published one), which is SwiftUI's behaviour (W1).

## SL-C — The default focus behaviour does not change (divergence 265)

SwiftUI selects all in a `TextField` focused from code and puts a `TextEditor`'s caret at its end
(C0, C0e); MetalUI's fields keep their stored caret (0 on first use). **Not changed**: focus is in
the must-not-move set, every existing app and test pins today's behaviour, and the binding gives
callers exact control. **Cost if wrong**: a port from SwiftUI that relied on select-all-on-code-focus
types before the text; one `selection:` write restores it. Deferred, owner none (spec §8).

## SL-D — A write is applied at the next frame's prepaint, at any time, focused or not

SwiftUI applies on the next run-loop turn (W3 against W1); MetalUI applies in the next frame's
`prepaint`, so a write from an input handler is in the frame that input draws, including the field's
first frame (the rename case) — **better than SwiftUI's `TextField`, whose preset loses to the
select-all (P1, F1)**, and the same as its `TextEditor` (P7). A key arriving between the write and
that frame still sees the old selection, as in SwiftUI's W3. **Cost if wrong**: a caller who needs the
write before the next key sequences it in input and lets the harness's one-frame-per-action draw.

## SL-E — Nil is never an instruction

Writing `nil` leaves the field's own selection (W4); the field also forgets `seenBinding` on nil, so
the same non-nil value written afterwards is applied again. A binding that starts nil and never
changes stays nil until the first selection-changing input publishes.

## SL-F — The binding is written only after input (divergence 266)

SwiftUI also writes at focus (`sel@0..n` for a `TextField`, `ins@n` for a `TextEditor`, C1/C1e) and at
resign (`ins@0`, F5). MetalUI writes after input only: a press (including the one that focuses),
a drag, a key, ⌘A, Tab traversal's select-all, a typed or composed commit, undo and redo. **Reason**:
focus from code is not input and a write there would be a phase-time write; a baseline (`reported`)
is taken in `prepaint` so the first mouse move on a focused field publishes nothing. **Cost if wrong**:
a caller reading the caret right after a code focus reads what it last wrote or nil.

## SL-G — Stale, out-of-range and multi-range values are clamped, never trapped

A `String.Index` outside the text clamps to the end and an unaligned one rounds down to a Character
boundary (S1, S2, W6, W8: no trap in SwiftUI either). `.multiSelection` applies its **first** range
(S3, W9) and is never published. The binding is not rewritten to the clamped value. **Cost if wrong**:
`String.distance` on a foreign index could misbehave on an exotic index — covered by 4.2 with a
UTF-16 index inside a grapheme cluster; a trap here would be a denial of service from app data, so
the clamp comes first.

## SL-H — A write during IME composition is held back; the commit's publish supersedes it

While `state.composition` is non-empty `reconcile` applies nothing and leaves `seenBinding`
unchanged, and nothing is published (the state's selection is then the replaced range). The probe
cannot compose, so there is **no SwiftUI evidence**; this is MetalUI's own rule, from `geometry(bounds:state:…)` splicing the marked text at the selection's start
(marked text lives at the selection's start). After the commit the input's publish overwrites the
held write (the user's composition is the later instruction). **Cost if wrong**: an app write
raced with composition is lost; applying it would move the marked text and break the IME. Human
check SL-3.

## SL-I — A selection write never touches undo history except to end the typing group

`reconcile` sets `history.openGroup = nil` (as a caret move does) and nothing else: `undo`, `redo`
and `lastText` are untouched, so `TI-G`'s "valid only for the text its last edit produced" holds (the
text did not change). Undo restores its snapshot's selection and publishes it. **Evidence**: tests
4.8 (pure) and 4.17 (end to end, two mutations). SwiftUI's undo is not observable in the instrument
(R4, R5) and no SwiftUI claim is made.

## SL-J — Conversions are offsets in Characters, counted

`String.Index` ↔ Character offset conversion happens only on a binding change (apply) and an input
that changed the selection (publish); caret x positions still come only from
`TextSystem.caretOffsets` (`TI-E`). `TextSelection.conversionCount` (internal) is the work counter
test 4.19 reads: zero conversions in a steady frame. Performance claims count work, never time.

## SL-K — Critic review of the design: no defect found, two arms re-run

The design was attacked for unprobed SwiftUI claims, public spellings, Apple types in portable
surfaces, one-renderer primitives, defaulted requirements, pixels, C enums and lane overlap. Arms C0
and P1s were re-run (2026-10-12) and read byte-identical to the header. No platform requirement,
primitive, enum or Backends/SDL file is touched, so those attacks have no object; `TextSelection` is
stdlib-only. Rejected: splitting lane 1 further (one file set, `Window.swift` edits are two small
sites; C16 also edits `Window.swift` input regions, so lane 1 rebases onto a fresh master before
its Window edit and keeps it minimal). Lane 2 owns every test, so no test is written by the author of
the code it pins except 4.1-4.9, which are pure and mutated by lane 2.

## SL-L — `TextSelection` is `@available(macOS 15, *)`; the field's state holds it type-erased

`RangeSet` (the `.multiSelection` payload, SwiftUI's shape) is the standard library's from macOS 15
(measured: `'RangeSet' is only available in macOS 15.0 or newer` at the package's macOS 14
deployment target). The design (§2) did not see it. **Ruling**: `TextSelection` and the four
initialisers that name it (`TextField`/`TextEditor` `selection:` Binding and controlled spellings)
carry `@available(macOS 15, *)` — SwiftUI's own availability for the type — and nothing else in the
package is gated: `TextEditState.seenBinding` holds the value as `ErasedSelection` (an
`AnyHashable` box, `@unchecked Sendable`: only ever built from a `TextSelection`), the field stores
`selection: AnyHashable?` and a `selectionWriter` closure built inside the available initialiser,
and `TextEditing.reconcile(binding: AnyHashable?, …)` casts under `#available`. The platform floor
(`.macOS(.v14)`) does not move. **Alternatives rejected**: raising the floor (every app and the
must-not-move set); an own `RangeSet` lookalike (not SwiftUI's type, and `.multiSelection(RangeSet)`
would not compile against SwiftUI code); gating `TextEditState`/`TextInputTarget`/`Handlers`
(availability spreads through every file that names them). **Cost if wrong**: an app on macOS 14
cannot bind a selection (SwiftUI cannot either); Linux and Windows have no gate. Tests that name the
type are `@available(macOS 15, *)`.

## SL-M — `TextInputTarget` carries its two closures in class boxes: `Handlers` stays 488 bytes

The first build added `selectionSink` (an optional closure, 16 bytes) to `TextInputTarget`, which
`Handlers.textInput` holds inline: `Handlers` grew 488 to 504 and two existing pins reddened
(`theNewDeclarationsCostHandlersAtMostOnePointer`, `handlersGainsOneReferenceMember`, measured in the
full run). The design (§3) said the field is "internal and gains one optional field" and did not
count bytes. **Ruling**: `onSubmit` and the sink are each one class box (`TextTargetHook`, one
pointer), exposed through computed `onSubmit`/`selectionSink`, behind an explicit initialiser with
the memberwise labels — net zero, `Handlers` back to 488, no pin edited. **Alternative rejected**:
one box for both (480; the exact-488 pin would move and owe a migration note). **Cost**: one
allocation per bound or submitting field per frame.

## SL-N — The demo is a root of its own, `METALUI_SELECTION_DEMO=1`, not a section of the text-input demo

The design (§4 "Demo") put a "Selection" section in `METALUI_TEXT_INPUT_DEMO`. **Measured**:
`textInputDemoContent()` is pinned by `theTextInputDemoRendersAndTypes` (`fields.count == 3`) and
by the accessibility audit's `textinput` trees, so a fourth field would move two existing suites.
**Ruling**: `selectionDemoContent()` (`SelectionDemo.swift`, macOS 15 like `TextSelection`) is its
own root behind `METALUI_SELECTION_DEMO=1`, built by `everyProductionTreeBuildsOnAOneMegabyteThread`
(`buildTheSelectionDemo`) and driven by `theSelectionDemoRenamesWithTheWholeTitleSelectedAndOpensANoteAtItsEnd`.
Nothing is in the default demo: the fourteen images are unmoved. **Cost**: one more env var in the
list. Test 4.15 also gained a work arm (the frame after a publish converts nothing): with the equal-range
guard in `reconcile`, a missing `seenBinding` store is otherwise invisible in write counts.

## SL-O — The undo contract after a selection write (measured through the harness; amends `SL-H`)

Measured by `theUndoContractAfterASelectionWrite` and
`aCommitOfOneGraphemeContinuesTheTypingGroupAndALongerOneDoesNot` (ime-driver `IM-H`), which matched the
code reading: (1) after typing `a`,`b`, a selection write to a different range and typing `c`,
⌘Z removes only `c` and restores the **written** selection (the snapshot is taken after `reconcile` moved
the selection), (2) a second ⌘Z removes `ab`; (3) with no write, one ⌘Z removes `abc`; (4) a write
equal to the field's own selection ends no group; (5) a write while composing is held, so it ends no
group, and the commit's `insert` continues a typing group for one grapheme and is its own step for
several. Not changed. Amendment to `SL-H`: SwiftUI evidence for the held write is `IM-G` (divergence
326; SwiftUI publishes during composition and applies a write at once). Documented in `docs/testing.md`.


## SL-P — A text replaced from outside moves the caret to the end (no selection binding); with one the binding wins

**Question.** A focused `TextEditor`/`TextField` whose bound text is replaced from code (autocomplete "/com" ->
"/compact ", an `@path` mention appended) kept its old caret offset, so the next key landed mid-text ("/comXpact ").
**Measured** (`docs/probes/swiftui-text-external-replace.swift`, macOS 27.0.1, Swift 6.4, compiled, one arm per
process, run twice, byte-identical; 26 arms plus 10 bound arms): without a selection binding, SwiftUI's `TextField` and
`TextEditor` agree on every row: the text after the replacement and one typed X is the new text with X **at its end**
whenever the text changed: extend at the caret `/com`@4 -> `/compact ` gives `/compact X`; extend under a mid caret
`ab cd`@2 -> `abXY cd` gives `abXY cdX` (not after the inserted XY); rewrite earlier text (`foo bar`@7 -> `FOO bar`, and
under a caret at 3 -> `goo bar`) gives `FOO barX`/`goo barX`; insert before the caret gives `AAfoo barX`; append under a mid
caret gives `foo bar @pathX`; shrink with the caret at the end, past it (`hello world`@8 -> `hel`) or inside the kept text
(@2 -> `hello`) gives `helloX`/`helX`/`helloX`; cleared gives `X`; unrelated and longer gives `completely differentX`.
**Only identical text keeps the caret** (`hello`@2 -> `hello` gives `heXllo`). It is not "clamp the old offset" (the
shrink-inside row) and not "end only when the edit is not at the caret" (the extend rows). **With a selection binding
attached** SwiftUI keeps the old offset, clamped (`/com`@4 -> `/comXpact `, `ab cd`@2 -> `abXXY cd`, `hello world`@8 ->
`helX`): the binding is not rewritten by the replacement and wins.
**Ruling.** `TextEditState.seenText` is the text the state last saw: set by every edit, undo and redo (`recording`,
`restored`) and otherwise by the frame. `TextEditing.followExternalText` runs where `reconcile` runs, in the same
compared `withState(unchanged: ==)` of `TextEditor.prepaint`/`TextField.prepaint` (the table of
`everyStateWriteSiteIsClassified` is unchanged: one site, now always taken, the `if selectionWriter != nil` became
`if bound ... else follow`): when `seenText` differs from the text, anchor and head go to the end, the typing group and the
goal column end and the caret is revealed. The first text seen is a baseline (no move). Composition holds the move back as
it does a binding's write (`SL-H`). **Only a focused field follows** (`pass.frame.focusedElement == id`, the pre-clearing
answer, since `PrepaintPass.isFocused` is paint-only): an unfocused field resets `seenText` to `nil`, so a click or Tab that
focuses it after the text changed under it is not a replacement (its press placed the caret; a jump to the end would
override it) and a field that left the tree and returned reads `TextEditState()`
(`aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh` is why). A text replaced while the field is unfocused moves no
caret, and a field then focused from code keeps its stored caret (divergence 265/266 unchanged). Pinned by
`aReplacementWhileAFieldWasUnfocusedDoesNotMoveALaterClick`. No `@Observable` is written; the write is the editor's own state, compared, in the
phase, as the scroll's and the binding reconcile are, and a field's own keystroke writes nothing there (`recording` already
stored `seenText`). **Cost**: an unbound field now takes the compared write each prepaint (one equality test; a change only
on a replacement or the first frame); the undo history is dropped lazily as before (`synced`), so an undo pressed after a
replacement and before any edit still restores the older snapshot (unchanged, and SwiftUI's undo is not measurable, `SL-O`).
A binding that transforms or rejects an edit (a constant binding, a filter) is a replacement too: the caret goes to the end,
as it does in SwiftUI. Pinned by `aReplacedTextPutsTheCaretWhereSwiftUIPutsIt` (13 rows x field and editor),
`aSelectionBindingKeepsTheOldOffsetAcrossAReplacement` (the bound arms), `theFieldsOwnEditsNeverMoveTheCaretToTheEnd` and
`consecutiveReplacementsEachMoveTheCaret`. Mutations in record 241.

## SL-Q — `selectedOffsets`: the selection binding as Character offsets, the macOS 14 spelling

**Question (Alloy G11).** `TextEditing.reconcile` guarded `#available(macOS 15, *)`, so the selection binding did
nothing on macOS 14. **Measured by reading**: the guard is not incidental. `TextSelection` itself is
`@available(macOS 15, *)` (`SL-L`: `Indices.multiSelection(RangeSet<String.Index>)`, `RangeSet` being the standard
library's from macOS 15, and SwiftUI's `TextSelection` is macOS 15 too), so no `TextSelection` value can exist on 14 and the
cast the guard protects is the only thing it protects; the package deploys to macOS 14 (`Package.swift`).
**Ruling.** Keep `TextSelection` as it is and add a MetalUI-only binding with no `RangeSet`:
`TextField(_:text:selectedOffsets:)` and `TextEditor(_:text:selectedOffsets:)` over `Binding<Range<Int>?>`, Character
offsets into the current text, empty is the caret. The erased state already holds any `Hashable`: `reconcile` tries
`Range<Int>` first (no availability question at all) and `TextSelection` behind `#available(macOS 15, *)` second; the
writer returns the `Range<Int>`; everything else (`SL-B`..`SL-J`: echo-free, next-frame apply, `nil` ignored, composition
holds, clamped) is shared. An insertion at the caret is the app editing `text` and writing the caret after it. Negative
bounds clamp to 0. Class M (no divergence: SwiftUI has no such spelling). **Test**: the harness cannot run macOS 14, so
`theOffsetsInitialisersCarryNoAvailabilityGate` reads the sources (no `@available` above the two initialisers, the
offsets cast before the macOS 15 branch), and `ExternalTextCaretTests` is written with no `@available`, so it fails to
compile if either initialiser gains one (mutation checked: "only available in macOS 15 or newer").
