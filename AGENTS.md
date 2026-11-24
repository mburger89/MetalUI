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
  live SwiftUI difference — **236 live, next label 244**; which labels each milestone reserved, used or
  retired: `docs/rules/divergence-labels.md`; retired labels are never reused), `docs/migration.md`, `THIRD-PARTY-NOTICES.md` (licences of the vendored C code, the bundled Lucide icons and SDL3/AccessKit, per product), `docs/verification/human-checks.md`
  (one group per milestone, each headed in the file; **not run — an agent cannot**), `docs/verification/voiceover-script.md`.
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
# also METALUI_TEXT_INPUT_DEMO=1, METALUI_CONTROLS_DEMO=1, METALUI_DND_DEMO=1, METALUI_LOOKS_DEMO=1, METALUI_METALVIEW_DEMO=1, METALUI_MENUS_DEMO=1, METALUI_SERVICES_DEMO=1, METALUI_LIST_DEMO=1, METALUI_RICH_TEXT_DEMO=1, METALUI_CANVAS_DEMO=1, METALUI_APP_SHELL_DEMO=1, METALUI_SELECTION_DEMO=1, METALUI_INVALIDATION_DEMO=1, METALUI_RETAINED_DEMO=1, METALUI_CHROME_DEMO=1, METALUI_CLIPBOARD_DEMO=1, METALUI_LAZY_DEMO=1, METALUI_CODE_DEMO=1, METALUI_MARKDOWN_DEMO=1, METALUI_TABS_DEMO=1, METALUI_OUTLINE_DEMO=1, METALUI_TERMINAL_DEMO=1, METALUI_GLASS_DEMO=1, METALUI_KEY_FOCUS_DEMO=1, METALUI_OVERLAYS_DEMO=1, METALUI_ACCESSIBILITY_DEMO=1, METALUI_TABLE_DEMO=1
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
METALUI_RUN_100K_OUTLINE_TEST=1 swift test --filter anOutlinesWorkIsTheSameFor100kPathsAsFor500
METALUI_RUN_1M_TABLE_TEST=1 swift test --filter aTablesWorkIsTheSameFor1MBy200AsFor1kBy20
```
- **Counts (2026-11-23, `feat/linear-element-builder`, record 398): root 7265 tests in 79 suites, full run green (+5: `theTupleGroupFindsEachMemberWhereTheTupleStoresIt`, `aBuilderBlocksStackGrowsLinearlyWithItsChildren`, `elevenChildrenOfOneBlockKeepTheirFlatIdsAndTheirState`, `elevenChildrenKeepTheirAccessibilityIdsAndTheirTabOrder`, `theSiftToolbarShapeBuildsOnA768KiBThread`; `--build-system native`, `--no-parallel`); divergences unchanged, 236 live, next label 244; the previous line, record 397: see below; before that, record 395: root 7242 tests in 79 suites, full run green (+6: `MemoBoundaryWriteCostTests` and `TertiaryLabelTests`; `--build-system native`, `--no-parallel`); the previous line, record 392 "Fixes after merge": root 7236 tests in 79 suites, full run green (+1: `aSortedHeaderCostsOnlyItsChevronWhileNoClientCollects`; `--build-system native`, `--no-parallel`); before that, record 392: root 7235 tests in 79 suites, full run green (`--build-system native`, `--no-parallel`; +15 over `feat/table-d`'s 7220: `TableAccessibilityTests` 10, `TableAppKitAccessibilityTests` 4, `AccessibilityTableFieldsTests` 1; the two node-field parity tests gained four arms each); SDL package (`swift test` in `Backends/SDL` with `fetch-accesskit.py`'s flags): 441 tests, +5 `AccessKitTableTests`, `windowServerTrafficNeverStopsTheMainRunLoop` fails as on master and `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` fails only in a sandbox that cannot write the Xcode toolchain's `pm` directory; divergences 236 live (1107 added, 32 amended), next label 244 (1107 is from the TBL reservation). Earlier counts: record §67 and its appendix.**
- **Counts (2026-11-23, `feat/code-style-faces`, record 397): root 7260 tests in 79 suites, full run green (+14: `CodeStyleFacesTests` 12 and `CodeStyleFacesFontsTests` 2, the portable arm running where a monospaced family is installed; `aDirectoryScanFindsEveryFaceWithItsNamesInPathOrder` now lists the two new test fonts; `--build-system native`, `--no-parallel`); divergences unchanged, 236 live, next label 244; the previous line, record 396: root 7246 tests in 79 suites, full run green (+4: `HarnessInputTests` newline, CRLF, tab and submit; `--build-system native`, `--no-parallel`; divergences unchanged, 236 live, next label 244); the previous line, record 395: root 7242 tests in 79 suites, full run green (+6: `MemoBoundaryWriteCostTests` and `TertiaryLabelTests`; `--build-system native`, `--no-parallel`); the previous line, record 392 "Fixes after merge": root 7236 tests in 79 suites, full run green (+1: `aSortedHeaderCostsOnlyItsChevronWhileNoClientCollects`; `--build-system native`, `--no-parallel`); before that, record 392: root 7235 tests in 79 suites, full run green (`--build-system native`, `--no-parallel`; +15 over `feat/table-d`'s 7220: `TableAccessibilityTests` 10, `TableAppKitAccessibilityTests` 4, `AccessibilityTableFieldsTests` 1; the two node-field parity tests gained four arms each); SDL package (`swift test` in `Backends/SDL` with `fetch-accesskit.py`'s flags): 441 tests, +5 `AccessKitTableTests`, `windowServerTrafficNeverStopsTheMainRunLoop` fails as on master and `thePublicLocateDoesNotEvaluateItsBundleWhenTheExecutableCandidateOpens` fails only in a sandbox that cannot write the Xcode toolchain's `pm` directory; divergences 236 live (1107 added, 32 amended), next label 244 (1107 is from the TBL reservation). Earlier counts: record §67 and its appendix.**
  - E24 hard-fails under the root locale; seven `AnimationTests` need a
    display device.
