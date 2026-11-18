# 379 - Terminal accessibility and the demo (`TRM-BH`, `TRM-BI`)

Branch `feat/terminal-a11y-demo` on master 0327155d. Class M, no divergence (labels untouched). Phase 5.6 of the terminal plan. Alloy's answer 6 bound it: v1 accessibility is the visible rows' text only.

**Accessibility (`TRM-BH`).** `TerminalView` publishes one read-only `.textArea` node while a client is present: label `accessibilityLabel` (new parameter after `cursorStyle`, default "Terminal"), value the viewport's rows with trailing blanks trimmed, joined by newlines (one line per row). The cursor is not published: the node model has no selection or insertion point. **Output stays free:** the node is declared in the surface element's `prepaint` (`PrepaintPass.terminalDeclareAccessibility`, `package`), which records the node and a live value closure (`Frame.liveAccessibilityValues`); `Window` merges the closures into `WindowAccessibility` and re-reads them after every surface-only frame (`refreshLiveValues`), publishing a changed value through the existing tree channel. No build, no element request and no tree build for output; with no client one `Bool` read in the element and a `guard` in the window.

**Demo (`TRM-BI`).** `METALUI_TERMINAL_DEMO=1 swift run MetalUIDemo` (macOS): a `TerminalView` over `$SHELL` (else /bin/sh), the window titled by the program's title. The session is `TerminalDemoSession` in the new `package`-only target `MetalUITerminalDemo`, built from the public `PseudoTerminal`, `TerminalEmulator` and `TerminalSnapshotSource` as Alloy builds its host; the smoke tests run the same class. Not on the SDL demo (the portable demo content stays free of the terminal products).

**Human checks.** `TRM17`..`TRM21` (vim and less, htop, IME, VoiceOver, the demo window). The SDL keys lane took `TRM16`.

**Tests.** `TerminalAccessibilityTests` (7) and `TerminalDemoSmokeTests` (4); mutations in each test's header.
