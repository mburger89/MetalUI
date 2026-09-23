// Recorded on macOS (arm64, HarfBuzz 14.5.0) by running
// `METALUI_PORTABLE_RECORD=1 swift test` in this package and pasting the
// printed table; see HarfBuzzDeterminismTests.swift. Rows are in `corpus`
// order. `advance` and the position checksum are in DESIGN UNITS, so the
// numbers do not depend on a point size; the end-to-end raster is at 13 pt,
// subpixel variant 0, scale 1.
//
// Do not re-record from a platform where the assertions fail — a difference
// between platforms is the finding.

let expectedRuns: [PinnedRun] = [
    PinnedRun(ids: [55, 75, 72, 3, 84, 88, 76, 70, 78, 3, 69, 85, 82, 90, 81, 3, 73, 82, 91, 3, 77, 88, 80, 83, 86, 3, 82, 89, 72, 85, 3, 87, 75, 72, 3, 79, 68, 93, 92, 3, 71, 82, 74], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42], isRightToLeft: false, advance: 20930, positions: 0x7ef761f1347cf8bd),  // NotoSans-Regular.ttf plain
    PinnedRun(ids: [36, 57], clusters: [0, 1], isRightToLeft: false, advance: 1199, positions: 0x5c3c1ef58c24d89a),  // NotoSans-Regular.ttf kern AV
    PinnedRun(ids: [55, 82], clusters: [0, 1], isRightToLeft: false, advance: 1091, positions: 0xa4a4535fea13e4df),  // NotoSans-Regular.ttf kern To
    PinnedRun(ids: [55, 92], clusters: [0, 1], isRightToLeft: false, advance: 1046, positions: 0xaeb77a96d9374cfe),  // NotoSans-Regular.ttf kern Ty
    PinnedRun(ids: [47, 55], clusters: [0, 1], isRightToLeft: false, advance: 1060, positions: 0xc06b2206c6a461d8),  // NotoSans-Regular.ttf kern LT
    PinnedRun(ids: [1654], clusters: [0], isRightToLeft: false, advance: 602, positions: 0x913e3c6a75d6e3b5),  // NotoSans-Regular.ttf liga fi
    PinnedRun(ids: [1655], clusters: [0], isRightToLeft: false, advance: 602, positions: 0x913e3c6a75d6e3b5),  // NotoSans-Regular.ttf liga fl
    PinnedRun(ids: [1656], clusters: [0], isRightToLeft: false, advance: 946, positions: 0xd72b0cff101aad92),  // NotoSans-Regular.ttf liga ffi
    PinnedRun(ids: [171], clusters: [0], isRightToLeft: false, advance: 564, positions: 0x187bf7bd83ec86db),  // NotoSans-Regular.ttf mark e+acute
    PinnedRun(ids: [166], clusters: [0], isRightToLeft: false, advance: 561, positions: 0x8d0b21ca7c05c08a),  // NotoSans-Regular.ttf mark a+diaeresis
    PinnedRun(ids: [179], clusters: [0], isRightToLeft: false, advance: 618, positions: 0xc19a26e6e1e25785),  // NotoSans-Regular.ttf mark n+tilde
    PinnedRun(ids: [19, 20, 21, 22, 23, 24, 25, 26, 27, 28], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], isRightToLeft: false, advance: 5720, positions: 0xd3c753db6451b955),  // NotoSans-Regular.ttf digits
    PinnedRun(ids: [17, 15, 30, 29, 4, 34, 16, 11, 12, 10, 5], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], isRightToLeft: false, advance: 3330, positions: 0xbaf8e55fdd90fbb1),  // NotoSans-Regular.ttf punctuation
    PinnedRun(ids: [21, 35, 32, 1, 44, 48, 36, 30, 38, 1, 29, 45, 42, 50, 41, 1, 33, 42, 51, 1, 37, 48, 40, 43, 46, 1, 42, 49, 32, 45, 1, 47, 35, 32, 1, 39, 28, 53, 52, 1, 31, 42, 34], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42], isRightToLeft: false, advance: 18483, positions: 0x585af12a14c2a025),  // SourceSans3-Regular.otf plain
    PinnedRun(ids: [2, 23], clusters: [0, 1], isRightToLeft: false, advance: 1045, positions: 0xe058fe930c27c478),  // SourceSans3-Regular.otf kern AV
    PinnedRun(ids: [21, 42], clusters: [0, 1], isRightToLeft: false, advance: 1012, positions: 0xd406ad68edf81d70),  // SourceSans3-Regular.otf kern To
    PinnedRun(ids: [21, 52], clusters: [0, 1], isRightToLeft: false, advance: 970, positions: 0xfee58d00e79da819),  // SourceSans3-Regular.otf kern Ty
    PinnedRun(ids: [13, 21], clusters: [0, 1], isRightToLeft: false, advance: 902, positions: 0xef5308937a0aac3e),  // SourceSans3-Regular.otf kern LT
    PinnedRun(ids: [33, 36], clusters: [0, 1], isRightToLeft: false, advance: 538, positions: 0xcc1574b0095ffbf0),  // SourceSans3-Regular.otf liga fi
    PinnedRun(ids: [33, 39], clusters: [0, 1], isRightToLeft: false, advance: 547, positions: 0x930438b8b51dd639),  // SourceSans3-Regular.otf liga fl
    PinnedRun(ids: [687, 36], clusters: [0, 2], isRightToLeft: false, advance: 823, positions: 0x150a01b305727f2c),  // SourceSans3-Regular.otf liga ffi
    PinnedRun(ids: [371], clusters: [0], isRightToLeft: false, advance: 496, positions: 0xb4e9df194fc994da),  // SourceSans3-Regular.otf mark e+acute
    PinnedRun(ids: [328], clusters: [0], isRightToLeft: false, advance: 504, positions: 0x2cda8d59e87256e2),  // SourceSans3-Regular.otf mark a+diaeresis
    PinnedRun(ids: [452], clusters: [0], isRightToLeft: false, advance: 547, positions: 0xb3910824b2047c10),  // SourceSans3-Regular.otf mark n+tilde
    PinnedRun(ids: [1333, 1334, 1335, 1336, 1337, 1338, 1339, 1340, 1341, 1342], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], isRightToLeft: false, advance: 4970, positions: 0x645347ca678e29c9),  // SourceSans3-Regular.otf digits
    PinnedRun(ids: [1387, 1388, 1390, 1389, 1392, 1394, 1415, 1442, 1443, 1396, 1397], clusters: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], isRightToLeft: false, advance: 3302, positions: 0x93e870e9acd77c2d),  // SourceSans3-Regular.otf punctuation
    PinnedRun(ids: [9, 316, 16, 27, 31, 79], clusters: [4, 3, 3, 2, 1, 0], isRightToLeft: true, advance: 2104, positions: 0x09b6dcdf0319c6ad),  // NotoSansArabic-Regular.ttf arabic word
    PinnedRun(ids: [77, 72, 9, 48, 72, 9, 316, 19, 3, 9, 316, 16, 27, 31, 79], clusters: [12, 11, 10, 9, 8, 7, 6, 6, 5, 4, 3, 3, 2, 1, 0], isRightToLeft: true, advance: 4818, positions: 0xcf7143613dee8ba6),  // NotoSansArabic-Regular.ttf arabic sentence
    PinnedRun(ids: [10, 73], clusters: [1, 0], isRightToLeft: true, advance: 582, positions: 0xa1692dba2d5d6852),  // NotoSansArabic-Regular.ttf arabic lam-alef
    PinnedRun(ids: [9, 374, 316, 16, 370, 27, 378, 31, 370, 79], clusters: [8, 6, 6, 6, 4, 4, 2, 2, 0, 0], isRightToLeft: true, advance: 2104, positions: 0xc876ef3d6cdcd57c),  // NotoSansArabic-Regular.ttf arabic harakat
    PinnedRun(ids: [137, 136, 135, 134, 133, 132, 131, 130, 129, 128], clusters: [9, 8, 7, 6, 5, 4, 3, 2, 1, 0], isRightToLeft: true, advance: 5720, positions: 0xd3c753db6451b955),  // NotoSansArabic-Regular.ttf arabic-indic digits
]
let expectedEndToEnd = PinnedRaster(glyphs: 35, coverageBytes: 2917, checksum: 0xa1d6b34dfbba93a7)
