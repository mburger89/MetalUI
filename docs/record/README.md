# The long-form project record

**This directory is the pre-2026-09-09 `CLAUDE.md`, moved here verbatim and
split at its top-level headings.** Concatenating `01-…` through `08-…` in
order reproduces that file byte for byte (checked with `diff` when the split
was made, at commit `6591360` on `feat/animation`).

**2026-09-14: that byte-for-byte property no longer holds, and has not since
2026-09-09.** Five commits edited `01`–`08` after the split (`18a137d`):
`916d607`, `2c1391d`, `2457da8`, `eff5776` and `cca5a18`
(`git log -- docs/record`). The SwiftUI-alignment record then added dated
errata lines to them. To recover the original file, run
`git show 6591360:CLAUDE.md` (4,172 lines); concatenating these files will not
reproduce it. `09-…` was never part of that file.

It was moved because the file had grown to 4,172 lines / 307 KB — roughly
75k tokens loaded into every session — and most of it is *record* (task-by-task
test-count climbs, quoted human reports, the history of how each sentence was
corrected) rather than *rules*. The rules are now in the root `CLAUDE.md`,
which points here for the reasoning.

**Every citation into the old file still resolves.** Test names, ruling ids,
divergence labels, greps and the wording of each paragraph are unchanged; only
the location moved. When a sentence here expires, correct it here and, if it
changes a rule, in the root `CLAUDE.md` too — the practices doc's
"correct where it was COPIED TO" mechanism applies across the two files.

