# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift, with SwiftUI as the design authority. **Supported: macOS
(AppKit + Metal, the default), Linux and Windows** (`Backends/SDL`,
`App(platform:textSystem:)`, the portable text system; `XP-A`/`XP-B`,
`docs/superpowers/plans/2026-09-23-cross-platform-roadmap.md`). **iOS, iPadOS, tvOS, watchOS
and visionOS are an explicit product boundary** (`PB-A`, record §65): no UIKit
conformer, no touch, no safe areas, none planned.

**This file is rules only.** The full 2026-10-01 version (177 KB: every
milestone summary, count history, renumbering note, guard-by-guard tally and
per-stage narrative) is frozen verbatim at
`docs/record/69-claude-md-full-2026-10-01.md`; older snapshots are record §19
(2026-09-21) and §67 (counts history). Reasoning and history live in
`docs/record/` (`README.md` indexes it, one row per milestone). Citations in
the record were not all re-checked after later refactors — verify a test name
or grep before relying on it. **New milestones append their record to
`docs/record/` and add only the rule to its area's shard in `docs/rules/`** —
one or two sentences, not a summary.

`AGENTS.md` is a byte-identical copy for Codex (the shards are shared): edit `CLAUDE.md`, then
`cp CLAUDE.md AGENTS.md`; `cmp CLAUDE.md AGENTS.md` before committing.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`;
  per-milestone specs and plans in `docs/superpowers/specs/` and `plans/`.
  SwiftUI-alignment plan: `docs/superpowers/plans/2026-09-12-swiftui-alignment.md` (tasks 1–15;
  12 and 15 wait on human checks). **The source is the authority** over the
  2026-09-12 kernel/modifier specs.
- **Decisions docs:** `docs/superpowers/<date>-<milestone>-decisions.md`, or a
  milestone's own spec for prefixes without one. Read their "Carried…"
  sections before new work. Ruling ids are namespaced by prefix; **the prefix →
  document → next-id list is `docs/rules/decision-prefixes.md`** (a new prefix adds
  its row there). **To find the next unused id, read the file's last `## <PREFIX>-`
  heading, not its header** — headers have lagged. A decisions doc's "next unused"
  line moves in the commit that appends the ruling. A numbered citation of a
  lettered prefix (`LR-3`, `DN-3`, `AI-3`) is a typo.
- **Record:** `docs/record/NN-*.md`, one per milestone. When two lines publish
  the same number, the later merge renumbers and says so in its header.
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.
- **Public documents:** `docs/api-overview.md`, `docs/divergences.md` (every
  live SwiftUI difference — **178 live, next label 209** (207 never published and unused; 255 retired and 745–754 unused by LH; 735–737 used and 738–744 unused by BG; 705–714 unused by DT; 625–634 unused by C14-i; 635–638 used and 639–644 unused by L1; 645, 646 used and 647–654 unused by G1; 655–664 unused by E1; 665–674 unused by S11; 675–684 unused by S12; 685–694 unused by XP-G21; 695–704 reserved by C14-j; 715–717 used and 718–724 unused by CP; 455, 456 used by S3; 465 used and 466–474 unused by S4+S8; 425, 426 used and 427–434 unused by S1; 435 used and 436–444 unused by S2; 345–354 reserved by C14: 346 used, 345 refuted, 347–354 unused; 196–204 unused by C12, 215–224 unused by item 8, 226–234 unused by C15, 237–244 unused by C16, 256–264 unused by C20, 250–254 unused by C21, 267–274 unused by C25, 278–284 unused by C22, 285–294 unused by C24, 295–296 used and 297–304 unused by C23, 305–314 unused by C26, 315 used and 316–324 unused by C27, 325–326 used and 327–334 unused by C28, 189–194 unused by C9); retired labels are
  never reused), `docs/migration.md`, `THIRD-PARTY-NOTICES.md` (licences of the vendored C code and SDL3/AccessKit, per product), `docs/verification/human-checks.md`
  (groups A–Y, EL, BG, VL, RT, WS, AS, CL, KF, PF, SG, HT, OV, IF, BB, WD, SL, GC, GT, RF, MT, IM, GD, IV, GA, SB, HP, IB, CW, CB, IC, RK, SI, RO, FS, RG, AT, RL, AP, EX, GB, GS, BS, LZ, RZ, DT, CP, BG, LG, TL, TP, HX, BT and WA, **not run — an agent cannot**), `docs/verification/voiceover-script.md`.
