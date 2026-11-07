import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C13 / PERF-a, lane 2 — `compositingGroup()` (ruling `PF-E`; spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` §5, §8, tests
// L2.3–L2.11). SwiftUI's side is `docs/probes/swiftui-shadow-cache.swift`,
// arms P1, P2 and CG1–CG7.
//
// A shadow or blur outside a `compositingGroup()` sees the group as ONE leaf:
// one image of the union, drawn before the whole group. The overlap fixture is
// `ShadowTests`' 3.15 (SH5): a 60 × 60 accent square and a separator square
// offset (20, 20), centred in the 200 window, so the stack is at (70, 70).

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The kinds of a finalized scene's draw runs, in draw order.
private func runKinds(_ scene: Scene) -> [PrimitiveKind] { scene.drawList.map(\.kind) }

/// The SH5 overlap: two 60 × 60 squares, the second offset (20, 20).
@MainActor private func overlap() -> some Element & ProposalElementGroup {
    ZStack {
        Color(.accent).frame(width: px(60), height: px(60))
        Color(.separator).frame(width: px(60), height: px(60)).offset(x: px(20), y: px(20))
    }
}

/// A scene's rects and images as bytes, and its run kinds: equal for equal
/// draws.
private func sceneBytes(_ scene: Scene) -> [[UInt8]] {
    [scene.rects.withUnsafeBytes { Array($0) }, scene.images.withUnsafeBytes { Array($0) },
     runKinds(scene).map { UInt8(truncatingIfNeeded: "\($0)".hashValue & 0xFF) }]
}

// MARK: - L2.3, L2.4 (P2, P1)

/// **L2.3** (`PF-E` item 2, P2). `overlap().compositingGroup().shadow(radius:
/// 0, x: 10, y: 10)` draws ONE shadow image before both squares — so the
/// overlap shows the top square, never a shadow — shaped as the union: inked
/// under each square's offset area, clear in the L's notch. The separating
/// arm (**L2.4**, the SH5 pin `aShadowIsDrawnBelowEachLeaf` re-read on this
/// fixture): without the group, two images, shadow–square–shadow–square.
/// Mutation **M2c** (the composite forwards per primitive).
@Test @MainActor func aCompositingGroupCastsOneShadowOfTheUnion() throws {
    let plain = effectFrame(overlap().shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10)))
        .finalizedScene()
    try #require(gxImages(plain).count == 2, "L2.4, per leaf: \(gxImages(plain).count) images")
    try #require(runKinds(plain) == [.image, .rect, .image, .rect], "L2.4 order: \(runKinds(plain))")

    let scene = effectFrame(overlap().compositingGroup()
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one shadow for the group: \(images.map { gxDescribe($0.image.bounds) })")
    #expect(runKinds(scene) == [.image, .rect], "the shadow below the whole group: \(runKinds(scene))")
    #expect(scene.rects.count == 2, "both squares drawn: \(scene.rects.count)")
    let b = images[0].image.bounds
    #expect(b.origin.x == 80 && b.origin.y == 80 && b.size.width == 80 && b.size.height == 80,
            "the union's box, offset 10: \(gxDescribe(b))")
    #expect(gxAlpha(images[0], 85, 85) == 255, "under the first square")
    #expect(gxAlpha(images[0], 155, 155) == 255, "under the second square")
    #expect(gxAlpha(images[0], 115, 115) == 255, "under the overlap")
    #expect(gxAlpha(images[0], 150, 85) == 0, "the L's notch is clear")
}

// MARK: - L2.5 (CG4)

/// **L2.5** (`PF-E` item 2, CG4). With no shadow or blur outside it,
/// `compositingGroup()` pushes no scope and draws the identical scene; under a
/// shadow it pushes one (the separating arm); under a shadow but inside a
/// `Deferred` (past the barrier) none. Mutation **M2d** (the scope always
/// pushed).
@Test @MainActor func aCompositingGroupAloneChangesNothingAndPushesNoScope() throws {
    let bare = effectFrame(overlap())
    let alone = effectFrame(overlap().compositingGroup())
    #expect(alone.compositeScopesPushed == 0, "alone: \(alone.compositeScopesPushed) scopes")
    #expect(sceneBytes(alone.finalizedScene()) == sceneBytes(bare.finalizedScene()), "alone draws the bare scene")
    let shadowed = effectFrame(overlap().compositingGroup().shadow(radius: px(0), x: px(10), y: px(10)))
    try #require(shadowed.compositeScopesPushed == 1, "under a shadow: \(shadowed.compositeScopesPushed) scopes")
    let portal = effectFrame(Column {
        Box().frame(width: px(60), height: px(20)).background(.separator)
        Deferred { Box().frame(width: px(50), height: px(30)).background(.accent).compositingGroup() }
    }
    .frame(width: px(160), height: px(100))
    .shadow(radius: px(0), x: px(10), y: px(10)))
    #expect(portal.compositeScopesPushed == 0, "past a barrier: \(portal.compositeScopesPushed) scopes")
}

