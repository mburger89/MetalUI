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
