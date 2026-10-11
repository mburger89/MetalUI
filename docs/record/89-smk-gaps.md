# 89 — SMK configurator port gaps MG-23…MG-28: the drawn menu bar, `EventModifiers.primary`, design families, portable-text products, the asserts compiler, `Window.drawnChromeHeight` (item C12)

Branch `fix/smk-port-gaps` from `0b400b4` (master at the time: `GX-X`/`GX-Y` and the
`feat/controls-looks` merge); master `9ad2254` (`GX-Y`) merged at `57e02a4` (the baseline of the
lanes' counts and pixels), then master `ebcf3c7` merged at the Record phase (§10: app shell §87,
key-focus §88, shadow cache §90). **Not a plan task**: item C12 of the gpui-gap priority list
(user request 2026-10-02), reported by the SMK configurator's Linux/Windows port (C4b) as
`MG-23`…`MG-28` in its `docs/superpowers/2026-10-06-metalui-gaps.md` (read, never edited). Spec
`docs/superpowers/specs/2026-10-09-smk-gaps-design.md`; rulings `SG-A`…`SG-L` in the new decisions
doc `docs/superpowers/2026-10-09-smk-gaps-decisions.md` (next unused `SG-M`); probe
`docs/probes/swiftui-shortcut-modifiers.swift` (new). Parallel branches at the time:
`feat/app-shell` (§87, merged first), `feat/key-focus` (§88), `perf/shadow-cache` (§90) and
`feat/test-harness` (§91).

**Numbering.** This record is §89 as the design reserved it; master published §87, §88 and §90
and no 89 before the merge, so it stands. **Divergence label 195** is this branch's reserved range
195–204 (196–204 unused). **Human-checks group `SG`** (SG1…SG6), a provisional letter in the manner
of `RT`, `VL`, `WS`, `AS` and `KF`; it did not collide at the merge.

