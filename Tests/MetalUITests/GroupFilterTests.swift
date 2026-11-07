import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// R4-5 PR B (ruling prefix `GF-`, record 219; probe `docs/probes/swiftui-group-filter.swift`). A shadow or blur outside an
// opacity group lifts the mark every leaf shares (GF0 reads model F: the fade is applied to the shadow and the content as
// one group), and a leaf the CPU cannot read goes through an offscreen group the renderers filter (a GPU surface,
// divergence 167; a leaf under a projective effect, 1066; a leaf still inside an opacity group).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let yAxis: (x: Double, y: Double, z: Double) = (0, 1, 0)

/// The SH5 overlap: two 60 x 60 squares, the second offset (20, 20), centred in the 200 window (the stack at (70, 70)).
@MainActor private func overlap() -> some Element & ProposalElementGroup {
    ZStack {
        Color(.accent).frame(width: px(60), height: px(60))
        Color(.separator).frame(width: px(60), height: px(60)).offset(x: px(20), y: px(20))
    }
}

@MainActor private func shadowed<E: Element>(_ element: E) -> some Element where E: ProposalElementGroup {
    element.shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))
}

/// Indices of `scene`'s groups whose filter is `kind`.
private func groups(_ scene: Scene, _ kind: Scene.GroupFilter.Kind) -> [Int] {
    scene.groupFilters.indices.filter { scene.groupFilters[$0].kind == kind }
}

// MARK: - GF-A: lifting (T1 to T4, T12)

/// **T1** (`GF-A`, probe `GF0`: model F; divergence 221 retired). A shadow written outside an opacity group is cast by the
/// **unfaded** composite and joins the group's opacity: one group holds the shadow and both squares, the shadow's
/// silhouette has the full shadow-colour alpha (the control without the opacity reads the same), and the quad fades the
/// whole at 0.5. Mutations: the lifting replaced by `bakedGroupAlpha` (the silhouette reads half); a fresh token for the
/// shadow item (model S: two groups).
@Test @MainActor func aShadowOutsideAnOpacityGroupCastsTheCompositesShadow() throws {
    let scene = effectFrame(shadowed(overlap().compositingGroup().opacity(0.5))).finalizedScene()
    let control = effectFrame(shadowed(overlap().compositingGroup())).finalizedScene()
    try #require(scene.groups.count == 1, "the shadow and the content are one group (F): \(scene.groups.count)")
    #expect(scene.groups[0].opacity == 0.5, "the whole fades: \(scene.groups[0].opacity)")
    #expect(scene.groupFilters == [.none], "an opacity group, not a filtered one: \(scene.groupFilters)")
    let inner = scene.groupScenes[0]
    #expect(inner.rects.count == 2 && inner.rects.allSatisfy { $0.background.a == 1 }, "both squares, unfaded inside")
    let shadows = gxImages(inner)
    try #require(shadows.count == 1 && gxImages(control).count == 1, "one shadow of the union")
    let want = gxAlpha(gxImages(control)[0], 155, 155)
    try #require(want > 0, "set up: the control casts at (155, 155): \(want)")
    #expect(gxAlpha(shadows[0], 155, 155) == want, "the silhouette is unfaded: \(gxAlpha(shadows[0], 155, 155)) for \(want)")
    #expect(inner.drawList.map(\.kind) == [.image, .rect], "the shadow under the squares: \(inner.drawList.map(\.kind))")
}

/// **T2** (`GF-A`; divergence 221 retired). A blur outside an opacity group blurs the **composite** and fades the blurred
/// image: one image, no group, its raster holds the top colour at the overlap unfaded (alpha 255), and the quad's
/// opacity is 0.5. Mutation: per-leaf baking (the raster holds alpha 128).
@Test @MainActor func aBlurOutsideAnOpacityGroupBlursTheComposite() throws {
    let scene = effectFrame(overlap().compositingGroup().opacity(0.5).blur(radius: px(4))).finalizedScene()
    #expect(scene.groups.isEmpty, "a CPU blur, no group: \(scene.groups.count)")
    let images = gxImages(scene)
    try #require(images.count == 1, "one blurred image: \(images.count)")
    #expect(images[0].image.opacity == 0.5, "faded as the image: \(images[0].image.opacity)")
    #expect(gxAlpha(images[0], 110, 110) == 255, "unfaded inside the raster: \(gxAlpha(images[0], 110, 110))")
}

