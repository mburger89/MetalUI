import MetalUICore
import MetalUILayout
import MetalUITextSystem

// Rich text, lane 2 — the run model of one `Text` (rulings RT-E, RT-F, RT-G,
// RT-K, RT-L; spec §1.3). A `Text` holds its content — one plain string, or
// segments as written (`TextRunRequest`) — and its own `Text`-level fields,
// the OUTER layer: a segment's own field wins, the `Text`'s reaches only the
// segments that left it unset (RT-E item 2). Resolution runs once per run in
// layout and again in paint, through `resolveTextStyle` (TE-AA); the layout
// half crosses the seam as a `StyledText` (RT-F), the paint half — colours,
// decorations, backgrounds — stays here and is applied by run index.

/// One segment of a styled `Text`, as written (spec §1.3): its string and the
/// fields it set (`nil`: unset — the outer `Text`'s field reaches it).
struct TextRunRequest: Sendable, Hashable {
    var string: String
    var font: TextFontRequest?
    var weight: Font.Weight?
    var italic: Bool?
    var monospaced: Bool?
    var foreground: Color?
    var background: Color?
    /// `isActive` false is an explicit "none" an outer underline does not
    /// override.
    var underline: Text.LineStyle?
    var strikethrough: Text.LineStyle?
    var kerning: Double?
    var tracking: Double?
    var baselineOffset: Double?
    /// The destination of a link run (`RT-K`): styled, inert (divergence 150).
    var link: String?

    init(string: String, font: TextFontRequest? = nil, weight: Font.Weight? = nil, italic: Bool? = nil,
         monospaced: Bool? = nil, foreground: Color? = nil, background: Color? = nil,
         underline: Text.LineStyle? = nil, strikethrough: Text.LineStyle? = nil, kerning: Double? = nil,
         tracking: Double? = nil, baselineOffset: Double? = nil, link: String? = nil) {
        self.string = string
        self.font = font
        self.weight = weight
        self.italic = italic
        self.monospaced = monospaced
        self.foreground = foreground
        self.background = background
        self.underline = underline
        self.strikethrough = strikethrough
        self.kerning = kerning
        self.tracking = tracking
        self.baselineOffset = baselineOffset
        self.link = link
    }

    /// Whether every field but the string equals `other`'s — two such
    /// neighbours are one run.
    func hasSameAttributes(as other: TextRunRequest) -> Bool {
        var copy = other
        copy.string = string
        return copy == self
    }

    /// Whether the only fields set are the ones a plain `Text` already had —
    /// font, weight, italic, colour (`RT-F` item 3's fast path).
    var setsOnlyPlainFields: Bool {
        monospaced == nil && background == nil && underline == nil && strikethrough == nil
            && kerning == nil && tracking == nil && baselineOffset == nil && link == nil
    }
}

/// A `Text`'s content (spec §1.3): one plain string — the only form before
/// rich text — or segments as written.
enum TextContent: Sendable, Hashable {
    case plain(String)
    case runs([TextRunRequest])

    /// The rendered string: the segments' strings, concatenated (`RT-L` item 1).
    var string: String {
        switch self {
        case .plain(let string): string
        case .runs(let runs): runs.map(\.string).joined()
        }
    }

    /// `runs` with neighbours whose attributes agree joined into one segment,
    /// so `Text("a") + Text("b")` is the one run `"ab"` (`RT-F` item 3: a text
    /// whose runs collapse to one run takes the plain calls).
    static func joined(_ runs: [TextRunRequest]) -> [TextRunRequest] {
        var result: [TextRunRequest] = []
        result.reserveCapacity(runs.count)
        for run in runs {
            if let last = result.last, last.hasSameAttributes(as: run) {
                result[result.count - 1].string += run.string
            } else {
                result.append(run)
            }
        }
        return result
    }
}

/// The rich `Text`-level fields (ruling RT-E item 3), beside the four a plain
/// `Text` already had (font, weight, italic, colour). `nil`: unset.
struct TextRichFields: Sendable, Hashable {
    var underline: Text.LineStyle?
    var strikethrough: Text.LineStyle?
    var kerning: Double?
    var tracking: Double?
    var baselineOffset: Double?
    var monospaced: Bool?

    /// No rich field is set — a condition of the fast path (`RT-F` item 3).
    var isEmpty: Bool {
        underline == nil && strikethrough == nil && kerning == nil && tracking == nil
            && baselineOffset == nil && monospaced == nil
    }
}

