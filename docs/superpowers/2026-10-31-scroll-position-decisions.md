# Scroll extras and `@Bindable` - decisions

Rulings for round-3 item R3-4: pinned section views, `scrollPosition(id:anchor:)` with `scrollTargetLayout()`, an animated `scrollTo`, `@Bindable`, two-axis scrolling. Prefix `SP-`.
Branch `feat/scroll-position` from master `28a819e9` (record 177). **Next unused: `SP-M`.**
Probe: `docs/probes/swiftui-scroll-position.swift` (arms V, W, H, O pin sections; P, X, A could not be measured headless; B is `@Bindable`). Carried from: `LZ-N` (`pinnedViews:`/`Section` not built), `MD-H` item 6
(`@Bindable`), `CN-M`, `DD-AB` items 5-6, `CX-I` item 2 (two-axis, `scrollPosition`, animated `scrollTo`).

## SP-A - `scrollPosition(id:anchor:)` binds the topmost scroll target

**Ruling.** `ScrollView` and `ProposalScrollView` gain `scrollPosition(id: Binding<ID?>, anchor: UnitPoint? = nil)`.
*Reading:* the binding holds the first scroll target whose extent reaches the viewport's leading edge (a partly visible target leads: offset 310 over 20-point rows reads the row at 300); with an `anchor`, the target
holding that point of the viewport (`.bottom`/trailing: the last target that starts before the far edge). Where the offset is outside what the targets cover (a lazy container's unrealised range) nothing is read, until
a frame covers it (`SP-C`). *Writing:* a binding value the scroller did not put there scrolls to that target, its leading edge (`anchor`'s point, default `.topLeading`) at the viewport's, resolved as a `scrollTo` is
(`DD-G`, `LZ-O`: an unrealised lazy unit lands in at most two frames), including under `withAnimation` (`SP-F`). An initial non-nil value scrolls on the first frames; a value no target matches does nothing.
**Evidence.** Unmeasured: SwiftUI's `scrollPosition` did not report headless (probe P0-P4: the binding stayed nil through a scrolled clip view, the body never re-ran; X: a write scrolled nothing). The rule is
SwiftUI's documentation (the identity of the view at the scroll position) and is marked unproven; **no divergence is claimed** for which id a partly visible target reports or what `anchor` selects.
**Pins.** `aWheelWritesTheTopmostVisibleTargetAndSettlingFramesWriteNothing`, `aBottomAnchorReportsTheTargetAtTheTrailingEdge`, `writingTheBindingScrollsToTheTarget`,
`writingTheBindingWithABottomAnchorAlignsTheTargetsBottomEdge`, `anInitialValueScrollsOnTheFirstFrames`, `aHorizontalScrollerReportsAlongItsAxis`. **Cost if wrong.** An app reading the id of a half-scrolled row
gets the row SwiftUI might call the next one; the fix is the one comparison in `ScrollPositionRegistry.target`.

## SP-B - scroll targets are `ForEach` elements under `scrollTargetLayout()`

**Ruling.** `scrollTargetLayout(isEnabled: Bool = true)` on any `ElementGroup` wraps it in `ScrollTargetLayout`, layout- and identity-transparent (no cursor index, no node, no id: the `EnvironmentScope` shape without an
environment value, so `EnvironmentValues` and the retained environment epoch are untouched). Inside a scroller that carries `scrollPosition`, every `ForEach` element built under it - eager (`ForEach.prepaintGroup`)
or lazy (a `LazyVStack`/`LazyHStack` unit, legacy or proposal) - reports its extent along the scroller's axis from **prepaint** (`Frame.noteScrollTarget`), in content coordinates. A static child, a `List` row and a
lazy-grid cell are not targets (divergence 916). A nested `ForEach` element is a target too; the outermost one that reaches the edge wins (ties: the longer extent first). Without the wrapper, or without a
position binding above, nothing is noted: a tree with no `scrollPosition` pays one flag read per `ForEach`.
**Pins.** `withoutScrollTargetLayoutNothingIsATargetAndTheBindingStaysNil`, `anEagerStacksForEachElementsAreTargetsToo`, `equatableRowsAreScrollTargetsAndTheReplayAgrees` (the legacy `ForEach` path, also under
`METALUI_VERIFY_RETAINED=1`). **Cost if wrong.** A tree that marks only some `ForEach`es as targets gets all of them under the wrapper.

## SP-C - the binding is written from input, never from a phase

**Ruling.** `Window.scroll(_:by:)` (the wheel) calls `ScrollPositionRegistry.didScroll` after it moves the offset: the binding is written there, from input, when the frame before it covers the new offset. When
it does not (a wheel past a lazy container's window) the entry is flagged and the **frame that realises the new window** reports it once after paint (`Frame.applyScrollResolutions` -> `finishFrame`), as it
reports the scroller a `scrollTo` moved (a scroll no wheel made). Layout, prepaint and paint never write it (pin `idleFramesNeverWriteThePositionBinding`: 20 idle ticks and a redraw write nothing). The registry
(`ScrollRequestQueue.positions`) is window-owned, holds each scroller's targets from its last prepaint and the value the binding last held as far as the scroller knows; an untouched entry is kept (a replayed
retained subtree does not prepaint) until the table passes 256 scrollers.
*An external write* is a binding value that differs from that: the scroller's layout injects its `scrollTo` into the **current** frame (`Frame.injectScrollRequest`), not the window's queue, so a frame abandoned for
a redo (`RK-D`) injects it again and nothing is lost to `restore`. The registry learns the value at the end of the frame that read it.
**Pins.** `idleFramesNeverWriteThePositionBinding`, `aWheelPastTheRealizedWindowIsReportedAfterTheFrameThatRealizesIt`, the pins of `SP-A`. **Cost if wrong.** A write after paint dirties the window once for one more frame; a
hot scroll writes the binding once per change of the topmost target, not per wheel event.

## SP-D - `@Bindable` is a thin wrapper, with no new observation

**Ruling.** `Bindable<Value: AnyObject & Observable>` is a `@MainActor @dynamicMemberLookup @propertyWrapper` whose `projectedValue` is itself and whose `subscript(dynamicMember: ReferenceWritableKeyPath)` returns
`Binding(get:set:)` over the property. A getter read registers with the open `withObservationTracking` (the frame build, `ContentMemo`'s tracked content); a setter write fires the same `onChange` any write to an
`@Observable` fires, and it is not animated (`AN-Z`: only a `State` source applies its transaction). `Bindable(model)` also works as a local, and over an `@Environment(Model.self)` object. This retires `MD-H`
item 6's "not built". **Probe.** B1, B2 (`Bindable(m).name` is `Binding<String>`, writes through). **Pins.** `aBindableProjectsBindingsThatReadAndWriteThroughTheObject`,
`aBindableBindingWrittenFromInputRedrawsTheObservingFrame`. **Cost if wrong.** None known; it holds one reference.

## SP-E - Carried: `List` rows, grid cells, `ScrollPosition`, `scrollTargetBehavior`

**Ruling.** Not built, each a second design: a `List` row as a target (its windowing is `List`'s own, `VL-`; a `List` `scrollTo` exists and a position binding over its rows is the same shape as the lazy stack's
through `rowID`), a lazy-grid cell (rows are lines; a target is a line's first cell), SwiftUI's `ScrollPosition` struct (`scrollPosition(_:)` with `scrollTo(edge:)`, `scrollTo(y:)`), `scrollTargetBehavior`,
`ScrollView`'s `onScrollGeometryChange`. A `List` or grid under `scrollPosition(id:)` writes nothing. **Cost if wrong.** An app binding a `List`'s top row keeps its own `onAppear` bookkeeping.

## SP-F - `scrollTo` under `withAnimation` glides on the frame clock

**Ruling.** `ScrollViewProxy.scrollTo` records the transaction in force (`Animation.pendingTransaction`) in its request; the resolution (`Frame.applyScrollResolutions`) stores `ScrollState.glide` (from, to, the resolving
frame's timestamp, the `Animation`) beside the unchanged target and the display link is kept awake (`noteActiveAnimation`, never `requestAnotherFrame`, `identity-state.md`). Every phase reads the one value
`ScrollChrome.currentOffset(state, now: frame.timestamp)` - layout's `ScrollContext.offset` (so a lazy container windows against it), prepaint's clamp (which stores it, compared, `RW-H`) and paint - so the three
agree on one frame and the glide lands exactly on the target. A refinement carried by a lazy container (`VL-P`) keeps the animation (`Frame.scrollRequestAnimation`). A wheel event ends the glide where it stands
(`Window.scroll` clears it). Outside `withAnimation` the call jumps as before. `scrollPosition` writes glide the same way and report the target at its start.
**Evidence.** Unmeasured (probe A0/A1: `scrollTo` is a broken instrument headless); SwiftUI documents `withAnimation { proxy.scrollTo }` as animated. **Pins.** `scrollToUnderWithAnimationGlidesAndTheControlJumps`
(quarter, half, three quarters, landing; the display link stays awake mid-glide; the control jumps), `aWheelEndsAnAnimatedScrollWhereItStands`. **Cost if wrong.** A glide interrupted by a `scrollTo` made without
animation snaps to its target (the later resolution clears the glide).

## SP-G - `pinnedViews:` pins the current section's header and footer; the header is not pushed off

**Ruling.** `LazyVStack`/`LazyHStack` gain `pinnedViews: PinnedScrollableViews = []` (`.sectionHeaders`, `.sectionFooters`). In a windowed stack the **header** of the section holding the viewport's leading edge is
placed at `max(natural, viewport leading edge)` and the **footer** of the section holding the trailing edge at `min(natural, viewport trailing edge - extent)`, by the container's own placement: a pinned view is a
real node at its pinned place, so its hitbox, accessibility frame and the scroller's anchor correction follow without a paint-time translation. The pinned views are prepainted and painted **last**, above the rows they
cover (pin `aPinnedHeaderIsAboveTheRowsUnderIt`). A header is **not pushed by its section's end**: probe O reads header 0 at 0 until the last point of its section while header 1 slides to it, and at the section
boundary it is gone - the next header overlaps it (so the first spec wording "push off as the next header arrives" is refuted by the measurement; SwiftUI is the authority).
**Evidence.** Probe V1/V0 (header 0 at 0 at offsets 100 and 230 against -100 and -230), H1/H0 (the horizontal axis), O (no push-off), W1. **Unproven**, as in the probe's reading 4: the markers of pinned views of later
sections read stale and the footers of later sections read off screen, so footer pinning is the header's rule mirrored, and a later section's header pin rests on the same rule as section 0's. No divergence is claimed
for them. **Pins.** `aPinnedHeaderStaysAtTheTopWhileItsSectionIsCurrent`, `aPinnedFooterStaysAtTheBottomWhileItsSectionIsCurrent`, `aLazyHStackPinsAlongItsAxis`.

## SP-H - `Section` is transparent; a `ForEach` of sections is read as units

**Ruling.** `Section<Header, Content, Footer>` is a `ProposalElementGroup` over three `ProposalElementGroup`s taking their cursor indices in order (a `Pair` of three): no node, no identity of its own. Inits:
`Section(content:header:footer:)` written `Section { } header: { } footer: { }`, and the header-only, footer-only and content-only forms; the deprecated value forms (`Section(header: Text("x")) { }`) are not offered (a legacy `Text` is not proposal content). In a lazy stack a `Section` flattens into its parts' unit
sources tagged with their role (`LazyRoleSource`); a **`ForEach` whose elements are sections** (the common spelling) is read by `LazySectionForEachSource`: the content closure runs once per element each frame to count
the units (O(sections), never O(rows)), a unit is identified by `LazySectionedUnitID` (section id, part, the part's own id - row ids repeat across sections), realised under the element's named scope with the part's
cursor, and `scrollTo` knows a header by its section's id and a row by its own id. Not for `List`; no title-string inits (`Section("Title") { }`): not built.
**Pins.** `aSectionInAnOrdinaryStackIsItsPartsInSequence`, the stack pins of `SP-G`/`SP-I`. **Cost if wrong.** 100 000 sections cost 100 000 closure calls per frame; group rows into fewer sections or use a `List`.

## SP-I - the stack stays windowed: pinned views outside the window are extra units

**Ruling.** The header (or footer) to pin is found from the viewport's edges through the extent index (`index.index(containing:)`), its units realised if the window does not hold them and appended after the window's
nodes (`LazyStackLayout.sequenceCount` separates the in-sequence nodes from the extras, which take no room in `sizeThatFits`). A pinned stack realises the window plus at most the header and footer units: pin
`aPinnedStackRealizesOnlyTheWindowAndThePinnedViews` (the control's window + exactly 2, three sections of 100 rows). `LazyStackLayout` stays unhashable (`LZ-F`).

## SP-J - pins need a windowed stack; grids are carried

**Ruling.** Pinning happens only when the stack is bounded (`LazyPlanMode.bounded`): a stack made eager by an `if`/`switch`/`for` member (`LZ-B`, divergence 636) or outside a scroller along its axis lays its
sections out in sequence and pins nothing (divergence 915). `LazyVGrid`/`LazyHGrid` have no `pinnedViews:` and no `Section` flattening (a `Section` in a grid is one eager cell group): carried with `SP-E`.

## SP-K - Carried: two-axis scrolling, `ScrollView([.horizontal, .vertical])`

**Ruling.** Not built. `ScrollAxis` is a public closed `enum` (`.vertical`, `.horizontal`); `[.horizontal, .vertical]` needs an `OptionSet` (a source break for every `switch`), a two-component `ScrollState`, a
kernel viewport that answers both axes unspecified (`requestNativeScrollViewport(child:axis:)` takes one), two scroll regions and a two-axis wheel, and `ScrollContext`/`ScrollerFrame`/lazy planning (all one-axis by
`MP-M`) a second dimension. That is not cheap, and the one-axis nesting `ScrollView(.horizontal) { ScrollView { } }` is not the same. **Cost if wrong.** A canvas/grid app nests two scrollers.

## SP-L - Divergences 915 and 916

**Ruling.** 915: pinned views need a windowed lazy stack (`SP-J`). 916: scroll targets are `ForEach` elements only (`SP-B`). Labels 917-924 stay unused; `docs/divergences.md` and `record/04` carry the rows.
