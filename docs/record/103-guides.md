# 103 — Developer guides whose every code block compiles

Branch `docs/guides` from `ff8a1ea4`, merged with master `848ee029` (§98, §99, §100, §101 and §102
had landed; **no record numbered 103 existed, so §103 stands**). **Not a plan task**: item 10b of the
gpui-gap priority list, the agent-doable half of item 10 (docs); user request 2026-10-02. Spec
`docs/superpowers/specs/2026-10-12-guides-design.md`; rulings `DG-A`…`DG-Q` in the new decisions doc
`docs/superpowers/2026-10-12-guides-decisions.md` (next unused `DG-R`). **No public API, no source
change outside `Tests/`, no probe (the guides make no new SwiftUI claim, `DG-F`), no divergence
(the branch's reserved labels 335–344 are unused).**

**Status: LANDED.** Two lanes, each red first, each verified `ok: true`; this Record phase merged
master, re-took the suite and wrote the links. One deferral is named (§6).

## §0 Baseline

At `ff8a1ea4`: **3513 tests in 3 suites**, 0 goldens, 222 typecheck guards, `docs/` holding
`getting-started.md`, `api-overview.md` (a reference), `migration.md`, `divergences.md`,
`packaging.md`, `testing.md` (the only doc with compiled recipe blocks, by
`TestingRecipeTests.swift`) and no task-led guide for anything else. `typecheckFile` was
considered as the compile mechanism and refused (`DG-C`): it skips silently outside the native
build system, so a block could rot green.

## §1 What landed

- **Six guides** (`DG-A`, `DG-B`) in `docs/guides/`, indexed by `README.md`: `layout.md`,
  `state-and-identity.md`, `input.md` (lane 1); `presentations-and-app-shell.md`,
  `drawing-and-gpu.md`, `cross-platform.md` (lane 2). Each is task-led, links
  `api-overview.md`/`divergences.md`/`testing.md` rather than repeating them, closes with the
  divergences a reader will hit by number, and claims a behaviour only as `(pin: \`testName\`)`.
- **The compile mechanism** (`DG-C`, `DG-D`): every `swift` fence is a file-scope fragment copied
  by hand, byte for byte, into a `// guide: <file> #<n>` … `// end guide` region of an ordinary
  `MetalUITestingTests` source file, so every build system compiles it and macOS, Linux and Windows
  CI build it. No generator (it would compare a file with itself). A macOS-only API is wrapped
  `#if os(macOS)` inside the block (`DG-H`); SDL snippets are `text`/`sh` fences (`DG-L`).
- **Files** (all under `Tests/MetalUITestingTests/`): `GuideDocCheck.swift` (the extractor and
  nine tests), `GuideMirrorsLane1.swift` (guides 1–3 and 17 tests),
  `GuideMirrorsLane2.swift` (guides 4–6, 15 tests and the completeness test).
- **Links** (`DG-I`): `README.md`, `docs/getting-started.md`, `docs/api-overview.md` and
  `docs/guides/README.md`. `docs/testing.md` is not edited (C28 owns it); guide 3 links it.

## §2 Tests

Doc-check (`GuideDocCheck.swift`): `everyGuideBlockIsCompiledVerbatim` (T1),
`aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed` (T2), `everyCitedPinNamesATestThatExists`
(T3), `everyCitedDivergenceHasARow` (T4), `everyRelativeLinkResolves` (T5),
`noGuideNamesAnApiThatIsNotOnMaster` (T6), `aBehaviourWordHasAPinOnItsLine`,
`theExtractorFindsFencesNestedInListsAndIgnoresTildesAndCRLF` (T7) and
`theProseChecksReadPinsLabelsLinksAndBehaviourWords`. Lane 1's runnable claims: layout (`Row` and
`HStack` differ by the default gap; the modifier order of a background; an `.id` written last names
the whole element; a `Grid` column takes its widest cell), state (a typed name writes the binding;
`ForEach` rows keep `@State` across a reorder; a hidden branch starts fresh on return; a new id
starts fresh; a `List` builds its window and selects on click) and input (a click presses a
`Button` without focusing it; a lost release runs `onCancelled` once; a window-drag handle asks the
platform once; a key goes to the key region under the pointer; select-all writes the
`TextSelection` binding). Lane 2's: the shell (a popover opens from its button, an alert's button
runs and closes it, a drawn alert is pressed through the tree, an importer hears the chosen file, a
context-menu item and a command run, a tree titles the window and a toolbar item runs, a dirty
document vetoes a close), drawing (a path shape draws as one image and a solid `Rectangle` as none;
a material is one backdrop and degrades under a shadow) and cross-platform (a missing file decodes
to `nil`; the primary modifier fires the shortcut), plus `theGuideSetIsComplete` (exactly the six
names, each in the README).

**Counts.** Lane 1 measured 3539 (3513 + 26); lane 2 measured 3555 (+ 16); the merged tree is
3624 (§5).

## §3 Rulings that changed the spec

`DG-K` (CRLF normalised, names unique across both lanes' files, not "within a lane"), `DG-M` (the
pin check accepts `func name` and `@Test func name`; the total moves, "suite unchanged" meaning no
existing test or pixel), `DG-N` (a tilde fence is found and **refused**, superseding "ignores
tildes"; a pin broken across a wrapped line is read), `DG-O` (the behaviour-word list is the verbs
and their forms, outside inline code), `DG-P` (see §7), `DG-Q` (**MetalUI has no public `Canvas`** at
this base, so guide 5 has shapes, paths, gradients, shadows, materials and `GPUSurface`/`MetalView`
and says there is no `Canvas`; the spec's mention of it was inaccurate).

## §4 Red runs and mutations

Red first: lane 1's doc-check and guides were committed before their mirrors (the build failed with
84 errors, "cannot find the guides' roots"); lane 2's mirror tests were committed before their
blocks. Mutations were applied once each, committed first, restored from a copy, the unfiltered suite
run, `git status --short` clean after each. **Lane 1 batched M1 and M5–M10 in one run, and MB, ME and
MF in another; safe only because each reddens a different test, and read per test.**