/// The rich fields behind one reference (`RT-R` item 4): a `Text` is held by
/// value inside every container's generic content, so its size is stack on a
/// 1 MB Windows thread (`everyProductionTreeBuildsOnAOneMegabyteThread`).
/// Immutable and replaced on every write — value semantics — and `nil` while
/// no rich field is set, so a plain `Text` grows by one word.
final class TextRichBox: Sendable {
    let fields: TextRichFields
    init(_ fields: TextRichFields) { self.fields = fields }

    /// `fields` boxed, or `nil` when none is set.
    static func boxing(_ fields: TextRichFields) -> TextRichBox? { fields.isEmpty ? nil : TextRichBox(fields) }
}

// MARK: - Concatenation (RT-E items 2, 4)

/// The segments of a text with its own `Text`-level fields pushed into every
/// segment that left them unset (ruling RT-E item 2) — what `+` concatenates.
func pushedRuns(_ content: TextContent, own: TextStyleRequest, rich: TextRichFields) -> [TextRunRequest] {
    let runs: [TextRunRequest] = switch content {
    case .plain(let string): [TextRunRequest(string: string)]
    case .runs(let runs): runs
    }
    return runs.map { run in
        var pushed = run
        if pushed.font == nil, own.font != .inherit { pushed.font = own.font }
        if pushed.weight == nil { pushed.weight = own.weight }
        if pushed.italic == nil, own.italic { pushed.italic = true }
        if pushed.monospaced == nil { pushed.monospaced = rich.monospaced }
        if pushed.foreground == nil { pushed.foreground = own.foreground }
        if pushed.underline == nil { pushed.underline = rich.underline }
        if pushed.strikethrough == nil { pushed.strikethrough = rich.strikethrough }
        if pushed.kerning == nil { pushed.kerning = rich.kerning }
        if pushed.tracking == nil { pushed.tracking = rich.tracking }
        if pushed.baselineOffset == nil { pushed.baselineOffset = rich.baselineOffset }
        return pushed
    }
}

/// What a value read through `Mirror` is, for the operand check (`RT-O`
/// item 1).
enum MirrorFieldKind: Equatable {
    case optional, collection, equatable, unrecognised
}

/// How the operand check reads a stored field (`RT-O` item 1): an optional by
/// its nil-ness, a collection or dictionary by its emptiness, an `Equatable`
/// value by `==`, anything else unrecognised.
func mirrorFieldKind(_ value: Any) -> MirrorFieldKind {
    switch Mirror(reflecting: value).displayStyle {
    case .optional: return .optional
    case .collection, .dictionary, .set: return .collection
    default: return value is any Equatable ? .equatable : .unrecognised
    }
}

/// Whether `value` reads as its default `reference` (`RT-O` item 1): `nil`
/// when its kind is unrecognised.
func mirrorFieldIsDefault(_ value: Any, reference: Any) -> Bool? {
    switch mirrorFieldKind(value) {
    case .optional:
        return Mirror(reflecting: value).children.isEmpty == Mirror(reflecting: reference).children.isEmpty
    case .collection:
        return Mirror(reflecting: value).children.isEmpty
    case .equatable:
        guard let equatable = value as? any Equatable else { return nil }
        return equalsAsItsOwnType(equatable, reference)
    case .unrecognised:
        return nil
    }
}

/// `value == other` when `other` is `value`'s own type (the opened
/// existential of `mirrorFieldIsDefault`).
private func equalsAsItsOwnType<T: Equatable>(_ value: T, _ other: Any) -> Bool {
    (other as? T) == value
}

/// The first member of `handlers` that is not `Handlers()`'s, by name, or
/// `nil` when every member is the default (`RT-O` item 1). **Compared child by
/// child through `Mirror`**, so a member `Handlers` gains later is checked
/// without an edit here; a member of a kind the check cannot read is reported
/// as set (a refusal, never a silent pass).
@MainActor
func firstSetHandlersMember(_ handlers: Handlers) -> String? {
    let reference = Array(Mirror(reflecting: Handlers()).children)
    for (index, child) in Mirror(reflecting: handlers).children.enumerated() {
        let label = child.label ?? "#\(index)"
        guard index < reference.count, mirrorFieldIsDefault(child.value, reference: reference[index].value) == true
        else { return label }
    }
    return nil
}

