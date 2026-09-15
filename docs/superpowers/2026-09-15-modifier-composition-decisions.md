# Modifier composition — decisions for plan task 3

These are the rulings for plan task 3, "Build a typed modifier-composition
foundation" (`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`). They are
written at design time, on `feat/modifier-composition` at `f64e58a`, before any
lane runs, **revised at design review** (`MC-N`), and **revised again after
lane 1's critic round** (`MC-P`, `MC-Q`). A revised ruling says so
in its heading's first paragraph and keeps what it replaced where the
replacement's reason depends on it.

Prefixed **`MC-`** and **lettered** (`MC-A`, `MC-B`, …), per this repo's
convention. **A bare `MC-3` is a typo, not a citation.** The next unused letter
is **`MC-S`**.

Read alongside:

- `docs/superpowers/specs/2026-09-15-modifier-composition-design.md`, which
  holds the three lanes, their API, files, tests and mutations;
- `docs/record/10-modifier-composition.md`, this track's record;
- `docs/probes/swiftui-modifier-identity.swift` and
  `docs/probes/swiftui-modifier-order.swift` (SwiftUI probes, output in their
  headers) and `docs/probes/modifier-composition-skeletons/` (typecheck,
  timing and allocation skeletons, output in their headers);
- `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`, whose `SA-R`
  hands this task its compile-time open proof. That doc is not edited here.

## How to read the letters

- **`MC-A`…`MC-C`** — the legacy wrapper representation and its identity
  rules. Lane 2 implements them; lane 1 writes the oracle they must match.
- **`MC-D`…`MC-F`** — the open proofs on today's code: `@State` across chained
  modifiers, the overlay identity collision, once-per-phase delegation. Lane 1.
- **`MC-G`, `MC-H`** — `SA-R`'s compile-time check: the typed native node id,
  and the one helper its defaults share. Lane 3.
- **`MC-I`…`MC-K`** — what the representation owes the rest of the framework:
  per-site guard arms, the demo, allocation. Lanes 2 and 3.
- **`MC-L`** — deferred, with owners. **`MC-M`** — method: what was measured,
  where, and what was only read. **`MC-N`** — the design review, finding by
  finding.
- **`MC-O`** — lane 1's departures from the spec, and the suite truncation its
  mutations found.
- **`MC-P`** — the overlay's identity, revised: an overlay-side id no cursor
  can produce, replacing `MC-E`'s threaded cursor. **`MC-Q`** — the critic
  round after lane 1, finding by finding.
- **`MC-R`** — lane 2's departures from the spec: two skeletons, the counts'
  base, the demo capture that could not be taken and what stood in for it, and
  a parallel-run hazard.

**Every ruling ends with a "Mutations" line reading _owed by lane N_.** The lane
that implements a ruling replaces it with the mutations it ran and the tests
each one reddened. A ruling whose line still says "owed" has not been
mutation-tested and must not be cited as proven.

## Where each number was measured

All in the worktree `/Users/maxburger/Developer/MetalUI-modifier-composition`
at `f64e58a`, one agent live in it. macOS 26.6.2 (25G83). Two toolchains are
installed: `xcrun swiftc` and `/usr/bin/swift` are Apple Swift 6.4
(swiftlang-6.4.0.33.1); PATH `swiftc` (swiftly) is Apple Swift 6.3.3
(swift-6.3.3-RELEASE).

**Design session, 2026-09-14/15:**

- **The SwiftUI identity probe**, both forms (`/usr/bin/swift`, and compiled
  with `swiftc` 6.3.3): byte-identical stdout, exit 0. The design reviewer
  re-ran the script form and matched the header byte for byte.
- **The overlay collision, end to end**, by an uncommitted scratch test
  (`scratchMeasureOverlayIdentity`, run with `--filter`, since deleted),
  through a real `Window` and `FakePlatformWindow`.
- **The one-cursor overlay fix.** It was applied temporarily and the same
  scratch test re-run. Then the **whole suite**: `Test run with 1085 tests in
  1 suite passed` (1084 committed + the scratch test), no `error:`, no
  `warning:`. The source was restored from a `cp` backup, and
  `git status --short` showed only the new untracked files.
- **The orphan-legacy-node run** (`scratchMeasureOrphanLegacyNode`, same
  scratch file, since deleted).
- **Two typecheck skeletons.** The first recording said `xcrun swiftc` 6.3.3;
  which toolchain that was is not established, since `xcrun swiftc` now reports
  6.4. `TypedNodeKit.swift` was re-run at design review under both toolchains,
  with identical results.

**Design review, 2026-09-15** (`MC-N`):

- **`chain-typecheck-timing.py`**: three wrapper designs timed at 8, 12, 16
  and 24 modifiers, with two argument spellings and a demo-shaped builder,
  under `xcrun swiftc` 6.4; cross-checked under 6.3.3.
- **`LayerBaseKit.swift`** and five clients, and **`CombinedKit.swift`** with
  the eight typed clients and one layered client, under `xcrun swiftc` 6.4.
- **`LayerAllocationModel.swift`**, at `-Onone` and `-O`, under both
  toolchains, plus a `consuming` variant.
- **`swiftui-modifier-order.swift`**, both forms (`/usr/bin/swift` 6.4 and
  `swiftc` 6.3.3): byte-identical stdout, exit 0.
- **Two uncommitted scratch test files, run with `--build-system native
  --filter` and deleted before commit:**
  - `zzScratchLegacyModifierOrder` (lane 1 test 10's numbers on today's code);
  - `zzScratchDuplicateInOneContainer`, `zzScratchOneChildTwoContainers` and
    `zzScratchOrphanLegacySubtree` (`MC-G` holes 4 and 6).

  `git status --short` was empty after each deletion.

**Critic round after lane 1, 2026-09-15** (`MC-P`, `MC-Q`), at `ec65da6`, then
`661efd9` (the overlay change, tests, probe) and `39f6237` (test 9's printable
readings); the docs commit follows. The
worktree held a paused lane-2 skeleton (uncommitted); it was saved with `git
stash push -u` plus a copy in the scratchpad before any build, and restored
after the last run. `swift package clean` before the first recorded run.

- **`swiftui-overlay-primary-shape.swift`** (the critic's arms A, B, P1-P4 plus
  controls P5 and Q), both forms: byte-identical stdout (`cmp`), exit 0,
  empty stderr.
- **`chain-solver-scope-guard.sh`**: minimum passing
  `-solver-scope-threshold` for the three designs at 8/16/24 modifiers, and the
  guard's two-module shape, under `/usr/bin/xcrun swiftc` 6.4 and PATH
  `swiftc` 6.3.3: identical numbers.
- **Whole-suite runs** (`swift test --build-system native --no-parallel`): the
  green run after the overlay change, and five mutations (`R1`-`R5`), each
  restored from a `cp` backup with `git status --short` empty and the marker
  grep empty after each.

**Lane 2, 2026-09-15** (`e9248c3` red, `5fe5a30` implementation, `49270c7`
test spelling; `MC-R`), one agent in the worktree, the display asleep and the
session locked throughout:

- **Whole-suite runs** (`swift test --build-system native --no-parallel`): the
  red run on the skeleton, the green run after `swift package clean`, and 19
  mutations run by a script (`cp` backup, one anchor replaced exactly once, a
  `// MC2-MUTATION` marker, the suite, the restore; `git status --short` and
  the marker grep empty after every run).
- **The solver-scope minimum** of the real module, binary-searched with
  `swiftc -typecheck -Xfrontend -solver-scope-threshold=N` under PATH `swiftc`
  6.3.3 against `.build/arm64-apple-macosx/debug/Modules`, and under `xcrun
  swiftc` 6.4 against a `MetalUI` built by `xcrun swift build --build-system
  native --target MetalUI` into a scratch path.
- **Type-check-time builds** with `-warn-long-expression-type-checking=100` and
  `-warn-long-function-bodies=100`: `f64e58a`'s demo, `b675451`'s tests
  (pre-lane) and this lane's demo and tests, each from a scratch copy or
  scratch path, in parallel builds (the times carry that contention).
- **The allocation test** under 6.3.3 (suite) and 6.4 (`xcrun swift test
  --no-parallel --scratch-path`, filtered).
- **An offscreen scene comparison of the default demo** in place of the window
  capture (`MC-J`, `MC-R` item 5).

**Carried, not re-taken:** the suite count 1084, 45 guards and 97 goldens at
`553b980` (plan task 2's entry). `f64e58a` differs from `553b980` in docs only.

---

# The decisions

## MC-A — legacy modifier wrappers become ONE flat type, `ModifiedElement<Content>`, reached through ONE overload per modifier: one layer per modifier, one node and one identity level per layer, and a type that does not grow along a chain

**Revised at design review (`MC-N` findings 1 and 9).** The first design
declared `padding`/`frame` on the protocols returning `ModifiedElement<Self>`,
and redeclared them concretely on `ModifiedElement` returning
`ModifiedElement<Content>`. That shape infers the flat type, but its
type-checking time is exponential in chain length (measured below). The overload
set is replaced; the representation is not.

**The choice.**

```swift
public protocol ElementGroup {                      // ElementGroup.swift, additive
    // … existing requirements …
    associatedtype LayerBase: ElementGroup = Self
    func _wrap(_ layer: ModifierLayer) -> ModifiedElement<LayerBase>
}
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public typealias LayerBase = Content
    public var content: Content
    // internal: the outermost layer inline, the rest in an array (MC-K)
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Content>   // appends
}
extension ElementGroup where LayerBase == Self {
    public func _wrap(_ layer: ModifierLayer) -> ModifiedElement<Self>      // wraps
}
extension StyledElement { func padding(_:) -> ModifiedElement<LayerBase> }  // both spellings
extension ElementGroup  { func frame(width:height:) -> ModifiedElement<LayerBase> }
```

- **A layer** (`ModifierLayer`, a public type with internal members) holds a
  `Style`, a `Decoration`, `Handlers` and an `ElementID?`. That is exactly
  what one `Box` around one child carries.
  - `.padding(_:)` makes a layer whose `style.padding` holds the edges.
  - `.frame(width:height:)` makes one centred on both axes with the given
    sizes, which is `FrameModifier.init` today.
- **One overload per modifier spelling.** Its return type is
  `ModifiedElement<LayerBase>`, and it calls `_wrap`.
  - **On a `ModifiedElement`**, `LayerBase` is its content, and `_wrap`
    appends a layer.
  - **On anything else**, `LayerBase` is `Self`, and the default `_wrap`
    wraps.
  - **In generic code**, dispatch goes through the requirement, so a generic
    `.padding` over a chain also appends.
- **`ModifiedElement`'s `style`, `decoration`, `handlers` and `elementID` read
  and write the outermost layer.** So every `Self`-returning `StyledElement`
  modifier written after a wrapper configures that wrapper, as it configures
  today's `Box<Self>`.
- **`FrameModifier` is deleted**, with its public `init(content:width:height:)`.
  No typealias is kept: `FrameModifier<FrameModifier<T>>` would name a nested
  type that is now unspellable.
- **The proposal path keeps `ModifiedContent`** (a closed enum over proposal
  content). Unifying the two is plan task 7's, after the legacy engine goes.

**Why flat, when SwiftUI nests.**

- **SwiftUI's type nests.** Probe arm T: SwiftUI's
  `Color.red.padding(4).padding(8)` is
  `ModifiedContent<ModifiedContent<Color, _PaddingLayout>, _PaddingLayout>`.
  MetalUI diverges **in type shape only**, and on purpose.
- **The plan asks for a type that does not grow.** Its task-3 text asks for a
  representation that "can nest without forcing callers to expose ever-growing
  concrete types such as `Box<Box<Box<Text>>>`".
- **The pressure is prospective, not present.** **No stored type in `Sources/`
  spells a `.padding`/`.frame` chain today** (grep). The first draft of this
  ruling cited the demo's `CounterPanel`
  (`Box<Pair<Pair<Box<Text>, Box<Text>>, Box<Text>>>`) as evidence. That type
  comes from hand-built `Box {}` calls (`main.swift:244-290`), no `.padding` is
  involved, and this design leaves it unchanged (design review finding 9).
  - **Task 4** converts `width`/`height` into layers. Every chained sizing call
    would otherwise add a type level, so chains of the lengths timed below
    become ordinary.
  - **A stored subtree** would then spell each of those levels.
- **The flat type grows once**, at the first wrapper, and never again. Every
  observable of the nested shape — identity, nodes, rects, hitbox and paint
  order, animation slots — is kept (`MC-B`).

**Measured: type-checking time** (`chain-typecheck-timing.py`, `xcrun swiftc`
6.4, `probeBody` from `-debug-time-function-bodies`). The chain is `Text("d")`
followed by pairs of `.padding(x).frame(width: x)`, over a base carrying the
real module's competing overloads (proposal `padding`/`frame`s,
`Component.padding`/`width`):

| modifiers | `Pixels(i)`: nested today | single overload (chosen) | first design | integer literals: nested | single | first design |
|---|---|---|---|---|---|---|
| 8 | 0.54 ms | 0.50 ms | 4.80 ms | 0.67 ms | 0.66 ms | 6.69 ms |
| 12 | 0.64 ms | 0.77 ms | 183.87 ms | 0.97 ms | 1.01 ms | 106.61 ms |
| 16 | 0.83 ms | 0.85 ms | **44 897.85 ms** | 1.28 ms | 1.36 ms | 1 911.60 ms |
| 24 | 1.34 ms | 1.36 ms | not run | 1.86 ms | 1.99 ms | 6 616.70 ms, then **"the compiler is unable to type-check this expression in reasonable time"** |
| demo-shaped builder | 5.87 ms | 5.95 ms | 61.84 ms | | | |

- **Under swift.org 6.3.3:**
  - single overload, 24 `Pixels`: 1.57 ms;
  - first design: 196.82 ms at 12 `Pixels`, and 1 898.56 ms at 16 integer
    literals;
  - first design at 24 integer literals: the same error.
