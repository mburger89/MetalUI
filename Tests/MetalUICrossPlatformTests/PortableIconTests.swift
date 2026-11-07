import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIIconData
@testable import MetalUI

// Alloy gap G3, PR 2 (record 232, prefix `SYM-`): the bundled Lucide icons, `Icon`, and the portable box and stroke. These
// run on Linux and Windows too — the route they test is the only one there — and on macOS under the `SymbolRoute.forcesBundled`
// seam (test 19). Every pixel is read analytically from the scene's tinted path raster (`composite`); there are no goldens.
// The box and baseline factors are the fit of `docs/probes/swiftui-symbol-images.swift` S1 and S2 (`SYM-J`).

private let red = Color(red: 1, green: 0, blue: 0)

/// Runs `body` with the bundled route forced (a no-op off macOS).
@MainActor
private func bundled<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    let old = SymbolRoute.forcesBundled
    SymbolRoute.forcesBundled = true
    defer { SymbolRoute.forcesBundled = old }
    return try body()
}

@MainActor
private func render<E: Element>(_ width: Float, _ height: Float, _ root: E) -> (Frame, Scene) {
    var root = root
    let frame = Frame(contentSize: Size(width: Pixels(width), height: Pixels(height)), scaleFactor: 1)
    frame.render(&root)
    return (frame, frame.finalizedScene())
}

/// The scene's image quads source-over onto a `width` x `height` canvas of premultiplied RGBA (each quad is a path raster:
/// one texel per device pixel at an integer origin, so no resampling is needed).
private func composite(_ scene: Scene, width: Int, height: Int) -> [UInt8] {
    var canvas = [UInt8](repeating: 0, count: width * height * 4)
    for image in scene.images {
        let texture = scene.textures[Int(image.texture)]
        let ox = Int(image.bounds.origin.x.rounded()), oy = Int(image.bounds.origin.y.rounded())
        for y in 0..<texture.height {
            for x in 0..<texture.width {
                let cx = ox + x, cy = oy + y
                guard cx >= 0, cy >= 0, cx < width, cy < height else { continue }
                let s = (y * texture.width + x) * 4, d = (cy * width + cx) * 4
                let inverse = 255 - Int(texture.pixels[s + 3])
                for c in 0..<4 { canvas[d + c] = UInt8(min(255, Int(texture.pixels[s + c]) + (Int(canvas[d + c]) * inverse + 127) / 255)) }
            }
        }
    }
    return canvas
}

private func pixel(_ canvas: [UInt8], _ x: Int, _ y: Int, width: Int) -> [UInt8] {
    Array(canvas[(y * width + x) * 4..<(y * width + x) * 4 + 4])
}

/// A custom layout that records the size its only subview answers at a nil proposal.
private final class SizeRecord: @unchecked Sendable { var size: SizeD? }
private struct MeasuresAtNil: ProposalLayout {
    let record: SizeRecord
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        record.size = subviews[0].sizeThatFits(ProposedSize(width: nil, height: nil)).size
        return LayoutMeasurement(size: .zero)
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

@MainActor
private func size<G: ProposalElementGroup>(_ content: G) -> SizeD {
    let record = SizeRecord()
    var root = ProposalLayoutContainer(MeasuresAtNil(record: record)) { content }
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1)
    frame.render(&root)
    return record.size ?? SizeD(width: -1, height: -1)
}

/// A fixed 10 x 16 leaf with a first and last baseline of 13 that records where it is placed.
private final class MarkRecord { var bounds: Bounds<Pixels>? }
private struct Mark: ProposalElement {
    let record: MarkRecord
    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 16), firstBaseline: 13, lastBaseline: 13) }, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) { record.bounds = bounds }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

