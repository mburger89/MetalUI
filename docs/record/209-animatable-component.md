# Record 209: `Component & Animatable` (round 4 item R4-3 PR E)

Branch `feat/r4-3-animatable-component`, on `feat/r4-3-animatable` (PR D, record 208, not open) on `feat/r4-3-leaver-moves` (PR C, #203). Decisions: `docs/superpowers/2026-11-04-animatable-decisions.md` (`VA-I`..`VA-M`). Human check: `VA4`. Divergences: **none added, retired or narrowed** (209 live, next label 217; row 215's text gained a clause). Probe recordings used: `VA5`, `VA7`, `VA7s`, `VT2`, `VT3` (all present in `docs/probes/swiftui-animatable-run.txt`); no probe was run.

## 1. What changed

- `Sources/MetalUI/Component.swift`: `interpolateAnimatableComponent(_:id:pass:)` (the one shared body: empty-data guard, `animatedVector` at `layerAnimationKey(id, "animatable")`, setter only when the frame differs), `extension Component where Self: Animatable` with the `requestGroupLayout` witness (interpolate, then `enterComponent`, `content`, `finishComponent`) and a witness of the new requirement `_interpolateAnimatableData(under:at:pass:)` (default: no-op, no id computed).
- `Sources/MetalUI/EquatableComponent.swift`: one call to the requirement before `enterComponent`, so the memo compares the interpolated value.
- Tests: `AnimatableComponentTests.swift` (10), fixtures in `AnimatableComponentFixtures.swift` and `AnimatableComponentSplit.swift` (the `Animatable` conformance of `SplitCounter` in a file of its own).
- Docs: this record, README row, decisions `VA-I`..`VA-M`, prefix row, `identity-state.md` sentence, migration, human check `VA4`, `Tasks.md` (R4-3 left unticked), divergences row 215 clause.

## 2. Differences from the plan

- **The witness is selected across files and modules** (`aWitnessDeclaredInAnotherFileIsSelected`: the type in one test file, `: Animatable` in another, both outside MetalUI). `[PREDICTED]` held, so no dynamic check was built or counted.
- **A requirement was added to `Component`**, which the plan did not list: `EquatableComponent` is generic over `Component & Equatable` and cannot reach a `Self: Animatable` witness without a cast. `package` is refused on a protocol requirement ("'package' modifier cannot be used in protocols"); `@_spi(ComponentInternals)` compiled MetalUI and broke every outside `Component` ("type 'VariableListDemo' does not conform to protocol 'Component'", measured in MetalUIDemoContent). It is `public`, underscored, documented as framework-internal; the inventory scripts print nothing.
- **No mirror in `StyledComponent`** (plan: "both entries, `:219` and `:555`"): `StyledComponent` calls `component.requestGroupLayout`, a requirement, which reaches the constrained witness (`aTypedEntryAnimatesToo`). So `ME3` ("typed entry skips") is spelled as the `.equatable()` entry skipping.
- **The bare path calls the helper directly** and the equatable path calls the requirement, so each entry fails alone (`ME1` and `ME1b`).
- A first version computed the id in `EquatableComponent` before calling the hook and cost **one allocation per equatable non-animatable component per frame (398 to 399)**; found by a scratch measure against PR D's head, fixed by computing the id inside the Animatable witness, pinned by `aNonAnimatableComponentAllocatesWhatItDid` (`ME7`).
- Added beyond the plan: `aSetterThatRebuildsSelfKeepsItsState` (the separating arm for `ME4`), `interpolationWritesNoStateAndRequestsNoFrame`, `aNonAnimatableComponentAllocatesWhatItDid`.
- Not done: no Windows or Linux build (the new code uses nothing platform specific; the hazard note was followed: no loop or closure was added to generic content); `VA4` is a human check; a macro was not offered (`VA-H`).

## 3. Tests that changed

None. No existing expected value moved. The pre-existing pins, green and unchanged: `aSteadyFrameCapturesAndOpensNothing`, `anEquatableOccurrenceWithAnIfStillGrafts` (grafts 4, hits 4, prepaint hits 4, requests 1, prepaints 2, paints 1), `aComponentThatIsAnimatableNeedsNonisolatedLikeSwiftUIsView`.

## 4. Counts before and after (non-animatable)

A steady frame holding a bare and an `.equatable()` non-animatable `Component` (`aNonAnimatableComponentAllocatesWhatItDid`): allocations **398 on PR D's head `7c684807`, 399 on the first version of this PR, 398 as committed**; `vectorTrackRebuilds` 0 and `AnimationStore.count` 0 on both. `aNonAnimatableComponentPaysNoTrack`: a flight under a transaction leaves `vectorTrackRebuilds` at 0, adds no store entry over the inline content and the same interpolation count. `lastFrameCapturedPrimitives` (`aSteadyFrameCapturesAndOpensNothing`): 0, unchanged; steady allocation pin 455 unchanged and green.

## 5. Mutations

Applied with `scratchpad/mut/run.py` on the committed tree (each restored by `git checkout Sources`, `git status` read clean of `Sources` and `Tests` afterwards), filter `AnimatableComponentTests|ComponentTests|AnimatableTests|AnimatableCompileGuards` (51 tests), final head `2abd59a2`.

| mutation | reddened |
|---|---|
| ME1 the constrained `requestGroupLayout` renamed (the witness removed) | `aTypedEntryAnimatesToo`, `aWitnessDeclaredInAnotherFileIsSelected`, `anAnimatableComponentsContentSeesInterpolatedValues`, `interpolationWritesNoStateAndRequestsNoFrame`, `itsChildIsProposedInterpolatedWidths` |
| ME1b the `Self: Animatable` witness of `_interpolateAnimatableData` renamed (the `.equatable()` entry loses it) | `anEquatableAnimatableComponentRunsInFlightAndSkipsSettled`, `anAnimatableComponentInARetainedOccurrenceIsNotFrozen` |
| ME2 `==` compared before interpolating (the hook moved after the memo) | the same two |
| ME3 the `.equatable()` entry does not call the hook | the same two |
| ME4 interpolated after the `@State` bind | `aSetterThatRebuildsSelfKeepsItsState` only |
| ME5 the empty-data guard removed | `aNonAnimatableComponentPaysNoTrack` only |
| ME6 the hook called before the build window opens | **none: green** |
| ME7 an id computed in `EquatableComponent` before the hook (the first version of this PR) | `aNonAnimatableComponentAllocatesWhatItDid` only (399 against 398) |

**ME6 is green and is reported, not explained away in the code**: the interpolated value differs on every frame of a flight, so the `==` memo misses and the occurrence is rebuilt whatever the window saw; the only frame where it could matter is the change frame, which reads its own `from` and paints what the last frame painted. The placement inside the window is harmless and not load-bearing; `VA-K` and the source comment say so. An earlier table (before the retained fixture's own frame animation was switched off, which made `anAnimatableComponentInARetainedOccurrenceIsNotFrozen` blind to ME1b, ME2 and ME3 because the inner frame animated itself, divergence 96) is superseded.

ME4 and ME5 are each caught by one test; ME4's separating arm is a setter that replaces `self`, the only shape where the order is observable (the `@State` wrappers of the replacement are unbound; bound afterwards its writes are discarded).

## 6. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests` (exit 0), `swift test --build-system native --no-parallel`, unfiltered, 2026-11-04: **`Test run with 5135 tests in 14 suites passed after 279.127 seconds`** (5125 + 10 `AnimatableComponentTests`); `FR-J no-argument frame: succeeded=true deprecations=2`. `anUnannotatedInsertionAndRemovalFadeByDefault` passed on this fresh build (R4-3d: no failure). `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1` first read **one failure each**, `aNonAnimatableComponentAllocatesWhatItDid` (`allocations == 398`, read 1085: the verify modes recompute every hit, so the allocation count is not theirs to read); the test is now `.enabled(if:)` off under both, as `anEquatableOccurrenceWithAnIfStillGrafts` is. After that edit (a gate only, no `Sources/` change): unfiltered `5135 tests in 14 suites passed after 279.365 seconds`, `METALUI_VERIFY_RETAINED=1` `passed after 272.642 seconds`, `METALUI_VERIFY_LAYOUT_MEMO=1` `passed after 329.297 seconds`. `METALUI_RUN_100K_LIST_TEST=1 swift test --build-system native --no-parallel --filter aListsWorkIsTheSameFor100kRowsAsFor500`: `Test run with 1 test in 1 suite passed after 15.887 seconds` (taken before the gate edit; nothing it runs changed). `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

## 7. Downstream

Not built. The change adds one public requirement with a default to `Component` and a constrained extension; the only downstream-visible risk is a conformer that declares its own `_interpolateAnimatableData`, which no one has. MetalCreator and MetalFlow have no `Component & Animatable`.

## 8. Not verified

How an animated component looks (`VA4`, a human check, the screen was not used); a spring (every test runs a linear curve; the spring path is `animatedVector`'s, pinned by record 208); Windows and Linux builds and the asserts compiler on the new constrained extension (no loop or closure in generic content was added, but no CI ran); a `Component & Animatable` whose data is `AnimatablePair` or a custom `VectorArithmetic` (the helper is generic over `AnimatableData`, only `Double` is exercised); `Backends/SDL`.
