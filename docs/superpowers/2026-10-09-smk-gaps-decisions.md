# SMK configurator port gaps MG-23…MG-28 — decisions

Rulings for the six gaps the SMK configurator's Linux/Windows port (C4b)
reported against MetalUI `70ed000` (user request 2026-10-02, item C12 of the
gpui-gap priority list; **not a plan task**). Prefix `SG-`. Spec:
[`specs/2026-10-09-smk-gaps-design.md`](specs/2026-10-09-smk-gaps-design.md).
Record: `../record/89-smk-gaps.md` (written in the Record phase). Branch
`fix/smk-port-gaps` from `0b400b4`. The gap list is the configurator's
`docs/superpowers/2026-10-06-metalui-gaps.md` (headings `MG-23`…`MG-28`, read
only; never edited from here).

**Next unused id: `SG-I`.**

## The final spellings (what the configurator swaps its workarounds for)

| gap | the configurator's workaround | MetalUI's answer, by name |
| --- | --- | --- |
| MG-23 | a Linux/Windows-only `.toolbar` mirroring the File and View menus | **nothing to write**: `app.commands { … }` is drawn as an in-window menu bar wherever `Platform.setMenuBar(_:)` answers `false` (SDL) — `SG-A` |
| MG-24 | `primaryShortcutModifier` passed on every `.keyboardShortcut` | **`EventModifiers.primary`**, and it is now the **default** of `KeyboardShortcut(_:modifiers:)` and `.keyboardShortcut(_:modifiers:)` — `.keyboardShortcut("s")` is ⌘S on macOS and Ctrl+S on Linux/Windows — `SG-B` |
| MG-25 | `resolver.register(design: .monospaced, family: "DejaVu Sans Mono"/"Consolas")` | **nothing to write**: `SystemFonts.resolver()` registers the platform's monospaced and serif families (`SystemFonts.designFamilies`) — `SG-C` |
| MG-26 | the two portable-text products unconditional on the app target | the same, now what `metalui new --cross-platform` and `docs/getting-started.md` write — `SG-D` |
| MG-27 | package the Windows debug build | `SG-E` (reduced, measured; the spec's lane 3 decides between a `Component` change and the documented workaround — this ruling is completed by that lane) |
| MG-28 | the literal 39 | **`Window.drawnChromeHeight`** (read-only, `Pixels`), and an explicit `Window.minSize`/`maxSize` is now measured **below** the drawn chrome, as AppKit's `contentMinSize` is below its toolbar — so the app's `+ 39` goes — `SG-F` |

Evidence:

- [`../probes/swiftui-shortcut-modifiers.swift`](../probes/swiftui-shortcut-modifiers.swift)
  (**new**; default build and the `PRIMARY`/`PLATFORM` separating arms) —
  SwiftUI's default shortcut modifier and the absence of a "primary" one.
- [`../probes/swiftui-commands.swift`](../probes/swiftui-commands.swift)
  (`MN-I`'s; PLAIN and FULL) — the AppKit menu bar SwiftUI builds, which
  `SG-A`'s drawn style departs from on purpose.
- The source at `0b400b4`: `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`
  (`setMenuBar` records and draws nothing, `MN-I` item 3);
  `Sources/MetalUI/Commands.swift` (`MenuBarModel`, the AppKit-shaped
  standard menus); `Sources/MetalUI/MenuSession.swift`/`MenuPanel.swift` (the
  drawn menu; `MenuPanel.shortcutText` labels `.command` "Ctrl" off Apple —
  untrue today, the SDL bridge maps `SDL_KMOD_GUI` to `.command`);
  `Sources/MetalUI/ToolbarStrip.swift` + `Frame.computeRootLayout` (the drawn
  strip, `MD-K`, the precedent for chrome laid out above the root);
  `Sources/MetalUIAppKit/AppKitMenus.swift` (`deliverEditKey`: AppKit's Edit
  items are already delivered to the window as their own key — `SG-A` item 4's
  precedent); `Sources/MetalUIAppKit/AppKitPresentations.swift:173`
  (`contentMinSize`/`contentMaxSize` — AppKit's limits exclude its toolbar);
  `Sources/MetalUISystemFonts/SystemFonts.swift` (no `register(design:)`
  call); `Sources/MetalUIPortableText/PortableFontResolver.swift:187`
  (`register(design:family:)` stores a name, reads nothing);
  `Sources/MetalUIScaffold/Scaffold.swift:252` (the conditional products).
- CI's Linux images, measured 2026-10-09: `swift:6.4-noble` and
  `metalui-portable` both carry `/usr/share/fonts/truetype/dejavu/`
  (DejaVu Sans, Sans Mono, Serif, with bold/oblique) and **no `fc-match`**.
- `feat/controls-looks`'s `LK-X` (an asserts-compiler crash in a `Component`
  witness thunk, reduced on the Mac with
  `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a`), the family MG-27 belongs to.
- A first standalone reduction attempt for MG-27 (this session, scratch only):
  a ten-line `Group`/`Comp` protocol pair mimicking `ElementGroup`/`Component`
  with an `Array` prepaint in a nested component compiles under the asserts
  snapshot at `-Onone` and `-O` — the trigger needs more of MetalUI's shape
  than that; lane 3 reduces from MetalUI itself.

## SG-A — `App.commands` is drawn as an in-window menu bar where the platform declines it

**Ruling.** Supersedes `MN-I` item 3's "an in-window menu bar is deferred,
owner none".

1. **The seam: `Platform.setMenuBar(_:) -> Bool`**, still defaultless, its
   return type changed (the `presentMenu`/`setToolbar`/`presentAlert`
   pattern): `true` when the platform shows the bar itself (AppKit,
   `NSApp.mainMenu`, unchanged), `false` when it cannot (SDL: SDL3 has no
   menu-bar API; it still records the bar for tests). Every test fake answers
   a configurable value, default `true`, so every existing window test is
   unmoved. **Migration** (`docs/migration.md`): a third-party conformer
   changes `func setMenuBar(_:) {}` to `func setMenuBar(_:) -> Bool { false }`
   (or `true` if it shows a bar). A conformer that keeps the `Void` spelling
   no longer conforms — pinned by a plain-import typecheck guard (spec 2.21).
2. **When it is drawn.** `App.installMenuBar()` keeps the answer; every
   window of the app — open and later — draws the bar **when the answer was
   `false` and the app declared `commands`**. An app that never calls
   `.commands` draws nothing: its bar would hold only the standard Edit items,
   whose keys already work in a field; and every existing SDL window, test and
   image stays as it is. Each window draws its own bar (the Windows and GTK
   convention: a menu bar per top-level window).
3. **The drawn style of the bar's model** (`MenuBarModel`, a `style:`
   parameter; the AppKit style is byte-for-byte today's, its pins unmoved). The
   desktop convention, not the Mac's: **no application menu**; **File** = the
   `.newItem` group, then the additions at `.appVisibility` and
   `.appTermination` (their standard items dropped); **Edit** = Undo, Redo, —,
   Cut, Copy, Paste, Delete, Select All (the `.undoRedo` and `.pasteboard`
   groups, standard items kept unless a `CommandGroup(replacing:)` replaces
   them, exactly as the AppKit style replaces them — amended by `SG-H` item
   3; shortcuts `.primary`, `SG-B`); then every
   `CommandMenu` in declaration order; **Window** only when something is
   placed at `.windowSize`/`.windowArrangement` (standard items dropped — no
   `PlatformWindow` minimise/zoom exists); **Help** = the `.help` group, then
   the additions at `.appInfo` (About lives in Help on Windows and GNOME). A
   menu left empty is not shown (File is empty unless the app adds to it —
   Close/Quit are item 11's deferral).
4. *(Amended by `SG-H` items 1–2: the Edit items are enabled only while a
   text field is focused, as AppKit's `validateMenuItem` enables them
   (`MN-K`); Delete is `\u{7f}` with no modifiers, AppKit's `delete(_:)`
   key — not `\u{f728}`.)* **A standard Edit item is delivered as its own key** to the window that
   drew the bar — `.primary`+Z, `.primary`+⇧Z, `.primary`+X/C/V/A, and Delete
   as `\u{7f}` with no modifiers — through the window's ordinary key
   pipeline, from input. AppKit already does exactly this
   (`AppKitMenus.deliverEditKey`, the same seven keys), so a focused
   `TextField` handles both bars' Edit items through one path. The items are
   **disabled unless a text field holds focus** (AppKit's
   `MetalHostView.validateMenuItem`, `MN-K`), evaluated at each open, so a
   drawn Select All never reaches a `Button` shortcut or an app command bound
   to the same key.
5. **Geometry and look.** A strip across the window's top, **25 points**:
   a 24-point bar (the regular control height `MD-K` item 1 uses) and a
   1-point `.separator` line, filled `.surface` like the toolbar strip. Titles
   in the control font, each padded 8 horizontally, no spacing between them,
   the row padded 4 at the leading edge; the title whose menu is open is
   filled with the drawn menu's highlight colour and drawn in its highlighted
   text colour (`MenuPanel`'s tokens, so the open title and the highlighted
   row match). When the toolbar strip is drawn too it sits **below** the bar;
   the root is laid out below both (`SG-F`'s chrome).
6. **Elements and identity.** The bar is ordinary elements under a
   window-owned **named root `$menubar`** at cursor index **2** (beside the
   root's `(nil, 0)` and `$toolbar`'s `(nil, 1)`), its name noted (`ID-R`) —
   an element name, never a `StateTable` slot: the seven retention slots are
   unmoved. Titles are keyed by menu index and title (`ForEach(id:)`). A new
   naming site, so it owes `StateTable.noteNamed` and an arm in
   `everyNamingSiteStartsAReturningNameFresh`.
7. **A title is `Text` + `.padding` + `.background` + `.onClick` +
   `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)`** — existing
   modifiers only, so no new `StyledElement` site, no new handler-registering
   site (the D2 guard and `DN-X` are not owed), no new accessibility role (no
   bridge rows). An `onClick` target does not take focus and is not a Tab stop
   (divergence 94's rule): the bar is reached by pointer and F10, not Tab.
   Cost if wrong: VoiceOver/Narrator read the titles as buttons, not menu-bar
   items — a role row on both bridges would fix it later, owner none.
8. **Input.** *(Amended by `SG-H` item 4: a title's `onClick` opens on the
   click, i.e. the release, not the press.)* A click on a title opens its menu through the window's existing
   menu machinery (`MenuSession`, `presentMenuOnPlatform` first — SDL answers
   `false`, so the in-window panel), anchored at the title's bottom-leading
   corner, the session remembering which bar menu it is. While a bar menu is
   open: the pointer moving onto another title opens that one instead; Left
   and Right on a level with no submenu to enter or leave move to the
   adjacent menu, wrapping; a press on the open title, Escape or a press
   outside closes it (the session's existing dismissals). **F10** with no
   modifiers opens the first menu with its first enabled row highlighted —
   as an *unclaimed-key* stage after the keymap, a focused field, the `onKey`
   bubble, `Button` shortcuts and the command stage, beside Tab traversal —
   only in a window that draws a bar; Shift+F10 stays the context-menu key
   (`ContextMenuKeys`). A command item chosen runs through
   `PlatformMenuBar.perform` (the app's one action table, evaluated at the
   open, so ids match), under the same dispatch as AppKit's; a `Toggle` item
   shows its state.
9. **Liveness.** The titles are evaluated for every build in which the bar is
   drawn (a `CommandMenu` under an `if` comes and goes on the next frame, as
   `MN-I`'s "evaluated afresh" promises); the items at each open. Evaluation
   writes nothing.
10. **Shortcuts are unchanged.** The window's command stage (`MN-J`) is still
    the one shortcut path; the drawn bar adds none, so a command shortcut runs
    once whether or not the bar is drawn.
11. **Deferred.** (a) **File ▸ Close and Exit/Quit**: they need
    `PlatformWindow.close()` and `Platform.terminate()`, which `feat/app-shell`
    (C8, `AS-`) is adding now; owner: **whichever of C8 and C12 merges second**
    adds them to the drawn File menu (`.close`, `.quit` standard items,
    performed through those requirements). Until then the window's close
    button is the way out, as today. (b) Alt-alone activation and `&`
    mnemonics (SDL reports no modifier-only key; SwiftUI titles carry no
    mnemonic) — owner none. (c) A native Win32 `HMENU` through SDL's window
    properties — owner none: one drawn look on every SDL platform, and Linux
    has no equivalent. (d) Window ▸ Minimize/Zoom — no `PlatformWindow` API,
    owner none.

**Divergence 195** (this branch's range): on SDL the commands' menu bar is
drawn inside the window, above the toolbar strip, taking the content's height,
in the desktop arrangement of item 3 (no application menu; Edit items
delivered as keys; File ▸ Close/Quit absent until item 11a). SwiftUI ships only
on Apple platforms, where the bar is the system's.

**Evidence.** `MN-I` item 3 (SDL3 has no menu-bar API — re-checked: SDL 3.4's
headers name none); the drawn strip `MD-K` (chrome above the root, its own
layout run, a named root, paint after the root and before presentations);
`AppKitMenus.deliverEditKey`. gpui's approach, **recalled, not measured, and
no item rests on it**: gpui's Linux and Windows platforms keep the menus
`set_menus` is handed and Zed draws an application menu in its own title bar.

**Cost if wrong.** A drawn bar that should not be there (an app with
`.commands` that wanted none on Linux) costs 25 points; the app can drop its
`.commands` under `#if os(macOS)`. Changing `setMenuBar`'s return type breaks
third-party `Platform` conformers at compile time (honest, with a migration
line).

## SG-B — `EventModifiers.primary`, and it is the default shortcut modifier

**Ruling.**

1. **SwiftUI's answer, probed** (`swiftui-shortcut-modifiers.swift`):
   `KeyboardShortcut("s").modifiers == .command` (raw 16); SwiftUI has no
   `.primary` or `.platform` member (both separating arms refused by the
   compiler). SwiftUI ships only on Apple platforms, so "⌘" is its primary
   modifier by construction; it has no answer off Apple.
2. **`public static let primary: Modifiers`** (so `EventModifiers.primary`) in
   `MetalUIPlatform` beside `.command`: `.command` on Apple platforms,
   `.control` elsewhere (the same `os(...)` split as `TextEditing.platform`,
   `TI-D`). Not a new bit: a name for one of the existing four. MetalUI-only
   (inventory **M**).
3. **The defaults become `.primary`**: `KeyboardShortcut.init(_:modifiers:)`
   and `Button.keyboardShortcut(_:modifiers:)` (and every other
   `.keyboardShortcut(_:modifiers:)` spelling that defaults a modifier), and
   the standard menu items' shortcuts (`MenuBarModel.standard`'s default and
   Redo's `[.primary, .shift]`; Hide Others stays `[.command, .option]` — an
   AppKit-only item). **On macOS nothing moves**: `.primary == .command`, so
   every macOS pin, AppKit menu and test is value-identical (no divergence).
   On Linux/Windows `.keyboardShortcut("s")` fires on Ctrl+S.
4. **An explicit `.command` keeps meaning the Super/Windows key off Apple** —
   no event translation, the SDL bridge's `SDL_KMOD_GUI → .command` is
   unchanged. Qt's "Ctrl means ⌘ on macOS" re-mapping was considered and
   refused: it makes `.command` and `.control` collide off Apple
   (`[.command, .control]` would be Ctrl+Ctrl) and makes a Super binding
   unspellable. Modifiers still match exactly (`IX-F` item 2).
5. **Labels.** The drawn menu's shortcut text off Apple names each key
   honestly: `.control` "Ctrl", `.command` "Super" on Linux and "Win" on
   Windows, `.option` "Alt", `.shift` "Shift", in that order (Ctrl+Super+Alt+
   Shift+K). Today's text labels `.command` "Ctrl" — false since the bridge
   maps GUI to `.command`; with `.primary` the default, a default shortcut
   reads "Ctrl+S" and is Ctrl+S.
6. **Unchanged**: `TextEditing` and `ControlKeys` already switch ⌘/Ctrl by
   platform (`TI-D`); `AppKitMenus` is macOS-only.
7. **Deferred**: a `"primary"` token in `Keymap`'s keystroke parser
   (`Keymap.modifierNames`) — `feat/key-focus` (C9) is changing the key
   pipeline now and a gpui-spelling claim (`secondary`) needs gpui's source;
   owner none (a later keymap item).

**Migration** (`docs/migration.md`): on Linux/Windows a shortcut written
without modifiers now fires on Ctrl, not Super; write `.command` to keep the
Super key. A portable app's `primaryShortcutModifier` constant can be replaced
by `.primary` or dropped.

**Cost if wrong.** An SDL app that deliberately used the default for Super
moves to Ctrl (one migration line). A Linux app binding Ctrl+key in a raw
`onKey` now also has a default shortcut on the same key if it declares one —
the shortcut pipeline order (`MN-J`) is unchanged, so which runs is as before
for an explicit `.control`.

## SG-C — The portable system fonts register monospaced and serif families

**Ruling.**

1. **`public static var designFamilies: [FontDesign: [String]]`** on
   `SystemFonts`, beside `defaultFamilies`/`fallbackFamilies`, and a
   `designFamilies:` parameter on `SystemFonts.resolver(...)` defaulting to
   it. For each design, the **first family in its list with an installed
   face** is registered through `PortableFontResolver.register(design:family:)`
   (TE-C item 1). Registration stores a name: **no face is read** until a
   request for the design resolves (SF-B laziness kept; the faces are already
   registered by name, `inCascade: false`). A design with no installed family
   registers nothing and resolves to the default face, as an unregistered
   design does today — never a trap.
2. **The lists** (the lane measures each family name as FreeType reports it
   and corrects a spelling before landing; a list is names, not files):
   - **Linux**: `.monospaced` — fontconfig's `monospace` (when `fc-match`
     exists), then DejaVu Sans Mono, Noto Sans Mono, Liberation Mono, Ubuntu
     Mono, FreeMono; `.serif` — fontconfig's `serif`, then DejaVu Serif, Noto
     Serif, Liberation Serif, FreeSerif; `.rounded` — none.
   - **Windows**: `.monospaced` — Cascadia Mono, Consolas, Courier New;
     `.serif` — Georgia, Times New Roman; `.rounded` — none (Windows ships no
     rounded UI face).
   - **macOS** (the portable system on macOS is tests and tools only;
     production uses CoreText, whose SF Mono/New York/SF Rounded answer is
     TE-C's): `.monospaced` — SF Mono, Menlo, Courier New; `.serif` — New York,
     Times New Roman, Times; `.rounded` — SF Pro Rounded, Arial Rounded MT Bold.
3. **`.rounded` off Apple resolves to the default face** (no family to name);
   documented on `designFamilies`. An app that has a rounded face installs it
   and calls `register(design: .rounded, family:)` itself, as before.
4. **fontconfig**: `fontconfigSansSerif()` generalises to one query per
   generic family (`sans-serif`, `monospace`, `serif`), its answer leading the
   list, behind an injectable query so the ordering is tested on every
   platform (CI's images have no `fc-match`).

**Evidence.** The CI images' fonts (above); `SystemFonts.swift` registers no
design today; `PortableFontResolver.register(design:family:)` and its
"unregistered design is the default face" rule.

**Cost if wrong.** A wrong list entry resolves to the next one or to the
default face (never a trap); a family name FreeType spells differently is
caught by the platform test on that platform.

**Measured (lane 1, 2026-10-09, macOS 27, FreeType's family names over
`SystemFonts.directories`).** The system's own SF Mono and New York are the
**hidden** families `.SF NS Mono` (`SFNSMono.ttf`, Light only) and `.New York`
(`NewYork.ttf`), not "SF Mono"/"New York"; those two names resolve only where
Apple's downloadable fonts are installed in `/Library/Fonts`. The lists are
kept (a dot-prefixed family is private to CoreText and is not named): on a
stock Mac `.monospaced` resolves **Menlo** (`Menlo-Regular`) and `.serif`
**Times New Roman** (`TimesNewRomanPSMT`); `.rounded` resolved SF Pro Rounded
on the measuring Mac (Apple's download installed) and is Arial Rounded MT Bold
on a stock one. Test 1.6's macOS arm computes the first installed name of
each list from the scan and asserts it exactly (Menlo/Times New Roman where the
downloads are absent). **Laziness, stated precisely**: registering a design
reads nothing; resolving one reads the design's face **and the cascade's
default face** (`resolve` loads the cascade, SF-C) — test 1.5 pins the exact
set after the first resolve.

## SG-D — The cross-platform manifest names the portable-text products on every platform

**Ruling.** MG-26 is a SwiftPM defect: a product reached conditionally through
the executable target (filtered out on macOS) and unconditionally by the test
target is dropped from the test target's module-map flags, so
`swift build --build-tests` on macOS fails with
`error: unable to resolve module dependency: 'CFreeType'` (and `CHarfBuzz`,
`CSheenBidi`, `CUnibreak`). The configurator measured both ways at `70ed000`;
**lane 1 re-measures at this branch, on both build systems, in a scratch
package depending on this checkout by path**, and records the verbatim lines.

1. `metalui new --cross-platform` and `docs/getting-started.md` name
   **`MetalUIPortableText` and `MetalUISystemFonts` unconditionally**;
   `MetalUISDL` keeps `condition: .when(platforms: [.linux, .windows])` and
   the traits. The generated `main.swift` is unchanged: its
   `#if canImport(MetalUISDL)` still compiles the SDL path only off macOS.
   Both targets are portable (`PC-A`), so they build on macOS; the cost is
   linking FreeType/HarfBuzz/libunibreak into a macOS app that never calls
   them — the lane measures the release binary's size with and without and
   records it.
2. `docs/getting-started.md` says why in two sentences, naming the defect, so
   a consumer who re-adds the condition knows what breaks.
3. The scaffold's env-gated build test gains a test target in a copy of the
   generated package (the generated package itself still has none), so this
   cannot regress unseen.
4. **If the defect does not reproduce at this branch** on either build system,
   items 1–2 are withdrawn (the condition stays — it saves the macOS link),
   item 3 stays as the tripwire, and the record says what was measured.
5. The upstream SwiftPM report text goes in the record (the lane writes it;
   nobody files it from an agent).

**Cost if wrong.** A macOS app links code it never runs (size measured).

**Measured (lane 1, 2026-10-09, at `c98c0cb` plus the fix; Xcode-beta's
toolchain, a scratch `metalui new Smoke --cross-platform --local <checkout>`
plus a `SmokeTests` target naming both products and constructing a
`PortableTextSystem`).** Item 4 does not apply — the defect reproduces:

| build | conditional products | unconditional |
| --- | --- | --- |
| default build system, `swift build --build-tests` | **fails**: `error: unable to resolve module dependency: 'CFreeType'`, and the same for `'CHarfBuzz'`, `'CSheenBidi'`, `'CUnibreak'` (`clang dependency scanning failure` in `SwiftDriver SmokeTests`) | builds, no `warning:` |
| native build system | builds | builds |
| `swift build -c release --product Smoke` (no test target in play) | 8 554 184 bytes | 10 706 552 bytes (+2 152 368, 2.15 MB) |

So the dropped module maps are the products' **C** modules, not the Swift
modules; `docs/getting-started.md`, the scaffold's comment and test 1.9's doc
quote the measured line.

## SG-E — Swift 6.4.0's asserts compiler on a `Component` whose content is a `switch`

**Ruling (frame; lane 3 completes it with its measurements).** MG-27 and
`LK-X` are one family: SILGen's `verifyLexicalLowering` assertion while
emitting a `Component`'s `ElementGroup` witness thunk (`prepaintGroup`), on
compilers built with assertions (Windows' 6.4.0+Asserts; the Mac snapshot
`swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a`). macOS's and Linux's release
compilers never fire, so **no CI job except Windows can see it**.

1. **Reduce first**, with the asserts snapshot on the Mac (and the UTM VM's
   6.4.0+Asserts ARM64 at `-c release` when `ssh metalui-win` answers): a
   one-file fixture against MetalUI reproducing MG-27's shape (a `Component`
   whose `content` is a builder `switch` over several cases, one a nested
   `Component` holding a loop, at `-c release`) and `LK-X`'s, each reduced by
   one-edit steps into a table like `LK-X`'s. Then a standalone file with no
   MetalUI import, if one exists, for the upstream report.
2. **One MetalUI-side candidate, measured, adopted only if it holds**: give
   `Component`'s `GroupPrepaint` the same heap box `PE-J` gave its layout
   (`ComponentLayout`) — a final-class box, so an outer aggregate holding a
   `Component`'s prepaint lowers a class reference, not the inner content's
   eager-move `Array` leaf. Adopted only if (a) both fixtures compile under
   the asserts snapshot in debug and release, (b) the full suite is green
   with the count moved only by new tests, (c) 0 px in all fourteen images,
   (d) every work/allocation/stack-budget pin it moves is named and justified
   (one allocation per `Component` per frame is the expected cost). Other
   candidates the reduction suggests may be tried under the same four gates.
3. **Otherwise no source change**: the workaround (the looping branch, or the
   nested looping `Component`, becomes a `@MainActor` function returning
   `some Element`/`some ElementGroup` — `LK-X`'s rule, extended to `switch`
   branches) is documented prominently in `docs/packaging.md` (the Windows
   release build) and, in the Record phase, as a CLAUDE.md CI hazard.
4. **A guard either way**: an env-gated test
   (`METALUI_RUN_ASSERTS_COMPILER_TEST=1`, the toolchain path from
   `METALUI_ASSERTS_TOOLCHAIN`, default the snapshot's) that builds a scratch
   package holding the fixtures against this checkout. With a fix: the trigger
   shape compiles. Without: the workaround shape compiles **and** the trigger
   shape still fails with the assertion — a tripwire that reddens when a
   toolchain fixes it, so the workaround note can go. It counts while skipped
   (fifteen env-gated tests with spec test 1.9 — amended by `SG-H` item 7).
5. The upstream bug text (title, the reduced file, the exact assertion and
   frames, toolchain versions) goes in the record.

**Cost if wrong.** A box that does not cure the crash costs an allocation per
`Component` per frame for nothing — gate (a) prevents it landing.

## SG-F — `Window.drawnChromeHeight`, and explicit size limits are measured below the drawn chrome

**Ruling.**

1. **`public var drawnChromeHeight: Pixels { get }`** on `Window`: the height
   MetalUI draws above the root in this window — the drawn menu bar (`SG-A`,
   25) plus the drawn toolbar strip (`MD-K`, 39) — as the last adopted frame
   laid them out; **0** where the platform shows its own (AppKit) and before
   the first frame. Read-only (guarded). MetalUI-only (inventory **M**).
2. **An explicit `minSize`/`maxSize` is a size of the content below the
   drawn chrome**: where chrome is drawn, the limits sent to
   `setContentSizeLimits` add `drawnChromeHeight` to the height axis (an
   infinite maximum stays infinite). AppKit's limits are `contentMinSize`/
   `contentMaxSize`, which exclude its toolbar, so a portable app's
   `minSize` now means the same rect on both platforms. The content-measured
   limits (`.contentMinSize`/`.contentSize`) already add the strip
   (`Frame.computeRootLayout`); they add the whole chrome now.
3. Re-sent when the chrome changes (a toolbar appearing, the bar's first
   build), through the existing `reconcileContentSizeLimits` after every
   built frame — no new call site. (Lane 1: the call in `Window.adopt` moved out of the
   `windowResizability != .automatic` branch, so it runs under `.automatic`
   too — there `contentLimits` stays empty and only the explicit limits plus
   the chrome reach the platform; an unchanged pair sends nothing. Mutation,
   on `58fe672`, `Window.adopt`'s spelling: the call moved back inside the
   `if` — the full unfiltered native suite reddens
   `anExplicitMinimumIsMeasuredBelowTheDrawnChrome` (2.20) at
   `WindowSizingTests.swift:414` and `:423`, nothing else beyond the five
   screen-lock `AppKitPresentationTests`; restored, `git status` clean.)
4. `ToolbarStrip.height` stays internal; the strip's and bar's heights are
   documented on `drawnChromeHeight`.

**Migration** (`docs/migration.md`): an SDL app that added the strip's 39 to
its `minSize` removes it.

**Cost if wrong.** An app relying on `minSize` including the strip on SDL gets
a window 39 (or 64) points taller at minimum — visible, never clipped.

## SG-G — Scope, lanes and the parallel branches

1. *(Superseded by `SG-H` item 5: lane 1 takes `SG-B` item 5 and `SG-F`'s strip term; lane 3 may run concurrently in a sibling worktree.)* **Three lanes, run one after another** in this worktree (spec §4): lane 1
   `SG-B`'s modifier and defaults, `SG-C`, `SG-D`; lane 2 `SG-A`, `SG-F` and
   `SG-B`'s menu adoption and labels; lane 3 `SG-E`. Source files are
   disjoint; the generated census (`closeout-public-api.tsv`) and the
   inventory map take rows from lanes 1 and 2 in that order.
   `docs/migration.md`, `docs/divergences.md` and
   `docs/verification/human-checks.md` are lane 2's alone (lane 1's and lane
   3's text is given in the spec).
2. **Parallel branches.** `feat/app-shell` (C8) adds members to every
   `Platform`/`PlatformWindow` conformer, including the compile-guard
   conformers `SG-A` item 1 edits — conflicts are textual and additive (keep
   both). `feat/key-focus` (C9) touches `KeyboardShortcut.swift` (line 22,
   `Hashable`) and `Keymap.swift`'s documentation only; `SG-B` edits line 79's
   default and nothing in `Keymap.swift`. `feat/controls-looks` (C10) and
   `fix/clip-nested-flattening` (C19) are in PR: merge master when it moves.
3. **Not moved**: identity and retention (the seven slots; `$menubar` is a
   name), hit testing's one ranking, accessibility bridges, animation, focus,
   `List`, `Deferred`, text input. The fourteen offscreen images read 0 px
   (no window there has an `App`, so no bar; no default shortcut is drawn).

## SG-H — Critic review of the design (2026-10-09): six corrections, one rejection, the parallel plan

**Ruling.** A review of `a7b38fc` against the source at `0b400b4` and master
`9ad2254`. The probe was re-run (default build and the `PRIMARY`/`PLATFORM`
arms): stdout and both refusals byte-identical to its header. Corrections,
each made in place in `SG-A`/`SG-E`/`SG-G` and the spec:

1. **The drawn Edit items are enabled only while a text field is focused.**
   `SG-A` item 4 cited `AppKitMenus.deliverEditKey` as "exactly this" but let
   the drawn items run "with nothing focused … where any key goes". AppKit's
   `MetalHostView.validateMenuItem` disables the seven Edit selectors unless a
   caret is set (`MN-K`). Without the same rule a drawn Select All with
   nothing focused would be delivered as `.primary`+A and run a `Button`
   shortcut or an app command bound to that key — a menu row running an
   unrelated action, which AppKit never does. Pinned by spec 2.11's new arm.
2. **Delete is `\u{7f}`**, not `\u{f728}`: `MetalHostView.delete(_:)`
   delivers `"\u{7f}"` with no modifiers; one path means one key.
3. **A `CommandGroup(replacing: .undoRedo/.pasteboard)` replaces the drawn
   Edit items** as it replaces AppKit's — `SG-A` item 3 said "standard items
   kept" unconditionally. Spec 2.6 gains the arm.
4. **A title opens on the click, not the press.** The title is an `onClick`
   (`SG-A` item 7, chosen so no new handler site is owed), which fires on
   release; `SG-A` item 8 said "press". Native Windows/GTK bars open on the
   press and allow press-drag-release onto a row; the drawn bar does not.
   Recorded in divergence 195's text by lane 2 (no new label). Cost if wrong:
   a press-drag-release user gets nothing until release, then the menu.
5. **Lanes rebalanced; lane 3 parallel.** Lane 2 held ~20 tests and every
   menu-bar file while lane 1 was small. `SG-B` item 5 (labels,
   `MenuPanel.shortcutText`, test 2.2) and `SG-F` over the **toolbar strip**
   (which exists at the base, so 2.19's strip arms, 2.20 and guard 2.21b
   separate without the bar) move to lane 1; lane 2 adds the bar's 25 and its
   arms. Lane 3 (`SG-E`) shares no file with lanes 1–2 and needs nothing they
   add, so it **may run concurrently** in a sibling worktree
   (`smk-gaps-asserts`, branch `fix/smk-port-gaps-asserts` from this HEAD),
   merged after lane 2 and verified on the merge. Lanes 1 → 2 stay
   sequential: lane 2 spells `.primary`, the labels and `drawnChromeHeight`.
   Splitting lane 2 itself was considered and **rejected**: its files
   (`Window`, `Frame`, `MenuSession`, `Commands`) are one feature's, and a
   split would put two agents on `Window.swift`'s key dispatch. Generated
   files are re-generated after a merge, never hand-merged.
6. **Baseline moved.** Master moved to `9ad2254` (GX-Y, `Frame.swift`/
   `RenderEffects.swift` only, no file of this design); merged at `57e02a4`.
   Counts are re-taken there by lane 1 before its first commit and the pixel
   comparison's base is `57e02a4`.
7. **Two counting/gate omissions.** Env-gated tests are fifteen after 1.9 and
   3.2, not fourteen (`SG-E` item 4). `SG-E` item 2's box changes
   `Component`'s public `GroupPrepaint` witness type: a fifth gate — doc
   comment, inventory row, re-recorded census — if it lands.

**Rejected: spelling `SG-F` as a safe-area inset.** SwiftUI's macOS toolbar
is outside the content view (the content is laid out below it, not under it
with an inset), MetalUI lays the root out below the drawn chrome the same way
(`MD-K`), and safe areas are outside the product boundary (`PB-A`). A
read-only height is the honest spelling; `drawnChromeHeight` stands.

**Checked and standing** (no change): every `Platform` conformer is in the
spec's list (`AppKitPlatform`, `SDLPlatform`, the `SDLLifecycleTests`
wrapper, `Fakes`, `AppIconCompileGuards`, `CommandsCompileGuards`; the
trait-off `SDLPlatform` is an unavailable stub, not a conformer); the nine
`CommandGroupPlacement`s are all placed by `SG-A` item 3, so no command
becomes unreachable in the drawn style; the fourteen images are rendered over
`FakePlatformWindow` with no `App` and none shows the menus demo; the SDL
bridge's modifier constants are already converted with `UInt32(...)`;
`mui_push_event` round-trips through `SDL_KMOD_*`, so 1.4's bridge mutation
reaches; key-focus (C9) changes `dispatchAction`/adds `dispatchKeyPress` in
`Window.swift` but not the unclaimed-key stage F10 joins, and its `KF-X`
reads `commandShortcuts`, which `SG-A` leaves unchanged.

