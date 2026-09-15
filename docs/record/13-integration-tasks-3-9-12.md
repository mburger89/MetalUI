# 13 — Integrating plan tasks 3, 9 and 12

*2026-09-15, branch `integrate/tasks-3-9-12`, from `f64e58a`.* The three
tracks ran in parallel worktrees and were merged here, in this order, each with
`git merge --no-ff`: `feat/modifier-composition` (`f4bf879`, record §10),
`feat/environment` (`b58f6c7`, record §11) and `feat/ax-bridge` (`8ab2633`,
record §12). All three tracks' verifier rounds reported `ok: true`; none was
skipped. This file records what the merges needed, what only the merged tree
could show, and the measurements behind each. The rules it produced are in
`CLAUDE.md`.

## The merges

| step | commit | textual conflicts | suite after the step |
|---|---|---|---|
| composition | `f8a345e` | none | 1116 passed, 0 `error:`, 0 `warning:` |
| environment | `ff7717f` | `ElementGroup.swift` (1 hunk) | 1165 passed |
| wrapper and E11 arms | `5d63bf4` | — | 1165 passed |
| `EV-X` on the proposal path | `5220d3f` | — | 1166 passed |
| bridge | `80172ac` | `ElementGroup.swift` (1), `Frame.swift` (2, in `registerHandlers`), `Window.swift` (1) | **1223 tests, 2 issues — red on purpose**, below |
| per-layer `AB-O` | `fba579e` | — | 1223 passed |
| joint disabled test | `c9b9674` | — | 1224 passed |
| run-time layer × AX | `869dab1` | — | 1225 passed |
| `EV-Y` arms, disabled `ScrollView`, doc relabels | `2456c69` | — | 1226 passed |

`Sources/MetalUIDemo/main.swift` and `Passes.swift` auto-merged. No
`NativeTappable.swift` conflict appeared (the composition notes predicted one).

### Environment into composition (`EV-W` items 1 and 2)

- **`ElementGroup.swift`**: `Element.requestGroupLayout` takes the composition
  track's `GlobalElementID.enteringGroupMember` (`MC-H`); the helper's bind was
  respelled `StateBinder.bind(element, in: pass.frame, id: id)`. Loud: without
  it the build fails at `GroupMember.swift:39`.
- **`EnvironmentScope`'s typed `requestProposalGroupLayout`**, written exactly
  as `EV-W` item 1 gives it. Loud: without it, `EnvironmentScope.swift:108` does
  not conform.
- **E11's `NativeEnvRecorder` and E23's `NativeClickCounter`** ported from
  `Element` + empty `ProposalElementGroup` conformance (rejected by `MC-G`) to
  `ProposalElement`, the layout read kept inside `requestProposalLayout`. Loud:
  four test-build errors (`EnvironmentTests.swift:95`, `:110`, `:480`, `:498`).
- **Owed arms, added in `5d63bf4`** (silent until written): E11 gains the scope
  outside an inner `HStack` and a no-writer control (it **is** the composition
  track's owed `aProposalContainerReadsTheEnvironmentDuringLayout`; that name is
  not added); `everyModifierWrapperDelegatesEachPhaseExactlyOnce` gains
  `EnvironmentScope, legacy` and `EnvironmentScope, proposal`, each `[1, 1, 1]`.

**Mutations of the typed entry, on the merged tree** (1165 tests each; whole
native suite; restored with `git checkout`, `git status --short` empty after):

| mutation | reddened |
|---|---|
| no `withEnvironment` push | `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` `:655` hstack, `:661` outside, `:667` scroll — each `[0, 7, 7]` (3 issues) |
| `cursor += 1` before forwarding | `aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex` `:462` ×3 |
| fresh cursor under `.child(of: parent, at: cursor, name: nil)` | the same, `:462` ×3 |
| value-keyed parent (`"value:" + String(describing: values)`) with a fresh cursor | `:462` ×3 and `aProposalStateCounterKeepsItsCountAcrossAChangingScope` `:532` (`readings.last` 0) |
| content laid out twice (once on a copy) | `everyModifierWrapperDelegatesEachPhaseExactlyOnce` `:831`, `[2, 1, 1]` — silent before the arms existed (`EV-W`'s scratch measurement) |

### `EV-X` on the proposal path — measured

The environment track left open which side of a scope a proposal `.padding` or
flexible frame written after it sits on. **Outside**, as the legacy frame layer
and SwiftUI's probe O2/O3/O6 are (the probe was not re-run; this measures
MetalUI only). Pinned by `aProposalModifierWrittenAfterAScopeSitsOutsideIt`
(`TrackInteractionTests.swift`), green on arrival, each arm with a disagreeing
spelling that writes the scope last. Mutations (1166 tests):

