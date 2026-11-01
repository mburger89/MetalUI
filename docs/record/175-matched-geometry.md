# 175 — Matched geometry and the `Transition` protocol (round 3 item R3-2; `MG-A`…`MG-H`)

2026-10-31, branch `feat/matched-geometry` from master `7d3d1b80`. Rulings: `docs/superpowers/2026-10-31-matched-geometry-decisions.md` (prefix `MG-`, next `MG-I`). SwiftUI's side:
`docs/probes/swiftui-matched-geometry.swift` (recorded output in its header, `SA-O`). Divergences 895-898 (182 live; 899-904 reserved by MG and unused).

## What was built

- `ElementGroup.matchedGeometryEffect(id:in:properties:anchor:isSource:)` -> `MatchedGeometryGroup`, `MatchedGeometryProperties` (`.position`, `.size`, `.frame`), over the existing `@Namespace` (`LG-K`).
  An identity- and layout-transparent group (`TransitionGroup`'s shape, typed twin, `Element`/`StyledElement` conformances); bookkeeping in `AnimationStore.matched` (`MatchedGeometryStore`).
- A paint map from the laid-out rectangle to the drawn one: `Frame.paintWithDeviceMap` is `paintWithRenderEffect`'s second half extracted; `MatchedGeometryStore.beginPaint` computes the map per frame.
- `protocol Transition: Sendable`, `TransitionPhase`, `TransitionContent` (`opacity`, `scaleEffect`, `offset`), `AnyTransition(_:)`, `.transition(_:)` over a `Transition`; two new internals: `AnyTransition.Kind.custom`
  and `TransitionAtom.alpha(_:)` (an opacity target other than 0).
- `BuildAudit.matched` (graft refusal by name `matchedGeometry`), the store in `AnimationStore.Checkpoint`/`rollbackBuild`, `TransitionStore.removalWasAnnotatedInstant`.

## What SwiftUI does (probe), and where the brief was wrong

The brief said "the newcomer animates from the old frame". Measured (recorder and bitmap, both in the probe header): **true only when SwiftUI keeps the leaver on screen**. A leaver given `.transition(.identity)` hands nothing over
(S2, S4-S8), and a leaver that is not a source hands nothing over (S12, S13: there the *leaver* moves to the newcomer instead). `properties: .position` is the **centre** (the recorder's geometry pair is centre-based: the delta of a swap reads
`[325, 155, 50, 30]` = B − A in centre and size). Two live views with one id (P1-P6): the last source wins and the others are drawn at its frame, at rest. `contentTransition` (CT0-CT4): only `.identity` suppresses the cross-fade;
the other three record the same opacity delta. A custom `Transition`'s `.willAppear`/`.didDisappear` states are the animation's ends (TP1, TP2); `.blurReplace` is opacity + a 7 pt blur + a 0.1 scale (TP3).

## Mutation table

Each mutation applied to one spelling in a clean tree, `swift test --no-parallel --filter MatchedGeometryTests` (default build system), source restored by `git checkout`; the tests named are the ones it reddened.
| mutation (spelling mutated) | tests reddened |
|---|---|
| M-A: never start a flight (`if false && start != target`) | `aNewcomerFliesFromTheLeaversFrameToItsOwn`, `propertiesSelectWhichPartOfTheFrameIsHandedOver`, `anAnchorPicksTheCornerThatIsHandedOver`, `onlyAMatchingSourceLeaverHandsItsFrameOver`, `aFlightInterruptedByAnotherSwapStartsWhereTheViewWasDrawn`, `aFlightKeepsTheDisplayLinkAwakeThenLeavesNothing`, `aFlightInsideRetainedOccurrencesLeavesTheStillSiblingAlone` |
| M-B: a missing animation flies with `linear(1)` | `withoutATransactionTheNewcomerIsAtItsOwnFrameAtOnce` |
| M-C: `properties` ignored (`takesPosition = takesSize = true`) | `propertiesSelectWhichPartOfTheFrameIsHandedOver`, `anAnchorPicksTheCornerThatIsHandedOver`, `aFollowerIsDrawnAtTheSourcesFrame` |
| M-D: anchor fixed at the centre | `anAnchorPicksTheCornerThatIsHandedOver` |
| M-E: hand over whatever the leaver's transition | `aLeaverRemovedByAnIdentityTransitionHandsNothingOver` |
| M-F: a non-source leaver hands over | `onlyAMatchingSourceLeaverHandsItsFrameOver` |
| M-F2: match the id alone, ignoring the namespace | `onlyAMatchingSourceLeaverHandsItsFrameOver` |
| M-G: the first source wins (sort order reversed) | `aFollowerIsDrawnAtTheSourcesFrame` |
| M-I: `noteActiveAnimation()` omitted | `aFlightKeepsTheDisplayLinkAwakeThenLeavesNothing`, `aFlightInsideRetainedOccurrencesLeavesTheStillSiblingAlone` |
| M-J: the group always opens a +3 pt map (a layout/paint shift at rest) | `theModifierMovesNothingAtRest` and eight more (`aNewcomerFlies…`, `aFollowerIsDrawn…`, `withoutATransaction…`, `onlyAMatching…`, `propertiesSelect…`, `aLeaverRemoved…`, `aFlightInterrupted…`, `aFlightInsideRetained…`) |
| M-K: a flight starts from the leaver's laid-out rect, not its drawn one | `aFlightInterruptedByAnotherSwapStartsWhereTheViewWasDrawn` |
| M-L: custom atoms ignored (`.custom` -> `[]`) | `aCustomTransitionInsertsFromItsWillAppearState`, `aCustomTransitionRemovesToItsDidDisappearState`, `aCustomTransitionIsAskedForEveryPhase`, `reduceMotionTurnsACustomTransitionIntoAFade` |
| M-M: removal plays `.willAppear` | `aCustomTransitionRemovesToItsDidDisappearState`, `aCustomTransitionIsAskedForEveryPhase` |
| M-N: the identity phase never asked | `aCustomTransitionIsAskedForEveryPhase` |
| M-O: Reduce Motion skipped for custom transitions | `reduceMotionTurnsACustomTransitionIntoAFade` |
| M-P: `buildActivity` always 0 (no graft refusal) | `aFlightInsideRetainedOccurrencesLeavesTheStillSiblingAlone` (it pins the refusal `matchedGeometry` and `grafts == 0`) |
| M-Q: `TransitionContent.init` public (native build) | `theUnsupportedTransitionsDoNotCompile` |
| M-H: register the hitbox at the flying rect | no mutation site (the group's `prepaintGroup` is a pure forward): `aFlyingViewIsHitAtItsFinalFrame` is a pin, not a mutation-tested test |

Two earlier mutation passes were discarded: a first table was corrupted by overlapping runs of the mutation script on one tree (visible as impossible reds), and M-P first stayed green until
the test gained a follower inside a retained occurrence and read the refusal by name. The table above is one clean sequential pass over the committed tree. The suite also passes under `METALUI_VERIFY_RETAINED=1` (`MatchedGeometryTests`, `TransitionTests`).

## Not built (`MG-H`)

`contentTransition(_:)` (and `.numericText()`): needs an old-text capture per `Text` identity; `.blurReplace`: no blur atom; `.modifier(active:identity:)`; the **`glassEffectID` morph** (divergence 828 stays): a glass blob merges at paint from member
rects (`LG-G`), so a morphing member needs the container to merge on shown rects; content carrying glass already flies with `matchedGeometryEffect`. The leaver's own move to the newcomer (897) and a layout-time size (896) are
divergences, not carried work.

## Unresolved / owed

- SwiftUI's `.size` alone showed no visible motion on a fixed-frame child (S10, P6); MetalUI implements the name. `anchor` is unprobed (`MG-D`). Reduce Motion is not applied to the flight (unprobed).
- A cross-container swap inside a scrolled region uses root-space rectangles plus the paint offset; both views are assumed to share one translation context (a flight between two scroll views is not tested).
- A position whose conditional was not evaluated (a `List` row leaving its window) reads as a leaver (`MG-B` c); a second view with the same id arriving in that frame would fly from it.
- Human checks: group `MG` (the looks of the morph, the stretch, the click during a flight).
- No mutation site for the hit-test pin (`aFlyingViewIsHitAtItsFinalFrame`): the group's `prepaintGroup` is a pure forward.

## Counts

Root: `swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel --skip AppKitPresentationTests`: one summary line,
`Test run with 4651 tests in 12 suites ... after 306.874 seconds with 1 issue` - the one issue was `everyStateTableAndAnimationStoreChannelIsClassified` (the new `matched` channel owed a row; added as `.ledger`, and
that test, `MatchedGeometryTests` and the transition guard re-run green under `--build-system native`). So 4651 tests pass after the fix (4635 at `HT-Z` + 16 here); guards: `FR-J no-argument frame: succeeded=true`, and
`AN-AE unsupported: supported succeeded=true ... blurReplace succeeded=false` printed (the guard ran, not skipped). The CLAUDE.md counts line is not edited, by instruction. `Backends/SDL`: `swift build $(python3 scripts/fetch-accesskit.py --print-flags)` complete.
`zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. The full run was taken on a Mac shared with other builds; the figure is a test count, not a timing.
