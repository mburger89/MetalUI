# 16 — Integration of plan tasks 4 and 5

`integrate/tasks-4-5`, from `c4b5853`, 2026-09-16. Two tracks, each verified
`ok` on all four lanes by its own verifiers (records §14 and §15):

- `feat/frame-sizing` (plan task 4, rulings `FR-A`…`FR-V`), 1247 / 97 / 63 alone;
- `feat/outer-modifiers` (plan task 5, rulings `OM-A`…`OM-AM`), 1274 / 97 / 64 alone.

This step ran in two sessions. The first was cut off by a usage limit after
three commits; the second resumed from the branch alone.

## Merges

| commit | what |
|---|---|
| `a6899ea` | `--no-ff` merge of `feat/frame-sizing` at `957b068`. Clean. |
| `4f356a8` | `--no-ff` merge of `feat/outer-modifiers` at `792893f`. **One conflict, `Box.swift`**: outer-modifiers deleted `borderWidth(_:)` (`OM-M`) where frame-sizing had annotated `borderWidth(_ edges:)` as one of four public rem entry points (`FR-Q`'s addendum). The deletion stands; `padding(_ edges:)`'s and `margin(_ edges:)`'s comments now count **three** (`padding`, `margin`, `inset`) and say why. Suite after `swift package clean`: 1295, green, no interaction red. |
| `45f15e8` | six cross-track tests, `FrameDecorationInteractionTests.swift` (below). 1301. |
| `520f039` | the seventh test, probe arms S0–S3, doc sentences. 1302. |
| (docs commit) | the eighth test (probe B1/B2/D1/D2), the shared docs. 1303. |
| `c847573`, `e35832c` | `--no-ff` merges of the tracks' last record commits (`3858eff`, `77740f8`), docs only, made because the first session merged each branch before its final record commit. No `Sources/` or `Tests/` change. |

**No interaction fix was needed.** Every behaviour both tracks verified
survived the merge; the cross-track tests below are characterizations, green on
arrival, each proved able to fail by a mutation.

## The uncommitted change the interrupted session left

`git status` on resuming showed one modified file, `ModifiedElement.swift`,
`paintLayer`:

```swift
var decoration = depth == inner.count ? outermost.decoration : inner[depth].decoration
if depth == inner.count { decoration.clipsContent = false }
```

Either an interaction fix in progress or a mutation never reverted. Measured
both ways, `swift test --build-system native --no-parallel`, unfiltered:

- **with it**: `Test run with 1301 tests in 1 suite failed … with 5 issues`;
- **without it**: `Test run with 1301 tests in 1 suite passed`.

So it was a mutation (**M0** below), and it was reverted. It removes the
outermost layer's paint clip and nothing else.

## Cross-track tests and their mutations

All eight in `Tests/MetalUITests/FrameDecorationInteractionTests.swift`. M0–M4
and M8 are in `ModifiedElement.swift` and touch the **outermost layer only**
(`depth == inner.count`), so what reddens is what can see a frame layer's
decoration or handlers. Full unfiltered suite per mutation unless noted; each
reverted with `git checkout`, and the suite re-read passed afterwards.

| # | test | pair |
|---|---|---|
| 1 | `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` | `FR-N` × `OM-G`/`OM-V` |
| 2 | `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` | `FR-C`/`FR-E` × `OM-J` |
| 3 | `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame` | `FR-C` × `OM-L` |
| 4 | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` | the component frame side door × `OM-D`/scopes |
| 5 | `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset` | `FR-C` × `OM-J` × `AB-E` |
| 6 | `aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick` | `FR-C` × `OM-L` × `EV-D`/`EV-X` |
| 7 | `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt` | `OM-J` × `MC-A`, probe S0–S3 |
| 8 | `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes` | `FR-C` × `OM-C`, probe `swiftui-outer-modifier-order` B1/B2/D1/D2 |

| mutation | reddened (issues) |
|---|---|
| **M0** `paintLayer`: outermost `decoration.clipsContent = false` | `everyDecorationScopingSiteContainsItsOwnContent` (1), `aChainsOuterLayerScopesContainTheLayersInsideIt` (2), **test 1** (1), **test 4** (1) |
| **M1** `prepaintLayerBody`: outermost `handlers.contentShapeInset = nil` | **test 2** (1), **test 5** (1) — and nothing else: no track test puts a content shape on a `ModifiedElement` layer. *Measured at `45f15e8`, before test 7 existed. Re-run at `d3bffbc` by the integration check (isolated worktree, default build system, unfiltered): 3 issues — test 2 (1), test 5 (1) and **test 7** (1), whose S2 arm puts the inset on the outermost layer. Still no track test.* |
| **M2** `paintLayer`: outermost `focusBorder = nil; hoverBorder = nil` | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` (2), **test 3** (2), **test 6** (1) |
| **M3** `prepaintLayerBody`: the outermost layer's registration runs under `withEnvironment` with `isEnabled = true` | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` (2), `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest` (8), **test 6** (1) |
| **M4** `prepaintLayerBody`: the outermost layer with an `onClick` and an inset registers at `hitRegion(bounds, inset)` with the inset cleared (the inset applied at the call site, moving the accessibility frame with it) | **test 5** (1), alone |
| **M5** `Frame.hitRegion` returns `bounds` for a non-negative inset (filtered to test 7) | **test 7** at its `#require` that the two orders disagree |
| **M6** `Frame.registerHandlers` inserts a hitbox for `isPointerTarget || contentShapeInset != nil` (filtered to test 7) | **test 7** (2): the before-order's regions and clicks |
| **M7** `FrameLayer.swift`: `.center` lowers to `justifyContent = .flexStart` | 34 issues in 14 tests: `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` (2), `chainedFramesRemainConcreteAndNestTheirLayoutNodes` (2), **test 2** (2), **test 3** (3), **test 4** (1), **test 5** (2), **test 8** (4), `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` (1), `aLegacyFixedFrameDoesNotShrinkAsAFlexItem` (2), `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` (1), `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite` (1), `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (6), `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (3), `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` (4) |
| **M8** `paintLayer`: an outermost layer with inner layers paints its decoration at the innermost layer's bounds | 10 issues in 9 tests: `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyDecorationPaintingSiteDrawsItsBorder`, `everyDecorationScopingSiteContainsItsOwnContent`, `aChainsOuterLayerScopesContainTheLayersInsideIt`, **test 8** (D1), `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (2), `aModifierChainIsIdenticalToHandBuiltNestedBoxes`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` |

## `contentShape` across a wrapping layer — probed

Lane 3's verifier on the outer-modifiers track measured that
`.contentShape(inset: 20).padding(10).onClick { }` registers the padded layer's
whole frame and `.padding(10).contentShape(inset: 20).onClick { }` the inset
one, and the track carried it as unprobed and unpinned. Four additive arms in
`docs/probes/swiftui-content-shape-hit-region.swift`, run 2026-09-16 09:29 PDT
under `/usr/bin/swift`, exit 0, every older arm (H0–H6, P1–P5, N1–N2, X0–X3)
byte-identical to its header. A 120x120 colour padded by 40 in a 200x200
window, clicked at the centre (100, 100), the colour's outer band (50, 100)
and the padding (10, 100):

```
S0 colour.padding(40).tap (control)          : centre 1 band 1 edge 0
S1 colour.shape(inset 20).padding(40).tap    : centre 1 band 0 edge 0
S2 colour.padding(40).shape(inset 20).tap    : centre 1 band 1 edge 0
S3 colour.padding(40).shape(Rectangle()).tap : centre 1 band 1 edge 1
```

S3 is the positive control (the edge point is delivered). MetalUI reads S2's
`[1, 1, 0]` at `[20 20 160x160]` (agreement) and `[1, 1, 1]` at
`[0 0 200x200]` for S1's spelling, where SwiftUI reads `[1, 0, 0]`:
**divergence 50**, pinned wrong on purpose by test 7. It is `OM-I`'s and
`OM-AL`'s mechanism (the default region is the frame; a per-layer field does
not reach a click on a later layer), not a new one. Doc sentences added to
`StyledElement.contentShape(inset:)` and `Handlers.contentShapeInset`.

