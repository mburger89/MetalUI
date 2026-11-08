# Two-axis scrolling and per-axis wheel routing - decisions (prefix `XS-`)

Alloy gap G5. Branch `feat/scroll-axis-routing` (PR 1, record 236) from master `c6779ba4` (then merged with `dc20b918`); branch `feat/two-axis-scroll` (PRs 2 and 3, record 237). Probe `docs/probes/swiftui-two-axis-scroll.swift` (PR 0, recorded 2026-11-07; arms `L1e`-`L1g` added in PR 2). **PR 1 built `XS-E`..`XS-G` on ONE-axis scrollers; PRs 2 and 3 (record 237) build `XS-A`..`XS-D` and `XS-H`..`XS-M` and add `XS-P`..`XS-U`.** `SP-K` (two-axis scrolling "not built") is superseded by this document. Class `A` (SwiftUI-aligned); **no divergence added** (the two rulings that go beyond a reading, `XS-R` and `XS-S`, are stated assumptions with human checks). Next unused id: `XS-V`.

## XS-A: API, no source break (built, PR 2)

`public init(_ axes: Axis.Set, elementID:content:)` on `ScrollView` and `ProposalScrollView`, `@_disfavoredOverload`; a stored `public var axes: Axis.Set` (SwiftUI's) replaces the stored `axis`, which is now a computed get/set over it: `.horizontal` for exactly `[.horizontal]`, `.vertical` for everything else (a two-axis scroller's PRIMARY axis is vertical, `XS-C`). `ScrollAxis` stays a closed enum. `ScrollView(.horizontal)` still resolves to `ScrollAxis` (stop condition 3 not triggered: guard `everySpellingOfTheScrollAxesCompilesFromAPlainImport`, mutation: `@_disfavoredOverload` removed), an array literal, a set value and `[]` to `Axis.Set`. `axes == [.horizontal]` or `[.vertical]` takes today's one-axis path byte for byte (`aOneAxisSetIsTheScrollerTheScrollAxisSpellingIs`: rects, hitbox fields, `NativeLayoutWork`). A stored property on a public type: `swift package clean` (`docs/migration.md`).

## XS-B: kernel (built, PR 2)

