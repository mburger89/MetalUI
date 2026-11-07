import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIPlatform
@testable import MetalUI
import AppKit

// Alloy gap G3, PR 1 (record 230, prefix `SYM-`): `Image(systemName:)` on macOS. Every literal is a reading of
// `docs/probes/swiftui-symbol-images.swift` (the arm is named on each test), taken on macOS 27.2. The pure name
// resolution (S5, S5b) has no AppKit in it; the rest asks AppKit, so a different macOS may move a literal: the probe
// is the instrument that re-reads them.

private let red = Color(red: 1, green: 0, blue: 0)
private let green = Color(red: 0, green: 1, blue: 0)

@MainActor
private func render<E: Element>(_ width: Float, _ height: Float, scaleFactor: Float = 1, _ root: E) -> (Frame, Scene) {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: scaleFactor)
    frame.render(&root)
    return (frame, frame.finalizedScene())
}

@MainActor
private func size<G: ProposalElementGroup>(_ content: G) -> SizeD { kernelAnswers(content)[0] }

private func s(_ w: Double, _ h: Double) -> SizeD { SizeD(width: w, height: h) }

/// A fixed leaf with a first baseline that records its prepaint bounds.
private final class MarkRecord { var bounds: Bounds<Pixels>? }
private struct Mark: ProposalElement {
    let record: MarkRecord
    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 16), firstBaseline: 13, lastBaseline: 13) }, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) { record.bounds = bounds }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

// MARK: - 4: the pure resolution

/// **Test 4 - `resolveSymbolName` (probes S5, S5b).** Words append in the order slash, shape, fill; a missing full name
/// drops words with the priority slash > shape > fill, then the name itself; an explicit name is kept; a missing base is
/// `nil`. Mutations: **M4a** the suffix order swapped to shape-before-slash (reddens the `bell` row); **M4b** the fallback
/// removed (`return nil` for a missing full name; reddens every fallback row).
@Test func symbolVariantsResolveByTheMeasuredSuffixOrderAndFallBack() {
    func resolve(_ name: String, _ variants: SymbolVariants, _ catalogue: Set<String>) -> String? {
        resolveSymbolName(name, variants: variants, exists: { catalogue.contains($0) })
    }
    #expect(resolve("star", .fill, ["star", "star.fill"]) == "star.fill")
    #expect(resolve("xmark", .circle.fill, ["xmark", "xmark.circle", "xmark.circle.fill"]) == "xmark.circle.fill")
    #expect(resolve("xmark", .fill.circle, ["xmark", "xmark.circle.fill"]) == "xmark.circle.fill", "chain order is the caller's, name order is fixed")
    #expect(resolve("bell", .circle.slash, ["bell", "bell.slash", "bell.slash.circle", "bell.circle.slash"]) == "bell.slash.circle", "slash before the shape")
    #expect(resolve("bell", .circle.slash.fill, ["bell", "bell.slash.circle.fill", "bell.slash.circle"]) == "bell.slash.circle.fill")
    #expect(resolve("chevron.right", .fill, ["chevron.right"]) == "chevron.right", "S5: no .fill name falls back to the base")
    #expect(resolve("star", .circle.slash, ["star", "star.circle", "star.slash"]) == "star.slash", "S5b: slash outranks the shape")
    #expect(resolve("doc", .rectangle.slash.fill, ["doc", "doc.fill"]) == "doc.fill", "S5b: fill survives when the rest are missing")
    #expect(resolve("plus", .slash.fill, ["plus"]) == "plus", "S5b")
    #expect(resolve("star.fill", .slash, ["star.fill", "star.slash.fill"]) == "star.fill", "S5: an explicit name is kept")
    #expect(resolve("nope", .fill, ["star"]) == nil, "a missing base is a missing symbol")
    #expect(resolve("star", .none, ["star", "star.fill"]) == "star")
}

// MARK: - 5: a missing name

/// **Test 5 - a missing name (probe S6).** A 0 x 0 leaf at every proposal, no image in the scene, no stderr, and the
/// diagnostics count the name once however many frames miss it. Mutations: **M5a** a placeholder `Rectangle` painted for
/// a missing name (the scene has a rect); **M5b** `noteMiss` incrementing every call (the count reads 2).
@Test @MainActor func aMissingSymbolIsAnEmptyLeafCountedOncePerName() throws {
    SymbolDiagnostics.reset()
    let name = "this.symbol.does.not.exist"
    #expect(kernelAnswers(Image(systemName: name)) == Array(repeating: s(0, 0), count: 5), "S6: 0 x 0 at the five proposals")
    for _ in 0..<2 {
        let (_, scene) = render(100, 60, scaleFactor: 2, Image(systemName: name))
        #expect(scene.images.isEmpty && scene.rects.isEmpty, "nothing drawn: \(scene.images.count) images \(scene.rects.count) rects")
    }
    #expect(SymbolDiagnostics.misses[name] == 1, "once per name: \(SymbolDiagnostics.misses)")
    #expect(size(Image(systemName: name).frame(width: Pixels(30), height: Pixels(30))) == s(30, 30), "S6: a frame still sizes it")
}

