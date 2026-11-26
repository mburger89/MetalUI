# `defaultScrollAnchor` - decisions (prefix `DSA-`)

Rulings for Alloy gap G6 (a chat transcript, `ScrollView { LazyVStack { ForEach(blocks) { ... } } }` with thousands of variable-height blocks, appended while streaming, that starts at the bottom and stays pinned to it while the user is at the bottom). Branch `feat/default-scroll-anchor` from master `4d4c59db`; record 224. Class `A` with one divergence (226). **Next unused id: `DSA-K`.** Public API: `ScrollView`/`ProposalScrollView` `.defaultScrollAnchor(_:)` and `.defaultScrollAnchor(_:for:)`, `ScrollAnchorRole` (`.initialOffset`, `.sizeChanges`, `.alignment`). Probe: `docs/probes/swiftui-default-scroll-anchor.swift` (run twice; the only drift is the rubber-band residue of a wheel, 1-2 points).

## DSA-A: SwiftUI's spelling, per scroller, first call wins

Both overloads exist on macOS 15 and later. `nil` declares nothing (probe `O3`, `O4`); a role's own anchor beats the one for every role whatever the order (`O5`, `O6`); among two for the same role the INNER one (the first call, in a modifier chain) wins (`O1`, `O2`). SwiftUI applies the modifier through the environment, so on an ancestor too (`O7`); MetalUI stores it on the `ScrollView`/`ProposalScrollView` it is called on, like `scrollIndicators` and `scrollPosition(id:)` (divergence 226). The anchor is read along the scroll axis: `.bottom`/`.top`/`.center` by y on a vertical scroller, `.leading`/`.trailing` by x on a horizontal one, and the wrong-axis component takes the cross axis' value (`.leading` on a vertical scroller is the centre, `I4`; `.bottom` on a horizontal one, `H2`).

## DSA-B: the initial offset

At the first prepaint with a viewport and some content the offset is `y x (content - viewport)` (`I1` 1800 of 2000, `I3` 900, `I6` 450); an anchor that is not the trailing edge places the scroller once and never follows (`I3`: an append leaves 900). A lazy container's first extent is an estimate, so a non-trailing placement repeats until the extent is the same in two prepaints, at most 6 times; a trailing anchor needs only one because it is then followed (DSA-C). An explicit position wins: a `scrollTo`/`scrollPosition(id:)` from the first frame leaves the pin released and the target in place (`P1`, `P2`).

## DSA-C: the pin is decided in layout, in the frame the content grew

A scroller that follows its end publishes `ScrollContext.followsEnd` (internal) from `requestLayout` (last prepaint's memory and the stored offset, which a wheel may have moved since). A lazy container or `List` inside then windows around the END of its own extent (`windowOffset` is past every extent, clamped by the reader's own `min`), so the frame that appended the rows realises the new last rows, never the old window; the cold first frame realises the LAST 32 lines (`LazyLinePlanner.plan`, anchor at the first of them). Prepaint places the offset at the end of the content that was laid out, through the clamp write-back the offset always had (`ScrollChrome.resolvedOffset`, a compared write: a settled pinned scroller asks for no frame). No `@Observable` or `@State` is written from a phase; the one extra state is `ScrollState.anchor`, written only where `ScrollState` already is.

## DSA-D: what releases and what re-engages (probe `W0`-`W5`, `G`, `T`)

A stored offset more than 1 point short of last prepaint's end releases a pin (a wheel up, or a `scrollTo` elsewhere: an instrument that moves the clip view without a wheel, as the probe's `G2`, is not a user scroll to SwiftUI, and has no counterpart here). A wheel down, or a rubber-band overshoot, is at the end. Content that did not overflow the viewport last prepaint releases nothing. Roles: `.initialOffset` places and follows from the start until the first release, and never re-engages (`W3`); `.sizeChanges` has no initial offset, follows content growth whenever the scroller was at the end of overflowing content, and re-engages on every return to it (`W2`, `S3`: content shorter than the viewport is not "at the end"); `.alignment` only places content shorter than the viewport and, with a trailing anchor, follows once it grows (`S2`, `W4`: no follow from overflowing content). The plain overload is all three (`W1`).

## DSA-E: a pinned scroller takes no `VL-G` adjustment