// MARK: - L2.6 (MC-A, MC-C)

/// **L2.6** (`PF-E` item 2, `MC-A`/`MC-C`). The proposal `compositingGroup()`
/// is one identity level: the content's ids under it equal those under a
/// one-layer `.padding(0)` chain and differ from the bare content's. Mutation
/// **M2f** (two layers).
@Test @MainActor func theCompositingGroupLayerIsOneIdentityLevel() throws {
    func tapIDs(_ e: some ProposalElementGroup) -> [GlobalElementID] {
        effectFrame(VStack { e }).hitboxes.filter { $0.handlers.gestures.count > 0 }.map(\.id)
    }
    let bare = tapIDs(fxBar(40, 20).onTapGesture {})
    let padded = tapIDs(fxBar(40, 20).onTapGesture {}.padding(Edges(all: px(0))))
    let grouped = tapIDs(fxBar(40, 20).onTapGesture {}.compositingGroup())
    try #require(bare.count == 1 && padded.count == 1 && bare != padded, "the arms disagree: \(bare) \(padded)")
    #expect(grouped == padded, "one level: \(grouped) vs \(padded)")
}

/// Which tree a window's content closure builds; a reference so it survives.
@MainActor private final class TapGeneration { var value = 0 }

/// What a `TapCounter` read in its last paint.
@MainActor private final class TapLog {
    var taps = -1
    var bounds: Bounds<Pixels>?
}

/// A 40 × 40 native leaf with its own `@State`, incremented by a click and
/// logged in paint (`ModifierCompositionProofTests`' `CountingProposalLeaf`,
/// reduced).
private struct TapCounter: ProposalElement {
    @State var taps = 0
    var log: TapLog

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 40)) }, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log.bounds = bounds
        var handlers = Handlers()
        let state = _taps
        handlers.onClick = { state.wrappedValue += 1 }
        pass.registerHandlers(handlers, at: bounds, id: id)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {
        log.taps = taps
        pass.fill(bounds, color: pass.resolve(Color(.accent)))
    }
}

/// `TapCounter` under `.padding(0)`, with `compositingGroup()` added when
/// `grouped`, then a shadow: ONE type either way (`MC-A`), so only the layer
/// count differs.
@MainActor private func tapChain(_ log: TapLog, grouped: Bool) -> ModifiedContent<TapCounter, LayoutModifier> {
    var chain = TapCounter(log: log).padding(Edges(all: px(0)))
    if grouped { chain = chain.compositingGroup() }
    return chain.shadow(radius: px(4))
}

/// **L2.6b** (`MC-A`). Adding `compositingGroup()` at run time resets the
/// content's `@State`, as adding any layer does (one click read 1, then 0);
/// under it, `@State` survives frames (three clicks and two more redraws read
/// 3).
@Test @MainActor func addingACompositingGroupResetsStateAndStateUnderItIsRetained() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = TapLog()
    let generation = TapGeneration()
    let (window, platformWindow) = try makeFakeWindow(device: device, size: 120) {
        HStack { tapChain(log, grouped: generation.value > 0) }
    }
    window.drawFrameIfNeeded()
    let bounds = try #require(log.bounds)
    let centre = Point(x: bounds.origin.x + Pixels(20), y: bounds.origin.y + Pixels(20))
    func click() {
        platformWindow.simulateInput(.mouseDown(MouseEvent(position: centre)))
        platformWindow.simulateInput(.mouseUp(MouseEvent(position: centre)))
        window.drawFrameIfNeeded()
    }
    click()
    try #require(log.taps == 1, "set up: one click: \(log.taps)")
    generation.value = 1
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(log.taps == 0, "a layer added at run time resets the content: \(log.taps)")
    for _ in 0..<3 { click() }
    for _ in 0..<2 {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    #expect(log.taps == 3, "retained across frames under the group: \(log.taps)")
}

