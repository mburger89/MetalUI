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

## 7. Lane 1 — the unified `ModifiedContent<Content, Modifier>` (2026-09-25)

Commits `273bbd8` (red first: N1.1, N1.2, G1.1, G1.2) and `82c5ef9` (the
type). Ruling `LR-GB`, which corrects two spec errors this lane found (N1.2's
spelling, M1a's spelling).

**What was built** (spec §3, `LR-FV`, as ruled). There is a new
`Sources/MetalUI/ModifiedContent.swift`. It holds the flat struct (`content`,
`outermost`, `inner`, `prefix`) and `ModifierLayerKind` with its five
underscored requirements. It holds the one layer recursion, which is
`ModifiedElement`'s moved: `innermostID`, the shared `wrapLayers`,
`prepaintLayer`/`prepaintLayerBody` and `paintLayer`, walking *prefix, inner,
outermost*. The `MC-B` per-layer mirrors now run for proposal layers too. The
file also holds `ModifierLayer`'s arm (lowered → `animated` → `lowerLegacyLayer`;
`registerAndScope`; `paintDecoration`) and `LayoutModifier`'s arm
(`nativeWrapperNode`; the hit-testing/clip scope; the opacity/fill/clip/border
paint, all moved verbatim). It declares the conditional `StyledElement` and
`ProposalElementGroup`/`ProposalElement` conformances and `typealias
ModifiedElement`. `ModifiedElement.swift` keeps `ModifierLayer`, `_wrap`'s
default and the fixed `frame`. In `NativeModifiedContent.swift` every proposal
modifier returns `ModifiedContent<ProposalBase, LayoutModifier>` through
`_wrapLayout`, and `NativeModifiedContent` is retargeted. In
`ProposalElementGroup.swift` the protocol gains `ProposalBase`/`_wrapLayout`
and its default, and the unconditional `extension ModifiedContent:
ProposalElement {}` is gone. The doc lines in `ElementGroup.swift` and
`DecorationScope.swift` name the new home.

### 7.1 Red first

At `273bbd8` the implementation was absent (the four source files as at
`47c0d98`). N1.1 and N1.2 **do not compile**, which is their red, so that
commit's test target does not build by design:

    UnifiedModifiedContentTests.swift:88:32: error: generic type 'ModifiedContent' specialized with too many type parameters (got 2, but expected 1)
    UnifiedModifiedContentTests.swift:90:19: error: value of type 'ModifiedContent<ModifiedContent<ModifiedContent<Rectangle>>>' has no member 'layerCount'
    UnifiedModifiedContentTests.swift:138:32: error: generic type 'ModifiedContent' specialized with too many type parameters (got 2, but expected 1)
    UnifiedModifiedContentTests.swift:140:19: error: value of type 'ModifiedElement<ModifiedContent<Rectangle>>' has no member 'prefix'

With that file set aside, the two guards ran and failed:

| test | first failure line |
|---|---|
| G1.1 `aProposalModifierChainInfersOneFlatModifiedContent` | `UnifiedModifiedContentCompileGuards.swift:73:9: Expectation failed: flat.succeeded != nested.succeeded`. Both fixtures fail with `generic type 'ModifiedContent' specialized with too many type parameters (got 2, but expected 1)` |
| G1.2 `anExternalModifierLayerKindCannotBuildAModifiedContent` | `UnifiedModifiedContentCompileGuards.swift:141:9: Expectation failed: conformer.succeeded != memberwise.succeeded && …`. All three fail with `cannot find type 'ModifierLayerKind' in scope` |

**Literals from `47c0d98`**, a scratch test, deleted. The nested chain
`ZStack { leaf().padding(e).frame(width: 60).background(.accent) }` has 4 nodes,
work 2/2/7 and five recorded bounds. N1.2's generic spelling inferred
`ModifiedElement<ModifiedContent<Rectangle>>`, with 3 nodes, work 1/2/3, bounds
root (80, 65) 40×30, `.child(root, 0)` (86, 71) 28×18 and content (90, 75)
20×10, and a fill at (80, 65) 40×30. Arm 2 has 5 nodes, work 1/4/5, bounds
(72, 57) 56×46, (80, 65) 40×30, (86, 71) 28×18 and (90, 75) 20×10, and the fill
at (80, 65) 40×30.

### 7.2 The budget guard first

