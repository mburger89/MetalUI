# Incremental invalidation — decisions

Rulings for item C14 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**), requested by MetalCreator (gap PERF-b in its
`docs/metalui-gaps.md`, measured by its M7). Prefix `IV-`. Spec:
[`specs/2026-10-13-incremental-invalidation-design.md`](specs/2026-10-13-incremental-invalidation-design.md).
Record: `../record/104-incremental-invalidation.md`. Branch
`perf/incremental-invalidation` from `f6f865c1`. Divergence labels reserved for
this branch: 345–354.

SwiftUI's side: `docs/probes/swiftui-incremental-invalidation.swift` (arms R0,
R-unread, R, S, T, U, V, O, ES, L0, L-unread, L-colour, L-width; output in its
header, run three times, deterministic). Swift Observation's side:
`docs/probes/swift-observation-nested-scopes.swift` (arms N0, N, M, T, U). MetalUI's
own numbers: `docs/probes/incremental-invalidation/` and the committed counted
baseline `Tests/MetalUITestingTests/IncrementalInvalidationBaselineTests.swift`
(`oneObservedLeafChangeRebuildsTheWholeWindow`). gpui has no retained layout tree
to borrow: it re-requests layout for a whole view each time the entity is
notified; where this document says "SwiftUI" a probe arm backs it.

**Next unused id: `IV-N`.**

## IV-A — Measure first: the build recursion is half a frame, the layout kernel a fifth, and nothing is a hot spot

**Question.** MetalCreator reports ~43% of a frame in `requestLayout` and calls it
"layout". Which phase does an observed change really pay, and is any of it a
micro-optimisation away?

**Evidence** (release, `-Xswiftc -enable-testing`, a 3-ary `Component` tree, one
`Text` per leaf, one `@Observable` leaf written per frame, 200 frames after 20
warm; the instrument is `docs/probes/incremental-invalidation/phase-timing.patch`;
shares, not milliseconds — other workflows were running):

| leaves | nodes | build | layout kernel | prepaint | paint | sweeps | render | tick |
|---|---|---|---|---|---|---|---|---|
| 9 | ~22 | 0.110 | 0.054 | 0.023 | 0.037 | 0.012 | 0.238 | 0.297 |
| 27 | ~67 | 0.329 | 0.151 | 0.066 | 0.091 | 0.034 | 0.675 | 0.830 |
| 81 | ~202 | 1.006 | 0.363 | 0.201 | 0.265 | 0.113 | 1.955 | 2.463 |

Build is 51%, the kernel 19%, prepaint 10%, paint 14%, sweeps 6%; the `Component`
content getters are 0.211 of the 1.006 ms. A release `sample` of 6000 frames: the
top of the stack is `swift_release`/`swift_retain`, `__RawDictionaryStorage.find`,
`GlobalElementID.==`, `Hasher`, `_swift_getGenericMetadata`, `swift_beginAccess` —
spread over the whole build, no function over ~3%. Counted at `f6f865c1`, per
frame at 81 leaves: 1 build, 81 leaf and 40 branch bodies, 81 leaf measures, 832
layout-cache hits, 337 misses, 162 text-system measures, 81 `placeGlyphs`; at 27
leaves 27/13 bodies and at 9 leaves 9/4 (the formula is linear:
`leaves + (leaves - 1)/2` bodies).

**Ruling.** (1) The baseline test stays in the suite as the "before" and is the
source of the red-on-arrival numbers (spec §2, §6). (2) "layout" in MetalCreator's
profile is the **build phase**; a layout-only item cannot reach PERF-b. (3) No
micro-optimisation is ruled: the profile has no hot spot, and the cost is
retain/release, hashing and dictionary traffic per node per frame, which only
doing less work removes. (4) Wall clock appears only in the instrument; every pin
counts work.

