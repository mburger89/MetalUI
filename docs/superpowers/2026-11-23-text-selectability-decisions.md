# `Text` selection: decisions (`TXS-`)

Alloy's request: a plugin's stderr log (up to 64 KiB) is a `Text` in a disclosure and users must drag-select it and copy it.
SwiftUI's `View.textSelection(_:)` with `TextSelectability` (`.enabled` / `.disabled`). Design:
`docs/superpowers/specs/2026-11-23-text-selectability-design.md`. Probe: `docs/probes/swiftui-text-selection-enabled.swift`
(recorded 2026-11-23, macOS 27.2.1; arm ids below are its). Prefix `TXS-` (new; the table row is in
`docs/rules/decision-prefixes.md`). Class: API class A, behaviour class D (divergences from label 244, pending the build).

Next unused ruling: `TXS-J`.

## What the probe could and could not measure (read first)

A selectable SwiftUI `Text` is an AppKit view, `SwiftUI.AppKitTextInteractionView` (an `NSTextInteraction` host, a real first
responder). **No synthetic pointer event made it select**, on any route tried (probe header, INSTRUMENT 4: the events reach its
`mouseDown:`, its gesture recognisers never act, and `CGEventPost` needs a grant). So every arm that needs a pointer to
select is NOT MEASURED and is a human check (list at the end): drag, double click, triple click, right-click on a word,
click-to-focus, click-to-clear, and whether a real click fires an `onTapGesture` or opens a link. What WAS measured is what an
assistive client does: the selection set with `setAccessibilitySelectedTextRange:`, first responder moved with
`makeFirstResponder`, and everything downstream driven by the real `⌘C` / `⌘A` keys, the real Edit menu, the real pasteboard
and the AX tree (arms marked PROXY). A ruling below resting only on a PROXY or synthetic arm says so and names its human check.

**Where a result changed the draft design it is marked `CHANGED FROM DRAFT` and quotes the arm.** Rulings with no such mark
stand as drafted (some now carry a measured confirmation).

## TXS-A: the API (ruled, as drafted)

`protocol TextSelectability { static var allowsSelection: Bool { get } }`, `EnabledTextSelectability`,
`DisabledTextSelectability`, `static var enabled` / `.disabled` (`where Self ==`),
`ElementGroup.textSelection<S: TextSelectability>(_:) -> EnvironmentScope<Self>` writing an **internal** stored `Bool`
`textSelectionEnabled` on `EnvironmentValues` (SwiftUI publishes no key), following `textFieldStyle`; added to
`EnvironmentFingerprint`. Class A; inventory rows and doc comments.

Inheritance and the nearest-wins rule are **measured**: E0 every `Text` below `.enabled` owns a selection view in a VStack,
HStack, Group, ZStack, ScrollView, a `Label`'s title, a `.bold().padding()` Text, a markdown-link Text, a concatenated
`Text + Text` (one view), a List row, a Form row, and a Text in `.overlay` and in `.background` (E0e; 10 Texts, 9 views). A
`Button`'s label Text gets none (E0: nine selection views, the button publishes `AXButton`). E1 an inner `.disabled` removes
the view (2 of 3); E1b an inner `.enabled` under an outer `.disabled` gives one. A plain Text with no modifier has none
(E0c). Not measured: whether `.disabled(true)` / `.allowsHitTesting(false)` / `.opacity(0)` on the Text stop a pointer
selecting; in all three the selection view still exists (E1c, E1d, E1e).

## TXS-B: state and focus (ruled; the focus half pending HC-TXS-1)

One `TextSelectionSession?` on `Window` (`id: GlobalElementID`, a `TextEditState`, the string, lazily built geometry), never
`StateTable`. `Text.prepaint` reads `frame.environmentTop.textSelectionEnabled` directly. SB-X extended:
`retainedSubtreeHasPointerPressOrFocus` returns true for a subtree holding the selected Text. As drafted.

