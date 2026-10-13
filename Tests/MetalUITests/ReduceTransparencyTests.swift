import Testing
import Foundation
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// C27 lane B — Reduce Transparency, the frame side (rulings `MT-D`, `MT-F`, `MT-H`, `MT-I`;
// spec `docs/superpowers/specs/2026-10-12-material-followups-design.md`, tests 8-12).
// With `accessibilityReduceTransparency` true every material site draws the
// scheme's material grey at alpha 1 as an ordinary rect (or path raster): no
// backdrop record, so no split, no blur and no frame-target copy. Headless: the
// finalized `Scene` of one `Frame`; the setting is written by a scope (the
// module's own `internal(set)`), as `TransitionTests` writes Reduce Motion.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// `element` under Reduce Transparency `reduce` and `scheme`, as one frame.
@MainActor private func rtFrame<E: Element>(_ element: E, reduce: Bool, scheme: ColorScheme = .light,
                                            side: Float = 100) -> Frame {
    effectFrame(Column { element }
        .environment(\.accessibilityReduceTransparency, reduce)
        .environment(\.colorScheme, scheme), side: side)
}

@MainActor private func rtScene<E: Element>(_ element: E, reduce: Bool, scheme: ColorScheme = .light) -> Scene {
    rtFrame(element, reduce: reduce, scheme: scheme).finalizedScene()
}

/// The `LK-L` table's grey for the two materials these tests use, as literals
/// (not through `Material`): ultraThin and regular, by scheme.
private let rtGrey: [ColorScheme: [String: Float]] = [
    .light: ["ultraThin": 0.9250, "regular": 0.9121],
    .dark: ["ultraThin": 0.2248, "regular": 0.2045],
]

private let rtMaterials: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("regular", .regularMaterial)]

/// The 40 x 20 rects of `scene` (the panels these tests draw).
private func panels(_ scene: Scene) -> [MUIRect] {
    scene.rects.filter { $0.bounds.size.width == 40 && $0.bounds.size.height == 20 && $0.background.a > 0 }
}

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

// MARK: - 8

/// **8** (`MT-F`, `MT-I`). Every material site draws an opaque rect under Reduce
/// Transparency, in both schemes: no backdrop record, and the rect is the table's
/// grey at alpha 1. One arm per site: the proposal `.background(_:)` (`ModifiedContent`),
/// the legacy decoration (`AnimatedColor`), `Shape.fill(_:)`, `.background(_:in:)`
/// and a `ShapeView` material layer (the last three share `paintShapeMaterial`, each is
/// its own arm). The separating arm: the same tree without the setting holds one
/// backdrop record. Mutation, per site: restore its `fillBackdrop(tint:)` call (each
/// reddens its own arm).
@Test @MainActor func everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency() throws {
    func check<E: Element>(_ site: String, _ scheme: ColorScheme, _ name: String, _ element: E) throws {
        let grey = try #require(rtGrey[scheme]?[name])
        let label = "\(scheme) \(name) \(site)"
        let control = rtScene(element, reduce: false, scheme: scheme)
        try #require(control.backdrops.count == 1, "\(label): the control holds one backdrop record")
        let scene = rtScene(element, reduce: true, scheme: scheme)
        #expect(scene.backdrops.isEmpty, "\(label): no backdrop record under Reduce Transparency")
        #expect(!scene.drawList.contains { $0.kind == .backdrop }, "\(label): no backdrop run")
        let rect = try #require(panels(scene).first, "\(label): an opaque panel rect")
        let c = rgba(rect.background)
        #expect(abs(c.r - grey) < 2e-3 && abs(c.g - grey) < 2e-3 && abs(c.b - grey) < 2e-3 && abs(c.a - 1) < 1e-4,
                "\(label): rect \(c) vs grey \(grey) at alpha 1")
    }
    for scheme in [ColorScheme.light, .dark] {
        for (name, material) in rtMaterials {
            try check("proposal background", scheme, name,
                      Color.clear.frame(width: px(40), height: px(20)).background(material))
            try check("legacy background", scheme, name,
                      Box().frame(width: px(40), height: px(20)).background(material))
            try check("Shape.fill", scheme, name, Rectangle().fill(material).frame(width: px(40), height: px(20)))
            try check("background(in:)", scheme, name,
                      Color.clear.frame(width: px(40), height: px(20)).background(material, in: Rectangle()))
            try check("ShapeView layer", scheme, name,
                      Rectangle().fill(Color.clear).fill(material).frame(width: px(40), height: px(20)))
        }
    }
}

