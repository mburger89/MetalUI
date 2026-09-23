// Recorded on macOS (arm64, libunibreak 8.0, HarfBuzz 14.5.0) by running
// `METALUI_PORTABLE_RECORD=1 swift test` in this package and pasting the
// printed values; see LineBreakingDeterminismTests. Do not re-record from a
// platform where the assertions fail — a difference is the finding.

let expectedBreakCount = 82
let expectedBreakChecksum: UInt64 = 0xa7f07b783fee89ad
let expectedWraps: [PinnedWrap] = [
    PinnedWrap(lines: 6, checksum: 0x2fdd31a422e7e087),  // NotoSans 13pt w=60, the pangram
    PinnedWrap(lines: 29, checksum: 0x425035722d057f3a),  // NotoSans 11pt w=7.25, "Affix…" (grapheme breaks)
    PinnedWrap(lines: 7, checksum: 0x57aac1320ecb0eae),  // SourceSans 17pt w=90, tabs + a long word
    PinnedWrap(lines: 4, checksum: 0x9943522b4f5af8cf),  // SourceSans 26pt w=nil, LF / CRLF / U+2028
]

// LB-K: line metrics and paragraphs through `emitLines`; see
// LineEmissionDeterminismTests. Recorded the same way.
let expectedMetricsChecksum: UInt64 = 0x1f61c39b5230b14c
let expectedParagraphs: [PinnedEmit] = [
    PinnedEmit(glyphs: 56, rects: 0x6ffa6ba88c7a9518, advance: 0x4052000000000000, dirty: [0, 0, 501, 53], coverage: 0xed33b8e5a821e956),  // NotoSans 13pt ×2 w=120, pangram + LF + soft hyphens
    PinnedEmit(glyphs: 35, rects: 0x123f6196ee28d743, advance: 0x4061400000000000, dirty: [0, 0, 272, 16], coverage: 0x0fc44934a26083b4),  // SourceSans 17pt ×1 w=90, tabs + U+2028
]

// Roadmap item 3: runs and content widths; see ContentSizeDeterminismTests.
let expectedContentChecksum: UInt64 = 0xd7c257bb6f02bed0
