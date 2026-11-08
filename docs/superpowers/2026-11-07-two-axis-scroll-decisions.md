# Two-axis scrolling and per-axis wheel routing - decisions (prefix `XS-`)

Alloy gap G5. Branch `feat/scroll-axis-routing` from master `c6779ba4` (then merged with `dc20b918`); record 236. Probe `docs/probes/swiftui-two-axis-scroll.swift` (PR 0, recorded 2026-11-07). **PR 1 (this branch) builds `XS-E`..`XS-G` on ONE-axis scrollers; `XS-A`..`XS-D` and `XS-H`..`XS-N` are the plan for PR 2/3 and are not built.** `SP-K` (two-axis scrolling "not built") is superseded by this document. Class `A` (SwiftUI-aligned); no divergence added by PR 1. Next unused id: `XS-P`.

## XS-A: API, no source break (planned, PR 2)

`public init(_ axes: Axis.Set, elementID:content:)` on `ScrollView` and `ProposalScrollView`, `@_disfavoredOverload`; `public var axes: Axis.Set` (SwiftUI's), `axis: ScrollAxis` stays as a computed view of it. `ScrollAxis` stays a closed enum. `axes == [.horizontal]` or `[.vertical]` takes today's one-axis path byte for byte. Stop condition: `@_disfavoredOverload` leaving `ScrollView(.horizontal)` ambiguous.

## XS-B: kernel (planned, PR 2)

A both-axes case of the private native scroll viewport: content proposed `nil x nil`, the viewport answers the proposal on both axes. **The centring of small content is NOT ruled**: this probe read (0, 0) in an AppKit-backed scroller (L1b) against SCG2's (25, 35) in the layout probe; PR 2 re-measures before it rules.

## XS-C, XS-D: state and chrome per axis (planned, PR 2)

`ScrollState` keeps the vertical axis as the primary and gains a cross slot; one chrome core over `inout` slot fields, never copied; an indicator per axis with the shared corner shortened. `ScrollChrome.wheelOffset` is not used on the window path (the write is deliberately unbounded, the prepaint write-back is the clamp).

## XS-E: the hitbox carries what the wheel chain needs (built)

`Hitbox.scrollAxes: Axis.Set` (declared), `scrollTakes: Axis.Set` (the declared axes whose content exceeds the viewport) and `scrollRoom: ScrollRoom` (four bits: the offset can fall or grow, per axis), set in prepaint from the RESOLVED offset (`PrepaintPass.registerScrollRegion(_:id:axis:chrome:offset:contentSize:)`, internal). On the hitbox, not on `Handlers` (its size pins). All three are in `Hitbox.fingerprint`. The public `registerScrollRegion(_:id:axis:)` declares takes and both directions open: **a custom scroller registered through it now passes the other axis on** (a behaviour change, `docs/migration.md`). The room is last frame's: events between two frames bank into the unbounded stored offset until the prepaint clamp, as before.

## XS-F: the per-axis chain (built; amended by the probe)

The plan was "split the components between scrollers, handlers see the remainder". **The probe refuted the split** (N3: a diagonal goes WHOLE to the dominant axis, here the outer's y, the inner's x is dropped), so: `dispatchScrollChain` computes ONE axis for the event (`XS-G`) and walks the cover's chain as before. At each id the wheel handlers run first and see the RAW event; the multi-line editor (`TI-H`) takes the vertical axis only and lets a horizontal wheel go on (it still claims at its own ends: its edge chaining is not built); then the id's scroller takes the wheel when it declares the axis, `scrollTakes` contains it and `scrollRoom` allows the wheel's direction. Otherwise the wheel goes on to the ancestors (N1, N6, N6b, N7, **N8: a one-axis scroller at its end passes the wheel up**, mid-gesture too: N8b gave the outer the rest). If nothing takes it, the innermost scroller on the axis that had no room still takes it (stamp, banked offset and the prepaint clamp as before; also keeps the indicator on a lone scroller at its end); after the chain the wheel is claimed when the cover is opaque (`DD-Y`). An all-zero event (a terminal phase) keeps its answer: the innermost scroller's stamp. `didScroll` (`SP-C`) reports the offset as before. **Carried to PR 2:** a TWO-axis scroller does NOT chain at its edge in SwiftUI (N9c..N9f: outer stays 0 at the inner's end, even 30 short of it); PR 2 must make a two-axis `scrollRoom` swallow.

## XS-G: the lock (built; amended by the probe)

`ScrollLatch.lock: Axis?`: the dominant component (`|dy| >= |dx|` vertical, a tie vertical) of the first event of the scroll that carried a delta, kept through the momentum stage (A4, A4c, A5). **A phaseless event is decided by itself** (A3, A3c), not "never locked" as planned. **The lock applies to one-axis scrollers** (A8, A8b, A8c: a vertical-only scroller under an x-dominant gesture does not move; it reads the dominant component, not its own). `.onScrollWheel` handlers keep the raw event (R6). A plain SDL wheel is phaseless and so decided per event; SDL precise streams get synthesized phases and lock (checked in PR 3, Z9). Momentum is unmeasured (the synthetic momentum events moved nothing in the probe, M0): the lock through momentum follows the latch, not a reading.

## XS-H..XS-M: context, scrollTo, anchor, scroll position, retained, accessibility (planned, PR 3)

As the plan, plus the probe's facts: T (anchor x/y per axis, `.top` centres x, nil is least distance per axis, T5), **T7: `scrollTo` a target inside a nested inner scroller moves ONLY the inner (the outer stays) in SwiftUI**, S5 (the `defaultScrollAnchor` pin is released PER AXIS), P1 (`scrollPosition(id:)` on row ids tracks y and ignores a dx-only wheel), R1 (right-to-left opens at the right edge, sign mirrored). A9 is unreadable here (legacy scrollers).

## XS-N: Markdown defaults (recommendation, belongs to `BM-`)

Keep `codeWraps = true` (a streaming long line keeps its tail visible); flip `tableScrolls` to true in a `BM-` follow-up. PR 1 moves the BM2 pin only: the vertical wheel now passes a horizontal fence on, in both arms.

## XS-O: the instrument

Events go through `NSWindow.sendEvent` from `CGEvent` scroll events, the window at the screen origin (`NSEvent(cgEvent:)` has no window and a screen-based location); D0 shows `sendEvent` and `hitTest` delivery agree. Momentum events cannot be delivered this way (M0), and the thumbs are always visible on a legacy-scroller machine (A9).