Focus, **measured**: the selection view `acceptsFirstResponder` and `canBecomeKeyView` (F0), `⌘C` copies only when it is first
responder (D1q: a range set while the Text is not focused leaves Edit > Copy off and the pasteboard untouched), and a focused
`TextField` keeps `⌘C` until the Text takes focus: F1p field focused, the Text's range set by AX, `⌘C` copies the FIELD
(`'fieldtext'`) and the field keeps `@FocusState`; F1q once the Text IS made first responder the field's `@FocusState` goes
`false` and `⌘C` copies the Text (`'sel'`). It is **not a Tab stop** (F2 = control F2c: Tab and Shift-Tab alternate the two
fields exactly as with a plain Text; F2b: with a selectable Text and a Button nothing takes focus; Full Keyboard Access off,
`fka=false`).

**CHANGED FROM DRAFT (the draft said "if SwiftUI gives the Text key focus, it takes focus without being a Tab stop or initial
seat").** F0 + F1q say it does take focus when focused, F2 says never by Tab. What a CLICK does (F1, A1d: the synthetic click
left the field editor first responder) is NOT MEASURED. Ruling, provisional: **a primary press on a selectable Text, and
only that, moves focus: the focused element (a field) is blurred (`FW-`/`FC-` blur, no element takes focus), the session
becomes the target of `⌘C` / `⌘A` / Edit > Copy; the Text is never focusable by Tab and never an initial seat (`FC-E`).** This
is one line in the window stage (the blur) over the fallback design the draft already had ("⌘C / ⌘A as a fallback after the
focus chain declines"); with no focused element the two read the same. If HC-TXS-1 shows a click does NOT take focus from a
field, delete the blur and keep the draft (the field keeps `⌘C` while the Text keeps its selection, the pre-probe design).

## TXS-C: registration (ruled; one condition CHANGED)

When enabled and the frame is enabled with hit testing on, `Text.prepaint` inserts one opaque hitbox with empty `Handlers()`
and appends `SelectableTextRegion(id, glyphBox, textValue)` to a frame array reserved from last frame's count (no class box;
`Handlers` unchanged). Prepaint replay carries it via the prepaint log (as context menus do).

**CHANGED FROM DRAFT (the draft: "A Text with its own pointer handlers is skipped (pending G1)").** Measured, G3: the hit-test
view over a selectable Text IS the selection view, also with an `onTapGesture` on it. G1, G1e: a single click on a
selectable Text with its own `onTapGesture` does not fire the tap (0.8 s wait, so not the double-click delay); G2, G2d: an
ancestor's tap does not fire when the click lands on the text, G2b it does off the text; the controls fire (G1f, G2e); G1c a
double click fires the Text's tap once. **Ruling: no skip. The selection hitbox is opaque and wins over a tap on the Text or an
ancestor, exactly as the opaque hitbox of any element does in MetalUI; that is the measured G2 shape and G1's.** Not measured: whether a REAL click fires the tap
(the synthetic one reaches the selection view's gesture recognisers, which also select nothing, so the swallowing may be the
instrument's: HC-TXS-4). If it does fire, a Text with its own pointer handlers (the `ElementGroup` wrapper's handler on the
same element) is the case to skip, as the draft said.

## TXS-D: geometry (ruled, as drafted)

Built at press time: `system.measure(StyledText, wrappingAt:, options:)` -> `TextLineBox` ranges, tops, `offsetX`;
`Text.glyphBox` origin/width; per-line `caretOffsets` (styled runs concatenated per run); UTF-16 -> grapheme via a monotonic
cursor (not `TextEditor.lineModel`, which is quadratic); cached by (width, height, string); then `TextEditing.press`/`drag`.
**T1 measured:** a `lineLimit(1)` Text truncated at 60 pt selects and copies its WHOLE string, not the visible part: `⌘A` then
`⌘C` pastes all 35 characters, the AX value and `AXNumberOfCharacters` are the whole string, the AX visible range is
`{0, 35}` (T1, T1b). The range is over the string; the highlight is drawn only on the lines that exist (the draft's per-line
rects). Word / line / paragraph units for a double and a triple click (D2, D3, D3b) are NOT MEASURED (HC-TXS-2); keep the
draft's `TextEditing.wordRange` for a double click and the line (visual line, then paragraph on a second pass) as the
**provisional** triple-click unit, to be fixed by the check.

## TXS-E: commands and the context menu (ruled; two items CHANGED)

`⌘C` / `⌘A` as a fallback after the focus chain declines (`dispatchClipboardKey`); `chainClipboardCommands` adds `.copy` and
select-all so Edit > Copy and Edit > Select All enable.