## The frame/background orders — probed again, pinned

`docs/probes/swiftui-outer-modifier-order.swift` was re-run under
`/usr/bin/swift` (exit 0) and its whole output compared with its header by
`diff`: identical. Its B1/B2/D1/D2 arms were task 5's "probed, no MetalUI
test" item. Test 8 builds all four on the legacy path and reads the same
numbers (bg 60x60 at the origin after the frame, 20x20 at (20, 20) before it,
the leaf at (20, 20) in all four), `#require`-ing B1 ≠ B2 first. Agreement, no
divergence. The radius orders (`swiftui-border-clip-paint` C3/D1) stay
unpinned.

## Counts

**Final, at the docs commit** (source identical to `520f039` plus test 8):
`Test run with 1303 tests in 1 suite passed` under `--build-system native`,
guards 66, goldens 97 — see "Final re-take" at the end. The figures below were
taken at `520f039`, before test 8.

At `520f039`, after `swift package clean` (`Decoration` and `Handlers` gained
stored properties across the module boundary):
`swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel`:

- `Test run with 1302 tests in 1 suite passed after 39.643 seconds.`
- 0 `error:`; the only `warning:` is SwiftPM's `--build-system native`
  deprecation notice; only `regenerateAllGoldens` and
  `aListsWorkIsTheSameFor100kRowsAsFor500` skipped.
