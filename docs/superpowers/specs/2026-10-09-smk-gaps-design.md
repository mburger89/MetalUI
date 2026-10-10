# SMK configurator port gaps MG-23…MG-28 — design

C12 of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**). Branch `fix/smk-port-gaps` from `0b400b4`, master `9ad2254` (GX-Y) merged at
`57e02a4` — **the baseline for counts and pixels is `57e02a4`** (`SG-H` item 6), worktree
`~/Developer/worktrees/MetalUI/smk-gaps`. Rulings `SG-A`…`SG-G` in
[`../2026-10-09-smk-gaps-decisions.md`](../2026-10-09-smk-gaps-decisions.md)
(read them first: this spec is the build plan, the rulings are the reasons).
Record `docs/record/89-smk-gaps.md` (Record phase). Source of the gaps: the
configurator's `docs/superpowers/2026-10-06-metalui-gaps.md`, `## MG-23`…
`## MG-28` (read only).

## 1. Scope

| gap | what lands | ruling | lane |
| --- | --- | --- | --- |
| MG-23 SDL draws no menu bar | the drawn menu bar; `Platform.setMenuBar(_:) -> Bool` | `SG-A` | 2 |
| MG-24 `.command` is Super off Apple | `EventModifiers.primary`, the default; honest labels | `SG-B` | 1 (modifier, defaults, drawn-menu labels), 2 (the drawn bar's standard items) |
| MG-25 no monospaced/serif family | `SystemFonts.designFamilies`, registered lazily | `SG-C` | 1 |
| MG-26 conditional products break macOS test builds | unconditional portable-text products in the scaffold and getting-started; a build-test arm | `SG-D` | 1 |
| MG-27 asserts compiler on `Component` + `switch` | reduction; a measured `Component` change or the documented workaround; an env-gated guard; upstream text | `SG-E` | 3 |
| MG-28 strip height not public | `Window.drawnChromeHeight`; explicit limits below drawn chrome | `SG-F` | 1 (the strip), 2 (adds the bar) |

Deferred (named, with reason and owner) in §8.

## 2. SwiftUI's answers (probed) and the other evidence

- **Shortcut modifiers** — `docs/probes/swiftui-shortcut-modifiers.swift`
  (new, recorded 2026-10-09): SwiftUI's default is `.command` (16); no
  `.primary`/`.platform` member (separating arms refused). `SG-B`.
- **The menu bar** — `docs/probes/swiftui-commands.swift` (`MN-I`): the AppKit
  bar; SwiftUI has no off-Apple bar. The drawn bar's arrangement is the desktop
  convention (`SG-A` item 3), not a SwiftUI claim. gpui (recalled, not
  measured, nothing rests on it): Zed draws its menus itself on Linux/Windows.
- **Fonts** — no SwiftUI claim: the design → family mapping off Apple is the
  platform's (CoreText's answer on macOS is TE-C's, unchanged). CI images:
  DejaVu Sans/Sans Mono/Serif present, no `fc-match` (measured).
- **MG-26, MG-27** — toolchain defects; measured by lanes 1 and 3.

## 3. Design

### 3.1 `EventModifiers.primary` (lane 1, `SG-B` items 1–4, 6)

- `Sources/MetalUIPlatform/InputEvent.swift`: in `Modifiers`,
  `public static let primary: Modifiers` = `.command` under
  `#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)` (the
  split `TextEditing.platform` uses), else `.control`. Doc comment says: ⌘ on
  macOS, Ctrl on Linux and Windows; the default of every shortcut; `.command`
  is the Super/Windows key off Apple.
- `Sources/MetalUI/KeyboardShortcut.swift:79` and
  `Sources/MetalUI/Button.swift:199`: `modifiers: EventModifiers = .primary`;
  their doc comments name the default.
- Inventory: one **M** row (`Modifiers.primary`); census re-recorded.
- Lane 1 writes **no** migration text; lane 2 writes `SG-B`'s migration
  paragraph (decisions doc) into `docs/migration.md`.

### 3.2 Design families (lane 1, `SG-C`)

- `Sources/MetalUISystemFonts/SystemFonts.swift`:
  - `public static var designFamilies: [FontDesign: [String]]` (per-platform
    lists, `SG-C` item 2; Linux's lists lead with fontconfig's answers for
    `monospace`/`serif`).
  - `resolver(directories:defaultFamilies:fallbackFamilies:designFamilies:load:)`
    — the new parameter before `load`, defaulting to `designFamilies`. After
    the existing registration loops: for each design, the first family with an
    installed face (`ordered.first { $0.isFamily(family) }`) →
    `resolver.register(design:family:)` with **that face's own family
    spelling**. No load.
  - `fontconfigSansSerif()` → `fontconfigFamily(_ generic: String)`; the
    Linux lists are built by an internal
    `static func linuxDesignFamilies(fontconfig: (String) -> String?) -> [FontDesign: [String]]`
    compiled on every platform (tested everywhere), `designFamilies` calling it
    with the real query on Linux.
  - The doc comment of `designFamilies` says `.rounded` has no family off
    Apple and resolves to the default face.
- Lane 1 measures each list's names with `FreeTypeFaceNames.read` on macOS
  (`/System/Library/Fonts` and `Supplemental`) and in `swift:6.4-noble`, and on
  the UTM VM when reachable (else the Windows names stand as Microsoft's
  documented family names, said so in the record).
- `MetalUISystemFonts` keeps its imports (Foundation, `MetalUIFreeType`,
  `MetalUIPortableText`; `FontDesign` comes through `MetalUIPortableText`'s
  re-export or an added `MetalUITextSystem` import — the lane picks the one
  that builds on Linux without a new manifest dependency, or adds the
  dependency to the portable list, `PC-A`).
- Inventory: one **M** row (`SystemFonts.designFamilies`); the `resolver`
  row's spelling changes in the census.

### 3.3 The manifest (lane 1, `SG-D`)

- **Measure first** (record verbatim): a scratch package (in the scratchpad)
  shaped as `metalui new --cross-platform --local <this checkout>` plus
  `.testTarget(name: "AppTests", dependencies: ["App", .product(name:
  "MetalUIPortableText", …), .product(name: "MetalUISystemFonts", …)])` with
  one file importing both and constructing a `PortableTextSystem`;
  `swift build --build-tests` on macOS with the default and the native build
  system, conditional vs unconditional. Then the release binary size of the
  generated app (no test target) with and without the condition.
- `Sources/MetalUIScaffold/Scaffold.swift:252-254`: `MetalUISDL` keeps
  `condition: \(portable)`; the other two lose it. A comment above them names
  `SG-D` and the defect in one line.
- `docs/getting-started.md:107-109` likewise, plus two sentences (`SG-D` item 2).
- `docs/packaging.md` is **lane 3's** (not touched here).
- If the defect does not reproduce: `SG-D` item 4 — only the test arm (1.9)
  lands; the ruling is amended in the same commit.

### 3.4 The drawn menu bar (lane 2, `SG-A`)

Files: `Sources/MetalUIPlatform/Platform.swift` (requirement),
`Sources/MetalUIAppKit/AppKitPlatform.swift` (`return true`),
`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift` (`return false`, still
records; doc comment rewritten), `Sources/MetalUI/Commands.swift`
(`MenuBarModel(entries:appName:style:)`, `enum MenuBarStyle { case appKit,
drawn }`; `installMenuBar` keeps the answer; `commands(content:)`'s doc
comment), `Sources/MetalUI/App.swift` (hand each window its bar source, as
`commandShortcuts` is handed today), new `Sources/MetalUI/MenuBarStrip.swift`
(geometry, element, `Frame.requestMenuBarStrip`), `Sources/MetalUI/Frame.swift`
(request/lay out/prepaint/paint the bar beside the strip;
`computeRootLayout(root:toolbarStrip:menuBar:)` with `top = bar + strip`),
`Sources/MetalUI/Window.swift` (titles per build, title frames, F10 stage,
standard Edit delivery, `drawnChromeHeight`), `Sources/MetalUI/MenuSession.swift`
(`barIndex`, hover switching, Left/Right), `Sources/MetalUI/MenuPanel.swift`
(labels, `SG-B` item 5).

1. **Seam.** `func setMenuBar(_ menuBar: PlatformMenuBar) -> Bool` (doc
   comment: `true` shown by the platform, `false` drawn by MetalUI; the
   migration line). `App` stores `menuBarIsDrawn = !platform.setMenuBar(…)`.
2. **Window side.** `App.openWindow` sets on each window a source:
   `drawnMenuBar: (() -> [PlatformMenu])?` (nil unless `menuBarIsDrawn &&
   commandsContent != nil`, re-read each build so `.commands` called after
   `openWindow` takes effect) and `performMenuBarItem: (Int) -> Void`. Before a
   build the window evaluates titles (`MenuBarModel(style: .drawn)` menus'
   titles) and hands them to the frame (`frame.menuBarTitles`, plus the open
   bar index for the highlight).
3. **Frame.** `requestMenuBarStrip(pass:)` after `requestToolbarStrip`,
   under `MenuBarStrip.rootID = .child(of: nil, at: 2, name: "$menubar")`,
   `stateTable.noteNamed` at index 2; `reportUnconsumedLoweredItems` on its
   node; its own layout run (before the strip's and the root's, so the root's
   run stays last for `lastNativeLayoutWork`); bar at y 0…25, strip 25…64 when
   both, root below; prepaint and paint **after the toolbar strip** (hitboxes
   above it, paint above it, below presentations, the drag preview, the menu
   panel, the tooltip and the alert). `contentMinimum`/`contentMaximum` add the
   whole `top`. Each title's bounds are recorded for the window (anchor and
   hover switching).
