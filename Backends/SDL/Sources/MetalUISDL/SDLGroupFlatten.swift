// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUIScene
import MetalUIShaderTypes
import SDLBridge

/// An offscreen group tree flattened for the bridge (ruling GO-F, record 218). The bridge uploads one buffer a kind, so a
/// frame's groups are appended **after the root's records**, post-order (a group's runs name only earlier groups): every
/// transform index of a record is shifted by the transforms before its group's, every run start by the records before
/// it, and a group quad — an image record in an image run — names its target by `texture`, which the bridge's handle
/// array holds after the frame's own handles (`groupTextureBase + the group's index`). The same arithmetic as
/// `FlatFrame` in `ReplayFixture` (which `MetalUISDL` cannot import: the root manifest does not declare it), pinned
/// by the parity frame that plays the fixture form against the Metal reference.
struct SDLGroupSet {
    var rects: [MUIRect] = []
    var glyphs: [MUIGlyph] = []
    var images: [MUIImage] = []
    var transforms: [MUITransform] = []
    /// The groups' runs only; `ReplayGroup.run_start` is absolute (the root's runs come first).
    var runs: [ReplayRun] = []
    var groups: [ReplayGroup] = []
    /// The root scene's group quads, `texture` rewritten to the group's flat index plus the base: the caller appends
    /// them to the root's image array, where the root's `.group` runs index them.
    var rootQuads: [MUIImage] = []

    private init() {}

    /// `counts`: the root's record counts as the bridge will see them (surface quads and surface text included), and
    /// `mainRunCount` its run count; `textureIndex` maps an `ImageTexture` to its handle index in the shared list;
    /// `surfaceIndex` maps a surface id to the handle index the bridge's image-handle array holds it at (a surface inside
    /// a filtered group, `GF-C`), `nil` when it has none (the run is dropped).
    init(_ scene: Scene, counts: (rects: Int, glyphs: Int, images: Int, transforms: Int), mainRunCount: Int,
         groupTextureBase: UInt32, textureIndex: @escaping (ImageTexture) -> UInt32,
         surfaceIndex: @escaping (SurfaceID) -> UInt32? = { _ in nil }) {
        var builder = Builder(counts: counts, mainRunCount: mainRunCount, base: groupTextureBase, textureIndex: textureIndex,
                              surfaceIndex: surfaceIndex)
        let quads = builder.visit(scene)
        self = builder.set
        rootQuads = quads
    }

    /// The scene's textures, then those only a group samples (`GO-F`): the one list whose handles the bridge holds, root
    /// textures first so the root's image records keep their indices.
    static func sharedTextures(of scene: Scene) -> [ImageTexture] {
        var seen = Set(scene.textures.map(ObjectIdentifier.init))
        var shared = scene.textures
        func visit(_ scene: Scene) {
            for child in scene.groupScenes {
                visit(child)
                for texture in child.textures where seen.insert(ObjectIdentifier(texture)).inserted { shared.append(texture) }
            }
        }
        visit(scene)
        return shared
    }

    private struct Builder {
        var set = SDLGroupSet()
        let counts: (rects: Int, glyphs: Int, images: Int, transforms: Int)
        let mainRunCount: Int
        let base: UInt32
        let textureIndex: (ImageTexture) -> UInt32
        let surfaceIndex: (SurfaceID) -> UInt32?

        init(counts: (rects: Int, glyphs: Int, images: Int, transforms: Int), mainRunCount: Int, base: UInt32,
             textureIndex: @escaping (ImageTexture) -> UInt32, surfaceIndex: @escaping (SurfaceID) -> UInt32?) {
            self.counts = counts; self.mainRunCount = mainRunCount; self.base = base; self.textureIndex = textureIndex
            self.surfaceIndex = surfaceIndex
        }