**Cost if wrong.** If a real app's cost were dominated by one function the profile
here missed (MetalCreator's nodes are 50× heavier per node), a retained-subtree
design would still help and a micro-fix would be additive; nothing here forecloses it.

## IV-B — `.equatable()` is the opt-in, and `==` decides

**Question.** SwiftUI skips a child's body when the child's stored inputs compare
equal. How does a MetalUI `Component` get that, and what compares?

**Evidence** (probe, arms S, U, V, O, ES, EqPod, EqRef, Eq-equatable()): a child
holding plain values or the same class instance is skipped when the parent
re-evaluates (Plain, ReadA, WithRef); a child whose input changed re-runs
(PlainTick, V); `.equatable()` with a custom `==` skipped the plain-value view
(EqPod); a view holding a capturing closure (Eq-equatable()) or a freshly
allocated class instance (EqRef) re-ran on the **first** bump after the first
render (S) although `==` said equal, but **not on the second or third** (S2, S3,
added by the critic: the S result was a first-bump artefact, which is what U's
unexplained difference was), so SwiftUI **honours `==`** and the original
reading was refuted; an observed read and the view's own `@State` beat an equal `==` (O, ES). SwiftUI skips
**by default**, reflectively; MetalUI today never skips (every `content` is
evaluated every frame, and `ComponentTests`/`contentIsMaterializedExactlyOncePerFrame`
and the GT-A test's plain-class model rely on that: a plain class read in `content`
with `setNeedsRedraw()` is not observed and would go stale under an automatic skip).

**Ruling.** (1) **Opt-in, SwiftUI's spelling:** `Component.equatable()` where
`Self: Equatable`, returning `EquatableComponent<Self>` (an `ElementGroup`, no
public initialiser, no identity level or cursor index of its own). No automatic
skipping (`IV-K`). (2) **`==` decides** for every stored property, closures and
class references included — the contract is "the content is a function of the
value, the component's own `@State`, and the `@Observable` properties it reads"
(**no divergence**: S2/S3 show SwiftUI honours `==` too; label 345 is
unused, see the critic ruling `IV-L`). (3) An observed read and an own-`@State` write beat an equal `==`, as
in SwiftUI (O, ES; `IV-C`, `IV-D`). (4) A `Binding` input is a value; an author
who reads `binding.wrappedValue` in `content` includes it in `==` (documented on
`equatable()`).

**Cost if wrong.** A `==` that ignores an input the content reads gives a stale
subtree until something else changes; the failure is the author's and local to one
component, found by the differential 2.9 pattern. An automatic skip was the
alternative; refused for the reason above.

## IV-C — Observation: a per-memo session over the getter only; the whole-frame session stays

**Question.** A skipped getter reads nothing, so the window's single
`withObservationTracking` no longer covers what the last evaluation read. What
re-evaluates the component when that property changes? And can per-`Component`
scopes replace the whole-frame session (SwiftUI's "re-evaluate only readers")?

**Evidence** (`swift-observation-nested-scopes.swift`, Swift 6.4 / macOS 27):
access lists **merge upward** — a read in an inner `withObservationTracking`
call is also registered with every enclosing call (N: write a, read only inner,
fires inner and outer; M: the same), and the order of the two callbacks varies
between runs; a per-scope token read inside the session and written before
re-evaluation gives exactly one live session (T: 50 re-evaluations, 49 flush
callbacks, 1 `onChange` after a write) where without it the sessions accumulate
(U: 50) — `RedrawSentinel`'s trick, generalised. Public API only (nothing here is
SPI), so Linux and Windows behave as the toolchain's Observation does.

**Ruling.** (1) Each memoized component has **its own session over its getter call
only** (`withObservationTracking { _ = token.tick; materialized = content }`): the
getter returns before `requestGroupLayout` evaluates any child, so these sessions
**never nest in one another** — no ancestor is fired by a descendant's read. (2)
Its handler checks a serial: a real change marks the entry stale and dirties the
window through the **same** entry point `markDirtyFromObservation` uses (both
branches, the `isFlushing` guard, `observationDirtyings`); a flush (the token
write before a re-evaluation bumps the serial first) does nothing. (3) The memo
session does not read the window's `RedrawSentinel`, so the per-frame flush does
not invalidate it, and a skipped component re-arms nothing (no accumulation).
(4) **The window's whole-frame session is untouched** (RX-K's orderings, the
sentinel, `isFlushing`, both branches). Automatic per-scope attribution replacing
it is **not ruled**: merging means a nested scope cannot be told from the outer,
so attribution needs the outer gone and every read site wrapped (root closure,
`ForEach` rows, `Canvas`/`GPUSurface` closures, user layouts) — a site missed goes
silently stale, where today's blanket session is safe by default. That is `IV-H`'s
prerequisite, not this item's. (5) An off-main write follows the existing
limitation: at most one stale frame, pinned as it stands (test 2.13).

