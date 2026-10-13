# Developer guides — decisions

Rulings for item 10b: task-oriented guides whose every code block compiles (user request
2026-10-02; not a plan task). Spec:
[`specs/2026-10-12-guides-design.md`](specs/2026-10-12-guides-design.md). Record:
`../record/103-guides.md` (written at the Record phase).

Evidence: an inventory of `docs/` and `Sources/` at `ff8a1ea4` (spec §1); `docs/testing.md` and
`TestingRecipeTests.swift` as the prior art. No SwiftUI probe was run: the item makes no new
SwiftUI claim (`DG-F`); gpui has no analogue (documentation).

Prefix **`DG-`**, lettered. **Next unused: `DG-P`.** (Moves in the commit that appends a ruling.)
Branch `docs/guides` from `ff8a1ea4`. Reserved divergence labels 335–344: none used.

**Carried items.** `HT-` (`MetalUITesting`, the harness the mirrors run in); `SA-P` (plain import);
the practice `verifying-tests-can-fail.md`; the test-count rule (counts are read, never inferred).

## DG-A — Six guides, no more

**Ruling.** Six guides: layout; state and identity; input; presentations and the app shell;
drawing and GPU; cross-platform. **Reasoning.** `api-overview.md` is organised by area and is a
reference; the questions an app author coming from SwiftUI actually trips on are the ones the
CLAUDE.md rules spend the most words on — modifier order and `.id()` (layout), what resets state and
`List` windowing (state), the one arena and focus rules (input), the shell (presentations), the
renderer constraints (drawing) and SDL (cross-platform). **Evidence.** Spec §2's table maps each to
divergence rows. **Cost if wrong.** A missing seventh topic is a later guide; the doc-check is
per-file, so adding one costs a mirror and a manifest line.

## DG-B — Form of a guide

**Ruling.** Task-led (`How do I…`), 3–6 tasks, short, links to `api-overview.md`,
`divergences.md` and `testing.md` rather than repeating them, closing with the divergences the
reader will hit, **each by number**. A block is a complete file-scope fragment. **Reasoning.** A
fragment of statements cannot be mirrored without wrapping, and a wrap is not byte-for-byte.
**Cost if wrong.** A reader copies a block that needs a `main.swift`: the guide's first task shows
the root function once and later blocks add to it by name.

## DG-C — Compile by mirroring in a test target, not by `typecheckFile`

**Ruling.** Each block is mirrored verbatim in a `MetalUITestingTests` source file and compiled by
the ordinary build. **Reasoning.** `typecheckFile` skips silently outside the native build system
(CLAUDE.md: guards), so a skipped guard would let a block rot green; a mirror file is compiled by
**every** build system and by the Linux and Windows CI that already build the target. It also lets a
block *run* in a `TestWindow` (spec T8–T13). **Evidence.** The target already runs portably (72 tests
in `swift:6.4-noble`). **Cost if wrong.** Duplicated text; bounded by DG-D's byte check.

## DG-D — The doc-check compares bytes, and a generator is refused

**Ruling.** `// guide: <file> #<n>` … `// end guide` regions in the mirror must equal the guide's
swift fences in order, byte for byte; a hand-copied mirror, never generated. **Reasoning.** A
generator that writes the mirror from the guide makes the check compare a file with itself. The
check is itself a mutation site: spec T1 and T7 list the five mutations that must redden it before
a guide is trusted. **Cost if wrong.** Copying is manual; a drift is a red test, never a silent one.

## DG-E — Citations are checked

**Ruling.** A behaviour is claimed only as `(pin: \`testName\`)`; the doc-check proves the test
exists (`func testName` under `Tests/`), every `divergence N` has a row, every relative link
resolves, and a sentence with a behaviour word (resets, cancels, retains, focuses, dismisses)
carries a pin. **Reasoning.** CLAUDE.md warns that record citations "were not all re-checked after
later refactors"; a guide is read by strangers. **Cost if wrong.** A renamed test reddens a doc
check, whose fix is one line — cheaper than a stale claim. Existence is checked, not that the test
asserts the claim; the lane reads each pinned test once.

## DG-F — Guides state no unmeasured SwiftUI fact and name no unmerged API

**Ruling.** A SwiftUI statement may only restate `api-overview.md` or a `divergences.md` row; a new
one requires a probe in `docs/probes/guides-*.swift` (positive control and separating arm).
`.resignsFocusOnPress`, `TextMeasurer`, the Material follow-ups and the IME driver are not
documented until merged (the denylist test). **Reasoning.** The user's rule: do not document
unmerged API; parallel branches C23/C24/C27/C28 are live. **Cost if wrong.** A guide short of a
feature until its branch's Record phase adds a section.

## DG-G — Two lanes, in order, disjoint files; the helper is lane 1's

