# Text selection and caret control — decisions

Rulings for item C25 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), requested by MetalCreator (gap CT-b). Prefix `SL-`. Spec:
[`specs/2026-10-12-text-selection-design.md`](specs/2026-10-12-text-selection-design.md). Record:
`../record/96-text-selection.md`. Branch `feat/text-selection` from `0abce86`. Divergence labels
reserved for this branch: 265–274.

SwiftUI's side: `docs/probes/swiftui-text-selection.swift` (arms C, P, R, W, F, S; run twice,
byte-identical; recorded in its header). gpui's side, where SwiftUI has nothing, is recalled
(`EntityInputHandler`, no binding) and rests no ruling.

**Next unused id: `SL-L`.**

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
