# `List` row identity by value — design

Round 2 item 8; rulings `LH-A`…`LH-H` in
[`../2026-10-22-list-row-identity-decisions.md`](../2026-10-22-list-row-identity-decisions.md).
Branch `feat/list-row-identity` from `4197f825`. Record §145. Status: DESIGNED, not built.

## Outcome

A `List` row is identified by its id's Hashable value, as a `ForEach` element is
(`FI-A`) and as SwiftUI's List is (probe `swiftui-list-row-identity.swift` L1–L3). No public API: `Box.elementID` is
already public and settable; `ElementID(name:key:)`/`IdentityKey` stay internal.
Divergence 255 is retired.

## Inventory (what the item touches)

All in `Sources/MetalUI/List.swift` (1274 lines), three `String(describing: datum.id)` sites:
- ~L531 realised row: `Box(...).id(String(describing: datum.id))` (both the uniform and `.variable` paths build rows here).
- ~L515 `DD-K` scroll-key note: `GlobalElementID.child(of: id, at: 0, name: ElementID(String(describing:)))`, run only while a `scrollTo` is pending.
- ~L1175 `accessibilityRowSelection`'s `byRow` map (input time, one scan of `data`).
Doc text to rewrite: List type doc "`String(describing:)` is not injective" (L88-96), `ListRows.swift` L33 and L44 comments, the comment at L527.
Already by value: selection, click/lead/anchor, `RowExtentIndex`, `ListOrigin`, `LazyUnits.swift` (keyed since `LZ-`).
`Tests/MetalUITests/ForEachIdentityTests.swift` 2.10 `aListRowsCollisionIsStillDivergence255` is pinned wrong on purpose and is rewritten.

## Design

`ElementID.forRow<ID: Hashable>(_ id: ID, keyed: Bool) -> ElementID` (internal, `ElementID.swift`): `keyed ? ElementID(name: String(describing: id), key: IdentityKey(AnyHashable(id))) : ElementID(String(describing: id))`.
`List.build` computes `let keyed = !(Data.Element.ID.self is DescriptionInjectiveID.Type)` once per build and passes it to sites 1 and 2; site 3 computes it itself (input time). Row: `rowBox.elementID = ElementID.forRow(datum.id, keyed: keyed)`.
`Frame.listIdentityWork` increments `rows` and `keyed` per realised row. Nothing else moves: no layout, no windowing, no handler.

## Lane

One lane (disjoint-file split buys nothing, three sites in one file): `List.swift`, `ElementID.swift`, `Frame.swift` (the counter), the tests below, then record phase. Checker re-runs the mutations.

## Tests (each red before the change unless marked; mutation that must redden it)

Fixtures: `Twin` (Hashable on `u`, description "twin") from `ForEachIdentityTests`; a `List` of rows each holding `@State` token, in `rowHeight:` and in content-sized form.
1. `aUniformListsCollidingIDsKeepSeparateState` — red before (shared state). Mutation M1: `keyed` forced `false` in `forRow`'s caller.
2. `aVariableListsCollidingIDsKeepSeparateState` — red before. M1; M1b only the variable path's call (guards a fork).
3. `aListRowsStateFollowsItsIDThroughAReorder` — red before for Twin. M1.
4. `anInjectiveListRowNamesThePlainIDByteForByte` — green before (a characterization, labelled so): Int, String, UUID rows' `ElementID == ElementID(String(describing:))`, `key == nil`, `listIdentityWork.keyed == 0`. M2: `keyed` forced `true`.
5. `anAccessibilitySelectionPicksTheRightRowAmongCollidingIDs` — red before (`byRow`'s last write wins). M3: site 3 reverted to the plain name.
6. `aPendingScrollToReachesTheRightRowAmongCollidingIDs` — red before. M4: site 2 reverted to the plain name (red: the note never matches the row's scope).
7. `aKeyedListRowsStateSurvivesABoundedExcursionButNotALongerOne` — TB-AH twin (`TombstoneTests`). Red only under M5: the key dropped from the row scope's `==` is not applicable; M5 instead drops the key at site 1 while the test's rows still collide — red.
8. `aListRowAndAForEachElementNameTheSameID` — the same id through `ForEach`, `List`, a `LazyVStack` unit gives equal `ElementID`s. M6: `forRow` joins the name with a prefix.
9. `aListsIdentityWorkIsPerRealisedRowAtAnyCount` — `rows == window` and `keyed` (0 for Int, window for Twin) equal at 500 and at 100k rows (a 5000-row arm runs always; the 100k arm rides `METALUI_RUN_100K_LIST_TEST=1`). M7: minting over all of `data`.
10. Existing, unmoved: 2.12 `theKeyedComponentCostsOneReference`, G1 plain-import guard, `aListsWorkIsTheSameFor100kRowsAsFor500` (before and after numbers recorded), `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`.
2.10 is deleted (its claim retired) and replaced by 1.

## Demo

None (no visible change for a string-shaped id). The sample app `Jotter` uses `UUID` ids and is unaffected (run `METALUI_RUN_SAMPLE_APP_TEST=1` once).

## Verification

Native unfiltered after `swift package clean` (4293 plus the new tests, minus 2.10), verify-switch run, default-build warnings 0, inventory scripts print nothing, fourteen images 0 px against `4197f825`, the 100k test before/after, Linux image portable tests.

## Human checks

None added: no look changes. (`docs/verification/human-checks.md` untouched.)

## Deferred

- Folding `ForEach`/`LazyUnits`' three spellings into `forRow` (`LH-G`): optional, owner the implementer if byte-identical, else a refactor item.
- Per-row `@State` for a `List` whose `data` holds a duplicate id: unchanged precondition, not built.

## Record phase owes

`docs/record/145-list-row-identity.md`; divergences.md 255 to Retired (header count -1, next label left); CLAUDE.md's `ForEach` identity paragraph and counts; `docs/record/README.md` row; `ForEachIdentityTests` header comments; `FI-I` cross-reference note in the FI decisions doc.