Once the type compiled, and before the suite ran,
`aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` and
`aNestedModifiedElementCannotBeSpelled` passed. The first printed `MC-A solver
budget 1000: positive succeeded=true messages=[]; negative succeeded=false
messages=[the compiler is unable to type-check this expression in reasonable
time; …]`. **No fallback.** `ModifiedElementCompileGuards.swift` is untouched:
`extension ModifiedElement` over the typealias still exhausts the budget, as
the skeleton predicted. The positive fixture was binary-searched against each
commit's own `MetalUI` module (the demo-pixel harness's exported builds) at
**186** scopes for `47c0d98` and **214** for `82c5ef9` (`LR-GB` item 5).

### 7.3 Green

After `swift package clean`: `swift build --build-system native
--build-tests` gave 0 `error:`, with SwiftPM's deprecation notice the only
`warning:`. `swift build --build-tests` under the default build system
(`--scratch-path` in the scratchpad) gave 0 `error:` and 0 `warning:`. The
unfiltered `swift test --build-system native --no-parallel` read **`Test run
with 1430 tests in 3 suites passed after 80.725 seconds.`**, and the log
carries `FR-J no-argument frame: succeeded=` (the guards ran). **1430 = 1426 +
4** (N1.1, N1.2, G1.1, G1.2). Guards 82 → **84**. No test was retired, and no
retained test changed its answer. The T rows are annotation and type-name
changes only: `legacyModifierChainsInferOneConcreteType` (the names now print
`ModifiedContent<…, ModifierLayer>`),
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder` and
`proposalLayoutFrameUsesTheTypedProposalWrapper` (annotations),
`everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (four
pins gain `, LayoutModifier`) and
`proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous` (its
return type). **Every state-retention and identity test spec §3.3 names ran
unedited and green.** `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`)
builds and tests, 21 + 19 passed. Docker is not available on this machine, so
the container check was not run.

### 7.4 Mutations

Each mutation was applied by a script to the committed tree (`82c5ef9`), built,
run through the whole suite unfiltered, and restored from a copy, with `git
status --short` empty after each. M1a and M1h change a public declaration, so
each was run after `swift package clean`. So was M1b, the first body mutation
after M1a (`LR-GB` item 3).

| id | mutation (spelling, branch) | suite | reddened |
|---|---|---|---|
| M1a (as spelled by the spec) | `typealias ProposalBase = Content` deleted | 1430 passed | **nothing: a broken instrument.** `ProposalBase` is re-inferred from `_wrapLayout`'s return type, so the mutant is the implementation (`LR-GB` item 2) |
| M1a | the typealias **and** the appending `_wrapLayout` witness deleted, clean build | test target does not compile | `NativeLayoutIntegrationTests.swift:655: cannot assign value of type 'ModifiedContent<ModifiedContent<NativeProbeLeaf, LayoutModifier>, LayoutModifier>' to type 'ModifiedContent<NativeProbeLeaf, LayoutModifier>'` (T row `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`) |
| M1a (runtime) | the same, with that one annotation relaxed to `var root = stored` | 4 issues | N1.1 `aProposalChainIsOneFlatModifiedContentWithTheNestedChainsIdentities` (2: the type assertion `:88`, the layer count `:90`); G1.1 `aProposalModifierChainInfersOneFlatModifiedContent` (2: the flat fixture fails `:75`, the nested one compiles `:76`) |
| M1b | `innermostID`'s inner-layer component `at: Modifier.self == LayoutModifier.self ? 1 : 0` | 3 issues | N1.1 (1, `flat.bounds == nested.bounds`); `stateSurvivesFramesUnderAProposalModifierChain` (2, `ModifierCompositionProofTests.swift:800–801`, the padding and frame components read `.positional(1)`) |
| M1i | `recordElementBounds` skipped in `prepaintLayerBody`'s `inside()` when the next layer is a proposal one (`Modifier == LayoutModifier` or a prefix layer) | 3 issues | N1.1 (1, bounds); N1.2 `aLegacyWrapperAfterAProposalChainAbsorbsItAsItsInnermostLayers` (2: arm 1's and arm 2's bounds) |
| M1d | `LayoutModifier._legacyStack` returns `([], [])` (the prefix dropped) | 5 issues | N1.2 (5: the prefix count, arm 1's bounds and node/work, arm 2's bounds and node/work) |
| M1d′ | `wrapLayers` walks `inner` before `prefix` (the absorbed layers above the inner legacy ones) | 2 issues | N1.2 arm 2 only (bounds `:159`, rects `:164`). Arm 1, with no inner legacy layer, is the identity, which is why arm 2 exists |
| M1h | the memberwise `init(content:outermost:inner:prefix:)` made `public`, clean build | 1 issue | G1.2 `anExternalModifierLayerKindCannotBuildAModifiedContent` (`:141` `#require`: the memberwise fixture compiles, `memberwise succeeded=true`) |

