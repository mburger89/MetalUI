# 53 — Page keys in `TextEditor`, and Tab between inputs, 2026-09-24

Branch `feat/text-page`, from `master` `0843866`. Rulings `TI-I` (page keys)
and `TI-J` (Tab moves focus), added to
`docs/superpowers/specs/2026-09-23-text-input-design.md` (next `TI-K`).
Follow-ups to `TextEditor` (record §52). The user asked for Tab traversal
while the page keys were in progress, and both land in one branch.

## What changed

- **`TextEditing`:** the page keys (`U+F72C`/`U+F72D`, AppKit's and
  `SDLKeys`'). On a Mac they scroll `scrollY` a page and leave the caret, not
  revealing it. Elsewhere they make a vertical move of `linesPerPage` lines at
  the remembered column.
- **`TextLineModel`:** gains `lineHeight`, `visibleHeight`, `pageHeight`
  (visible − one line, at least one line), `linesPerPage` and `maxScrollY`.
  `TextEditor` sets the two heights on the model it hands the target.
- **`FocusRegistry.tabOrder`:** focusable ids in registration order.
- **`Window.dispatchFocusTraversal`:** runs after the raw `onKey` bubble and
  before `onInput`. Tab and shift-Tab (or `U+0019`) move to the next and
  previous element, wrapping, and command, control or option opts out.
  Tabbing into a text target selects all of its text.

## Measured

- The first page test pressed 2 points into the field and landed after the
  narrow "l", not at 0. It now presses at the left edge; this was a test
  artifact, not a code fault.
- The first `onKey` arm expected a handler to see Tab with nothing focused.
  `onKey` bubbles from the focused element, so with nothing focused it sees
  nothing. That rule predates this change, and the arm now focuses a field
  first.
- The whole suite stayed green with Tab now moving focus by default: no
  existing test relied on an unclaimed Tab reaching `onInput`.

## Counts

1430 tests, 0 goldens, 79 guards; 0 `error:` and 0 new `warning:` on both
build systems after `swift package clean` (`Test run with 1430 tests in 3
suites passed`; the guards ran). **1430 = 1423 + 7**:
- `TextEditingTests` +2;
- `TextEditorTests` +1;
- `FocusTraversalTests` +4.

## Mutations (`--filter FocusTraversalTests|TextEditingTests|TextEditorTests`)

| # | Mutant | Reddens |
|---|---|---|
| P1 | Mac page keys move the caret too | `onAMacPageKeysScrollAndLeaveTheCaret`, `pageDownPagesTheEditor` |
| P2 | a page is the whole visible height | `offApplePageKeysMove…`, `onAMacPageKeys…` |
| P3 | the Mac page scroll is not clamped | `onAMacPageKeys…` |
| P4 | the editor does not hand over its heights | `pageDownPagesTheEditor` |
| J1 | no wrap-around | `tabWalksTheFocusableElementsInTreeOrderAndWraps`, `tabbingIntoAFieldSelectsItsTextAndAnEditorPassesTabOn` |
| J2 | shift ignored | the same two |
| J3 | no select-all on tabbing in | `tabbingIntoAField…` |
| J4 | traversal before the raw `onKey` bubble | **green at first**: the handler claimed only option-Tab, which traversal refuses anyway. A plain Tab the handler claims now reddens `anAppsHandlersSeeTabFirstAndAModifiedTabIsNotTraversal` |
| J5 | modifiers not checked | `anAppsHandlersSeeTabFirst…` |
| J6 | the backtab character ignored | `tabWalks…` |

## Open

- **Human looks:**
  - Tab and shift-Tab through the text-input demo on AppKit and on SDL;
    AppKit's input context re-delivers Tab through `doCommand(insertTab:)`.
  - Page keys on a Mac keyboard (fn-↑/↓) and on a PC keyboard.
- **Not built:**
  - a visible focus ring by default — `focusBorder` stays opt-in;
  - SwiftUI's `focusable(interactions:)` scoping of which elements Tab
    visits;
  - Tab order overrides.