**Cost if wrong.** If a toolchain stopped merging reads upward, the memo's own
sessions still work (they never relied on it) and the whole-frame session would
simply fire less; nothing breaks. If a getter read is made off a session (a
`nonisolated` hop), it is untracked exactly as it is today.

## IV-D — A memo's other inputs: own `@State` by version; `@Environment` and `@FocusState` refuse

**Question.** What else can change a getter's answer?

**Evidence.** `@State` lives in `StateTable` entries keyed by the component's id;
a write goes through `StateTable.write`/`withState`. `EnvironmentValues` stores
custom keys as `[ObjectIdentifier: Any]` and `Window.environment`'s documentation
says it "cannot compare an old and a new value", which is why every write dirties
the window. `@FocusState` is applied from input before a frame
(`applyPendingFocusStateWrites`, `IX-J`). `NodeView` in MetalCreator declares
`@Environment(ThemeStore.self)`.

**Ruling.** (1) `StateTable` keeps an **entry version** bumped on every write; the
memo records the versions of the component's own `@State` slots (found by the
cached reflection shape) and misses on any difference (ES). (2) A component that
declares `@Environment` or `@FocusState` is **refused**: evaluated every frame, a
`contentRefusals` count, no trap (divergence 346). (3) The adoption note for
MetalCreator: resolve the palette in the parent and pass it as a value input.
(4) A component-level **environment epoch** is carried (C14-c).

**Cost if wrong.** An author who needs the environment loses the memo until C14-c;
the counter says why. Allowing the environment without an epoch would be silent
staleness on a theme or locale change.

## IV-E — A layout memo by structural signature, never by node id

**Question.** The request wants layout to "re-measure only dirty paths, reusing
cached measurements elsewhere". CLAUDE.md says the invalidation cache "lives for
one call" and ids are per frame (C-3). What can persist?

**Evidence.** `NativeLayoutRun.cache` is keyed `(LayoutNodeID, ProposedSize)` and
dies with the call; `Frame` allocates a `LayoutTree` per frame and `reset` has no
production caller; a spacer's measurement depends on a mark its parent stack writes
after it registers (`spacerAxes`, CN-C), grid row tokens are fresh per frame
(`nextGridRowToken`), leaf measure functions and third-party layouts are opaque
closures/values. SwiftUI re-measured every sibling of a changed row in a custom
`Layout` (L-colour: fit x6 per row, half the first layout's, not confined to the
changed row; L-width: x12): layout skipping is MetalUI's own design here, not
parity.

**Ruling.** (1) A window-owned `LayoutMemo` keyed by a 128-bit **structural
signature** computed by one post-order pass over the run's reachable nodes **at the
start of the run** (so contextual marks are included; grid tokens are normalised
to row equality). It holds values (`LayoutMeasurement`, rects, widths) and **no
`LayoutNodeID`**; the per-call run cache and C-3's rule are untouched (CLAUDE.md's
sentence "the cache lives for one call" is amended in the Record phase to say the
*run cache* does). (2) A leaf contributes its **key**; no key means unique per run,
which unmatches exactly its ancestors. Lane 1 keys plain text, `Divider`, built-in
shapes and the gradient leaf only; every other leaf and non-`Hashable` custom layout
is unkeyed. (3) Two uses: **(M)** measurement by `(signature, proposal)`, **(P)** a
whole-run copy when `(rootSignature, proposal, bounds)` equals the previous run's,
restoring unrounded rects and measured widths and then running the same rounding
walk. (4) Entries live two runs. (5) `LayoutMemo.verifies` recomputes every hit
fresh and traps on a bit difference; the full suite is run once with it on. (6) A
render effect (`.offset`, `.scaleEffect`, `.rotationEffect`) registers no layout
node ("the child itself, for a paint-only modifier", `ModifiedContent.swift`), so a
drag by offset is a signature-identical frame: one lookup.