/// **T3** (`GF-A`). The CPU raster never holds the alpha, so a fade of a shadowed group makes no texture and rasters no
/// pixel after its first frame. Mutation: the alpha left in the leaf (`bakedGroupAlpha` in `processScopes`).
@Test @MainActor func aFadeOfAShadowedGroupRastersNothingAfterItsFirstFrame() throws {
    func tree(_ alpha: Float) -> some Element { shadowed(overlap().compositingGroup().opacity(alpha)) }
    let h = TransitionHarness()
    h.frame(0, nil, tree(0.5), side: 200)
    let rasters = h.store.rasters
    try #require(rasters.lastTexturesMade > 0, "set up: the first frame rastered: \(rasters.lastTexturesMade)")
    let second = h.frame(1, nil, tree(0.4), side: 200).finalizedScene()
    try #require(second.groups.count == 1 && second.groups[0].opacity == 0.4, "the fade moved: \(second.groups.map(\.opacity))")
    #expect(rasters.lastTexturesMade == 0 && rasters.lastRasterizedPixels == 0,
            "nothing rastered: \(rasters.lastTexturesMade) textures, \(rasters.lastRasterizedPixels) px")
}

/// **T4** (`GF-A`, probe `GF4`). A leaf whose marks are mixed (part of it in an inner opacity group) is filtered on the
/// GPU: one filtered group, shadow kind, whose scene holds the inner opacity group and the unfaded square. Mutation:
/// `needsGPU` ignores marks.
@Test @MainActor func aMixedMarkLeafIsFilteredOffscreen() throws {
    let frame = effectFrame(shadowed(ZStack {
        overlap().compositingGroup().opacity(0.5)
        Color(.accent).frame(width: px(30), height: px(30)).offset(x: px(100), y: px(100))
    }.compositingGroup()))
    let scene = frame.finalizedScene()
    #expect(frame.filterGroups == 1, "one filtered group: \(frame.filterGroups)")
    let filtered = groups(scene, .shadow)
    try #require(filtered.count == 1, "a shadow group: \(scene.groupFilters)")
    let inner = scene.groupScenes[filtered[0]]
    #expect(inner.groups.count == 1 && inner.groups[0].opacity == 0.5, "the inner opacity group composites inside it")
    #expect(inner.rects.count == 1, "the unmarked square beside it: \(inner.rects.count)")
}

/// **T12** (`GF-A` item 6). A shadow of an unmarked, surface-free, affine leaf stays on the CPU: no group, one image, no
/// filtered group counted. Mutation: `needsGPU` returning true.
@Test @MainActor func aShadowOfAnUnmarkedAffineLeafStaysOnTheCPU() throws {
    let frame = effectFrame(shadowed(Color(.accent).frame(width: px(40), height: px(40))))
    let scene = frame.finalizedScene()
    #expect(scene.groups.isEmpty && frame.filterGroups == 0, "no group: \(scene.groups.count)")
    #expect(gxImages(scene).count == 1 && scene.rects.count == 1, "the shadow image and the square")
}

// MARK: - GF-B: the filtered group (T5 to T8, T11)

