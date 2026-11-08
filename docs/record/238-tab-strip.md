# Record 238: the tab strip (Alloy gap G4)

Branch `feat/tab-strip` (master `7523f587`). Rulings `TBS-A`..`TBS-I` in `docs/superpowers/2026-11-07-tab-strip-decisions.md` (new prefix; next `TBS-J`). Class `M`; no divergence added.

## 1. What was asked and built

Alloy's editor needs a native-looking closable tab bar for its file panel. `Sources/MetalUI/TabStrip.swift`: `TabStrip<ID>(selection:tabs:)` with `.onCloseTab` and `.onMoveTab`, `TabStripItem<ID>(id:title:icon:isDirty:isClosable:accent:)`, the internal `TabStripTab`, `TabStripLabel`, `TabStripCloseSlot` components, `TabStripWidthLayout` (a `ProposalLayout`) and `TabStripMetrics`. Built from existing views: a horizontal `ProposalScrollView` in a `ScrollViewReader`; gestures for select, middle-click close and drag reorder. `Image.isSameDrawing(as:)` (internal) is the icon's equality. No new platform requirement, `Handlers` member, accessibility role or seam. Demo: `METALUI_TABS_DEMO=1` (`TabStripDemo.swift`), built by `buildTheTabStripDemo()` in its own `@inline(never)` frame.

API as agreed, with two readings fixed here: `onMoveTab`'s `to` is the index **after** the move (`insert(remove(at: from), at: to)`), and `onCloseTab` closes nothing (the app removes the tab and moves the selection).

## 2. Findings along the way

- **A flexible frame is the wrong clamp.** `.frame(minWidth: 96, maxWidth: 220)` on the tab clamped the frame and let the title overflow it: the horizontal scroller proposes no width, the child measures its natural width, and the dirty dot landed 100 points outside its tab. `TabStripWidthLayout` measures the content's natural width, clamps it and lays the content out at the clamped width, so the title truncates.
- A button's accessibility frame is its label, not its tab: the close slot lies 18 points past it. A test that clicks a slot takes `frame.maxX + 9`.
- One tab body in a single builder did not type-check in reasonable time; the label and the slot are components of their own.
- `@State` in a component reads through a shadowing `let`; the write goes through `$state` captured as a binding before the closures.
- A demo component that reads an `@Observable` model traps on the 1 MB test thread; only the demo's root is built there (as the Markdown transcript's).
- There is no way to stop the harness mid-drag, so the drag marker is read in `onMoveTab`, which runs at the release before the next frame.
- A drag of 3 points against a slop of 4 or of 0 is indistinguishable in a test (the tap wins under the tap slop and a drag that ends where it began reports nothing): mutation M19 survives as an equivalent mutant.

## 3. Tests

`Tests/MetalUITestingTests/TabStripTests.swift` (15), portable (plain imports, `harnessTextSystem`); run under `METALUI_VERIFY_RETAINED=1` too.

## 4. Mutations (each alone, in place after the commit, restored with `git checkout`; filtered run `--filter TabStripTests`)

| Mutation | Reddened |
| --- | --- |
| tab's `onTapGesture` removed | `aClickOnATabSelectsIt`, `aDragReordersAndATinyDragDoesNot` |
| close reports `tabs[0].id` | `aMiddleClickClosesAClosableTab`, `theCloseButtonReportsTheIdAndDoesNotSelect` |
| middle gesture on `.secondary` | `aMiddleClickClosesAClosableTab` |
| middle close ignores `isClosable` | `aMiddleClickClosesAClosableTab` |
| slot built for every tab (`if true`) | green first (its button was hidden and inert); `aTabWithNoSlotIsEighteenPointsNarrower` added, reddens |
| `showsDot: item.isDirty` | `theDirtyDotGivesWayToTheCloseButtonOnHover` |
| `accent` ignored | `theAccentIsDrawnInItsColour` |
| destination counts the dragged tab's own middle | `aDragReordersAndATinyDragDoesNot`, `aDraggedTabDimsAndMarksWhereItWouldLand` |
| `onMoveTab` called when `to == from` | `aDragReordersAndATinyDragDoesNot` |
| `scrollTo` removed from `onChange` | `aSelectionOffScreenScrollsIntoView` |
| `maxTabWidth` 400 | `tabsClampTheirWidth` |
| `==` always true | `anUnchangedStripReplaysAndAChangedOneRebuilds` |
| `isSame` ignores `isDirty` | `anUnchangedStripReplaysAndAChangedOneRebuilds` |
| drop edges swapped | `aDraggedTabDimsAndMarksWhereItWouldLand` |
| marker never drawn | `aDraggedTabDimsAndMarksWhereItWouldLand` |
| group label removed | `theAccessibilityTreeHasTheStripsShape` |
| `.isSelected` trait removed | `aClickOnATabSelectsIt`, `theAccessibilityTreeHasTheStripsShape` |
| `showsClose: false` | green first (the click works without the glyph); `theCloseButtonShowsOnTheSelectedAndTheHoveredTab` added, reddens |
| drag slop 0 | green: equivalent (section 2) |
| icon removed from the label | `anIconWidensTheTabAndCountsInEquality` |
| icons always equal | `anIconWidensTheTabAndCountsInEquality` |

## 5. Counts

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5655 tests in 26 suites passed after 470.766 seconds` (0 failures; the same count under `METALUI_VERIFY_RETAINED=1`, `372.608 seconds`), `FR-J no-argument frame: succeeded=true`. Portable container (`git archive HEAD` over stdin to `docker run --rm -i metalui-portable:latest`): `swift build --build-tests` complete (158.05 s); `Test run with 961 tests in 11 suites passed` (`MetalUITestingTests`), then 9, 16, 73, 68, 53, 25, 286, 165, 24 and 45, all passed. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 6. Carried

A tab-group accessibility role (AppKit `AXTabGroup`, AccessKit `TAB_LIST`) with radio-button tabs; a ghost of the dragged tab under the pointer and neighbours that shift (needs a z-order); a tab context menu and a drag-out of the strip; human checks `TBS1`..`TBS6` (not run).
