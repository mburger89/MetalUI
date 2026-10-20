# 126 — Finer retention scopes: a `List` row that replays, and a shifted or scrolled row that replays translated

Branch `perf/finer-scopes` from `711ab9c4`, merged with master `679f5d7d` (§124 raster overscan; §125 was already in the base). **Item C14-d**, user
request 2026-10-02 (the gpui-gap priority list; **not a plan task**), the carried half of §104 §7, §109 §11 (`SB-AE`), §110, §120 (C14-c4) and §121.
Spec `docs/superpowers/specs/2026-10-20-finer-scopes-design.md` (status: **LANDED**, section 6 amends section 2); rulings `FS-A`…`FS-T` in the new
decisions doc `docs/superpowers/2026-10-20-finer-scopes-decisions.md` (next unused `FS-U`); probe and instrument `docs/probes/finer-scopes/`.

**Numbering.** Written as §126: §124 (raster overscan) merged to master during this branch and §125 was in the base, so §126 is the next free
number; no renumbering. Divergence labels 555–564 were reserved and **none is taken** (no public type, no SwiftUI-visible difference).
Human-checks group letters `FS` (provisional, in the manner of `RT`, `KF`, `IF`).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a human** (group `FS`, §8). Two lanes, run one after the other, each
red first and verified `ok: true`; this Record phase re-took the suite (§6).

## §0 What the item turned out to be (measured first, 711ab9c4)

The brief said one changed row, element or node kills its whole enclosing `.equatable()` occurrence and every sibling rebuilds. **That is false for
a row that is an `.equatable()` `Component`** and true for two things the brief did not name (`FS-A`; counts are `FrameWork`, 24 cards, scale 2):

| # | scenario | requests / prepaints / paints | hits / misses | grafts |
|---|---|---|---|---|
| F1 | one `ForEach` row's value changes, graft on | 8 (161 skipped) / 9 / 11 | 23 / 1 | 23 |
| F2 | an id inserted first, or a header above grows 4 pt | 171–190 / 172–191 / 244–271 | 0 / 24–27 | 0 |
| F3 | wheel -30 over a `ScrollView` of the rows (ceiling, nothing moving: 3 / 4 / 4, 24 / 0) | 171 / 172 / 244 | 0 / 24 | 0 |
| F4 | static `List(rowHeight: 22)`, 9 visible card rows | 84 / 85 / 22 | 9 / 0 at paint | **0** |

So: no implicit element or row scope (`FS-A`), no separate modifier-level scope (`FS-B`; a changing `.offset` is the existing translated replay and
a changing layout modifier is lane 2), and two lanes — **lane 1** the `List` row that never replayed its prepaint nor grafted, **lane 2** a row
that **moves**.

## §1 Lane 1 — a standing record's stale prepaint ledger (`FS-C`, `FS-N`, `FS-H`)

- **Cause** (measured, not the `suppression` part of the key, which only showed it). With an accessibility client collecting, `List.prepaint`
  opens `withAccessibilitySuppressed(except: listID)` around its rows while its window is unbounded (the first frame, `AB-X` rule 1), so a row's first
  prepaint ledger is keyed `suppression == [listID]`. Later frames key `[]`, every other part equal: the prepaint runs, makes a correct ledger, but
  the paint record is still valid and hits, `finishRetainedPaint` is not reached, and the record keeps the old ledger for ever: prepaint never
  replays, no graft stands. With **no client** the exception never exists and the same list already replays (pin `aStaticListWithNoAccessibilityClientAlreadyReplays`,
  green on arrival). Both branches share the code.
- **Fix** `RetainedSubtree.refreshLedger(of:from:)`: on a paint **hit** whose prepaint ran this frame, the fresh ledger replaces the record's when its
  key differs **and** every entry it read is one the record already versions (`ledger.reads` a subset of `record.versions`). No key widened, no counter.
  `suppression` stays a real key part. Figures, per frame (uniform static): 84 / 85 / 22, hits 0, grafts 0 → **21 (63 skipped) / 22 / 22, 9 hits, 9
  grafts**; variable static 23 / 24 / 24, 10 / 10; one row's value changing 28 / 29 / 32, 8 hits 1 miss 8 grafts (variable 30 / 31 / 34, 9 / 1, 9). The pins
  warm 16 frames: four sit inside the redo backoff (9 builds) and read the old figures.
