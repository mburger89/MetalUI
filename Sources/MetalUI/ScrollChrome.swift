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
/// rather than one; and `ScrollContext` publication is each scroller's own
/// `requestLayout` (ruling `LR-BF`; since `PE-V` a `ProposalScrollView`
/// publishes one too, because `PE-B` lets a `List` be its content).
struct ScrollChrome {
    var axis: ScrollAxis
    var cornerRadius: Pixels
    var indicatorVisibility: ScrollIndicatorVisibility
    /// Whether the content is laid out right-to-left along this scroller's (horizontal) axis (`LD-E`): the
    /// offset is then **logical**, the distance from the leading (right) edge, so a larger offset moves the
    /// content to the right. Set by the scroller from the environment at its site; vertical never.
    var mirrored = false
    /// The scroller's `defaultScrollAnchor` declarations (`DSA-A`); empty for a scroller with none.
    var anchors = DefaultScrollAnchors()
    /// Whether the scroller ALSO scrolls horizontally (`XS-D`): `axis` is then `.vertical`, the primary slot of `ScrollState`, and
    /// the horizontal axis lives in `ScrollState.cross`. `false` for every one-axis scroller, whose paths do not read it.
    var crossAxis = false
    /// `mirrored` for the horizontal (cross) axis of a two-axis scroller (`LD-E`); `mirrored` itself stays the primary's.
    var crossMirrored = false
    /// The scroll-content margins along this axis, logical (`CMG-D`); zero for a scroller with none.
    var contentInset: (start: Double, end: Double) = (0, 0)
    /// The scroll-indicator margins along this axis (`CMG-C`): the thumb's track is the viewport minus them.
    var indicatorInset: (start: Double, end: Double) = (0, 0)
    /// `contentInset` and `indicatorInset` of the horizontal axis of a two-axis scroller.
    var crossContentInset: (start: Double, end: Double) = (0, 0)
    var crossIndicatorInset: (start: Double, end: Double) = (0, 0)

    /// Reads the environment's content margins (`CMG-A`): each axis' start and end insets, for content and indicators.
    mutating func resolveMargins(_ margins: ContentMargins) {
        contentInset = margins.scrollContent.along(axis)
        indicatorInset = margins.scrollIndicators.along(axis)
        if crossAxis {
            crossContentInset = margins.scrollContent.along(.horizontal)
            crossIndicatorInset = margins.scrollIndicators.along(.horizontal)
        }
    }

    /// Sets both mirrored flags from the environment (`LD-E`): the horizontal axis, whichever slot it is in, lays out right-to-left.
    mutating func resolveLayoutDirection(rightToLeft: Bool) {
        mirrored = axis == .horizontal && rightToLeft
        crossMirrored = crossAxis && rightToLeft
    }

    /// The horizontal slot of the `ScrollContext` a two-axis scroller publishes (`XS-H`): the glide-aware raw offset, last frame's
    /// viewport extent and whether the axis follows its end (`XS-J`, per axis).
    func crossContext(_ state: ScrollState, now: Double) -> ScrollAxisContext {
        let raw = Self.currentCrossOffset(state, now: now)
        return ScrollAxisContext(offset: raw, viewportExtent: state.cross.viewportExtent,
                                 followsEnd: crossChrome.layoutFollowsEnd(memory: state.cross.anchor, raw: raw))
    }

    /// The horizontal slot of the `ScrollerFrame` a two-axis scroller prepaints its content in (`XS-H`).
    func crossFrame(offset: Double, bounds: Bounds<Pixels>, contentSize: Size<Pixels>) -> ScrollerFrame.Cross {
        let horizontal = crossChrome
        return ScrollerFrame.Cross(offset: offset, contentExtent: horizontal.extent(contentSize), mirrored: crossMirrored,
                                   inset: crossContentInset)
    }

