import MetalUI
import Observation

/// The block Markdown demo (`BM-`, record 235, human checks group BM), reached with
/// `METALUI_MARKDOWN_DEMO=1 swift run MetalUIDemo`: a chat transcript anchored at the bottom (`LazyVStack` in a
/// vertical scroller, `defaultScrollAnchor(.bottom)`) whose last reply streams in a few characters at a time through
/// `MarkdownDocument.append`, the way a model's tokens arrive. The reply holds every block kind (headings, inline
/// styles and a link, bullet and ordered lists with nesting, a quote, a rule, a highlighted Swift fence and a table).
/// A button streams another reply; a toggle switches long code lines between wrapping and the horizontal scroller
/// (a vertical wheel over it scrolls the transcript, `XS-F`).
///
/// **The human looks** (group BM): no flicker or jump at the bottom while a reply streams; a vertical wheel over a
/// code block or a table scrolls the transcript (wrapping on); a horizontal wheel scrolls the unwrapped block; links
/// open in the browser; the colours read in light and dark; VoiceOver reads headings as headings, list items and code.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and `Expected.swift` do not move. The
/// builder is its own function (the Windows 1 MB stack rule, `demoContent()`'s note), built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func markdownDemoContent() -> some Element {
    markdownDemoRoot(MarkdownDemoTranscript())
}

/// The root: a bar over the transcript.
@MainActor
private func markdownDemoRoot(_ transcript: MarkdownDemoTranscript) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        MarkdownDemoBar()
        transcript
    }
    .padding(Pixels(12))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.surface)
}

/// The demo's one model: the replies, whether the last one is streaming, and the wrap switch.
@Observable @MainActor
public final class MarkdownDemoModel {
    /// The replies, oldest first; the last one grows while streaming.
    public var replies: [MarkdownDocument] = (0..<3).map { MarkdownDocument(parsing: markdownDemoReply($0)) }
    /// Whether code blocks wrap their long lines.
    public var codeWraps = true
    /// How many replies have been streamed so far (selects the next script).
    var streamed = 0
    /// Whether a reply is streaming now.
    public private(set) var isStreaming = false

    /// A model holding three finished replies.
    public init() {}

    /// Streams another reply into the transcript, `chunk` characters every `delay` nanoseconds.
    public func stream(chunk: Int = 3, delay: UInt64 = 25_000_000) async {
        guard !isStreaming else { return }
        isStreaming = true
        defer { isStreaming = false }
        let script = Array(markdownDemoReply(3 + streamed))
        streamed += 1
        replies.append(MarkdownDocument())
        var at = 0
        while at < script.count, !Task.isCancelled {
            let next = min(at + chunk, script.count)
            replies[replies.count - 1].append(String(script[at..<next]))
            at = next
            try? await Task.sleep(nanoseconds: delay)
        }
    }
}

/// The model the demo and its test share.
@MainActor public let markdownDemoModel = MarkdownDemoModel()

/// A reply's script: every block kind, with `n` in the first heading so replies differ.
public func markdownDemoReply(_ n: Int) -> String {
    """
    # Reply \(n): a tour of the blocks

    Streaming Markdown has **bold**, *italic*, ~~struck~~ text, `inline code` and a [link to the docs](https://example.com). \
    This paragraph is long enough to wrap over more than one line in a narrow window, so that a token \
    changes only the last block while the lines above it stay put.

    ## A list and a quote

    - First bullet, with `code`
    - Second bullet
      - A nested bullet
      - Another one
    - Third bullet

    1. Ordered one
    2. Ordered two

    > A block quote keeps its bar as tall as its text.
    > It can hold **styled** text too.

    ---

    ### A highlighted fence

    ```swift
    func greet(_ name: String) -> String {
        // A long line stays whole when code does not wrap: \(String(repeating: "abcdefghij ", count: 12))
        let message = "Hello, \\(name)!"
        return message
    }
    print(greet("Markdown"))
    ```

    ### A table

    | Language | Typed | Score |
    |:---------|:-----:|------:|
    | Swift    | yes   | 9.5   |
    | Python   | no    | 8     |
    | Rust     | yes   | 9     |

    That is the end of reply \(n).
    """
}

/// A highlighter for the demo: Swift keywords, strings and comments by a byte scan. A pure read of its arguments.
final class MarkdownDemoHighlighter: MarkdownCodeHighlighter {
    private static let keywords: Set<String> = ["func", "let", "var", "return", "if", "else", "for", "in", "print"]
    private let keyword = CodeStyle(foreground: Color(hue: 0.83, saturation: 0.7, brightness: 0.8))
    private let string = CodeStyle(foreground: Color(hue: 0.05, saturation: 0.8, brightness: 0.85))
    private let comment = CodeStyle(foreground: Color(hue: 0.33, saturation: 0.6, brightness: 0.6))

    func highlight(code: String, language: String?, isClosed: Bool) -> [MarkdownCodeRun] {
        guard language == "swift" else { return [] }
        let bytes = Array(code.utf8)
        var runs: [MarkdownCodeRun] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "/"), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "/") {
                var j = i
                while j < bytes.count, bytes[j] != 10 { j += 1 }
                runs.append(MarkdownCodeRun(range: i..<j, style: comment))
                i = j
            } else if b == UInt8(ascii: "\"") {
                var j = i + 1
                while j < bytes.count, bytes[j] != UInt8(ascii: "\""), bytes[j] != 10 { j += 1 }
                j = min(j + 1, bytes.count)
                runs.append(MarkdownCodeRun(range: i..<j, style: string))
                i = j
            } else if (b >= 97 && b <= 122) || (b >= 65 && b <= 90) {
                var j = i
                while j < bytes.count, (bytes[j] >= 97 && bytes[j] <= 122) || (bytes[j] >= 65 && bytes[j] <= 90) { j += 1 }
                if Self.keywords.contains(String(decoding: bytes[i..<j], as: UTF8.self)) {
                    runs.append(MarkdownCodeRun(range: i..<j, style: keyword))
                }
                i = j
            } else {
                i += 1
            }
        }
        return runs
    }
}

/// The demo highlighter, one instance (the view compares highlighters by identity).
@MainActor private let markdownDemoHighlighter = MarkdownDemoHighlighter()

/// The bar: a title, the stream button and the wrap toggle.
struct MarkdownDemoBar: Component {
    var content: some ProposalElementGroup {
        HStack(spacing: Pixels(12)) {
            ProposalText("Markdown transcript").font(size: 18)
            Button("Stream another reply") { Task { await markdownDemoModel.stream() } }
            Toggle("Wrap code", isOn: Binding(get: { markdownDemoModel.codeWraps },
                                              set: { markdownDemoModel.codeWraps = $0 }))
        }
    }
}

/// The transcript: replies in a lazy stack, anchored at the bottom, the first stream started when the window appears.
struct MarkdownDemoTranscript: Component {
    var content: some ElementGroup {
        let model = markdownDemoModel
        var theme = MarkdownTheme()
        theme.codeWraps = model.codeWraps
        let shown = theme
        return ProposalScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(14)) {
                ForEach(Array(model.replies.indices), id: \.self) { index in
                    MarkdownView(model.replies[index])
                        .markdownTheme(shown)
                        .codeHighlighter(markdownDemoHighlighter)
                        .equatable()
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        .task { await model.stream() }
    }
}