- **Public-API inventory:** `docs/probes/closeout-public-api.sh` censuses every
  public declaration; `closeout-inventory-map.tsv` classifies each (A
  SwiftUI-aligned / D divergence / M MetalUI-only / X deprecated / R absent).
  **A new public declaration owes a map row and a doc comment**:
  `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` both print nothing when complete.

## Build and test

```bash
swift build
swift test --no-parallel
swift build --build-system native --build-tests && swift test --build-system native --no-parallel  # guards run
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # value exactly "1"
# also METALUI_TEXT_INPUT_DEMO=1, METALUI_CONTROLS_DEMO=1, METALUI_DND_DEMO=1, METALUI_LOOKS_DEMO=1, METALUI_METALVIEW_DEMO=1, METALUI_MENUS_DEMO=1, METALUI_SERVICES_DEMO=1, METALUI_LIST_DEMO=1, METALUI_RICH_TEXT_DEMO=1, METALUI_CANVAS_DEMO=1, METALUI_APP_SHELL_DEMO=1, METALUI_SELECTION_DEMO=1, METALUI_INVALIDATION_DEMO=1, METALUI_RETAINED_DEMO=1, METALUI_CHROME_DEMO=1, METALUI_CLIPBOARD_DEMO=1, METALUI_LAZY_DEMO=1
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
```

- **Counts (2026-10-31, `fix/run-until-idle-load` on master d2797c5d, `HT-Y`): root 4613 tests passed with `AppKitPresentationTests` skipped (screen lock not read; its 9 tests would bring an unfiltered run to about 4622, not measured), 0 goldens, 285 typecheck guards** (unchanged from record 168, not re-tallied by grep; `FR-J no-argument frame: succeeded=true` printed; incremental native build, not after `swift package clean`; record 171). A count is stale the moment a test lands: re-measure (`swift package clean`, native build, unfiltered `--no-parallel` run, `--build-system native` for the guards). The dated history of every earlier count, with its branch and lane readings, is frozen verbatim in `docs/record/159-counts-history-2026-10-27.md`; new milestones put their count in their own record, and this line is replaced, not appended to.
- **Read the printed counts, never the exit status.** Native prints one
  summary line ("in 3 suites"); the default build system may print several
  (sum them). Thirteen env-gated oracle/measure/build tests count while skipped.
- **`--no-parallel` always**: CoreText font registration and `malloc_logger`
  tests race under a parallel run. **Adding an AppKit test? Run the whole
  suite unfiltered** (`--filter` is a different program).
- **Guards skip silently** unless `.build/<triple>/debug/Modules` is where
  `#filePath` expects (default build system, `--scratch-path`, `-c release`
  all skip; the total does not move). Take guard counts under
  `--build-system native` and grep the log for
  `FR-J no-argument frame: succeeded=`. macOS CI sets
  `METALUI_REQUIRE_GUARDS=1` so a skipped guard fails (`CX-J`). Two helpers:
  `typecheck(_:importing:)` (fixture wrapped in a function) and
  `typecheckFile(_:importing:)` (whole-file Swift 6). **A guard about what an
  external module can write uses `typecheckFile` with a plain import** (`SA-P`).
- **`swift package clean` when the impossible happens** (SIGSEGV, no summary
  line, an impossible value, `Undefined symbols … direct field offset`):
  causes are the untracked shader header symlink
  (`Sources/MetalUIShaderTypes/include/`) and any new case/stored property on
  a public type crossing a module boundary.
- **No goldens, ever again** (stage 7a): a layout fact gets a native arm. No
  text fixture, ever (TX-B). `find Tests/MetalUILayoutTests -name "*.json"`
  reads 0 (not `find Tests` — `PortableTests/.build` holds JSON).
- **The manifest is two lists** (`PC-A`): targets importing no Apple framework
  are declared on every platform; the rest under `#if os(macOS)`. A new target
  goes in the list its imports allow. Linux/Windows CI build every portable
  target and run `MetalUILayoutTests`, `MetalUICoreTests`,
  `MetalUICrossPlatformTests`. A Darwin-only test there is gated per
  declaration with `#if canImport(Darwin)` (`PC-B`).
- **`Backends/SDL`** is a package (`MetalUISDL`) whose library targets the
  root manifest also declares by `path:` (`PX-H`, below). It links AccessKit's
  C bindings, fetched not vendored (`AX-A`): run
  `python3 Backends/SDL/scripts/fetch-accesskit.py` once, then from
  `Backends/SDL` build/test with `swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)` (**not** `PKG_CONFIG_PATH`: the pkg-config route is gone,
  `PX-I`). macOS CI does not run its tests.
