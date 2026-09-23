// Recorded on macOS (arm64, Swift 6.4) by
// `METALUI_CROSSPLATFORM_RECORD=1 swift test --filter recordDemoFrames`.
// Do not re-record from a platform where the assertion fails.
//
// Re-recorded 2026-09-23 at the merge of plan task 7 stage 6b (the root
// switch: `Frame.defaultLayoutAuthority` is `.proposal`) with `master`
// `654a503`. The same frame under `layoutAuthority: .legacy` still reads the
// values recorded before the merge (scale 1 `0xe35ec9f9db1a34c5` /
// `0x556151fc7c4451f1`, scale 2 `0xd48286cbf9d0ff9b` / `0x2b84ea9c1486803f`),
// so the root switch is the only input that moved; every paired rect and glyph
// delta is one of stage 6b's named causes (record §41 §20). Linux and Windows
// CI re-confirm these on push.
let expectedDemoFrames: [(Float, DemoFrame)] = [
    (1.0, DemoFrame(rects: 518, glyphs: 15710, runs: 1008, primitives: 0x93022181f7ac03d7, atlas: 0x583ae5dca644fe93)),
    (2.0, DemoFrame(rects: 518, glyphs: 15710, runs: 1008, primitives: 0x7000ee7e5d7a4bb9, atlas: 0xd5a9cf3e477fb669)),
]
