import MetalUICore

// SwiftUI's padding spellings on both vocabularies (ruling `DX-B`,
// `docs/superpowers/2026-10-30-dashboard-text-timeline-decisions.md`). Additive: the
// existing `padding(_: Pixels)` / `padding(_: Edges<Length>)` (`StyledElement`, so `Text`)
// and `padding(_: Edges<Pixels>)` (`ProposalElementGroup`, so stacks and `ProposalText`)
// keep their types and their layout; these only add the spellings an app copies from
// SwiftUI, each lowering to the one existing modifier of its vocabulary.

extension Edge {
    /// A set of edges — SwiftUI's `Edge.Set`, for `padding(_:_:)`. `leading` is the left edge
    /// and `trailing` the right: MetalUI has no right-to-left layout (divergence 208).
    public struct Set: OptionSet, Sendable, Hashable {
        /// The set's bits.
        public let rawValue: UInt8
        /// A set from its bits.
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        /// The top edge.
        public static let top = Set(rawValue: 1 << 0)
        /// The leading (left) edge.
        public static let leading = Set(rawValue: 1 << 1)
        /// The bottom edge.
        public static let bottom = Set(rawValue: 1 << 2)
        /// The trailing (right) edge.
        public static let trailing = Set(rawValue: 1 << 3)
        /// Leading and trailing.
        public static let horizontal: Set = [.leading, .trailing]
        /// Top and bottom.
        public static let vertical: Set = [.top, .bottom]
        /// All four edges.
        public static let all: Set = [.top, .leading, .bottom, .trailing]

        /// The set holding just `edge`.
        public init(_ edge: Edge) {
            switch edge {
            case .top: self = .top
            case .leading: self = .leading
            case .bottom: self = .bottom
            case .trailing: self = .trailing
            }
        }
    }
}

/// An inset on each edge — SwiftUI's `EdgeInsets` (leading is the left edge, divergence 208).
public struct EdgeInsets: Sendable, Hashable {
    /// The top inset.
    public var top: Pixels
    /// The leading (left) inset.
    public var leading: Pixels
    /// The bottom inset.
    public var bottom: Pixels
    /// The trailing (right) inset.
    public var trailing: Pixels

    /// Insets of zero.
    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }

    /// Insets with a value each.
    public init(top: Pixels, leading: Pixels, bottom: Pixels, trailing: Pixels) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }

    /// The same insets as per-edge values.
    var edges: Edges<Pixels> {
        Edges(top: top, right: trailing, bottom: bottom, left: leading)
    }
}

extension Edge.Set {
    /// `length` on each edge in the set, zero elsewhere.
    func insets(_ length: Pixels) -> Edges<Pixels> {
        Edges(top: contains(.top) ? length : 0, right: contains(.trailing) ? length : 0,
              bottom: contains(.bottom) ? length : 0, left: contains(.leading) ? length : 0)
    }
}

extension StyledElement {
    /// Padding on the edges in `edges` only — SwiftUI's `padding(_:_:)` (the default `Edge.Set`
    /// and a default length are not offered, divergence 208). Applies to a new outer layer, as
    /// `padding(_: Pixels)` does.
    public func padding(_ edges: Edge.Set, _ length: Pixels) -> ModifiedElement<LayerBase> {
        padding(edges.insets(length))
    }

    /// Padding of `insets` — SwiftUI's `padding(_: EdgeInsets)`.
    public func padding(_ insets: EdgeInsets) -> ModifiedElement<LayerBase> {
        padding(insets.edges)
    }

    /// The per-edge form in points, as a stack's `padding(_: Edges<Pixels>)` is spelled; the
    /// `Edges<Length>` form stays for rem lengths (`FR-Q`).
    public func padding(_ insets: Edges<Pixels>) -> ModifiedElement<LayerBase> {
        padding(Edges(top: Length.pixels(insets.top), right: .pixels(insets.right),
                      bottom: .pixels(insets.bottom), left: .pixels(insets.left)))
    }
}

extension ProposalElementGroup {
    /// The same padding on every edge — SwiftUI's `padding(_ length:)`.
    public func padding(_ length: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> {
        padding(Edges(all: length))
    }

    /// Padding on the edges in `edges` only — SwiftUI's `padding(_:_:)` (divergence 208).
    public func padding(_ edges: Edge.Set, _ length: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier> {
        padding(edges.insets(length))
    }

    /// Padding of `insets` — SwiftUI's `padding(_: EdgeInsets)`.
    public func padding(_ insets: EdgeInsets) -> ModifiedContent<ProposalBase, LayoutModifier> {
        padding(insets.edges)
    }
}

extension Component where Self: ProposalElementGroup {
    /// A `Component` over proposal content keeps `Component.padding(_:)`'s meaning (padding around
    /// each top-level node, `OM-D`), not `ProposalElementGroup.padding(_:)`'s: this is the more
    /// specialised overload that settles the choice the compiler would otherwise call ambiguous
    /// (`DX-B`). It is `Component.padding(_:)` itself.
    public func padding(_ points: Pixels) -> StyledComponent<Self> {
        StyledComponent(component: self, ops: [.wrap(paddingWrapperStyle(points))])
    }
}