- **Copy** enables with a non-empty range and the Text focused (D1p: Copy off with no range, on with one; `⌘C` pastes exactly
  the range, `'alpha bet'`); off while the Text is not focused (D1q). Matches the draft.
- **CHANGED FROM DRAFT (the draft added select-all "while the session is non-empty").** D1p: **Select All is enabled while the
  Text is focused even with no range** (`Copy=off/Select All=on`), and D1q off while it is not. So the session exists from a
  press, and Select All is on for as long as it does, empty or not.
- **`⌘A` selects all of that Text only** (A1: Text A focused -> `0+12 / none`, pastes `'first text A'`; A1c with B focused
  selects B). With nothing focused it does nothing (A1b). Matches the draft ("the whole of that Text only").
- **Right-click, CHANGED FROM DRAFT.** The draft: a region with no declared `.contextMenu` gets an input-time menu with Copy.
  M1/M1b/M1d/M1h: SwiftUI's menu is the full text-editing menu of an `NSTextInteraction`: with no selection
  `[(Cut)|(Copy)|(Paste)|(Paste and Match Style)|-|Font|-|Spelling and Grammar|Substitutions|Transformations|Speech|Writing
  Direction|Layout Orientation]`, with one `[Look Up "alpha"|Translate "alpha"|-|Search With Google|-|(Cut)|Copy|(Paste)|
  (Paste and Match Style)|-|Share...|-|Font|...]` (parentheses: disabled). **M1e: a declared `.contextMenu { Button("Mine") }`
  on a selectable Text is NOT shown; the text menu replaces it** (a plain Text has no menu, M1f). **Ruling: MetalUI offers
  `[Copy, Select All]` (Copy disabled with no range) and a declared `.contextMenu` WINS over it** (a declared menu is the app's
  intent, and MetalUI's menus are the app's). Divergences: the menu's other items (Look Up, Translate, Search, Share, Font...)
  are absent; a declared `.contextMenu` replaces SwiftUI's text menu where SwiftUI's replaces the declared one. Whether a real
  right-click selects the word under it is NOT MEASURED (M1d, M1h: the synthetic one left the range as it was; HC-TXS-3);
  provisional: it does not, until the check.

## TXS-F: the window stage and paint (ruled; the clearing rule CHANGED)

`dispatchTextSelection` right after `dispatchTextInput`: a press over a region starts or updates the session, then
`TextEditing.press`/`drag` as drafted.

