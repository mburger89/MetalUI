# 70 — App icon

Branch `feat/app-icon` from `330f02b` (master: drag and drop merged, PR #36;
master's later `a985d23`/`5800703` cut `CLAUDE.md` to rules only and merged in
at `c8fea9f`). **Not a plan task**: the SwiftUI-alignment plan is
agent-complete; this is new feature work requested by the user on 2026-10-01.
Spec `docs/superpowers/specs/2026-10-01-app-icon-design.md`; rulings
`AI-A`…`AI-M` in the new decisions doc
`docs/superpowers/2026-10-01-app-icon-decisions.md` (next unused `AI-N`). **No
SwiftUI probe**: SwiftUI has no runtime icon API (measured against the macOS 27
SDK's `SwiftUI.framework` interface, decisions doc header), so the feature
claims no SwiftUI behaviour and is inventory class M.

**Numbering.** This record was written as §70 because the concurrent
`feat/metal-view` line was to take §69. Master then published §69 itself (the
frozen `CLAUDE.md`, `69-claude-md-full-2026-10-01.md`), so the metal-view
record must renumber at its own merge (§71 or later) if this line reaches
`master` first — the 24→25, 26→27, 28→29 precedent. §70 stays here: the spec,
the decisions doc, human-checks group O and the inventory map already cite it.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group O, §6). Two lanes, each red
first, both verified `ok: true`; the Record phase's close (§7) re-took the
suite, the counts, the inventory checks and the pixel comparison.

## §0 Baseline and design

- **Baseline** at `330f02b`: **2028 tests in 3 suites**, 0 goldens, 125
  typecheck guards, `Backends/SDL` 22 + 41, public census 1940 declarations
  in 99 families, 69 live divergences (next label 103).
- Before this branch nothing in `Sources/` or `Backends/` set an icon
  (`grep -rn "applicationIconImage\|SDL_SetWindowIcon"` read 0 hits): a bare
  `swift run MetalUIDemo` showed the generic executable icon.
- A design session and a critic round produced `AI-A`…`AI-K`. The critic round
  corrected three claims by measurement: `NSApplication.applicationIconImage`'s
  getter is a snapshot (never the assigned object, one 2× snapshot rep, the
  generic icon after `nil`) so the AppKit pin reads the platform's own stored
  image (`AI-I`); `S5` runs on `SDLPlatform`, not through `App`, because
  `MetalUISDLTests` does not depend on `MetalUI` (`AI-J`); `run()`'s
  re-assignment is unpinnable headless and is declared so (`AI-K`).

## §1 What landed

- **The API** (`Sources/MetalUI/App.swift`, `AI-A`, `AI-C`): one settable
  `App.icon: [ImageBitmap]`, default `[]`, application-level only (no
  per-window icon, no init parameter). An `App` that never assigns it never
  calls the platform; every assignment calls the platform exactly once,
  synchronously, with the list **normalized** — sorted by `width × height`
  ascending (stable), a repeated `width × height` pair dropped (first wins),
  the bitmaps' own `ImageTexture`s passed with no copy. `icon` reads back
  exactly what was assigned. Opening a window never re-sends it.
