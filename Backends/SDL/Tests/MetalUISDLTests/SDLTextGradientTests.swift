import Foundation
import Testing
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUIScene
import MetalUIShaderTypes
import MetalUIPortableText
@testable import MetalUI
@testable import MetalUISDL
import SDLReplay

// R4-5 PR D (rulings `TG-C`, `TG-D`; record 221): a gradient `foregroundStyle` on text on the SDL renderer. The text is one
// masked offscreen group: its content is the gradient raster over the glyphs' ink and its mask scene holds the glyph run
// (and no rect), so the bridge's mask pass draws glyph sprites into the scratch (`draw_run` for every run kind) before the
// destination-in blend. Analytic pixels as `GroupMaskTests`/`TextGradientTests` (Metal); the Metal-to-SDL agreement is parity
// frame 19. The tree is rendered through `renderFrame` over the portable text system (Noto Sans), as `DemoCapture` does.

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

private let width = 200, height = 60

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let pureRed = Color(Hsla(h: 0, s: 1, l: 0.5, a: 1))
private let pureBlue = Color(Hsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1))

/// White-on-black text of `style`, the same tree for the gradient and for the solid oracle.
@MainActor
private func scene<S: ShapeStyle>(_ style: S, atlas: GlyphAtlas, turned: Bool = false) throws -> Scene {
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: font))
    return renderFrame({
        ZStack(alignment: .topLeading) {
            Color(Hsla(h: 0, s: 0, l: 0, a: 1)).frame(width: px(Float(width)), height: px(Float(height)))
            Text("HIWMN").font(size: 40).foregroundStyle(style).padding(Edges(top: px(4), right: px(0), bottom: px(0), left: px(6)))
                .rotationEffect(.degrees(turned ? 8 : 0))
        }
        .frame(width: px(Float(width)), height: px(Float(height)), alignment: .topLeading)
    }, size: Size(width: px(Float(width)), height: px(Float(height))), scaleFactor: 1, textSystem: system, atlas: atlas)
}

@MainActor private func renderer() throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

@MainActor
private func draw(_ scene: Scene, atlas: GlyphAtlas, on renderer: SDLWindowRenderer) throws -> [UInt8] {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: atlas))
    return try renderer.readPixels(width: width, height: height)
}

/// (r, g, b) of a BGRA readback.
private func rgb(_ pixels: [UInt8], _ x: Int, _ y: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i])]
}

/// **S1** (`TG-C`, `TG-D`). Gradient text is one masked group whose mask is the glyph run: on a red-to-blue sweep over black
/// no channel of any pixel exceeds the solid white text's coverage there, nothing is drawn where that text is clear, the ink is red at its left and blue at its right, the frame ran one group pass and one mask pass
/// and no mask failed, the mask scene holds glyphs and no rects, and the replay path (the fixture form) draws the same bytes.
/// Mutations: the mask pass skipped in `render_groups` (the gradient fills its whole box: pixels between the letters are
/// coloured); `SDLGroupSet.Builder.append` not shifting a mask glyph's transform index (the glyphs read the wrong record; a
/// transformed mask is drawn elsewhere) is `SDLClipMaskTests.aGroupsMaskRunsAreShifted`'s site.
@MainActor
@Test func aGradientTextMatchesMetal() throws { try checkGradientText(turned: false) }

/// **S2** (`TG-D`, `CM-A`). The same under `rotationEffect`: the mask scene's glyph records carry a transform record, which
/// `SDLGroupSet.Builder.append` shifts past the root's and the group's like any record's. Mutation: the glyph's transform
/// index not shifted (`SDLGroupFlatten.swift`: the mask glyphs read the wrong record and land unrotated, so the ink leaves
/// the solid text's coverage).
@MainActor
@Test func aRotatedGradientTextMatchesTheRotatedSolidText() throws { try checkGradientText(turned: true) }

@MainActor
private func checkGradientText(turned: Bool) throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let gradient = try scene(LinearGradient(colors: [pureRed, pureBlue], startPoint: .leading, endPoint: .trailing), atlas: atlas,
                             turned: turned)
    let solid = try scene(Color.white, atlas: atlas, turned: turned)
    try #require(gradient.groupMasks.compactMap { $0 }.first?.glyphs.isEmpty == false, "set up: the mask scene holds the glyph run")
    #expect(gradient.groupMasks.compactMap { $0 }.first?.rects.isEmpty == true, "the mask holds glyphs only")
    #expect(solid.groups.isEmpty, "set up: solid text is no group")

    let r = try renderer()
    let pixels = try draw(gradient, atlas: atlas, on: r)
    let oracle = try draw(solid, atlas: atlas, on: try renderer())
    #expect(r.lastGroupPasses == 1 && r.lastMaskPasses == 1 && r.lastMaskFailures == 0,
            "\(r.lastGroupPasses) \(r.lastMaskPasses) \(r.lastMaskFailures)")

    var inked = 0, over = 0, outside = 0, blackInside = 0
    var leftMost: [Int]?, rightMost: [Int]?
    for y in 0..<height {
        for x in 0..<width {
            let p = rgb(pixels, x, y), c = rgb(oracle, x, y)[1]
            if c > 0 { inked += 1 }
            // Coverage is the solid text's: no channel exceeds it, nothing is drawn where the solid text is clear, and
            // a fully covered pixel carries the gradient's colour (a mid-sweep colour has green, so no channel is pinned).
            if p.max()! > c + 3 { over += 1 }
            if c == 0 && p.max()! > 1 { outside += 1 }
            if c >= 250 { if p.max()! < 100 { blackInside += 1 }; if leftMost == nil { leftMost = p }; rightMost = p }
        }
    }
    #expect(inked > 200, "set up: the text drew ink (\(inked))")
    #expect(over == 0 && outside == 0 && blackInside == 0,
            "coverage is the solid text's: \(over) pixels over it, \(outside) outside it, \(blackInside) fully covered but black")
    let left = try #require(leftMost), right = try #require(rightMost)
    #expect(left[0] > 200 && left[2] < 60, "the ink starts red: \(left)")
    #expect(right[2] > 200 && right[0] < 60, "the ink ends blue: \(right)")
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory, driver: SDLWindowRenderer.defaultDriver)
    let replayed = try replayer.render(gradient, atlas: atlas, width: width, height: height,
                                       projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    var replayWorst = 0
    for i in 0..<pixels.count { replayWorst = max(replayWorst, abs(Int(pixels[i]) - Int(replayed[i]))) }
    #expect(replayWorst <= 1, "the window renderer and the replay path draw one frame (worst \(replayWorst))")
}
