# 74 — Menus, popovers and tooltips

User request 2026-10-02 (an item of the gpui-gap priority list; **not a plan
task**). Branch `feat/menus-popovers` from `b9da519`. Spec
`docs/superpowers/specs/2026-10-02-menus-popovers-design.md`; rulings
`MN-A`…`MN-T` in `docs/superpowers/2026-10-02-menus-popovers-decisions.md`;
probes `docs/probes/swiftui-menus-popovers.swift` and
`docs/probes/swiftui-commands.swift` (both new). This file is written in
phases: the design section now, each lane's section as it lands, the Record
phase's close last (renumbered then if another line publishes §74 first).

## §1 Design (2026-10-02)

**Baseline at `b9da519`**, re-taken by the design session: `swift build
--build-system native --build-tests` 0 `error:`, the one `warning:` SwiftPM's
deprecation notice; `swift test --build-system native --no-parallel` → `Test
run with 2227 tests in 3 suites passed after 117.176 seconds`, the `FR-J
no-argument frame: succeeded=true` line present. 133 guards (record §73), 0
goldens, 76 live divergences, next label 110.

**The screen was locked for the whole session** (`CGSSessionScreenIsLocked =
1`, `displayAsleep main: 1`), so both probes are headless and the app never
had a key window. Readings that need one — control-click (C5c, with its
separating arm C5n), a popover's Escape and outside click (P3, P3b, P4a,
P4c), the tooltip (H7) and the key-window order of a shortcut both a menu
item and a window `Button` claim — are recorded as broken instruments and
owned by human checks R1, R5, R6 and R4 (spec §8).

**Probes.** `swiftui-menus-popovers.swift`, compiled form, run twice: stdout
byte-identical (131 lines), exit 0, stderr empty. `swiftui-commands.swift`,
both builds (`-D PLAIN` and full), run twice each: byte-identical, exit 0.
Outputs verbatim in their headers.

**What the probes settled** (decisions doc for the reasoning): SwiftUI's
context menu is a native `NSMenu` built from the declared items and rebuilt
at each open (C1–C4c); a right press opens it (C5r); nested menus — the inner
wins at the inner view (C8); a disabled view's menu opens with items disabled
(C9); an empty one does not open (C10); VoiceOver's show-menu opens it
(C11); a context item's shortcut is inactive while closed (C12); a right
click presses a SwiftUI `Button` and fires a tap, where an `NSButton` ignores
it (C6, C6t, C6n — divergence 110, `MN-B`); `Menu` is `AXMenuButton` (M1); a
popover is a transient `NSPopover` in its own window, placed on `arrowEdge`'s
side, extending past the presenting window, flipped against the screen,
default edge `.top`, published as a non-modal `AXPopover` (P1, P2, P2b, P5,
P7 — divergences 111, 112); `.help` is `AXHelp` with the hint's precedence
and distribution (H1–H5); the default menu bar and where `CommandMenu`/
`CommandGroup` put their items (the commands probe).

**Design.** Native `NSMenu` on AppKit and a window-drawn menu elsewhere,
through one new defaultless `PlatformWindow.presentMenu(_:at:) -> Bool`, the
choice returning as a queued `InputEvent.menuAction` (`MN-C`); a closed
`MenuContent` vocabulary evaluated at each open (`MN-D`); `App.commands { }`
with a defaultless `Platform.setMenuBar(_:)`, the standard menus installed by
every AppKit app (a migration note), command shortcuts as one stage after
`Button` shortcuts in the window's pipeline and AppKit asking that pipeline
before the main menu (`MN-I`…`MN-K`); popovers as a one-level wrapper with an
anchored presentation root, flipped and clamped in the window, dismissed from
input (`MN-L`…`MN-O`); `.help` as the accessibility hint plus a drawn,
tick-timed tooltip (`MN-P`, divergence 113). Three lanes (spec §5); expected
counts 2303 / 0 / 141 (spec §6.4).

## §2 Critic round (2026-10-02)

**Probes re-run first, unchanged.** `swiftui-menus-popovers.swift` as
committed reproduced its 130 recorded output lines byte for byte (screen
still locked); both `swiftui-commands.swift` builds reproduced theirs (only
the process name, which follows the binary's file name, differs in the
application menu's titles).

**Four arms appended** to the menus probe after C10, nothing above them
changed; extended form run twice, stdout byte-identical (137 lines), exit 0,
stderr empty; header re-recorded:

- C11n — `accessibilityPerformShowMenu` on a node with no context menu →
  `false`, no tracking. The dumps' `[showMenu]` is `responds(to:)`, true of
  every node, so it was never evidence (`MN-W`).
- C13c / C13 — a right press opens the menu (`["X"]`); under
  `.allowsHitTesting(false)` it opens nothing. The design had registered the
  region outside that gate, copying drop destinations (`MN-U`).
- C14 — an opaque `Color` covering a context-menu view blocks its menu. The
  design's test 1.10 asserted the opposite (`MN-V`, divergence 114 for a
  cover that only paints).

**Spellings read from the SDK** (`SwiftUI.swiftinterface`, macOS 27.0):
`popover(…arrowEdge: Edge? = nil…)`, not `Edge = .top`; `commands(content:)`,
not an unlabelled closure (`MN-X`).

**Design defects fixed by ruling**: P4a's outside click reached the button
beneath, so an outside press now dismisses and passes through, with the
anchor's own press consumed (`MN-Y`); the popover chrome registered no
hitbox, so a press on its padding would have reached a lower layer — a raw
opaque hitbox now blocks (`MN-Z`); an Edit menu action would have
re-delivered a ⌘-key the window had just declined (`MN-AA`); the in-window
menu would have vanished under `IX-X` modal isolation (`MN-AB`);
control-click is AppKit-only (SDL's ctrl-click is `List`'s toggle) with a
migration note, the existing `MemoryLayout<Handlers>` bound in
`AccessibilityModifierTests` moves, and `FrameLoopTests`' `App(device:)` now
installs `NSApp.mainMenu` in the shared test process (`MN-AC`); lanes
rebalanced — SDL input to lane 1, the `Menu` pull-down to lane 2 (`MN-AD`).

**Checked and kept**: divergence labels (76 live, next 110 at `b9da519`);
`Edge` has `leading`/`trailing`; `PrepaintPass.insertHitbox(_:id:opaque:)`
exists; no new drawable primitive; every new requirement defaultless with
honest fakes; the demo touches no default-mode image.

**Revised expectations**: 2308 root tests (lane 1 35, lane 2 20, lane 3 26),
141 guards, `Backends/SDL` +5, live divergences 81 (110–114), next label 115.
Rulings `MN-U`…`MN-AD`; next unused `MN-AE`.