private func point(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func rectPath(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Path {
    var path = Path()
    path.move(to: point(x, y)); path.addLine(to: point(x + w, y)); path.addLine(to: point(x + w, y + h))
    path.addLine(to: point(x, y + h)); path.closeSubpath()
    return path
}

private let box24 = Size(width: Pixels(24), height: Pixels(24))

/// The Alloy icon set and its action buttons (plan section 2's table): every SF name the bundled table promises.
private let alloyNames = [
    "magnifyingglass", "doc", "doc.text", "pencil", "square.and.pencil", "doc.badge.plus", "terminal", "apple.terminal", "brain",
    "brain.head.profile", "sparkles", "globe", "person", "person.crop.circle", "exclamationmark.triangle", "xmark", "xmark.circle",
    "play", "play.fill", "stop", "stop.fill", "stop.circle", "checkmark", "chevron.right", "chevron.down", "doc.on.doc",
    "arrow.uturn.backward", "arrow.up.right.square", "rectangle.split.2x1", "cpu",
]

// MARK: - 3: the catalogue

/// **Test 3 - every Alloy name is a bundled icon (`SYM-I`).** Each name of the set resolves to an `Icon` with at least one
/// layer whose coordinates (control points included) are finite and inside the 24 x 24 view box, and whose path has ink; the
/// `.fill` names add a fill layer under the stroke and the others do not; `robot` (which exists nowhere) and a `.fill` of an
/// open outline are `nil`. The vendored data itself: 29 icons, each with ops for its coordinates. Mutations: **M3a** one table
/// row dropped (`cpu`): the count and that name's arm redden; **M3b** the fill layer dropped from `play.fill`.
@Test @MainActor func everyAlloyNameIsABundledIconInsideItsViewBox() throws {
    try #require(alloyNames.count == 30, "the Alloy set is 30 names")
    for name in alloyNames {
        let icon = try #require(Icon.bundled(name), "\(name) has no bundled icon")
        #expect(!icon.layers.isEmpty, "\(name): layers")
        #expect(icon.viewBox == box24, "\(name): view box")
        for layer in icon.layers {
            let bounds = layer.path.boundingRect
            let (x0, y0) = (bounds.origin.x.value, bounds.origin.y.value)
            let (x1, y1) = (x0 + bounds.size.width.value, y0 + bounds.size.height.value)
            #expect([x0, y0, x1, y1].allSatisfy(\.isFinite) && x0 >= 0 && y0 >= 0 && x1 <= 24 && y1 <= 24 && x1 > x0 && y1 > y0,
                    "\(name): path bounds (\(x0), \(y0))-(\(x1), \(y1)) leave the view box")
        }
    }
    let data = try #require(LucideIcons.names.count == 29 ? LucideIcons.names : nil, "29 vendored icons: \(LucideIcons.names.count)")
    for name in data {
        let icon = try #require(LucideIcons.data(named: name), "\(name) vendored but unreadable")
        let args = icon.ops.reduce(0) { $0 + [2, 2, 6, 0][Int($1)] }
        #expect(args == icon.coords.count && icon.coords.allSatisfy { $0.isFinite && $0 >= -0.01 && $0 <= 24.01 },
                "\(name): ops want \(args) coordinates, data has \(icon.coords.count)")
    }
    #expect(try #require(Icon.bundled("play.fill")).layers.count == 2 && Icon.bundled("play")?.layers.count == 1, "fill adds a layer")
    #expect(Icon.bundled("robot") == nil && Icon.bundled("robot.fill") == nil, "robot exists nowhere")
    #expect(Icon.bundled("xmark.circle.fill") == nil && Icon.bundled("doc.fill") == nil, "an outline that cannot be filled has no .fill name")
}

// MARK: - 6: the box

