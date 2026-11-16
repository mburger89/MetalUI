# Split views - decisions

Rulings for `HSplitView` / `VSplitView` (MetalFlow's palette | canvas | inspector layout). Prefix `HS-`. Branch `feat/mf-split`. Code: `Sources/MetalUI/SplitView.swift`; tests:
`Tests/MetalUITestingTests/SplitViewTests.swift` (portable, plain imports). **Next unused: `HS-L`.** Divergence 206 (the orchestrator moves the label if another branch took it).

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

## HS-I - `splitViewDivider(_:thickness:)`: the divider's line and gutter, environment-propagated

**Ruling.** MetalUI-only (SwiftUI has no spelling; precedent `windowTitleBarMetrics`, `AS-R`). `splitViewDivider(_ visibility: Visibility = .automatic, thickness: CGFloat? = nil)` is an `EnvironmentScope` write of an internal `SplitDividerStyle` (`hidden`, `thickness`), read by `SplitEngine.requestLayout` each frame, so it applies to the split view it modifies and to split views inside it (nearest writer wins) and a change relayouts it with no rebuild of the panes: the scope is transparent to identity, the style is a value in the `SplitLayout`/`SplitDivider` the engine rebuilds, so pane `@State` and ids are kept. `.hidden` draws no line (the line `Color` is `.clear`); `.automatic` and `.visible` draw today's `.separator`. `thickness` (default 1, negative clamps to 0) is the divider's layout thickness and so the panes' spacing; the hit area is `max(thickness, 6)` centred on the divider, overlaying the panes, so a gutter of 0 keeps a 6-point hit area straddling the boundary. Pointer and drag are unchanged; the divider has no accessibility node. Defaults are byte-identical (`theDefaultSplitViewDividerIsTheOneItAlwaysWas`). **Carried:** as the window root the scope breaks the drag (the `EV-B` root restriction): write it inside the root's first container.
**Pins.** `theDefaultSplitViewDividerIsTheOneItAlwaysWas`, `aHiddenDividerDrawsNoLineButStillDrags`, `aThicknessOfSixSpacesThePanesBySixAndIsTheHitArea`, `aWideGutterIsItsOwnHitArea`, `aGutterOfZeroKeepsASixPointHitAreaOnTheBoundary`, `aVSplitViewTakesTheSameDividerStyle`, `changingTheGutterAtRunTimeRespacesAndKeepsPaneState`.

## HS-J - a split view answers the proposal it is offered, so a bare nested split view is flexible

**Ruling.** Probe `docs/probes/swiftui-nested-split-sizing.swift` (record 310): SwiftUI's `HSplitView`/`VSplitView` answer `sizeThatFits` with the proposal itself, whatever their panes (fixed, flexible or min/ideal/max frames give identical rows): zero is 0, a finite size is itself, **infinity is infinity**, nil is 0. `SplitLayout.sizeThatFits` now answers infinity for an infinite proposal on either axis (it answered the sum of the panes' ideals, so its maximum equalled its ideal and a split view that was a pane of another never stretched: 10 of 600 wide beside a plain pane). A nil proposal keeps the sum of the panes' ideals (SwiftUI answers 0; kept because a split view in a fit-content parent needs a size; divergence 206). No frame wrapper is needed around a nested split view; one still works.
**Pins.** `aBareNestedSplitViewStretchesLikeSwiftUIs` (literals from the probe: 300 / 299 wide at x 301), `aBareNestedHSplitViewInAVSplitViewStretches` (was already green: the cross axis never hit the bug), and the other tests of `NestedSplitViewTests`.
**Mutation.** Restoring the sum-of-ideals answer for an infinite proposal reddens `aBareNestedSplitViewStretchesLikeSwiftUIs` alone.

## HS-K - a divider is an accessibility element: `AXSplitter`, value = the pane before it, settable, no actions

