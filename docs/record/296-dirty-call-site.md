# 296 - The dirty tag names its call site (`FP-R`)

Branch `feat/trace-dirty-callsite` from master `24176012`. Class M, no divergence label. Ruling `FP-R` in
`docs/superpowers/2026-11-07-frame-timing-decisions.md`.

**Why.** Alloy's trace with `METALUI_LATENCY_TRACE_ALL=1` and two static glass controls (record 293): each key is a
frame with `dirty=explicit/7`, a tick `dirty=observation/5`, then about four ticks `dirty=explicit/1`. Glass: 825
`explicit/1` in 1032 non-input frames; no glass: 62 in 269. Typing p50 30 ms against 16 ms. Some untagged
`setNeedsRedraw()` fires once per frame for a few frames after a content change, only with glass. No headless setup
(`TestWindow`, the fake Metal platform, Alloy's UI) reproduced it.

**Change.** `Window.setNeedsRedraw(_:_:)` takes the caller's `#fileID` and `#line` as defaulted arguments; the first
`explicit` dirtying since the previous frame prints as `dirty=explicit@Window.swift:143/1`. Recorded only while a trace
sink exists (a `StaticString` and a number; no string built; nothing stored otherwise). `@State` writes (the state
table's hook) are tagged `state`, the glyph atlas's request `atlas`.

**Step 2, by reading (not provable headlessly).** Ranked suspects for a per-frame `explicit` that appears only with a
backdrop on screen, none confirmed:
1. `Window.onResize` (`Window.swift` ~1033): AppKit's `syncSurfaceGeometry` (`AppKitPlatform.swift:1270`) reports
   geometry from `setFrameSize`, `viewDidChangeBackingProperties`, the `contentLayoutRect` observer and the title-bar
   placement hook; it calls `setNeedsRedraw()` each time. A real-window layer or backdrop resizing each frame would do
   this and no headless platform would.
2. `Window.swift:1881`, `if resizeCount != resizesBeforeBuild { setNeedsRedraw() }`, the same source seen from a frame.
3. `reconcileWindowBackdrop` (`ContainerBackground.swift:102`/`109`): asks again when the fallback colour changes
   or the platform's answer to `setWindowBackdrop` changes; only for a window backdrop, not glass controls.
4. `scrollRequests.onEnqueue` (`Window.swift:1027`): a `CodeView` caret-follow request made outside the input handler.
5. The glyph atlas (`Window.swift:143`) is now tagged `atlas`, so it can be ruled out by the next trace.
The next trace names the site; no further guessing is needed.
