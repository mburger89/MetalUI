# MetalUI and SwiftUI — where they differ

MetalUI's public vocabulary follows SwiftUI on macOS. This page lists every
place it knowingly does not: **73 live divergences**, each measured (a probe
arm in `docs/probes/`, run against real SwiftUI) or ruled as MetalUI's own
choice, each with the test that pins MetalUI's answer. A divergence is not a
bug report: it is expected, measured behaviour. If a test named here starts
failing, read the row first — the change may be a fix.

This is the current list (plan task 15, ruling `CX-G`; 2026-10-01; drag and
drop added 100–102, rulings `DN-G`, `DN-K`, `DN-M`; the app-owned GPU surface
added 103, ruling `MV-G`; paths, shadows and transforms' lane 2 added 107–109 and amended 41, rulings `GX-I`, `GX-H`, `GX-G`, `GX-P` — 104–106 are allocated to that branch's lane 3 by `GX-M`, next label 110). Its dated
history, with every mechanism and measurement, is
[`record/04-divergences.md`](record/04-divergences.md); the rulings named in
each row are in [`superpowers/`](superpowers/). Labels are stable ids:
retired labels (listed at the end) are never reused, so a gap is not a lost
row.

Also on this page: [what SwiftUI offers that MetalUI does not](#not-offered)
(documented absences), and [what this list does not cover](#scope).

Columns: **#** label · **what differs** · **SwiftUI** · **MetalUI** ·
**ruling** · **pin** (the test asserting MetalUI's answer; "unpinned" where
none exists, with the reason) · **owner** ("none" means kept by design, not
scheduled).

## Live

| # | what differs | SwiftUI | MetalUI | ruling | pin | owner |
|---|---|---|---|---|---|---|
| 1 | colour space | colours render as authored in sRGB | the layer's colour space is Display P3 while `Hsla.rgb(_:)` authors sRGB, so a hex colour renders somewhat more saturated | spec §7.8 | unpinned (a property of `MetalLayerSurface`'s `CAMetalLayer`, no headless reading) | none |
| 9 | absolute box with no insets | (no absolute positioning; CSS uses the static position) | an all-`auto`-inset `.position(.absolute)` box inside a `Deferred` sits at the window's origin | `AP-F`, `LR-CI` | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` (its divergence-9 arm) | none |
| 10 | portals and clipping | a sheet/popover is outside the presenter's tree; an `.overlay` is clipped with it | `Deferred` escapes every ancestor clip and scroll translation, whatever surrounds it; there is no spelling for a portal one ancestor clips | `AP-I`, `LR-CP` item 5 | `aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface`, `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll` | none |
| 13 | `List` window on resize | a `List` lays out at its new size immediately | the first frame after a resize windows against last frame's viewport extent (two rows of overscan cover it), then asks for one more frame | `MP-F`, `DD-F` items 3–4 | `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `aGrownViewportIsFilledOnTheNextFrameWithoutInput` | none |
| 20 | a modifier added at run time | modifiers carry no state | a layer added to a legacy modifier chain is adopted by the new outermost layer (old id, animation baseline, hitbox id, accessibility node); the wrapped element moves one level down and resets | `MC-C` | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne` | none |
| 21 | focus on disable | a focused element that becomes disabled keeps focus (probe K2) | it loses focus at once; re-enabling does not restore it | `EV-F` (a), `IX-G` item 1 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce` | none |
| 22 | keys under a disabled ancestor | a disabled parent's `.onKeyPress` still runs (K6) | a disabled ancestor's raw `onKey` and `keyContext` are removed | `EV-F` (b), `IX-G` item 1 | `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`, `aDisabledPaneContributesNoKeyContext` | none |
| 23 | a disabled click target | its shape still blocks a click to what is under it (P2f/P2g) | it registers no hitbox, so the click reaches an enabled element under it | `EV-E` | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` | none |
| 25 | `layoutDirection` | right-to-left mirrors stacks | carried and readable; no container mirrors | `EV-K` | `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack` | none |
| 26 | key bubbling order | an ancestor's `.onKeyPress` runs first (K5) | raw `onKey` bubbles outward from the focused element, innermost first | (measured in task 9, record §04) | `anUnhandledKeyEventBubblesToItsAncestorsInnermostFirst` | none |
| 27 | press through accessibility | a tap gesture is not pressable, even with `.isButton` | gestures publish no press either (G1–G5, G7); MetalUI's own `onClick` is pressable — SwiftUI has no `onClick` to compare | `AB-G`, `IX-Y` item 3 | `aGestureOrTapPublishesNoPressAndAnAccessibilityActionAddsOne` | none |
| 29 | a button over an interactive descendant | collapsed into one element (R7) | stays an unlabelled button with its children | `AB-G` | unpinned (record §04's 2026-09-15 table) | none |
| 30 | a labelled focusable/adjustable container | distributes the label and copies the adjustable action to each child (C1, C5, C5i) | keeps a labelled group | `AB-T` | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` (arm 7) | none |
| 31 | nothing focused | reports the first focusable node (arm 13) | reports the host view | `AB-J` | unpinned (record §04's 2026-09-15 table) | none |
| 32 | `List` rows to accessibility | all rows reachable through `AXRows` (L1) | AppKit publishes `AXOutline`/`AXRow` as SwiftUI does, but only realised rows | `AB-L`, `IX-AA` item 3 | `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline` | none |
| 33 | role of a labelled generic node | `AXUnknown` (also under `.ignore`, a removed `.isButton`, a labelled shape) | `AXGroup` | `AB-F`, `IX-V` | `anAccessibilityElementIgnoresItsChildrenByDefault` | none |
| 34 | `Stack` accessibility order | front to back | declaration order | `AB-P` | unpinned (record §04's 2026-09-15 table) | none |
| 38 | a negative fixed size or maximum | diagnosed and floored at 0 (H6, H10) | traps at registration (a negative minimum is floored as SwiftUI does) | `SA-J`, `FR-L`, `FR-R` | `aNegativeFixedFrameDimensionTraps`, `aNegativeFrameMaximumTraps` | none |
| 41 | default hit region | content-derived: a stack's empty middle misses (H1); under a render effect a handler written outside a padding hits only the turned content (probe `swiftui-paths-shadows-transforms.swift` H1b's reading) | the element's whole frame (a bare `Shape`'s too); a handler written outside a rect-changing layer (`.padding`) over a `rotationEffect`/`scaleEffect`/`offset` hits its own axis-aligned frame — write it inside the padding or before the effect (`GX-P` item 2) | `OM-I`, `GX-P` | `metalUIsDefaultHitRegionIsTheElementsWholeFrame`, `aHandlerOutsideAPaddingOverAnEffectHitsItsAxisAlignedFrame` | none |
| 42 | a padded click target | edge misses in both orders (P1/P2) | hittable in its padding when the `onClick` is written after the padding | `OM-K` | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | none |
| 43 | content shape against a clip | a grown content shape hits through `.clipped()` (H6) | a grown (negative-inset) content shape is intersected with an ancestor's clip; `clipShape`'s own hit region is its rect, not its rounded geometry | `OM-AJ`, `IX-L` item 2 | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `aClipShapesCornersStayHittableAndItsRectBoundsTheHit` | none |
| 44 | `allowsHitTesting(false)` on an inner layer | no hit in either order (X1–X3) | does not reach a click written on a later layer | `OM-AL` | `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` | none |
| 46 | two `.opacity` on one element | multiply (0.25) (G1/G2) | the second replaces the first (0.5) | `OM-AH` | `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` | none |
| 47 | legacy `.cornerRadius` | clips its content; a background or border written after it is square (C1, C3, D1) | on a legacy element it rounds the fill and border and clips nothing (`.clipped()` clips), in either order — one order-insensitive `Decoration`. The proposal-path `.cornerRadius` agrees with SwiftUI | `OM-G`, `CX-B` | `aBareCornerRadiusDoesNotClipTheChildren`, `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` | none |
| 49 | legacy rounded border | a square border clipped by the radius (D2 vs M1) | a rounded stroke that follows the arc | `OM-W` | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`, `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` | none |
| 50 | `contentShape(inset:)` before a wrapper | the inset is honoured (S1/S2) | written before a wrapping modifier with the `onClick` after it, it is inert | record §16 | `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt` | none |
| 51 | spacing beside text in a stack | font-derived (text\|text 0, rect\|text 4.74) (S) | the default 8 | `CN-H` | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` | none |
| 52 | `Row`/`Column` default spacing | `HStack`/`VStack` default to 8 | the legacy `Row`/`Column` default to 0 (they keep their CSS gap); `HStack`/`VStack` default to 8 | `CN-P` 1, `CX-E` | `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault`, `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` | none |
| 54 | legacy `ScrollView`'s cross axis | a scroll view takes its content's cross size (SC2) | the legacy `ScrollView` takes its parent's; `ProposalScrollView` takes its content's | `CN-P` 3, `DD-AB` item 5 | `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem` | none |
| 56 | `.frame` on a multi-member `Component` | `Group` frames each member and the parent lays them out (L1–L3, L5, L8) | one layer over a row of per-member frames: rows them in a vertical parent, occupies its parent over zero members, aligns members by the frame's own alignment | `CN-N`, `ID-I` | `aFrameOverAMultiMemberComponentFramesEachMember`, `aMultiMemberFrameRowAlignsItsMembersByTheFramesOwnAlignment` | none |
| 57 | a click through a primary | a non-clickable primary blocks a click to its `.background` content (H3) | it passes the click through | `CN-K` | `aDrawnElementWithoutAPointerTargetDoesNotBlockAClickBeneathIt` | none |
| 58 | a `ZStack` placed in larger bounds | (no such placement) | the union of its children sits at the bounds' origin | `CN-E` | `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` | none |
| 60 | a text's width | ceiled to the `displayScale` pixel grid (M1) | the unrounded widest line; only the stored rect is rounded | `TE-G` item 1 | `aTextAnswersItsUnroundedWidestLineWhereSwiftUICeilsToThePixelGrid` | none |
| 61 | `Grid` residual model disagreements | SwiftUI's undocumented span/priority rules (GZ2–GZ8) | the reference model; the GZ table is the dated baseline no change may lower | `GR-O` 1, `CX-H` | `theModelsDisagreementsWithSwiftUIArePinned` | none |
| 62 | `Grid` divergence corpus | as above, the committed 65 cases | the model's answers | `GR-O` 2, `GR-AH` item 4, `CX-H` | `theModelDisagreesWithSwiftUIOnTheDivergenceCorpus` | none |
| 63 | `gridCellColumns(0)` | — (probe `GR-O` 3) | lays out as 1 | `GR-O` 3 | `gridCellColumnsZeroLaysOutAsOne` | none |
| 65 | rows of text in a `Grid` | font-derived row spacing | the default row spacing | `GR-O` 5 | `textRowsTakeTheDefaultRowSpacing` | none |
| 66 | a modifier on a multi-cell `GridRow` | applies per cell | traps | `GR-O` 6 | `aModifierOnAMultiCellGridRowTraps` | none |
| 67 | a column count above `Int32.max` | — | traps | `GR-O` 7, `GR-S` | `aColumnCountAboveInt32MaxTraps` | none |
| 68 | grid size limit | — | the kernel's grid bookkeeping is bounded by `Int32` | `GR-S` | unpinned (`aColumnCountAboveInt32MaxTraps`' doc comment records it) | none |
| 70 | a stack's infinite tie | serves the child larger at 0 first (T7) | breaks a tie in declaration order | `GR-X` | `aStackServesItsLeastFlexibleChildFirst` | none |
| 71 | one value placed twice, written outside input | each occurrence's own storage (S5, S6) | a write from a phase or a raw closure reaches the last-bound occurrence (a dispatched handler resolves its own) | `ID-F` | `aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence` | none |
| 72 | two siblings with one `.id` | distinct (X2) | share one identity, state entry, hitbox id and accessibility node | `ID-H` | `twoSiblingsWithTheSameIDShareOneStateEntry`, `twoSiblingGroupsWithTheSameIDShareOneIdentity` | none |
| 73 | `.overlay {}`/`.background {}` on a multi-member primary | one instance per member (G3–G6) | traps naming the count | `ID-I` item 3 | `aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount`, `aLegacyBackgroundOnATwoMemberComponentTrapsNamingItsPrimaryCount` | none |
| 76 | `controlSize` | resizes text and every control (Z2, Z3) | reaches every text's default font and `Button`'s chrome; `TextField`'s padding, `Toggle`, `Picker`, `Slider`, `Stepper` read nothing | `EV-AC`, `DD-R` item 4, `TE-F` item 4 | `controlSizeReachesTheDefaultFontButNoControlsChrome` | none |
| 77 | layout rounding | to the `displayScale` pixel grid (S4) | every stored rect to whole points | `EV-AD` | `layoutRoundsToWholePointsWhateverTheDisplayScale` | none |
| 78 | `Binding` isolation | nonisolated, `Sendable` | `@MainActor` | `DD-D` item 4 | `aBindingIsMainActorIsolated` | none |
| 79 | `ForEach` ids colliding in description | both elements (S6) | only the first (`1` and `"1"` share a name) | `DD-L` | `aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst` | none |
| 80 | controls and Full Keyboard Access | controls take keys and Tab reaches them only with Full Keyboard Access on (F5/F6) | every control is focusable, Tab reaches it and it takes its keys; MetalUI reads no system setting | `DD-T` item 3, `TI-J` | `aFocusedButtonActivatesOnSpaceAndOnReturnOnlyOffApple`, `tabVisitsTheControlsAndAControlItFocusedTakesItsKeys` | none |
| 81 | the automatic `Picker` | a pop-up menu (PK0/PK1) | segmented; `.pickerStyle(.menu)` does not compile | `DD-V` item 4, `IX-M` | `aMenuPickerStyleIsNotOffered` | none |
| 82 | stepper/radio-group accessibility | a sibling static text beside an unlabelled control; a slider value indicator; stepper arrows read disabled | the partial fold names the control from its descendants; no value indicator; arrows enabled | `DD-U` items 3, 9 | `aPickerPublishesARadioGroupTitledByItsTitle`, `aStepperPublishesALabelledIncrementorWithTwoArrowButtons` | the human VoiceOver run |
| 84 | `List` shape | greedy, self-scrolling, any content, per-row heights (LS0) | `rowHeight × count`, needs an enclosing `ScrollView`, data-driven, one row height — virtualized by design | `DD-AB` item 3 | `aListSizesItselfToCountTimesRowHeight` | none |
| 86 | line advance | TextKit's line-fragment height (X13) | `ceil(ascent + descent + leading)` on both text systems | `TE-G` item 3 | `aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree` | none |
| 87 | middle truncation | sometimes keeps more at the same width (X5) | keeps what `CTLineCreateTruncatedLine(.middle)` keeps | `TE-I` | `aMiddleTruncationKeepsCoreTextsStringWhereSwiftUIKeepsMore` | none |
| 88 | baseline-aligned `GridRow` | keeps the row height and overflows (X11) | traps at registration | `TE-K` item 4 | `aGridRowWithATextBaselineAlignmentTraps` | none |
| 89 | a wrapping text beside a `Spacer` | shares a limited height with the spacer (K1, K4) | offered the height less the spacer's minimum | `TE-Z` | `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes` (its two spacer arms) | none |
| 90 | continuous corners | Apple's continuous curve | drawn circular (196 px at r = 20 in 100×60) | `TE-AG` item 2 | `theContinuousStyleIsTheDefaultAndIsDrawnCircular` | none |
| 91 | an ellipse clip | clips to the ellipse | `clipShape(Ellipse())` traps naming the divergence | `TE-AJ` item 4 | `clipShapeOfAnEllipseTrapsNamingDivergence91` | none |
| 92 | crossing rounded clips | their exact intersection | the square bounding box | `TE-AJ` item 5 | `twoCrossingRoundedClipsIntersectAsTheSquareBox` | none |
| 93 | `.interpolation(.high)` | high-quality sampling | bilinear, as `.low`/`.medium` | `TE-AL` | `interpolationNoneIsNearestAndEveryOtherLinear` | none |
| 94 | a click on a focusable view | focuses it (F3) | a click on `.focusable()` or a `Button` does not focus it (a `TextField`, `TextEditor` and selectable `List` do) | `IX-K` item 2 | `clickingAFocusableElementDoesNotFocusIt`, `aButtonIsFocusableButAClickDoesNotFocusIt` | none |
| 95 | a held element under a modal | still presses (M5) | a request naming an id outside an isolated (`.isModal`) tree is refused | `IX-Z` item 3, `IX-AF` | `aRequestForAnElementOutsideTheModalIsRefused` | none |
| 96 | what animates | placed geometry and render effects, laid out once at the final values (W1, P1, P2, X00) | the declared input, re-laid out every frame; agree for a wrapper's own rect, differ where a child re-lays out or a sibling moves | `AN-X` | `aProposalFrameReLaysItsChildAtEachIntermediateWidth` | none |
| 97 | what snaps on the proposal path | animates | `nil` ↔ value, finite ↔ infinite, `fixedSize`, `layoutPriority`, `aspectRatio`, `allowsHitTesting`, alignment, a `clipShape`'s shape snap | `AN-AB` | `aProposalFlexibleFrameAnimatesAFiniteBoundAndSnapsAnInfiniteOne` | none |
| 98 | default transition | an unannotated insertion/removal cross-fades (X0, W10) | instant | `AN-AE` | `anUnannotatedInsertionAndRemovalAreInstant` | none |
| 99 | nested or sequential `withAnimation` | each write animates with its own call's curve (T9, T10) | one transaction per build: both share the one parked curve; `.animation(_:value:)` is the per-value remedy | `AN-Y` | unpinned (measured by probe T9/T10; no test asserts the shared curve) | none |
| 100 | a disabled drag source or drop destination | still drags (P9) and still takes the drop (P8) | the one disabled gate removes both: a `.disabled` source does not drag, a `.disabled` destination is never targeted and takes no drop | `DN-G` | `aDisabledSourceDoesNotDragAndADisabledDestinationRefuses` | none |
| 101 | a drag leaving the window | a system drag session from the start; its translucent preview leaves the window with it (P6c, P18) | AppKit hands the drag to an `NSDraggingSession` at the window's edge, its image the payload's own (a file's icon, a text badge), not the preview; on SDL a drag cannot leave the window (SDL3 has no outgoing drag API) | `DN-K` | `leavingTheWindowHandsTheDragToThePlatformWhenItCan`, `anSDLWindowCannotBeginAnExternalDrag` (`Backends/SDL`) | none |
| 102 | hovering an external drop on SDL | targets only a destination whose type matches (P16) | SDL gives no types until the drop, so the deepest destination is targeted whatever its type (a non-matching one turns `false` at the drop and runs no action); a URL dragged from a browser arrives as text, so a `URL` destination refuses it. The AppKit backend knows the types and matches SwiftUI | `DN-M` | `anExternalDropWithUnknownTypesTargetsOptimistically`, `sdlDropEventsBecomeOneDropSession` (`Backends/SDL`) | none |
| 103 | when a drawing surface re-runs | a `Canvas` re-runs whenever its declaring view's body re-runs, even for a change it does not read (probe R1); not when idle (R0) or when only its own view's unchanged inputs are re-evaluated (R3); and on a value it reads (R2) | MetalUI rebuilds the whole tree every dirty frame, so "the declaring body re-ran" is every frame: an `.onDemand` `GPUSurface`/`MetalView` redraws only for a new target (first sight, resize, rescale) or a changed `value:` — R0, R2 and R3's answers, not R1's. Remedy: pass what the drawing reads as `value:` | `MV-G` item 5 | `aRequestedTargetIsCreatedAndDrawnOnceThenReused`, `aChangedValueRedrawsAndAnUnchangedOneDoesNot` | none |
| 107 | an accessibility frame under a rotation off a right angle | a 33 × 24 view turned 45° reports a 35.36 square (probe `swiftui-paths-shadows-transforms.swift` X3, unexplained); offset, scale and 90° report the transformed frame's bounding box (X1, X2, X4, X5) | the bounding box of the transformed frame at every angle — 40.31 square at 45° | `GX-I` | `theAccessibilityFrameIsTheTransformedBoundingBox` | none |
| 108 | a legacy element's render effects against its own background and border | a modifier written after `.rotationEffect` is outside it: a background written after the effect is not turned (T8) | `rotationEffect`/`scaleEffect`/`offset` on a `StyledElement` return `Self` and always wrap the whole element — background, content and border — whatever order they are written in (the legacy `Decoration` is order-insensitive, divergence 47's reason); their order among themselves is kept. The proposal vocabulary follows SwiftUI (one layer each) | `GX-H` | `aLegacyEffectWrapsTheWholeElementWhateverTheOrder` | none |
| 109 | a clip between two nested rotations | the clip turns with the outer rotation and cuts the inner content exactly | the clip becomes its axis-aligned screen bounding box (a primitive carries one local mask and one screen mask, not a mask per effect) | `GX-G` | `aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox` | none |