// MARK: - L2.7 (CG2)

/// **L2.7** (`PF-E` item 2, CG2). `overlap().compositingGroup().blur(radius:
/// 4)` draws ONE blurred image of the composite, where the plain blur draws
/// two (B2's per-leaf, the separating arm). Mutation **M2c**.
@Test @MainActor func aCompositingGroupIsBlurredAsOneLeaf() throws {
    let plain = gxImages(effectFrame(overlap().blur(radius: px(4))).finalizedScene())
    try #require(plain.count == 2, "per leaf: \(plain.count)")
    let scene = effectFrame(overlap().compositingGroup().blur(radius: px(4))).finalizedScene()
    let images = gxImages(scene)
    try #require(images.count == 1, "one blur for the group: \(images.map { gxDescribe($0.image.bounds) })")
    #expect(scene.rects.isEmpty, "both squares are inside the blurred image: \(scene.rects.count) rects")
    let b = images[0].image.bounds
    #expect(b.size.width > 80 && b.size.height > 80, "covers the union, grown: \(gxDescribe(b))")
}

// MARK: - L2.8 (GX-G)

/// **L2.8** (`PF-E` item 2, `GX-G`). A `Deferred` inside a composited,
/// shadowed column is not part of the group: one shadow, the in-flow bar's (60
/// wide, offset 10), and the presentation's 50 × 30 box drawn as its own rect.
/// Mutation **M2e** (the barrier ignored by the composite).
@Test @MainActor func aDeferredInsideACompositingGroupIsNotShadowed() throws {
    let scene = effectFrame(Column {
        Box().frame(width: px(60), height: px(20)).background(.separator)
        Box().frame(width: px(40), height: px(20)).background(.separator)
        Deferred { Box().frame(width: px(50), height: px(30)).background(.accent) }
    }
    .frame(width: px(160), height: px(100))
    .compositingGroup()
    .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene()
    let bar = try #require(scene.rects.first {
        abs($0.background.h - Theme.light[.separator].h) < 0.001 && $0.bounds.size.width == 60
    }, "the in-flow bar")
    try #require(scene.rects.contains { $0.bounds.size.width == 50 && $0.bounds.size.height == 30 },
                 "the presentation drew")
    let images = gxImages(scene)
    try #require(images.count == 1, "one shadow, the two bars': \(images.map { gxDescribe($0.image.bounds) })")
    let b = images[0].image.bounds
    #expect(b.origin.x == bar.bounds.origin.x + 10 && b.size.width == 60 && b.size.height == 40,
            "the bars' union, offset 10, not the presentation: \(gxDescribe(b)) for \(gxDescribe(bar.bounds))")
}

// MARK: - L2.9 (GO-A, CG1; divergence 205 retired)

/// **L2.9** (`GO-A`, CG1, `GO0`). `.compositingGroup().opacity(0.5)` composites: the two squares draw
/// unfaded into one offscreen group the scene holds as a quad at opacity 0.5, so the overlap reads the top
/// colour over the backdrop (SwiftUI's (255, 128, 128), not red through blue). Mutations: no `withOpacityBase`
/// (the squares fade inside the group as well), marks not added (per primitive), alpha written to colours
/// instead of the mark, the box grown by 0.
@Test @MainActor func aCompositingGroupCompositesAnOpacity() throws {
    let scene = effectFrame(overlap().compositingGroup().opacity(0.5)).finalizedScene()
    try #require(scene.groups.count == 1, "one offscreen group: \(scene.groups.count)")
    #expect(scene.rects.isEmpty && scene.images.isEmpty, "nothing drawn beside the group: \(scene.rects.count) rects")
    let inner = scene.groupScenes[0]
    try #require(inner.rects.count == 2, "two rects in the group: \(inner.rects.count)")
    #expect(inner.rects.allSatisfy { $0.background.a == 1 }, "unfaded inside: \(inner.rects.map(\.background.a))")
    let quad = scene.groups[0]
    #expect(quad.opacity == 0.5, "the group fades as a whole: \(quad.opacity)")
    let b = quad.bounds
    #expect(b.origin.x == 69 && b.origin.y == 69 && b.size.width == 82 && b.size.height == 82,
            "the union (70, 70)-(150, 150) grown one pixel: \(gxDescribe(b))")
    #expect(runKinds(scene) == [.group], "one group run: \(runKinds(scene))")
}

