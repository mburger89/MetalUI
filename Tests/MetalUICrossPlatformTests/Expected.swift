// Recorded on macOS (arm64, Swift 6.4) by
// `METALUI_CROSSPLATFORM_RECORD=1 swift test --filter recordDemoFrames`.
// Do not re-record from a platform where the assertion fails.
let expectedDemoFrames: [(Float, DemoFrame)] = [
    (1.0, DemoFrame(rects: 518, glyphs: 15710, runs: 1008, primitives: 0xe35ec9f9db1a34c5, atlas: 0x556151fc7c4451f1)),
    (2.0, DemoFrame(rects: 518, glyphs: 15710, runs: 1008, primitives: 0xd48286cbf9d0ff9b, atlas: 0x2b84ea9c1486803f)),
]
