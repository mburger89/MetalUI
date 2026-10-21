# 128 — Retained geometry observers, placement-memo translation, per-shelf atlas uploads (C14-f)

Branch `perf/retained-geometry` from `99b21a1c`, merged with master `c502f14c` (§127 warm settle) at the Record phase. Not a plan task: item C14-f of the gpui-gap
list (user request 2026-10-02), carrying §126 (`FS-G` placement-memo translation, the unpinned `hitboxClipped`, a shift under a moved render effect) and C14-e's parts (c)
and (f) (MetalCreator's findings of 2026-10-20). Spec `docs/superpowers/specs/2026-10-20-retained-geometry-design.md`; rulings `RG-A`…`RG-O` in
`docs/superpowers/2026-10-20-retained-geometry-decisions.md` (next unused `RG-P`). Divergence labels 575–584 reserved: **none taken**. One public declaration,
`GlyphAtlas.dirtyRects` (class M, one census line; `dirtyRect` stays, now computed). §1–§2 are lane 1, §3–§4 lane 2, §5–§6 lane 3, §7 on are the Record phase.
No number collision: master held 127, this record is 128.

## §1 Lane 1 — a geometry note is replayed, not a taint (`RG-A`, `RG-C`, `RG-J`)

At `99b21a1c` a `.onGeometryChange` scope inside an `.equatable()` occurrence called `prepaintLog?.taint("geometryChange")` (`RK-E`), so the occurrence was
prepaint-ineligible every steady frame (MetalCreator's graph panel: 222 element requests per orbit frame with `.equatable()` against 199 without). Now
`Frame.noteGeometry` appends a `GeometryNoteRecord(watch, key, owner, value, global)` to the `PrepaintLog` (`Marks.geometry`, counted into the ledger's slice) and no
longer taints; `PrepaintLedger.geometry` holds the slice, and `replayPrepaintLedger` re-notes each record **in recorded order** through `LifecycleStore.noteGeometry`, re-appends
it to any outer open log and counts `retainedReplayedGeometryNotes` (`package`). The re-note is the point: `closeGeometry` drops a key not noted in a build silently, so a
skipped note would be a G7 re-report of `initial` on the next build. `KF-J`'s delivery is untouched (the action runs in the lifecycle drain, after the build, only when the value
differs from the last delivered). The replayed record carries the closure of the build that produced it (the `.equatable()` contract every replayed handler already has, `RG-I` 2).

Two refusals, both by name. **`geometryTranslated`** (`RG-C`): a translated replay (`movedPrepaintLedger` and the effect-translation path) of a ledger holding a note is refused,
because the value would need the user's transform re-run over a moved proxy. **`geometryGraft`** (`RG-J`, found in lane 1's test 5): a graft decides before layout, so a shifted
grafted occurrence met `geometryTranslated` after the layout it had skipped, the prepaint cannot run on a graft, and the window redid the frame (`retainedRedos == 1`) and backed
replay off for eight builds; a ledger with a note is therefore never grafted (`graftRefusals["geometryGraft"]`). The win is prepaint and paint replay of an observer; its build
recursion keeps running. `onModifierKeysChanged` keeps its taint (`RG-D`). The demo gains a geometry card in its own function (`RetainedDemoGeometry`,
`METALUI_RETAINED_DEMO=1`, Windows 1 MB stack).

## §2 Lane 1 — tests and red runs

`Tests/MetalUITests/RetainedGeometryTests.swift`, six tests. Red at `99b21a1c` (commit `e0005fcd`): 1 `aGeometryScopeInAnEquatableOccurrenceDoesNotTaintItsLedger`
(`reasons["geometryChange"] > 0` each steady frame, 0 after), 2 `aReplayedGeometryNoteDeliversNothingUntilTheValueChanges`, 5 `aTranslatedReplayOfAGeometryNoteIsRefusedByName`
(a pure whole-pixel shift, not a scroll: a scroll changes `AmbientKey.offset` and misses before translation is considered, `RG-I` 3), 6
`twoGeometryScopesStackedAtOnePositionAreBothHeldThroughAReplay`; 3 `theDeliveredValuesEqualAFreshWindowsOverAScript` (resize, scroll, shift; retention on against
`testingRetainedSubtrees = false`) and 4 `aGeometryNoteUnderAChangedRenderEffectMissesAndDelivers` are differential and green by design. `GeometryChangeTests` unedited.
**Test 3 is a regression net, not a pin** (`RG-B`, amended): no mutation reddened it (the shift step of its script delivers correctly even with the refusal removed); tests 2, 5
and 6 carry the mutation evidence. Test 6 pins that **both** scopes of a stacked pair stay in the store through a replay, not their replay order: reversing the order was an
equivalent mutant (`RG-K`, the spec's "keep their ordinals" is superseded).

## §3 Lane 2 — placement translation (`RG-E`, `RG-L`) and the carried pins (`RG-M`, `RG-N`)

**Measured first** (`b30e1e11`, FS shift fixture at `99b21a1c`, translation on, graft off): header frames `layoutSubtreeHits` 0, memo lookups 336, 23 memo misses, 171 element
requests, 172 signature nodes; insertFront 358–372 lookups, 26 misses. A card in a plain `VStack` cannot hit a translated placement: the stack divides the remaining height, so a shift
changes each card's *proposal*. A card in a `ScrollView`'s stack keeps its proposal: ten cards, header +4 pt, memo lookups 140 with 0 subtree hits at `99b21a1c`, 10 lookups and 10 hits
after; insertion in front 162/176 lookups with 0 hits, then 19/20 with 11/12 hits. Debug wall time on 60 cards, 100 alternating frames (dated, never a pin): 11.95–12.34 ms off,
10.40–10.84 ms on (about −13 %). Not the dominant cost (element requests and signature nodes do not move), but the largest counter that does, additive and cheap, so built.

`LayoutMemo.translatedPlacements` (two generations, swept beside `placements`) is keyed `(signature, proposal, width, height)` and holds the unrounded rects with the origin they were
recorded at and, per axis, whether origin and every rect coordinate on that axis are exact sixteenths. `lookupPlacementTranslated` runs only after the exact-origin key missed: per axis
the origin is bit-equal (copied) or an exact sixteenth against an exact record (shifted by an exact add); else `nil`. A subtree holding a `.custom` layout is never stored
(`holdsCustomLayout`, at the store only: its lookup twin was an equivalent mutant and was removed). A hit is a `memoSubtreeHits`, recomputed under `METALUI_VERIFY_LAYOUT_MEMO=1`.
Existing pin amended: `SubtreePlacementTests` 2.3 `aMovedSubtreeIsPlacedFreshNotRestored` reads 1 subtree hit, rects still equal fresh. Per-axis, because a centred card's x is
`(width − w) / 2` with a fractional text width.

**Merge with C14-e (`CF-E`).** §127 changed `Placed` (rects plus a `Footprint`) in the same functions. The merge keeps both: a `TranslatedPlacement` also stores the recording's
`Footprint`, `lookupPlacementTranslated` returns a `Placed` (translated rects, the same footprint), and `subtreePlacement` runs `touch(placed.footprint)` and extends an enclosing
footprint for a translated restore exactly as for an exact one. The two conflicted edits (`LayoutMemo` storage, `LayoutTree`'s store `defer` and restore site) are resolved in
`c76a6a37`; no existing method of either lane changed behaviour.

**The carried pins.** `hitboxClipped` (`RG-M`): reachable only where the inner-clipped region registers a hitbox and paints nothing (the paint record's `maskStraddlesEntryClip` is the same
predicate and is asked first, so a `Button` in the clipped box counts that name instead). Tests `anInnerClippedHitboxInsideBothClipsMoves`, `anInnerClippedHitboxTouchingTheAmbientClipRefuses`,
`theClippedRowsAreRefusedByTheNameHitboxClipped`; the guard text is unchanged. A shift under a moved render effect (`RG-N`): `.offset` above an occurrence whose layout also moves keeps its
refusal (`RK-G`'s branch needs equal rects, `FS-O`'s equal effects; combining them is not a few lines) and now counts `retainedTranslationRefusedReasons["effectAndLayoutMoved"]` instead
of falling through silently; test `aShiftUnderAMovedRenderEffectIsRefusedByName`.

## §4 Lane 2 — tests and red runs

`Tests/MetalUILayoutTests/SubtreePlacementTranslationTests.swift` (`aSubtreeShiftedByAnExactAmountRestoresTranslated`, `aNonSixteenthShiftFallsBackToTheExactKey`,
`aSubtreeHoldingACustomLayoutIsNotTranslated`) and `Tests/MetalUITestingTests/PlacementTranslationTests.swift` (`aShiftedFrameRestoresTheCardPlacementsTranslated`, two arms, and the four
carried-pin tests above). Red at `99b21a1c` (`b30e1e11`): `aShiftedFrameRestoresTheCardPlacementsTranslated` (both arms), `aSubtreeShiftedByAnExactAmountRestoresTranslated` and
`aShiftUnderAMovedRenderEffectIsRefusedByName` (the name); the non-sixteenth, custom-layout and `hitboxClipped` tests are pins of today's behaviour (green on arrival, mutated red in §8).
The four `hitboxClipped`/effect tests are `.enabled(if: !rsVerifying)`: verify mode changes the counters, as the existing prepaint pair tests do, so the verify-switch run skips them.

## §5 Lane 3 — per-shelf atlas dirty rects (`RG-H`, `RG-I`, `RG-O`)

`GlyphAtlas.dirtyRect` was one bounding rect, so two first-use glyphs on distant shelves in one frame uploaded the whole span (MetalCreator fillet-drag step 51: 350 texels inserted,
26 468 uploaded; SDL uploaded the whole `aw × ah` atlas on any dirt). `GlyphAtlas.dirtyRects` is a list: `markDirty` extends the last rect when the slot is on the same shelf row and
x-adjacent (height the larger), else appends; **at most eight**, the ninth collapses to the bounding rect and from then on every slot unions into that one rect until
`clearDirtyRect()` (sticky, so the list stays a superset, `RG-I` 1). `dirtyRect` is the computed union (no reader moved). Metal: `upload` calls `replace(region:)` once per rect, each with
the pointer offset to the rect's origin and `bytesPerRow` the atlas width (the first spelling passing the base pointer for every rect is what test `aTwoRectUploadLeavesEveryTexelEqualToTheAtlas`
catches). Headless: `lastAtlasUploadPixels` is the sum of areas. SDL: `mui_renderer_finish` takes `const uint32_t *atlas_rects, uint32_t atlas_rect_count` (x, y, w, h each) in place of
`bool atlas_dirty`; a new or resized atlas still uploads whole, otherwise the rects are validated against the atlas size (a rect outside is an `SDL_SetError` refusal, never a read past the buffer),
packed tightly into one buffer and one transfer buffer, and copied by one `SDL_UploadToGPUTexture` per rect; `mui_renderer_last_atlas_bytes` (package recorder) reads the bytes moved.
No shader change; replay parity untouched. A gap-merge threshold and atlas eviction are not built (`RG-H`).

## §6 Lane 3 — tests and red runs

Red commit `fc3069c4`: `Tests/MetalUITestingTests/GlyphAtlasDirtyRectsTests.swift` (`twoGlyphsOnDistantShelvesCountTheirOwnAreasNotTheSpan` (counts 2176, the span, at `99b21a1c`),
`adjacentSlotsOnOneShelfMergeIntoOneRect`, `theNinthRectCollapsesToTheBoundingRect`, `dirtyRectIsTheUnionOfDirtyRects`), `Tests/MetalUIRenderTests/AtlasRectUploadTests.swift`
(`aTwoRectUploadLeavesEveryTexelEqualToTheAtlas`, a Metal readback, 0 px), the plain-import typecheck guard `dirtyRectStaysReadableAsATuple`
(`Tests/MetalUITests/AtlasDirtyRectsCompileGuards.swift`) and `Backends/SDL`'s `theAtlasTransferMovesOnlyTheRects` (`SDLWindowRendererTests`).

## §7 Suite and verification

Merged tree `c76a6a37` (branch `d85cc670` + master `c502f14c`), screen unlocked to the suite:

- `swift package clean`, `swift build --build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice. Native unfiltered run: **4073 tests in 5 suites passed**, 0 issues recorded
  (the five `AppKitPresentationTests` sheet issues of `CI-AF` did not appear), `FR-J no-argument frame: succeeded=true`. 4073 = master's 4053 + 20 (lane 1's 6, lane 2's 8, lane 3's 6, the
  guard included); **250 typecheck guards** (249 + `dirtyRectStaysReadableAsATuple`; 459 `typecheck`/`typecheckFile` calls against 458 at `99b21a1c`). Branch alone, before the merge (verifier readings):
  4044 after lane 1, 4052 after lane 2, 4058 after lane 3 (on 4038).
- `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`: **4073 passed** in 5 suites, no trap (a skipped-by-design set of lane 2 pins is counted)
- Default build system `swift build --build-tests`: DEFAULTWARN. Inventory and undocumented scripts print nothing; census **3680** (3679 + `GlyphAtlas.dirtyRects`), re-recorded after the merge's line shifts.
- Fourteen images against `99b21a1c`: **0 px, scene identical in all fourteen** (lane verifiers at `121402a8` and `d85cc670`; DEMOPIXELS).
- Linux image `metalui-portable` (OrbStack, volumes `metalui-root-build-retained-geometry`, `metalui-sdl-build-retained-geometry`), on the merged tree: root `MetalUITestingTests` + the portable tests 412 in 2 suites,
  then 9, 40, 28, `MetalUILayoutTests` 233, `MetalUICoreTests` 128 and the cross-platform 22, all passed; `Backends/SDL` **30 + 215** (macOS 30 + 218 at lane 3: three are macOS-only).
- `Backends/SDL` on macOS at lane 3's head: 30 + 218 passed, including `theAtlasTransferMovesOnlyTheRects`.
- Windows D3D12 for the SDL atlas copy not run (CI compiles it, check RG3).

## §8 Mutations

Each applied after commit, restored from a copy, `git status --short` clean after each. **Lane 1** (filtered to 154 retained, geometry and prepaint tests by the verifier): M3 (the
`geometryTranslated` refusal removed at both sites) reddened `aTranslatedReplayOfAGeometryNoteIsRefusedByName`; M2 (the re-note into `LifecycleStore` dropped) reddened
`aReplayedGeometryNoteDeliversNothingUntilTheValueChanges` and `twoGeometryScopesStackedAtOnePositionAreBothHeldThroughAReplay`; M6 (the `geometryGraft` refusal removed) reddened
`aTranslatedReplayOfAGeometryNoteIsRefusedByName` (its `retainedRedos == 0`). The implementer's M1 (the taint restored), M4 (stale size on replay) and M5 (the effect left out of the ambient
comparison) were run at lane 1 (commit `fc491cd3`); the verifier did not re-run them and the reddened names are not recorded here. Test 3 stayed green under every mutation (§2).
**Lane 2** (filtered, 17–19 tests): M1 (`lookupPlacementTranslated` returns nil) reddened `aMovedSubtreeIsPlacedFreshNotRestored`, `aShiftedFrameRestoresTheCardPlacementsTranslated` (both arms) and
`aSubtreeShiftedByAnExactAmountRestoresTranslated`; M2 (the per-axis exactness guard removed) `aNonSixteenthShiftFallsBackToTheExactKey`; M3 (the store-site custom-layout guard replaced by `if true`)
`aSubtreeHoldingACustomLayoutIsNotTranslated`, which **aborts the run** through the `IV-J` precondition (memo ×375 against fresh ×400); M4 (the `hitboxClipped` guard line deleted)
`anInnerClippedHitboxTouchingTheAmbientClipRefuses` and `theClippedRowsAreRefusedByTheNameHitboxClipped`; M5 (the `effectAndLayoutMoved` counter line removed)
`aShiftUnderAMovedRenderEffectIsRefusedByName`. **Lane 3**: M1 (`Atlas.markDirty` back to the bounding union), full unfiltered native, reddened exactly `aTwoRectUploadLeavesEveryTexelEqualToTheAtlas`,
`twoGlyphsOnDistantShelvesCountTheirOwnAreasNotTheSpan`, `adjacentSlotsOnOneShelfMergeIntoOneRect`, `theNinthRectCollapsesToTheBoundingRect`, `dirtyRectIsTheUnionOfDirtyRects`; M6 (`SDLWindowRenderer`
passes the whole atlas as the only rect), `Backends/SDL` tests: `theAtlasTransferMovesOnlyTheRects`. GUARD-MUTATION
Filtered, not unfiltered, for lanes 1 and 2: a test outside the set that a mutation reddens is not listed.

## §9 Hazards

- **The verify-switch run skips four lane-2 pins** (`rsVerifying`), counted in the total and skipped there; they run in the plain suite.
- **A translated placement is never stored from a root hit**: the first frame of a shift has nothing recorded and the second hits (a one-off shift pays one frame, `RG-L`).
- **A card in a plain stack never hits a translated placement** (the proposal moves); the win is for scroller content and insertion in front.
- **A geometry note's closure is the producing build's** (`RG-I` 2); a transform capturing state the key does not hold replays stale, as every `.equatable()` replay does.
- **An observed occurrence still builds** (`RG-J`): element requests stay whole, prepaint and paint are replayed.
- **`GlyphAtlas.dirtyRect` is now computed**: source-compatible for every reader (it had `private(set)`), but not a stored property.
- **SDL's `mui_renderer_finish` changed its C signature** (`Backends/SDL` internal; every call site moved). A new SDL renderer or a test double calling it passes rects.
- C14-e's `LayoutMemo`/`Footprint` and this lane's translated dictionaries meet in four places (§3); a third change there re-runs both lanes' pins.

## §10 Looks, deferred, with owner

- **Looks owed:** human-checks group **RG** (RG1–RG3, §03 entry): a geometry reader following a real resize and a scroll with retention on, first-use text on distant shelves on Metal and SDL, and the
  SDL Windows D3D12 atlas copy (CI only). Nothing here changes a pixel (fourteen images 0 px).
- Re-evaluating a geometry closure under translation (`RG-C`, `RG-J`: would lift both refusals): a later C14 item, if MetalCreator's scroll figures ask.
- `onModifierKeysChanged` replay (`RG-D`): needs its own design (its value is window-wide).
- A footprint for the root placement (`IV-E` (P)), carried from §127.
- An atlas gap-merge threshold and eviction (`RG-H`).
- Windows D3D12 for the SDL atlas copy: CI only (check RG3); the Linux image runs on lavapipe.
- A shift under a moved render effect still builds (`RG-N`).
