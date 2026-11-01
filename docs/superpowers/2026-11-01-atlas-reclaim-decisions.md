# Glyph atlas reclaim (item MF-atlas, MetalFlow 2026-11-01) - decisions

Rulings for the full-atlas bug MetalFlow reported. Prefix `GL-`. **Next unused: `GL-K`.** Record: `../record/184-atlas-reclaim.md`.
Branch `fix/atlas-reclaim` from master `3a2c5715`. Divergence labels 985-994 reserved: **none taken** (`GL-I`).

## The bug, as measured

`Window.atlasExtent` was 1024 square, the shelf packer never reclaimed a row, and `GlyphAtlas.evictUnusedSince` had no caller (and would have
stranded the evicted pixels). When the atlas was full, `Frame.draw` returned silently: MetalFlow's node cards use `.font(size: 14 * zoom)`, so each
zoom level is a new set of `GlyphKey`s; a headless sweep from 25% to 150% in 1% steps at scale 2 filled the 1024 rows and every new glyph after that
was dropped ("150%" drew as "15 %") until the window was reopened.

**What the report did not say, and the design turns on.** A glyph's atlas rect is held by far more than the frame being painted. A `MUIGlyph` carries
`atlasBounds`, and `MUIGlyph` is stored in: the retained paint record (`CapturedPrimitive.glyph`, `RetainedSubtree`), the translated copies of it
(`RetainedTranslation`), a transition's captures and its ghosts (`TransitionStore`), a drag session's snapshot (`DragSession`), a raster key
(`Shadow.keyLeaf` adds `g.atlasBounds`) and the retained verify snapshot. A rebuild that moves glyphs makes every one of them name another glyph, or
none. `SB-I` (retained-subtrees decisions) had already ruled that replaying a glyph stamped in a past frame "is only sound while nothing evicts" and
pinned it with a grep for any `evictUnusedSince(` caller. This work is the first thing that moves a slot, so it amends `SB-I` (`GL-F`).

## GL-A - reclaim at a frame boundary; never restart a frame

**Ruling.** The rebuild (`GlyphAtlas.reclaim()`) runs in `Window.draw`, once, **before the first build of the draw and outside every phase**
(`reclaimAtlasIfNeeded()`); `precondition(!isBuildingFrame)` makes any other call trap. It clears the packer, the pixels and the key table, advances
`GlyphAtlas.layoutGeneration`, and re-rasterizes **lazily**: a glyph is rasterized again by the first paint that asks for it, in paint order, so a
rebuilt atlas holds what a fresh one would hold after that frame. `wantsReclaim` decides (`GL-H`).

