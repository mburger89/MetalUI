import MetalUICore
import MetalUILayout

public enum ScrollAxis: Sendable, Equatable { case vertical, horizontal }

/// Whether `ScrollView` paints its fading overlay indicator.
///
/// **SwiftUI's spelling, deliberately narrowed to two cases** (ruling EP-5):
/// SwiftUI's `ScrollIndicatorVisibility` also has `.visible` and `.never`,
/// but those distinctions only pay off with nested scroll views and
/// platform-level defaults this framework does not have. `.automatic` is
/// this element's only behaviour today, so a third case would be a case
/// that does nothing — the exact shape CLAUDE.md's declared-but-inert table
/// exists to keep out. Add one later if a caller needs it; that is
/// source-compatible, unlike shipping an inert case now.
public enum ScrollIndicatorVisibility: Sendable, Equatable {
    /// Today's behaviour: the thumb appears while scrolling and fades out
    /// afterward. The default.
    case automatic
    /// No indicator is ever painted, and no frame is ever requested to fade
    /// one — `ScrollChrome.paintIndicator` returns before either happens.
    case hidden
}

/// Cross-frame scroll position, in logical points along the scroll axis.
public struct ScrollState: Sendable {
    public var offset: Double = 0

    /// The most recent scroll's instant, on the same clock as
    /// `PaintPass.timestamp` (both trace to `mach_absolute_time`) but sourced
    /// from the input event itself rather than the display link's last tick.
    /// Drives the overlay indicator's fade in `ScrollView.paint`: opaque while
    /// `timestamp - lastScrollTime` is small, ramping to invisible after.
    /// `Window.applyScroll` is the sole writer, stamping it from
    /// `ScrollEvent.timestamp` at the moment a wheel event lands — not from
    /// the display link's `lastTick`, which holds the *target* presentation
    /// instant for whichever frame is currently being built (spec §4.4) and
    /// goes stale for as long as the link is paused while idle.
    ///
    /// **Defaults to `-.infinity`, meaning "never scrolled" — not `0`.**
    /// `Window.lastTick` is also 0 until the display link first fires, and
    /// `App.openWindow` draws one frame before that happens, so a `0` default
    /// made that frame's `age` exactly 0: every scrollable `ScrollView` painted
    /// its thumb at full strength on the window's first frame and requested
    /// another one. With `-.infinity`, any finite `timestamp` gives
    /// `age == +.infinity`, the ramp gives `max(0, -.infinity) == 0` rather
    /// than NaN, and `ScrollChrome.paintIndicator`'s `guard alpha > 0` returns before
    /// `requestAnotherFrame()`. The init's parameter default is the one
    /// `ScrollState()` actually reaches, so it carries the same value.
    /// Pinned by `aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame`.
    public var lastScrollTime: Double = -.infinity

    /// The viewport's extent along the scroll axis, as of the last `prepaint`
    /// — written by `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload from the same
    /// `bounds` it clamps against. `requestLayout` reads this back **next**
    /// frame to publish `LayoutPass.scrollContext`: it is pure layout output,
    /// so the only way to have it during layout is to have stored it a frame
    /// earlier. Zero until the first `prepaint` ever runs for this element.
    public var viewportExtent: Double = 0

    public init(offset: Double = 0, lastScrollTime: Double = -.infinity, viewportExtent: Double = 0) {
        self.offset = offset
        self.lastScrollTime = lastScrollTime
        self.viewportExtent = viewportExtent
    }
}

/// The ambient value a `ScrollView` publishes to its descendants during
/// `requestLayout`, read back through `LayoutPass.scrollContext`. Named
/// rather than left as the bare tuple it started as — the same shape
/// `clipStack`'s entries have on `Frame`, except that tuple is `private` and
/// never crosses `MetalUI`'s own boundary, where this one is `public` and
/// was showing up spelled out at five call sites across `Frame` and
/// `LayoutPass`.
///
/// **Both fields answer a different question than `ScrollState`'s own.**
/// `offset` here is the CURRENT raw stored value — unclamped, because
/// clamping needs the content node's laid-out size, which does not exist
/// during layout (see `ScrollView.requestLayout`). `viewportExtent` is ONE
/// FRAME STALE, copied from `ScrollState.viewportExtent`, which only
/// `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload ever writes.
public struct ScrollContext: Sendable, Equatable {
    public var offset: Double
    public var viewportExtent: Double