**Each new guard was mutated red once**: G1.1 by M1a, and G1.2 by M1h.

### 7.5 Value sizes and the stack budget (after lane 1)

Taken with a scratch test in `MetalUICrossPlatformTests` (debug, macOS arm64),
deleted afterwards:

| type / value | `47c0d98` (§1) | `82c5ef9` |
|---|---|---|
| `Decoration` | 77 | 77 |
| `Handlers` | 320 | 320 |
| `ModifierLayer` | 662 | 662 |
| `LayoutModifier` | 46 | 46 |
| `ModifiedElement<Box<EmptyGroup>>` | 1272 | **1280** (the empty `prefix`) |
| `Box<EmptyGroup>` | 600 | 600 |
| a one-layer proposal chain over `Rectangle` | 62 | **80**, for any length (two nested levels were 110) |
| `OverlayModifier<Rectangle, Rectangle>` | 23 | 23 |
| `demoContent()` | 33 912 | **34 064** (+152, +0.45 %) |
| `nativeLayoutPreviewContent()` | 935 | **801** |
| `textInputDemoContent()` | 5 312 | 5 328 |

**Stack.** One exit test per size ran `buildEveryProductionTree(onAThreadOf:)`
at 480, 496, 512, 516, 520, 524, 528, 532, 536, 540, 544 and 560 KB. It got
`.signal(SIGBUS)` at 480, 496 and 512, and success at 516 and above. So the
smallest stack is **> 512 and ≤ 516 KB**: inside the design's `(512, 528]`, and
under the 544 KB block (spec §8). `everyProductionTreeBuildsOnAOneMegabyteThread`
is green in the suite.

### 7.6 The demo

`docs/probes/demo-pixels/compare.sh <scratch>/pix 47c0d98 82c5ef9`. The
controls at `47c0d98` read the stage-9 corrected values: light vs dark
1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0,
preview light vs dark 1048576, chrome pair 0, distinct 544 / 216, prod default
vs modal 491221, distinct prod-default-light 529, indicator rects 0. **All
fourteen images read 0 differing, and every scene is identical.**

### 7.7 Deferred from lane 1

Nothing is deferred from lane 1. The overlay's widening (`OverlayModifier` over
`ElementGroup`, the `.overlay` moved to `ElementGroup`) is lane 2's, and it
touches no file of this lane.

## 8. Lane 2 — the legacy `.overlay` (2026-09-25)

Commits `131fe16` (red first: N1.3–N1.7 and the overlay T rows) and `540da08`
(the overlay). Ruling `LR-GC`, which applies two T rows the design missed and
adds N1.3's group arm.

