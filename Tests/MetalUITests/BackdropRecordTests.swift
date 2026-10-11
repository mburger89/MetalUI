import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// Backdrop blur, lane 1, tests 1.1-1.8 (rulings `BB-A`, `BB-B`, `BB-G`, `BB-H`;
// spec `docs/superpowers/specs/2026-10-10-backdrop-blur-design.md` §3.1, §3.6,
// §5). The frame side of a material: every material site emits ONE `MUIBackdrop`
// record (and no tint rect) carrying the `LK-L` table's tint, the shape, the
// clip, the transform index and the opacity. Headless: the finalized `Scene` of
// one `Frame`, no renderer.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private let allMaterials: [(String, Material)] = [
    ("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial),
    ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar),
]

/// Rects that draw anything: a tint rect would show here.
private func tinted(_ scene: Scene) -> [MUIRect] { scene.rects.filter { $0.background.a > 0 } }

// MARK: - 1.1

/// **1.1** (`BB-A`). Every material site emits one backdrop record and no tint
/// rect: the proposal `.background(_:)`, the legacy one, `.background(_:in:)`
/// and `Shape.fill(_:)`. Red before: the scene held a tint rect and no
/// `backdrops`. Mutation: `Material`'s proposal-path site back to
/// `background(material.color)`.
@Test @MainActor func aMaterialBackgroundEmitsOneBackdropRecordAndNoTintRect() throws {
    func check<E: Element>(_ name: String, _ element: E) throws {
        let scene = lkScene(element, side: 100)
        try #require(scene.backdrops.count == 1, "\(name): one backdrop record, got \(scene.backdrops.count)")
        #expect(tinted(scene).isEmpty, "\(name): no tint rect")
        #expect(scene.drawList.filter { $0.kind == .backdrop }.count == 1, "\(name): one backdrop run: \(scene.drawList)")
    }
    try check("proposal background", Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial))
    try check("legacy background", Box().frame(width: px(40), height: px(20)).background(.regularMaterial))
    try check("background(in:)",
              Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial, in: Rectangle()))
    try check("Shape.fill", Rectangle().fill(.regularMaterial).frame(width: px(40), height: px(20)))
    try check("ShapeView.fill", Rectangle().fill(Color.clear).fill(.thinMaterial).frame(width: px(40), height: px(20)))
}

// MARK: - 1.2

/// **1.2** (`BB-A`, `LK-L` item 3). The record's tint is the `LK-L` table for
/// every material in both schemes: straight alpha, the table's grey, the same
/// resolution `Material.color` gives. Mutation: swap two rows of
/// `Material.fill(for:)`.
@Test @MainActor func theBackdropTintIsTheLKLTableForEverySchemeAndMaterial() throws {
    for scheme in [ColorScheme.light, .dark] {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        for (name, material) in allMaterials {
            let scene = lkScene(Column {
                Color.clear.frame(width: px(40), height: px(20)).background(material)
                    .environment(\.colorScheme, scheme)
            }, side: 100)
            let record = try #require(scene.backdrops.first, "\(scheme) \(name): a record")
            let want = material.color.resolve(in: environment)
            let got = Hsla(h: record.tint.h, s: record.tint.s, l: record.tint.l, a: record.tint.a).toRgba()
            #expect(abs(got.r - want.red) < 1e-4 && abs(got.g - want.green) < 1e-4 && abs(got.b - want.blue) < 1e-4
                    && abs(got.a - want.opacity) < 1e-4,
                    "\(scheme) \(name): tint \(got) vs the table \(want)")
        }
    }
}

// MARK: - 1.3

/// **1.3** (`BB-B`, `BB-H`). The record's shape is the filled geometry: a
/// rectangle and a rounded rectangle are `MUIShapeRoundedRect` with the corner
/// radii, a circle the ellipse. Mutation: encode an ellipse as
/// `MUIShapeRoundedRect`.
@Test @MainActor func theBackdropShapeIsTheFilledRoundedRectOrEllipse() throws {
    let rounded = lkScene(RoundedRectangle(cornerRadius: px(9)).fill(.thickMaterial)
        .frame(width: px(40), height: px(20)), side: 100)
    let circle = lkScene(Ellipse().fill(.thickMaterial).frame(width: px(30), height: px(20)), side: 100)
    let rr = try #require(rounded.backdrops.first), ell = try #require(circle.backdrops.first)
    #expect(rr.shape & 0xFF == MUIShapeRoundedRect.rawValue, "rounded rectangle: \(rr.shape)")
    #expect(rr.cornerRadii.topLeft == 9 && rr.cornerRadii.bottomRight == 9, "radii: \(rr.cornerRadii)")
    #expect(ell.shape & 0xFF == MUIShapeEllipse.rawValue, "ellipse: \(ell.shape)")
    #expect(rr.bounds.size.width == 40 && rr.bounds.size.height == 20, "bounds: \(rr.bounds)")
    #expect(rr.sigma == Float(MUIBackdropSigmaPoints), "sigma is 52 points at scale 1: \(rr.sigma)")
    let retina = lkScene(Rectangle().fill(.thickMaterial).frame(width: px(40), height: px(20)),
                         side: 100, scaleFactor: 2)
    let r2 = try #require(retina.backdrops.first)
    #expect(r2.sigma == 2 * Float(MUIBackdropSigmaPoints) && r2.bounds.size.width == 80,
            "sigma is in device pixels: \(r2.sigma), bounds \(r2.bounds)")
}

