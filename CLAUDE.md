# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift. **macOS with AppKit and Metal by default; the framework also
builds on Linux and Windows** (`XP-A`), drawing through `Backends/SDL`
(`App(platform:textSystem:)`, `XP-B`) with the portable text system — see
`plans/2026-09-23-cross-platform-roadmap.md` for what is left. No UIKit, no
`.touch` input: the spec's iOS target is unmet. `PlatformWindow`'s `onAccessibilityRequest` and
`publishAccessibilityTree(_:)` have no default implementations (`AB-R`).

**This file is rules only.** The full pre-2026-09-21 version (120 KB: every
test name, divergence row, inert row, human-verification row, performance
figure and CI hazard) is `docs/record/19-claude-md-full-2026-09-21.md`; below,
"§19 <section>" points into it. **§19 is frozen at `cb2e708` and does not carry
plan task 7's stage 2 or its grids stage** — for those tables read the dated
sections at the end of records §03, §04 and §05, and the tracks themselves
(§21, §22, §23). Reasoning and history live in `docs/record/`
(`README.md` indexes it). Citations in the record were not all re-checked after
later refactors — verify a test name or grep before relying on it. New
milestones append their record to `docs/record/` and put only the rule here.

`AGENTS.md` is a byte-identical copy for Codex: edit `CLAUDE.md`, then
`cp CLAUDE.md AGENTS.md`; check `cmp CLAUDE.md AGENTS.md` before committing.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`;
  per-milestone specs and plans beside it in `specs/` and `plans/`.
- **Decisions docs:** `docs/superpowers/<date>-<milestone>-decisions.md`, one
  per milestone; read their "Carried…" sections before new work. Ruling ids
  are namespaced by prefix — numbered: `F-`/`PF-`/`C-` (m0/m1a; bare `F-1` is
  ambiguous), `FS-`, `AL-`, `BM-`, `WR-`, `EP-` (`EP-2`/`EP-4` never
  assigned); lettered: `CS-`, `SI-`, `TX-`, `CL-`, `ST-`, `AP-`, `MP-`, `IN-`,
  `SZ-`, `TB-`, `RX-`, `CO-` (next `CO-AA`), `AN-` (next `AN-X`; its letters do
  not track its ledger's), `SA-` (next `SA-V`), `MC-` (next `MC-T`), `EV-`
  (next `EV-AA`), `AB-` (next `AB-AH`), `FR-` (next `FR-W`), `OM-` (next
  `OM-AN`), `CN-` (next `CN-V`), `LR-` (next `LR-CT`), `GR-` (next `GR-AU`),
  `PS-` (next `PS-H`; rulings in its spec, no separate decisions doc), `FT-`
  (next `FT-L`; rulings in its spec, no separate decisions doc), `SH-` (next
  `SH-L`; rulings in its spec, no separate decisions doc), `PT-` (next `PT-K`;
  rulings in its spec, no separate decisions doc), `LB-` (next `LB-P`;
  rulings in its three specs: line breaking, lines emission, content sizes),
  `FN-` (next `FN-E`; rulings in its spec), `PC-` (next `PC-D`; rulings in
  its spec), `TS-` (next `TS-E`; rulings in its spec), `RS-` (next `RS-E`;
  rulings in its spec), `SP-` (next `SP-D`; rulings in its spec), `XP-`
  (next `XP-D`; rulings in its spec; `MP-` is the measure-performance one),
  `DC-` (next `DC-D`; rulings in its spec), `FB-` (next `FB-D`; rulings in
  its spec), `BD-` (next `BD-E`; rulings in its spec). A numbered citation
  of a lettered prefix (`CS-3`, `LR-3`, `GR-3`, `SH-3`, `PT-3`, `LB-3`) is a typo; sweep
  case-insensitively.
  **A decisions doc's "next unused" line moves in the commit that appends the
  ruling** — read the file's last `## <PREFIX>-` heading, not its header; the
  grids doc's header was a letter behind for a whole round (record §23 §7).