    /// The horizontal axis of a two-axis scroller as a one-axis chrome (`XS-D`): the SAME code reads its slot, so the cross axis
    /// has no copy of the clamp, the anchor or the glide to drift from the primary's.
    var crossChrome: ScrollChrome {
        var chrome = self
        chrome.axis = .horizontal
        chrome.crossAxis = false
        chrome.mirrored = crossMirrored
        chrome.crossMirrored = false
        chrome.contentInset = crossContentInset
        chrome.indicatorInset = crossIndicatorInset
        return chrome
    }

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

    /// The offsets after a wheel event of `delta` (`CV-O`), per axis, natural scrolling (content follows
    /// the fingers, so the offset falls), each clamped to `0...maximum`. The one arithmetic of a scroller
    /// that owns its offsets: `TextEditor`'s vertical arm and a `CodeView`'s two axes.
    static func wheelOffset(x: Double, y: Double, delta: Point<Pixels>,
                            maximum: (x: Double, y: Double)) -> (x: Double, y: Double) {
        (min(max(x - Double(delta.x.value), 0), maximum.x), min(max(y - Double(delta.y.value), 0), maximum.y))
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

    /// The translation a scroller applies for the logical `offset` (`LD-E`): `delta(-offset)`, and
    /// `delta(+offset)` when mirrored, because the content starts at the right edge and a larger offset
    /// reveals what is to its left.
    func translation(offset: Double) -> Point<Pixels> { delta(mirrored ? offset : -offset) }

    /// The translation of a two-axis scroller (`XS-D`): the primary's plus the horizontal axis's, each from the one-axis rule.
    func translation(offset: Double, cross: Double) -> Point<Pixels> {
        let primary = translation(offset: offset)
        guard crossAxis else { return primary }
        let horizontal = crossChrome.translation(offset: cross)
        return Point(x: Pixels(primary.x.value + horizontal.x.value), y: Pixels(primary.y.value + horizontal.y.value))
    }

    /// Whether two stored scroll states are the same value (`RW-H`): the compared write's `unchanged:`.
    static func sameScrollState(_ a: ScrollState, _ b: ScrollState) -> Bool {
        a.offset == b.offset && a.viewportExtent == b.viewportExtent && a.lastScrollTime == b.lastScrollTime
            && a.glide == b.glide && a.anchor == b.anchor && a.cross == b.cross
    }

    /// The offset a phase of the frame stamped `now` sees (`SP-F`): the stored one, or the animated value of
    /// a `scrollTo` made under `withAnimation`. The glide's first frame is the frame after the one that
    /// resolved the request, so a landed glide equals the stored target.
    static func currentOffset(_ state: ScrollState, now: Double) -> Double {
        state.glide?.value(at: now).offset ?? state.offset
    }

    /// The horizontal axis's offset of a two-axis scroller at `now` (`XS-C`): `currentOffset` for the cross slot.
    static func currentCrossOffset(_ state: ScrollState, now: Double) -> Double {
        state.cross.glide?.value(at: now).offset ?? state.cross.offset
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
        resolvedOffsets(id, bounds: bounds, contentNode: contentNode, pass: pass).primary
    }

    /// Both axes' offsets (`XS-D`): the primary's, and the horizontal axis's when `crossAxis` is set (0 otherwise). **One core
    /// resolves each slot** (`resolveSlot`), so the cross axis gets the glide, the anchor, the clamp and the write-back the
    /// primary has always had, and a copy of that code cannot drift from it.
    @MainActor
    func resolvedOffsets(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                         contentNode: LayoutNodeID, pass: PrepaintPass) -> (primary: Double, cross: Double) {
        let contentSize = pass.bounds(of: contentNode).size
        let viewport = extent(bounds.size)
        let content = extent(contentSize)
        let horizontal = crossChrome
        let crossViewport = crossAxis ? horizontal.extent(bounds.size) : 0
        let crossContent = crossAxis ? horizontal.extent(contentSize) : 0
        var resolved: Double = 0, crossResolved: Double = 0
        let now = pass.frame.timestamp
        var gliding = false
        // A compared write (`RW-H`): a settled scroller re-stores what is there, which bumps no version and taints nothing.
        pass.withState(id, initial: ScrollState(), unchanged: Self.sameScrollState) {
            gliding = resolveSlot(offset: &$0.offset, glide: &$0.glide, anchor: &$0.anchor, viewportExtent: &$0.viewportExtent,
                                  content: content, viewport: viewport, now: now)
            resolved = $0.offset
            if crossAxis {
                if horizontal.resolveSlot(offset: &$0.cross.offset, glide: &$0.cross.glide, anchor: &$0.cross.anchor,
                                          viewportExtent: &$0.cross.viewportExtent, content: crossContent,
                                          viewport: crossViewport, now: now) { gliding = true }
                crossResolved = $0.cross.offset
            }
        }
        if gliding { pass.frame.noteActiveAnimation() }   // keeps the display link running, never dirties
        return (resolved, crossResolved)
    }

    /// One axis's resolution of one prepaint, over the fields of its slot (`XS-D`): the glide step (`SP-F`), the default anchor
    /// (`DSA-D`), the clamp, and the viewport extent `requestLayout` reads back next frame. Returns whether a glide is still
    /// running. `self` is the chrome of THAT axis (`crossChrome` for the horizontal slot of a two-axis scroller).
    func resolveSlot(offset: inout Double, glide: inout ScrollGlide?, anchor: inout ScrollAnchorMemory,
                     viewportExtent: inout Double, content: Double, viewport: Double, now: Double) -> Bool {
        var gliding = false
        if let running = glide {   // `SP-F`: the animated value is the stored one, and a landed glide ends
            let step = running.value(at: now)
            offset = step.offset
            if step.finished { glide = nil } else { gliding = true }
        }
        if !anchors.isEmpty {   // `DSA-D`: the anchor decides the offset the clamp then bounds
            offset = anchoredOffset(offset, content: content, viewport: viewport, memory: &anchor)
        }
        offset = clampOffset(offset, content: content, viewport: viewport)
        // The half `ScrollState.viewportExtent`'s own doc names: this is
        // the only writer, and it is what lets NEXT frame's `requestLayout`
        // read a viewport extent at all.
        viewportExtent = viewport
        return gliding
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
        let stored = Self.currentOffset(pass.readState(id, initial: ScrollState()), now: pass.frame.timestamp)   // `RW-H`
        return clampOffset(stored, content: content, viewport: viewport)
    }

    /// Both axes' offsets for paint (`XS-D`): the primary's as above, and the horizontal axis's, clamped on read the same way.
    @MainActor
    func resolvedOffsets(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                         contentNode: LayoutNodeID, pass: PaintPass) -> (primary: Double, cross: Double) {
        let primary = resolvedOffset(id, bounds: bounds, contentNode: contentNode, pass: pass)
        guard crossAxis else { return (primary, 0) }
        let horizontal = crossChrome
        let state = pass.readState(id, initial: ScrollState())   // `RW-H`
        let contentSize = pass.bounds(of: contentNode).size
        let stored = Self.currentCrossOffset(state, now: pass.frame.timestamp)
        return (primary, horizontal.clampOffset(stored, content: horizontal.extent(contentSize),
                                                viewport: horizontal.extent(bounds.size)))
    }

    /// The fading overlay scroll indicator: a thumb sized and positioned to
    /// the viewport/content ratio, opaque for 0.6s after a scroll and then
    /// ramped linearly to invisible over the next 0.4s.
    ///
    /// **A hand-rolled ramp, not an easing curve.** `PaintPass.timestamp` is a
    /// borrowed M4 primitive — an input to animation, not an animation system —
    /// so this is the one place in either scroller that computes a value that
    /// changes over time, and it does so with a `let` and an `if`.
    ///
    /// **The fade is a live animation, so it raises `noteActiveAnimation()`,
    /// never `requestAnotherFrame()`** (ruling `HT-Z` item 1, CLAUDE.md
    /// "Always"): it keeps the display link drawing without marking the window
    /// dirty, because nothing changed — only the clock moves it. Dirtying, as
    /// it did until `HT-Z`, made a frozen clock's window dirty forever, so
    /// `TestWindow.runUntilIdle()` threw `.notIdle` after every scroll.
    @MainActor
    func paintIndicator(_ id: GlobalElementID, bounds: Bounds<Pixels>, offset: Double, cross: Double = 0,
                        contentNode: LayoutNodeID, pass: inout PaintPass) {
        let size = pass.bounds(of: contentNode).size
        let lastScroll = pass.readState(id, initial: ScrollState()).lastScrollTime   // `RW-H`
        guard crossAxis else {
            paintIndicator(bounds: bounds, offset: offset, content: extent(size), viewport: extent(bounds.size),
                           lastScroll: lastScroll, pass: &pass)
            return
        }
        // `XS-D`: one indicator per axis from the one numeric painter; where both thumbs show, each track stops short of the
        // shared corner so they do not meet. One stamp lights both (A9 is unmeasured: a stated assumption).
        let horizontal = crossChrome
        let both = extent(size) > extent(bounds.size) && horizontal.extent(size) > horizontal.extent(bounds.size)
        let inset = both ? Self.cornerInset : 0
        paintIndicator(bounds: bounds, offset: offset, content: extent(size), viewport: extent(bounds.size),
                       lastScroll: lastScroll, trackInset: inset, pass: &pass)
        horizontal.paintIndicator(bounds: bounds, offset: cross, content: horizontal.extent(size),
                                  viewport: horizontal.extent(bounds.size), lastScroll: lastScroll, trackInset: inset,
                                  pass: &pass)
    }

    /// How far a two-axis scroller's tracks stop short of the corner they share, in points (`XS-D`).
    static let cornerInset = 8.0

    /// The same indicator from numbers instead of a content node and a `ScrollState` (`CV-O`): the content
    /// and viewport extents along the axis, the scroll offset, and when the wheel last moved the view. What
    /// a scroller that owns its offset (a `CodeView`, later a two-axis `ScrollView`) paints with; each axis
    /// is one call, so two axes are two.
    @MainActor
    func paintIndicator(bounds: Bounds<Pixels>, offset: Double, content: Double, viewport: Double,
                        lastScroll: Double, trackInset: Double = 0, pass: inout PaintPass) {
        // Checked first and unconditionally: `.hidden` must cost nothing at
        // all, not paint a suppressed-alpha rect, and must never reach
        // `noteActiveAnimation()` below — a hidden indicator that kept
        // asking would hold the display link awake forever, exactly the
        // failure `guard alpha > 0` exists to prevent for a faded one.
        //
        // `.never` is `.hidden` and `.visible` is `.automatic` (ruling `DD-H`,
        // probe I1–I5: SwiftUI's macOS answers on overlay scrollers).
        switch indicatorVisibility {
        case .hidden, .never: return
        case .automatic, .visible: break
        }
        let scrollable = max(0, content - viewport)
        // Nothing to scroll: no thumb, and — just as important for spec
        // §4.4 — no `noteActiveAnimation()` either. A scroller whose content
        // fits must cost exactly as little as a `Box`.
        guard scrollable > 0 else { return }

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
        pass.frame.noteActiveAnimation()   // `HT-Z` item 1: a fade, not a change

        // `XS-D`: shorter by the corner it shares with the other axis's thumb; `CMG-C`: and by the indicator margins
        let track = max(0, viewport - trackInset - indicatorInset.start - indicatorInset.end)
        let thumb = max(20, track * (viewport / content))
        let travel = (offset / scrollable) * (track - thumb) + indicatorInset.start

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
        // `LD-E`: a mirrored horizontal indicator travels from the right edge.
        let startX = mirrored
            ? bounds.origin.x.value + bounds.size.width.value - Float(travel) - Float(thumb)
            : bounds.origin.x.value + Float(travel)
        switch axis {
        case .vertical:
            return Bounds(
                origin: Point(x: Pixels(bounds.origin.x.value + bounds.size.width.value - 5),
                              y: Pixels(bounds.origin.y.value + Float(travel))),
                size: Size(width: Pixels(3), height: Pixels(Float(thumb))))
        case .horizontal:
            return Bounds(
                origin: Point(x: Pixels(startX),
                              y: Pixels(bounds.origin.y.value + bounds.size.height.value - 5)),
                size: Size(width: Pixels(Float(thumb)), height: Pixels(3)))
        }
    }
}

/// What a scroller tells the content it is prepainting (ruling `DD-F` item 2):
/// pushed by `ScrollView` and `ProposalScrollView` around their content's
/// prepaint, read by `List` (`Frame.activeScrollerFrame`).
///
/// Every rect is **layout space** — `PrepaintPass.bounds(of:)`'s untranslated
/// geometry — so a descendant's own `bounds` minus `contentOrigin` is its
/// position within the scroller's content, whatever the offset.
struct ScrollerFrame {
    /// The scroller's own element id.
    var scrollerID: GlobalElementID
    var axis: ScrollAxis
    /// The content node's origin, layout space.
    var contentOrigin: Point<Pixels>
    /// The viewport's bounds this frame, layout space.
    var viewport: Bounds<Pixels>
    /// The offset `ScrollChrome.resolvedOffset` resolved (clamped) this frame.
    var offset: Double
    /// The content's extent on the scrolling axis — what a `scrollTo`
    /// resolution clamps against (`DD-G` item 2, T7).
    var contentExtent: Double
    /// Whether this scroller carries a `scrollPosition(id:)` binding, so targets inside it note their extents
    /// (`SP-B`).
    var tracksPosition = false
    /// Whether the scroller lays its content out right-to-left (`LD-E`): `offset` is the distance from the
    /// content's right edge and `logicalStart(of:)` measures from there.
    var mirrored = false
    /// The horizontal slot of a two-axis scroller (`XS-H`); `nil` for a one-axis one. `axis`, `offset`, `contentExtent` and
    /// `mirrored` above are the primary axis, vertical for a two-axis scroller.
    var cross: Cross?
    /// Whether this frame IS the horizontal slot of a two-axis scroller, from `along(.horizontal)`: what a write to the
    /// scroller's state (`scrollTo`, an anchor adjustment) uses to pick the slot.
    var isCross = false
    /// The scroll-content margins along `axis` (`CMG-D`): `scrollTo` and the reported position treat the visible
    /// region as the viewport minus them.
    var inset: (start: Double, end: Double) = (0, 0)

