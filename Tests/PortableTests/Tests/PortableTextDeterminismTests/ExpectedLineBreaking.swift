// Recorded on macOS (arm64, libunibreak 8.0, HarfBuzz 14.5.0) by running
// `METALUI_PORTABLE_RECORD=1 swift test` in this package and pasting the
// printed values; see LineBreakingDeterminismTests. Do not re-record from a
// platform where the assertions fail — a difference is the finding.

let expectedBreakCount = 82
let expectedBreakChecksum: UInt64 = 0xa7f07b783fee89ad
let expectedWraps: [PinnedWrap] = [
    PinnedWrap(lines: 6, checksum: 0x2cecdd3fca12ef2b),  // NotoSans 13pt w=60, the pangram
    PinnedWrap(lines: 29, checksum: 0x2c9a63a3f724c111),  // NotoSans 11pt w=7.25, "Affix…" (grapheme breaks)
    PinnedWrap(lines: 7, checksum: 0x21167e009c26f520),  // SourceSans 17pt w=90, tabs + a long word
    PinnedWrap(lines: 4, checksum: 0xecf4275c9a390781),  // SourceSans 26pt w=nil, LF / CRLF / U+2028
]
