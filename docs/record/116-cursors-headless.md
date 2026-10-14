# 116 — Image cursors and a supported headless SDL launch (items S4 and S8)

Branch `feat/image-cursors-headless` from `fb9a7e42` (retained subtrees, §109), merged at the Record phase with master
`ceca59f6` (§111 hot paths, §112 SDL chrome, §113 image decoding). Master held no record 116 (111–113 are the other
branches' and 114–115 are other lanes' reservations), so §116 stands, no renumbering. User request 2026-10-02
(gpui-gap priority list, items S4 and S8; **not a plan task**), reported as MetalCreator's SDL-port gap 8 and XP-G9
(developer-c0, 2026-10-13/14; read, never edited). Spec
`docs/superpowers/specs/2026-10-14-cursors-headless-design.md`; rulings `IC-A`…`IC-R` in the new decisions doc
`docs/superpowers/2026-10-14-cursors-headless-decisions.md` (next unused `IC-S`); probe
`docs/probes/swiftui-image-cursor.swift`; human checks group `IC`. Divergence 465 added (range 465–474; 466–474
unused).

**Status: LANDED — every agent-doable clause is built; the cursor's look, the SDL hand and zoom recipe on real
drivers and the Windows run are owed to a human or to CI** (`docs/verification/human-checks.md` group IC). Two
lanes (A: S8 headless launch, B: S4 image cursors), each red first, each with a verifier (`ok: true`), then this
Record phase merged master, re-took the suite and the counts.

## §0 What the two items asked

**S4.** `PointerStyle` had twelve statics and no custom image: on SDL grab showed `MOVE` and zoom showed the arrow
(`CI-H` item 8), and `image`/`shape` were absent by `CI-A` because an image cursor adds an enum case (`CI-AC`). SwiftUI
(macOS 15) has `PointerStyle.image(_:hotSpot:)` and `.shape(_:eoFill:size:)`. **S8.** MetalCreator's CI smoke test opens
the real window on Linux and Windows with no display (Mesa llvmpipe, WARP), runs until a `.task` has run in the first
frame and exits 0; the only route was `@_spi(Checks) SDLPlatform(hiddenWindows:offscreenRenderers:)` (`TF-C`, `TF-E`,
`WS-B`), so an app's smoke test imported SPI. Baseline at `fb9a7e42`: **3717 tests in 3 suites**, 0 goldens, 234
typecheck guards.

## §1 What landed

**The seam** (`IC-A`). `PlatformPointerStyle` gains `case image(PlatformCursorImage)`, the `CI-AC` case: an outside
`PlatformWindow` conformer's exhaustive `switch` owes an arm or `default:` (`docs/migration.md`); no requirement is added
to `PlatformWindow` or `Platform`. `PlatformCursorImage` (`MetalUIPlatform/PointerStyle.swift`, public, `Sendable`,
`Hashable`) carries the `ImageTexture` itself, `scale`, the hot spot in points from the top-left, and the read-backs
`pixelWidth`, `pixelHeight`, `pointWidth`, `pointHeight`. Its public initialiser exists because the `Backends/SDL`
package cannot reach `package` API. **Equality and hash are the texture's identity**, the scale and the hot spot, never
the bytes: two bitmaps with equal pixels are two cursors, one bitmap rebuilt into an `Image` every frame is one.

**The API** (`IC-B`, `IC-C`, `IC-F`). `PointerStyle.image(_ image: Image, hotSpot: UnitPoint)`, SwiftUI's two-argument
spelling. MetalUI's `Image` wraps exactly one `ImageBitmap`, so there is no other `Image` kind to refuse; `resizable()`,
`interpolation` and the label are ignored (probe `I5`). Measured: the cursor's point size is `pixels / scale` (`I1`,
`I4`), the hot spot `UnitPoint x point size` from the top-left (`I1`–`I3`). **A hot spot outside the unit square clamps
per axis** (SDL refuses one off its surface; SwiftUI's own reading for `(2, -1)` was `(32, 16)`, not understood,
probe `I6`): **divergence 465**. A bitmap beyond a platform's cursor size limit leaves the current cursor (`IC-C` 3).
`Window` still sends on a change only (`CI-J`): identity decides, so a rebuilt `Image` of the same bitmap sends once.