    /// Which axis the two numbers above are measured along — so a reader can
    /// tell an offset it can use from one it cannot.
    ///
    /// **Carried from the start and read by nothing until the whole-branch
    /// review** (ruling MP-M), which is how `List` came to window a column of
    /// rows against a horizontal distance and a viewport *width*. `List` now
    /// declines to window at all unless this is `.vertical`; a publisher must
    /// therefore set it truthfully rather than defaulting it, and there is no
    /// default for exactly that reason.
    public var axis: ScrollAxis

    public init(offset: Double, viewportExtent: Double, axis: ScrollAxis) {
        self.offset = offset
        self.viewportExtent = viewportExtent
        self.axis = axis
    }
}

/// A clipped, scrollable viewport over content taller (or wider) than itself.
///
/// **SwiftUI's shape, not CSS's** (ruling EP-5): `ScrollView { … }` rather than
/// `Box.overflow(.scroll)`. `Style.overflow` stays the substrate this element
/// writes into, the way `Column.init` writes `alignItems` without `Style`'s
/// default moving (ruling EP-8).
///
/// **Two layout nodes, and the reason is measured rather than assumed.** A
/// viewport node takes the offered size; a content node inside it overflows.
/// Five 40pt rows in a 200×100 viewport, probed against the real engine:
///
/// | content node | height | overflows |
/// |---|---|---|
/// | `min-height: auto` (default), `flexShrink: 0` | 200 | yes |
/// | `min-height: auto` (default), `flexShrink` default | 200 | yes |
/// | `min-height: 0`, `flexShrink: 0` | 200 | yes |
/// | `min-height: 0`, `flexShrink` default | **100** | **no** |
///
/// **CSS Sizing §4.5's automatic minimum is what overflows this content node**
/// — `min-height: auto` floors it at its content size, divergence FS-3's
/// mechanism — and rows one and two show `flexShrink` cannot be *substituted*
/// for it: with the automatic minimum in place, both spellings overflow.
///
/// **Those four rows are true and the conclusion once drawn from them was
/// not.** They were read as "`flexShrink` matters only in row four, row four
/// is unreachable through this type, therefore `flexShrink: 0` is inert here",
/// and the line was deleted on that argument. The rows cannot support it,
/// because every one of them is measured on fixed-height `Box`es — content
/// whose **min-content and max-content sizes are the same number**. That is
/// exactly the corpus-uniformity hazard CLAUDE.md records about the 61
/// empty-div fixtures, reproduced in a four-row probe.
///
/// **`flexShrink: 0` is load-bearing whenever the content's intrinsic sizes
/// differ — which is any content holding text.** The automatic minimum floors
/// this node at **min-content**; its flex base size is **max-content**. Where
/// those differ, the freeze loop shrinks the node down from the base size
/// towards the floor, and only `flexShrink = 0` stops it. Measured through
/// this type:
///
/// | probe | line deleted | line present |
/// |---|---|---|
/// | `ScrollView(.horizontal) { Text(…); Text(…) }` in 200pt | content **200** == viewport: nothing to scroll, indicator suppressed | content **507.8** |
/// | `ScrollView(.vertical) { 5 × Text(…) }` in 200×40 | content **80**: half the list unreachable | content **160** |
///
/// `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport`
/// (`Tests/MetalUITests/ScrollViewTests.swift`) is the pin, with CoreText as
/// its oracle; deleting the line reddens exactly it. The engine mechanism the
/// four-row table *does* isolate — that `flexShrink: 0` also holds a node open
/// once an explicit zero minimum has removed the automatic one — stays pinned
/// independently of this type by
/// `flexShrinkHoldsAContentNodeOpenOnceItsAutomaticMinimumIsRemoved`
/// (`Tests/MetalUILayoutTests/ScrollLayoutTests.swift`).
///
/// **Scroll position is `StateTable` state, so it inherits §4.3's adoption
/// rule**: a `ScrollView` inside a vanishing `if` hands its offset to the
/// trailing sibling, not to a fresh zero — a list silently inheriting another
/// list's scroll position is a confusing thing to meet cold. The remedy is the
/// counter-intuitive one CLAUDE.md records — name the **trailing sibling**, not
/// the conditional content, to keep this element's offset from drifting onto
/// whatever renders after it vanishes.
public struct ScrollView<Content: ElementGroup>: Element {
    public var axis: ScrollAxis
    public var elementID: ElementID?
    public var content: Content