/// **Test 6 - the portable box (`SYM-J`).** A symbol is a square of `pointSize x factor[scale]`, factors 0.94, 1.15 and 1.46
/// (the medians of probe S1 over 38 names x 6 sizes): 13 pt is 12.22, 14.95 and 18.98; 26 pt 24.44, 29.9 and 37.96; `.title`
/// (22 pt) reads the font, not the 13 pt default. The same box holds for `Image(icon:)`. Mutations: **M6a** `imageScale`
/// ignored (the small and large rows read the medium box); **M6b** the default font read (the 26 pt and `.title` rows read 13 pt).
@Test @MainActor func aPortableSymbolIsASquareOfThePointSizeTimesTheScaleFactor() throws {
    try bundled {
        @MainActor func side(_ image: some ProposalElementGroup) -> Double {
            let s = size(image)
            #expect(s.width == s.height, "a square box: \(s)")
            return s.width
        }
        let rows: [(Double, Image.Scale, Double)] = [
            (13, .small, 12.22), (13, .medium, 14.95), (13, .large, 18.98),
            (26, .small, 24.44), (26, .medium, 29.9), (26, .large, 37.96),
        ]
        for (points, scale, expected) in rows {
            let s = side(Image(systemName: "play").font(.system(size: points)).imageScale(scale))
            #expect(abs(s - expected) < 1e-9, "\(points) pt \(scale): \(s), expected \(expected)")
        }
        let title = side(Image(systemName: "play").font(.title))
        let titleLarge = side(Image(systemName: "play").font(.title).imageScale(.large))
        #expect(abs(title - 22 * 1.15) < 1e-9 && abs(titleLarge - 22 * 1.46) < 1e-9, ".title is 22 pt: \(title), \(titleLarge)")
        #expect(abs(side(Image(systemName: "play")) - 14.95) < 1e-9, "no font is the 13 pt body at medium")
        let icon = try #require(Icon.bundled("play"))
        #expect(abs(side(Image(icon: icon, label: Text("Play")).font(.system(size: 26)).imageScale(.large)) - 37.96) < 1e-9, "an icon has the same box")
        #expect(size(Image(systemName: "play").resizable().frame(width: Pixels(40), height: Pixels(30))) == SizeD(width: 40, height: 30),
                "a resizable symbol answers the proposal")
    }
}

// MARK: - 7: the baseline

/// **Test 7 - the portable baseline (`SYM-J`, probe S2).** SF Symbols' baseline is `height - alignmentRect.minY` (H2), which
/// the portable box fits as `side - pointSize x descent[scale]` with descents 0.09, 0.19 and 0.35: at 26 pt medium the first
/// baseline is 29.9 - 4.94 = 24.96, so a 13-baseline mark beside it in `HStack(.firstTextBaseline)` sits at y = 11.96, and at
/// 48 pt large (70.08 - 16.8 = 53.28) at 40.28 (the layout places on whole points: 12 and 40); where the icon's baseline is above the mark's (13 pt small: 12.22 - 1.17 =
/// 11.05) the mark stays at 0. The last baseline is the same. Mutation: **M7** `firstBaseline` and `lastBaseline` returned as
/// nil (the mark sits at the box's bottom edge less 13: 16.9 at 26 pt).
@Test @MainActor func aPortableSymbolsBaselineIsItsBoxLessTheFittedDescent() throws {
    try bundled {
        let rows: [(Double, Image.Scale, Double)] = [(26, .medium, 12), (48, .large, 40), (13, .small, 0), (13, .medium, 0)]
        for alignment in [VerticalAlignment.firstTextBaseline, .lastTextBaseline] {
            for (points, scale, expected) in rows {
                let mark = MarkRecord()
                _ = render(300, 200, HStack(alignment: alignment, spacing: Pixels(0)) {
                    Image(systemName: "play").font(.system(size: points)).imageScale(scale)
                    Mark(record: mark)
                }.frame(width: Pixels(300), height: Pixels(200), alignment: .topLeading))
                let y = try #require(mark.bounds).origin.y.value
                #expect(abs(Double(y) - expected) < 1e-3, "\(alignment) \(points) pt \(scale): the mark sits at \(y), expected \(expected)")
            }
        }
    }
}

// MARK: - 8: the stroke