/// Why `text` cannot be an operand of `+` or an interpolated `Text` (ruling
/// RT-E item 4, divergence 155): the first of its style, decoration, id or a
/// handler member that is set, by name; `nil` when it carries only text.
@MainActor
func textOperandRefusal(_ text: Text) -> String? {
    if text.style != Style() { return "style (a layout modifier such as .margin or .flexGrow)" }
    if text.decoration != Decoration() { return "decoration (.background, .border, .opacity, .cornerRadius …)" }
    if let id = text.elementID { return "elementID (.id(\"\(id)\"))" }
    if let member = firstSetHandlersMember(text.handlers) { return "handlers.\(member)" }
    return nil
}

/// Traps when `text` carries anything but text (ruling RT-E item 4).
@MainActor
func requireTextOperand(_ text: Text, _ side: String) {
    if let field = textOperandRefusal(text) {
        preconditionFailure("""
            Text + Text: the \(side) operand carries \(field), which a concatenation cannot keep \
            (divergence 155, ruling RT-E item 4). Concatenate plain Texts and decorate the result.
            """)
    }
}

// MARK: - The fast path (RT-F item 3)

/// The string and request the plain calls take, when `content` is plain or
/// one run setting only font, weight, italic or colour and no rich
/// `Text`-level field is set (`RT-F` item 3); `nil`: the styled path.
func plainTextForm(_ content: TextContent, own: TextStyleRequest,
                   rich: TextRichFields) -> (string: String, request: TextStyleRequest)? {
    guard rich.isEmpty else { return nil }
    switch content {
    case .plain(let string):
        return (string, own)
    case .runs(let runs):
        guard runs.count == 1, runs[0].setsOnlyPlainFields else { return nil }
        let run = runs[0]
        return (run.string, TextStyleRequest(font: run.font ?? own.font, weight: run.weight ?? own.weight,
                                             italic: run.italic ?? own.italic,
                                             foreground: run.foreground ?? own.foreground))
    }
}

// MARK: - Resolution (RT-E item 2, RT-K, RT-L)

/// One resolved run's paint attributes — what never crosses the seam (RT-F
/// item 1). Colours are unresolved `Color`s, resolved by `PaintPass.resolve`
/// at paint (they snap, `RT-L` item 2).
struct TextRunPaint: Hashable, Sendable {
    var foreground: Color
    var background: Color?
    /// The underline's colour when the run is underlined (its own colour,
    /// else the run's foreground, `RT-J` item 4).
    var underline: Color?
    var strikethrough: Color?
}

/// A styled `Text` resolved against its environment and text system: the
/// `StyledText` that crosses the seam, one paint record per run (index for
/// index — equal neighbours kept, `RT-R` item 1) and the `Text`-level style
/// (line limit, truncation, alignment).
struct ResolvedRichText {
    var text: StyledText
    var paints: [TextRunPaint]
    var style: ResolvedTextStyle
}

