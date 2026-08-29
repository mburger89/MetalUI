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
    /// one — `paintIndicator` returns before either happens.
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
    /// the display link's `lastTick`, which is frozen at whatever instant the
    /// last frame ran and goes stale for as long as the link is paused while
    /// idle (spec §4.4).
    public var lastScrollTime: Double = 0

    /// The viewport's extent along the scroll axis, as of the last `prepaint`
    /// — written by `resolvedOffset`'s `PrepaintPass` overload from the same
    /// `bounds` it clamps against. `requestLayout` reads this back **next**
    /// frame to publish `LayoutPass.scrollContext`: it is pure layout output,
    /// so the only way to have it during layout is to have stored it a frame
    /// earlier. Zero until the first `prepaint` ever runs for this element.
    public var viewportExtent: Double = 0

    public init(offset: Double = 0, lastScrollTime: Double = 0, viewportExtent: Double = 0) {
        self.offset = offset
        self.lastScrollTime = lastScrollTime
        self.viewportExtent = viewportExtent
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
    /// `Box(decoration:)`, exactly as `Sources/MetalUIDemo/main.swift` does.
    /// This property is what lets the caller give this element's CLIPS the
    /// same curve as that background: ruling CL-A. Nothing enforces that the
    /// two values agree — this element cannot see its container's
    /// `Decoration` — so a caller that changes one radius owns changing both.
    ///
    /// **It governs the overlay indicator's clip as well as the content's**,
    /// which is not decoration: the thumb is painted outside the content's
    /// clipped block so that it does not scroll, and outside that block it
    /// carried no clip at all — so it painted square across the very corner
    /// this radius exists to curve. `paintIndicator` pushes the same bounds
    /// and the same radii with a zero offset.
    public var cornerRadius: Pixels = Pixels(0)

    /// Whether `paintIndicator` paints the fading thumb at all. `.automatic`
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
    /// makes while fading — see `paintIndicator`'s guard.
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

    /// `0 ... max(0, content - viewport)`.
    ///
    /// **Clamped on read, not on write.** The wheel handler that writes the
    /// offset (Task 7) has no access to the current layout, and the layout that
    /// would validate it does not exist until the next frame — so a stored
    /// value may legitimately be out of range when content shrinks between
    /// frames. `aStoredOffsetPastTheEndIsClampedWhenItIsRead` in
    /// `ScrollViewTests.swift` is what this guarantees.
    ///
    /// **The result is written back to the state table by `resolvedOffset`, and
    /// that write-back is what bounds the stored value.** Clamping the read
    /// alone leaves the stored number free to run away — see `resolvedOffset`.
    static func clamp(offset: Double, content: Double, viewport: Double) -> Double {
        min(max(0, offset), max(0, content - viewport))
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        // The raw stored offset, unclamped — a scroll that landed before this
        // frame (`Window.applyScroll` writes it, then dirties the window) is
        // visible here, exactly as it will be to prepaint's own read a few
        // lines later in the frame. `viewportExtent` is last frame's, because
        // this frame's viewport does not exist until layout runs. See
        // `ScrollState.viewportExtent`'s doc for why neither is resolved or
        // clamped here — that is `resolvedOffset`'s job, once bounds exist.
        var rawOffset: Double = 0
        var lastViewportExtent: Double = 0
        pass.withState(id, initial: ScrollState()) {
            rawOffset = $0.offset
            lastViewportExtent = $0.viewportExtent
        }

        var cursor = 0
        var children: [LayoutNodeID] = []
        var inner: Content.GroupLayout!
        // Pushed before the subtree is built and popped after, via `defer`
        // inside `withScrollContext` — the same shape as `clipped(to:offsetBy:)`,
        // so a sibling declared after this `ScrollView` (rather than inside
        // it) sees none of it.
        pass.withScrollContext((offset: rawOffset, viewportExtent: lastViewportExtent, axis: axis)) {
            (children, inner) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
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
        let contentNode = pass.requestNode(style: contentStyle, children: children)

        var viewportStyle = Style()
        viewportStyle.flexDirection = axis == .vertical ? .column : .row
        // Written for the model's sake. The engine reads `overflow` nowhere
        // today — measured: removing this line moved no number in the layout
        // probe — so it documents intent rather than driving behaviour. See
        // CLAUDE.md's declared-but-inert table.
        viewportStyle.overflow = Axes(both: .scroll)
        let node = pass.requestNode(style: viewportStyle, children: [contentNode])

        return (node, Layout(node: node, contentNode: contentNode, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        // Registered OUTSIDE `clipped(to:offsetBy:)`, using the bounds handed
        // in rather than anything computed inside the block: `bounds` here is
        // this viewport's rect in its PARENT's space, which is what a wheel
        // event's window-space position needs to be compared against. Inside
        // the block, `pass`'s active clip has already absorbed this rect, so a
        // nested `ScrollView` registers ITS rect intersected with this one —
        // see `Frame.registerScrollRegion`.
        pass.registerScrollRegion(bounds, id: id, axis: axis)
        var result: Content.GroupPrepaint!
        pass.clipped(to: bounds, offsetBy: delta(-offset),
                    cornerRadii: Corners(all: cornerRadius)) {
            result = content.prepaintGroup(layout: &layout.inner, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        let offset = resolvedOffset(id, bounds: bounds, layout: layout, pass: pass)
        // The clip is rounded to `cornerRadius` — the same curve the caller's
        // wrapping background (typically a `Box(decoration:)`) paints, so a
        // row scrolled to the very top or bottom is cut by the same curve
        // rather than painting square into a corner the background left
        // transparent. Ruling CL-A.
        pass.clipped(to: bounds, offsetBy: delta(-offset),
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
        // **Outside this block, not unclipped**: `paintIndicator` pushes its
        // own clip at the same bounds and radii with a ZERO offset, which is
        // what leaves the thumb inside the rounded corner without leaving it
        // subject to the scroll. Being outside here and clipped by nothing at
        // all was a reported defect — see `paintIndicator`.
        paintIndicator(id, bounds: bounds, offset: offset, layout: layout, pass: &pass)
    }

    /// The fading overlay scroll indicator: a thumb sized and positioned to
    /// the viewport/content ratio, opaque for 0.6s after a scroll and then
    /// ramped linearly to invisible over the next 0.4s.
    ///
    /// **A hand-rolled ramp, not an easing curve.** `PaintPass.timestamp` and
    /// `requestAnotherFrame()` are borrowed M4 primitives — inputs to
    /// animation, not an animation system — so this is the one place in the
    /// element that computes a value that changes over time, and it does so
    /// with a `let` and an `if`.
    private func paintIndicator(_ id: GlobalElementID, bounds: Bounds<Pixels>, offset: Double,
                                layout: Layout, pass: inout PaintPass) {
        // Checked first and unconditionally: `.hidden` must cost nothing at
        // all, not paint a suppressed-alpha rect, and must never reach
        // `requestAnotherFrame()` below — a hidden indicator that kept
        // asking would hold the display link awake forever, exactly the
        // failure `guard alpha > 0` exists to prevent for a faded one.
        guard indicatorVisibility != .hidden else { return }
        let content = extent(pass.bounds(of: layout.contentNode).size)
        let viewport = extent(bounds.size)
        let scrollable = max(0, content - viewport)
        // Nothing to scroll: no thumb, and — just as important for spec
        // §4.4 — no `requestAnotherFrame()` either. A `ScrollView` whose
        // content fits must cost exactly as little as a `Box`.
        guard scrollable > 0 else { return }

        var lastScroll: Double = 0
        pass.withState(id, initial: ScrollState()) { lastScroll = $0.lastScrollTime }
        let age = pass.timestamp - lastScroll
        let alpha = age < 0.6 ? 1.0 : max(0, 1.0 - (age - 0.6) / 0.4)
        guard alpha > 0 else { return }
        // Unconditional here on purpose: the guard just above is what stops
        // the asking. Once `alpha` has reached zero this point is
        // unreachable at all, so an idle window that was scrolled once and
        // left alone stops requesting frames on its own — a wrapping
        // `if age < 1.0` here would read as a second guard but can never be
        // false when reached (`alpha > 0` above already implies it), so it
        // stayed as a comment instead of a condition that cannot fail.
        pass.requestAnotherFrame()

        let thumb = max(20, viewport * (viewport / content))
        let travel = (offset / scrollable) * (viewport - thumb)

        var color = pass.theme[.scrollIndicator]
        color.a *= Float(alpha)
        // **The same clip as the content, with the translation taken out.**
        // Being outside `paint`'s `clipped(to:offsetBy:)` block is what stops
        // the thumb scrolling away with the content; it also left it clipped by
        // nothing at all, so on a rounded viewport it painted square across the
        // corner the background had curved away — `Frame.fill` stamps every
        // rect with `activeClip` and `activeClipRadii`, and outside a block
        // those are the whole surface and zero radii.
        //
        // `offsetBy: .zero` is the load-bearing half of this call, and it is
        // what makes "clipped but not scrolled" expressible: the same `bounds`
        // and the same `cornerRadius` as the content clip, and none of its
        // `-offset` translation. Passing `delta(-offset)` here instead would
        // reproduce exactly the bug painting inside the block would.
        pass.clipped(to: bounds, offsetBy: Point(x: Pixels(0), y: Pixels(0)),
                    cornerRadii: Corners(all: cornerRadius)) {
            pass.fill(indicatorBounds(bounds: bounds, thumb: thumb, travel: travel),
                     color: color, cornerRadii: Corners(all: Pixels(3)))
        }
    }

    /// The thumb's rect: 3pt wide (or tall, for `.horizontal`), inset 2pt from
    /// the viewport's trailing edge, `thumb` long and `travel` from the start
    /// along the scroll axis.
    private func indicatorBounds(bounds: Bounds<Pixels>, thumb: Double,
                                 travel: Double) -> Bounds<Pixels> {
        switch axis {
        case .vertical:
            return Bounds(
                origin: Point(x: Pixels(bounds.origin.x.value + bounds.size.width.value - 5),
                             y: Pixels(bounds.origin.y.value + Float(travel))),
                size: Size(width: Pixels(3), height: Pixels(Float(thumb))))
        case .horizontal:
            return Bounds(
                origin: Point(x: Pixels(bounds.origin.x.value + Float(travel)),
                             y: Pixels(bounds.origin.y.value + bounds.size.height.value - 5)),
                size: Size(width: Pixels(Float(thumb)), height: Pixels(3)))
        }
    }

    // Two overloads, one per pass type, rather than one function taking a
    // shared protocol. `PrepaintPass` and `PaintPass` have no common protocol
    // to write this against — `Passes.swift` records why: a `StatefulPass`
    // requirement would force `frame` public on both, and `PaintPass.frame`
    // leaking makes `scaleFactor` reachable through it, which is exactly the
    // double-application hazard `PaintPass` is built to keep out of element
    // code. Three lines duplicated is cheaper than that leak.
    ///
    /// **The prepaint overload writes the clamped value BACK, and that line is
    /// what keeps scrolling responsive rather than being a tidy-up.** `Window.applyScroll`
    /// writes `offset -= delta` with no bound — it has this region's rect but
    /// not the content node's size, and no layout at all for the frame it is
    /// about to cause. Reading through a clamp while leaving the stored number
    /// alone therefore lets a gesture against either end bank an arbitrarily
    /// large excess *invisibly*: the view sits at the end looking correct, and
    /// every event in the opposite direction then spends itself paying that
    /// excess down instead of moving anything. Measured on a 200pt content in a
    /// 120pt viewport (80pt of travel), one frame per event, before the
    /// write-back existed: twenty -37 events stored **740**, and seventeen of
    /// the twenty events that followed in the opposite direction moved the view
    /// by nothing. How long that dead band lasted was a function of how far past
    /// the end the user had already scrolled, which is why it was reported as
    /// scrolling that worked and then intermittently stopped.
    ///
    /// The bound this buys is "one frame's worth of events", not zero: events
    /// arriving between two frames still accumulate unclamped, and `Window`
    /// dirties the window on every one of them, so the next frame normalises
    /// them together. That is the tightest bound available from here — the
    /// ceiling does not exist until layout has run. Pinned by
    /// `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`
    /// (`ScrollRoutingTests.swift`).
    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                layout: Layout, pass: PrepaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var resolved: Double = 0
        pass.withState(id, initial: ScrollState()) {
            $0.offset = Self.clamp(offset: $0.offset, content: content, viewport: viewport)
            resolved = $0.offset
            // The half `viewportExtent`'s own doc names: this is the only
            // writer, and it is what lets NEXT frame's `requestLayout` read a
            // viewport extent at all.
            $0.viewportExtent = viewport
        }
        return resolved
    }

    /// **This one clamps on read and does NOT write back, unlike the prepaint
    /// overload above — measured, not assumed.** `Frame.render` runs prepaint
    /// before paint unconditionally, and `ScrollView.prepaint` calls its
    /// overload unconditionally, so by the time this runs the stored value has
    /// already been normalised against this same layout and a second write
    /// could only store the number it just read. Adding one back reddens
    /// nothing on a 498-test suite, which is redundancy rather than a coverage
    /// gap: the mutant provably cannot behave differently. The read clamp
    /// itself stays, so this phase is correct on its own terms rather than by
    /// trusting the phase before it.
    private func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                layout: Layout, pass: PaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: layout.contentNode).size)
        var stored: Double = 0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return Self.clamp(offset: stored, content: content, viewport: viewport)
    }

    private func delta(_ v: Double) -> Point<Pixels> {
        axis == .vertical ? Point(x: Pixels(0), y: Pixels(Float(v)))
                          : Point(x: Pixels(Float(v)), y: Pixels(0))
    }

    func extent(_ size: Size<Pixels>) -> Double {
        Double(axis == .vertical ? size.height.value : size.width.value)
    }
}
