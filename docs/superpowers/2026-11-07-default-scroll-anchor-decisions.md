# `defaultScrollAnchor` - decisions (prefix `DSA-`)

Rulings for Alloy gap G6 (a chat transcript, `ScrollView { LazyVStack { ForEach(blocks) { ... } } }` with thousands of variable-height blocks, appended while streaming, that starts at the bottom and stays pinned to it while the user is at the bottom). Branch `feat/default-scroll-anchor` from master `4d4c59db`; record 224. Class `A` with one divergence (226). **Next unused id: `DSA-J`.** Public API: `ScrollView`/`ProposalScrollView` `.defaultScrollAnchor(_:)` and `.defaultScrollAnchor(_:for:)`, `ScrollAnchorRole` (`.initialOffset`, `.sizeChanges`, `.alignment`). Probe: `docs/probes/swiftui-default-scroll-anchor.swift` (run twice; the only drift is the rubber-band residue of a wheel, 1-2 points).

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

## Carried

SwiftUI's ancestor application (divergence 226); the right-to-left reading of `.trailing`; a `List`'s end-aware cold frame; the `scrollPosition(id:)` binding following a pin; a user-scroll threshold other than 1 point is unmeasured (the probe's wheel arms are whole-gesture).