/// **GO0 / CG1** the separating arm: a plain `.opacity(0.5)` on a container stays per primitive.
@Test @MainActor func aPlainOpacityOnAContainerIsPerPrimitive() throws {
    let frame = effectFrame(overlap().opacity(0.5))
    let scene = frame.finalizedScene()
    #expect(scene.groups.isEmpty && frame.compositeScopesPushed == 0, "no group: \(scene.groups.count)")
    try #require(scene.rects.count == 2, "two rects: \(scene.rects.count)")
    #expect(scene.rects.allSatisfy { abs($0.background.a - 0.5) < 0.001 },
            "each at half alpha: \(scene.rects.map(\.background.a))")
}

/// **GO1.** An opacity written inside the group is per primitive (`overlap().opacity(0.5).compositingGroup()`).
@Test @MainActor func anOpacityInsideTheGroupIsPerPrimitive() throws {
    let frame = effectFrame(overlap().opacity(0.5).compositingGroup())
    let scene = frame.finalizedScene()
    #expect(scene.groups.isEmpty && frame.compositeScopesPushed == 0, "no group: \(scene.groups.count)")
    #expect(scene.rects.count == 2 && scene.rects.allSatisfy { abs($0.background.a - 0.5) < 0.001 }, "per leaf")
}

/// **CG4 / GO-A.** A group alone, at opacity 1 or with a pure-0 opacity changes nothing and pushes no scope.
@Test @MainActor func aGroupAloneOrAtFullOpacityChangesNothing() throws {
    let bare = effectFrame(overlap())
    for element in [effectFrame(overlap().compositingGroup()), effectFrame(overlap().compositingGroup().opacity(1))] {
        #expect(element.compositeScopesPushed == 0, "scopes: \(element.compositeScopesPushed)")
        #expect(sceneBytes(element.finalizedScene()) == sceneBytes(bare.finalizedScene()), "draws the bare scene")
    }
    let zero = effectFrame(overlap().compositingGroup().opacity(0))
    #expect(zero.compositeScopesPushed == 0 && zero.finalizedScene().groups.isEmpty, "opacity 0 is per primitive")
}

/// **GO-C.** A group of one primitive is baked into the primitive's colour: no offscreen pass.
@Test @MainActor func aSingleLeafGroupIsBaked() throws {
    let frame = effectFrame(fxBar(60, 30).compositingGroup().opacity(0.5))
    let scene = frame.finalizedScene()
    #expect(scene.groups.isEmpty, "no group quad")
    try #require(scene.rects.count == 1, "one rect")
    #expect(abs(scene.rects[0].background.a - 0.5) < 0.001, "faded by its colour: \(scene.rects[0].background.a)")
    #expect(frame.groupsBaked == 1 && frame.groupsComposited == 0, "baked \(frame.groupsBaked)")
}

/// **GO2 / GO4.** Two opacities multiply on one group; a group inside a group nests, each its own quad.
@Test @MainActor func nestedGroupsNest() throws {
    let twice = effectFrame(overlap().compositingGroup().opacity(0.5).opacity(0.5)).finalizedScene()
    try #require(twice.groups.count == 1, "one group")
    #expect(abs(twice.groups[0].opacity - 0.25) < 0.0001, "0.5 x 0.5: \(twice.groups[0].opacity)")
    let nested = effectFrame(ZStack {
        overlap().compositingGroup().opacity(0.5)
        Color(.textPrimary).frame(width: px(30), height: px(30))
    }.compositingGroup().opacity(0.5)).finalizedScene()
    try #require(nested.groups.count == 1, "outer group: \(nested.groups.count)")
    let outer = nested.groupScenes[0]
    try #require(outer.groups.count == 1, "inner group inside the outer: \(outer.groups.count)")
    #expect(outer.groups[0].opacity == 0.5 && nested.groups[0].opacity == 0.5, "each at its own 0.5")
    #expect(outer.groupScenes[0].rects.count == 2 && outer.rects.count == 1, "two in the inner, the green square in the outer")
}

// MARK: - L2.10 (divergence 108)