- **The seam** (`Sources/MetalUIPlatform/Platform.swift`, `AI-B`): a **defaultless**
  `Platform.setApplicationIcon(_ images: [ImageTexture])` — `AB-R`/`EV-AB`/`DN-C`'s
  rule — on `Platform`, not `PlatformWindow` (the icon is the application's).
  `ImageTexture`, not `ImageBitmap`, because `MetalUIPlatform` imports only
  `MetalUICore` and `MetalUIScene`. Implemented by `AppKitPlatform`,
  `SDLPlatform` and the test fake (`FakePlatform`, new in `Fakes.swift`,
  recording every call). Plain-import guard
  `aPlatformWithoutSetApplicationIconDoesNotCompile`.
- **AppKit** (`Sources/MetalUIAppKit/AppKitIcon.swift`, `AppKitPlatform.swift`,
  `AI-E`): `AppKitIcon.cgImage(from:)` wraps each texture's premultiplied sRGB
  bytes **as stored** (`premultipliedLast | byteOrder32Big`, no
  un-premultiply, no second premultiply); `image(from:)` makes one
  `NSBitmapImageRep` per texture inside one `NSImage` (every rep's `size` the
  largest's, so they are resolutions of one picture) and answers `nil` for `[]`.
  `AppKitPlatform` assigns `NSApplication.applicationIconImage` (`[]` restores
  the bundle's or the generic icon), keeps the image in `iconImage`, and
  re-assigns it in `run()` after `setActivationPolicy(.regular)` — **unpinned
  by design** (`AI-K`, human check O1).
- **SDL** (`Backends/SDL/Sources/MetalUISDL/SDLIcon.swift`, `SDLPlatform.swift`,
  `SDLBridge.c`, `AI-F`): SDL icons are **straight** alpha, so
  `SDLIcon.straightRGBA(_:)` un-premultiplies in integer arithmetic (`a == 0`
  → 0; else `min(255, (c·255 + a/2) / a)`); `mui_icon_surface_create` builds an
  `SDL_PIXELFORMAT_RGBA32` surface row by row through `pitch`, the first
  (smallest) texture the primary and the rest alternates
  (`SDL_AddSurfaceAlternateImage`); `mui_window_set_icon` applies it. The
  platform applies the stored icon to every open window **and to each window
  opened afterwards**, destroying the surface at once. `[]` cannot clear on SDL
  (SDL3 has no way to restore a default; `NULL` is never passed, counted by
  `mui_window_set_icon_null_calls()`); a failed application (e.g. Wayland
  without `xdg-toplevel-icon-v1`) is not surfaced (`AI-D`), recorded only in
  `SDLWindow.iconResult` for tests. The pixel-format value Swift compares is a
  C-exported `uint32_t` constant, never a C enum's `rawValue` (the Windows
  hazard).
- **Invalid input** (`AI-D`): no new trap or refusal — an `ImageBitmap` is valid
  by construction (a zero side or a wrong byte count traps in
  `ImageBitmap.init`, already pinned by
  `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps`).
- **The demo** (`AI-G`): `MetalUIDemoContent.demoIcon()` — six square bitmaps,
  16 to 512 px, a `#2F6FEB` rounded square (radius 0.22 s) with a white disc
  (radius 0.28 s), classified per pixel centre, no anti-aliasing. Both
  `MetalUIDemo` and `MetalUISDLDemo` set `app.icon = demoIcon()` before opening
  a window. The icon is in no element tree.
- **Docs** (`AI-H`): `docs/packaging.md` (new; build-side, not framework API;
  macOS `.app` + `.icns` verified signed ad hoc and launched, Linux `.desktop`
  + hicolor verified by validator and layout, the Wayland window matching and
  the Windows `.ico`/`.rc` link step marked unverified where they are),
  human-checks group O (O1–O4), the API overview's "Application icon" section,
  a migration row, a README link, the inventory family `app-icon`.

## §2 Tests and guards, per file

Root suite **2028 → 2041** (+13; 0 removed). `Backends/SDL` `MetalUISDLTests`
**41 → 48** (+7), `ReplayFixtureTests` 22. Guards **125 → 126**. Goldens 0.

| file | tests | note |
|---|---|---|
| `Tests/MetalUITests/AppIconTests.swift` | 7 | lane 1: 1.1–1.7 — never-set sends nothing; one call with the bitmaps' own textures; smallest first, no repeated size; read-back as assigned; re-assign and clear; the demo icon's six sizes and its exact pixels |
| `Tests/MetalUITests/AppKitIconTests.swift` | 5 | lane 1: A1–A5 — one rep per texture; the `CGImage` carries the stored bytes; drawing adds no second premultiply (the whole 3×2 texture); `AppKitPlatform` sets the icon; `[]` makes no image |
| `Tests/MetalUITests/AppIconCompileGuards.swift` | 1 | G1.1 `aPlatformWithoutSetApplicationIconDoesNotCompile`, whole-file `typecheckFile` |
| `Backends/SDL/Tests/MetalUISDLTests/SDLIconTests.swift` | 7 | lane 2: S1–S7 (S7 macOS-only, added at the fix round) |

**13 = 7 + 5 + 1.** `Fakes.swift` gains `FakePlatform` (30 lines) — no
existing test changed. Helpers: 40 `typecheck` and **85** `typecheckFile`
guards (84 before; the new guard is whole-file), verified at §7. The new file
reads 1 by `grep -c canTypecheck`.

## §3 Red runs

- **Lane 1** (`39d18a9`): over a skeleton that stores `App.icon` but never
  sends it, `AppKitIcon.cgImage` answering `nil`, `image` an empty `NSImage`,
  `demoIcon` `[]`, and a protocol-extension default on the requirement — every
  new test red for its own reason (G1.1 red as `succeeded=false` for the
  default).
- **Lane 2** (`c5aa5b4`): over a skeleton (`straightRGBA` identity,
  `makeSurface` `nil`, `setApplicationIcon` empty, `iconResult` never set),
  `Backends/SDL` **22 + 47** (before S7), 6 issues, one per test S1–S6.

## §4 Mutation tables

Each applied to the green tree from a copy, the full unfiltered suite,
restored, `git status --short` clean after every one.

**Lane 1** (root suite, 2041 tests; full table in decisions doc `AI-L`):

| Mutation | Reddened |
|---|---|
| M1a `App.init` calls `setApplicationIcon([])` | 1.1, 1.2, 1.3, 1.5 |
| M1b `didSet` empty | 1.2, 1.3, 1.5 |
| M1c textures copied from the same pixels | 1.2, 1.3, 1.5 |
| M1d no sort | 1.3 |
| M1e no dedupe | 1.3 |
| M1f dedupe keeps the last | 1.3 |
| M1g `icon` rewritten to the normalized list | 1.4 |
| M1h call only when the count changes | 1.5 |
| M1i skip the call for `[]` | 1.5 |
| M1j drop the 512 | 1.6, 1.7 |
| M1k disc radius 0.30 s | 1.7 |
| M1l corner radius 0.18 s | 1.7 |
| M1m `openWindow` re-sends `icon` | 1.1, 1.2 |
| MA1 only the first texture becomes a rep | A1, A4 |
| MA2 un-premultiply before wrapping | A2, A3 |
| MA3 `.last` instead of `.premultipliedLast` | A2, A3 |
| MA4 `setApplicationIcon` body empty | A4 |
| MA5 `[]` returns early keeping the old image | A4 |
| MA6 `image(from: [])` returns `NSImage()` | A4 **by crash** (`NSImageCacheException`, no summary line — `AI-L` item 1); A5 only in a filtered run |
| MG1.1 a protocol-extension default | G1.1 |
| `AI-K` delete `run()`'s re-assignment | **none — unpinned by design** |

The verifier's own seven (V1–V7) re-ran the table's key rows and added: V2
`cgImage` byte order little-endian → A3; V3 sort descending → 1.2, 1.3; V4 assign
`nil` but keep `iconImage` → A4; V5 drop `rep.size` → A1; V6 `genericRGBLinear`
→ A2, A3; V1 a `Platform` default → G1.1. **V7 — dedupe on width alone —
reddened nothing.** 1.3's input has distinct widths and distinct heights except
the true duplicate, so width-only and height-only dedupe give the same answer:
"a duplicate is the whole `(width, height)` pair" (`AI-C` item 3) is only
half pinned. **Open, owner: none (minor)** — the verifier's remedy (a 32×64 and
a 64×32 after a 32², both kept, with V7 and a height-only twin recorded) is a
three-line test addition; not made on this branch because the Record phase
changes no source or test file.

**Lane 2** (`Backends/SDL` unfiltered, `PKG_CONFIG_PATH=.accesskit swift test
--no-parallel`; full table in `AI-M`): MS1 `straightRGBA` returns premultiplied
bytes → S1, S2; MS2 no clamp → S1 by trap (truncated run); MS3 `a == 0` keeps
colours → S1; MS4 w/h swapped → S2; MS5 surface from premultiplied bytes → S2;
MS6 alternate skipped → S3; MS7 first open window only → S4; MS8
`openSDLWindow` skips the stored icon → S5; MS9 `[]` keeps the last icon for new
windows → S6; MS10 `[]` passes `NULL` → S6 (the counter). **V7 (verifier):
`mui_window_set_icon` returns `true` without calling `SDL_SetWindowIcon` →
S7 only**; S4 and S5 stayed green because their `applied` is the C wrapper's own
answer, which is why S7 (SDL's Cocoa backend turns the window icon into
`NSApplication.applicationIconImage`, read from outside the wrapper) was added.
Off macOS `SDL_SetWindowIcon` itself stays unobserved (O3/O4).

## §5 Demo comparison

`docs/probes/demo-pixels/compare.sh <scratch> 330f02b HEAD`: **0 differing
pixels and identical scenes in all fourteen offscreen images** (lane 1 at
`0cba7da`; re-taken at the Record phase at `14e44f2`, §7). `DemoFrameDeterminismTests`'
`Expected.swift` unedited; `everyProductionTreeBuildsOnAOneMegabyteThread`
green. The icon is outside every tree, and both demos' `main.swift` change is
one assignment before `openWindow`.

## §6 Deferrals and human checks

- **Group O of `docs/verification/human-checks.md`, none performed (an agent
  cannot)**: O1 the Dock icon of `swift run MetalUIDemo` (also the only check of
  `run()`'s re-assignment, `AI-K`, and of "no blue icon lingers after Q"); O2
  the Dock icon of `MetalUISDLDemo` on macOS; O3 Linux X11 and Wayland (a
  generic icon under GNOME is the expected answer without
  `xdg-toplevel-icon-v1`); O4 Windows title bar, taskbar and Alt-Tab, sharp at
  a scaled display. The lock probe was not re-run for this branch (no
  window capture is owed: no tree changed).
- **`SDL_SetWindowIcon` itself** is observed only through the macOS Cocoa
  backend (S7); X11/Wayland/Windows delivery is O3/O4's.
- **`[]` on SDL** keeps the last icon on open windows (SDL3 has no restore),
  documented on the method (`AI-F` item 5); not a divergence.
- **A per-window icon** is additive later (`AI-A` cost-if-wrong); owner none.
- **Packaging**: the Windows link step and the Wayland window-to-entry
  matching are marked unverified in `docs/packaging.md`; the document says to
  package with the **default** build system (a resource-bundle placement
  measured in `AI-M` item 5).
- **No new divergence** (SwiftUI has nothing to diverge from); no divergence
  retired: **69 live, next label 103**.

## §7 Branch check (Record phase, 2026-10-01)

Taken after `swift package clean`.

- Native build: `swift build --build-system native --build-tests` — 0
  `error:`, the one `warning:` SwiftPM's native deprecation notice (lane 1 also
  read 0 `warning:` under the default build system).
- Unfiltered `swift test --build-system native --no-parallel`:
  **`Test run with 2041 tests in 3 suites passed after 114.137 seconds`**; the FR-J line present; the G1.1 line present.
- `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`): **22 + 48**, passed on
  macOS; a `swift:6.4-noble` container (`metalui-portable-ax`, lane 2): 22 + 45
  (the two macOS-only run-loop tests and S7 absent). Five environmental
  `warning:` lines predate this branch — four `ld: warning … libSDL3.0.dylib
  which was built for newer version 26.0` (one per linked product, Homebrew's
  SDL3) and one pkg-config `prohibited flag(s): -Wl,-rpath` — plus
  `AccessKitControlsParityTests.swift:83`'s unnecessary-`try`, none from this
  branch's source.
