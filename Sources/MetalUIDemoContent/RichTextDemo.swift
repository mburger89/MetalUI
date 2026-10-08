import MetalUI
import Foundation

/// The rich-text demo (spec `2026-10-08-rich-text-design.md` §6, ruling
/// `RT-O` item 10), reached with `METALUI_RICH_TEXT_DEMO=1 swift run
/// MetalUIDemo` — and under SDL with the same variable. Six sections, styled
/// runs inside one `Text` each: **Markdown** in a literal, **interpolation**
/// of styled `Text` segments (never `+`, which is deprecated and warns), a
/// **mixed-size** paragraph that wraps, **decorations** (underline, coloured
/// underline, strikethrough, kerning, tracking, a superscript), **truncation**
/// of a two-colour line in tail and head modes, and **`Text(AttributedString)`**
/// with every key of MetalUI's scope.
///
/// **The human looks** (`docs/verification/human-checks.md` group RT): the
/// styles read as styled in light and dark, decorations crisp at 1× and 2×,
/// even line spacing, the same demo under SDL, VoiceOver reading the whole
/// sentence, links inert.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each section is its own function, passed as an
/// argument to a generic composing function (the Windows 1 MB stack rule,
/// `demoContent()`'s note); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func richTextDemoContent() -> some Element {
    richTextRoot(markdown: richTextMarkdown(), interpolation: richTextInterpolation(), sizes: richTextSizes(),
                 decorations: richTextDecorations(), truncation: richTextTruncation(),
                 attributed: richTextAttributed())
}

/// The root: a title, then the sections in a column.
@MainActor
private func richTextRoot(markdown: some Element, interpolation: some Element, sizes: some Element,
                          decorations: some Element, truncation: some Element,
                          attributed: some Element) -> some Element {
    Column(gap: Pixels(18)) {
        Text("Rich text").font(size: 22)
        markdown
        interpolation
        sizes
        decorations
        truncation
        attributed
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

/// One section: a caption over its content.
@MainActor
private func richTextSection(_ title: String, @ElementBuilder content: () -> some Element) -> some Element {
    Column(gap: Pixels(6)) {
        Text(verbatim: title).foregroundColor(.secondary)
        content()
    }
    .alignItems(.flexStart)
}

/// Markdown in a literal: every inline form SwiftUI parses (ruling RT-B).
@MainActor
private func richTextMarkdown() -> some Element {
    richTextSection("Markdown") {
        Text("**Bold**, _italic_, ***bold italic***, ~~struck~~, `code`, [a link](https://example.com) and https://example.com")
    }
}

/// Coloured and weighted segments interpolated into a literal (`C2`'s shape,
/// ruling RT-C item 4).
@MainActor
private func richTextInterpolation() -> some Element {
    let total = Text("12").bold().foregroundColor(.red)
    let pending = Text("3").foregroundColor(.blue)
    return richTextSection("Interpolation") {
        Text("Total: \(total) items, \(pending) pending, **\(Text("1").italic()) late**")
    }
}

/// A 10-, 20- and 30-point paragraph wrapping across lines (`RT-G`). The
/// sizes are `font(size:)`, not `font(.system(size:))`: `Text.font(_: Font?)`
/// traps when a tree is built off the main thread, as
/// `everyProductionTreeBuildsOnAOneMegabyteThread` builds it (a closure in
/// its body carries a main-actor check — measured, and so at `70ed000`;
/// ruling RT-T item 5).
@MainActor
private func richTextSizes() -> some Element {
    let medium = Text("twenty points").font(size: 20)
    let large = Text("thirty points").font(size: 30)
    let small = Text("and ten points again, wrapping").font(size: 10)
    return richTextSection("Mixed sizes") {
        Text("Thirteen points, \(medium), \(large) \(small) to the next line and the next.")
            .frame(width: Pixels(360), alignment: .leading)
    }
}

/// Underline, coloured underline, strikethrough, kerning, tracking and a
/// superscript (`RT-J`, `RT-H`).
@MainActor
private func richTextDecorations() -> some Element {
    let underlined = Text("underlined").underline()
    let coloured = Text("coloured").underline(color: .red)
    let struck = Text("struck").strikethrough()
    let kerned = Text("kerned").kerning(3)
    let tracked = Text("tracked").tracking(3)
    let superscript = Text("2").font(size: 9).baselineOffset(6)
    return richTextSection("Decorations") {
        Text("\(underlined), \(coloured), \(struck), \(kerned), \(tracked), E = mc\(superscript)")
    }
}

/// A two-colour line under `lineLimit(1)`, truncated at the tail and at the
/// head (`RT-I`).
@MainActor
private func richTextTruncation() -> some Element {
    let red = Text("A red beginning that runs on").foregroundColor(.red)
    let blue = Text("into a blue ending that cannot fit").foregroundColor(.blue)
    return richTextSection("Truncation") {
        Column(gap: Pixels(4)) {
            Text("\(red) \(blue)").lineLimit(1).truncationMode(.tail).frame(width: Pixels(300), alignment: .leading)
            Text("\(red) \(blue)").lineLimit(1).truncationMode(.head).frame(width: Pixels(300), alignment: .leading)
        }
        .alignItems(.flexStart)
    }
}

/// `Text(AttributedString)` with every key of MetalUI's scope (ruling RT-D).
@MainActor
private func richTextAttributed() -> some Element {
    richTextSection("AttributedString") {
        Text(richTextAttributedString())
    }
}

/// An attributed string setting each key on its own word.
@MainActor
func richTextAttributedString() -> AttributedString {
    var string = AttributedString()
    func word(_ text: String, _ style: (inout AttributedString) -> Void) {
        var piece = AttributedString(text)
        style(&piece)
        string.append(piece)
        string.append(AttributedString(" "))
    }
    word("Title") { $0.font = .title3 }
    word("orange") { $0.foregroundColor = .orange }
    word("highlighted") { $0.backgroundColor = .yellow }
    word("underlined") { $0.underlineStyle = Text.LineStyle(pattern: .solid, color: .blue) }
    word("struck") { $0.strikethroughStyle = .single }
    word("kerned") { $0.kern = 2 }
    word("tracked") { $0.tracking = 2 }
    word("raised") { $0.baselineOffset = 4 }
    word("linked") { $0.link = URL(string: "https://example.com") }
    return string
}