**Cost if wrong.** A key that omits an input the measure reads is a stale
measurement, silent and pixel-visible; the defences are the table-driven
"every registrar parameter is in its signature" test, the per-key "covers the
closure" tests, verify mode over the whole suite, and the conservative key list.
Hash collision: 2^-128 per lookup pair, accepted.

## IV-F — Nothing in S1 skips a phase, so every interaction is the unchanged one

**Question.** The request names identity resets, the lifecycle drain, animation
transactions and `AnimationStore`, `List` windowing, presentations, focus,
accessibility, the gesture arena and the hitbox list. Which does the first slice
touch?

**Ruling**, one line each, each pinned by the differential 2.9 (scene, hitboxes,
accessibility tree and focus order equal with and without `.equatable()` over a
12-step script) and the named test:
* **Identity** (`ID-B`, `ID-C`, `ID-R`, `DD-C`, `MC-A`/`MC-C`/`MC-P`, `.id()`
  outermost, the seven retention slots): `EquatableComponent` adds no id level or
  cursor index; `requestGroupLayout` (which runs `noteNamed`, `StateBinder.bind`
  and every nested bind) still runs on the reused value; a conditional inside a
  *skipped* content cannot flip (its inputs are equal), and one inside a
  re-evaluated content resets as today (2.6).
* **Lifecycle** (`LC-`, `.task`, `onChange`, `GeometryChangeScope`): presence is
  membership in a build and the elements are in the reused value (2.10).
* **Animation** (`AN-`, `AnimationStore`, transactions, keyframes): `withAnimation`
  writes `@State` → version → re-evaluation; the animator's trigger is an input;
  `AnimationStore` touches happen in `requestGroupLayout`/paint, kept (2.10).
* **`List` windowing, `DD-F`, `TB-AH`**: rows are produced by `List.requestLayout`,
  not a getter; a `List` inside a memoized component is a value (2.10).
* **Presentations, toolbar, preferences**: registered by elements in
  `requestGroupLayout`, kept.
* **Focus, accessibility, gesture arena, hitboxes (one ranking), text input**:
  registered in prepaint/`registerHandlers`, kept; `@FocusState` components refuse.
* **Layout memo**: sits under `computeNativeLayout`, so `lowering`, `hiddenNodes`
  and `LoweredItem` records (all registration-time) are untouched; presentation
  roots, the toolbar strip and the menu bar run through the same entry and the
  same memo.

**Cost if wrong.** A phase silently skipped would show in 2.9 first; the slice's
design makes that structurally impossible (no phase is conditional).

## IV-G — What stays whole-window, with numbers

**Question.** What does the first slice buy, and what does it leave?

**Ruling** (shares from `IV-A`, counts from the spec's table): after lane 1 the
layout kernel costs one lookup for a signature-identical frame and the changed path
for a text change (≤ 2 leaf measures, ≤ 2·(L+3) misses at depth L, vs 81 and 337 at
81 leaves); after lane 2 a one-leaf change evaluates 1 body, not 121. **Build
recursion (51%), prepaint (10%), paint (14%), sweeps (6%) stay whole-window.**
Together the slice is worth about a quarter to a third of render in the synthetic
tree and more where text measurement or a heavy `content` dominates; **it does not
meet PERF-b's 8.3 ms and says so**. The remaining 75% is `IV-H`.

**Cost if wrong.** If lane 1's win on real trees were nil (every frame's signature
differing because an unkeyed leaf sits at the root's path), the counters show
`layoutMemoHits == 0` and the lane is a no-op, not a regression; a root-path
unkeyed leaf is the first thing C14-b's keys address.

## IV-H — Retained subtrees (the full goal) are carried, with their design ruled

**Question.** What would skip the build recursion, prepaint and paint of an
unchanged `Component`, and why is it not this item?

**Evidence** (read from the source): `Frame` allocates a `LayoutTree` per frame and
every id carries its generation (C-3), so a skipped subtree has no nodes;
`ComponentLayout`/`ComponentPrepaint` are heap boxes `prepaintGroup`/`paintGroup`
mutate in place (`withPayload`, `withPrepaint`) and nested boxes are shared by a
struct copy, so a retained record is post-paint, not post-layout; `Frame` has ~110
stored per-frame channels, `StateTable`'s frame sets (`marked`, `namedPositions`,
`producedSlots`, `loopExtents`, `windowedParents`, `departedNames`) feed the sweep.