// MARK: - 11: tint and texture size

/// **Test 11 - tint and the texture's size (S4, S9).** `square.fill` at 40 pt under `.foregroundStyle(red)` has an exactly
/// red centre pixel (S4: (255, 0, 0)), and the texture is `round(bounds x 2)` wide at scale factor 2. Mutations: **M11a** the
/// tint skipped (the centre reads black); **M11b** the raster made at scale 1 (the width reads half).
@Test @MainActor func aSymbolIsTintedByTheForegroundAndRasterisedAtTheFramesScale() throws {
    let image = Image(systemName: "square.fill").font(.system(size: 40)).foregroundStyle(red)
    let (_, scene) = render(100, 100, scaleFactor: 2, image)
    try #require(scene.images.count == 1 && scene.textures.count == 1)
    let texture = scene.textures[0]
    let bounds = scene.images[0].bounds
    #expect(Float(texture.width) == (bounds.size.width).rounded() && Float(texture.height) == bounds.size.height.rounded(),
            "texture \(texture.width)x\(texture.height) against device bounds \(bounds.size.width)x\(bounds.size.height)")
    let centre = (texture.height / 2 * texture.width + texture.width / 2) * 4
    #expect(Array(texture.pixels[centre..<centre + 4]) == [255, 0, 0, 255], "S4 centre pixel: \(Array(texture.pixels[centre..<centre + 4]))")
}

// MARK: - 12: sizes

/// **Test 12 - sizes (S1, H1').** The SwiftUI sizes at a nil proposal, read from `NSHostingView.fittingSize`: `star` at 13 pt
/// is 17 x 16 (medium), 23 x 20 (large), 14 x 14 (small bold); 33 x 32 at 26 pt; **`doc.badge.plus` is 15 x 18, its
/// alignment rect's width, not `NSImage.size`'s 17 (H1')**; `square.and.pencil` at 48 pt bold is 60 x 61. Mutations:
/// **M12a** small and large swapped in the scale map; **M12b** the weight dropped (the bold row reads 14 x 13); **M12c**
/// `size.width` instead of the alignment width (the badge reads 17 x 18).
@Test @MainActor func aSymbolsSizeIsTheFontsAtTheImageScale() {
    func star(_ pt: Double = 13) -> EnvironmentScope<Image> { Image(systemName: "star").font(.system(size: pt)) }
    #expect(size(star()) == s(17, 16), "S1 star@13 medium")
    #expect(size(star().imageScale(.large)) == s(23, 20), "S1 star@13 large")
    #expect(size(Image(systemName: "star").font(.system(size: 13, weight: .bold)).imageScale(.small)) == s(14, 14), "S1 star@13 small bold")
    #expect(size(star(26)) == s(33, 32), "S1 star@26")
    #expect(size(Image(systemName: "xmark.circle").font(.system(size: 48))) == s(56, 56), "S1 xmark.circle@48")
    #expect(size(Image(systemName: "doc.badge.plus").font(.system(size: 13))) == s(15, 18), "H1': the alignment rect's width")
    #expect(size(Image(systemName: "doc.badge.plus").font(.system(size: 13)).imageScale(.large)) == s(19, 23), "H1' large")
    #expect(size(Image(systemName: "square.and.pencil").font(.system(size: 48, weight: .bold))) == s(60, 61), "H1' square.and.pencil")
    #expect(size(Image(systemName: "star")) == s(17, 16), "S3: no font is the 13 pt body")
}

// MARK: - 13: baselines

