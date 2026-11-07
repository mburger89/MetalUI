# Record 222: text under transforms (R4-5 PR E) — DRAFT, run 1 of 2

Branch `feat/text-zoom` (master `9116adff`). Rulings `TZ-A`..`TZ-F` (new prefix) in a decisions doc run 2 writes; this run's ruling is `TZ-B` (the nested clip mask). Divergences **109 retired** (this run's code); **106 narrowed** (run 2). Probe `docs/probes/swiftui-text-under-transform.swift` (commit `3a795e14`). Plan: the reviewed R4-5 PR E plan (`tz-plan.md`); the deviations are in section 4.

**Status.** Run 1 (this file): the probe, lane 1 (109, `TZ-B`), its tests and mutations. Run 2: lane 2 (106, the re-key), parity frame 20, the demo strip, the ledger, the shards. Every `TODO(run 2)` below is run 2's.

## 1. What was measured (probe, compiled `ImageRenderer`, `-O`, two byte-identical runs, 25 lines)

Readings that decide the design (the lines are in the probe header as `[MEASURED]`):

- **Z0 reproduces T15b**: partial pixels 326 (20 pt scaled 2x) / 298 (native 40 pt) / 1237 (bilinear upscale). Its "differing" count is 1237 against T15b's recorded 1444: the macOS 27.0.1 raster differed by a few pixels from this machine's 27.2; the partial counts that carry the claim did not move.
- **Z1, Z6, Z7: under `scaleEffect` SwiftUI re-rasterizes**, per axis and with no cap seen: Z1 (1.5x) 246 partials vs 253 vector, 237 native 30 pt, 685 resample; Z6 (`x: 2, y: 1`) 227 vs 215 vector, 229 for a device-scale-2 raster squeezed, 512 resample; Z7 (20 pt "H" at 8x and 20x) 578 vs 477 native / 9648 resample, and 1443 vs 1443 exactly. Z2 (0.5x) does not separate a re-raster from a box downsample (77 / 79 / 81). The cap and floor in lane 2 are MetalUI's, not SwiftUI's.
- **Z3, Z4: under `rotationEffect` SwiftUI is vector-exact** (Z3 187 partials vs 194 vector vs 303 bilinear rotation; sad 25.5 vs 42.7 against a floor of 22.7 on the upright control; Z4 380 vs 384 vs 1221). Scale-then-rotate and rotate-then-scale are 0 px apart. Rotated and skewed text therefore stays in 106's residue.
- **Z5, Z5b: a projection alone is a resample, a projection of a scaled text rasterizes at the scale.** `rotation3DEffect` of unscaled text: sad(sw, projected 1x raster) 21.3 (the floor) vs 38.8 against a 4x4 supersampled vector projection. With `scaleEffect(2)` first: 1844 partials (resample of 1x: 2823, device-scale-2 raster projected: 1255) and sad 244.9 to the 2x raster vs 403.8 to the 1x. **This contradicts the plan's σ over the projective Jacobian** (section 4, item 1): the projective factor must not raise the raster scale, only the flattening scale `f` does.
- **NC1-NC5: SwiftUI clips exactly** between two rotations (0 ink beyond 1 px of the rotated 60 x 60 square; the box model would add 2724 px), with rounded corners cut (3476 inside vs 3476.4 analytic), under an outer `rotation3DEffect` (6 px beyond the fitted quad, the same 6 the solid rect has), for an ellipse, and with a flattening `scaleEffect(2)` inside the clip. Stop condition 2 did not fire; 109 is real. (NC0 reproduces T7/T7b.)

Instrument limits: the CoreText vector reference's floor is sad 22.7 of 146.2 ink (P3); the quad fit's rms is 0.01 px (P4); the on-screen renderer is not `ImageRenderer` (human check `TZ1`, run 2).

## 2. Lane 1: the design as built (`TZ-B`)

