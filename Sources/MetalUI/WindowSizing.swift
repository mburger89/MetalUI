import MetalUICore
import MetalUIPlatform

// Window sizing (rulings `SV-L`, `SV-M`; spec
// `docs/superpowers/specs/2026-10-04-platform-services-design.md` §2). MetalUI's
// `App` is not a `Scene`, so SwiftUI's scene modifiers `.defaultSize` and
// `.windowResizability` become window state: `App.openWindow(size:)` is the
// default size (`W3`), and `Window.minSize`/`maxSize`/`windowResizability`
// limit it, reaching the platform through
// `PlatformWindow.setContentSizeLimits(minimum:maximum:)`.

/// How a window's content limits its size — SwiftUI's `WindowResizability`
/// (ruling `SV-L`), set on `Window.windowResizability` or passed to
/// `App.openWindow`.
///
/// **Divergence 126**: SwiftUI's `.automatic` on macOS *is* `.contentMinSize`
/// (the probe's `W0` = `W1`); MetalUI's `.automatic` asks the content nothing,
/// so no existing window grows. SwiftUI's limits also include the title bar's
/// 32-point inset; MetalUI's are the root's.
public struct WindowResizability: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case automatic, contentSize, contentMinSize }
    let kind: Kind

    /// The content sets no limit — only `Window.minSize`/`maxSize` do. SwiftUI's
    /// is `.contentMinSize` on macOS (divergence 126).
    public static let automatic = WindowResizability(kind: .automatic)
    /// The window is at least the root's answer at a zero proposal and at most
    /// its answer at an infinite proposal (`W2`): a root of
    /// `.frame(minWidth: 400, maxWidth: 900, minHeight: 300, maxHeight: 600)`
    /// limits the window to 400 × 300 … 900 × 600.
    public static let contentSize = WindowResizability(kind: .contentSize)
    /// The window is at least the root's answer at a zero proposal, with no
    /// maximum from the content (`W1`). The minimum follows the content as it
    /// changes (`W5`).
    public static let contentMinSize = WindowResizability(kind: .contentMinSize)
}

/// A window's content size limits, as handed to the platform.
struct ContentSizeLimits: Equatable {
    var minimum: Size<Pixels>?
    var maximum: Size<Pixels>?

    /// No limit either way.
    static let none = ContentSizeLimits(minimum: nil, maximum: nil)

    /// The limits a window applies (ruling `SV-L` item 4), per axis: the
    /// minimum is the larger of the explicit and content minima, the maximum
    /// the smaller of the explicit and content maxima, raised to the minimum
    /// when below it. A negative value counts as 0; an infinite maximum axis is
    /// no maximum there — sent as `Float.greatestFiniteMagnitude`, and a
    /// maximum unbounded on both axes as `nil`. `nil` inputs set nothing. NaN
    /// never reaches here: `Window`'s setters trap on it, and the kernel's
    /// checkpoint 2 on a NaN answer.
    static func effective(minimum: Size<Pixels>?, maximum: Size<Pixels>?,
                          contentMinimum: Size<Pixels>?, contentMaximum: Size<Pixels>?) -> ContentSizeLimits {
        // Starting at 0 is what clamps a negative minimum (and, through the
        // raise below, a negative maximum) to 0 — mutation M2.41b.
        var minW: Float = 0, minH: Float = 0
        for candidate in [minimum, contentMinimum].compactMap({ $0 }) {
            minW = max(minW, candidate.width.value)
            minH = max(minH, candidate.height.value)
        }
        let hasMinimum = minimum != nil || contentMinimum != nil
        var maxW = Float.infinity, maxH = Float.infinity
        for candidate in [maximum, contentMaximum].compactMap({ $0 }) {
            maxW = min(maxW, candidate.width.value)
            maxH = min(maxH, candidate.height.value)
        }
        maxW = max(maxW, minW)
        maxH = max(maxH, minH)
        let resolvedMaximum: Size<Pixels>?
        if maxW.isInfinite && maxH.isInfinite {
            resolvedMaximum = nil
        } else {
            resolvedMaximum = Size(width: Pixels(maxW.isInfinite ? .greatestFiniteMagnitude : maxW),
                                   height: Pixels(maxH.isInfinite ? .greatestFiniteMagnitude : maxH))
        }
        return ContentSizeLimits(minimum: hasMinimum ? Size(width: Pixels(minW), height: Pixels(minH)) : nil,
                                 maximum: resolvedMaximum)
    }

    /// Traps on a NaN axis of a limit assigned to `Window` (`SA-J`'s rule:
    /// a non-finite value is clamped where it has a meaning — negative to 0,
    /// infinity to none — and NaN has none).
    static func requireNotNaN(_ size: Size<Pixels>?, _ name: String) {
        guard let size else { return }
        precondition(!size.width.value.isNaN && !size.height.value.isNaN,
                     "Window.\(name) must not be NaN: \(size) (SV-L item 4)")
    }
}
