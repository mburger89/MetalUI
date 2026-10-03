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

## §3 Lane 1 — the seam, context menus, SDL input (2026-10-02)

**Commits.** `bdf9d96` (red: the declarations and stubs, the tests),
`24da763` (implementation), then this record's commit.

**What landed** (spec §2.1–§2.3, §3.1–§3.3, §3.9, §3.11's input; ruling
`MN-AE` for what building it settled):

- `MetalUIPlatform`: `InputEvent.rightMouseDown`/`.rightMouseUp`/
  `.menuAction(MenuActionEvent)`; `Menus.swift` (`PlatformKeyEquivalent`,
  `StandardMenuAction`, `PlatformMenuItem`, `PlatformMenu` — `PlatformMenuBar`
  is lane 2's); `PlatformWindow.presentMenu(_:at:)` with **no default**:
  `AppKitWindow` an interim `false` (lane 2 replaces it with `NSMenu`),
  `SDLWindow` a final `false`, `FakePlatformWindow` a settable answer that
  records every call, and the three compile-guard fixtures
  (`ControlStateCompileGuards`, `TransactionCompileGuards`,
  `DragAndDropCompileGuards`); five roles, `AccessibilityActions.showMenu`,
  `AccessibilityRequest.showMenu`.
- `MetalUI`: `MenuContent` (closed: an `@_spi(MenuInternals)` requirement),
  `MenuContentBuilder`, `MenuItems`, `Divider` (menu-only), the conformances
  of `Button`/`Toggle` (with a `Text` label), `Text`, `EnvironmentScope` and
  `Menu` (as a submenu item), and `Menu`'s declaration with its storage
  (`MN-AD`); `Button`'s `action`/`box`/`shortcut` and `Toggle`'s `isOn`/`box`
  went from `private` to internal for the item conformances — no public
  surface moved. `.contextMenu` on `StyledElement` (returns `Self`) and on
  `ProposalElementGroup` (`ContextualModifier<Content>`, one level for its
  caller). `Handlers.contextual` (`ContextualAttachment`, a class box):
  `MemoryLayout<Handlers>.size` **456 → 464**.
- `Frame.registerHandlers`: the non-opaque contextual region inside the
  `allowsHitTesting` gate and before the disabled gate (`MN-U`), carrying the
  element's `isEnabled` (`Hitbox.contextualEnabled`); a per-frame
  `contextMenuRecords` table for the keyboard and accessibility openers; a
  context menu counts as something to say for accessibility (`MN-AE` item 2).
- `Window`: `contextualTarget(at:where:)` (`MN-V`: one ranking over opaque
  hitboxes and regions, an opaque hit yielding its own or its nearest
  same-layer ancestor's region); the menu stage and the context-menu stage
  after the drag session (`MN-F` item 3, `MN-E`); the `.menuAction` stage
  (token-checked, enabled items only, run under `StateDispatch`); the
  keyboard opener after the raw `onKey` bubble (`MN-G` item 1, `MN-AE` item
  4); resize and losing key dismiss the in-window menu; the panel's nodes
  appended after the builder's isolation (`MN-AB`); `.showMenu` and a press
  on a panel row in `WindowAccessibility`. `MenuSession.swift` (the session,
  `ContextMenuKeys`), `MenuPanel.swift` (pure layout and placement, the
  paint after `paintDragPreview()` through `Frame.fill`/`draw` and the
  existing shadow — no new primitive).
- Bridges: AppKit `AXMenu`/`AXMenuItem`/`AXMenuButton`/`AXPopover`, a check
  item's state as its numeric value (`MN-AE` item 1), and
  `accessibilityPerformShowMenu` overridden on every element (the inherited
  one forwards to an unimplemented `accessibilityPerformAction:` and threw an
  `NSInvalidArgumentException` on the red run). AccessKit `MENU`,
  `MENU_ITEM`, `MENU_ITEM_CHECK_BOX` (toggled), `BUTTON` + `has_popup MENU`
  (a new `AccessKitSnapshot.Node.hasPopupMenu`), a non-modal `DIALOG`, and
  `SHOW_CONTEXT_MENU` both ways.
- `Backends/SDL`: `SDLBridge.c` reports `SDL_BUTTON_RIGHT` as
  `MUI_EVENT_RIGHT_DOWN`/`_UP` (appended kinds, nothing renumbered; a
  ctrl-click stays primary, `MN-AC` item 1), the injection path takes them,
  and `mui_push_raw_mouse_event` with C-exported `mui_sdl_*` type, button and
  mask constants drives SDL's own queue in tests; `SDLKeys.named` maps
  `SDLK_APPLICATION` to `U+F735`.
- Docs: divergences 110 and 114 (78 live; 111–113 reserved for lane 3, next
  label 115), four documented absences, migration rows (`presentMenu`, the
  three enum switches, AppKit's control-click), inventory family
  `context-menus` (`ContextMenu.swift`, `MenuContent.swift`; `Menus.swift` is
  the existing `platform` family's catch-all), census **2086 → 2146**, both
  checks print nothing.

**Red first** (`bdf9d96`, filtered run of the new files): 32 of the 34
`ContextMenuTests` red, each on its first `#require`/`#expect` (no region
registered, no `presentMenu` call, no `menuSession`, no `.showMenu` node, or
`ContextMenuKeys` answering `false`); `theAppKitBridgePublishesTheMenuRoles…`
red with 6 issues (roles `.group`, no value, `performShowMenu` `false`);
`Backends/SDL` S1.1 red (9 issues), S3.1 red (the right button dropped), S3.2
red (no `U+F735`). **Green on arrival, each then reddened by its own
mutation**: 1.8 `aSecondaryPressNeverRunsOnClickOrATap` (a pin of an
absence), 1.33 `handlersGainsOneReferenceMember` (the member landed with the
declarations), S1.2 `anSDLWindowDeclinesToPresentAMenu` (SDL's final answer
landed with the requirement), and the four guards (declarations). G1.4's
first run was a broken instrument — the fixture spliced a literal
`\(member)` — fixed before the red commit.

**Mutations** (each applied after committing, restored from a copy, full
unfiltered suite, `git status --short` clean after each):

| # | mutation | reddened (and nothing else) |
|---|---|---|
| MG1.1 | every `@_spi(MenuInternals)` removed from `MenuContent.swift` | `anOutsideTypeCannotConformToMenuContent` |
| MG1.2 | `MenuContentBuilder.buildArray` removed (the positive arm's `for` fails; the spec's "Divider made an Element" would need a whole conformance) | `theMenuSpellingsCompileFromAPlainImport` |
| MG1.3 | `extension Picker: MenuContent` | `aPickerIsNotAMenuItem` |
| MG1.4 | a protocol-extension default `presentMenu` answering `false` | `aPlatformWindowWithoutPresentMenuDoesNotCompile` |
| M1.8 | `.rightMouseDown`/`Up` rewritten to `.mouseDown`/`Up` at the top of `onInput` | `aSecondaryPressNeverRunsOnClickOrATap` (3 issues) and every test that opens a menu (35 issues in all) |
| M1.33 | a second, inline `String?` member beside `contextual` | `handlersGainsOneReferenceMember`, `theNewDeclarationsCostHandlersAtMostOnePointer` |

The remaining rows of spec §6.1's mutation column are the lane verifier's.

**Counts.** `swift build --build-system native --build-tests`: 0 `error:`,
the one `warning:` SwiftPM's deprecation notice. Unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 2266
tests in 3 suites passed after 125.920 seconds`** (2227 + 35 + 4 guards),
the `FR-J no-argument frame: succeeded=true` line present. Guards 133 → 137.
`Backends/SDL`: **24 + 61** (`MetalUISDLTests` +4: S1.1, S1.2, S3.1, S3.2). Re-taken after
`swift package clean` (a public type gained a stored property): the same
2266, passed after 119.436 seconds. `swift build --build-tests` (default build
system): 0 `warning:`. A `swift:6.4-noble` container (OrbStack, started and
stopped) builds with 0 `error:`/`warning:` and runs **199 + 22 + 21 + 31 + 18
+ 6**, as at record §73. `MetalUILayout` and `MetalUIScene` untouched;
`Menus.swift` imports only `MetalUICore`. `DemoFrameDeterminismTests`'
`Expected.swift` unedited. `ContextualModifier` registers no click, so it gets
no arm in D2 (`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`),
which also has no drop-destination or draggable arm.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> b9da519 HEAD`
(HEAD `24da763`): **0 differing pixels, scene identical, in all fourteen
images**; controls as at `b9da519`.

**Stack budget.** The smallest thread building every production tree, by a
16 KB bisection with the existing harness (`buildEveryProductionTree`, exit
tests, throwaway file, not committed): **704 KB SIGBUS / 720 KB passes at
`24da763`; 688 KB SIGBUS / 704 KB passes at `b9da519`** on this machine and
toolchain (record §73 read 672 KB — a different build, re-measured here
rather than compared) — one step, from the 8 bytes every `Handlers` gained;
inside 1 MB (`everyProductionTreeBuildsOnAOneMegabyteThread` green).

**Not taken.** The real-window capture and any demo launch: the lock probe
read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`.

### §3.1 Lane 1 review fix round (2026-10-02)

Five review findings (two major, three minor), each answered red-first by a
mutation run through the full unfiltered suite (`--build-system native
--no-parallel`, one summary line each; `git status --short` empty after every
restore). Unmutated: **`Test run with 2269 tests in 3 suites passed after
120.510 seconds`** (2266 + 3 new tests; 1.4 gained arms, not a test), the
`FR-J no-argument frame: succeeded=true` line present.

| Finding | Answer | Mutation | Reddened |
|---|---|---|---|
| keyboard opener unreached (major) | internal seam `Window.contextMenuKeyPlatform` (defaults to `TextEditing.platform`, read by `dispatchContextMenuKey`); test 1.29b `shiftF10AndTheMenuKeyOpenTheFocusedElementsAncestorsMenuOffApple` | `for id in focusChain` → `focusChain.first` | 1.29b only (2 issues) |
| `MN-AE` item 3 unpinned (major) | test 1.30b `aDisabledElementAdvertisesNoShowMenuButTheRequestOpensItsMenuDisabled` | advertise `.showMenu` without `record.isEnabled` | 1.30b only |
| | | refuse `.showMenu` for a disabled record | 1.30b only (2 issues) |
| `MN-AE` item 6 unpinned (minor) | test 1.38 `aFocusedFieldsSpaceChoosesTheHighlightedInWindowItem` (positive control: with the menu closed the same `.textInput(" ")` types) | `text == " "` → `text == "never"` | 1.38 only (3 issues) |
| 1.4 cannot see per-frame caching (minor) | 1.4 gains two no-frame arms: Flag re-chosen (blind — a toggle reads its binding when the platform items are built, so caching `MenuItems` leaves it green, found by running), and a title read from the model in the content closure | cache `MenuItems` in the frame's `ContextualAttachment` | green before the title arm; `theMenuIsEvaluatedAtEachOpen` only after |
| migration row not live (minor) | `docs/migration.md`'s control-click row marked *pending lane 2* | — | — |

The seam is internal and production never writes it; no public declaration,
census or inventory row moves. Nothing in `Sources/` changes behaviour.
