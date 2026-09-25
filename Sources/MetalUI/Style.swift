import MetalUICore

// `Style` and its vocabulary live in `MetalUI` since plan task 7, stage 10
// (ruling `LR-FM` item 3): the proposal lowering (`LegacyLowering.swift`) is
// their only reader, and the layout kernel, `MetalUILayout`, declares no CSS
// vocabulary at all. Until stage 9 a CSS engine read these types in the
// kernel; that engine, its WebKit fixtures and every `positionStackItems`
// citation are history (records §51, §52).
//
// Stage 10 also deleted the fields no lowering read to produce a layout —
// `aspectRatio`, `overflow`, `flexWrap`, `alignContent`, `border` — with
// `Position.relative` and the enums `FlexWrap`, `AlignContent` and `Overflow`
// (`LR-FM` item 1, `LR-FN` for each migration spelling), and made every
// surviving stored field `package` (`LR-FM` item 2): outside the package a
// `Style` is an opaque value, and an element's layout is spelled only through
// its modifiers.

/// How a legacy container lays its children out: `.flex` a row or column,
/// `.stack` every child layered in one cell, `.none` hidden — `hidden()`
/// (`LR-DH`). Written only by `Stack` and `hidden()`; `package` since stage 10
/// (no public writer remained).
package enum Display: Sendable, Equatable { case flex, stack, none }

/// Whether a box participates in its container's flow. `.absolute` inside a
/// `Deferred` is a presentation root placed against the window (`LR-CH`,
/// `LR-FF`: the window is the only containing block); anywhere else it is
/// refused by name (`LR-FO` item 2). `.relative` was removed by stage 10
/// (`LR-FN` item 3).
public enum Position: Sendable, Equatable { case `static`, absolute }

public enum FlexDirection: Sendable, Equatable {
    case row, rowReverse, column, columnReverse

    /// True when the main axis is horizontal.
    public var isRow: Bool { self == .row || self == .rowReverse }
    /// True when items are placed from the far end of the main axis.
    public var isReverse: Bool { self == .rowReverse || self == .columnReverse }
}

/// `.baseline` has no lowering and is reported by name (owner plan task 11,
/// baselines; `LR-FO` item 3).
public enum AlignItems: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

/// Inline-axis alignment of each item of a `.stack` container within the
/// stack's area — written only by `Stack(alignment:)` and `.frame(alignment:)`,
/// read by the stack lowering. `nil` means `stretch`, as `alignItems`'s does.
/// `package` since stage 10 (no public writer remained).
package enum JustifyItems: Sendable, Equatable { case start, center, end, stretch }

/// `.baseline` is reported by name, as `AlignItems.baseline` is.
public enum AlignSelf: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum JustifyContent: Sendable, Equatable {
    case flexStart, flexEnd, center, spaceBetween, spaceAround, spaceEvenly
}

/// A legacy element's layout inputs, read by the proposal lowering
/// (`LegacyLowering.swift`), which gives each field its SwiftUI answer
/// (`LR-AB`…`LR-BA`) or refuses it by name (`LR-FO`).
///
/// Border-box: `size`, `minSize` and `maxSize` include padding.
///
/// **Every stored field is `package`** (`LR-FM` item 2): outside the package
/// `Style` is `init()`, `default` and `==`, and each field is written through
/// its element's modifier (`LR-FN`'s table). `Box(style:)`'s parameter is
/// therefore inert outside the package (`LR-FR` F5).
public struct Style: Sendable, Equatable {
    // Box
    package var display: Display = .flex
    package var position: Position = .static
    package var inset: Edges<Dimension> = Edges(all: .auto)
    package var size: Size<Dimension> = Size(width: .auto, height: .auto)
    package var minSize: Size<Dimension> = Size(width: .auto, height: .auto)
    package var maxSize: Size<Dimension> = Size(width: .auto, height: .auto)
    package var margin: Edges<Dimension> = Edges(all: .length(.pixels(Pixels(0))))
    package var padding: Edges<Length> = Edges(all: .pixels(Pixels(0)))

    // As a container
    package var flexDirection: FlexDirection = .row
    package var gap: Axes<Length> = Axes(both: .pixels(Pixels(0)))
    package var justifyContent: JustifyContent? = nil
    package var alignItems: AlignItems? = nil
    /// `nil` means `stretch`, matching `alignItems`'s convention. See
    /// ``JustifyItems``.
    package var justifyItems: JustifyItems? = nil

    // As an item
    package var flexGrow: Float = 0
    package var flexShrink: Float = 1
    package var flexBasis: Dimension = .auto
    package var alignSelf: AlignSelf? = nil

    public init() {}

    public static let `default` = Style()
}