| mutation | reddened |
|---|---|
| `ModifiedContent`'s background fill hoisted into its content's scope values (a `Mirror` walk for a `values` field) | `:75` (15pt background), `:80` (22pt) |
| `OnTapModifier` registering inside its content's scope values | `:104` (the after-`.disabled` tap reads 0) |
| `EnvironmentScope.paintGroup` without its push | 38 issues across the environment tests, including this test's six dark arms |

### The bridge into both (`EV-W` items 2, 4, 5)

- **`ElementGroup.swift`**: the bridge's `display: none` block kept after the
  prepaint re-bind; its bind respelled `in: pass.frame`.
- **`Window.swift`**: both statements — `collectsAccessibility:` in the
  `Frame(...)` expression, `frame.rootEnvironment = environment` after it.
- **`Frame.registerHandlers`**: the 3-argument overload is a bare forward; the
  gate lives in the 5-argument implementation (focus registration, the `$focus`
  write and the hitbox gated; `focusedElementProducedThisFrame` ungated);
  `AB-L`'s `declaration` kept, with `.disabled` inserted on a copy of
  `handlers.axNode` inside `if !declaration.isEmpty`; the client record carries
  `isEnabled: enabled`, not the bridge's literal `true`. The doc's caller list
  now names `ModifiedElement` (five callers, re-grepped).

**Red at the merge commit, on purpose.** `80172ac` reads `Test run with 1223
tests in 1 suite failed … with 2 issues`: `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`
`AccessibilityTreeTests.swift:682` (`axEmissions` not empty) and `:683`
(`hidden.nodes` not empty). The bridge wrote the test for this merge: a hidden
inner layer of a `ModifiedElement` gets no `Element.prepaintGroup`, where
`AB-O`'s check lived — `MC-B`'s "any hook in the group defaults is mirrored per
layer". **Fixed in `fba579e`**: one helper, `Frame.suppressingAccessibilityIfHidden(_:_:)`,
is the only `display: none` check; `Element.prepaintGroup` calls it for the
whole element and `ModifiedElement.prepaintLayer` wraps each inner layer's
registration and everything inside it.

| mutation (1224 tests) | reddened |
|---|---|
| the per-layer wrap deleted | exactly `:682`, `:683` (`:684`, `:685` since `2456c69` added two doc lines above them; re-run at `dbea8b5` by the integration checker: exactly those two) |
| `Element.prepaintGroup`'s wrap deleted | `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` `:621`, `:623`, `:630`; `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` `:755`, `:756` |

## Tests only the merged tree could hold

All in `Tests/MetalUITests/TrackInteractionTests.swift`.

### `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`

The joint test both tracks named (`EV-W` item 4, `AB-Z`), written once. Five
arms under an activated fake window, each against a control identical but for
`.disabled(true)`: clickable, focusable, adjustable (the three `EV-W` gives),
and two the composition merge adds — the `onClick` on a `ModifiedElement`'s
outermost layer and on an inner layer. Presence and role read the ungated
`handlers`; `.press` comes from the hitboxes and `isFocusable` /
`.increment` from the focus registry, so a disabled element publishes as a
disabled button/element with no actions and refuses every request. Green on
arrival. Mutations (1224 tests):

| mutation | reddened |
|---|---|
| J1 the record's `isEnabled: true` | `:154` ×3 (the three click arms), `:209` focusable, `:235` adjustable |
| J2 the whole record gated on `enabled` | `:134` (the `publishedAccessibilityTrees.last` require, "nothing published": with no record no tree is published at all, so the test stops before `:135`'s `nodes.count == 1`; re-run at `dbea8b5` by the integration checker, 1 issue) |
| J2b `enabled &&` around the synthesized terms | `:134` |
| J3 focus registration ungated | `:210`, `:211`, `:213` (focusable), `:236`–`:238` (adjustable), and lane 3's eight focus tests |
| J4 a hitbox registered when disabled | `:155`–`:157` ×3 (press accepted, handler ran), D2 ×11, D3 and 8 more lane-3 tests, and `aProposalModifierWrittenAfterAScopeSitsOutsideIt` `:105` |
| J5 `ModifiedElement`'s inner layers registering under a pushed `isEnabled = true` | `:154`–`:157` (the inner-layer arm alone) and D2's padding-frame arm `:298` |

### `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`

Where `MC-C` meets `AB-D`. A labelled click target inside a labelled chain
gains a `.padding` layer at run time (same type): the outer node keeps its id,
the wrapped node's id changes (its old element is detached and a new one
published), one node per label, the leaf still the outer node's child. A
control frame without the change republishes both ids unchanged. Pinned as it
stands. Mutations (1225 tests):

| mutation | reddened |
|---|---|
| K1 the outermost id keyed on the layer count | `:302` (outer id) and five composition tests |
| K2 inner layers register the outermost's handlers | `:284` (two "outer" nodes) and eight per-site guards |
| K3 inner id levels entered only for the innermost layer | **nothing here** — at 1 → 2 layers it still moves the leaf; a broken instrument for this test, not a gap |
| K3b no inner id levels at all | `:303` (leaf id unchanged) and 26 more issues |