**Ruling.** The design for C14-b, not built here: (1) **persistent append-only
tree with epochs** — nodes of an unchanged `Component` keep their ids; the window
bumps the generation (a full rebuild, today's behaviour) when growth passes twice
the live count; a child's parent entry carries a frame serial so re-parenting a
retained root is legal (CN-L is about two parents in one frame); (2) **replay, not
element retention** — an eligible subtree's evaluation is *recorded* as data (layout
nodes by the persistent tree; `StateTable` frame-set deltas as a journal; scene
primitives, hitboxes, focus stops, accessibility emissions and touches of the
atlas/raster/surface/animation/lifecycle stores as ranges) and re-applied, so
`prepaint`/`paint` idempotence never matters; (3) **an eligibility gate by
ledger** — a `Frame` channel counter snapshot before/after the first evaluation;
any channel not in the replayable whitelist (presentations, scroll, named spaces,
drag, animations in flight, time reads) makes the subtree ineligible, and a
Mirror-based **classification guard** over `Frame`/`StateTable`/`AnimationStore`
stored properties fails when a new one is unclassified; (4) a replay key includes
the subtree's absolute bounds, clip stack top, opacity, layer, scale, theme and its
hover/active/focus membership; (5) the observation question of `IV-C` (4) must be
answered first or the memo sessions of this item are reused. Owner: **C14-b**.
Refused now: retaining the post-layout element record (idempotence unproven for
~100 element types and apps' own `Element`s).

**Cost if wrong.** If persistence proves too invasive for `LayoutTree`'s public
surface, a per-`Component` segment list (ids `(segment, local)`) is the fallback;
nothing in this item's memos depends on either.

## IV-I — GT-F: `drawText` stays deferred

**Question.** Record §99 deferred `MetalDrawContext.drawText` and its SDL twin to
C14's close-out: after incremental invalidation, is an element `Text` overlay still
too costly?

**Evidence/Ruling.** Lane 1's test 1.1 re-takes `theOverlayCostIsLinearAndCounted`
with a prediction fixed before the run (spec §8): per camera frame N labels moving
by `.offset` cost 0 layout measure calls, 0 misses, 0 seam measures and N
`placeGlyphs`, no raster/upload/texture. What remains per label is the element
construction in the root closure, the build recursion, an accessibility record and
one glyph placement. The first three are what retained subtrees (C14-b) remove for
an unchanged label; a `drawText` would also remove the label's accessibility
record, and a second text path in both renderers (`shaders.metal` and
`replay.hlsl` identically, TE-AD) is the larger cost. **Still deferred**; re-taken
at C14-b's close-out with the same test.

**Cost if wrong.** MetalCreator keeps labels as views; its S5-c entry already says so.

## IV-J — Verification: a differential and a verify mode, because the pins count work and work is not output

**Ruling.** Count pins prove work moved; they cannot prove the output did not. So
each lane carries an output-equality instrument: lane 2's differential 2.9 (the
same tree with and without `.equatable()` over a scripted sequence, comparing
scene arrays, hitboxes, the accessibility tree and focus order each frame) and
lane 1's `LayoutMemo.verifies` (every hit recomputed and compared bit for bit)
plus the whole suite run once under it (1.12). Together with the unmoved fourteen
images (0 px against `f6f865c1`) and `DemoFrameDeterminismTests`' `Expected.swift`
unedited.

**Cost if wrong.** A mutation that leaves the differential green is a finding about
the instrument, to be reported, not about the change.

## IV-K — Refused: automatic skipping, a layout cache keyed by id, and a reflective `==`

