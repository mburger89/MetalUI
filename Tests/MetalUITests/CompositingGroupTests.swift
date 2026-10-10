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

// MARK: - L2.9 (divergence 205, CG1)

/// **L2.9** (divergence 205, CG1). `.compositingGroup().opacity(0.5)` is NOT
/// composited: each square is drawn at half alpha, so the overlap shows the
/// lower square through the upper (SwiftUI composites the opacity: CG1 reads
/// (255, 128, 128) at the overlap, MetalUI (191, 64, 128)). **Pinned wrong on
/// purpose**: an offscreen pass would redden it, as a fix.
@Test @MainActor func aCompositingGroupDoesNotCompositeAnOpacity() throws {
    let scene = effectFrame(overlap().compositingGroup().opacity(0.5)).finalizedScene()
    #expect(gxImages(scene).isEmpty, "no offscreen image: \(gxImages(scene).count)")
    try #require(scene.rects.count == 2, "two rects: \(scene.rects.count)")
    #expect(scene.rects.allSatisfy { abs($0.background.a - 0.5) < 0.001 },
            "each at half alpha: \(scene.rects.map(\.background.a))")
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