/// **8b** (`MT-F`, divergence 248's flat branch). A path filled with a material is
/// the flat tint's raster: under Reduce Transparency its pixels equal the raster of
/// the same path filled with the table's grey at alpha 1 -- not the translucent
/// tint. Mutation: `paintShapeMaterial`'s path branch resolves `material.color`.
@Test @MainActor func aPathFilledWithAMaterialDrawsTheOpaqueGreyUnderReduceTransparency() throws {
    for scheme in [ColorScheme.light, .dark] {
        let grey = try #require(rtGrey[scheme]?["regular"])
        let material = rtScene(gxTriangle(40).fill(Material.regularMaterial).frame(width: px(40), height: px(40)),
                               reduce: true, scheme: scheme)
        let literal = rtScene(gxTriangle(40).fill(Color(white: Double(grey))).frame(width: px(40), height: px(40)),
                              reduce: false, scheme: scheme)
        let translucent = rtScene(gxTriangle(40).fill(Material.regularMaterial).frame(width: px(40), height: px(40)),
                                  reduce: false, scheme: scheme)
        try #require(material.images.count == 1 && literal.images.count == 1 && translucent.images.count == 1)
        #expect(material.backdrops.isEmpty)
        let got = try #require(material.textures.first).pixels
        let want = try #require(literal.textures.first).pixels
        let flat = try #require(translucent.textures.first).pixels
        #expect(got.count == want.count && zip(got, want).allSatisfy { abs(Int($0) - Int($1)) <= 1 },
                "\(scheme): the path raster is the opaque grey's")
        #expect(got != flat, "\(scheme): and not the translucent tint's (the separating arm)")
    }
}

// MARK: - 9

/// **9** (`MT-F`, `BB-C`). A frame of materials under Reduce Transparency costs the
/// renderer no blur work: every backdrop counter is 0 and no frame target is copied;
/// the control (the same tree without the setting) splits, blurs and copies. Mutation:
/// `fillMaterial` ignores the setting.
@Test @MainActor func reduceTransparencyCostsNoBlurWork() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let tree = Column {
        Color.clear.frame(width: px(40), height: px(20)).background(.ultraThinMaterial)
        Box().frame(width: px(40), height: px(20)).background(.regularMaterial)
        Rectangle().fill(.thickMaterial).frame(width: px(40), height: px(20))
    }
    func counters(reduce: Bool) throws -> [Int] {
        let scene = rtScene(tree, reduce: reduce)
        _ = try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(100), height: DevicePixels(100)))
        return [renderer.lastBackdropSplits, renderer.lastBackdropBlurs, renderer.lastBackdropPasses,
                renderer.lastFrameTargetCopies]
    }
    let control = try counters(reduce: false)
    try #require(control[0] > 0 && control[1] > 0 && control[2] > 0 && control[3] > 0,
                 "the instrument works: the control blurs \(control)")
    #expect(try counters(reduce: true) == [0, 0, 0, 0], "no split, blur, pass or frame-target copy")
}

// MARK: - 10

/// **10** (`MT-H`). With the setting false (explicitly, and by default) a material
/// tree draws the scene it drew before: the same records, rects and draw list as
/// the default frame, and the BB tests' tint. Mutation: `fillMaterial` uses the
/// opaque colour unconditionally (this and 1.1/1.2 redden).
@Test @MainActor func aWindowWithoutReduceTransparencyDrawsTheSameSceneAsBefore() throws {
    let tree = Column {
        Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
        Box().frame(width: px(40), height: px(20)).background(.thinMaterial)
        Rectangle().fill(.thickMaterial).frame(width: px(40), height: px(20))
    }
    let plain = lkScene(tree, side: 100)
    let off = rtScene(tree, reduce: false)
    let on = rtScene(tree, reduce: true)
    try #require(plain.backdrops.count == 3)
    #expect(String(describing: off.backdrops) == String(describing: plain.backdrops),
            "an explicit false changes no record")
    #expect(String(describing: off.rects) == String(describing: plain.rects) && off.drawList == plain.drawList)
    #expect(on.backdrops.isEmpty && String(describing: on.rects) != String(describing: plain.rects),
            "the separating arm: true differs")
}

// MARK: - 11