| Mutation | Reddened |
|---|---|
| M1 one character in a `layout.md` block, mirror unchanged | `everyGuideBlockIsCompiledVerbatim` |
| MB one character in the mirror only | `everyGuideBlockIsCompiledVerbatim` |
| MC delete the first `// end guide` of lane 1's mirror | `everyGuideBlockIsCompiledVerbatim` |
| MD an unmirrored swift fence appended to `state-and-identity.md` (alone: a combined run was masked by the parser mutation) | `everyGuideBlockIsCompiledVerbatim` |
| M5 `no-compile` on a swift fence of `input.md` | `aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed` |
| M6 a misspelt pin in `layout.md` | `everyCitedPinNamesATestThatExists` |
| M7 divergence 999 in `layout.md` | `everyCitedDivergenceHasARow` |
| M8 a broken relative link in `layout.md` | `everyRelativeLinkResolves` |
| M9 `resignsFocusOnPress` in guide prose | `noGuideNamesAnApiThatIsNotOnMaster` |
| M10 the pin deleted from the "focuses a `TextField`" sentence | `aBehaviourWordHasAPinOnItsLine` |
| ME `.onCancelled` removed from block and mirror together (the byte check stays green) | `theInputGuideALostReleaseRunsOnCancelledOnce` |
| MF `.id("whole")` moved before `.padding` in block and mirror together | `theLayoutGuideAnIdWrittenLastNamesTheWholeElement` |
| MT7 the parser's fence close (`run >= length` to `run > length`), with MC and MD | `theExtractorFindsFencesNestedInListsAndIgnoresTildesAndCRLF`, and, because nothing parses, `aBehaviourWordHasAPinOnItsLine`, `aSwiftFenceCarriesNoInfoStringAndOtherFencesAreNamed`, `everyCitedDivergenceHasARow`, `everyCitedPinNamesATestThatExists`, `everyGuideBlockIsCompiledVerbatim`, `everyRelativeLinkResolves`, `noGuideNamesAnApiThatIsNotOnMaster` |
| Lane 2: `DrawingDiamond()` replaced by `Rectangle()` in the test's own root (line 362) | `theDrawingGuideAPathShapeDrawsAsOneImage` |

**A finding that became a fix.** Lane 2's first path test passed against a `Rectangle` (it counted
images in the guide's tree, not in a separating arm); it now draws a control root, a solid red
`Rectangle`, and expects 1 image for the path and 0 for the control. Its doc comment names the
mutation at line 362 (the comment's first wording, a replacement in the guide block and its mirror,
reddened nothing, and was corrected). **Limit (`DG-E`).** A pin is checked for existence, not for
what the test asserts; the lanes read each pinned test once.

## §5 Merge, suite and pixels

Master `848ee029` merged cleanly (documents only; no source file of the guides' two sides shares a
path). After `swift package clean`, native build and the unfiltered `--no-parallel` run: **3624 tests in
3 suites** (master's 3582 + 42: nine, 17 and 16), `failed ... with 5 issues`, exactly the five
`AppKitPresentationTests` sheet issues of `CI-AF` on a locked screen and nothing else; 0 `error:`, the
only `warning:` SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=true`; guards 229,
unmoved (the branch adds none). No source under `Sources/` or `Backends/SDL/` changed, so the fourteen
offscreen images are 0 px against `ff8a1ea4` by construction (lane 1 ran `compare.sh`: 0 px) and
`Expected.swift` is unedited. Both analyser scripts print nothing (the branch declares nothing
public). In `swift:6.4-noble` the 26 lane-1 guide tests passed.

## §6 Deferrals, with owners

- **`.resignsFocusOnPress` (§98), `TextMeasurer` (§99), the Material follow-ups (§101) and the IME
  driver (§102) are on master now but still named in `noGuideNamesAnApiThatIsNotOnMaster`'s
  denylist and absent from the guides.** Owner: a follow-up lane adds a task to guides 3, 5 and 3
  with its mirror and removes the name from the denylist in the same commit.
- A seventh guide (testing is `docs/testing.md`); a generator for the mirrors (refused, `DG-D`);
  a `Canvas` task (no `Canvas`, `DG-Q`).

## §7 Findings for the orchestrator (`DG-J`)

**In `swift:6.4-noble` on arm64, `TestWindow.runUntilIdle()` throws `notIdle` after 64 rounds once a
`Button` has been clicked**, whatever the action (empty, `@State`, plain class, `@Observable`), even
after `advanceFrames(30)`; macOS returns idle, and a window with no click is idle on both. The first
Linux run of the guide tests failed on this alone. The cause is not isolated and the lane-1 verifier
did not reproduce it separately; `DG-P` keeps the guides on `setNeedsRedraw()` plus `tick()`, the
recipe `docs/testing.md` gives for a model written off the macOS main loop. Possibly a real bug in
`runUntilIdle` or the frame loop under the offscreen driver; not fixed here.

## §8 Looks owed

`docs/verification/human-checks.md` group **GD** (GD1): a person new to the framework reads each
guide once against the running demo and marks every step that surprised them. Nothing else needs
eyes; no agent can do it.
