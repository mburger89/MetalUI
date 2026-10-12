import MetalUICore

// Window drag (item C22, rulings `WD-A`…`WD-J`; spec
// `docs/superpowers/specs/2026-10-12-window-drag-design.md`). Evidence:
// `docs/probes/swiftui-window-drag.swift`.

/// SwiftUI's `WindowDragGesture` (ruling `WD-B`): attached to a region with
/// `.gesture(_:)`, a press-drag that begins on it moves the window.
///
/// ```swift
/// Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
/// ```
///
/// It is a leaf of the one arena (`IX-D`): it rides its element's hitbox like
/// any gesture, so the region wins over what is beneath it in the window's one
/// hit ranking, and it begins at a 5-point move from the press (`WD-C`) so a
/// `Button` or tap in the same region still clicks. When it acts, the other
/// members of the arena are cut off and the platform is asked to move the
/// window (`PlatformWindow.performWindowDrag`, `WD-D`, `WD-E`).
///
/// **Divergence 275**: SwiftUI runs the window gesture alongside its
/// neighbours; MetalUI cuts them off (each that had reported runs its
/// `onCancelled`). **Divergence 276**: on SDL the move is the system title
/// bar's, not the region's (`WD-F`). A drag gesture on the same element or a
/// descendant attached *before* it outranks it, as in SwiftUI.
///
/// The gesture has no value and no callbacks (`Value` has no members).
public struct WindowDragGesture: Gesture {
    /// A window drag reports no value; SwiftUI's `Value` has no members.
    public struct Value: Equatable, Sendable {
        init() {}
    }

    /// A gesture that moves the window.
    public init() {}

    @_spi(MetalUIGesture) public func _recognizers() -> _GestureRecognizers {
        _GestureRecognizers(.leaf(GestureLeaf(kind: .windowDrag)))
    }
}
