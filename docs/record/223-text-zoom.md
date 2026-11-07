# Record 223: text under transforms (R4-5 PR E)

Branch `feat/text-zoom` (master `9116adff`). Rulings `TZ-A`..`TZ-F` (new prefix; `docs/superpowers/2026-11-07-text-zoom-decisions.md`, next `TZ-G`). **Divergence 109 retired** (`TZ-B`), **106 narrowed** (`TZ-A`, `TZ-C`, `TZ-D`), **224 and 1065 amended**; the live count is 208 (209 - 1) and the next label 226. Probe `docs/probes/swiftui-text-under-transform.swift` (commit `3a795e14`). Plan: the reviewed R4-5 PR E plan (`tz-plan.md`); the deviations are in section 5. Run 1 (probe, lane 1, `63b0f767`..`aaf53ea0`) and run 2 (lane 2, parity frame 20, demo strip, ledger) are one record.

## 1. What was measured (probe, compiled `ImageRenderer`, `-O`, two byte-identical runs, 25 lines)

Readings that decide the design (the lines are in the probe header as `[MEASURED]`):

- **Z0 reproduces T15b**: partial pixels 326 (20 pt scaled 2x) / 298 (native 40 pt) / 1237 (bilinear upscale). Its "differing" count is 1237 against T15b's recorded 1444: the macOS 27.0.1 raster differed by a few pixels from this machine's 27.2; the partial counts that carry the claim did not move.
- **Z1, Z6, Z7: under `scaleEffect` SwiftUI re-rasterizes**, per axis and with no cap seen: Z1 (1.5x) 246 partials vs 253 vector, 237 native 30 pt, 685 resample; Z6 (`x: 2, y: 1`) 227 vs 215 vector, 229 for a device-scale-2 raster squeezed, 512 resample; Z7 (20 pt "H" at 8x and 20x) 578 vs 477 native / 9648 resample, and 1443 vs 1443 exactly. Z2 (0.5x) does not separate a re-raster from a box downsample (77 / 79 / 81). The cap and floor in lane 2 are MetalUI's, not SwiftUI's.
- **Z3, Z4: under `rotationEffect` SwiftUI is vector-exact** (Z3 187 partials vs 194 vector vs 303 bilinear rotation; sad 25.5 vs 42.7 against a floor of 22.7 on the upright control; Z4 380 vs 384 vs 1221). Scale-then-rotate and rotate-then-scale are 0 px apart. Rotated and skewed text therefore stays in 106's residue.
- **Z5, Z5b: a projection alone is a resample, a projection of a scaled text rasterizes at the scale.** `rotation3DEffect` of unscaled text: sad(sw, projected 1x raster) 21.3 (the floor) vs 38.8 against a 4x4 supersampled vector projection. With `scaleEffect(2)` first: 1844 partials (resample of 1x: 2823, device-scale-2 raster projected: 1255) and sad 244.9 to the 2x raster vs 403.8 to the 1x. **This contradicts the plan's σ over the projective Jacobian** (section 5, item 1): the projective factor must not raise the raster scale, only the flattening scale `f` does; the reviewed change (approved after run 1) takes `k` from `f` alone and gives the transform a factor of 1.
- **NC1-NC5: SwiftUI clips exactly** between two rotations (0 ink beyond 1 px of the rotated 60 x 60 square; the box model would add 2724 px), with rounded corners cut (3476 inside vs 3476.4 analytic), under an outer `rotation3DEffect` (6 px beyond the fitted quad, the same 6 the solid rect has), for an ellipse, and with a flattening `scaleEffect(2)` inside the clip. Stop condition 2 did not fire; 109 is real. (NC0 reproduces T7/T7b.)

Instrument limits: the CoreText vector reference's floor is sad 22.7 of 146.2 ink (P3); the quad fit's rms is 0.01 px (P4); the on-screen renderer is not `ImageRenderer` (human check `TZ1`, run 2).

## 2. Lane 1: the design as built (`TZ-B`, run 1)

