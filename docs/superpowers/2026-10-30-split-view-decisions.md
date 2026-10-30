# Split views - decisions

Rulings for `HSplitView` / `VSplitView` (MetalFlow's palette | canvas | inspector layout). Prefix `HS-`. Branch `feat/mf-split`. Code: `Sources/MetalUI/SplitView.swift`; tests:
`Tests/MetalUITestingTests/SplitViewTests.swift` (portable, plain imports). **Next unused: `HS-I`.** Divergence 206 (the orchestrator moves the label if another branch took it).

## HS-A - the shape: two ProposalElements over one engine, class D not A

**Ruling.** `HSplitView<Content: ProposalElementGroup>` and `VSplitView` are `Element, ProposalElement` structs (init `@ProposalContentBuilder`, SwiftUI's `init(content:)`) holding one
internal `SplitEngine<Content>` and one `@State SplitModel`; the engine registers the panes, then one `SplitDivider` per pair, then a single native node for `SplitLayout`
(a `ProposalLayout`). They are not `Component`s because `Component` has an associated type named `Content`, which the SwiftUI generic parameter would collide with.
The inventory class is **D** (family `split-view`, divergence 206), not the A the brief asked for: class A needs a SwiftUI probe file with recorded output and a test citing its arm, and no
probe was run (an agent can run a probe, but `NSSplitView`'s resize distribution is not something a layout-only probe settles; the divider look and hit area need eyes). A later probe plus
human check can promote the family to A and retire 206.
**Cost if wrong.** A label and an inventory class.

## HS-B - the limits are three measurements, the initial size is the ideal

**Ruling.** `SplitLayout` measures each pane along the split axis at proposal 0 (minimum), nil (ideal) and infinity (maximum), with the cross proposal fixed, so a pane's
`.frame(minWidth:idealWidth:maxWidth:)` is read exactly as SwiftUI's own stacks read it; a non-finite maximum is unbounded. The three are ordered by `SplitPaneLimits.init` (a maximum below the
minimum rises to it, the ideal clamps between). Panes start at their ideal. A pane with no `.frame` answers its content's ideal and is unbounded, so it takes what the others leave ("panes
without an ideal share the remaining space").
**Pin.** `panesStartAtTheirIdealWidthsAndTheFlexiblePaneTakesTheRest`. **Cost if wrong.** Initial widths.

## HS-C - distribution: unbounded panes first, equally; then bounded ones

**Ruling.** `SplitSolver.solve`: each pane starts at its preferred size (the user's, when the stored array has one entry per pane) else its ideal, clamped to its limits. A surplus or deficit
goes to the panes with an unbounded maximum, equally, by water-filling (a pane that reaches a limit drops out, the rest take its share); what those cannot take goes to the bounded panes the
same way; minimums that do not fit overflow (the container still places each pane at its size). The container answers the proposal along the axis when it is finite, else the sum of the ideals
plus the dividers, and the cross proposal else the tallest pane. It fills a finite proposal (SwiftUI's `HSplitView` expands).
**Pins.** `windowResizeGivesTheSpaceToTheFlexiblePane`, `aDraggedSizeSurvivesAWindowResize`, `withNoUnboundedPaneTheBoundedOnesShareTheSurplus`.
**Cost if wrong.** Which pane absorbs a resize; unprobed against `NSSplitView` (divergence 206).

## HS-D - a drag is the press-time sizes plus the translation, clamped on the pair; state is written from the handler only

**Ruling.** The divider is a `DragGesture(minimumDistance: 0)`. Its first event keeps a `SplitDragSnapshot` (the sizes and limits the layout last placed) in the split view's `@State`; every
event after computes `SplitSolver.dragged(snapshot, by: translation)`: the two neighbours keep their total, each clamped to its limits (the near pane's max and min, the far pane's, so the
excess never reaches a third pane), every other pane keeps its size. The result is written as the whole `[Double]` of pane sizes (the "preferred" array); the end clears the snapshot and saves
(HS-G). A press that does not move writes no sizes and saves nothing. Nothing writes sizes from a phase: layout reads `preferred` and reports, input writes (the "write state from input"
rule). The clamp is on the total translation, not accumulated, so going past a limit and back follows the pointer. The solver re-clamps every preferred size, so the drag's own clamps are what
keep a third pane still: three tests pin the three bounds that the re-clamp would otherwise hide.
**Pins.** `draggingADividerResizesItsTwoNeighbours`, `aDragIsClampedToTheNeighboursLimits`, `goingPastALimitAndBackFollowsThePointer`, `aDragStopsWhereThePaneBeingDraggedReachesItsMaximum` / `...Minimum`,
`aDragStopsWhereTheFarNeighbourReachesItsMaximum` / `...Minimum`, `aClickOnTheDividerChangesNothing`.
**Cost if wrong.** Drag feel at limits.

## HS-E - the layout reports back through a per-build class; no layout memo for the subtree

**Ruling.** The handlers need the laid-out sizes and limits, which exist only in the kernel. `SplitLayout` carries a `SplitReport` (a final class, `@unchecked Sendable`) created in the same
`requestLayout` as the divider closures and filled in `placeSubviews`; only input handlers read it. `SplitLayout` is **not `Hashable`**, so it taints its ancestors for the layout memo as
`LazyStackLayout` does (`LZ-F`): a hit could otherwise skip the placement that fills the report. Observed: the gesture arena keeps the closures of the press frame, so the report a drag reads is
the press-time one even without the snapshot; the `@State` snapshot is kept anyway so the drag does not depend on that (mutation M4 is therefore an equivalent mutant).
**Cost if wrong.** The subtree is never memoized; a split view inside an `.equatable()` is replayed with its press-time report, which stays consistent with its closures.

## HS-F - the divider is composed from existing modifiers: no new registration site

**Ruling.** `SplitDivider` (a `Component`) is `Color(.separator).frame(1 across)` with an `.overlay` of `Color.clear.frame(6 across).gesture(DragGesture).pointerStyle(.columnResize | .rowResize)`.
The 1-point line is the layout node; the 6-point hit area is an overlay so it takes no room, overlaps each neighbour by 2.5 points, and ranks above the panes because the dividers register after
them. The handlers register through `GestureModifier` and `PointerStyleModifier`, which already go through `registerHandlers`, so there is **no new handler-registering site** and the D2
guard needs no new arm. Panes are requested inside `withStackAxis`, as `HStack`'s, so a `Divider()` that is itself a pane draws across the split. The divider publishes no accessibility node
(the gesture modifier synthesizes none) and has no hover highlight.
**Pins.** `theDividerShowsTheColumnResizePointerOverItsHitArea`, `aVSplitViewIsTheSameOnTheVerticalAxis` (row resize).
**Cost if wrong.** Divider look; accessibility (Carried).

## HS-G - autosave behind a public seam

**Ruling.** `.splitViewAutosaveName(_ name: String, store: (any SplitViewAutosaveStore)? = nil)` (MetalUI-only, class M, a method on `HSplitView` and `VSplitView` returning `Self`; write it
directly on the split view) names an entry. `SplitViewAutosaveStore` is a public `@MainActor` class-bound protocol (`paneSizes(forName:)`, `setPaneSizes(_:forName:)`) so an app's test target, which
uses plain imports, can inject an in-memory store; the default is `UserDefaultsSplitViewStore` over `UserDefaults.standard`, key `MetalUI.SplitView.<name>` (`MetalUI` already imports
Foundation on every platform: `Color.swift`). Sizes are saved once, when a drag that moved ends; they are restored whenever the state holds none (read on each build until the first drag), and
a stored array whose length differs from the pane count is ignored.
**Pins.** `autosaveRoundTripsThroughTheInjectedStore`, `aClickOnTheDividerChangesNothing`. **Cost if wrong.** The key spelling is a compatibility promise to saved defaults.

## HS-H - VSplitView is the same engine on the other axis

**Ruling.** `SplitLayout.axis` decides every read: width or height proposals, the divider's across/along, the row-resize pointer. The limits come from `.frame(minHeight:idealHeight:maxHeight:)`.
**Pin.** `aVSplitViewIsTheSameOnTheVerticalAxis`.

## Mutations

Method: edit the named declaration in `Sources/MetalUI/SplitView.swift`, run `--filter SplitViewTests` under `--build-system native`, restore. Named tests are those that reddened.

| # | mutation | reddened |
|---|---|---|
| M1 | `SplitSolver.solve`: start from the minimum, not the ideal | `panesStartAtTheirIdealWidthsAndTheFlexiblePaneTakesTheRest` and nine more (every test that reads a column) |
| M2 | `dragged`: leave the second pane of the pair alone (`sizes[b]` not set) | `draggingADividerResizesItsTwoNeighbours`, `aDragIsClampedToTheNeighboursLimits`, `autosaveRoundTripsThroughTheInjectedStore` |
| M3 | `dragged`: drop `maximums[a]` from the upper bound | `aDragStopsWhereThePaneBeingDraggedReachesItsMaximum` (the first spelling of the other tests stayed green: the solver's re-clamp hides it when the neighbour is unbounded, hence the dedicated test) |
| M3b | `dragged`: drop `total - maximums[b]` from the lower bound | `aDragStopsWhereTheFarNeighbourReachesItsMaximum` |
| M3c | `dragged`: drop `total - minimums[b]` from the upper bound | `aDragStopsWhereTheFarNeighbourReachesItsMinimum` |
| M3d | `dragged`: drop `minimums[a]` from the lower bound | `aDragStopsWhereThePaneBeingDraggedReachesItsMinimum` |
| M4 | `dragChanged`: never reuse the snapshot (`if let held = state.drag, ..., false`) | **none, an equivalent mutant**: the arena keeps the press-time closures and report (HS-E), so the snapshot is the same either way |
| M5 | `solve`: spread over the bounded panes before the unbounded | eight tests including `panesStartAtTheirIdealWidthsAndTheFlexiblePaneTakesTheRest`, `windowResizeGivesTheSpaceToTheFlexiblePane`, `draggingADividerResizesItsTwoNeighbours` |
| M6 | `placeSubviews`: solve with `preferred: nil` | `draggingADividerResizesItsTwoNeighbours`, `aDragIsClampedToTheNeighboursLimits`, `goingPastALimitAndBackFollowsThePointer`, `aDraggedSizeSurvivesAWindowResize`, `aVSplitViewIsTheSameOnTheVerticalAxis`, `autosaveRoundTripsThroughTheInjectedStore` |
| M7 | `SplitDivider`: `.rowResize` for the horizontal split | `theDividerShowsTheColumnResizePointerOverItsHitArea` |
| M8 | `hitExtent` 6 to 1 | `theDividerShowsTheColumnResizePointerOverItsHitArea`, `aDragIsClampedToTheNeighboursLimits`, `aVSplitViewIsTheSameOnTheVerticalAxis` |
| M9 | `dragEnded`: do not save | `autosaveRoundTripsThroughTheInjectedStore` |
| M10 | `requestLayout`: do not read the store | `autosaveRoundTripsThroughTheInjectedStore` |
| M11 | `dragChanged`: write sizes for a zero translation | **none, an equivalent mutant** (the written sizes equal the placed ones; a click only freezes them) |
| M11b | `dragEnded`: `moved = true` | `aClickOnTheDividerChangesNothing` (after the test gained a click following a drag) |
| M12 | `SplitLayout.horizontal` always `true` | `aVSplitViewIsTheSameOnTheVerticalAxis` |
| M13 | `solve`: skip the bounded pass | `withNoUnboundedPaneTheBoundedOnesShareTheSurplus` |

The mutated spelling was applied to the declaration named; the 1 MB-stack and AppKit-only checks were not touched (no demo section, no AppKit file).

## Carried

- A probe of `HSplitView` against real SwiftUI/`NSSplitView` (resize distribution, divider thickness and colour, minimum overflow) and a human look; either settles divergence 206 and could make the family class A.
- No pane collapse or hide, no double-click-to-reset, no keyboard resize, no divider accessibility node (a `separator` role with a value), no hover highlight on the divider.
- Autosave is per split view and not environment-propagated, so `.frame(...).splitViewAutosaveName(...)` does not compile; two split views must take two names.
- Autosave saves at drag end only (a window resize does not write), so the saved array can sum to a different total than a later window; the solver reconciles it.
- Nested split views are not tested; the divider overlay of an inner view overlaps its own panes only.
- No demo section and no human-check group were added.
- `docs/rules/` and `CLAUDE.md` are untouched (orchestrator): the rule to add is "a split view's sizes are written only by its divider handler; `SplitLayout` is non-Hashable".
