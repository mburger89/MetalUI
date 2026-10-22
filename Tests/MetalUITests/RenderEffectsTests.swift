import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// `WR-C` (record §139): `PaintPass.withRenderEffects` recurses by index, and a legacy shadow's colour track
// is keyed by its position among the element's effects. The index form must pass `count - 1` at each depth
// where the old slice form read `effects.count - 1` of the shrinking slice.

/// **everyLegacyRenderEffectOpensItsScopeAtItsIndex.** An element with `[.shadow(a), .blur, .shadow(b)]`
/// holds shadow colour tracks at indices 0 and 2 under its id, none at 1 (the blur) or 3. Mutation: pass
/// `count` for `count - 1` in the shadow arm of `openingRenderEffects` (tracks at 1 and 3).
@Test @MainActor func everyLegacyRenderEffectOpensItsScopeAtItsIndex() throws {
    let h = TransitionHarness()
    let tree = fxLegacyBar(40, 40)
        .shadow(color: .textPrimary, radius: Pixels(2))
        .blur(radius: Pixels(1))
        .shadow(color: .accent, radius: Pixels(3))
    h.frame(0, nil, tree, side: 200)
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    for index in 0...3 {
        let present = h.store.value(at: legacyShadowColourKey(for: root, index: index)) != nil
        #expect(present == (index == 0 || index == 2), "shadow track \(index): present=\(present)")
    }
}