// MARK: - 1.4

/// **1.4** (`BB-H`, divergence 248). A path filled with a material draws the
/// flat tint: no backdrop record, the path's raster (an image) instead.
/// Pins the degrade by name. Mutation: emit a backdrop for a path.
@Test @MainActor func aPathFilledWithAMaterialDrawsTheFlatTint() throws {
    let scene = lkScene(gxTriangle(40).fill(.regularMaterial).frame(width: px(40), height: px(40)), side: 100)
    #expect(scene.backdrops.isEmpty, "a path fill has no backdrop")
    #expect(scene.images.count == 1, "the path's flat tint is its raster: \(scene.images.count) images")
}

// MARK: - 1.5

/// **1.5** (`BB-A`, probe `O`). `.opacity(0.5)` multiplies the record's
/// opacity and leaves the tint's alpha alone: the layer composites at half
/// weight over the sharp backdrop. Mutation: multiply `tint.a` instead.
@Test @MainActor func opacityMultipliesTheRecordOpacityAndLeavesTheTintAlone() throws {
    let plain = lkScene(Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial), side: 100)
    let faded = lkScene(Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
        .opacity(0.5), side: 100)
    let p = try #require(plain.backdrops.first), f = try #require(faded.backdrops.first)
    #expect(p.opacity == 1 && f.opacity == 0.5, "opacity \(p.opacity) -> \(f.opacity)")
    #expect(f.tint.a == p.tint.a, "the tint's alpha is untouched: \(p.tint.a) vs \(f.tint.a)")
    // The legacy decoration's opacity reaches the record the same way.
    let legacy = lkScene(Box().frame(width: px(40), height: px(20)).background(.regularMaterial).opacity(0.25),
                         side: 100)
    let l = try #require(legacy.backdrops.first)
    #expect(l.opacity == 0.25 && l.tint.a == p.tint.a, "legacy: opacity \(l.opacity), tint \(l.tint.a)")
}

// MARK: - 1.6

/// **1.6** (`BB-B`, `BB-H`). A clip maps into `contentMask` with its radii; an
/// `.offset` flattens into the bounds; a rotation names a transform record
/// (`shape` bits 8...31) and keeps its local bounds. Mutation: drop
/// `contentMask` in `fillBackdrop`.
@Test @MainActor func aClipAndAnOffsetMapIntoTheRecord() throws {
    let panel = Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
    let base = try #require(lkScene(panel, side: 100).backdrops.first)
    let clipped = try #require(lkScene(panel.clipShape(RoundedRectangle(cornerRadius: px(4)))
        .frame(width: px(40), height: px(20)), side: 100).backdrops.first)
    #expect(clipped.contentMask.size.width <= 40 && clipped.contentMask.size.height <= 20,
            "the clip is in the record: \(clipped.contentMask)")
    #expect(clipped.maskCornerRadii.topLeft == 4, "its radii too: \(clipped.maskCornerRadii)")
    #expect(base.contentMask.size.width > 40, "unclipped, the mask is the whole surface: \(base.contentMask)")
    let moved = try #require(lkScene(panel.offset(x: px(10), y: px(5)), side: 100).backdrops.first)
    #expect(moved.bounds.origin.x == base.bounds.origin.x + 10 && moved.bounds.origin.y == base.bounds.origin.y + 5,
            "a flattening offset moves the bounds: \(base.bounds) -> \(moved.bounds)")
    #expect(moved.shape >> 8 == 0, "an offset names no transform record")
    let rotated = lkScene(panel.rotationEffect(.degrees(30)), side: 100)
    let r = try #require(rotated.backdrops.first)
    #expect(r.shape >> 8 == 1 && rotated.transforms.count == 1, "a rotation names transform 1: \(r.shape >> 8)")
    #expect(r.bounds.size.width == 40 && r.bounds.size.height == 20, "local bounds are kept: \(r.bounds)")
}

// MARK: - 1.7

