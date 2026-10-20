# Retained geometry observers, placement translation, per-shelf atlas uploads (C14-f)

Branch `perf/retained-geometry` from `99b21a1c`. Not a plan task: item C14-f of the gpui-gap list (user request 2026-10-02), carrying
record §126 (`FS-G`, the unpinned `hitboxClipped`, a shift under a moved render effect) and C14-e parts (c) and (f) (MetalCreator's
findings, 2026-10-20). Rulings `RG-A`...`RG-H` in [`../2026-10-20-retained-geometry-decisions.md`](../2026-10-20-retained-geometry-decisions.md).
Divergence labels reserved 575-584: **none expected** (the only public declaration, `GlyphAtlas.dirtyRects`, is class M and not
SwiftUI-facing). Record `docs/record/128-retained-geometry.md` (Record phase).

**SwiftUI/gpui claims.** No SwiftUI-visible behaviour changes: lane 1 keeps `KF-J`'s probed semantics (value-differs delivery, G1..G7,
`GeometryChangeTests`); lanes 2 and 3 are value-identical. No new SwiftUI probe is owed. gpui's precedent (`reuse_prepaint`/`reuse_paint`
replays recorded ranges of a frame) is from memory, not run. A probe is owed only if a ruling changes an observable delivery order.

## 1. Inventory (the code at `99b21a1c`)

- `Frame.noteGeometry` (`GeometryChange.swift:102`) calls `prepaintLog?.taint("geometryChange")` then computes the proxy and calls
  `LifecycleStore.noteGeometry(value, watch:, key:, owner:)` (`Lifecycle.swift:263`), which numbers the note by occurrence and keeps it
  in `geometryCurrent`; `closeGeometry()` diffs against `geometryPrevious` and **drops silently a key not noted this build**. So a
  replayed prepaint that does not re-note would make the next build report `initial` again (G7): replay must re-note.
- The proxy is a function of: the content nodes' union rect (size; rects are in `PrepaintKey.rects`), `scrolled(...)` (the offset,
  `AmbientKey.offset`), `prepaintEffects.last.composed` (render effect, in the ambient) and `namedSpaces`. A non-empty `namedSpaces`
  already refuses retention by name (`Frame.swift:3902`, "namedSpaces"), and a space opened inside the occurrence is inside its key.
- `PrepaintLog` collects focus, ax nodes, press-only, context menus, element bounds, anchors, lives per recorder window (`Marks`);
  `PrepaintLedger` stores the slices; `Frame.replayPrepaintLedger` (the site at `Frame.swift:3998`) replays them;
  `Frame.movedPrepaintLedger` (`RetainedTranslation.swift:308`) is the translated variant.
- `LayoutMemo.PlacementKey(signature, proposal, bounds)` keys the origin (`SB-AD`); a shifted subtree misses (`FS-G`).
- `GlyphAtlas.dirtyRect` (`Atlas.swift:166`): one bounding tuple; one reader each in `MetalWindowRenderer.upload` (`Renderer.swift:765,793`),
  `HeadlessWindowRenderer.finishFrame` (`:82`), `SDLWindowRenderer` (`:351`, a bool to C: **SDL uploads the whole `aw*ah` atlas
  whenever anything is dirty**, `SDLBridge.c:1086-1100`), two SDL tests. It is public (`closeout-public-api.tsv:3000`).

## 2. Lane 1 - geometry notes replay (files: `GeometryChange.swift`, `RetainedPrepaint.swift`, `Frame.swift` replay site, tests)

- `PrepaintLog.geometry: [GeometryNoteRecord]`, `Marks.geometry`; `GeometryNoteRecord` = `(watch, key, owner, value: Any, global: Bounds)`.
  `noteGeometry` appends the record **instead of tainting** (the note itself still runs: a fresh build is unchanged).
- `PrepaintLedger.geometry` = the slice. Replay (untranslated, key equal) calls `LifecycleStore.noteGeometry` for each record in order,
  re-appends them to any outer open `prepaintLog`, and counts them (`LifecycleStore.workThisFrame` as a fresh note does; a
  `package` read-back `FrameWork`-adjacent counter `retainedReplayedGeometryNotes`, not public). Occurrence ordinals and `order` come out
  equal because notes replay in recorded order and the store numbers them.