/// **Test 8 - a custom icon's stroke (`SYM-J`).** A butt-capped horizontal line across a 24-unit icon at y = 12, width 2:
/// drawn in a 24 pt frame the rows 11 and 12 are fully covered (255) and rows 10 and 13 empty; in a 48 pt frame the stroke
/// scales with the box (side / 24 = 2, width 4: rows 22-25 covered, 21 and 26 empty); `.fontWeight(.bold)` multiplies the
/// width by 2.75 / 2, which at 24 pt covers rows 11 and 12 fully and rows 10 and 13 by 0.375 (alpha 96). A bundled symbol
/// obeys the same weight rule: its stroke is `side / 24 x 2.75` at bold. Mutations: **M8a** the stroke not scaled by
/// `side / viewBox` (the 48 pt arm reads 2 rows); **M8b** the weight not applied (the bold arm has no partial rows).
@Test @MainActor func aCustomIconsStrokeScalesWithTheBoxAndTheFontWeight() throws {
    var line = Path()
    line.move(to: point(0, 12)); line.addLine(to: point(24, 12))
    let icon = Icon(viewBox: box24, layers: [Icon.Layer(line, paint: .stroke(width: Pixels(2), cap: .butt, join: .miter))])
    func canvas(_ side: Int, bold: Bool = false) -> [UInt8] {
        let image = Image(decorative: icon).resizable().frame(width: Pixels(Float(side)), height: Pixels(Float(side)))
        let (_, scene) = bold ? render(Float(side), Float(side), image.fontWeight(.bold)) : render(Float(side), Float(side), image)
        return composite(scene, width: side, height: side)
    }
    func alphas(_ canvas: [UInt8], column: Int, side: Int) -> [Int] { (0..<side).map { Int(pixel(canvas, column, $0, width: side)[3]) } }

    let small = alphas(canvas(24), column: 12, side: 24)
    #expect(small.enumerated().allSatisfy { ($0.offset == 11 || $0.offset == 12) ? $0.element == 255 : $0.element == 0 },
            "24 pt: rows 11 and 12 full, the rest empty: \(small)")
    let large = alphas(canvas(48), column: 24, side: 48)
    #expect(large.enumerated().allSatisfy { (22...25).contains($0.offset) ? $0.element == 255 : $0.element == 0 },
            "48 pt: rows 22-25 full, the rest empty: \(large)")
    let boldRows = alphas(canvas(24, bold: true), column: 12, side: 24)
    #expect(boldRows[11] == 255 && boldRows[12] == 255 && boldRows[9] == 0 && boldRows[14] == 0
                && abs(boldRows[10] - 96) <= 2 && abs(boldRows[13] - 96) <= 2,
            "bold: width 2.75, rows 10 and 13 at 0.375: \(boldRows)")
    // The line is butt-capped: no ink past either end.
    let ends = canvas(24)
    #expect(pixel(ends, 0, 12, width: 24)[3] == 255 && pixel(ends, 23, 12, width: 24)[3] == 255, "the line spans the box")

    // The bundled route obeys the same rule: `xmark` at 24 pt (side 24) strokes 2 / 24 x 24 = 2 wide, and bold 2.75.
    try bundled {
        let (_, regular) = render(30, 30, Image(systemName: "xmark").font(.system(size: 24 / 1.15)))
        let (_, bold) = render(30, 30, Image(systemName: "xmark").font(.system(size: 24 / 1.15, weight: .bold)))
        func ink(_ scene: Scene) -> Int { composite(scene, width: 30, height: 30).enumerated().filter { $0.offset % 4 == 3 }.reduce(0) { $0 + Int($1.element) } }
        #expect(ink(bold) > ink(regular) * 6 / 5, "a bold symbol has a thicker stroke: \(ink(bold)) against \(ink(regular))")
    }
}

// MARK: - 9: tint

