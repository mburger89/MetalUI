# Replacement closeout — design (plan task 15)

Plan task 15 of [`../plans/2026-09-12-swiftui-alignment.md`](../plans/2026-09-12-swiftui-alignment.md):

> Re-run the full inventory; require that no public behaviour is
> unclassified, each supported overlap has a probe and discriminating
> MetalUI test, and each remaining difference is documented. Update
> migration guidance and public API documentation, run the full suite and
> relevant human visual checks, and ensure the retired CSS engine has no
> production caller, and remove or reclassify all browser goldens as
> migration-only historical evidence.

**Status: LANDED 2026-10-01 — every agent-doable clause closed; plan task 15's box stays unticked pending the human checklist (record §66 §7).**

Rulings `CX-A`…`CX-S` in
[`../2026-09-30-closeout-decisions.md`](../2026-09-30-closeout-decisions.md)
(next unused `CX-T`; `CX-P` is the critic round's corrections, `CX-Q` lane 1's
fix round, `CX-R` lane 2's divergence re-read: 2, 35, 39, 53, 55 retire, 66 live; `CX-S` lane 2's fix round). Record: [`../../record/66-closeout.md`](../../record/66-closeout.md).
Branch `feat/closeout` from `1b093b8`.

## 1. Baseline (measured at `1b093b8`)

| quantity | value | how |
|---|---|---|
| tests | **1961 in 3 suites** | `swift test --build-system native --no-parallel` (task text; re-taken by lane 1 before its first change) |
| goldens | 0 | `find Tests/MetalUILayoutTests -name "*.json" \| wc -l` |
| typecheck guards | 119 | CLAUDE.md "Guards" |
| live divergences | 72 (next label 100) | record §04 |
| public declarations | **1871** in 15 targets | `docs/probes/closeout-public-api.sh` → `closeout-public-api.tsv` (re-run identical) |
| public declarations with no doc comment | 888; **592** excluding protocol-requirement witnesses | `CX-K`'s rule |
| GZ table / divergence corpus | identical to `GR-B`'s baseline (sha `5d20…61ba`) | `CX-H` |
| real-window default/preview | 0 differing `6c961e3` → `1b093b8`; control 958986 | `capture.sh`, screen unlocked 23:41 PDT (`CX-M`) |
| retired engine | absent; closing check green | `CX-N` |

## 2. What this task changes

### 2.1 Public API (all in `Sources/MetalUI/Box.swift`)

| change | ruling | migration |
|---|---|---|
| `Box.init(style:decoration:content:)`, `init(style:decoration:@ElementBuilder content:)`, `init(style:decoration:)` → **`package`**, `style` without a default; new **public** `init(decoration:content:)`, `init(decoration:@ElementBuilder content:)`, `init(decoration:)` | `CX-D` | `Box(style: Style(), decoration: d)` → `Box(decoration: d)` |
| `flexBasis(fraction:)` gains `@available(*, deprecated, message:)` | `CX-C` item 2 | declare a length (`flexBasis(_:)` with px) or a `.frame` |

Nothing else public is added, removed or re-spelled. Doc comments are added
(`CX-K`) without behaviour.

### 2.2 Behaviour

| change | ruling | observable |
|---|---|---|
| `StateTable.peek` returns `nil` for an **absent** entry whatever `S` is | `CX-F` | `@State var x: Int? = 2` reads 2 before its first write (was `nil`); a written `nil` still reads `nil` |

No id path, hit-testing, accessibility, animation, focus, scrim, `List`
windowing/TB-AH retention, `Deferred` or text-input behaviour moves.
`theSevenRetentionSlotsAreMutuallyDistinct` stays green unedited.

### 2.3 Infrastructure

`.github/workflows/swift.yml`'s macOS job builds and tests under
`--build-system native` with `METALUI_REQUIRE_GUARDS=1` (`CX-J`).

### 2.4 Documents

`docs/migration.md`, `docs/api-overview.md`, `docs/divergences.md`
(`CX-L`, `CX-G`), `docs/verification/human-checks.md` (`CX-M`), the
inventory map/check scripts (`CX-A`), the undocumented-declaration script
(`CX-K`), the closeout probe, record §66.

## 3. The probe

