# C14-d measurement probe (`FS-`)

`FinerScopesMeasure.swift.txt` is the throw-away instrument the design phase ran at `711ab9c4` (2026-10-20). It is a `.txt` so
SwiftPM does not compile it. To re-run: copy it to `Tests/MetalUITestingTests/FinerScopesMeasure.swift` (delete the copy
afterwards), then

    swift test --build-system native --no-parallel --filter finerScopesMeasure           # all scenarios
    FSM_ONLY=listStatic METALUI_TRACE_RETAINED=1 swift test ... --filter finerScopesMeasure   # one scenario, with the miss trace

It prints one `FSM <scenario> graft=<bool> frame <n>:` line per frame and asserts nothing: counts only (`FrameWork`), never time.
The readings are in `docs/superpowers/2026-10-20-finer-scopes-decisions.md` (`FS-A`) and the spec's section 1. The scenarios are
24 `.equatable()` card rows at scale 2 in a 320 x 400 window: `valueChange` (one row's value), `insertFront` (an id inserted first),
`position` (a header above the rows grows 4 pt), `scroll` (a 300 x 150 `ScrollView` of the rows, wheel -30 at its centre),
`listScroll`/`listStatic`/`listValue` (a `List(rowHeight: 22)` of the same cards, each in a `Column`).
