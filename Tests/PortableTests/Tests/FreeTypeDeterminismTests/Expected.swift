// Recorded on macOS (arm64, Swift 6.4) with `METALUI_PORTABLE_RECORD=1 swift test`
// on 2026-09-22; one row per `grid` case, in `grid`'s order. Never re-pin
// from a platform where the test fails — that difference is the finding (FT-J).
let expected: [Pinned] = [
    Pinned(glyph: 82, width: 10, height: 11, left: -1, top: 9, checksum: 0x96749c83f2d12e1b),  // NotoSans-Regular.ttf 'o' 13pt v0 @1x
    Pinned(glyph: 82, width: 16, height: 18, left: 0, top: 16, checksum: 0x9f20264315e21c9b),  // NotoSans-Regular.ttf 'o' 13pt v0 @2x
    Pinned(glyph: 82, width: 9, height: 11, left: 0, top: 9, checksum: 0xd032b3c8ade9dbf4),  // NotoSans-Regular.ttf 'o' 13pt v3 @1x
    Pinned(glyph: 82, width: 16, height: 18, left: 1, top: 16, checksum: 0x34371e18d47fcd8c),  // NotoSans-Regular.ttf 'o' 13pt v3 @2x
    Pinned(glyph: 82, width: 16, height: 18, left: 0, top: 16, checksum: 0x9f20264315e21c9b),  // NotoSans-Regular.ttf 'o' 26pt v0 @1x
    Pinned(glyph: 82, width: 29, height: 32, left: 1, top: 30, checksum: 0xa3ea7afdb98ca371),  // NotoSans-Regular.ttf 'o' 26pt v0 @2x
    Pinned(glyph: 82, width: 16, height: 18, left: 1, top: 16, checksum: 0x34371e18d47fcd8c),  // NotoSans-Regular.ttf 'o' 26pt v3 @1x
    Pinned(glyph: 82, width: 29, height: 32, left: 2, top: 30, checksum: 0x33779f878f707698),  // NotoSans-Regular.ttf 'o' 26pt v3 @2x
    Pinned(glyph: 74, width: 9, height: 14, left: -1, top: 9, checksum: 0x614ffc07ea5cb561),  // NotoSans-Regular.ttf 'g' 13pt v0 @1x
    Pinned(glyph: 74, width: 15, height: 24, left: 0, top: 16, checksum: 0x36e1d6c030150633),  // NotoSans-Regular.ttf 'g' 13pt v0 @2x
    Pinned(glyph: 74, width: 9, height: 14, left: 0, top: 9, checksum: 0xc5a086f4fce2d4f3),  // NotoSans-Regular.ttf 'g' 13pt v3 @1x
    Pinned(glyph: 74, width: 15, height: 24, left: 1, top: 16, checksum: 0x189591ffa46d5e76),  // NotoSans-Regular.ttf 'g' 13pt v3 @2x
    Pinned(glyph: 74, width: 15, height: 24, left: 0, top: 16, checksum: 0x36e1d6c030150633),  // NotoSans-Regular.ttf 'g' 26pt v0 @1x
    Pinned(glyph: 74, width: 28, height: 44, left: 1, top: 30, checksum: 0x9f9ed4a21e85fddc),  // NotoSans-Regular.ttf 'g' 26pt v0 @2x
    Pinned(glyph: 74, width: 15, height: 24, left: 1, top: 16, checksum: 0x189591ffa46d5e76),  // NotoSans-Regular.ttf 'g' 26pt v3 @1x
    Pinned(glyph: 74, width: 28, height: 44, left: 2, top: 30, checksum: 0xdc5fe90b04a9e0fc),  // NotoSans-Regular.ttf 'g' 26pt v3 @2x
    Pinned(glyph: 58, width: 14, height: 12, left: -1, top: 11, checksum: 0x7d7ef7aa8a2cf8ad),  // NotoSans-Regular.ttf 'W' 13pt v0 @1x
    Pinned(glyph: 58, width: 26, height: 21, left: -1, top: 20, checksum: 0xdd53cbd0c3505e82),  // NotoSans-Regular.ttf 'W' 13pt v0 @2x
    Pinned(glyph: 58, width: 15, height: 12, left: -1, top: 11, checksum: 0x2dc533afce100fb4),  // NotoSans-Regular.ttf 'W' 13pt v3 @1x
    Pinned(glyph: 58, width: 26, height: 21, left: 0, top: 20, checksum: 0x26857bd1e80faf3a),  // NotoSans-Regular.ttf 'W' 13pt v3 @2x
    Pinned(glyph: 58, width: 26, height: 21, left: -1, top: 20, checksum: 0xdd53cbd0c3505e82),  // NotoSans-Regular.ttf 'W' 26pt v0 @1x
    Pinned(glyph: 58, width: 50, height: 40, left: -1, top: 39, checksum: 0xe3cfb5b1420465c5),  // NotoSans-Regular.ttf 'W' 26pt v0 @2x
    Pinned(glyph: 58, width: 26, height: 21, left: 0, top: 20, checksum: 0x26857bd1e80faf3a),  // NotoSans-Regular.ttf 'W' 26pt v3 @1x
    Pinned(glyph: 58, width: 50, height: 40, left: 0, top: 39, checksum: 0x0a83f8c93c7ff445),  // NotoSans-Regular.ttf 'W' 26pt v3 @2x
    Pinned(glyph: 77, width: 6, height: 16, left: -2, top: 11, checksum: 0xbedad5d74cf9a553),  // NotoSans-Regular.ttf 'j' 13pt v0 @1x
    Pinned(glyph: 77, width: 9, height: 29, left: -3, top: 21, checksum: 0x9d17c3292ee30cab),  // NotoSans-Regular.ttf 'j' 13pt v0 @2x
    Pinned(glyph: 77, width: 6, height: 16, left: -1, top: 11, checksum: 0x7bd6a6ccdde47419),  // NotoSans-Regular.ttf 'j' 13pt v3 @1x
    Pinned(glyph: 77, width: 9, height: 29, left: -2, top: 21, checksum: 0xd17759fd723c7365),  // NotoSans-Regular.ttf 'j' 13pt v3 @2x
    Pinned(glyph: 77, width: 9, height: 29, left: -3, top: 21, checksum: 0x9d17c3292ee30cab),  // NotoSans-Regular.ttf 'j' 26pt v0 @1x
    Pinned(glyph: 77, width: 15, height: 54, left: -4, top: 40, checksum: 0xc3b2e5c97b561754),  // NotoSans-Regular.ttf 'j' 26pt v0 @2x
    Pinned(glyph: 77, width: 9, height: 29, left: -2, top: 21, checksum: 0xd17759fd723c7365),  // NotoSans-Regular.ttf 'j' 26pt v3 @1x
    Pinned(glyph: 77, width: 16, height: 54, left: -4, top: 40, checksum: 0x6929cd0474091553),  // NotoSans-Regular.ttf 'j' 26pt v3 @2x
    Pinned(glyph: 17, width: 5, height: 5, left: -1, top: 3, checksum: 0x37db654ae94673bc),  // NotoSans-Regular.ttf '.' 13pt v0 @1x
    Pinned(glyph: 17, width: 7, height: 7, left: 0, top: 5, checksum: 0xaf6c3108146e4029),  // NotoSans-Regular.ttf '.' 13pt v0 @2x
    Pinned(glyph: 17, width: 5, height: 5, left: 0, top: 3, checksum: 0x8e3c29a5f928c975),  // NotoSans-Regular.ttf '.' 13pt v3 @1x
    Pinned(glyph: 17, width: 6, height: 7, left: 1, top: 5, checksum: 0x1c9f553d2be6608f),  // NotoSans-Regular.ttf '.' 13pt v3 @2x
    Pinned(glyph: 17, width: 7, height: 7, left: 0, top: 5, checksum: 0xaf6c3108146e4029),  // NotoSans-Regular.ttf '.' 26pt v0 @1x
    Pinned(glyph: 17, width: 10, height: 10, left: 2, top: 8, checksum: 0xedf37b781b14552f),  // NotoSans-Regular.ttf '.' 26pt v0 @2x
    Pinned(glyph: 17, width: 6, height: 7, left: 1, top: 5, checksum: 0x1c9f553d2be6608f),  // NotoSans-Regular.ttf '.' 26pt v3 @1x
    Pinned(glyph: 17, width: 9, height: 10, left: 3, top: 8, checksum: 0x987d31cecc95cb07),  // NotoSans-Regular.ttf '.' 26pt v3 @2x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 13pt v0 @1x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 13pt v0 @2x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 13pt v3 @1x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 13pt v3 @2x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 26pt v0 @1x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 26pt v0 @2x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 26pt v3 @1x
    Pinned(glyph: 3, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // NotoSans-Regular.ttf ' ' 26pt v3 @2x
    Pinned(glyph: 42, width: 9, height: 10, left: -1, top: 8, checksum: 0x36ae9ec874bbe977),  // SourceSans3-Regular.otf 'o' 13pt v0 @1x
    Pinned(glyph: 42, width: 14, height: 16, left: 0, top: 14, checksum: 0x2375809eb6431c9a),  // SourceSans3-Regular.otf 'o' 13pt v0 @2x
    Pinned(glyph: 42, width: 9, height: 10, left: 0, top: 8, checksum: 0x8dee74d1cdd82eeb),  // SourceSans3-Regular.otf 'o' 13pt v3 @1x
    Pinned(glyph: 42, width: 15, height: 16, left: 0, top: 14, checksum: 0x6fbeedcf6a671768),  // SourceSans3-Regular.otf 'o' 13pt v3 @2x
    Pinned(glyph: 42, width: 14, height: 16, left: 0, top: 14, checksum: 0x2375809eb6431c9a),  // SourceSans3-Regular.otf 'o' 26pt v0 @1x
    Pinned(glyph: 42, width: 26, height: 29, left: 1, top: 27, checksum: 0x74f7ba7d30f7a12a),  // SourceSans3-Regular.otf 'o' 26pt v0 @2x
    Pinned(glyph: 42, width: 15, height: 16, left: 0, top: 14, checksum: 0x6fbeedcf6a671768),  // SourceSans3-Regular.otf 'o' 26pt v3 @1x
    Pinned(glyph: 42, width: 26, height: 29, left: 2, top: 27, checksum: 0xba249f9a1041189f),  // SourceSans3-Regular.otf 'o' 26pt v3 @2x
    Pinned(glyph: 34, width: 9, height: 12, left: -1, top: 8, checksum: 0x8641406ce90005da),  // SourceSans3-Regular.otf 'g' 13pt v0 @1x
    Pinned(glyph: 34, width: 14, height: 21, left: 0, top: 14, checksum: 0xa66dac54d070e01b),  // SourceSans3-Regular.otf 'g' 13pt v0 @2x
    Pinned(glyph: 34, width: 9, height: 12, left: 0, top: 8, checksum: 0x061b194df3d7de84),  // SourceSans3-Regular.otf 'g' 13pt v3 @1x
    Pinned(glyph: 34, width: 15, height: 21, left: 0, top: 14, checksum: 0x68d7de981341fe4a),  // SourceSans3-Regular.otf 'g' 13pt v3 @2x
    Pinned(glyph: 34, width: 14, height: 21, left: 0, top: 14, checksum: 0xa66dac54d070e01b),  // SourceSans3-Regular.otf 'g' 26pt v0 @1x
    Pinned(glyph: 34, width: 26, height: 40, left: 1, top: 27, checksum: 0x90a3a402dd53f001),  // SourceSans3-Regular.otf 'g' 26pt v0 @2x
    Pinned(glyph: 34, width: 15, height: 21, left: 0, top: 14, checksum: 0x68d7de981341fe4a),  // SourceSans3-Regular.otf 'g' 26pt v3 @1x
    Pinned(glyph: 34, width: 26, height: 40, left: 2, top: 27, checksum: 0x7d36da907448a9c4),  // SourceSans3-Regular.otf 'g' 26pt v3 @2x
    Pinned(glyph: 24, width: 12, height: 11, left: -1, top: 10, checksum: 0xdcce8085ff54e655),  // SourceSans3-Regular.otf 'W' 13pt v0 @1x
    Pinned(glyph: 24, width: 22, height: 20, left: -1, top: 19, checksum: 0xdb46c0dd4df5a48e),  // SourceSans3-Regular.otf 'W' 13pt v0 @2x
    Pinned(glyph: 24, width: 12, height: 11, left: 0, top: 10, checksum: 0xe9262527a1e298c1),  // SourceSans3-Regular.otf 'W' 13pt v3 @1x
    Pinned(glyph: 24, width: 22, height: 20, left: 0, top: 19, checksum: 0xea76a02d21fc1b42),  // SourceSans3-Regular.otf 'W' 13pt v3 @2x
    Pinned(glyph: 24, width: 22, height: 20, left: -1, top: 19, checksum: 0xdb46c0dd4df5a48e),  // SourceSans3-Regular.otf 'W' 26pt v0 @1x
    Pinned(glyph: 24, width: 41, height: 37, left: 0, top: 36, checksum: 0xeb89a5da0699ae98),  // SourceSans3-Regular.otf 'W' 26pt v0 @2x
    Pinned(glyph: 24, width: 22, height: 20, left: 0, top: 19, checksum: 0xea76a02d21fc1b42),  // SourceSans3-Regular.otf 'W' 26pt v3 @1x
    Pinned(glyph: 24, width: 42, height: 37, left: 0, top: 36, checksum: 0xaa4bdfbb729cf2d2),  // SourceSans3-Regular.otf 'W' 26pt v3 @2x
    Pinned(glyph: 37, width: 6, height: 15, left: -2, top: 11, checksum: 0xc44fabb17ea3260a),  // SourceSans3-Regular.otf 'j' 13pt v0 @1x
    Pinned(glyph: 37, width: 9, height: 27, left: -3, top: 20, checksum: 0x0f03eaac7d53cd03),  // SourceSans3-Regular.otf 'j' 13pt v0 @2x
    Pinned(glyph: 37, width: 6, height: 15, left: -1, top: 11, checksum: 0x0e762e52006756ad),  // SourceSans3-Regular.otf 'j' 13pt v3 @1x
    Pinned(glyph: 37, width: 9, height: 27, left: -2, top: 20, checksum: 0xa1f49ecbf3eab281),  // SourceSans3-Regular.otf 'j' 13pt v3 @2x
    Pinned(glyph: 37, width: 9, height: 27, left: -3, top: 20, checksum: 0x0f03eaac7d53cd03),  // SourceSans3-Regular.otf 'j' 26pt v0 @1x
    Pinned(glyph: 37, width: 15, height: 51, left: -4, top: 38, checksum: 0x08c1f527413c7a5c),  // SourceSans3-Regular.otf 'j' 26pt v0 @2x
    Pinned(glyph: 37, width: 9, height: 27, left: -2, top: 20, checksum: 0xa1f49ecbf3eab281),  // SourceSans3-Regular.otf 'j' 26pt v3 @1x
    Pinned(glyph: 37, width: 15, height: 51, left: -3, top: 38, checksum: 0xc7d94e090efccd8f),  // SourceSans3-Regular.otf 'j' 26pt v3 @2x
    Pinned(glyph: 1387, width: 5, height: 5, left: -1, top: 3, checksum: 0x5ae28d0f9185cd6b),  // SourceSans3-Regular.otf '.' 13pt v0 @1x
    Pinned(glyph: 1387, width: 6, height: 6, left: 0, top: 4, checksum: 0x314afc8534a1377f),  // SourceSans3-Regular.otf '.' 13pt v0 @2x
    Pinned(glyph: 1387, width: 5, height: 5, left: 0, top: 3, checksum: 0x5d6b890f490f46d8),  // SourceSans3-Regular.otf '.' 13pt v3 @1x
    Pinned(glyph: 1387, width: 6, height: 6, left: 1, top: 4, checksum: 0x4754dc2f8e4b647c),  // SourceSans3-Regular.otf '.' 13pt v3 @2x
    Pinned(glyph: 1387, width: 6, height: 6, left: 0, top: 4, checksum: 0x314afc8534a1377f),  // SourceSans3-Regular.otf '.' 26pt v0 @1x
    Pinned(glyph: 1387, width: 9, height: 9, left: 2, top: 7, checksum: 0xf0ff1309cf9400fd),  // SourceSans3-Regular.otf '.' 26pt v0 @2x
    Pinned(glyph: 1387, width: 6, height: 6, left: 1, top: 4, checksum: 0x4754dc2f8e4b647c),  // SourceSans3-Regular.otf '.' 26pt v3 @1x
    Pinned(glyph: 1387, width: 9, height: 9, left: 3, top: 7, checksum: 0x3dfe2956c827d586),  // SourceSans3-Regular.otf '.' 26pt v3 @2x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 13pt v0 @1x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 13pt v0 @2x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 13pt v3 @1x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 13pt v3 @2x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 26pt v0 @1x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 26pt v0 @2x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 26pt v3 @1x
    Pinned(glyph: 1, width: 0, height: 0, left: 0, top: 0, checksum: 0xcbf29ce484222325),  // SourceSans3-Regular.otf ' ' 26pt v3 @2x
]
