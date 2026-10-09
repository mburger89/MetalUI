// CoreText probe: where does kCTKernAttributeName / kCTTrackingAttributeName
// add its space — per glyph, per character or per grapheme — and what happens
// at a run boundary that keeps the face? Evidence for ruling RT-P items 2–5 in
// docs/superpowers/2026-10-08-rich-text-decisions.md (rich text, lane 1): the
// portable system (HarfBuzz) must place what CoreText places.
//
// HOW TO RUN, from the repository root:
//
//   xcrun swiftc docs/probes/coretext-styled-spacing.swift -o /tmp/spacing-probe && /tmp/spacing-probe
//
// INSTRUMENT: CTLineGetTypographicBounds, CTLineGetTrailingWhitespaceWidth and
// each CTRun's glyphs (id@string index:advance) for attributed strings in the
// suite's own test faces (Tests/Fonts), at 13 points.
// POSITIVE CONTROL: P0 — Noto Sans "AV" is narrower than "A" + "V" (the face
// pair-kerns), and kern 1 on "abc" is plain + 3 (one per glyph = one per
// character there).
// SEPARATING ARMS: S1 — "e" + U+0301 + U+0302 + "x" is 4 UTF-16 units, 3
// glyphs (é composed, a circumflex mark, x) and 2 graphemes: per unit adds 4,
// per glyph 3, per grapheme 2. S2 — Arabic "ب" alone is 2 glyphs, 1 character.
//
// RECORDED 2026-10-08 by rich-text lane 1, macOS 27.0, compiled twice (output
// byte-identical):
//
//     P0 AV 15.587 A+V 16.107 | abc plain 21.528 kern1 24.528
//     S1 e+0301+0302+x plain 13.949 kern1 15.949 track1 15.949 glyphs 171@0:3.679 2667@2:5.393 91@3:8.877 (kern 2)
//     S2 ب plain 12.909 kern1 13.909 glyphs 316@0:-5.330 14@0:13.909 (kern 1)
//     S2b بالعالم plain 31.902 kern1 38.902 track1 38.902 glyphs 77@6:7.306 111@6:1.000 72@5:4.380 9@4:3.783 111@4:1.000 48@3:6.773 111@3:1.000 72@2:4.380 9@1:3.783 111@1:1.403 316@0:-0.403 19@0:4.497 (kern 1)
//     S3 A|V(kern1) 16.587 A(kern1)|V 16.587 A(kern1)|V(kern2) 18.587 A|V(track1) 16.587 A(track1)|V(track2) 18.587
//     S4 trailing whitespace: ab(track2) 19.288/2.000 ab(kern2) 19.288/0.000 "ab "(track2) 24.668/7.380 "ab " plain 18.668/3.380
//     S5 office kern1 4 glyphs 37.735 | track1 6 glyphs 39.735 | plain 4 glyphs 33.735
//
// Reading: kerning and tracking add their value once per **grapheme** (S1:
// +2 for kern 1 over 3 glyphs and 4 units; S2: +1 for 2 glyphs; a ligature
// once, S5), on the grapheme's last glyph in the run's glyph order (S1: on the mark 2667, not on é; S2:
// on 14, not 316). Joined Arabic gets tatweel (kashida, glyph 111) glyphs
// inserted to carry the space (S2b) — the width is still plain + 7 × 1 for 7
// characters. A boundary where only kerning or tracking changes keeps the
// face's pair kerning (S3: AV's 15.587 + the added space, never A + V's
// 16.107). A tracked line's last glyph's tracking counts as trailing
// whitespace; kerning does not (S4). Tracking breaks ligatures, kerning keeps
// them (S5).
import CoreText
import Foundation

let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Tests/Fonts")

func face(_ file: String) -> CTFont {
    let data = try! Data(contentsOf: fonts.appendingPathComponent(file))
    let descriptor = (CTFontManagerCreateFontDescriptorsFromData(data as CFData) as! [CTFontDescriptor])[0]
    return CTFontCreateWithFontDescriptor(descriptor, 13, nil)
}
let noto = face("NotoSans-Regular.ttf"), arabic = face("NotoSansArabic-Regular.ttf")
let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
let kernKey = NSAttributedString.Key(kCTKernAttributeName as String)
let trackKey = NSAttributedString.Key(kCTTrackingAttributeName as String)

