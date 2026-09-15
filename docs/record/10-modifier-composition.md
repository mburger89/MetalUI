## Modifier composition (plan task 3) — `feat/modifier-composition`, from 2026-09-15

The record for plan task 3. Spec
`docs/superpowers/specs/2026-09-15-modifier-composition-design.md`; rulings
`MC-A`…`MC-N` in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md` (next unused
`MC-O`). The track runs in its own worktree,
`/Users/maxburger/Developer/MetalUI-modifier-composition`, beside two parallel
tracks, and is merged by an integration step that owns `CLAUDE.md`, the plan,
`docs/record/README.md` and the SA decisions doc. **Nothing in this file has
been copied into those yet.**

### Design session, 2026-09-14/15, at `f64e58a`

No source change was committed. What was run, and where its output lives:

| run | result | where recorded |
|---|---|---|
| SwiftUI probe `docs/probes/swiftui-modifier-identity.swift`, `/usr/bin/swift` and compiled `swiftc` | byte-identical stdout, exit 0. Arms: T (types nest), A/B controls, C/D2 value change keeps state, D1/D3 length change resets, E/F/G overlay/background views own distinct state, H control | the probe's header; `MC-A`, `MC-C`, `MC-E` |
| scratch test `scratchMeasureOverlayIdentity` (uncommitted, `--filter`, deleted) | primary and overlay ids **equal**; three clicks on the primary → primary 3, **overlay 3**; hover on the primary → **2** hover fills, 60 and 10pt | `MC-E` |
| the same, with the overlay's cursor threaded from the primary's | ids unequal; primary 3, overlay 0; 1 hover fill (60pt) | `MC-E` |
| whole suite with only that fix, `swift test --build-system native --no-parallel` | `Test run with 1085 tests in 1 suite passed` (1084 + the scratch test); no `error:`, no `warning:` | `MC-E` |
| scratch test `scratchMeasureOrphanLegacyNode` (deleted) | a marker conformer registering an unattached legacy node beside a native leaf renders with no trap: prepaint bounds 10×10, 1 rect | `MC-G` hole 2 |
| typecheck skeleton `docs/probes/modifier-composition-skeletons/FlatChainOverloads.swift` | chains infer `ModifiedElement<Text>`, `ModifiedElement<Two>`, `Row<ModifiedElement<Text>>`; a contextual nested annotation also typechecks. **Superseded at design review**: this overload shape's type-checking time is exponential | the file's header; `MC-A`, `MC-B` |
| typecheck skeleton `TypedNodeKit.swift` + eight clients, plain import, Swift 6 | five lies rejected with named diagnostics; `liar4` and an overriding `requestLayout` compile; `ProposalElement` must restate `associatedtype LayoutState` | the file's header; `MC-G` |

**Restores.** `NativeOverlayModifier.swift` was restored from a `cp` backup
after the fix trial. `git status --short` then showed only the untracked probe
files, and the scratch test file was deleted before commit.

**Toolchains.** macOS 26.6.2 (25G83); `swiftc` Apple Swift 6.3.3
(swift-6.3.3-RELEASE); `/usr/bin/swift` Apple Swift 6.4
(swiftlang-6.4.0.33.1).

### Design review, 2026-09-15, at `f64e58a` (design commit `1c6f686`)

Twelve critic findings, all applied (`MC-N` has each disposition). No source
change was committed. Every scratch test was created in `Tests/MetalUITests/`,
run with `swift test --build-system native --skip-build --filter`, and deleted.
`git status --short` was empty after each deletion.

| run | result | where recorded |
|---|---|---|
| `chain-typecheck-timing.py`: three wrapper designs × 8/12/16/24 modifiers × `Pixels(i)`/integer literals, plus a demo-shaped builder, `xcrun swiftc` 6.4 `-debug-time-function-bodies` | today's nested and the single-overload design both stay at 0.5–2 ms up to 24 modifiers (6 ms for the builder). The first `MC-A` design reads 4.8 ms → 184 ms → **44.9 s** at 8/12/16 `Pixels`, and at 24 integer literals prints "the compiler is unable to type-check this expression in reasonable time" after 6.6 s. The swift.org 6.3.3 cross-check agrees | the script's header; `MC-A` |
| `LayerBaseKit.swift` + five clients, plain import | a chain infers `ModifiedElement<Leaf>` (3 layers); a generic `.padding` over a chain appends (2 layers); the proposal `frame` still wins on a proposal type; the nested spelling is rejected in both forms; the initializer is inaccessible; **the `_wrap` forwarding liar compiles (a hole)** | the file's header; `MC-A`, `MC-B` |
| `CombinedKit.swift`: `TypedNodeKit` + `LayerBase` | the kit builds; all eight typed clients print their recorded diagnostics unchanged; a layered client typechecks; no extra associated-type restatement is needed | the file's header; `MC-A`, `MC-G` |
| `TypedNodeKit.swift` re-run under `xcrun swiftc` 6.4 and PATH `swiftc` 6.3.3 | identical eight results under each (the first recording's toolchain attribution is not established) | the file's header |
| `LayerAllocationModel.swift`, `-Onone`/`-O`, both toolchains, and a `consuming` variant | per chain, swift.org `-Onone`: nested 2/3/4 and flat 2/6/9 for 1/2/3 layers; `-O`: nested 0/0/0 and flat 1/3/4. Construction alone costs k−1 buffers. `consuming` gives identical numbers. Calibration read 16 of 16 (32 under swiftlang `-Onone`) | the file's header; `MC-K` |
| SwiftUI probe `swiftui-modifier-order.swift`, `/usr/bin/swift` and compiled `swiftc` | byte-identical stdout, exit 0, empty stderr. K0 20×20 (0,0); K1 36×36 (8,8); K2 52×52 (16,16); O1 60×60 (20,20); O2 76×76 (28,28); O3 56×56 (18,18); O4 64×64 (22,22) | the probe's header; `MC-L` |
| scratch `zzScratchLegacyModifierOrder` (today's `Box`/`FrameModifier`) | all seven arms equal SwiftUI's numbers | the probe's header; spec lane 1 test 10 |
| scratch `zzScratchDuplicateInOneContainer` | `requestNativeLinearStack(children: [leaf, leaf])`: no trap; stack (60, 0, 20×10); leaf (70, 0, 10×10); measure calls 1; `nodeCount` 4 | `MC-G` hole 4 |
| scratch `zzScratchOneChildTwoContainers` | one leaf in a 30×30 top-leading frame and a 50×50 bottom-trailing frame: no trap; stack (30, 0, 80×50); leaf (100, 40, 10×10); measure calls 2; `nodeCount` 6 | `MC-G` hole 4 |
| scratch `zzScratchOrphanLegacySubtree` | a discarded `Box { StatefulLegacyLeaf() }` laid out through `requestGroupLayout`: no trap; 0 rects; `nodeCount` 5; the orphan `Box`'s `$anim` slot live. With the leaf only declaring `@State` (then only reading it), its `$state0` entry did not exist (`peek` nil). With the leaf writing it 7 → 8 in `requestLayout`: `peek` 8, live | `MC-G` hole 6 |

**Scratch-test fixes along the way**, recorded so the shapes are reproducible:
`pass.fill` takes an `Hsla`, so the orphan leaf's fill resolved its token as
`pass.theme[.accent]`. Two earlier spellings failed to build and ran nothing:
`.accent`, and `pass.theme.resolve(.accent)`.

**Toolchains, corrected.** `xcrun swiftc` and `/usr/bin/swift` report Apple
Swift 6.4 (swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) reports Apple Swift
6.3.3. The design session's two skeleton headers attributed 6.3.3 to
`xcrun swiftc`, which is not what `xcrun` reports today. `TypedNodeKit.swift`'s
header now says so, and `FlatChainOverloads.swift`'s carries the superseded
note.

### Lanes

*Each lane appends here: its commits, red runs (quoted lines), mutation runs
with the tests each reddened, the suite/guard/golden counts it re-took, and, for
lanes 2 and 3, the demo captures (`MC-J`): image dimensions, differing-pixel
count and coordinates, and the logged pointer position.*

### For the integration step

Collected here so the merge does not have to re-derive them:

- **`FrameModifier` is deleted by lane 2.** `CLAUDE.md`'s Animation section
  counts registering sites and `pass.fill` sites; record §09's "It is live in
  three places the per-site guards were written to watch" and "Owed before
  this work is cited as done: `FrameModifier` arms" both change.
- **Record §09's hazard 3 (the overlay id collision) is closed by lane 1**
  (`MC-E`), and plan task 3's open-proof bullet "`OverlayModifier` gives its
  primary element and its overlay element the same id, by reading" is
  measured and fixed.
- **`SA-R`'s amended criterion is met by lane 3** (`MC-G`), with **six**
  named holes (the design review added holes 4, 5 and 6). The SA decisions doc
  is not edited by this track.
- **The guard count moves 45 → 46 (lane 2) → 52 (lane 3) by design.** Re-count
  per file.
- **`ElementGroup` gains two defaulted requirements** in lane 2
  (`associatedtype LayerBase = Self`, `_wrap`), and `Element`'s default entry
  calls lane 3's `GroupMember.swift` helper.
- **Collisions with the environment track** (spec merge notes, in full):
  1. **`EnvironmentScope: ProposalElementGroup` stops compiling at merge.** Its
     typed entry must wrap layout in `withEnvironment`, or layout-time reads on
     the proposal path silently read the default. The environment track's E11
     reads only in paint.
     - **Owed test:** `aProposalContainerReadsTheEnvironmentDuringLayout`.
     - **Its arms:** `HStack { recorder.environment(\.probe, 7) }` and
       `HStack { recorder }.environment(\.probe, 7)` each read 7, and a control
       reads 0.
     - **Its mutation:** the typed entry without `withEnvironment` reddens the
       first arm.
  2. **`StateBinder.bind(…environment:…)`.** Lane 3 adds no call sites: the
     helper replaces `ElementGroup.swift:112`.
     - **At merge:** a textual conflict there, plus a compile error in the
       helper until it passes `environment:`.
     - **`Component.swift:130`** remains the environment track's own edit.
- **`FrameModifier` in other tracks' lists:**
  - the environment track's D2 "frame" arm;
  - the AX-bridge spec's in-scope emit site and its "untouched" line;
  - the shared arm lists in `InputDispatchTests.swift` and
    `AXEmitSiteTests.swift`.

  **Change each arm to a two-layer `ModifiedElement`; never delete it**
  (`MC-I`).
- **A candidate divergence** (`MC-C`, lane 2 test 5): a layer added to a chain
  at run time is adopted by the new outermost layer, which takes over its
  `$anim` baseline and its hitbox id. No SwiftUI analogue.
- **A new hole** (`MC-A`): an `ElementGroup` conformer that declares
  `LayerBase` and forwards `_wrap` compiles, and its `.padding` drops the
  receiver.
- **`MC-K`'s named cost, for task 4:** about +3 allocations per 2-layer chain
  and +5 per 3-layer chain per frame build, over nested boxes, in the model's
  debug build. Lane 2 re-measures this in the real build.