- **Windows locally: the UTM VM** (`ssh metalui-win`): recipe, x64 emulation and
  the console-session rule are in `docs/rules/windows-vm.md`.

### Targets and import rules (each fails silently on macOS)

Twenty-four one-way-dependent targets (`MetalUIPath`, `GX-B`, the last two
`MetalUIScaffold` and `MetalUICLI`, `SC-A`, and portable `MetalUITesting`, which imports
only `MetalUI` and `MetalUIScene`, `HT-A`) plus `Tests/MetalUITestSupport`;
`MetalUIDemoContent` holds the demo tree so tests can import it (`LR-S`).
Linux/Windows CI (`scene-linux`, `root-windows`) is the only place most of
these violations show.

- `MetalUILayout` imports only `MetalUICore` and declares no `Style` (`LR-FM`).
- `MetalUIScene` imports only `MetalUIShaderTypes` (`PS-A`); an initialiser
  that must stay unspellable outside the package is `package`, with a
  plain-import guard (`PS-D`, `PS-E`).
- `MetalUIFreeType` imports only `MetalUIScene`, `CFreeType` (`FT-K`).
  **`MetalUIPath` imports nothing** (no Foundation, no `MetalUICore`; `package`
  API; `GX-B`) — its coverage is bit-identical on every platform because its
  trigonometry is its own `PathMath.sinCos`; a libm call or a Foundation import
  there breaks that silently on macOS.
  `MetalUIHarfBuzz` imports only `CHarfBuzz` (`SH-K`). `MetalUITextSystem`
  imports only `MetalUIScene` (`TS-A`). `MetalUIPortableText` imports only
  `MetalUIScene`, `MetalUIShaderTypes`, `MetalUIHarfBuzz`, `MetalUIFreeType`,
  `CUnibreak`, `MetalUITextSystem` (`PT-A`). **`MetalUISystemFonts` is the one
  text target with Foundation/a file system** (`SF-A`); system faces are lazy
  and outside the cascade unless a platform fallback family (`SF-B`, `SF-C`).
- `MetalUIPlatform` is portable (`MetalUICore`, `MetalUIScene` only);
  `MetalUIRender` depends on it; the AppKit platform is `MetalUIAppKit`
  (`RS-C`), sharing one `Renderer` across windows. Windows draw through
  `PlatformWindow.renderer` (`RS-A`). Inside `MetalUI`, CoreText stays behind
  `#if canImport(MetalUIText)`.
- **`PlatformWindow`'s defaultless requirements** — `onAccessibilityRequest`,
  `publishAccessibilityTree(_:)`, `controlActiveState`/
  `onControlActiveStateChange`, `accessibilityReduceMotion`/
  `onAccessibilityReduceMotionChange`, `accessibilityReduceTransparency`/`onAccessibilityReduceTransparencyChange` (`MT-D`), `beginExternalDrag(_:at:)`, `presentMenu(_:at:) -> Bool`, `setPreferredColorScheme(_:)` (`CR-M`), `presentFileDialog(_:) -> Bool`, `presentAlert(_:) -> Bool`, `dismissPresentation(token:)`, `setContentSizeLimits(minimum:maximum:)` (`SV-B`), `setToolbar(_:) -> Bool` (`MD-J`), `setPointerStyle(_:)` (`CI-J`), and the app shell's seven — `onCloseRequest`, `close()`, `setDocumentEdited(_:)`, `setRepresentedFilePath(_:)`, `setTitleBarStyle(_:) -> Bool`, `titleBarInsets`, `performTitleBarPress(clickCount:) -> Bool` (`AS-H`, `AS-J`), and `performWindowDrag() -> Bool` (`WD-E`), `orderFrontAndMakeKey()` (`WA-A`), and the clipboard's four — `writeClipboard(_ representations:) -> Bool`, `clipboardTypeIdentifiers()`, `readClipboard(identifier:)`, `setClipboardCommands(_:)` (`CB-E`) — have no
  default so a conformer that forgets one fails to compile. Both conformers,
  the headless `HeadlessPlatform*` of `MetalUITesting` (**a new requirement owes it an honest
  answer in the same change**, `HT-X` 1) and every test fake implement all of them. **`Platform` (not a window) has
  seven: `setApplicationIcon(_:)`** (`AI-B`), **`setMenuBar(_:) -> Bool`** (`MN-I`, `SG-A`: `true` when the platform shows the bar) **and the app shell's
  `onTerminateRequest`, `replyToTerminateRequest(_:)`, `terminate()`, `onOpenURLs`** (`AS-H`) **and `activate()`** (`WA-A`), beside it for the same reason,
  and so does **`WindowRenderer.finishFrame(scene:atlas:surfaces:)`** (`MV-F`
  item 1; the two-argument spelling forwards `surfaces: []`). **`TextSystem` has
  three** since rich text (styled measure, styled layout, decoration metrics,
  `RT-F`): a third-party conformer must add them (`docs/migration.md`).
