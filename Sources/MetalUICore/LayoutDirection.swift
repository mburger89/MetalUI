/// The direction a horizontal layout reads in — SwiftUI's `LayoutDirection`,
/// carried as an environment value (`EnvironmentValues.layoutDirection`,
/// ruling EV-K).
///
/// **Right-to-left mirrors layout** (round 3 item R3-10 item 4, ruling `LD-A`; probe
/// `docs/probes/swiftui-layout-direction.swift`). A node registered under `.rightToLeft` reflects each
/// child's rect about the middle of its own bounds when it is placed: a 10pt and a 20pt child of an
/// `HStack` in a 100pt leading frame sit at x 90 and 70. Offsets, effect anchors, multiline text
/// alignment and a horizontal scroller's origin follow. What stays unmirrored (a shape's path, a
/// gradient's unit points, `trim`, `UnevenRoundedRectangle`'s corners) is divergence 1045.
///
/// **It lives in `MetalUICore`, not `MetalUI`, for the kernel's sake.**
/// Mirroring is a placement transform in the proposal kernel, so the direction
/// has to be recorded on native nodes in `LayoutTree`, and `MetalUILayout`
/// imports only `MetalUICore`. `MetalUI` re-exports this module, so no caller
/// sees the difference.
public enum LayoutDirection: Sendable, Hashable, CaseIterable {
    case leftToRight
    case rightToLeft
}
