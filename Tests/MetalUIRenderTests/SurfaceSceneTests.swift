import Testing
import MetalUIShaderTypes
@testable import MetalUIRender

// MetalView lane 1, tests 1.1–1.3 (ruling `MV-C`; spec
// `docs/superpowers/specs/2026-10-01-metal-view-design.md` §3, §8). The scene
// side of an app-owned surface: `PrimitiveKind.surface`, an `MUIImage` record
// per quad and one opaque `SurfaceTarget` (id + device-pixel size) per distinct
// surface. No Metal, SDL or closure type enters the scene (`PS-A`).

private func quad(order: MUIUInt = 0) -> MUIImage {
    MUIImage(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 10, height: 10)),
             contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1000, height: 1000)),
             maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
             opacity: 1, texture: 0, filter: 0, order: order)
}

private func rect() -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 10, height: 10)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 1000, height: 1000)),
            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: 0, shape: 0)
}

private let targetA = SurfaceTarget(id: SurfaceID(rawValue: 1), width: 20, height: 10)
private let targetB = SurfaceTarget(id: SurfaceID(rawValue: 2), width: 8, height: 8)

/// **1.1** (`MV-C` item 2). A surface run breaks where its target changes, as
/// an image run breaks where its texture changes, so the run count stays the
/// draw-call count (one texture bound per instanced draw) — and a second
/// `finalize()` reproduces it.
///
/// Mutation **M1a**: drop the target-index check from `finalize()`'s run
/// continuation for `.surface` (the first two runs merge).
@Test func surfaceRunsBreakWhereTheTargetChanges() throws {
    var scene = Scene()
    scene.insert(quad(), surface: targetA)
    scene.insert(quad(), surface: targetA)
    scene.insert(quad(), surface: targetB)
    scene.insert(rect())
    scene.finalize()
    func runs() -> [String] { scene.drawList.map { "\($0.kind) \($0.start)+\($0.count)" } }
    let expected = ["surface 0+2", "surface 2+1", "rect 0+1"]
    #expect(runs() == expected)
    #expect(scene.surfaces.map(\.texture) == [0, 0, 1], "each quad's texture field indexes surfaceTargets")
    scene.finalize()
    #expect(runs() == expected, "idempotent")
    #expect(scene.surfaces.map(\.texture) == [0, 0, 1])
}

/// **1.2** (`MV-C` item 2). A scene holding only a surface is not empty —
/// `Renderer.encode` returns early on an empty scene, so an `isEmpty` that
/// missed `surfaces` would draw nothing in a frame whose paint emitted only a
/// surface — and `clear()` empties both new arrays.
///
/// Mutation **M1b**: `isEmpty` omits `surfaces`.
@Test func aSceneHoldingOnlyASurfaceIsNotEmpty() {
    var scene = Scene()
    scene.insert(quad(), surface: targetA)
    #expect(!scene.isEmpty)
    scene.clear()
    #expect(scene.isEmpty)
    #expect(scene.surfaces.isEmpty && scene.surfaceTargets.isEmpty)
}

/// **1.3** (`MV-C` item 1). A target drawn twice is carried once, in
/// first-use order — a drag preview replays its source's quad over the same
/// target — and the highest layer and per-kind layer read the new arrays.
///
/// Mutation **M1c**: append a target per insert (no dedupe).
@Test func aSurfaceTargetIsCarriedOncePerID() {
    var scene = Scene()
    scene.insert(quad(), surface: targetB, layer: 0)
    scene.insert(quad(), surface: targetA, layer: 3)
    scene.insert(quad(), surface: targetB, layer: 1)
    #expect(scene.surfaceTargets == [targetB, targetA])
    #expect(scene.surfaces.map(\.texture) == [0, 1, 0])
    #expect(scene.highestLayer == 3)
    #expect((0..<3).map { scene.layer(of: .surface, at: $0) } == [0, 3, 1])
}