- **SwiftUI-alignment plan:** `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`.
  Its 2026-09-12 kernel/modifier specs describe types never built; **the
  source is the authority**. Per task: spec in `specs/`, decisions doc, record
  file — task 2 `SA-` (§09), 3 `MC-` (§10), 9 `EV-` (§11), 12 `AB-` (§12),
  3/9/12 integration (§13), 4 `FR-` (§14), 5 `OM-` (§15), 4/5 integration
  (§16), 6 `CN-` (§17), 7 stage 1 of 14 `LR-` (§18, spec
  `specs/2026-09-17-engine-replacement-design.md`), 7 stage 2 `LR-AB`…`LR-BA`
  (§21, spec `specs/2026-09-17-engine-stage-2-design.md`, same decisions doc,
  probe `swiftui-engine-replacement-stage2.swift` revision 4), 7 stage 3
  `LR-BB`…`LR-BP` (§25, spec `specs/2026-09-22-engine-stage-3-design.md`, same
  decisions doc, probe `swiftui-engine-replacement-stage3.swift` revision 2),
  7 stage 4 `LR-BQ`…`LR-CG` (§27, spec
  `specs/2026-09-23-engine-stage-4-design.md`, same decisions doc; **no new
  probe** — its SwiftUI claims are `swiftui-stack-algorithms.swift`'s K6),
  7 stage 5 `LR-CH`…`LR-CS` (§29, spec
  `specs/2026-09-23-engine-stage-5-design.md`, same decisions doc, probe
  `swiftui-overlay-presentation.swift` revision 2 — group Q added, P and H
  re-run byte-identical), 7 stage G grids
  `GR-` (§22, spec `specs/2026-09-17-grids-design.md`,
  `2026-09-17-grids-decisions.md`, ten runnable probes), stage 2 / stage G
  integration (§23). **Lazy grids (`LazyVGrid`/`LazyHGrid`/`GridItem`) are out
  of scope**, proposed as stage G2 after stage 4 (`GR-L`) — **stage 4 has
  landed**, so the windowing they need exists (`WindowedRowsLayout`, `LR-BQ`)
  and G2 is unblocked rather than waiting. Seventeen record files are not tasks of
  this plan: §19 is the
  frozen `CLAUDE.md` snapshot, §20 the portable `MetalUIScene` move (`PS-`),
  §24 the FreeType rasterizer (`FT-`, spec
  `specs/2026-09-22-freetype-rasterizer-design.md`, rulings in that spec),
  §26 the HarfBuzz shaper (`SH-`, spec
  `specs/2026-09-22-harfbuzz-shaper-design.md`, rulings in that spec),
  §28 the portable text pipeline (`PT-`, spec
  `specs/2026-09-23-portable-text-design.md`, rulings in that spec), §30
  portable line breaking (`LB-`, spec
  `specs/2026-09-23-portable-line-breaking-design.md`) and §31 portable
  metrics and multi-line emission (`LB-F`, `LB-H`…, spec
  `specs/2026-09-23-portable-lines-emit-design.md`) and §32 portable min-
  and max-content (`LB-L`…, spec `specs/2026-09-23-portable-content-sizes-design.md`),
  §33 portable font resolution (`FN-`, spec
  `specs/2026-09-23-portable-font-resolver-design.md`), §34 Core and
  Layout off macOS (`PC-`, spec `specs/2026-09-23-portable-core-layout-design.md`),
  §35 the text seam (`TS-`, spec `specs/2026-09-23-text-seam-design.md`),
  §36 the render seam (`RS-`, spec `specs/2026-09-23-render-seam-design.md`),
  §37 the SDL3 platform (`SP-`, spec `specs/2026-09-23-sdl-platform-design.md`),
  §38 MetalUI off Apple (`XP-`, spec `specs/2026-09-23-metalui-portable-design.md`),
  §39 the demo on Linux and Windows (`DC-`, spec
  `specs/2026-09-23-demo-cross-platform-design.md`), §40 portable font
  fallback (`FB-`, spec `specs/2026-09-23-font-fallback-design.md`) and §41
  portable bidi (`BD-`, spec `specs/2026-09-23-bidi-design.md`). **Cross-platform work
  follows `plans/2026-09-23-cross-platform-roadmap.md`**, one item per branch,
  ticked in the PR that lands it.
  **§24 is FreeType and §25 is stage 3; §26 is HarfBuzz and §27 is stage 4**
  — each stage record was renumbered (24→25, 26→27) at its merge because the
  other line was pushed first (record §25's and §27's headers, and the
  precedent in record §23 §8). §28 was written as §27 and renumbered when
  stage 4 reached `master` first. **§29 (stage 5) was written as §28** on
  `feat/engine-stage-5` from `e5caefb` and renumbered 28→29 at its merge,
  because `master`'s portable-text line had already published §28 — the same
  shape as 24→25 and 26→27 (record §29's header). **§30 (line breaking) was
  written as §29** and renumbered when stage 5 reached `master` first.
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.

## Build and test

```bash
swift build
swift test --no-parallel
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc   # suite total
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # proposal preview (value exactly "1")
```

- **Counts (2026-09-23, `feat/engine-stage-5` — plan task 7 stage 5 — merged
  with `master` at `42b9ab4`, the portable text line; then `PT-J`, +5; then line breaking, +6; then
  lines emission, +14; then content sizes, +10; then font resolution, +6; then the text seam, +5; then MetalUI off Apple, +3; then font fallback, +4; then bidi, +4): 1697 tests, 97
  goldens, 77 typecheck guards**, 0 `error:`, 0 `warning:`, taken after
  `swift package clean` with `swift build --build-system native
  --build-tests` then unfiltered `swift test --build-system native
  --no-parallel` (**one summary line**, `Test run with 1697 tests in 3 suites
  passed`; twelve skipped: the two gated tests, the FreeType, HarfBuzz,
  portable text, line breaking, lines emission (two), content sizes, font
  fallback and bidi oracles' gated measurement tests, and the demo-frame
  recorder; the guards ran — the log
  carries `FR-J no-argument frame: succeeded=`). Goldens unmoved against
  `e5caefb` (`git diff --name-only e5caefb HEAD -- 'Tests/**/*.json'` is
  empty). **1697 = 1640 + 5 + 6 + 14 + 10 + 6 + 5 + 3 + 4 + 4**: the `PT-J` follow-up's
  `EmitParameterTests` (record §28), line breaking's 6 (the `LB-E` oracle,
  its gated measurement, contract tests; record §30) and lines emission's 14
  (ten metric/placement oracle tests, two of them gated, and four
  `EmitLinesTests`; record §31), content sizes' 10 (record §32) and font
  resolution's 6 (record §33), the text seam's 5 (record §35) and
  `MetalUICrossPlatformTests`' 3 (record §38, one a gated recorder) and
  font fallback's 4 (record §40, one gated) and bidi's 4 (record §41, one
  gated; `Tests/PortableTests` separately runs 18 + 6 + 5 since bidi;
  `Tests/PortableTests` separately runs 16 + 6 + 5); **1640 = 1617 + 15 + 8**: master's `e5caefb` (1617) plus stage 5's
  15 (lane 1, the presentation root, +7; lane 2, the exit suites, +2; lane 3,
  the must-not-move set through real windows, +6; record §29) plus the
  portable text line's 8 (`MetalUIPortableTextTests`; record §28;
  `Tests/PortableTests` separately runs 4 + 6 + 5). Each side was taken the
  same way before the merge: 1632 on `feat/engine-stage-5` alone, 1625 at
  `master` `42b9ab4`. **None of these lines added a golden or a guard**, so
  97 / 77 are unchanged, the per-file list below is unchanged and so is the
  "all 77 guards skip under the default build system" sentence. Master's
  1617 was itself **1580 + 15 + 22**: master `f5e5651` (1595) is
  `integrate/stage-3`'s 1580 plus the HarfBuzz line's 15 (record §26), and
  stage 4 adds 22 (lane 1 +3, lane 2 +9, lane 3 +1, lane 4 +5, lane 5 +4;
  record §27). **`List` is
  public and its stored `box`'s generic argument changed at stage 4, so
  `swift package clean` before re-taking.** Before stage 4 met the HarfBuzz line: 1602 /
  97 / 77 on `feat/engine-stage-4` alone, 1595 / 97 / 77 at master
  `f5e5651`, both from 1580 / 97 / 77 on `integrate/stage-3` (2026-09-22,
  task 7 stage 3 merged with the FreeType rasterizer line), itself **1558 +
  22 = 1550 + 8 + 22** — master `b10594c` (1558) is 1550 plus the FreeType
  line's 8, and stage 3 added 22 (lane 1 +3, lane 2 +8, lane 3 +2, lane 4 +6,
  lane 5 +3); records §24 (FreeType) and §25 (stage 3). Guards per file:
  `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `GridCompileGuards` 4,
  `AXNodeTests` 3, `DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits,
  one a comment), `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards`
  2, `SceneBoundaryCompileGuards` 2, `LayoutAuthorityCompileGuards` 1.
  Earlier: 1558 / 97 / 77 at `b10594c` (the FreeType line, record
  §24, +8 tests and no guard) and 1572 / 97 / 77 on `feat/engine-stage-3`
  (record §25), both from 1550 / 97 / 77 at `57893d0` — itself the merge of
  two lines, 1548 / 97 / 75 on `integrate/stage-2-grids`
  (2026-09-21, task 7 stages 2 and G; records §21, §22, §23) and 1411 / 97 / 73
  on `feat/portable-scene` (2026-09-22, `MetalUIScene`; record §20). Both
  descend from 1409 / 97 / 71, so that merged total is 1409 + 139 + 2. History:
  record §06, §19 "Build and test". A count is stale the moment a test lands;
  re-measure.
