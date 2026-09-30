# 63 — Accessibility (plan task 12, part 2)

Branch `feat/accessibility-bridge` from `31d3565` (master, plan task 12 part 1
landed, record §62). Spec `docs/superpowers/specs/2026-09-29-accessibility-design.md`;
rulings `IX-U`…`IX-AE` appended to part 1's decisions doc,
`docs/superpowers/2026-09-29-interaction-decisions.md` (next unused `IX-AF`).
Probes: `docs/probes/swiftui-accessibility-part2.swift` (new) and
`docs/probes/swiftui-controls-and-selection.swift` (re-run, compiled).

**Status: DESIGNED.** Lanes 1–3 not begun. **Task 12's box stays unticked**
until a human runs `docs/verification/voiceover-script.md` (written by lane 3)
and the Record phase re-reads it (`IX-AE`). No agent can run VoiceOver or
claim the validation.

## §1 Design (2026-09-29)

**Baseline re-taken at `31d3565`** in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1837 tests in 3 suites passed after 113.321 seconds`, the
`FR-J no-argument frame: succeeded=true` line present. 113 guards, 0 goldens,
69 live divergences, next label 95. AccessKit 0.23.0 fetched
(`Backends/SDL/scripts/fetch-accesskit.py`, checksum matched) to read
`accesskit.h`.

**Probe.** `swiftui-accessibility-part2.swift` (new; groups `C` controls, `E`
children behaviour, `H` hidden, `T` traits, `M` modal, `N` hint/identifier,
`A` actions, `B` buttons, `G` gestures, `X` truncation, `F` focus, `L` list,
`I` images, `P` proposal containers): run twice with `/usr/bin/swift`,
filtered stdout byte-identical (308 lines), exit 0, filtered stderr empty,
screen **locked** (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`).
Every read is in-process (KVC on `NSHostingView`'s tree after
`AXEnhancedUserInterface`), so the lock blinds nothing but `F4`, recorded as
non-separating. Positive controls C0 (arm 11's `label=vol value=5`), C1 (two
static texts), C2 (AppKit's own `NSButton` publishes no key-equivalent
attribute) all read as expected. Three instrument fixes before the recorded
run, none changing an arm: `L1`'s rows are AppKit `NSOutlineRow`s, not
KVC-compliant for the accessibility keys, so `kv` guards on `responds(to:)`
and rows read through the informal attribute API; `F2`'s two `@FocusState`
writes arrived in either order across runs, so they print sorted; `E14` and
`T3p` were added after the first reading (the `.combine` custom-action rule
and whether removing `.isButton` keeps the press).

`swiftui-controls-and-selection.swift` re-run the same session: the
`/usr/bin/swift` JIT form fails to link on macOS 27 (`Symbols not found:
___isPlatformVersionAtLeast`); compiled with `xcrun swiftc -o` it runs, exit
0, and its LA0–LB3 lines are byte-identical to its header.

**The audit** (spec §2, `IX-U`): 44 rows — part 1's rows 27–37 split where one
row named several concepts, plus the brief's own items and every carried
accessibility item. Built: `accessibilityElement(children:)`,
`accessibilityHidden`, hint, identifier, eight traits, modal isolation,
declared and named actions, settable selection on AppKit, the proposal path's
emission, a labelled `Image`, both bridges' new fields. Pinned as SwiftUI's:
gestures publish no press, button role/shortcut/style publish nothing,
truncated text publishes its whole string, focus/`@FocusState` interplay.
Divergences: 28 and 83 retire, 95 added, 27/32/33 amended, 82 kept for the
human run; live 69 → 68, next label 96 (expected, spec §10).

**Lanes** (spec §7, `IX-AE`): 1 the neutral tree and both bridges; 2 every
`Sources/MetalUI` file (modifiers, builder, proposal path, dispatch, `List`
selection); 3 the audit tests, the demo modal's two accessibility modifiers
and the VoiceOver script. Disjoint files, one declared stub arm. Expected
close 1878 tests, 116 guards, `Backends/SDL` 22 + 32.

**Demo** (spec §8, `IX-X` item 4): 0 px expected in all fourteen offscreen
images; the modal panel's new declaration adds one `$ax` slot while the modal
is up (named).

**Lock probe at design time**: locked, so the real-window capture is owed, as
at every task since stage 6b.