    /// What a two-axis scroller's horizontal axis adds to its frame.
    struct Cross {
        var offset: Double
        var contentExtent: Double
        var mirrored: Bool
        var inset: (start: Double, end: Double) = (0, 0)
    }

    /// The frame along `other`, or `nil` when the scroller does not scroll that way (`XS-H`). Along its own axis it is `self`;
    /// along `.horizontal` a two-axis scroller answers a one-axis horizontal frame over the cross slot, so every reader that
    /// asks "my axis" (`LazyHStack`, `scrollTo`'s cross resolution) reads the right numbers and nothing else.
    func along(_ other: ScrollAxis) -> ScrollerFrame? {
        if other == axis { return self }
        guard other == .horizontal, let cross else { return nil }
        var frame = self
        frame.axis = .horizontal
        frame.offset = cross.offset
        frame.contentExtent = cross.contentExtent
        frame.mirrored = cross.mirrored
        frame.inset = cross.inset
        frame.cross = nil
        frame.isCross = true
        return frame
    }

    /// A layout-space rect's start along the scroller's axis, from the content's **leading** edge: from
    /// `contentOrigin` normally, from the content's right edge when mirrored (`LD-E`). What every
    /// `scrollTo` target, position note and lazy window measures with.
    func logicalStart(of rect: Bounds<Pixels>) -> Double {
        if axis == .vertical { return Double(rect.origin.y.value - contentOrigin.y.value) }
        if mirrored {
            return Double(contentOrigin.x.value) + contentExtent - Double(rect.origin.x.value + rect.size.width.value)
        }
        return Double(rect.origin.x.value - contentOrigin.x.value)
    }

    /// The viewport's extent on the scrolling axis.
    var viewportExtent: Double {
        Double(axis == .vertical ? viewport.size.height.value : viewport.size.width.value)
    }
}
