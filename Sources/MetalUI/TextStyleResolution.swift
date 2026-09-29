import MetalUICore
import MetalUILayout
import MetalUITextSystem

// The ONE resolution function every text element calls, in layout and in paint
// (spec §3, "Resolution"; rulings TE-B, TE-D, TE-F, TE-H). Pure over the
// element's own request and the environment, so the two phases — which read
// the same environment — resolve the same answer by construction.

/// What a text element asked for itself.
struct TextStyleRequest {
    var font: TextFontRequest = .inherit
    var weight: Font.Weight?
    var italic = false
    var foreground: ColorToken?
}

/// A text's resolved style: the face to ask the text system for, the glyph
/// colour, and what `.lineLimit`, `.truncationMode` and
/// `.multilineTextAlignment` above it wrote.
struct ResolvedTextStyle: Equatable {
    var descriptor: FontDescriptor
    var foreground: ColorToken
    var lineLimit: TextLineLimit
    var truncation: TextTruncation
    var alignment: TextLineAlignment
}

/// The default font — what a text resolves when neither it nor the
/// environment names one (ruling TE-F item 1; probe F8, Z2, R2): the system
/// face at 9 pt under `.mini`, 11 under `.small`, 13 otherwise.
func defaultFont(for controlSize: ControlSize) -> Font {
    switch controlSize {
    case .mini: .system(size: 9)
    case .small: .system(size: 11)
    case .regular, .large, .extraLarge: .system(size: 13)
    }
}

/// The resolution (spec §3): the font is the element's own (an explicit font,
/// or the default font for `font(nil)`), else the environment's, else the
/// default font by `controlSize`; then the element's own `fontWeight`, else the
/// environment's, over it, and italic if the font, the element or the
/// environment asks for it. The colour is the element's own token, else the
/// environment's `foregroundStyle`, else `.textPrimary`.
func resolveTextStyle(_ own: TextStyleRequest, in environment: EnvironmentValues) -> ResolvedTextStyle {
    let font: Font
    switch own.font {
    case .explicit(let explicit): font = explicit
    case .defaultFont: font = defaultFont(for: environment.controlSize)
    case .inherit: font = environment.font ?? defaultFont(for: environment.controlSize)
    }
    let descriptor = font.descriptor(weight: own.weight ?? environment.fontWeight,
                                     italic: own.italic || environment.italic)
    return ResolvedTextStyle(
        descriptor: descriptor,
        foreground: own.foreground ?? environment.foregroundStyle ?? .textPrimary,
        lineLimit: environment.textLineLimit,
        truncation: environment.truncationMode.seam,
        alignment: environment.multilineTextAlignment.seam)
}

extension Text.TruncationMode {
    var seam: TextTruncation {
        switch self {
        case .head: .head
        case .tail: .tail
        case .middle: .middle
        }
    }
}

extension TextAlignment {
    var seam: TextLineAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// How many lines a text draws at `width` inside `height`, and the options
/// that draw them (rulings TE-H item 2, TE-G item 4): the limit's upper bound
/// (below 1 acts as 1), then — for a finite `height` — `max(1, ⌊height /
/// lineHeight⌋)` when that is fewer (probe L5, X9). Measurement passes the
/// proposal; paint passes the width it wraps at and the box it was placed in,
/// so the two agree whenever the box is the answer (and a reserved or framed
/// box, being taller, caps nothing more).
struct TextLines {
    var options: TextLayoutOptions
    var measured: TextMeasurement
    var lines: Int
    var metrics: TextFontMetrics
}

@MainActor
func textLines(_ string: String, font: FontKey, system: any TextSystem, wrappingAt width: Double?,
               height: Double?, style: ResolvedTextStyle) -> TextLines {
    let metrics = system.fontMetrics(font)
    var options = TextLayoutOptions(maxLines: style.lineLimit.max.map { Swift.max($0, 1) },
                                    truncation: style.truncation, alignment: style.alignment)
    var measured = system.measure(string, font: font, wrappingAt: width, options: options)
    let lineHeight = metrics.lineHeight
    var lines = lineHeight > 0 ? Swift.max(1, Int((measured.totalHeight / lineHeight).rounded())) : 1
    if let height, height.isFinite, lineHeight > 0 {
        let heightLines = Swift.max(1, Int(Swift.min(height / lineHeight, Double(Int.max / 2)).rounded(.down)))
        if heightLines < lines {
            options.maxLines = heightLines
            measured = system.measure(string, font: font, wrappingAt: width, options: options)
            lines = heightLines
        }
    }
    return TextLines(options: options, measured: measured, lines: lines, metrics: metrics)
}

/// A text's answer to `proposal` (rulings LR-AU, TE-H, TE-G item 4): a
/// concrete width wraps it, an unspecified width asks for its intrinsic
/// one-line-per-hard-break width; a finite height limits its lines. The width
/// is the widest kept line, never above a finite proposal; the height is the
/// kept lines, padded to the limit's lower bound (probe L2, L3; not for an
/// empty string, X10); the baselines are `round(ascent)` and that plus
/// `(lines − 1) × lineHeight` (B1).
@MainActor
func proposalTextMeasurement(_ string: String, font: FontKey, system: any TextSystem,
                             proposal: ProposedSize, style: ResolvedTextStyle) -> LayoutMeasurement {
    // SKELETON (lane 3 red commit): the style is not applied yet.
    proposalTextMeasurement(string, font: font, system: system, proposal: proposal)
}