- The guards ran: the log carries `FR-J no-argument frame: succeeded=true
  deprecations=2`, `FR-S overload resolution: succeeded=true` and the
  `OM-B/OM-N/OM-T collision` line with `crossedShape succeeded=false`.
- Goldens: `find Tests -name '*.json' | wc -l` = 97;
  `git diff --stat c4b5853 -- '*.json'` empty.
- Guards, per-file `grep -c canTypecheck`: `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `AXNodeTests` 3, `DecorationCompileGuards` 3,
  `UnitSafetyTests` 3 hits (one a comment), `ModifiedElementCompileGuards` 2,
  `FrameSizingCompileGuards` 2 — **66** guards. `typecheckFile`: 26 (the 21
  before, plus `FrameSizingCompileGuards`' two and `DecorationCompileGuards`'
  three); `typecheck`: 40.
- Delta from `2456c69`'s 1226 / 97 / 61: **+76 tests** (frame-sizing +21,
  outer-modifiers +48, integration +7), 0 goldens, **+5 guards**.
- **Default build system**, same tree, `swift build --build-tests` then
  `swift test --no-parallel`: SIX summary lines, 65 + 714 + 55 + 28 + 418 + 22
  = **1302**, all passed, 0 `error:`, 0 `warning:`; the guards ran there too
  (the `FR-J`/`FR-S` fixture lines are in that log), against the native
  build's surviving `Modules` directory (CI section). The one-line-versus-six
  difference is the build system, as the outer-modifiers track also read.

No new guard was written here, so none needed a red run in this worktree; the
tracks' guard mutations are in §14 and §15, and the three fixture lines above
show the guards executed.

## The demo: not captured; offscreen pixels instead

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>` (09:29 PDT). No demo
was launched, no input sent, the pointer not moved. The frame track's
`FR-V` notes that `IOConsoleLocked` has read `false` on a locked display; it
read `true` here, which is enough to refuse.

**Stand-in**, the harness record §13 describes (`main.swift` up to `runDemo()`
compiled into a generated test, `SI`-prefixed; a real `Window` over
`FakePlatformWindow`, 1024×1024, scale 1; `fakeSurface.readPixels()` and the
`Scene` description). The base is a `git archive c4b5853` tree (its `Sources/`
checked `diff -rq`-identical to the archive), the merged tree a
`git archive 520f039`. Ten images each: `demoContent()` light and dark at
frame 0 and after three ticks, the modal, the settled animation look, and
`nativeLayoutPreviewContent()` light and dark. Debug builds.

| comparison | differing pixels | scene dump |
|---|---|---|
| control: base light vs dark f0 | 1 048 576 | differs |
| control: base default vs modal | 1 030 498 | differs |
| control: base default vs animation | 210 027, bbox (16,113)–(981,1007) | differs |
| base f0 vs f3 | 0 | identical |
| **`c4b5853` vs merged, all ten** | **0** | **identical, all ten** |
| instrument: merged with `padding(_ points:)` doubled AND the kernel's `framedProposal` less 10 | default 402 223 / dark 402 218, modal 395 220 / 395 199, animation 414 103 / 414 100, **preview 66 477 / 66 469** | differs, all ten |

