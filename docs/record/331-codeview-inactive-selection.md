# 331 - `CodeTheme.inactiveSelection` (`CV-BB`)

Branch `feat/codeview-inactive-selection` from master `c625d565`. Class M, no divergence (follows AppKit). Alloy request: with two split editors of one buffer the selections of both look alike, so the focus is hard to find.

**Probe.** `docs/probes/appkit-inactive-selection.swift` (recorded in its foot): `NSColor.unemphasizedSelectedTextBackgroundColor` is #DCDCDC light and #464646 dark (`selectedTextBackgroundColor` #B3D7FF / #3F638B). The pixel part of the probe could not measure `NSTextView` itself: the script process never became the active application, so the text view painted its unemphasized fill in all three states; the system colours are exact and are what the defaults use.

**What landed.** `CodeTheme.inactiveSelection` (initialiser parameter last, so existing calls compile), `CodeTheme.defaultInactiveSelection`. `CodeViewPlan.windowIsKey` (from `environment.controlActiveState == .key`) and the paint pass choose `theme.selection` when `windowIsKey && pass.isFocused(id)`, else `theme.inactiveSelection`. Rule: `CV-BB`.

**Redraw path.** Nothing new: the window already redraws on a focus change and on a control-state change, and the colour is read at paint. Test 4 drives `.inactive`, `.active` (not key) and `.key`; test 3 moves the focus between two splits.

**Steady-frame cost.** Zero, literals identical on master c625d565 (a reverted choice, unconditional `theme.selection`, gives the same numbers): one retained card 4 requests / 0 hits / 1 miss / 0 ineligible, two 5 / 1 / 1 / 0, with and without the focus. A focus move between three retained views leaves the third a hit.

**Tests** (`Tests/MetalUITestingTests/CodeViewInactiveSelectionTests.swift`), each with its mutation in its doc comment. Shown failing: unconditional `theme.selection` fails tests 1 to 6 (7 and 8 stay green, as they must); dropping `windowIsKey` fails test 4 only; an extra wrapper element fails test 7 (4 becomes 5).

**Limits.** The window is "not key" when `controlActiveState != .key`; a view in a key window whose focus is elsewhere in the window (a text field, another split) is inactive too.