/// One run of an attributed string: its text, face, kern and tracking (0 is
/// "attribute absent", RT-O item 7).
struct Piece { var text: String; var font = noto; var kern = 0.0; var track = 0.0 }

func line(_ pieces: [Piece]) -> CTLine {
    let string = NSMutableAttributedString()
    for piece in pieces {
        var attributes: [NSAttributedString.Key: Any] = [fontKey: piece.font]
        if piece.kern != 0 { attributes[kernKey] = piece.kern }
        if piece.track != 0 { attributes[trackKey] = piece.track }
        string.append(NSAttributedString(string: piece.text, attributes: attributes))
    }
    return CTLineCreateWithAttributedString(string)
}
func width(_ pieces: [Piece]) -> String { String(format: "%.3f", CTLineGetTypographicBounds(line(pieces), nil, nil, nil)) }
func trailing(_ pieces: [Piece]) -> String {
    let l = line(pieces)
    return String(format: "%.3f/%.3f", CTLineGetTypographicBounds(l, nil, nil, nil), CTLineGetTrailingWhitespaceWidth(l))
}
func glyphs(_ pieces: [Piece]) -> String {
    var out: [String] = []
    for run in CTLineGetGlyphRuns(line(pieces)) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var ids = [CGGlyph](repeating: 0, count: count), advances = [CGSize](repeating: .zero, count: count)
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetGlyphs(run, CFRange(), &ids)
        CTRunGetAdvances(run, CFRange(), &advances)
        CTRunGetStringIndices(run, CFRange(), &indices)
        for index in 0..<count { out.append("\(ids[index])@\(indices[index]):" + String(format: "%.3f", advances[index].width)) }
    }
    return out.joined(separator: " ")
}
func glyphCount(_ pieces: [Piece]) -> Int {
    (CTLineGetGlyphRuns(line(pieces)) as! [CTRun]).reduce(0) { $0 + CTRunGetGlyphCount($1) }
}

print("P0 AV \(width([Piece(text: "AV")])) A+V \(String(format: "%.3f", Double(width([Piece(text: "A")]))! + Double(width([Piece(text: "V")]))!)) | abc plain \(width([Piece(text: "abc")])) kern1 \(width([Piece(text: "abc", kern: 1)]))")
let marks = "e\u{301}\u{302}x"
print("S1 e+0301+0302+x plain \(width([Piece(text: marks)])) kern1 \(width([Piece(text: marks, kern: 1)])) track1 \(width([Piece(text: marks, track: 1)])) glyphs \(glyphs([Piece(text: marks, kern: 2)])) (kern 2)")
print("S2 ب plain \(width([Piece(text: "ب", font: arabic)])) kern1 \(width([Piece(text: "ب", font: arabic, kern: 1)])) glyphs \(glyphs([Piece(text: "ب", font: arabic, kern: 1)])) (kern 1)")
let hello = "بالعالم"
print("S2b \(hello) plain \(width([Piece(text: hello, font: arabic)])) kern1 \(width([Piece(text: hello, font: arabic, kern: 1)])) track1 \(width([Piece(text: hello, font: arabic, track: 1)])) glyphs \(glyphs([Piece(text: hello, font: arabic, kern: 1)])) (kern 1)")
print("S3 A|V(kern1) \(width([Piece(text: "A"), Piece(text: "V", kern: 1)])) A(kern1)|V \(width([Piece(text: "A", kern: 1), Piece(text: "V")])) A(kern1)|V(kern2) \(width([Piece(text: "A", kern: 1), Piece(text: "V", kern: 2)])) A|V(track1) \(width([Piece(text: "A"), Piece(text: "V", track: 1)])) A(track1)|V(track2) \(width([Piece(text: "A", track: 1), Piece(text: "V", track: 2)]))")
print("S4 trailing whitespace: ab(track2) \(trailing([Piece(text: "ab", track: 2)])) ab(kern2) \(trailing([Piece(text: "ab", kern: 2)])) \"ab \"(track2) \(trailing([Piece(text: "ab ", track: 2)])) \"ab \" plain \(trailing([Piece(text: "ab ")]))")
print("S5 office kern1 \(glyphCount([Piece(text: "office", kern: 1)])) glyphs \(width([Piece(text: "office", kern: 1)])) | track1 \(glyphCount([Piece(text: "office", track: 1)])) glyphs \(width([Piece(text: "office", track: 1)])) | plain \(glyphCount([Piece(text: "office")])) glyphs \(width([Piece(text: "office")]))")
