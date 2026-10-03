# 74 — Menus, popovers and tooltips

User request 2026-10-02 (an item of the gpui-gap priority list; **not a plan
task**). Branch `feat/menus-popovers` from `b9da519`. Spec
`docs/superpowers/specs/2026-10-02-menus-popovers-design.md`; rulings
`MN-A`…`MN-AH` in `docs/superpowers/2026-10-02-menus-popovers-decisions.md`;
probes `docs/probes/swiftui-menus-popovers.swift`,
`docs/probes/swiftui-commands.swift` and `docs/probes/swiftui-popover-chaining.swift` (all new). This file was written in
phases (design, one section per lane, the Record phase's close §6); master had
not moved past `b9da519` at the close, so §74 stands.

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

## §4 Lane 2 — AppKit, the menu bar, the `Menu` pull-down (2026-10-02)

From `d3520ef` (lane 1's fix round, 2269 tests). Commits `6f25891` (red) and
`071046e` (implementation). Ruling `MN-AF` (decisions doc, next unused
`MN-AG`).

**Built.** `AppKitMenus.swift`: `AppKitMenuBuilder` (a `PlatformMenu` →
`NSMenu`, `autoenablesItems = false` on every level, states, key equivalents
with their mask, each action item's tag its id), `AppKitMenuTarget`,
`AppKitMenuBar` (the main menu, `menuNeedsUpdate` rebuilding a menu from fresh
content as it opens; standard items on AppKit's selectors — the application
menu's and Bring All to Front targeting `NSApp`, the rest the responder chain;
command items calling `PlatformMenuBar.perform`), and the host view's Edit
actions (`cut:` … `delete:` deliver the item's key; `validateMenuItem` enables
them only while a caret is set, `MN-K`; nothing is delivered when
`currentEvent` is the key equivalent the window declined, `MN-AA`).
`AppKitPlatform.swift`: `presentMenu` pops the menu up through the replaceable
`menuPresenter` and delivers `.menuAction` through `scheduleMenuOutcome` after
returning (`MN-C` item 4); `rightMouseDown`/`Up`; a control-press is a
secondary press with its drag dropped (`MN-AC` item 1);
`performKeyEquivalent(with:)` offers a ⌘-key to the window first and never
twice (identity, `MN-J` item 3), `keyDown(with:)` skipping the remembered
event; `setMenuBar` installs `NSApp.mainMenu`. `Commands.swift`: `Commands`
(closed, SPI requirement), `CommandItems`, `CommandsBuilder`, `CommandMenu`,
`CommandGroup` (before/after/replacing), `CommandGroupPlacement` (nine),
`MenuBarModel` and `App.commands(content:)`; every `App` initialiser installs
the default bar (`MN-I` item 4) and every window it opens gets
`commandShortcuts`. `Window.dispatchCommandShortcut` directly after
`dispatchShortcut` (`MN-J`). `Platform.setMenuBar(_:)`, no default: AppKit,
SDL (records), `FakePlatform` (records) and `AppIconCompileGuards`' fixture.
`PullDownMenu.swift`: `extension Menu: Element, StyledElement` over
`Button<Pair<Label, Text>>` (the `⌄` hidden from accessibility), the window-owned
anchor map (`Window.lastPresentationAnchors` ← `Frame.presentationAnchors`),
`MenuPresenter`, `Window.openPullDownMenu` (bottom-leading, through
`openContextMenu(of:_:)`), and `AXNode.menuButtonHint` → `.menuButton`
(stripped before `isEmpty` as `selectionHint` is). `Menu`'s initialiser now
sets `Button`'s chrome as its default style and decoration.
`docs/migration.md`: `setMenuBar` for a `Platform` conformer; an AppKit app
has a menu bar; ⌘-keys through `performKeyEquivalent`; a command's key is
claimed by the command stage; the control-click row is live (no longer
*pending lane 2*). Inventory families `menu-bar` (A, `swiftui-commands.swift`
PLAIN) and `pull-down-menu` (A, M1); census **2146 → 2184**;
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

**Red** (`6f25891`, full unfiltered suite: `Test run with 2291 tests in 3
suites failed … with 25 issues`): 17 of the 20 root tests red, each first line

| Test | First red line |
|---|---|
| 2.1 `anAppKitMenuIsBuiltFromThePlatformMenu` | `AppKitMenuTests.swift:136: menu.items.count == 6` |
| 2.2 `aChosenNativeItemArrivesAsAMenuActionAfterThePopUpReturns` | `:176: shown` |
| 2.3 `aDismissedNativeMenuArrivesAsANilMenuAction` | `:193: appKit.presentMenu(c1Menu, at: pt(10, 10))` |
| 2.4 `aRightMouseDownAndAControlClickReachOnInputAsRightMouseDown` | `:214: log.entries == ["rdown(30,40)", …]` |
| 2.5 `theHostViewOffersACommandKeyToTheWindowBeforeTheMainMenu` | `:232: view.performKeyEquivalent(…⌘k…)` |
| 2.13 `theMainMenuMapsStandardActionsToAppKitSelectors` | `:286: NSApplication.shared.mainMenu` |
| 2.14 `theEditMenuReachesTheFocusedFieldAsItsKeys` | `:312: log.entries == ["key[⌘x]", …]` |
| 2.15 `aMenuBarItemRunsItsCommand` | `:332: NSApplication.shared.mainMenu` |
| 2.16 `theMenuBarIsRefreshedWhenAMenuOpens` | `:352: NSApplication.shared.mainMenu` |
| 2.18 `anEditKeyTheWindowDeclinedIsNotDeliveredAgainByTheEditMenu` | `:376: log.entries == ["key[⌘z]"]` |
| 2.7 `aCommandsShortcutFiresWhenNothingInTheWindowClaimsIt` | `CommandsTests.swift:108: fake.simulateInput(key("j", .command))` |
| 2.10 `theDefaultMenuBarHasTheStandardMenus` | `:138: describe(app.menuBarContent()) == […]` |
| 2.11 `aCommandMenuIsInsertedBeforeTheWindowMenu` | `:151: menus.map(\.title) == […]` |
| 2.12 `commandGroupsPlaceTheirItemsBeforeAfterAndReplacing` | `:168: describe(app.menuBarContent()) == […]` |
| 2.17 `everyAppInstallsTheDefaultMenuBar` | `:187: platform.menuBars.count == 1` |
| 1.31 `aPullDownMenuPublishesAsAMenuButtonAndOpensBelowItself` | `PullDownMenuTests.swift:58: buttons.count == 1` |
| 1.32 `aPullDownMenuOpensFromButtonsActivationKeysAndNotWhenDisabled` | `:91: platform.presentedMenus.count == 2` |

**Green on arrival, by construction**: 2.6
`aButtonsShortcutWinsOverACommandsAndFiresOnce` (the stub had no command
stage, so the button alone answered) and 2.8 `aDisabledCommandsShortcutDoesNothing`
(nothing ran) — each is the mutation column's to redden (the verifier's). A
first red run truncated with no summary line (an unguarded `describe(menus)[3]`
in 2.11 trapped on the stub's empty bar); fixed to `try #require` on the
titles (practices shape 13) before the recorded red run. `Backends/SDL`:
S2.1 `sdlRecordsTheMenuBarAndDrawsNothing` red at
`SDLMenuBarTests.swift:25: platform.menuBar`.

**Found by running** (`MN-AF` item 1): 1.32 as specified ("Space and Return
each open") stayed red after the implementation — `ControlKeys.activatesButton`
is Space on a Mac, Return only off Apple, and `Menu` is `Button`'s keys. The
spec's `MN-H` item 1 was amended, not the key table; 1.32 now asserts Space
opens it and Return does so only off Apple.

**Guard mutations** (commit first, restored from a copy, full unfiltered
suite, `git status --short` clean after each):

| # | Mutation | Reddened (only) |
|---|---|---|
| MG2.1 | every `@_spi(MenuInternals)` removed from `Commands.swift` (the fabricated conformance compiles: `fabricated succeeded=true`) | `theCommandsSpellingsCompileFromAPlainImport` |
| MG2.2 | `extension Platform { public func setMenuBar(_:) {} }` (`without succeeded=true`) | `aPlatformWithoutSetMenuBarDoesNotCompile` |

The rest of spec §6.2's mutation column is the lane verifier's.

**Counts.** `swift build --build-system native --build-tests`: 0 `error:`,
the one `warning:` SwiftPM's deprecation notice. Unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 2291
tests in 3 suites passed after 125.080 seconds`** (2269 + 20 + 2 guards), the
`FR-J no-argument frame: succeeded=true` line present; re-taken after
`swift package clean` (public `App`, `AppKitPlatform` and `AXNode` gained
stored properties): the same 2291, passed after 121.224 seconds. Guards
137 → 139 (G2.1, G2.2; spec §6.4's 141 with lane 3's two). `swift build
--build-tests` (default build system): 0 `warning:`, 0 `error:`.
`Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`): **24 + 62**
(`MetalUISDLTests` +1, S2.1). A `swift:6.4-noble` container (OrbStack, already
running; left as found) builds with 0 `error:`/`warning:` and runs **199 + 22
+ 21 + 31 + 18 + 6**, unmoved (no lane-2 test is in a portable suite; the
container shows `Commands.swift`, `PullDownMenu.swift` and the `Platform`
requirement compile off Apple). `MetalUILayout` and `MetalUIScene` untouched.
`DemoFrameDeterminismTests`' `Expected.swift` unedited.
`MemoryLayout<Handlers>.size` unmoved at 464 (the hint fits `AXNode`'s
padding; `handlersGainsOneReferenceMember` green); no production tree gained an
element, so the stack budget was not re-bisected.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> b9da519 HEAD` (HEAD
`071046e`): **0 differing pixels, scene identical, in all fourteen images**;
controls as at `b9da519`.

**Real window.** The lock probe read no `CGSSessionScreenIsLocked` line and
`displayAsleep main: 0`, so `docs/probes/window-capture/capture.sh <scratch>
b9da519 HEAD` ran: each window's pair 0 differing, **`b9da519 → HEAD`
default 0, preview 0** (1840 × 1176), control default vs preview 958986. The
menu bar itself, a native context menu's look, ⌘Q and the Edit menu by click
were not exercised — no input is sent (human checks R1, R3, R4).

**Deferred / owed.** The AppKit seams' production defaults (`NSMenu.popUp`,
the next-turn scheduler, `NSApp.currentEvent`) and the event-identity reading
are pinned by no test (`MN-AF` items 7–8; human checks R1, R4). A closed
menu's stale tag after a structural change, dispatched by the main menu rather
than the window (`MN-AF` item 3), owner none. Lane 3 extends the anchor map
for popovers.

### §4.1 Lane 2 review fix round (2026-10-03)

Four review findings (two major, two minor), each answered red-first by a
mutation run through the full unfiltered suite (`--build-system native
--no-parallel`, one summary line each; `git status --short` empty after every
restore; mutations applied to `32e0240`, the spelling quoted). Unmutated:
**`Test run with 2293 tests in 3 suites passed after 129.364 seconds`** (2291 +
1.31b, 1.31c; 2.9 gained an arm, not a test), the `FR-J no-argument frame:
succeeded=true` line present, 0 `error:`, the only native `warning:` SwiftPM's
deprecation notice; `swift build --build-tests` 0 `warning:`.

| Finding | Answer | Mutation | Reddened |
|---|---|---|---|
| `MN-AF` item 6's scroll translation unpinned (major) | test 1.31b `aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame`: a `Menu` 100 pt down a 200 × 200 scroller wheel-scrolled by 37 presents at the scrolled published frame's bottom-leading corner | MANCH: `bounds.origin.x.value + activeOffset.x.value` / `…y…` → `bounds.origin.x.value` / `…y…` in `Frame.recordPresentationAnchor` | 1.31b only (1 issue) |
| `MN-AF` item 5's no-`$ax` claim unpinned (major) | test 1.31c `aPullDownMenuWritesNoAXNodeAndNoAXSlot`: client on and off, no `Frame.axNodes` entry and no `$ax` slot under the menu's id (its one hitbox's owner — the hidden `⌄` text declares a node of its own, found by running); separating arm, a declared `.selected` trait, writes both | M1.31c: `declaration.menuButtonHint = false` deleted from `Frame.registerHandlers` | 1.31c only (4 issues) |
| `performKeyEquivalent`'s repeat guard unpinned (minor) | test 2.9 offers the same declined event twice before `keyDown(with:)`: one delivery (`MN-AF` item 10) | M2.9b: `if event === lastOfferedKeyEquivalent { return false }` deleted from `performKeyEquivalent(with:)` | 2.9 `aKeyEquivalentDeclinedByTheWindowIsNotDeliveredAgainAsAKeyDown` only (2 issues) |
| the forwarded `isEnabled` is dead; 1.32's name stale (minor) | `MN-AF` item 9 and spec row 1.32: the gate is `Button`'s (`Frame.registerHandlers`), the forward kept as belt-and-braces with a source note; 1.32 renamed `aPullDownMenuOpensFromButtonsActivationKeysAndNotWhenDisabled` | — (the reviewer's M1.32 green stands; no test can see it) | — |

No public declaration, census row, `Sources/` behaviour or pixel moves (one
source comment in `PullDownMenu.swift`).

## §5 Lane 3 — popovers, `.help` and the tooltip, the demo (2026-10-03)

From `1cecaf5` (lane 2's fix round, 2293 tests). Commits `8d14ff7` (red),
`a91314b` (implementation), `defb937` (the demo's `Observation` import, found
by the Linux container). Ruling `MN-AG` (decisions doc, next unused `MN-AH`).

**Built.** `Popover.swift`: `PopoverModifier<Content, PopoverContent>` (both
vocabularies; `ProposalElementGroup` when its content is), the four
`.popover(isPresented:/item:arrowEdge:content:)` spellings (`arrowEdge: Edge?
= nil`, `nil` is `.top`), the evaluated-optional slot at cursor 1 —
`OptionalGroup<AnchoredPresentation<Box<P>>>`, produced while presented and
anchored, `item:` naming the chrome `Box` by the item's id — and
`Window.dispatchPopovers` (an outside press dismisses from input under
`StateDispatch` and passes on; a press on a dismissed popover's anchor is
consumed with its release; Escape dismisses the topmost; between the open
menu's stage and the context menu's). `AnchoredPresentation.swift`:
`Deferred`'s three halves with its own lowering — `lowerAnchoredPresentation`
queues a window-sized `PopoverPlacement` (`ProposalLayout`: measure at nil,
capped at the window less 16; `origin(anchor:size:edge:window:)`, pure: 8-pt
gap, centred, flip, clamp 8) in `LoweringState.presentations`; prepaint
inserts the raw opaque blocking hitbox (`MN-Z`) and registers the
`OpenPopover`; paint draws the panel (one bordered rect, one shadow, `MN-AG`
item 1). `Frame.previousPresentationAnchors`/`openPopovers`/`tooltip`,
`Window.lastOpenPopovers`/`popoverClaimsRelease`/`tooltipTracker`.
`AXNode.popoverHint` → `.popover` (stripped before `isEmpty`, no `$ax`).
`Tooltip.swift`: `.help` on both vocabularies (`StyledElement` returns `Self`:
the hint plus `ContextualAttachment.help`; the proposal spelling a
`ContextualModifier`, which now declares the hint and registers synthesizing
when it carries help, `MN-AG` item 7), `TooltipTracker` (idle → pending →
shown → spent), `Window.trackTooltip` (every event, never claiming),
`advanceTooltip(to:)` in the display-link callback beside `advanceGestures`,
the pause rule (`isPending` keeps the link awake), `hideTooltip` on leaving
key, `TooltipPlacement.origin(pointer:size:window:)` and `Frame.paintTooltip`
after the menu panel. `MetalUIDemoContent/MenusDemo.swift`
(`menusDemoContent()`, each section its own function; `MenusDemoModel`),
`METALUI_MENUS_DEMO=1` in `MetalUIDemo` (with `app.commands { CommandMenu("Demo")
…; CommandGroup(after: .newItem) … }`) and in `MetalUISDLDemo`; `menusDemoContent()`
joins `buildEveryProductionTree`. `docs/verification/human-checks.md` group R
(R1–R8); divergences 111–113 and an absences row; inventory families
`popovers` and `help` (class A, P1 and H1); census **2184 → 2197**;
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.

**Red** (`8d14ff7`, full unfiltered suite against the stubs: `Test run with
2321 tests in 3 suites failed after 137.437 seconds with 47 issues`): all 26
tests red, each first line

| Test | First red line |
|---|---|
| 3.1 `thePopoverSitsOnItsArrowEdgeOfTheAnchor` (×4) | `PopoverTests.swift:129: window.lastOpenPopovers.last` |
| 3.2 `theDefaultArrowEdgeIsTop` | `:144: window.lastOpenPopovers.last` |
| 3.3 `aPopoverThatWouldLeaveTheWindowFlipsToTheOppositeEdge` | `:164: window.lastOpenPopovers.last` |
| 3.4 `aPopoverThatFitsNeitherSideIsClampedInsideTheWindow` | `:179: window.lastOpenPopovers.last` |
| 3.5 `aPressOutsideThePopoverWritesFalseAndReachesWhatItLandsOn` | `:210: window.lastOpenPopovers.last` |
| 3.6 `aPressInsideThePopoverReachesItsContent` | `:226: window.lastOpenPopovers.last` |
| 3.7 `escapeDismissesTheTopmostPopoverBeforeTheKeymap` | `:255: window.lastOpenPopovers.count == 2` |
| 3.8 `aPopoverIsAPresentationOnAHigherLayer` | `:297: window.lastOpenPopovers.last` |
| 3.9 `thePopoverPublishesAPopoverNodeAndIsolatesNothing` | `:362: popovers.count == 1` |
| 3.10 `aPopoverAddsOneIdentityLevelOnlyForItsCaller` | `:395: !wrapped.lastOpenPopovers.isEmpty` |
| 3.11 `aRepresentedPopoversContentStartsFresh` | `:436: log.entries == ["n=1", "n=2"]` |
| 3.12 `popoverItemFollowsTheItemAndResetsOnANewID` | `:462: window.lastOpenPopovers.count == 1` |
| 3.13 `aPopoverFollowsItsAnchorWithinOneFrame` | `:488: window.lastOpenPopovers.last` |
| 3.14 `anInitiallyPresentedPopoverAppearsOnTheSecondFrame` | `:508: window.needsRedraw` |
| 3.15 `aPopoverWritesNoStateTableEntry` | `:525: window.lastOpenPopovers.count == 1` |
| 3.16 `thePopoverChromeIsARoundedPanelWithNoArrow` | `:541: scene.highestLayer` |
| 3.17 `aTooltipAppearsAfterTheHoverDelayOfTickTime` | `TooltipTests.swift:72: window.visibleTooltip?.text == "Explains"` |
| 3.18 `theTooltipDelayIsStampedFromTheFirstTickAfterEntering` | `:89: window.visibleTooltip != nil` |
| 3.19 `aPressAWheelAKeyOrLeavingHidesTheTooltip` (×4) | `:99: window.visibleTooltip?.text == "Explains"` |
| 3.20 `aHiddenTooltipReturnsOnlyAfterLeavingAndReentering` | `:122: window.visibleTooltip?.text == "Explains"` |
| 3.21 `theTooltipIsPlacedBelowThePointerAndFlippedInsideTheWindow` | `:151: origin(50, 50) == [50, 68]` |
| 3.22 `helpPublishesTheSameTreeAsAccessibilityHint` | `:183: help == hint` |
| 3.23 `aHelpRegionAddsNoPointerTarget` | `:199: window.lastHitboxes.contains { … help == "h" }` |
| 3.24 `thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending` | `:229: window.visibleTooltip != nil` |
| 3.25 `theTooltipIsPaintedAboveEverything` | `:243: window.visibleTooltip?.text == "Explains"` |
| 3.26 `aPressOnTheAnchorDismissesThePopoverAndIsConsumed` | `:333: window.lastOpenPopovers.last` |

(Line numbers are the red commit's.) The guards: G3.1's first fixture chained
two legacy `.popover`s, which `PopoverModifier` does not offer (`MN-AG` item
4), and G3.2's first negative was refused for an uninferrable `P`, not for
`attachmentAnchor`; both were re-spelt before the commit and are **green
against the stubs by construction** (spellings guards) — their mutations
below.

**Found by running** (`MN-AG`): test 3.16 read two rects and two shadow
images — a legacy `Box` paints fill and border as two primitives, so the panel
moved into `AnchoredPresentation.paint` (item 1); test 3.15's "count equal"
was false by the chrome's and content's own `$anim`/`$anim-color` slots, so
it was restated (item 8); 3.5 pressed outside a `Button`'s hitbox (a legacy
`.frame` layer leaves the button its label's size), and 3.8's cover was a
`Button` whose hitbox did not reach the chrome's padding — 3.5 now presses the
label, 3.8's cover is a frame-sized `.onClick` `Box`; 3.1's `@Test(arguments:)`
literal spanned a line the inventory's `CITE` scan stops at, so the arguments
became a named constant; the Linux container refused `@Observable` in
`MenusDemo.swift` (no `import Observation`; Foundation re-exports it only on
Apple) — `defb937`.

**Guard mutations** (commit `a91314b` first, restored from a copy, full
unfiltered suite, `git status --short` clean after each):

| # | Mutation | Reddened (only) |
|---|---|---|
| MG3.1 | `extension StyledElement { public func help(_ text: Text) -> Self { self } }` in `Tooltip.swift` (`helpText succeeded=true`) | `thePopoverAndHelpSpellingsCompileFromAPlainImport` (1 issue; 2321 tests) |
| MG3.2 | `StyledElement.popover(isPresented:attachmentAnchor: Int = 0, arrowEdge:content:)` forwarding, in `Popover.swift` (`with succeeded=true`) | `aPopoverHasNoAttachmentAnchorParameter` (1 issue; 2321 tests) |

Spec §6.3's mutation column for 3.1–3.26 is the lane verifier's.

**Counts.** `swift build --build-system native --build-tests`: 0 `error:`,
the one `warning:` SwiftPM's deprecation notice. Unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 2321
tests in 3 suites passed after 147.992 seconds`** (2293 + 26 + 2 guards; 3.1
and 3.19 parameterized, counted once each), the `FR-J no-argument frame:
succeeded=true` line present; re-taken after `swift package clean` (public
`Window`, `Frame` and `AXNode` gained stored properties): the same 2321,
passed after 133.096 seconds. Guards 139 → **141** (G3.1, G3.2; spec §6.4's
141); goldens 0. `swift build --build-tests` (default build system): 0
`warning:`, 0 `error:`. `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`):
builds with 0 `error:` (its only `warning:`s the environment's — Homebrew
SDL3's dylib built for macOS 27 and SwiftPM's `-Wl,-rpath` notice) and runs
**24 + 62**, unmoved (no lane-3 SDL test: popovers and tooltips are portable
`MetalUI` code, exercised through `FakePlatformWindow`; `MetalUISDLDemo`
gained the `METALUI_MENUS_DEMO` branch). A `swift:6.4-noble` container
(OrbStack, already running; left as found), over a `git archive` of `defb937`
with `--scratch-path` inside the container, builds with 0 `error:`/`warning:`
and runs **199 + 22 + 21 + 31 + 18 + 6**, unmoved (its first run, over
`a91314b`, failed to build `MenusDemo.swift`: `unknown attribute
'Observable'`). Divergences 78 → **81 live** (111–113), next label 115.
`MetalUILayout` and `MetalUIScene` untouched (`git diff b9da519` reads nothing
under either). `DemoFrameDeterminismTests`' `Expected.swift` unedited.
`MemoryLayout<Handlers>.size` unmoved at 464 (`contextual` already existed;
`popoverHint` fits `AXNode`'s padding); `everyProductionTreeBuildsOnAOneMegabyteThread`
green with `menusDemoContent()` added, on macOS and in the container. A
throwaway (uncommitted) test rendered `menusDemoContent()` through a 900-pt
`FakePlatformWindow`: the popover presented (224 × 96 at (199, 122)) and a
tooltip showed after 1.1 s of ticks.

**Pixels.** `docs/probes/demo-pixels/compare.sh <scratch> b9da519 HEAD` (HEAD
`a91314b`): **0 differing pixels, scene identical, in all fourteen images**;
the controls as at `b9da519` (light vs dark 1048576, default vs modal
1031003, default vs animation 454895, f0 vs f3 0, preview light vs dark
1048576, chrome legacy vs proposal 0, distinct 544/216, prod default vs modal
491221, distinct prod 529, indicator rects 0).

**Real window.** The lock probe read no `CGSSessionScreenIsLocked` line and
`displayAsleep main: 0`, so `docs/probes/window-capture/capture.sh <scratch>
b9da519 HEAD` (HEAD `defb937`) ran: each window's pair 0 differing,
**`b9da519 → HEAD` default 0, preview 0** (1840 × 1176), control default vs
preview 958986. The menus demo was not launched (no input is sent by the
instrument; the popover's look, the tooltip and the menu bar are human checks
R3, R5, R6).

**Deferred / owed.** Spec §6.3's mutation column (3.1–3.26) is the lane
verifier's (recorded in §5.1). `PopoverModifier` is not a `StyledElement`, so
a `StyledElement` modifier and a second `.popover` cannot follow a legacy
`.popover` (`MN-AG` item 4, reworded and made divergence 115 by `MN-AH`),
owner none. The popover's Escape
and outside click against a native `NSPopover`, the tooltip's delay against
AppKit's, and the look of both are unmeasured (locked probes) — human checks
R5, R6; VoiceOver R7. No SDL test covers a popover or a tooltip (portable
code; R2/R5 under `MetalUISDLDemo`). The Record phase owes CLAUDE.md,
AGENTS.md, README, record index and records 03/04/05.

### §5.1 Lane 3 review fix round (2026-10-03)

The lane verifier's mutations V3.1–V3.26 (with V3.5b, V3.7a/b, V3.16a/b) and
VX.1–VX.4 ran on `defb937`'s sources, each through the full unfiltered
native suite (2321 tests) with `git status --short` clean after each restore;
spec §6.3's mutation column now records each one and the tests it reddened
(`MN-AH` item 6; row 3.12's is "drop the chrome `Box`'s `elementID`", there
being no `IdentifiedGroup`; V3.15's and V3.22's first spellings did not build
and were re-spelt — V3.22 writes the help as the accessibility identifier).
V3.5 (claim every non-anchor press, `guard onAnchor else { return true }`)
failed with 216 issues but not test 3.5; besides 3.8 it reddened 121 tests
outside lane 3.

Seven review findings (one major, six minor), answered red-first in
`d6c62fe` (tests) and `551cff2` (3.27 re-spelt), ruling `MN-AH` (next unused
`MN-AI`). This round's mutations (the verifier's spellings from its
`mutants.py`, plus V3.5a and MG3.3) each through the full unfiltered native
suite, `git status --short` showing no `Sources/` or `Tests/` path after
each restore:

| Finding | Answer | Mutation | Reddened |
|---|---|---|---|
| no proposal-path popover runs (major) | 3.27 `aProposalPathPopoverPresentsPlacesAndDismisses` | VX.4: `PopoverSlot(nil)` laid out in place of `layOutPopover` in `requestProposalLayout` | against the first spelling (a root `HStack {…}.frame(…).popover`): **nothing** (2327 passed) — a root `.popover` takes the legacy `requestLayout`; re-spelt with the popover inside an `HStack` (`551cff2`): 3.27 only (1 issue) |
| 3.5's mutation cannot redden 3.5 (minor) | 3.28 `theDismissingPressReachesAGestureBeneath` owns "passes on"; 3.5's doc comment and spec row restated, its mutation V3.5a | V3.5b: claim a press that dismissed a popover | 3.8 `aPopoverIsAPresentationOnAHigherLayer`, 3.28 (2 issues) |
| | | V3.5a: the dismissal loop never runs (`while false, let top = …`), on `551cff2` | 3.5, 3.8, 3.12, 3.26, 3.27, 3.28 and 3.29 (both cases) (15 issues; 3.29 found by the Record phase's verifier, the issue total unchanged by the earlier list's omission) |
| leaving key hides the tooltip, unpinned (minor) | 3.30 `theWindowLeavingKeyHidesTheTooltip`; divergence 113's pin gains it | VX.2: `self?.hideTooltip()` deleted from `onControlActiveStateChange` | 3.30 only (2 issues) |
| a menu open hides the tooltip, unpinned (minor) | 3.31 `noTooltipStartsWhileAMenuIsOpen` | VX.3: the `guard menuSession == nil` block deleted from `trackTooltip` | 3.31 only (2 issues) |
| the anchor release claim unpinned (minor) | kept; 3.29 `theAnchorPressesReleaseIsConsumedToo` (×2): without it a lone release reaches the raw `onInput` (`MN-AH` item 4) | VX.1: the `.mouseUp where popoverClaimsRelease == false, .rightMouseUp …` case deleted | 3.29 only (both cases, 4 issues) |
| chaining after a legacy `.popover` has no divergence row (minor) | divergence 115 (82 live, next label 116); new probe `docs/probes/swiftui-popover-chaining.swift` (CH1 chains `.padding` and a second `.popover` after `.popover`, CH2 control, NEGATIVE separating arm; run twice, identical); guard G3.3 `aStyledModifierCannotFollowALegacyPopover`; `MN-AG` item 4 reworded (`ElementGroup`-level `.frame`/`.id`/`.overlay`/`.background`/`.environment` do follow) | MG3.3: `public func padding(_ points: Pixels) -> Self { self }` on `PopoverModifier` | G3.3 only (1 issue) |
| stale build artifacts in the main checkout (minor) | reported to the user (`swift package clean` there before its next build); the main checkout was not touched | — | — |
| spec §6.3's mutation column is the plan (minor) | replaced with what was run (above), row 3.12 corrected | — | — |

**Counts.** Unmutated, on `551cff2`: **`Test run with 2327 tests in 3 suites
passed after 124.376 seconds`** (2321 + 3.27–3.31 + G3.3; 3.29 parameterized,
counted once), the `FR-J no-argument frame: succeeded=true` line and G3.3's
`MN-AH popover chaining:` line present; native build 0 `error:`, the only
`warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0
`warning:`; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print
nothing. Guards 141 → **142**. No `Sources/`
file, public declaration, census row or pixel moves in this round
(`git diff 63c80fe -- Sources` is empty), so the pixel, real-window, SDL and
container readings of §5 stand. The Record phase owes record 04 sections for
divergences 111–113 and 115.

## §6 Record phase — what landed, the close (2026-10-03)

`git fetch` at the close: `origin/master` is still `b9da519`, so nothing was
merged and §74 was not renumbered. All three lanes' verifiers returned `ok:
true`; their mutation tables are in §3.x, §4 and §5.1 (the Record phase adds
none of its own: it changes no `Sources/` or `Tests/` file).

**What landed.**

- **Seam** (`MetalUIPlatform`): `InputEvent.rightMouseDown/rightMouseUp/menuAction`
  (`MN-B`, a secondary press never presses, divergence 110), the closed
  `PlatformMenu`/`PlatformMenuItem`/`PlatformKeyEquivalent`/`StandardMenuAction`/
  `PlatformMenuBar` vocabulary, defaultless `PlatformWindow.presentMenu(_:at:) -> Bool`
  and `Platform.setMenuBar(_:)` (migration notes), five accessibility roles
  (`menu`, `menuItem`, `menuItemCheckBox`, `menuButton`, `popover`) and the
  `showMenu` request (`MN-R`).
- **Context menus** (`ContextMenu.swift`, `MenuContent.swift`, `MenuSession.swift`,
  `MenuPanel.swift`): `.contextMenu { }` on both vocabularies over a closed
  `MenuContent` (`Button`, `Toggle`, `Menu`, `Divider`, `if`/`for`), evaluated at
  each open (`MN-D`); AppKit builds an `NSMenu` (`AppKitMenus.swift`), SDL and any
  platform answering `false` get MetalUI's drawn menu with keyboard, hover,
  submenus, outside-click dismissal and AccessKit nodes; Shift-F10 and the Menu
  key open the focused element's menu off Apple (`MN-G`).
- **Menu bar** (`Commands.swift`): `App.commands { CommandMenu / CommandGroup(before:/after:/replacing:) }`
  over SwiftUI's `CommandGroupPlacement` spellings; every AppKit app installs the
  standard main menu (a behavioural migration note); command shortcuts are one
  stage after `Button` shortcuts in the window's pipeline, and AppKit offers a
  ⌘-key to that pipeline before the main menu, once (`MN-I`…`MN-K`, `MN-AA`).
  SDL draws no bar (shortcuts still fire).
- **`Menu("Title") { }`** (`PullDownMenu.swift`): a button opening its items below
  itself, an `AXMenuButton` (`MN-H`).
- **Popovers** (`Popover.swift`, `AnchoredPresentation.swift`): the four
  `.popover(isPresented:/item:arrowEdge:content:)` spellings, anchored to the
  declaring element, flipped then clamped in the window, no arrow, dismissed from
  input (divergences 111, 112; `MN-L`…`MN-O`, `MN-Y`).
- **Tooltips** (`Tooltip.swift`): `.help(_:)` publishes `accessibilityHint`'s tree on
  both bridges and draws a tick-timed tooltip (1.0 s; divergence 113).
- **Demo**: `menusDemoContent()` (`MenusDemo.swift`, its own function) behind
  `METALUI_MENUS_DEMO=1` on `MetalUIDemo` and `MetalUISDLDemo`.

**Tests per file** (`@Test` counts at HEAD; guards among them).
`ContextMenuTests` 37, `PopoverTests` 20, `AppKitMenuTests` 11, `TooltipTests`
11, `CommandsTests` 7, `PullDownMenuTests` 4, `MenuCompileGuards` 4,
`PopoverCompileGuards` 3, `CommandsCompileGuards` 2, `AppKitAccessibilityTests`
+1; `Backends/SDL`: `SDLMenuInputTests` 2, `AccessKitMenuTests` 2,
`SDLMenuBarTests` 1 (plus `MetalUISDLTests`' S1.1–S3.2 and S2.1 from §3 and §4).
Parameterized tests count once.

**Counts at the close.** `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered `swift test --build-system native --no-parallel`:
see §6.1 for the reading. Climb: 2227 (`b9da519`) → lane 1 2269 (+42) → lane 2
2293 (+24) → lane 3 2327 (+34). Guards 133 → 142 (lane 1 +4, lane 2 +2, lane 3
+3); goldens 0; `Backends/SDL` 24 + 57 → 24 + 62; census 2086 → 2206 (lane 3's 2197 plus nine `MetalUIDemoContent` rows —
`menusDemoContent` and `MenusDemoModel` — that its census file had not
re-recorded; re-taken at the close, both inventory scripts print nothing);
divergences 76 → 82 live (110–115 added, none retired, none amended), next
label 116; rulings `MN-A`…`MN-AH`, next `MN-AI`; human checks group R, R1–R8.

**Probes.** `swiftui-menus-popovers.swift` (groups C, M, P, H), `swiftui-commands.swift`
(plain and full builds) and `swiftui-popover-chaining.swift` (CH1, CH2, a
NEGATIVE separating arm): each run twice, byte-identical, outputs in their
headers. The first two ran in a **locked** session (§1), so seven readings are
broken instruments and owned by human checks (C5c/C5n, P3, P3b, P4a, P4c, H7,
the shortcut order of `MN-J` item 4).

**Red runs.** Every lane wrote its tests red first (each lane's section names
its red commit and readings). Every new
typecheck guard was mutated red once (G1.x in §3, G2.1/G2.2 in §4, G3.1–G3.3 in
§5/§5.1).

**Mutation tables.** Lane 1's verifier, six mutations, each reddening exactly
the named test: the focus-chain walk (`shiftF10AndTheMenuKeyOpenTheFocusedElementsAncestorsMenuOffApple`),
the bottom-leading anchor (that test and `aShowMenuRequestOpensTheElementsMenu`),
the disabled advertisement and refusal (`aDisabledElementAdvertisesNoShowMenuButTheRequestOpensItsMenuDisabled`,
both), the field's space key (`aFocusedFieldsSpaceChoosesTheHighlightedInWindowItem`),
the per-attachment cache (`theMenuIsEvaluatedAtEachOpen`). Lane 2's: `MANCH`
(`aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame`), `M1.31c`
(`aPullDownMenuWritesNoAXNodeAndNoAXSlot`, 4 issues), `M2.9b`
(`aKeyEquivalentDeclinedByTheWindowIsNotDeliveredAgainAsAKeyDown`), and `M1.32`
(forwarding `isEnabled: true`) reddened nothing **by design** — `MN-AF` item 9
documents the forward as belt-and-braces. Lane 3's: VX.4, V3.5a, V3.5b, VX.1–VX.3
and MG3.3 as in §5.1. No suite hung.

**Pixels and real window.** 0 differing pixels, scenes identical, against
`b9da519` in all fourteen offscreen images (§5); `capture.sh` ran once unlocked
(default 0, preview 0). The menus demo itself was not launched: the instrument
sends no input, so the look is human checks R1–R8.

**Hazards for the next branch.**

- **AppKit behaviour moved** (migration.md): control-click is a secondary press
  (`MN-AC`); every AppKit app has a main menu; ⌘-keys reach `onInput` through
  `performKeyEquivalent`; a key a command binds is claimed after `Button`
  shortcuts and before Tab traversal.
- A root `.popover` takes the legacy `requestLayout`; a proposal-path popover
  must sit under a proposal container to be exercised (test 3.27, VX.4's first
  spelling stayed green against a root fixture).
- `PopoverModifier` is not a `StyledElement` (divergence 115): write styled
  modifiers before `.popover`.
- `Observation` must be imported explicitly off Apple (`MenusDemo.swift`, found
  by the container).
- Stale build artifacts (`Tooltip.*`) remain in the main checkout's `.build`: run
  `swift package clean` there before its next build.
- A new menu-bearing platform adds `presentMenu` and `setMenuBar` with honest
  bodies; a new handler-registering site gains an arm in the D2 guard and the
  context-menu gate (`MN-U`).

**Deferred, owner none** (spec §10; divergences "Not offered"): `Picker`,
`Section`, `Label`/image items inside a menu; `Divider` as a stack view; menu
type-select, a scrolling menu, a submenu-open delay; `.contextMenu(forSelectionType:)`
and `menuItems:preview:`; `.popover(attachmentAnchor:)`, a drawn arrow,
`.help(Text)`, a native AppKit tooltip; an in-window menu bar on SDL; Windows'
open-on-release convention. Looks owed: human-checks group R (record §03).

### §6.1 Verification at the close

Unmutated, after `swift package clean`, at the Record phase's HEAD (this commit
changes only documents and `closeout-public-api.tsv`): `swift build
--build-system native --build-tests` 0 `error:`, the one `warning:` SwiftPM's
deprecation notice; unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 2327 tests in 3 suites passed after 122.769 seconds`**, one
summary line, the `FR-J no-argument frame: succeeded=true` line present.
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
Counts **2327 / 0 / 142** as the lanes read them.

### §6.2 Branch check (2026-10-03, adversarial, `b9da519..f7d8496`)

- **Suite**: `swift package clean`, native build (0 `error:`, the one `warning:`
  SwiftPM's deprecation notice), unfiltered `swift test --build-system native
  --no-parallel`: **`Test run with 2327 tests in 3 suites passed after 124.841
  seconds`**, `FR-J no-argument frame: succeeded=true`. `swift build
  --build-tests` (default build system): 0 `warning:`, 0 `error:`. Guards: a
  `@Test`-body grep for `typecheck(`/`typecheckFile(` reads 132 → 141 (the same
  instrument at both commits; it misses one guard the lanes count, so +9 agrees
  with 133 → 142).
- **Docs**: `cmp CLAUDE.md AGENTS.md` identical; every `MN-` id cited in a
  changed file resolves to a `## MN-` heading (`MN-AI` is only the next-unused
  line); all 113 backticked names of 25+ characters added to changed `.md`
  files resolve (109 test functions, four source names). The census re-taken
  reads byte-identical to `closeout-public-api.tsv` (2206); both inventory
  scripts print nothing. **Fixed**: `docs/divergences.md`'s dated header said
  menus "added 110–114" while listing 115 — now 110–115.
- **Mutations** (each on `f7d8496`, restored from a copy, `git status --short`
  clean after, full unfiltered suite):
  - **MA** — `Window.swift`: `dispatchCommandShortcut` swapped ahead of
    `dispatchShortcut`. Reddened exactly
    `aButtonsShortcutWinsOverACommandsAndFiresOnce` (1 issue).
  - **MB** — `Frame.registerHandlers`: the contextual region inserted
    `opaque: true`. Reddened 39 tests, every one new on this branch (47
    issues): `aChosenItemRunsItsActionFromInputUnderStateDispatch`,
    `aClickOrAPressDragReleaseOnAnItemChoosesIt`,
    `aContextMenuItemsShortcutDoesNotFireWhileClosed`,
    `aContextMenuMovesNoIDAndWritesNoStateTableEntry`,
    `aCoveringPointerTargetWithoutAMenuBlocksTheMenuBeneath`,
    `aDeclinedNativeMenuOpensInWindowAtThePointer`,
    `aDisabledElementsMenuOpensWithEveryItemDisabled`,
    `aDisabledItemCannotBeChosen`,
    `aFocusedFieldsSpaceChoosesTheHighlightedInWindowItem`,
    `aHelpRegionAddsNoPointerTarget`,
    `aHiddenTooltipReturnsOnlyAfterLeavingAndReentering`,
    `aMenuActionWithAStaleTokenRunsNothing`,
    `anEmptyContextMenuPresentsNothingAndDoesNotClaimThePress`,
    `aPaintedCoverWithNoHitboxDoesNotBlockTheMenuBeneath`,
    `aPresentationOnAHigherLayerBlocksAContextMenuBeneath`,
    `aPressOutsideTheMenuDismissesItAndReachesNothingBeneath`,
    `aResizeOrLosingKeyDismissesTheInWindowMenu`,
    `aRightPressOverAContextMenuPresentsItsItemsToThePlatform`,
    `arrowKeysMoveTheHighlightOverEnabledRowsWithoutWrapping`,
    `aToggleItemWritesItsBinding`, `aTooltipAppearsAfterTheHoverDelayOfTickTime`,
    `escapeClosesTheDeepestLevelFirst`,
    `hoveringASubmenuRowOpensItAndAShallowerRowClosesIt`,
    `menuItemsResolveDisabledThroughTheEnvironmentScope`,
    `noTooltipStartsWhileAMenuIsOpen`,
    `returnChoosesTheHighlightedItemAndClosesTheMenu`,
    `rightArrowOpensASubmenuAndLeftArrowClosesIt`,
    `shiftF10AndTheMenuKeyOpenTheFocusedElementsAncestorsMenuOffApple`,
    `theInnermostContextMenuOpens`, `theInWindowMenuFlipsAndClampsInsideTheWindow`,
    `theInWindowMenuIsPublishedAndPressableUnderModalIsolation`,
    `theInWindowMenuPublishesAMenuOfMenuItems`,
    `theInWindowMenuWritesNoStateTableEntry`, `theMenuIsEvaluatedAtEachOpen`,
    `theOpenMenuIsPaintedAboveEverything`,
    `thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending`,
    `theTooltipDelayIsStampedFromTheFirstTickAfterEntering`,
    `theTooltipIsPaintedAboveEverything`, `theWindowLeavingKeyHidesTheTooltip`.
- **Pixels**: `compare.sh <scratch> b9da519 HEAD` — controls as recorded, all
  fourteen images `differing=0`, `scene identical`.
- **`Backends/SDL`** on macOS: 0 `error:`, **24 + 62** passed. **Linux**
  (`swift:6.4-noble`, OrbStack already running and left as found, `git archive`
  of `f7d8496`, `--scratch-path` inside the container): builds with 0
  `error:`/`warning:`, **199 + 22 + 21 + 31 + 18 + 6**.
- **Unmoved**: no file under `Sources/MetalUILayout`, `Sources/MetalUIScene`,
  `Sources/MetalUIShaderTypes` or either shader changed; `Expected.swift`
  unedited; the files holding `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`,
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` and
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` unedited and green.
  Pre-existing tests edited only for `Handlers`' sixteenth member
  (`HandlerShape`, `HandlerFingerprint`, the modifier table 54 → 55, the
  `Handlers` size bound +8) and the two new defaultless requirements in
  conformer fixtures.
- **Finding (code, not fixed here)**: `MN-J` item 3 routes only
  **⌘-modified** keys to the window before the main menu. A throwaway
  (uncommitted, deleted) test installed `CommandMenu` items bound to ⌃K and
  to a plain N: `NSApp.mainMenu.performKeyEquivalent` claimed both and ran
  the commands, `MetalHostView.performKeyEquivalent` declined ⌃K, and
  `NSApp.sendEvent(⌃K)` ran the menu's command without the window seeing the
  key (plain N reached the window, the menu did not fire). So on AppKit a
  command bound to a ⌃ shortcut without ⌘ (⌥ unmeasured) pre-empts a `Button` with the
  same shortcut and a focused field's editing key (⌃A, ⌃E, ⌃K…), against
  `MN-J` item 2. The window was not key in that session (locked), so the
  key-window order is AppKit's documented one, not a measurement. Fix:
  offer every key-down carrying ⌘ **or ⌃** (and ⌥, once measured) in `performKeyEquivalent`, with
  a test pinning a ⌃-key `Button` over a ⌃-key command.
