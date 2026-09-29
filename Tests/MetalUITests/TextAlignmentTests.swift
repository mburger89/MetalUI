import Testing
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 (spec row 3.18; ruling TE-J): each line sits in
// the text's own box, `(box − lineWidth) × factor` in, the box being the width
// paint wraps at — the text's widest line when it is not wrapped by its parent.

private let twoLines = "Short line\nA much longer second line"

/// The first glyph sprite's x of each of the two lines `content` draws, at
/// scale 1: the lines are told apart by the sprite's top (line 2 sits a line
/// height lower).
@MainActor
private func lineStarts<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws -> [Float] {
    let frame = try controlRender(controlRoot { content() })
    let glyphs = frame.finalizedScene().glyphs
    try #require(glyphs.count > 20)
    let tops = glyphs.map(\.bounds.origin.y)
    let split = (tops.min()! + tops.max()!) / 2
    let first = glyphs.filter { $0.bounds.origin.y < split }.map(\.bounds.origin.x).min()!
    let second = glyphs.filter { $0.bounds.origin.y >= split }.map(\.bounds.origin.x).min()!
    return [first, second]
}

/// **3.18.** A1: under `.center` and `.trailing` the short line moves by
/// `(box − w₁) × ½` and `× 1` inside a box as wide as the long line, and the
/// long line stays; A2: a wider leading-aligned frame changes nothing (the box
/// is the text's, not the proposal); A3: a one-line text is unmoved; A4: the
/// value comes through the environment.
///
/// Mutation **M3q**: the box is the proposal.
@MainActor
@Test func multilineTextAlignmentPlacesLinesInsideTheTextsBox() throws {
    let system = teSystem()
    let key = system.resolveFont(family: nil, size: 13)
    let short = system.measure("Short line", font: key, wrappingAt: nil).widestLine
    let box = system.measure(twoLines, font: key, wrappingAt: nil).widestLine
    try #require(box - short > 40)
    let leading = try lineStarts { Text(twoLines) }
    for (alignment, factor) in [(TextAlignment.center, 0.5), (.trailing, 1.0)] {
        let moved = try lineStarts { Text(twoLines).multilineTextAlignment(alignment) }
        let shift = Double(moved[0] - leading[0])
        #expect(abs(shift - (box - short) * factor) <= 1, "A1 \(alignment): moved \(shift)")
        #expect(moved[1] == leading[1], "A1 \(alignment): the long line spans the box")
        let framed = try lineStarts {
            Text(twoLines).multilineTextAlignment(alignment).frame(width: Pixels(300), alignment: .leading)
        }
        #expect(framed == moved, "A2 \(alignment): a wider frame is not the box")
    }
    let single = try controlRender(controlRoot { Text("One line").multilineTextAlignment(.trailing)
        .frame(width: Pixels(200), alignment: .leading) })
    let plain = try controlRender(controlRoot { Text("One line").frame(width: Pixels(200), alignment: .leading) })
    #expect(teSprites(single) == teSprites(plain), "A3: one line is unmoved")
    let env = try lineStarts { Column { Text(twoLines) }.multilineTextAlignment(.trailing) }
    let own = try lineStarts { Text(twoLines).multilineTextAlignment(.trailing) }
    #expect(env[0] - env[1] == own[0] - own[1], "A4: through the environment")
    #expect(env[0] != env[1])
}

