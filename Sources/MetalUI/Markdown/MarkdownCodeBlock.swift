import MetalUICore

/// A highlighter's answer for one stretch of a code block: `style` over the UTF-8 byte `range` of the code.
///
/// Ranges are in bytes of the block's `code` (not characters or UTF-16 units), so a highlighter built on
/// tree-sitter or a byte scanner reports what it already has. The view sorts runs, clips overlaps (an earlier
/// run wins the bytes it covers) and snaps an end that falls inside a scalar down to the scalar's start.
/// MetalUI-only (SwiftUI has no block Markdown).
public struct MarkdownCodeRun: Hashable, Sendable {
    /// The UTF-8 byte range the style covers.
    public var range: Range<Int>
    /// The colours: a glyph colour, a background, or both. `CodeView` uses the same type.
    public var style: CodeStyle

    /// A run of `style` over the byte `range`.
    public init(range: Range<Int>, style: CodeStyle) {
        self.range = range
        self.style = style
    }
}

/// Colours the code of a Markdown code block (`BM-F`).
///
/// Set one with ``MarkdownView/codeHighlighter(_:)``; the default is plain text. The view holds it strongly and
/// compares it **by identity**, so changing the colours means giving the view another instance. It is called
/// while a fence's view is built, once per change of that fence (a block that did not change is not built
/// again) and never on a frame where nothing changed, so it must be a pure read of its arguments: no observed
/// writes and no state that makes the same call answer differently. `isClosed` is false while the fence is
/// still streaming in, so a highlighter can answer cheaply or defer. MetalUI-only.
public protocol MarkdownCodeHighlighter: AnyObject {
    /// The runs that colour `code`, in the language named by the fence's info string (`nil` when it has none).
    func highlight(code: String, language: String?, isClosed: Bool) -> [MarkdownCodeRun]
}

/// The pure part of a code block: run normalisation and the cut into chunks of at most 32 lines (`BM-H`).
enum MarkdownCodeSlicing {
    /// Lines per chunk. A streaming token changes only the last chunk, so it shapes at most this many lines
    /// whatever the fence's length.
    static let linesPerChunk = 32

    /// A run inside one chunk, in UTF-8 bytes from the chunk's start.
    struct ChunkRun: Hashable {
        var range: Range<Int>
        var style: CodeStyle
    }

    /// Up to 32 lines of a fence and the runs that colour them.
    struct Chunk: Hashable {
        var index: Int
        var text: String
        var runs: [ChunkRun]
    }

    /// `runs` sorted by start, clipped to `0 ..< byteCount` and against each other, snapped down to scalar
    /// boundaries, with empty runs dropped.
    static func normalized(_ runs: [MarkdownCodeRun], in bytes: [UInt8]) -> [MarkdownCodeRun] {
        if runs.isEmpty { return [] }
        let sorted = runs.sorted { $0.range.lowerBound != $1.range.lowerBound
            ? $0.range.lowerBound < $1.range.lowerBound : $0.range.upperBound < $1.range.upperBound }
        var out: [MarkdownCodeRun] = []
        out.reserveCapacity(sorted.count)
        var cursor = 0
        for run in sorted {
            var lo = max(run.range.lowerBound, cursor), hi = min(run.range.upperBound, bytes.count)
            while lo > cursor, lo < bytes.count, bytes[lo] & 0xC0 == 0x80 { lo -= 1 }
            while hi > lo, hi < bytes.count, bytes[hi] & 0xC0 == 0x80 { hi -= 1 }
            if hi <= lo { continue }
            out.append(MarkdownCodeRun(range: lo..<hi, style: run.style))
            cursor = hi
        }
        return out
    }

    /// `code` cut into chunks of at most ``linesPerChunk`` lines, each with the normalised `runs` that fall in
    /// it.
    static func chunks(code: String, runs: [MarkdownCodeRun], linesPerChunk: Int = MarkdownCodeSlicing.linesPerChunk)
        -> [Chunk] {
        let bytes = Array(code.utf8)
        let normal = normalized(runs, in: bytes)
        var starts = [0]
        var line = 0
        var i = 0
        while i < bytes.count {
            if bytes[i] == 10 {
                line += 1
                if line % linesPerChunk == 0 { starts.append(i + 1) }
            }
            i += 1
        }
        var chunks: [Chunk] = []
        chunks.reserveCapacity(starts.count)
        var first = 0   // the first run that can still reach a later chunk
        var index = 0
        while index < starts.count {
            let start = starts[index]
            let end = index + 1 < starts.count ? starts[index + 1] - 1 : bytes.count
            while first < normal.count, normal[first].range.upperBound <= start { first += 1 }
            var local: [ChunkRun] = []
            var k = first
            while k < normal.count, normal[k].range.lowerBound < end {
                let r = normal[k].range
                local.append(ChunkRun(range: (max(r.lowerBound, start) - start)..<(min(r.upperBound, end) - start),
                                      style: normal[k].style))
                k += 1
            }
            chunks.append(Chunk(index: index, text: String(decoding: bytes[start..<end], as: UTF8.self), runs: local))
            index += 1
        }
        return chunks
    }

    /// The styled content of a chunk: runs with a colour or background are their own segments.
    static func textContent(_ chunk: Chunk) -> TextContent {
        if chunk.runs.isEmpty { return .plain(chunk.text) }
        let bytes = Array(chunk.text.utf8)
        var requests: [TextRunRequest] = []
        var at = 0
        func slice(_ lo: Int, _ hi: Int) -> String { String(decoding: bytes[lo..<hi], as: UTF8.self) }
        for run in chunk.runs {
            if run.range.lowerBound > at { requests.append(TextRunRequest(string: slice(at, run.range.lowerBound))) }
            requests.append(TextRunRequest(string: slice(run.range.lowerBound, run.range.upperBound),
                                           foreground: run.style.foreground, background: run.style.background))
            at = run.range.upperBound
        }
        if at < bytes.count { requests.append(TextRunRequest(string: slice(at, bytes.count))) }
        return collapsedTextContent(requests)
    }
}