**Ruling.** Probe `docs/probes/swiftui-split-divider-ax.swift` (record 324, macOS 27.2.1): SwiftUI's dividers are `NSSplitViewSplitter`s, `NSAccessibilityElement`s interleaved with the panes in the split's `accessibilityChildren`: role `AXSplitter` ("splitter"), `AXOrientation` 1 (vertical) for an `HSplitView`'s line and 2 for a `VSplitView`'s, `AXValue` a number in points equal to the size of the pane BEFORE the divider (not its position, not a fraction), `AXMinValue` 0, `AXMaxValue` the two neighbours' sum (the panes' own limits are not in it), `AXValue` settable: a write moves the divider as a drag does (the pair keeps its total; below the pane's minimum clamps to it; above the total is ignored, not clamped). **No actions**: `accessibilityPerformIncrement`/`Decrement` are inherited and raise "unrecognized selector". No label, identifier or help; `.accessibilityIdentifier` on the split or a pane does not reach it.

MetalUI matches: each `SplitDivider` records an element (the proposal-path accessibility wrapper over its hit area) with `AXNode.roleHint = .splitter` (the existing optional role-hint enum gains a case, 1 byte: `AXNode` and `Handlers` keep their pinned sizes) and one internal `SplitterAccessibility` action registered on the divider, which the tree builder asks for the value, the pair's total, the orientation and whether the pair can move (`SplitSolver.movableRange` is not a point), and `Window` sends `.set(value)` through `AccessibilityRequest.setValue` (new; `AccessibilityActions.setValue`, `AccessibilityRole.splitter`, `AccessibilityOrientation`, `AccessibilityNode.numericRange`/`orientation`). A set is `SplitSolver.dragged(snapshot, by: value - current)` written as `SplitModel.sizes`, and the autosave entry once, only if the sizes changed (a drag writes at its end; a set has no end). Increment and decrement are NOT advertised, as the probe. A divider whose neighbours cannot move (fixed, or limits that leave no room) or in a disabled subtree is disabled and advertises nothing (SwiftUI's element reads enabled `false` always, so this is the same signal made meaningful). AppKit: `AXSplitter`, `AXOrientation`, numeric `AXValue`, `AXMinValue`, `AXMaxValue`, `setAccessibilityValue(_:)`; AccessKit 0.23: `SPLITTER` (it has the role), `orientation`, `numeric_value`, `min/max_numeric_value`, `SET_VALUE` with numeric action data (a string value names no action), no `INCREMENT`/`DECREMENT`.

**Identifiers (class M).** SwiftUI has no way to name a divider (probe arm I). `splitViewDividerIdentifier(_ prefix:)` on `HSplitView`/`VSplitView` (MetalUI-only; family `split-view-divider-accessibility`) gives divider *i* the identifier `prefix.i` (`AXIdentifier`, AccessKit `author_id`); none by default, so a plain split matches SwiftUI's nil. A split's own `.accessibilityIdentifier` is not inherited by the dividers.

**Differences kept, in divergence 206's row, no new label.** The element's frame is the 6-point hit area, not the 1-point line; the dividers are published after the panes, not interleaved with them (the tree order is the registration order: panes, then dividers); an immovable divider is disabled (see above); a hidden divider (`splitViewDivider(.hidden)`) is still an element. VoiceOver's own keyboard resize is not measurable by an agent (human check HS1).

**Pins.** `SplitDividerAccessibilityTests`, `SplitDividerAppKitAccessibilityTests`, `AccessKitSplitterTests` (SDL package). Mutations are listed in record 324.

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
| M11 | `SplitDivider`: the line drawn although hidden | `aHiddenDividerDrawsNoLineButStillDrags` and four more |
| M12 | `SplitDivider`: hit area `thickness`, not `max(thickness, 6)` | `aGutterOfZeroKeepsASixPointHitAreaOnTheBoundary` and the three older hit-area tests |
| M13 | `requestLayout`: layout thickness 1 whatever the style | `aThicknessOfSixSpacesThePanesBySixAndIsTheHitArea`, `aWideGutterIsItsOwnHitArea`, `aGutterOfZeroKeepsASixPointHitAreaOnTheBoundary`, `aVSplitViewTakesTheSameDividerStyle`, `changingTheGutterAtRunTimeRespacesAndKeepsPaneState` |
| M10 | `requestLayout`: do not read the store | `autosaveRoundTripsThroughTheInjectedStore` |
| M11 | `dragChanged`: write sizes for a zero translation | **none, an equivalent mutant** (the written sizes equal the placed ones; a click only freezes them) |
| M11b | `dragEnded`: `moved = true` | `aClickOnTheDividerChangesNothing` (after the test gained a click following a drag) |
| M12 | `SplitLayout.horizontal` always `true` | `aVSplitViewIsTheSameOnTheVerticalAxis` |
| M13 | `solve`: skip the bounded pass | `withNoUnboundedPaneTheBoundedOnesShareTheSurplus` |

The mutated spelling was applied to the declaration named; the 1 MB-stack and AppKit-only checks were not touched (no demo section, no AppKit file).

## Carried

- A probe of `HSplitView` against real SwiftUI/`NSSplitView` (resize distribution, divider thickness and colour, minimum overflow) and a human look; either settles divergence 206 and could make the family class A.
- No pane collapse or hide, no double-click-to-reset, no keyboard resize, no keyboard increment/decrement of a divider (the probe: none in SwiftUI), no hover highlight on the divider.
- Autosave is per split view and not environment-propagated, so `.frame(...).splitViewAutosaveName(...)` does not compile; two split views must take two names.
- Autosave saves at drag end only (a window resize does not write), so the saved array can sum to a different total than a later window; the solver reconciles it.
- Nested split views are tested to depth 5 (`HS-J`); the divider overlay of an inner view overlaps its own panes only.
- No demo section and no human-check group were added.
- `docs/rules/` and `CLAUDE.md` are untouched (orchestrator): the rule to add is "a split view's sizes are written only by its divider handler; `SplitLayout` is non-Hashable".
