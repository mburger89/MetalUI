# `contentMargins` - decisions (prefix `CMG-`)

Rulings for Alloy gap G43 (glass bars float over scrolled content: file tabs and a header over a `CodeView`, a composer over a chat `ScrollView`; the content must start below and end above the bar yet scroll underneath it). Branch `feat/content-margins` from master `e852cb12`; record 287. Class `A`, no divergence added. **Next unused id: `CMG-G`.** Public API: `contentMargins(_:_:for:)` (an `EdgeInsets`, or a length, on an `Edge.Set`) and `contentMargins(_:for:)` on any `ElementGroup`, `ContentMarginPlacement` (`.automatic`, `.scrollContent`, `.scrollIndicators`). Probe: `docs/probes/swiftui-content-margins.swift` (**written, not run**: an agent opens no window; the arms carry the readings the documentation and the WWDC23 session give, to be confirmed on a Mac; the one fact read from Apple's pages is that a nearer modifier of a placement overrides one above it). `safeAreaInset` was considered and refused: safe areas are the product boundary `PB-A`, and `contentMargins` needs none.

## CMG-A: the placements and what a scroller does with them

`.scrollContent` insets the scrolled content inside the scroll area: at offset 0 the first content starts at the leading margin, at the end the last content ends before the trailing one, and the content **draws and scrolls under the margin region** (nothing clips there). `.scrollIndicators` insets the indicators only. `.automatic` is both. Margins **add to** the content's own padding (the margin is outside it). **Uncertain:** whether `.automatic` also insets the indicators on a `ScrollView` (Apple's page says only "The automatic placement"; an unverified recollection of the WWDC23 session is both, `.scrollContent` being the way to inset content alone); chosen: both, and every Alloy use names `.scrollContent`.

Mechanism: the scroll-content margins of the environment at the scroller (`EnvironmentValues.contentMargins`, internal, in the retained fingerprint) wrap the scroller's content node in one **native padding node** (`Frame.paddedForContentMargins`), and that node is the content node the scroller clamps, translates, hit-tests and windows against. So the clamp, the scroll range, the lazy windows (a `LazyVStack` or `List` learns its own origin from last frame exactly as it does below a header), the indicator's thumb ratio and `defaultScrollAnchor`'s end all measure one extent. No margin set adds no node and changes nothing.

## CMG-B: writing and overriding

`contentMargins(_ edges:, _ insets:, for:)` writes the inset of each edge in `edges` for the placement and leaves the other edges as they were; `.automatic` writes both placements. A `nil` length writes zero (SwiftUI's "default" is the safe area plus nothing; there is none). Apple's page: "modifiers with the same placement will override modifiers higher up", so the nearest write wins, **per edge** here (unmeasured whether SwiftUI overrides per edge or the whole placement). The environment propagates, so a nested scroller beneath also receives the margins (as in SwiftUI). Leading and trailing are the left and right under left-to-right and reflect under right-to-left through the layout tree, as `padding` does (`LD-A`); the right-to-left reading of the indicator's horizontal inset is unmeasured.

## CMG-C: the indicator

The thumb's track is the viewport minus the `.scrollIndicators` start and end insets: it starts at the start inset and its travel is the track minus the thumb. The thumb's length keeps `track x viewport / content` (the 20-point floor stays), so the proportion is the unmargined one. A `.scrollContent` margin lengthens the content, so the thumb shortens as it would for any longer content. Unmeasured against SwiftUI: the thumb's exact length with an inset.

## CMG-D: positions measure the viewport minus the margins

`scrollTo(_:anchor:)`, a `scrollPosition(id:anchor:)` binding and its writes use the visible region `start + margin ... end - margin` in place of the viewport: `.top` puts the target just below the top margin, `.bottom` just above the bottom one, no anchor brings a row below to the bottom margin and one above to the top margin (`ScrollerFrame.inset`, read by `Frame.scrollOffset(bringing:into:anchor:)` and `ScrollPositionRegistry.target`). `defaultScrollAnchor(.bottom)` needs nothing more: the content's end is the padding node's end, so the last row sits above the bottom margin and the pin follows it. Zero insets are the old arithmetic exactly.

## CMG-E: a margin that changes (the composer that grows)

A margin change is a layout change, not a rebuild: the environment value reaches the scroller in layout, the padding node is registered with the new insets, and content components that are equal are not rebuilt (test `aMarginChangeRelaysOutWithoutRebuildingTheContent`). A scroller pinned to its end (`DSA-C`: the pin is decided in layout from last prepaint's memory) stays pinned in the SAME frame whether the bottom margin grows or shrinks: the last row is just above the new margin one tick after the write, no jump, no one-frame lag. A scroller scrolled away keeps its offset, so a **bottom** margin change moves nothing in view; a **top** margin change moves the content by the change (the offset is a distance from the content's start, which includes the margin) - the tests pin the bottom case Alloy needs.

## CMG-F: unset is unchanged

With no margin set a scroller registers no padding node, resolves zero insets and paints the thumb on the old arithmetic, so its layout, offsets and draw list are byte-identical (the whole scroll, list, lazy and retained suites pass unchanged, with `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1`). The fingerprint grows one field (`contentMargins`), so a retained subtree replays only under the margins it was recorded under.

## Carried

`CodeView` reads the same environment in its own scroll model (PR 2, `CV-AV`). A horizontal margin on a horizontal scroller in right-to-left; the per-edge versus whole-placement override; `.automatic` and the indicators; the thumb length with an inset (all above, probe arms `M1`-`M9` to run). `ScrollView`'s `scrollTargetBehavior` does not exist here. `contentMargins(for:edges:alignment:)` and `ContentMarginGuide` (layout guides) are not offered.
