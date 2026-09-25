# §54 — Engine replacement, stage 11: modifier unification

Spec `docs/superpowers/specs/2026-09-25-engine-stage-11-design.md`; rulings
`LR-FV`…`LR-FZ` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`;
probes `docs/probes/stage-11-unified-modifier-skeleton/` (new),
`docs/probes/swiftui-border-clip-paint.swift` (group H added),
`docs/probes/swiftui-overlay-primary-shape.swift` and
`docs/probes/swiftui-outer-modifier-order.swift` (re-run). Branch
`feat/engine-stage-11` from `47c0d98`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-11`.

## 1. Design baseline (2026-09-24, `47c0d98`)

**Suite.** `swift build --build-system native --build-tests` → `Build
complete!`, 0 `error:`, one `warning:` (SwiftPM's `--build-system native`
deprecation notice). `swift test --build-system native --no-parallel`,
unfiltered → **`Test run with 1426 tests in 3 suites passed after 79.235
seconds`**; the log carries `FR-J no-argument frame: succeeded=` once (the
guards ran). Goldens 0 (`find Tests -name "*.json" -not -path "*/.build/*"`
reads 0); `grep -rn "computeLayout(" Tests` reads 0.

**Probes**, macOS 27.0 (26A428), `/usr/bin/swift` = Apple Swift 6.4
(swiftlang-6.4.0.33.1), exit 0 and empty stderr each:

| probe | result |
|---|---|
| `swiftui-outer-modifier-order.swift` | every recorded line byte-identical (a `diff` of the header's lines against stdout is empty); controls C0–C2, L1 |
| `swiftui-overlay-primary-shape.swift` | the eight output lines byte-identical; controls A, B, P5, Q |
| `swiftui-border-clip-paint.swift` | G1–G4 byte-identical (and the other twenty-two lines); then **group H** added and the file re-run in script and compiled (`xcrun swiftc`) forms, stdout byte-identical (`cmp`), the twenty-six earlier lines unchanged |

Group H (the new arms; the header carries them):

    H1 clear.border(blue,4).opacity(0.5)  : corner(1,1)=rgb(0.57,0.59,1.00) … topmid(20,1)=rgb(0.57,0.59,1.00) centre(20,20)=white
    H2 clear.opacity(0.5).border(blue,4)  : corner(1,1)=rgb(0.02,0.20,1.00) … topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=white
    H3 clear.opacity(.5).background(red).opacity(.5): every point rgb(1.00,0.58,0.58)

H1 vs H2 separates (faded vs B2's full border colour); H3 reads G3's single
fade, not G2's 0.80. `swiftui-outer-modifier-order.swift` has **no G group**
(its groups are C, L, A, B, D, E, F): the parent row's "outer-modifier-order
probe's G3/G4 arms" are border-clip-paint's (`LR-FY` item 4).

**Value sizes**, a scratch test in `MetalUICrossPlatformTests` (debug, macOS
arm64, deleted afterwards):

| type / value | bytes |
|---|---|
| `Decoration` | 77 |
| `Handlers` | 320 |
| `ModifierLayer` | 662 |
| `LayoutModifier` | 46 |
| `ModifiedElement<Box<EmptyGroup>>` | 1272 |
| `Box<EmptyGroup>` | 600 |
| `ModifiedContent<Rectangle>` | 62 |
| `ModifiedContent<ModifiedContent<Rectangle>>` | 110 |
| `Rectangle` | 10 |
| `OverlayModifier<Rectangle, Rectangle>` | 23 |
| `demoContent()` | **33 912** |
| `nativeLayoutPreviewContent()` | 935 |
| `textInputDemoContent()` | 5 312 |

**Stack budget**: `buildEveryProductionTree(onAThreadOf:)` (the
`DemoStackBudgetTests` harness) in one exit test per size, 400–560 KB in
16 KB steps: `.signal(SIGBUS)` at every size through 512 KB, success at 528 KB
and above — **> 512 and ≤ 528 KB** (stage 10 recorded > 480 and ≤ 484 KB at
`133f634`, before the text editor merged).

## 2. The unified-type skeleton

`docs/probes/stage-11-unified-modifier-skeleton/run.sh` (header carries the
full output, md5 `2fa710b9152c7a33633cd67eb1ff1900`). `Kit.swift` models
`ElementGroup` (with `LayerBase`/`_wrap`), `Element`, `ProposalElementGroup`
(with the proposed `ProposalBase`/`_wrapLayout`), `ProposalElement`,
`StyledElement`, the proposed `ModifiedContent<Content, Modifier>` with
`ModifierLayerKind`, `ModifierLayer`, `LayoutModifier`, a generalized
`OverlayModifier`, `Box`, `Rect` and `HStack`, compiled as its own module in
Swift 6 mode; `main.swift` is the client.

Findings, each read off the output:

1. Legacy chain → `ModifiedContent<Box, ModifierLayer>`; proposal chain →
   `ModifiedContent<Rect, LayoutModifier>`; proposal-then-legacy →
   `ModifiedContent<Rect, ModifierLayer>` with the proposal layer innermost.
2. Ids: proposal chain layers at `[7]`, `[7, 0]`, `[7, 0, 0]`, content at
   `[7, 0, 0, 0]` — nested `ModifiedContent`'s path; proposal-then-legacy
   `[7]`, `[7, 0]`, content `[7, 0, 0]` — `ModifiedElement<ModifiedContent<Rect>>`'s.
3. `.background(Token())` resolves on both chains; `Rect().padding(Pixels(8))
   .opacity(0.5).id(2)` compiles (legacy vocabulary over proposal content), and
   `Rect().padding(1).id(2)` does not (no `StyledElement` member on a proposal
   chain).
4. Rejected as predicted: a legacy chain in `HStack` (new message: "requires
   the types 'ModifierLayer' and 'LayoutModifier' be equivalent"); a legacy base
   through `ModifiedContent(content:modifier:)` ("requires that 'Box' conform to
   'ProposalElementGroup'"); `HStack { Box().overlay { Rect() } }`; a nested
   annotation of a flat proposal chain.
5. `extension ModifiedElement { … }` over the generic typealias compiles (the
   budget guard's negative fixture keeps its spelling).
6. Overlays: legacy `Box().overlay { Box() }` registers the overlay at
   `[7, -1, 0]`; a proposal overlay enters an `HStack`; a proposal modifier
   after an overlay nests once (`ModifiedContent<OverlayModifier<Rect, Rect>,
   LayoutModifier>`), as today.

Two designs were rejected on the way, by reasoning the skeleton's type checker
confirmed rather than by a separate build: a `ModifiedContent` whose second
parameter is a *modifier* (SwiftUI's nesting) with the legacy stack as one
kind cannot give `LayerBase` a per-kind witness (one associated-type witness
per conformance), so a legacy wrapper after an overlay or a proposal modifier
could not both stay flat and keep the other's subtree; a one-parameter flat
type makes `StyledElement` and `ProposalElementGroup` decoration members
collide on proposal content.

## 3. Scratch measurement: `deferred.amended`

A scratch test (`Tests/MetalUITests/ZZScratchStage11.swift`, deleted
afterwards) rendering each tree as the root of a 200×100 `Frame` with
`reportsUnlowerableFields`, at `47c0d98`'s source. `SSolo` is a `Component`
whose one member is `Deferred { Box().background(.accent).onClick {}
.position(.absolute).inset(top: 5, left: 5).cssWidth(10).cssHeight(10) }`.

| tree | fields | hitboxes |
|---|---|---|
| `Box { SSolo() }` | `[]` | (5, 5) 10×10 |
| `Box { SSolo().frame(width: 70) }` (a legacy frame **layer**) | `[]` | (5, 5) 10×10 |
| `Box { SSolo().width(70) }` (a component **amend**) | `["deferred.amended"]` | (5, 5) 10×10 |

The frame layer already hands the placeholder on and drops it with nothing
said; the amend lands on the same rect and only reports. `LR-FY` item 1.

## 4. Scratch measurement: a multi-member absolute frame in a `Deferred`

Same harness. `SPair` is two `Box().cssWidth(10).cssHeight(10)` members with
`onClick`. The tree is `Box { Deferred { SPair().frame(width: 20, height: 20)
.position(.absolute).inset(top: 10, left: 30) } }`.

| source | fields | hitboxes |
|---|---|---|
| `47c0d98` | `["modifierLayer.style"]` | two 0×0 at (0, 0) |
| `&& childCount <= 1` removed from `legacyFrameLayerDiagnostics` (scratch) | `[]` | (35, 15) and (55, 15), 10×10 each |
| in-flow control, `Box { SPair().frame(width: 20, height: 20) }` | `[]` | (85, 45) and (105, 45) |

The members sit centred in their 20×20 per-member frames, 20 apart, as in the
in-flow row (`LR-BH`), the row placed at the insets. Reverted with `git
checkout Sources/MetalUI/LegacyLowering.swift`; `git status --short` then
showed only this design's probe edit. `LR-FY` item 3.

## 5. Design close

Committed: the spec, `LR-FV`…`LR-FZ` (the decisions doc's next unused moves to
`LR-GA` in the same commit), this record, the skeleton probe, the probe
headers. No `Sources/` or `Tests/` file changed.

## 6. Critic round 1 (2026-09-24)

Ruling `LR-GA`; the spec was amended in place, and each amended passage says so.

**Probe re-runs** (script form, `/usr/bin/swift` 6.4, exit 0, empty stderr):
`swiftui-border-clip-paint.swift`'s G3, G4, H1, H2, H3 lines are each found
verbatim in its header (`grep -F`). All eleven stdout lines of
`swiftui-overlay-primary-shape.swift` are also found verbatim in its header,
controls A, B, P5, Q included.

**Findings, each read in the source at `47c0d98`, all applied:**

| # | finding | evidence | disposition |
|---|---|---|---|
| 1 | one fill bit for three slots: `.background(red).opacity(0.5).hoverBackground(blue)` paints the unhovered red opaque | `Box.swift:723/741/758` write three slots; `AnimatedColor.swift:357` paints the winner | six-member `escapesOpacity`; the winning slot decides; N2.4, M2i |
| 2 | an unconditional flag breaks `Decoration` equality for identical paint | `ModifierTests.swift:416`; `Decoration: Hashable` (`Box.swift:211`) | inserted only while `opacity < 1`; N2.4's equality arm; M2j |
| 3 | a two-member legacy primary under `.overlay` traps unruled | `NativeBackgroundModifier.swift:91` | ruled; exit test N1.7; `Group` overlay → task 8 |
| 4 | `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` expects `deferred.amended`, and is not in the T list | `PresentationLoweringTests.swift:440–442` | T row added; N2.3 gains the out-of-`Deferred` control (M2g′) |
| 5 | divergence 54 ("stage 11 / task 10's") and 56's `TB-M` remainder ("stage 11") are missing from §2 | record §04, the 2026-09-22 section | re-owned: 54 → task 10, 56's remainder → task 8 (spec §6.5) |
| 6 | the task-7 tick checked only the §4.1 rows, and row 8 cited a record; the live divergence count is stale | plan task 7's paragraph and `CN-Q`; record §04's stage-9 section reads 56 live | spec §9.1; row 8 now reads the branch; 56 → 55 |
| 7 | lane 1 was two lanes' work, and the stack budget had no threshold | spec §7 as designed | three lanes; bisection after lane 1 and lane 3; above 544 KB blocks |

**Accounting as amended:** 1426 → **1439** tests, guards 82 → 84, goldens 0,
no test retired.