| file | what it holds |
|---|---|
| `01-start-here.md` | the decisions-doc index and the per-subsystem essays (identity, `List`, `Deferred`, `Component`, `@State`, `@Observable`, hitboxes, focus, `Text`) |
| `02-practices.md` | the taxonomy's history: shapes 12–16 and record-mechanisms 1–7, with the incidents that produced each |
| `03-verified-on-real-hardware.md` | every milestone's human-verification entry: what was looked at, what was said, what a positive report closes, and the standing scripts |
| `04-divergences.md` | the divergences in full (eleven when split; `CLAUDE.md` lists twelve since divergence 19), plus the retired labels and why each was retired |
| `05-declared-but-inert.md` | the inert-API table with every row's full mechanism and grep |
| `06-build.md` | test/golden/guard counts milestone by milestone, the summary-line correction, the module-boundary staleness family |
| `07-layout-cost.md` | the per-node layout cost tables, the 100k cold frame, identity path construction |
| `08-when-ci-lands.md` | the guarantees that lapse silently (three when split, five items now; item 5, the freeze loop's allocation pin, appended 2026-09-14), and the guard count's moves: seven in the file, the eighth (35 → 39) dated in an erratum and in `09` — the first move whose guards mostly came after their hazard |
| `09-swiftui-alignment.md` | **not part of the split file.** The record of `a15ec83..7cfcddc` (2026-09-11 … 09-14): the proposal/measure/place kernel beside the CSS engine, the typed proposal modifiers and wrappers, stacks/priority/spacer, alignment, aspect ratio, the text bridge, `ProposalScrollView`, and the legacy `.padding` → `Box<Self>` change. It also covers each theme's pins, the SwiftUI probes (recorded as prose only, with no source in the repo), hazards, stale documents, what the plan leaves open, and the counts 993 / 97 / 39. **Appended 2026-09-14:** "Kernel completion (task 2)" (`3bb1ca1..553b980` on `feat/kernel-completion`): `ProposalLayout`, the boundary traps and invalidation contract, validation, depth guard and work counters, the two committed probes, the verifiers' mutation tables and the green mutations they found, counts 1084 / 97 / 45; dated corrections inline in the sections above |

| `10-modifier-composition.md` | plan task 3: `ModifiedElement`, the overlay-side id, the typed `ProposalNodeID`; lanes, red runs, verifier mutation tables. Lane 1's `M2`/`M3`/`M8`/`M11` and `R4` rows mutated the deleted `FrameModifier` and are historical |
| `11-environment.md` | plan task 9: scoped environment, the disabled gate, `KeyBinding`; four lanes, two verifier rounds, and the merge obligations |
| `12-accessibility-bridge.md` | plan task 12's bridge half: the `NSAccessibility` bridge, defaults and modifiers, `List` as a table; three lanes and their verifier rounds |
| `13-integration-tasks-3-9-12.md` | the integration of tasks 3, 9 and 12: merge resolutions, the red merge and the per-layer `AB-O` fix, the cross-track tests and their mutations, counts 1226 / 97 / 61, and the offscreen pixel stand-in for the untaken demo capture |
| `14-frame-and-sizing.md` | plan task 4 on `feat/frame-sizing`: the kernel's greedy flexible frame, the legacy frame's SwiftUI surface and its one lowering (`FrameSpec.style()`), the sizing inventory (`width`/`height` refused with measurements; `percent:` is a fraction); four lanes, the lost lane 1–2 verdicts reconstructed, lane 3–4 verifier tables, the pixel stand-in and `FR-U`/`FR-V`, counts 1247 / 97 / 63 |
| `15-outer-modifiers.md` | plan task 5 on `feat/outer-modifiers`: the wraps / self / paint-only / prepaint-only / distributes matrix and its table-driven test, `Component` padding wrapping per member, the legacy `border`/`focusBorder`/`opacity`/`clipped`/`allowsHitTesting`/`contentShape` modifiers with their two helpers and per-site guards, `borderWidth` deleted, divergence 15 fixed, five SwiftUI probes, four lanes' red runs and mutation tables, the verifier verdicts, the offscreen demo comparison, counts 1274 / 97 / 64 |
| `16-integration-tasks-4-5.md` | the integration of tasks 4 and 5: the `borderWidth` merge conflict, the interrupted session's un-reverted mutation, eight cross-track tests (frame layer × decorations, hit testing, accessibility, the disabled gate, the component side door, `contentShape` across a wrapper, the frame/background orders) and their mutations, probe arms S0–S3, divergence numbering 35–50, counts 1303 / 97 / 66, and the offscreen pixel stand-in with an instrument that sees the preview |
| `17-containers.md` | plan task 6 on `feat/containers`: SwiftUI's stack distribution, spacer, per-edge default spacing, typed alignments, `ZStack` and root placement, overlay/background content, the duplicate-parent trap and scroll axes on the proposal path; the one-node legacy frame and `fraction:`; the legacy audit and its pins; five lanes, their red runs, verifier verdicts (all five `ok`, lane 3 at the closeout) and mutation tables; the offscreen pixel stand-in; counts 1355 / 97 / 70; the Docs phase's re-take and probe revision 9; the branch checker; the closeout (the `hidden()` regression fixed, mutation F pinned by probe revision 10, 1357 / 97 / 70) at the end |
| `18-engine-replacement-stage-1.md` | plan task 7 stage 1 on `feat/engine-replacement`: the inventory of `FlexEngine` consumers, the fourteen-stage plan, the layout authority and per-site checks, the bounds log and differential harness, leaf/container/`Stack`/layer lowering, the demo content library, pipeline parity, depth and work pins; five lanes, red runs, verifier verdicts (all `ok`, lane 5 with four open minors) and mutation tables; the offscreen pixel stand-in and the chrome pair; counts 1409 / 97 / 71, re-taken after `swift package clean` at the Docs phase |
| `19-engine-replacement-stage-2.md` | plan task 7 stage 2 on `feat/engine-stage-2`: flex-item semantics lowered by the parent — item records and the unconsumed report, the cross and main axes, the box model, distribution and reverse, animated fields; the two proposal-path answers that reach production; five lanes, red runs, verifier verdicts (all `ok`, fourteen minors) and mutation tables; the offscreen pixels, the chrome pair and the first real-window captures; counts 1460 / 97 / 71 |
| `20-grids.md` | plan task 7 stage G on `feat/grids`: SwiftUI's `Grid`/`GridRow` on the proposal path as a kernel `NativeNode` case — the plan and the nil solve, the finite solve's group/share/commit arithmetic, cell attributes and the modifier-chain walk, the elements and identity; four lanes, each red first, all verified (lane 2's two label-and-prose findings applied in the docs round); ten runnable probes and three recorded corpora, sixteen green mutations found (fourteen pinned, two equivalent), the offscreen and real-window comparisons reading the preview delta as exactly the grid's four cells; counts 1493 / 97 / 75 |
| `21-integration-stage-2-grids.md` | the integration of task 7's stages 2 and G on `integrate/stage-2-grids`: two conflict-free merges (both tracks appended to `LayoutTree.swift`), why `feat/grids`' stale `allOk: false` was merged, four cross-track tests at the one seam the two share — a grid cell whose content the lowering produced, a grid inside a lowered legacy container, one text measurement through both spellings, an item field on a cell reported unconsumed — and the five mutations proving them, including XM4, which found that the **lowered** half of lane 3's text clamp was pinned by neither track; the twelve-image comparison (nine at 0, the three preview images attributed cell by cell to the grids track's preview grid) and the locked-screen gate; counts 1548 / 97 / 75 |

New milestones should append their record **here** (a new file or a new
section in the matching one) and put only the rule in `CLAUDE.md`.