- **Read the printed counts, never the exit status.** `--build-system native`
  prints ONE summary line even with three suites in the run (it says "in 3
  suites"); the default build system may print several (sum them).
  **Twelve** gated tests count toward the total while skipped —
  `regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`, the
  FreeType oracle's `measure(file:)`, the HarfBuzz oracle's `measure()`
  (`METALUI_HARFBUZZ_MEASURE=1`) and the portable text oracle's
  `theMeasuredDifferences` (`METALUI_PORTABLE_ORACLE_MEASURE=1`) and the line
  breaking oracle's `measureWrapDifferences` (`METALUI_LINEBREAK_MEASURE=1`)
  and the lines emission oracle's `measureLineEmissionDifferences` and
  `measurePatchedFaceMetrics` (both `METALUI_LINES_EMIT_MEASURE=1`) and the
  content sizes oracle's `measureContentSizeDifferences`
  (`METALUI_CONTENT_MEASURE=1`), `recordDemoFrames`
  (`METALUI_CROSSPLATFORM_RECORD=1`), `measureFallbackDifferences`
  (`METALUI_FALLBACK_MEASURE=1`) and `measureBidiDifferences`
  (`METALUI_BIDI_MEASURE=1`). **Tests that register fonts with CoreText
  process-wide race under a parallel run** (measured with a filtered run:
  the resolver oracle and the seam test fail together) — `--no-parallel`.
  The lone `warning:`
  under native is SwiftPM's deprecation notice.
- **Goldens must not move** on a change outside `Sources/MetalUILayout/`
  (`find Tests/MetalUILayoutTests -name "*.json" | wc -l` — not all of
  `Tests/`, where `Tests/PortableTests/.build/` holds JSON build artifacts).
  WebKit is the oracle for the CSS engine only. The proposal kernel shares `LayoutTree.swift` storage
  (`newNode`, `reset`, `roundLayout`, the `SA-G`/`SA-I` preconditions), so a
  proposal-path edit there can move a golden — run the fixtures. No text
  fixture, ever (TX-B).
- **Guards:** `grep -c canTypecheck` per file across `PhaseSeparationTests`,
  `ErasureCompileGuards`, `ElementGroupTrapTests`, `ProposalLayoutCompileGuards`,
  `ModifiedElementCompileGuards`, `ProposalNodeIDCompileGuards`,
  `EnvironmentCompileGuards`, `FrameSizingCompileGuards`,
  `DecorationCompileGuards`, `ContainerCompileGuards`,
  `LayoutAuthorityCompileGuards`, `GridCompileGuards`,
  `UnitSafetyTests` (one hit is a comment),
  `AXNodeTests`, `SceneBoundaryCompileGuards`; `Typecheck.swift` holds only
  the declaration. Two helpers, 40 and 37:
  `typecheck(_:importing:)` wraps the fixture in a function (Swift 5, nothing
  `public`/file-scope compiles); `typecheckFile(_:importing:)` is whole-file
  Swift 6 — the six/two/six of `ProposalLayout`/`ModifiedElement`/
  `ProposalNodeID`, two `FrameSizing`, three `Decoration`, four `Container`,
  four `Grid`, one `LayoutAuthority`, two `SceneBoundary` and seven of
  `EnvironmentCompileGuards`'. A guard about what an external module can write
  uses `typecheckFile` (`SA-P`). **Guards skip silently** when
  `.build/<triple>/debug/Modules` is not where `#filePath` expects
  (default swiftbuild system, `--scratch-path`, `-c release`) — the total
  does not move and the run passes. A worktree with its own `.build` at its
  root runs them (measured under `~/Developer/worktrees/`, record §28); grep
  the log for `FR-J no-argument frame: succeeded=` rather than assume.
- **Adding an AppKit or WebKit test? Run the whole suite unfiltered** (shared
  process and run loop; `--filter` is a different program).
- **`swift package clean` when the impossible happens**: SIGSEGV, a truncated
  run with no summary line, an expected value its source cannot produce, or
  `Undefined symbols … direct field offset`. Causes: the untracked shader
  header symlink (`Sources/MetalUIShaderTypes/include/`), and any new
  case/stored property on a public type crossing a module boundary — the grids
  stage added six stored mark tables to `LayoutTree`, and the `MetalUIScene`
  move relocated `Scene`, `FontKey`, `GlyphImage` and the atlas types across
  three modules.
- **The manifest is two lists** (`PC-A`): targets that import no Apple
  framework are declared on every platform; everything else — and the
  portable oracles, which compare against CoreText — under `#if os(macOS)`.
  **A new target goes in the list its imports allow**; Linux and Windows CI
  (`scene-linux`, `root-windows`) build every portable target — `MetalUI`
  and `MetalUIDemoContent` included since `XP-A`, their Apple dependencies
  appended on macOS in the manifest — and run `MetalUICoreTests`,
  `MetalUILayoutTests` and `MetalUICrossPlatformTests` (486 + 22 + 3), the
  last pinning the demo's whole frame byte-for-byte against macOS (`XP-C`).
  Inside `MetalUI`, CoreText stays behind `#if canImport(MetalUIText)`; off
  Apple a `Frame`/`Window` without a text system traps (`XP-B`). A test there
  that needs WebKit or Darwin is compiled out by `#if canImport(…)` per
  declaration (`PC-B`); typecheck guards read only this platform's `.build`
  (`PC-C`) and skip off macOS.
- **Targets:** twenty one-way-dependent (`MetalUICore`, `MetalUILayout`,
  `MetalUIScene`, `CFreeType`, `MetalUIFreeType`, `CHarfBuzz`, `CUnibreak`, `CSheenBidi`,
  `MetalUIHarfBuzz`, `MetalUITextSystem`, `MetalUIPortableText`, `MetalUIText`, `MetalUIShaderTypes`,
  `MetalUIPlatform`, `MetalUIPrimitives`, `MetalUIRender`, `MetalUIAppKit`, `MetalUI`,
  `MetalUIDemoContent`, `MetalUIDemo`) plus
  `Tests/MetalUITestSupport`. `MetalUIDemoContent` holds the demo tree so
  tests can import it (`LR-S`). `MetalUIScene` holds
  `Scene`/`DrawRun`/`PrimitiveKind`, the glyph atlas types and the `FontKey`
  struct; `MetalUIText` and `MetalUIRender` re-export it (`PS-B`), so its
  types need no new import. It is also a library product, consumed by
  `Backends/SDL` — a **separate package** (`MetalUISDL`, so the root never
  needs SDL3) holding `SDLWindowRenderer` and the replay parity harness
  (`RS-D`), and `SDLPlatform`/`SDLWindow`, the SDL3 `Platform` (`SP-A`;
  keys translated to AppKit's characters so `Keymap` works, `SP-C`; **no
  accessibility**, explicitly — a divergence until roadmap item 13, `SP-B`).
  **Windows draw through `PlatformWindow.renderer`, a
  `WindowRenderer`** (`RS-A`: `beginFrame() -> Float?`, then
  `finishFrame(scene:atlas:)`), declared in `MetalUIPlatform`, which is now
  portable (imports only `MetalUICore`, `MetalUIScene`). `MetalWindowRenderer`
  (`MetalUIRender`, which depends on `MetalUIPlatform` — the old edge
  reversed) is the Metal one over a `RenderSurface` (`RS-B`); the AppKit
  platform lives in `MetalUIAppKit` (`RS-C`) and shares one `Renderer`
  across windows. `Window` holds no `Renderer`. `CFreeType` is FreeType 2.14.3, vendored
  (`FT-A`; `Sources/CFreeType/VENDORED.md`), a C target with no Swift API.
  `MetalUIFreeType` is the FreeType-backed glyph rasterizer (`FreeTypeFont`,
  `FreeTypeRaster`, `FT-B`…`FT-E`) that matches `GlyphRaster`'s contract
  exactly; also a library product, for non-Apple backends. Nothing in
  production calls it — `GlyphRaster` stays the rasterizer on Apple platforms
  (`FT-I`). `CHarfBuzz` is HarfBuzz 14.5.0, vendored (`SH-A`;
  `Sources/CHarfBuzz/VENDORED.md`), a C++ target with no Swift API.
  `MetalUIHarfBuzz` is the HarfBuzz-backed shaper (`HarfBuzzFont`,
  `HarfBuzzShaper`, `SH-B`…`SH-E`), depending on `CHarfBuzz` only; also a
  library product. Nothing in production calls it — `Shaper` stays the shaper
  on Apple platforms (`SH-J`). `MetalUIPortableText` joins the two
  (`PT-A`…`PT-E`): `PortableFont` opens one file in both engines and **checks
  they agree** at construction (`PT-B`), and `PortableText.emit` turns one run
  on one line into `MUIGlyph`s plus atlas coverage with `Frame.draw`'s
  arithmetic (`PT-D`), taking the mask's corner radii, `order` and `layer`
  that `Frame.draw` reads from frame state (`PT-J`; defaults square/0/0) — no
  bidi, itemization or fallback. It also wraps:
  `PortableText.lines(_:font:wrappingAt:)` gives `Shaper.shape(wrappingAt:)`'s
  display lines (UAX #14 via `CUnibreak`, libunibreak 8.0 vendored, `LB-A`),
  equal to CoreText's over 13,464 cases; its four fitting rules are measured
  (`LB-D`: whitespace hangs, advance is the paragraph's share, cluster-then-
  grapheme emergency breaks, 28 pt tab stops) — do not simplify one without
  re-running the oracle. `PortableText.emitLines` draws the wrapped lines
  from a box's top-left with `PortableFont.metrics` (`LB-F`, `LB-H`), equal
  in placement to `ShapedText.placedGlyphs` over 26,928 cases (`LB-I`).
  **Four measured CoreText rules live there — do not simplify one without
  re-running the oracle**: metrics are `hhea`'s (not `FT_Face.ascender`,
  which follows OS/2 under `USE_TYPO_METRICS`; only patched faces see it),
  a TrueType metric is rounded to a 16.16 fraction of the em; design units
  scale `units × (size / unitsPerEm)` (`HarfBuzzFont.points`); and
  `drawnGlyph` drops default ignorables and draws the space glyph for a
  control or hard-break character (`emit` too). `unbreakableRuns`,
  `minContentWidth` and `maxContentWidth` give TX-F's and TX-K's answers
  (`LB-N`); **opportunities are libunibreak's under `"en-strict"`** — its
  English quote tailoring and strict small kana, equal to `CFStringTokenizer`
  over 4,418 class pairs (`LB-L`); Thai (no dictionary) and a German-quote
  typesetter heuristic differ, pinned (`LB-M`). `PortableFontResolver`
  answers `family:size:` from registered font files with
  `CTFontCreateWithName`'s rules — PostScript, family or full name, case
  folded and nothing else; `nil` and every unmatched name give the default
  face (`FN-A`…`FN-C`); its oracle runs once per default face, because a
  single default hides a wrong match on that face's own name. **Every
  shaping path goes through `shapeCascading`** (`FB-A`): a grapheme goes to
  the first face of the font's cascade (`PortableFont.fallbacks`; from the
  resolver, every other registered face, `FB-B`) that covers it, and glyphs
  carry their face to placement and the atlas — a new shaping call site that
  calls `HarfBuzzShaper` directly loses fallback. Runs also split by bidi
  level and script and are shaped in their direction (`BD-B`, SheenBidi,
  vendored as `CSheenBidi`); each line is laid out in UAX #9 visual order,
  a right-to-left line's trailing whitespace hung off its left edge, and a
  line starting inside a split lam-alef re-shaped (`BD-C`) — all measured
  against CoreText, 0 differences over 320 cases. Also a
  library product; nothing in production calls it (`PT-I`). The subpixel
  placement rule lives once, in `GlyphImage.subpixelPlacement(forDeviceX:)`
  (`PT-C`); `GlyphRaster` forwards — do not re-inline it on either side.
  `Experiments/SDLGPU`'s frame 4 is drawn from it (`PT-G`) and replayed by
  `Backends/SDL`; frame 5 is the demo's whole tree, which `Backends/SDL`'s
  `DemoCapture` rebuilds natively on Linux and Windows and checks against
  macOS (scene byte-for-byte, pixels within parity; `DC-B`).
  `renderFrame(_:size:scaleFactor:textSystem:atlas:)` renders a tree
  headless (`DC-A`).

Eight constraints that fail silently:

