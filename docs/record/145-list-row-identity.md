# 145 — `List` row identity by value

Branch `feat/list-row-identity` from `4197f825`. **Not a plan task**: round 2 item 8 of the gpui-gap list, requested by the user on 2026-10-21; it
discharges `FI-I` (record §95) and retires **divergence 255**. Spec `docs/superpowers/specs/2026-10-22-list-row-identity-design.md`; rulings `LH-A`…`LH-I`
in the new decisions doc `docs/superpowers/2026-10-22-list-row-identity-decisions.md`; probe `docs/probes/swiftui-list-row-identity.swift` (arms L1–L3, run
2026-10-22, output in its header). No public declaration, no shader or platform change, no new divergence (labels 745–754 untouched).

**Numbering.** Written as §145 on the assignment of the orchestrator; origin/master `4d166812` holds §140-§143 and §147, so 145 stays free and was not renumbered. Merged with master `4d166812` after the branch work (record phase). The header count of `docs/divergences.md` is left to the merge (one fewer live: 255).

**Status: LANDED.** One lane (three sites in one file), red first, then the implementation, then this record.

## §1 What was built

- `ElementID.forRow(_:keyed:)` (`ElementID.swift`, internal): `keyed ? ElementID(name: String(describing: id), key: IdentityKey(AnyHashable(id))) : ElementID(String(describing: id))`.
  The same constructor `ForEach` and the lazy units use, so a row, a `ForEach` element and a lazy unit of one id name one component (`aListRowAndAForEachElementNameTheSameID`).
- `keyed = !(Data.Element.ID.self is DescriptionInjectiveID.Type)` is decided **once per build** (`FI-B`) and used at the three sites of `List.swift`:
  1. the realised row: `rowBox.elementID = ElementID.forRow(datum.id, keyed:)` (replaces `.id(String(describing:))`, which mints a key-less component);
  2. the `DD-K` scroll-key note (run only while a `scrollTo` is pending);
  3. `accessibilityRowSelection`'s `byRow` map (input time; its function lost `private` so a test can call it).
- `Frame.listIdentityWork: (rows, keyed)` counts per realised row (`LH-E`), classified `.buildOnly` in `RetainedSubtreeInternalTests.frameChannels`.
- Already by value and untouched: selection, lead/anchor, `RowExtentIndex`, `ListOrigin`, `LazyUnits.swift`.
- Docs: the `List` type doc paragraph on `String(describing:)` and `ListRows`' comments rewritten; divergence 255 moved to Retired; CLAUDE.md/AGENTS.md `FI` sentence;
  `docs/guides/state-and-identity.md` no longer cites 255 (`noGuideCitesARetiredDivergence` reddened on it); the inventory map's `foreach` row no longer carries 255.

## §2 Rulings found while building

- The spec's M1b ("only the variable path's call, guards a fork") has no site to mutate: both `List` forms realise rows in the one `List.build` loop, so there is one call. The fork cannot exist; the pin runs both paths (`aListRowsStateFollowsItsIDThroughAReorder`, `aPendingScrollToReachesTheRightRowAmongCollidingIDs` take `[.uniform, .variable]`).
- The cold frame of a `List` in a `ScrollView` has no viewport yet and realises every row (`MP-I`); the work pin counts the warm frame as the window.
- ID-R: a `List` row's `noteNamed` is a no-op under a windowed parent (`StateTable.noteNamed` ignores them, `TB-AH`), so no arm of `everyNamingSiteStartsAReturningNameFresh` is owed for a keyed row; `aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne` is the keyed twin of the tombstone test.

## §3 Red first

