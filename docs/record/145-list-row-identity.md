# 145 — `List` row identity by value

Branch `feat/list-row-identity` from `4197f825`. **Not a plan task**: round 2 item 8 of the gpui-gap list, requested by the user on 2026-10-21; it
discharges `FI-I` (record §95) and retires **divergence 255**. Spec `docs/superpowers/specs/2026-10-22-list-row-identity-design.md`; rulings `LH-A`…`LH-I`
in the new decisions doc `docs/superpowers/2026-10-22-list-row-identity-decisions.md`; probe `docs/probes/swiftui-list-row-identity.swift` (arms L1–L3, run
2026-10-22, output in its header). No public declaration, no shader or platform change, no new divergence (labels 745–754 untouched).

**Numbering.** Written as §145 on the assignment of the orchestrator. The header count of `docs/divergences.md` is left to the merge (one fewer live: 255).

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
