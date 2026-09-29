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
/// **The built-in controls consume it** (plan task 12 part 1, ruling `IX-H`):
/// a control's accent — `Toggle`'s on indicator, `Slider`'s fill, a radio
/// `Picker`'s selection and the focus ring — is painted only in the key window
/// (probe `swiftui-interaction` PX17–PX20: accent at `.key`, none at
/// `.inactive`); `.active` is treated as not key, MetalUI's choice (the probe's
/// process is never active, PX23).
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