    /// The radius the clips this element pushes are rounded to, in points.
    /// Zero — a square clip — unless `cornerRadius(_:)` sets it.
    ///
    /// **`ScrollView` has no `Decoration` and paints no background of its
    /// own** — the caller supplies one, typically a wrapping
    /// `Box(decoration:)`, exactly as `Sources/MetalUIDemoContent/DemoContent.swift` does.
    /// This property is what lets the caller give this element's CLIPS the
    /// same curve as that background: ruling CL-A. Nothing enforces that the
    /// two values agree — this element cannot see its container's
    /// `Decoration` — so a caller that changes one radius owns changing both.
    ///
    /// **It governs the overlay indicator's clip as well as the content's**,
    /// which is not decoration: the thumb is painted outside the content's
    /// clipped block so that it does not scroll, and outside that block it
    /// carried no clip at all — so it painted square across the very corner
    /// this radius exists to curve. `ScrollChrome.paintIndicator` pushes the same bounds
    /// and the same radii with a zero offset.
    ///
    /// **Does NOT animate, silently, where the identical modifier on a `Box`
    /// does (M4 spec 3, Task 4's fix round).** This is a plain stored
    /// `Pixels`, not a `Decoration.cornerRadius` — it never reaches
    /// `animated(_:_:for:pass:)`, which only substitutes the `Style`/
    /// `Decoration` pair each of `requestLayout`'s TWO nodes builds fresh.
    /// A caller who wraps a `cornerRadius(_:)` change in `withAnimation`
    /// here gets an instant snap, with no error and nothing in the type
    /// system to say why — a `Box`'s `.cornerRadius(_:)` right next to it in
    /// the same tree would smoothly interpolate. The `Decoration()` passed
    /// to `animated(_:_:for:)` at both of this type's registering sites is
    /// deliberately fresh and discarded (`ScrollView` has none of its own),
    /// which means each call mints and immediately drops a
    /// `Decoration.cornerRadius` field that nothing here reads — a real,
    /// harmless-but-wasted per-frame `animateField` call for a property this
    /// type does not have.
    public var cornerRadius: Pixels = Pixels(0)

    /// Whether `ScrollChrome.paintIndicator` paints the fading thumb at all. `.automatic`
    /// unless `scrollIndicators(_:)` sets it.
    public var indicatorVisibility: ScrollIndicatorVisibility = .automatic

    public init(_ axis: ScrollAxis = .vertical, elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        self.axis = axis
        self.elementID = elementID
        self.content = content()
    }

    /// Rounds the corners of both clips this element pushes — the one around
    /// its scrolling content and the one around its overlay indicator, which
    /// take the same bounds and the same radii and differ only in that the
    /// indicator's carries no scroll translation. See `cornerRadius`'s doc
    /// comment for what this does and does not do.
    public func cornerRadius(_ points: Pixels) -> Self {
        var copy = self
        copy.cornerRadius = points
        return copy
    }

    /// Sets whether the fading overlay indicator is ever painted.
    /// `.hidden` suppresses it entirely, including the frame requests it
    /// makes while fading — see `ScrollChrome.paintIndicator`'s guard.
    public func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> Self {
        var copy = self
        copy.indicatorVisibility = visibility
        return copy
    }

    public struct Layout {
        public var node: LayoutNodeID       // viewport
        public var contentNode: LayoutNodeID
        var inner: Content.GroupLayout
    }