**Status: LANDED, with one deferral that became this branch's** (§9: File ▸ Close and Quit in the
drawn bar). Every agent-doable clause of the six gaps is built and verified `ok: true` in the
final re-verification (lane 1 once; lane 2 by two verifiers, the second finding only the minor `SG-L`;
lane 3 once, which also re-ran lane 2's mutations); the looks and the Windows run are owed to a human
(`docs/verification/human-checks.md` group SG, §7). A design session and a critic (`SG-H`), then
three lanes (1 → 2 sequential, 3 in parallel), each red first and each with a review round; this
Record phase merged master, re-took the suite and the counts, fixed the last verifiers' minor
findings (`SG-L`) and wrote the shared docs. The spec's Status line is marked.

## §0 What the request was, and the final spellings

Six asks; six answered, one by a documented workaround plus a fix on MetalUI's side:

| # | Gap | Answer |
|---|---|---|
| MG-23 | SDL draws no menu bar | **Built** (`SG-A`): `App.commands { … }` is drawn as a 25-point in-window bar wherever `Platform.setMenuBar(_:) -> Bool` answers `false` (SDL); divergence 195 |
| MG-24 | `.command` is Super off Apple | **Built** (`SG-B`): `EventModifiers.primary` (`.command` on Apple, `.control` elsewhere), the **default** of every `.keyboardShortcut`; honest labels in the drawn menu |
| MG-25 | no monospaced/serif/rounded families | **Built** (`SG-C`): `SystemFonts.designFamilies`, registered lazily by `SystemFonts.resolver()`; `.rounded` off Apple resolves to the default face |
| MG-26 | conditional portable products break macOS test builds | **Built** (`SG-D`): `metalui new --cross-platform` and `getting-started.md` name the two products unconditionally; the SwiftPM defect measured and its report text below |
| MG-27 | Windows release compiler assert on `Component` + `switch` | **Fixed in MetalUI** (`SG-E`): a `Component`'s prepaint record is one heap box (`ComponentPrepaint`); reduced to a 25-line standalone file; env-gated guard; upstream text below; Windows run is human check SG6 |
| MG-28 | the toolbar strip's 39 is not public | **Built** (`SG-F`): `Window.drawnChromeHeight`, and an explicit `minSize`/`maxSize` is measured below the drawn chrome |

The configurator's swap list (`SG-` decisions doc, "The final spellings"): drop the Linux/Windows-only
`.toolbar` mirror of the menus; drop `primaryShortcutModifier` (write `.keyboardShortcut("s")` or
`.primary`); drop its `register(design:family:)` calls; drop the conditional on the two products;
drop the `+ 39` from `minSize`; the `Component`/`switch` shape compiles under the asserts compiler.

## §1 What landed

**`SG-A` — the drawn menu bar** (`MenuBarStrip.swift` new, `Commands.swift`, `Window.swift`,
`Frame.swift`, `MenuSession.swift`, `MenuPanel.swift`, `App.swift`, `Platform.swift`,
`AppKitPlatform.swift`, `SDLPlatform.swift`).
`Platform.setMenuBar(_:)` now returns `Bool` — still **defaultless** (the `presentMenu`/`setToolbar`
pattern): AppKit `true` (`NSApp.mainMenu`, unchanged), SDL `false` (it still records the bar), every
fake configurable (`menuBarIsNative`, default `true`, so no existing window test moved). When the
answer is `false` and the app declared `commands`, every window of the app — open and later — draws
the bar (`Window.drawnMenuBarSource`, set in `App.openWindow`). The bar is ordinary elements under
the **named root `$menubar`** at cursor index 2 (beside the root's `(nil, 0)` and `$toolbar`'s
`(nil, 1)`), noted with `StateTable.noteNamed`; it is an element name, never a `StateTable` slot (the
seven retention slots unmoved). Geometry: a 24-point row plus a 1-point `.separator` line, filled
`.surface`, above the toolbar strip; the root is laid out below both (`Frame.computeRootLayout`).
Titles are `Text` in a measured frame + `.background` + `.onClick` + `.accessibilityLabel` +
`.accessibilityAddTraits(.isButton)` — existing modifiers only, so no new `StyledElement` site, no new
handler-registering site and no new accessibility role. A click (the release: `SG-H` item 4) opens the
menu through the existing `MenuSession` (the in-window panel, anchored under the title, the session
remembering its bar index); with a bar menu open the pointer onto another title switches, Left/Right
wrap, a press on the open title / Escape / a press outside close it. **F10** opens the first menu with
its first enabled row highlighted, as an *unclaimed-key* stage after the keymap, `onKeyPress`
(`dispatchKeyPress`, §88, `KF-C`), a focused field, the `onKey` bubble, `Button` shortcuts and the
command stage, beside Tab traversal — pinned to be where C9 left the pipeline (§10). The model's drawn
style (`MenuBarModel`, a `style:` parameter; the AppKit style byte-for-byte as before) follows the
desktop convention: no application menu; File (`.newItem`, then `.appVisibility`/`.appTermination`
additions), Edit (Undo, Redo, Cut, Copy, Paste, Delete, Select All, replaceable), every `CommandMenu`,
Window only when something is placed there, Help. A standard Edit item is **delivered as its own key**
to the focused field through `Window.deliverStandardEditKey` (the seven keys `AppKitMenus.deliverEditKey`
delivers; Delete `\u{7f}`), and is **enabled only while a text field holds focus** (`SG-H` item 1).
`App.commands(content:)` marks every window dirty when the bar is drawn (a call after `openWindow`
shows on the next frame, `SG-I` item 6). Shortcuts are unchanged: the window's command stage (`MN-J`)
is still the one shortcut path.

**`SG-B` — `EventModifiers.primary`** (`InputEvent.swift`, `KeyboardShortcut.swift`, `Button.swift`,
`Commands.swift`, `MenuPanel.swift`). `Modifiers.primary` is `.command` on Apple, `.control` elsewhere —
a name for one of the existing four bits, not a new one. It is the default of
`KeyboardShortcut.init(_:modifiers:)`, `.keyboardShortcut(_:modifiers:)` and the standard menu items
(Redo `[.primary, .shift]`; Hide Others stays `[.command, .option]`). On macOS nothing moves
(value-identical); on Linux/Windows `.keyboardShortcut("s")` fires on Ctrl+S, an explicit `.command`
stays the Super/Windows key (`SDLBridge` unchanged — Qt's re-mapping was considered and refused), and
`MenuPanel.shortcutText` now names each key honestly off Apple (Ctrl/Super or Win/Alt/Shift).

**`SG-C` — design families** (`SystemFonts.swift`). `SystemFonts.designFamilies: [FontDesign: [String]]`
and a `designFamilies:` parameter on `resolver(...)`; the first installed family of each list is
registered through `register(design:family:)` (a name, no face read until a request resolves). Lists
measured per platform (the macOS hidden `.SF NS Mono`/`.New York` are not named, so a stock Mac resolves
Menlo and Times New Roman); fontconfig's `monospace`/`serif` answer leads the Linux lists behind an
injectable query (`linuxDesignFamilies`), since CI's images have no `fc-match`.

**`SG-D` — the manifest** (`Scaffold.swift`, `docs/getting-started.md`). The defect reproduced (§12
carries the report): a product reached conditionally through the executable and unconditionally by a
test target loses the products' **C** modules from the test target's module map on the default build
system. The two portable-text products are now unconditional; the cost is +2 152 368 bytes (2.15 MB) in a
macOS release build that never calls them. The scaffold's env-gated build test gains a test target.

**`SG-E` — the asserts compiler** (`Component.swift`, `AssertsCompilerTests.swift`, `docs/packaging.md`).
Reproduced under the Mac snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a` in debug and release,
reduced by one-edit steps (`SG-E` items 7, 8) to a 25-line file with no MetalUI import; the cure measured
on it (a final class around the witness's result) became `ComponentPrepaint`: a public struct over a
`final class` holding `Content.GroupPrepaint`, made in `prepaintGroup` and mutated in place by
`paintGroup`. All five gates held (`SG-E` item 9); no migration note (an associated type no conformer
names).

**`SG-F` — `Window.drawnChromeHeight`** (`Window.swift`, `Frame.swift`). `public var drawnChromeHeight:
Pixels { get }`: the bar's 25 plus the strip's 39 as the last adopted frame laid them out; 0 where the
platform shows its own and before the first frame. An explicit `minSize`/`maxSize` is a size of the
content **below** the drawn chrome (AppKit's `contentMinSize` is below its toolbar), sent to
`setContentSizeLimits` with the chrome added on the height axis; `reconcileContentSizeLimits` now runs
under `.automatic` too, and re-sends when the chrome changes.

**Also** (`SG-J`): `Text.font(_:)` and its three siblings in `TextModifiers.swift` no longer use a
`font.map { .explicit($0) }` closure (`if let`/`else`): the menus demo's new monospaced line was the first
`Text.font(Font)` in a production tree, and its main-actor-inheriting closure trapped the 1 MB build.
The demo (`MenusDemo.swift`) gained Reset Status and a "⇧ + primary + H" line; it builds in its own
functions.

## §2 Tests and guards, per file

Counts at the lanes (native, unfiltered, after `swift package clean`): baseline `57e02a4` 2884 (master's
2879 + `GX-Y`'s 5) → lane 1 **2895** (+11) → lane 2 **2910** (+15), **2913** (+3, the verifier's pins
2.11b, 2.16b, 2.16c) → lane 3 **2915** (+2: the env-gated guard and the box pin). Two new typecheck
guards (`aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform` and `drawnChromeHeightIsReadOnly`);
`aPlatformWithoutSetMenuBarDoesNotCompile` is kept, its fixture re-spelled. The merged counts are §11.

| file | tests |
|---|---|
| `Tests/MetalUICrossPlatformTests/PrimaryModifierTests.swift` | `thePrimaryModifierIsCommandOnAppleAndControlElsewhere` (1.1) |
| `Tests/MetalUITests/KeyboardShortcutTests.swift` | `aShortcutWithNoModifiersDefaultsToThePrimaryOne` (1.2) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLPrimaryShortcutTests.swift` | `ctrlSRunsADefaultShortcutOffAppleAndSuperSDoesNot` (1.3), `anExplicitCommandStaysTheSuperKeyOffApple` (1.4) — through `mui_push_event` |
| `Tests/MetalUISystemFontsTests/SystemFontsTests.swift` | `aDesignResolvesToItsFirstInstalledFamilyAndReadsNothingUntilAsked` (1.5), `thePlatformsOwnDesignFamiliesResolve` (1.6), `fontconfigsAnswerLeadsEachDesignsLinuxList` (1.7) |
| `Tests/MetalUIScaffoldTests/ScaffoldTests.swift` | `theCrossPlatformManifestNamesThePortableTextProductsOnEveryPlatform` (1.8), env-gated `aCrossPlatformPackagesTestTargetBuildsOnMacOS` (1.9, with a generated `SmokeTests`) |
| `Tests/MetalUICrossPlatformTests/DrawnMenuBarModelTests.swift` | `theDrawnBarsStandardShortcutsUseThePrimaryModifier` (2.1) |
| `Tests/MetalUITests/MenuPanelLabelTests.swift` | `aDrawnMenusShortcutTextNamesEachKey` (2.2) |
| `Tests/MetalUITests/MenuBarStripTests.swift` (new, 15) | 2.3 `aDeclinedMenuBarIsDrawnAboveTheRootInEveryWindow`, 2.4 `anAppWithoutCommandsDrawsNoMenuBar`, 2.5 `aMenuBarThePlatformShowsIsNotDrawn`, 2.7 `clickingATitleOpensItsMenuBelowItAndAChoiceRunsTheCommand`, 2.8 `hoveringAnotherTitleWhileOpenSwitchesAndArrowsWrap`, 2.9 `thePressedOpenTitleAndEscapeCloseTheMenu`, 2.10 `f10OpensTheFirstMenuOnlyWhenNothingClaimsIt`, 2.11 `aDrawnEditItemReachesTheFocusedField`, 2.11b `everyDrawnEditRowDeliversItsKey`, 2.12 `aCommandShortcutStillRunsOnceWithADrawnBar`, 2.14 `theMenuBarAndTheToolbarStripStackAboveTheRoot`, 2.15 `aMenuBarTitleIsAnAccessibleButton`, 2.16 `theDrawnBarsTitlesFollowTheCommandsLive`, 2.16b `aCommandsObservableWriteOutsideInputRedrawsTheBar`, 2.16c `commandsDeclaredAfterOpenWindowDrawTheBarOnTheNextFrame` |
| `Tests/MetalUITests/CommandsTests.swift` | 2.6 `theDrawnBarFollowsTheDesktopArrangement` |
| `Tests/MetalUITests/ExplicitIdentityTests.swift` | 2.13 an arm `$menubar` in `everyNamingSiteStartsAReturningNameFresh` (the titles' keying, `SG-I` item 1) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLMenuBarTests.swift` | 2.17 `sdlDeclinesTheMenuBarAndRecordsIt`, 2.18 `anSDLWindowDrawsTheCommandsAndAClickRunsOne` (a real window's click path) |
| `Tests/MetalUITests/WindowSizingTests.swift` | 2.19 `drawnChromeHeightIsTheBarPlusTheStrip`, 2.20 `anExplicitMinimumIsMeasuredBelowTheDrawnChrome` |
| `Tests/MetalUITests/MenuBarCompileGuards.swift` (new) | 2.21a `aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform` (plain-import `typecheckFile`: `Void` refused, `-> Bool` accepted) |
| `Tests/MetalUITests/ChromeHeightCompileGuards.swift` (new) | 2.21b `drawnChromeHeightIsReadOnly` (read compiles, write refused) |
| `Tests/MetalUIScaffoldTests/AssertsCompilerTests.swift` (new) | 3.2 env-gated `theComponentSwitchShapeAgainstAnAssertsCompiler` (`METALUI_RUN_ASSERTS_COMPILER_TEST=1`; six builds: LKX, MG27, Workaround in debug and release, plus the standalone reduction as the positive control) |
| `Tests/MetalUITests/ComponentPrepaintBoxTests.swift` (new) | 3.3 `aComponentsPrepaintIsHeldOnceAndMutatedInPlace` |
| `Tests/MetalUITests/Fakes.swift`, `AppIconCompileGuards.swift`, `CommandsCompileGuards.swift`, `SDLLifecycleTests.swift` | the conformers' `setMenuBar` answers `Bool` (`FakePlatform` gains `windowSize`, `windowsShowToolbars`, `menuBarIsNative`) |

The env-gated tests are now **fifteen** (`SG-H` item 7); they count while skipped.

## §3 Probes

`docs/probes/swiftui-shortcut-modifiers.swift` (new; recorded 2026-10-09): SwiftUI's default shortcut
modifier is `.command` (raw 16); there is **no** `.primary` or `.platform` member (the `PRIMARY` and
`PLATFORM` separating arms are refused by the compiler, and the default build compiles). The critic
re-ran it: stdout and both refusals byte-identical to the header (`SG-H`). `swiftui-commands.swift`
(`MN-I`'s) is the AppKit menu bar SwiftUI builds, which `SG-A`'s drawn style departs from on purpose;
nothing in SwiftUI answers the question off Apple. The asserts reduction is not a SwiftUI probe: it is
`standaloneFixture` in `AssertsCompilerTests.swift` (25 lines, no MetalUI import), with the one-edit
tables in `SG-E` items 7–8.

## §4 Red runs

Each lane committed its tests red before the change: `c98c0cb` (lane 1: primary modifier, labels, design
families, portable products, drawn chrome), `5a3ddb6` (lane 2: the drawn menu bar), `3c566bd` (lane 3: the
asserts-compiler guard, red with four assertion issues at `AssertsCompilerTests.swift:229`).

## §5 Mutation tables

Every mutation: source restored from a copy, full unfiltered suite, `git status --short` empty after.
`CI-AF`'s five `AppKitPresentationTests` sheet issues appear on a locked or asleep screen only and are
not counted below.

**Lane 1 (verifier, on `980663e`, ok).**

| mutation | reddened |
|---|---|
| M1.2 `Button.keyboardShortcut` default `.primary` → `.option` | 14 tests incl. `aShortcutWithNoModifiersDefaultsToThePrimaryOne`, `aButtonsShortcutWinsOverACommandsAndFiresOnce`, `aCommandMenuIsInsertedBeforeTheWindowMenu`, `commandGroupsPlaceTheirItemsBeforeAfterAndReplacing` (31 issues) |
| M1.2b `KeyboardShortcut.init` default → `.option` | `thePrimaryModifierIsCommandOnAppleAndControlElsewhere` |
| M1.1 `Modifiers.primary` non-Apple `.control` → `.command` (noble) | `thePrimaryModifierIsCommandOnAppleAndControlElsewhere` |
| M1.3 same, Linux image, `Backends/SDL` | `ctrlSRunsADefaultShortcutOffAppleAndSuperSDoesNot` |
| M1.4 `SDLBridge.c mods()` maps CTRL to COMMAND (macOS 24 + 100, Linux image 24 + 97) | `anExplicitCommandStaysTheSuperKeyOffApple`, `ctrlSRunsADefaultShortcutOffAppleAndSuperSDoesNot` |
| M1.5a design loop skipped / M1.5b last installed / M1.5c `families.first` uninstalled | `aDesignResolvesToItsFirstInstalledFamilyAndReadsNothingUntilAsked`, `thePlatformsOwnDesignFamiliesResolve` each |
| M1.6 `designFamilies` `[:]` (macOS spelling; Linux spelling in noble) | `thePlatformsOwnDesignFamiliesResolve` |
| M1.7 fontconfig's answer appended after the fixed list | `fontconfigsAnswerLeadsEachDesignsLinuxList` |
| 1.8 `condition:` restored on the two products | `theCrossPlatformManifestNamesThePortableTextProductsOnEveryPlatform`, `crossPlatformNoLongerNeedsALocalCheckout`, `theLocalCrossPlatformManifestNamesNoBackendsSDLPackage` |
| 2.19 strip arm `drewToolbarStrip ? 0 : 0` | `drawnChromeHeightIsTheBarPlusTheStrip`, `anExplicitMinimumIsMeasuredBelowTheDrawnChrome` |
| 2.20 limits sent unadjusted | `anExplicitMinimumIsMeasuredBelowTheDrawnChrome` |
| `SG-F` item 3, `reconcileContentSizeLimits()` back inside `if windowResizability != .automatic` | `anExplicitMinimumIsMeasuredBelowTheDrawnChrome` (`WindowSizingTests.swift:414`, `:423`) |
| 2.21b `drawnChromeHeight` made settable | `drawnChromeHeightIsReadOnly` |

**Lane 2.** Guard 2.21a, mutated red once on `b1b7918` (a protocol-extension default `func
setMenuBar(_:) -> Bool { true }`): `aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform` (void and
answering both `succeeded=true`) and `aPlatformWithoutSetMenuBarDoesNotCompile`. The first verifier
(`fa5ff84`) found five instruments that could not fail (`SG-K`); the fixer's `1dec007` answered them; the
second verifier re-ran every one on `1dec007` (2913 tests):

| mutation | reddened |
|---|---|
| M2.11b Copy delivered as primary+X | `aDrawnEditItemReachesTheFocusedField`, `everyDrawnEditRowDeliversItsKey` |
| M2.11d Delete delivered as `\u{8}` | `everyDrawnEditRowDeliversItsKey` |
| M2.11e Undo delivered as primary+shift+Z | `everyDrawnEditRowDeliversItsKey` |
| M2.10c `key.modifiers.isEmpty` removed from `dispatchMenuBarKey` | `f10OpensTheFirstMenuOnlyWhenNothingClaimsIt` (3 issues: shift, control, option) |
| M2.16b titles moved out of `withObservationTracking` | `aCommandsObservableWriteOutsideInputRedrawsTheBar` |
| M2.16c `App.commands`' `setNeedsRedraw()` loop removed | `commandsDeclaredAfterOpenWindowDrawTheBarOnTheNextFrame` |
| M2.15 drop `.accessibilityAddTraits(.isButton)` | nothing — **equivalent** (`SG-K`) |
| M2.15b drop `.onClick { open(index) }` | five click tests (`aDrawnEditItemReachesTheFocusedField`, `clickingATitleOpensItsMenuBelowItAndAChoiceRunsTheCommand`, `everyDrawnEditRowDeliversItsKey`, `hoveringAnotherTitleWhileOpenSwitchesAndArrowsWrap`, `thePressedOpenTitleAndEscapeCloseTheMenu`) but **not 2.15** — also equivalent for 2.15 (`SG-L`) |
| M2.15c drop both | 2.15 `aMenuBarTitleIsAnAccessibleButton` plus the five (13 issues) |

The third verifier (lane 3's, on `d55b162`) re-ran M2.11b, M2.11d, M2.11e, M2.10c, M2.16b and M2.16c with
the full suite and read each reddened as above.

**Lane 3 (verifier, `d55b162`, ok).**

| mutation | reddened |
|---|---|
| M3.2 un-box: `prepaintGroup`/`paintGroup` back to `Content.GroupPrepaint` (env-gated run only; the macOS suite stays green — no macOS test can see it) | `theComponentSwitchShapeAgainstAnAssertsCompiler`, four issues: LKX and MG27 assert in debug and in release; Workaround compiles; the standalone control asserts |
| M3.3 `withPrepaint` runs `body` on a copy | `aComponentsPrepaintIsHeldOnceAndMutatedInPlace` |

The positive control was re-run by the verifier: `xcrun --toolchain org.swift.64202605271a swiftc` on the
standalone file asserts at `TypeLowering.cpp:3390`; wrapping the witness's result in a struct over a final
class compiles clean; the release (non-asserts) compiler compiles the unwrapped file.

## §6 Green mutations and pins that prove less than they look

- **M2.15 and M2.15b are equivalent for 2.15.** The title's role has two sources — the `.isButton` trait and
  the clickable record (`AccessibilityTreeBuilder.resolveText`'s `isButtonLike`) — so 2.15 reddens only
  when both go. `SG-K` item 1 named M2.15b as the separating mutation, and was wrong; `SG-L` corrects it
  in the test's doc comment, the spec and `SG-K`. 2.15 is not widened: a press-action assertion would
  only re-pin the five click tests.
- **M2.13** (drop the `$menubar` root's `noteNamed`) is expected green and recorded: `$menubar` is one
  fixed name at its own position, so `noteNamed` departs nothing and no arm can see it (`MD-Z` item 1's
  finding for `$toolbar`). 2.13's arm pins the **titles' keying** instead (M2.13b, titles keyed by index
  alone, reddens it).
- **The Windows run of the asserts guard is unpinned by anything an agent can run**: the guard launches
  `/usr/bin/env` and so runs on macOS and Linux only; Windows CI's 6.4.0+Asserts compiler is human check
  SG6. The UTM VM did not answer on 2026-10-10 (`ssh metalui-win` timed out; `utmctl list` reads
  `stopped`; it was not started).
- **Un-boxing is invisible to every macOS test** (M3.2): only the env-gated guard under an asserts
  toolchain reddens. The box pin 3.3 pins the mutation-in-place, not the crash cure.
- **The drawn bar's look, a real pointer and keyboard on a desktop, the monospaced face on screen and a
  Windows release build** are seen by nothing headless (§7).

## §7 Demo comparison and looks

**Pixels.** The fourteen offscreen images (`docs/probes/demo-pixels/compare.sh <scratch> <base>
<head>`) read **0 differing pixels, every scene identical, in every step**: `57e02a4` → `b1b7918` (lane
2), `0b400b4` → `1dec007` and → `d55b162` (lane 3; controls 1048576 / 1031003 / 454895 / 0 / 1048576 / 0 /
544 / 216 / 491221 / 529 / 0). No window there has an `App`, so none draws a bar, and no default shortcut
is drawn. The merged tree against master `ebcf3c7` is §11.

**Looks owed to a human** (`docs/verification/human-checks.md` group SG, SG1…SG6), also record §03:
the bar's look and its menus on Linux/Windows (SG1), Ctrl+Shift+H and the honest labels (SG2), the Edit
items on a focused field (SG3), the monospaced face (SG4), the bar and a toolbar together and the minimum
size (SG5), a Windows ARM64/x64 release build (SG6).

## §8 Hazards

- **A third-party `Platform` conformer no longer compiles** until `setMenuBar` answers `Bool`
  (`docs/migration.md`, `SG-A` item 1); pinned by guard 2.21a. A conformer that shows a bar itself answers
  `true`.
- **On Linux/Windows a shortcut written without modifiers moved from Super to Ctrl** (`SG-B`;
  `docs/migration.md`). macOS is value-identical.
- **A `minSize` that added the strip's 39 on SDL now double-counts** (`SG-F`; `docs/migration.md`).
- **`Text.font(_:)` closures**: `SG-J` — a closure in a modifier body inherits the main actor and checks its
  executor; the 1 MB harness builds trees on a secondary thread with the isolation cast away. A future
  production tree reaching another such closure traps `everyProductionTreeBuildsOnAOneMegabyteThread` with
  `SIGTRAP`; the backtrace names the closure.
- **A single scratch directory for the asserts guard would race across worktrees** — fixed (`SG-L`): the
  directory name carries a hash of the checkout path.
- **SwiftPM (MG-26) and Swift (MG-27) are toolchain defects**; neither is fixable inside MetalUI beyond the
  two measures above. `CLAUDE.md`'s CI hazards line for the asserts compiler is updated: with
  `ComponentPrepaint` a `Component` whose content is a loop, nested inside another `Component`, now
  compiles under 6.4.0+Asserts; code with its own protocols of the same shape still needs `LK-X`'s
  function remedy.
- **Stale claims fixed in passing** (`SG-K` item 5): `docs/api-overview.md`, `docs/migration.md` and the
  inventory map's `menu-bar` family row said SDL draws no bar.

## §9 Deferrals, with owners

- **File ▸ Close and Exit/Quit in the drawn bar** (`SG-A` item 11a) — **resolved** (`SG-M`, §14). C8 (§87)
  merged first, so the work was this branch's.
- Alt-alone activation and `&` mnemonics; a native Win32 `HMENU`; Window ▸ Minimize/Zoom on SDL — owner none
  (`SG-A` item 11).
- A menu-bar accessibility role (VoiceOver/Narrator read the titles as buttons) — owner none (`SG-A` item 7).
- A `"primary"` token in `Keymap`'s keystroke parser — owner none, a later keymap item (`SG-B` item 7); C9
  has merged and does not add it.
- A rounded face off Apple — none ships (`SG-C` item 3); owner none.
- Filing the SwiftPM (§12) and Swift (`SG-E` item 11) reports upstream — a human files them.
- The Windows run of the asserts guard and of the SMK configurator's release build — human check SG6.
- Client-side window decorations are `AS-E` item 6's deferral and not this branch's.

## §10 Merge with master (2026-10-10, `ebcf3c7`)

Master moved past `0b400b4` by 94 commits (controls-looks §85, app shell §87, key-focus §88, shadow cache
§90 among them). Conflicts, all textual and additive:

- `Sources/MetalUI/App.swift`: master's `adoptShell(window, platformWindow)` replaces the old close wiring;
  this branch's `window.drawnMenuBarSource = drawnMenuBarSource()` stays above it. `windows` keeps master's
  doc comment and `shell` state.
- `Sources/MetalUIPlatform/Platform.swift`: `setMenuBar(_:) -> Bool` with `SG-A`'s documentation, followed by
  master's four app-shell requirements.
- `Backends/SDL/Tests/.../SDLLifecycleTests.swift`: the wrapper forwards `setMenuBar -> Bool` and master's
  four app-shell members.
- `docs/divergences.md` (195 beside master's 205), `docs/packaging.md` (this branch's §4 "Release builds
  and the asserts compiler" and master's "Documents and URLs" section), `docs/verification/human-checks.md`
  (groups SG and KF both kept), `docs/probes/closeout-inventory-map.tsv` (the `primary-modifier` row beside
  `app-shell-seam`), `closeout-public-api.tsv` (taken from master then **regenerated**, never hand-merged).

C9 changed the key pipeline (`dispatchAction`, `dispatchKeyPress`); F10's `dispatchMenuBarKey` still sits
after `dispatchCommandShortcut` and before `dispatchFocusTraversal`, i.e. after `onKeyPress` as `SG-H`
asked, and `KF-X` (an app command's key is declined by `onKeyPress` and runs the command) reads
`commandShortcuts`, which `SG-A` leaves unchanged. **Merge pins** (conformer fixtures that each branch's tests spell
without the other's requirement; found by the first merged run, 3235 tests with exactly two issues, both
typecheck fixtures): `AppShellSeamCompileGuards`' `platformConformer` now answers `setMenuBar -> Bool`,
`MenuBarCompileGuards`' `conformer` carries `AS-H`'s four requirements, and the four `Backends/SDL`
`Platform` wrappers (`SDLLifecycleTests`', resolved in the conflict; `SDLPrimaryShortcutTests`' and
`SDLMenuBarTests`', this branch's; `SDLAppShellAppTests`', master's) forward the `Bool` and the four
requirements. The Linux image
and macOS SDL runs compile them (§11). A clause both tracks share can be pinned by neither; these were
the merge's owed tests.

## §11 Counts on the merged tree (2026-10-10)

**`fix/smk-port-gaps` merged with master `ebcf3c7`** (`8bff55d`, then the merge pins' two commits):

- **3235 tests, 0 goldens, 205 typecheck guards** — master's 3204 + the branch's 31 tests (11 + 15 + 3 + 2
  at the lanes, §2), 203 + 2 guards (`aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform`,
  `drawnChromeHeightIsReadOnly`; counted as `canTypecheck(module:` occurrences under `Tests`, 205 at
  master, 207 here; both new ones ran in the merged run: `SG-A setMenuBar answers: void succeeded=false`,
  `SG-F drawnChromeHeight write: succeeded=false`). Native unfiltered `--no-parallel` on an **unlocked**
  screen: "Test run with 3235 tests in 3 suites passed after 265.071 seconds", `FR-J no-argument frame:
  succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `swift build --build-tests`
  (default build system) 0 warnings. (The first merged run read 3235 with the two fixture issues above.)
- **Census 3139** (master's 3134 + five declarations: `struct ComponentPrepaint`,
  `Window.drawnChromeHeight`, `Modifiers.primary`, `SystemFonts.designFamilies`,
  `installMenusDemoCommands`), regenerated after the merge, never hand-merged;
  `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- **`Backends/SDL`**: 24 + 111 on macOS (master 24 + 108, + `SDLPrimaryShortcutTests`' two and the menu-bar
  test's one); 24 + 108 in the `metalui-portable` Linux image (the three macOS-only tests excluded; its one
  `warning:` is master's `AccessKitControlsParityTests.swift:83`, an unnecessary `try`). Root in
  `swift:6.4-noble`: 9 + 38 + 21 + 199 + 78 + 22, all passed, 0 warnings or errors.
- **Pixels**: the fourteen offscreen images, master `ebcf3c7` → this branch (`4650edb`): **0 differing
  pixels, every scene identical**; controls as recorded (1048576 / 1031003 / 454895 / 0 / 1048576 / 0 /
  544 / 216 / 491221 / 529 / 0). `DemoFrameDeterminismTests`' `Expected.swift` is unedited (Linux and
  Windows CI confirm on push).
- Divergences **134 live, next label 206** (195 added; 196–204 of C12's range unused).
- **Not run**: the UTM Windows VM (timed out, human check SG6); any real-window capture (no capture was
  needed to land; the looks are group SG).

## §12 The upstream report text

**SwiftPM (MG-26; for swiftlang/swift-package-manager; not filed from here).**

> **Title:** `swift build --build-tests` on the default build system drops a conditionally-reached
> product's C module dependencies from a test target's module map
>
> **Setup:** an executable target depends on product `P` with `condition: .when(platforms: [.linux,
> .windows])`; a test target of the same package depends on `P` unconditionally; `P`'s targets import C
> modules (`CFreeType`, `CHarfBuzz`, `CSheenBidi`, `CUnibreak`). Building on macOS.
>
> **Result (default build system):** `error: unable to resolve module dependency: 'CFreeType'` (and the
> same for the other three), reported as a `clang dependency scanning failure` in `SwiftDriver
> SmokeTests`. `--build-system native` builds; making `P` unconditional on the executable builds on both.
>
> **Measured** at this repository's `c98c0cb` + the fix, Xcode-beta's toolchain, in a scratch package
> generated by `metalui new Smoke --cross-platform --local <checkout>` plus a `SmokeTests` target. A
> macOS `swift build -c release --product Smoke` is 8 554 184 bytes with the conditional products and
> 10 706 552 with the unconditional ones.

**Swift (MG-27, `LK-X`; for swiftlang/swift; not filed from here).** The full text — title, toolchains,
the 25-line reproduction, the assertion and frames, the narrowing — is `SG-E` item 11 in
`docs/superpowers/2026-10-09-smk-gaps-decisions.md`.

## §13 Branch checker (2026-10-10, `54dda21`)

Adversarial check of `0b400b4..54dda21`, the branch's own change read as `ebcf3c7..54dda21`.

- **Lane 2's verifier issues are resolved by `1dec007`.** M2.11b is caught by 2.11's added `model.text
  == "abc"` expectation. The seven Edit keys are pinned by 2.11b `everyDrawnEditRowDeliversItsKey`.
  F10 with a modifier is pinned by 2.10's added Shift, Control and Option arm. The observed titles
  and late commands are pinned by 2.16b `aCommandsObservableWriteOutsideInputRedrawsTheBar` and 2.16c
  `commandsDeclaredAfterOpenWindowDrawTheBarOnTheNextFrame`. M2.15 is recorded as equivalent
  (`SG-K`, `SG-L`). The api-overview, migration and inventory-map rows describe the drawn bar.
  `MenuBarStrip.swift`'s F10 guard reads `key.modifiers.isEmpty`; the stray mutation is gone.
- **Suite.** After `swift package clean`, the native build has 0 `error:`, and its one `warning:` is
  SwiftPM's deprecation notice. The unfiltered native `--no-parallel` run read "Test run with 3235
  tests in 3 suites passed after 256.065 seconds", with `FR-J no-argument frame: succeeded=true`,
  `SG-A setMenuBar answers: void succeeded=false` and `SG-F drawnChromeHeight write:
  succeeded=false`. The default build system's `swift build --build-tests` has 0 warnings. There are
  207 `canTypecheck(module:` occurrences against master's 205, and 0 goldens. `cmp CLAUDE.md
  AGENTS.md` matches. The inventory and undocumented checks print nothing. Every `SG-` id cited in a
  changed file resolves (`SG-A`…`SG-L`, next `SG-M`). Every test name cited in an added doc line
  resolves, except `sdlRecordsTheMenuBarAndDrawsNothing`, which is cited as the test `SG-A` replaced.
- **Unchanged.** `theSevenRetentionSlotsAreMutuallyDistinct`, `everyNamingSiteStartsAReturningNameFresh`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`
  and `everyProductionTreeBuildsOnAOneMegabyteThread` all pass. The branch edits no hit-testing,
  accessibility-builder, animation or focus source. No existing test assertion was removed except
  the ones the rulings moved (`SG-A`'s S2.1 rewrite, `SG-D`'s manifest expectations, the `Void`
  `setMenuBar` fixtures). `MetalUILayout` imports only `MetalUICore`, and `MetalUIScene` imports only
  `MetalUIShaderTypes`.
- **Pixels.** `compare.sh <scratch> ebcf3c7 HEAD` gives 0 differing pixels and an identical scene in
  all fourteen images. The controls read 1048576 / 1031003 / 454895 / 0 / 1048576 / 0 / 544 / 216 /
  491221 / 529 / 0.
- **SDL and Linux.** `Backends/SDL` on macOS passes 24 + 111. The `metalui-portable` Linux image passes
  24 + 108. Root in `swift:6.4-noble` passes 9 + 38 + 21 + 199 + 78 + 22; that build was incremental on
  the slug volume.
- **The checker's mutations** (full unfiltered native suite each, restored from a copy, `git status`
  clean after each):
  - **MX1** set `MenuBarStrip.rootIndex` from 2 to 0, the window root's own position. The suite
    stayed green, 3235 passed. Like M2.13, this is equivalent under `noteNamed`. `$menubar` is
    produced every frame it is noted, so a position it shares with another name departs nothing that
    is not produced elsewhere. `SG-I` item 1's "(nil, 2)" is a convention and no test can see it.
  - **MX2** made `SystemFonts.resolver` pick a design's *last* installed family
    (`families.reversed()`). It reddened `aDesignResolvesToItsFirstInstalledFamilyAndReadsNothingUntilAsked`
    and `thePlatformsOwnDesignFamiliesResolve` (6 issues).
- **Doc defect fixed.** `Package.swift`'s comment on `MetalUISystemFonts` listed its imports without
  `MetalUITextSystem`, which `SG-C` added for `FontDesign`. It is a comment only.
- *(Owed then, done in §14:)* File ▸ Close and Quit in the drawn bar (`SG-A` item 11a).
- **Not run.** The Windows VM and real-window capture. The looks are human-checks group SG.

## §14 File ▸ Close and Quit/Exit in the drawn bar (`SG-M`, 2026-10-10)

`SG-A` item 11a, owed by §9. The drawn File menu is now `.newItem` additions, `.appVisibility` additions,
**Close**, the `.appTermination` group (standard item **Quit**, **Exit** under `#if os(Windows)`), its
additions. `Window.openMenuBarMenu` handles `.close`/`.quit` before the Edit key delivery: Close runs
`performClose()` (asks `onCloseRequest`; disabled once the window is closed), Quit a new internal
`DrawnMenuBarSource.terminate` closure (`App.terminate()`, the terminate-request walk). No shortcut is shown.
File is never empty now, so the bar's first title is File: nine existing `MenuBarStripTests` indices moved
(Edit 0 → 1, Tools 1 → 2, F10 opens File) and `theDrawnBarFollowsTheDesktopArrangement` gained File lines and
a `replacing: .appTermination` arm. No public declaration changed.

New tests: `theDrawnFileMenusCloseAsksTheWindowFirst` (2.17: `.cancel` keeps the fake window open with the
handler asked once, `.now` closes it; never a real `performClose(_:)`, `AS-O` item 7) and
`theDrawnFileMenusQuitRunsTheTerminateWalk` (2.18: `onTerminateRequest` asked, `.cancel` leaves
`platform.terminateCalls` 0, `.now` makes it 1).

**Asserts guard** (lane 3's two minors, finished): the scratch directory already carried a hash of the
checkout path (djb2 over the UTF-8 bytes, deterministic); on Windows the guard now finds `swift.exe` on
`PATH` (split at `;`) and launches it directly. It compiles there and has never run: human check `SG6`.
`docs/packaging.md` says so.

**Mutations** (full unfiltered `swift test --build-system native --no-parallel`, 3237 tests each, source
restored from a copy after each):

| Mutation | Reddened (tests) |
|---|---|
| M14.1 drop the Close group from the drawn File menu (`[newItem, visibility, closeGroup, termination]` without `closeGroup`) | `theDrawnFileMenusCloseAsksTheWindowFirst`, `theDrawnBarFollowsTheDesktopArrangement`, `f10OpensTheFirstMenuOnlyWhenNothingClaimsIt`, `hoveringAnotherTitleWhileOpenSwitchesAndArrowsWrap` (7 issues) |
| M14.2 Close runs `close()` instead of `performClose()` | `theDrawnFileMenusCloseAsksTheWindowFirst` (2) |
| M14.3 swap the two actions (Close → `terminate`, Quit → `performClose`) | `theDrawnFileMenusQuitRunsTheTerminateWalk` (2); the Close test stays green — the terminate walk also asks the window's `onCloseRequest` and a `.cancel` answers the same, then `.now` closes the window |
| M14.4 Quit outside the `.appTermination` group (`termination = quit`) | `theDrawnBarFollowsTheDesktopArrangement` (2: the `replacing` arm) |

**Counts**: 3237 tests (3235 + 2), 0 goldens; guard count measured in the final run below. The human check
is `SG7`.

