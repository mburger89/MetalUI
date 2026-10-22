import Testing
@testable import MetalUI

// C14-i (`RZ-B`): `ReplayKey.effectRelation(from:)` over hand-built keys. Every `.effect` scope a real frame pushes carries alpha 1, and a
// change of an effect's entry clip depth moves the key's own `depths` and clip with it (a clip added outside the effect also encloses
// the occurrence), so no window sequence separates those two halves of the `effectScopeChanged` guard: this pins it at the key.

/// An effect scope's vector in `retainedAmbientKey`'s layout: kind, alpha, entry depth, flattens, six affine numbers, no outer mask.
private func effectVector(scale: Double, alpha: Double = 1, entryDepth: Double = 0) -> [Double] {
    [AmbientKey.effectKind, alpha, entryDepth, 0, scale, 0, 0, scale, 0, 0, 0]
}

@MainActor private func key(_ scope: [Double]) -> ReplayKey {
    let ambient = AmbientKey(clip: [0, 0, 100, 100, 0, 0, 0, 0], offset: [0, 0], layerOpacityScale: [0, 1, 1, 100, 100],
                             depths: [1, 0, -1, 1], scopes: [scope], environment: EnvironmentValues().retainedFingerprint,
                             snappingTransaction: true, disablesAnimations: false)
    return ReplayKey(rects: [0, 0, 10, 10], interior: 7, shapeInterior: 3, nodeCount: 1, ambient: ambient)
}

enum KeyArm: CaseIterable, CustomStringConvertible {
    case alpha, entryDepth
    var description: String { self == .alpha ? "alpha" : "entryDepth" }
}

/// A zoom step with the effect's alpha or entry clip depth also changed is refused by name, and the unchanged-otherwise zoom is affine.
/// Mutation, one per arm: `new[1] != was[1]` dropped; `new[2] != was[2]` dropped (the relation reads `.affine`).
@Test(arguments: KeyArm.allCases) @MainActor
func aZoomStepWithAnAlphaOrEntryDepthChangeIsRefusedByName(arm: KeyArm) {
    let old = key(effectVector(scale: 1))
    #expect(key(effectVector(scale: 1.25)).effectRelation(from: old) == .affine, "the control: a zoom alone is an affine change")
    let changed = arm == .alpha ? effectVector(scale: 1.25, alpha: 0.5) : effectVector(scale: 1.25, entryDepth: 1)
    #expect(key(changed).effectRelation(from: old) == .refused("effectScopeChanged"), "\(arm)")
}