`Frame.paintWithDeviceMap` opens a **mask scope around a non-flattening effect scope** when `nestedClipMask()` returns a mask: `paintWithMask(primitive:maskDepth:)` with the clip in force as a white rounded rect, emitted in the space outside the new scope, so every enclosing effect maps it on its way out (`RenderEffect.apply` maps a mark's masks, `CM-A`). The scope's own outer mask stays the screen box, a superset the mask multiplies. Counter `nestedClipMasks` (frame-local). Fixture stays v9; no renderer change.

`nestedClipMask()` is `nil` (the box stays) when:
- no clip was pushed since the innermost non-flattening effect (`clipDepth <= clipBase`), or no non-flattening effect encloses the clip before a barrier;
- a scope that is not a flattening **effect** (a transition, capture or fade) opened after the clip was pushed (`aClipAroundATransitionAroundARotationKeepsTheBox`; the transition's own map is a uniform scale and could be undone, it is not here);
- a mask scope already cuts the clip in force (an ellipse or path clip, a crossing pair): the new path would add a second, redundant group;
- the composed map of the enclosing effects keeps the clip an axis-aligned rect and the clip has no rounded corner (a quarter turn: the old arithmetic, `aClipBetweenRightAngleRotationsTakesNoGroup`).

The mask rect is the clip (bounds, radii x scale), its content mask the clip grown by `max(16, size)` on every side (`CM-I`; never `Frame.unboundedMask`). Fallbacks are CM's: a material or glass inside keeps the box (`masksFlattenedBackdrop`), a group over 8192 draws per primitive (`masksFlattenedOversize`).

## 3. Lane 2: the design as built (`TZ-A`, `TZ-C`, `TZ-D`)

A glyph is emitted exactly as before. `Frame.insertIntoScene`'s `.glyph` arm calls `Frame.rekeyedGlyph(_:)` (`Sources/MetalUI/TextZoom.swift`), so every route into a scene re-keys: the root, `collectingIntoFreshScene` (opacity, filtered and masked groups), a gradient text's ink mask, ghosts (which replay the previous frame's scene, whose glyphs carry re-keyed slots: the reverse map holds those keys too, so the scale composes), drag previews, retained replays. `f = bounds.width / slot.width`; `k = TextZoom.rasterScale(f, emPixels:)` is the ladder `2^(n/8)` (a 3 percent scale rounds to rung 0 and is left alone), floored at 1/4 and capped at 256 px of em when it enlarges; `k == 1` inserts as before and **reads no dictionary** (counter `glyphRekeyLookups` is 0). Otherwise the key comes from `GlyphAtlas`'s new `package` slot-to-key map (`keysBySlot`, written on a pack miss, cleared by `reclaim()`), the pen from the bounds, the new variant from `GlyphImage.subpixelPlacement(forDeviceX: penX * r)`, `r = k / f`, and the glyph is drawn at `slot / r`. A refused or unknown glyph is drawn from its base raster and counted (`glyphRekeyFallbacks`). Counters `glyphsRekeyed`, `glyphRekeyFallbacks`, `glyphRekeyLookups` (frame-local, three `everyFrameChannelIsClassified` rows). **No `CapturedPrimitive`, `TextSystem`, bridge, shader, fixture or `CoreTextTextSystem`/`PortableTextSystem` change**: `GlyphKey` already had `scaleFactor` and both systems honour it (stop condition 3 did not fire).

## 5. What the code and the probe forced (deviations from the plan)

1. **The raster scale comes from the flattening scale alone** (the reviewed change after run 1; probe `Z5`, `Z5b`). The transform contributes 1: a projection of unscaled text keeps the device-scale raster, a scale **inside** a rotation or projection (which flattens) re-rasterizes at the scale, a scale **outside** a rotation does not flatten and keeps the device raster. Test 11 was reworked (`aScaleInsideARotationRasterizesAtTwoAndOneOutsideItKeepsTheDeviceRaster`: the plan's "both orders rasterize at 2" is false under this rule, and SwiftUI is vector-exact for both orders, `Z4`, so the outside order is 106's residue); test 12 became `aProjectedUnscaledTextKeepsTheDeviceScaleRaster`, with a second arm for the scaled-then-projected text (`Z5b`).
2. **The 256 px cap and the 1/4 floor are MetalUI's, not SwiftUI's** (`Z7`: sharp at 20x). They are in 106's residue (`TZ-C`).
3. **The ladder is `2^(1/8)`** (`Z1` shows SwiftUI exact at 1.5x, which is a rung of 1.542 here: a resample of at most 4.4 percent; the ladder stays in the residue).
4. **A third counter, `glyphRekeyLookups`** (not in the plan): without it "the common case reads no dictionary" is an unpinned claim, and mutation T12 (the lookup moved ahead of the rung check) has nothing to redden, since a lookup for an f = 1 glyph changes no other counter.
5. **A bare `Text(...).scaleEffect(...)` does not animate in the `TransitionHarness`** while the same text under a `.frame(width:height:)` does (measured: both reach the settled scale on the first frame without it); test 13 therefore frames its text. Not investigated further; no divergence claimed.
6. **NC5's extension was taken** (run 1, item 2 of the draft): about 12 lines; test 5 pins exactness.
7. **A latent bug found by parity frame 20's first render and fixed** (lane 1): a nested clip (and, before this change, the box that stood for it) under an **enclosing flattening effect** (`.offset`, a scroll's translation) did not move with the effect. The content's screen box, `t.outerMask`, was intersected with the outer rotation's entry clip and relabelled with that clip's (shallower) `outerDepth`, so the flattening effect did not count it as pushed inside it and left it in place: the shifted content was cut at the unshifted edge (81 px of ink became 71 under `.offset(x: 10, y: 10)`; with the box model, before this PR, the ink did not move at all). Fix in `RenderEffect.applyToShape`: a box that lies inside the enclosing clip came from the deeper clip alone and keeps its (deeper) `outerDepth`. New test `aNestedClipUnderAnEnclosingOffsetMovesWithIt` (mutation L9). The same relabel applies to every nested non-flattening effect pair under a flattening one, so a rotated clip inside a scrolled container is the case this fixes in the real world; no test could have seen it before frame 20 (the lane 1 tests have no enclosing offset), which is why the frame contains the pair inside the stack's `.offset`.
8. **Stop conditions.** 1 (Z0 reproduces T15b, Z1, Z2 show re-rasterization) and 2 did not fire in run 1; 3 (`TextSystem` change, `CoreTextTextSystem.rasterize` trapping on a re-keyed font from the production path) did not fire; 4 (an allocation pin, the 1 MB stack test, `MemoryLayout<CapturedPrimitive>` or the fourteen images moved for a tree with no paint scope, or an `RZ-`/`HP-` work pin for anything but glyph rasterization) did not fire (section 7); 5 (parity beyond the glyph tolerance) did not fire; 6 (the fixture cannot carry a grown atlas) did not fire: frame 20's atlas starts at 256 and grows to 1024 and the fixture replays on Metal, SDL-over-MSL and llvmpipe; 7 (an animated zoom inflating the atlas past 4096 with drops) was not reached (a one-glyph 120-tick zoom made at most 32 rasters, test 13); 8 did not fire (a mask scope at the nested entry forced no new refusal).

## 6. Lane 2 mutations (run 2; in place after committing the sources, the files restored with `git checkout` after each, because the disk had 11 GB free; filter: the nine lane-2 tests, the old scale-transition pin and the render test, 15 tests)

| # | Site and spelling | Reddened |
|---|---|---|
| T1 | `insertIntoScene`: `scene.insert(glyph, ...)` (the re-key disabled) | tests 9, 11, 12 (the scaled arm), 13, 14, 15, 16, 17, 18, 21 and the moved scale-transition pin (11 tests) |
| T2 | `rekeyedGlyph`: `f = 1.0` (the flattening scale ignored: nothing is left to key on) | the same 11 |
| T3 | `TextZoom.rung`: `.rounded()` to `.rounded(.up)` (no snap near 1) | test 10 (its 3 percent arm; a rotation has f = 1 exactly) |
| T4 | `rekeyedGlyph`: `r = k` (the flattening scale dropped from the pen and bounds mapping) | tests 9, 14, 21 and the scale-transition pin |
| T5 | a factor of 1.5 on `f` for a glyph inserted with a transform record (a projection's σ), spelled as a `sigma:` parameter the arm passes; **the first spelling, `glyph.transform != 0`, was inert: the record is assigned by `scene.insert`, after the re-key** | tests 10, 11, 12, `plainTextOutsideEveryScopeIsUnchanged` and the existing `aGradientTextUnderARotationTurnsEveryGlyphMask` |
| T6 | `rasterScale`: the exact `f` as the raster scale (no ladder) | tests 13 and 14 |
| T7 | `rasterScale`: the cap removed (`n = max(0, n)`) | test 14 |
| T8 | the arm: a glyph the atlas refused is not inserted | test 15 |
| T9 | `Frame.replayPaint`: glyphs inserted unre-keyed for the whole replay (`TextZoom.mutantNoRekey`); **the first spelling, only the fast path's `insertLeaves` loop, was green**: the zoom fixture's replays take the `processScopes` branch | test 16 |
| T10 | `TransitionStore.draw(ghost)`: the ghost's captures inserted unre-keyed | test 17 |
| T11 | `collectingIntoFreshScene`: the body runs unre-keyed (only the root scene re-keys) | test 18 |
| T12 | `rekeyedGlyph`: `glyphRekeyLookups += 1` before the rung check | test 19 |
| T13 | `GlyphAtlas.reclaim()`: `keysBySlot` not cleared | test 20 |

**Green, explained.** T5's first spelling (inert, above) and T9's first spelling (a branch the fixture does not take) were green and were respelled. Test 8, `anEllipseClipBetweenNestedRotationsWasAlreadyExact`, is a control and green by design. `plainTextOutsideEveryScopeIsUnchanged` is red under T12 only through the new counter (item 4). Test 21 (`aTwiceScaledTextHasTheSharpnessOfTwiceTheSize`, Metal) is red under T1.

## 7. Pins moved (each with its cause)

- `RenderEffectTests.aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox`: deleted (109 retired, run 1).
- `PathTests.aTextUnderScaleEffectIsResampledNotReRasterized`: deleted (106 narrowed); replaced by test 9 in `TextZoomTests`.
- `TransitionTests.aScaleTransitionScalesTheGroupsPrimitivesAboutItsAnchor`: its glyph arm read "the glyph resamples the same atlas slot" under a half-way `.scale` transition; the glyph is now re-rasterized at the 0.5 rung, so it reads "a smaller atlas slot, drawn within the ink padding (two pixels) of half the settled size, about the same centre within two pixels".
- `RetainedSubtreeInternalTests.everyFrameChannelIsClassified`: `nestedClipMasks` (run 1), `glyphsRekeyed`, `glyphRekeyFallbacks`, `glyphRekeyLookups` (all `.frameLocal`).
- `LooksLifecycleDemoTests.theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`: its fake window is 1500, not 1400. Adding the demo's text-zoom strip made the demo taller, a legacy flex column that overflows its window shrinks its children, and the test finds the stepper's halves by their 20 x 12 size (0 found). Measured: even a one-`Text` row in the strip's place reddened it, so the budget was already spent; no other looks test moved (`LooksColourDemoTests`, `ShadowTests` read 1400 and pass).
- `RPSnapshot` (`RetainedPrepaintTests.swift`), **only under `METALUI_VERIFY_RETAINED=1`**: a glyph's `atlasBounds.origin` is zeroed before the comparison. `aZoomedNodeIsHitWhereItIsDrawn` reddened at its second zoom step (`differences: ["glyphs"]`): verify mode builds a replayed frame whose scene is discarded and then the fresh one, and a glyph re-keyed at insert packs its raster when a scene first holds it, so the retaining window's atlas packed the same rasters in another order than the unretained window's. Same glyphs, same slot sizes, other slot origins; an origin names no pixel two atlases share. Not a visual difference and not a retained-replay bug (the non-verify run, which has no discarded frame, compares the origins and passes); the finding is that **lazy packing at insert makes a slot origin order-dependent**, which any future snapshot comparing slot origins across two windows meets in verify mode.
- `GuideDocCheck.noGuideCitesARetiredDivergence` reddened on `docs/guides/drawing-and-gpu.md` (it cited 109 and the old 106 wording); the guide was reworded.
- None else: the unfiltered run and the `METALUI_VERIFY_RETAINED=1` run read no other moved pin, no allocation pin, no `RZ-`/`HP-` pin, no stack test, no image.

## 8. Parity (frame 20 `textZoomFrame`, `--expect 21` on both lines of `sdl-gpu-linux.yml`)

31 glyphs, 3 masked groups (the two nested clips and the gradient text), 2 transform records: 16 pt text at `scaleEffect` 2, 1.5 and (a 32 pt label) 0.5; scaled then rotated; scaled inside `rotation3DEffect`; a gradient text at `scaleEffect(2)`; the NC1 and NC2 clips inside the stack's `.offset`; a plain label. Its atlas starts at 256 and may grow to 1024.

- [MEASURED] SDL-over-MSL (`swift run --build-system native -Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib Replay --portable --record`): frames 0-20 all `differing pixels=0, max channel delta=0`, frame 20 `720x380: 0 rects, 31 glyphs, 0 images, 2 transforms, 3 groups, 5 runs`; the draw-order control detects (283 px, delta 152).
- [MEASURED] llvmpipe Vulkan (`metalui-portable`, `PortableReplay ... --driver vulkan --dump --expect 21`, the worktree mounted): PASS over all 21; **frame 20 outside sprites 0 px max D0 (<=1), inside glyph and image quads 2485 px max D3 (<=8)**; frame 19 16901 px D3, frame 18 D1, frames 12 and 13 D3 against 3, unchanged. The tolerance regions needed no extension. Not run: Direct3D 12 (CI's `root-windows` line, `--expect 21` there too).
- The first render of frame 20 showed the nested clips cut flat on their right and bottom edges, on Metal and SDL alike (they agreed): the offset bug of item 7.

## 9. Runs

Head: the commit that adds this record's final text; macOS 27.2, Xcode toolchain.

- `swift package clean`, `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel` unfiltered (head `05aaa622` plus the lifecycle window): `✔ Test run with 5355 tests in 14 suites passed after 481.373 seconds.` and `FR-J no-argument frame: succeeded=true`. A third unfiltered run at the final head (comments and `RPSnapshot` only since) read `✘ Test run with 5355 tests in 14 suites failed after 401.404 seconds with 1 issue.`: `aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged` (`PlatformTests.swift:259`, a real mouse event's scrolling deltas), green in the run before it, in the verify run after it and alone: **environmental, not this PR** (CLAUDE.md names environmental failures).
- `METALUI_VERIFY_RETAINED=1`, the same: `✔ Test run with 5355 tests in 14 suites passed after 338.539 seconds.` and `FR-J no-argument frame: succeeded=true` (after the `RPSnapshot` verify-mode relaxation, section 7; before it `aZoomedNodeIsHitWhereItIsDrawn` read red).
- Portable container (`metalui-portable:latest`, a `git archive` of `05aaa622`, `swift build --build-tests` then `swift test --skip-build --no-parallel`): `✔ Test run with 809 tests in 10 suites passed`, then `9`, `16`, `73`, `68`, `49`, `286`, `154`, `24` tests passed (`everyProductionTreeBuildsOnAOneMegabyteThread` included).
- `Backends/SDL` in the Linux image by filter `ReplayFixture|SDLGroup|SDLClipMask|SDLTextGradient`: `40 tests` and `15 tests` passed (nothing added there).
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh`: both print nothing (no public declaration was added; the atlas accessors are `package`).
- Guards: this PR adds none; call sites not re-counted.
- Disk: mutations ran in place after committing the sources (11 GB free), not in a scratch worktree; the Docker volumes `mui-tz-build` and `mui-tz-root` and the scratch archive were removed afterwards.

## 10. Not run

Human checks `TZ1`..`TZ6` (an agent cannot); the Windows ARM VM and Direct3D 12; the portable text system on a real Linux or Windows window; the 100k-row list test (env-gated); `Backends/SDL`'s whole target (it exits mid-run on macOS, by filter only).