- `MetalUILayout` imports only `MetalUICore` (anchored grep; since `PC-A`
  an Apple import also fails the Linux and Windows builds).
- `MetalUIScene` imports only `MetalUIShaderTypes` — no Foundation, CoreText,
  CoreGraphics or Metal (`PS-A`). macOS cannot see a violation; the Swift
  workflow's `scene-linux` job can (`PS-G`). An initialiser that must stay
  unspellable outside the package is `package`, with a plain-import guard
  (`FontKey`, `GlyphImage`: `PS-D`, `PS-E`).
- `MetalUIFreeType` imports only `MetalUIScene` and `CFreeType` — no
  Foundation, CoreText, CoreGraphics or Metal (`FT-K`). macOS cannot see a
  violation; the `scene-linux` job builds this target too, and
  `Tests/PortableTests` (a separate package depending on the root's
  `MetalUIFreeType` product) runs FreeType's own output through Linux and
  Windows CI, pinned byte-for-byte against macOS (`FT-J`).
- `MetalUIHarfBuzz` imports only `CHarfBuzz` — no Foundation, CoreText,
  CoreGraphics or Metal (`SH-K`). macOS cannot see a violation; the
  `scene-linux` job builds this target too, and `Tests/PortableTests` (a
  second test target, `HarfBuzzDeterminismTests`, depending on the root's
  `MetalUIHarfBuzz` and `MetalUIFreeType` products) pins HarfBuzz's glyph
  ids, clusters and design-unit positions byte-for-byte against macOS on
  Linux and Windows CI (`SH-I`).
- `MetalUITextSystem` imports only `MetalUIScene` (`TS-A`), and
  `MetalUIPortableText` only `MetalUIScene`, `MetalUIShaderTypes`,
  `MetalUIHarfBuzz`, `MetalUIFreeType`, `CUnibreak` and `MetalUITextSystem` — no Foundation, CoreText,
  CoreGraphics or Metal (`PT-A`). macOS cannot see a violation; the
  `scene-linux` job builds this target too, and `Tests/PortableTests`' third
  target, `PortableTextDeterminismTests`, pins its emitted rects, advance,
  atlas dirty rect and coverage byte-for-byte against macOS (`PT-H`). **That
  pin's Arabic case is the only test that sees a shaping offset**: the Apple
  oracle's Latin corpus has none (`noCorpusGlyphCarriesAShapingOffset`), so
  dropping `xOffset` from `emit`'s pen walk reddens nothing on macOS except
  the portable package.
- Every `LayoutTree` that could exchange ids needs a distinct `generation`
  (C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` (gamma-space compositing, §7.8).
- Percentage `padding`/`border` resolve against the containing block's
  **width** on every edge; `Style.inset` is horizontal-vs-width,
  vertical-vs-height (AP-D).

## Architecture rules

Detail and pinning tests for every paragraph: §19 "Architecture rules", record §01.

**Phases.** `requestLayout` → `prepaint` → `paint`. `isHovered`, `isActive`,
`isFocused` exist only on `PaintPass`, each typecheck-guarded; a new
paint-only query gains a guard and a bullet in `PhaseSeparationTests.swift`'s
header in the same change.

**Identity is structural; `.id()` overrides a position, never joins it.**
- A vanishing `if` makes the **trailing sibling adopt** its state, focus and
  click dispatch. Remedy: name the trailing sibling.
- `.padding(_:)` and every legacy `.frame(...)` return one flat
  `ModifiedElement<LayerBase>` (`MC-A`); each modifier is one layer = one node
  = one id level; outermost layer takes the parent's slot, inner layers are
  `positional(0)`, content numbers from 0 under the innermost (`MC-C`).
  **`.id()` must be the outermost modifier.** Changing layer COUNT resets the
  wrapped element's `@State`/focus/`$anim`/AX node; changing VALUES does not.
  A decoration/handler written after a wrapper configures the outermost layer
  (`.padding(8).background` fills the padded box, `OM-C`).
- An `.overlay`'s primary numbers under the modifier's id, the overlay under
  `.child(of: id, at: -1)` (`MC-P`); nothing else may mean `-1`.
- `GlobalElementID.cachedHash` and `==` are safe alone, unsafe together; do not
  simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ above the engine (EP-5).

**Legacy containers.** `Column`/`Row` centre on the cross axis, `Box`
stretches (EP-8, set in inits) — a childless `Box` with no cross size paints
nothing. **Modifier order decides which box a modifier reaches**: container
modifiers (`.alignItems`, `.gap`, `.justifyContent`) and item modifiers
(`.flexGrow`, `.alignSelf`, `.margin`) go **before** `.padding`; size,
background and corner radius **after** it. All wrong orders compile. Chained
`.padding` accumulates. They keep their CSS algorithms (`CN-A`, `CN-P`):
`Row`/`Column` gap 0 vs `HStack`/`VStack` 8; `Stack` offers fit-content vs
`ZStack` its proposal; porting `Row {}` → `HStack {}` changes behaviour
silently. `Stack` layers last-on-top; no `display: contents`, no z-index.

**Legacy `.frame`** has SwiftUI's full parameter surface and lowers to one
`Style` in `FrameLayer.swift` `FrameSpec.style()` (`FR-C`): fixed axes pinned
by `size` + axis-named `minSize` (never `flexShrink = 0`, `FR-P`); fill only
when BOTH maximums are infinite (`FR-O`). Over exactly one node it lowers to a
one-cell `display: .stack` (`CN-N`) — the child overflows, and `.flexGrow`/
`.alignSelf` on it do nothing (`width(fraction: 1)` fills); `lowered` must
keep `display: .none`. Over 0 or ≥2 nodes it stays a flex row. `idealWidth`/
`idealHeight` trap at legacy registration (`LR-H`). `.frame()` with no args is
a deprecated no-op on both paths. **`ElementGroup` keeps exactly ONE fixed
`frame` overload** (`FR-S`). The two hand-spelled `frameStyle` oracles in
`ModifiedElementTests`/`ModifierCompositionProofTests` must change with the
lowering.

**Sizing modifiers** (`width`, `height`, `min/max…`, `width(fraction:)`,
`height(fraction:)`) write the element's own box and return `Self`; `.frame`
wraps (`FR-F`). Not deprecated (`FR-I`). `.minHeight(0)` is the only way to
cancel flex's automatic minimum (`FR-G`). `fraction: 0.5` is half; `percent:`
is a deprecated rename that still takes a fraction (`CN-O`).

**`List`** is a windowed `Box`: needs `Identifiable` data, uniform `rowHeight`,
an enclosing `ScrollView`, and being that scroller's **only**
layout-contributing child (else blank, divergence 14). Frame 0 builds every
row. Rows out of window >2 generations lose `@State` once the table exceeds
256 entries (TB-AH) — keep durable values in data. Publishes an `AXTable` of
realized rows only.

**Under the proposal authority a `List` lowers** (stage 4, `LR-BQ`…`LR-CG`):
its rows are a `ListRows` group whose realized rows are consumed, planned and
wrapped by stage 2's item machinery and placed by a `WindowedRowsLayout` at
`(firstIndex + i) × rowHeight`; the layout answers `rowHeight × logicalCount`
on the height — **not** SwiftUI's greedy answer (probe K6): a `List` is
virtualized and its content height is the point — and the proposal, or its
widest realized row at a nil axis, on the width. There is **no site check and
no `.list` site report left**. On the **legacy** path the leading spacer is now
a bare node, not a `Box` element: it mints no `$anim` entry, records no
`elementBounds` row and no longer animates, which is one fewer `StateTable` id
per `List`. Everything else is unchanged and measured so under **both**
authorities — row identity, `@State` and focus retention and their loss past
the bound, the `AXTable` and its `AXIndex`es, the unbounded-window and
one-more-frame rules, `MP-I`'s cold frame, wheel routing, hit testing and the
disabled gate — and **divergences 13 and 14 survive**, their pins now running
on both authorities.

**`Deferred`** is a portal: one child, no layout node, hoists to the root
layer, resets clip and scroll offset (AP-I) but **not opacity** (`OM-AA`).
One element contributes one opacity scope (divergence 46). Absolute
positioning is `.position(.absolute)` + `.inset(...)`. A tooltip needs the
portal; a modal needs both.

**Under the proposal authority a `Deferred` whose one content node is
`.position(.absolute)` is a presentation root** (stage 5, `LR-CH`…`LR-CS`):
the content lowers as element → greedy W on each stretched axis (aliased as
the element's rect) → padding for the given insets → a window-sized frame
aligned per axis, laid out in its own native run **before** the root in
`computeRootLayout` — so `SA-M`'s work counters and `SA-L`'s depth still read
the root's own run. The `Deferred` hands its parent a 0×0 placeholder aliased
to the content's element rect, dropped by every lowered container. An
**in-flow** `Deferred` is untouched — it already agrees with the legacy
engine, measured. The declaring scope's environment, escape from every clip
(divergence 10) and click-to-dismiss/wheel routing (`IN-W`) all still hold and
are now pinned under **both** authorities (`PresentationWindowTests`). Every
case where the legacy containing block is not the window
(`deferred.containingBlock`/`.nested`/`.root`/`.amended`, owner stage 9), an
absolute box **outside** a `Deferred` (`position`/`inset` at the consumer,
owner stage 10), and `minSize`/`maxSize` on an absolute box's `auto` axis
(`…absolute`, owner stage 8) each **report by name** rather than lower to a
different answer. `LayoutAuthority.proposal` is still inert in production
until stage 6b, so none of this is reachable outside a test yet.

**`Component`** is layout-transparent and identity-opaque: no layout node, one
cursor index, `@State` under its own id. Its `.padding` wraps each top-level
node (`OM-D`); `.width`/`.height` **overwrite** each member (divergence 48);
`.frame` wraps the body in one layer. No `.background`/`.id()` (declare `var
elementID`) — by type only, and `anyComponent.frame(...)` is a side door. A
caller's modifier on a component never animates (B-7): declare animated sizes
inside it. Over proposal content declare `some ProposalElementGroup`.

**`@State`** is a box seeded by reflection per element per frame; slots are
`.named("$state<n>")`. Seven reserved names (`$state<n>`, `$focus`, `$ax`,
`$anim`, `$anim-color` slots; `$anim-content`/`$anim-viewport` id prefixes),
pinned by `theSevenRetentionSlotsAreMutuallyDistinct`. **Write from input,
never from a phase** (keeps the link awake forever). Inert inside
`AnyElement`. `prepaintGroup`/`paintGroup` re-bind, so a group-entry bind is
observable only at layout time. One element VALUE placed twice shares one box
(divergence 19) — build two values.

**`@Observable`**: the whole frame build is tracked. The `RedrawSentinel`, the
flush ordering in `drawFrameIfNeeded`, the `isFlushing` guard and
`markDirtyFromObservation`'s two branches are all load-bearing (RX-K);
collapsing either branch breaks the suite. A phase-time `@Observable` write is
silently stale.

**Hit testing.** One hitbox list; ranking is `topmostOpaqueHitbox(in:at:)` —
no second copy. `onClick` alone makes an opaque pointer target; the keyboard
gate (`onKey || isFocusable || actions || keyContext`) stays separate.
`allowsHitTesting(false)` gates only `registerHandlers`' pointer hitbox —
scroll regions and raw `insertHitbox` bypass it (`OM-AK`); it is per layer
(divergence 44). `contentShape(inset:)` moves the pointer region only and
needs an `onClick` on its layer (`OM-J`, `OM-AB`). Default hit region is the
whole frame (41). Handlers outlive the frame: `.onClick { window.x() }` is a
retain cycle.

**`StyledElement`** has four requirements (`style`, `decoration`, `elementID`,
`handlers`). A conformer calls `registerAndScope(handlers, decoration, …) {
content }` in `prepaint` and `paintDecoration(decoration, in:, for:) { content
}` in `paint` (background before content, border after, `OM-V`). Sites: `Box`,
`Stack`, `Text`, `ModifiedElement` (per layer). Each helper half has its own
per-site guard (`OM-AI`) — doing the work outside the closure passes one and
fails the other. `registerHandlers` holds the hitbox, focus, AX record and the
disabled gate; skipping it makes an element ungated and invisible to
VoiceOver. **Any hook added to `Element`'s group defaults must be mirrored per
layer in `ModifiedElement` and in `AnyElement`'s group entry** (`MC-B`,
`LR-AA`). `Handlers` has eight members; `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) each gain a field when it
gains one.

