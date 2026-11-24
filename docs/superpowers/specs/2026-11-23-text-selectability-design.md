# `textSelection(_:)` on `Text` — design (probe recorded 2026-11-23; rulings in `2026-11-23-text-selectability-decisions.md`)

**Why:** Alloy shows a plugin's stderr log (≤ 64 KiB) as a `Text` in a disclosure; users must drag-select and ⌘C it. `CodeView` read-only is too heavy. SwiftUI's `View.textSelection(_:)` with `TextSelectability` (`.enabled` / `.disabled`). Requirements: drag selects, ⌘C copies, accessibility exposes the selection, zero cost when idle or unselected. New prefix `TXS-` (own decisions doc). Status: **the probe (task 1) is recorded** (`docs/probes/swiftui-text-selection-enabled.swift`); the rulings are `docs/superpowers/2026-11-23-text-selectability-decisions.md` (`TXS-A`..`TXS-H`) and win over this text where they differ (each change is marked there `CHANGED FROM DRAFT`). The probe's synthetic pointer cannot make a selectable `Text` select, so every arm that needs a pointer is a human check (HC-TXS-1..8, end of the decisions doc); the bullets below say which.

Existing traces: probe arm `LK13` (`docs/probes/swiftui-text-links.swift`; a link click under `.textSelection(.enabled)` did not open in the instrument; human check `LI4`). `SelectionDemo` is the field binding (SL-) only. Reuse `TextEditState`, `TextEditing.press`/`drag`/`wordRange`, `TextLineModel`, `caretOffsets` — not CodeView's `CodeEditSession`.

## SwiftUI semantics (macOS) — probed 2026-11-23

