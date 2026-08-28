import MetalUICore

/// How a container lays its children out.
///
/// `.stack` layers every child at the same position and sizes the container to
/// the largest of them on each axis — CSS's one-cell grid, SwiftUI's `ZStack`.
/// It reads neither `flexDirection` nor any flex property on its children;
/// `flexGrow`, `flexShrink` and `flexBasis` are flex-container properties and a
/// stack ignores them, as CSS does.
public enum Display: Sendable, Equatable { case flex, stack, none }
public enum Position: Sendable, Equatable { case relative, absolute }
public enum FlexWrap: Sendable, Equatable { case noWrap, wrap, wrapReverse }
public enum Overflow: Sendable, Equatable { case visible, hidden, scroll }

public enum FlexDirection: Sendable, Equatable {
    case row, rowReverse, column, columnReverse

    /// True when the main axis is horizontal.
    public var isRow: Bool { self == .row || self == .rowReverse }
    /// True when items are placed from the far end of the main axis.
    public var isReverse: Bool { self == .rowReverse || self == .columnReverse }
}

public enum AlignItems: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

/// Inline-axis alignment of each item within its own area — CSS's
/// `justify-items`.
///
/// **Read only by the stack path**, and that is not a declared-but-inert entry:
/// it has a production reader. It is also what CSS does — `justify-items` has no
/// effect on a flex container there either, so the inertness belongs to the
/// model rather than to this implementation. Do not add it to CLAUDE.md's table.
///
/// Four cases rather than CSS's full set: `start`/`end` instead of
/// `flexStart`/`flexEnd` because a stack has no flex-relative axis to be the
/// start of, and no `baseline` because `AlignItems.baseline` is itself
/// unimplemented and falls back to `flexStart` (CLAUDE.md's inert table). Adding
/// a case later is additive.
///
/// **`.stretch` fills an item's axis only when that item's own declared size on
/// that axis is `auto`** — CSS Box Alignment's rule, matched exactly by
/// `positionStackItems`. A child with a declared size (including a percentage,
/// which is not `auto` either) keeps it and sits at the start edge instead;
/// stretching it anyway is the bug `stack_stretch_declared_size` in
/// `StackFixtureTests.swift` pins. This applies to `AlignItems.stretch` too —
/// both axes share the one rule.
public enum JustifyItems: Sendable, Equatable { case start, center, end, stretch }

public enum AlignSelf: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum AlignContent: Sendable, Equatable {
    case flexStart, flexEnd, center, stretch, spaceBetween, spaceAround, spaceEvenly
}

public enum JustifyContent: Sendable, Equatable {
    case flexStart, flexEnd, center, spaceBetween, spaceAround, spaceEvenly
}

/// A node's layout inputs.
///
/// Box model is border-box only (spec §5.2): `size`, `minSize` and `maxSize`
/// include padding and border. There is deliberately no `boxSizing` property.
public struct Style: Sendable, Equatable {
    // Box
    public var display: Display = .flex
    public var position: Position = .relative
    public var inset: Edges<Dimension> = Edges(all: .auto)
    public var size: Size<Dimension> = Size(width: .auto, height: .auto)
    public var minSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var maxSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var aspectRatio: Float? = nil
    public var margin: Edges<Dimension> = Edges(all: .length(.pixels(Pixels(0))))
    public var padding: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var border: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var overflow: Axes<Overflow> = Axes(both: .visible)

    // As a flex container
    public var flexDirection: FlexDirection = .row
    public var flexWrap: FlexWrap = .noWrap
    public var gap: Axes<Length> = Axes(both: .pixels(Pixels(0)))
    public var justifyContent: JustifyContent? = nil
    public var alignItems: AlignItems? = nil
    public var alignContent: AlignContent? = nil
    /// `nil` means CSS's `stretch`, matching `alignItems`'s convention. See
    /// ``JustifyItems``.
    public var justifyItems: JustifyItems? = nil

    // As a flex item
    public var flexGrow: Float = 0
    public var flexShrink: Float = 1
    public var flexBasis: Dimension = .auto
    public var alignSelf: AlignSelf? = nil

    public init() {}

    public static let `default` = Style()
}
