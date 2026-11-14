import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Alloy gap G44 (ruling prefix `CT-`, record 291): "any `clipShape`/`clip` around the chat drops the syntax colours from the
// drawn glyphs". The colours were never lost. A clip the per-primitive mask cannot express (an ellipse, a path, two crossing
// rounded clips) paints its content into an offscreen group (`CM-A`, `CM-B`), and that content is in `scene.groupScenes`,
// not in `scene.glyphs`; a test that read `scene.glyphs` saw no key-coloured glyphs. The glyphs inside the group carry
// the theme's colours (`ClipThemeKeyGlyphPixelTests` reads the pixels). `TestWindow.allGlyphs` reads every drawn glyph.
// **Red before the change** (`allGlyphs` absent; with it, mutation M1: not recursing into `groupScenes`: the ellipse and crossing arms of 1 and 3; mutation M2, `Frame.resolve` against `Theme.light`: every dark arm).

/// A palette key whose default is red; the window theme overrides it to blue.
struct CTKey: ThemeColorKey { static let defaultValue = Color(red: 1, green: 0, blue: 0) }
/// The key's resolved blue hue.
private let blueHue: Float = 2.0 / 3.0

private final class CTHighlighter: MarkdownCodeHighlighter, @unchecked Sendable {
    func highlight(code: String, language: String?, isClosed: Bool) -> [MarkdownCodeRun] {
        [MarkdownCodeRun(range: 0..<4, style: CodeStyle(foreground: Color(CTKey.self)))]
    }
}
private let highlighter = CTHighlighter()

private struct CTFence: Component, @MainActor Equatable {
    let md: String
    var content: some ElementGroup {
        let doc = MarkdownDocument(parsing: md)
        var t = MarkdownTheme(); t.codeWraps = false; t.tableScrolls = true; t.showsCodeCopyButton = true
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(doc.blocks, id: \.id) { block in MarkdownBlockView(block).markdownTheme(t).codeHighlighter(highlighter).equatable() }
        }
    }
}

private func keyed() -> AttributedString {
    var a = AttributedString("func "); a.foregroundColor = Color(CTKey.self)
    return a + AttributedString("plain")
}

/// Every way the content is wrapped; `group` is whether the wrapper makes an offscreen group.
private enum Wrap: String, CaseIterable, Sendable {
    case none, clipped, roundedShape, roundedClip, ellipse, crossing
    var group: Bool { self == .ellipse || self == .crossing }
}

private enum Content: String, CaseIterable, Sendable { case text, attributed, fence }

@MainActor private func body(_ content: Content) -> some ElementGroup {
    VStack(alignment: .leading, spacing: Pixels(0)) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            switch content {
            case .text: Text("func hello").foregroundStyle(Color(CTKey.self))
            case .attributed: Text(keyed())
            case .fence: CTFence(md: "```swift\nfunc a\n```").equatable()
            }
        }
    }
}

/// A window of `content` in `wrap`, the dark theme overriding `CTKey` to blue once the first frames are drawn when `late`.
@MainActor private func window(_ content: Content, _ wrap: Wrap, late: Bool = true) throws -> TestWindow {
    var theme = Theme.dark
    theme[CTKey.self] = Color(red: 0, green: 0, blue: 1)
    let size = Size(width: Pixels(300), height: Pixels(300))
    let w: TestWindow
    switch wrap {
    case .none: w = try TestWindow(size: size, colorScheme: .dark) { VStack { body(content) } }
    case .clipped: w = try TestWindow(size: size, colorScheme: .dark) { VStack { body(content) }.clipped() }
    case .roundedShape:
        w = try TestWindow(size: size, colorScheme: .dark) { VStack { body(content) }.clipShape(RoundedRectangle(cornerRadius: Pixels(10))) }
    case .roundedClip: w = try TestWindow(size: size, colorScheme: .dark) { VStack { body(content) }.clip(cornerRadius: Pixels(10)) }
    case .ellipse: w = try TestWindow(size: size, colorScheme: .dark) { VStack { body(content) }.clipShape(Ellipse()) }
    case .crossing:
        w = try TestWindow(size: size, colorScheme: .dark) {
            VStack { body(content) }.frame(width: Pixels(150), height: Pixels(60), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(4)))
                .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(80)))
        }
    }
    if late {
        w.window.setNeedsRedraw(); w.tick(); w.window.setNeedsRedraw(); w.tick()
        w.window.darkTheme = theme
    }
    w.window.setNeedsRedraw(); w.tick(); w.window.setNeedsRedraw(); w.tick()
    return w
}