/// **L2.10** (`PF-E` item 2, divergence 108). The legacy `compositingGroup()`
/// joins the render effects in written order: `.compositingGroup().shadow(…)`
/// on a two-bar column casts one shadow; `.shadow(…).compositingGroup()` casts
/// one per bar (the group is inside the shadow, with nothing outside it).
@Test @MainActor func theLegacyCompositingGroupJoinsRenderEffectsInWrittenOrder() throws {
    let grouped = gxImages(effectFrame(Column {
        Box().frame(width: px(60), height: px(20)).background(.separator)
        Box().frame(width: px(40), height: px(20)).background(.separator)
    }
    .frame(width: px(160), height: px(100))
    .compositingGroup()
    .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene())
    let perLeaf = gxImages(effectFrame(Column {
        Box().frame(width: px(60), height: px(20)).background(.separator)
        Box().frame(width: px(40), height: px(20)).background(.separator)
    }
    .frame(width: px(160), height: px(100))
    .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))
    .compositingGroup()).finalizedScene())
    try #require(perLeaf.count == 2, "the group inside the shadow: per leaf: \(perLeaf.count)")
    #expect(grouped.count == 1, "the group outside the shadow's leaves: one: \(grouped.count)")
}

// MARK: - L2.11 (PF-E, the report's ask 2)

/// MetalCreator's node (`RasterAnchorTests`' fixture): nine leaves.
@MainActor private func nodeContent() -> some Element & ProposalElementGroup {
    VStack(spacing: px(2)) {
        RoundedRectangle(cornerRadius: 4).fill(.accent).frame(width: px(70), height: px(12))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(50), height: px(6))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(40), height: px(6))
        Color(.separator).frame(width: px(60), height: px(6))
        Color(.separator).frame(width: px(30), height: px(6))
        Circle().fill(.accent).frame(width: px(10), height: px(10))
        Text("Node").font(size: 11)
    }
}

/// **L2.11** (`PF-E`, `PF-G`). A nine-leaf node under
/// `.compositingGroup().shadow(radius: 10)` blurs ONE mask: one shadow image,
/// and the frame's blurred pixels are exactly that image's area; per leaf (the
/// separating arm) nine images and blurred pixels the sum of the seven distinct
/// textures' areas (the three 60-wide bars share one cached raster, `PF-A`).
/// Mutation **M2c**.
@Test @MainActor func aCompositedNodeBlursOneMask() throws {
    func work(_ e: some Element) -> (blurred: Int, images: [(image: MUIImage, texture: ImageTexture)]) {
        let h = TransitionHarness()
        let frame = h.frame(0, nil, e, side: 300, scaleFactor: 1)
        return (h.store.rasters.lastBlurredPixels, gxImages(frame.finalizedScene()))
    }
    let plain = work(nodeContent().shadow(radius: px(10)))
    try #require(plain.images.count == 9, "per leaf: \(plain.images.count)")
    // Equal leaves share one cached raster (`PF-A`: the three 60-wide bars
    // differ only by position), so per leaf blurs each DISTINCT texture once.
    var seen = Set<ObjectIdentifier>()
    let plainArea = plain.images.reduce(0) {
        seen.insert(ObjectIdentifier($1.texture)).inserted ? $0 + $1.texture.width * $1.texture.height : $0
    }
    try #require(seen.count == 7, "seven distinct leaf shapes: \(seen.count)")
    try #require(plain.blurred == plainArea, "per leaf blurs each distinct image: \(plain.blurred) vs \(plainArea)")
    let grouped = work(nodeContent().compositingGroup().shadow(radius: px(10)))
    try #require(grouped.images.count == 1, "one shadow: \(grouped.images.count)")
    let area = grouped.images[0].texture.width * grouped.images[0].texture.height
    #expect(grouped.blurred == area, "one padded mask: \(grouped.blurred) vs \(area)")
    #expect(grouped.blurred < plain.blurred, "less work than per leaf: \(grouped.blurred) vs \(plain.blurred)")
}

// MARK: - L2.12 (PF-E, the inner clip through the scope)

/// A 60 × 60 square clipped to its left 30 points.
@MainActor private func clippedSquare() -> some Element & ProposalElementGroup {
    Color(.accent).frame(width: px(60), height: px(60))
        .frame(width: px(30), height: px(60)).clipped()
}

