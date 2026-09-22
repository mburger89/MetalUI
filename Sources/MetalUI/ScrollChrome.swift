import MetalUICore
import MetalUILayout

/// The clamp, the offset resolution and the fading overlay indicator — the
/// behaviour a scrolling viewport has that is neither its layout nor its
/// content — shared by ``ScrollView`` and ``ProposalScrollView``.
///
/// **Why it exists (plan task 7, stage 3, ruling `LR-BD`).** Both elements held
/// their own copy of all seven members below. The copies were line-equivalent
/// and every assertion about them named `ScrollView`, so CLAUDE.md's practice —
/// *a copy of a pinned implementation is unpinned* — applied exactly:
/// `ProposalScrollView`'s clamp, write-back, thumb floor, ramp and indicator
/// clip could have drifted without a single test noticing. One of them already
/// had: `ScrollView.paintIndicator` seeded its `lastScroll` local at `0` and
/// `ProposalScrollView`'s at `-Double.infinity`, two different answers to the
/// same question ten lines apart. (Both were dead —
/// `StateTable.withState` always runs its closure — which is the only reason
/// the drift was harmless.)
///
/// **Computed, never stored.** Both elements build a `ScrollChrome` on demand
/// from `axis`, `cornerRadius` and `indicatorVisibility`, which they already
/// store. Adding a stored property to a public type that crosses a module
/// boundary is CLAUDE.md's incremental-build hazard (`Scene` twice, `Display`,
/// `FontKey`), and this fold's whole claim is that nothing observable changed —
/// a `swift package clean` in the middle of it would be the wrong shape of
/// evidence.
///
/// **Two things deliberately did NOT fold.** The two `resolvedOffset` overloads
/// stay two functions (see their own comment below), four copies becoming two
/// rather than one; and `ScrollContext` publication stays `ScrollView`'s alone
/// (ruling `LR-BF`) — nothing can read one from a `ProposalScrollView`, so
/// publishing one there would be the declared-but-inert shape CLAUDE.md's table
/// exists to keep out.
struct ScrollChrome {
    var axis: ScrollAxis
    var cornerRadius: Pixels
    var indicatorVisibility: ScrollIndicatorVisibility

    /// `0 ... max(0, content - viewport)`.
    ///
    /// **Clamped on read, not on write.** The wheel handler that writes the
    /// offset has no access to the current layout, and the layout that would
    /// validate it does not exist until the next frame — so a stored value may
    /// legitimately be out of range when content shrinks between frames.
    /// `aStoredOffsetPastTheEndIsClampedWhenItIsRead` in `ScrollViewTests.swift`
    /// is what this guarantees.
    ///
    /// **The result is written back to the state table by the `PrepaintPass`
    /// overload of `resolvedOffset`, and that write-back is what bounds the
    /// stored value.** Clamping the read alone leaves the stored number free to
    /// run away — see that overload.
    static func clamp(offset: Double, content: Double, viewport: Double) -> Double {
        min(max(0, offset), max(0, content - viewport))
    }

    /// A size's length along the scroll axis.
    func extent(_ size: Size<Pixels>) -> Double {
        Double(axis == .vertical ? size.height.value : size.width.value)
    }

    /// A scalar along the scroll axis as a translation.
    func delta(_ value: Double) -> Point<Pixels> {
        axis == .vertical ? Point(x: Pixels(0), y: Pixels(Float(value)))
                          : Point(x: Pixels(Float(value)), y: Pixels(0))
    }

