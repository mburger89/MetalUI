# Record 219: a shadow and a blur over a group texture (R4-5 PR B)

Branch `feat/group-filter` (master `54aa3c43`). Rulings `GF-A`..`GF-H` in `docs/superpowers/2026-11-06-group-filter-decisions.md` (new prefix; next id `GF-I`). Divergences: **221 and 1066 retired**, **167 reworded and still live**, **104, 105, 1065 amended**, **223 added**; 210 live, next label 224. Probe `docs/probes/swiftui-group-filter.swift`.

## 1. What was measured

- [MEASURED] The probe, compiled, run twice, stdout byte-identical (14 lines), macOS 27.2, Swift 6.4.2, screen **locked**, no computer use. **`GF0` separates** (`FR-M`): `overlap().compositingGroup().opacity(0.5).shadow(black, 0, 10, 10)` differs 0 pixels from the F reference (shadow, then the group faded as one) and 4800 from the S reference; (65, 65) reads (128, 128, 255) (the shadow does not show through), (95, 95) reads gray 128. **Model F.** `GF1`: a view's `.opacity(0.5).shadow` is F as well ((55, 55) = (255, 128, 128), (65, 65) = (128, 128, 128)); a colour's alpha before the shadow is S ((191, 64, 64)): divergence 223. `GF2`: radius 6, the default colour, 0 differing from F. `GF3` separates for blur: (255, 128, 128) composite against (192, 64, 128) per leaf, 5611 pixels. `GF4`: the shadow-only pixel under the faded part reads 128, under the unfaded part 0. `GF5`: a `rotation3DEffect` leaf is shadowed (ink grows 1181 pixels) and blurred (ink 78 x 112): 1066 is real, no stop. `GF6`: `ImageRenderer` draws no platform view (cannot measure).
- [NOT RUN] **`W1`**: `appkit-screen-lock-state.swift` read `CGSSessionScreenIsLocked = 1`; no window arm was written and no computer use. Per the lead's instruction **167 was not retired**: the behaviour is built (a surface under a blur is blurred), the row is reworded (SwiftUI's side for platform views unmeasured) and human check `GF3` carries it. To be put to the user.
- [MEASURED] Shader: only `group_tint_fragment` is new and it reads `[[position]]` like every pass shader; no group-content shader does (stop condition 8 did not fire). Blobs from the pinned shadercross (`~/Developer/tools/shadercross`, commit `1ff05bec`): 41 existing files byte-identical, `tint.fragment.{spv,msl,dxil,json}` new.
- [MEASURED] **Parity** on SDL-over-MSL (`Replay --portable`), frames 0-17: `differing pixels=0, max channel delta=0` on every frame including the new **frame 17** (six filtered groups: blur sigma 2, sigma 12 at L = 2, a shadow with a fractional offset, a projective blurred rect, a filtered quad under a projective record, a filtered group inside an opacity group; 7 group quads). `--expect 18` on both workflow lines. Linux Vulkan and Windows D3D12 not run.

## 2. Mutations (a scratch `git worktree` of `388151e5`, removed afterwards)

Root, filter `GroupFilter*`, `RetainedGroupFilter`, `CompositingGroup`, `Blur`, `Shadow`, `ProjectionPaint`; spelling quoted:

| id | mutation (file, spelling) | reddened |
|---|---|---|
| M1 | `Frame.swift` shadow arm: `liftSharedMarks` replaced by `bakedGroupAlpha` on the leaf, no lifted marks | `aShadowOutsideAnOpacityGroupCastsTheCompositesShadow`, `aFadeOfAShadowedGroupRastersNothingAfterItsFirstFrame`, `aMixedMarkLeafIsFilteredOffscreen`, `aRetainedReplayOfAFilteredGroupEqualsAFreshFrame` |
| M2 | shadow item given fresh tokens (model S) | `aShadowOutsideAnOpacityGroupCastsTheCompositesShadow`, `aFadeOfAShadowedGroupRastersNothingAfterItsFirstFrame` |
| M3 | blur arm bakes instead of lifting | `aBlurOutsideAnOpacityGroupBlursTheComposite` |
| M4 | `needsGPU` ignores marks | `aMixedMarkLeafIsFilteredOffscreen`, `aRetainedReplayOfAFilteredGroupEqualsAFreshFrame` |
| M5 | `needsGPU` surface arm to `break` | `aSurfaceUnderBlurIsBlurredOffscreen`, `aSurfacesShadowFollowsItsPixels`, `aFilteredGroupsBoxCoversTheReachInWholeLevels`, `aGhostOfABlurredSurfaceStaysBlurred`, `anOversizeFilteredLeafFallsBackToTheCPU`, `aSurfaceInsideAGroupKeepsItsTarget` |
| M6 | `needsGPU` projective arm removed | `aProjectiveLeafCastsAShadowOffscreen`, `aProjectiveLeafUnderBlurIsBlurred` |
| M7 | `pad` + 1 to + 0 | `aFilteredGroupsBoxCoversTheReachInWholeLevels` |
| M8 | no widening to 2^L (`multiple = 1`) | `aFilteredGroupsBoxCoversTheReachInWholeLevels` |
| M9 | the 8192 limit `if false` | `anOversizeFilteredLeafFallsBackToTheCPU` |
| M10 | `capturedGroup`'s filtered arm returns the bare leaves | `aGhostOfABlurredSurfaceStaysBlurred` |
| M11 | `replayPaint` fast path back to `insertIntoScene` | `aRetainedReplayOfAnOpacityGroupStillComposites` only; **`aRetainedReplayOfAFilteredGroupEqualsAFreshFrame` stays green**: its replay takes the `processScopes` branch (the leaves need boundaries), which ends in `insertLeaves` and is not mutated. The fast branch is pinned by record 218's test; T10 pins the other branch's filter equality. A finding, not closed with a test |
| M12 | `finalize` takes `groupFilters` unpermuted | `finalizeKeepsEachGroupsFilter` |
| M13 | the quad always `.nearest` | `aFilteredGroupsBoxCoversTheReachInWholeLevels` |
| M14 | Gaussian horizontal pass skipped (`Renderer.filterGroup`) | `aBlurredGroupMatchesTheReferenceGaussian`, `aLargeSigmaBlurReadsAtBBR`, `aFilteredGroupSteadyFrameMakesNoTexture`, `aSurfaceInsideAGroupResolvesItsTarget`, `aSurfaceInsideAGroupKeepsItsTarget` |
| M15 | both Gaussian passes horizontal (an axis swap alone is green by design, `LR-X`: separable passes commute) | `aBlurredGroupMatchesTheReferenceGaussian`, `aLargeSigmaBlurReadsAtBBR` |
| M16 | `group_tint_fragment` returns the texel | `aShadowGroupIsTintedAndOffset` |
| M17 | `group_tint_fragment` returns the tint, alpha ignored | `aShadowGroupIsTintedAndOffset` |
| M18 | blur and shadow fallbacks swapped | `aFilterAllocationFailureDegradesByName` |
| M19 | the shadow arm's intermediates not given back | `aFilteredGroupSteadyFrameMakesNoTexture` |
| M20 | `MetalWindowRenderer` `references:` reads the root only | **green** (the draw requests keep the target); with the handle loop also root-only (M20b) `aSurfaceInsideAGroupKeepsItsTarget` reddens: the two lines guard each other |

SDL (`Backends/SDL`, filter `SDLGroupFilterTests|ReplayFixtureTests|SDLGroupTests`): S1 the C tint pass removed reddens `aShadowGroupIsTintedOnTheWindowRenderer`; S2 `SDLGroupSet` writes `filter_kind: 0`: `aBlurredGroupMatchesMetal`, `aFailedFilterDegradesByName`, `aShadowGroupIsTintedOnTheWindowRenderer`; S3 the fixture writer omits the filter words: `aFixtureWithGroupsRoundTripsInPostOrder`, `aGroupsFilterRoundTripsInVersionEightAndVersionSevenLoadsWithNone`; S4 the group surface handle not offset by the texture handles: `aGroupsSurfaceHandleIsShifted` (**a finding of the first draft**: the test had no ordinary image, so `handles.count` was 0 and the mutation was green; the test now holds one); S5 the C fallbacks swapped: `aFailedFilterDegradesByName`; S6 `FlatFrame` not shifting a group quad's transform: `aFlatFrameCarriesTheFilterAndShiftsAGroupQuadsTransform`.

