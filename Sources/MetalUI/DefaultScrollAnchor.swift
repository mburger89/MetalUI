import MetalUICore
import MetalUILayout

// `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` (Alloy gap G6, rulings `DSA-A`...`DSA-H`; probe
// `docs/probes/swiftui-default-scroll-anchor.swift`).
//
// **Reading.** The anchor is decided in the layout and prepaint of the scroller it is declared on, never from a
// phase-time `@Observable` write. A scroller that *follows its end* publishes that in its `ScrollContext`
// (`followsEnd`), so a lazy container or `List` inside windows around the content's END in the very frame the
// content grew; prepaint then places the offset at the end of the content it actually laid out
// (`ScrollChrome.resolvedOffset`, the same clamp write-back the offset has always had). The wheel is the only
// thing that releases the pin: a stored offset that is not at last frame's end when the next prepaint reads it.

/// The part of a scroll view that a default scroll anchor applies to (SwiftUI's `ScrollAnchorRole`).
///
/// SwiftUI's three roles, each measured (probe `swiftui-default-scroll-anchor.swift`, arms `R1`-`R6`, `W1`-`W5`,
/// `S1`-`S3`):
/// - ``initialOffset``: the offset the scroller starts at. With a trailing-edge anchor it also keeps the content's
///   end in view as the content grows, until the user scrolls away (and does not re-engage when they return).
/// - ``sizeChanges``: not an initial offset; whenever the content's size changes and the scroller is at the
///   trailing edge of scrollable content, it stays there, and re-engages when the user scrolls back.
/// - ``alignment``: content shorter than the viewport sits at the anchor instead of the leading edge, and keeps
///   to the trailing edge when it then grows past the viewport.
public struct ScrollAnchorRole: Sendable, Hashable {
    enum Kind: UInt8, Sendable { case initialOffset, sizeChanges, alignment }
    let kind: Kind

    /// The role of the scroll view's initial offset.
    public static let initialOffset = ScrollAnchorRole(kind: .initialOffset)
    /// The role of how the scroll view keeps its position when its content's or viewport's size changes.
    public static let sizeChanges = ScrollAnchorRole(kind: .sizeChanges)
    /// The role of how content smaller than the viewport is aligned in it.
    public static let alignment = ScrollAnchorRole(kind: .alignment)
}

/// A scroller's declared anchors: one general one and one per role; a role's own beats the general one, and
/// among equals the first declared (the innermost, SwiftUI's environment order, probe `O1`-`O6`) wins.
struct DefaultScrollAnchors: Sendable, Equatable {
    private(set) var general: UnitPoint?
    private(set) var initial: UnitPoint?
    private(set) var sizeChanges: UnitPoint?
    private(set) var alignment: UnitPoint?

    /// Declares `anchor` for `role` (`nil` role: every role). A `nil` anchor declares nothing (probe `O3`, `O4`).
    mutating func declare(_ anchor: UnitPoint?, for role: ScrollAnchorRole?) {
        guard let anchor else { return }
        switch role?.kind {
        case nil: if general == nil { general = anchor }
        case .initialOffset?: if initial == nil { initial = anchor }
        case .sizeChanges?: if sizeChanges == nil { sizeChanges = anchor }
        case .alignment?: if alignment == nil { alignment = anchor }
        }
    }

    var isEmpty: Bool { general == nil && initial == nil && sizeChanges == nil && alignment == nil }

    /// Each role's anchor along `axis`: the fraction of the free extent that lies before the content.
    func initialFraction(_ axis: ScrollAxis) -> Double? { Self.along(initial ?? general, axis) }
    func sizeChangesFraction(_ axis: ScrollAxis) -> Double? { Self.along(sizeChanges ?? general, axis) }
    func alignmentFraction(_ axis: ScrollAxis) -> Double? { Self.along(alignment ?? general, axis) }

    private static func along(_ point: UnitPoint?, _ axis: ScrollAxis) -> Double? {
        guard let point else { return nil }
        return min(max(0, axis == .vertical ? point.y : point.x), 1)
    }
}

/// What a scroller with a default anchor remembers between frames (`ScrollState.anchor`).
struct ScrollAnchorMemory: Sendable, Equatable {
    /// The initial offset has been applied (the first prepaint with a viewport and some content).
    var initialDone = false
    /// Following the end until the user leaves it (set by the initial and alignment roles).
    var pinned = false
    /// Last prepaint's end position and whether the content then overflowed the viewport.
    var lastEnd = 0.0
    var lastScrollable = false
    /// Whether last prepaint put the offset at the end (pinned, or the size-changes role armed).
    var following = false
    /// The content extent last prepaint saw and the prepaints that have placed a non-end initial offset: a
    /// lazy container's first extent is an estimate, so the placement repeats until the extent settles (`DSA-B`).
    var lastContent = -1.0
    var initialFrames = 0
}

extension ScrollChrome {
    /// How far past `lastEnd` a stored offset may be, or short of it, and still be "at the end": a rubber-band
    /// overshoot, a float residue (probe `W1`: a wheel to the bottom reads 1-2 points past it).
    static let endTolerance = 1.0

    /// Whether this scroller's content should be windowed around its END this layout (`ScrollContext.followsEnd`).
    /// `raw` is the stored offset a wheel may have moved since the last prepaint.
    func layoutFollowsEnd(_ state: ScrollState, raw: Double) -> Bool {
        layoutFollowsEnd(memory: state.anchor, raw: raw)
    }

