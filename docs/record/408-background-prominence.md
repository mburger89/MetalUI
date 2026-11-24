# 408: `EnvironmentValues.backgroundProminence` (`OG-Q`, divergence 244, Alloy)

Class `A` (SwiftUI-aligned API, one divergence). Branch `feat/background-prominence`, base master `361c9944`. **Numbering:** 404, 406 and 407 belong to in-flight PRs and 405 is master's last; this is 408. Alloy's file tree needs a selected row's label to switch colour (git-status orange is unreadable on the accent fill), and its `.equatable()` `FileTreeLabel`s read the whole selection, so every selection change re-ran every visible label. A per-row environment value makes only the old and the new selected row rebuild.

## The probe

`docs/probes/swiftui-background-prominence.swift` (macOS 27.2.1, Swift 6.4.2; arms `BP1`..`BP17`, output recorded in its header, byte-identical over two runs). A row reads the value one container down, as Apple's discussion of the property says it must. Measured:

- A selected row reads `.increased` **only while emphasized** (window key and the list the first responder, set after the first draw): `BP1`. Resigning the key (`BP2`, `BP6`) or moving the first responder off the list (`BP3`) gives `.standard` again, and a window never key never reads `.increased` (`BP4`). So an unfocused selection is `.standard` in SwiftUI.
- It moves with the selection (`BP5`: old row `standard`, new row `increased`) and clears on deselect; every row of a multi-selection reads it (`BP1`); the `ListStyle` changes nothing (`BP7`); a list with no selection never reads it (`BP10`).
- `DisclosureGroup` header and leaf rows (`BP11`), `OutlineGroup` and `List(_:children:)` rows (`BP12`, `BP13`, `BP15`) and `Table` rows (`BP16`) read `.increased` when selected. Two quirks: the row's own child read directly reads `.standard` (`BP8`), and a row inside a `DisclosureGroup`'s *content* reads `.standard` though selected (`BP11`, `BP14`).
- `.environment(\.backgroundProminence, .increased)` sets it for the subtree (`BP17`).
- Apple's discussion says `.primary`/`.secondary` adapt under `.increased`; the probe reads the value, not the drawn colour, so that is Apple's text, not a measurement.

## What changed