- `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` print nothing. Public census
  **1940 → 1943** (`App.icon`, `AppKitPlatform.setApplicationIcon`,
  `demoIcon`) in **100** families (`app-icon` new); `Platform.setApplicationIcon`
  is a protocol requirement, not a `public` declaration of its own, and its map
  row is kept so a future `public` spelling maps to the family.
- Pixels: `compare.sh <scratch> 330f02b HEAD` (`14e44f2`), controls non-zero as recorded: **0 differing, scene identical, all fourteen images**.
- Guards: raw `grep -c canTypecheck` over the four root test targets reads 128, two of them comments (`UnitSafetyTests`, `CloseoutCompileGuards`) = **126**.
- Counts **2041 / 0 / 126** tests/goldens/guards; `Backends/SDL` 22 + 48.

## §8 Adversarial branch check (2026-10-01, at `a767055`)

An independent re-take of 330f02b..HEAD after `swift package clean`.

- Native build: 0 `error:`, one `warning:` (SwiftPM's native deprecation
  notice). Default build system (`swift build --build-tests`): 0 `warning:`.
- Unfiltered `swift test --build-system native --no-parallel`:
  **`Test run with 2041 tests in 3 suites passed after 110.194 seconds`**; the
  FR-J line and `AI-B member required: without succeeded=false` present.
  Guards: raw `grep -c canTypecheck` 128, two comments → **126**.