/// **T5** (`GF-A`, divergence 167 retired in code; `LK-K` item 5). A GPU surface under a blur is blurred offscreen: no
/// root surface, one blur group (sigma = radius) whose scene holds the surface, the colour leaf still a CPU image.
/// Mutation: the 167 skip restored.
@Test @MainActor func aSurfaceUnderBlurIsBlurredOffscreen() throws {
    let scene = lkScene(VStack(spacing: 0) {
        GPUSurface(value: 1) { _ in }.frame(width: px(40), height: px(40))
        Color(.accent).frame(width: px(40), height: px(40))
    }.blur(radius: px(4)), side: 200, scaleFactor: 2)
    #expect(scene.surfaces.isEmpty, "no surface at the root: \(scene.surfaces.count)")
    let blurred = groups(scene, .blur)
    try #require(blurred.count == 1, "one blur group: \(scene.groupFilters)")
    #expect(scene.groupFilters[blurred[0]].sigma == 8, "sigma = 4 x the scale: \(scene.groupFilters[blurred[0]].sigma)")
    #expect(scene.groupScenes[blurred[0]].surfaces.count == 1, "the surface inside the group")
    #expect(scene.allSurfaceTargets().count == 1, "the target is still referenced: \(scene.allSurfaceTargets().count)")
    #expect(gxImages(scene).count == 1, "the colour leaf, blurred on the CPU: \(gxImages(scene).count)")
}

/// **T11** (`GF-A`; divergence 104 narrowed). A surface's shadow follows its pixels: a shadow group holding the surface,
/// not an image of its quad. Mutation: the surface arm of `needsGPU` removed (the quad silhouette returns).
@Test @MainActor func aSurfacesShadowFollowsItsPixels() throws {
    let scene = effectFrame(GPUSurface(redraw: .onDemand) { _ in }.frame(width: px(50), height: px(30))
        .shadow(color: .textPrimary, radius: px(0), x: px(10), y: px(10))).finalizedScene()
    let shadow = groups(scene, .shadow)
    try #require(shadow.count == 1, "a shadow group: \(scene.groupFilters)")
    #expect(gxImages(scene).isEmpty, "no CPU image of the quad: \(gxImages(scene).count)")
    #expect(scene.groupScenes[shadow[0]].surfaces.count == 1, "the surface is the silhouette's source")
    #expect(scene.surfaces.count == 1, "the surface itself still draws at the root: \(scene.surfaces.count)")
}

/// **T6** (`GF-A`; divergence 1066 retired). A leaf under a projective effect casts a shadow and is blurred offscreen: the
/// group's scene holds the projective record. The affine control is still a CPU image. Mutations: the `casting` filter
/// restored (the shadow group disappears); the projective blur skip restored.
@Test @MainActor func aProjectiveLeafCastsAShadowOffscreen() throws {
    let affine = effectFrame(Color(.accent).frame(width: px(60), height: px(40)).rotationEffect(.degrees(20))
        .shadow(color: .textPrimary, radius: px(3), x: px(2), y: px(2))).finalizedScene()
    #expect(gxImages(affine).count == 1 && affine.groups.isEmpty, "control: the affine effect's leaf is a CPU shadow")
    let scene = effectFrame(Color(.accent).frame(width: px(60), height: px(40))
        .rotation3DEffect(.degrees(40), axis: yAxis).shadow(color: .textPrimary, radius: px(3), x: px(2), y: px(2)))
        .finalizedScene()
    let shadow = groups(scene, .shadow)
    try #require(shadow.count == 1, "a shadow group: \(scene.groupFilters)")
    #expect(scene.groupScenes[shadow[0]].transforms.contains { $0.det3 != 0 }, "the projective record draws inside it")
}

@Test @MainActor func aProjectiveLeafUnderBlurIsBlurred() throws {
    let scene = effectFrame(Color(.accent).frame(width: px(60), height: px(40))
        .rotation3DEffect(.degrees(40), axis: yAxis).blur(radius: px(3))).finalizedScene()
    let blurred = groups(scene, .blur)
    try #require(blurred.count == 1, "a blur group: \(scene.groupFilters)")
    #expect(scene.groupScenes[blurred[0]].transforms.contains { $0.det3 != 0 }, "the projective record draws inside it")
    #expect(scene.rects.isEmpty, "nothing drawn unblurred: \(scene.rects.count)")
}