Before the implementation (commit `e444f48c`), on the unchanged `List`: `aUniformListsCollidingIDsKeepSeparateState`, `aVariableListsCollidingIDsKeepSeparateState`,
`aListRowsStateFollowsItsIDThroughAReorder` (both arguments), `anAccessibilitySelectionPicksTheRightRowAmongCollidingIDs` (two expectations: `byRow`'s last write won),
`aPendingScrollToReachesTheRightRowAmongCollidingIDs` (both arguments), and the characterizations, red only through the counter (`anInjectiveListRowNamesThePlainIDByteForByte`,
`aListsIdentityWorkIsPerRealisedRowAtAnyCount`) or through the shared twin scope (`aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne`,
`aListRowAndAForEachElementNameTheSameID`). Test 2.10 of `ForEachIdentityTests` (`aListRowsCollisionIsStillDivergence255`, pinned wrong on purpose) is retired.

## §4 Mutations

Each mutation was applied to `Sources/` on the committed implementation, the whole suite run unfiltered (4301 tests in 5 suites), the source restored with `git checkout -- Sources`,
`git status --short` clean after each. Reddened tests, by name (counts are issues):

| # | mutation (spelling) | reddened |
|---|---|---|
| M1 | `List.build`'s `keyed` forced `false` (row and scroll note plain) | `aUniformListsCollidingIDsKeepSeparateState`, `aVariableListsCollidingIDsKeepSeparateState`, `aListRowsStateFollowsItsIDThroughAReorder` (both), `aPendingScrollToReachesTheRightRowAmongCollidingIDs` (both), `aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne` (3), `aListRowAndAForEachElementNameTheSameID` (2), `aListsIdentityWorkIsPerRealisedRowAtAnyCount` (4); 15 issues |
| M1b | the variable path's call alone | **no site**: one call serves both forms (`LH-J`) |
| M2 | `keyed` forced `true` | `anInjectiveListRowNamesThePlainIDByteForByte` (8), `aListsIdentityWorkIsPerRealisedRowAtAnyCount` (4), and 150 issues in the 20 existing tests that hand-compute a row's `ElementID(data[i].id)`: `aLoweredListLaysOutEveryWindowedShape`, `aLoweredListsRowsAreNamedDirectlyUnderTheList`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aVariableListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, the selection, click, AX and VoiceOver tests (168 issues in all) |
| M3 | `accessibilityRowSelection`'s `byRow` keyed by the plain name | `anAccessibilitySelectionPicksTheRightRowAmongCollidingIDs` (2): the only test that sees site 3, since every older AX selection test uses an injective id |
| M4 | the `DD-K` scroll-key note named by the plain description | `aPendingScrollToReachesTheRightRowAmongCollidingIDs` (both arguments) |
| M5 | the row's own identity plain (`ElementID(String(describing:))`) | `aUniformListsCollidingIDsKeepSeparateState`, `aVariableListsCollidingIDsKeepSeparateState`, `aListRowsStateFollowsItsIDThroughAReorder` (both), `aPendingScrollToReachesTheRightRowAmongCollidingIDs` (both), `aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne` (3), `aListRowAndAForEachElementNameTheSameID` (2); 11 issues |
| M6 | `forRow` prefixes the keyed name with `"row:"` | `aListRowAndAForEachElementNameTheSameID` (2), `anAccessibilitySelectionPicksTheRightRowAmongCollidingIDs` (2) |
| M7 | identity minted over all of `data` (a loop before the rows, counter bumped per datum) | `aListsIdentityWorkIsPerRealisedRowAtAnyCount` (10), `anInjectiveListRowNamesThePlainIDByteForByte` (2), `aSelectableListsWarmFrameTouchesOnlyItsRealisedRows` (1, an existing work pin) |

M2's wide red is the useful finding: the `ElementID` of a row is hand-computed by many older tests, so a wrong `keyed` for an injective id cannot hide.

## §5 Work counts (`LH-E`, counted never timed)

`Frame.listIdentityWork` (rows, keyed), cold (first frame, no viewport, every row realised, `MP-I`) then warm, `Int` ids then `Twin` ids (description constant, Hashable on `u`):

| form | rows | `Int` cold / warm | `Twin` cold / warm |
|---|---|---|---|
| uniform `rowHeight:` | 500 | (500, 0) / (5, 0) | (500, 500) / (5, 5) |
| uniform | 5000 | (5000, 0) / (5, 0) | (5000, 5000) / (5, 5) |
| uniform | 100 000 | (100000, 0) / (5, 0) | (100000, 100000) / (5, 5) |
| content-sized | 500, 5000, 100 000 | cold = n, keyed 0 / warm (9, 0) | cold = n, keyed = n / warm (9, 9) |

The warm frame is O(window): 5 rows uniform, 9 content-sized, identical at 500 and 100k, `keyed` 0 for an injective id and equal to the window for a custom one.
**Before and after for the 100k test:** `aListsWorkIsTheSameFor100kRowsAsFor500` is unedited and asserts the kernel's warm work equal to the literal `demoLikeRowsWarmWork` at 500 and at
100 000 rows and equal shaping-cache storage; it passed at `4197f825` (the baseline) and passes now with the same literals, so the work did not move (the cold 100k frame took
35.3 s on this loaded machine, a wall-clock figure for the record, never a pin). The new counter did not exist before; its injective figure is 0 keyed by construction.
`ElementID` stays 24 bytes and `GlobalElementID` in its 64-byte bucket (`theKeyedComponentCostsOneReference`, unmoved). Lazy containers (`LazyUnits.swift`) already named by value (`LZ-`), and
`aListRowAndAForEachElementNameTheSameID` pins that a `List` row and a `ForEach` element name one component.

## §6 Verification

- `swift package clean`, native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; native unfiltered run: **4301 tests in 5 suites passed** (621.8 s, a heavily loaded machine; baseline
  `4197f825` 4293; +9 tests, test 2.10 retired: 4293 + 9 - 1), `FR-J no-argument frame: succeeded=true`; the same under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`: 4301 passed, no trap (582.5 s).
  Typecheck guards unmoved at 265 (no guard added; G1 of `FI-` unmoved, `listIdentityWork` classified `.buildOnly` in `everyFrameChannelIsClassified`).
- The first full run, before the doc edits, read 3 issues, all caught by existing instruments: `noGuideCitesARetiredDivergence` (twice: `docs/guides/state-and-identity.md` cited 255) and
  `everyFrameChannelIsClassified` (the new `Frame` field). Both fixed.
- `METALUI_RUN_100K_LIST_TEST=1`: `aListsWorkIsTheSameFor100kRowsAsFor500` and the identity work pin at 100 000 rows passed.
- `swift build --build-tests` on the default build system: 0 `warning:`, 0 `error:`. Inventory and undocumented scripts print nothing (no public declaration, census unmoved).
- The fourteen offscreen images, `docs/probes/demo-pixels/compare.sh <scratch> 4197f825 HEAD`: **0 differing pixels, scene identical, all fourteen**; the controls read as before.
- Linux image `metalui-portable` (swift:6.4-noble, volume `metalui-root-build-list-row-identity`): root build 0 errors; `MetalUITestingTests` 515 (two suites), `MetalUILayoutTests` 238,
  `MetalUICoreTests` 22, `MetalUICrossPlatformTests` 141 passed. `Backends/SDL` untouched, not re-run.
- Sample app `METALUI_RUN_SAMPLE_APP_TEST=1 ... aSampleAppBuildsAndItsTestsPassAgainstThisCheckout`: passed (Jotter 21 tests; its `UUID` ids take the injective path).

## §7 Deferred

- Folding `ForEach`'s and `LazyUnits`' spellings into `forRow` (`LH-G`): not done, optional.
- A duplicate id in a `List`'s `data` stays the `Identifiable` precondition (not a trap, not deduped).
- `docs/divergences.md` header count and next label are the merge's (255 retired: one fewer live). Human checks: none added, nothing looks different.

## §8 Merge re-take

Merged with origin/master `4d166812` (§140 single miss, §143 sync batch, §147 small items; conflicts only in CLAUDE.md/AGENTS.md prefix list, counts and record map, and the record README). `swift package clean`, native build 0 `error:`, native unfiltered run on the merged tree: **4315 tests in 7 suites passed** (586.5 s; master 4307 + the branch's net 8: 9 tests added, test 2.10 retired), `FR-J no-argument frame: succeeded=true`, 266 typecheck guards (master's; none added here). The verify-switch run, the fourteen images, the Linux image and the 100k test were taken at the branch head (§6) and are owed on the merged tree; master's merge touched `Retained*.swift`, `ContentMemo.swift` and `Backends/SDL` only outside `List.swift`.