/// **L2.12** (`PF-E` item 2). A `.clipped()` inside a composited, shadowed
/// group keeps its mask when the composite's captures pass through the shadow
/// (`PaintScope.captureDepths`, `insertThroughScopes(leaf:depths:)`): the
/// group's shadow is the per-leaf shadow texel for texel — 30 wide, offset 10,
/// alpha 0 where the unclipped square would reach. Mutation **Xa** (the depths
/// dropped: the group's shadow reads 60 wide).
@Test @MainActor func aClipInsideACompositingGroupCutsItsShadow() throws {
    let per = gxImages(effectFrame(clippedSquare()
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene())
    let group = gxImages(effectFrame(clippedSquare().compositingGroup()
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene())
    try #require(per.count == 1 && group.count == 1,
                 "one shadow each: \(per.map { gxDescribe($0.image.bounds) }) / \(group.map { gxDescribe($0.image.bounds) })")
    let b = per[0].image.bounds
    try #require(b.size.width == 30 && b.size.height == 60, "the per-leaf shadow is clipped: \(gxDescribe(b))")
    #expect(group[0].image.bounds.size.width == 30, "the group's shadow is clipped: \(gxDescribe(group[0].image.bounds))")
    var diff = 0
    var outside = 0
    let x0 = Int(b.origin.x), y0 = Int(b.origin.y)
    for y in y0 - 20..<y0 + Int(b.size.height) + 20 {
        for x in x0 - 20..<x0 + 60 + 20 {
            if gxAlpha(per[0], x, y) != gxAlpha(group[0], x, y) { diff += 1 }
            if x >= x0 + 30, gxAlpha(group[0], x, y) != 0 { outside += 1 }
        }
    }
    #expect(diff == 0, "texel for texel: \(diff) differ")
    #expect(outside == 0, "nothing past the clip: \(outside) texels")
}

/// **L2.13** (`PF-E` item 2, through an effect). The same clipped square with
/// an `.offset` between the `compositingGroup()` and the shadow: the effect's
/// arm of `insertThroughScopes` keeps each capture's clip depth (`emitted =
/// kept`), so the group's shadow is still 30 wide. Mutation **C1** (record §90
/// §5: `emitted = nil` in that arm) reads 60 wide and reddens this test alone.
@Test @MainActor func aClipInsideACompositingGroupUnderAnEffectCutsItsShadow() throws {
    let group = gxImages(effectFrame(clippedSquare().compositingGroup().offset(x: px(4), y: px(0))
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene())
    try #require(group.count == 1, "one shadow: \(group.map { gxDescribe($0.image.bounds) })")
    #expect(group[0].image.bounds.size.width == 30, "the group's shadow is clipped: \(gxDescribe(group[0].image.bounds))")
}

// MARK: - GO-A, GO-C, GO-G, GO-H (record 218)

/// A legacy two-tile group (`GO0`'s overlap in the legacy vocabulary), under `if shown` with `.transition(.opacity)`.
@MainActor private func fadingGroup(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown {
                Column {
                    Box().frame(width: px(60), height: px(20)).background(.accent)
                    Box().frame(width: px(60), height: px(20)).background(.separator)
                }
                .compositingGroup()
                .transition(.opacity)
            }
        }
    }
}

/// **GO-B.** A transition written outside a group fades the **group**: at half way the scene holds one group quad at
/// 0.5 and the tiles inside it are unfaded. Mutation: `RenderEffect.apply`'s flattening branch multiplies the colours
/// (the tiles fade inside the group as well, the quad stays 1).
@Test @MainActor func aTransitionFadeOutsideAGroupFadesTheGroup() throws {
    let h = TransitionHarness()
    h.frame(0, nil, fadingGroup(false))
    h.frame(0, Animation.linear(duration: 1), fadingGroup(true))
    let mid = h.frame(0.5, nil, fadingGroup(true)).finalizedScene()
    try #require(mid.groups.count == 1, "one group at half way: \(mid.groups.count)")
    #expect(abs(mid.groups[0].opacity - 0.5) < 0.001, "the group fades: \(mid.groups[0].opacity)")
    #expect(mid.groupScenes[0].rects.allSatisfy { $0.background.a == 1 }, "unfaded inside")
    let settled = h.frame(2, nil, fadingGroup(true)).finalizedScene()
    #expect(settled.groups.isEmpty && settled.rects.count >= 2, "settled: drawn plainly, no group")
}