/// **T7** (`GF-B` item 4). The box covers the reach in whole levels: a 40 x 40 surface at (80, 80) blurred with sigma 12
/// (L = 2) grows by ceil(36) + 1 = 37 to (43, 43)-(157, 157) = 114 on a side, widened to 116, a multiple of 4. Mutations:
/// the pad removed; the 2^L rounding removed.
@Test @MainActor func aFilteredGroupsBoxCoversTheReachInWholeLevels() throws {
    let scene = effectFrame(GPUSurface(value: 1) { _ in }.frame(width: px(40), height: px(40)).blur(radius: px(12)))
        .finalizedScene()
    let blurred = groups(scene, .blur)
    try #require(blurred.count == 1, "a blur group: \(scene.groupFilters)")
    let box = scene.groups[blurred[0]].bounds
    #expect(gxDescribe(box) == "(43.0, 43.0, 116.0×116.0)", "the box: \(gxDescribe(box))")
    #expect(Int(box.size.width) % 4 == 0 && Int(box.size.height) % 4 == 0, "whole levels")
    #expect(scene.groupFilters[blurred[0]].sigma == 12, "sigma: \(scene.groupFilters[blurred[0]].sigma)")
    #expect(ImageFilter(rawValue: scene.groups[blurred[0]].filter & 0xFF) == .linear, "read linearly at L = 2")
}

/// **T8** (`GF-G`). A filtered leaf above 8192 on a side takes the CPU raster, counted: the shadow of a 9000 wide surface
/// is an image again and no group is made. Mutation: the limit removed.
@Test @MainActor func anOversizeFilteredLeafFallsBackToTheCPU() throws {
    let frame = effectFrame(GPUSurface(value: 1) { _ in }.frame(width: px(9000), height: px(20))
        .shadow(color: .textPrimary, radius: px(0), x: px(2), y: px(2)), side: 10_000)
    let scene = frame.finalizedScene()
    #expect(frame.filtersFlattenedOversize == 1 && frame.filterGroups == 0, "counted: \(frame.filtersFlattenedOversize)")
    #expect(scene.groups.isEmpty && gxImages(scene).count == 1, "the CPU image of the quad: \(gxImages(scene).count)")
}

// MARK: - GF-D: ghosts

@MainActor private func blurredSurfaceUnit(_ shown: Bool) -> some Element {
    Column {
        Stack {
            Box().frame(width: px(200), height: px(100))
            if shown {
                GPUSurface(value: 1) { _ in }.frame(width: px(40), height: px(40)).blur(radius: px(4))
            }
        }
    }
}

/// **T9** (`GF-D`). A removed unit holding a blurred surface fades its ghost as a blurred surface: the ghost frame still
/// holds a filtered group (the blur, at the default fade's alpha). Mutation: `capturedGroup`'s filtered arm yields the
/// bare leaves (no blur group).
@Test @MainActor func aGhostOfABlurredSurfaceStaysBlurred() throws {
    let h = TransitionHarness()
    let rest = h.frame(0, nil, blurredSurfaceUnit(true)).finalizedScene()
    try #require(groups(rest, .blur).count == 1, "set up: the unit holds a blur group at rest: \(rest.groupFilters)")
    h.frame(0, Animation.linear(duration: 1), blurredSurfaceUnit(false))
    let mid = h.frame(0.5, nil, blurredSurfaceUnit(false)).finalizedScene()
    let ghost = groups(mid, .blur)
    try #require(ghost.count == 1, "the ghost is still a blur group: \(mid.groupFilters)")
    #expect(abs(mid.groups[ghost[0]].opacity - 0.5) < 0.001, "faded by the default fade: \(mid.groups[ghost[0]].opacity)")
    #expect(mid.groupScenes[ghost[0]].surfaces.count == 1, "the surface inside")
}
