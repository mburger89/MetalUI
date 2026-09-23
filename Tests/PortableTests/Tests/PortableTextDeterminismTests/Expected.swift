// Recorded on macOS (arm64, HarfBuzz 14.5.0, FreeType 2.14.3) by running
// `METALUI_PORTABLE_RECORD=1 swift test` in this package and pasting the
// printed table; see PortableTextDeterminismTests.swift. Rows are in `corpus`
// order.
//
// Do not re-record from a platform where the assertions fail — a difference
// between platforms is the finding.

let expectedEmits: [PinnedEmit] = [
    PinnedEmit(glyphs: 7, rects: 0x2c36d18c86a16307, advance: 0x404d2c083126e977, dirty: [0, 0, 65, 14], coverage: 0x53cb7d5873e2d5a5),  // NotoSans-Regular.ttf 13.0pt ×1.0 at (10.0, 20.0) "Hamburg"
    PinnedEmit(glyphs: 36, rects: 0x2ca49143295bbe6c, advance: 0x407685db22d0e560, dirty: [0, 0, 511, 67], coverage: 0x838970e71a05fcbd),  // NotoSans-Regular.ttf 17.0pt ×2.0 at (10.37, 30.0) "The quick brown fox jumps over the lazy dog."
    PinnedEmit(glyphs: 24, rects: 0x1a0c1dde9f53c0e2, advance: 0x40740a872b020c49, dirty: [0, 0, 297, 22], coverage: 0x0688fdee153c519a),  // SourceSans3-Regular.otf 26.0pt ×1.0 at (3.5, 40.0) "Affix the fluffy waffle: AV To Ty"
    PinnedEmit(glyphs: 6, rects: 0xb1a56e686d71704c, advance: 0x4041b72b020c49ba, dirty: [0, 0, 66, 19], coverage: 0x29215d7bb009b97c),  // SourceSans3-Regular.otf 11.0pt ×2.0 at (7.125, 18.0) "in a box"
    PinnedEmit(glyphs: 18, rects: 0x2c19a7eddd816289, advance: 0x4056e2b020c49ba5, dirty: [0, 0, 239, 31], coverage: 0xf523938a0a0eaf49),  // NotoSansArabic-Regular.ttf 19.0pt ×2.0 at (5.25, 30.0) "مَرْحَبًا بالعالم"
]