**CHANGED FROM DRAFT (the draft: "a primary press elsewhere clears it (pending C1-C3)").** Measured: **a selectable Text that
stops being first responder loses its selection; the selection is CLEARED, not kept inactive.** C2 the TextField focused ->
A's AX range `none`, `⌘C` copies nothing; C3 (PROXY) another selectable Text made first responder -> A `none`; C6 first
responder cleared -> `none`; C2b refocusing A does not bring the range back. Where focus does NOT leave, the selection stays:
C1 a click on empty space changes neither first responder nor range (synthetic; the Text's own click gesture is not driven,
HC-TXS-5); C5b the window really resigning key keeps responder and range (so the active/inactive colour of the draft's paint
rule is the only difference, and the colour is NOT MEASURED, HC-TXS-6); C3b two Texts both given a range by AX without a focus
move both hold it (an AX client only). **Ruling: the session is dropped when focus moves to an element, when another
selectable Text is pressed, when the Text leaves the tree, and on a string change; it is KEPT on a press on empty space or
a non-focusable element and when the window loses key.** Window-not-key keeps the session and paints the inactive colour.
There is therefore no "clears where SwiftUI greys" divergence (the draft's second divergence bullet is dropped).

**String change while selected (S1), CHANGED FROM DRAFT's wording, kept in effect.** SwiftUI: the AX range reads `none`, the
view is reused, but `⌘C` copies the OLD range applied to the NEW string (S1 `'ALPHA B'`, S1c `'alpha b'`), Edit > Copy stays
on, and **a string shorter than the old range aborts the process on `⌘C`** (S1b/S1d via S1x, S1y: exit 6,
`NSRangeException` in `attributedSubstringFromRange:` under `-[NSTextInteraction copy:]`). Ruling: **MetalUI drops the
session when its string changes** (the draft's "drop the session if its string changed"), never clamps, never crashes. New
divergence (SwiftUI keeps a stale range and aborts on a shrink).

Double and triple click units, the drag, the caret-less press: see TXS-D and HC-TXS-2. Paint, as drafted: only for the
selected id, per-line rects before glyphs in `paintGlyphs`: `Color.accentColor.opacity(0.3)` (as `MultilineText`), the inactive
colour when the window is not key.

## TXS-G: accessibility (ruled; two items CHANGED)

`selectedTextRange: Range<Int>?` (UTF-16) on `AccessibilityNode` / `AXEmission`, set only while a client collects
(`withAccessibilitySuppressed`); AppKit answers `accessibilitySelectedTextRange`, `accessibilitySelectedText`,
`accessibilityNumberOfCharacters`. AccessKit needs `TextRun` children: a divergence. As drafted, with measured shapes (X1):

- The role stays `AXStaticText` (X1, X1d: the same as a plain Text).
- **CHANGED FROM DRAFT (the draft: set only for the selected Text).** A **selectable** Text answers the three text-area
  attributes **even with no selection**: X1 before any selection `AXSelectedTextRange` = `{NSNotFound, 0}`, `AXSelectedText` =
  `''`, `AXNumberOfCharacters` = 16; after a range 0+7: `{0, 7}`, `'alpha b'`; after `⌘A`: `{0, 16}`, the whole string (X1b,
  X1c). A plain Text publishes none of the three (X1d). So the node carries an `isSelectable` flag (or the optional range plus
  a "selectable" bit), and the AppKit bridge answers the three for every selectable Text, `NSNotFound` when no range.
- **CHANGED FROM DRAFT (new).** SwiftUI's element is one `AXStaticText` holding the selection attributes with an inner
  `AXStaticText` child of the same value (X1); MetalUI publishes one node: not a label-worthy difference. The element also
  answers `accessibilityRangeForLine:`, `accessibilityLineForIndex:`, `accessibilityStringForRange:` and a settable
  `accessibilitySelectedTextRange` (X1e); `accessibilityFrameForRange:` answered a zero rect (X1f). **MetalUI does not offer a
  settable selection to AX clients** (carried; divergence, as `SL-` ruled for fields): the built-in set is read-only.
- AccessKit publishes no selection for a selectable `Text` (`text_selection` needs `TextRun` children): divergence, as
  drafted.

## TXS-H: cost contract (ruled, as drafted)

- No modifier: one environment field load and branch in `Text.prepaint`; no hitbox, append, StateTable entry or AX field;
  fingerprints equal; the new stage returns early when no regions and no session. `FrameWork` identical.
- Enabled, idle: element requests + the modifier's layer, + one hitbox per Text; allocations do not grow with N.
- Selected, idle: one Text fills K rects from cached geometry; its occurrence misses retained replay, as a focused element does.

(64 KiB: `Text` already measures and places every glyph each paint with or without this feature; selection adds one geometry
build per press.)

## TXS-I: what the build ruled (record 399)

The probe fixed the behaviour; the build fixed these shapes, each marked where it differs from the design text.

1. **The region carries no geometry and no closure** (changes TXS-D's "built at press time"). A `SelectableTextRegion` is the
   element id, the index of its hitbox and its string; an idle selectable `Text` therefore adds one hitbox and one array
   entry, no allocation (TXS-H). The press is recorded in the session with its point in the `Text`'s local space (the
   hitbox's `elementLocalPoint`, the glyph box's origin being the hitbox's) and **applied at the first prepaint of the
   pressed `Text`**, which has its environment and the frame's text system; a drag after that applies at once against the
   cached geometry. A harness `click`, `drag` and `doubleClick` each draw a frame, so a test sees the result.
2. **The selection hitbox shares the `Text`'s own id** (no `$select` child): a press there finds no handler on the topmost
   hitbox, so no click fires; it is registered inside the decoration's scope after the `Text`'s own hitbox, so it ranks above
   it and above an ancestor's. The rule that a `Text` with handlers of its own would skip registration is one function,
   `Frame.skipsRegistration(forHandlers:)`, returning `false` until `HC-TXS-4` says otherwise.
3. **A selectable `Text` leaves no prepaint ledger.** Its occurrence's prepaint is refused (`prepaintLog.taint("textSelection")`):
   the region array is not a journal channel and replaying the hitbox alone would orphan the region. Its paint record still
   replays while nothing is selected; `retainedSubtreeHasPointerPressOrFocus` is true for a subtree holding the selected `Text`
   (`Frame.textSelection`), so the selected occurrence paints in full and the highlight is never replayed. No `withState` write
   is made anywhere (the session is on `Window`).
4. **One string read.** A selectable `Text` reads its string once in `prepaint`; every other `Text` reads it exactly as before.
5. **A triple click selects the visual line and a fourth click the paragraph** (provisional, `HC-TXS-2`); a drag after a
   triple click moves the head from the line's start.
6. **Select All is a clipboard command.** `ClipboardCommands.selectAll` (the platform seam) is sent while the session exists,
   `.copy` while it has a range; AppKit's Edit > Select All and the drawn menu bar read it (`TXS-E`).
7. **The session ends** on a focus move to an element (the `focusedElement` observer), on a press on another selectable `Text`,
   when the frame did not produce its `Text` with its string (`Window.settleTextSelection`, run after each adopted frame).
   A string change drops it in the `Text`'s own prepaint, the same frame it is painted.
8. **The accessibility state is one field**, `AccessibilityNode.textSelection: AccessibilityTextSelection?` (non-nil: the node
   answers the three text-area attributes; its `range` is nil with nothing selected), carried on the record
   (`AXEmission.textSelection`) like a table's, so `AXNode` and `Handlers` keep their sizes. AppKit answers the three
   attributes read-only (a client cannot set the selection, divergence 1127); AccessKit publishes nothing (1125).
9. **The inactive colour** is `.separator`, the accent at 0.3 in a key window; neither is measured (`HC-TXS-6`).
10. **No pointer cursor is declared** (`HC-TXS-8`): the I-beam row of `docs/divergences.md`'s absences names the selectable `Text`.

## Divergences this implies (labels 1125-1128, written at the build; 245-248 were already live, so the block is TXS's own)

1. AccessKit publishes no selection for a selectable `Text` (as drafted).
2. The right-click menu is `[Copy, Select All]` and a declared `.contextMenu` wins; SwiftUI's is the full text-editing menu and
   replaces a declared one (TXS-E).
3. A string change drops the selection; SwiftUI keeps a stale range and aborts on a shrink (TXS-F).
4. AX clients cannot set the selection (TXS-G).
5. Pending HC-TXS-4: a link in a selectable `Text` opens on a click and a tap on a selectable `Text` fires (LK13:
   L1 confirms in the instrument that a single click on the link does NOT open, a double click opens once, with the same
   instrument that cannot select; the control opens).
6. Amend the I-beam row to include the selectable Text (cursor NOT MEASURED, HC-TXS-8).
7. Dropped from the draft: "a click elsewhere clears where SwiftUI greys" (the measured clear-on-focus-loss agrees, TXS-F).

## Carried: the human checks this probe could not make (to become group TXS in `docs/verification/human-checks.md` with task 8)

By hand, in a SwiftUI app with `Text("...").textSelection(.enabled)` (a long multi-line string, a link, a field):

- **HC-TXS-1 (F1):** a TextField focused; click a selectable Text. Does the field keep its caret/focus? Does `⌘C` copy the field or
  the Text? (TXS-B's blur rule.)
- **HC-TXS-2 (D1-D3, A1d):** drag selects and `⌘C` copies it; a double click selects a word; a triple click selects what (visual
  line, paragraph)? Does a drag after a double click extend by word? A click on the text then `⌘A`: whole Text only?
- **HC-TXS-3 (M1):** a right-click on an unselected word: does it select the word? What does the menu offer?
- **HC-TXS-4 (G1, G2, L1):** a tap or a link on a selectable Text: does a single click fire the tap / open the link? Does a drag
  select without firing it?
- **HC-TXS-5 (C1):** select, then click empty space: still selected? Click a TextField / another selectable Text: cleared?
- **HC-TXS-6 (C5):** the selection colour when the window (and the app) is not key: active, inactive grey, or cleared?
- **HC-TXS-7 (E1c, E1d):** `.disabled(true)` and `.allowsHitTesting(false)` on a selectable Text: does a drag still select?
- **HC-TXS-8:** the I-beam cursor over a selectable Text; Full Keyboard Access on: is the Text a Tab stop (F2)?
