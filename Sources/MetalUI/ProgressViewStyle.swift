/// How a ``ProgressView`` draws — SwiftUI's `ProgressViewStyle`'s three
/// built-in values (C10 lane 2, ruling `LK-E` items 1–2).
///
/// `.automatic` draws the spinner without a value and the linear bar with one;
/// `.linear` draws a bar either way (an indeterminate one without a value);
/// `.circular` draws the spinner without a value and a determinate ring with
/// one. Written on the view (``ProgressView/progressViewStyle(_:)``) or on a
/// container (``ElementGroup/progressViewStyle(_:)``); **the innermost wins**
/// (`MD-B`'s `textFieldStyle` precedent). A custom style is not offered
/// (`LK-A`'s deferral table).
public struct ProgressViewStyle: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case automatic, linear, circular
    }

    let kind: Kind

    init(kind: Kind) { self.kind = kind }

    /// The spinner without a value, the linear bar with one.
    public static let automatic = ProgressViewStyle(kind: .automatic)
    /// A bar: determinate with a value, indeterminate without.
    public static let linear = ProgressViewStyle(kind: .linear)
    /// The spinner without a value, a ring with one.
    public static let circular = ProgressViewStyle(kind: .circular)
}

/// The environment's progress-view style: `nil` until a container writes one.
struct ProgressViewStyleKey: EnvironmentKey {
    static let defaultValue: ProgressViewStyle? = nil
}

extension EnvironmentValues {
    /// The style a container wrote with ``ElementGroup/progressViewStyle(_:)``,
    /// nearest writer winning; `nil` reads as `.automatic`.
    var progressViewStyle: ProgressViewStyle? {
        get { self[ProgressViewStyleKey.self] }
        set { self[ProgressViewStyleKey.self] = newValue }
    }
}

extension ElementGroup {
    /// Sets the style of every ``ProgressView`` inside — SwiftUI's
    /// `progressViewStyle(_:)` on a container (`LK-E` item 1). A view's own
    /// style, or a nearer container's, wins.
    public func progressViewStyle(_ style: ProgressViewStyle) -> EnvironmentScope<Self> {
        environment(\.progressViewStyle, style)
    }
}
