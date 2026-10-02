import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Paths, shadows and transforms, lane 2 — render effects animate (ruling
// `GX-H`; spec `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md`
// §8, tests 2.16–2.17). SwiftUI's side is
// `docs/probes/swiftui-paths-shadows-transforms.swift`, arms N1, N2, N3, N9:
// the angle and its anchor, both factors and their anchor, and the offset
// animate.
//
// The shape of every arm: a resting frame at 0, the change at 0 under
// `linear(duration: 1)`, 0.5 half-way — one harness, so one `StateTable` and
// one `AnimationStore`, as a `Window` holds them. No test sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let linear1 = Animation.linear(duration: 1)

/// The `.accent` rect and its record half-way through `before` → `after`.
@MainActor
private func midway<E: Element>(_ tree: (Bool) -> E) throws -> (rect: MUIRect, record: MUITransform?, rest: MUIRect) {
    let h = TransitionHarness()
    let rest = try #require(effectRects(h.frame(0, nil, tree(false), side: 200).finalizedScene()).first)
    h.frame(0, linear1, tree(true), side: 200)
    let scene = h.frame(0.5, nil, tree(true), side: 200).finalizedScene()
    let rect = try #require(effectRects(scene).first)
    return (rect, effectRecord(rect, in: scene), rest)
}

// MARK: - 2.16 (N1, N2, N3, N9)

/// **2.16** (N1, N2, N3, N9). Under `withAnimation`, half-way: a rotation
/// 0° → 90° whose anchor moves `.center` → `.topLeading` is 45° about the
/// anchor (¼, ¼); a scale 1 → 3 is 2 (flattened); a non-uniform scale
/// `x: 1 → 3` is `x: 2`; an offset 0 → 40 is 20. Mutation **M2n**: the anchor
/// snaps.
@Test @MainActor func rotationScaleAndOffsetAnimateValueAndAnchor() throws {
    let turn = try midway { on in
        fxBar(100, 20).rotationEffect(.degrees(on ? 90 : 0), anchor: on ? .topLeading : .center)
    }
    let o = turn.rect.bounds.origin
    let anchorX = Double(o.x) + 0.25 * 100, anchorY = Double(o.y) + 0.25 * 20
    #expect(fxMatches(turn.record, .rotation(radians: Double.pi / 4, about: anchorX, anchorY)),
            "45° about (¼, ¼) half-way: \(fxDescribe(turn.record))")

    let grow = try midway { on in fxBar(40, 20).scaleEffect(on ? 3 : 1) }
    #expect(grow.rect.bounds.size.width == 80 && grow.rect.bounds.size.height == 40 && grow.record == nil,
            "scale 2 half-way, flattened: \(fxDescribe(grow.rect.bounds))")

    let stretch = try midway { on in fxBar(40, 20).scaleEffect(x: on ? 3 : 1, y: 1) }
    let cx = Double(stretch.rest.bounds.origin.x + 20), cy = Double(stretch.rest.bounds.origin.y + 10)
    #expect(fxMatches(stretch.record, .scale(x: 2, y: 1, about: cx, cy)),
            "x: 2 half-way: \(fxDescribe(stretch.record))")

    let slide = try midway { on in fxBar(40, 20).offset(x: px(on ? 40 : 0)) }
    #expect(slide.rect.bounds.origin.x == slide.rest.bounds.origin.x + 20,
            "offset 20 half-way: \(fxDescribe(slide.rect.bounds)) from \(fxDescribe(slide.rest.bounds))")
}

// MARK: - 2.17

/// **2.17** (`GX-H`). A legacy effect animates on the window's animation store
/// under `$anim-effects`, not in the `StateTable`: half-way through 0° → 90° it
/// is 45°, the store holds the track, and the table holds no entry of that
/// name. Mutation **M2o**: legacy effects snap.
@Test @MainActor func aLegacyEffectAnimatesOnTheStoreNotTheStateTable() throws {
    func tree(_ on: Bool) -> some Element { fxLegacyBar(100, 20).rotationEffect(.degrees(on ? 90 : 0)) }
    let h = TransitionHarness()
    let rest = try #require(effectRects(h.frame(0, nil, tree(false), side: 200).finalizedScene()).first)
    h.frame(0, linear1, tree(true), side: 200)
    let scene = h.frame(0.5, nil, tree(true), side: 200).finalizedScene()
    let rect = try #require(effectRects(scene).first)
    let cx = Double(rest.bounds.origin.x + 50), cy = Double(rest.bounds.origin.y + 10)
    #expect(fxMatches(effectRecord(rect, in: scene), .rotation(radians: Double.pi / 4, about: cx, cy)),
            "45° half-way: \(fxDescribe(effectRecord(rect, in: scene)))")
    let root = GlobalElementID.child(of: nil, at: 0, name: nil)
    let key = legacyEffectsAnimationKey(for: root)
    #expect(h.store.value(at: key) != nil, "the store holds the track at \(key)")
    #expect(h.table.peek(key, as: StoredNumberTracks.self) == nil, "the table does not")
}