`LayoutTree.NativeNode.scrollViewport(axis:)` now holds a private `ScrollViewportAxes` (`horizontal`, `vertical`, `both`, `neither`); `newNativeScrollViewport(child:axis:)` maps to the first two (the memo signature tags 0 and 1 are the ones it always mixed) and the new `package` `newNativeScrollViewport(child:horizontal:vertical:)` reaches `both` (tag 2, content proposed `nil x nil`, the viewport answers its proposal on both axes and the content's answer where there is none) and `neither` (tag 3, `ScrollView([])`: the content is proposed the parent's proposal, placed at the viewport's size, probe `L3`). `LayoutPass.requestNativeScrollViewport(child:axis:)` is untouched. **Small content sits at (0, 0), not centred: `XS-P`.**

## XS-C, XS-D: state and chrome per axis (built, PR 2)

`ScrollState` keeps `offset`, `viewportExtent`, `glide` and `anchor` as the primary slot (vertical for a two-axis scroller) and gains an internal `cross: ScrollAxisSlot` (the same four, horizontal); `lastScrollTime` stays shared. `ScrollChrome` gains `crossAxis`/`crossMirrored`, `crossChrome` (the horizontal axis as a one-axis chrome) and **one core**, `resolveSlot(offset:glide:anchor:viewportExtent:content:viewport:now:)` over the fields of a slot, called for the primary and, through `crossChrome`, for the cross slot: the glide step, the default anchor, the clamp and the write-back are one body (`resolvedOffsets`; `resolvedOffset` is its `.primary`). `translation(offset:cross:)` is the primary's plus `crossChrome`'s. The indicator is the numeric `paintIndicator` once per axis (`trackInset:` defaults to 0, so `CodeView` and every one-axis scroller are byte-identical); **where both thumbs show, each track stops `ScrollChrome.cornerInset` = 8 points short of the shared corner and the thumb and its travel are computed on the shortened track (`XS-T`)**. `ScrollChrome.wheelOffset` is not used on the window path (`XS-U`).

## XS-E: the hitbox carries what the wheel chain needs (built)

`Hitbox.scrollAxes: Axis.Set` (declared), `scrollTakes: Axis.Set` (the declared axes whose content exceeds the viewport) and `scrollRoom: ScrollRoom` (four bits: the offset can fall or grow, per axis), set in prepaint from the RESOLVED offset (`PrepaintPass.registerScrollRegion(_:id:axis:chrome:offset:contentSize:)`, internal). On the hitbox, not on `Handlers` (its size pins). All three are in `Hitbox.fingerprint`. The public `registerScrollRegion(_:id:axis:)` declares takes and both directions open: **a custom scroller registered through it now passes the other axis on** (a behaviour change, `docs/migration.md`). The room is last frame's: events between two frames bank into the unbounded stored offset until the prepaint clamp, as before.

## XS-F: the per-axis chain (built; amended by the probe)

The plan was "split the components between scrollers, handlers see the remainder". **The probe refuted the split** (N3: a diagonal goes WHOLE to the dominant axis, here the outer's y, the inner's x is dropped), so: `dispatchScrollChain` computes ONE axis for the event (`XS-G`) and walks the cover's chain as before. At each id the wheel handlers run first and see the RAW event; the multi-line editor (`TI-H`) takes the vertical axis only and lets a horizontal wheel go on (it still claims at its own ends: its edge chaining is not built); then the id's scroller takes the wheel when it declares the axis, `scrollTakes` contains it and `scrollRoom` allows the wheel's direction. Otherwise the wheel goes on to the ancestors (N1, N6, N6b, N7, **N8: a one-axis scroller at its end passes the wheel up**, mid-gesture too: N8b gave the outer the rest). If nothing takes it, the innermost scroller on the axis that had no room still takes it (stamp, banked offset and the prepaint clamp as before; also keeps the indicator on a lone scroller at its end); after the chain the wheel is claimed when the cover is opaque (`DD-Y`). An all-zero event (a terminal phase) keeps its answer: the innermost scroller's stamp. `didScroll` (`SP-C`) reports the offset as before. **Carried to PR 2:** a TWO-axis scroller does NOT chain at its edge in SwiftUI (N9c..N9f: outer stays 0 at the inner's end, even 30 short of it); PR 2 must make a two-axis `scrollRoom` swallow.

## XS-G: the lock (built; amended by the probe)

`ScrollLatch.lock: Axis?`: the dominant component (`|dy| >= |dx|` vertical, a tie vertical) of the first event of the scroll that carried a delta, kept through the momentum stage (A4, A4c, A5). **A phaseless event is decided by itself** (A3, A3c), not "never locked" as planned. **The lock applies to one-axis scrollers** (A8, A8b, A8c: a vertical-only scroller under an x-dominant gesture does not move; it reads the dominant component, not its own). `.onScrollWheel` handlers keep the raw event (R6). A plain SDL wheel is phaseless and so decided per event; SDL precise streams get synthesized phases and lock (checked in PR 3, Z9). Momentum is unmeasured (the synthetic momentum events moved nothing in the probe, M0): the lock through momentum follows the latch, not a reading.

## XS-H..XS-M: context, scrollTo, anchor, scroll position, retained, accessibility (built, PR 3)

**XS-H.** `ScrollContext` gains an internal `cross: ScrollAxisContext?` and `along(_:)`, `ScrollerFrame` an internal `cross: Cross?`, `isCross` and `along(_:)`: along a scroller's own axis they are `self`, along `.horizontal` a two-axis scroller answers the numbers of its cross slot as a horizontal frame, otherwise `nil`. `LazyLinePlanner.plan`/`prepaint`/`resolveScrollRequests` and the pinned views of `LazyVStack` read `along(their axis)`, so a `LazyVStack` windows on the vertical offset and a `LazyHStack` on the horizontal one inside the same scroller. `List` reads the primary (vertical) and needs no change. An anchor adjustment (`VL-G`) carries the slot (`noteScrollAnchorAdjustment(scroller:delta:cross:)`; **not pinned by a test**: a `LazyHStack` of variable columns in a two-axis scroller is not built as a fixture).

**XS-I.** `resolveScrollRequest` resolves the primary axis as before and, for a two-axis scroller, the horizontal one by the same `scrollOffset(bringing:into:anchor:)` over `scroller.along(.horizontal)`; `applyScrollResolutions` lands each slot with one `land` (a glide under `withAnimation`, else the offset). `.top` centres x (T3), no anchor is the least distance per axis (T4, T5). **A target inside a nested scroller moves the nearest one only (T7)**: `activeScrollerFrame` is already the nearest, so nothing changed; the "nearest per axis" of the plan is refuted.

**XS-J.** The cross slot has its own `ScrollAnchorMemory` and runs the same `anchoredOffset` through `crossChrome`; `layoutFollowsEnd(memory:raw:)` is per slot and published in `ScrollContext.cross`. The pin releases per axis (S5): a wheel on x leaves the y pin following (`defaultScrollAnchorWorksPerAxisInATwoAxisScroller`). `DSA-E` applies per slot.

**XS-K.** `scrollPosition(id:)` tracks the primary (vertical) axis because `ScrollerFrame.axis` is vertical; `Window.scroll` reports `didScroll` for the primary slot only, so a dx-only wheel leaves the binding alone (P1).

**XS-L.** `PrepaintExtras.scroller` gains indices 10 (the cross offset) and 11 (the cross content extent), always appended (0, 0 for a one-axis scroller); `zeroScrollOffsets()` sets aside indices 7 and 10 at the three sites that compared the vector. A diagonally scrolled settled card replays translated (`aDiagonallyScrolledTwoAxisScrollerReplaysItsCardsTranslated`). `Hitbox.fingerprint` already carried `scrollAxes`/`scrollTakes`/`scrollRoom` (PR 1).

**XS-M.** MetalUI exposes no scroll area or scroll action to accessibility, and two-axis adds none; the absence is carried.

## XS-N: Markdown defaults (recommendation, belongs to `BM-`)

Keep `codeWraps = true` (a streaming long line keeps its tail visible); flip `tableScrolls` to true in a `BM-` follow-up. PR 1 moves the BM2 pin only: the vertical wheel now passes a horizontal fence on, in both arms.

## XS-O: the instrument

Events go through `NSWindow.sendEvent` from `CGEvent` scroll events, the window at the screen origin (`NSEvent(cgEvent:)` has no window and a screen-based location); D0 shows `sendEvent` and `hitTest` delivery agree. Momentum events cannot be delivered this way (M0), and the thumbs are always visible on a legacy-scroller machine (A9).

## XS-P: small content in a two-axis viewport sits at the leading corner (built, PR 2; re-measured)

The probe's L1b read (0, 0) against `swiftui-stack-algorithms.swift` SCG2's (25, 35). PR 2 re-measured in the hosted-window harness of this probe, three framings: `L1e` (`.frame(100x100)` in a 300x300 window, coordinate space outside), `L1f` (a 100x100 window, coordinate space on the scroll view) and `L1g` (the document view's frame in WINDOW space, i.e. pixels): content in the scroll view (0, 0) in all three and the document view at the viewport's top-left corner (50x30); the single-axis controls in the same arms read (25, 0) vertical and (0, 35) horizontal (the viewport narrower than its `.frame`, centred by the frame: the existing SC2 pins). **Ruled: (0, 0), not centred.** SCG2's (25, 35) is a layout-harness reading of the same SwiftUI that paints at the corner here; the pixels are what a user sees. Kernel pin: `aTwoAxisViewportProposesNothingToItsContentAndAnswersTheProposalOnBothAxes`. No divergence (the pixels agree).

## XS-Q: `ScrollView([])` (built, PR 2)

Nothing scrolls: the viewport is the `neither` node (`XS-B`), the content is sized to the viewport (probe `L3`: a 500x500 child reads 300x300), the scroller registers no scroll region (so a wheel over it passes on, **a stated assumption**: the probe read that the wheel moves nothing, not whether SwiftUI's empty `NSScrollView` swallows it) and paints no thumb. `aViewportWithNoAxesSizesItsContentToTheViewport`.

## XS-R: the lock through momentum (assumption)

`ScrollLatch.lock` is kept through the momentum stage (XS-G): momentum events cannot be delivered in the probe (M0, A6, A6b, N10). Not measured; human check `XS8`.

## XS-S: the thumbs of a two-axis scroller (assumption)

One `lastScrollTime` stamp lights both thumbs. Whether SwiftUI flashes only the axis that moved (A9) is unreadable on a legacy-scroller machine (both always visible). Not measured; human check `XS7`.

## XS-T: indicator geometry (MetalUI's own choice)

The system draws SwiftUI's thumbs; MetalUI's is drawn. Where both axes scroll each track is shortened by 8 points at the shared corner (`ScrollChrome.cornerInset`), the thumb is `max(20, track * viewport/content)` and the travel `offset/scrollable * (track - thumb)` on that track; with one scrollable axis the track is the viewport and the formulas are the one-axis ones, byte for byte. `aTwoAxisScrollerPaintsOneThumbPerAxisWithTheCornerInset`.

## XS-U: the window path does not use `ScrollChrome.wheelOffset` (ruling)

`Window.scroll` writes `offset -= delta` with no bound on either slot and the prepaint write-back is the clamp (`resolveSlot` for both), as for one axis: `wheelOffset` needs a maximum the window does not have (pinned by `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack`, and for the cross slot `aTwoAxisScrollerMovesEachAxisAndClampsAndWritesBackBoth`).

## XS-F addendum (PR 2): the two-axis scroller swallows at its edge (built)

`PrepaintPass.registerScrollRegion(_:id:axis:chrome:offset:cross:contentSize:)` declares a two-axis region with `scrollAxes` both, `scrollTakes` the axes whose content exceeds the viewport and `scrollRoom` open BOTH ways on each taken axis, so it never passes a wheel up at its edge (probe `N9c`-`N9f`) but does when the content fits on the wheel's axis (capability). `aTwoAxisScrollerSwallowsTheWheelAtItsEdgeAndAFittingOneLetsItThrough`. `Window.dispatchScrollChain` takes the wheel when `region.scroll == axis || region.scrollAxes.contains(axis)`, and `scroll(_:by:along:)` writes the slot the wheel's axis names (the primary slot for the primary axis and for an all-zero event, `cross` otherwise).