The anchor-preservation adjustment (`noteScrollAnchorAdjustment`, applied after paint) moves the stored offset by what re-measured rows above the viewport changed. A scroller that followed its end this frame (`ScrollAnchorMemory.following`) skips it: prepaint puts the offset at the end of the new extent anyway, and the shifted stored offset would read as the user leaving. An unpinned scroller keeps `VL-G` untouched (the probe's `T1` scrolled-up arm: SwiftUI does not compensate for growth above either, the offset holds).

## DSA-F: alignment of short content

Content shorter than the viewport sits at `-(viewport - content) x fraction` (`S1`, `N1`: three 20-point rows in 200 sit at 140 with `.bottom`); `ScrollChrome.clampOffset` allows exactly that one negative offset when an alignment applies, in both prepaint and paint, so hit-testing, the lazy window and the clip agree. `.sizeChanges` alone does not align (`S3`).

## DSA-G: horizontal and RTL

Horizontal scrollers read x (`H1` `.trailing` starts at the end and follows, `H3` `.leading` is the start). The anchor is logical along the scroll axis: in a right-to-left layout `.trailing` is the logical end (the visually left one); SwiftUI's behaviour there is unmeasured (carried).

## DSA-H: work

The first (cold) frame realises 32 lines, the settled ones the viewport's (12 at the end: no line follows the last); an append at the end realises the same 12 (`lazyUnitsRealized`), and a settled pinned scroller is idle (`runUntilIdle`).

## DSA-I: nesting, `scrollTo`, `List`

`followsEnd` rides the scroller's own `ScrollContext`, so a nested scroller without an anchor is not pinned by its parent. `scrollTo(last, anchor: .bottom)` lands at the end and so pins; `scrollTo` elsewhere releases. A `List` inside windows against `windowOffset` too (uniform and variable), but its cold frame is not end-aware (carried: one frame of the old rows on a `List`'s first frame). `scrollPosition(id:)`'s binding is written from a wheel or a `scrollTo`, not from a pinned follow (carried).

## DSA-J: a scroller presents its offset on the device-pixel grid (record 426)

Class `A`, no divergence row. SwiftUI never presents a fractional scroll offset of its own making (probe `swiftui-scroll-offset-pixel-snap.swift`, record 425): `scrollPosition(y: 100.3)` gives 100, a bottom anchor over a 399.5 content reports 99.0, `contentOffset` equals the clip origin, and a clip origin AppKit was handed at a fraction (which SwiftUI did not place) is the only thing that draws blended. A MetalUI scroller moved by a wheel or trackpad delta that is not a whole device pixel painted at a fractional offset, and every record under it was refused (`fractionalTranslation`, `inexactTranslation`) and cost a redo.

- **The grid.** `ScrollChrome.snap(v, scale) = floor(v * scale + 0.5) / scale`: nearest device pixel, ties up (30.25 is 30.0 at 1x and 30.5 at 2x, as the probe's hairlines). A scale of 0 or less snaps nothing.
- **Where.** Once, at the commit: `ScrollChrome.resolveSlot` (prepaint's write-back, which already clamps) stores `presentedOffset(raw)` in `ScrollState.offset`. Everything that read the offset reads that number: paint (`resolvedOffset(pass: PaintPass)` re-applies the same function, which is idempotent, to what prepaint committed or to a glide's value), `ScrollerFrame.offset` and so hitboxes, the clip, `scrollTo` and the `scrollPosition(id:)` registry, and layout, which cannot see the content size and so reads `ScrollChrome.layoutOffset` (the raw stored position, snapped, unclamped) into `ScrollContext.offset`; lazy windows and `List` plan against it. A wheel's `didScroll` and a `scrollTo`'s reported offset are snapped with the same function.
- **Input accumulates raw.** `ScrollState.residue` (and the cross slot's) is what the grid did not take: `offset + residue` is the raw position. A wheel still writes `offset += delta`; the next prepaint adds the residue, clamps, snaps, commits `offset` and keeps the new remainder. Ten 0.3 pt deltas at 1x present 0 1 1 1 2 2 2 2 3 3 and end at 3. Anything a program chose (a `scrollTo` landing, a glide step, an anchor's placement, the clamp at an end) resets the residue to 0: input's leftovers do not leak into a position the program set. The compared write (`sameScrollState`) includes it, so a settled scroller still writes nothing.
- **Clamping.** The content is clamped first (`clampOffset`, including the alignment role's negative offset), then snapped, then held to `snapDown(max(0, content - viewport))`, the last grid position at or before the end, so a fractional extent never lets the grid push the offset past the end (a gap). Probe `F1`: 399.5 in 300 gives 99.0 at 1x, `presentedOffset(99.5) == 99` here. At 2x the half point 99.5 is on the grid and is the end. MetalUI's layout rounds to whole points (divergence 77), so a window builds a fractional extent only at a fractional scale; the rule is pinned through `resolveSlot` directly.
- **Not changed.** `CodeView`, `TextEditor` and the table body own their offsets (`CV-O`, `wheelOffset`) and are not scrollers of this path; they keep theirs.
- **Open: the 2x grid.** The author has only a 1x display. The probe's injected 2x measured the leaf grid (half a point) but its scroll position stayed whole points (100.3 gave 100.0, the bottom anchor of 399.5 gave 99.0), because AppKit's clip alignment follows the window's real backing scale, which stayed 1. MetalUI's rule is the device-pixel grid at the real scale (100.5 at 2x for 100.3). If a Retina Mac shows SwiftUI also stopping at whole points there, `snap` becomes `floor(v + 0.5)` for the scroll position and nothing else moves: human check `PSN1`.

## Carried

SwiftUI's ancestor application (divergence 226); the right-to-left reading of `.trailing`; a `List`'s end-aware cold frame; the `scrollPosition(id:)` binding following a pin; a user-scroll threshold other than 1 point is unmeasured (the probe's wheel arms are whole-gesture).
