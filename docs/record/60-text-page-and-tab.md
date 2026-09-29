# 60 — Page keys in `TextEditor`, and Tab between inputs, 2026-09-24

**Written as §53** on `feat/text-page` from `0843866`, **renumbered 53→59**
at its merge with `master` at `169d166` (which had already published
§53–§58, stage 10 through plan task 10 part 2), and **renumbered 59→60** at
its merge with `master` at `ff2ae92`, whose plan task 11 part 1 record
(text semantics) had published §59 while this branch's CI ran — the same
shape as record §53's own 52→53 and §48's 42→48, and §42's 40→41→42.
Master's §53 citations are stage 10's and its §59 citations are task 11 part
1's; this file's are §60. The merges are §Merge and §Merge 2 at the end.

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

## Merge with `master` at `169d166` (2026-09-28)

`master` had moved 100+ commits since `0843866`: task 7 stages 10–11, plan
tasks 8, 9 and 10 parts 1–2. Git merged every source file cleanly
(`Window.swift`, `Focus.swift`, `TextEditor.swift`, `TextEditing.swift`); the
conflicts were docs only — `CLAUDE.md`/`AGENTS.md` (master's text kept, this
branch's `TI-I`/`TI-J` rules re-added into its "Focus" and "Text input"
paragraphs, `TI-` next `TI-K`) and `docs/record/README.md` (every row kept,
this file's row renumbered to §59, now §60).

**Key order after the merge**, unchanged in shape: `Keymap` → a focused
field's editing keys (`dispatchTextKey`) → the raw `onKey` bubble
(`dispatchKey`, which is where a control's own keys run — `ControlKeys`,
through the control's `onKey`, after a caller's own declines, `DD-T` item 2) →
Tab traversal (`dispatchFocusTraversal`) → `onInput`. No control's key table
claims Tab, so a focused control passes it on.

**Tab and master's controls — a ruling, amending `TI-J`.** Plan task 10 part
2 made `Button`, `Toggle`, `Slider`, `Stepper`, `Picker` and a selectable
`List` focusable (`DD-T`) and gave each a key table that reads no system
setting (divergence 80). `TI-J`'s rule — Tab visits *every* registered
focusable element — therefore now visits those controls too. **Kept, not
narrowed to text inputs.** AppKit's documented default (keyboard navigation
off) moves Tab only between text fields and lists, and turns on the other
controls under Full Keyboard Access; but `DD-T` item 3 already rules that
MetalUI reads no such setting and a focused control takes its keys
regardless. Narrowing Tab to text inputs would leave those key tables
reachable only through `Window.focus(_:)` or an accessibility client, since a
click focuses no control (bar a selectable `List`). So MetalUI's Tab behaves
as AppKit's does with keyboard navigation **on**, and on Windows and GTK,
whose convention is that Tab visits every control. **This is part of
divergence 80's scope, not a new number**: SwiftUI's own Tab answer is
unmeasured (no probe has sent it Tab; the screen was locked at every
task-10 check), so no SwiftUI claim is made. `DD-T`'s "Cost if wrong"
sentence ("MetalUI has no Tab traversal (task 12)") gains an erratum note in
place. If plan task 12 rules focus to follow the system setting, it filters
`FocusRegistry.tabOrder` by role in one place.

**New test (the merge's own, since neither branch could write it):**
`tabVisitsTheControlsAndAControlItFocusedTakesItsKeys` — a field, a `Button`,
a `Toggle` and a `Slider`: Tab visits all four in order, Space presses the
Tab-focused button and flips the Tab-focused toggle, a focused slider passes
shift-Tab and Tab on, and Tab wraps. **Re-spelled**: this branch's
`FocusTraversalTests` fixture used `.width`/`.height`, deprecated on `master`
since stage 8 (`LR-ES`); both became `.frame` (R2: `.focusable()` after the
frame), clearing the two build warnings the merge introduced.

**Counts** (after `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered `swift test --build-system native --no-parallel`):
`Test run with 1652 tests in 3 suites passed`, the FR-J line present; 0
`error:`; 0 `warning:` under the default build system. **1652 = 1644 + 7 +
1**: master's 1644, this branch's 7, the merge's 1. Guards 100 and goldens 0,
unmoved. `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`) 21 + 23, as on
`master`; its key translation already maps Tab and the page keys
(`SDLPlatform.swift`) and is untouched.

**Mutation** (on the merged tree, `--filter FocusTraversalTests`):
| # | Mutant | Reddens |
|---|---|---|
| MJ1 | traversal moved ahead of the `onKey` bubble (where control keys run) | `anAppsHandlersSeeTabFirstAndAModifiedTabIsNotTraversal` (2 issues) |
| MJ2 | the rejected alternative: Tab order filtered to text inputs | `tabWalksTheFocusableElementsInTreeOrderAndWraps`, `aDisabledFieldIsSkipped`, `tabVisitsTheControlsAndAControlItFocusedTakesItsKeys` (9 issues) |

Both restored; `git diff -- Sources` empty afterwards.

## Merge 2 with `master` at `ff2ae92` (2026-09-28)

`master` published plan task 11 part 1 (text semantics, record §59) while
this branch's CI ran on the first merge (`3807dec`), and the PR read
`CONFLICTING`. Merged again, the same way. Sources merged cleanly, including
`TextEditor.swift`. The conflicts were docs only:
- `CLAUDE.md`/`AGENTS.md`: this branch's counts bullet re-taken, above
  master's.
- `docs/record/04-divergences.md`: master's task-11 section kept, with this
  branch's divergence-80 section after it and the live count read as
  master's **65**.

This file was renumbered 59→60. Only this branch's own §59 citations moved:
the README row, the spec's `TI-J` header and amendment, the §04 section, the
`DD-T` erratum, and `CLAUDE.md`'s Focus paragraph and counts bullet. Master's
§59 citations are task 11's and stay.

**The page keys against task 11's font resolution.** `TextEditor` now
resolves its font through the environment: its own font, else the
environment's, else the default font by `controlSize` (`TE-F` item 2). The
line height the editor hands the page keys (`TextLineModel.lineHeight`) is
the geometry's `g.lineHeight`, and the geometry now takes the resolved face.
So a page is measured in the new default font with no edit.

`pageDownPagesTheEditor` cannot see this. It compares the model's line
height with the target's, and both come from the same geometry. So the
merge adds `aPageIsMeasuredInTheEnvironmentsResolvedFont`: an editor under
`.controlSize(.mini)` (9 pt) has a shorter line, and more lines per page,
than one under `.regular` (13 pt). `.large` would not separate them: it
resolves to 13 pt, as `.regular` does. Mutant MP1 hard-codes a 13-point line
height on the model handed to the page keys; it reddens only the new test
(3 issues).

**Counts:** `Test run with 1715 tests in 3 suites passed`, the FR-J line
present; 0 `error:`; 0 `warning:` under the default build system. **1715 =
1706 + 7 + 1 + 1**: master's 1706, this branch's 7, the first merge's 1 and
this merge's 1. Guards 105 and goldens 0 are master's, unmoved.
`Backends/SDL` 21 + 23.

**Mutations re-run on the merged tree:**
- MJ1 reddens `anAppsHandlersSeeTabFirstAndAModifiedTabIsNotTraversal` (2
  issues).
- MJ2 reddens `tabWalksTheFocusableElementsInTreeOrderAndWraps`,
  `aDisabledFieldIsSkipped` and
  `tabVisitsTheControlsAndAControlItFocusedTakesItsKeys` (9 issues).
- All three mutants were restored; `git diff -- Sources` is empty.
