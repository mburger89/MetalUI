# 177 — Scroll extras and `@Bindable`: pinned section views, `scrollPosition(id:)`, an animated `scrollTo` (`SP-A`…`SP-L`)

2026-10-31, branch `feat/scroll-position` from master `28a819e9` (round-3 item R3-4; the earlier `LZ-N` and `MD-H` item 6 had carried `pinnedViews:`/`Section` and `@Bindable`, and `CN-M`, `DD-AB` items 5-6 and `CX-I` item 2
had carried `scrollPosition(id:)` and an animated `scrollTo`). Decisions: `docs/superpowers/2026-10-31-scroll-position-decisions.md`. Probe: `docs/probes/swiftui-scroll-position.swift`.

## What shipped

- **`@Bindable`** (`SP-D`): `Bindable<Value: AnyObject & Observable>`, `$model.property` as `Binding(get:set:)`. No new observation: the getter's read is tracked by the frame build, the setter's write fires `onChange`.
- **`LazyVStack`/`LazyHStack` `pinnedViews: PinnedScrollableViews`** over **`Section`** (`SP-G`…`SP-J`). The current section's header (the one holding the viewport's leading edge) is placed at `max(natural, edge)` and
  the footer (holding the trailing edge) at `min(natural, edge - extent)` by `LazyStackLayout.placeSubviews`, so a pinned view is a real node at its place - hitbox, accessibility frame and the scroller's anchor
  correction follow - painted and prepainted after the rows. A pinned unit the window does not hold is realised as an extra unit after the window's nodes (`sequenceCount`); the stack stays windowed (window + at most
  the 2 pinned views). `Section` is transparent (three parts on one cursor); a `ForEach` of sections is read by `LazySectionForEachSource` (O(sections) closure calls per frame, rows only in the window).
- **`scrollPosition(id: Binding<ID?>, anchor:)`** on `ScrollView`/`ProposalScrollView` with **`scrollTargetLayout(isEnabled:)`** (`SP-A`…`SP-C`). Targets (`ForEach` elements, eager or lazy, legacy or proposal) report their extent from
  prepaint; `ScrollPositionRegistry` (window-owned, on `ScrollRequestQueue`) keeps them and writes the binding from `Window.scroll` (the wheel), or once after the frame that covers an offset the wheel or a `scrollTo`
  moved the scroller to - never from layout, prepaint or paint. A binding value the scroller did not write is injected into the current frame as a `scrollTo` (redo-safe).
- **`scrollTo` under `withAnimation`** glides (`SP-F`): `ScrollState.glide`, read by every phase through `ScrollChrome.currentOffset` on the frame's timestamp, `noteActiveAnimation` while it runs, ended by a wheel,
  a lazy refinement of the same target keeps it. A binding write under `withAnimation` glides the same way and is reported where it lands.
- **Carried** (`SP-E`, `SP-K`): two-axis scrolling (`ScrollAxis` is a closed one-axis enum; the kernel viewport, `ScrollState`, wheel regions and the lazy planner are one-axis), `List`-row and lazy-grid targets, `LazyVGrid`
  `pinnedViews:`, SwiftUI's `ScrollPosition` struct, `scrollTargetBehavior`.

## The probe (macOS 27.2, Swift 6.4.2)

Pinned: header 0 at 0 at offsets 100 and 230 (V1) where the control reads -100 and -230 (V0); `LazyHStack` the same (H1/H0); 20 of 6000 rows built with a pinned header at offset 30000 (W1); **no push-off**: header 0 stays at 0 to the
last point of its section while header 1 slides in, and is gone at the boundary (O). Unprovable here: the markers of pinned views after section 0 read stale (V1 offset 300: -330 -330), so footers and later headers are
ruled by symmetry. `scrollPosition` (P, X) and an animated `scrollTo` (A) did not drive headless (the broken instrument of `swiftui-lifecycle.swift`), so `SP-A` and `SP-F` rest on documentation, claim no divergence and say
so. The first spec wording ("headers push off as the next header arrives") was refuted by O and not built.

## Divergences

**915** (pins need a windowed stack: an eager stack lays its sections out in sequence), **916** (targets are `ForEach` elements only). 180 live; next label 210; 917-924 reserved by SP, unused. `docs/divergences.md` rows and
`record/04` section; the "not offered" rows for `pinnedViews:`, `scrollPosition(id:)`, an animated `scrollTo` and `@Bindable` are rewritten to what is still absent.

## Tests (two files, `Tests/MetalUITestingTests`)