/// **1.7** (`BB-G`). A removal ghost replays the record: half-way through an
/// opacity removal the ghost's record has opacity 0.5 and the tint's alpha is
/// the table's; a drag preview's replay cuts the record's mask; and the two
/// fade flattenings multiply `opacity` on the record, never the tint.
/// Mutation: `multiplyAlpha`'s `.backdrop` arm returns the record unchanged
/// (deleting the arm does not compile, `BB-O` 2).
@Test @MainActor func aTransitionGhostAndADragPreviewReplayTheRecord() throws {
    func stage(_ shown: Bool) -> some Element {
        Column {
            Stack {
                Box().frame(width: px(200), height: px(100))
                if shown {
                    Box().frame(width: px(50), height: px(30)).background(.regularMaterial).transition(.opacity)
                }
            }
        }
    }
    let h = TransitionHarness()
    let rest = try #require(h.frame(0, nil, stage(true)).scene.backdrops.first, "the live record")
    h.frame(0, Animation.linear(duration: 1), stage(false))
    let mid = h.frame(0.5, nil, stage(false))
    let ghost = try #require(mid.scene.backdrops.first, "a ghost replays the record half-way")
    #expect(abs(ghost.opacity - 0.5) < 1e-6, "ghost opacity 1/2: \(ghost.opacity)")
    #expect(ghost.tint.a == rest.tint.a, "the tint is untouched: \(rest.tint.a) vs \(ghost.tint.a)")
    #expect(ghost.bounds.origin.x == rest.bounds.origin.x, "at its last place")
    #expect(h.frame(1.0, nil, stage(false)).scene.backdrops.isEmpty, "gone at the end")

    // The two flattenings and the drag preview's replay, on a captured record.
    var captured = CapturedPrimitive.backdrop(rest, layer: 0, innerMask: false)
    captured.multiplyAlpha(0.5)
    guard case let .backdrop(faded) = captured.kind else { Issue.record("not a backdrop"); return }
    #expect(faded.opacity == 0.5 * rest.opacity && faded.tint.a == rest.tint.a, "multiplyAlpha: \(faded.opacity)")
    let effect = RenderEffect(alpha: 0.5, affine: Affine2D(a: 2, d: 2))
    let mapped = try #require(effect.apply(to: .backdrop(rest, layer: 0, innerMask: false), flattens: true, outer: nil))
    guard case let .backdrop(scaled) = mapped.kind else { Issue.record("not a backdrop"); return }
    #expect(scaled.opacity == 0.5 && scaled.tint.a == rest.tint.a, "apply: opacity \(scaled.opacity)")
    #expect(scaled.bounds.size.width == 2 * rest.bounds.size.width && scaled.sigma == 2 * rest.sigma,
            "apply scales the quad and the blur with the layer: \(scaled.bounds), sigma \(scaled.sigma)")
    let whole = MUIBounds(origin: MUIPoint(x: 5, y: 5), size: MUISize(width: 10, height: 10))
    let replay = CapturedPrimitive.backdrop(rest, layer: 0, innerMask: false).replayed(mask: whole, layer: 7)
    guard case let .backdrop(replayed) = replay.kind else { Issue.record("not a backdrop"); return }
    #expect(replayed.contentMask.size.width == 10 && replay.layer == 7, "a preview cuts the mask: \(replayed.contentMask)")
}

// MARK: - 1.8

/// **1.8** (`BB-H`, divergence 248). A material inside `.shadow`, `.blur` or a
/// `.compositingGroup()` under a shadow draws its flat tint: those scopes
/// rasterize leaves on the CPU and cannot read a GPU backdrop. A bare
/// `.compositingGroup()` changes nothing (the record stays). Mutation: remove
/// the degrade in `insertThroughScopes`.
@Test @MainActor func aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint() throws {
    func panel() -> some ProposalElementGroup {
        Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
    }
    let shadowed = lkScene(panel().shadow(radius: px(3), x: px(2), y: px(2)), side: 100)
    #expect(shadowed.backdrops.isEmpty, "inside a shadow: flat")
    #expect(shadowed.images.count >= 1, "the shadow's and the tint's rasters are images: \(shadowed.images.count)")
    let blurred = lkScene(panel().blur(radius: px(2)), side: 100)
    #expect(blurred.backdrops.isEmpty && blurred.images.count == 1, "inside a blur: flat, one blurred image")
    let grouped = lkScene(panel().compositingGroup().shadow(radius: px(3), x: px(2), y: px(2)), side: 100)
    #expect(grouped.backdrops.isEmpty, "inside a compositing group under a shadow: flat")
    let bare = lkScene(panel().compositingGroup(), side: 100)
    #expect(bare.backdrops.count == 1, "a bare compositing group changes nothing")
    // Legacy: a Box background under a shadow.
    let legacy = lkScene(Box().frame(width: px(40), height: px(20)).background(.regularMaterial)
        .shadow(radius: px(3)), side: 100)
    #expect(legacy.backdrops.isEmpty, "legacy inside a shadow: flat")
}
