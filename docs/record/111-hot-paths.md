# 111 - Hot paths (item P1), lane 2: isolation, animation, shadows

Branch `perf/hot-paths` from `fb9a7e42`. Lane 1 (text: placement box, `GlyphKey` hash, rich memo, markdown
table) is `HP-H` and its own commits; this section is lane 2 (`HP-C`, `HP-E`, `HP-I`). Spec
`docs/superpowers/specs/2026-10-13-hot-paths-design.md` s3.1, s3.4, s3.6, tests 11-18. No public declaration,
no divergence, no shader, no `Backends/SDL`.

## 1. What changed

- Plain loops or `guard let` for closures passed to stdlib generics in `@MainActor` code: `hasPercentEdge`
  (now file-level `edgesHavePercent`), `Shadow.shadowImage`'s canonical-leaf `map`, `ProposalAnimation`'s
  `px`/`raw`/`ordered`/`dimension`/`length` `Optional.map` sites. `MenuSession.contextualTarget` moved into a
  static list form (`Window.contextualTarget(in:at:where:)`), bodies unchanged.
- `AnimatedStyle.borderWidths` returns before building any key string when nothing is in flight and the
  border is unchanged (and on the `nil` branch when nothing is in flight). `animatedNumbers` returns
  `declared` when `inFlight` is empty and every position is bit-equal to its baseline (NaN excluded).
- `RasterKey` carries a stored hash folded by every `add...`; the fields are `private(set)`. `RasterCache`
  touches a coverage or tint entry in place with one `index(forKey:)` (epoch stamp), and the tint key no longer
  allocates a `[UInt32]` per lookup. `Affine2D.boundingBox` is four scalar corners.

## 2. Pins (red on arrival where a counter exists)

Red lines at commit `8084f798` (before the implementation):
`aSettledBorderlessTreeBuildsNoBorderWidthKeys` (`borderKeyBuilds == before`),
`aSettledProposalTreeAllocatesNoTracks` and `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut`
(`numberTrackRebuilds == before`), `aRasterKeyHashesFromItsStoredHash` (two issues: six keys stored one hash;
a later word did not move it), `aShadowHitDoesNotRehashItsKey` (`perFrame == 2`, was 4 per shadow). Green first
(pure refactors, mutation-verified instead): `edgesHavePercentAgreesWithItsClosureFormForEverySubset`,
`contextualTargetPicksTheSameHitboxAsTheClosureForm`, `boundingBoxEqualsTheFourCornerArrayForm`,
`aChangedBorderWidthStillAnimatesAfterTheEarlyOut`. Test 14's first version did not see the search direction
(M6 passed): the random lists now count ambiguous matches (`ambiguous > 15`) and M6 reddens it.
`everyStateTableAndAnimationStoreChannelIsClassified` (`SB-E`) owed the two new `AnimationStore` counters a
row (`.frameLocal`); a one-line addition to `RetainedSubtreeInternalTests` that C14b-2's merge must keep.

## 3. Mutations (filtered to the HotPath files plus the animation, shadow and gradient suites for M1-M4, M10)

Applied to the committed implementation, restored with `git checkout`, `git status --short` clean after each.
Not the full unfiltered suite per mutation (the Mac ran at load 90-130; a full run is 8-10 minutes): a
deviation from the practice, named here.