- **The reviewer's run of the first design** read 18.6 s and then the error at
  16 `Pixels`. This run completed at 44.9 s. Same exponential, different solver
  cut-off.

**Measured: inference and reachability** (`LayerBaseKit.swift`, plain import,
Swift 6). Without a contextual type:

- `Leaf().padding(4).frame(width: 60).padding(8).width(70)` is
  `ModifiedElement<Leaf>` with 3 layers;
- a `Component`'s `.frame(width:).padding(_:)` is `ModifiedElement<Comp>`;
- an external generic group's `.frame` is `ModifiedElement<Group<Leaf>>`;
- a stored `Row<ModifiedElement<Leaf>>` typechecks;
- `Rect().frame(width: 1)` on a proposal type is still `ModifiedContent<Rect>`;
- `wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }`
  over a one-layer chain returns 2 layers;
- external conformers that never mention `LayerBase` or `_wrap` compile.

**The nested shape is unreachable:**

- `let _: ModifiedElement<ModifiedElement<Leaf>> = Leaf().padding(4).padding(8)`
  fails: "cannot assign value of type 'ModifiedElement<ModifiedElement<Leaf>.LayerBase>'
  (aka 'ModifiedElement<Leaf>') to type 'ModifiedElement<ModifiedElement<Leaf>>'";
- a generic `-> ModifiedElement<T>` fails: "cannot convert return expression of
  type 'ModifiedElement<T.LayerBase>' to return type 'ModifiedElement<T>'";
- the initializer is internal.

**Measured with lane 3** (`CombinedKit.swift`): `LayerBase` and the typed node
id coexist on one `ElementGroup`. No second associated-type restatement is
needed, and every typed client's diagnostic is unchanged.

**The hole this adds** (`layer-client-liar.swift`, exit 0). A conformer can
declare `typealias LayerBase = Leaf` and implement `_wrap` by forwarding to
another value, and its `.padding` then silently drops the receiver.

- **No access-control spelling closes it.** A protocol requirement is as
  visible as its protocol.
- **It is named and documented instead.** `_wrap` is underscored, and its doc
  says it is not for conformers.
- **Owner:** task 7, when the legacy protocols go.
- **For integration:** it goes into the holes list.

**Why not a modifier protocol (`ElementModifier`) now.**

- **The 2026-09-12 typed modifier spec proposed one.** No caller needs a
  user-defined legacy modifier, and the legacy engine is scheduled for
  deletion (task 7).
- **It would re-open a closed exposure.** A protocol whose requirements must
  reach `LayoutPass` would re-open the `LayoutNodeID` exposure that
  `LayoutModifier`'s doc comment rules out.
- **The layer's members stay internal**, so tasks 4 and 5 can add layer kinds
  (a paint-only layer, a proposal frame) without a public break.

**What it costs if wrong.**

- **Source breaks, all compile errors, none silent:**
  - `FrameModifier` spelled by name (one test file, `ComponentTests.swift`,
    plus the other tracks' spec text; see the spec's merge notes);
  - `Box<Self>` spelled as the result of `.padding` (no caller in `Sources/` or
    `Tests/`, by grep);
  - `Box`-only API after `.padding`, i.e. `.flexDirection` (no caller, by
    grep).
- **`ElementGroup` gains two requirements**, both defaulted. An external
  conformer is unaffected unless it already declares a member named
  `LayerBase` or `_wrap`.
- **SwiftUI type-shape parity is lost.** An author porting a stored
  `ModifiedContent<ModifiedContent<…>>` spelling cannot write the MetalUI one
  the same way. Nothing in MetalUI spells a legacy chain type today except the
  test above.
- **A chain's length can now vary at run time without a type change.** `MC-C`
  rules what that does and pins it.
- **The `_wrap` hole above.**
- **If the single-overload design regresses to the first design's shape**, a
  24-modifier chain's solver work goes exponential. **Revised after lane 1's
  critic round (`MC-Q` finding 3):** the first draft relied on the chain
  failing to compile, but that cut-off is a compiler time-out that varies by
  run (the reviewer's error at 16 `Pixels`; this session's success at 44.9 s),
  and a build failure takes down the whole test target rather than reddening
  one test. Lane 2 test 6 is now a **typecheck guard with a solver work
  budget** (`-Xfrontend -solver-scope-threshold`), which is deterministic,
  identical on both toolchains and about 0.1 s per fixture
  (`chain-solver-scope-guard.sh`: the chosen design needs 7n + 4 scopes in the
  model, the first design 1321 at 8 modifiers and 338 601 at 16). The guard
  carries an in-test negative — the first design's concrete overloads declared
  in the fixture file — which reproduces the blow-up against a module that has
  only the chosen design.

**Mutations:** lane 2, at `49270c7`, each a whole-suite run of 1103
(`--build-system native --no-parallel`), restored with `git status --short`
empty (record §10 has every run's summary line and issue lines).

- **Test 1's mutation**, a concrete
  `extension ModifiedElement { public func padding(_ points: Pixels) -> ModifiedElement<Self> }`,
  builds and reddens `legacyModifierChainsInferOneConcreteType`
  (`name(componentChain) → "ModifiedElement<ModifiedElement<ChainComp>>"`),
  `aNestedModifiedElementCannotBeSpelled` (the annotated negative compiles) and
  `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (the positive
  fixture now fails at 1000 with "unable to type-check"), 4 issues. So one
  extra concrete overload is already enough to leave the solver budget.
- **The first design's three overloads moved into `ModifiedElement.swift`**
  (guard 6's named mutation) reddens the guard alone: "fixture.swift:21:5:
  error: the compiler is unable to type-check this expression in reasonable
  time", positive and negative both rejected, the `#require` fails; 1 issue.
  The test target itself still built: nothing in `Tests/` or `Sources/` spells
  a chain long enough to hit the default solver limit.
- **`_wrap` replacing `outermost` instead of appending** reddens 15 tests, 29
  issues, among them test 2 and test 1 (layer counts), lane 1's tests 4, 5
  and 10, all six `MC-I` guards' inner arms, and the existing
  `chainedFramesRemainConcreteAndNestTheirLayoutNodes` and
  `chainedPaddingCreatesNestedWrappers`.

**The real module's type-check time** (spec lane 2's recorded measurement, not
a test). With `-warn-long-expression-type-checking=100` and
`-warn-long-function-bodies=100`:

- `f64e58a`'s `MetalUIDemo`: **no warning** at all.
- This lane's `MetalUIDemo`: **no warning** at all.
- This lane's tests: 44 distinct warning lines, **none of them an expression**
  containing a `.padding` or `.frame` chain (the three `expression took`
  lines are in `GeneratorTests`, `RoundingTests` and a `#expect` expansion).
  Function bodies that contain a chain and were warned:
  `aModifierChainIsIdenticalToHandBuiltNestedBoxes` 228 ms (207 ms in the
  pre-lane `b675451` build, where the chain was `Box`/`FrameModifier`),
  `everyRegisteringSiteAnimatesItsStyle` 128/136 ms (100/110 ms pre-lane; this
  lane adds an arm with two chains), `stateSurvivesFramesUnderAProposalModifierChain`
  112 ms (100 ms; a proposal chain), and two new tests with no pre-lane
  counterpart, `aGenericWrapOverAChainIsIdenticalToTheFlatChain` 184 ms and
  `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` 122 ms. Both builds ran
  parallel compile jobs, and unrelated bodies moved by similar amounts between
  them (`ThemeTests.theSubscriptReturnsEachTokensOwnProperty` 172 → 166 ms,
  `NestedClipTests` 127 → 181 ms), so **these are within the harness's
  contention, not a measured regression**. The model's expectation, none
  attributable to a chain, holds.

**Test 6's threshold, from the real module.** The positive fixture's minimum
passing `-solver-scope-threshold` is **186 under both 6.3.3 and 6.4** (the model
read 190). The guard uses **1000** (5.4×). The in-test negative fails at 500,
1000, 2000 and 5000 under both. At 1000 each fixture takes about 0.16 s. The
fallback to a build sentinel was not needed.

---

## MC-B — the flat chain, a generic `.padding` over a chain, and hand-built nested `Box`es must be OBSERVATIONALLY IDENTICAL; the hand-built boxes are the oracle, lane 1 writes it before the type exists, and every compared observation has its own disagreeing oracle

**Revised at design review (`MC-N` findings 1 and 6).** Under the first `MC-A`,
a nested `ModifiedElement<ModifiedElement<…>>` was reachable, from a contextual
type or from generic code, and had to be compared. Under the revised `MC-A`, it
is unspellable outside the module. What generic code produces instead is a flat
chain with one more layer, reached by dynamic dispatch, and that is what is
compared. The rect oracle alone could not show that the other observations can
disagree.

**The choice.** For the same modifiers in the same order, these three trees
produce the same observations:

1. the flat chain (`X.padding(4).frame(width: 60, height: 40).padding(8)`);
2. the same chain built partly in generic code
   (`func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T.LayerBase> { t.padding(8) }`
   applied to `X.padding(4).frame(…)`). Its type must EQUAL the flat chain's;
3. hand-built `Box(style:decoration:content:)` values, one per modifier, with
   the layer's style, and the layer's own `Self`-returning modifiers applied to
   that `Box`.

A **typecheck guard** pins that the nested spelling does not compile (lane 2
guard 7).

**The observations compared:**