    /// The clamp, the offset resolution and the fading overlay indicator, all
    /// of which this element shares with ``ProposalScrollView`` (ruling
    /// `LR-BD`). **Computed, not stored** — see `ScrollChrome`'s own doc for
    /// why, and for what the fold deliberately left alone.
    var chrome: ScrollChrome {
        ScrollChrome(axis: axis, cornerRadius: cornerRadius,
                     indicatorVisibility: indicatorVisibility)
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        // The raw stored offset, unclamped — a scroll that landed before this
        // frame (`Window.applyScroll` writes it, then dirties the window) is
        // visible here, exactly as it will be to prepaint's own read a few
        // lines later in the frame. `viewportExtent` is last frame's, because
        // this frame's viewport does not exist until layout runs. See
        // `ScrollState.viewportExtent`'s doc for why neither is resolved or
        // clamped here — that is `ScrollChrome.resolvedOffset`'s job, once bounds exist.
        var rawOffset: Double = 0
        var lastViewportExtent: Double = 0
        pass.withState(id, initial: ScrollState()) {
            rawOffset = $0.offset
            lastViewportExtent = $0.viewportExtent
        }

        var cursor = 0
        // Pushed before the subtree is built and popped after, via `defer`
        // inside `withScrollContext` — the same shape as `clipped(to:offsetBy:)`,
        // so a sibling declared after this `ScrollView` (rather than inside
        // it) sees none of it. `withScrollContext` is generic over its
        // closure's result, so the subtree's own return value threads
        // straight out with no local IUO to hoist it through.
        let (children, inner) = pass.withScrollContext(
            ScrollContext(offset: rawOffset, viewportExtent: lastViewportExtent, axis: axis)
        ) {
            content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        }

        // The site's own authority check (plan task 7, ruling LR-C): a
        // `ScrollView` has no proposal lowering until stage 3, so it traps by
        // name — after its content (which checks its own sites first) and before
        // either node or `$anim` prefix. Under diagnostics one 0×0 native leaf
        // stands for both the viewport and the content node. The item records its
        // content returned are consumed first (plan task 7, stage 2, ruling LR-AQ):
        // this site's own entry already makes the tree unlowerable.
        if pass.lowersToProposal {
            for child in children { _ = pass.frame.lowering.consume(child) }
            let node = pass.frame.unlowerable(UnlowerableField(site: .scrollView, field: "noLowering"))
            return (node, Layout(node: node, contentNode: node, inner: inner))
        }

        var contentStyle = Style()
        contentStyle.flexDirection = axis == .vertical ? .column : .row
        // **Load-bearing, and for content whose min-content and max-content
        // widths DIFFER — i.e. anything with text in it.** The automatic
        // minimum floors this node at its *min-content* size; its flex base
        // size is *max-content*. Where those differ the freeze loop shrinks
        // the node from the latter towards the former, and only
        // `flexShrink = 0` stops it. Measured through this type: a
        // horizontal `ScrollView` of two `Text`s in a 200pt viewport gives a
        // content node of 200 (== viewport, nothing to scroll) without this
        // line and 508 with it. See the type doc.
        contentStyle.flexShrink = 0
        // M4 spec 3 §5: `ScrollView` registers TWO nodes from one element id,
        // so passing `id` itself to `animated(_:_:for:)` twice would collide
        // both nodes' fields under the identical `$anim` retention slot
        // (`animRetentionSlot(for:)` derives one slot per id, not per call).
        // A named child id per node — on the same collision footing as
        // `$state`, `$focus` and `$ax` — keeps them apart. Note the SHAPE:
        // these two are id PREFIXES, not slots. `animated(...)` derives
        // `animRetentionSlot(for:)` from whatever id it is handed, so the
        // stored value ends up at `child(child(id, "$anim-content"),
        // "$anim")` — a grandchild — and nothing is ever stored at
        // `$anim-content` itself. `ScrollView` has no
        // `Decoration` of its own (see `cornerRadius`'s doc above), so a
        // fresh, discarded one is passed through and back. The two derived
        // ids are shared functions (`AnimatedStyle.swift`), not inlined here
        // — see that file's own doc for why a copy would leave a rename
        // uncaught.
        (contentStyle, _) = animated(contentStyle, Decoration(), for: scrollViewContentAnimID(for: id),
                                     pass: &pass)
        let contentNode = pass.frame.requestNode(style: contentStyle, children: children)

        var viewportStyle = Style()
        viewportStyle.flexDirection = axis == .vertical ? .column : .row
        // Written for the model's sake. The engine reads `overflow` nowhere
        // today — measured: removing this line moved no number in the layout
        // probe — so it documents intent rather than driving behaviour. See
        // CLAUDE.md's declared-but-inert table.
        viewportStyle.overflow = Axes(both: .scroll)
        (viewportStyle, _) = animated(viewportStyle, Decoration(), for: scrollViewViewportAnimID(for: id),
                                      pass: &pass)
        let node = pass.frame.requestNode(style: viewportStyle, children: [contentNode])

        return (node, Layout(node: node, contentNode: contentNode, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let chrome = self.chrome
        let offset = chrome.resolvedOffset(id, bounds: bounds, contentNode: layout.contentNode,
                                           pass: pass)
        // Registered OUTSIDE `clipped(to:offsetBy:)`, using the bounds handed
        // in rather than anything computed inside the block: `bounds` here is
        // this viewport's rect in its PARENT's space, and being outside the
        // block is what keeps this scroller's OWN offset out of its own
        // registered rect — a viewport does not scroll away from itself.
        //
        // Being outside its own block does NOT zero the ambient offset: an
        // ANCESTOR scroller's `clipped(to:offsetBy:)` is still in effect here,
        // because this element's whole `prepaint` runs inside it. That is
        // exactly right, and it is what `Frame.insertHitbox` translates by —
        // a nested `ScrollView` receives wheel events where it paints. It was
        // wrong until scroll regions folded into the hitbox list (ruling IN-F):
        // the old `registerScrollRegion` dropped the translation, so a nested
        // scroller inside a scrolled one was registered at a rect that has
        // moved out from under it — it kept whatever part of its hit area the
        // stale rect still overlaps and lost the rest to whatever is beneath.
        // NOT all of it: measured on
        // `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`
        // with the fix reverted, a wheel at (100, 120) reached the OUTER
        // scroller and one at (100, 170) still reached the inner one.
        pass.registerScrollRegion(bounds, id: id, axis: axis)
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: chrome.delta(-offset),
                    cornerRadii: Corners(all: cornerRadius)) {
            result = content.prepaintGroup(layout: &layout.inner, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let chrome = self.chrome
        let offset = chrome.resolvedOffset(id, bounds: bounds, contentNode: layout.contentNode,
                                           pass: pass)
        // The clip is rounded to `cornerRadius` — the same curve the caller's
        // wrapping background (typically a `Box(decoration:)`) paints, so a
        // row scrolled to the very top or bottom is cut by the same curve
        // rather than painting square into a corner the background left
        // transparent. Ruling CL-A.
        pass.clipped(to: bounds, offsetBy: chrome.delta(-offset),
                    cornerRadii: Corners(all: cornerRadius)) {
            content.paintGroup(layout: &layout.inner, prepaint: &prepaint, pass: &pass)
        }
        // Deliberately OUTSIDE the block above and emitted AFTER it — the one
        // composition Task 1's draw list exists for. Inside the block, this
        // fill would inherit the same `-offset` translation as the content
        // above it and scroll away with it; before the draw list existed, a
        // rect emitted here would still have drawn BENEATH any glyphs the
        // content just emitted regardless of order, so an overlay indicator
        // over a list of text was not expressible at all.
        //
        // **Outside this block, not unclipped**: `ScrollChrome.paintIndicator` pushes its
        // own clip at the same bounds and radii with a ZERO offset, which is
        // what leaves the thumb inside the rounded corner without leaving it
        // subject to the scroll. Being outside here and clipped by nothing at
        // all was a reported defect — see `ScrollChrome.paintIndicator`.
        chrome.paintIndicator(id, bounds: bounds, offset: offset,
                              contentNode: layout.contentNode, pass: &pass)
    }
}