`ScrollPositionTests.swift` (17): the wheel writes the topmost target and settling frames write nothing; idle frames never write; no wrapper means no target; writing the binding scrolls (top and `.bottom` anchor);
an initial value; a wheel past the window; the trailing anchor; eager stacks; the horizontal axis; equatable rows (also under `METALUI_VERIFY_RETAINED=1`); a static child is not a target; the glide (quarter, half,
three quarters, landing; the link stays awake; the control jumps), a wheel ending it, a binding write gliding and reporting at the landing; `@Bindable` reading, writing through and redrawing.
`PinnedSectionTests.swift` (7): the header pin and its absence of a push-off, the footer pin, the windowed count (control + exactly 2), the hit order in and out of the window, the horizontal axis, sections written
directly in the stack, an eager stack pinning nothing, and a `Section` in a plain `VStack`.

## Mutations (each applied to the declaration the test is named for, run with `swift test --filter 'ScrollPositionTests|PinnedSectionTests'`, then reverted)

- **M1 topmost rule end>reference -> start>reference** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`, `aHorizontalScrollerReportsAlongItsAxis`, `aWheelPastTheRealizedWindowIsReportedAfterTheFrameThatRealizesIt`, `aWheelWritesTheTopmostVisibleTargetAndSettlingFramesWriteNothing`, `anEagerStacksForEachElementsAreTargetsToo`, `equatableRowsAreScrollTargetsAndTheReplayAgrees`, `writingTheBindingScrollsToTheTarget`
- **M2 finishPrepaint reports (a write from a phase)** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`, `aBottomAnchorReportsTheTargetAtTheTrailingEdge`, `aHorizontalScrollerReportsAlongItsAxis`, `aStaticChildOfAScrollTargetLayoutIsNotATarget`, `aWheelPastTheRealizedWindowIsReportedAfterTheFrameThatRealizesIt`, `aWheelWritesTheTopmostVisibleTargetAndSettlingFramesWriteNothing`, `anEagerStacksForEachElementsAreTargetsToo`, `anInitialValueScrollsOnTheFirstFrames`, `equatableRowsAreScrollTargetsAndTheReplayAgrees`, `idleFramesNeverWriteThePositionBinding`, `writingTheBindingScrollsToTheTarget`, `writingTheBindingWithABottomAnchorAlignsTheTargetsBottomEdge`
- **M3 notesScrollTargets ignores scrollTargetLayout** - red: `withoutScrollTargetLayoutNothingIsATargetAndTheBindingStaysNil`
- **M4 beginLayout injects no scrollTo** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`, `anEagerStacksForEachElementsAreTargetsToo`, `anInitialValueScrollsOnTheFirstFrames`, `equatableRowsAreScrollTargetsAndTheReplayAgrees`, `writingTheBindingScrollsToTheTarget`, `writingTheBindingWithABottomAnchorAlignsTheTargetsBottomEdge`
- **M5 first frame does not scroll to an initial value** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`, `anInitialValueScrollsOnTheFirstFrames`, `writingTheBindingScrollsToTheTarget`, `writingTheBindingWithABottomAnchorAlignsTheTargetsBottomEdge`
- **M6 needsReport never set** - red: `aBottomAnchorReportsTheTargetAtTheTrailingEdge`, `aStaticChildOfAScrollTargetLayoutIsNotATarget`, `aWheelPastTheRealizedWindowIsReportedAfterTheFrameThatRealizesIt`, `aWheelWritesTheTopmostVisibleTargetAndSettlingFramesWriteNothing`, `equatableRowsAreScrollTargetsAndTheReplayAgrees`
- **M7 trailing anchor reads the first target** - red: `aBottomAnchorReportsTheTargetAtTheTrailingEdge`
- **M8 ForEach prepaint notes no target** - red: `anEagerStacksForEachElementsAreTargetsToo`
- **M9 noteScrollTarget ignores the scroller axis** - red: `aHorizontalScrollerReportsAlongItsAxis`
- **M10 scrollTo reads no pending transaction** - red: `scrollToUnderWithAnimationGlidesAndTheControlJumps`
- **M11 wheel keeps the glide** - red: `aWheelEndsAnAnimatedScrollWhereItStands`
- **M12 Bindable getter returns a copy taken at creation** - red: `aBindableProjectsBindingsThatReadAndWriteThroughTheObject`
- **M13 pinned views never pinned** - red: `aLazyHStackPinsAlongItsAxis`, `aPinnedFooterStaysAtTheBottomWhileItsSectionIsCurrent`, `aPinnedHeaderIsAboveTheRowsUnderIt`, `aPinnedHeaderStaysAtTheTopWhileItsSectionIsCurrent`, `aPinnedStackRealizesOnlyTheWindowAndThePinnedViews`, `sectionsWrittenDirectlyInTheStackPinToo`
- **M14 footer pinned at the edge instead of edge - extent** - red: `aPinnedFooterStaysAtTheBottomWhileItsSectionIsCurrent`, `sectionsWrittenDirectlyInTheStackPinToo`
- **M15 pin realises the whole section** - red: `aPinnedStackRealizesOnlyTheWindowAndThePinnedViews`
- **M16 LazyHStack drops pinnedViews** - red: `aLazyHStackPinsAlongItsAxis`
- **M17 pinned boxes prepainted in unit order** - red: `aPinnedHeaderIsAboveTheRowsUnderIt`
- **M18 Section returns its footer nodes before its content** - red: `aSectionInAnOrdinaryStackIsItsPartsInSequence`
- **M19 footer role not recognised in the section spans** - red: `sectionsWrittenDirectlyInTheStackPinToo`
- **M19b footer role not recognised in a ForEach of sections** - red: `aPinnedFooterStaysAtTheBottomWhileItsSectionIsCurrent`, `aPinnedStackRealizesOnlyTheWindowAndThePinnedViews`
- **M20 glide value ignored (stored target used)** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`, `scrollToUnderWithAnimationGlidesAndTheControlJumps`
- **M21 pins computed for an unbounded plan (no existing line separates an unbounded plan: `plan.index` is nil there; see M21b)** - red: none (see note)
- **M21b the eager rule dropped (LZ-B): an eager stack read as no units** - red: `anEagerLazyStackLaysItsSectionsOutInSequenceAndPinsNothing`
- **M22 static units noted as targets** - red: `aStaticChildOfAScrollTargetLayoutIsNotATarget`
- **M23 injected request carries no animation** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`
- **M24 report while gliding** - red: `aBindingWrittenUnderWithAnimationGlidesAndReportsAtTheLanding`
- **M25 glide restarted by a refinement** - red: `scrollToUnderWithAnimationGlidesAndTheControlJumps`