- the wrapped element's `GlobalElementID` and bounds;
- each layer's hitbox: id, bounds, registration order;
- the scene's rects in emission order, with bounds, colour and all four corner
  radii (radii added in lane 2's verifier round, below);
- `Frame.tree.nodeCount`;
- for each layer id, `StateTable.isLive(animRetentionSlot(for:))`.

**One disagreeing oracle per observation** (practices shape 15). Each is
`try #require`d to differ from the oracle before the real comparison runs:

| observation | disagreeing oracle |
|---|---|
| rects | paddings 4 and 8 swapped |
| rects' corner radii | the padding-4 layer's radius and the outermost's exchanged; also required EQUAL to the oracle with radii zeroed |
| the inner layers' fill order | the oracle's rect list with the two inner fills (entries 1, 2) exchanged, after `try #require(oracle.rects.count == 4)` |
| ids (the wrapped element's, the hitboxes') | `.id("mid")` moved to another layer |
| the hitbox list | one layer's `onClick` dropped |
| `$anim` liveness, node count | one layer fewer |

**Why the oracle is hand-built boxes, and why lane 1 writes it.**

- **It is green on arrival.** Today's `.padding` *is* a `Box`, and today's
  `.frame` is a `Box`-equivalent (`FrameModifier`'s three phases are, line for
  line, `Box`'s). So a test comparing today's chain with hand-built boxes
  passes before any change.
- **Staying green is the migration proof.** Lane 2 then replaces the chain's
  representation, and the same test staying green shows that identity,
  `@State`, handlers and phase order were preserved.
- **The oracle cannot move with a mutation.** Its side never runs
  `ModifiedElement` code (practices shape 12).
- **Each observation's own disagreeing oracle** shows that that comparison can
  fail. The reviewer noted that swapped paddings change rects while leaving
  ids, hitboxes and liveness comparable.

**What it costs if wrong.** Without it, lane 2 could ship a representation whose
inner layers share the outer layer's id: one `$anim` slot, one hitbox id, and a
wrapped element re-seeded one level up. Every existing padding and frame test
asserts rects and node counts, and all of them would stay green.

**What "every observable" does NOT cover (added after lane 1's critic round,
`MC-Q` finding 2).** The oracle compares ids, bounds, hitboxes, rects, node
count and `$anim` liveness. It compares **nothing that `Element`'s group
defaults (`requestGroupLayout`/`prepaintGroup`/`paintGroup`) do per element**,
because a nested `Box` is an element and gets those defaults at every level,
while a `ModifiedElement` layer is not an element and gets them once for the
whole chain. On this branch those defaults do three things: enter the id,
bind `@State` and re-bind it in the later phases. Layers hold no `@State`, so
none of the three applies per layer, and the oracle loses nothing today. **The
AX-bridge track adds a fourth** (`feat/ax-bridge:Sources/MetalUI/ElementGroup.swift:130-140`,
ruling AB-O): inside `Element.prepaintGroup`, a `display: none` node's subtree
is suppressed from accessibility. A layer does not pass that check, so after
merge `Text("x").padding(4).hidden().frame(width: 60)` (the padding layer is
inner and hidden) would publish the text where nested boxes hide it, with this
oracle green. It is a merge obligation, not a change on this branch, because
the check does not exist here (spec merge notes, "AB-O and per-layer group
hooks").

**Mutations:** lane 1 done, at `6ff2d31`/`2571d4a`, each a whole-suite run of
1094 (`--build-system native --no-parallel`), restored from a `cp` backup with
`git status --short` empty after each. Test 4 is
`aModifierChainIsIdenticalToHandBuiltNestedBoxes`.

- **The four disagreeing oracles** are `try #require`d to differ inside test 4,
  on every run; the green run is their measurement.
- **`FrameModifier.prepaint` registering its handlers after its content**
  reddens test 4 alone (1 issue: hitbox order `[P8, leaf, frame]` against
  `[P8, frame, leaf]`).
- **`FrameModifier.prepaint` calling its content twice** reddens test 4 (a
  duplicate leaf hitbox) and test 7's legacy-frame and chain arms.
- **`Box.prepaint` registering after its content** reddens test 4, test 8 and
  the existing `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire`.
- **`FrameModifier.init` dropping `justifyContent = .center`** reddens test 4
  (leaf bounds, hitboxes, rects), test 10 and the existing
  `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` and
  `chainedFramesRemainConcreteAndNestTheirLayoutNodes`.
- **The equal-layer-count `$anim` oracle** (added after lane 1's critic round,
  `MC-Q` finding 6; mutations at `39f6237`, record §10 R4/R5). Test 4 builds
  the frame layer as a test-local `BoxWithoutAnimated` (`Box`'s phases minus
  `animated(_:_:for:pass:)`) and `#require`s `[true, false, true]` against the
  oracle's `[true, true, true]`.
  - `FrameModifier.requestLayout` skipping `animated` (R4) reddens test 4
    (`chain.animLive → [true, false, true]`) **and** test 5 (its per-ancestor
    `$anim` liveness), 2 issues.
  - `BoxWithoutAnimated` calling `animated` (R5) reddens test 4's `#require`
    alone (`animSkipped.animLive → [true, true, true]`), 1 issue: the
    disagreeing oracle disagrees only through the missing call.
- **A differential, not a gap to close here:** `FrameModifier`'s content cursor
  starting at 1 reddens test 5 and NOT test 4. Test 4's padding-4 layer is
  named `"mid"`, and a name replaces the index, so a cursor offset beneath a
  named layer is invisible to test 4's id observation (`MC-O` item 6).

**Lane 2's mutations** (at `49270c7`, whole suite, record §10), each reddening
lane 1's test 4 (`aModifierChainIsIdenticalToHandBuiltNestedBoxes`) and lane 2's
test 2 (`aGenericWrapOverAChainIsIdenticalToTheFlatChain`), which compare the
same observations:

- **every inner layer taking the outermost id** (7 tests, 13 issues: also
  test 5, lane 1 test 5, and the style, AX and hover-fade inner arms);
- **`.id` landing on the wrong layer** (`_wrap` moving the old outermost
  layer's name back out to the new one): tests 4 and 2 alone, 9 issues;
- **layers registered innermost-first, all before the content**: tests 4 and
  2 alone, 3 issues — lane 1's test 8 has one padding layer and cannot see a
  layer-order reversal;
- **a layer registering after everything inside it** (a `defer` around the
  registration): tests 4 and 2 and lane 1's test 8 (hitbox ids not
  `[padding, leaf]`; the in-leaf click logged `["outer"]`), 5 issues;
- **fills painted after the content**: tests 4 and 2 and test 8
  (`.surface` emitted at index 1, after `.accent`), 4 issues. **This is not
  the inner paint loop reversed** — that mutation (N8, below) was green on the
  whole suite until the verifier round;
- **inner layers skipping `animated`**: tests 4 and 2, test 5 (`P/0`'s `$anim`
  slot not live at generation 1), lane 1 test 5, and the style guard's inner
  arm, 7 issues.

**Verifier round, two holes closed** (found by the verifier's mutations at
`6d0ea97`, each of which left all 1103 tests green). Until then every oracle
chain had ONE inner layer with a background, and `RectShape` compared bounds
and colour but not radii:

- **N8, the inner-layer paint loop run innermost-first**
  (`for k in inner.indices` for `.reversed()` in `ModifiedElement.paint`): a
  deeper layer's fill lands under its container's, visibly. Pinned now by the
  padding-4 layer gaining `.background(.surfaceSecondary)`, so two inner layers
  fill. Whole suite, 1103 tests, 3 issues: `aGenericWrapOverAChainIsIdenticalToTheFlatChain`
  (flat and generic) and `aModifierChainIsIdenticalToHandBuiltNestedBoxes`,
  both at the `rects` comparison. The mutant emits 76×56 r9, **28×28 r3,
  60×40 r5**, 20×20 against the oracle's 76×56 r9, 60×40 r5, 28×28 r3, 20×20.
- **N3, an inner layer's fill painted with the OUTERMOST layer's radius**
  (`inner[k].decoration.cornerRadius` → `outermost.decoration.cornerRadius`).
  Pinned now by `RectShape.radii` (all four corners) in both oracle files and
  radii 3 / 5 / 9 on padding 4 / frame / padding 8. Whole suite, 1103 tests, 3
  issues, the same two tests: the mutant reads radii 9, **9, 9**, 0 against
  9, 5, 3, 0.

Both tests gained two disagreeing oracles for these (table above), and every
existing arm carries the same new declarations so each arm still differs from
the oracle only in what it is named for.

**The skeleton's red run** (`e9248c3`, 1102 tests, 40 issues): test 2, 14
issues (leaf id, bounds, hitboxes `[P8 36×36, leaf]` against the oracle's
three, rects, `nodeCount` 3 against 5, layer ids, `animLive` `[true]`), and lane
1's test 4, 7 issues, the same observations. Test 2's type-name and
layer-count `#require`s were green there, because the committed skeleton's
type was already flat (`MC-R` item 1).

---

## MC-C — identity: the outermost layer takes the parent's cursor slot, each inner layer is `positional(0)` (or its name) under the next one out, the content numbers from 0 under the innermost layer; a run-time change of layer COUNT resets the wrapped element's state, a change of layer VALUES does not, and a layer added at run time is ADOPTED by the new outermost layer

**Revised at design review (`MC-N` finding 5).** The first draft said "both
directions agree with SwiftUI". Only the wrapped element's reset is measured
parity. What the layers themselves do when a layer is added has no SwiftUI
counterpart, and is now named, pinned and offered as a candidate divergence.

**The choice.**

- **The ids.** For a chain of n layers:
  - `L[n-1]` (outermost) gets
    `GlobalElementID.child(of: parent, at: cursor, name: L[n-1].elementID)`;
  - `L[k]` gets `.child(of: id(L[k+1]), at: 0, name: L[k].elementID)`;
  - the content group is laid out `under: id(L[0])` with a fresh cursor at 0.

  **This is exactly the path `Box<Box<…>>` produces today**, so no state entry,
  focus slot or `$anim` baseline moves when `.padding` and `.frame` change type.
- **`.id(_:)` names the layer it follows.** `X().padding(4).id("a").padding(8)`
  names the padding-4 layer, as it names the inner `Box` today. The record §01
  remedy "name the trailing sibling" still needs `.id` outermost.
- **A layer's values are not part of its identity.**

**SwiftUI, probe `swiftui-modifier-identity.swift`:**

| arm | change between two updates | SwiftUI |
|---|---|---|
| C | every value in a three-modifier chain (padding 4→8, frame 100→120, padding 2→6) | state **kept** |
| D2 | one modifier's value 0→8, count unchanged | **kept** |
| D1 | chain length 1→2, through `if`/`else` | **new** state |
| D3 | chain length 1→2, behind `AnyView` | **new** state |
| A / B | controls: plain input change / `.id(generation)` | kept / new |

**What is parity, and what is not.**

- **The wrapped element: parity.**
  - A value change keeps the wrapped element's state, like C and D2.
  - A layer-count change resets it, like D1 and D3.

  That second direction is argued, not measured. D3 shows a reset when the
  **type** behind `AnyView` changes. SwiftUI cannot express a chain that
  changes length while keeping its type, so **no arm covers the flat
  `ModifiedElement` case itself** (`var c = X().padding(4); if flag { c = c.padding(8) }`,
  one type). MetalUI resets there because the content moves one level deeper,
  which is the structural reason D1 and D3 reset. Lane 2 test 3 pins
  MetalUI's behaviour.
- **The layers themselves: no SwiftUI counterpart.** When a layer is added at
  run time, **the new outermost layer takes over the old outermost layer's
  identity**: its `$anim` baseline, its hitbox id, and any active or focus
  state keyed on that id. The old layer's own values move one level in, to a
  fresh id.
  - **In SwiftUI**, D1 creates everything anew.
  - **In MetalUI**, `withAnimation { flag = true }` over
    `.padding(4)` → `.padding(4).padding(8)`: the padding-8 layer animates from
    4 to 8, and the new inner padding-4 layer snaps. The content therefore
    jumps from 4 to 8 at t = 0 and then slides to 12. That is predicted by
    reading, and lane 2 test 5 measures and pins it.
  - **Why it is kept.** The alternative, keying the outermost id on the layer
    count, breaks `MC-B`'s identity with nested boxes, and so re-seeds every
    padded element's state on the change of type. It is the same adoption rule
    as record §01's trailing sibling, applied to layers.
  - **For integration:** a **candidate divergence**, "a layer added to a chain
    at run time is adopted by the new outermost layer (no SwiftUI analogue)",
    for CLAUDE.md's table.

**What it costs if wrong.**

- **If a later change keys a layer's id on its values** (for instance, to let a
  frame change "look like" a new view), an animated `.padding(open ? 16 : 8)`
  resets its content's `@State` on every toggle, with no diagnostic.
- **If it keys content identity on the outermost layer only**, adding a layer
  at run time silently keeps state that the structure says should reset.
- **If the adoption is mistaken for SwiftUI's behaviour**, an author expects a
  fresh layer and gets an animation from the old layer's baseline.

All three are pinned (spec, lane 2 tests 3, 4 and 5).

**Mutations:** lane 2 (at `49270c7`, whole suite, record §10).

- **Measured, replacing the prediction:** test 5 read x = **8 at t = 0, 10 at
  t = 0.5, 12 settled**, `P`'s `$anim` slot live at both generations, `P/0`'s
  not live at generation 0 and live at generation 1, taps reset to 0 — the
  predicted values exactly. The candidate divergence stands as written.
- **Content laid out under the outermost id** (`requestGroupLayout(under:
  id, …)`) reddens test 3 (the content's grandparent is not the old parent;
  taps read 3), test 5 (taps 3), lane 1's test 5 (the leaf's third ancestor is
  missing), tests 4 and 2, and the style guard's inner arm (`start.inner`
  reads 4 but the halfway value is not 12; by reading, the wrapped `Box`'s id
  then equals the inner layer's, so the two share one `$anim` slot), 17
  issues. On the skeleton,
  test 3 read 3 and test 5 read x 4, 6, 8.
- **An unnamed inner layer named by its style**
  (`ElementID("\(inner[k].style.padding)")`) reddens test 4 (taps 0), test 5,
  lane 1's test 5 (a `.named("Edges<Length>(…)")` component), tests 4 and 2,
  the style and AX inner arms, and the allocation test (the interpolated
  string allocates: +63 500 and +126 500 over nested per 500 builds), 17
  issues.
- **The outermost layer's id keyed on the layer count**
  (`elementID ?? ElementID("\(layerCount)")`) reddens test 5 at its
  betweenness `#require` ("min(start, end) < mid → false": the snap), test 3,
  lane 1's test 5 and tests 4 and 2, 12 issues.
- **The instrument's check:** `setNeedsRedraw()` moved out of the
  `withAnimation` body reddens test 5 alone, at the same `#require`, 1 issue.


---

## MC-D — `@State` across chained modifiers is proven on BOTH paths, with the wrapped element inside a proposal container on the proposal path so that lane 3's typed entry point is the one exercised

**The choice.** Two end-to-end tests through a real `Window`:

- **legacy:** a stateful `StyledElement` leaf under
  `.padding(4).frame(width: 60, height: 40).padding(8)` in a `Row`, clicked
  three times, then two more frames. It reads 3. Its id is three levels below
  the chain's slot, and all three layer ids hold a live `$anim` slot, so the
  two chained modifiers are two identities with distinct retention slots;
- **proposal:** inside an `HStack`, three children:
  - a stateful proposal leaf under `.padding(…).frame(…).background(…)`,
    clicked three times, which reads 3 with its id three `ModifiedContent`
    levels deep;
  - an unmodified stateful sibling, which reads 0;
  - a stateful proposal `Component`, clicked twice, which reads 2.

**Why "inside an `HStack`".**

- **The typed path is the one at risk.** After lane 3, a proposal container
  reaches its children through the typed requirement. Its defaults for
  `ProposalElement` and for `Component` must bind state and advance the cursor.
  Since design review they do that through the helper `MC-H` names.
- **A test elsewhere would miss it.** With the stateful leaf at the root, or
  under a legacy container, it would reach the untyped entry instead, and a
  typed default that skipped the helper would go unseen.
- **The sibling** is there so that a missing `cursor += 1` (two siblings on one
  id) is visible too.

**What it costs if wrong.**

- **The proofs are open.** The plan lists "No test checks `@State` across
  chained modifiers" as an open proof. The typed-modifier spec's first required
  proof is "two chained modifiers have two structural identities and preserve
  distinct `@State` slots".
- **Without the proposal-container placement**, lane 3 could drop state
  binding for every proposal element in a container. The demo's
  `PreviewToggle` would stop toggling, with the suite green.

**Mutations:** lane 1 done, at `6ff2d31`, whole suite (1094) per mutation:

- `FrameModifier.requestLayout`'s content cursor starting at 1 reddens
  `stateSurvivesFramesUnderALegacyModifierChain` (1 issue: padding 4 reads
  `.positional(1)`);
- `ModifiedContent.requestLayout`'s cursor starting at 1 reddens
  `stateSurvivesFramesUnderAProposalModifierChain` (3 issues: the leaf, the
  padding and the frame each read `.positional(1)`).

Neither mutation changes a `taps` reading: a cursor offset moves an id
consistently across frames, so the state still accumulates. The id
assertions are what see it. Lanes 2 and 3 owe their own.

---

## MC-E — `OverlayModifier` threads ONE cursor through primary and overlay, as `Pair` does; the collision is measured end to end first, and the fix is one line

**SUPERSEDED IN ITS CHOICE by `MC-P`** (after lane 1's critic round, `MC-Q`
finding 1). The measurement of the collision below stands. The threaded cursor
does not: a SwiftUI probe with controls shows an overlay keeps its state
through a flip of its primary's shape, where the threaded cursor reset it.
Two claims below are **struck**: "MetalUI after the fix agrees" (it agreed only
on arms E-G, none of which changes the primary's shape) and the remedy "name
the overlay's element" (proposal content has no `.id()` until task 12, so it
could only be taken by wrapping the overlay in a `Component` that declares
`elementID`). The rest is kept as the record `MC-P`'s reasons depend on.

**Measured before any change (scratch test through a real `Window`).**
`ZStack { Leaf(60).overlay(alignment: .topLeading) { Leaf(10) } }` in a
100×100 window. Each leaf:

- holds `@State var taps`, and registers its own `onClick` that increments it;
- logs its id in prepaint and its taps in paint;
- fills its bounds when `pass.isHovered(id)`.

The readings:

- **The two ids compared equal** (`equal=true`).
- **Three clicks at (70, 70)**, over the primary only: the primary read **3**,
  and the overlay, never clicked, read **3**.
- **The pointer at (70, 70):** **two** hover fills were painted, 60pt and 10pt
  wide. The overlay drew its hover affordance with the pointer 40pt away.

**With `overlay.requestGroupLayout(under: id, at: &contentCursor, …)` applied:**

- the ids were unequal;
- the primary read 3 and the overlay **0**;
- **one** hover fill was painted, 60pt;
- the whole suite with only that change: **1085 passed** (1084 + the scratch
  test). No existing test depends on the collision.

**The choice.** One cursor: the primary's elements take indices from 0, the
overlay's continue where the primary's stopped. This is `Pair`'s rule and every
legacy container's ("Legacy containers thread one cursor through the whole
group", record §09 hazard 3).

**Alternatives rejected.**

- **A reserved name for the overlay slot** (`.named("$overlay")`).
  - **For:** it would keep the overlay's index independent of the primary's
    shape, avoiding the shift below. (`MC-P` takes that property by another
    spelling.)
  - **Against:** it would be an eighth reserved name. CLAUDE.md records seven,
    none guarded against a user `.id` that describes to one
    (`theSevenRetentionSlotsAreMutuallyDistinct` covers retention slots only).
  - **Verdict:** not worth a new unguarded collision. Lane 1 test 9 uses this
    alternative as its mutation.
- **An intermediate id per side** (`EitherGroup`'s shape) moves the primary one
  level deeper. That re-seeds the state of every overlaid primary, the demo's
  preview included.

**The index stability cost, restated at design review (`MC-N` finding 11).**
The first draft argued, by reading, that a primary which renders at all always
consumes the same number of indices. **That is false.**

- **The counterexample.** A `Component` whose content is empty consumes one
  index and contributes zero nodes. So a primary block
  `{ if flag { EmptyProposalComponent() }; Rectangle(…) }` has one node either
  way, and satisfies the one-node precondition, but consumes 2 indices or 1.
  When `flag` toggles, the overlay's index moves between 2 and 1. Its state is
  then read from a different entry: fresh, or retained from earlier (divergence
  18).
- ~~**This is not a defect of the fix.** It is the trailing-sibling rule of
  record §01 applied to an overlay, and every legacy container already behaves
  so.~~ **Struck (`MC-P`):** the trailing-sibling rule governs siblings in ONE
  container; SwiftUI does not apply it across a primary and its overlay, which
  are separate positions.
- **Lane 1 test 9 pins it.** Its readings are predicted by reading and replaced
  by the measured ones.
- ~~**Remedy for authors:** the same as record §01's. Keep the primary's
  index-consuming shape fixed, or name the overlay's element.~~ **Struck
  (`MC-P`).**

**SwiftUI, same probe.**

- **Arms E (overlay), F (background) and G (two-view primary)** each give the
  attached view its own state, distinct from the primary's and kept across an
  update.
- **H (two `HStack` siblings)** is the control for "distinct".
- ~~**MetalUI after the fix agrees.**~~ **Struck (`MC-P`):** it agreed on E-G,
  which never change the primary's shape; it disagreed on the shape flip
  `swiftui-overlay-primary-shape.swift` measures.
- **No arm can show shared state**, since SwiftUI never shares it here, so the
  instrument's "same" reading comes from arm A, across time.

**What it costs if wrong.** Before the fix, the demo preview's `PreviewToggle`
and anything overlaid share hover, press dispatch, `@State`, `ScrollState` and
`$anim` between primary and overlay. The preview does not show it only because
its overlay `Rectangle` holds no state and registers no hitbox.

**Mutations:** lane 1 done. The fix is `6ff2d31`; the red run is `6d89906`.
**These are lane 1's runs against `MC-E`'s design, kept as record.** Since
`MC-P` (`661efd9`), test 9 is `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`,
tests 1 and 9 pin the overlay-side id, and the threaded cursor below is
mutation R1; `MC-P` has the current runs.

- **Red run** (the tests at `6d89906`, before the fix; whole suite: `Test run
  with 1094 tests in 1 suite failed after 25.299 seconds with 11 issues`),
  reddening exactly the four overlay tests:
  - `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`: "Expectation
    failed: (primary → MetalUI.GlobalElementID) != (overlay →
    MetalUI.GlobalElementID)", plus both index-1 assertions;
  - `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`: "(log.taps["overlay"]
    → 3) == 0", then primary 4 and overlay 4 after the overlay's click;
  - `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay`: "(hoverFillWidths() →
    [60.0, 10.0]) == ([60] → [60.0])", and the same two fills at (25, 25);
  - `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed`: all three
    readings `positional(0)`, 3 taps, index-2 slot not live.
