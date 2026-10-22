import MetalUICore
import MetalUIPlatform

// Background window drag (rulings `BG-G`...`BG-J`, record 144; spec
// `docs/superpowers/specs/2026-10-22-presentation-extras-design.md`). SwiftUI's `Scene` modifier
// `windowBackgroundDragBehavior(_:)` (macOS 15), probed in `docs/probes/swiftui-presentation-extras.swift`
// (the `D` arms): only `.enabled` moves the window from a press on the content's background, and it does
// not use AppKit's `isMovableByWindowBackground`. MetalUI has no `Scene`, so the behavior is a `Window`
// property beside `windowStyle` (divergence 736).

/// How a press on a window's background moves the window — SwiftUI's `WindowInteractionBehavior`
/// (macOS 15). Set with ``Window/backgroundDragBehavior``.
///
/// SwiftUI measured: with `.enabled` a press-drag on the content background asks AppKit to move the window;
/// with `.automatic` (the default) and `.disabled` it never does, so MetalUI treats those two alike (ruling
/// `BG-G`).
public struct WindowInteractionBehavior: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case automatic, enabled, disabled }
    let kind: Kind

    /// The platform's default behavior: no background drag.
    public static let automatic = WindowInteractionBehavior(kind: .automatic)
    /// A press no element claims drags the window.
    public static let enabled = WindowInteractionBehavior(kind: .enabled)
    /// No background drag (the same as `.automatic`; the title band keeps its own drag, `BG-J`).
    public static let disabled = WindowInteractionBehavior(kind: .disabled)

    /// Whether this behavior moves the window from the background.
    var dragsFromBackground: Bool { kind == .enabled }
}

extension Window {
    /// Whether a press on the window's background — one no element claimed — moves the window. SwiftUI's
    /// `windowBackgroundDragBehavior(_:)` scene modifier as a window property, because MetalUI has no
    /// `Scene` (ruling `BG-G`, MetalUI-only, divergence 736). Default `.automatic`, which does not drag.
    ///
    /// With `.enabled`, a primary press that reaches the end of the input path unclaimed — no opaque
    /// target under it, no gesture arena (the one ranking, `AS-J`'s rule) — asks the platform to drag the
    /// window: on AppKit through the title bar's own drag call (`BG-H`; a double click on the background
    /// does nothing); on SDL through a hit-test region over the content, carved by every control
    /// (`BG-I`), where hover, wheel and pointer-style events inside the region are lost (divergence 737).
    /// A control, a text field, a scroller, a draggable or a `WindowDragGesture` handle is never a
    /// background. The title band's drag (`AS-J`, `CW`) is unchanged by this setting (`BG-J`).
    public var backgroundDragBehavior: WindowInteractionBehavior {
        get { shell.chrome.backgroundDragBehavior }
        set {
            guard newValue != shell.chrome.backgroundDragBehavior else { return }
            shell.chrome.backgroundDragBehavior = newValue
            setNeedsRedraw()
        }
    }
}