## 3. Runs

- [MEASURED] Root, `swift package clean`, native build, unfiltered `--no-parallel`: **5280 tests in 14 suites passed** on `388151e5` (5261 at record 218; the new tests are 13 in `GroupFilterTests` (one the 223 pin), 6 + 2 in `GroupFilterRenderTests`, 1 in `GroupFilterMetalViewTests`, 1 in `RetainedGroupFilterTests`, less the four replaced); `FR-J no-argument frame: succeeded=true`. The same with `METALUI_VERIFY_RETAINED=1`: **5280 tests in 14 suites passed**. A first full run (5280, clean) on the pre-fix head failed two: the 1 MB stack test (the demo strip's types in the section's frame: SIGBUS; fixed by making the strip a `Component` and splitting its columns) and `noGuideCitesARetiredDivergence` (the guides cited 221 and 167's old text).
- [MEASURED] Portable (`metalui-portable:latest`, a `git archive` copy so the worktree's `.git` pointer is not needed): **797 tests in 10 suites** in `MetalUITestingTests`, plus 9, 16, 73, 68, 49, 286, 154 and 24: all passed.
- [MEASURED] `Backends/SDL` by filter: `SDLGroupFilterTests` + `SDLGroupTests` 8 passed, `ReplayFixtureTests` 37 passed, the renderer files (`SDLBackdropTests`, `SDLWindowRendererTests`, `SDLSurfaceTests`, `SDLDrawTextTests`, `SDLGlassTests`) 39 passed. The whole `MetalUISDLTests` target was not run (it exits mid-run on this Mac at `aFailedBlurTextureDrawsTheFlatTint`, as on master). `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; `cmp CLAUDE.md AGENTS.md` is silent.

## 4. What the code forced (deviations from the plan)

1. **The shadow's offset moves the content, not the quad** (plan GF-B item 5 moved the quad's bounds): the renderer's group target takes its origin from the quad's bounds, so a moved quad would shift the content twice. The leaf is mapped by `translation(offset) . full`, as the CPU's `shadowCoverage` does; the quad stays at the box, `.nearest` at L = 0 under an affine record even for a fractional offset.
2. **Plan T11 and the `aMetalViewsShadowIsItsQuad` name**: replaced by `aSurfacesShadowFollowsItsPixels`; `aSurfaceLeafUnderBlurIsDrawnUnblurred`, `aShadowOutsideAnOpacityGroupStillCompositesTheGroup` and `aShadowOutsideAProjectiveEffectCastsNothingFromIt` were replaced as planned. The last one **passed unchanged after the change** for the wrong reason (it counted images; the shadow had become a group), so it was rewritten, not left (a green pin that no longer pins).
3. **Pins outside the planned list**: `everyFrameChannelIsClassified` gained `filterGroups` and `filtersFlattenedOversize` (planned); `ReplayFixtureTests`' version literals 7 to 8 and the "version 8 is unsupported" probe to 9; `noGuideCitesARetiredDivergence` forced three guide edits (`docs/guides/drawing-and-gpu.md`, `docs/api-overview.md`); the 1 MB stack test forced the strip into a `Component` (cause above). No other pin moved; `ShadowTests`, `BlurTests`, `RasterOverscanTests` (stop condition 4) passed unchanged.
4. **An oversize filtered leaf** draws what the CPU can read (a surface as its quad under a shadow, nothing under a blur), not "today's behaviour" exactly.
5. **`SurfaceTarget`s in a group** needed `Scene.allSurfaceTargets()` in both window renderers and a surface-quad append in `SDLGroupSet`.
6. Commits before the last three lack the attribution trailer (an oversight).

## 5. Not done, or not measured

`W1` (locked screen; 167 stays live); Linux Vulkan and Windows D3D12 parity frame 17, the `root-windows` asserts-compiler arm and the 1 MB run of the strip on Windows (only macOS measured); the whole `MetalUISDLTests` target; human checks `GF1`..`GF5`; the T10 mutation M11 gap (section 2); divergence 223's fix (a view's opacity as a mark).