- **The fix, whole suite:** `Test run with 1094 tests in 1 suite passed`.
- **The second cursor restored as a mutation** on the fixed tree reproduces the
  red run exactly (11 issues, the same four tests).
- **The rejected alternative as a mutation** (the overlay laid out under a
  reserved `.named("$overlay")` id with its own cursor) reddens
  `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities` (index 0 in both
  arms) and `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed` (index 0 and
  3 taps at all three steps — the state kept across the flip). Tests 2 and 3
  stay green under it, since its ids are still distinct: the differential is
  that only tests 1 and 9 see WHERE the overlay's identity comes from.
- **Test 9's readings, measured on its first run after the fix, equal the
  prediction:** `(positional(2), 3 taps, index-2 slot live)`, then
  `(positional(1), 0, not live)`, then `(positional(2), 3, live)`.

---

## MC-F — once-per-phase delegation is pinned for EVERY wrapper at once, by a counting leaf whose instrument is first shown able to read 2

**The choice.** One test, one arm per wrapper. Each arm renders one frame with a
counting leaf (legacy or proposal, as the wrapper requires) and expects exactly
one `requestLayout`, one `prepaint`, one `paint`. The arms:

- **legacy:** `.padding`, `.frame`, a three-modifier chain, and a `Component`'s
  distributing `.padding` (`StyledComponent`);
- **proposal `ModifiedContent`,** one arm per distinct code path in its phases:
  - a node-registering case (`frame`);
  - `flexibleFrame`, `padding`, `fixedSize`, `aspectRatio`, `layoutPriority`;
  - the passthrough `background` and `border`;
  - `opacity` (paint closure);
  - `clip` (closures in both phases);
  - `allowsHitTesting(true)` and `(false)` (prepaint closure);
- **`OnTapModifier`;**
- **`OverlayModifier`,** the counting leaf on the primary side and, separately,
  on the overlay side;
- **the builder wrappers** `ProposalFrame`, `Padding`, `Background`, `FixedSize`.

**The control arm:** `Pair(leaf, leaf)` under a `Row` reads 2 in each phase.
Without it, an instrument that counted per type rather than per call would pass
every arm (practices shape 15). Counts are `try #require`d before any per-phase
indexing (shape 13).

**Phase order** is a second, small test. For
`leaf.background(.accent).onClick(inner).padding(4).background(.surface).onClick(outer)`:

- `lastHitboxes` lists the outer layer before the leaf;
- the scene emits the surface rect before the accent rect;
- a click in the padding ring runs `outer`;
- a click inside the leaf runs `inner`.

**Why one test over many.** It is `onClickIsLiveOnEveryConformerThatCanRegisterOne`'s
footing: a new wrapper that forgets a phase is an API that compiles and
misbehaves, and only a per-wrapper list can see it. A wrapper added later
without an arm is a gap a reader can find in one place.

**What it costs if wrong.** Today `ModifiedContent.prepaint`'s
`allowsHitTesting` and `clip` branches call `content.prepaintGroup` inside a
closure and force-unwrap the result (`result!`). A refactor that calls it twice,
or not at all, would double-register or drop every hitbox below. The plan
records "No test checks once-per-phase delegation" as open.

**Mutations:** lane 1 done, whole suite (1094) per mutation, test 7 being
`everyModifierWrapperDelegatesEachPhaseExactlyOnce` and test 8
`aModifierChainRegistersAndPaintsOuterLayersFirst`:

| mutation | commit | reddens (arm and reading) |
|---|---|---|
| `allowsHitTesting` branch calls `prepaintGroup` twice | `6ff2d31` | test 7: `allowsHitTesting(true)` and `(false)`, each `[1, 2, 1]` |
| `clip` paint branch loses its `else` | `6ff2d31` | test 7: `clip` `[1, 1, 2]` |
| `OverlayModifier.paint` skips `overlay.paintGroup` | `2571d4a` | test 7: `overlay, overlay side` `[1, 1, 0]`; tests 2, 3 and 9 (the overlay never logs); the existing `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt` |
| `FrameModifier.prepaint` calls its content twice | `6ff2d31` | test 7: `legacy frame` and `legacy three-modifier chain`, each `[1, 2, 1]`; test 4 |
| `Box.prepaint` registers after its content | `2571d4a` | test 8: hitbox order and the in-leaf click (ran `outer`); test 4; the existing `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` |

**The overlay-paint mutation first truncated the suite** (at `6ff2d31`: no
summary line, "Fatal error: Index out of range"). The existing
`nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt` indexed
`rects[1]` after its `#expect(rects.count == 2)` failed (practices shape 13).
`2571d4a` makes that count, and the same shape in three sibling tests, a
`try #require`, and the row above is the re-run (`MC-O` item 5).

The control arm reads `[2, 2, 2]` on every run. Lane 2's mutations are owed by
lane 2.

---

## MC-G — `SA-R`'s compile-time check is DELIVERED: a typed `ProposalNodeID` with an internal initializer, returned by a new requirement on `ProposalElementGroup`; five lies become compile errors, and seven named holes stay, each pinned or cited

**Revised at design review (`MC-N` findings 7 and 8).** Two changes:

- **The hole list was incomplete.** Holes 4 (measured), 5 and 6 (measured) are
  added.
- **Hole 1's guard could not show that it runs.** It gains an in-test
  negative.

**The choice.**

```swift
public struct ProposalNodeID: Hashable, Sendable {
    public let layoutNodeID: LayoutNodeID
    init(_ id: LayoutNodeID)                       // internal
}

public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                             at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}

public protocol ProposalElement: Element, ProposalElementGroup {
    associatedtype LayoutState          // restated: required, see below
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}
// defaults: ProposalElement supplies requestLayout (untyped, for Frame's root
// and legacy containers) and requestProposalGroupLayout; Pair, OptionalGroup,
// ArrayGroup and EmptyGroup implement it conditionally; Component supplies it
// `where Content: ProposalElementGroup`. Both typed group defaults enter the
// member's identity through MC-H's helper.
```

Every public `LayoutPass.requestNative*` registrar returns `ProposalNodeID` and
takes `ProposalNodeID` children. Proposal containers and wrappers call
`requestProposalGroupLayout`, never `requestGroupLayout`.

**Measured, skeleton `TypedNodeKit.swift` + clients, plain import, Swift 6**
(re-run at design review under both toolchains, identical):

| client | what it tries | result |
|---|---|---|
| `honest` | a leaf, a container over a `Pair`, a `Component` retro-conformed | exit 0 |
| `liar1` | today's liar: `Element` + marker, legacy node, no typed entry | `type 'Liar' does not conform to protocol 'ProposalElementGroup'` |
| `liar2` | mint a typed id from a legacy node | `'ProposalNodeID' initializer is inaccessible due to 'internal' protection level` |
| `liar3` | a `Component` whose content is legacy, retro-conformed | `type 'LegacyComp' does not conform to protocol 'ProposalElementGroup'` |
| `liar5` | legacy content in a proposal container | `generic struct 'ProposalFrame' requires that 'Legacy' conform to 'ProposalElementGroup'` (true today too) |
| `opaque` | a `Component` with `var content: some ElementGroup`, retro-conformed | `type 'OpaqueComp' does not conform to protocol 'ProposalElementGroup'` |
| `opaqueOK` | the same with `some ProposalElementGroup` | exit 0 |
| `liar4` | a group writing both entry points: legacy nodes from one, zero typed nodes from the other | **exit 0** |
| `opaqueOK`'s `Both` | a `ProposalElement` that also overrides the untyped `requestLayout` | **exit 0** |

`CombinedKit.swift` repeats all nine with lane 2's `LayerBase` added: same
results.

**A finding the design depends on.** Without restating `associatedtype
LayoutState` in `ProposalElement`, the skeleton module itself fails to build:
`error: type 'Leaf' does not conform to protocol 'Element'`. Swift does not
infer `Element.LayoutState` through the default `requestLayout` that
`ProposalElement`'s extension supplies.

**What stays open, precisely.** Seven holes (hole 7 added after lane 1's critic
round, `MC-Q` finding 8). None is closed by an access-control or type-system
check available in this design.

1. **Two entry points can disagree** (`liar4`, `Both`).
   - **Where it can hurt.** The untyped entry is reached only by `Frame`'s root
     and by legacy containers, and a proposal element under a legacy container
     already traps (`SA-G`). A proposal element that lies there is therefore
     harmful only as a root, where it renders as the legacy element it
     registers.
   - A typed entry that returns the wrong *count* still trips the one-node
     wrapper preconditions.
   - **Pinned wrong on purpose** by a guard (spec lane 3, guard 6) that holds a
     positive fixture (the liar compiles) and an in-test negative (the liar
     minus its typed entry does not), and `#require`s that they disagree. So a
     skipped or broken instrument cannot read as the hole being open.
   - **Its post-landing red run:** delete the positive fixture's typed entry.
2. **A side-effect legacy NODE is invisible to the type.** Measured on today's
   code (scratch test): an element whose `requestLayout` calls
   `pass.requestNode(style: Style(), children: [])`, discards the result and
   returns a native leaf. Rendered inside `VStack { HStack { it }; Rectangle }`,
   it did not trap. Its prepaint saw 10×10, and the scene held 1 rect. The
   orphan legacy node is never attached. Pinned wrong on purpose (spec lane 3,
   test 7 arm a).