**Why not restart the frame (the brief's first option).** Restarting needs a frame to be redoable at the point a glyph does not fit, which is mid-paint.
The window has one redo (`RK-C`/`RK-D`), and it is not free: it needs `animationStore.checkpoint()` taken before the build, which the window takes only
when a prepaint replay might force a redo (`memos.prepaintReplayAllowed && ledgerEntries > 0`). Taking it every frame is a per-frame cost the brief rules
out; taking it only "near full" leaves the jump from half-empty to overflow unprotected, so two paths would exist, one untested in the case that matters.
Growth (`GL-B`) makes the restart unnecessary: the only reason to restart is that something already emitted would point at moved pixels, and growth
moves none.

**The one case that is not covered inside the frame** is the atlas at its cap holding older frames' glyphs while the current frame needs room: it cannot
grow and cannot rebuild mid-frame. It drops (`GL-E`) and sets `reclaimRequested` only if older glyphs held room (`packedArea > frameLiveArea`, so a frame
that dropped with nothing older to free does not ask). `Window.draw` then calls `setNeedsRedraw()` **after the frame**, which is the same place the
`finishFrame` failure already does it - not a `StateTable` write, not `requestAnotherFrame()`, nothing in a phase. The next frame starts with
`wantsReclaim` true, rebuilds, and draws every glyph. **Chosen: next-frame recovery for that case only**, because the alternatives cost every frame.
**Cost if wrong.** One frame at the cap can show missing glyphs; before this it was every frame for ever.

## GL-B - growth keeps every slot where it is

**Ruling.** When a glyph does not fit and the atlas is below `maximumExtent`, `GlyphAtlas.packed(for:rasterize:)` doubles both sides (`width * 2`,
`height * 2`, each capped) and tries again, repeating until it fits or the cap stops it. `resize` re-lays `pixels` out at the new row stride so **every
slot keeps its (x, y)**; the shelf packer's cursor stays valid, and the open shelf simply continues into the new width. Therefore a rect emitted earlier
in the same frame, and every retained record, stays true across growth, which is why growth does not advance `layoutGeneration`. The whole atlas is dirty
afterwards (`markEverythingDirty`) so a renderer that tracks only dirty rects still re-uploads it; both renderers also compare the extent and re-create
the texture on a size change (Metal `Renderer.upload`'s `sizeChanged`; SDL `atlas_new`), which `aGrownAtlasReplacesTheTextureAndKeepsEarlierGlyphs`
(Metal) and `aGrownAtlasIsRecreatedAndFullyUploaded` (SDL) pin.

**Shrinking.** `reclaim()` sizes the atlas for the working set: the smallest power-of-two multiple of the starting size, not above the cap, whose area is
three times what the last frame used plus what it was refused (`frameLiveArea + frameDroppedArea`). An atlas that grew for one busy frame is small again
after a rebuild, and a steady large working set does not shrink and regrow every frame. **Cost if wrong.** A re-created texture on a size change.

## GL-C - the cap, and who may grow

**Ruling.** `Window.atlasMaximumExtent = 4096` (16 MB of R8): every Metal GPU family, Vulkan's guaranteed `maxImageDimension2D` and D3D12 accept it, and
it is a documented safe cap rather than a per-device query (neither the window nor `GlyphAtlas` holds a device; the cap is a static, easy to raise).
`GlyphAtlas.init(width:height:maximumExtent:)` takes the cap as an optional argument; **the default is "no growth"** (`max(maximumExtent ?? 0, width,
height)`), so every existing user of the type (`PortableText` emitters, the SDL tests, `drawText`'s sink, the packer-geometry tests) keeps its geometry and
its `nil` on a full atlas. Only `Window.makeGlyphAtlas()` - the window's atlas and `Frame`'s default - opts in. **Cost if wrong.** A GPU with a smaller
limit fails the texture creation, which `Renderer.upload` already handles by drawing no text (`atlasTexture = nil`).

## GL-D - every holder of a slot either keys on the generation or is dropped

**Ruling.**

1. **Keyed.** `AmbientKey.atlasGeneration` (set by `retainedAmbientKey()` from `glyphAtlas.layoutGeneration`) is part of `==`, so the retained paint
   record, the prepaint ledger key and every relation built on them (`effectRelation`, translation) miss after a rebuild; `differences(from:)` names it
   (`atlasGeneration`). `BuildKey.atlasGeneration` is the same for a graft. **Why the graft needs it though it paints nothing:** a graft stands for a build
   whose prepaint key (which carries the generation) will refuse after a rebuild, and a graft the prepaint then refuses is a **redo of the whole frame**
   (`RK-C`, `EquatableComponent.prepaintGroup`'s `grafted` arm). Measured: without `BuildKey.atlasGeneration` the first frame after a rebuild redid
   (`retainedRedos == 1`) and the abandoned attempt packed glyphs in the wrong order, so the presented atlas differed from a fresh window's. The raster
   key adds the generation next to `g.atlasBounds` (`Shadow.keyLeaf`): two rebuilds can put different glyphs at equal rects.
2. **What a retained record stores.** A `MUIGlyph` by value, rect included (not a `GlyphKey`). Storing keys would make every replay hash and look up
   every glyph (`HP-B`'s hot path) to avoid one rare miss; the key is the cheaper correct choice.
3. **Dropped.** A transition's captured sprites and its ghosts' (`TransitionStore.forgetCapturedPrimitives()`) and a drag session's snapshot
   (`dragSession?.snapshot = []`) hold sprites and no keys; they cannot be re-rasterized. They are forgotten **once, on the frame the generation changed**
   (`reclaimAtlasIfNeeded` compares the generation it last saw, so a rebuild by anyone between frames is noticed). A ghost in flight at that moment stops
   drawing; the next removal ghosts normally. **Cost if wrong.** A fade-out cut short, once per rebuild (rare: only after the atlas is nearly full of stale
   glyphs).
4. **Not holders.** `Blur`/`Shadow` read atlas pixels at insert time inside one frame; `SurfaceText` records into a per-frame sink; `lastScene` is
   observed, never replayed. None survives a frame boundary.

**Cost if wrong.** A holder missed here shows another glyph at an old rect, which nothing in the suite can see except by comparing against a fresh window
(`aRetainedOccurrenceMissesAfterTheAtlasIsRebuilt`).

## GL-E - past the cap: drop, count, say so once

**Ruling.** A glyph that fits nowhere after growth is dropped: `packed` returns `nil` (not cached), `GlyphAtlas.droppedGlyphs` increments (a request
count: a glyph asked for by every frame counts every frame), and `Window.noteAtlasPressureAfterFrame()` prints one line to stderr in a DEBUG build the
first time the counter is non-zero. `MetalUIScene` imports no Foundation (`PS-A`), so the line is written by the window, not the atlas. Tests read the
counter (`pastTheCapGlyphsAreDroppedAndCounted`).

## GL-F - `evictUnusedSince(_:)` is removed; `SB-I` is amended

**Ruling.** The method was public API with no caller and a mechanism (`placed.filter`) that stranded pixels; the rebuild supersedes it. It is removed
(class X in the inventory: nothing to add; the map family needed no edit because the census row is gone). `docs/migration.md` has the row. `SB-I`'s guard
`theGlyphAtlasHasNoEvictionCaller` becomes `theGlyphAtlasIsReclaimedOnlyAtTheTopOfADraw`: **the only caller of `reclaim()` is `Window.swift`**, and
replay's soundness now rests on the key (`GL-D`) instead of on "nothing moves". `beginFrame()`/`endFrame()`/`currentGeneration`/`isBuildingFrame` stay:
the stamps now feed `wantsReclaim`, and `isBuildingFrame` is what makes `reclaim()` trap mid-frame.

## GL-G - the hot path

**Ruling.** Per glyph hit: the generation is stamped **only when it changed** (once per glyph per frame, not on every use), and the same branch adds the
glyph's area to `frameLiveArea`. That is one compare on a path that already wrote the stamp. Per frame: `wantsReclaim` is one integer comparison
(`(shelfY + shelfHeight) * 4 >= height * 3`) when the atlas is not three quarters through its rows; only past that does it read the stale-area ratio, and
only a rebuild does O(atlas) work. `aSteadyWindowNeverRebuildsOrGrows` pins that a steady window reports zero rebuilds, growths and drops.

## GL-H - when to rebuild

**Ruling.** `wantsReclaim` = `reclaimRequested` **or** (three quarters of the rows used **and** at least a quarter of the packed area untouched by the
last frame). An atlas full of glyphs the last frame used has nothing to give back - a rebuild would rasterize all of them again to land where they
are - and grows instead. `frameLiveArea` is counted at the first use of a glyph in a frame (hit) and at its packing (miss); `beginFrame()` zeroes it, so at
the top of a draw it holds the **previous** frame's. **Cost if wrong.** A rebuild one frame late, or an unneeded one (one frame of re-rasterizing).

## GL-I - class M, no divergence

**Ruling.** SwiftUI has no glyph atlas: no probe, no claim, class M. None of 985-994 is taken and nothing is published (`BS-H`); the live divergence
count and next label are unchanged. Public API added to `GlyphAtlas`: `init(width:height:maximumExtent:)`, `maximumExtent`, `initialWidth`,
`initialHeight`, `layoutGeneration`, `growCount`, `reclaimCount`, `droppedGlyphs`, `reclaimRequested`, `wantsReclaim`, `reclaim()`; `width`/`height`
become `private(set) var`. Removed: `evictUnusedSince(_:)`.

## GL-J - what is not done (carried)

- No pixel-preserving compaction: a rebuild re-rasterizes the live set (one frame's work) instead of copying live bitmaps to new places. Copying would
  keep the key table valid but needs the same generation key for every holder and saves only a frame of rasterization.
- No per-device texture limit query; the cap is a static (`GL-C`).
- Ghosts and a drag preview in flight at a rebuild are forgotten (`GL-D` 3).