    // Two overloads, one per pass type, rather than one function taking a
    // shared protocol. `PrepaintPass` and `PaintPass` have no common protocol
    // to write this against — `Passes.swift` records why: a `StatefulPass`
    // requirement would force `frame` public on both, and `PaintPass.frame`
    // leaking makes `scaleFactor` reachable through it, which is exactly the
    // double-application hazard `PaintPass` is built to keep out of element
    // code. Three lines duplicated is cheaper than that leak. The fold took
    // this from four copies to two, not to one, for that reason.
    ///
    /// **The prepaint overload writes the clamped value BACK, and that line is
    /// what keeps scrolling responsive rather than being a tidy-up.**
    /// `Window.applyScroll` writes `offset -= delta` with no bound — it has the
    /// scroll region's rect but not the content node's size, and no layout at
    /// all for the frame it is about to cause. Reading through a clamp while
    /// leaving the stored number alone therefore lets a gesture against either
    /// end bank an arbitrarily large excess *invisibly*: the view sits at the
    /// end looking correct, and every event in the opposite direction then
    /// spends itself paying that excess down instead of moving anything.
    /// Measured on a 200pt content in a 120pt viewport (80pt of travel), one
    /// frame per event, before the write-back existed: twenty -37 events stored
    /// **740**, and seventeen of the twenty events that followed in the
    /// opposite direction moved the view by nothing. How long that dead band
    /// lasted was a function of how far past the end the user had already
    /// scrolled, which is why it was reported as scrolling that worked and then
    /// intermittently stopped.
    ///
    /// The bound this buys is "one frame's worth of events", not zero: events
    /// arriving between two frames still accumulate unclamped, and `Window`
    /// dirties the window on every one of them, so the next frame normalises
    /// them together. That is the tightest bound available from here — the
    /// ceiling does not exist until layout has run. Pinned for `ScrollView` by
    /// `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`
    /// (`ScrollRoutingTests.swift`) and for `ProposalScrollView` by
    /// `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack`
    /// (`LoweringScrollTests.swift`); one implementation now, so **both** of
    /// them redden when the write-back goes.
    @MainActor
    func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        contentNode: LayoutNodeID, pass: PrepaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: contentNode).size)
        var resolved: Double = 0
        pass.withState(id, initial: ScrollState()) {
            $0.offset = Self.clamp(offset: $0.offset, content: content, viewport: viewport)
            resolved = $0.offset
            // The half `ScrollState.viewportExtent`'s own doc names: this is
            // the only writer, and it is what lets NEXT frame's `requestLayout`
            // read a viewport extent at all.
            $0.viewportExtent = viewport
        }
        return resolved
    }

    /// **This one clamps on read and does NOT write back, unlike the prepaint
    /// overload above — measured, not assumed.** `Frame.render` runs prepaint
    /// before paint unconditionally, and both scrollers' `prepaint` call their
    /// overload unconditionally, so by the time this runs the stored value has
    /// already been normalised against this same layout and a second write
    /// could only store the number it just read. Adding one back reddened
    /// nothing on a 498-test suite, which is redundancy rather than a coverage
    /// gap: the mutant provably cannot behave differently. The read clamp
    /// itself stays, so this phase is correct on its own terms rather than by
    /// trusting the phase before it.
    @MainActor
    func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        contentNode: LayoutNodeID, pass: PaintPass) -> Double {
        let viewport = extent(bounds.size)
        let content = extent(pass.bounds(of: contentNode).size)
        var stored: Double = 0
        pass.withState(id, initial: ScrollState()) { stored = $0.offset }
        return Self.clamp(offset: stored, content: content, viewport: viewport)
    }

    /// The fading overlay scroll indicator: a thumb sized and positioned to
    /// the viewport/content ratio, opaque for 0.6s after a scroll and then
    /// ramped linearly to invisible over the next 0.4s.
    ///
    /// **A hand-rolled ramp, not an easing curve.** `PaintPass.timestamp` and
    /// `requestAnotherFrame()` are borrowed M4 primitives — inputs to
    /// animation, not an animation system — so this is the one place in either
    /// scroller that computes a value that changes over time, and it does so
    /// with a `let` and an `if`.
    @MainActor
    func paintIndicator(_ id: GlobalElementID, bounds: Bounds<Pixels>, offset: Double,
                        contentNode: LayoutNodeID, pass: inout PaintPass) {
        // Checked first and unconditionally: `.hidden` must cost nothing at
        // all, not paint a suppressed-alpha rect, and must never reach
        // `requestAnotherFrame()` below — a hidden indicator that kept
        // asking would hold the display link awake forever, exactly the
        // failure `guard alpha > 0` exists to prevent for a faded one.
        guard indicatorVisibility != .hidden else { return }
        let content = extent(pass.bounds(of: contentNode).size)
        let viewport = extent(bounds.size)
        let scrollable = max(0, content - viewport)
        // Nothing to scroll: no thumb, and — just as important for spec
        // §4.4 — no `requestAnotherFrame()` either. A scroller whose content
        // fits must cost exactly as little as a `Box`.
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
        // Being outside the caller's `clipped(to:offsetBy:)` block is what stops
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
    func indicatorBounds(bounds: Bounds<Pixels>, thumb: Double,
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
}
