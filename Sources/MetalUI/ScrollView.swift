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
/// `Box.overflow(.scroll)`. (It wrote an inert `Style.overflow` until stage 10
/// deleted the field, `LR-FM` item 1.)
///
/// **Two layout nodes**: a content node — stage 2's container lowering, so its
/// children's stretch, grow, margins, gaps and `justifyContent` lower as under
/// any other container — inside the kernel's scroll viewport, which answers its
/// proposal on the scrolling axis and its content's answer on the other and
/// places the content at its own answer (`CN-M`, `CN-F`, ruling `LR-BC`). See
/// `loweredLayout(_:children:inner:pass:)`.
///
/// **History.** Until stage 9 (`LR-FC`) a legacy branch registered the same two
/// nodes on the CSS flex engine, where the content node overflowed by CSS
/// Sizing §4.5's automatic minimum and needed `flexShrink: 0` to stop the freeze
/// loop shrinking text content from max-content towards min-content (measured:
/// 507.8 against 200 in a 200-point horizontal viewport). The kernel viewport
/// has no freeze loop; `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport`
/// (`ScrollViewTests.swift`) still pins the answer; the measurements are in
/// this doc's git history (before `LR-FC`).
///
/// **Scroll position is `StateTable` state, so it follows the conditional
/// rules** (plan task 8): a `ScrollView` inside an `if` that goes false and
/// comes back returns at offset 0 (`ID-C` resets content an evaluated
/// conditional removes), and no trailing sibling inherits its offset (`ID-B`:
/// an `if` takes one slot whether or not it has content). Until then the offset
/// was handed to the trailing sibling and naming that sibling was the remedy.
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

        // Plan task 7, stage 3, ruling LR-BB: two nodes in a fixed order under
        // fixed ids, registered on the kernel — see
        // `loweredLayout(_:children:inner:pass:)`.
        return loweredLayout(id, children: children, inner: inner, pass: &pass)
    }

    /// `requestLayout`'s registration (plan task 7, stage 3, ruling `LR-BB`),
    /// split out only for length. `children` are the content's already
    /// registered nodes and `inner` its group layout; both come from the
    /// `withScrollContext` build above, so the ids, the `@State` slots and the
    /// published `ScrollContext` are the ones the legacy branch had until stage
    /// 9 (`LR-BF`).
    ///
    /// **The content node is stage 2's container lowering, entire.** It goes
    /// through `lowerLegacyNode` at site `scrollView` rather than straight to
    /// `requestNativeLinearStack` (which is what `ProposalScrollView` does)
    /// because the legacy content node is an ordinary flex container: its
    /// children's stretch, grow, margins, gaps and `justifyContent` are already
    /// implemented and already pinned there, and a bare stack would drop all of
    /// it silently. Passing `site:` is also what keeps `LoweringSite.scrollView`
    /// reachable — `lowerLegacyNode` hands it to `planLegacyItems` as
    /// `parentSite:`, so scroller children with unequal grow factors report
    /// `scrollView.flexGrow.weights` (ruling `LR-BM`).
    ///
    /// **`flexShrink: 0` is deliberately NOT carried.** Under the legacy engine
    /// (until stage 9) that line stopped the freeze loop shrinking the content
    /// node from its max-content flex base towards its min-content floor (the
    /// type doc's history: 200 against 508). The kernel viewport has no freeze loop — it
    /// measures its content with the scrolling axis unspecified and places it at
    /// its own answer — so the line has no counterpart here. It is not merely
    /// pointless: with the content record left unconsumed (below), carrying it
    /// would **report** `scrollView.flexShrink.unconsumed`, which is what makes
    /// the omission observable at all.
    ///
    /// **The content node's record is left unconsumed, and that is the truthful
    /// state.** The viewport lowers no item field of its content. Today that
    /// style carries only `flexDirection`, every item field is at its default and
    /// `reportUnconsumedLoweredItems` names nothing; a field a later stage puts
    /// on the **declared** style (`declaredContent`) reports rather than
    /// vanishing. Which of the two styles carries it decides whether there is a
    /// diagnostic at all: `reportUnconsumedLoweredItems` reads `item.declared`
    /// only, never `item.animated`, so a field added to `contentStyle` alone is
    /// dropped silently — which is also why mutation M2d has to be applied to
    /// `declaredContent` to be observable. `LR-AS` puts structural item fields on
    /// the declared style, so the case is narrow; it is not closed by anything
    /// but that convention (verification round, record §12).
    ///
    /// **The viewport is recorded as this element's own `LoweredItem`** —
    /// declared `Style()` (this element has no modifier surface), the animated
    /// viewport style for its values, `kind: .leaf`, content alignment
    /// `.topLeading` — so a lowered container above it stretches or grows it
    /// exactly as the legacy flex line did until stage 9, through the item frame stage 2
    /// registers and the rect alias that reports it.
    private mutating func loweredLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                        inner: Content.GroupLayout,
                                        pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var declaredContent = Style()
        declaredContent.flexDirection = axis == .vertical ? .column : .row
        // Structure from the declared style, lengths from the animated one
        // (ruling LR-AS). Neither `flexDirection` nor anything else on this style
        // is animatable, so the two are equal today; the split is kept because
        // `lowerLegacyNode`'s checks must never be tripped by an interpolation.
        var contentStyle = declaredContent
        (contentStyle, _) = animated(contentStyle, Decoration(), for: scrollViewContentAnimID(for: id),
                                     pass: &pass)
        let contentNode = pass.lowerLegacyNode(contentStyle, declared: declaredContent,
                                               children: children, site: .scrollView)

        var viewportStyle = Style()
        viewportStyle.flexDirection = axis == .vertical ? .column : .row
        (viewportStyle, _) = animated(viewportStyle, Decoration(), for: scrollViewViewportAnimID(for: id),
                                      pass: &pass)
        let node = pass.frame.requestNativeScrollViewport(
            child: contentNode, axis: axis == .vertical ? .vertical : .horizontal)
        _ = pass.recordLoweredItem(node, animated: viewportStyle, declared: Style(), site: .scrollView,
                                   contentAlignment: .topLeading, kind: .leaf)
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