4. **Model, drawn style** — exactly `SG-A` item 3. The AppKit style is
   untouched (its `describe` strings in `CommandsTests` are the pin).
5. **Opening.** A title's `onClick` (from input) calls
   `Window.openMenuBarMenu(index:)`: evaluates the bar once
   (`menuBarContent()`-equivalent for the drawn style, keeping the action
   table), numbers nothing new (the model's ids), builds `MenuItemAction`s:
   command ids → `performMenuBarItem(id)`; standard Edit ids → the window's
   key delivery (item 7); presents via `presentMenuOnPlatform` then the
   in-window `MenuSession` at the title's bottom-leading corner, `barIndex`
   set. Choosing runs from input under `StateDispatch` as menu actions do.
6. **While open.** In `dispatchMenuSession`: a pointer move over another
   recorded title → close and open that index (no flicker frame: one
   `setNeedsRedraw`); a press on the open title → close; Left/Right in
   `menuKey` when the highlighted row has no submenu to enter (Right) or the
   level is the root (Left) and `barIndex != nil` → adjacent index, wrapping,
   first enabled row highlighted.
7. **Edit delivery.** `Window.deliverStandardEditKey(_ action:)` builds the
   `KeyEvent` (`.primary` + z / ⇧z / x / c / v / a; Delete = `\u{7f}` (AppKit's key, `SG-H` item 2) with
   no modifiers) and runs it through the window's ordinary key dispatch from
   input — the path `AppKitMenus.deliverEditKey` reaches on AppKit. The
   seven items are built **disabled unless `focusedElement` has a text target**
   in `lastFocusRegistry` at the open (`MetalHostView.validateMenuItem`'s
   rule, `MN-K`; `SG-H` item 1).
8. **F10.** In the window's key dispatch, at the unclaimed-key stage beside
   Tab traversal (after keymap, focused field, `onKey` bubble, `Button`
   shortcuts, command stage — and, once C9 merges, after `onKeyPress`, which
   sits ahead of all of these; an F10 an `onKeyPress` handles opens nothing):
   F10 (`\u{f70d}`, no modifiers) in a window
   drawing a bar opens index 0, first enabled row highlighted. **Keep this
   edit minimal** — `feat/key-focus` is changing `Window`'s key dispatch
   (`git -C ~/Developer/worktrees/MetalUI/key-focus diff 0b400b4...HEAD --
   Sources/MetalUI/Window.swift` before editing); one guarded call, no
   reordering.
9. **Titles.** `Text(title).padding(h 8).frame(height: 24)`
   `.background(open ? highlight : clear).onClick { … }`
   `.accessibilityLabel(title).accessibilityAddTraits(.isButton)` inside an
   `HStack(spacing: 0)` padded 4 leading, then `Spacer`; a 1-point
   `.separator` line; `.background(.surface)`. Keyed `ForEach` over
   `(index, title)`.
10. **SDL.** `SDLPlatform.setMenuBar` returns `false` and records.
    `SDLLifecycleTests`' wrapper conformer forwards the `Bool`.
11. **Demo.** `MetalUIDemoContent` gains `installMenusDemoCommands(_ app:
    App)` (its own function; the commands `MetalUIDemo`'s menus demo declares
    today, moved verbatim, plus one shortcut-less command, "Reset Status",
    so the drawn bar has a menu-only action) called by `MetalUIDemo` and by
    `MetalUISDLDemo` under `METALUI_MENUS_DEMO=1`. The menus demo content gains
    one line in its own function: `Text("Shortcut: ⇧ + primary + H")` in
    `.font(.system(size: 12, design: .monospaced))` (MG-25's face, visible
    under `METALUI_SYSTEM_FONTS=1`). None of the fourteen images shows the
    menus demo; they read 0 px.

### 3.5 Drawn chrome height and limits (lane 1 for the toolbar strip, lane 2 adds the bar; `SG-F`, `SG-H` item 5)

Lane 1 lands `drawnChromeHeight` and the limit adjustment over the **toolbar
strip alone** (`drewToolbarStrip ? 39 : 0`; the strip already exists at the
base, so every arm separates in lane 1); lane 2 adds `drewMenuBar ? 25 : 0`
and its arms of 2.19 (bar only, both) and 2.14's minimum.


- `Window.drawnChromeHeight: Pixels` — set from the adopted frame
  (`drewToolbarStrip ? 39 : 0` + `drewMenuBar ? 25 : 0`), `public private(set)`
  is **not** enough for the guard's wording: spell it as a computed
  `public var … { get }` over an internal stored value.
- `reconcileContentSizeLimits()`: `ContentSizeLimits.effective(…)` gets the
  explicit limits with `drawnChromeHeight` added to the height (finite only)
  before combining with the content's (which already include it).
- `ToolbarStrip.height`'s doc comment points at `drawnChromeHeight`.
- Inventory: one **M** row (lane 1); the `setMenuBar` census line changes
  (lane 2).

### 3.6 The asserts compiler (lane 3, `SG-E`)

1. Reproduce with `~/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a.xctoolchain`
   (`swift build --toolchain <path>` or `TOOLCHAINS=<bundle id>`; record which
   works) on a scratch package depending on this checkout by path:
   `Fixture.swift` with (a) MG-27's shape — a `Component` whose `content` is a
   `switch` over ≥ 4 enum cases, one case a nested `Component` whose content is
   a `ForEach`, another an `AnyElement`, at `-c release` and debug; (b) `LK-X`'s
   shape (`feat/controls-looks`' table). Also `ssh metalui-win` (UTM VM,
   6.4.0+Asserts ARM64) if it answers — `-c release` of the same package.
2. Reduce by one-edit steps; record the table in `SG-E` (append items; the
   "next unused" line does not move for an amended ruling).
3. Try `SG-E` item 2's candidate (box `Component`'s `GroupPrepaint`:
   `Sources/MetalUI/Component.swift`, beside `ComponentLayout`; `StyledComponent`
   too if it has its own) and any candidate the reduction suggests, under the
   four gates. Adopt or withdraw; amend `SG-E` with the result. A box changes
   `Component`'s public `GroupPrepaint` witness type (and `StyledComponent`'s,
   `Component.swift` ~502): a new public type then owes a doc comment, an
   inventory row and a re-recorded census (`SG-H` item 7) — the fifth gate.