/// **Test 13 - the baseline (S2, H2).** `star` at 26 pt has a first baseline of 27 (`height - alignmentRect.minY`), so beside a
/// 13-baseline mark in `HStack(.firstTextBaseline)` the mark sits at y = 27 - 13 = 14 and the star at 0; at 13 pt (baseline
/// 13) both sit at 0. Mutation: **M13** the baseline measured from the other edge (`alignmentRect.minY`, which reads 5).
@Test @MainActor func aSymbolsBaselineIsItsHeightMinusTheAlignmentRectsBottom() throws {
    for (points, expected) in [(26.0, 14.0), (13.0, 0.0), (48.0, 36.0)] {
        let mark = MarkRecord()
        let (frame, _) = render(200, 100, HStack(alignment: .firstTextBaseline, spacing: Pixels(0)) {
            Image(systemName: "star").font(.system(size: points))
            Mark(record: mark)
        }.frame(width: Pixels(200), height: Pixels(100), alignment: .top))
        _ = frame
        let y = try #require(mark.bounds).origin.y.value
        #expect(Double(y) == expected, "star@\(points): the mark sits at \(y), S2 says \(expected)")
    }
}

// MARK: - 14: work

/// **Test 14 - the cache (SYM-C).** The first frame makes one raster; an identical second makes none and hands back the
/// **same texture**; a colour change makes no raster and one tint; a font change makes one raster. Mutations: **M14a** the
/// point size left out of the key (a font change makes none and draws the stale size); **M14b** the colour left out of the tint
/// key (a colour change returns the old texture); **M14c** the cache disabled (the second frame makes a raster).
@Test @MainActor func aSymbolIsRasterisedOnceAndRetintedWithoutRasterising() throws {
    let cache = SymbolRasterCache.shared
    cache.reset()
    func frame(_ color: Color, _ points: Double) throws -> ImageTexture {
        let (_, scene) = render(100, 100, scaleFactor: 2, Image(systemName: "star").font(.system(size: points)).foregroundStyle(color))
        return try #require(scene.textures.first)
    }
    let first = try frame(red, 20)
    #expect((cache.rastersMade, cache.tintsMade) == (1, 1), "first frame: \(cache.rastersMade) rasters, \(cache.tintsMade) tints")
    let second = try frame(red, 20)
    #expect((cache.rastersMade, cache.tintsMade) == (1, 1) && second === first, "the second frame does no work and keeps one identity")
    let recoloured = try frame(green, 20)
    #expect((cache.rastersMade, cache.tintsMade) == (1, 2) && recoloured !== first,
            "a colour change re-tints: \(cache.rastersMade) rasters, \(cache.tintsMade) tints")
    let resized = try frame(green, 30)
    #expect(cache.rastersMade == 2 && resized.width > recoloured.width, "a font change rasterises again: \(cache.rastersMade), \(resized.width) vs \(recoloured.width)")
    #expect(cache.coverageCount <= SymbolRasterCache.capacity && cache.tintedCount <= SymbolRasterCache.capacity)
}

// MARK: - 16: accessibility

/// **Test 16 - accessibility (S8, S8b).** A symbol is an `.image` labelled with SwiftUI's own label (`star` is "Favorite"),
/// a name outside the table falls back to AppKit's description, `.accessibilityHidden(true)` records nothing and
/// `.accessibilityLabel` replaces the label. Mutation: **M16** `prepaint` not recording (every arm but the hidden one reddens).
@Test @MainActor func aSymbolIsAnImageLabelledLikeSwiftUIAndHiddenWhenAsked() throws {
    let (_, shown) = try accessibilityBuild(HStack { Image(systemName: "star"); ProposalText("V") })
    let star = try shown.tree.one("Favorite").node
    #expect(star.role == .image && star.label == "Favorite", "S8: \(star)")

    let fallback = try #require(NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)?.accessibilityDescription)
    let (_, other) = try accessibilityBuild(HStack { Image(systemName: "bolt"); ProposalText("V") })
    #expect(other.tree.nodes.values.contains { $0.label == fallback && $0.role == .image }, "the AppKit fallback: \(other.tree.readings)")

    let (_, hidden) = try accessibilityBuild(HStack { Image(systemName: "star").accessibilityHidden(true); ProposalText("V") })
    #expect(hidden.tree.readings == ["V"] && hidden.tree.nodes.count == 1, "S8 hidden: \(hidden.tree.readings)")

    let (_, custom) = try accessibilityBuild(HStack { Image(systemName: "star").accessibilityLabel("Rate"); ProposalText("V") })
    #expect(custom.tree.nodes.values.contains { $0.label == "Rate" } && !custom.tree.nodes.values.contains { $0.label == "Favorite" }, "S8 custom: \(custom.tree.readings)")
}

// MARK: - 17: no hitbox

/// **Test 17 - a bare symbol registers no hitbox** (as `Image`). Mutation: **M17** a hitbox registered for a symbol.
@Test @MainActor func aSymbolRegistersNoHitbox() {
    let (frame, _) = render(100, 60, Image(systemName: "star"))
    #expect(frame.hitboxes.isEmpty, "\(frame.hitboxes.count) hitboxes")
}