## Retired

Never reused. Each was fixed, or its subject was deleted; record §04 has the
retiring section for every label.

| # | retired | how |
|---|---|---|
| 2 | 2026-10-01 (plan task 15, `CX-R`) | the CSS engine's flex sub-one clause is deleted with the engine (stage 9); a grow-factor sum below 1 lowers as SwiftUI's equal greedy share (`aGrowFactorSumBelowOneStillFillsTheLine`) |
| 3, 5, 6 | 2026-08-31 | sizing fixes |
| 4 | 2026-09-24 (stage 7b) | the CSS root rule went with its tests; production centres a root at its answer (`CN-J`) |
| 7 | before 2026-08-31 | renumbering |
| 8 | 2026-08-30 | `Text.paint` wraps at the measured width |
| 11 | 2026-09-24 (stage 9) | legacy engine deleted |
| 12, 17 | 2026-09-01 | tombstones (bounded) |
| 14 | 2026-09-25 (task 10) | a `List` windows against its own origin (`DD-F`) |
| 15 | 2026-09-16 | nested scroll mask fixed (`OM-U`) |
| 16 | 2026-09-28 (task 10) | the wheel passes to the enclosing scroller (`DD-Y`) |
| 18 | 2026-09-25 (task 8) | an evaluated conditional resets on return (`ID-C`) |
| 19 | 2026-09-25 (task 8) | a dispatched handler resolves its own occurrence (`ID-F`) |
| 24 | 2026-09-25 (task 9) | `displayScale` exposed and writable (`EV-AA`) |
| 28 | 2026-09-30 (task 12) | a press runs under `allowsHitTesting(false)` (`IX-Z`) |
| 35 | 2026-10-01 (plan task 15, `CX-R`) | a legacy flexible frame lowers greedy, SwiftUI's D4 answer (`aLoweredFlexibleFrameLayerTakesSwiftUIsAnswer`) |
| 36, 37, 40 | 2026-09-16 (task 6) | frame overflow, infinite answer, `fraction:` |
| 39 | 2026-10-01 (plan task 15, `CX-R`) | a legacy frame's `idealWidth`/`idealHeight` no longer trap; they answer an unspecified axis as SwiftUI's C1 (`anIdealFrameLowersAtANilProposal`) |
| 45 | 2026-09-25 (stage 11) | what is written after `.opacity` escapes it (`LR-FW`) |
| 48 | 2026-09-25 (task 8) | a `Component`'s width frames each member (`ID-K`) |
| 53 | 2026-10-01 (plan task 15, `CX-R`) | a legacy `Stack` lowers to a stack that offers its child its proposal, SwiftUI's A5 (`aLoweredStackOffersItsChildItsProposal`) |
| 55 | 2026-10-01 (plan task 15, `CX-R`) | a legacy `Row`/`Column` lowers with no weighted shrink; fixed children overflow as SwiftUI's G9 (`aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight`) |
| 59 | 2026-09-21 (stage 2) | text clamps to `min(proposal, widest line)` |
| 64 | 2026-09-29 (task 11) | `gridCellAnchor` takes a `UnitPoint` (`TE-AN`) |
| 69 | 2026-09-25 (task 8) | a vanishing grid cell/row hands nothing on (`ID-B`) |
| 74 | 2026-09-25 (task 10) | a loop's dropped element resets (`DD-C`) |
| 83 | 2026-09-30 (task 12) | `AXSelected` is settable on AppKit (`IX-AA`) |
| 85 | 2026-10-01 (plan task 15, `CX-F`) | an optional `@State` reads its non-`nil` default before its first write (probe O1; `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite`) |

