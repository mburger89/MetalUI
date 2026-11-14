import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// Alloy gap G44 (ruling prefix `CT-`, record 291): the drawn pixels, not the scene record. Text coloured by a `ThemeColorKey`
// is the key's colour in a window theme that overrides it, with no clip, a rounded clip (per-primitive mask), an ellipse clip
// (a masked group, `CM-A`) and two crossing rounded clips (a masked group, `CM-B`): every ink pixel is the blue, none the
// key's red default, and the blue coverage in a clip is the unclipped coverage. Every render is 200 x 200, scale 1, over a
// transparent target; U+2588 FULL BLOCK at 40 pt is the glyph (a solid interior).

private func px(_ v: Float) -> Pixels { Pixels(v) }
private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

private struct PixelKey: ThemeColorKey { static let defaultValue = Color(red: 1, green: 0, blue: 0) }
private struct SchemeKey: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 1, green: 0, blue: 0), dark: Color(red: 0, green: 0, blue: 1))
}

private enum Wrap: String, CaseIterable, Sendable { case none, clipped, rounded, ellipse, crossing }

/// Blue and red ink pixels (alpha at least 128) of a BGRA render.
private func ink(_ pixels: [UInt8]) -> (blue: Int, red: Int) {
    var blue = 0, red = 0
    for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] >= 128 {
        let b = Int(pixels[i]), g = Int(pixels[i + 1]), r = Int(pixels[i + 2])
        if b > 200 && r < 60 && g < 60 { blue += 1 }
        if r > 200 && b < 60 && g < 60 { red += 1 }
    }
    return (blue, red)
}

/// Five full blocks centred in the 200 x 200 frame, inside every wrap's shape, coloured by `key`, under `theme` in `scheme`.
@MainActor private func render<K: ThemeColorKey>(_ key: K.Type, theme: Theme, scheme: ColorScheme, wrap: Wrap) throws -> [UInt8] {
    func blocks() -> some Element & ProposalElementGroup {
        VStack(alignment: .leading, spacing: px(0)) { Text(String(repeating: "\u{2588}", count: 3)).font(size: 40).foregroundStyle(Color(key)) }
            .frame(width: px(200), height: px(200), alignment: .center)
    }
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let harness = TransitionHarness()
    let frame: Frame
    switch wrap {
    case .none: frame = harness.frame(0, nil, blocks().theme(theme).environment(\.colorScheme, scheme), side: 200)
    case .clipped: frame = harness.frame(0, nil, blocks().clipped().theme(theme).environment(\.colorScheme, scheme), side: 200)
    case .rounded:
        frame = harness.frame(0, nil, blocks().clipShape(RoundedRectangle(cornerRadius: px(20))).theme(theme).environment(\.colorScheme, scheme), side: 200)
    case .ellipse:
        frame = harness.frame(0, nil, blocks().clipShape(Ellipse()).theme(theme).environment(\.colorScheme, scheme), side: 200)
    case .crossing:
        frame = harness.frame(0, nil, blocks().frame(width: px(190), height: px(190), alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: px(4)))
            .frame(width: px(200), height: px(200), alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: px(90))).theme(theme).environment(\.colorScheme, scheme), side: 200)
    }
    renderer.upload(frame.glyphAtlas)
    let scene = frame.finalizedScene()
    if wrap == .ellipse || wrap == .crossing { #expect(scene.groupScenes.count == 1, "\(wrap): one masked group") }
    return try renderer.renderOffscreen(scene, size: size200)
}

@MainActor
struct ClipThemeKeyGlyphPixelTests {
    /// **4 (`CT-B`).** The window theme's override of a palette key paints the glyph ink whatever clip surrounds it: blue
    /// pixels, no red, and as many blue pixels as with no clip (the blocks sit inside every shape). Mutation **M2**
    /// (`Frame.resolve` against `Theme.light`): every arm paints the red default and reddens.
    @Test(arguments: Wrap.allCases)
    fileprivate func aThemeOverrideColoursTheInkInEveryClip(wrap: Wrap) throws {
        var theme = Theme.light
        theme[PixelKey.self] = Color(red: 0, green: 0, blue: 1)
        let baseline = ink(try render(PixelKey.self, theme: theme, scheme: .light, wrap: .none))
        #expect(baseline.blue > 1000 && baseline.red == 0, "unclipped: blue ink, \(baseline)")
        let wrapped = ink(try render(PixelKey.self, theme: theme, scheme: .light, wrap: wrap))
        #expect(wrapped.red == 0, "\(wrap): no red ink, \(wrapped)")
        #expect(wrapped.blue == baseline.blue, "\(wrap): the unclipped coverage, \(wrapped) against \(baseline)")
    }

    /// **5 (`CT-C`).** A scheme switch recolours the ink under the clip: the key's red in light, its blue in dark (mutation **M2**: dark stays red).
    @Test(arguments: Wrap.allCases)
    fileprivate func aSchemeSwitchRecoloursTheInkInEveryClip(wrap: Wrap) throws {
        let light = ink(try render(SchemeKey.self, theme: .light, scheme: .light, wrap: wrap))
        let dark = ink(try render(SchemeKey.self, theme: .dark, scheme: .dark, wrap: wrap))
        #expect(light.red > 1000 && light.blue == 0, "\(wrap) light: \(light)")
        #expect(dark.blue > 1000 && dark.red == 0, "\(wrap) dark: \(dark)")
        #expect(light.red == dark.blue, "\(wrap): the same coverage")
    }
}