**Ruling.** (1) Automatic reflective skipping (SwiftUI's default) is refused: it
would make existing apps stale (a plain-class model read in `content` with
`setNeedsRedraw()`, the GT-A test's own shape). (2) A cross-frame layout cache
keyed by `LayoutNodeID` is refused: it reintroduces C-3's hazard (an id naming a
different node). (3) Comparing a component by `Mirror` field-by-field is refused:
it costs what it saves and cannot see closures' captures.

**Cost if wrong.** (1) is revisited only with C14-b's replay in place, where a
wrong skip is detectable by the verification mode.

## Carried (named, with owner)

C14-b retained subtrees (`IV-H`); C14-c an environment epoch so `@Environment`
components can memoize; C14-d per-`ForEach`-row and per-`List`-row scopes; subtree
placement memo (C14-b); leaf keys for rich text, images, `GPUSurface` and controls
(lane 1 follow-ups, one site each); MetalCreator adoption (its own plan).

## IV-L — Critic: divergence 345 refuted by a separating arm; `.equatable()` matches SwiftUI

**Question.** `IV-B` and the spec called `==`-decides a divergence (345) on the
strength of arm S, where a closure-holding and a fresh-class-instance view re-ran
under `.equatable()` although `==` said equal. U, the same view set bumped again,
did not re-run them and the header called it "unexplained".

**Evidence.** The probe gained arms S2 and S3 (two more identical bumps after U);
re-run twice at the critic: S: `Top, WithCapture, PlainTick, Eq-plain,
Eq-equatable(), EqRef`; U, S2, S3: `Top, WithCapture, PlainTick` only. The extra
runs in S happen on the first bump after the first render, whatever the cause.

**Ruling.** (1) Divergence 345 is **not taken** (label unused; 346 stays, the
`@Environment`/`@FocusState` refusal, which SwiftUI does not have). (2) `==`
decides is SwiftUI's behaviour for steady frames; the contract text stays, the
word "divergence" goes. (3) A `Component` cannot see the first-bump effect (our
first frame always evaluates), so nothing is built for it. (4) Lane 2's test 2.3
gains arm 2.3b: a `Button` whose closure was built in the evaluation of frame 1 is
invoked after 5 skipped frames and still writes the component's `@State` (a
pristine content reuses frame 1's closures; they must write through the
`StateTable`, not a stale box). (5) Lane 2's test 2.7 gains an arm: a component
that re-evaluates every frame lets the window go idle (the token write inside the
window's whole-frame session must not re-dirty it).

**Cost if wrong.** If the first-bump effect were real SwiftUI behaviour, MetalUI
is still a superset of skips; nothing is lost.

## IV-M — Critic: the signature pass is a cost to count, and two pins must be able to be red

**Question.** (1) Lane 1 adds a post-order signature pass to **every** run; the
spec prices only the savings. (2) Tests 2.10 ("none specific" mutation) and 2.12
(`theBareComponentPathIsUnchanged`, no red-before, no mutation) cannot be shown
red, against `docs/practices/verifying-tests-can-fail.md`.

**Ruling.** (1) `NativeLayoutWork` gains `signatureNodesHashed`; test 1.1/1.2 pin
it equal to the reachable node count (a hand-derived literal), and lane 1 records
in the record the phase-timing instrument's signature-pass share beside the
kernel's. If the pass costs more than half of the kernel time it saves on the
81-leaf tree, the lane reports it as a finding and does not claim the win
(`IV-G`'s numbers are then restated). (2) Test 2.10 carries the mutation "key the
entry by the component's type alone, ignoring its id" (two same-type siblings with
different `@State`, lifecycle counts and a windowed `List` row diverge from the
unmemoized tree); test 2.12 is **not a test**: it is the re-run of the existing
`ComponentTests` mutations recorded in `Component.swift`, listed by name in the
record. (3) A test whose "red before" reads "does not compile" (1.3) is red by its
stub returning a wrong rect, recorded as such.

**Cost if wrong.** A memo whose signature pass eats its savings ships as a
no-gain; the counter and the share make that visible instead of assumed.