Label 75 was never assigned.

<a id="not-offered"></a>
## Not offered — documented absences

SwiftUI API MetalUI does not provide. None is a numbered divergence (there is
nothing to diverge from); each is ruled, and none has a scheduled owner unless
stated.

| SwiftUI | status | ruling |
|---|---|---|
| `App`/`Scene` lifecycle; iOS, iPadOS, tvOS, watchOS, visionOS, touch, safe areas, `UIAccessibility` | out of scope: MetalUI is macOS, Linux and Windows desktop windowing | `PB-A` |
| `LazyVGrid`/`LazyHGrid`/`GridItem` | not built; the windowing they need exists (`WindowedRowsLayout`) | `GR-L` |
| `transformEffect`, `projectionEffect`, `rotation3DEffect`; a render effect on a `Component` | not built: a public affine type and a projective primitive; on a `Component` declare the effect on its members or a wrapping element | `GX-A`, `GX-P` item 5 |
| two-axis scrolling; `scrollPosition(id:)`; an animated `scrollTo`/scroll offset | not built | `CN-M`, `DD-AB` items 5–6, `CX-I` item 2 |
| `ButtonStyle`/`PrimitiveButtonStyle` as open protocols, `.borderedProminent`, `.link`, `.toggleStyle`, `.pickerStyle(.menu)`, menus, `.contextMenu` | not built (`ButtonStyle`/`PickerStyle` are closed structs) | `IX-E`, `IX-M` |
| `.sequenced`, `@GestureState`, `GestureMask`, a custom gesture `body`, location taps | not built | `IX-B` |
| `Path`, gradients, `StrokeStyle`, SF Symbols, colour glyphs | renderer constraints | shapes spec §9 (`specs/2026-09-28-shapes-and-rendering-design.md`) |
| elliptical corners (`RoundedRectangle(cornerSize:)`), `UnevenRoundedRectangle` | renderer constraint (per-corner circular radii only) | shapes spec §9, `CX-I` item 3 |
| `matchedGeometryEffect`, `contentTransition`, `.modifier(active:identity:)` and custom transitions, `AnyTransition.animation(_:)`, `.blurReplace` | not built | `AN-AE` |
| a readable `colorScheme`; Increase Contrast, Reduce Transparency, Differentiate Without Colour | not built (Reduce Motion is: `accessibilityReduceMotion`, `AN-AD`) | `TE-AO` item 1, `CX-I` item 3 |
| `Image(systemName:)`, asset-catalog images | not built; `Image` takes an `ImageBitmap` | `TE-AL` |
| `.onDrag`/`.onDrop` (`NSItemProvider`), `DropDelegate`; table-row and tab drop variants | not built: `NSItemProvider` is Apple-only and cannot cross the portable surface, and `DropDelegate` is a second surface for the same behaviour — `draggable(_:)`/`dropDestination(for:action:isTargeted:)` are offered | `DN-A` item 2 |
| the `DropSession` family: `dropDestination(for:isEnabled:action:)`, `onDropSessionUpdated`, `dropConfiguration`, `onDragSessionUpdated`, `dragConfiguration`, `dragContainer`, `draggable(containerItemID:)`, `dragPreviewsFormation` | not built (macOS 26 API: a session object with phases, multi-item containers and preview formations is a second design) | `DN-A` item 2 |
| `Transferable`'s conformer spelling, `static var transferRepresentation` (`DataRepresentation`, `CodableRepresentation`, `ProxyRepresentation`, `FileRepresentation`); CoreTransferable's `async` loading | not built: a MetalUI conformer writes `Transferable`'s four synchronous members (`String`, `URL` and `Data` conform already) | `DN-B` item 1, `DN-S` item 4 |
| `NSViewRepresentable` (hosting an arbitrary `NSView`, an `MTKView` among them) | not built: app GPU work goes through `GPUSurface`/`MetalView`, which MetalUI composites itself | `MV-F` item 6 |
| for an app-owned surface (spec §7.7's sketch): a depth attachment, EDR / `rgba16Float` targets, a per-element error channel, device-loss rebuild | not built: the app allocates its own depth texture sized from `pixelSize`; targets are `bgra8Unorm` (§7.8); an encoding error fails the frame's command buffer, which Metal's validation reports | `MV-F` item 6 |

<a id="scope"></a>
## What this list does not cover

- **MetalUI-only API** — the legacy CSS-derived vocabulary (`Box`, `Row`,
  `Column`, `Stack`, the legacy `ScrollView`, `List`, the item/container
  modifiers), `Deferred`, `Component`, the keymap, the theme, `onClick` and the
  backend targets. They have no SwiftUI counterpart to differ from; see
  [`api-overview.md`](api-overview.md) and [`migration.md`](migration.md) for
  their SwiftUI-vocabulary replacements.
- **Declared-but-inert API** — spellings that compile and do little or nothing
  by design (`ButtonRole` draws nothing; `AccessibilityTraits.updatesFrequently`
  publishes nothing, as on macOS; `locale` has no reader; `dynamicTypeSize`
  reaches no text size, as on macOS). The list is
  [`record/05-declared-but-inert.md`](record/05-declared-but-inert.md).
- **Looks nobody has seen yet** — behaviour pinned headless but owed a human
  look: [`verification/human-checks.md`](verification/human-checks.md).