/// **Test 9 - the foreground colours an icon (`SYM-E`).** A filled-square icon under `.foregroundStyle(.red)` has an exactly red
/// centre pixel; by default it is the theme's `textPrimary` (`Theme.light[.textPrimary]`, the colour a plain `Rectangle` fills with); `.tint(.red)`
/// changes nothing; a bundled `play.fill` is red the same way. Mutation: **M9** the tint read instead of the foreground
/// (the red arm reads the default, the tint arm reads red).
@Test @MainActor func anIconIsDrawnInTheForegroundStyleAndNeverTheTint() throws {
    let square = Icon(viewBox: box24, layers: [Icon.Layer(rectPath(0, 0, 24, 24), paint: .fill(FillStyle()))])
    func centre<E: Element>(_ root: E) -> [UInt8] {
        let (_, scene) = render(24, 24, root)
        return pixel(composite(scene, width: 24, height: 24), 12, 12, width: 24)
    }
    let icon = Image(decorative: square).resizable().frame(width: Pixels(24), height: Pixels(24))
    #expect(centre(icon.foregroundStyle(red)) == [255, 0, 0, 255], "red foreground: \(centre(icon.foregroundStyle(red)))")
    let byDefault = centre(icon)
    let expected = Theme.light[.textPrimary].toRgba()
    func byte(_ v: Float) -> Int { Int((v * 255).rounded()) }
    #expect(zip(byDefault, [byte(expected.r), byte(expected.g), byte(expected.b), 255]).allSatisfy { abs(Int($0) - $1) <= 1 },
            "the default is textPrimary: \(byDefault) against the rect's \(expected)")
    try #require(byDefault != [255, 0, 0, 255], "set up: textPrimary is not red")
    #expect(centre(icon.tint(red)) == byDefault, "a tint changes nothing: \(centre(icon.tint(red)))")
    #expect(centre(icon.tint(red).foregroundStyle(red)) == [255, 0, 0, 255], "tint and foreground together read the foreground")
    try bundled {
        let play = Image(systemName: "play.fill").resizable().frame(width: Pixels(24), height: Pixels(24)).foregroundStyle(red)
        #expect(centre(play) == [255, 0, 0, 255], "a bundled filled symbol: \(centre(play))")
    }
}

// MARK: - 10: levels

/// **Test 10 - hierarchical levels (`SYM-E`).** A two-layer icon (a primary left half, a secondary right half) under
/// `.symbolRenderingMode(.hierarchical)` has alpha 255 in the primary half and 0.5 (127 or 128) in the secondary; under the
/// default and `.multicolor` both are 255; the `Image` method beats the environment. A bundled icon has one level, so it
/// draws monochrome under every mode (divergence 231). Mutation: **M10** `level` ignored (the secondary half reads 255).
@Test @MainActor func aSecondaryLayerDrawsAtHalfUnderHierarchicalOnly() throws {
    let left = rectPath(0, 0, 12, 24), right = rectPath(12, 0, 12, 24)
    let icon = Icon(viewBox: box24, layers: [Icon.Layer(left, paint: .fill(FillStyle())),
                                              Icon.Layer(right, paint: .fill(FillStyle()), level: .secondary)])
    func alphas(_ image: some Element) -> (Int, Int) {
        let (_, scene) = render(24, 24, image)
        let canvas = composite(scene, width: 24, height: 24)
        return (Int(pixel(canvas, 6, 12, width: 24)[3]), Int(pixel(canvas, 18, 12, width: 24)[3]))
    }
    let base = Image(decorative: icon).resizable().frame(width: Pixels(24), height: Pixels(24)).foregroundStyle(red)
    let hierarchical = alphas(base.symbolRenderingMode(.hierarchical))
    #expect(hierarchical.0 == 255 && abs(hierarchical.1 - 128) <= 1, "hierarchical: \(hierarchical)")
    let (_, halfScene) = render(24, 24, base.symbolRenderingMode(.hierarchical))
    #expect(abs(Int(pixel(composite(halfScene, width: 24, height: 24), 18, 12, width: 24)[0]) - 128) <= 1,
            "the secondary half is the red at half, premultiplied")
    #expect(alphas(base) == (255, 255) && alphas(base.symbolRenderingMode(.monochrome)) == (255, 255), "monochrome: both full")
    #expect(alphas(base.symbolRenderingMode(.multicolor)) == (255, 255), "multicolor: both full")
    let method = alphas(Image(decorative: icon).symbolRenderingMode(.hierarchical).resizable().frame(width: Pixels(24), height: Pixels(24))
        .foregroundStyle(red))
    #expect(method.0 == 255 && abs(method.1 - 128) <= 1, "Image.symbolRenderingMode: \(method)")
    try bundled {
        let play = Image(systemName: "play.fill").resizable().frame(width: Pixels(24), height: Pixels(24)).foregroundStyle(red)
        for mode in [SymbolRenderingMode.monochrome, .hierarchical, .multicolor] {
            let (_, scene) = render(24, 24, play.symbolRenderingMode(mode))
            let centre = pixel(composite(scene, width: 24, height: 24), 11, 12, width: 24)
            #expect(centre == [255, 0, 0, 255], "a one-level bundled icon under \(mode): \(centre)")
        }
    }
}