- **A translated replay of a ledger holding a geometry note is refused by name `geometryTranslated`** (`RG-C`): the value is a user closure
  over a global frame that moved; re-evaluating it is carried (section 6).
- The graft is unaffected (it skips build recursion only; geometry notes are made in prepaint). Paint records are unaffected.
- `ModifierKeysChange` keeps its `taint("modifierKeys")` (`RG-D`, not in this item).

## 3. Lane 2 - placement translation and the carried pins (files: `RetainedTranslation.swift` (guard pins are tests only), `LayoutMemo.swift`,
`LayoutTree.swift` restore site, tests)

(a) **Measure first** (commit 1: counters of the FS shift fixture, `FinerScopesMeasure` re-taken: `layoutMemoRootHits/Misses`,
`layoutSignatureNodes`, F2/F3 rows). `RG-E`: build translation only if placement misses are the dominant remaining cost of the shifted
frame; else rule it not justified with the figures. If built: a second dictionary `translatedPlacements` keyed `(signature, proposal,
width, height)` (origin-free) holding rects **relative to the bounds origin**; `lookupPlacementTranslated` adds the new origin, **only
when every relative and absolute coordinate is an exact sixteenth** (the `isExactSixteenth` rule of `RK-S`), else the old exact-origin key
decides. Existing methods and the two-generation sweep gain two lines each and nothing else (C14-e's `Footprint` touch merges beside).
`METALUI_VERIFY_LAYOUT_MEMO=1` recomputes every translated hit and traps.
(b) Pin `hitboxClipped`: an occurrence containing a legacy `clipped(to:offsetBy:)` region whose hitbox is registered at an inner clip
depth, shifted so the inner hitbox (i) stays strictly inside the ambient clip before and after (moves, equals fresh) and (ii) touches
the ambient clip after (refuses `hitboxClipped`, the occurrence runs its prepaint, equals fresh).
(c) A shift under a moved render effect: measure; `RG-G` pins the current refusal (reason by name) or, if cheap, replays it. Default:
pin the refusal.

## 4. Lane 3 - per-shelf atlas dirty rects (files: `Atlas.swift`, `Renderer.swift`, `HeadlessWindowRenderer.swift`, `Backends/SDL`, tests)

- `GlyphAtlas.dirtyRects: [(x,y,width,height)]` (public, doc comment, map row): `markDirty(slot)` extends the last rect when the slot is on
  the same shelf row (`slot.y == last.y`) and **x-adjacent** (`slot.x == last.x + last.width`), height `max`; else appends. **Cap 8**:
  the ninth collapses the list to its bounding rect (a one-element list). `dirtyRect` stays as the computed union of the list (every
  old reader and test compiles; `RG-H`). `clearDirtyRect()` clears both. `theDirtyRectIsTheUnionOfWhatWasWrittenAndClears` stays green
  unedited.
- Metal: `upload` loops `replace(region:)` over `dirtyRects` (bytesPerRow stays the atlas width); the full-upload branches unchanged.
- Headless: `lastAtlasUploadPixels` = sum of rect areas.
- SDL: `mui_renderer_finish` takes `const uint32_t *atlas_rects, uint32_t atlas_rect_count` in place of `bool atlas_dirty`; a new atlas
  or size change still uploads whole; otherwise the transfer buffer packs the rects tightly (one packed copy) and one
  `SDL_UploadToGPUTexture` per rect with `pixels_per_row = rect width` and the packed offset. A package C recorder
  `mui_renderer_last_atlas_bytes` lets a test read the bytes moved. No shader change; `Backends/SDL` run on macOS and in the Linux image.

## 5. Tests (name - red before - mutation that must redden)

Lane 1 (`Tests/MetalUITests/RetainedGeometryTests.swift`):
1. `aGeometryScopeInAnEquatableOccurrenceDoesNotTaintItsLedger` - at `99b21a1c` `reasons["geometryChange"] > 0` each steady frame; after
   0 and prepaints skipped. Mutation: restore the `taint` line.
2. `aReplayedGeometryNoteDeliversNothingUntilTheValueChanges` - steady frames deliver 0 actions after the initial one. Mutation: drop the
   re-note on replay (the next build reports `initial` again: reddens 2 and 3).
3. `theDeliveredValuesEqualAFreshWindowsOverAScript` - resize, scroll, shift script, retention on vs `testingRetainedSubtrees = false`,
   equal sequences. Mutation: replay with the previous frame's size.
4. `aGeometryNoteUnderAChangedRenderEffectMissesAndDelivers` - `.scaleEffect` above the occurrence changes: ledger misses, new value
   delivered. Mutation: leave `composed` out of the ambient comparison.
5. `aTranslatedReplayOfAGeometryNoteIsRefusedByName` - a scrolling shift refuses `geometryTranslated`, equal to fresh. Mutation: let the
   translated ledger through.
6. `twoGeometryScopesStackedAtOnePositionKeepTheirOrdinals` - two scopes, replay order equals fresh. Mutation: replay reversed.
Whole-suite runs with `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`.

Lane 2 (`PlacementTranslationTests.swift`, `HitboxClipGuardTests.swift`):
7. `aWholePixelShiftReusesTheRecordedPlacementTranslated` (only if `RG-E` builds): root hits up, signature nodes down on the shifted
   frame, rects equal fresh. Mutation: key the origin again.
8. `aNonSixteenthShiftFallsBackToTheExactKey` - Mutation: drop the exactness guard (reddens through `VERIFY_LAYOUT_MEMO`).
9. `anInnerClippedHitboxInsideBothClipsMoves` / 10. `anInnerClippedHitboxTouchingTheAmbientClipRefuses` - Mutation: delete the
   `guard inside(b), inside(moved)` line; 10 must redden (11. a pin of the refusal's counter reason `hitboxClipped`).
12. `aShiftUnderAMovedRenderEffectIsRefusedByName` (or replays, per `RG-G`) - Mutation: remove the effect refusal.

Lane 3 (`GlyphAtlasDirtyRectsTests.swift`, `HeadlessAtlasUploadTests`, `SDLAtlasUploadTests`):
13. `twoGlyphsOnDistantShelvesCountTheirOwnAreasNotTheSpan` - red at `99b21a1c` (counts the span). Mutation: `markDirty` back to the bounding box.
14. `adjacentSlotsOnOneShelfMergeIntoOneRect`. Mutation: drop adjacency merge (count 2).
15. `theNinthRectCollapsesToTheBoundingRect`. Mutation: raise the cap to 16.
16. `dirtyRectIsTheUnionOfDirtyRects`. Mutation: return only `last`.
17. `aTwoRectUploadLeavesEveryTexelEqualToTheAtlas` (Metal readback, 0 px) and 18. SDL `theAtlasTransferMovesOnlyTheRects` (bytes via the
    C recorder; macOS and Linux image on lavapipe; gated `.enabled(if:)` where the offscreen driver draws no frame). Mutation: pass `aw*ah`.
Guards: a typecheck guard `dirtyRectStaysReadableAsATuple` (plain import) - mutate by making `dirtyRect` internal.

## 6. Demo, human checks, deferred

- Demo: `METALUI_RETAINED_DEMO=1` gains a geometry-reader card in its own function (Windows 1 MB stack): the panel strip's
  prepaints count stays low with the reader present. A text-heavy card on two shelves shows the atlas figure.
- Human checks group `RG` (not run, an agent cannot): RG1 the geometry card's reported size follows a real window resize and a scroll
  with retention on, same as off; RG2 first-use text on distant shelves renders on Metal and SDL (no blank glyph) after a font-size
  change; RG3 SDL Windows D3D12 atlas copy (CI only).
- Deferred: re-evaluating a geometry closure under translation (owner: a later C14 item, if MetalCreator's scroll figures ask;
  `RG-C`); `onModifierKeysChanged` replay (`RG-D`); atlas eviction and a rect-merge threshold with a gap (`RG-H`).
