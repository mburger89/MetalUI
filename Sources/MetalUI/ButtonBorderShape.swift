import MetalUICore
import MetalUILayout

// SwiftUI's `buttonBorderShape(_:)` and `ButtonBorderShape` (Alloy gap G46, record 294; rulings `BY-L`, `BY-M` in
// `docs/superpowers/2026-10-31-styles-decisions.md` and `SD-E` in `2026-11-01-segmented-dark-decisions.md`).

/// The shape of a button's border (SwiftUI's `ButtonBorderShape`, ruling `BY-L`): the automatic shape, a capsule, a
/// rounded rectangle with the chrome's radius or a given one, or a circle. Set with ``ElementGroup/buttonBorderShape(_:)``.
///
/// SwiftUI's `ButtonBorderShape` is also a `Shape` (macOS 14) and has `Shape.buttonBorder`; MetalUI's is a plain value:
/// a MetalUI `Shape` is main-actor isolated and cannot be an environment key's default, and a shape cannot read the
/// environment (both absent, class R, `BY-L`).
public struct ButtonBorderShape: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case automatic
        case capsule
        case roundedRectangle(Float?)
        case circle
    }
    let kind: Kind

    /// The platform's shape: the bordered chrome's 5-point rounded rectangle, and a capsule for `.glass` and
    /// `.glassProminent`. The default, and what every control drew before this API existed.
    public static let automatic = ButtonBorderShape(kind: .automatic)
    /// A capsule: the corner radius is half the button's height (the rounded ends of a pill).
    public static let capsule = ButtonBorderShape(kind: .capsule)
    /// A rounded rectangle with the bordered chrome's radius, 5 points.
    public static let roundedRectangle = ButtonBorderShape(kind: .roundedRectangle(nil))
    /// A rounded rectangle with corners of `radius` points (clamped to half the button's shorter side).
    public static func roundedRectangle(radius: Pixels) -> ButtonBorderShape {
        ButtonBorderShape(kind: .roundedRectangle(max(radius.value, 0)))
    }
    /// A circle: the corner radius is half the button's shorter side, so a square button is a circle and a wider one
    /// a capsule (SwiftUI's is an ellipse there; unmeasured, `BY-L`).
    public static let circle = ButtonBorderShape(kind: .circle)

    /// The radius of the bordered chrome (`Button.chromeCornerRadius`).
    static let defaultRadius: Float = 5

    /// The corner radius this shape gives a button `size` points across, or `nil` for the chrome's own (`.automatic`).
    func radius(forWidth width: Float, height: Float) -> Float? {
        let half = max(min(width, height) / 2, 0)
        switch kind {
        case .automatic: return nil
        case .capsule, .circle: return half
        case .roundedRectangle(let radius): return min(radius ?? Self.defaultRadius, half)
        }
    }

    /// The shape a glass button draws: a capsule unless a rounded rectangle is asked for.
    @MainActor var glassShape: any Shape & Hashable {
        switch kind {
        case .automatic, .capsule, .circle: Capsule()
        case .roundedRectangle(let radius): RoundedRectangle(cornerRadius: Pixels(radius ?? Self.defaultRadius))
        }
    }
}

/// The key behind `.buttonBorderShape(_:)` (internal: SwiftUI's `_buttonBorderShape` is internal too). `Equatable`, so a
/// retained subtree's key sees a change (`EE-F`).
struct ButtonBorderShapeKey: EnvironmentKey { static let defaultValue = ButtonBorderShape.automatic }

extension EnvironmentValues {
    /// The border shape of the bordered buttons below.
    var buttonBorderShape: ButtonBorderShape {
        get { self[ButtonBorderShapeKey.self] }
        set { self[ButtonBorderShapeKey.self] = newValue }
    }
}

extension ElementGroup {
    /// Sets the border shape of the bordered buttons in this content — SwiftUI's `buttonBorderShape(_:)` (ruling
    /// `BY-L`). An environment write: it reaches every `Button` with `.bordered`, `.borderedProminent`, `.glass`,
    /// `.glassProminent` (or the automatic style), every `Menu` and every `Picker` in the `.menu` style below, and the
    /// nearest writer wins. `.plain`, `.borderless` and `.link` buttons draw no border and a custom style draws its own
    /// body, so they ignore it; a segmented `Picker` ignores it too — its own shape is
    /// ``segmentedPickerShape(_:)`` (`SD-E`). A caller's own `.cornerRadius(_:)` on a `Button` outranks it.
    public func buttonBorderShape(_ shape: ButtonBorderShape) -> EnvironmentScope<Self> {
        environment(\.buttonBorderShape, shape)
    }

    /// Sets the shape of the segmented `Picker`s in this content: ``ButtonBorderShape/capsule`` rounds the track and
    /// the selected segment to half the row's 24 points, ``ButtonBorderShape/roundedRectangle(radius:)`` gives the track
    /// that radius (the segment 1 point less, as the default's 6 and 5), `.automatic` is today's 6 and 5. MetalUI-only
    /// (class M): SwiftUI's segmented picker takes no shape (`SD-E`); an environment write, the nearest writer wins.
    public func segmentedPickerShape(_ shape: ButtonBorderShape) -> EnvironmentScope<Self> {
        environment(\.segmentedPickerShape, shape)
    }
}

/// The key behind `.segmentedPickerShape(_:)`.
struct SegmentedPickerShapeKey: EnvironmentKey { static let defaultValue = ButtonBorderShape.automatic }

extension EnvironmentValues {
    /// The shape of the segmented pickers below.
    var segmentedPickerShape: ButtonBorderShape {
        get { self[SegmentedPickerShapeKey.self] }
        set { self[SegmentedPickerShapeKey.self] = newValue }
    }
}