    /// `layoutFollowsEnd` over one axis's memory (`XS-J`): the primary's `state.anchor` or the cross slot's, one rule.
    func layoutFollowsEnd(memory: ScrollAnchorMemory, raw: Double) -> Bool {
        guard !anchors.isEmpty else { return false }
        if !memory.initialDone {
            return (anchors.initialFraction(axis) ?? 0) >= 1 || (anchors.alignmentFraction(axis) ?? 0) >= 1
        }
        let atEnd = !memory.lastScrollable || raw >= memory.lastEnd - Self.endTolerance
        if memory.pinned { return atEnd }
        return (anchors.sizeChangesFraction(axis) ?? 0) >= 1 && memory.lastScrollable && atEnd
    }

    /// The offset aligned content shorter than the viewport takes (negative: the content starts inside the
    /// viewport), or `nil` when no alignment applies.
    func alignedOffset(content: Double, viewport: Double) -> Double? {
        guard content < viewport, let fraction = anchors.alignmentFraction(axis) else { return nil }
        return -(viewport - content) * fraction
    }

    /// `clamp(offset:content:viewport:)` with the alignment role's negative offset for short content.
    func clampOffset(_ offset: Double, content: Double, viewport: Double) -> Double {
        alignedOffset(content: content, viewport: viewport)
            ?? Self.clamp(offset: offset, content: content, viewport: viewport)
    }

    /// The anchored offset of one prepaint: the initial placement, the release on departure, the pin at the end
    /// and the alignment; updates `memory`. `offset` is the stored one after a glide step, unclamped.
    func anchoredOffset(_ offset: Double, content: Double, viewport: Double, memory: inout ScrollAnchorMemory) -> Double {
        var offset = offset
        let scrollable = content > viewport
        let end = max(0, content - viewport)
        var armed = false
        if !memory.initialDone {
            if viewport > 0 && content > 0 {
                let fraction = anchors.initialFraction(axis)
                if let fraction {
                    offset = scrollable ? fraction * end : 0
                    if fraction >= 1 { memory.pinned = true }
                }
                // An end anchor is followed from here on, so one placement is enough; any other waits for the
                // extent to stop moving (a lazy container's first extent is an estimate), at most 6 prepaints.
                memory.initialFrames += 1
                if (fraction ?? 0) >= 1 || fraction == nil || content == memory.lastContent || memory.initialFrames >= 6 {
                    memory.initialDone = true
                }
            }
        } else {
            let atEnd = !memory.lastScrollable || offset >= memory.lastEnd - Self.endTolerance
            if memory.pinned && !atEnd { memory.pinned = false }
            armed = (anchors.sizeChangesFraction(axis) ?? 0) >= 1 && memory.lastScrollable && atEnd
        }
        if let aligned = alignedOffset(content: content, viewport: viewport) {
            if (anchors.alignmentFraction(axis) ?? 0) >= 1 { memory.pinned = true }
            offset = aligned
        } else if scrollable && (memory.pinned || armed) {
            offset = end
        }
        memory.following = scrollable && (memory.pinned || armed)
        memory.lastContent = content
        memory.lastScrollable = scrollable
        memory.lastEnd = scrollable ? end : 0
        return offset
    }
}

extension ScrollView {
    /// SwiftUI's `defaultScrollAnchor(_:)`: the part of the content the scroll view shows by default, for every
    /// ``ScrollAnchorRole`` (probe `swiftui-default-scroll-anchor.swift`).
    ///
    /// With `.bottom` (a vertical scroller) the content starts scrolled to its end, content shorter than the
    /// viewport sits at the bottom, and **while the scroller is at the end the end stays in view as content is
    /// added or resized**, lazy windows included; a scroll away (wheel, or a `scrollTo` elsewhere) releases it and
    /// scrolling back to the end re-engages it. Any other anchor places the scroller at that fraction of the
    /// content once, at its first layout. An anchor reads its component along the scroll axis, so `.trailing` is
    /// the end of a horizontal scroller and `.leading` the middle of a vertical one.
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack { ForEach(blocks) { BlockView($0) } }
    /// }
    /// .defaultScrollAnchor(.bottom)   // a transcript: starts at, and follows, the newest block
    /// ```
    ///
    /// Declared on the scroll view itself, not on an ancestor (divergence 210); the first call for a role wins and
    /// `nil` declares nothing.
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> Self {
        var copy = self
        copy.defaultAnchors.declare(anchor, for: nil)
        return copy
    }

    /// SwiftUI's `defaultScrollAnchor(_:for:)`: the anchor for one ``ScrollAnchorRole`` only; a role's own anchor
    /// beats the one for every role.
    ///
    /// `.defaultScrollAnchor(.bottom, for: .sizeChanges)` alone keeps an already-bottomed scroller at the bottom as
    /// its content grows, without starting there (re-engaging whenever the user scrolls back to the end);
    /// `for: .initialOffset` starts there and follows until the first scroll away.
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> Self {
        var copy = self
        copy.defaultAnchors.declare(anchor, for: role)
        return copy
    }
}

extension ProposalScrollView {
    /// ``ScrollView/defaultScrollAnchor(_:)`` for a scroller over proposal content.
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> Self {
        var copy = self
        copy.defaultAnchors.declare(anchor, for: nil)
        return copy
    }

    /// ``ScrollView/defaultScrollAnchor(_:for:)`` for a scroller over proposal content.
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> Self {
        var copy = self
        copy.defaultAnchors.declare(anchor, for: role)
        return copy
    }
}