- `BackgroundProminence.swift`: `enum BackgroundProminence { standard, increased }` (`Sendable`, `Hashable`); `EnvironmentValues.backgroundProminence` (public stored, doc comment); the field is in `EnvironmentFingerprint` (so in the retained replay and graft keys) and in `differences(from:)`.
- `Frame.withIncreasedProminence`: sets the one field in `environmentTop` in place and restores it, uncounted by `environmentPushCount`, no copy of the values.
- A selected row's three phases run inside it: `ListRows.increased` (selected positions in the window; empty set for a list with none) for the data `List`; `LazyStackEngine.unitIncreased` (asked before a unit is realised, set only while the binding holds a selection) plus the unit wrapper's prepaint and paint for the content form (flat `ForEach`, `DisclosureGroup`, `OutlineGroup`, `List(_:children:)`); `TableRowElement.increased` for a table row, off in cell mode (the unemphasised fill, `TCM-D`).
- `LazyForEachSource` and `LazyLegacyForEachSource` answer `lazySelectionTag` without calling the row closure when the content type is not `ListRowTagged`: the pre-realise selection check would otherwise call every untagged `ForEach` closure twice (measured: 22 calls against master's 11).

## Decisions

- **`.increased` whatever the focus (divergence 244).** MetalUI paints the selection fill in the accent focused or not, so the value follows the fill: reading `.standard` over an unfocused accent would be the unreadable case the value exists for. SwiftUI greys the fill and reads `.standard` unfocused; MetalUI has no unfocused selection look (a standing difference, not changed here). The same row's direct child and a `DisclosureGroup`'s content rows read `.increased` too (the two SwiftUI quirks are not copied).
- **No existing colour changed.** `.primary`, `.secondary` and the hierarchical styles do not adapt to `.increased` (SwiftUI's do). The G21 answer (record 259, `CR-AD`) stands: contrast on a fill is the theme's or the caller's, and the caller now has the value to read. Reported rather than fixed.

## Cost evidence

Counts over `frameWork`, after `runUntilIdle()` then `tick()`; the master literals were taken on `361c9944` in a second worktree.

- **The pin** (`movingTheSelectionRunsOnlyTheOldAndTheNewLabel`): 200 rows, `.equatable()` labels reading the value, selection 3 to 5: **2 label bodies** (`r3`, `r5`), 2 `contentEvaluations`. Content form, 60 folders of 3 leaves (`movingAnOutlineSelectionRunsOnlyTheOldAndTheNewLabel`): 2.
- **Steady frame, a list that never reads it** (`aListThatNeverReadsTheValueKeepsItsWork`, plain `Text` rows): idle and selection change both `builds 1 requests 41 prepaints 42 paints 42 evaluations 0 measures 1 hits 0 misses 0`, master's to the count.
- **`.equatable()` rows that do not read it** (`equatableLabelsThatNeverReadTheValueMissOnlyAtTheTwoRows`; content form `aContentListThatNeverReadsTheValueKeepsItsWork`): the idle frame is master's. A selection change costs the old and the new row one retained miss each, because the value is in the replay key (a style resolved by a scope or at paint must not replay stale: `aStyleResolvedAtPaintSeesTheValueThroughARetainedLabel`): flat `paints 29 -> 31, hits 13 -> 11, misses 0 -> 2`; content `paints 21 -> 23, hits 15 -> 13, misses 0 -> 2`. Builds, requests, prepaints and evaluations are master's, and the content form's `ForEach` closure runs 11 times as on master.

## Mutations (each reddened the tests named; restored, verified with `git diff`)

- Push `.increased` to every row (`increased: Set(rows.indices)`): `theSelectedRowReadsIncreasedAndItMovesAndClears`, `everySelectedRowOfAMultiSelectionReadsIncreased`, `aListWithNoSelectionReadsStandardEverywhere`, the two pins, `settingAndClearingTheSelectionRunsOnlyThatLabel`, `equatableLabelsThat...`, `aStyleResolved...`. The plain-row steady test stays green: a row that reads nothing does no more work, which is its point.
- Drop the insert of the selected offset: the same family minus the no-selection test. Content form's `unitIncreased` off or answering `true`: `aSelectedOutlineRowReadsIncreased...` and the content pin. `unitIncreased` asking the id alone: `aTaggedRowReadsIncreasedByItsTag`. Table `row.increased` dropped: `aSelectedTableRowReadsIncreased`; set whatever the mode: `aCellModeTablesSelectedRowReadsStandard`.
- Each phase unwrapped in turn (`ListRows` layout, prepaint, paint; the content unit's prepaint and paint; the table row's layout, prepaint and paint): `prepaintAndPaintOfASelectedRowRunUnderTheValueInEveryForm` for every prepaint and paint, and the read tests for layout.
- `backgroundProminence` out of `retainedFingerprint`: `equatableLabelsThat...` and `aStyleResolved...`. The `LazyForEachSource` tag guard dropped: `aContentListThatNeverReadsTheValueKeepsItsWork` (closure calls 22).

## Tests

16 new in `BackgroundProminenceTests` (flat, multi, no selection, explicit write, the two pins, set and clear, the three steady-frame arms, outline leaf and header, tagged rows, `Table`, cell mode, the three phases), and the two fingerprint guards gained a row (37 fields). Full run: root 7335 tests in 79 suites green (`--build-system native`, `--no-parallel`); divergences 241 live, next label 250.

## Not done

The built-in hierarchical styles do not adapt (a colour change, left to a ruling of its own); an unfocused selection look; a pinned section header realised outside the window is not wrapped. Human checks: none (no pixels changed).