A selectable `Text` is an AppKit view (`AppKitTextInteractionView`, an `NSTextInteraction` host, a real first responder). Measured
(arm ids are the probe's; PROXY = the selection set through the accessibility API, never by a pointer):
- **E0/E1:** inherited by every `Text` below (stacks, Group, ScrollView, `Label`, List and Form rows, overlay, background,
  concatenated and markdown Texts); a `Button` label gets none; an inner `.disabled` removes it, an inner `.enabled` under an outer
  `.disabled` gives it.
- **D1p/D1q, A1:** `⌘C` copies exactly the range and only while the Text is first responder; Edit > Copy is off with no range,
  Select All is on whenever the Text is focused; `⌘A` selects all of that Text only, nothing when nothing is focused.
- **F0-F2, F1p/F1q:** accepts first responder and key-view status, **not a Tab stop** (Full Keyboard Access off); a focused field
  keeps `⌘C` until the Text is made first responder, which sets the field's `@FocusState` false. A click's effect: HC-TXS-1.
- **C1-C6:** the selection is **cleared** when the Text stops being first responder (field, another Text, responder cleared);
  kept on a click on empty space (synthetic) and when the window resigns key. Colour: HC-TXS-6.
- **M1:** right-click gives the full text-editing menu (Look Up, Translate, Search With Google, Cut/Copy/Paste, Share, Font...),
  **replacing** a declared `.contextMenu`; a plain `Text` has no menu. Word selection by right-click: HC-TXS-3.
- **S1:** a string change leaves a stale range that `⌘C` applies to the new string; a shorter string **aborts the process**.
- **T1:** a truncated Text selects and copies its whole string.
- **G1-G3, L1:** the hit-test view is the selection view; a single synthetic click fires no tap (own or ancestor) and opens no
  link, a double click fires/opens once (the instrument also selects nothing: HC-TXS-4).
- **X1:** `AXStaticText`; the three text-area attributes exist on every selectable Text (`AXSelectedTextRange` `{NSNotFound,0}`
  with no selection), none on a plain Text.
- **D1-D3 (drag, word, triple click unit):** NOT MEASURED, HC-TXS-2. The I-beam: HC-TXS-8.

## API (TXS-A)

`protocol TextSelectability { static var allowsSelection: Bool { get } }`, `EnabledTextSelectability`, `DisabledTextSelectability`, `static var enabled` / `.disabled` (`where Self ==`), `ElementGroup.textSelection<S: TextSelectability>(_:) -> EnvironmentScope<Self>` writing an **internal** stored `Bool` `textSelectionEnabled` on `EnvironmentValues` (SwiftUI publishes no key), following `textFieldStyle` (`TextFieldStyle.swift`). Added to `EnvironmentFingerprint` (the Mirror guard enforces it). Class A; inventory rows and doc comments.

## Mechanism

- **TXS-B, state:** one `TextSelectionSession?` on `Window` (`id: GlobalElementID`, a `TextEditState`, the string, lazily built geometry) — never `StateTable` (a read creates an entry; snapshots are counted). `Text.prepaint` reads `frame.environmentTop.textSelectionEnabled` directly. SB-X extended: `retainedSubtreeHasPointerPressOrFocus` returns true for a subtree holding the selected Text, so it never replays or records while selected. **F1/F2 (TXS-B, CHANGED):** the Text is a first responder but never a Tab stop or initial seat (`FC-E`); a press on it blurs a focused field (provisional, HC-TXS-1) and the session takes `⌘C`/`⌘A`.
- **TXS-C, registration:** when enabled and the frame is enabled with hit testing on, `Text.prepaint` inserts one opaque hitbox with empty `Handlers()` and appends `SelectableTextRegion(id, glyphBox, textValue)` to a frame array reserved from last frame's count (no class box; `Handlers` unchanged). Prepaint replay carries it via the prepaint log (as context menus do). **G1/G2 (TXS-C, CHANGED):** no skip for a Text with its own tap: the opaque selection hitbox wins over a tap on the Text or an ancestor (measured, G1/G2; a real click: HC-TXS-4).
- **TXS-D, geometry:** built at press time: `system.measure(StyledText, wrappingAt:, options:)` → `TextLineBox` ranges, tops, `offsetX`; `Text.glyphBox` origin/width; per-line `caretOffsets` (styled runs: concatenated per run); UTF-16 → grapheme via a monotonic cursor (not `TextEditor.lineModel`, which is quadratic). Cached by (width, height, string). Then `TextEditing.press`/`drag`.
- **Window stage** `dispatchTextSelection` right after `dispatchTextInput`: press over a region starts/updates the session; **C1-C3 (TXS-F, CHANGED):** the session is dropped when focus moves to an element or another selectable Text is pressed, kept on a press on empty space or a non-focusable element and when the window loses key (not cleared on every outside press); after a frame, drop the session if its id was not produced or its string changed (**S1**, measured: SwiftUI keeps a stale range and aborts on a shrink). Double/triple click units per *D2/D3*: HC-TXS-2, provisional word / visual line.
- **Paint:** only for the selected id, per-line rects before glyphs in `paintGlyphs`: `Color.accentColor.opacity(0.3)` (as `MultilineText`), inactive colour when the window is not key.
- **TXS-E, commands:** ⌘C / ⌘A as a fallback after the focus chain declines (`dispatchClipboardKey`); `chainClipboardCommands` adds `.copy` while the range is non-empty and select-all while the session exists even when empty (**D1p, CHANGED**) so Edit › Copy / Select All enable; right-click on a region gets an input-time `[Copy, Select All]` menu, and **a declared `.contextMenu` wins** (**M1/M1e, CHANGED**: SwiftUI shows its full text-editing menu and replaces a declared one).
- **TXS-G, accessibility:** `selectedTextRange: Range<Int>?` (UTF-16) on `AccessibilityNode`/`AXEmission`, set while a client collects (`withAccessibilitySuppressed`), and **every selectable Text answers the three text-area attributes, `NSNotFound` with no range** (**X1, CHANGED**; the range itself only for the selected Text); AppKit answers `accessibilitySelectedTextRange`, `accessibilitySelectedText`, `accessibilityNumberOfCharacters`. AccessKit needs `TextRun` children: a divergence.
- **64 KiB:** `Text` already measures and places every glyph each paint (no culling) with or without this feature; Alloy should keep the log under `.equatable()`. Selection adds one geometry build per press.

## TXS-H, cost contract

- No modifier: one environment field load and branch in `Text.prepaint`; no hitbox, append, StateTable entry or AX field; fingerprints equal; the new stage returns early when no regions and no session. `FrameWork` identical.
- Enabled, idle: element requests + the modifier's layer, + one hitbox per Text; allocations do not grow with N.
- Selected, idle: one Text fills K rects from cached geometry; its occurrence misses retained replay, as a focused element does.

## Divergences (from 244; reserved at the build, listed in the decisions doc)

- AccessKit publishes no selection for a selectable `Text` (`text_selection` needs `TextRun` children).
- The right-click menu is `[Copy, Select All]` and a declared `.contextMenu` wins (SwiftUI: the full text menu, replacing a declared one).
- A string change drops the selection (SwiftUI keeps a stale range and aborts on a shrink).
- AX clients cannot set the selection.
- Pending HC-TXS-4: a link in a selectable Text opens on click (LK13/L1: not on a single synthetic click).
- Amend the I-beam row to include the selectable Text.
- Dropped: "a click elsewhere clears where SwiftUI greys" (C1–C6: SwiftUI clears on focus loss too).

## Tests

`harnessWindow`, `Modifiers.primary`, `runUntilIdle()` then `tick()`, sum `FrameWork`; triple-click as a raw `mouseDown` with `clickCount: 3`.
`aTextWithoutTextSelectionCostsWhatItCost`, `anEnabledIdleTextCostsOneHitboxAndTheModifierLayer`, `aSelectedIdleTextFillsOnlyItsRects`, `dragSelectsAndPrimaryCCopies`, `doubleClickSelectsAWord`, `selectAllSelectsOnlyThatText`, `focusLeavingTheTextDropsTheSelection`, `aPressOnEmptySpaceKeepsTheSelection`, `aPressOnTheTextBlursAFocusedField` (HC-TXS-1), `aStringChangeDropsTheSelection`, `aSelectableTextWithATapSelectsAndDoesNotFireIt` (HC-TXS-4), `aDeclaredContextMenuWinsOverTheCopyMenu`, `editCopyIsEnabledWhileSelected`, `innerDisabledWins`, `aRetainedSubtreeRepaintsTheHighlight`, `theSelectedTextPublishesItsRange`, plus parity arms in `everyAccessibilityNodeFieldHasAnAppKitArm` and `everyAccessibilityNodeFieldHasAnAccessKitArm` (asserting the documented absence). Each with a mutation that must turn it red.

## Tasks (one PR)

1. Probe + recording + decisions doc — **done 2026-11-23** (`TXS-A`..`TXS-H`; results amended the rulings above, marked in the decisions doc).
2. API + environment + fingerprint + inventory.
3. `SelectableTextGeometry` (`make(text:style:box:system:)`, `boundary(at:)`), pure tests incl. alignment, wrapping, 64 KiB timing sanity.
4. Registration + cost tests.
5. Window stage: press/drag/clear, ⌘C/⌘A, commands, context menu, SB-X.
6. Highlight paint.
7. Accessibility field, AppKit, parity arms, AccessKit divergence.
8. Paperwork: divergences, rules shard, record, CLAUDE.md counts.

Out of scope: `ProposalText` (Markdown) — follow-up with the same helper.