**Environment (`EV-`).** `EnvironmentScope` is layout- and
identity-transparent; nearest writer wins; transforms run once per frame in
layout and are re-pushed (`EV-V`). Readable in every phase except `theme`
(`PaintPass` only). `@Environment` binds like `@State`; unbound it silently
reads defaults. `Window.environment` writes always dirty — write from input.
`theme`/`pixelLength` are re-stamped each frame. **A modifier written after a
scope sits outside it** (`EV-X`). `.disabled(d)` is
`transformEnvironment(\.isEnabled) { $0 = $0 && !d }` (`EV-D`); the one gate
is in `Frame.registerHandlers`' **5-argument** implementation. Disabled: no
hitbox, nothing in the focus registry, still published to AX as disabled.
Scroll regions are outside the gate. A new handler-registering site gains an
arm in the D2 guard. `Binding` is a deprecated alias of `KeyBinding`, deleted
by task 10.

**Accessibility (`AB-`).** Nothing recorded until a client activates the
window (sticky). Synthesized nodes are records (`Frame.axEmissions`), never
`axNodes` or `$ax` (`AB-U`). Geometry is not structure (`AB-K`). Every
`NSAccessibility` override answers through `mainActorAnswer(_:fallback:_:)`,
never a bare `assumeIsolated` (`AB-AE`). A `display: none` layer suppresses
everything inside via `Frame.suppressingAccessibilityIfHidden` (`AB-O`). A
text-painting conformer passes `accessibleText:`. Qualify
`MetalUIPlatform.AccessibilityRequest` in files importing AppKit.

**Focus:** `Window.focus(_:)` is the only mover; clicking does not focus. Keys
go to the `Keymap` first, then bubble raw `onKey` up the parent chain.
`focusBorder(_:width:)` is the (opt-in) ring; background and border resolve
`focus ?? hover ?? plain`.

**Text.** `Text` and `ProposalText` measure and draw **only through
`Frame.textSystem`** (`TS-A`): a `TextSystem` chosen once per app
(`App(device:textSystem:)`), CoreText over the frame's `ShapingCache` by
default (`TS-B`), `PortableTextSystem` otherwise (`TS-C`). A new text-drawing
element goes through the seam too — reaching `ShapingCache` or
`placedGlyphs` directly puts it on CoreText whatever the app chose, which
`TextSystemSeamTests` catches only for the elements it renders. Never key a cache on a family or PostScript name — `FontKey` reads
four components off the resolved `CTFont` (and still conflates shaping
behaviour, pinned wrong on purpose). `FontKey` stores its hash; `==` uses it
as early reject only; to force collisions under mutation make the **stored**
hash constant. `FontResolver.resolve` traps on non-finite/non-positive sizes.
`fonts` and `resolvedFonts` are never swept, deliberately — move both or
neither. Min-content is `CFStringTokenizer`'s longest word (TX-F); the public
`unbreakableRuns(of:)` must create a tokenizer per call; every path bumps
`Shaper.runCallCounter`. Max-content is one line per hard break (TX-K). The
glyph atlas is grow-only; `evictUnusedSince` has no caller and would strand
pixels.

**Renderer.** No semaphore; the atlas texture is written only while
`atlasTextureWasEncoded` is false, else replaced, and it is uploaded
**before** encode (`MetalWindowRenderer.finishFrame`; mutation R1 reddens the
blank-first-frame test). The SDL renderer keeps its atlas texture between
frames and re-uploads it whole when dirty; both clear the atlas' dirty rect
after a frame. `Text.requestLayout` and
`ProposalText`'s measure closures use unguarded `MainActor.assumeIsolated` —
layout must stay synchronous on the main actor.

**Animation (`AN-`).** `withAnimation` writes `pendingTransaction` (lexical)
and `parkedTransaction` (handed to exactly one frame build). The park rolls
back unless a frame build is coming; both clauses are measured fixes.
Layout-phase helper `animated(_:_:for:pass:)` (`AnimatedStyle.swift`); colour
helper `animatedBackground` in paint (`AnimatedColor.swift`, needs the theme).
A site that skips its helper is silently unanimated — guards
`everyRegisteringSiteAnimatesItsStyle`, `everyBackgroundPaintingSiteAnimatesItsColour`.
Interpolation is per-component RGB, never hue; slots store tokens. "Live" is
`Frame.noteActiveAnimation()` → `hasActiveAnimations`, copied after the whole
render; **not** `wantsAnotherFrame` — never raise both. **Snaps:** any
`Dimension`/`Length` case change (incl. anything touching `.auto` — declare a
real baseline), the five paint-only `Decoration` fields, a caller's modifier
on a `Component`, everything on the proposal path (`Grid` and `GridRow`
included). **An animated flex-item field snaps its STRUCTURE** (`LR-AS`): the
lowering reads which wrappers exist from the *declared* style and only their
values from the animated one, so a grow that appears or vanishes mid-flight
jumps and two equal declared factors stay equal mid-flight
(`anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`). Tests never
sleep: drive `simulateTick(timestamp:)`.