- Every `LayoutTree` that could exchange ids needs a distinct `generation`
  (C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` (§7.8).
- Percentage `padding` resolves against the containing block's **width** on
  every edge; `Style.inset` horizontal-vs-width, vertical-vs-height (AP-D).

## Always — rules that cross every shard

- **Write state from input, never from a phase** (keeps the display link awake;
  a phase-time `@Observable` write is silently stale). Live animation is
  `noteActiveAnimation()`, never `requestAnotherFrame()` (`identity-state.md`).
- **Tests never sleep**: drive `simulateTick(timestamp:)` or `tick()`
  (`identity-state.md`).
- **`.id()` must be the outermost modifier**; a new site that mints a named id
  owes `StateTable.noteNamed` (`identity-state.md`).
- **A new handler-registering site goes through `registerHandlers`** (gate, AX,
  hitbox) and gains an arm in the D2 guard; a new `StyledElement` site paints
  through `paintDecoration` (`identity-state.md`, `input-focus.md`).
- **A new `StateTable` write site owes a journal event** and a classification
  in `everyStateWriteSiteIsClassified` (`retained.md`).
- **A new drawable capability lands in `shaders.metal` and `replay.hlsl`
  identically**, or is a documented renderer constraint (`TE-AD`, `drawing.md`).

## Rule shards — read before touching the area

The architecture rules live in `docs/rules/`, one file per area. **Before changing code, tests or docs in
an area, read its shard in full** (they are rules, not history; each is 5–30 KB). A milestone's rule goes
in its area's shard (one or two sentences); a new area gets a new shard and a row here.

- `docs/rules/identity-state.md` — phases, `.id()`, `@State`/`Binding`/`@Observable`, `Component`, `StyledElement`/`Handlers`, environment, `ForEach` identity, `onAppear`/`.task`, `@GestureState`, animation.
- `docs/rules/layout.md` — legacy containers and `.frame`, sizing modifiers, `List`, controls in SwiftUI stacks, lazy containers, layout allocations, the proposal layout kernel.
- `docs/rules/input-focus.md` — controls, `scrollTo`, hit testing, gestures, drag and drop, accessibility, focus, keys (`onKeyPress`, Keymap), pointer, wheel, window drag, overlays and coordinate spaces, menu anchors.
- `docs/rules/text.md` — text input, selection, `Text`/fonts, rich text, text over a GPU surface, `drawText`, the IME driver, the portable text system.
- `docs/rules/drawing.md` — shapes, images in the renderer, paths, shadows, render effects, raster caches, GPU surfaces, backdrop blur, materials, Liquid Glass, colour, hot paths.
- `docs/rules/retained.md` — `.equatable()`, the layout memo, paint/prepaint replay, the graft, translation, environment readings, read-only state, observation threading, anything in `Retained*.swift`, `ContentMemoStore`, `LayoutMemo`.
- `docs/rules/app-shell.md` — `Deferred`, app icon, menus/popovers/tooltips, file dialogs and alerts, toolbar, close/terminate, the drawn menu bar, `presentationBackground`, clipboard.
- `docs/rules/sdl.md` — `Backends/SDL`, Linux/Windows apps, window chrome on SDL, single instance, app id, SDL_GPU (`MetalUISDLGPU`), shaders and shadercross, precise scroll, SDL test helpers, the Windows release crash.
- `docs/rules/images.md` — decoding, orientation, image cursors, the headless SDL launch, header reads, format sniff.
- `docs/rules/tooling.md` — `metalui new`, `Examples/Jotter`, `MetalUITesting`, the developer guides, small carried items.
- `docs/rules/decision-prefixes.md` — every ruling prefix → decisions doc and its next unused id.
- `docs/rules/windows-vm.md` — running the Windows CI jobs locally (UTM VM, x64 under emulation).

## Workflows and subagents — token budget

A five-lane stage has cost 6–12M tokens. Two or three lanes, split only on
disjoint files. Opus for design, implementation and mutation verification;
`model: 'sonnet'` for record, docs, counts and greps. Merge adjacent agents
over the same material. Re-verify only on a finding. Pass paths, not
content; agents return conclusions. Stay under the session's workflow size
guideline.

## Practices — the short form

Read `docs/practices/verifying-tests-can-fail.md`; history in record §02.

- **Findings come from mutation, not inspection.** Mutate the declaration a
  test is named for and run it. A mutation that reddens nothing is a broken
  instrument or the finding. Name the reddened tests, not a count. Record
  which branch **and which spelling** a mutation was applied to.
- Any count a later loop indexes on is `try #require`.
- A `@testable` test cannot prove an access-level narrowing — use a
  plain-import typecheck guard, in the change that introduces the hazard.
- When a claim is refuted, fix everywhere it was copied (spec, plan, source
  comment, this file, the record). Re-take whole tables.
- Re-run a mutation a doc comment names when the code under it changes.
- A confident "cannot" that was not measured is the tell.
- Reviewer dispatches say not to invoke the `code-review` skill. Mutate in an
  isolated `git worktree` when another agent is live.
- Performance tests count work, never wall clock; red on arrival; branching
  tree.
- A probe needs a separating arm before a ruling rests on it (`FR-M`).
- A helper with two halves needs two per-site guards (`OM-AI`); an order test
  needs a two-layer chain (`OM-AD`).
- A harness decision is a mutation site. A fixture of fixed-size leaves cannot
  see a container lowering. A green mutant may be the correct spelling (`LR-X`).
- Parallel tracks owe tests for the merge; a clause both tracks share can be
  pinned by neither.

## Reference tables

- **Divergences**: `docs/divergences.md` (178 live, next label 209). A new
  divergence gets the next label, a row there, a section in record §04 and a
  pin. Many rows are pinned wrong on purpose — a reddening test may be a fix.
- **Declared but inert**: record §05 (plan task 15's section is the final
  list). Adding an unimplementable property: add a row.
- **Human verification**: `docs/verification/human-checks.md`. Paint order,
  portals, scroll direction, presentation, the display link and real hover
  are looks; nothing in the suite sees them.
- **Performance**: record §105 (`BL-`, 2026-10-13, `848ee029`; §07's CSS-engine tables are history). Wall clock is re-taken by `zsh docs/probes/perf-baselines.sh` and recorded dated, never pinned; a pin counts work.
- **CI hazards** (record §08, §61 §9):
  - A proposal-path regression that reports an `…unconsumed` or presentation
    field **traps in a `Window` test and truncates the run with no summary
    line** — read the last lines of the log.
  - **Windows CI's compiler is 6.4.0+Asserts; macOS's is not.** A `Component`
    whose content is a loop, nested in a container inside another
    `Component`'s content, crashes SILGen there (`verifyLexicalLowering`,
    `LK-X`, MG-27) — fixed for a `Component` by its prepaint record being one
    heap box (`ComponentPrepaint`, `SG-E`); code with its own protocols of that
    shape still needs the inner one as a function. Reproduce with the asserts
    dev snapshot in `~/Library/Developer/Toolchains`
    (`METALUI_RUN_ASSERTS_COMPILER_TEST=1`, macOS and Linux only).
  - **Windows threads have 1 MB stacks.** A new demo section goes in its own
    function passed to a generic composer, not inline
    (`everyProductionTreeBuildsOnAOneMegabyteThread`); that test builds each
    large tree in its own `@inline(never)` frame — inline in its composer the
    canvas tree passed on macOS and overflowed only in `swift:6.4-noble` (`CI-AI`).
  - **A C enum's `rawValue` is `Int32` on Windows, `UInt32` on Apple** —
    always convert explicitly.
  - `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` is compiled out on
    Windows by design.
  - **A macOS test process that initialises SDL video can `exit(0)`
    mid-run.** `SDLPlatform.init` runs `NSApp.run()` once; a new entry point
    owes the same, and **every new SDL test helper creating an `SDLPlatform`
    arms `armMainRunLoopExitCheck()`**.
  - E24 hard-fails under the root locale; seven `AnimationTests` need a
    display device.