**What was built** (spec §5, `LR-FX`, as ruled). `OverlayModifier<Content:
ElementGroup, Overlay: ElementGroup>` gets an untyped `requestLayout` in its
body (both sides through `requestGroupLayout`) and a conditional `extension
OverlayModifier: ProposalElementGroup, ProposalElement where Content:
ProposalElementGroup, Overlay: ProposalElementGroup` with the typed
`requestProposalLayout`. The two share `overlaySide(of:)` (`MC-P`'s `-1`) and
`attach`. `attach` runs both sides through `lowerAttachmentChildren`, then calls
`requestSecondaryContentAttachment`. The one `.overlay(alignment:content:)` moved
to `extension ElementGroup`; the deprecated `nativeOverlay` and the
`NativeOverlayModifier` typealias stay proposal-only. The new
`Sources/MetalUI/AttachmentLowering.swift` holds `lowerAttachmentChildren`:
`droppingPresentations`, `consume`, `planLegacyItems` at `parentKind: .stack`,
`parentSite: .modifierLayer` against a `.center`/`.center` parent, then
`registerLegacyItems`. `NativeBackgroundModifier.swift`'s
`requestSecondaryContentAttachment` takes and returns `LayoutNodeID`s.
`ProposalElementGroup.swift`'s unconditional `extension OverlayModifier:
ProposalElement {}` is gone.

### 8.1 Red first

At `131fe16` the implementation was absent, so the new file does not compile.
That is the red for all five tests, and the test target does not build by
design. The build's error lines, one per test body:

    LegacyOverlayTests.swift:275:10: error: value of type 'Box<Pair<OptionalGroup<Box<EmptyGroup>>, TapLeaf>>' has no member 'overlay'   (N1.3, L1)
    LegacyOverlayTests.swift:294:10: error: referencing instance method 'overlay(alignment:content:)' on 'ModifiedContent' requires that 'Box<Pair<OptionalGroup<Box<EmptyGroup>>, TapLeaf>>' conform to 'ProposalElementGroup'   (N1.3, L3)
    LegacyOverlayTests.swift:304:42: error: instance method 'overlay(alignment:content:)' requires that 'TapLeaf' conform to 'ProposalElementGroup'   (N1.3, L4: a proposal primary, a legacy overlay)
    LegacyOverlayTests.swift:374:14: error: value of type 'Box<EmptyGroup>' has no member 'overlay'   (N1.4)
    LegacyOverlayTests.swift:412:51: error: value of type 'Deferred<Box<EmptyGroup>>' has no member 'overlay'   (N1.5)
    LegacyOverlayTests.swift:435:30: error: value of type 'TwoMembers' has no member 'overlay'   (N1.7)

N1.3's other arms fail the same way (L2 `:284`, controls `:319`–`:343`). The
lines were taken from a build one helper-rename before the commit: the file's
`group` builder helper clashed at the call site (`value of type 'group' has no
member 'overlay'`) and was renamed `members` before `131fe16`. L5's own lines
were re-taken at `131fe16` by the lane's verifier (and recorded by the fix
round, `LR-GD` item 5):

    LegacyOverlayTests.swift:310:26: error: referencing instance method 'overlay(alignment:content:)' on 'OptionalGroup' requires that 'EmptyComponent' conform to 'ProposalElementGroup'   (N1.3, L5)
    LegacyOverlayTests.swift:311:13 and :313:10   (N1.3, L5: the same failure's follow-on lines) N1.6 is a must-not-move pin with no red by
design. Its literals — **5 nodes, work 3/4/8, six recorded bounds, rects (80,
65) 40×30 and (95, 75) 10×10 at alpha 0.5** — were taken at `47c0d98` by a
scratch test in the demo-pixel harness's export of that commit (`src-47c0d98`),
which was deleted afterwards.

### 8.2 Green

After `swift package clean` (`OverlayModifier`'s public generic constraints
changed), `swift build --build-system native --build-tests` gave 0 `error:`,
with SwiftPM's deprecation notice the only `warning:`. The first unfiltered run
read `Test run with 1435 tests in 3 suites failed … with 2 issues`. Both issues
were in `anItemFieldNoLoweredContainerConsumesIsReportedByName`, whose
`.overlay` primary and slot arms read `[]` against an expected
`[box.flexGrow.unconsumed]`. That is the move `LR-FX` item 3 rules, missed by
the design's T list (`LR-GC` item 2). `proposalOverlayAcceptsProposalContentAndRejectsLegacyContent`
was found by reading before the run (`LR-GC` item 1). With both T rows applied,
the unfiltered `swift test --build-system native --no-parallel` read **`Test
run with 1435 tests in 3 suites passed after 80.951 seconds.`**, and the log
carries `FR-J no-argument frame: succeeded=` (the guards ran). **1435 = 1430 +
5** (N1.3–N1.7). Guards stay at 84: lane 2 edits two guards' bodies and adds
none. No test was retired. The default build system (`swift build
--build-tests --scratch-path <scratch>`) gave 0 `error:` and 0 `warning:`.
`MetalUILayout` imports only `MetalUICore`, and no file of it changed.

Measured control readings (N1.3): each arm read `[tally .positional(0) at the
overlay side, 3 taps]` at all three steps, with its primary's trailing member
at `.positional(1)`, `.positional(0)`, `.positional(1)`. A read `[3, 3, 3]`, B
`[3, 0, 0]`, P5 `[3, nil, 3]` and Q `[3, 0, 3]`. The third step of P5 and Q is
divergence 18's retention (`LR-GC` item 4).

**Every identity test spec §3.3 lists ran unedited and green**, among them
`theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`,
`aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`,
`hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` and
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`.

**Gates.** `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`) built with 0
`error:` (its only warnings are the pre-existing SDL dylib deployment-target
linker notes) and tested 21 + 19 passed. Docker was available this time. In a
`swift:6.4-noble` container (aarch64), `git archive 540da08` built with the
default build system with 0 `error:`/`warning:` lines. `swift test --filter
'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'` read three
summary lines, 188, 10 and 22 tests passed, with
`theDemoFrameMatchesTheValuesRecordedOnMacOS` among them. `Expected.swift` is
unmoved.