/// Resolves every run (ruling RT-E item 2): `run.field ?? text.field`, then
/// `resolveTextStyle` with the run's merged request — **once per run**, in
/// layout and again in paint; a link run with no colour at either layer is
/// `Color.accentColor` before the environment is consulted (`RT-K`). Runs
/// whose layout and paint attributes agree join (`C9b`); empty runs drop.
@MainActor
func resolveRichText(_ content: TextContent, own: TextStyleRequest, rich: TextRichFields,
                     in environment: EnvironmentValues, system: any TextSystem) -> ResolvedRichText {
    let requests: [TextRunRequest] = switch content {
    case .plain(let string): [TextRunRequest(string: string)]
    case .runs(let runs): runs
    }
    var styledRuns: [StyledTextRun] = []
    var paints: [TextRunPaint] = []
    var string = ""
    for run in requests {
        let length = run.string.utf16.count
        if length == 0, !styledRuns.isEmpty { continue }
        let request = TextStyleRequest(
            font: run.font ?? own.font, weight: run.weight ?? own.weight, italic: run.italic ?? own.italic,
            foreground: run.foreground ?? own.foreground ?? (run.link != nil ? .accentColor : nil),
            monospaced: run.monospaced ?? rich.monospaced ?? false)
        let resolved = resolveTextStyle(request, in: environment)
        let style = TextRunStyle(font: system.resolveFont(resolved.descriptor),
                                 kerning: run.kerning ?? rich.kerning ?? 0,
                                 tracking: run.tracking ?? rich.tracking ?? 0,
                                 baselineOffset: run.baselineOffset ?? rich.baselineOffset ?? 0)
        let underline = (run.underline ?? rich.underline).flatMap { $0.isActive ? ($0.color ?? resolved.foreground) : nil }
        let strike = (run.strikethrough ?? rich.strikethrough)
            .flatMap { $0.isActive ? ($0.color ?? resolved.foreground) : nil }
        let paint = TextRunPaint(foreground: resolved.foreground, background: run.background,
                                 underline: underline, strikethrough: strike)
        string += run.string
        if let last = styledRuns.last, last.length == 0 {
            // An empty first run gives way to the first run with text.
            styledRuns[styledRuns.count - 1] = StyledTextRun(length: length, style: style)
            paints[paints.count - 1] = paint
        } else if let last = styledRuns.last, last.style == style, paints[paints.count - 1] == paint {
            styledRuns[styledRuns.count - 1].length += length
        } else {
            styledRuns.append(StyledTextRun(length: length, style: style))
            paints.append(paint)
        }
    }
    return ResolvedRichText(text: StyledText(keepingNeighbours: string, runs: styledRuns), paints: paints,
                            style: resolveTextStyle(own, in: environment))
}

// MARK: - Measurement (RT-G)

/// How many lines a styled text draws at `width` inside `height`, and the
/// options that draw them (ruling RT-G item 3): the limit's upper bound
/// first, then — for a finite `height` — as many leading lines as fit their
/// summed heights, at least one (`C16`, `C16b`).
struct RichTextLines {
    var options: TextLayoutOptions
    var measured: StyledTextMeasurement
}

@MainActor
func styledTextLines(_ resolved: ResolvedRichText, system: any TextSystem, wrappingAt width: Double?,
                     height: Double?) -> RichTextLines {
    var options = TextLayoutOptions(maxLines: resolved.style.lineLimit.max.map { Swift.max($0, 1) },
                                    truncation: resolved.style.truncation, alignment: resolved.style.alignment)
    var measured = system.measure(resolved.text, wrappingAt: width, options: options)
    if let height, height.isFinite, measured.lines.count > 1 {
        var kept = 0
        var sum = 0.0
        for line in measured.lines {
            guard kept == 0 || sum + line.height <= height else { break }
            sum += line.height
            kept += 1
        }
        if kept < measured.lines.count {
            options.maxLines = kept
            measured = system.measure(resolved.text, wrappingAt: width, options: options)
        }
    }
    return RichTextLines(options: options, measured: measured)
}

/// A styled text's answer to `proposal` (rulings LR-AU, RT-G): the widest
/// kept line, never above a finite proposal; the kept lines' summed heights,
/// padded to the limit's lower bound with the **first run's** line height
/// (`C18`); the first baseline `round(first line's ascent)` and the last
/// `top(last) + round(last line's ascent)` (RT-G item 2).
@MainActor
func richTextMeasurement(_ resolved: ResolvedRichText, system: any TextSystem,
                         proposal: ProposedSize) -> LayoutMeasurement {
    let wrappingAt = proposal.width.map { Swift.max($0, smallestWrapWidth) }
    let laid = styledTextLines(resolved, system: system, wrappingAt: wrappingAt, height: proposal.height)
    let width = proposal.width.map { Swift.min($0, laid.measured.widestLine) } ?? laid.measured.widestLine
    var height = laid.measured.totalHeight
    if let minimum = resolved.style.lineLimit.min, !resolved.text.string.isEmpty {
        let first = system.fontMetrics(resolved.text.runs[0].style.font).lineHeight
        height = Swift.max(height, Double(Swift.max(minimum, 1)) * first)
    }
    guard let firstLine = laid.measured.lines.first, let lastLine = laid.measured.lines.last else {
        return LayoutMeasurement(size: SizeD(width: width, height: height), firstBaseline: 0, lastBaseline: 0)
    }
    let first = firstLine.top + (firstLine.baseline - firstLine.top).rounded()
    let last = lastLine.top + (lastLine.baseline - lastLine.top).rounded()
    return LayoutMeasurement(size: SizeD(width: width, height: height), firstBaseline: first, lastBaseline: last)
}