**AppKit** (`AppKitCursor.swift`, `IC-D`). An `NSCursor` from one `NSBitmapImageRep` wrapping the texture's pixels as
stored (premultiplied, never re-premultiplied: `AI-E`), `NSImage` size = the point size, hot spot in AppKit's top-left
image coordinates; a per-window cache bounded at 16, least recently used out.

**SDL** (`SDLCursor.swift`, `SDLBridge.c`, `IC-E`, `IC-O`, `IC-R`). `SDL_CreateColorCursor` from an RGBA32 surface of
`SDLIcon.straightRGBA` (the one un-premultiply, `AI-F`), hot spot in surface pixels; an integer scale >= 2 gives a
box-downsampled primary and the bitmap as an alternate image. The table is `SDLImageCursorTable<Key, Handle>` (pure
Swift, generic over key and handle so its pins run on every driver): bounded at 8, least recently used out, a cursor SDL
still shows is *parked* and destroyed by the next sweep that no longer shows it, a refused creation is not stored, and
`removeAll()` runs on the last window close and on platform deinit. The table is the **platform's** (the cursor is
process-global, `CI-S`). The bridge exports recorders (`mui_cursor_created_count`, `_destroyed_count`, `_live_count`,
`_attempt_count`, `_set_count`, the last creation's width, height, hot spot, alternate count and `_last_pixel(index)`)
that record in the production path; `SDL_SetCursor` is skipped for the cursor already shown. SDL's hand and zoom
statics stay system cursors (`CI-H` item 8); **no art is bundled** and the recipe is the app's own `.image` with a 1x
and a 2x bitmap (`IC-H`, `docs/guides/input.md`). `.shape(_:eoFill:size:)` is **carried** (`IC-G`): `size:`, colour and
hot spot are unprobed, and an app rasterizes to an `ImageBitmap`. The headless platform records the `.image` value
`Window` sent (`IC-I`, `HT-X` 1); `TestWindow.pointerStyle` reads it, no new `TestWindow` API.

**The headless launch** (`IC-J`…`IC-M`, `IC-P`, `IC-Q`; `SDLPlatformOptions.swift`). `public struct SDLPlatform.Options`
(`hidesWindows`, `rendersOffscreen`; statics `.default` and `.headless`) and `public convenience init(options:)`;
`init(hiddenWindows:)` equals `Options(hidesWindows:)`; the trait-off unavailable stub declares the same `Options` and
`init(options:)` so a call names the trait. `Options.headlessIfRequested(environment:)` returns `.headless` when
`METALUI_SDL_HEADLESS` is **exactly `"1"`** and is a pure function a test calls with a dictionary; `SDLPlatform.init`
never reads the environment (an inherited variable must not hide a library user's windows). The `@_spi(Checks)
init(hiddenWindows:offscreenRenderers:)` stays and forwards (`IC-L`), not deprecated. The recipe is in `docs/testing.md`
("A CI smoke test of the real window", linked from `docs/packaging.md`); `HeadlessLaunchCheck` in `Backends/SDL` is that
recipe verbatim against a plain import. `IC-Q`: a `.task` can run in the first frame, before `platform.run()` starts,
and a `stop()` from the task is undone by `run()`, so the recipe sets a flag in the task and calls `stop()` from the
display-link tick (`iterations=1` on macOS), bounded by an iteration count, never a clock (`IC-P`).

**Demo and guides.** `METALUI_CANVAS_DEMO=1` gains a "ring" cell in its pointer strip (a generated bitmap, its hot spot
at the ring's centre). `docs/guides/input.md` has the image-cursor block (compiled mirror in
`GuideMirrorsLane1.swift`, `DG-C`) and `docs/guides/cross-platform.md` the headless block (a `text` fence, `DG-L`).

## §2 Tests and guards, per file

Baseline 3717 tests / 234 guards at `fb9a7e42`.

| file | what it holds |
|---|---|
| `Tests/MetalUITestingTests/ImageCursorTests.swift` | 6 tests over `TestWindow` (plain imports; also run in the Linux image's root set): `anImageCursorSendsItsPointSizeAndHotSpot`, `aHotSpotOutsideTheUnitSquareClampsToTheImage`, `aBitmapRebuiltEveryFrameSendsOneCursor`, `twoBitmapsWithEqualBytesAreTwoCursors`, `aNilStyleOutsideAnImageCursorKeepsItAndAnInnerStyleBeatsAnOuterImage`, `anImageIgnoresResizableAndInterpolation` |
| `Tests/MetalUITests/AppKitImageCursorTests.swift` | 2 tests: `appKitImageCursorHasTheImagesPointSizeHotSpotAndStoredPixels`, `appKitCachesAnImageCursorPerImageAndBoundsTheCache` |
| `Tests/MetalUITests/ImageCursorCompileGuards.swift` | 2 guards: `anOutsideSwitchOverPlatformPointerStyleOwesTheImageCase` (with its `default:` separating arm), `aPlatformCursorImageCanBeBuiltFromAPlainImport` |
| `Tests/MetalUITests/SDLTraitCompileGuards.swift` | 1 guard `anSDLPlatformWithoutTheSDLTraitNamesTheTraitForItsOptionsInitialiser` (spec 22; prints `IC-22 … succeeded=`) |
| `Tests/MetalUITestingTests/GuideMirrorsLane1.swift` | the image-cursor guide block's mirror (counted in `GuideDocCheck`, no new test function) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLImageCursorTests.swift` | straight-alpha pixels, hot spot in surface pixels with the alternate, system cursors unchanged for grab and zoom, not set twice, last-close destroy; the pure table's reuse, ninth-image eviction (never the current) and parked-destroyed pins. All run on every driver: measured in the Linux image, the offscreen driver creates colour cursors (`IC-R` 3) |
| `Backends/SDL/Tests/MetalUISDLTests/SDLHeadlessLaunchTests.swift` | `headlessOptionsHideWindowsAndRenderOffscreen`, `theEnvironmentConvenienceReadsOnlyTheValueOne`, `theSPIInitialiserStillForwards`, `aHeadlessAppRunsItsTaskAndExits` (launches `HeadlessLaunchCheck` as a child process, bounded by a deadline that kills only that child, ungated in the Linux image) |

Counts are in §6. Every new SDL helper that creates an `SDLPlatform` arms `armMainRunLoopExitCheck()`; every C enum
constant is converted explicitly.

## §3 Probes

`docs/probes/swiftui-image-cursor.swift`: the pointer-arm instrument of `swiftui-input-apis.swift`, positive control `I0`
(`NSCursor.crosshair.set()` reads back as crosshair), separating arms the three hot spots and the two image sizes.
Recorded 2026-10-14 (macOS 27.0.1, Swift 6.4, screen locked, twice, byte-identical): point size = pixels / scale (`I1`
vs `I4`); hot spot = unit point x point size, top-left (`I1`–`I3`); `.resizable()` changes nothing (`I5`); hot spot
`(2, -1)` reads `(32, 16)`, **not understood**, so MetalUI clamps (`I6`, divergence 465); an outer `nil` does not remove
an inner image style (`I7`). SwiftUI's rep is always 2x on a 2x display. gpui has no image-cursor API of this shape.

## §4 Red runs

- Lane A: `3b847bb9` failed at `HeadlessLaunchCheck/main.swift:35:42 error: extra argument 'options' in call`
  (`SDLPlatform.Options` absent); green at `bcacfd54`.
- Lane B: `f9d80e7b` red tests 1–17 against a tree without `PointerStyle.image`; green at `30314c09`; `d3c919ae` ungated the
  SDL cursor tests after the offscreen driver was measured to create cursors.
- The critic round (`8c0f684d`) moved `IC-O`: tests 13–15 were to be gated on a driver that creates cursors, which would
  have skipped them in the Linux image, exactly where they must run; the table became pure Swift.

## §5 Mutation tables

**What this phase can state.** The implementers' own tables were not handed to the Record phase; what follows is what the
verifiers re-ran (each on the unmutated suite first, `git status --short` clean after), plus the mutation the spec names
for every pin (spec §5, the instrument each pin was written to redden). **The spec's list is a plan, not a result.**

| lane | mutation (spelling) | reddened | by whom |
|---|---|---|---|
| A | `Options.headlessIfRequested` accepts any non-nil value (`SDLPlatformOptions.swift`), `Backends/SDL` full suite | `theEnvironmentConvenienceReadsOnlyTheValueOne` (6 issues) | lane A verifier |
| A | the SPI `init(hiddenWindows:offscreenRenderers:)` forwards `rendersOffscreen: false` (`SDLPlatform.swift`), `Backends/SDL` full suite | `theSPIInitialiserStillForwards` (2 issues) | lane A verifier |
| B | the hot-spot clamp removed (`unit(...)` replaced by a raw `Float` conversion in `PointerStyle.image`), **filtered** to `ImageCursorTests`, `PointerStyle`, `aHotSpot` | `aHotSpotOutsideTheUnitSquareClampsToTheImage` | lane B verifier |

**Scope caveat (lane B verifier).** The one lane B mutation above was run filtered, not on the full suite; the
implementer's other mutations were also filtered and were read, not re-run. The unmutated full suite finished normally on
an unlocked screen, so the six tests a locked screen skips have a green full-suite run (§6).

## §6 Green pins that prove less than they look

- **`headlessOptionsHideWindowsAndRenderOffscreen` (test 18) is partly tautological**: its `#expect(platform.options.rendersOffscreen)`
  re-checks the value just compared with `.headless`. The behavioural pin is `aHeadlessAppRunsItsTaskAndExits`, which reddens
  a `.headless` without offscreen renderers only **in the Linux image** (the `offscreen` driver, where a window presents no
  frame); on macOS that mutation is caught only by the options-value checks. Carried (§9).
- The docs/testing.md recipe is a `text` fence and so not compiled; `HeadlessLaunchCheck` is its compiled twin and
  defines `textSystem` with `portableTextSystem()`. The recipe now carries a comment saying where `textSystem` comes from (Record phase).
- A cursor's look, its hot spot on the clicked pixel and its crispness at 2x are not seen by any test: the recorders pin what
  the bridge was asked for, `NSCursor` read-backs pin the AppKit object. Group IC.

## §7 Demo comparison

No scene, renderer, shader or default tree changed: a cursor is set at the platform, never drawn into a scene, and the
canvas demo's ring cell is behind `METALUI_CANVAS_DEMO=1`. The lanes read 0 px in the fourteen offscreen images against
`fb9a7e42`; **this phase did not re-take the fourteen images on the merged tree** (master's own branches each report 0 px
against the same base). `DemoFrameDeterminismTests`' `Expected.swift` is unedited.

## §8 Hazards

- **A seam case, not a requirement.** An outside conformer fails to compile only where its `switch` is exhaustive; a
  `default:` hides the new case and shows the arrow. The migration table names it.
- **A `.task` in the first frame runs before `platform.run()` on macOS.** A `stop()` from the task is undone by `run()`
  (`IC-Q`): stop from the display-link tick.
- **Destroying the cursor SDL shows makes SDL fall back.** The table parks it (`IC-E` 3, `IC-R` 1).
- **`SDLCursorTable` was taken.** It is the system-cursor enum (`CI-H` item 8); the image table is
  `SDLImageCursorTable`.
- **`mui_cursor_last_alternate_count`**: `SDL_GetSurfaceImages` counts the surface itself, so the recorder subtracts one.
- The root manifest declares no `MainQueueDrainCheck` (nor `HeadlessLaunchCheck`): they are `Backends/SDL/Package.swift`
  executables, which is why `Options` had to be public.
- A cursor bitmap an OS refuses (size limits) leaves the current cursor; the sizes are unmeasured (check IC1).

## §9 Deferrals, with owners

| item | why | owner |
|---|---|---|
| `PointerStyle.shape(_:eoFill:size:)` | `size:`, colour and hot spot unprobed (`IC-G`); additive later over the same `.image` case | a follow-up item when an app asks |
| bundled hand and zoom art for SDL | a design asset and a notices entry (`IC-H`) | none; the recipe |
| `columnResize(directions:)`, `rowResize(directions:)` | still `CI-A` | none |
| per-platform cursor size limits | platform-specific; leaves the current cursor | human check IC1 reports them |
| Wayland and X11 colour-cursor behaviour | not machine-testable here | Linux CI and IC1 |
| a behavioural macOS pin for `rendersOffscreen` | test 18 re-checks its own options value (§6) | the next SDL item; the Linux image pin stands |
| Windows run (D3D12 / WARP) of the cursor and headless pins | no Windows machine in this phase | Windows CI on push; IC4 |

## §10 Merge with master (2026-10-14, `ceca59f6`)

Master had moved 45 commits past `fb9a7e42` (§111 hot paths, §112 SDL chrome, §113 image decoding). The merge auto-resolved
the sources and conflicted in three documents only: `docs/divergences.md` (465 beside master's 425, 426, 435: both kept),
`docs/verification/human-checks.md` (group IC beside HP, IB and CW: all kept, IC first as merged) and
`docs/probes/closeout-public-api.tsv` (a generated file: taken from master and **re-recorded** with
`docs/probes/closeout-public-api.sh`, 3587 rows). The inventory map merged cleanly. No source edit was needed after the
merge. The number 116 stood (§114, §115 are other lanes').

## §11 Final counts

Measured by the Record phase on the merged tree (`swift package clean`, then `swift build --build-system native
--build-tests`, then the unfiltered `swift test --build-system native --no-parallel`), on a machine loaded by other
workflows (the run took 713 s):

- **Root: `Test run with 3811 tests in 3 suites passed`**, 0 issues recorded (the screen was unlocked, so the
  `AppKitPresentationTests` sheet issues of a locked run did not appear), 0 `error:`, the only `warning:` SwiftPM's
  `--build-system native` deprecation notice, `FR-J no-argument frame: succeeded=true`, `IC-22 … succeeded=false` carrying
  the trait's remedy. Master at the merge was 3799 (§112), so the branch adds **12 tests**: 6 `ImageCursorTests`, 2
  `AppKitImageCursorTests`, 3 guards (two in `ImageCursorCompileGuards`, one in `SDLTraitCompileGuards`) and the guide
  mirror's test. **Typecheck guards 241 (238 + 3)**, counted by arithmetic from master's recorded 238 and the three new
  guards, not re-counted by a log grep. The baseline at `fb9a7e42` was 3717 / 234.
- **`swift build --build-tests`, the default build system: 0 `warning:`**, exit 0.
- **`Backends/SDL` on macOS** (`swift test $(python3 scripts/fetch-accesskit.py --print-flags)`): 30 + 157 passed (master's
  30 + 145 plus the branch's 12).
- **`Backends/SDL` in `swift:6.4-noble`** (`metalui-portable`, volume `metalui-sdl-build-cursors-headless`,
  `SDL_VIDEO_DRIVER=offscreen`): 30 + 154 passed (the three fewer are the pins the offscreen driver gates, `CW-`); the cursor
  pins and `aHeadlessAppRunsItsTaskAndExits` run there ungated. The root portable test set in the image was **not**
  re-taken after the merge (lane B read 233 + 79 before it).
- **Public API census 3587**; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- **Divergences**: 465 added, **156 live** (the header's count; the next label stays the merge's, 466–474 unused).
- **Not re-taken here**: the fourteen offscreen images on the merged tree (lanes: 0 px against `fb9a7e42`; §7), Windows
  (D3D12, WARP), a real window, the `docs/probes/swiftui-image-cursor.swift` run (recorded 2026-10-14 by the designer).

Docs changed by this phase: this record, `docs/record/README.md` (row), `docs/record/03-verified-on-real-hardware.md`
(looks owed), `CLAUDE.md` and `AGENTS.md` (the `IC-` rule and prefix, the `CI-` sentence, divergence count, counts bullet),
`README.md` (the pointer-style sentence), `docs/divergences.md` (header count), `docs/testing.md` (the recipe's `textSystem`
comment), the spec's Status, and the merge's three conflict resolutions. `docs/api-overview.md`, `docs/migration.md`,
`docs/verification/human-checks.md` (group IC) and the inventory map were written with the lanes and verified against
source here.