@MainActor private func hues(_ glyphs: [MUIGlyph]) -> [Float: Int] {
    Dictionary(grouping: glyphs, by: { $0.color.h }).mapValues(\.count)
}
private func blueCount(_ glyphs: [MUIGlyph]) -> Int {
    glyphs.filter { abs($0.color.h - blueHue) < 0.002 && $0.color.s > 0.9 }.count
}

/// A key whose default is red in the light scheme and blue in the dark one (`CR-N`: a palette colour resolves per scheme).
struct CTSchemeKey: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 1, green: 0, blue: 0), dark: Color(red: 0, green: 0, blue: 1))
}

@MainActor
struct ClipThemeKeyGlyphTests {
    /// **1 (`CT-A`, `CT-B`).** Whatever wraps the content, the colours the window draws are the unwrapped ones: the same
    /// hue and glyph counts through `allGlyphs`, the key's blue among them. Red before: `allGlyphs` absent; mutation
    /// **M1** (it does not recurse into `groupScenes`): the ellipse and crossing arms redden.
    @Test(arguments: Content.allCases, Wrap.allCases)
    fileprivate func everyWrapDrawsTheUnwrappedColours(content: Content, wrap: Wrap) throws {
        let plain = try window(content, .none)
        let wrapped = try window(content, wrap)
        let expected = hues(plain.allGlyphs)
        #expect(blueCount(plain.allGlyphs) > 0, "the key's override reaches the glyphs with no clip")
        #expect(hues(wrapped.allGlyphs) == expected, "\(content) in \(wrap): \(hues(wrapped.allGlyphs)) against \(expected)")
    }

    /// **2 (`CT-A`).** Where the glyphs live: a group wrap holds them in exactly one offscreen group scene and none in the
    /// root scene (what Alloy's `scene.glyphs` read), a per-primitive clip keeps them in the root and builds no group.
    @Test(arguments: Wrap.allCases)
    fileprivate func groupWrapsHoldTheirGlyphsInAGroupScene(wrap: Wrap) throws {
        let w = try window(.fence, wrap)
        if wrap.group {
            #expect(w.scene.groupScenes.count == 1, "one masked group")
            #expect(w.scene.glyphs.isEmpty, "the root scene holds no text of the group")
            #expect(w.scene.groupScenes[0].glyphs.count == w.allGlyphs.count)
        } else {
            #expect(w.scene.groupScenes.isEmpty, "no group")
            #expect(w.scene.glyphs.count == w.allGlyphs.count)
            #expect(blueCount(w.scene.glyphs) > 0)
        }
    }

    /// **3 (`CT-C`).** A scheme switch under the clip recolours the glyphs: light draws the key's red, dark its blue, in every
    /// wrap. Mutation **M2** (`Frame.resolve` against `Theme.light`): every dark arm stays red.
    @Test(arguments: Wrap.allCases)
    fileprivate func aSchemeSwitchUnderTheClipRecolours(wrap: Wrap) throws {
        let size = Size(width: Pixels(300), height: Pixels(300))
        let w: TestWindow
        func text() -> some ElementGroup { Text("func hello").foregroundStyle(Color(CTSchemeKey.self)) }
        switch wrap {
        case .none: w = try TestWindow(size: size, colorScheme: .light) { VStack { text() } }
        case .clipped: w = try TestWindow(size: size, colorScheme: .light) { VStack { text() }.clipped() }
        case .roundedShape:
            w = try TestWindow(size: size, colorScheme: .light) { VStack { text() }.clipShape(RoundedRectangle(cornerRadius: Pixels(10))) }
        case .roundedClip: w = try TestWindow(size: size, colorScheme: .light) { VStack { text() }.clip(cornerRadius: Pixels(10)) }
        case .ellipse: w = try TestWindow(size: size, colorScheme: .light) { VStack { text() }.clipShape(Ellipse()) }
        case .crossing:
            w = try TestWindow(size: size, colorScheme: .light) {
                VStack { text() }.frame(width: Pixels(150), height: Pixels(60), alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: Pixels(4)))
                    .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: Pixels(80)))
            }
        }
        w.window.setNeedsRedraw(); w.tick(); w.window.setNeedsRedraw(); w.tick()
        let light = hues(w.allGlyphs)
        #expect(light.count == 1 && light.keys.allSatisfy { $0 < 0.002 }, "light: red, \(light)")
        w.setAppearance(.dark)
        w.window.setNeedsRedraw(); w.tick(); w.window.setNeedsRedraw(); w.tick()
        let dark = hues(w.allGlyphs)
        #expect(dark.count == 1 && dark.keys.allSatisfy { abs($0 - blueHue) < 0.002 }, "dark: blue, \(dark)")
        #expect(dark.values.reduce(0, +) == light.values.reduce(0, +), "the same glyphs")
    }
}