### 8.3 Mutations

Each mutation was applied by a script (`muts.py` in the scratchpad) to the
committed tree (`540da08`), built incrementally (body-only changes), run
through the whole suite unfiltered, and restored from a copy of
`Sources/MetalUI/`. `git status --short` was empty after each.

| id | mutation (spelling, branch) | suite | reddened |
|---|---|---|---|
| M1c | `overlaySide(of:)` returns `.child(of: id, at: 0)` (both entries share it) | 14 issues | N1.3 `aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape` (L1–L5 and control A, each on `tallyAtOverlaySide`); N1.4 `aLegacyOverlayConsumesItsPrimarysAndOverlaysRecordsAsAFrameLayerDoes` (the overlay's rect, `:387`); N1.6 `aProposalOverlayRegistersExactlyTheNodesItDidBeforeUnification` (`elementBounds.count == 6`, `:473`: the overlay's key collides with the primary's); `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities` (2); `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` (3); `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` (1) |
| M1c′ | the **untyped** entry's overlay side registered under `id`, continuing the primary's cursor (`MC-E`'s `6ff2d31`) | 8 issues | N1.3 (L1–L4 and A on the id only; **L5 on the state too**: the tally at indices 2, 1, 2 with taps 3, **0**, 3); N1.4 (`:387`); `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` (1) |
| M1e | `attach` passes the primary's nodes unlowered | 4 issues | N1.4 (`unlowerableFields.isEmpty`, `:380`: `box.flexGrow.unconsumed`); `anItemFieldNoLoweredContainerConsumesIsReportedByName` (the overlay-primary arm, `:819`); N1.5 `anOverlayOnAPresentationTrapsNamingItsPrimaryCount` (2: the child exits 0, since the placeholder is not dropped) |
| M1e′ | `attach` passes the overlay side's nodes unlowered | 2 issues | N1.4 (`:380`, `box.margin.unconsumed`); `anItemFieldNoLoweredContainerConsumesIsReportedByName` (the overlay-slot arm, `:819`) |
| M1f | the primary lowered with `dropsPresentations: false` (a parameter added in the mutant; the overlay side still drops) | 2 issues | N1.5 (2: expected `.failure`, got `EXIT_SUCCESS`; the stderr line absent) |
| M1g | `lowerAttachmentChildren` wraps every record-less child in `requestNativeFrame(child:alignment: .center)` | 4 issues | N1.6 (node count `:470`, work `:472`); `anEmptyOverlayOrBackgroundLeavesThePrimaryAlone` (`nodeCount == 1`); `everyProductionRootsDeepestNativeLevelIsMeasured` (the demo's overlay adds a level) |
| M1j | `requestSecondaryContentAttachment`'s precondition relaxed to `primary.count >= 1` | 2 issues | N1.7 `aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount` (2: the child exits 0; the stderr line absent) |

*Fix round (`LR-GD`, commit `58a4f5c`).* The lane's verifier found three
mutations of `lowerAttachmentChildren` that reddened nothing (V2, V4, V5). Four
pins were added, N1.8–N1.11, and each mutation was re-applied to `58a4f5c`, run
through the whole suite unfiltered (1439 tests), and restored from a copy;
`git status --short` showed no source change after each.

| id | mutation (spelling, branch) | suite | reddened |
|---|---|---|---|
| V5 | `guard fields.isEmpty else {` → `if false, !fields.isEmpty {` (the report block skipped; both sides) | 3 issues | N1.8 `eachSideOfALegacyOverlayReportsItsUnlowerableFieldsByName` (`:510`, the report reads `[]`); N1.9 `aProductionFrameTrapsOnAnOverlaySidesUnlowerableField` (2: the child exits 0; the stderr line absent) |
| V2 | `parent.justifyItems = .center` and `parent.alignItems = .center` deleted (a default, stretching parent) | 2 issues | N1.10 `aMultiViewLegacyOverlayStretchesNoneOfItsViews` (`:576`, `:578`: both views' rects) |
| V4 | `lowerAttachmentChildren` gains `dropsPresentations: Bool = true` in the mutant only; `attach` passes `false` for the **overlay side**, the primary still drops | 1 issue | N1.11 `anOverlaySideDeferredPresentsAgainstTheWindowAndLeavesNoPlaceholder` (`:611`, nodes 8 against 7; the presented rect unchanged, as predicted) |

With N1.8–N1.11 the suite reads **`Test run with 1439 tests in 3 suites
passed`** (1435 + 4), guards still 84, the log carrying `FR-J no-argument
frame: succeeded=`. N1.11's count literal (7) was measured, not derived; the
verifier's 9 was the same overlay inside an enclosing `Box`.

Every new test is reddened by at least one of its named mutations. No new
typecheck guard was added in this lane, so none is owed a red.

### 8.4 The demo

`docs/probes/demo-pixels/compare.sh <scratch>/pix 47c0d98 56275c5 540da08`.
The controls at `47c0d98` read the stage-9 corrected values again: light vs
dark 1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0,
preview light vs dark 1048576, chrome pair 0, distinct 544 / 216, prod default
vs modal 491221, distinct prod-default-light 529, indicator rects 0. **All
fourteen images read 0 differing, and every scene is identical**, for `47c0d98 →
56275c5` and `56275c5 → 540da08` alike. The demo content's one `.overlay` (`PreviewToggle`'s
`.topTrailing` badge in the proposal preview) takes the typed entry, and its
record-less nodes pass through unwrapped (N1.6's rule; M1g, which wraps them,
reddens `everyProductionRootsDeepestNativeLevelIsMeasured`).

Value sizes are not re-taken: this lane adds no stored property, and
`OverlayModifier<Rectangle, Rectangle>` has the same two stored sides and
alignment. `everyProductionTreeBuildsOnAOneMegabyteThread` is green in the
suite. The spec re-takes the bisection after lanes 1 and 3.

### 8.5 Deferred from lane 2

Nothing new is deferred from this lane. A legacy `.background { content }`
(`LR-FX` item 6) and per-member overlay distribution over a multi-member
`Component` (`LR-GA` item 3) stay plan task 8's, as ruled.

## 9. Lane 3 — opacity order and the owned lowering items (2026-09-25)

Commits `dcdc415` (red first: T2.1 renamed, N2.1–N2.4, the four T rows' arms
moved), `40e48bd` (implementation) and `529b032` (a comment). Ruling `LR-GE`.
Files as spec §7 lane 3 lists them; `ModifierTests` unedited.

### 9.1 Red first

Built with 0 `error:`/`warning:` beyond SwiftPM's notice, then the whole suite
unfiltered at `dcdc415`'s tests over lane 2's source: **`Test run with 1443
tests in 3 suites failed … with 10 issues`**, every issue in a new or renamed
test:

| test | red line |
|---|---|
| T2.1 `aBackgroundOrBorderWrittenAfterOpacityEscapesIt` | `DecorationPaintTests.swift:911` — `abs(g3 - g4) > 0.001` (G4 faded like G3) |
| N2.1 `theOpacityOrderAnswersTheSameOnBothPathsThroughTheUnifiedType` | `OpacityOrderTests.swift:120` — the legacy path's `abs(path.g3 - path.g4) > 0.001` |
| N2.4 `aHoverOrFocusFillWrittenAfterOpacityEscapesOnlyWhileItIsTheResolvedOne` | `:186` hovered fill `0.5 ×`; `:211` focused ring `0.5 ×` |
| N2.2 `aComponentAmendOverAPresentationMemberAnswersAsAFrameLayerDoes` | `PresentationContainingBlockTests.swift:164` ×3 — `.width(70)`, `.height(70)` report `["deferred.amended"]`, the `StyledComponent` arm two of them; the frame-layer control green, hitboxes already (5, 5) 10×10 |
| N2.3 `aTwoMemberAbsoluteFrameInADeferredIsARowOfPerMemberFramesAgainstTheWindow` | `PresentationLoweringTests.swift:725` `["modifierLayer.style"]`; `:726` both hitboxes 0×0 at (0, 0); `:735` the control read `["modifierLayer.style", "modifierLayer.position", "modifierLayer.inset"]` (`LR-GE` item 1) |

T2.1's H1 and H3 arms were green before (the legacy path already faded both
orders, so only the after-opacity arms G4 and H2 moved).

### 9.2 Green

`swift package clean` (a stored property on the public `Decoration`), then
`swift build --build-system native --build-tests` 0 `error:`, one `warning:`
(SwiftPM's notice); `swift test --build-system native --no-parallel`
unfiltered: **`Test run with 1443 tests in 3 suites passed`**, the log carrying
`FR-J no-argument frame: succeeded=true`. `swift build --build-tests` under the
default build system: 0 `error:`, 0 `warning:`. No file of `MetalUILayout`
changed.

### 9.3 Mutations

Applied by `mutations.py` (scratchpad) to the committed tree `529b032`, built
incrementally, whole suite unfiltered (1443 tests each), restored from a copy of
the four touched files; `git status --short` empty after each.

| id | mutation (spelling, branch) | suite | reddened |
|---|---|---|---|
| M2a | `.background`'s `$0.noteWrite(.plainFill)` deleted | 2 issues | T2.1 (`:911`, G3 ≠ G4); N2.1 (`:120`, legacy G3 ≠ G4) |
| M2b | `let escapes: Decoration.OpacityEscapes = []` in `paintDecoration` | 4 issues | T2.1 (`:911`); N2.1 (`:120`); N2.4 (`:186` hover, `:211` focus) |
| M2c | `escapesOpacity = []` deleted from `setOpacity` | 3 issues | T2.1 (`:930`, H3 reads the full fill); N2.1 (`:132` H3 legacy ≠ proposal, `:133` H3 ≠ G3) |
| M2d | `let borderEscapes = false` | 3 issues | T2.1 (`:914`, H1 ≠ H2); N2.1 (`:122`, legacy H1 ≠ H2); N2.4 (`:211`, focus ring) |
| M2e | `fillEscapes` negated (`!escapes.contains($0.slot.fill)`, `LR-GE` item 3) | 14 issues | T2.1 (`:918` G3, `:921` G4, `:930` H3); N2.1 (`:124`, `:128`, `:129`, `:132`); N2.4 (`:171`, `:186`); `opacityMultipliesAndFadesTheElementsOwnBackground` (`:837`, `:850`); `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` (`:988`, `:991`); `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority` (`OuterModifierMatrixTests.swift:697`) |
| M2f | `frame.noteUnlowerable(UnlowerableField(site: .deferred, field: "amended"))` restored in `loweredComponentFrame`'s presentation branch | 3 issues | N2.2 (`:164` ×3, the three amend arms) |
| M2g | `if declared.position == .absolute && childCount <= 1 {` | 3 issues | N2.3 (`:725`, `:726`, and `:735` — the control gains `style` too) |
| M2g′ | `if d.position == .absolute && item.kind != .frameLayer {` in `planLegacyItems`' outside-a-`Deferred` report (`LR-GE` item 4) | 2 issues | N2.3 control (`:735`); `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred` (`:676`, arm 2) |
| M2h | `LayoutModifier._paint`'s `case .opacity: inside()` (`LR-GE` item 5) | 3 issues | N2.1 (`:120`, the proposal G3 ≠ G4); `aProposalOverlayRegistersExactlyTheNodesItDidBeforeUnification` (`LegacyOverlayTests.swift:478`); `opacityMultipliesItsDescendantsPaintAlpha` (`NativeLayoutIntegrationTests.swift:943`) |
| M2i | `.hoverBackground`/`.focusBackground` note `.plainFill`, and `PointerStateSlot.fill` answers `.plainFill` for all three slots (the design's one bit) | 1 issue | N2.4 (`:171`, the unhovered red escapes) |
| M2j | `noteWrite` inserts unconditionally (`opacity < 1` dropped) | 11 issues | N2.4 (`:217`, `:219`, the equality arms); `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (`ModifierTests.swift:416` ×9 — the one-field table) |

Every new test is reddened by at least one of its named mutations. No typecheck
guard was added, so none is owed a red.

### 9.4 The demo, the pins, the gates

`docs/probes/demo-pixels/compare.sh <scratch>/pix 47c0d98 540da08 529b032`.
The controls at `47c0d98` read the stage-9 corrected values (light vs dark
1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3 0,
preview light vs dark 1048576, chrome pair 0, distinct 544 / 216, prod default
vs modal 491221, distinct prod-default-light 529, indicator rects 0). **All
fourteen images read 0 differing, every scene identical**, for `47c0d98 →
540da08` and `540da08 → 529b032` alike: no demo site writes a legacy `.opacity`
before a `.background` or `.border`, so divergence 45's retirement moves no
pixel, as spec §8 predicted. `Tests/MetalUICrossPlatformTests/Expected.swift`
is unmoved (`git diff 47c0d98 HEAD` empty).

`Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`): build 0 `error:`, tests 21 +
19 passed. `swift:6.4-noble` container (aarch64, OrbStack), `git archive
529b032`, default build system: no `error:`/`warning:` line; `swift test
--filter 'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'` read
188, 10 and 22 passed, `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
`everyProductionTreeBuildsOnAOneMegabyteThread` among them.

### 9.5 Value sizes and the stack budget (after lane 3)

The lane-1 scratch (`ZZScratchSizes.swift` in `MetalUICrossPlatformTests`,
debug, macOS arm64), deleted afterwards:

| type / value | `47c0d98` | `82c5ef9` (lane 1) | `529b032` |
|---|---|---|---|
| `Decoration` | 77 | 77 | **78** (`escapesOpacity`) |
| `Handlers` | 320 | 320 | 320 |
| `ModifierLayer` | 662 | 662 | 662 |
| `LayoutModifier` | 46 | 46 | 46 |
| `ModifiedElement<Box<EmptyGroup>>` | 1272 | 1280 | 1280 |
| `Box<EmptyGroup>` | 600 | 600 | 600 |
| `ModifiedContent<Rectangle, LayoutModifier>` | 62 | 80 | 80 |
| `OverlayModifier<Rectangle, Rectangle>` | 23 | 23 | 23 |
| `demoContent()` | 33 912 | 34 064 | 34 064 |
| `nativeLayoutPreviewContent()` | 935 | 801 | 801 |
| `textInputDemoContent()` | 5 312 | 5 328 | 5 328 |

The one byte fits in `Decoration`'s padding, so no containing value moves.
**Stack**: exit tests at 480–560 KB — `.signal(SIGBUS)` at 480, 496, 512,
success at 516 and above: **> 512 and ≤ 516 KB**, the same as after lane 1 and
under the 544 KB block. `everyProductionTreeBuildsOnAOneMegabyteThread` is green
in the suite and in the container.

### 9.6 Deferred from lane 3

Nothing new. For the Record phase: `UnlowerableField.owner` no longer names task
7 (its only branch left is `"plan task 11"`), but `trapMessage`'s permanent
clause reads `"refused by name (plan task 7, LR-FO)"` — a ruling citation, not
an owner — so spec §9.1's `grep -n "plan task 7" Sources` hits it (and many
comments) and must be read, not counted. The mid-animation snap when a hover or
focus change moves the winning slot across the scope is owed to record §05's
snap list (spec §4).

### 9.7 Lane 3's fix round — the escape's emission order (N2.5)

Ruling `LR-GF`, commit `d86cb4e`. The verifier found that no test pinned where
an escaped fill or border sits relative to the element's content: its **V3**
(the escaped-fill block moved after the opacity scope) left 1443 green, and a
scratch test showed the mutant paints an opaque 40×40 background over a faded
20×20 child. **N2.5** `anEscapedFillPaintsUnderTheContentAndAnEscapedBorderOverIt`
(`OpacityOrderTests`) puts a child in the G4 and H2 subjects on three shapes
(legacy `Box { child }`, legacy padding layer, proposal `Rectangle` padding
layer) and asserts fill index < child index < border index, after set-up
requires that the fill/border escaped and the child did not.

Mutations applied by `mut.py` (scratchpad) to `d86cb4e`, built, whole suite
unfiltered, restored from a copy, `git status --short` empty after each:

| id | mutation | suite | reddened |
|---|---|---|---|
| V3 | `if fillEscapes` block moved after `opacity(…) { … }` | 1444, 2 issues | N2.5 (`OpacityOrderTests.swift:325` ×2, the two legacy G4 shapes) |
| V4 | `if borderEscapes` block moved before `opacity(…) { … }` | 1444, 3 issues | N2.5 (`:333` ×2, the two legacy H2 shapes); `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority` (`FrameDecorationInteractionTests.swift:449`) |

Suite at `d86cb4e`: `swift build --build-system native --build-tests` 0
`error:`, one `warning:` (SwiftPM's notice); `swift test --build-system native
--no-parallel` unfiltered **`Test run with 1444 tests in 3 suites passed`**,
`FR-J no-argument frame: succeeded=true`; `swift build --build-tests` 0
`error:`, 0 `warning:`. T2.1's doc comment now spells M2e as the source
inversion (`LR-GE` item 3).
