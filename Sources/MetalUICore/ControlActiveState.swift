/// Whether a control's window is the key window, active, or inactive —
/// SwiftUI's `ControlActiveState`, carried as an environment value
/// (`EnvironmentValues.controlActiveState`, ruling EV-AB).
///
/// **`.key` in a bare `EnvironmentValues()`**, as in SwiftUI (probe
/// `swiftui-environment-control-state.swift` V0), so a `Frame` built without a
/// window and `renderFrame` read `.key`. A `Window` stamps its platform
/// window's state over that (`PlatformWindow.controlActiveState`), and a scope
/// may write it (probe C4).
///
/// **No built-in consumer**: MetalUI's controls do not change in an inactive
/// window. SwiftUI's look there is unprobed; owner plan task 12, with the
/// disabled look.
///
/// **It lives in `MetalUICore`, not `MetalUI`**, so `MetalUIPlatform` (which
/// imports only `MetalUICore` and `MetalUIScene`) and `Backends/SDL` can name
/// it in the platform-window seam, as `Appearance` is. `MetalUI` re-exports
/// this module, so no caller sees the difference.
public enum ControlActiveState: Sendable, Hashable, CaseIterable {
    case key
    case active
    case inactive
}
