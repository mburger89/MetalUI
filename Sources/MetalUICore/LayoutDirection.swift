/// The direction a horizontal layout reads in — SwiftUI's `LayoutDirection`,
/// carried as an environment value (`EnvironmentValues.layoutDirection`,
/// ruling EV-K).
///
/// **Carried, not yet honoured.** No container mirrors under `.rightToLeft`
/// today: probe H of `docs/probes/swiftui-environment-scoping.swift` measured
/// SwiftUI placing a 10pt and a 20pt child at x 90 and 70 in a 100pt leading
/// frame, and MetalUI places them at 0 and 10.
/// `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack` pins that wrong on
/// purpose; it flips in the change that implements mirroring (plan task 6).
///
/// **It lives in `MetalUICore`, not `MetalUI`, for that change's sake.**
/// Mirroring is a placement transform in the proposal kernel, so the direction
/// has to be recorded on native nodes in `LayoutTree`, and `MetalUILayout`
/// imports only `MetalUICore`. Declaring the type in `MetalUI` now would force
/// a public type across a module boundary later — the stale-incremental-build
/// hazard CLAUDE.md records. `MetalUI` re-exports this module, so no caller
/// sees the difference.
public enum LayoutDirection: Sendable, Hashable, CaseIterable {
    case leftToRight
    case rightToLeft
}