3. **`unsafeBitCast`**, and `@testable` code calling the internal initializer.
   - **Out of reach of any access-control check.**
   - **The backstop:** the run-time traps from `SA-G`.
   - **The existing liar trap test** is rewritten to mint its id through
     `@testable`, so the trap stays pinned.
4. **One typed id can be used twice. Measured at design review** (scratch
   tests, untyped ids, which a `ProposalNodeID` wraps unchanged). `appendNode`
   checks only the generation (`LayoutTree.swift:146-155`). In
   `VStack { HStack { it } }` at 140×90:
   - **one leaf listed twice** in one horizontal linear stack:
     - no trap;
     - the stack reserves both slots, (60, 0, 20×10);
     - the leaf is placed once, at the **second** slot, (70, 0, 10×10);
     - measure calls: 1; `nodeCount`: 4;
   - **one leaf handed to two frames** (30×30 top-leading, 50×50
     bottom-trailing) in one stack:
     - no trap;
     - the stack is (30, 0, 80×50);
     - the leaf is drawn where the **last** placement puts it, (100, 40, 10×10);
     - the first frame's slot is empty;
     - measure calls: 2; `nodeCount`: 6.

   A type with an internal init constrains who mints an id, not how often it is
   used. Pinned wrong on purpose (spec lane 3, test 8).
5. **A legacy style modifier on a proposal `Component` still compiles.**
   `Toggle().width(Pixels(70))` gives `StyledComponent<Toggle>`, a plain
   `ElementGroup`, so lane 3's requirement never applies to it. Inside a legacy
   container it still traps at `setStyle`. That is `SA-R`'s second run-time
   trap, pinned today by
   `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, which stays.
   Owner: task 5 (`Component` distribution).
6. **A side-effect legacy SUBTREE is invisible to the type, and it is not
   inert. Measured at design review** (scratch test). The element's
   `requestLayout` lays out a discarded `Box { StatefulLegacyLeaf() }.background(.accent)`
   through `requestGroupLayout(under: id, at: &c)`; the leaf writes its `@State`
   from 7 to 8 during layout. The element then returns a native leaf. In
   `VStack { HStack { it } }`:
   - no trap;
   - the leaf's `$state0` slot reads **8** and is **live**, so it is bound and
     marked;
   - the orphan `Box`'s `$anim` slot is **live**;
   - **0** rects (nothing of the subtree is painted);
   - `nodeCount` 5 (2 orphan nodes).

   So an orphaned registration keeps state entries alive and animation
   baselines moving for elements that never paint. Pinned wrong on purpose
   (spec lane 3, test 7 arm b).
7. **A typed id can be stored and returned in a later frame.** `ProposalNodeID`
   is `Hashable, Sendable` and storable, so a conformer can cache one from an
   earlier frame and return it or pass it to a registrar. The type check
   passes. **The backstop is a run-time trap, not a compile-time check**, by
   reading: every `Frame` builds a `LayoutTree` with a fresh generation
   (`Frame.swift:1049`, ruling C-3), and every registration's children pass
   through `LayoutTree.slot`, whose precondition rejects an id from another
   generation ("the id outlived the tree that issued it",
   `LayoutTree.swift:560-567`). Pinned at the kernel today by
   `adoptingAChildFromAnotherTreeTraps` (`LayoutTreeTests.swift`); lane 3 pins
   it end to end through a native registrar with an exit test (spec lane 3,
   test 9).

**Why deliver it here, when `SA-R` feared a second entry point.** `SA-R`
deferred it because a second, typed entry point is "a change to how elements
compose". That is this task. The skeleton shows the second entry point costs
conformers nothing: a proposal element writes only `requestProposalLayout`, and
the untyped `requestLayout` comes from the default.

**What it costs if wrong.**

- **Every proposal element's layout signature changes once.** A grep at
  `f64e58a` counts 35 conformances:
  - 20 in `Sources/MetalUI`: four builder groups and 16 element types, 13 of
    them in `ProposalElementGroup.swift`;
  - 2 in the demo;
  - 10 test helpers;
  - 3 guard fixtures.

  The eleven public registrars and `requestNativeLayout` change with them.
- **An external author who retro-conformed a `Component` with
  `var content: some ElementGroup`** gets a compile error and must write
  `some ProposalElementGroup`. The demo's `PreviewToggle` is one such author.
- **The environment track's `EnvironmentScope` proposal conformance** stops
  compiling at merge. Its typed entry must wrap layout in `withEnvironment`, or
  layout-time reads fall back silently. The spec's merge notes name the
  integration test.
- **If the holes above are later mistaken for closed**, a lying conformer that
  compiles is again a run-time trap (holes 3, 5 and 7), or, for holes 4 and 6,
  silently wrong output. They are named here and pinned so they cannot be.

**Mutations:** owed by lane 3.

---

## MC-H — the identity entry for a group member lives in ONE internal helper that the untyped `Element` default and both typed defaults call; `Element.swift` and `Component.swift` are not edited; the registrars change IN PLACE rather than gaining typed twins

**Revised at design review (`MC-N` finding 2).** The first draft copied
`GlobalElementID.child`, `StateBinder.bind` and `cursor += 1` into the two typed
defaults, leaving `ElementGroup.swift` untouched. The environment track changes
`StateBinder.bind`'s signature at "the five call sites" it knows. Two copies it
does not know about would make seven — the "second thing to go missing from
the copy" hazard, arriving on the first parallel track.

**The choice.**

- **`Sources/MetalUI/GroupMember.swift` (new, internal)** holds one helper:
  `GlobalElementID.enteringGroupMember(_:name:under:at:pass:)`. It does
  `child(of:at:name:)`, then `StateBinder.bind`, then `cursor += 1`, and returns
  the id. Its doc names every caller and the one remaining copy.
- **`ElementGroup.swift`, one localized edit.** In `Element`'s default
  `requestGroupLayout`, the three lines become one call to the helper. The
  `prepaintGroup`/`paintGroup` re-binds are a different job (re-pointing a
  shared box), and they stay where they are.
- **`Sources/MetalUI/ProposalNodeID.swift` (new)** holds `ProposalNodeID`,
  `ProposalElement` and its two defaults, and the
  `extension Component where Content: ProposalElementGroup` default. Both typed
  defaults call the helper.
- **`Component.swift` is not edited.**
  - **Its untyped default keeps its own three lines**, the one copy left. It
    is interleaved with a page of mutation history that names those exact
    lines.
  - **Its bind and its `cursor += 1`** are already pinned by
    `aComponentsOwnStateSurvivesAcrossFrames` and
    `twoSiblingComponentsHoldIndependentState`.
  - **The helper's doc says so**, so a reader changing the helper finds the
    copy.
- **`ProposalElementGroup.swift`** gains the requirement, and the builder
  groups' conditional implementations beside their existing conditional
  conformances.
- **`Passes.swift`** changes only the registrar block's parameter and return
  types (lines 55–150 at `f64e58a`). `Frame`'s internal registrars stay
  untyped.

**Why a helper, at the cost of a shared-file edit.**

- **The copy is the known hazard.** `AnyElement`'s default already lost its
  bind and then its cursor advance, each unguarded until found.
- **A signature change would be loud; other changes would not.** A copy
  survives a change that alters behaviour without altering the signature, and
  that is exactly how `AnyElement`'s went missing.
- **The helper keeps the bind call sites at five.** The environment track then
  edits those five and no more. The conflict at `ElementGroup.swift:112` is
  textual, and the helper's stale bind is a compile error, so neither half of
  the merge is silent.
- **The shared-file edit is three lines to one**, inside one function body.

**Why the registrars change in place, not as typed twins.** Three tracks run in
parallel and merge afterwards, and `Passes.swift` is a named shared file.

- **Twins would be additive**, keeping the untyped registrars.
- **They would also leave inert public API:** eleven public untyped native
  registrars with no caller in `Sources/`, minting native nodes that no
  proposal element can use. That is a declared-but-inert row by construction.
- **Changing the types in place** is a localized edit to one block.

**What it costs if wrong.**

- **The helper becomes a single point** that both engines' state binding runs
  through. A mistake in it breaks legacy and proposal `@State` together. That
  is loud, and it is the reason for the helper.
- **`Component.swift`'s copy can still drift from the helper.** It is bounded
  by the two existing Component tests, and named in the helper's doc.
- **The helper is bounded by four mutations**, each of which must redden a
  named test, all carried by `MC-D`'s proposal test (and, for the first, the
  legacy `@State` tests):
  1. delete the helper's bind;
  2. `ProposalElement`'s typed default bypasses the helper;
  3. `Component`'s typed default bypasses the helper;
  4. delete the helper's `cursor += 1`.

**Mutations:** owed by lane 3.

---

## MC-I — `ModifiedElement` is a registering site in both phases and gets an arm in all six per-site guards, each arm exercising an INNER layer as well as the outermost; every per-site list that named `FrameModifier` changes its arm, never deletes it

**The choice.** Arms for a two-layer chain are added in place to:

- `everyRegisteringSiteAnimatesItsStyle` and
  `everyBackgroundPaintingSiteAnimatesItsColour` (`AnimationTests.swift`);
- `everyBackgroundPaintingSiteHonoursHoverAndFocus` and
  `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`
  (`BackgroundChainTests.swift`);
- `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`);
- `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
  (`AXEmitSiteTests.swift`).

**Added at design review (`MC-N` finding 3): the other tracks' lists.** Two
parallel tracks name `FrameModifier` as a site:

- the environment track's D2
  (`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, arm "frame");
- the AX-bridge spec's scope boundaries (an in-scope emit site, "untouched").

The rule for integration: **each such arm becomes a `ModifiedElement` arm over
a two-layer chain, asserting on the inner layer too, and is never deleted.** A
deleted arm would silently drop the only per-site coverage the list had for
`.frame`.

**Why the inner layer.** The likeliest wrong implementation of a flat chain
wires the outermost layer — the one `StyledElement`'s accessors reach — and
forgets the loop. An arm on a one-layer chain would pass it.

**Why in place, in shared-ish files.**

- **The guards' value is one list.** CLAUDE.md's Animation section: "A site
  that skips its helper is silently unanimated with no diagnostic; the two
  per-site guards are …".
- **The debt transfers.** Record §09 already lists `FrameModifier` arms in five
  of these guards as owed, and `FrameModifier` is replaced by this type.
- **The conflict cost is textual.** Each arm is one additive block, so a merge
  conflict is textual at worst. The spec's merge notes name the two files that
  other tracks also extend.

**What it costs if wrong.** Without the arms, `ModifiedElement`'s `animated`,
`animatedBackground` and `registerHandlers` calls could each be deleted with the
suite green, the demo sidebar's width animation among them (it lives on a
padding wrapper). Record §09 says so of `FrameModifier` today, by reading.

**Mutations:** lane 2 (at `49270c7`, whole suite, record §10). Every arm was
red on the skeleton for its inner layer (`e9248c3`): the style arm read
`start.inner` as the leaf's padding; the colour arm found no rect; both
`BackgroundChainTests` arms found no 40×40 rect; the click arm logged `[]`; the
AX arm emitted no node under the inner layer's id. The outermost arms were
green there, as the likeliest wrong implementation would leave them.

- **Inner layers skip `animated`**: the style arm's INNER expectation
  (`start?.inner == .pixels(4) → false`), plus tests 4, 2 and 5 and lane 1's
  test 5; the outermost expectation stays green.
- **Inner layers resolve their background token directly instead of calling
  `animatedBackground`**: `everyBackgroundPaintingSiteAnimatesItsColour` (the
  inner arm reads the target at t = 0 and at t = 0.5),
  `everyBackgroundPaintingSiteHonoursHoverAndFocus` (the inner layer paints
  `.surface` while focused or hovered) and
  `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour` (no active
  animation, no mid-flight colour), 15 issues, every one on an inner arm.
- **Inner layers skip `registerHandlers`**: `onClickIsLiveOnEveryConformerThatCanRegisterOne`
  (`["modified inner layer"]` expected, `[]`),
  `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` (the inner
  node is not emitted), and both `BackgroundChainTests` guards (0 hitboxes),
  plus tests 4 and 2, 7 issues.
- **Layer styles minted outermost-first** reaches the arms too (the style
  arm's inner and outer expectations, the AX arms' frames, both
  `BackgroundChainTests` guards), as well as lane 1's test 10 (O1 76×76, O2
  60×60: swapped), `chainedFramesRemainConcreteAndNestTheirLayoutNodes`,
  test 5 and the allocation test, 25 issues.


---

## MC-J — the demo: the default window must not change pixel-for-pixel apart from desktop corners, compared against a build of `f64e58a` itself; lane 3 edits two preview declarations; no look is claimed for the preview

**Revised at design review (`MC-N` finding 12).** The first draft took the
baseline "at the lane's start commit" and argued, by reading, that it equals
`f64e58a`'s. The baseline is now built from `f64e58a` directly.

**The choice.**

- **The baseline build.** `git archive f64e58a | tar -x -C <scratchpad>/mc-base`,
  then `swift build -c release` in that directory.
  - It is a plain directory, not a worktree, so no other checkout is touched.
  - The archive keeps the shader-header symlink.
  - Lanes 2 and 3 compare against this one build.
- **The capture method** is record §03's of 2026-09-14, used for both the
  baseline and each lane's release build of this worktree:
  - launch `MetalUIDemo`, and wait for the first frame;
  - find the window through `CGWindowListCopyWindowInfo`'s bounds;
  - `screencapture -x -R<x,y,w,h>`;
  - **no input sent, pointer not moved**, and the pointer position logged
    first, since a pointer over a list row changes its hover colour;
  - compare every pixel.

  Record §03's accepted difference: a few dozen pixels at x ≤ 8, y ≤ 46 (the
  desktop behind the rounded corner).
- **Lane 2** captures the default window.
- **Lane 3** repeats the default-window capture, since it rebuilds every
  proposal type the preview uses. It also captures the preview window
  (`METALUI_NATIVE_LAYOUT_PREVIEW=1`) from the same two builds.
- **Lane 3 edits the demo's preview** as `MC-G` forces:
  - `PreviewToggle.content` becomes `some ProposalElementGroup`;
  - `PriorityPreviewPanel` conforms to `ProposalElement`, with a typed
    `requestProposalLayout`.

  That is a regression check, not the human look that record §09 says the
  preview has never had.

**What it costs if wrong.** The 2026-09-14 `.padding` change regressed the
default demo, and it went unseen until a capture (record §03). A representation
change to the same wrapper is exactly that risk again.

**Mutations:** not applicable. The capture is the check; its two PNG sizes and
the differing-pixel count go in record §10.

**Lane 2's result: the window capture could NOT be taken; an offscreen scene
comparison stands in for it, and the capture is owed** (`MC-R` item 5). The
baseline release build of `git archive f64e58a` succeeded, and its window
opened (828×533 at (614, 259) by `CGWindowListCopyWindowInfo`, not frontmost),
but the session was locked with the display asleep
(`CGSessionCopyCurrentDictionary` `CGSSessionScreenIsLocked` = 1,
`CGDisplayIsAsleep` = 1, screen-capture access granted):
`screencapture -x -R614,259,828,533` and `-l<window id>` both printed "could
not create image" and a full-screen capture was black. No input was sent and
the pointer was not moved; it read (1090.18, 339.99) before each launch.

**What stood in:** the demo's `demoContent()` from `f64e58a` and from
`49270c7`, each rendered through `@testable` `Frame.render` in a scratch copy
of its own tree (the last line `try runDemo()` replaced by a harness; nothing
committed): 920×560 at scale 2, three frames under `Theme.light` and three
under `Theme.dark`, one shared `StateTable`/`ShapingCache`/`GlyphAtlas`, every
`MUIRect`, `MUIGlyph` and hitbox printed. The two dumps are **byte-identical**
(18 838 lines each; frame 0 has 2036 nodes, 518 rects, 15 711 glyphs; later
frames 60 nodes, 24 rects, 493 glyphs, 3 hitboxes). **The instrument can
disagree:** the same harness over `49270c7` with `ModifiedElement.paint`
emitting its fills after its content differs in 87 diff lines (the root's and
the header's rects move), and is identical again once restored. What this does
NOT cover that a capture would: the renderer, the window's real size and
backing scale, the display link, a focused counter at launch, and the pointer's
hover.

---

## MC-K — the outermost layer is stored inline and the rest in an array, so a single-layer chain allocates nothing a `Box` did not in the model's debug build; multi-layer chains cost array buffers that nested boxes did not, measured in a model and re-measured by lane 2 at 1, 2 and 3 layers

**Revised at design review (`MC-N` finding 4).** The first draft measured only
one-layer chains, the one case that does not allocate. Task 4 makes 2- and
3-layer chains the ordinary shape.

**The choice.**

- **Storage.** `ModifiedElement` stores `outermost: ModifierLayer` and
  `inner: [ModifierLayer]`.
- **Layout.** Its `Layout` stores the outermost node inline, and the inner
  layers' nodes in an array.
- **The one-layer case.** An empty array owns no buffer, so a one-layer chain
  has no array cost.

**Measured, model `LayerAllocationModel.swift`** (not the real module). Counts
are per chain, per frame build, averaged over 500, with the counter calibrated
first:

| layers | swift.org 6.3.3 `-Onone`: nested `Box` | flat | flat − nested | `-O`: nested | flat |
|---|---|---|---|---|---|
| 1 | 2 | 2 | **+0** | 0 | 1 |
| 2 | 3 | 6 | **+3** | 0 | 3 |
| 3 | 4 | 9 | **+5** | 0 | 4 |

- **Construction alone costs k−1 buffers** for k layers.
- **`consuming func _wrap` does not remove them.** It was measured, with
  identical numbers. The buffers are the array's growth on append, since an
  empty array has no buffer; they are not copy-on-write of a shared buffer.
- **The rest** is the `Layout`'s inner-node array, plus the per-layer loops.
- **The swiftlang 6.4 toolchain at `-Onone`** adds its known floor:
  calibration 16 → 32, and nested 3/4/5.
- **At `-O`**, even the one-layer case costs one allocation, where the nested
  version's arrays are optimised away. So the first draft's "a single-modifier
  chain allocates nothing a `Box` did not" holds in the model's debug build
  only.

**Owed by lane 2, in the real test build** (spec, lane 2):

- **Count** 500 chains of 1, 2 and 3 layers against hand-built
  `Box<Leaf>`, `Box<Box<Leaf>>` and `Box<Box<Box<Leaf>>>`.
- **Record** all six numbers here.
- **Keep a bounded test only if each arm reddens under its named mutation:**
  - one-layer arm: "one array for all layers";
  - two- and three-layer arms: "one extra array per inner layer".
- **Otherwise**, record the numbers and keep no test. A test that cannot fail
  is the disease this repo's practices doc names.

**Why not inline storage for more layers now.** A fixed inline capacity (say,
three layers before spilling to an array) removes the construction buffers.
But it adds a second storage path, whose own bugs are the kind `MC-B`'s oracle
exists to catch.

- **The measured cost is a few allocations per multi-layer chain per frame.**
- **The demo's padded list rows are one-layer chains** (`main.swift:857`, one
  `.padding(Edges(…))` per row, by reading), so the 500-row list is the +0
  case.
- **Deferred to task 4**, which creates the multi-layer chains, with these
  numbers as its baseline.

**What it costs if wrong.**

- **Per frame build, per multi-layer chain:** about +3 allocations at 2 layers
  and +5 at 3 layers over nested boxes, in the model's debug build; +3 and +4
  in its release build. That is on every chain rebuilt by a content closure.
- **Behaviour** does not change.
- **A task-4 screen of N elements**, each with a 3-layer sizing chain, pays on
  the order of 5N allocations per frame that the nested representation did not.
  **That is the number task 4 must re-measure** before converting
  `width`/`height`.

**Measured by lane 2, the real module, the suite's configuration** (debug test
build, swift.org 6.3.3; `aModifierChainAllocatesABoundedAmountOverNestedBoxes`).
Per 500 frame builds — construction AND `requestLayout` — of `Box().padding(…)`
chains against `Box(style:content:)` nested to the same depth, each in a fresh
`Frame` warmed with 1500 builds; calibration 16 of 16 (17 in one filtered run):

| layers | nested `Box` | flat | flat − nested, per chain |
|---|---|---|---|
| 1 | 17 002 | 17 002 | **+0** |
| 2 | 27 001 | 28 501 | **+3** |
| 3 | 37 004 | 39 504 | **+5** |

The differences are **exactly the model's** (+0/+3/+5). The absolute counts are
the real frame's work (tree nodes, `$anim` state, children arrays), about 34,
54 and 74 per chain for nested boxes. Under the swiftlang 6.4 toolchain
(`xcrun swift test --no-parallel`, filtered): calibration 32, a bare 67-item
index loop 67, nested 17 502 / 27 501 / 37 504, flat 17 502 / 29 501 / 41 004,
so +0, +4, +7 per chain; the test prints `MC-K-ALLOC: two- and three-layer
bounds NOT CHECKED` there and checks only the one-layer arm. **The test is kept**:
each arm reddens under a named mutation.

**Mutations:** lane 2 (at `49270c7`, whole suite, record §10).

- **A `requestLayout`-local array of every layer** (`inner + [outermost]`):
  the one-layer arm (18 002 against 17 002), and the two- and three-layer arms
  (+2 per chain each), 3 issues, that test alone.
- **One extra array per `requestLayout` over the inner layers**
  (`let _ = inner.map { $0.style }`): the two- and three-layer arms (3 000 and
  5 000 over nested) and **not** the one-layer arm, whose `inner` is empty; 2
  issues, that test alone.

**A hazard the test adds** (`MC-R` item 6): it and
`freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine` each install the
process-wide `malloc_logger` hook, so two counting windows that overlap
corrupt each other. Measured once, filtered to the two and run without
`--no-parallel` under 6.4: the freeze-loop test's calibration `#require`
failed. The whole suite without `--no-parallel` (6.3.3) passed once. Under
CLAUDE.md's `--no-parallel` the two cannot overlap.


---

## MC-L — deferred, and to whom

Not in this track. Each item is named so a green run of this track is not read
as covering it.

| item | why not here | owner |
|---|---|---|
| `width`/`height`/min/max as layers; legacy `.frame` min/ideal/max/alignment | the plan forbids it here | task 4 |
| inline layer storage for multi-layer chains (`MC-K`) | a second storage path; the multi-layer chains arrive with task 4 | task 4 |
| `Component` modifier distribution (`StyledComponent`), and caller modifiers snapping (B-7) | the plan forbids it here | task 5 |
| `MC-G` hole 5 (a legacy style modifier on a proposal `Component` compiles, traps) | distribution's | task 5 |
| paint-only legacy layers (`background`, `cornerRadius`, …) and the wrap/distribute/paint matrix | task 5's matrix | task 5 |
| unifying `ModifiedElement` with proposal `ModifiedContent` | two engines until task 7 | task 7 |
| a public, user-definable modifier protocol; the `_wrap` hole (`MC-A`) | `MC-A` | task 7 or later |
| `EitherGroup: ProposalElementGroup` (record §09 boundary 4) | not composition of modifiers | tasks 6/8 |
| one-node wrapper traps on 0 or 2+ nodes (boundary 2) | a typed id fixes the kind, not the count | task 6 |
| `MC-G` holes 1–4, 6 and 7 | holes 3 and 7: no mechanism within public Swift (7's backstop is C-3's trap); holes 1, 2 and 6 need the legacy root switch gone; hole 4 needs a duplicate-parent check in the kernel | task 7 (hole 4: task 6) |
| proposal `.id()`, focus, AX | interaction | task 12 |
| animation on proposal wrappers, and wrappers joining transactions | | task 13 |
| divergence 19 (one value placed twice) and `@State` inside `AnyElement` | not modifier composition | task 8 |
| a separate test that two `ProposalScrollView`s in an overlay keep separate `ScrollState` | closed by `MC-E`'s mechanism, not separately pinned | task 6 |
| deprecating `nativeFrame(…)` | breaks the 0-warning baseline (record §09) | integration step |
| ~~`aProposalContainerReadsTheEnvironmentDuringLayout`~~ — **withdrawn after lane 1's critic round (`MC-Q` finding 5):** the environment track already has it as `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` (`feat/environment:Tests/MetalUITests/EnvironmentTests.swift:468`, E11, ruling EV-W), reading layout, prepaint and paint `[7, 7, 7]` under an `HStack` and a `ProposalScrollView` | the typed `EnvironmentScope` entry is written at merge; EV-W's test is its check | integration step |
| `EnvironmentScope` arms in `everyModifierWrapperDelegatesEachPhaseExactlyOnce` (legacy and proposal) | the wrapper does not exist on this branch | integration step |
| per-layer mirroring of AB-O's `display: none` accessibility suppression in `ModifiedElement.prepaint`, and its test | the check does not exist on this branch (`MC-B`'s "does NOT cover") | integration step |
| legacy `.frame` against SwiftUI outside test 10's scope: a nil axis, a frame smaller than its content, under a stretching `Box` (EP-8), in a shrinking row (SZ-L) | legacy `.frame` semantics are task 4's; by reading the legacy frame node stretches or shrinks where a SwiftUI frame stays fixed | task 4 |
| CLAUDE.md / AGENTS.md / plan / record README updates: guard count, "registering points", `FrameModifier` mentions, the candidate divergence (`MC-C`), the holes | owned by the integration step | integration |

**The superseded typed-modifier spec's required proofs**, and where each now
lives. **Added at design review (`MC-N` finding 10):** the first draft dropped
two.

| 2026-09-12 spec's required proof | owner here |
|---|---|
| two chained modifiers have two structural identities and preserve distinct `@State` slots | `MC-D`, lane 1 tests 5–6 |
| once-per-phase delegation | `MC-F`, lane 1 tests 7–8 |
| explicit `AnyElement` remains opt-in; no ordinary modifier path introduces it | lane 2 test 1 (no type name contains `AnyElement`; exact `ModifiedElement<…>` names) |
| frame ordering changes the measured/placed result where SwiftUI does | **closed for a narrow scope only** (qualifier added after lane 1's critic round, `MC-Q` finding 7): a fixed 20×20 leaf, both frame axes given, frames at least as large as the content, under an unconstrained `.flexStart` parent. Lane 1 test 10, `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`, against `swiftui-modifier-order.swift`: all seven arms (K0-K2, O1-O4) committed and green at `6d89906`, with O1 ≠ O2 and O3 ≠ O4 `#require`d first; `FrameModifier.init` dropping `justifyContent = .center` reddens it (O1-O4's leaf x reads 8, 8, 12, 12 against 20, 28, 18, 22). It must stay green through lane 2. **Not closed, and handed to task 4 by name:** a nil axis (`.frame(width: 60)`, which lane 2 test 1 uses), a frame smaller than its content, a frame under a stretching `Box` (EP-8), a frame in a shrinking row (SZ-L) — the row above |

---

## MC-M — method: what was measured, and what was only read

- **Measured:**
  - every table row in `MC-A` (timing, inference, reachability), `MC-C`'s
    SwiftUI arms, `MC-E`, `MC-G` (skeletons and holes 2, 4 and 6), and
    `MC-K`'s model;
  - lane 1 test 10's numbers, on SwiftUI and on today's MetalUI;
  - after lane 1's critic round: the overlay primary-shape probe, the
    solver-scope thresholds, and `MC-P`'s end-to-end readings and mutations.

  The runs are listed under "Where each number was measured".
