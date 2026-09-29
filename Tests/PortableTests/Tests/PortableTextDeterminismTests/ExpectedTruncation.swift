// Recorded on macOS (arm64, HarfBuzz 14.5.0, FreeType 2.14.3) by running
// `METALUI_PORTABLE_RECORD=1 swift test` in this package and pasting the
// printed table; see TruncationDeterminismTests.swift. Rows are in
// `truncationCorpus` order. Do not re-record from a platform where the
// assertions fail — a difference between platforms is the finding.

let expectedTruncations: [PinnedEmit] = [
    PinnedEmit(glyphs: 20, rects: 0xe8f95433b10dab5d, advance: 0x4042000000000000, dirty: [0, 0, 160, 14], coverage: 0xad8c1d6052e0704a),  // 13.0pt ×1.0 w=100.0 maxLines=2 tail leading "Alpha beta gamma delta epsilon zeta eta theta"
    PinnedEmit(glyphs: 22, rects: 0x3d00e05bc323b1af, advance: 0x4042000000000000, dirty: [0, 0, 135, 14], coverage: 0xb25518715a43bcb7),  // 13.0pt ×1.0 w=100.0 maxLines=2 head leading "Alpha beta gamma delta epsilon zeta eta theta"
    PinnedEmit(glyphs: 20, rects: 0x8794db9cbe9efe8d, advance: 0x4042000000000000, dirty: [0, 0, 166, 14], coverage: 0x5353726480312c6b),  // 13.0pt ×1.0 w=100.0 maxLines=2 middle leading "Alpha beta gamma delta epsilon zeta eta theta"
    PinnedEmit(glyphs: 19, rects: 0xf7aaea8b9279d5aa, advance: 0x4045000000000000, dirty: [0, 0, 170, 18], coverage: 0x9c90967c1644ed36),  // 15.0pt ×1.0 w=100.0 maxLines=2 tail center "The quick brown fox jumps over the lazy dog, twice over."
    PinnedEmit(glyphs: 27, rects: 0xce58d4dfaeccf85a, advance: 0x404f800000000000, dirty: [0, 0, 408, 33], coverage: 0xb6fa51ce62e43fa4),  // 15.0pt ×2.0 w=100.0 maxLines=3 middle trailing "The quick brown fox jumps over the lazy dog, twice over."
    PinnedEmit(glyphs: 9, rects: 0x4010643f19e0197c, advance: 0x4042000000000000, dirty: [0, 0, 124, 23], coverage: 0x7f9a3e79baa91043),  // 13.0pt ×2.0 w=100.0 maxLines=2 tail center "Ready\nSet\nGo"
]