### Pins added for the environment track's open items

- **`EV-Y`'s two unpinned claims** — `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne`
  gains a windowless-`Frame` arm and an unbound-`@Environment` arm, behind its
  existing `Locale.current != ''` require. The second round's mutants now
  redden: m1 (`Frame.init` roots at `windowDefault()`) `EnvironmentTests.swift:914`;
  m2 (the unbound fallback is `windowDefault()`) `:917`.
- **A `.disabled` `ScrollView` still scrolls** — `aDisabledScrollViewStillScrollsOnTheWheel`
  (`DisabledTests.swift`), pinned as it stands with a missed-wheel control
  (offset 0) and an enabled control. SwiftUI's answer is unmeasured (`EV-Q`).
  Mutation: `registerScrollRegion` returning early when disabled → `:966`.
- D12's doc comment now names the joint test; the bridge's AB-O test doc says
  it was red at the merge and why it is green.

## Counts at `2456c69`

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`: **`Test run with 1226 tests in 1 suite
passed`**, 0 `error:`, 0 `warning:`; only `regenerateAllGoldens` and
`aListsWorkIsTheSameFor100kRowsAsFor500` skipped. Default build system
(`swift test --no-parallel`, guards reading the native build's modules): 1226
passed, 0 / 0.

- Tests: 1084 (task 2) + 32 (composition) + 49 (environment) + 57 (bridge) +
  4 (integration: three in `TrackInteractionTests.swift`, one in
  `DisabledTests.swift`) = 1226. The E11 and E24 arms added no test.
- Goldens: 97; `git diff --stat f64e58a -- '*.json'` empty.
- Guards: 61 by per-file `grep -c canTypecheck` — `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `AXNodeTests` 3, `UnitSafetyTests` 2 (3 hits, one
  a comment), `ModifiedElementCompileGuards` 2; plus the declaration in
  `Typecheck.swift`. 40 use `typecheck(_:importing:)` (the 39 older and one of
  the environment's), 21 use `typecheckFile`. The integration added none.

## The demo capture: not taken; a pixel stand-in instead

**Neither release window was captured.** `ioreg -n Root -d1 -a` reported
`IOConsoleLocked` true, and a full `screencapture -x` wrote a 4112×2658
all-black PNG (the same failure every track recorded). No input was sent, the
pointer was not moved, and no demo was launched.

**Stand-in, pixels rather than scene dumps.** `git archive f64e58a` and
`git archive 2456c69` into scratch directories; in each, a generated test file
holds that tree's `main.swift` up to `runDemo()` (types prefixed `SI`, top-level
globals `nonisolated(unsafe)`) and one test that renders through a real
`Window` over `FakePlatformWindow` (1024×1024, scale 1) and writes
`fakeSurface.readPixels()`. Ten images per tree: `demoContent()` light and dark
at frame 0 and after three ticks, the modal (`showModal = true`), the animation
look settled (`animationDemoActive = true`, no transaction), and
`nativeLayoutPreviewContent()` light and dark. Debug builds.

| comparison | differing pixels |
|---|---|
| control: base light vs base dark | 1 048 576 (all) |
| control: base default vs base modal | 1 030 499 |
| control: base default vs base animation | 210 043, bbox (16, 113, 966×895) |
| base f0 vs base f3 | 0 (deterministic clock) |
| **base vs merged, all ten images** | **0** |
| instrument: merged vs merged with `ModifiedElement.paint`'s outermost fill emitted after its content | default 949 108, modal-dark 920 191, animation 949 108; **preview 0** |

**Reading.** The merged tree renders the default demo, the modal, the settled
animation look and the proposal preview byte-identical to `f64e58a` in both
themes. The instrument sees a `ModifiedElement` paint-order change in every
legacy image; it cannot see the preview (proposal path, no `ModifiedElement`),
so the preview's zero is a weaker claim. Not covered: the drawable, the
display's colour space, the real 920×560 window and AppKit appearance,
anything input-, focus-, hover- or scroll-driven, a mid-flight animation, and a
release build. **The release-window captures stay owed** (`MC-J`, `EV-P`), by
`MC-J`'s method on an unlocked session.

## Carried, not done here

- The second lane-2 bridge verifier's five test changes (`AB-AF` item 10:
  L2N03, L2N09, L2N14, L2N15/L2N15y, L2N21, L2N30, L2N33/L2N33b, L2N37 survive
  on the committed suite).
- The VoiceOver script (record §12) — nobody has run it.
- The shape-13 sweep of other test files (`MC-O` item 5).
- A shared `malloc_logger` counter; the `_wrap` hole (`MC-A`).
- Lane 1's `M2`/`M3`/`M8`/`M11` and `R4` rows in record §10 are historical:
  they mutated `FrameModifier`, deleted in `5fe5a30`; lane 2's table holds the
  current equivalents.