- **By reading, not run:**
  - that `FrameModifier`'s phases equal `Box`'s. That is `MC-B`'s premise, and
    lane 1's oracle test is its measurement;
  - that lane 1's counting arms cover every distinct code path in
    `ModifiedContent`'s phases. Lane 1 enumerates them against the source;
  - the 35-conformance count (grep);
  - that no stored type in `Sources/` spells a `.padding`/`.frame` chain
    (grep);
  - `MC-C`'s adoption prediction (8 / 10 / 12). Lane 2 test 5 measures it;
  - `MC-G` hole 7's trap path (`Frame.swift:1049`, `LayoutTree.slot`); lane 3
    test 9 measures it;
  - `MC-B`'s AB-O gap: read from `feat/ax-bridge` at `53d3bf6`, not run;
  - lane 1 test 9's predicted readings;
  - that `Component.swift`'s untyped default is pinned by the two tests `MC-H`
    names (from their doc comments' recorded mutations).
- **The scratch tests were deleted, not committed.** Their shapes are
  reproduced as:
  - lane 1's first three tests, which must be red on their first run;
  - lane 1's test 10, green as measured;
  - lane 3's tests 7 and 8, green as measured.
- **Instrument checks:**
  - **The SwiftUI probes' controls are their positive controls:** identity
    probe A and B; order probe K0–K2, whose outer sizes and origins differ;
    overlay primary-shape probe A, B, P5 (the flip happened) and Q (a reset
    inside an overlay is visible).
  - **The skeletons' negative clients** each printed the specific diagnostic,
    not just a non-zero exit (practices shape 16's "print the real diagnostic
    before trusting it").
  - **The allocation model** was calibrated against 16 known buffers in every
    run, and read 16 (or 32 under the swiftlang floor).
  - **The timing probe** printed the inferred types for all three variants
    before its timings were read, so the three designs were shown to differ
    only in overload shape.

**Mutations:** not applicable.

---

## MC-N — design review, 2026-09-15: each finding and what was done with it

Twelve findings from the critic's review of `1c6f686`. Every one was applied;
none was rejected. Where a finding offered alternatives, the one taken is named
with its reason.

| # | finding | disposition |
|---|---|---|
| 1 | `MC-A`'s overloads make type-checking time exponential in chain length; replace them before lane 2, or prove the cost on the real module | **Applied, by replacement.** The reviewer's numbers were re-taken with a generator carrying the real module's competing overloads (`chain-typecheck-timing.py`); the exponential was confirmed under two toolchains. `MC-A` now uses the reviewer's measured alternative, one overload through `ElementGroup.LayerBase`, checked two-module (`LayerBaseKit.swift`) and together with lane 3 (`CombinedKit.swift`). The real-module check is kept as a recorded lane-2 measurement. Lane 2 test 6 (a 24-modifier chain) turns a regression into a build failure. The new `_wrap` hole is recorded in `MC-A`. |
| 2 | Lane 3 breaks the environment track at merge: `EnvironmentScope`'s proposal conformance, and two unknown `StateBinder.bind` copies | **Applied.** Both collisions are in the spec's merge notes and record §10. The copied defaults were **replaced by one helper** (`MC-H`), the reviewer's second option, at the cost of a three-line edit to `ElementGroup.swift`. The layout-time environment test cannot be written on this branch, since the API does not exist; its exact shape and mutation are specified for integration (`MC-L`). |
| 3 | Deleting `FrameModifier` conflicts with both other tracks | **Applied.** The environment track's D2 arm, the AX-bridge spec's scope-boundary entry and "untouched" line, and the shared arm lists are named in the spec's merge notes. The change-not-delete rule is in `MC-I`. |
| 4 | `MC-K` measures only the case that does not allocate | **Applied, and measured now.** A model counts 1, 2 and 3 layers against nested boxes (+0/+3/+5 debug). A `consuming` variant shows the buffers are growth, not copies. Lane 2 re-measures in the real build. The cost is named in `MC-K`, and inline storage is deferred to task 4 with these numbers. |
| 5 | `MC-C`'s "both directions agree with SwiftUI" overreaches; layer adoption is unnamed | **Applied.** Reworded: only the wrapped element's reset is claimed as parity, and even that is argued for the flat case, not measured. The adoption is named and pinned (lane 2 test 5), and proposed as a candidate divergence for integration. The reviewer's re-run of the probe matched its header; not re-run again. |
| 6 | `MC-B`'s disagreeing oracle covers rects only | **Applied.** One disagreeing oracle per observation (id moved, `onClick` dropped, a layer fewer), each `#require`d. |
| 7 | Guard 6 cannot show that it runs | **Applied.** An in-test negative fixture (the liar minus its typed entry), `#require`d to disagree, and a post-landing red run owed by lane 3. |
| 8 | `MC-G`'s holes are incomplete | **Applied, and measured now.** Duplicate id in one container, and one id in two containers, by scratch tests (hole 4). The orphan legacy subtree binds and marks state and `$anim`, and paints nothing, by scratch test (hole 6). The proposal-`Component` style modifier is hole 5, pinned by the existing exit test. Holes 4 and 6 are pinned by lane 3 tests 7–8. |
| 9 | `CounterPanel` evidence is misattributed | **Applied.** `MC-A` now says no stored type in `Sources/` spells a chain, and gives task 4 as the pressure. |
| 10 | Two proofs from the superseded spec are unassigned | **Applied.** `AnyElement` opt-in goes to lane 2 test 1. Frame ordering goes to lane 1 test 10, backed by a new SwiftUI probe (`swiftui-modifier-order.swift`) and a scratch measurement showing today's MetalUI already matches on all seven arms. `MC-L` has a table mapping each superseded proof to its owner. |
| 11 | `MC-E`'s index-stability argument has a counterexample | **Applied.** The claim is withdrawn, and the counterexample is pinned as lane 1 test 9 (`EmptyProposalComponent` in an optional primary). |
| 12 | Minor inconsistencies | **Applied.** The hover fill is `.textPrimary`, which no chain uses. Lane 3's helper conversions in `ModifierCompositionProofTests.swift` count 2. The demo baseline is built from `git archive f64e58a` (`MC-J`). |

**What the review did not change:**

- the flat representation itself;
- lane order;
- `MC-D` and `MC-F`'s substance;
- `MC-G`'s delivery of the compile-time check.

**Mutations:** not applicable.

---

## MC-O — lane 1's departures from the spec, and a suite truncation its mutations found: six items, none changing a ruling's substance

Written by lane 1 (commits `6d89906`, `6ff2d31`, `2571d4a`), 2026-09-15. The spec
is corrected at each line these items make false.

1. **Test 4's id-moving oracle moves the name from the padding-4 layer, not
   from "the frame layer".** In the chain
   `….padding(4).id("mid").frame(…)`, `.id` follows `.padding(4)`, so by
   `MC-C`'s "`.id(_:)` names the layer it follows" it names the padding-4
   layer, and the oracle mirrors it there. The spec's table said the name moves
   "from the frame layer", which names a layer the chain never puts it on. The
   disagreeing oracle moves `"mid"` from the padding-4 layer to the outermost
   padding-8 layer, and is `#require`d to differ in the leaf's id and the
   hitbox ids.
2. **Tests 4, 7 and 10 render through `Frame` directly, not a `Window`.** None
   needs pointer state. Test 4 therefore reads `Frame.hitboxes`, which is the
   array `Window.drawFrameIfNeeded` copies into `lastHitboxes`, and
   `Frame.scene.rects` in emission order.
3. **Test 10 also pins K0 and K2**, the probe's own controls, beside K1 and
   O1-O4.
4. **The log class is `CompositionLog`, not `PhaseLog`.** `PipelineTests.swift`
   already declares an internal `PhaseLog`; a `private` one in another file of
   the same target fails to build ("invalid redeclaration of 'PhaseLog'").
5. **A shape-13 truncation, fixed outside the lane's file list.** Mutating
   `OverlayModifier.paint` to skip `overlay.paintGroup` (`MC-F`) ended the run
   with "Fatal error: Index out of range" and no summary line.
   `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt`
   (`NativeLayoutIntegrationTests.swift`) indexed `rects[1]` after
   `#expect(rects.count == 2)` recorded a failure. Three sibling tests in that
   file had the same shape
   (`nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent`,
   `builderNativeBackgroundPaintsBeneathItsNativeChild`,
   `nativeBorderPaintsOverContentWithoutChangingItsFrame`). All four now
   `try #require` the count (`2571d4a`, test-only, eight lines). Re-run, the
   mutation reports `Test run with 1094 tests … with 8 issues`.
   - **Why here:** a wrong implementation truncating the suite is exactly what
     lane 2's mutation runs over `OverlayModifier`'s neighbours would otherwise
     hit again.
   - **Not swept:** other files' `#expect(… .count …)` followed by indexing.
     Only the file this mutation reached was adjudicated.
6. **Test 4 cannot see a cursor offset beneath a named layer.** Measured:
   `FrameModifier`'s content cursor starting at 1 reddens test 5 and not
   test 4. The padding-4 layer's name replaces its index, so the leaf's id and
   every hitbox id are unchanged. That is `MC-C`'s name-replaces-position rule
   working, not a broken instrument. Test 5, whose chain is unnamed, carries
   the cursor. By reading, not run: lane 2's "every inner layer takes the
   outermost id" mutation stays visible to test 4, because it changes the
   leaf's depth and the layer ids, not an index beneath the name.

**What it costs if wrong.** Item 1: an oracle that put `"mid"` on the frame
layer would differ from the chain, and test 4 would be red on arrival rather
than green. Item 5: none in behaviour; four tests stop
at the count instead of reporting per-field failures after it.

**Mutations:** item 5's is the overlay-paint row of `MC-F`; item 6's is the
cursor bullet of `MC-B`.

---

## MC-P — `OverlayModifier` numbers the primary from 0 under its own id and the overlay from 0 under `.child(of: id, at: -1, name: nil)`, an overlay-side id no cursor can produce; the overlay's identity is independent of the primary's shape, as SwiftUI's is (replaces `MC-E`'s threaded cursor)

Written after lane 1's critic round (`MC-Q` finding 1), 2026-09-15, commit
`661efd9`.

**What SwiftUI does, measured** (`docs/probes/swiftui-overlay-primary-shape.swift`,
both forms byte-identical). A conditional in the primary flips true, false,
true; the number is the overlay's state serial per step:

| arm | primary | overlay serial per step |
|---|---|---|
| A (control) | plain probe, input changes | 1, 1, 1 — kept |
| B (control) | `.id(generation)` | 2, 3, 4 — new |
| P1 | `ZStack { if; Color }` | 5, 5, 5 |
| P2 | `Group { if; Color }` | 6, 6, 6 |
| P3 | a multi-view `body` | 7, 7, 7 |
| P4 | `Group { if EmptyView; Color }` | 8, 8, 8 |
| P5 (control) | `ZStack { if Probe c; Color }` | c: 9, absent, 11 (the flip happened); o: 10, 10, 10 |
| Q (control) | overlay content itself flips `if`/`else` | 12, 13, 14 — a reset inside an overlay is visible |

Every arm evaluated each probe once per step (`n=1`).

**What MetalUI did under `MC-E`, measured** (test 9 with the threaded cursor
restored as mutation R1, record §10): the overlay read `.positional(2)` with 3
taps, then `.positional(1)` with **0**, then `.positional(2)` with 3 (retained,
divergence 18).

**The choice.**

```swift
var contentCursor = 0
content.requestGroupLayout(under: id, at: &contentCursor, pass: &pass)
var overlayCursor = 0
let overlaySide = GlobalElementID.child(of: id, at: -1, name: nil)
overlay.requestGroupLayout(under: overlaySide, at: &overlayCursor, pass: &pass)
```

- **The primary does not move.** Its elements keep `MC-E`'s ids
  (`.child(of: id, at: 0…)`), so no primary's state re-seeds, the demo
  preview's `PreviewToggle` included.
- **The overlay moves one level**, to `.child(of: .child(of: id, at: -1), at: 0…)`.
  Its state entries at `MC-E`'s ids are abandoned once, on the first frame of
  a build carrying this change. No persisted state crosses a launch, so that
  is a within-session concern only, and no release has shipped `MC-E`.
- **`-1` is unreachable from any cursor.** Every cursor starts at 0 and only
  grows (`Element`, `Pair`, `EitherGroup`'s `+= 2`, `ArrayGroup`), so however
  many indices the primary consumes it cannot land on the overlay side.
- **No reserved name is added.** CLAUDE.md's seven reserved names are
  unguarded against a `List` datum or `.id` that describes to one; a
  `.positional(-1)` component cannot be described by a name at all, since
  names are `.named`.

**Alternatives, and why not.**

- **`MC-E`'s threaded cursor** — diverges from SwiftUI (table above). Kept as
  mutation R1.
- **A reserved name** (`.named("$overlay")`) — the same independence, at the
  cost of an eighth unguarded reserved name. Kept as mutation R3: test 9's
  taps stay 3 under it, and only the id assertions of tests 1 and 9 see which
  spelling is used.
- **An intermediate id on both sides** (`EitherGroup`'s shape) — re-seeds
  every overlaid primary's state (`MC-E`).
- **Keeping `MC-E` and recording a divergence** (the critic's option b) —
  rejected: the parity answer costs one line and one level on the overlay
  side only, and `MC-E`'s case against its closest alternative (a reserved
  name) does not apply to `-1`.

**Tests** (`ModifierCompositionProofTests.swift`):

- **Test 1** `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities` pins
  primary `== .child(of: modifier, at: 0)` and overlay
  `== .child(of: .child(of: modifier, at: -1), at: 0)`, and the same overlay
  shape under a two-leaf `HStack` primary.
- **Test 9**, renamed from `anOverlaysIdentityFollowsTheIndicesItsPrimaryConsumed`
  to **`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`**, and
  inverted: its primary's plain `Rectangle` became a `CountingProposalLeaf("p")`
  so the test carries the probe's P5 control, `#require`-ing that `p` reads
  `.positional(1)`, `(0)`, `(1)` across the flip. The overlay then reads, at
  all three steps: path `[.positional(0), .positional(-1)]`, the exact expected
  id, 3 taps, its `$state0` slot live.
- **Tests 2 and 3** are unchanged and stay green.

**Measured** (whole suite, `--build-system native --no-parallel`, record §10):

| run | at | summary | reddens |
|---|---|---|---|
| green | `661efd9`, after `swift package clean` | 1094 passed | — |
| green | `39f6237` | 1094 passed | — |
| R1: `MC-E`'s threaded cursor restored | `39f6237` | 1094, 5 issues | test 1 (both arms); test 9 (index 2/1/2, taps 3/0/3, slot not live) |
| R2: the original shared id (overlay under `id` with a cursor at 0) | `39f6237` | 1094, 11 issues | tests 1, 2, 3, 9 |
| R3: overlay side `.named("$overlay")` | `39f6237` | 1094, 5 issues | test 1 (both arms); test 9 on path and id only (taps 3 at every step) |

**What it costs if wrong.**

- **If `-1` were ever produced by a cursor** (a container that counts down, or
  an index computed as `cursor - 1`), an overlay could collide with that
  element. No such cursor exists in `Sources/` today (grep for
  `positional(` and `at: -`). Test 1 pins the spelling, not the absence of
  such a container.
- **Anything that walks `GlobalElementID.parent` and expects every ancestor to
  be an element** now meets one synthetic ancestor above an overlay. The one
  walker in `Sources/` on this branch is `focusChain(from:)`
  (`Focus.swift:134-142`), whose doc already says an id with no produced
  element "is harmless: `dispatchKey` finds no handler" for it — the same
  footing as `ScrollView`'s `$anim-content`/`$anim-viewport` named children.
  **Run since, in the lane-1 verifier-fix round (record §10):**
  `aKeyAFocusedOverlayDeclinesBubblesThroughTheOverlaySideIDToItsHolder`
  focuses a focusable overlay under a holder with `onKey` through a real
  `Window`; the overlay claims its own key and a key it declines reaches the
  holder. A detached overlay-side id (`.child(of: nil, at: -1)`) reddens its
  bubble assertion.
- **The AX bridge's parent walk** (`feat/ax-bridge:Sources/MetalUI/AccessibilityTreeBuilder.swift:30-41`,
  "the nearest `GlobalElementID.parent` ancestor that recorded") steps over the
  synthetic ancestor, which records nothing, to the overlay modifier's nearest
  recording ancestor. For integration: by reading, not run. **Owed at merge
  with `feat/ax-bridge`:** an AX-emitting arm beside test 11 (an overlay
  declaring `handlers.axNode`, asserting its bridge parent is the holder's
  node), since this branch has no bridge to run it against.

**For CLAUDE.md, owned by integration:** the identity section gains "an
overlay's elements number under a synthetic `.positional(-1)` child of the
modifier, so its state is independent of the primary's shape (MC-P, SwiftUI
parity)"; lane 1's record line "the overlay's index now depends on its
primary's index count" is withdrawn.

**Mutations:** R1-R3 above; R1, R2 and the detached-id mutation re-taken
against test 11 in record §10's verifier-fix round.

---

## MC-Q — critic round after lane 1, 2026-09-15: each finding and what was done with it

Eight findings against `ec65da6`. Seven applied, one partly applied with the
rest rejected for a stated reason. Lane 2's paused skeleton was stashed and
restored around this round and was not edited.

| # | finding | disposition |
|---|---|---|
| 1 | `MC-E` pins overlay behaviour SwiftUI does not have, and calls it parity | **Applied, option (a).** The critic's probe was committed with two added controls (P5, Q) and a per-arm evaluation count, run in both forms. The overlay now numbers under `.child(of: id, at: -1)` (`MC-P`); tests 1 and 9 are inverted (9 renamed and given the P5 control); `MC-E`'s parity sentence, trailing-sibling sentence and remedy are struck in place; the source doc comment is rewritten. Measured green, and red under R1 (threaded), R2 (shared) and R3 (reserved name). |
| 2 | After merge, an inner `hidden()` layer stops hiding its subtree from accessibility | **Applied in part; the rest rejected with a reason.** Applied: `MC-B` now states what "every observable" does not cover (per-element group-default hooks) and why nothing is lost on this branch; the spec's merge notes gain the rule "any hook added to `Element`'s default `requestGroupLayout`/`prepaintGroup`/`paintGroup` is mirrored per layer in `ModifiedElement`", the concrete AB-O mirroring (one helper shared with `Element.prepaintGroup`, wrapping layer k's registration and everything inside it), and the owed integration test comparing `Frame.axEmissions` for `Text("x").padding(4).hidden().frame(width: 60)` against hand-built boxes, with its mutation. **Rejected: implementing the per-layer suppression and its shared helper on this branch.** AB-O's check, `Frame.collectsAccessibility`, `withAccessibilitySuppressed` and `axEmissions` do not exist here; a helper written now would be an identity wrapper with no behaviour, no test able to redden and a textual conflict with AB-O's own edit to the same function at merge — a declared-but-inert seam. Lane 2's spec asks only that the per-layer loop be written so each layer's registration and everything inside it can be wrapped in one scoped call. |
| 3 | Lane 2 test 6 cannot reliably catch a return to the first `MC-A` design | **Applied.** `-solver-scope-threshold` exists on both toolchains; `chain-solver-scope-guard.sh` measures the model's thresholds (identical on both) and the guard's two-module shape with an in-file negative (0.1 s each). Test 6 becomes the guard `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`: positive at threshold T, in-test negative (the first design's overloads in the fixture) rejected with "unable to type-check", `#require`d to disagree; T set by lane 2 from the real module's measured minimum; red once by moving the concrete overloads into `ModifiedElement.swift`. `Typecheck.swift` gains an additive frontend-arguments parameter. Type names stay in test 1. |
| 4 | Lane 2 test 5 could pin a snap | **Applied.** The spec now requires the generation change to be a write plus `setNeedsRedraw()` INSIDE the `withAnimation` body, cites the rollback at `Animation.swift:717-720`, and requires a `try #require` that the t = 0.5 reading lies strictly between the t = 0 and settled readings before any value is pinned. |
| 5 | The merge notes are stale against `feat/environment` at `f4dcad8` | **Applied.** `bind(_:in:id:)` (`StateReflection.swift:104`, no `environment:` parameter, no default by EV-W); the invented `aProposalContainerReadsTheEnvironmentDuringLayout` withdrawn in favour of E11 `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` (`EnvironmentTests.swift:468`); the environment record's stale "two `StateBinder.bind` call sites" (`docs/record/11-environment.md:258-259`) named for integration (not edited: another track's file); `EnvironmentScope` arms owed in test 7 on both paths; the `NativeTappable.swift` conflict with AX lane 3's `OnTapModifier.prepaint` edit named. |
| 6 | Test 4's `$anim` check was never shown to detect a missing slot | **Applied.** `BoxWithoutAnimated`, a test-local copy of `Box`'s phases minus `animated`, is the equal-count disagreeing oracle, `#require`d to read `[true, false, true]`. R4 (`FrameModifier` skips `animated`) reddens test 4 and test 5; R5 (the wrapper calls `animated`) reddens the `#require` alone. |
| 7 | `MC-L` marks frame ordering closed on a narrow probe | **Applied.** The scope is stated in `MC-L`'s row and in test 10's doc comment; the uncovered cases are a new `MC-L` row owned by task 4. |
| 8 | `MC-G`'s holes omit a stored typed id | **Applied, as hole 7** (not folded into hole 3, which is about minting, not reuse): a run-time trap by reading, pinned at the kernel today, and end to end by a new lane 3 exit test (test 9). |

**What this round did not change:** `MC-A`'s representation, `MC-C`, `MC-D`,
`MC-F`, `MC-H`, `MC-I`, `MC-J`, `MC-K`, lane order.

**Mutations:** `MC-P`'s R1-R3 and `MC-B`'s R4-R5.

---

## MC-R — lane 2's departures from the spec: two skeletons, not one; counts from 1095; test 2's padding-8 spelled with `Edges`; guard 7's positive gains a call; the demo compared offscreen because the screen was locked; and a parallel-run hazard

Written by lane 2 (commits `e9248c3`, `5fe5a30`, `49270c7`), 2026-09-15. The
spec is corrected at each line these items make false.

1. **The red runs were taken on two skeletons, because the spec's one skeleton
   cannot compile the lane's own tests.** The spec's skeleton omits
   `typealias LayerBase = Content`, so chains nest. But tests 1, 2, 3 and 5
   (and `ComponentTests`' stored `Row<ModifiedElement<TwoLeaves>>`) spell a
   chain as ONE `ModifiedElement<Leaf>` — tests 3 and 5 by design, since a
   chain whose length changes at run time in one type is what they pin — and
   on a nesting skeleton those spellings are compile errors, which take the
   whole test target down rather than reddening tests.
   - **S1, committed as the red commit `e9248c3`:** the flat type
     (`LayerBase = Content`, the appending `_wrap`) with phases that register
     only the outermost layer, around the content, under the outermost id.
     Red there: tests 2, 3, 5, all six `MC-I` inner arms, lane 1's tests 4, 5
     and 10, and two existing `ComponentTests` (1102 tests, 40 issues).
     Green there: test 1 (the type was flat), test 4, both guards.
   - **S2, uncommitted:** S1 minus the typealias and the appending `_wrap`.
     `swift build --build-tests` failed with, among others,
     `ModifiedElementTests.swift:271:69: error: cannot assign value of type
     'ModifiedElement<ModifiedElement<ChainLeaf>>' to type
     'ModifiedElement<ChainLeaf>'` and `:301:37: error: cannot convert return
     expression of type
     'ModifiedElement<ModifiedElement<ModifiedElement<LayerLeaf>>>' to return
     type 'ModifiedElement<LayerLeaf>'` — tests 1 and 2's type claims, red as
     build errors. With `ModifiedElementTests.swift` moved aside and
     `ComponentTests`' stored type patched, the guards ran
     (`--filter ModifiedElementCompileGuards`): guard 7 red ("annotated
     succeeded=true"), guard 6 green. Everything was restored from copies and
     `git status --short` showed only the intended uncommitted files.
2. **The counts start from 1095, not 1094.** Lane 1's verifier-fix round
   (`b675451`) added test 11. So lane 2 reads **1102** without the allocation
   test and **1103** with it (the spec's 1101/1102 plus one). Guards 45 → 47
   (`grep -c canTypecheck`: 19, 10, 5, 3 with one a comment, 3, 6, 2).
3. **Test 2's flat chain spells its padding-8 layer
   `.padding(Edges(all: .pixels(8)))`** (`49270c7`). Under test 1's mutation a
   `Pixels` padding on a chain nests, and test 2's `-> ModifiedElement<LayerLeaf>`
   would stop compiling. The generic arm keeps `t.padding(8)`.
4. **Guard 7's positive fixture also calls the generic wrap over a chain**
   (`func use() -> ModifiedElement<Leaf> { wrap(Leaf().padding(4)) }`), so the
   positive is sensitive to nesting as well. Measured on S2: the generic nested
   negative stays rejected even when chains nest (`T.LayerBase` is abstract), so
   the annotated negative and this call are the halves that see nesting.
5. **The default demo was not captured; an offscreen scene comparison stands in,
   and the window capture is owed** (`MC-J`'s result has the numbers). The
   session was locked with the display asleep for the whole lane, so
   `screencapture` could produce no image. The stand-in compares every rect,
   glyph and hitbox the demo's content emits through `Frame.render`, byte for
   byte, and was shown able to disagree. **Owed:** the capture of the release
   demo against `f64e58a`'s release build, by the method `MC-J` names, once
   the display is available; `mc-base`'s release build is in the session
   scratchpad, not in the repository, and must be rebuilt if gone. **The
   stand-in exercises only ONE-layer legacy chains:** every legacy `.padding`
   in `Sources/MetalUIDemo/main.swift` is a single layer, and its `.frame`
   calls are the native overloads, so no multi-layer `ModifiedElement` reaches
   the demo (verifier round; tests 4 and 2 cover multi-layer chains). Still
   locked at the verifier-fix round (`IOConsoleLocked` and
   `CGSSessionScreenIsLocked` true), so the capture remains owed.
6. **A parallel-run hazard, measured and not fixed.** `ModifiedElementTests.swift`
   copies `FreezeLoopAllocationTests.swift`'s counter, and both install
   libmalloc's process-wide `malloc_logger` hook. Run concurrently they can
   corrupt each other's counts (measured once: the freeze-loop calibration
   `#require` failed in a filtered run without `--no-parallel`). A shared,
   locked counter needs a `MetalUITestSupport` dependency that
   `MetalUILayoutTests` does not have (a `Package.swift` change), so it is
   named here, in the test's doc comment and in record §10 instead. Not fixed
   in the verifier round either: the two tests live in different targets, so
   `.serialized` on one suite cannot order them against the other; carrying it
   into `CLAUDE.md`'s When-CI-lands list is the integration step's.
7. **The style guard's inner arm reads the inner node as the outer node's only
   child in the layout tree**, not through `ModifiedElement.Layout`, so the
   reading does not depend on the bookkeeping under test; and its helper returns
   an optional rather than calling `#require` inside a local function, where
   the compiler warned "no calls to throwing functions occur within 'try'
   expression" on both a `Bool` and an `Optional` `#require`.
8. **`prepaint` is a recursion over the layers** (`prepaintLayer(_:id:bounds:layout:pass:)`),
   the spec's "or equivalent" taken literally: one call per layer covers its
   registration and everything inside it.
9. **`Component.swift`'s `Box.swift:643`/`:603`/`:607` citations were already
   stale at `f64e58a`** (`padding(_ points:)` is at `:640`, `width` at `:593`,
   `height` at `:597`, both before and after this lane). The lane's `Box.swift`
   edit did not move them, and `Component.swift` is a shared file the spec
   leaves unedited, so they are left for integration.

**What it costs if wrong.** Item 1: none in behaviour; a reader looking for one
red commit carrying every red finds S2's in record §10 instead. Item 5: a
renderer-level or window-level difference in the default demo would go unseen
until the owed capture. Item 6: an intermittent red in an unfiltered parallel
run.

**Mutations:** the items' runs are the Mutations lines of `MC-A`, `MC-B`,
`MC-C`, `MC-I` and `MC-K`.

