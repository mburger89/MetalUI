import Testing
import MetalUIShaderTypes
@testable import MetalUIRender
import MetalUIScene

// Backdrop blur, lane 1, tests 1.9-1.11 (rulings `BB-A`, `BB-D`, `BB-E`; spec
// `docs/superpowers/specs/2026-10-10-backdrop-blur-design.md` §3.2, §3.3). The
// scene side of a material: `PrimitiveKind.backdrop`, one `MUIBackdrop` record
// per material, the run rule of `finalize()` and the one region function both
// renderers call. No Metal, SDL or closure type enters the scene (`PS-A`).

private let square = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
private let whole = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1000, height: 1000))

private func backdrop(_ x: Float, _ y: Float, _ w: Float, _ h: Float, order: MUIUInt = 0) -> MUIBackdrop {
    MUIBackdrop(bounds: MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h)),
                contentMask: whole, maskCornerRadii: square, cornerRadii: square,
                tint: MUIHsla(h: 0, s: 0, l: 0.9, a: 0.7), order: order, shape: 0, sigma: 52, opacity: 1)
}

private func rect() -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 10, height: 10)),
            contentMask: whole, maskCornerRadii: square,
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1), borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: square, borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0)
}

private func runs(_ scene: Scene) -> [String] { scene.drawList.map { "\($0.kind) \($0.start)+\($0.count)" } }

/// **1.9** (`BB-E`). A backdrop run ends where a record's device box
/// intersects an earlier record's in the run (a later material must see the
/// earlier one) and where another kind interleaves; boxes that only touch
/// share a run. A second `finalize()` reproduces the runs. Red before: no
/// kind. Mutation: break on touching instead of intersecting.
@Test func backdropRunsBreakWhereRegionsOverlapAndWhereAnotherKindInterleaves() throws {
    var scene = Scene()
    scene.insert(backdrop(0, 0, 50, 50))
    scene.insert(backdrop(50, 0, 50, 50))     // touches the first: same run
    scene.insert(backdrop(120, 0, 30, 30))    // disjoint: same run
    scene.insert(backdrop(130, 10, 30, 30))   // overlaps the third: a new run
    scene.insert(rect())                      // another kind: a new run
    scene.insert(backdrop(0, 0, 10, 10))
    scene.finalize()
    let expected = ["backdrop 0+3", "backdrop 3+1", "rect 0+1", "backdrop 4+1"]
    #expect(runs(scene) == expected)
    scene.finalize()
    #expect(runs(scene) == expected, "idempotent")
    #expect(scene.backdrops.count == 5)
    // A transformed record's box is its bounding box: this one, rotated 90
    // degrees about the origin into the negative quadrant, overlaps nothing
    // at (0..50, 0..50) in the second scene.
    var rotated = Scene()
    rotated.insert(backdrop(0, 0, 50, 50))
    let quarter = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 200, ty: 0, pixelScale: 1, _reserved: 0,
                               outerMask: whole, outerMaskRadii: square)
    rotated.insert(backdrop(0, 0, 50, 50), transform: quarter)   // maps to x 150...200
    rotated.finalize()
    #expect(runs(rotated) == ["backdrop 0+2"], "a rotated record's box is where it lands: \(runs(rotated))")
}

/// **1.10** (`BB-A`). A scene holding only a backdrop is not empty
/// (`Renderer.encode` returns early on an empty scene), `clear()` forgets it,
/// and the layer and highest-layer readers see the new array. Mutation: drop
/// `backdrops` from `isEmpty`.
@Test func aSceneHoldingOnlyABackdropIsNotEmptyAndClearForgetsIt() {
    var scene = Scene()
    scene.insert(backdrop(0, 0, 10, 10), layer: 4)
    #expect(!scene.isEmpty)
    #expect(scene.highestLayer == 4 && scene.layer(of: .backdrop, at: 0) == 4)
    scene.clear()
    #expect(scene.isEmpty && scene.backdrops.isEmpty && scene.drawList.isEmpty)
    scene.insert(backdrop(0, 0, 10, 10))
    scene.finalize()
    #expect(runs(scene) == ["backdrop 0+1"], "a cleared scene starts its sequence over")
}

/// **1.11** (`BB-D` 3). `backdropRegion` is the transformed bounds' integer
/// bounding box (floor/ceil) clamped to the target, `nil` when nothing is
/// left. Mutation: skip the clamp.
@Test func backdropRegionIsTheTransformedBoundingBoxClampedToTheTarget() throws {
    var scene = Scene()
    scene.insert(backdrop(10.2, 5.7, 20, 10))                      // 0: fractional
    scene.insert(backdrop(-30, -20, 50, 50))                       // 1: hangs off the top left
    scene.insert(backdrop(190, 90, 50, 50))                        // 2: hangs off the bottom right
    scene.insert(backdrop(300, 300, 10, 10))                       // 3: entirely outside
    let double = MUITransform(a: 2, b: 0, c: 0, d: 2, tx: 10, ty: 0, pixelScale: 2, _reserved: 0,
                              outerMask: whole, outerMaskRadii: square)
    scene.insert(backdrop(0, 0, 20, 10), transform: double)        // 4: scaled and moved
    let target = (width: 200, height: 100)
    let fractional = try #require(scene.backdropRegion(0, target: target))
    #expect(fractional == Scene.BackdropRegion(x: 10, y: 5, width: 21, height: 11), "\(fractional)")
    let topLeft = try #require(scene.backdropRegion(1, target: target))
    #expect(topLeft == Scene.BackdropRegion(x: 0, y: 0, width: 20, height: 30), "\(topLeft)")
    let bottomRight = try #require(scene.backdropRegion(2, target: target))
    #expect(bottomRight == Scene.BackdropRegion(x: 190, y: 90, width: 10, height: 10), "\(bottomRight)")
    #expect(scene.backdropRegion(3, target: target) == nil, "off the target: nothing")
    let scaled = try #require(scene.backdropRegion(4, target: target))
    #expect(scaled == Scene.BackdropRegion(x: 10, y: 0, width: 40, height: 20), "x' = 2x + 10: \(scaled)")
}