// MARK: - 18: cursor

/// **Test 18 - a symbol cursor (`SYM-L`).** `PointerStyle.image(Image(systemName: "star"))` is the 13 pt star at scale 2:
/// 34 x 32 pixels at scale 2, with one texture identity across rebuilds, so `Window` sends it once. A missing name is the
/// arrow. Mutation: **M18** a re-rasterisation per call (the identities differ).
@Test @MainActor func aSymbolCursorIsTheBodyFontStarAtScaleTwoWithOneIdentity() throws {
    func cursor(_ name: String) -> PlatformCursorImage? {
        if case .image(let image) = PointerStyle.image(Image(systemName: name), hotSpot: .center).kind { return image }
        return nil
    }
    let first = try #require(cursor("star")), second = try #require(cursor("star"))
    #expect((first.texture.width, first.texture.height, first.scale) == (34, 32, 2), "\(first.texture.width)x\(first.texture.height) @\(first.scale)")
    #expect(first.texture === second.texture, "one identity across rebuilds")
    #expect(cursor("this.symbol.does.not.exist") == nil, "a missing name is not an image cursor")
}

// MARK: - the divergences' pins (227, 228, 229): wrong on purpose

/// **Divergence 227's pin.** The AppKit raster of `star` at 13 pt, scale factor 2, has its ink in device rows 2..<30 and columns
/// 2..<31; SwiftUI's own raster of the same symbol ends one row earlier, at 29 (probe S9, the 40 x 30 canvas ink boxes
/// (5, 5)-(19.5, 18.5) pt against (5, 5)-(19.5, 19)). A reddening test may be a fix: the placement moved toward SwiftUI's.
/// Mutation: **M227** the image drawn half a point higher (the bottom row reads 29).
@Test @MainActor func anAppKitSymbolRasterSitsOneDeviceRowLowerThanSwiftUIs() throws {
    let (_, scene) = render(40, 30, scaleFactor: 2, Image(systemName: "star").font(.system(size: 13)).foregroundStyle(Color(red: 0, green: 0, blue: 0)))
    let texture = try #require(scene.textures.first)
    var rows = Set<Int>(), columns = Set<Int>()
    for y in 0..<texture.height { for x in 0..<texture.width where texture.pixels[(y * texture.width + x) * 4 + 3] > 5 { rows.insert(y); columns.insert(x) } }
    #expect(rows.min() == 2 && rows.max() == 29 && columns.min() == 2 && columns.max() == 30,
            "ink rows \(rows.min() ?? -1)...\(rows.max() ?? -1), columns \(columns.min() ?? -1)...\(columns.max() ?? -1); SwiftUI's last row is 28")
}

/// **Divergence 228's pin.** A symbol outside `SymbolAccessibilityLabels` is labelled with AppKit's description, which is the
/// lower-case word SwiftUI capitalises: `bolt` reads "flash" where SwiftUI reads "Flash" (probe S8b's method; `heart` "love"
/// against "Love"). Mutation: **M228** the description capitalised (reads "Flash", which equals SwiftUI's and fixes the row).
@Test @MainActor func aSymbolOutsideTheLabelTableReadsAppKitsLowerCaseDescription() throws {
    let (_, build) = try accessibilityBuild(HStack { Image(systemName: "bolt"); ProposalText("V") })
    #expect(build.tree.nodes.values.contains { $0.role == .image && $0.label == "flash" }, "\(build.tree.readings)")
}

/// **Divergence 229's pin.** Under `.scaleEffect(2)` the symbol samples its unscaled raster (an image is resampled, `GX-`): the
/// quad is 34 x 32 device pixels wide at scale factor 1 while the texture keeps the 17 x 16 of the unscaled star, where SwiftUI
/// re-rasterises the vector. Mutation: **M229** nothing to mutate but the effect (a fix re-keys the raster to the scale and the
/// texture reads 34 x 32).
@Test @MainActor func aSymbolUnderScaleEffectSamplesItsUnscaledRaster() throws {
    let (_, scene) = render(100, 100, Image(systemName: "star").font(.system(size: 13)).scaleEffect(2))
    let texture = try #require(scene.textures.first), quad = try #require(scene.images.first)
    #expect((texture.width, texture.height) == (17, 16) && quad.bounds.size.width == 34, "texture \(texture.width)x\(texture.height), quad \(quad.bounds.size.width) wide")
}