Twenty-six of twenty-seven mutations redden at least one test; M21 reddens none because the `bounded` check is redundant with the `plan.index` check on that path (the eager path never reaches it), and M21b mutates the line that does carry the claim. Each was applied to one spelling in `Sources/MetalUI` and reverted with the file's original text.

## Counts

2026-10-31, `feat/scroll-position` at the commit that adds this record, on master `28a819e9`: **root 4660 tests passed in 12 suites with `AppKitPresentationTests` skipped (`--skip`; the screen may be locked)**, `swift package clean`, then
`swift build --build-system native --build-tests` and `swift test --build-system native --no-parallel --skip AppKitPresentationTests`; `FR-J no-argument frame: succeeded=true` printed. The suite before this change was 4635 (master `872e11b7`...`28a819e9`);
the 24 new tests are `ScrollPositionTests` (17) and `PinnedSectionTests` (7); the guard `lazyInitHasNoPinnedViewsParameter` became `lazyInitTakesPinnedViewsAndNoOtherExtraArgument` (a rename, not a new guard), so the guard count (285) is unchanged and not re-tallied.
Under `METALUI_VERIFY_RETAINED=1`, `--filter "Retained|ContentMemo|Lazy|ScrollPosition|PinnedSection|VariableHeightList|ScrollAnchor"`: 313 tests passed. `Backends/SDL`: `swift build $(python3 scripts/fetch-accesskit.py --print-flags)` builds. Not run: Linux and
Windows CI (the new files import `Observation` only in `Bindable.swift`, which `ContentMemo.swift` already does), and the human checks (group SP).

## What a later reader should know

- A lazy window plus `scrollPosition` lags one frame after a big wheel (the entry is reported after the frame that realises the window): the binding is correct at rest, not on the frame of the wheel.
- The pin test figures use one extent (20) for headers, rows and footers on purpose: the lazy index estimates unrealised units by the measured mean, so a mixed-height fixture's pinned offsets are only right after
  every unit has been measured; `settle` ticks until an anchor adjustment stops.
- `scrollTargetLayout()` is a wrapper, not an environment value (adding a field to `EnvironmentValues` would have touched the epoch and the retained fingerprints for a flag read in two places).