- **C14-c4 (`FS-H`) is a dead conjunct, not a separable site.** The graft site's `environmentTop.uncomparableCustomCount == 0` replaced by `true`
  reddened nothing in the whole native unfiltered run (3996 passed) nor under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` (3996): an
  uncomparable reading is `.uncomparable`, unequal to itself, so `BuildKey.environment` can never equal a recorded key that held one, and the paint and
  prepaint refusals dominate. **Removed**, with a comment naming `BuildKey` as the refusing site. The brief asked for a pin red on arrival; none
  can be (three conditions already guarantee the behaviour, `FS-H`).

**Tests** (`Tests/MetalUITestingTests/FinerScopesElementTests.swift`, fixture `FinerScopesFixture.swift`; `Tests/MetalUITests/FinerScopesGraftKeyTests.swift`):

- `aStaticListOfEquatableRowsReplaysPrepaintAndGrafts(branch:)` and `aChangedListRowMissesAloneAndTheOthersGraft(branch:)` — **red at 711ab9c4** (prepaint
  hits 0, grafts 0), both branches (`rowHeight:`, `List(_:rowContent:)`).
- `aSuppressedFirstFrameLedgerReplaysTheSameTreeAsAFreshWindow(branch:)` and `aListRowReplayEqualsAFreshWindowWithAccessibilityOnAndOff(branch:accessibility:)` —
  scene, hitboxes, accessibility tree and Tab order equal a retention-off window.
- `aFreshLedgerThatReadAnUnversionedEntryIsNotSwappedIn` — the subset guard; `aFieldRowListReplaysAndEqualsAFreshWindow(branch:)`.
- `aBuildKeyUnderAnUncomparableReadingEqualsNothing` (`MetalUITests`).
- **Green on arrival, named as characterisations:** `aChangedRowMissesAloneAndItsSiblingsReplayAndGraft` (F1), `aStaticListWithNoAccessibilityClientAlreadyReplays(branch:)`,
  and **`aGraftIsRefusedUnderAnUncomparableKey`** (window level, green by construction; the paint refusal dominates, so no window-level mutation reaches
  the graft half, which is pinned at `BuildKey` level only).
- Every existing `VL-`/`DD-` test and literal is unedited (`VL-I`); row naming is untouched, so the 100k re-take is **not owed**.

## §2 Lane 2 — translated replay for a layout shift (K1) and a scroll offset (K2) (`FS-D`, `FS-E`, `FS-M`, `FS-O`, `FS-P`)

`Sources/MetalUI/RetainedTranslation.swift` (new, 373 lines), `RetainedSubtree.swift`, `RetainedPrepaint.swift`, `Frame.swift`, `Hitbox.swift`,
`ContentMemo.swift`, `LayoutTree.swift`. The spike of `FS-E` succeeded; the lane extends `RK-G`/`RK-S`'s translated replay, it does not fork it.

- **Key.** `ReplayKey` and `PrepaintKey` keep their absolute `rects`/`interior` (so `==` and every old decision compare as before) and gain
  `shapeInterior`, `LayoutTree.subtreeSignatures(of:relativeTo:)` (one walk, both hashes; `MetalUILayout` imports unchanged). `RetainedShape.shift` is
  the one relation: same node count, same relative signature, same top sizes and relative origins, and a shift of the first origin (K1) or of where it lands
  with the ambient offset (K2). An occurrence under a moved **render effect** is not combined with these (deferred, `FS-S` 2).
- **Move** (`Frame.movedPaintRecord`): the first top node's device origin with `fill`'s own arithmetic, the delta the difference, the record's leaves moved
  by one add through `processScopes`. Allow-list: **rect, glyph, image**; path, gradient, surface, shadow, blur and backdrop refuse by kind name
  (`unlistedKind:<kind>`), a transformed primitive (`transformedPrimitive`), a record that passed an **inner** paint scope (`innerScope`). Masks: read at the
  entry clip are left, read deeper move only when strictly inside the entry clip before and after (`maskStraddlesEntryClip`).
- **Gate** (`FS-M`, a critic finding: an exact add is not an equal paint, since subpixel bins, resampling and `RasterAnchor` rasters depend on the fractional
  position): the delta must be a **whole number of device pixels** (`fractionalTranslation`) and every number a multiple of 1/16 below 2^19 (`inexactTranslation`).
  **Measured amendment:** scales 1.5 and 3 are *not* refused wholesale (layout rounds to whole points, so a 4 pt shift is 6 or 12 px and exact); what refuses is a
  fraction. The scale differential is bit-identical to a retention-off window at 1, 1.5, 2, 3 and 4, with and without an accessibility client.
- **Prepaint** (`Frame.movedPrepaintLedger`): hitboxes and element bounds move; **a hitbox keeps its uncut rect and clip depth** (`Hitbox.unclipped`,
  `clipDepth`, additive, read by nothing else), so a row cut by a scroller's edge is recomputed as `clip ∩ (rect + delta)`, not shifted; **the pointer is read against
  the moved hitboxes** (testing the old ones let a card scroll under a resting pointer, replay, and meet the paint's pointer rule: a redo, found by
  `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`). The paint record must be able to follow before a prepaint is replayed (`Frame.paintTranslation`), else the
  prepaint runs and no redo is owed. Refused by name: `accessibilityRecords`, `pressOnly`, `contextMenus`, `presentationAnchor`, `hitboxUnderEffect`,
  `hitboxShape`, `hitboxScrolls`, `hitboxHandlers`, `hitboxClipped`, `inexactTranslation`.
- **Rebase.** A successful translated hit rebases the record and the prepaint ledger at the new position (not in verify mode), so the settle frame is an exact hit.
- **Switch.** `ContentMemoStore.translatesLayout`, `METALUI_RETAINED_TRANSLATION=0`, package `Window.testingRetainedTranslation`: the A/B of the figures in one binary.
- **Public API: one `MetalUITesting` field**, `FrameWork.retainedTranslationRefusedReasons: [String: Int]` (class M, doc comment, inventory row on
  `test-harness-host`, census re-recorded, `FS-J`). **No divergence label taken.**

**Figures** (`FS-Q`; element requests / prepaints / paints per frame; 24 cards, scale 2, retention and prepaint replay on):

| scenario | before (switch off) | translation on, graft off | on, graft on |
|---|---|---|---|
| header +4 pt (K1) | 171 / 172 / 244, hits 0 | 171 / 4 / 4, 24 translated | 3 (168 skipped) / 4 / 4, 24 grafts |
| id inserted first | 176–190 / 177–191 / 251–271, hits 0 | same requests / 9 / 11, hits 24–26 | 8 / 9 / 11 |
| wheel -30 over a `ScrollView` (K2) | 171 / 172 / 244 | 171 / 4 / 4 (0 on the settle frame: exact hit) | 3 / 4 / 4 |
| wheel -30 over a `List`, uniform | 102–111 / 103–112 / 116–148 | not measured | 32–41 / 33–42 / 36–50, 9–11 translated and grafted |
| header, accessibility on | 171 / 172 / 244 | 171 / 172 / 4, refused `accessibilityRecords` 24 | one redo, then as left |

Unmoved, existing pins unedited: the bracket node drag (144 / 153 and `.value` 208 / 219) and the orbit with panels (6 / 7 / 7).

**Release, dated 2026-10-20** (`zsh docs/probes/perf-baselines.sh release shiftscroll`, MacBookPro18,2 / M1 Max / macOS 27.0.1, a **shared Mac**, load average 5 to 7,
commit `6543453c`; 60 cards in a scroller, scale 2; main-thread CPU median of 160 frames per movement; `METALUI_RETAINED_TRANSLATION=0` against the default alternating in one
binary, three pairs): header ±4 pt 3.44, 3.46, 3.55 ms off against 2.84, 3.00, 2.85 ms on (-15 to -18 %); wheel 30 pt 3.68, 3.70, 3.77 off against 2.27, 2.41, 2.29 on
(-35 to -39 %). **A dated measurement, never a pin.** What is left of a shifted frame is layout (`layoutMemoMisses` 23 to 175: the placement memo keys the origin, `FS-G`).

**Tests** (`FinerScopesTranslationTests.swift`; `Tests/MetalUILayoutTests/SubtreeSignatureTests.swift`; one existing file amended): `aShiftedOrScrolledRowReplaysTranslated(kind:accessibility:)`
(red at 711ab9c4: hits 0), `aShiftedCardStackEqualsAFreshWindow(arm:)`, `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale(arm:)`, `aClickAfterAShiftReachesTheMovedButton(scale:graft:)`,
`aFractionalShiftIsRefusedNotApproximated(step:)`, `anInexactCoordinateIsRefusedNotApproximated`, `aShiftThatAlsoResizesTheOccurrenceMisses` (the separating arm for the shape
comparison), `everyUntranslatableKindRefusesByName(kind:)`, `aScrolledListReplaysTheRowsStillInTheWindow(branch:accessibility:)`,
`theSwitchOffMissesEveryShiftedRowAndOnTranslatesThem(kind:)`, `aFrameAfterAShiftReplaysAnExactLedgerNotAMovedOne`, `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`,
`aRelativeSubtreeSignatureIsTranslationInvariant`-family in `SubtreeSignatureTests`. **One existing pin moved, by ruling** (`FS-R`): `everyKeyComponentSeparates`' `topRect` and
`flexRect` arms read `translated` (2 and 1) instead of a miss, because a moved but unchanged neighbour now translates; the key components they separated (a changed size or interior)
keep their separating arm in `aShiftThatAlsoResizesTheOccurrenceMisses`. The retained demo's occurrence count rose with its new section (16 → 40, 13 → 37 replayed).
**Demo:** `METALUI_RETAINED_DEMO=1` gains `RetainedDemoShift` (header control above a `ScrollView` of 24 cards, counters line; its own function for the Windows 1 MB stack).

## §3 Red runs, mutations and survivors

Lane 1 (reproduced by the lane verifier): the reads-subset guard line of `refreshLedger` deleted → `aFreshLedgerThatReadAnUnversionedEntryIsNotSwappedIn` reddens alone
(60-test filtered run); `custom` dropped from `EnvironmentValues.retainedFingerprint` → `aBuildKeyUnderAnUncomparableReadingEqualsNothing`, `aGraftMissesWhenACustomKeyChanges`,
`anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay`, `theFingerprintDistinguishesCustomValuesAndNotEqualOnes` redden. From
the implementer (`FS-N`): refresh body skipped → both branches of the static, changed-row and suppressed-first-frame pins redden; `suppression` dropped from `retainedPrepaintKey` →
`aSuppressedFirstFrameLedgerReplaysTheSameTreeAsAFreshWindow` (accessibility tree).

Lane 2 (`FS-T`, full table there; each mutation applied to the committed tree and restored from git, `git status --short` clean after each, the 447-test retained-related set):
K1 off → `aShiftedOrScrolledRowReplaysTranslated`, `aShiftedCardStackEqualsAFreshWindow`, `everyUntranslatableKindRefusesByName`, `aClickAfterAShiftReachesTheMovedButton`,
`everyKeyComponentSeparates`, `aFractionalShiftIsRefusedNotApproximated`, `anInexactCoordinateIsRefusedNotApproximated`; K2 off → the first two, `aScrolledListReplaysTheRowsStillInTheWindow`,
`everyUntranslatableKindRefusesByName`; the add applied to y twice → `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` (120 issues), `aShiftedCardStackEqualsAFreshWindow` (66), the graft sweep pins;
whole-pixel test removed → `aFractionalShiftIsRefusedNotApproximated`; inner masks unmoved → `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` (160),
`aListRowReplayEqualsAFreshWindowWithAccessibilityOnAndOff` (44); hitboxes replayed unmoved → `aClickAfterAShiftReachesTheMovedButton`, `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`;
accessibility refusal removed → `aShiftedCardStackEqualsAFreshWindow` (33) and five more; paint rebase removed → `aShiftedOrScrolledRowReplaysTranslated`; ledger rebase removed →
`aFrameAfterAShiftReplaysAnExactLedgerNotAMovedOne`; the switch left out of the paint decision → `theSwitchOffMissesEveryShiftedRowAndOnTranslatesThem`. **Reproduced by the lane verifier** (137-test
filter): the pointer-vs-moved-hitbox check disabled → `aHitboxTheScrollersClipCutIsRecomputedAtItsNewPlace`; `old.innerScopes` refusal removed → `everyUntranslatableKindRefusesByName(kind: innerScope)`.

**Survivors, stated.** (1) Each of the two explicit shape guards alone (top sizes; the relative subtree signature) is an **equivalent mutant**: the signature hashes every node's size, so the
size test is an early-out; removed together, `aShiftThatAlsoResizesTheOccurrenceMisses` reddens. (2) **`hitboxClipped` is unpinned**: proposal `.clipped()` and `.clipShape` register
hitboxes at the ambient clip depth, so no tree in this suite reaches it; it stays as the conservative answer for a legacy `clipped(to:offsetBy:)` inside an occurrence, **carried** (§7).
(3) Removing the exactness test alone leaves the pixels equal (the Float add of a whole delta happened to be exact); only the refusal-name pin reddens. **The mutation runs were filtered
sets, not full unfiltered runs**, each reported with its reddened tests above.

## §4 Hazards found

- **The redo backoff hides a fix.** Four warm frames sit inside the 9-build backoff after a redo and read the unfixed figures; pins warm 16 (`FS-N`).
- **An exact add is not an equal paint** (`FS-M`): subpixel bins, resampling phase and anchored rasters depend on the fractional device position.
- **A replayed prepaint leaves no element state**, so a paint that then misses is the redo: the prepaint decision asks whether the paint record can follow first (`FS-P`).
- **A scroller's cut is not a shift of the cut:** hitboxes keep the uncut rect so the clipped bounds are recomputed (`FS-P`).
- **With a client active every translated prepaint refuses** (`accessibilityRecords`): the shifted rows build every frame as today; one redo per backoff window for a grafted occurrence.

## §5 Not done, with owners (`FS-K`, `FS-S`)

Implicit equality scopes and an `.equatableRows()` opt-in (rejected, `FS-A`; a new item with a probe); `List`/`ForEach` rows as groups without a `Column` wrapper (SwiftUI-alignment item);
**placement-memo translation, C14-e** (layout is the dominant remaining cost of a shifted frame: `layoutMemoMisses` 23 to 175); a layout shift combined with a moved render effect; path, gradient and
shadow rasters as translated leaves (their keys are anchored, `PF-A`); the unpinned `hitboxClipped`; avoiding the one redo of a graft with a client active; divergence 255 / `FI-I` (rows name
by description); out-of-window rows (`TB-AH`); MetalCreator's own reading of the orbit (`FS1`, no agent touches it).

## §6 Suite and counts (Record phase, 2026-10-20)

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel` unfiltered on the merged tree (master `679f5d7d`), on a **locked
screen**: `Test run with 4038 tests in 5 suites failed after 724.286 seconds with 5 issues`, the five being exactly the `AppKitPresentationTests` sheet issues of `CI-AF`
(lines 120, 139, 161, 183, 200) and nothing else; **4038 = master's 4015 + 23** (lane 1's 10, lane 2's 13); `FR-J no-argument frame: succeeded=true`; 0 `error:`, the only `warning:`
SwiftPM's deprecation notice for `--build-system native`; 0 goldens; typecheck guards 249, none added (`git diff` of `Tests/` holds no `typecheck` line); public census 3679 unmoved by the
merge (`closeout-public-api.sh` equals the recorded tsv; the one new declaration, `FrameWork.retainedTranslationRefusedReasons`, was recorded at lane 2); `closeout-inventory-check.sh` and
`closeout-undocumented.sh` print nothing. Lane figures before the merge: 4010 at lane 1's head `31f80ad4` (5 issues, same five), 4014 passed with `AppKitPresentationTests` skipped at lane 2's
head `8ca801d2`.

## §7 Verification this phase did not take, said plainly

The Linux image (`metalui-portable`) `MetalUITestingTests`, `MetalUILayoutTests`, `MetalUICoreTests`, `MetalUICrossPlatformTests`; the `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`
whole-suite re-take on the merged tree (taken on the lane-1 head: 3996 passed, `FS-N`); the fourteen-image comparison against `711ab9c4` (0 px at the lanes, `FS-Q`; not re-taken after the merge
with §124); an unlocked-screen run of `AppKitPresentationTests` (a locked screen gives its five `CI-AF` sheet issues). `Backends/` and both shaders are untouched.

## §8 Looks owed — `docs/verification/human-checks.md` group FS (none performed, an agent cannot)

`FS1` the owner's MetalCreator orbit and pan with the graph panel open against 25.8 ms; `FS2` a long `List` of retained rows scrolled with a wheel and trackpad, a row edited while scrolling,
VoiceOver on the rows; `FS3` the demo's shift-and-scroll strip at scales 1, 2 and a non-dyadic scale, no tearing, no stale row after a fast wheel and a data change; `FS4` VoiceOver on the shifted strip.