`docs/probes/swiftui-closeout.swift` (lane 1; compiled with `xcrun swiftc`,
as `swiftui-transactions-animation.swift` is; header carries the run command,
date, machine, lock state and the verbatim output of two identical runs):

| arm | what | expected (to be recorded, not assumed) |
|---|---|---|
| O0 | positive control: `@State var n: Int = 2` read in `body` before any write | **2 — recorded** (critic round, two runs identical, `CX-F`) |
| O1n | control: `@State var x: Int? = nil` | **nil — recorded** |
| O1 | `@State var x: Int? = 2` read in `body` before any write | **2 — recorded** (the claim `CX-F` rests on) |
| O2 | O1 after a write of `nil` (closure from `onAppear`, re-rendered) | **nil — recorded** (separating arm: a fix that treats a stored `nil` as absent would read 2) |
| SW0 | positive control: an `if`/`else` branch change with `.transition(.move(edge: .leading))` under `withAnimation(A)` records an offset | an offset line (task 13's recorder, copied) |
| SW1 | the same with a three-case `switch` | an offset line, same delta as SW0 |
| SW1n | SW1 with no transaction | nothing animated |

Group O is committed with its output (critic round); lane 1 appends group SW
and records its own two runs. `swiftui-border-clip-paint.swift` was re-run
compiled at the critic round: K0, C3 and D1 byte-identical to its header
(`CX-P` item 10).

## 4. Lanes (`CX-O`) — run in order; no file in two lanes

### Lane 1 — code (Opus)

**Files**: `Sources/MetalUI/StateTable.swift`, `Sources/MetalUI/State.swift`,
`Sources/MetalUI/Box.swift`, `Sources/MetalUI/AnimatedStyle.swift` (the
"re-owned to plan task 15" doc sentence only), `Tests/MetalUITests/CloseoutTests.swift`
(new), `Tests/MetalUITests/CloseoutCompileGuards.swift` (new),
`Tests/MetalUITests/ContainerCompileGuards.swift`,
`Tests/MetalUITests/ModifierTests.swift`, `Tests/MetalUITests/LoweringItemTests.swift`,
`Tests/MetalUITests/CSSSizing.swift`,
`Tests/MetalUITests/DecorationCompileGuards.swift` (doc comment only,
`CX-P` item 5), `Tests/MetalUILayoutTests/NativeGridTests.swift` (the
"Owner: plan task 15" doc comment only, `CX-P` item 6),
`docs/verification/human-checks.md` (new, `CX-P` item 9), any test file a `Box(style:)`
split forces a re-spelling in (expected none — `package` reaches tests),
`.github/workflows/swift.yml`, `docs/probes/swiftui-closeout.swift` (new),
record §66 §4. Doc comments for every census row in the `Sources/` files it
edits (`CX-K`).

**Tests** (every one: red before or a named mutation reddens it; mutations on
a committed tree, restored from a copy, full unfiltered suite, `git status
--short` empty after each, every reddened test named):

| # | name (file) | red before? | mutation that must redden it (and only what is named) |
|---|---|---|---|
| 1.1 | `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite` (`CloseoutTests`) — a `Box` with `@State var x: Int? = 2` rendered through a real `Window` reads 2 in `requestLayout` and in a `$x` `Binding`'s `wrappedValue` | **red** at `1b093b8` (reads `nil`) | M1a: restore `storage[id]?.value as? S` → 1.1 alone |
| 1.2 | `aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue` (`CloseoutTests`) — the same element, a write of `nil` from a click, the next frame reads `nil` | green before and after (separating arm) | M1b: `peek` treats a stored `nil` as absent (returns `nil` when `entry.value` is `Optional.none`) → 1.2 alone |
| 1.3 | `aBackgroundWrittenAfterCornerRadiusIsSquare` (`CloseoutTests`) — proposal `Color`/`Rectangle` 40×40 `.cornerRadius(12).background(red)`: the background rect's mask radii are 0 and its corner pixel region is filled (probe C3) | pin (green on arrival) | M1c: the proposal background layer paints inside the inner clip layer's mask (pass the clip's radius to the fill) → 1.3 (and name anything else) |
| 1.4 | `aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill` (`CloseoutTests`) — `.cornerRadius(12).border(blue, 4)`: the border band is square, the fill rounded (probe D1) | pin | M1d: the border layer inherits the clip's corner radius → 1.4 |
| 1.3L | `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` (`CloseoutTests`) — legacy `Box` 40×40 `.cornerRadius(12).background(red)`: the answer the legacy path gives (expected rounded — one order-insensitive `Decoration`; wrong on purpose against C3, divergence 47 amended) | pin | M1cL: square the legacy background's mask → 1.3L (`CX-P` item 2) |
| 1.4L | `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` (`CloseoutTests`) — legacy `.cornerRadius(12).border(blue, 4)` (expected: the band follows the arc, divergence 49's answer; wrong on purpose against D1) | pin | M1dL: square the legacy border band → 1.4L |
| 1.5 | `aSwitchBranchTransitionsAsAnIfElseBranchDoes` (`CloseoutTests`) — a three-case `switch` whose case content carries `.transition(.move(edge: .leading))`; a case change under `withAnimation` draws the removed case's ghost offset mid-flight exactly as the `if`/`else` arm does (both arms in one body, required to agree, and both required to differ from a no-transaction control) | pin | M1e: the transition claim ignores the second `buildEither` path (the lane finds the line; record which copy) → 1.5 |
| 1.6 | `measureSettledStoreEntryAllocations` (`CloseoutTests`, gated `METALUI_STORE_ALLOC_MEASURE=1`) — allocations of three settled proposal-preview frames, store entries vs. a tree with none, printed | n/a (a figure) | n/a; output recorded in record §66 |
| G1 | `aPlainImportCannotPassBoxAStyle` (`CloseoutCompileGuards`, whole-file `typecheckFile`, plain `import MetalUI`) — `Box(style: Style())` fails; control `Box()` and `Box(decoration: Decoration()) { }` compile | **red** at `1b093b8` (the call compiles) | MG1: re-publish one `style:` init → G1 red |
| G2 | `theTypecheckGuardsRanWhereTheyAreRequired` (`CloseoutCompileGuards`) — with `METALUI_REQUIRE_GUARDS=1`, `#expect(canTypecheck)` | **red** under the default build system with the env var; green under native | MG2: the test ignores the env var → green under default-with-env (instrument proof) |
| T1 | `ContainerCompileGuards`' G4 flexBasis arm — inverted: `flexBasis(fraction:)` **is** deprecated (`CX-C`); renamed to say so | inverted answer by ruling | MT1: delete the new `@available` → T1 red |

**If 1.3 or 1.4 is red on arrival, lane 1 stops** — a proposal answer
differing from SwiftUI's C3/D1 is owed a ruling (fix or new divergence),
not a re-spelt test (`CX-P` item 2). Test 1.6's `malloc_logger` installer
is a second one beside `ModifiedElementTests`'; gated and `--no-parallel`
only (`CX-P` item 8). `flexBasis(percent:)` loses its `renamed:` to a
now-deprecated spelling and takes the same `message:` (`CX-P` item 7). The
public `Box(decoration:…)` initialisers **forward** to the package
`init(style: Style(), …)` (`CX-P` item 5). Every sentence in lane 1's files
naming plan task 15 as a future owner is re-spelled (`CX-P` item 6).

**The human checklist** (`CX-M` item 1, moved here by `CX-P` item 9):
`docs/verification/human-checks.md`, every item citing its record §03 (or
task-record) source, the VoiceOver script linked, not copied; build it by
grep of record §03 and record its command in record §66.

**Counts after lane 1**: tests 1961 + 1.1–1.6 + 1.3L + 1.4L + G1 + G2 =
**1971**; guards 119 + G1 + G2 = **121** (CLAUDE.md's `grep -c
canTypecheck` rule counts G2, which calls `canTypecheck`; `CX-P` item 4); goldens 0; 0 `warning:` on
both build systems (the T1 callers move to `cssFlexBasis(fraction:)` or the
`DeprecatedSpelling` witness). `swift package clean` after the `Box`
initialiser change (a public type's initialisers cross a module boundary).

**Must hold**: 0 px against `1b093b8` in all fourteen offscreen images
(`docs/probes/demo-pixels/compare.sh`); `Expected.swift` unedited and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green;
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`theSevenRetentionSlotsAreMutuallyDistinct` green; `MetalUILayout` imports
only `MetalUICore`; `Backends/SDL` builds and its tests pass
(`PKG_CONFIG_PATH=$PWD/.accesskit`); a `swift:6.4-noble` container builds
and runs the portable suites if Docker is available (expected **199 + 10 +
22**, plus 1.1/1.2 only if `CloseoutTests` lands in a portable target — it
does not: `MetalUITests`).

### Lane 2 — the inventory and the public documents (Opus for the inventory, may be one agent)

**Files**: `docs/probes/closeout-inventory-map.tsv` (new),
`docs/probes/closeout-inventory-check.sh` (new), record §66 §1–§3 and §5,
`docs/divergences.md` (new), `docs/migration.md` (new),
`docs/api-overview.md` (new). No `Sources/` or `Tests/` file.

**Work**:
1. Complete record §66 §1's family table (`CX-A`): one row per family, class,
   behaviour, evidence; split families whose members differ (item 4). Write
   the map and the check script; the check prints nothing at the lane's tip.
2. Re-read all 72 live divergences against `CX-G`'s criterion (85 already
   retired by lane 1); per-row verdict table in record §66; publish
   `docs/divergences.md`.
3. Write the tasks 4 and 5 settlement (`CX-B`) as record §66 §5, every
   citation resolved by grep.
4. The "task 15" sweep table (record §66 §3) and the old "Carried…" sections
   (`CX-I` item 6).
5. `docs/migration.md` and `docs/api-overview.md` (`CX-L`), the grep
   commands that collected the migration notes recorded in record §66.

**Check**: `closeout-inventory-check.sh` prints nothing; every test name in
the four documents resolves in `Tests/`; every ruling id resolves in
`docs/superpowers/`.

### Lane 3 — doc comments (Opus or Sonnet)

**Files**: every `Sources/**/*.swift` file **except** lane 1's four, doc
comments only (`docs/probes/closeout-undocumented.sh` is committed at design, reading 592),
including re-spelling `ModifiedContent.swift`'s "its fate is plan task 15's"
sentence to `CX-C` item 3 (`CX-P` item 6).

**Work**: (1) `CX-K`: bring `closeout-undocumented.sh` to 0;
`git diff <lane-2 tip> -- Sources | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[-+]\s*///'`
prints nothing (comment-only). (The checklist moved to lane 1, `CX-P` item 9.)

**Check**: full suite count unmoved from lane 1's (1971); 0 `warning:`; 0 px
(nothing can move — re-taken anyway at the Record phase).

## 5. Record phase (Sonnet; after lane 3)

Re-take counts after `swift package clean` (expected **1971 / 0 / 121**),
the fourteen-image comparison, `Backends/SDL`, the container; re-run the lock
probe and, if unlocked, `capture.sh <scratch> 1b093b8 <HEAD>`; the closing
check and the golden grep (`CX-N`). Then — the only phase that may — edit
`CLAUDE.md` (copy to `AGENTS.md`, `cmp`), `README.md` (links to the four
documents; the WebKit section labelled migration-only history), the plan
(tasks 4 and 5 ticked with dated notes per `CX-B`; task 15 left unticked with
a dated note naming `docs/verification/human-checks.md`, per `CX-M` item 3),
`docs/record/README.md` (row 66), record §03 (a dated section: the design-time
capture and the checklist), §04 (85 retired, `CX-G`'s retirements, 52/61/62
kept owner none, 47 amended with the legacy C3/D1 answer, every stale pin
name lane 2 lists corrected — `CX-P` items 2, 3), §05 (`Box(style:)` row deleted; `AXNode.actions` row
re-read), and record §66's close. `goldensUnchanged`: no `@Test` removed; one
retained test's answer inverted by ruling (T1, `CX-C`).

## 6. Risks

- **`Box` initialiser split ambiguity** — a `package` init with a required
  `style:` and a public one without cannot both match one call; the build
  is the check.
- **`peek`'s fix reaching a non-`@State` caller** — every caller is listed in
  `CX-F`; all read non-optional types. Lane 1 confirms by grep at its tip.
- **CI change unverifiable locally** — `CX-J`'s test is checked locally under
  both build systems; the workflow edit is checked on push (the Record phase
  notes it as owed to CI).
- **Doc-comment volume** — 592 declarations; the comment-only diff check
  makes a behaviour slip mechanical to catch.
