# Developer guides — design

Item 10b of the plan list (the agent-doable half of item 10, docs; user request 2026-10-02;
**not a plan task**). Branch `docs/guides` from `ff8a1ea4`. Rulings `DG-A`… in
[`../2026-10-12-guides-decisions.md`](../2026-10-12-guides-decisions.md); record
`docs/record/103-guides.md` (written at the Record phase). **No public API, no source change
outside `Tests/`, no pixel change, no divergence added** (the branch's reserved labels 335–344 stay
unused unless a guide's verification finds a real difference, in which case it is a *finding* for
the orchestrator, `DG-J`).

**Status: LANDED** (record §103; two lanes verified `ok`). Where the build departed from this text, the
ruling wins: `DG-N` (tilde fences refused, not ignored), `DG-P` (no `runUntilIdle()` after a click),
`DG-Q` (no `Canvas` task: MetalUI has no public `Canvas`).

## 1 Inventory (what exists at `ff8a1ea4`)

`docs/` holds `getting-started.md` (scaffold), `api-overview.md` (57 KB reference by area),
`migration.md`, `divergences.md` (175 rows), `packaging.md`, `testing.md` (a task-led guide whose
recipe is compiled by `Tests/MetalUITestingTests/TestingRecipeTests.swift` — the model this item
generalises). There is **no** task-led guide for layout, state/identity, input, presentations,
drawing or the cross-platform differences. `typecheckFile` (`Tests/MetalUITestSupport`) compiles a
fixture through `swiftc` and **skips silently** unless the native build system's `Modules`
directory is where `#filePath` expects — so it is not the mechanism (`DG-C`).

Merged API a guide may use (checked in `Sources/`): `WindowDragGesture`, `onCancelled`,
`TextSelection`, `onKeyPress`, `hoverKeyRegion`, `Material` with its backdrop blur, `ForEach`
identity by `Hashable` value (§95). **Not on master, so documented nowhere:**
`.resignsFocusOnPress` (C24, §98), `TextMeasurer` (C23, §99), the Material follow-ups (C27, §101),
the IME driver (C28, §102). A denylist check pins that (`DG-F`).

## 2 The six guides (`DG-A`, `DG-B`)

Files under `docs/guides/`, indexed by `docs/guides/README.md`. Each: a `# How do I…` title in
task form, 3–6 task sections, a closing **"Divergences you will hit"** list (every label by
number, one line each, linking `../divergences.md`), links to `../api-overview.md` and
`../testing.md` instead of repeating them, behaviour claims only with `(pin: \`testName\`)`.

| # | file | tasks | divergences named (lane checks each against its row) |
|---|---|---|---|
| 1 | `layout.md` | stacks and frames; legacy `Row`/`Column`/`Box` vs SwiftUI; why modifier order matters and `.id()` is outermost; `Grid` | 52, 73, `Row {}`→`HStack {}` gap |
| 2 | `state-and-identity.md` | `@State`/`Binding`/`@Observable`/`@Environment`; what resets state; `ForEach` identity; `List` windowing, `List(selection:)`, variable rows | 71, 78, 125, 134, 145–147, 255 |
| 3 | `input.md` | buttons and controls; gestures and the one arena (tap, drag, magnify, `WindowDragGesture`, `onCancelled`); keyboard (`onKeyPress`, focus, `hoverKeyRegion`); text fields and `TextSelection` | 94, 110, 139, 187, 188, 275, 276, 277 |
| 4 | `presentations-and-app-shell.md` | popovers and overlays; context menus and commands (the drawn bar off Apple); alerts and file dialogs; toolbar; windows, close, terminate | 110, 115, 126, 135, 136, 175, 176, 195 |
| 5 | `drawing-and-gpu.md` | shapes, paths, gradients, shadows, `compositingGroup()`; `Material`/backdrop blur; `Canvas`; `GPUSurface`/`MetalView` and the draw contract | 105–109 as the lane verifies, 166, 167, 205 |
| 6 | `cross-platform.md` | what differs on Linux/Windows (SDL); the text system; images; fonts; packaging pointers | 137, 138, 126, 136, 195 plus the SDL rows the lane finds |

Each guide's divergence list is *completed by the lane* from `docs/divergences.md` by grepping the
guide's topic; a label cited that has no row fails the doc-check.

## 3 The compile mechanism (`DG-C`, `DG-D`)

**A guide's ```` ```swift ```` block is a complete file-scope fragment** (imports, types, functions;
no top-level statements) and is copied byte-for-byte into a mirror test file between markers:

```
// guide: layout #1
…the block, verbatim…
// end guide
```

