import MetalUICore
import MetalUILayout

// SF-Symbol-style image configuration (record 230, prefix `SYM-`): `Image.Scale` and `imageScale`,
// `SymbolRenderingMode` and `symbolRenderingMode`, `SymbolVariants` and `symbolVariant`. Probe
// `docs/probes/swiftui-symbol-images.swift` (S3, S4, S5, S5b) is the evidence for every default here.

extension Image {
    /// SwiftUI's `Image.Scale`: how large a symbol draws against the font's point size. `.medium` is the
    /// default (probe `S3`: no `imageScale` is `.medium`, 0 px). Maps to AppKit's `NSImage.SymbolScale`.
    public enum Scale: Sendable, Hashable, CaseIterable {
        case small, medium, large
    }
}

/// SwiftUI's `SymbolRenderingMode`. **`.palette` is not offered**: MetalUI has no multi-style
/// `foregroundStyle` to feed it (`SYM-M`, carried).
public enum SymbolRenderingMode: Sendable, Hashable {
    /// One colour, the foreground style, the symbol's coverage as its shape.
    case monochrome
    /// The foreground style at the symbol's own layer levels (probe `S4`: secondary layers at 0.5).
    case hierarchical
    /// The symbol's own colours; the foreground style is ignored (probe `S4`).
    case multicolor
}

/// SwiftUI's `SymbolVariants`: a shape (`circle`, `square`, `rectangle`), a `slash` and a `fill`, combined by
/// chaining (`.circle.fill`). `symbolVariant(_:)` appends them to a symbol's name when a variant of that
/// name exists and falls back to the name otherwise (probes `S5`, `S5b`; see ``resolveSymbolName``).
public struct SymbolVariants: Sendable, Hashable {
    enum Shape: Sendable, Hashable { case none, circle, square, rectangle }
    var shape: Shape = .none
    var hasFill = false
    var hasSlash = false

    /// No variant.
    public static let none = SymbolVariants()
    /// The filled variant.
    public static let fill = SymbolVariants(hasFill: true)
    /// The circle variant.
    public static let circle = SymbolVariants(shape: .circle)
    /// The square variant.
    public static let square = SymbolVariants(shape: .square)
    /// The rectangle variant.
    public static let rectangle = SymbolVariants(shape: .rectangle)
    /// The slashed variant.
    public static let slash = SymbolVariants(hasSlash: true)

    /// These variants with the filled one added (`.circle.fill`).
    public var fill: SymbolVariants { var copy = self; copy.hasFill = true; return copy }
    /// These variants with the circle added; a shape already named is replaced.
    public var circle: SymbolVariants { var copy = self; copy.shape = .circle; return copy }
    /// These variants with the square added; a shape already named is replaced.
    public var square: SymbolVariants { var copy = self; copy.shape = .square; return copy }
    /// These variants with the rectangle added; a shape already named is replaced.
    public var rectangle: SymbolVariants { var copy = self; copy.shape = .rectangle; return copy }
    /// These variants with the slash added.
    public var slash: SymbolVariants { var copy = self; copy.hasSlash = true; return copy }

    /// Whether every variant of `other` is in these.
    public func contains(_ other: SymbolVariants) -> Bool {
        (other.shape == .none || other.shape == shape) && (!other.hasFill || hasFill) && (!other.hasSlash || hasSlash)
    }

    init(shape: Shape = .none, hasFill: Bool = false, hasSlash: Bool = false) {
        self.shape = shape; self.hasFill = hasFill; self.hasSlash = hasSlash
    }

    /// `self` with `other`'s variants added (a named shape replaces). What nested `symbolVariant(_:)` calls reduce to;
    /// SwiftUI's nesting is unmeasured (`SYM-F`).
    func adding(_ other: SymbolVariants) -> SymbolVariants {
        SymbolVariants(shape: other.shape == .none ? shape : other.shape,
                       hasFill: hasFill || other.hasFill, hasSlash: hasSlash || other.hasSlash)
    }
}

extension ElementGroup {
    /// SwiftUI's `imageScale(_:)`: the scale symbols below draw at (`.medium` by default).
    public func imageScale(_ scale: Image.Scale) -> EnvironmentScope<Self> {
        environment(\.imageScale, scale)
    }

    /// SwiftUI's `symbolRenderingMode(_:)`: how symbols below colour themselves; `nil` restores the default
    /// (monochrome). A mode written on an `Image` itself (``Image/symbolRenderingMode(_:)``) beats this one.
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> EnvironmentScope<Self> {
        environment(\.symbolRenderingMode, mode)
    }

    /// SwiftUI's `symbolVariant(_:)`: symbols below show `variant` where their name has it. Variants add up
    /// through nested calls (`SYM-F`).
    public func symbolVariant(_ variant: SymbolVariants) -> EnvironmentScope<Self> {
        transformEnvironment(\.symbolVariants) { $0 = $0.adding(variant) }
    }
}
