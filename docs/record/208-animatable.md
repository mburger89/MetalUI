# Record 208: a public `Animatable` on shapes and keyframes (round 4 item R4-3 PR D)

Branch `feat/r4-3-animatable`, on `feat/r4-3-leaver-moves` (PR C, #203; master `2478df03`). Decisions: `docs/superpowers/2026-11-04-animatable-decisions.md` (`VA-A`..`VA-H`). Human checks: none added. Divergences: **947 retired, 169 narrowed, 215 and 216 added** (209 live, next label 217). Probe: `docs/probes/swiftui-animatable.swift` gained arm `VA6d`, **typechecked and not run** (the screen was locked, `CGSSessionScreenIsLocked = 1`, 2026-11-04).

## 1. What changed

- `Sources/MetalUI/Animatable.swift` (new): `Animatable`, `EmptyAnimatableData`, `AnimatablePair`; conformers `Double`, `CGFloat`, `Angle`, `Float` (a MetalUI extra), `UnitPoint`, `CGPoint`, `CGSize`, `CGRect`, `EdgeInsets`. `VectorArithmetic.scaled(by:)` is public.
- `Shape: ProposalElement, Sendable, Animatable`; every built-in has no data.
- `ProposalAnimation.swift`: `VectorTrack<V>` and `animatedVector(_:at:frame:transaction:)` (the curve over the vector's length, snaps on zero or non-finite length, retargets from the current value at rest, a settled track returns before allocating). `AnimationStore.vectorTrackRebuilds` (`.frameLocal` in the channel table).
- `TrimmedShape.swift`: `PaintAnimatedShape` and its cast are deleted; `shapeForPaint` returns at once for `EmptyAnimatableData`, otherwise one track at `layerAnimationKey(id, "animatable")`. `TrimmedShape` is `Animatable` over the base's data and the two fractions times 128. The `$anim-trim` and `$anim-trim.base` keys are gone.
- `Keyframes.swift`: `LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`, `KeyframeTrack`, `KeyframeTrackContent` and `KeyframeTrackContentBuilder` take `Value: Animatable`; `KeyframeSpec` and `KeyframeSegments` stay on `Value.AnimatableData`.
- Docs: decisions, `decision-prefixes.md`, `drawing.md` (`PG-F` sentence), divergences, inventory map, migration, record README, `Tasks.md`. Tests: `AnimatableTests.swift` (14 tests), `AnimatableCompileGuards.swift` (4 guards).

## 2. The spike (the first commit, `7169bae5`)

Plain-import `typecheckFile`, Swift 6 mode, against the nonisolated `Animatable`:

| arm | spelling | MetalUI | SwiftUI (measured) |
|---|---|---|---|
| S1 | `struct S: Shape { var animatableData: Double }` | **error**: "conformance of 'S' to protocol 'Animatable' crosses into main actor-isolated code" | compiles (`VT1`) |
| S2 | the same, `nonisolated var animatableData` | compiles, reads the stored property | not measured |
| S3 | `struct C: Component, Animatable` | error, same message | error (`VT2`) |
| S4 | the same, `nonisolated` | compiles (after the fixture used `content`) | compiles (`VT3`) |
| S5 | a shape with no data | compiles | compiles (`VT9`) |
| S6 | `Double`, `CGFloat`, `Angle`, `UnitPoint` to a generic `Animatable` function | compiles | compiles (`VT10`) |
| S7 | `LinearKeyframe` over a custom `Animatable` | compiles after the keyframe commit; `Float` too | compiles (`VT14`); `Float` errors (`VT16`) |
| nonisolated struct | `public nonisolated struct S: Shape` with the plain spelling | compiles | |
| `@MainActor` witness | `@MainActor public var animatableData` | error | |
| `@MainActor` requirement (measured, then reverted) | `@MainActor var animatableData` in the protocol | **S1 and S3 compile**, S2 too | |

Ruling: `[PREDICTED]` held. S1 fails and S2 compiles, so the nonisolated requirement stays and divergence 215 states the difference; the `@MainActor` alternative compiles S1 but also accepts S3 (SwiftUI rejects it) and would put `Double` and the timeline on the main actor. S3 and S4 match SwiftUI, so no row for `Component`.

## 3. Differences from the plan

- `Double`, `CGFloat`, `Angle` and `Float` spell `AnimatableData` and `animatableData` out. The defaulted witness (`where Self: VectorArithmetic`) was reported "multiple matching properties" because Foundation exposes SwiftUICore's `Animatable` extensions on `Double` and `CGFloat`; `CGRect` spells its data type out for the same reason (`'AnimatableData' is ambiguous`).
- The fractions are `Double` in MetalUI, so the trim's data is `AnimatablePair<CGFloat, CGFloat>` converted at the boundary.
- `EdgeInsets` is four `CGFloat`s over MetalUI's `Pixels` fields.
- `animatedVector` calls the conformer's setter only when the animated value differs from the declared one, and writes the store only when something changed (a flight to the same target writes nothing; the read touched the entry).
- `Flight` stores `to` explicitly (`from + delta` need not equal `declared` bit for bit).
- Added beyond the plan: `aRetargetUnderASpringRestartsAtRest` (divergence 216 pinned wrong on purpose) and the `vectorTrackRebuilds` counter (the plan's `aSettledShapeDoesNoStoreWork` needed one).
- MD6 is spelled "the retarget keeps the old flight's `from` and start time" (a per-component retarget has no spelling on a generic vector).
- Not done: `VA6d` was not run (screen locked); the plan's velocity-projection and superposition builds (the plan said not to); `RoundedRectangle`'s `AnimatableData`; the `@Animatable` macro.

## 4. Tests that flipped

None. `trimAnimatesItsEndFraction`, `aBareTrimmedShapeAnimatesToo`, `bothFractionsAnimate` and `keyframeAnimatorTypechecksWithSwiftUIsCallShape` stayed green with their expected values unchanged. One unchanged-test edit: `everyStateTableAndAnimationStoreChannelIsClassified` gained the row `"vectorTrackRebuilds": .frameLocal` (it asked for the new stored property).

## 5. Mutations

Applied with `scratchpad/mut/run.py` on the committed tree (restored from an in-memory copy, `git status` read after each: clean of `Sources` and `Tests`), filter `AnimatableTests|AnimatableCompileGuards|PathOpsTests|Keyframe|HotPathAnimationTests|everyStateTableAndAnimationStore`.

| mutation | reddened |
|---|---|
| MD1 `nonisolated` removed from the S2 and S4 fixtures | `aShapesAnimatableDataNeedsNonisolatedInSwift6`, `aComponentThatIsAnimatableNeedsNonisolatedLikeSwiftUIsView` |
| MD2 the interpolated data not written back | 9: `aCustomShapeAnimatesItsData`, `aRetargetOnOneComponentRebasesTheWholePair`, `aTrimOfATrimAnimatesBothLayers`, `trimAnimatesItsEndFraction`, `bothFractionsAnimate`, `aBareTrimmedShapeAnimatesToo` and 3 more |
| MD3 the "animates nothing" guard inverted | 11, incl. `aCustomShapeAnimatesItsData`, `aSettledShapeDoesNoStoreWork`, `trimAnimatesItsEndFraction` |
| MD4 a trim's data not scaled by 128 (getter and setter) | `aTrimsDataIsScaledBy128` only (the animated tests are scale-blind for a linear curve) |
| MD5 the inner data dropped from a trim's | `aTrimsDataIsScaledBy128`, `aWrapperForwardingATrimAnimatesBoth`, `aTrimOfATrimAnimatesBothLayers` |
| MD6 the retarget keeps the old `from` and start time | `aRetargetOnOneComponentRebasesTheWholePair`, `aRetargetIsPositionContinuousFromRest` |
| MD7 the retarget starts from the old `from`, not the current value | the same two |
| MD8 the curve over unit progress | `aLargeDeltaLandsWithinTheCeiling` |
| MD9 the slow path always | `aSettledShapeDoesNoStoreWork` |
| MD10 no `noteInterpolation`/`noteActiveAnimation` | `anAnimatableShapeInARetainedOccurrenceIsNotFrozen`, `aLargeDeltaLandsWithinTheCeiling` |
| MD11 `AnimatablePair.scale` skips `second` | 8, incl. `pairArithmeticIsComponentwise`, `aKeyframeTrackOverACustomAnimatable`, `aTrimOfATrimAnimatesBothLayers`, `trimAnimatesItsEndFraction` |
| MD12 `magnitudeSquared` drops `first` | `pairArithmeticIsComponentwise` only |
| MD13 the keyframe track does not write the data back | 18+, incl. `aKeyframeTrackOverACustomAnimatable`, `linearKeyframesMatchK1` |

No mutant is green. MD4 and MD12 are caught by one test each: the scale is pinned as data (the animated arms cannot see it), and the pair's length by the arithmetic test alone.

## 6. Counts and checks

Steady frame (`aSteadyFrameCapturesAndOpensNothing`, `anEquatableOccurrenceWithAnIfStillGrafts`, unchanged and green): allocations 455, `lastFrameCapturedPrimitives` 0, grafts 4, hits 4, prepaint hits 4, requests 1, prepaints 2, as record 207 read them before this PR; no plain-shape counter or allocation pin moved (a plain shape's paint now returns at a metatype comparison where it made a failed `as? any PaintAnimatedShape` cast). `aSettledShapeDoesNoStoreWork`: a settled animatable shape rebuilds no track (`vectorTrackRebuilds` unchanged over five frames) and a plain shape counts 0.

`swift package clean`, `swift build --build-system native --build-tests` (exit 0), `swift test --build-system native --no-parallel`, unfiltered, 2026-11-04: **`Test run with 5125 tests in 14 suites passed after 279.017 seconds`** (5107 + 14 `AnimatableTests` + 4 `AnimatableCompileGuards`); `FR-J no-argument frame: succeeded=true deprecations=2`. `anUnannotatedInsertionAndRemovalFadeByDefault` passed on this fresh build (R4-3d: no failure this time). `METALUI_VERIFY_RETAINED=1`: `5125 tests in 14 suites passed after 274.422 seconds`; `METALUI_VERIFY_LAYOUT_MEMO=1`: `5125 tests in 14 suites passed after 321.453 seconds`; `METALUI_RUN_100K_LIST_TEST=1 swift test --build-system native --no-parallel --filter aListsWorkIsTheSameFor100kRowsAsFor500`: `Test run with 1 test in 1 suite passed after 16.167 seconds`. `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. An earlier unfiltered run (before the keyframe commit's classification row) read one failure, `everyStateTableAndAnimationStoreChannelIsClassified` (the new `vectorTrackRebuilds` property had no row), fixed by adding the row.

## 7. Downstream

Cloned with `git clone --local --no-hardlinks` into the scratchpad, `../MetalUI` a symlink to this worktree at `8033ebaa`, `swift build`: **MetalCreator** (`main`, `610f66d`) `Build complete! (29.50 sec)`, exit 0; **MetalFlow** (`main`) `Build complete! (24.42 sec)`, exit 0. No warning names `Animatable` or `Shape`. `DimensionLinesShape` and `DimensionArrowsShape` (`Shape, Hashable`) compile unchanged; neither app has a `Float` track, a `VectorArithmetic` conformer or an `animatableData`. Their tests were not built.

## 8. Not verified

How an animated shape looks (no pixels read; `XF6`-style human look owed); `VA6d` (whether SwiftUI keeps momentum on a retarget); Windows and Linux builds (`Animatable.swift` imports Foundation only and uses `CGFloat`, `CGPoint`, `CGSize`, `CGRect`, which swift-corelibs-foundation provides, but no CI ran); `Backends/SDL`.