- `cmp CLAUDE.md AGENTS.md` clean. Every `AI-` id cited anywhere resolves to a
  heading `AI-A`…`AI-M` (`AI-N` appears only as "next unused"); every
  backticked test or symbol name in the changed docs resolves in the source,
  except `assistiveAccessNavigationIcon` (a SwiftUI symbol, quoted as such) and
  record §03's pre-existing `theRunCounterIgnoresCallsMadeOffTheMainThread`
  (not this branch's text). No plan box ticked.
- `Backends/SDL` on macOS (`PKG_CONFIG_PATH=$PWD/.accesskit swift test
  --no-parallel`): **22 + 48**, passed. `swift:6.4-noble` container
  (`metalui-portable-ax`, from `git archive HEAD`): root builds with 0
  `error:`/`warning:` and runs **199 + 22 + 14** (plus a 6-test target);
  `Backends/SDL` builds (the two pre-existing environmental warnings only) and
  runs **22 + 45**.
- `compare.sh <scratch> 330f02b HEAD`: controls as at the Record phase; **0
  differing pixels, scene identical, all fourteen images**.
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- `docs/packaging.md` §macOS 1 re-run: the `sips`/`iconutil` loop over a
  1024² PNG gives `Mac OS X icon, … "ic12" type` and round-trips ten images —
  as the document says. Every other command there is labelled verified (with
  what) or unverified.

**Two mutations of this check's own design** (each from a copy, full
unfiltered suite, restored, `git status --short` clean after each):

| Mutation | Suite | Reddened |
|---|---|---|
| X1 `App.normalized` dedupes on **area** (`w·h`) instead of the `(w, h)` pair | root, 2041 | **none** (`Test run with 2041 tests in 3 suites passed`) |
| X2 `SDLIcon.straightRGBA` truncates (`c·255 / a`, no `+ a/2`) | `Backends/SDL`, 22 + 48 | `unpremultiplyingRestoresStraightAlpha` (S1), `anIconSurfaceIsRGBA32HoldingTheStraightBytesRowByRow` (S2) |

X1 widens §4's open V7 item: 1.3's sizes (16², 8×64, 32², 32²) have no two
distinct pairs sharing a width, a height **or an area**, so width-only,
height-only and area dedupe are all indistinguishable from the ruled pair
dedupe. The mutant differs on real input — a 32×64 and a 64×32, or a 16×64
after a 32², would lose one. `AI-C` item 3 stays half pinned; the remedy is
one more test input (e.g. 32×64 and 64×32 after 32², all three kept). Minor
(no shipping caller passes non-square icons), owner none, not fixed by this
docs-only check.
