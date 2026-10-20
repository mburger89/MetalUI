import Testing
import MetalUICore
import MetalUILayout
import MetalUIPath
import MetalUIScene
import MetalUITestSupport
@testable import MetalUI

// P4 lane 2 (rulings `OS-H`, `OS-L`, `OS-P`): the pooled scratch through `RasterCache`, where a nested leaf
// re-enters the rasterizer (a shadow of a blurred leaf) and the borrow rule matters.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let radialFill = RadialGradient(colors: [.red, .blue], center: .center, startRadius: px(0), endRadius: px(30))

@MainActor private struct Scene {
    let run: (TransitionHarness) -> Frame
    init<C: Element & ProposalElementGroup>(_ content: C) {
        run = { h in h.frame(0, nil, content, side: 300, scaleFactor: 2) }
    }
}

@MainActor private func scenes() -> [(String, Scene)] {
    [("nested shadow", Scene(ZStack { Color.black.frame(width: px(40), height: px(40)).shadow(radius: px(4)).shadow(radius: px(3)) })),
     ("shadow of text", Scene(ZStack { Text("Hi, you").font(size: 16).shadow(radius: px(4), x: px(2), y: px(1)) })),
     ("blurred text", Scene(ZStack { Text("Hi, you").font(size: 16).blur(radius: px(3)) })),
     ("blurred shadow", Scene(ZStack { Color.red.frame(width: px(30), height: px(30)).blur(radius: px(2)).shadow(radius: px(5)) })),
     ("radial", Scene(ZStack { Rectangle().fill(radialFill).frame(width: px(40), height: px(40)) }))]
}

/// Leaves every slot of `cache.scratch` holding garbage, so a missed zero-fill changes bytes.
@MainActor private func dirty(_ cache: RasterCache) {
    var cells = cache.scratch.takeCells(count: 400_000)
    for i in cells.indices { cells[i] = 3.5 }
    cache.scratch.returnCells(cells)
    for slot in RasterScratch.Slot.allCases {
        var ints = cache.scratch.takeInts(slot, count: 400_000)
        for i in ints.indices { ints[i] = 77 }
        cache.scratch.returnInts(slot, ints)
    }
}

/// Every raster of `scene`, flattened to bytes, computed through the harness's own cache.
@MainActor private func bytes(of scene: Scene, dirtied: Bool) -> [UInt8] {
    let h = TransitionHarness()
    var seen: [(CapturedPrimitive.Kind, PrimitiveTransform?)] = []
    h.store.rasters.onRaster = { kind, transform in seen.append((kind, transform)) }
    if dirtied { dirty(h.store.rasters) }
    let frame = scene.run(h)
    let cache = h.store.rasters
    if dirtied { dirty(cache) }
    var out: [UInt8] = []
    let clip = frame.rasterTarget
    for (kind, transform) in seen {
        switch kind {
        case let .shadow(paint):
            let full = (transform?.affine ?? .identity).concatenating(paint.local)
            var canonical = paint
            canonical.local = .identity
            let mask = frame.shadowCoverage(canonical, full: full, clip: RasterAnchor.shadowExtent(paint, full: full), cache: cache)
            out += mask.alpha
        case let .blur(paint):
            let full = (transform?.affine ?? .identity).concatenating(paint.local)
            var canonical = paint
            canonical.local = .identity
            let layer = frame.blurLayer(canonical, full: full, clip: RasterAnchor.blurExtent(paint, full: full), cache: cache)
            for y in layer.rect.y..<layer.rect.maxY {
                for x in layer.rect.x..<layer.rect.maxX { out += layer.texel(atX: x, y: y).map { $0 } }
            }
        case let .gradient(paint):
            let outer = transform?.affine ?? .identity
            let full = outer.concatenating(paint.local)
            let layer = frame.gradientPixels(paint, full: full, clip: RasterAnchor.gradientExtent(paint, outer: outer), cache: cache)
            for y in layer.rect.y..<layer.rect.maxY {
                for x in layer.rect.x..<layer.rect.maxX { out += layer.texel(atX: x, y: y).map { $0 } }
            }
        default: break
        }
    }
    _ = clip
    return out
}

/// **P1, nested arm** (`OS-L`). Shadow of a shadow, of a blurred leaf, blurred text and a radial gradient
/// rasterized through a cache whose scratch is full of garbage equal the rasters of a clean cache, byte for
/// byte: a nested leaf rasterizes while the outer one has handed its buffers back, and a stale cell would
/// change a byte. Mutations: any `take…` skipping its zero-fill; a call site holding `&cache.scratch` across
/// `silhouette`'s nested call (an exclusivity trap).
@Test @MainActor func aDirtyPooledCacheRastersEqualACleanOnesIncludingNestedLeaves() throws {
    var total = 0
    for (name, scene) in scenes() {
        let clean = bytes(of: scene, dirtied: false)
        let pooled = bytes(of: scene, dirtied: true)
        try #require(clean.count > 1000, "\(name): the scene rasterized something: \(clean.count)")
        #expect(clean == pooled, "\(name): the pooled bytes differ")
        total += clean.count
    }
    #expect(total > 20_000)
}

#if canImport(Darwin)
/// **P3** (`OS-H`). A warm raster does not allocate its scratch: the second `shadowCoverage` of a blurred
/// shadow on a warm `cache.scratch` makes at least four fewer allocations than the same call on a fresh one
/// (cells, the blur's two Int32 planes and its column sums), and a warm gradient at least one fewer. The
/// instrument is thread-filtered and differential (`PA-J`); the fixed allocations cancel. Mutation: no call
/// site passes `&cache.scratch` (each uses a fresh scratch).
@Test @MainActor func aWarmRasterAllocatesNoScratch() throws {
    for (name, scene, least) in [("shadow", scenes()[1].1, 4), ("gradient", scenes()[4].1, 1)] {
        let h = TransitionHarness()
        var seen: [(CapturedPrimitive.Kind, PrimitiveTransform?)] = []
        h.store.rasters.onRaster = { kind, transform in seen.append((kind, transform)) }
        let frame = scene.run(h)
        let cache = h.store.rasters
        let run: () -> Void = {
            for (kind, transform) in seen {
                switch kind {
                case let .shadow(paint):
                    let full = (transform?.affine ?? .identity).concatenating(paint.local)
                    var canonical = paint
                    canonical.local = .identity
                    _ = frame.shadowCoverage(canonical, full: full, clip: RasterAnchor.shadowExtent(paint, full: full), cache: cache)
                case let .gradient(paint):
                    let outer = transform?.affine ?? .identity
                    _ = frame.gradientPixels(paint, full: outer.concatenating(paint.local),
                                             clip: RasterAnchor.gradientExtent(paint, outer: outer), cache: cache)
                default: break
                }
            }
        }
        try #require(!seen.isEmpty, "\(name): a raster was requested")
        run()                                       // warm
        let warm = try #require(countAllocations(run))
        cache.scratch = RasterScratch()
        let cold = try #require(countAllocations(run))
        #expect(cold - warm >= least, "\(name): warm \(warm) allocations, cold \(cold)")
    }
}
#endif