/// An unannotated `if` unit holding a half-opaque group: its removal fades by the default ghost (`XF-H`), cut from the
/// previous frame's scene by sequence range.
@MainActor private func plainGroupUnit(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown {
                overlap().compositingGroup().opacity(0.5)
            }
        }
    }
}

/// **GO-G.** A removed unit holding a group fades its ghost as one group: the previous scene's group quad is expanded
/// into captured primitives under one mark and the default fade multiplies that mark (0.5 x 0.5 at half way).
/// Mutation: the `.group` arm of `Scene.capturedPrimitives` returns nothing (no ghost).
@Test @MainActor func aRemovedUnitHoldingAGroupFadesItsGhostAsOneGroup() throws {
    let h = TransitionHarness()
    let rest = h.frame(0, nil, plainGroupUnit(true)).finalizedScene()
    try #require(rest.groups.count == 1, "set up: the unit holds a group at rest")
    h.frame(0, Animation.linear(duration: 1), plainGroupUnit(false))
    let mid = h.frame(0.5, nil, plainGroupUnit(false)).finalizedScene()
    try #require(mid.groups.count == 1, "the ghost is one group: \(mid.groups.count)")
    #expect(abs(mid.groups[0].opacity - 0.25) < 0.001, "0.5 x the ghost's 0.5: \(mid.groups[0].opacity)")
    #expect(mid.groupScenes[0].rects.count == 2 && mid.groupScenes[0].rects.allSatisfy { $0.background.a == 1 }, "both squares, unfaded inside")
}

/// **GO-C.** A `Deferred` inside a group is not in it (its content is never faded from outside).
@Test @MainActor func aDeferredInsideAGroupIsNotInIt() throws {
    let scene = effectFrame(ZStack {
        Column {
            Box().frame(width: px(60), height: px(20)).background(.separator)
            Box().frame(width: px(60), height: px(20)).background(.separator)
            Deferred { Box().frame(width: px(50), height: px(30)).background(.accent) }
        }
        .frame(width: px(160), height: px(100)).compositingGroup()
    }.opacity(0.5)).finalizedScene()
    try #require(scene.groups.count == 1, "the in-flow bars group")
    #expect(scene.groupScenes[0].rects.count == 2, "two bars in the group: \(scene.groupScenes[0].rects.map { ($0.bounds.size.width, $0.bounds.size.height, $0.background.a) })")
    #expect(scene.rects.contains { $0.bounds.size.width == 50 && $0.background.a == 1 }, "the presentation outside, unfaded")
}

/// **GO-C.** A box above 8192 on a side is drawn per primitive (counted), not as a group. Mutation: no limit.
@Test @MainActor func anOversizeGroupIsBaked() throws {
    let frame = effectFrame(VStack(spacing: px(0)) {
        Color(.accent).frame(width: px(9000), height: px(10))
        Color(.separator).frame(width: px(9000), height: px(10))
    }.compositingGroup().opacity(0.5), side: 10_000)
    let scene = frame.finalizedScene()
    #expect(frame.groupsFlattenedOversize == 1 && scene.groups.isEmpty, "flattened: \(frame.groupsFlattenedOversize)")
    #expect(scene.rects.count == 2 && scene.rects.allSatisfy { abs($0.background.a - 0.5) < 0.001 }, "per primitive at 0.5")
}

/// **GO-A / divergence 222.** A group holding a material keeps its live backdrop: not marked, the opacity multiplies
/// each primitive (the backdrop record's opacity) and no group is made.
@Test @MainActor func aMaterialInsideAnOpacityGroupKeepsItsBackdrop() throws {
    let scene = effectFrame(ZStack {
        Color(.accent).frame(width: px(60), height: px(60))
        Color.clear.frame(width: px(40), height: px(40)).background(.regularMaterial)
    }.compositingGroup().opacity(0.5)).finalizedScene()
    #expect(scene.groups.isEmpty, "no group")
    try #require(scene.backdrops.count == 1, "the backdrop stays a backdrop: \(scene.backdrops.count)")
    #expect(abs(scene.backdrops[0].opacity - 0.5) < 0.001, "faded by its opacity: \(scene.backdrops[0].opacity)")
}

// `aShadowOutsideAnOpacityGroupStillCompositesTheGroup` is `aShadowOutsideAnOpacityGroupCastsTheCompositesShadow` since GF-A
// (GroupFilterTests.swift): divergence 221 is retired.