4. Guard: `Tests/MetalUIScaffoldTests/AssertsCompilerTests.swift` (the scaffold
   test target already shells out to `swift`; it imports no MetalUI module),
   env-gated as in `SG-E` item 4.
5. Docs: `docs/packaging.md` gains "Windows release builds" (the trigger, the
   workaround or the fix, how to check with an asserts toolchain); the
   upstream report text in the decisions doc's `SG-E` now and the record later.

## 4. Lanes

**Rebalanced and parallelised by `SG-H` item 5** (supersedes `SG-G` item 1).
Lane 1 now also takes `SG-B` item 5 (labels: `MenuPanel.swift`, test 2.2) and
`SG-F` over the toolbar strip (tests 2.19's strip arms, 2.20, guard 2.21b) —
those tests keep their numbers. **Lane 3 shares no source, test or doc file
with lanes 1 and 2** and depends on nothing they add, so it may run
**concurrently** with them in a sibling worktree
(`~/Developer/worktrees/MetalUI/smk-gaps-asserts`, branch
`fix/smk-port-gaps-asserts` from this design's HEAD), merged into
`fix/smk-port-gaps` after lane 2 and verified there (full suite, images).
**Lane 2 depends on lane 1** (`EventModifiers.primary`, the labels,
`drawnChromeHeight`), so lanes 1 → 2 stay one after another in this
worktree. Generated files (`closeout-public-api.tsv`) are **re-generated
after a merge, never hand-merged**; the inventory map and the decisions doc
merge additively (each lane edits only its own rulings' sections). Each lane
commits test-first (red), then the fix, then docs; full
unfiltered native suite at each lane's end; census and inventory checks print
nothing.

| lane | rulings | files (exclusive) |
| --- | --- | --- |
| 1 | `SG-B` items 1–6, `SG-C`, `SG-D`, `SG-F` (strip) | `Sources/MetalUIPlatform/InputEvent.swift`, `Sources/MetalUI/MenuPanel.swift` (labels only), `Sources/MetalUI/Window.swift` + `Sources/MetalUI/Frame.swift` + `Sources/MetalUI/ToolbarStrip.swift` (`SG-F` only), `Tests/MetalUITests/{WindowSizingTests,MenuPanelLabelTests (new),ChromeHeightCompileGuards (new)}.swift`, `docs/migration.md` (`SG-B`, `SG-F` rows), `Sources/MetalUI/KeyboardShortcut.swift`, `Sources/MetalUI/Button.swift`, `Sources/MetalUISystemFonts/**`, `Sources/MetalUIScaffold/Scaffold.swift`, `docs/getting-started.md`, `Tests/MetalUICrossPlatformTests/PrimaryModifierTests.swift` (new), `Tests/MetalUITests/KeyboardShortcutTests.swift`, `Tests/MetalUISystemFontsTests/**`, `Tests/MetalUIScaffoldTests/ScaffoldTests.swift`, `Backends/SDL/Tests/MetalUISDLTests/SDLPrimaryShortcutTests.swift` (new) |
| 2 | `SG-A`, `SG-F`'s bar term, `SG-B`'s drawn standard items | `Sources/MetalUIPlatform/Platform.swift`, `Sources/MetalUIAppKit/AppKitPlatform.swift`, `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`, `Sources/MetalUI/{Commands,App,Window,Frame,MenuSession,MenuBarStrip}.swift`, `Sources/MetalUIDemoContent/**` (menus demo), `Sources/MetalUIDemo/main.swift`, `Backends/SDL/Sources/MetalUISDLDemo/main.swift`, `Tests/MetalUITests/{Fakes,CommandsTests,CommandsCompileGuards,AppIconCompileGuards,MenuBarStripTests,MenuBarCompileGuards,ExplicitIdentityTests,WindowSizingTests,ToolbarStripTests}.swift` and every other compile-guard file holding a full `Platform` conformer, `Tests/MetalUICrossPlatformTests/DrawnMenuBarModelTests.swift` (new), `Backends/SDL/Tests/MetalUISDLTests/{SDLMenuBarTests,SDLLifecycleTests}.swift`, `docs/migration.md` (`SG-A` row), `docs/divergences.md`, `docs/verification/human-checks.md` |
| 3 (may run concurrently) | `SG-E` | `Sources/MetalUI/Component.swift` (only if adopted), `Tests/MetalUIScaffoldTests/AssertsCompilerTests.swift` (new), `docs/packaging.md`, the inventory map / census only if a box type becomes public (`SG-H` item 7) |

Shared, appended in lane order: `docs/probes/closeout-public-api.tsv`
(re-recorded), `docs/probes/closeout-inventory-map.tsv`, the decisions doc
(amendments to the lane's own rulings).

**A change touching `Backends/SDL`** (lanes 1 and 2) is also run in CI's
Linux image (`metalui-portable`, volume `metalui-sdl-build-smk-gaps`), and the
root package's portable tests in `swift:6.4-noble`
(`swift build --build-tests && swift test --skip-build`, scratch path in a
named volume of this worktree) — that is where 1.1, 1.3's Linux arm, 1.6's
Linux arm and 2.1 separate.

## 5. Tests

Numbered by lane. **Red before** is the state at the lane's base; **mutation**
is applied to the named declaration after the fix, the full unfiltered suite
run, every reddened test named, `git status --short` clean after restore.

### Lane 1

- **1.1** `thePrimaryModifierIsCommandOnAppleAndControlElsewhere`
  (`MetalUICrossPlatformTests/PrimaryModifierTests.swift`): `EventModifiers.primary`
  is `.command` on Darwin, `.control` elsewhere; `KeyboardShortcut("s").modifiers
  == .primary`. Red: does not compile. Mutation M1.1: `primary = .command` on
  every platform — reddens in `swift:6.4-noble` (record the run).
- **1.2** `aShortcutWithNoModifiersDefaultsToThePrimaryOne`
  (`KeyboardShortcutTests.swift`): `Button("S"){}.keyboardShortcut("s")`'s
  recorded shortcut modifiers `== .primary`, and ⌘S runs it once on macOS
  (unchanged behaviour). Red: does not compile (`.primary`). Mutation M1.2:
  default `.option` → reddens. (On macOS `.command` and `.primary` are equal, so
  the separating run is 1.3's Linux arm.)
- **1.3** `ctrlSRunsADefaultShortcutOffAppleAndSuperSDoesNot`
  (`SDLPrimaryShortcutTests.swift`): `App(platform: SDLPlatform(hiddenWindows:
  true, offscreenRenderers: true))` (`@_spi(Checks)`, `armMainRunLoopExitCheck()`
  on macOS), a window with `Button("Save"){ n += 1 }.keyboardShortcut("s")`;
  pump one frame; push a key-down S with `MUI_MOD_CONTROL` then one with
  `MUI_MOD_COMMAND` through `mui_push_event`; pump. Off macOS: n == 1 after Ctrl,
  still 1 after Super. On macOS: the reverse. Red: the Linux arm fails at
  `0b400b4` (Super runs it). Mutation M1.3: M1.1 → reddens in the Linux image.
  Not gated on `windowsPresentFrames` (offscreen renderers build frames, `TF-C`);
  if the run shows a frame is needed, gate it and say so.
- **1.4** `anExplicitCommandStaysTheSuperKeyOffApple` (same file):
  `.keyboardShortcut("s", modifiers: .command)` runs on Super+S and not on
  Ctrl+S on every platform. Red: green at base (a pin of `SG-B` item 4).
  Mutation M1.4: the bridge maps `SDL_KMOD_CTRL` to `MUI_MOD_COMMAND` → reddens.
- **1.5** `aDesignResolvesToItsFirstInstalledFamilyAndReadsNothingUntilAsked`
  (`SystemFontsTests.swift`): over `Tests/Fonts`, `designFamilies:
  [.monospaced: ["Not Installed", "source sans 3"], .serif: ["Noto Sans Arabic"]]`,
  `defaultFamilies: ["Noto Sans"]`, `fallbackFamilies: []`, a `LoadLog`: nothing
  read after building; `.monospaced` resolves `SourceSans3-Regular`, `.serif`
  `NotoSansArabic-Regular`, `.rounded` the default `NotoSans-Regular`; the log
  holds only the resolved files (after the first resolve: the design's face and
  the cascade's default face, which `resolve` loads — `SG-C`, measured). Red: does not compile. Mutations: M1.5a skip
  the design loop; M1.5b register the last installed family; M1.5c register
  the first entry whether installed or not — each reddens.
- **1.6** `thePlatformsOwnDesignFamiliesResolve`: macOS — `.monospaced` and
  `.serif` resolve to families from their lists (the measured first installed
  names, asserted exactly); Windows — `.monospaced` "Cascadia Mono" or
  "Consolas" (the first installed of the list, computed from the scan),
  `.serif` "Georgia"; Linux — when DejaVu Sans Mono is installed (the CI
  images), `.monospaced` "DejaVu Sans Mono" and `.serif` "DejaVu Serif",
  otherwise the test records why it asserts nothing; `.rounded` off Apple is
  the default face. Red: does not compile. Mutation M1.6: `designFamilies`
  empty → reddens on macOS and in `swift:6.4-noble`.
- **1.7** `fontconfigsAnswerLeadsEachDesignsLinuxList`: `linuxDesignFamilies(
  fontconfig: { ["monospace": "Hack", "serif": "Gelasio"][$0] })` puts "Hack"
  and "Gelasio" first, and a `nil` answer leaves the fixed lists. Red: does not
  compile. Mutation M1.7: append fontconfig's answer last → reddens.
- **1.8** `theCrossPlatformManifestNamesThePortableTextProductsOnEveryPlatform`
  (`ScaffoldTests.swift`): the generated manifest names `MetalUIPortableText`
  and `MetalUISystemFonts` with no `condition:` and `MetalUISDL` with
  `.when(platforms: [.linux, .windows])`. Red: fails at base. Mutation: restore
  the condition → reddens. Existing scaffold tests pinning the old text are
  updated and named in the commit.
- **1.9** `aCrossPlatformPackagesTestTargetBuildsOnMacOS` (env-gated
  `METALUI_RUN_SCAFFOLD_BUILD_TEST=1`, beside test 1.7 of `TF-B`): generate
  `--cross-platform --local`, append the test target of §3.3 in the copy,
  `swift build --build-tests` on macOS, require exit 0 and no `warning:` line.
  Red: with the condition, fails with the recorded `unable to resolve module
  dependency` lines. Mutation: restore the condition → reddens (env run).
  Counts while skipped.

### Lane 2

- **2.1** `theDrawnBarsStandardShortcutsUseThePrimaryModifier`
  (`MetalUICrossPlatformTests/DrawnMenuBarModelTests.swift`): the drawn-style
  model's Edit items' shortcut modifiers are `.primary` (`[.primary, .shift]`
  for Redo), i.e. `.control` off Darwin. Red: does not compile (`style:`).
  Mutation: standard default back to `.command` → reddens in `swift:6.4-noble`.
- **2.2** (lane 1, `SG-H` item 5) `aDrawnMenusShortcutTextNamesEachKey` (`MenuPanelLabelTests.swift`):
  `MenuPanel.shortcutText` with `platform: .other`: `.control`+k "Ctrl+K",
  `.command`+k "Super+K" (the Linux spelling; the Windows "Win" behind the
  same `superKeyName` parameter, asserted by passing it), `[.control,
  .command, .option, .shift]` "Ctrl+Super+Alt+Shift+K"; `.mac` unchanged. Red:
  fails at base ("Ctrl+K" for `.command`). Mutation: `.command` → "Ctrl" →
  reddens.
- **2.3** `aDeclinedMenuBarIsDrawnAboveTheRootInEveryWindow`: `App` over
  `FakePlatform` with a new `menuBarIsNative = false` (default `true`), `.commands { CommandMenu("Tools") {
  Button("Go") {…} } }`, two windows 400 × 400: each records `$menubar` at
  (0, 0, 400, 25), its root's bounds start at y ≥ 25, titles "Edit", "Tools".
  Red: no `$menubar`. Mutations M2.3a height 0; M2.3b only the first window.
- **2.4** `anAppWithoutCommandsDrawsNoMenuBar`: no `.commands` → no
  `$menubar`, root at y 0, `setMenuBar` called once (answered `false`).
  Mutation: drop `commandsContent != nil` → reddens.
- **2.5** `aMenuBarThePlatformShowsIsNotDrawn`: the default fake (`true`) →
  no `$menubar`. Mutation: ignore the answer → reddens.
- **2.6** `theDrawnBarFollowsTheDesktopArrangement` (model, `describe` strings):
  no application menu; File = newItem additions then appTermination
  additions; Edit with the standard items; `CommandMenu`s; Window only with
  additions; Help = help group then appInfo additions; empty menus dropped.
  And the AppKit style's existing strings (`defaultApp`…`defaultWindow`)
  unchanged. A `CommandGroup(replacing: .pasteboard)` replaces the drawn
  Edit's Cut/Copy/Paste/Delete/Select All as it replaces AppKit's (`SG-H`
  item 3). Mutations: keep the application menu in the drawn style; keep the
  standard items under a replacement → each reddens.
- **2.7** `clickingATitleOpensItsMenuBelowItAndAChoiceRunsTheCommand`: click
  "Tools" → an in-window session whose root level's origin is (Tools.minX,
  25); click "Go" → its action ran once, the session closed. Mutations:
  anchor at y 0; `performMenuBarItem` not called → each reddens.
- **2.8** `hoveringAnotherTitleWhileOpenSwitchesAndArrowsWrap`: open Edit,
  move over Tools → Tools' items; Right from Tools → Edit (wrap), Left → Tools.
  Mutations: no hover switch; no wrap.
- **2.9** `thePressedOpenTitleAndEscapeCloseTheMenu`. Mutation: a press on the
  open title reopens → reddens.
- **2.10** `f10OpensTheFirstMenuOnlyWhenNothingClaimsIt`: F10 opens Edit with
  Undo highlighted; with an `onKey` claiming F10 nothing opens; Shift+F10 over a
  focused element with a `.contextMenu` still opens the context menu (the
  window's `contextMenuKeyPlatform` set to `.other`); F10 in a window with no drawn bar
  does nothing. Mutation: the F10 stage before the `onKey` bubble → the second
  arm reddens.
- **2.11** `aDrawnEditItemReachesTheFocusedField`: a focused `TextField` holding
  "abc", Edit ▸ Select All then Edit ▸ Copy → fake clipboard "abc"; Edit ▸
  Paste with "Z" on the clipboard replaces the selection. With nothing
  focused, the seven Edit rows are disabled and a `Button("A"){…}
  .keyboardShortcut("a")` in the window has not run after a press on Select
  All's row (`SG-H` item 1). Mutations: deliver nothing; deliver Copy as "x";
  enable the Edit rows always → each reddens.
- **2.12** `aCommandShortcutStillRunsOnceWithADrawnBar`: a command bound to
  `.primary`+G runs once on that key in a window drawing the bar (`MN-J`).
  Mutation: also perform from the bar on a matching key → reddens (twice).
- **2.13** an arm `$menubar` in `everyNamingSiteStartsAReturningNameFresh`
  (`ExplicitIdentityTests.swift`). Mutation: drop the `noteNamed` → reddens.
- **2.14** `theMenuBarAndTheToolbarStripStackAboveTheRoot`: commands and a
  declined `.toolbar`: bar 0…25, strip 25…64, root from 64; under
  `.contentMinSize` the platform's minimum height is the root's + 64.
  Mutation: the strip at y 0 → reddens.
- **2.15** `aMenuBarTitleIsAnAccessibleButton`: once a client activated the
  window, the published tree holds each title as a button labelled with its
  title; no new role. Mutation: drop `.accessibilityAddTraits(.isButton)` →
  reddens.
- **2.16** `theDrawnBarsTitlesFollowTheCommandsLive`: a `CommandMenu` under
  `if model.flag` (an `@Observable`) appears on the frame after the flag is
  written from input. Mutation: evaluate titles once at install → reddens.
- **2.17** `sdlDeclinesTheMenuBarAndRecordsIt` (rewrites S2.1
  `sdlRecordsTheMenuBarAndDrawsNothing`, moved by `SG-A`): answers `false`,
  records, never calls `content`. Mutation: answer `true` → reddens.
- **2.18** `anSDLWindowDrawsTheCommandsAndAClickRunsOne` (Backends/SDL;
  offscreen renderers; also in the Linux image): a shortcut-less `Toggle`
  command; push mouse down/up at the title then at its row
  (`mui_push_raw_mouse_event`) → the toggle's binding flipped. Mutation: SDL
  answers `true` → reddens. If a presented frame is needed, gate on
  `windowsPresentFrames` and say so.
- **2.19** (strip arms lane 1, bar arms lane 2) `drawnChromeHeightIsTheBarPlusTheStrip`: 0 with neither; 39 strip
  only; 25 bar only; 64 both; 0 with both native. Mutation: report the strip
  only → reddens.
- **2.20** (lane 1) `anExplicitMinimumIsMeasuredBelowTheDrawnChrome`
  (`WindowSizingTests.swift`): `minSize` 200 × 300 with a drawn strip → the
  platform receives 200 × 339; `maxSize` 500 × ∞ → 500 × ∞; native → 200 × 300.
  Mutation: send unadjusted → reddens. Existing `SV-L` pins unmoved (verify).
- **2.21** typecheck guards (`MenuBarCompileGuards.swift`, plain import,
  `typecheckFile`): (a) `aPlatformWhoseSetMenuBarReturnsNothingDoesNotConform`
  — the `Void` spelling refused, the `-> Bool` spelling (positive control)
  compiles; mutate red once: a protocol-extension default `-> Bool { true }`.
  (b) (lane 1, `ChromeHeightCompileGuards.swift`) `drawnChromeHeightIsReadOnly` — assignment refused, a read compiles;
  mutate red once: make it settable. **+2 guards.**
- Every compile-guard and fake `Platform` conformer changes to `-> Bool`
  (existing `G2.2` guard keeps its meaning).

### Lane 3

- **3.1** the reduction table (`SG-E`), each row a one-edit measurement.
- **3.2** `theComponentSwitchShapeAgainstAnAssertsCompiler` (env-gated
  `METALUI_RUN_ASSERTS_COMPILER_TEST=1`, `AssertsCompilerTests.swift`):
  `SG-E` item 4's arms. Red: with no fix, the trigger arm's expectation is the
  crash (green), the workaround arm compiles — the red-before is the *fix's*
  arm (if adopted) failing at base. Mutation (if a fix lands): un-box →
  the trigger arm reddens under the env run. Counts while skipped.
- **3.3** (only if a fix lands) a unit pin of the box: `aComponentsPrepaintIsHeldOnceAndMutatedInPlace`
  (the `PE-J` `withPayload` pattern), mutation copy-on-write → reddens; plus
  every moved work/allocation/stack pin named.

### Counts

At `0b400b4`: **2879 tests in 3 suites**; **lane 1 re-takes the baseline at
`57e02a4`** (master's GX-Y tests added) before its first commit, and reads
the `FR-J` line for guards. Expected: lane 1 +12 tests (1.1–1.9, 2.2, 2.19's
strip arms as one test, 2.20; 1.9 env-gated) and +1 guard (2.21b), lane 2
+17 tests (2.1, 2.3–2.18; 2.13 is an arm; 2.19 gains arms, not a test) and +1
guard (2.21a), lane 3 +1 (3.2) or +2. Env-gated tests that count while skipped:
thirteen at the base, fifteen after 1.9 and 3.2.
Re-measure; never add these up in place of a run.

## 6. Verification (every lane)

`swift build --build-system native --build-tests`; `swift test
--build-system native --no-parallel` unfiltered (one summary line, the
`FR-J no-argument frame: succeeded=` line); `swift build --build-tests` 0
warnings; 0 `error:`; census/inventory scripts print nothing; fourteen images
0 px (`docs/probes/demo-pixels/compare.sh <scratch> 57e02a4 HEAD`);
`DemoFrameDeterminismTests`' `Expected.swift` unedited;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green; `MetalUILayout`
and `MetalUIScene` imports unchanged. Lanes 1 and 2: `Backends/SDL` on macOS
and in the Linux image; the root portable tests in `swift:6.4-noble`.
`swift package clean` after `setMenuBar`'s signature change (a public
protocol crossing module boundaries).

## 7. Demo and human checks

Demo: §3.4 item 11. Lane 2 adds group **SG** to
`docs/verification/human-checks.md` (not run — an agent cannot):

- **SG1** (Linux and Windows, `METALUI_MENUS_DEMO=1 METALUI_SYSTEM_FONTS=1`
  `MetalUISDLDemo`): a menu bar shows Edit, Demo (and File with New Note);
  clicking a title opens its menu under it; moving across titles switches;
  Left/Right switch; F10 opens Edit; Escape closes; Demo ▸ Reset Status (no
  shortcut) works.
- **SG2**: Ctrl+Shift+H runs Say Hello; Super/Win+Shift+H does not; the menu
  shows "Ctrl+Shift+H".
- **SG3**: in a focused text field, Edit ▸ Copy/Paste/Select All work.
- **SG4**: the "Shortcut:" line draws in DejaVu Sans Mono (Linux) / Cascadia
  Mono or Consolas (Windows) — monospaced, not the UI face.
- **SG5**: the bar and a toolbar together: bar on top, strip below, content
  below both; resizing to the minimum keeps the content's minimum visible.
- **SG6** (Windows ARM64 and x64): `swift build -c release` of the SMK
  configurator (or the `SG-E` fixture) — builds, or fails exactly as `SG-E`
  documents.

## 8. Deferred (named, with reason and owner)

- File ▸ Close and Exit/Quit in the drawn bar — need C8's
  `PlatformWindow.close()`/`Platform.terminate()`; owner: whichever of C8/C12
  merges second (`SG-A` item 11a).
- Alt-alone activation and mnemonics; native Win32 `HMENU`; Window ▸
  Minimize/Zoom on SDL — owner none (`SG-A` item 11).
- A menu-bar accessibility role (titles are buttons) — owner none (`SG-A` item 7).
- `Keymap` `"primary"` token — owner none, after C9 (`SG-B` item 7).
- A rounded face off Apple — none ships; owner none (`SG-C` item 3).
- Filing the SwiftPM (MG-26) and Swift (MG-27) reports upstream — text in the
  record; a human files them.
