import MetalUICore

/// Where a content margin applies — SwiftUI's `ContentMarginPlacement` (`CMG-A`).
///
/// `.scrollContent` insets the scrolled content inside the scroll area (the content still draws and scrolls under the
/// margin region: nothing clips there); `.scrollIndicators` insets only the scroll indicators; `.automatic` is
/// both, which is what a scroll view does with a margin it was not told a placement for (`CMG-A`).
public struct ContentMarginPlacement: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case automatic, scrollContent, scrollIndicators }
    let kind: Kind

    /// The automatic placement: a scroll view applies it to its content and its indicators.
    public static let automatic = ContentMarginPlacement(kind: .automatic)
    /// The scroll content placement: the content is inset, the indicators stay at the edge.
    public static let scrollContent = ContentMarginPlacement(kind: .scrollContent)
    /// The scroll indicators placement: only the indicators are inset.
    public static let scrollIndicators = ContentMarginPlacement(kind: .scrollIndicators)
}

/// What `contentMargins` writes into the environment: one inset per edge for each placement (`CMG-A`). Internal.
struct ContentMargins: Equatable, Sendable {
    var scrollContent = EdgeInsets()
    var scrollIndicators = EdgeInsets()

    /// Whether every inset of both placements is zero (the unset state: a scroller then does what it always did).
    var isZero: Bool { scrollContent == EdgeInsets() && scrollIndicators == EdgeInsets() }

    /// Writes `insets` on the edges in `edges` for `placement`; the other edges keep what they hold (`CMG-B`).
    mutating func write(_ edges: Edge.Set, _ insets: EdgeInsets, for placement: ContentMarginPlacement) {
        func merged(_ old: EdgeInsets) -> EdgeInsets {
            var new = old
            if edges.contains(.top) { new.top = insets.top }
            if edges.contains(.leading) { new.leading = insets.leading }
            if edges.contains(.bottom) { new.bottom = insets.bottom }
            if edges.contains(.trailing) { new.trailing = insets.trailing }
            return new
        }
        switch placement.kind {
        case .automatic: scrollContent = merged(scrollContent); scrollIndicators = merged(scrollIndicators)
        case .scrollContent: scrollContent = merged(scrollContent)
        case .scrollIndicators: scrollIndicators = merged(scrollIndicators)
        }
    }
}

extension EdgeInsets {
    /// The start and end insets along `axis`, logical (leading-based) along a horizontal one.
    func along(_ axis: ScrollAxis) -> (start: Double, end: Double) {
        axis == .vertical ? (Double(top.value), Double(bottom.value)) : (Double(leading.value), Double(trailing.value))
    }
}

extension ElementGroup {
    /// Insets the content of the scrollable views below, and their indicators, by `insets` on `edges` —
    /// SwiftUI's `contentMargins(_:_:for:)` (macOS 14, `CMG-A`). A `ScrollView`, a `ProposalScrollView`, a `List`
    /// (inside its scroller) and a `CodeView` read it: at offset 0 the first content starts at the leading margin, at the
    /// end the last content ends before the trailing one, and the content scrolls and draws **under** the margin
    /// region (a floating bar over a scroller). Margins add to the content's own padding. `scrollTo`, a
    /// `scrollPosition(id:)` anchor and a `defaultScrollAnchor` measure against the viewport minus the margins
    /// (`CMG-D`). A modifier of a placement overrides one above it, per edge (`CMG-B`). No safe area is involved
    /// (`PB-A`).
    public func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets,
                               for placement: ContentMarginPlacement = .automatic) -> EnvironmentScope<Self> {
        transformEnvironment(\.contentMargins) { $0.write(edges, insets, for: placement) }
    }

    /// The same `length` on each edge in `edges` for `placement`, SwiftUI's `contentMargins(_:_:for:)` with a length;
    /// `nil` writes zero there (SwiftUI's "the default": no safe area exists to fall back on, `CMG-B`).
    public func contentMargins(_ edges: Edge.Set = .all, _ length: Pixels?,
                               for placement: ContentMarginPlacement = .automatic) -> EnvironmentScope<Self> {
        let value = length ?? Pixels(0)
        return contentMargins(edges, EdgeInsets(top: value, leading: value, bottom: value, trailing: value), for: placement)
    }

    /// `length` on all four edges for `placement` — SwiftUI's `contentMargins(_:for:)`.
    public func contentMargins(_ length: Pixels, for placement: ContentMarginPlacement = .automatic)
        -> EnvironmentScope<Self> {
        contentMargins(.all, length, for: placement)
    }
}

extension Frame {
    /// `content` wrapped in a native padding node of the environment's scroll-content margins (`CMG-A`), or `content`
    /// itself, no node added, when none is set — so a scroller without margins lays out exactly as it always did.
    /// The scroller's content node IS this one: its origin and size include the margins, so the clamp, the
    /// lazy windows, hit-testing and the anchors all measure the same extent.
    func paddedForContentMargins(_ content: LayoutNodeID) -> LayoutNodeID {
        let margins = environmentTop.contentMargins.scrollContent
        guard margins != EdgeInsets() else { return content }
        return requestNativePadding(child: content, insets: Edges(
            top: Double(margins.top.value), right: Double(margins.trailing.value),
            bottom: Double(margins.bottom.value), left: Double(margins.leading.value)))
    }
}
