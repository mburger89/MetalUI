import MetalUI
import MetalUIMarkdown
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// Support for the block Markdown view tests (`BM-E`..`BM-J`, record 235): a text system that meters what the frame
// shapes, a transcript fixture (a vertical scroller over a `LazyVStack` of replies anchored at the bottom, the shape
// Alloy builds), and a small reader of the accessibility tree. Counts and values, never time.

/// A text system that records what the frame measures and lays out: the strings it was asked to shape and their bytes.
@MainActor final class MarkdownMeterTextSystem: TextSystem {
    let base: any TextSystem
    var measuredBytes = 0
    var measuredStrings: [String] = []
    init(_ base: any TextSystem) { self.base = base }
    func reset() { measuredBytes = 0; measuredStrings = [] }
    private func note(_ s: String) { measuredBytes += s.utf8.count; measuredStrings.append(s) }
    func resolveFont(_ d: FontDescriptor) -> FontKey { base.resolveFont(d) }
    func fontMetrics(_ f: FontKey) -> TextFontMetrics { base.fontMetrics(f) }
    func measure(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions) -> TextMeasurement {
        note(s); return base.measure(s, font: font, wrappingAt: w, options: options)
    }
    func placeGlyphs(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        base.placeGlyphs(s, font: font, wrappingAt: w, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func caretOffsets(_ s: String, font: FontKey) -> [Double] { base.caretOffsets(s, font: font) }
    func lineRanges(_ s: String, font: FontKey, wrappingAt w: Double?, options: TextLayoutOptions) -> [Range<Int>] {
        base.lineRanges(s, font: font, wrappingAt: w, options: options)
    }
    func measure(_ t: StyledText, wrappingAt w: Double?, options: TextLayoutOptions) -> StyledTextMeasurement {
        note(t.string); return base.measure(t, wrappingAt: w, options: options)
    }
    func layOut(_ t: StyledText, wrappingAt w: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        base.layOut(t, wrappingAt: w, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ f: FontKey) -> TextDecorationMetrics { base.decorationMetrics(f) }
    func rasterize(_ k: GlyphKey) -> GlyphImage { base.rasterize(k) }
    func beginFrame() { base.beginFrame() }
    func endFrame() { base.endFrame() }
}

/// The replies of a transcript, each a growing document.
@Observable @MainActor final class MarkdownTranscriptModel {
    var documents: [MarkdownDocument]
    var theme = MarkdownTheme()
    init(documents: [MarkdownDocument]) { self.documents = documents }
}

/// Frames after a model write. The write is announced explicitly (`setNeedsRedraw`): off Apple the harness does not
/// turn an `@Observable` write into a dirty window by itself.
@MainActor func markdownSettle(_ window: TestWindow, frames: Int = 6) {
    for _ in 0..<frames { window.window.setNeedsRedraw(); window.tick() }
}

/// A transcript window over `model`: a vertical scroller, a `LazyVStack` of equatable `MarkdownView`s, anchored at the bottom.
@MainActor func markdownTranscript(_ model: MarkdownTranscriptModel, text: @escaping @MainActor () -> any TextSystem = harnessTextSystem,
                                   size: Size<Pixels> = sz(420, 500)) throws -> TestWindow {
    try TestWindow(size: size, textSystem: text) {
        ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(8)) {
                ForEach(Array(model.documents.indices), id: \.self) { index in
                    MarkdownView(model.documents[index]).markdownTheme(model.theme).equatable()
                }
            }
        }
        .defaultScrollAnchor(.bottom)
    }
}

/// One reply of `blocks` blocks: paragraphs, with a list, a quote, a code fence and a table among them, ending in
/// a paragraph that a token can be appended to. `rich: false` has no inline markup in it (every text is a plain leaf).
func markdownReply(_ reply: Int, blocks: Int = 20, rich: Bool = true) -> String {
    var out = ""
    for b in 0..<(blocks - 1) {
        switch b % 5 {
        case 1: out += "- item a of \(reply)-\(b)\n- item b with \(rich ? "`code` and **bold**" : "plain words")\n\n"
        case 2: out += "> quoted \(reply)-\(b)\n\n"
        case 3: out += "```swift\nlet value\(b) = \(reply)\nprint(value\(b))\n```\n\n"
        case 4: out += "| name | n |\n|:--|--:|\n| r\(reply) | \(b) |\n\n"
        default: out += "Paragraph \(reply)-\(b) has some words in it, enough to wrap over a line or two in a narrow column.\n\n"
        }
    }
    return out + "The last paragraph of reply \(reply) is still"
}

/// `frames` summed.
func markdownTotal(_ frames: [FrameWork]) -> FrameWork { frames.dropFirst().reduce(frames[0], +) }

/// The scene's glyphs of the text colour with this hue.
@MainActor func markdownGlyphs(_ window: TestWindow, hue: Float) -> Int {
    window.scene.glyphs.filter { abs($0.color.h - hue) < 0.001 }.count
}