// MARK: - 19: the seam

/// **Test 19 - the macOS seam (`SYM-C`).** Where AppKit draws symbols, a symbol is AppKit's unless `forcesBundled` is set:
/// `play` at 13 pt medium is an integer SF box, not the portable 14.95, and with the seam set it is 14.95 square; off macOS the
/// seam changes nothing. Mutation: **M19** `usesBundled` ignoring the seam on macOS (this test and tests 6, 7, 9 and 10
/// redden; on Linux and Windows the mutation does not exist).
@Test @MainActor func theSeamForcesTheBundledRouteOnMacOSAndNothingElsewhere() throws {
    #expect(SymbolRoute.forcesBundled == false, "the seam is off by default")
    let unforced = size(Image(systemName: "play"))
    let forced = bundled { size(Image(systemName: "play")) }
    #expect(abs(forced.width - 14.95) < 1e-9 && forced.width == forced.height, "forced: the portable box \(forced)")
    #if canImport(MetalUIAppKit)
    #expect(unforced != forced && unforced.width == unforced.width.rounded(), "AppKit's own box is whole points: \(unforced) against \(forced)")
    #else
    #expect(unforced == forced, "off macOS the bundled route is the only one: \(unforced) against \(forced)")
    #endif
    #expect(SymbolRoute.forcesBundled == false, "the helper restores the seam")
}

// MARK: - missing names and accessibility

/// A name no bundled icon stands for is a 0 x 0 leaf that draws nothing, counted once (`SYM-G`); a `.fill` of an outline that
/// cannot be filled falls back to the base icon. Mutation: **M-miss** a placeholder drawn for a missing name.
@Test @MainActor func aMissingBundledNameIsAnEmptyLeafAndAnUnfillableFillFallsBack() throws {
    try bundled {
        SymbolDiagnostics.reset()
        let (_, scene) = render(100, 60, Image(systemName: "robot"))
        #expect(size(Image(systemName: "robot")) == SizeD(width: 0, height: 0) && scene.images.isEmpty && scene.rects.isEmpty)
        #expect(SymbolDiagnostics.misses["robot"] == 1, "once per name: \(SymbolDiagnostics.misses)")
        try #require(size(Image(systemName: "search")) == SizeD(width: 0, height: 0), "set up: `search` is Lucide's name, not an SF one")
        let filled = Image(systemName: "xmark.circle").symbolVariant(.fill)
        #expect(size(filled) == size(Image(systemName: "xmark.circle")), "a variant that does not exist falls back to the base")
        let (_, a) = render(30, 30, Image(systemName: "star"))
        let (_, b) = render(30, 30, Image(systemName: "star").symbolVariant(.fill))
        #expect(a.images.count == 1 && b.images.count >= 1, "outline and fill both draw")
        #expect(composite(a, width: 30, height: 30) != composite(b, width: 30, height: 30), "star.fill differs from star")
    }
}

/// A bundled symbol is an `.image` labelled with SwiftUI's own label for the name (`SYM-H`); `Image(icon:label:)` is labelled
/// by its text; `Image(decorative:)` and `.accessibilityHidden(true)` record nothing (a replacing `.accessibilityLabel` is the generic modifier's, tested on the AppKit route). Mutation: **M-ax** `prepaint` not recording.
@Test @MainActor func aBundledIconIsAnImageLabelledAndADecorativeOneIsNot() throws {
    func labels<E: Element>(_ root: E) -> [String] {
        var root = root
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1, collectsAccessibility: true)
        frame.render(&root)
        return frame.axEmissions.filter { $0.declared.role == .image }.compactMap(\.declared.label)
    }
    let icon = try #require(Icon.bundled("play"))
    try bundled {
        #expect(labels(Image(systemName: "play")) == ["Play"], "S8b's label for play")
        #expect(labels(Image(icon: icon, label: Text("Go"))) == ["Go"])
        #expect(labels(Image(decorative: icon)).isEmpty, "decorative")
        #expect(labels(Image(systemName: "play").accessibilityHidden(true)).isEmpty, "hidden")
    }
}