**Ruling.** Lane 1 (guides 1–3) owns `GuideDocCheck.swift`; lane 2 (4–6) uses it and owns its own
mirror and the completeness test. `docs/guides/README.md` is lane 1's, with lane 2's three rows
filled as a one-line edit. **Reasoning.** The two guide sets share nothing else; a helper in a third
file would need a third lane. **Cost if wrong.** Lane 2 waits for lane 1; sequential anyway.

## DG-H — Platform-only API appears inside `#if` in the block

**Ruling.** A block using `MetalView` or any AppKit-only declaration wraps it in
`#if os(macOS)` inside the block, and the guide says so. **Reasoning.** The mirrors build on Linux
and Windows, where an unconditional use would fail the build. **Cost if wrong.** A reader copies
the `#if` they did not need; harmless.

## DG-I — Where the guides are linked

**Ruling.** `README.md` and `docs/getting-started.md` link `docs/guides/README.md` at the Record
phase; `docs/testing.md`, `docs/api-overview.md` and the migration doc are not edited (C28 edits
testing.md). **Cost if wrong.** A reader of `testing.md` does not see the guides until C28 merges.

## DG-J — A bug a guide reveals is a finding, not a fix

**Ruling.** No source change outside `Tests/`. If writing or running a block shows behaviour that
contradicts a doc or a pin, the lane records it under "Findings" in its report and the guide leaves
the claim out. **Reasoning.** Scope: docs only, pixels and the suite unchanged. **Cost if wrong.**
A known bug is not fixed here; the orchestrator schedules it.

## DG-K — Line endings are normalised on both sides; names are unique across the module

**Ruling.** The doc-check converts CRLF to LF in the guide and the mirror before comparing (a
Windows checkout with `core.autocrlf` would otherwise fail every block); nothing else is
normalised (trailing whitespace still differs). Block-level names carry the guide's topic as
prefix and are unique across **both** lanes' mirror files (one module, `MetalUITestingTests`; the
spec's "within a lane" was wrong). **Reasoning.** Windows CI is a stated target; a duplicate
top-level name breaks the module build only after lane 2 lands. **Cost if wrong.** A mutation
(CRLF in a guide) must stay green and one changed byte red; T7 pins both.

## DG-L — Blocks import only what `MetalUITestingTests` depends on

**Ruling.** Blocks use `MetalUI`, `MetalUIScene`, `MetalUITesting` (and `MetalUIPortableText`).
`SDLPlatform`/`MetalUISDL` snippets in guide 6 are ```` ```text ```` or ```` ```sh ````, never
```` ```swift ````, and the guide says they are not compiled by this check (their package is built
by `Backends/SDL` and the Linux image). **Reasoning.** Adding a dependency edits `Package.swift`,
outside `Tests/` (scope), and would pull an SDL trait into every test build. **Cost if wrong.** An
SDL snippet can rot; the guide points at the starter that `metalui new --cross-platform` builds.

## DG-M — The pin check accepts `func name` and `@Test func name`; counts move

**Ruling.** A cited pin exists when `func <name>` occurs under `Tests/` (XCTest and Swift Testing
spell alike). The branch adds tests (T1–T14 and the mirrors' runnable claims): the record reports
the new total as measured, not "unchanged" — "suite unchanged" in the brief means no existing test
or pixel moves. Behaviour words inside a fenced code block are not claims. **Cost if wrong.** A
miscounted CLAUDE.md figure; the Record phase re-measures.

## DG-N — A tilde fence is found and refused; citations are read from wrapped blocks

**Ruling.** The extractor recognises ```` ``` ```` and `~~~` fences at any indent (so one nested in
a list is found; its own indent is removed from its lines) and reports the marker; spec T2
(`aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed`) fails any tilde fence. This supersedes the
spec's "ignores tildes" for T7: an extractor that skipped a `~~~swift` fence would let a block that
looks compiled escape the mirror. Pins, divergence labels and links are read from a paragraph with
its wrapped lines joined (a list item, a table row and a heading each start one), because a
`(pin:` broken across two lines is otherwise never seen — T3 would pass having checked nothing.
**Evidence.** Lane 1's T7 builds each case synthetically, including a pin broken across a line.
**Cost if wrong.** A guide author cannot use a tilde fence; the message names the line.

## DG-O — The behaviour-word list is the verbs and their forms, outside inline code

**Ruling.** `aBehaviourWordHasAPinOnItsLine` flags a sentence (split at `. `, `? `, `! ` within a
paragraph) containing, outside inline code, one of: reset(s), cancel(s), cancelled, retain(s),
retained, focuses, dismiss(es), dismissed (case-insensitive, whole words), unless the same sentence
cites a pin. This extends DG-E's five verbs by the forms a claim takes ("is reset", "was dismissed").
The noun "focus" is not a verb of the list. **Cost if wrong.** A false positive is reworded or
pinned; a false negative is a claim the lane's reading must catch.