## SwiftUI alignment — the proposal layout path

A propose/measure/place engine sits beside the CSS engine. Detail: §19
"SwiftUI alignment", record §09, §17, §18, §21, §22, §25, §27, §29.

- **Two engines, chosen by the window root alone**
  (`tree.isNativeLayoutNode(root)`). A native root is placed centred at its own
  answer (`CN-J`). The kernel is the private `NativeNode` enum in
  `LayoutTree.swift` (twelve cases + `custom(any ProposalLayout)`); a new case
  must choose its zero-spacing edges.
- **Layout authority (task 7, `LR-`):** `Frame.layoutAuthority`, `.legacy` in
  production, internal until stage 6b. Under `.proposal` every legacy site
  checks the authority itself and lowers (border-box: content → padding →
  fixed frame, built from the **animated** style, checked against the
  declared); unlowerable fields trap naming `<site>.<field>` or, with
  `reportsUnlowerableFields`, report. **A new legacy registration site gains
  its own check and an arm in `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.**
  A branch lowering from a style needs an animated arm. Differential harness:
  `LayoutDifferential.compare` under `DifferentialRoot`; never a wrapping
  `Text` or greedy child directly under the root; a window test under
  `.proposal` pre-flights under diagnostics with `try #require` on an empty
  report. The bounds log is recorded at four sites; a new group entry records
  too.
- **Stage 2 lowers the flex ITEM fields, by the parent** (`LR-AB`…`LR-BA`).
  Every lowered site records a `LoweredItem` and reports no item field itself;
  a lowered container consumes its children's records and wraps each, and **a
  record nobody consumes is reported by name** (`LR-AQ`) — a new lowering site
  that receives children consumes or marks them, or its children's fields go
  silent. Lowered: `stretch` and a non-stretch `alignSelf` as cross-axis frames
  (stretch's is **aliased as the element's rect**, so decoration, hitboxes,
  accessibility and text wrap follow it); `flexGrow` as a greedy main-axis
  frame shared equally; a zero `flexBasis` on an unsized grower;
  `flexShrink: 0` as `fixedSize` and any positive shrink as SwiftUI's
  compression; px/rem `minSize`/`maxSize` folded into a declared size as
  `max(min, min(size, max))`; `Style.border` as insets inside the declared
  size; a `Text`'s `Style.padding` around **its leaf** (glyphs paint and wrap
  at the leaf); `margin` as a native padding outside the item frame, unaliased,
  `.auto` as 0, negative accepted; `justifyContent`'s three distributions as
  native spacers plus a rigid gap leaf, with a declared main size only;
  `.rowReverse`/`.columnReverse` as the children's **nodes** reversed with the
  main factor mirrored (identity, paint, hit and accessibility order
  untouched). Still reported by name, each with an owner: percentages, unequal
  grow weights, a length `flexBasis`, a non-greedy `maxSize`, `space-*` on an
  unsized container a parent grows, `baseline`, `hidden()`. **Structure reads
  the declared style, values the animated one** (`LR-AS`); a new read of
  `Style` in the lowering owes an animated arm, or it is unpinned. A `Stack`
  and a `.frame` layer ignore a child's margin, as the legacy engine does. A
  child with **no record** — a proposal element such as a `Grid` — gets an
  empty plan: it is never stretched, grown or margined (record §23, X2).