The mirror files are ordinary members of `MetalUITestingTests` (portable: macOS, the
`swift:6.4-noble` image, Windows), so **every build system compiles them and nothing skips**. A
macOS-only API is wrapped `#if os(macOS)` *inside the block*, which the guide shows. Block-level
names are unique across both lanes (`DG-K`) (convention: the guide's topic as prefix, `LayoutFixtureRoot`).
The ```` ```swift ```` fence is only for compiled code; illustrative or deliberately non-compiling
text uses ```` ```text ````; any other info string on a swift fence (`swift no-compile`) is refused.

The doc-check parses every `docs/guides/*.md` (`README.md` excepted from block rules, not from
link rules), extracts the swift fences in order, finds the `// guide: <file> #<n>` regions in the
mirror, and fails when the sequences differ in count or by a byte. It reads the repository from
`#filePath` and never writes.

## 4 Files and lanes

Two lanes, disjoint files, **run in order** (lane 1 lands the doc-check helper that lane 2 uses).

| lane | writes |
|---|---|
| 1 — guides 1–3 | `docs/guides/{README,layout,state-and-identity,input}.md`; `Tests/MetalUITestingTests/GuideDocCheck.swift` (parser, T1–T7 below, owned here); `Tests/MetalUITestingTests/GuideMirrorsLane1.swift` (mirrors + T8–T10) |
| 2 — guides 4–6 | `docs/guides/{presentations-and-app-shell,drawing-and-gpu,cross-platform}.md`; `Tests/MetalUITestingTests/GuideMirrorsLane2.swift` (mirrors + T11–T13); the `docs/guides/README.md` rows for 4–6 are lane 1's placeholders, filled by lane 2 (one-line edit) |

Record phase (not a lane): `README.md` and `docs/getting-started.md` links, `docs/record/103-guides.md`,
`docs/record/README.md` row, the one-sentence `CLAUDE.md` rule (+ `AGENTS.md` copy), the counts, the
human-checks group `GD`. **`docs/testing.md` is not edited** (C28 edits it); guide 3 links it.

## 5 Tests, each with its red-before and mutation

Red-before for every doc-check test is the absence of the helper/files (the test cannot compile or
`try #require`s a count of ≥ 1 guide). Each mutation is applied once, suite run unfiltered, named
tests reported, restored from a copy.

| id | test (name) | asserts | mutation that must redden it |
|---|---|---|---|
| T1 | `everyGuideBlockIsCompiledVerbatim` | per guide, swift fences == mirror regions, byte for byte, count `#require`d ≥ 1 | change one character in a guide block; change one in the mirror; delete a `// end guide`; add an unmirrored swift fence |
| T2 | `aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed` | fences are exactly `swift`, `text`, `sh` | write ```` ```swift no-compile ```` |
| T3 | `everyCitedPinNamesATestThatExists` | each `(pin: \`name\`)` has a `func name` under `Tests/` | cite a misspelt name; rename the cited test |
| T4 | `everyCitedDivergenceHasARow` | each `divergence N`/`divergences N, M` label has a `\| N \|` row | cite 999 |
| T5 | `everyRelativeLinkResolves` | each `](relative)` file target (anchor stripped) exists | break a link |
| T6 | `noGuideNamesAnApiThatIsNotOnMaster` | the denylist (`resignsFocusOnPress`, `TextMeasurer`, `PhaseAnimator`) occurs in no guide | add one |
| T7 | `theExtractorFindsFencesNestedInListsAndIgnoresTildesAndCRLF` | the parser on synthetic input (an indented fence, `~~~`, CRLF, an unterminated fence → error) | break the parser's fence close; the test must redden before any guide does (`verifying-tests-can-fail`) |
| T8–T10 | `theLayoutGuideBuildsInAHeadlessWindow`, `theStateGuideBuildsInAHeadlessWindowAndItsClaimsHold`, `theInputGuideBuildsInAHeadlessWindowAndItsClaimsHold` | the guide's root functions build in a `TestWindow`; the few runnable claims (a counter increments; a `ForEach` row keeps `@State` across a reorder; a cancelled press runs `onCancelled`) | delete a modifier a block names (`.id`, the `onCancelled`) → the claim reddens |
| T11–T13 | the same three for guides 4–6 (a popover/alert/menu through the seam; a `Canvas`/`GPUSurface` root builds; `#if os(macOS)` arms excluded on Linux) | as above | as above |
| T14 | `theGuideSetIsComplete` (lane 2) | `docs/guides/` holds exactly the six names and the README lists each | remove a README row |

A guide's behaviour claim without a `(pin:)` is not allowed to say "resets", "cancels", "retains",
"focuses" or "dismisses": T3's companion check `aBehaviourWordHasAPinOnItsLine` (lane 1, in
`GuideDocCheck.swift`) fails a sentence containing one of those words and no pin; mutation: delete a
pin. (Where the word is not a claim, the lane rewords.)

## 6 Demo, human checks, deferred

- **Demo:** none. Pixels 0 px (`docs/probes/demo-pixels/compare.sh`), `Expected.swift` unedited.
- **Human checks (Record phase):** group `GD`, one item: a person reads each guide once against the
  running demo and marks any step that surprises them. Nothing else needs eyes.
- **SwiftUI claims** come only from rows and probes that already exist (`DG-F`); a new claim needs a
  probe in `docs/probes/guides-*.swift` with a separating arm — expected none.
- **Deferred, named:** a guide for `.resignsFocusOnPress`, `TextMeasurer`, the Material follow-ups
  and the IME driver waits for their merges (owner: each branch's Record phase adds a task section to
  guides 3, 5 and 3 respectively, with its mirror); a seventh guide (testing is `docs/testing.md`);
  extracting code from the doc into the mirror automatically (a generator) — not built, because a
  generator that writes the mirror makes the byte check vacuous (`DG-D`).
- **Platform notes:** CRLF is normalised before the byte compare, SDL snippets are never swift fences (`DG-K`, `DG-L`); new tests move the count (`DG-M`).
- **Cost if the mirror drifts on a platform:** a Linux/Windows compile failure at push (CI), which is
  the point.