        /// Visits `scene`'s groups; returns their quads with `texture` = base + flat index.
        mutating func visit(_ scene: Scene) -> [MUIImage] {
            var quads: [MUIImage] = []
            for (index, quad) in scene.groups.enumerated() {
                let child = scene.groupScenes[index]
                let childQuads = visit(child)
                let rectShift = counts.rects + set.rects.count, glyphShift = counts.glyphs + set.glyphs.count
                let imageShift = counts.images + set.images.count
                let transformShift = counts.transforms + set.transforms.count
                set.rects += child.rects.map { var r = $0; if r.shape >> 8 > 0 { r.shape += MUIUInt(transformShift) << 8 }; return r }
                set.glyphs += child.glyphs.map { var g = $0; if g.transform > 0 { g.transform += MUIUInt(transformShift) }; return g }
                set.transforms += child.transforms
                set.images += child.images.map {
                    var i = $0
                    i.texture = textureIndex(child.textures[Int($0.texture)])
                    if i.filter >> 8 > 0 { i.filter += MUIUInt(transformShift) << 8 }
                    return i
                }
                // The child's surface quads follow its images (`GF-C`): the handle index the bridge holds each target at.
                var surfaceRuns: [Int: Int] = [:]   // child surface index -> flat image index, -1 when dropped
                var keptSurfaces = 0
                for (k, quad) in child.surfaces.enumerated() {
                    guard let handle = surfaceIndex(child.surfaceTargets[Int(quad.texture)].id) else { surfaceRuns[k] = -1; continue }
                    var q = quad
                    q.texture = handle
                    if q.filter >> 8 > 0 { q.filter += MUIUInt(transformShift) << 8 }
                    set.images.append(q)
                    surfaceRuns[k] = imageShift + child.images.count + keptSurfaces
                    keptSurfaces += 1
                }
                // The child's group quads belong to the child's scene: their transform index (a filtered group drawn
                // under a projective record) is shifted like its images'.
                set.images += childQuads.map { var q = $0; if q.filter >> 8 > 0 { q.filter += MUIUInt(transformShift) << 8 }; return q }
                let quadBase = imageShift + child.images.count + keptSurfaces
                let runStart = mainRunCount + set.runs.count
                for run in child.drawList {
                    switch run.kind {
                    case .rect: set.runs.append(ReplayRun(kind: 0, start: UInt32(rectShift + run.start), count: UInt32(run.count)))
                    case .glyph: set.runs.append(ReplayRun(kind: 1, start: UInt32(glyphShift + run.start), count: UInt32(run.count)))
                    case .image: set.runs.append(ReplayRun(kind: 2, start: UInt32(imageShift + run.start), count: UInt32(run.count)))
                    case .group:
                        set.runs.append(ReplayRun(kind: 2, start: UInt32(quadBase + run.start), count: UInt32(run.count)))
                    case .surface:
                        // One target per run (`finalize()` breaks where it changes); a target with no handle drops it.
                        if let flat = surfaceRuns[run.start], flat >= 0 {
                            set.runs.append(ReplayRun(kind: 2, start: UInt32(flat), count: UInt32(run.count)))
                        }
                    case .backdrop: continue   // a group holds no backdrop: it draws its flat tint (`GO-C`)
                    }
                }
                let filter = scene.groupFilters[index]
                set.groups.append(ReplayGroup(x: quad.bounds.origin.x, y: quad.bounds.origin.y,
                                              width: UInt32(quad.bounds.size.width), height: UInt32(quad.bounds.size.height),
                                              run_start: UInt32(runStart),
                                              run_count: UInt32(mainRunCount + set.runs.count - runStart),
                                              filter_kind: filter.kind.rawValue, sigma: filter.sigma,
                                              tint: (filter.tint.x, filter.tint.y, filter.tint.z, filter.tint.w)))
                var flat = quad
                flat.texture = base + MUIUInt(set.groups.count - 1)
                quads.append(flat)
            }
            return quads
        }
    }
}
#endif