- **Stage 3 lowers scrolling and `Component` distribution** (`LR-BB`…`LR-BP`).
  A `ScrollView` lowers its content through `lowerLegacyNode` at site
  `scrollView` (stage 2's container lowering entire) under a
  `requestNativeScrollViewport`, and records **the viewport** as its own
  `LoweredItem`; `flexShrink: 0` is not carried, and the content record is left
  unconsumed, so a later field belongs on the **declared** content style or it
  vanishes silently (`reportUnconsumedLoweredItems` never reads the animated
  one). The lowered viewport **fills its proposal on the scrolling axis** where
  the legacy one hugs; the cross axis agrees, and divergence 54 **survives**
  because only a `ScrollView` records an item. `ScrollContext`, `$anim-content`
  and `$anim-viewport` are unchanged, and `List` still windows against the
  published context. A `Component`'s `.width`/`.height` lowers to **one native
  frame per member**, aligned per axis (`.center` on a declared axis, 0 on an
  `auto` one) with the member's record consumed and planned at
  `parentKind: .stack`, which **drops** its `flexGrow`, `flexShrink`,
  `flexBasis`, `alignSelf` and `margin`; `.padding` lowers as an ordinary
  one-child container; a `.frame` layer over several member nodes is a row of
  per-member frames at spacing 0. Site `component` has **no reachable report**
  left. **Both scroll suites run under both authorities** — 34 scenarios, a
  roll call that names any scenario that stops participating, and a new one
  owes an `AuthorityCoverage.record` call and a bump of the registry's
  literal (stage 4 renamed the registry and absorbed these 34 into its own
  count; 82 since stage 5).
- **Stage 4 lowers `List`** (`LR-BQ`…`LR-CG`). The behaviour is in the `List`
  paragraph above. Two things a reader needs here: the exit criterion is now
  **67 scenarios across ten files under both authorities** (82 across
  fifteen since stage 5), and
  `ScrollAuthorityCoverage` is **renamed `AuthorityCoverage`**, with
  `everyScrollScenarioRanUnderBothLayoutAuthorities` renamed
  `everyParameterisedScenarioRanUnderBothLayoutAuthorities` and moved to
  `Tests/MetalUITests/ZZAuthorityRollCall.swift` so that it sorts after every
  contributing file. A new parameterised scenario owes an
  `AuthorityCoverage.record` call and a bump of the literal (82 since
  stage 5, below).
- **Stage 5 makes `Deferred`'s absolute content a presentation root**
  (`LR-CH`…`LR-CS`). The behaviour is in the `Deferred` paragraph above. The
  exit criterion is now **82 scenarios across fifteen files under both
  authorities** (`AuthorityCoverage.expected`), and presentations are laid out
  in their own native runs, in registration order, **before** the root in
  `Frame.computeRootLayout` — separate runs so a presentation's depth counts
  from its own root and the root's `SA-M` work literal is untouched. A new
  parameterised scenario owes an `AuthorityCoverage.record` call and a bump of
  the 82.
- **`ProposalLayout`** (`SA-A`…`SA-F`): `sizeThatFits` + `placeSubviews`, no
  cache. Measurement cannot place (compile-time); `place` only records, last
  wins, unplaced is centred. Migration: leaf → `requestNativeLeaf`; algorithm
  → `ProposalLayout`; container with paint/input → `requestGroupLayout` +
  `requestNativeLayout`.
- **Stacks are SwiftUI's** (`CN-B`…`CN-I`, probe
  `swiftui-stack-algorithms.swift`): priority groups, least-flexible-first,
  overflow counted; `Spacer` priority −∞, default min 8; default spacing per
  adjacent pair (`CN-H`); typed alignment (`CN-I`); `ZStack` places each child
  at its own size in the union (`CN-E`); infinite proposal answered with ∞ by
  infinite-max frames, spacers, scroll axes (`CN-F`). Flexible frame is greedy
  (`FR-A`, `FR-M`; test is on the minimum's presence).
- **One authority per root, no adapter** (`SA-G`): native-under-legacy,
  legacy-under-native, a `Style` on a native node, `computeLayout` on a native
  root all trap. `ProposalElementGroup` has one requirement returning
  `[ProposalNodeID]`; `ProposalNodeID`'s init is internal (`MC-G`). One id
  registered under two parents traps (`CN-L`). **A copy of a pinned entry is
  unpinned**: the typed builder-group entries and `EnvironmentScope`'s are
  line-for-line copies, each with its own pin; a new group gets its own.
  Single-child proposal wrappers precondition exactly one node.
- **Invalidation** (`SA-H`, `SA-I`): the cache lives for one call; answers
  assumed pure; `setLayout` traps during measurement; **one `isLayingOut` flag
  guards both engines — do not split it.**
- **Validation** (`SA-J`, `SA-K`): reject a parameter only if SwiftUI rejects
  it or it would make a node non-finite at a finite proposal. Measurements may
  be infinite, stored rects may not, nothing may be NaN. Relaxing a trap into a
  clamp later is additive; the reverse breaks callers.
- **Depth guard** `NativeLayoutRun.maxDepth` = 88 (`SA-L`); raise only after
  re-bisecting all four node kinds. A padded, sized legacy container lowers to
  3 native levels, and since stage 2 an item with a margin, a padding, a size
  and a stretch is **five**, so a chain of those reaches the 88/89 boundary at
  122/123 nodes (record §21, test 4.8). The default demo's deepest lowered path
  is **measured at 18**, not the 22 `LR-Q` estimated. **`SA-L`'s own depth
  table is stale**: the vertical stack completes 128 levels at `cb2e708` where
  the 2026-09-14 table reads 151, which by `SA-L`'s rule would give 72 rather
  than 88 (found by the grids track; owner is `LR-Q`'s stage 6b re-bisection).
  **Work counters:** `LayoutTree.lastNativeLayoutWork` (`SA-M`) on a branching
  tree, literals derived before the run.
- **`Grid` and `GridRow` (stage G, `GR-`).** A column is as wide as its widest
  single-column cell, a row as tall as its tallest.
  - **A grid is a kernel CASE, not a `ProposalLayout`** (`GR-C`), so its
    algorithm is not reachable through the public protocol.
    `Content: ProposalElementGroup`, so `Grid { Box() }` is a compile error,
    not an `SA-G` trap (guard).
  - **A `GridRow` is the one proposal group with an identity level of its
    own**: one cursor index, its cells numbering from 0 under it. A
    `GridCellModifier` is layout- and identity-**transparent**, like
    `EnvironmentScope`.
  - **The row mark is written after the content registers and the OUTERMOST
    row mark wins**; a cell attribute keeps the **first** value written, so the
    **innermost** modifier wins; `gridCellColumns` **sums** along a chain and
    unsized axes **union**.
  - **Attributes are read through a modifier chain** (`frame`, `padding`,
    `fixedSize`, `aspectRatio`, `layoutPriority`, an overlay attachment's
    child 0) and the walk **stops** at a stack, a `ZStack`, an overlay's
    content side, a scroll viewport, a custom layout, a nested grid, a spacer
    or a leaf.
  - **Spacing `nil` is the largest platform-default pair spacing meeting at
    each boundary**, not one number for the grid (`GR-D`); a given value is
    used verbatim on every gap of that axis, negative included.
  - **A vanishing `if` inside a grid moves the cells after it** — the
    framework's universal trailing-sibling adoption, inside a row and between
    rows — and no built-in proposal element has `.id()`, so the documented
    remedy cannot be spelled until task 8.
  - A grid registers and paints nothing of its own, publishes nothing to
    accessibility and never animates (`GR-K`). It **consumes no `LoweredItem`**,
    so a legacy item field on a top-level cell reports
    `<site>.<field>.unconsumed` (record §23, X4).
- **Vocabulary.** Proposal types: `HStack(alignment:spacing:)`,
  `VStack(alignment:spacing:)`, `ZStack`, `Spacer`, `Rectangle`, `Color`,
  `ProposalFrame` (not `Frame`), `Padding`, `Background`, `FixedSize`,
  `ProposalScrollView`, `ProposalText`, `ProposalLayoutContainer`,
  `Grid(alignment:horizontalSpacing:verticalSpacing:)` and `GridRow(alignment:)`
  with the four cell modifiers `.gridCellColumns(_:)`, `.gridCellAnchor(_:)`,
  `.gridColumnAlignment(_:)` and `.gridCellUnsizedAxes(_:)`. Modifiers
  on `ProposalElementGroup` return `ModifiedContent`. `Native…` types and
  `native…` methods are deprecated aliases (except the two `nativeFrame`
  overloads — deprecating them breaks the 0-warning baseline); the kernel's
  `requestNative*`/`newNative*`/`computeNativeLayout` are primary API — 13
  registrars each on `LayoutPass` and `LayoutTree`, plus the two mark
  functions. **Count them by type, not by file**: `Passes.swift` holds only 12
  of `LayoutPass`' registrars; the thirteenth, `requestNativeGrid`, and both
  mark functions are in `Grid.swift`'s extension, so a grep of `Passes.swift`
  alone reads 12 and is wrong.
  `.padding` splits by argument type (no proposal `.padding(Pixels)`).
  `Text.proposalLayout()` silently drops background, handlers, id and
  hover/focus colours. **`ScrollView` and `ProposalScrollView` share one
  `ScrollChrome`** (clamp, extent, delta, indicator bounds, `paintIndicator`,
  both `resolvedOffset` overloads), a computed `var chrome` each side rebuilds
  from its `axis`, `cornerRadius` and `indicatorVisibility`, never stored;
  `ScrollView.clamp`/`.extent` are
  gone. A private copy re-inlined on either side **and drifting** reddens
  `theTwoScrollElementsShareOneChromeImplementation` — measured in both
  directions (M1f and the verifier's V7, each a `paintIndicator` copy with a
  30pt thumb floor). A **byte-identical** re-inline reddens nothing: that test
  compares the two elements' output, not their call graph, so it catches the
  drift, not the copy.
- **`SA-N`'s "probed, and the kernel disagrees" list is EMPTY.** Its last item
  — padding placing its child at the child's own size — was closed by stage 2's
  lane 3 (`LR-AU`) on both entries, pinned by
  `aNativePaddingPlacesItsChildAtTheChildsOwnSize`. Do not re-add a row without
  a probe run now.

## Workflows and subagents — token budget

A five-lane stage has cost 6–12M tokens (~25 Opus 1M-context agents at
0.2–0.5M each; every agent loads this file). When writing a workflow:

- **Two or three lanes, not five.** Split only where lanes touch disjoint
  files; each lane pays to load the same code.
- **Model by job:** Opus for design, implementation and mutation
  verification; `model: 'sonnet'` for record, docs, count re-takes, greps and
  first-pass checks.
- **Merge adjacent agents over the same material:** critique + revise in one
  agent, record + docs in one agent.
- **Re-verify only on a finding.** No fix/re-verify round when the verifier
  returned `ok`.
- **Pass paths, not content.** Prompts name the files, rulings and record
  sections an agent needs; agents return conclusions (a verdict, a mutation
  table, a diff summary), not file dumps.
- Stay under the session's workflow size guideline unless the user asks for
  more.

## Practices — the short form

Read `docs/practices/verifying-tests-can-fail.md`; history in record §02.

- **Findings come from mutation, not inspection.** Change the declaration a
  test is named for and confirm it reddens — by running it. Require the arms
  of a comparison to disagree before believing they agree (shape 15).
- **A mutation that reddens nothing is a broken instrument or the finding**;
  prove the mutant differs. Name the tests it reddens, not a count.
- **Any count a later loop indexes on is `try #require`** (shape 13).
- **A `@testable` test cannot prove an access-level narrowing** (shape 16);
  use a plain-import typecheck guard, written in the change that introduces
  the hazard.
- **When a claim is refuted, fix everywhere it was copied** — spec, plan,
  source comment, this file, the record. Re-take whole tables, not sampled rows.
- **State a "the old wording is gone" claim as the grep reads it.** A corrected
  paragraph usually keeps the old sentence as a quoted erratum, so the grep
  returns one hit and a checking reader concludes the fix never landed. Say
  which hit survives and why.
- **Re-run a mutation a doc comment names when the code under it changes.** A
  later lane can delete the branch the mutation targeted, or make the shape
  stop discriminating; both were found by re-running, not by reading.
- **A confident "cannot" that was not measured is the tell** (shape 14).
- **Reviewer dispatches say not to invoke the `code-review` skill.** Run
  mutation testing in an isolated `git worktree` when another agent is live.
- **Performance tests count work, never wall clock**, are red on arrival, and
  use a branching tree in a configuration where the code is reachable.
  Allocation counts (`malloc_logger`) are taken in the suite's configuration.
- **A probe must have a separating arm** before a ruling rests on it (`FR-M`);
  a rule read from one arm is unprobed for node kinds that arm lacks.
- **A helper with two halves needs two per-site guards** (`OM-AI`); an order
  test needs a two-layer chain (`OM-AD`).
- **A copy of a pinned implementation is unpinned** — mutate each copy.
  **Record which branch a mutation was applied to**: a whole-file substitution
  over two byte-identical call sites is a different mutation, with a different
  reddened set, from a scoped one (stage 3's M2g). **And record which SPELLING
  it was applied to, not only which branch**: "the records not consumed" and
  "the records neither read nor consumed" redden the same seven tests with 12
  and 46 issues, so a later reader re-running the wording gets a different
  number with no way to tell which reading is the instrument (stage 4's M2f,
  and M2a's 30 vs 47).
- **A harness decision is a mutation site.** Stage 4 lane 3's host box — the
  largest decision in the lane — was pinned by none of the lane's three
  mutations, and the one the verifier took (drop its declared height) both
  reddened eleven scenarios and refuted the published reason for it.
- **A fixture of fixed-size leaves cannot see a container lowering.**
  `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` are all
  no-ops over children that declare no item field, so "this lowers as the
  container lowering" needs a child that gives the container something to do
  (stage 3's M2b and M4b, the same finding one lane apart).
- **Parallel tracks owe tests for the merge**; only the merged suite runs them.
  **A clause both tracks share can be pinned by neither**: dropping the clamp
  from the lowered `Text` alone left all 1548 merged tests green, because the
  engine track pinned it only through `ProposalText` (record §23, XM4).
- **A green mutant may be the correct spelling** (`LR-X`).
- **A window test in a mode that traps pre-flights in a mode that reports.**

## Reference tables (moved to the record)

Consult before changing the behaviour they describe; each is a table of
expected, measured facts:

- **Known divergences** (**58 live**, stable labels; retired labels never
  reused: 3, 5–8, 12, 15, 17, 36, 37, 40, 59) — record §04 is current (its
  2026-09-21 section retires 59 and adds 60–70, the stage 2 and grids rows,
  its 2026-09-22 one amends 48, 54 and 56 for stage 3 without retiring or
  adding a number, its first 2026-09-23 section likewise amends **13, 14 and
  18** for stage 4 — 13 and 14 survive unchanged with 14's pin now running
  under both authorities, and 18's numbers move to `2n + 6`, crossing at
  **126** rows — and its second 2026-09-23 section (stage 5)
  amends **9, 10 and 11** without retiring or adding a number: 9 survives on
  both authorities, 10 is unchanged and gains SwiftUI evidence (agrees with
  SwiftUI's presentation, disagrees with its overlay), 11 becomes
  legacy-only (retires with the legacy authority at stage 9));
  §19 "Known divergences" is the frozen 48-row copy. Many are *pinned wrong on
  purpose*; a test named for one reddening may be a fix, not a bug.
- **Declared but inert** APIs (compile and do nothing: `AlignItems.baseline`,
  `Style.aspectRatio`/`overflow`, `margin: .auto`, `Style.border` on a
  container, `Position.relative` offset, `hidden()` on drawing/focusable
  subtrees, `AnyElement`'s `@State`, `PaintPass.isActive`, `onInput`'s `->
  Bool`, colour glyphs, baselines, `LayoutAuthority.proposal` in production,
  `locale`/`layoutDirection`/`dynamicTypeSize`, one axis each of
  `markNativeGridRow`/`markNativeGridCell`'s alignment, a grid mark outside a
  grid, …) — §19 "Declared but inert", record §05, whose 2026-09-21 section
  carries the stage 2 and grids changes, whose 2026-09-22 one carries stage
  3's and whose first 2026-09-23 one carries stage 4's: `UnlowerableField` site
  `.list` now has **no site-level reporter left** (the same shape as site
  `component`), `LayoutAuthority.proposal` in production stays inert until
  stage 6b, and the internal `ListRows.GroupLayout.spacer` is stored on every
  frame of every legacy `List` and read by nothing. **Three of those rows are
  legacy-authority only**: under `.proposal`, stage 2 lowers `margin: .auto`
  to nothing explicitly, `Style.border` on a container to insets, and a
  `Text`'s `Style.padding` around its leaf. `Style.overflow` is **not** one of
  them: stage 3's lowering does not carry it either, and `loweredLayout` says
  so in a comment. Implementing one: delete its row;
  adding an unimplementable property: add one. **Stage 5's (second
  2026-09-23) section adds no row**: its new reports
  (`deferred.containingBlock`/`.nested`/`.root`/`.amended`, the two
  `…absolute` fields, `position`/`inset` moved to the consumer) are
  diagnostics read by the report mechanism itself, not stored-but-unread
  state; `LayoutAuthority.proposal` in production is still the one inert row
  this stage touches, and it is unchanged.
- **Human verification** status per milestone, demo keys (**M** modal,
  **Space** theme, **F**/**Esc** focus, **=**/**-** count, **A** animation,
  **Q** quit) and open looks — §19 "Human verification", record §03, whose
  2026-09-21 section adds the two stage 2 / grids rows, whose 2026-09-22 one
  adds stage 3's and whose 2026-09-23 one adds stage 5's. Nothing
  in the suite sees paint order, portals, scroll direction, presentation, the
  display link or real hover; those are looks. Padded legacy container rule:
  container modifiers and `.flexGrow(1)` before `.padding`; size, background,
  corner radius after. **Four looks are open here**: the stage 2 / grids
  release-window capture (the screen was locked; the offscreen half read nine
  of twelve images at 0 and attributed the three preview images to the grids
  track's four preview cells); the preview's grid itself, which nobody has
  seen on screen (`GR-N`); and stage 3's capture against `57893d0` (the screen
  was locked at every lane, at the verification round and at the Docs phase —
  the offscreen stand-in read 0 in all twelve, twice more in verification, once
  with an independently written harness, and the two-authority chrome pair 0,
  but **none of the twelve scenes is ever scrolled**, so no indicator is
  painted in any of them and the fold's indicator half is pinned by tests, not
  pixels). **Stage 4's capture is taken, and read 0 differing** — three times
  (lane 3 at `352f838`, and two verifiers at `9ad98db` and `a53daeb`), each
  with four a-vs-b stability zeros and a ~921 000-pixel default-vs-preview
  control, plus the twelve offscreen images at 0 at every lane and twice more
  in verification. **The demo's `List` is never windowed in any of them** (one
  cold frame, `firstIndex == 0`), so the windowing is pinned by tests, not by
  pixels. Nothing in production runs under the proposal authority, so **no
  demo look is owed until stage 6b**. **Stage 5's capture is open too**: the
  screen was locked at all three lanes (03:11, 04:02, 04:41 PDT), so
  `capture.sh` was never run; the offscreen twelve read 0 differing at every
  lane, and no demo look is owed by this stage either — `Deferred` as a
  presentation root is reachable only under `LayoutAuthority.proposal`.
- **Performance** figures (µs/node, warm frame, cold `List`, native work
  counts) — §19 "Performance", record §07. Most are stale since `f1944f8`;
  re-measure before reasoning from them. **`MP-I`'s 100 000-row cold frame
  re-measured 2026-09-23 on this machine: 12.24 s release legacy / 7.55 s
  release proposal, 37.16 s / 24.98 s debug** — the ~17 s figure carried
  elsewhere is stale, and that staleness is not a change stage 4 made. The
  proposal path's cold frame is about a third faster than the legacy one at
  that size: measured, not a goal, and asserted by nothing.
- **CI hazards** — §19 "CI", record §08. Key ones: all **77** guards skip
  under the
  default build system (take guard counts under `--build-system native`, and
  grep logs for `FR-J no-argument frame: succeeded=` to know guards ran — a
  guard that ran costs real `swiftc -typecheck` time, ~0.46 s each for the four
  `GridCompileGuards`, which is the only way to tell it from one that returned
  true for free); the
  freeze-loop allocation pin checks only half itself on Apple toolchains
  (`FREEZE-ALLOC: strict per-pass bound NOT CHECKED`); `malloc_logger` tests
  need `--no-parallel`; E24 hard-fails under the root locale; seven
  `AnimationTests` hard-fail without a display device. Two more were added by
  stage 3 (the first renamed and widened by stage 4, then widened again by
  stage 5) and one by stage 4:
  - `everyParameterisedScenarioRanUnderBothLayoutAuthorities` (stage 3's
    `everyScrollScenario…`, renamed and moved to `ZZAuthorityRollCall.swift` by
    stage 4) reads coverage accumulated by **fifteen** other files (ten at
    stage 4; stage 5 adds `AbsoluteOverlayTests`, `DeferredTests`,
    `DecorationPaintTests`, `EnvironmentTests` and `PresentationWindowTests`)
    and so depends
    on Swift Testing's **unspecified** cross-file order (measured on Swift 6.4
    only). On a runner with a different order it is a spurious red, and
    `swift test --filter everyParameterisedScenario` hard-fails. It always
    names what it had not seen — read the names before debugging.
  - **Three `AccessibilityDefaultsTests` scenarios call
    `AuthorityCoverage.record` after `try #require(MTLCreateSystemDefaultDevice())`**,
    where the other eight parameterised scenarios record first. On a
    display-less runner they fail at the require *and* the roll call fails a
    second time naming them as having recorded no coverage — the second
    message points at the registry, not at the absent device.
  - A proposal-authority regression that reports an `…unconsumed` field now
    **traps in a `Window` test and truncates the run with no summary line**
    (the first such test is #1251). Read the last lines of the log, not the
    summary. **Stage 5 widens this**: any regression a presentation reports
    by name (`deferred.*`, `position`/`inset`, `…absolute`) traps the same
    way inside `PresentationWindowTests`, which is why every scenario there
    pre-flights under diagnostics with `try #require` on an empty report
    before opening its `Window` — a new presentation window test owes one
    pre-flight (and one per animated end state).