The instrument moves both the legacy images (element padding) and the preview
(the proposal frame), so the preview's zero is a claim this time, unlike §13's.
Not covered: the drawable, the real 920×560 window, input, hover, focus, a
mid-flight animation, a release build. The release-window captures stay owed
(`MC-J`), now for three integrations.

## Numbering decisions

- Divergences at `c4b5853` ran to **34**. Frame-sizing rows are **35–40**,
  outer-modifier rows **41–49**, test 7's **50**. **15 is retired** (`OM-U`).
- The outer-modifier list offered ten rows including "`OM-AA` a" (`.opacity`
  fades the receiver's own fill in both orders on the legacy path, one on the
  proposal path). That is the same fact as `OM-N`'s row seen from both paths,
  so it is folded into **45** rather than numbered twice.
- `FR-O`'s single-axis infinite maximum, `FR-J`'s `.frame()`, `OM-AB`'s
  inert content shape and `OM-AK`'s scroll region are inert-table rows, not
  divergences, as both tracks proposed.

## Verified before writing the shared docs

Every test name either track's "for the integrator" list cites was grepped
(`func <name>` exactly once in `Tests/`); all resolve. Also checked against
source: `grep -rn 'pass\.fill(' Sources/MetalUI` = 8 (two indicators, six
proposal fills); `grep -c 'public func' Sources/MetalUI/Box.swift` = 50;
`ModifierTests`' tripwire `cases.count == 47`; `Handlers` has eight stored
members and `Decoration` nine; `@available(*, deprecated` = 29 (26 `Native`
aliases and methods, `Binding`, and `frame()` on each protocol).

## Refuted or corrected track claims

- Frame-sizing's CLAUDE.md text names `borderWidth(_ edges:)` as a rem entry
  point; it no longer exists (merge conflict above). Three entry points.
- Outer-modifiers' lane 4 verifier called
  `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` misnamed; that
  track's record writer refuted it, and test 4 here builds on the same
  wrapping.

## Carried, not done here

- The release-window captures by `MC-J`'s method (locked display), and
  `FR-V`'s CGS lock check still lacks a positive control.
- The focus ring's look: nothing in the demo declares a `.focusBorder`.
- The radius orders (`swiftui-border-clip-paint` C3/D1): probed, no MetalUI
  test (task 5's open clause; the frame orders are test 8).
- The proposal column in `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`.
- `SA-N`'s "padding places its child at the child's size": neither task took
  it; unowned.
- `.padding` on a `Component` member that contributes no node (a `Deferred`,
  a false `if`) is dropped — documented on `StyledComponent`, unpinned, SwiftUI
  unprobed.
- The `$anim` end-to-end per-entry figures with the 80-byte `Decoration`
  (task 13).
- The two hand-spelled `frameStyle` oracles (`ModifiedElementTests`,
  `ModifierCompositionProofTests`) duplicate `FrameSpec.style()` (`FR-C`).

## Final re-take

At the docs commit (source = `520f039` + test 8 + the doc edits), 2026-09-16:

- `swift build --build-system native --build-tests`, `swift test
  --build-system native --no-parallel`: `Test run with 1303 tests in 1 suite
  passed after 39.129 seconds.` 0 `error:`, 0 `warning:` besides SwiftPM's
  deprecation notice; the two gated tests skipped; the three guard fixture lines
  present.
- Default build system, `swift build --build-tests`, `swift test
  --no-parallel`: six summary lines, 65+715+55+28+418+22 = **1303**, all passed, 0
  `error:`, 0 `warning:`.
- 97 goldens, `git diff --stat c4b5853 -- '*.json'` empty; 67 `canTypecheck`
  hits outside `Typecheck.swift`, one a comment: **66 guards**.
- **Plan boxes:** tasks 4 and 5 are NOT ticked; each has a dated, clause-by-
  clause progress note in the plan.
