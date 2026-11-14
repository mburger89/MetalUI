# 300 - The title-bar style known at open is built into the NSWindow (`AS-T`)

Branch `perf/window-open-style` from master `c3b22006`. Class M, no divergence label. Ruling `AS-T` in
`docs/superpowers/2026-10-08-app-shell-decisions.md`.

**Why.** Alloy's launch went about 156 to 171 ms (5 Time Profiler launches each). Two MetalUI shares:
`App.openWindow` +10.8 ms and `EnvironmentScope.reportingPreference` +7.4 ms in the first frame.

**1. openWindow.** `Window.windowStyle`, `applyWindowStyle`, `AppKitWindow.setTitleBarStyle` ran `setStyleMask:` on an
ordered-in window: `_setFrameCommon:`/`_oldPlaceWindow` 3.5 ms, `NSAnimation _runBlocking` 3.4 ms,
`NSPerformVisuallyAtomicChange` 4.2 ms. Now `Platform.openWindow(title:size:titleBarStyle:)` (defaulted for SDL and the
headless platform) lets `AppKitWindow.init` build the `NSWindow` with `.fullSizeContentView`, a transparent bar and a
hidden title; `setTitleBarStyle` answers `true` at once for the style already shown. The content rect of a hidden
window is the frame of the standard window of that content size, so frame, centring, content size and insets equal the
post-open path (pinned). Runtime changes keep the old path (flags, frame kept, `AS-O` item 1).

**2. reportingPreference.** Not a per-node cost: `reportingPreference` wraps `body`, the layout of the scope's whole
subtree, so its profile time is INCLUSIVE; a root `.windowTitleBarMetrics` (or any scope) puts the entire layout under
a new frame name (0 to 7.4 ms is the tree's layout, moved). Counted with a headless Alloy-shaped tree
(`FirstFramePreferenceTests`): `splitViewDivider` and `contentMargins` scopes add no build and no frame; a
`windowTitleBarMetrics` that changes the title-bar insets adds exactly one frame (2 builds, 2 frames against 1) because
the insets are stamped when the frame is built and the metrics are known only from that build (`AS-R` items 5, 8:
SwiftUI-semantic, the content may read `titleBarInsets`). It is bounded at one frame, not a loop. Not changed: avoiding
it would need read-tracking of the insets (the SDL chrome reads them too) for one retained-replayable frame.

**Numbers.** release build (`METALUI_WINDOW_OPEN_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter windowOpenStyleBench`),
unordered `AppKitWindow`, median of 15: built-in style 4.3 ms, standard then `setTitleBarStyle(.hidden)` 9.7 ms (the
saving of the style change alone is 5.4 ms unordered; on an ordered-in window the profile showed about 10 ms because the
blocking frame animation only runs for a visible window). First frame, headless Alloy-shaped tree: scopes only, 1 build
and 1 frame in both arms; with a changing title-bar metrics report, 2 builds and 2 frames.