| Mutation | Reddened |
|---|---|
| M1 `borderWidths` early return removed | `aSettledBorderlessTreeBuildsNoBorderWidthKeys` |
| M2 `borderWidths` returns declared while in flight (`\|\|`) | `aChangedBorderWidthStillAnimatesAfterTheEarlyOut`, `aSettledBorderlessTreeBuildsNoBorderWidthKeys`, `aFocusRingAnimatesItsWidth`, `aHoverBorderAnimatesItsWidth` |
| M3 `animatedNumbers` early return deleted | `aSettledProposalTreeAllocatesNoTracks`, `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut` |
| M4 early return ignores a changed baseline | 39 issues in 17 tests, among them `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut`, `aProposalFrameAnimatesItsWidthUnderATransaction`, `aSettledProposalTreeAllocatesNoTracks`, `everyAnimatableProposalModifierAnimates` |
| M5 in-flight clamp removed | the run aborts inside `aChangedValueStillAnimatesAndClampsAfterTheEarlyOut` (opacity above 1 reaches its precondition: the clamp's own reason) |
| M6 `contextualTarget` searches forward | `contextualTargetPicksTheSameHitboxAsTheClosureForm` (28 issues) |
| M7 `edgesHavePercent` omits `.left` | `edgesHavePercentAgreesWithItsClosureFormForEverySubset` |
| M8a hash skips `objects` | `aRasterKeyHashesFromItsStoredHash` |
| M8b `add(Int)` skips the fold | `aRasterKeyHashesFromItsStoredHash` (2 issues) |
| M8c `==` is hash-only | `aRasterKeyHashesFromItsStoredHash` |
| M9 a coverage hit probes twice | `aShadowHitDoesNotRehashItsKey` |
| M10 `boundingBox` y min/max swapped | `boundingBoxEqualsTheFourCornerArrayForm` (438 issues) and five scene tests (`aGradientUnderARotationFollowsTheTransform`, `aShadowInsideARotationOrScaleHasItsOffsetTransformed`, ...) |

## 4. Whole-branch verification (HEAD includes lane 1)

- Fourteen offscreen images against `fb9a7e42` at `3c767723` (lane 2's first implementation commit on top
  of lane 1): `docs/probes/demo-pixels/compare.sh`, every row `differing=0`, scene identical, controls as
  recorded.
- Unfiltered `swift test --build-system native --no-parallel` on HEAD (lane 1 + lane 2): **3736 tests in 3 suites passed** (3717 + 19 new across both lanes; lane 2 adds 9), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice. The first full run read one issue, the unclassified counters (section 2), fixed in `HP-I`'s follow-up commit. `swift build --build-tests` on the default build system: see the report.
- `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (no public
  declaration).

## 5. Measurements (dated 2026-10-13/14, not pins)

Release, headless, Prof harness (`/private/tmp/claude-501/profiling/Prof`) built twice: A = `fb9a7e42`
(`git archive`), B = this branch HEAD (**lane 1 and lane 2 together**). Alternated A,B three times per
scenario, 8 s each, median ms/frame (the middle of three medians). **The Mac was shared and loaded: load
average 65-130 throughout**, so the figures are an upper-noise bound, not a claim; a second machine state
will differ.

| Scenario | A ms | B ms | change |
|---|---|---|---|
| demo | 1.280 | 1.063 | -17 % |
| list-fixed | 0.942 | 0.689 | -27 % |
| list-var | 1.340 | 0.864 | -36 % |
| rich | 3.398 | 1.341 | -61 % |
| shadows | 2.033 | 1.297 | -36 % |
| materials | 0.650 | 0.517 | -21 % |
| bracket-orbit | 4.736 | 4.496 | -5 % |
| bracket-value | median 0.000 (the scenario's median frame is a no-op) | mean 7.1 / 9.9 / 12.6 (A), 6.1 / 11.2 / 20.4 (B) | too noisy to read |

Allocations per frame (`PROF_ALLOC=16`, one run each): bracket-value A 3,186,717 / 243 = 13,112, B
2,959,752 / 243 = 12,180 (-7 %); demo A 2,593,068 / 969 = 2,676, B 2,511,225 / 1,168 = 2,150 (-20 %).
Lane 2's share is not separable from this table (the harness builds lane 1 and 2 together).

## 6. Deferred

`Frame.swift` :2373 and :3224, `RetainedSubtree.swift` sites (C14b-2); layout pre-sizing, `measureNative`
hashing, `ForEach` (P2); path-raster clip key and R8 coverage (P3). `GradientRaster`'s image cache
(`RasterCache.image`) still uses the touched-set pair (two probes); its key is now cheap to hash, the pair
was left for a follow-up. The Linux image was not run for lane 2 (no portable text target or `Backends/SDL`
file touched; the lane 1 run owns the image).
