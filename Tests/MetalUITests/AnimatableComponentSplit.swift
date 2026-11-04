@testable import MetalUI

// The `Animatable` conformance of `SplitCounter`, written in a file of its own (`AnimatableComponentFixtures.swift`
// declares the type and its `Component` conformance). **No `_interpolateAnimatableData` and no
// `requestGroupLayout` here**: the constrained witnesses in `Component.swift` must be the ones the conformance picks.
extension SplitCounter: Animatable {
    nonisolated var animatableData: Double {
        get { x }
        set { x = newValue }
    }
}