`Frame.paintWithDeviceMap` opens a **mask scope around a non-flattening effect scope** when `nestedClipMask()` returns a mask: `paintWithMask(primitive:maskDepth:)` with the clip in force as a white rounded rect, emitted in the space outside the new scope, so every enclosing effect maps it on its way out (`RenderEffect.apply` maps a mark's masks, `CM-A`). The scope's own outer mask stays the screen box, a superset the mask multiplies. Counter `nestedClipMasks` (frame-local). Fixture stays v9; no renderer change.

`nestedClipMask()` is `nil` (the box stays) when:
- no clip was pushed since the innermost non-flattening effect (`clipDepth <= clipBase`), or no non-flattening effect encloses the clip before a barrier;
- a scope that is not a flattening **effect** (a transition, capture or fade) opened after the clip was pushed (`aClipAroundATransitionAroundARotationKeepsTheBox`; the transition's own map is a uniform scale and could be undone, it is not here);
- a mask scope already cuts the clip in force (an ellipse or path clip, a crossing pair): the new path would add a second, redundant group;
- the composed map of the enclosing effects keeps the clip an axis-aligned rect and the clip has no rounded corner (a quarter turn: the old arithmetic, `aClipBetweenRightAngleRotationsTakesNoGroup`).

The mask rect is the clip (bounds, radii x scale), its content mask the clip grown by `max(16, size)` on every side (`CM-I`; never `Frame.unboundedMask`). Fallbacks are CM's: a material or glass inside keeps the box (`masksFlattenedBackdrop`), a group over 8192 draws per primitive (`masksFlattenedOversize`).

## 3. Mutations (in the lane's own worktree, the sources restored with `git checkout` after each; filter `NestedClipMaskTests|RetainedClipMaskTests|ClipMaskTests|aClipBetween`, 32 tests)

| # | Site and spelling | Reddened |
|---|---|---|
| L1 | `paintWithDeviceMap`: `paintWithMask(...)` replaced by `open()` (the mask scope never opened; the counter still moves) | `aClipBetweenNestedRotationsIsExact`, `aRoundedClipBetweenNestedRotationsKeepsItsCorners`, `aClipBetweenAProjectiveAndARotationIsAFiniteProjectedMask`, `aClipBetweenAFlatteningAndARotationIsStillExact`, `aNestedClipMaskAroundAMaterialKeepsTheBox`, `aRetainedReplayUnderANestedClipEqualsAFreshFrame` |
| L2 | `RenderEffect.apply`: the marks' masks not mapped (`guard ..., false`; the mask is not routed through the outer scope, so its transform is lost) | `aClipBetweenNestedRotationsIsExact`, `aRoundedClipBetween...KeepsItsCorners`, `aClipBetweenAProjectiveAndARotation...`, `aClipBetweenAFlatteningAndARotationIsStillExact`, plus CM's `anEllipseClipUnderARotationTurnsItsMask`, `anEllipseClipInsideAnOffsetMovesItsMask`, `aCrossingPairInsideAnOffsetMovesWithIt`, `aShadowOfAnEllipseClipIsElliptical` |
| L3 | `nestedClipMask`: the axis-aligned-and-square shortcut removed | `aClipBetweenRightAngleRotationsTakesNoGroup` |
| L4 | the mask rect's `cornerRadii` zeroed | `aRoundedClipBetweenNestedRotationsKeepsItsCorners` |
| L5 | the mask rect's `contentMask` = `Frame.unboundedMask` | `aClipBetweenAProjectiveAndARotationIsAFiniteProjectedMask` |
| L6 | the flattening scopes' map not accumulated (`after`), the clip emitted unmapped | `aClipBetweenAFlatteningAndARotationIsStillExact` |
| L6c | `guard scope.kind == .effect, scope.flattens` reduced to `guard scope.flattens` (a transition or fade counted as a flattening effect) | `aClipAroundATransitionAroundARotationKeepsTheBox` |
| L7 | `ClipMask.paintWithMask`: the backdrop guard skipped (`if false, captures.contains...`) | `aNestedClipMaskAroundAMaterialKeepsTheBox`, CM's `aMaterialInsideAShapeClipClipsToItsBox` |
| L8 | `replayPaint`'s fast path: `insertLeaves` per op replaced by `insertIntoScene` per primitive | `aRetainedReplayUnderANestedClipEqualsAFreshFrame`, CM's `aRetainedReplayOfAMaskedClipEqualsAFreshFrame`, `aMaskedClipInsideAnOccurrenceMissesWhenItMovesAndEqualsAFreshFrame` |

**Green, explained.**
- **L6b** (the `scope.flattens` half of the same guard dropped, leaving `scope.kind == .effect`): green, **unreachable**. A non-flattening effect opened after the clip push sets `clipBase` to the clip's depth, so `clipDepth > clipBase` fails before the loop; the half is a belt over `clipBase`. L6c (the other half) is the live spelling.
- `anEllipseClipBetweenNestedRotationsWasAlreadyExact` is green on arrival by design (a control); it caught a real defect in the first cut: the ellipse's bounding clip also triggered the nested mask, a second group (`groupsMasked == 2`). The "a mask scope already cuts the clip" return fixed it.
- The first `aClipAroundATransition...` mutation (L6b) was green for the unreachable reason above, and the first draft of the test never opened a transition scope (the stage lacked the outer rotation and clip); the printed scope list (`effect@0, fade@1, transition@1`) is what showed the arm now separates.

## 4. What the code and the probe forced (deviations from the plan)

1. **Lane 2's σ over the projective Jacobian is not supported** (Z5/Z5b): a projection alone is a resample in SwiftUI, so `k` should come from the flattening scale `f` only, never from a projective Jacobian. TODO(run 2): change the algorithm's step 2 (σ affine: the largest singular value of the 2x2; projective: 1) and drop test 12's "rung >= the analytic max Jacobian" for "a projected unscaled text keeps the device-scale raster".
2. **NC5's extension was taken** (plan: only if under ~30 lines and SwiftUI exact; NC5 is exact): about 12 lines, the clip undone through the flattening scopes opened since (`after`, a uniform scale and a translation, always invertible). Test 5 pins exactness; the plan's "pins the box" arm became "exact", and 224's clause shrinks to material/glass/oversize and a non-effect scope between.
3. **A mask scope already cutting the clip returns `nil`** (not in the plan): without it an ellipse clip built two groups.
4. **A transition/capture/fade between returns `nil`** (a test arm the plan did not list): the transition's map could be undone like a flattening effect's, but it was not measured and the box is today's behaviour.
5. **The old pin was replaced, not mutated**: `aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox` (90 / 90, `RenderEffectTests`) is deleted; its arithmetic lives on in `aClipBetweenRightAngleRotationsTakesNoGroup`.
6. **Stop condition 8 did not fire.** `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` needed no new refusal (full run, section 6). TODO(run 2): state the retained-translation outcome for a nested clip moved by a layout shift.

## 5. Pins moved (each with its cause)

- `RenderEffectTests.aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox`: deleted (109 retired); see item 5.
- `RetainedSubtreeInternalTests.everyFrameChannelIsClassified`: one row, `nestedClipMasks` `.frameLocal` (a new counter).
- None else: the full suite, with and without `METALUI_VERIFY_RETAINED=1`, passed unmodified (section 6).

## 6. Runs

Head `63b0f767`+tests (code and tests as committed; this record and `Tasks.md` are the only later changes), macOS 27.2, Xcode toolchain, `swift package clean` first.

- `swift build --build-system native --build-tests && swift test --build-system native --no-parallel`, unfiltered: `✔ Test run with 5342 tests in 14 suites passed after 302.195 seconds.` and `FR-J no-argument frame: succeeded=true`. (CLAUDE.md's 4817 / 13 suites was 2026-11-01; the 14th suite and the difference are earlier PRs plus this one's 9 tests; run 2 re-measures the counts line.)
- The same with `METALUI_VERIFY_RETAINED=1`: `✔ Test run with 5342 tests in 14 suites passed after 303.872 seconds.` and `FR-J no-argument frame: succeeded=true`. No pin moved, no new refusal in `aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale` (stop condition 8 did not fire).
- Portable container (`metalui-portable:latest`, a `git archive` of the head, `swift build --build-tests` then `MetalUILayoutTests|MetalUICoreTests|MetalUICrossPlatformTests`): build complete; `✔ Test run with 286 tests`, `154 tests`, `24 tests` passed.
- Not run in run 1: `Backends/SDL`, the closeout inventory scripts (no public declaration was added), parity frames (lane 1 changed no renderer; frame 20 is run 2's).

## 7. TODO(run 2)

Lane 2 (106) and its tests 9-21 with mutations T1-T13; parity frame 20 (including the NC1/NC2 nested clips, the text zoom frames, and the SDL runs); the demo strip; the decisions doc `docs/superpowers/2026-11-xx-text-zoom-decisions.md` (`TZ-A`..`TZ-F`, superseding `GX-L` and GX-G's clip bullet); the ledger (109 retired, 106 narrowed with the residues Z3/Z6 name: rotation, skew, anisotropy are vector in SwiftUI and an upright raster here; beyond the cap and below the floor; text inside a projective filtered group; a text shadow or blur silhouette; `drawText` surface text; the image clause dropped; 224 and 1065 amended; the count and next label); human checks `TZ1`..`TZ4`; the shards (`drawing.md`, `text.md`, `retained.md`, `sdl.md`), `api-overview.md`, the inventory map row 182, `decision-prefixes.md`, the record README row, `CLAUDE.md`/`AGENTS.md`.