/// **11** (`MT-F`). The opaque rect composes as any rect: `.opacity(0.5)` halves its
/// alpha, a clip cuts it, and `.preferredColorScheme`-style scheme scopes pick the dark
/// grey from the element's own position (`environmentTop`), not the root's.
/// Mutation: resolve the scheme from the root instead of `environmentTop`.
@Test @MainActor func anOpaqueMaterialComposesWithOpacityClipAndTheDarkScheme() throws {
    let panel = Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
    let faded = try #require(panels(rtScene(panel.opacity(0.5), reduce: true)).first)
    #expect(abs(faded.background.a - 0.5) < 1e-4, "opacity multiplies the rect: \(faded.background.a)")
    let clipped = try #require(panels(rtScene(panel.clipShape(RoundedRectangle(cornerRadius: px(4)))
        .frame(width: px(40), height: px(20)), reduce: true)).first)
    #expect(clipped.maskCornerRadii.topLeft == 4 && clipped.contentMask.size.width <= 40,
            "the clip cuts the rect: \(clipped.contentMask) \(clipped.maskCornerRadii)")
    // A light window with a dark subtree: the subtree's own scheme picks the grey.
    let mixed = rtScene(Column {
        panel.environment(\.colorScheme, .dark)
    }, reduce: true, scheme: .light)
    let dark = try #require(panels(mixed).first)
    let c = rgba(dark.background)
    #expect(abs(c.r - 0.2045) < 2e-3, "the dark regular grey from the element's position: \(c)")
}

// MARK: - 12

/// **12** (`MT-F`). Toggling the setting snaps: a frame drawn under an animating
/// transaction right after the toggle already holds the opaque grey (no store
/// track blends the translucent tint into it), on the proposal and the legacy site.
/// Mutation: route the opaque colour through `animatedBackground`.
@Test @MainActor func togglingReduceTransparencySnapsAMaterial() throws {
    func tree(_ reduce: Bool) -> some Element {
        Column {
            Color.clear.frame(width: px(40), height: px(20)).background(.regularMaterial)
            Box().frame(width: px(40), height: px(21)).background(.regularMaterial)
        }
        .environment(\.accessibilityReduceTransparency, reduce)
    }
    let h = TransitionHarness()
    let before = h.frame(0, nil, tree(false), side: 100).finalizedScene()
    try #require(before.backdrops.count == 2)
    let toggled = h.frame(0.1, Animation.linear(duration: 1), tree(true), side: 100).finalizedScene()
    #expect(toggled.backdrops.isEmpty)
    let later = h.frame(0.6, nil, tree(true), side: 100).finalizedScene()
    for (height, label) in [(Float(20), "proposal"), (21, "legacy")] {
        let a = try #require(toggled.rects.first { $0.bounds.size.height == height && $0.background.a > 0 }, label)
        let b = try #require(later.rects.first { $0.bounds.size.height == height && $0.background.a > 0 }, label)
        #expect(String(describing: a.background) == String(describing: b.background)
                && abs(a.background.a - 1) < 1e-4,
                "\(label): the toggle frame is already the opaque grey, \(a.background) vs \(b.background)")
    }
}

// MARK: - 8c

/// **8c** (`MT-I`). No source file calls `fillBackdrop(` or reads `material.color`
/// outside `fillMaterial`'s home: a new material site goes through `fillMaterial`, or
/// it ignores Reduce Transparency. Reads `Sources/MetalUI` by `#filePath`. Mutation:
/// any site calling `pass.fillBackdrop(bounds, tint: pass.resolve(material.color))`.
@Test func noMaterialSiteBypassesFillMaterial() throws {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/MetalUI")
    let files = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
    try #require(files.count > 100 && files.contains("MaterialTransparency.swift"),
                 "the scan reads the real source directory: \(files.count) files")
    var offenders: [String] = []
    for file in files where file != "MaterialTransparency.swift" && file != "Material.swift" {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let code = line.drop { $0 == " " }
            if code.hasPrefix("//") { continue }
            if code.contains("fillBackdrop(") && !code.contains("func fillBackdrop(")
                && !(file == "Passes.swift" && code.contains("frame.fillBackdrop(")) {
                offenders.append("\(file):\(number + 1) \(code)")
            }
            if code.contains("material.color") { offenders.append("\(file):\(number + 1) \(code)") }
        }
    }
    #expect(offenders.isEmpty, "material sites outside fillMaterial: \(offenders)")
}