/// Up to 32 lines of a fence as one monospaced text (`BM-H`). Equatable, so a chunk whose lines and colours
/// did not change is not built again while the last chunk streams.
struct MarkdownCodeChunk: Component, ProposalElementGroup, @MainActor Equatable {
    let chunk: MarkdownCodeSlicing.Chunk
    let font: Font
    let foreground: Color?

    var content: some ProposalElementGroup {
        ProposalText(content: MarkdownCodeSlicing.textContent(chunk))
            .font(font)
            .foregroundColor(foreground)
    }

    static func == (l: MarkdownCodeChunk, r: MarkdownCodeChunk) -> Bool {
        l.chunk == r.chunk && l.font == r.font && l.foreground == r.foreground
    }
}

/// A fenced or indented code block: a rounded box around the chunks, in a horizontal scroller unless the theme
/// wraps (`BM-H`). Equatable on the block and the highlighter's identity, so the highlighter runs once per
/// change of this fence (`BM-F`).
struct MarkdownCodeFence: Component, ProposalElementGroup, @MainActor Equatable {
    let language: String?
    let code: String
    let isClosed: Bool
    let theme: MarkdownTheme
    let highlighter: (any MarkdownCodeHighlighter)?
    /// This fence's position among the document's code blocks (`BM-L`), the suffix of the button's identifier.
    let codeIndex: Int
    /// Read by the copy button's action (`BM-K`); an environment reading, so the fence stays comparable by its
    /// stored values (`EE-A`).
    @Environment(\.clipboard) var clipboard

    var content: some ProposalElementGroup {
        let runs = highlighter?.highlight(code: code, language: language, isClosed: isClosed) ?? []
        let chunks = MarkdownCodeSlicing.chunks(code: code, runs: runs)
        let theme = theme
        let column = VStack(alignment: .leading, spacing: Pixels(0)) {
            ForEach(chunks, id: \.index) { chunk in
                MarkdownCodeChunk(chunk: chunk, font: theme.codeFont, foreground: theme.codeForeground).equatable()
            }
        }
        let caption = theme.showsCodeLanguage ? language : nil
        let copyButton = theme.showsCodeCopyButton
        let clipboard = clipboard, code = code
        return VStack(alignment: .leading, spacing: Pixels(6)) {
            if let caption {
                ProposalText(verbatim: caption).font(theme.codeCaptionFont).foregroundColor(Color.secondary)
            }
            if theme.codeWraps {
                column
            } else {
                ProposalScrollView(.horizontal) { column }
            }
        }
        .padding(theme.codeBlockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: theme.codeBlockCornerRadius).fill(theme.codeBlockBackground)
        }
        .overlay(alignment: .topTrailing) {
            if copyButton {
                MarkdownCopyButton(code: code, clipboard: clipboard, font: theme.codeCaptionFont,
                                   identifier: theme.codeCopyButtonIdentifierPrefix.map { "\($0)\(codeIndex)" })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language ?? "Code")
    }

    static func == (l: MarkdownCodeFence, r: MarkdownCodeFence) -> Bool {
        l.codeIndex == r.codeIndex && l.code == r.code && l.language == r.language && l.isClosed == r.isClosed && l.theme == r.theme
            && markdownHighlighterIdentity(l.highlighter) == markdownHighlighterIdentity(r.highlighter)
    }
}

/// A highlighter's identity, `nil` for none: the view compares highlighters by instance.
func markdownHighlighterIdentity(_ highlighter: (any MarkdownCodeHighlighter)?) -> ObjectIdentifier? {
    guard let highlighter else { return nil }
    return ObjectIdentifier(highlighter)
}

/// The fence's copy button (`BM-K`, `BM-L`). Its own component, so a press writes this `@State` and rebuilds the
/// button alone, never the fence's chunks. The press bumps `presses` from input; a trigger `phaseAnimator` shows the
/// "copied" phase for the animation's 1.5 s (`GS-H`) on the window's clock, which tests drive with ticks, and a press
/// during the window restarts it.
struct MarkdownCopyButton: Component, ProposalElementGroup {
    /// How long the checkmark and "Copied" stay.
    static let feedbackSeconds = 1.5

    /// `pressed` is held for no time and draws like `copied`: a trigger that changes while `copied` is showing
    /// re-enters the phase it is already in with a hold of 0 (`enter` in `PhaseStepping`), which would end the
    /// window at once; entering `pressed` first, from `copied`, restarts the 1.5 s.
    enum Phase: CaseIterable { case idle, pressed, copied }

    let code: String
    let clipboard: Clipboard
    let font: Font
    let identifier: String?
    @State private var presses = 0

    var content: some ProposalElementGroup {
        let code = code, clipboard = clipboard, font = font, identifier = identifier
        let copy = {
            if clipboard.write(code) { presses += 1 }
        }
        return Box().phaseAnimator(Phase.allCases, trigger: presses) { _, phase in
            let copied = phase != .idle
            let button = Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(font)
                .foregroundColor(Color.secondary)
                .padding(Pixels(6))
                .onTapGesture { copy() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { copy() }
            return identifier.map { button.accessibilityIdentifier($0) } ?? button
        } animation: { phase in phase == .copied ? .linear(duration: Self.feedbackSeconds) : nil }
    }
}
