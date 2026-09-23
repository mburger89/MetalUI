# SwiftUI behavioral-alignment task list

## Goal and boundary

Replace MetalUI's CSS-derived layout model with a native SwiftUI-style layout
model, then make its public composition, layout, state, environment, input and
accessibility behaviour agree with SwiftUI wherever MetalUI exposes an
equivalent concept. This is **behavioural alignment**, not source-compatible
SwiftUI or a replacement for SwiftUI's platform framework.

SwiftUI's parent proposal / child measurement / placement model is the target;
CSS box, flex, grid, cascade and containing-block rules must not remain the
layout authority. The existing engine and WebKit corpus are temporary migration
evidence: retain them while ports are compared, then retire or reframe CSS-only
fixtures once their SwiftUI replacements are proven. Each difference must be
removed or retained as a documented, tested MetalUI divergence.

Every item that claims SwiftUI behaviour needs a small, versioned SwiftUI
probe with a positive control, followed by a MetalUI test whose alternatives
would produce different observations. Do not infer values, defaults, or
modifier placement from names alone.

*2026-09-14 (at `7cfcddc`):* this rule is not met yet. No SwiftUI probe
source is committed: no tracked file outside prose docs contains
`NSHostingView` or `import SwiftUI`. Commit `07e8615`, "Record SwiftUI aspect
ratio probe", touched only a test and this plan.

Every probe figure below survives only as a sentence here or in a test doc
comment, so none can be re-run. Most record no positive control. The same
range left no decisions doc and no mutation record for this milestone.

*Later on 2026-09-14 (task 2's completion):* two probes are committed, with
positive controls, under `docs/probes/`, and
`../2026-09-14-swiftui-alignment-decisions.md` (prefix `SA-`) records their
use and each ruling's mutations. They cover task 2's claims only; the figures
recorded as sentences for `a15ec83..7cfcddc` still have no source.

## Sequenced work

- [x] **1. Publish the replacement contract and CSS-debt inventory.**
  Catalogue every public `Element`, `ElementGroup`, modifier, container,
  interaction and environment API as: SwiftUI-aligned, CSS-derived,
  divergent, missing, or intentionally unsupported. Map every `Style`,
  `Display`, `LayoutTree` and `FlexEngine` concept to its replacement,
  deletion, or compatibility boundary. Give each entry a SwiftUI probe, a
  MetalUI proof, and an owner milestone. Reconcile the divergence table and
  remove CSS concepts from public documentation when they have no SwiftUI
  counterpart (for example, margin). The baseline inventory is
  [`2026-09-12-swiftui-layout-replacement-inventory.md`](../2026-09-12-swiftui-layout-replacement-inventory.md).

- [x] **2. Build the native layout kernel.**
  Replace CSS `Style` resolution and flex/grid placement with a layout protocol
  that receives a size proposal, measures a child response, caches the result
  for the frame, and places children in a resolved bounds rectangle. Establish
  the tree, invalidation, measurement cache, coordinate-space and pixel-rounding
  contracts before migrating public elements. Keep a temporary adapter only at
  the old engine boundary, never as the new layout authority.
  *Progress 2026-09-14 (at `7cfcddc`).*
  - **Done then:**
    - `ProposedSize`/`LayoutMeasurement`.
    - The per-call `(node, proposal)` cache.
    - Root-absolute placement.
    - Stored-rect rounding.
    - One root switch (`Frame.swift:1166`).
    - Eleven public `LayoutPass.requestNative*` registrars.

  *Closed 2026-09-14 on `feat/kernel-completion` (`3bb1ca1..553b980`).* Spec
  `specs/2026-09-14-native-kernel-completion-design.md`; rulings `SA-A`…`SA-U`
  in `../2026-09-14-swiftui-alignment-decisions.md`, each with a mutation
  record; probes in `docs/probes/`; record §09, "Kernel completion (task 2)".
  Each lane was written red first and its mutations re-run by an independent
  verifier. Suite 1084 tests (993 + 17 + 22 + 52), 97 goldens unmoved, 45
  guards (39 + 5 + 1), 0 `error:` / 0 `warning:`, re-taken at `553b980`.
  What was "Not done", item by item:
  - **A layout protocol — done** (`00a1e22`, lane 1, `SA-A`…`SA-F`).
    `ProposalLayout`, measurement proxies that cannot place, the `custom` node
    kind, `LayoutPass.requestNativeLayout`, `ProposalLayoutContainer` and
    `callAsFunction`. The eleven built-ins stay enum cases (`SA-B`).
  - **An invalidation contract — done** (`3c701a2`, lane 2, `SA-H`, `SA-I`).
    A cache per call and nothing surviving it; measurement never writes a rect;
    one `isLayingOut` flag for both engines, with registration, reset and
    re-entry trapping. It deliberately diverges from SwiftUI's cross-pass memo.
  - **Any adapter; native-under-legacy not rejected — the rejection is done,
    and "(c) an adapter" is ruled out, not built** (`3c701a2`, `SA-G`). Mixing
    traps in every direction. The root switch is the task's "old engine
    boundary", and no adapter was needed there.
  - **Validation, a depth guard and work counters — done** (`71c8b1c`, lane 3,
    `SA-J`…`SA-M`). Validation rejects only what SwiftUI rejects or what goes
    non-finite. `maxDepth` is 88 native nodes. `lastNativeLayoutWork` is
    counted on a branching tree.
  - **The migration story for external custom elements — done under `SA-R`'s
    amended criterion** (`00a1e22`, lane 1). It is compile-checked for every
    spelling an external module writes: four of lane 1's five file-scope,
    Swift 6 guards, the fifth being the `typecheckFile` instrument guard (the
    sixth guard in that file is lane 3's frame-split guard). A
    `ProposalElementGroup` conformer that registers a legacy node is a
    run-time trap, not a compile error; that check moves to task 3's open
    proofs.

  **Carried, not blocking.** These are coverage gaps that verifiers found by
  mutations that stayed green; each is listed in record §09:
  - the reference stack compares the horizontal path only — *closed
    2026-09-16 by `CN-B` (lane 1 compares a transposed tree; mutation F1
    re-run, now red)*;
  - the `measureDepth` bracket around built-in bodies;
  - `measureNativeLayout`'s flag, active-run and work-record assignments;
  - padding's right-inset term;
  - checkpoint 2's height and `lastBaseline`, and checkpoint 3's rect height.

  **Owned by later tasks** (`SA-N`):
  - a finite-`maxWidth` frame grows to its proposal, and argument-less
    `.frame()` is deprecated in SwiftUI (task 4) — *closed 2026-09-16 by
    `FR-A`/`FR-M` and `FR-J`*;
  - padding places its child at the child's size (task 5) — *2026-09-16: task
    5 did not take it (`OM-Q`, no kernel change); assigned to task 7 by `CN-Q`;
    **closed 2026-09-21 by task 7 stage 2's lane 3 (`LR-AU`)**, on both entries,
    pinned by `aNativePaddingPlacesItsChildAtTheChildsOwnSize`. `SA-N`'s list is
    now empty*;
  - `Spacer()`'s 8pt default minimum, and a single-child stack passing its
    child's priority through (task 6) — *closed 2026-09-16 by `CN-C` and
    `CN-D` (`feat/containers`)*;
  - `aspectRatio` at nil×nil (task 7) — *closed 2026-09-16 by `CN-G`*.

  Not in this task: replacing `Style` resolution and the legacy engine
  (task 7).

- [x] **3. Build a typed modifier-composition foundation.**
  Introduce a modifier wrapper representation that can nest without forcing
  callers to expose ever-growing concrete types such as `Box<Box<Box<Text>>>`.
  It must preserve structural identity, `@State`, handler registration,
  layout/prepaint/paint ordering, and stored subtrees. This is the prerequisite
  for converting the legacy direct-mutating size modifiers; plain return-type
  changes already break concrete `Box<T>` boundaries in the demo.
  *Progress 2026-09-14 (at `7cfcddc`; superseded by the 2026-09-15 closing
  note below, kept as history).* Proposal content has a
  concrete `ModifiedContent<Content>` over a closed `LayoutModifier` enum
  (`NativeModifiedContent.swift:9-31`). Legacy content has none: `.frame` is a
  standalone `FrameModifier`, and `.padding` returns `Box<Self>`.

  Open proofs:
  - No test checks `@State` across chained modifiers.
  - No test checks once-per-phase delegation.
  - `OverlayModifier` gives its primary element and its overlay element the
    same id, by reading of `NativeOverlayModifier.swift:28-33`.
  - *Added 2026-09-14 (`SA-R`).* Nothing checks **at compile time** that a
    `ProposalElementGroup` conformer registers native nodes. Task 2 closed its
    migration story under an amended criterion. Today a lying conformer traps
    at registration, pinned by
    `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`
    and `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`. `SA-R`
    sketches the compile-time mechanism, unmeasured: a typed native node id
    with no public initializer, returned by a new requirement.

  See the typed-modifier spec's Status.

  *Closed 2026-09-15 on `feat/modifier-composition` (`1c6f686..f4bf879`),
  integrated on `integrate/tasks-3-9-12` (record §13).* Spec
  `specs/2026-09-15-modifier-composition-design.md`; rulings `MC-A`…`MC-S` in
  `../2026-09-15-modifier-composition-decisions.md`; probes in `docs/probes/`;
  record §10. Each lane was written red first and re-verified by an
  independent verifier: 33 mutations, 32 reddened (one by truncating the suite),
  and the green one refuted a doc claim. On its branch: 1116 tests, 97 goldens
  unmoved, 53 guards. After the three-track integration: 1226 / 97 / 61.
  - **The representation — done** (lane 2, `MC-A`…`MC-C`, `MC-K`).
    `ModifiedElement<Content>` is one flat type for legacy `.padding` and
    `.frame`, reached through one overload per modifier via
    `ElementGroup.LayerBase`. `FrameModifier` is deleted. It is observationally
    identical to nested `Box`es; the solver work is bounded (guard) and the
    allocations are counted. **One per-element hook was not mirrored per layer
    and only the integration found it:** `AB-O`'s `display: none`
    accessibility suppression (red at the bridge merge, fixed in `fba579e`).
  - **`@State` across chained modifiers — done** on both paths (`MC-D`).
  - **Once-per-phase delegation — done** for every wrapper (`MC-F`), with
    `EnvironmentScope` arms added at integration.
  - **The overlay id — measured red, then fixed** (`6d89906`, `661efd9`,
    `MC-P`): the overlay numbers under `.child(of: id, at: -1)`, independent of
    the primary's shape, as SwiftUI's is (probe).
  - **`SA-R`'s compile-time check — done** (lane 3, `MC-G`, `MC-H`).
    `ProposalNodeID` has an internal initializer and is returned by
    `ProposalElementGroup.requestProposalGroupLayout`. Five lies are compile
    errors (six guards). Seven holes are named, each pinned or cited.

  **Carried, not blocking:** release-window captures of the default demo and
  the preview against `f64e58a` (an offscreen pixel stand-in reads 0 differing
  pixels, record §13; *real captures taken 2026-09-17, 0 differing pixels on both
  windows, record §03*); the `_wrap` hole; the shape-13 sweep; a shared
  `malloc_logger` counter. **Owned by later tasks** (`MC-L`): task 4 —
  `width`/`height`/min/max as layers and legacy `.frame` semantics; task 5 —
  `Component` distribution, B-7, hole 5 and paint-only layers; task 6 — hole 4
  and the one-node traps (*delivered 2026-09-16: hole 4 traps at run time,
  `CN-L`; the overlay side takes zero or several nodes, `CN-K`*); task 7 — unification with `ModifiedContent`, holes
  1–3, 6 and 7, and `_wrap`.

- [ ] **4. Finish frame and sizing semantics.**
  Specify and implement `.frame(width:height:alignment:)`, optional axes,
  min/ideal/max constraints, alignment within an offered proposal, and the
  ordering rules for chained frames. Move `width`, `height`, min/max sizing and
  alignment-facing convenience APIs onto that representation; deprecate APIs
  whose observable meaning cannot match SwiftUI. The additive
  `.frame(width:height:)` API exists; this task makes it the single semantic
  path.
  *Progress 2026-09-16, still open* (`feat/frame-sizing`, `4796bbb..3858eff`,
  integrated on `integrate/tasks-4-5`, record §16). Spec
  `specs/2026-09-15-frame-sizing-design.md`; rulings `FR-A`…`FR-V` in
  `../2026-09-15-frame-sizing-decisions.md`; four probes in `docs/probes/`
  (71 SwiftUI arms with positive controls); record §14.
  - **The kernel's flexible frame — fixed** (`FR-A`, `FR-B`, `FR-L`, `FR-M`):
    greedy at any maximum, `max(proposal, child)` with no minimum, declared
    negatives floored, an infinite proposal answering the child. `SA-N` items
    1 and 9 closed.
  - **The legacy frame's SwiftUI surface — done** (`FR-C`, `FR-D`, `FR-K`,
    `FR-O`, `FR-P`, `FR-S`): optional axes, min/max, the nine alignments,
    chained-frame ordering, one lowering in `FrameLayer.swift`; `ideal` traps;
    `.frame()` deprecated on both paths. Divergences 35, 36 and the single-axis
    inert row pinned wrong on purpose.
  - **The sizing inventory — ruled, not converted** (`FR-F`…`FR-I`, `FR-Q`,
    `FR-T`): `width`/`height`/min/max/percent stay CSS-box modifiers, with the
    node-count and automatic-minimum differences pinned; `width(percent:)`
    takes a fraction (divergence 40).
  - **Integration** (record §16): the frame layer carries task 5's decorations,
    hit-testing fields, focus ring, accessibility and the disabled gate on
    whichever side of it they are written; eight cross-track tests.

  **Not ticked, clause by clause.** "Move `width`, `height`, min/max sizing …
  onto that representation" is refused with measurements (`FR-F`, `FR-G`: the
  type-level blast radius and `.minHeight(0)`'s automatic-minimum override no
  layer can express) and moved to task 7 with a recipe. "Deprecate APIs whose
  observable meaning cannot match SwiftUI" is done for `frame()` only (`FR-J`);
  the rest is refused by the 0-warning gate (`FR-I`). "The single semantic
  path" is not met: two engines and two sizing vocabularies stay live; what is
  single is the parameter surface, the alignment vocabulary and the one
  lowering function. Also open: a greedy finite maximum, a single-axis infinite
  maximum and an overflowing oversized child on the legacy path (task 6),
  `ideal` on the legacy path (task 7), the `percent:` unit (task 6), the
  release-window captures (`MC-J`; `FR-V`; *taken 2026-09-17, 0 differing
  pixels on both windows, record §03*). *2026-09-16, task 6
  (`feat/containers`, record §17):* the oversized child overflows for a frame
  over one node (`CN-N`) and `percent:` is renamed `fraction:` (`CN-O`); the
  greedy finite and single-axis infinite maxima move to task 7 (`CN-Q`).

- [ ] **5. Finish outer modifiers and modifier order.**
  Complete the padding migration, then audit background, overlay, border,
  corner/clip shape, opacity, hit testing, focus drawing and content shape.
  Pin whether each wraps, distributes through a `Component`, or affects only
  paint. Test order-sensitive chains such as padding/background/frame/clip.
  *Progress 2026-09-16, still open* (`feat/outer-modifiers`,
  `981f78b..77740f8`, integrated on `integrate/tasks-4-5`, record §16). Spec
  `specs/2026-09-15-outer-modifiers-design.md`; rulings `OM-A`…`OM-AM` in
  `../2026-09-15-outer-modifiers-decisions.md`; five probes; record §15.
  - **Padding migration — done.** Element padding wraps (`f1944f8`);
    `Component` padding wraps each top-level node and accumulates (`OM-D`,
    `OM-E`); one shape on all three columns of spec §3.1.
  - **Audit — done**, spec §3.1, three columns. Legacy `overlay` is audited as
    "not offered; use `Stack` or `Deferred`" (task 6/7; *2026-09-16: task 7,
    `CN-Q` — a second subtree is the `ModifiedContent` unification*).
  - **Focus drawing and content shape — delivered**: `focusBorder` (the focus
    ring, `OM-L`) and `contentShape(inset:)` (`OM-J`), with `border`,
    `opacity`, `clipped()` and `allowsHitTesting` on the legacy path;
    `borderWidth(_:)` deleted; divergence 15 fixed.
  - **Order-sensitive chains — pinned**: padding/background (A1–A3, E1–E3),
    clip (`.clipped()` on a two-layer chain), hit testing (P1/P2, N1/N2,
    X0–X3), `Component` orders (G13–G16), and at integration the
    frame/background orders (probe B1/B2/D1/D2, record §16 test 8) and
    `contentShape` across a wrapper (probe S0–S3, divergence 50).
    Divergences 41–50 recorded.

  **Not ticked.** "Pin whether each wraps, distributes through a `Component`,
  or affects only paint" is pinned table-driven for the two legacy columns
  only (`everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`);
  the proposal column rests on the per-modifier tests each landed with in task
  2, never collected or checked row by row (spec §3.2; the integration step did
  not add a proposal-row shape). Also open, beyond the task's text: the
  `.cornerRadius`/`.background` and `.cornerRadius`/`.border` orders
  (`swiftui-border-clip-paint` C3, D1) have no test; the focus ring's look;
  the release-window captures (*taken 2026-09-17, 0 differing pixels on both
  windows, record §03*).

- [x] **6. Port SwiftUI's container algorithms to the proposal path and audit the legacy containers.**
  Make `HStack`, `VStack`, `ZStack`, `Spacer`, `.overlay`/`.background`
  content and `ProposalScrollView` agree with SwiftUI's probed distribution,
  spacing, alignment, root placement and scroll axes; audit `Row`, `Column`,
  `Stack`, `Box`, `ScrollView`, `List` and `Deferred` against them, pin each
  difference, and hand the replacement of the legacy spellings to task 7.
  *Amended and ticked 2026-09-16 by the user's acceptance of `CN-T`.* The
  original text read: "Replace containers with SwiftUI-style algorithms. Audit
  `Row`, `Column`, `Stack`, `Box`, `Spacer`, `ScrollView`, `List`, and
  `Deferred` against `HStack`, `VStack`, `ZStack`, `Spacer`, `ScrollView`,
  `List`, and overlay/presentation patterns. Port stack, overlay and spacer
  algorithms directly to the new proposal system. Cover proposal propagation,
  explicit versus platform-default spacing, all nine `Alignment` positions,
  frame alignment, and scroll axes. Preserve the existing centred stack
  defaults only where probes confirm them." Replacing the legacy containers
  moved to task 7 with it. Merged to `feat/review-fixes` at `ba1ebba`.
  *Progress 2026-09-16 on `feat/containers` (`75b5f69..`, from `9e439cb`);
  written while the task was open under its original text.* Spec `specs/2026-09-16-containers-design.md`; rulings
  `CN-A`…`CN-U` in `../2026-09-16-containers-decisions.md`; probes
  `docs/probes/swiftui-stack-algorithms.swift` (revision 10) and
  `swiftui-overlay-presentation.swift`; record §17. Five lanes, each red first;
  all five verified `ok` (lane 3 only at the closeout, whose independent
  verifier re-ran its mutations C–K; record §17's last section). Suite 1355
  (1303 + 52) at the Docs phase, 1357 after the closeout; 97 goldens unmoved,
  70 guards.
  - **Proposal containers — SwiftUI's** (lanes 1–4): stack distribution
    (least flexible first, lower minimums reserved, sum of answers), `Spacer`
    (−∞ priority, default minimum 8, 0 on its stack's cross axis), per-edge
    default spacing, typed stack alignments, `ZStack` placement, the centred
    root, overlay/background content with `.background(alignment:content:)`,
    the duplicate-parent trap, the scroll view's cross axis. `SA-N` items for
    `Spacer()`, `aspectRatio` at nil×nil and single-child priority closed;
    `FR-B` reversed.
  - **Legacy path** (lane 5): a legacy frame over one node overflows both axes
    (`FR-N` closed); `fraction:` sizing with `percent:` deprecated (`FR-T`
    resolved); `Row`/`Column` gap 0, `Stack` fit-content and `ScrollView`'s
    cross axis pinned as divergences 52–54.

  **Not ticked, clause by clause.**
  - *"Audit `Row`, `Column`, `Stack`, `Box`, `Spacer`, `ScrollView`, `List`,
    and `Deferred` against … overlay/presentation patterns"* — **done** (spec
    §3's table; probe K6 for `List`, P0–P6/H0–H3 for presentation; `Spacer`
    has no legacy counterpart).
  - *"Port stack, overlay and spacer algorithms directly to the new proposal
    system"* — **done** (`CN-B`…`CN-K`).
  - *"Cover proposal propagation, explicit versus platform-default spacing, all
    nine `Alignment` positions, frame alignment, and scroll axes"* — **done
    except two-axis scrolling** (task 10, `CN-M`); the nine positions are
    pinned for `ZStack`, `.overlay` and both frames, three per axis for the
    linear stacks; `.background(alignment:content:)` has three positions
    pinned (A9: `.topLeading`, `.center`, `.bottomTrailing`), not nine
    (*corrected by the branch checker, 2026-09-16*).
  - *"Preserve the existing centred stack defaults only where probes confirm
    them"* — **done** (A1–A3, A6, A9, K5g/K5h confirm centring).
  - *"Replace containers with SwiftUI-style algorithms"* (the title) — **not
    met**: no legacy container is replaced or lowered (`CN-A`), by ruling.

  **Not done, by ruling (`CN-A`, `CN-Q`):** the root switch, lowering the
  legacy containers, a windowed proposal `List`, a proposal portal for
  `Deferred`, legacy `.overlay` and the legacy frame's greedy finite and
  single-axis infinite maxima go to task 7; two-axis scrolling to task 10;
  text-edge spacing to task 11. **Before merging:** an independent verifier
  should re-run lane 3's mutations C–K and decide F (probe V1k mirrored, then
  an arm in test 3.6; record §17). *Branch checker, 2026-09-16:* re-ran
  lane 3's C (red, 3.6 only, 24 issues) and F (green, confirmed) plus two lane 1
  mutations, and re-took the twelve images with identical figures; C's
  siblings D–K were not re-run, so lane 3's re-verification is still
  incomplete. It also found an unfixed regression from `CN-N`:
  `.frame(…).hidden()` on a legacy element no longer hides (record §17,
  "Branch checker"). *Closeout, 2026-09-16* (record §17, "Closeout"): the
  `hidden()` regression is fixed, for layout and accessibility, and pinned
  (`hiddenAfterASingleChildLegacyFrameStillHidesTheElement`,
  `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`); F is
  decided — probe revision 10's V1l/V1m confirm the trailing clause and test
  3.6's new arms redden under F. The closeout's independent verifier then
  re-ran C–K, every one red on named tests, and passed lane 3 (`ok: true`).
  Suite 1357, 97 goldens unmoved, 70 guards.

  **Proposed amendment (`CN-T`), for the user to accept or not:** retitle this
  task "Port SwiftUI's container algorithms to the proposal path and audit the
  legacy containers", with the body: *Make `HStack`, `VStack`, `ZStack`,
  `Spacer`, `.overlay`/`.background` content and `ProposalScrollView` agree
  with SwiftUI's probed distribution, spacing, alignment, root placement and
  scroll axes; audit `Row`, `Column`, `Stack`, `Box`, `ScrollView`, `List` and
  `Deferred` against them, pin each difference, and hand the replacement of the
  legacy spellings to task 7* — and append "including a windowed proposal
  `List` and a proposal portal for `Deferred`" to task 7's "Migrate the
  remaining elements off `FlexEngine`". If accepted, tick this task (lane 3's
  re-verification is done). If not, it stays open until task 7 replaces the
  legacy containers.

  *Superseded note, 2026-09-14 (at `7cfcddc`):* no listed legacy container was
  ported; `HStack`, `VStack`, `ZStack`, `ProposalScrollView`, a nine-case
  `ProposalAlignment` and a new proposal `Spacer` (no legacy `Spacer` existed
  at `a15ec83`) were built beside them; `List` and `Deferred` had no proposal
  counterpart. All still true except the alignment, now typed (`CN-I`).

- [ ] **7. Port advanced layout, then remove the legacy engine.**
  Implement the proposal-system equivalents of unspecified, ideal, min/max,
  fixed-size, layout priority, compression, expansion, grids and custom
  layouts. Migrate the remaining elements off `FlexEngine` (including a windowed
  proposal `List` and a proposal portal for `Deferred`; added 2026-09-16 by
  `CN-T`), delete the CSS
  layout paths and dead `Style` fields, and replace browser-fixture goldens with
  SwiftUI probes or deterministic native layout tests. No production layout
  request may pass through the legacy engine after this task.
  *Progress 2026-09-14 (at `7cfcddc`), still open.* The proposal path has
  unspecified/ideal/min/max frames, fixed-size, `aspectRatio` and
  `layoutPriority`. Grids, custom layouts and expansion of non-spacer children
  are absent. The default demo root and every legacy element still use
  `FlexEngine`. The 97 goldens are unchanged.
  *Corrected 2026-09-14 (task 2, `00a1e22`):* custom layouts now exist on the
  proposal kernel as `ProposalLayout` (`SA-A`…`SA-F`); grids and expansion of
  non-spacer children are still absent.
  *Corrected 2026-09-16 (task 6, `feat/containers`):* expansion of non-spacer
  children exists — a greedy frame takes a stack's surplus (`CN-B`, probe
  G4r/G4f); grids are still absent. Task 6 hands this task the lowering of the
  legacy containers and the root switch, a windowed proposal `List`, a
  proposal portal for `Deferred`, legacy `.overlay`, the legacy frame's greedy
  finite and single-axis infinite maxima, a frame over a multi-member
  `Component`, `SA-N`'s padding item and divergences 35, 52–56 (`CN-Q`).
  *Progress 2026-09-17 on `feat/engine-replacement` (`59fd180..aea19ed`, from
  `c2290fc`), stage 1 of 14, still open.* Spec
  `specs/2026-09-17-engine-replacement-design.md` (inventory §2, stage plan §4);
  rulings `LR-A`…`LR-AA` in `../2026-09-17-engine-replacement-decisions.md`;
  probe `docs/probes/swiftui-engine-replacement-stage1.swift` (revision 2);
  record §18. **Stages:** 1 lowering foundation; 2 flex-item semantics onto
  SwiftUI's; 3 `ScrollView` and `Component` distribution (delivered
  2026-09-22); 4 windowed proposal
  `List` (delivered 2026-09-23); 5 `Deferred` presentation and absolute
  positioning; G grids (delivered
  2026-09-21), G2 lazy grids after stage 4 — **unblocked**, since stage 4
  landed the windowing they need; 6a custom
  elements and the public legacy registrars deprecated; 6b the root switch
  (`noProductionFrameReachesTheLegacyEngine`); 7a goldens replaced; 7b
  non-golden CSS tests retired; 8 sizing vocabulary onto `.frame`; 9 engine
  deleted; 10 `Style`'s CSS fields and the `dlsym` closing check; 11 modifier
  unification. **Stage 1 delivered** (five lanes, each red first, all verified
  `ok`; lane 5 with four open minors — 5.8's doc comment and the bracketed depth
  boundary, `compareInWindows` with no caller, the lazy demo globals, 5.5
  passing on an empty bounds log): a per-frame layout authority (internal,
  legacy by default); every legacy site reporting or trapping by name; an
  element-bounds log and a differential harness comparing rects, scene,
  hitboxes, accessibility and state slots; `Text`, childless and container
  `Box`, `Row`, `Column`, `Stack`, `.padding` and `.frame` layers lowered onto
  the kernel on the stage-1 subset, animated; legacy ideal under the proposal
  authority (the legacy trap moved to registration, `LR-H`); mixed trees ruled
  (`LR-T`); the demo's content in a `MetalUIDemoContent` library (`LR-S`);
  pipeline parity (clicks, focus, keys, accessibility, state slots, animation),
  work and depth pins. Suite 1409 (1357 + 52), 97 goldens unmoved, 71 guards,
  re-taken after `swift package clean` at the Docs phase; twelve offscreen demo
  images 0 differing pixels at every lane; real-window captures not taken
  (`IOConsoleLocked` true throughout; *taken 2026-09-17 against `c2290fc`, 0
  differing pixels on both windows, record §03*). **Not done:** no production frame runs
  under the proposal authority; nothing deleted; no golden retired. Unspecified,
  ideal, min/max, fixed-size, priority, compression, expansion and custom
  layouts exist on the proposal path; grids are still absent (stage G — *delivered
  2026-09-21, see the note below*). The
  handed items above each have a stage (`CN-Q`'s 2026-09-17 amendment).
  *Progress 2026-09-21, stages 2 and G, integrated on `integrate/stage-2-grids`
  (`356bb2b` merges `feat/engine-stage-2`, `a948f8a` merges `feat/grids`); task
  still open.* **Stage 2 delivered** (spec
  `specs/2026-09-17-engine-stage-2-design.md`; rulings `LR-AB`…`LR-BA` in the
  same decisions doc; probe
  `docs/probes/swiftui-engine-replacement-stage2.swift` revision 4; record §21;
  five lanes, each red first, all verified `ok`, fourteen minors all
  dispositioned): flex-item semantics lowered **by the parent** under the
  proposal authority — item records and the unconsumed report, stretch and
  `alignSelf`, `flexGrow`/`flexBasis`/`flexShrink`, CSS minima and maxima folded
  into a declared size, the box model (border as insets, a `Text`'s padding
  around its leaf, the `BM-4` floor as a divergence, margin as outer padding),
  `justifyContent`'s distributions as spacers and the reverse directions as
  reversed nodes, animated values with structure from the declared style — plus
  two proposal-path answers that reach production (`SA-N` item 4, and a text
  measurement never wider than its proposal, which **closes divergence 59**).
  Its exit test reports no stage-2 field. **Stage G delivered** (spec
  `specs/2026-09-17-grids-design.md`; rulings `GR-A`…`GR-AT` in
  `../2026-09-17-grids-decisions.md`; ten runnable probes and three recorded
  corpora; record §22; four lanes, each red first, lanes 1/3/4 verified `ok` and
  lane 2's one major and one minor — both label-and-prose, no executable line —
  applied in its docs round): SwiftUI's `Grid` and `GridRow` on the proposal path
  as a kernel `NativeNode` case (`GR-C`), with the nil×nil and finite solves,
  spans, cell anchors, per-column alignment, unsized axes, the modifier-chain
  attribute walk, the element API and its identity rules, a grid in the proposal
  preview, and depth and work pins. Fourteen green mutations were found by the
  verifiers and pinned; two deliberately equivalent clamps are left unpinned and
  say so in the source. **Integration** (record §23): two conflict-free merges,
  four cross-track tests at the one seam the tracks share, each proven by a
  mutation — one of which, XM4, found that the **lowered** half of stage 2's text
  clamp was pinned by neither track. Suite 1409 → **1548** (stage 2 +51, stage G
  +84, the integration +4), 97 goldens unmoved, 71 → **75** guards (all four
  `GridCompileGuards`); nine of twelve offscreen demo images 0 differing pixels
  and the three preview images attributed cell for cell to stage G's preview
  grid, the merge itself 0 against `feat/grids`; no real-window capture (screen
  locked, `FR-V`). **Not done:** production still runs the legacy authority
  (stage 6b); percentages, unequal grow weights, a length `flexBasis`, a
  non-greedy `maxSize`, `baseline`, `hidden()` and `space-*` on an unsized grown
  container still report by name, each with an owner (stage 8, task 11);
  divergence 60 (SwiftUI's integer text width) is new and unpinned; lazy grids
  (`LazyVGrid`/`LazyHGrid`/`GridItem`) are out of scope and proposed as **stage
  G2, after stage 4**, which owns the windowing they need (`GR-L`); no human has
  looked at a grid on screen (task 15's closeout, `GR-N`).
  *Progress 2026-09-22 on `feat/engine-stage-3` (`ca7272a` through the
  Docs-phase commit, from `57893d0`), stage 3 of 14, task still open.* Spec
  `specs/2026-09-22-engine-stage-3-design.md`; rulings `LR-BB`…`LR-BP` in
  `../2026-09-17-engine-replacement-decisions.md` (the same doc as stages 1 and
  2); probe `docs/probes/swiftui-engine-replacement-stage3.swift` (revision 2,
  groups V and W); record §25. **Stage 3 delivered** (five lanes, each with its
  own mutation table, all verified `ok`, thirteen minors all dispositioned):
  `ScrollView` lowers onto the kernel scroll viewport with stage 2's container
  lowering as its content and the viewport as its own item record; the lowered
  viewport fills its proposal on the scrolling axis, and divergence 54
  **survives** the lowering (pinned as a literal) rather than closing;
  `ProposalScrollView`'s private clamp and indicator fold into one shared
  `ScrollChrome`, the stage's only production-path edit; `$anim-content`,
  `$anim-viewport` and `ScrollContext` publication are unchanged, and `List`
  still windows against the published context; a `Component` amend lowers to one
  per-member native frame aligned per axis and a `.frame` layer over several
  members to a row of per-member frames, which is SwiftUI's answer to
  divergences 48 and 56 under the proposal authority. **Exit criterion met**:
  `ScrollRoutingTests` + `ScrollIndicatorTests` + `ScrollViewTests` run 34
  scenarios under **both** authorities, their 9 custom registrations re-spelled
  as native probe leaves, with a roll call that names any scenario that stops
  participating — inverting the lowered viewport's axis reddens 20 of the 34, on
  the proposal arm only. Suite 1550 → **1572**, 97 goldens unmoved, 77 guards
  (none added); twelve offscreen demo images 0 differing at every lane and twice
  more in verification, once with an independently written harness; **no
  real-window capture** (screen locked throughout, `FR-V`). **Not done:**
  production still runs the legacy authority (stage 6b); `List` windowing under
  the proposal authority is stage 4's and is checked only under the legacy one
  here; an `…unconsumed` regression now truncates the suite instead of failing
  by name; `ProposalScrollView` still publishes no `ScrollContext` and never
  animates (stage 11 / task 10).
  *Progress 2026-09-23 on `feat/engine-stage-4` (`6a943e1` through the
  Docs-phase commit, from `f2e981f`), stage 4 of 14, task still open.* Spec
  `specs/2026-09-23-engine-stage-4-design.md`; rulings `LR-BQ`…`LR-CG` in
  `../2026-09-17-engine-replacement-decisions.md` (the same doc as stages 1–3);
  **no new probe** — the SwiftUI answer is `swiftui-stack-algorithms.swift`'s
  K6, re-run and diffed byte-identical five times; record §27. **Stage 4
  delivered** (five lanes, each with its own mutation table, all verified `ok`,
  fifteen minors all dispositioned): `List`'s explicit site check is **deleted**
  and its realized rows are placed by a `WindowedRowsLayout` at
  `(firstIndex + i) × rowHeight`, each row consumed, planned and wrapped by
  stage 2's item machinery at `parentSite: .list`; the layout answers
  `rowHeight × logicalCount` on the height rather than SwiftUI's greedy answer,
  with the reason ruled (`LR-BR`); on the legacy path the windowing spacer is
  demoted from a `Box` element to a bare node, which moves the resident-entry
  formula to `2n + 5` and divergence 18's to `2n + 6` (crossing at 126 rows,
  measured). **Everything that had to survive did, and is now measured under
  both authorities**: row identity, `@State` and focus retention across a
  bounded excursion and their loss past it, the `AXTable` records and their
  `AXIndex`es, the unbounded-window and one-more-frame rules, `MP-I`'s cold
  frame, wheel routing, hit testing and the disabled gate — **not one literal
  moved** in the eleven retention and accessibility scenarios. Divergences 13
  and 14 **survive** and their pins now run on both authorities. **Exit
  criterion met**: 67 scenarios across ten files under both authorities with a
  roll call that names any scenario that stops participating, `ListTests`'
  custom rows re-spelled through the legacy lowering (a bare native leaf drops
  the item plan — measured, M3b), and `aListsWorkIsTheSameFor100kRowsAsFor500`
  running at both authorities counting native work: 17 / 103 / 120 at 500 rows
  and at 100 000, derived by hand from the window before the run. Suite 1580 →
  **1602**, 97 goldens unmoved, 77 guards (none added); twelve offscreen demo
  images 0 differing at every lane and twice more in verification, on a harness
  that is **committed this stage** (`docs/probes/demo-pixels/`), and **three
  real-window captures at 0**. **Not done:** production still runs the legacy
  authority (stage 6b); `Deferred` as a presentation root (stage 5) and
  `display: none` keep one `List` scenario each on the legacy arm; the
  nil-width measurement path is `O(logicalCount)`; five small test-file
  obligations are listed in record §27 §11.3. *Merged with `master` at
  `f5e5651` (the HarfBuzz shaper line, record §26) on 2026-09-23: 1617 / 97 /
  77 on the merged tree; this stage's record renumbered §26 → §27.*
  *Progress 2026-09-23 on `feat/engine-stage-5` (from `e5caefb`), stage 5 of
  14, task still open.* Spec `specs/2026-09-23-engine-stage-5-design.md`;
  rulings `LR-CH`…`LR-CS` in `../2026-09-17-engine-replacement-decisions.md`
  (the same doc as stages 1–4); probe `swiftui-overlay-presentation.swift`
  revision 2 (group Q added; P and H re-run byte-identical); record §28 (this
  branch — renumbered §29 at merge with `master`, whose portable-text line
  already took §28). **Stage 5 delivered** (three lanes, each with its own
  mutation table, all verified `ok`): a `Deferred` whose one content node is
  `.position(.absolute)` is now a presentation root under the proposal
  authority (`LR-CH`) — element → greedy W on each stretched axis (aliased as
  the element's rect) → padding for the given insets → a window-sized frame
  aligned per axis (`LR-CI`), laid out in its own native run **before** the
  root in `computeRootLayout` (`LR-CM`); the `Deferred` hands its parent a 0×0
  placeholder aliased to the content's rect, dropped by every lowered
  container (`LR-CK`). An in-flow `Deferred` is untouched. Two proposal-only
  answers are pinned by name (measured content at window − inset; a stretched
  axis keeps its inset box below its padding, `LR-CJ`); every case where the
  legacy containing block is not the window reports by name, owner stage 9
  (`LR-CL`); an absolute box **outside** a `Deferred` is removed from the
  proposal authority and reports `position`/`inset` at the consumer, owner
  stage 10 (`LR-CK`). Divergence 9 survives on both authorities; 10 is
  unchanged and gains SwiftUI evidence (agrees with SwiftUI's presentation,
  P4/P5; disagrees with its overlay, P1/P2); 11 is legacy-only from here
  (`LR-CN`); record §27 §8.2's claim that a `List` inside a `Deferred` aborts
  under `.proposal` is refuted (it was never measured — record §04's
  2026-09-23 section). **Exit criterion met**: `DeferredTests` (5 of 10
  element-level scenarios; the other five are pass-level and say so) and
  `AbsoluteOverlayTests` (1 of 1) run under both authorities, plus the
  must-not-move set through real `Window`s — the demo modal's scrim hoisting
  over everything and escaping the `ScrollView`'s clip and scroll translation,
  its click-to-dismiss and the wheel not scrolling the list beneath (`IN-W`),
  a presentation keeping its declaring scope's environment and not resetting
  opacity (`OM-AA`, divergence 46), nested presentations on one layer
  (`AP-H`), an animated inset, and accessibility/focus — all pinned through
  `PresentationWindowTests`, six scenarios under both authorities. The roll
  call is now 82 scenarios across fifteen files. Suite 1617 → **1632**, 97
  goldens unmoved, 77 guards (none added); twelve offscreen demo images 0
  differing at every lane; **no real-window capture** (screen locked
  throughout every lane). **Not done:** production still runs the legacy
  authority (stage 6b); the four `deferred.*` reports, the two `…absolute`
  reports and the consumer-side `position`/`inset` report are each owed a
  deletion once their owning stage lands; the real-window capture this stage
  owes stays open until the screen is next unlocked (not owed for acceptance:
  no legacy path changed).

- [ ] **8. Audit composition and identity.**
  Verify `Group`, conditional content, explicit identity, `Component`, and
  modifier placement against SwiftUI custom-view behaviour. Preserve MetalUI's
  structural identity model where it matches, and close or document the
  currently known state-retention and reused-value aliasing differences.

- [ ] **9. Expand the environment and control-state model.**
  Evolve `Theme` into scoped environment values: enabled state, layout
  direction, locale, dynamic type/scale, control state and platform metrics.
  Add read/write environment modifiers with nearest-ancestor precedence; do
  not recreate a CSS cascade. Resolve the existing `Binding` naming collision
  before introducing SwiftUI-like bindings.
  *Progress 2026-09-15, still open* (`feat/environment`, rulings `EV-A`…`EV-Z`,
  record §11; integrated, record §13). Delivered: `EnvironmentScope` with
  nearest-writer precedence and no cascade (`.environment`,
  `.transformEnvironment`, `.theme`, `.dynamicTypeSize`), `@Environment`,
  `Window.environment`; enabled state (`.disabled`, one gate in
  `Frame.registerHandlers`, reaching accessibility); layout direction (carried,
  no container mirrors, `EV-K`); locale (carried, no consumer); dynamic type
  (`dynamicTypeSize`); platform metrics (`pixelLength`); and the `Binding`
  collision resolved as `KeyBinding` with a deprecated alias. **Not delivered:
  "control state" apart from enabled state** (`controlActiveState`,
  `controlSize` are `EV-Q` items for task 12) **and "scale"** (`displayScale`
  is not exposed, `EV-J`, divergence 24). The release-window capture is untaken.
  Tick when control state and scale land, or when this text is amended to drop
  them.

- [ ] **10. Align data-driven controls and scrolling.**
  Define `ForEach`/identified-data semantics, bindings, common controls and
  selection. *Note 2026-09-15 (task 9):* the deprecated `Binding` alias (for
  `KeyBinding`) is deleted in the change that introduces a SwiftUI `Binding`;
  wheel scrolling under `.disabled` (SwiftUI unmeasured; MetalUI's `ScrollView`
  still scrolls, pinned as it stands) is `EV-Q`'s item for this task. Rework `List` and `ScrollView` limitations that make ordinary
  SwiftUI layouts blank or state-destructive, while retaining virtualization as
  an internal implementation choice. Specify scroll position, indicators and
  programmatic scrolling.

- [ ] **11. Close text, shape and rendering-facing semantics.**
  Add the overlapping SwiftUI text controls: foreground style, font metrics,
  line limit, truncation, multiline alignment, baseline alignment and dynamic
  type response. Then cover shapes, images, fills/strokes, overlays and
  clipping where MetalUI exposes them. Keep renderer constraints explicit when
  an exact effect is not supportable yet.

- [ ] **12. Align interaction, focus and accessibility.**
  Specify gesture composition, button semantics, disabled behaviour, keyboard
  focus, pointer hit testing and content shapes. Deliver the missing native
  accessibility bridge and validate it with VoiceOver; until then MetalUI
  cannot claim complete SwiftUI-level application behaviour.
  *Progress 2026-09-15, still open.* Accessibility bridge half delivered on
  `feat/ax-bridge` (`AB-A`…`AB-AG`, record §12; integrated, record §13):
  NSAccessibility elements keyed by id, roles/labels/values/traits, screen
  frames, hierarchy, focus, press/increment/decrement, coalesced notifications,
  `List` as `AXTable` with `AXRowCount`; disabled elements publish disabled with
  no actions (the joint test, written at integration). Disabled behaviour is
  task 9's `.disabled` gate. **Open:** the VoiceOver script (record §12), which
  nobody has run; gesture composition, button semantics, content shapes and the
  rest of the interaction half; focus retention on disable (divergence 21), raw
  keys on a disabled ancestor (22) and a disabled look are unowned;
  `controlActiveState`/`controlSize` (`EV-Q`).

- [ ] **13. Complete transaction and animation semantics.**
  Make modifier wrappers participate in transactions at their correct phase,
  then add environment-driven Reduce Motion and document the supported
  transition surface. Retain the existing distinction between layout and paint
  animation, and drive all animation tests by timestamps rather than sleeps.

- [ ] **14. Resolve platform completeness.**
  MetalUI is macOS-only today. If “complete SwiftUI alignment” includes
  SwiftUI's Apple-platform scope, implement and verify iOS/iPadOS platform
  conformers, touch input, safe areas, lifecycle and native accessibility.
  Otherwise record macOS-only as an explicit product boundary rather than an
  implied parity claim.

- [ ] **15. Run the replacement closeout.**
  Re-run the full inventory; require that no public behaviour is unclassified,
  each supported overlap has a probe and discriminating MetalUI test, and each
  remaining difference is documented. Update migration guidance and public
  API documentation, run the full suite and relevant human visual checks, and
  ensure the retired CSS engine has no production caller, and remove or
  reclassify all browser goldens as migration-only historical evidence.

## Current starting point

*Re-checked against the source at `7cfcddc` on 2026-09-14.* At that commit:
- 993 tests pass.
- There are 97 browser goldens, the same count as before this range.
- There are 39 typecheck guards: `ElementGroupTrapTests` went from 1 to 5.

The orchestrator measured those counts; this edit did not re-run them.
Bullets a reader refuted or found overstated are corrected in place, and
facts the list omitted are appended at the end. "By reading" marks a claim
derived from source and not executed.

- Structural identity, component flattening/distribution, centred `Row` and
  `Column` defaults, `Stack` alignment, and theme propagation already contain
  measured SwiftUI-inspired work; they still belong in the inventory audit.
- *History (2026-09-15): the `FrameModifier` bullets below describe `7cfcddc`.
  Task 3 deleted `FrameModifier`; `.frame`/`.padding` now add a
  `ModifiedElement` layer with arms in every per-site guard, and the overlay
  collision is fixed (`MC-P`).*
- `.frame(width:height:)` has been added as an additive wrapper API on every
  `ElementGroup`. It returns `FrameModifier<Self>` (`FrameModifier.swift:63-67`).
  - `FrameModifier` is a full `StyledElement` that registers a CSS node
    centred with `alignItems`/`justifyContent = .center`, with a definite
    `size` on each axis it is given (`FrameModifier.swift:17-24`). It has no
    proposal to pass down; its content are flex items laid out against that
    definite size (`:41`). By reading, content with its own size responds to
    it the CSS way: default `flexShrink` is 1 (`Style.swift:132`), so a
    max-content `Text` shrinks and wraps to fit, and percentage sizes resolve
    against it. Only content-less content fails to adopt it: a childless `Box`
    inside it stays 0×0.
  - It is a registering site in both phases: `animated` (`:40`),
    `registerHandlers` (`:48`), and `animatedBackground` plus `pass.fill`
    (`:55-57`).
  - No per-conformer or per-site guard has an arm for it. `FrameModifier` and
    `.frame(width` appear in `Tests/` only in `ComponentTests.swift` and one
    overload test.
- The parallel native composition surface now has proposal-layout frames
  (fixed, min/ideal/max and flexible axes), padding, fixed-size, background,
  border, rounded clip and overlay attachment wrappers. It also has opacity,
  allowsHitTesting, onTap, aspectRatio and layoutPriority. Its frame and paint
  ordering are covered by deterministic native tests, and the opt-in demo
  exercises the paint wrappers.
  - The demo is `METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo`
    (`Sources/MetalUIDemo/main.swift:1009`), and the value must be exactly `1`.
  - None of these wrappers animates. No `Native*`/`Proposal*` source file calls
    `animated`, `animatedBackground` or `noteActiveAnimation`.

  This is migration evidence for tasks 2–5, not completion: the established
  public `.frame`, direct sizing APIs, and ordinary legacy elements still route
  through the CSS-derived engine.
- The proposal-layout preview and its new interaction/paint surface use the
  canonical SwiftUI-facing vocabulary: `HStack`, `VStack`, `ZStack`, `Spacer`,
  `Rectangle`, `Color`, `ProposalFrame`, `Background`, `ProposalAlignment`,
  `ProposalStackAxis`, `ProposalMeasureFunction`, `ModifiedContent`, `LayoutModifier`, `.onTap`,
  `.allowsHitTesting`, `.opacity`, `.padding`, `.background`, `.border`,
  `.clip`, `.fixedSize`, and `.overlay`.
  - The list also covers `Padding`, `FixedSize`, `ProposalScrollView`,
    `ProposalText`, `OnTapModifier`, `OverlayModifier`, `ProposalElementGroup`,
    `.aspectRatio` and `.layoutPriority`.
  - Their `Native…`/`native…` predecessors remain deprecated source-compatible
    migration aliases, **except `nativeFrame(...)`**
    (`NativeModifiedContent.swift:147`). It has no `@available` and is a live
    duplicate of the proposal `.frame(...)`, used six times in
    `NativeLayoutIntegrationTests.swift`.
  - The direct legacy `.frame(width:height:)` is still a distinct CSS-era path
    and needs its own replacement rather than being silently conflated with
    this one.
  - Proposal `.frame` and `.background` share spellings with the legacy ones.
    Overload resolution picks the proposal wrapper for a `ProposalElementGroup`
    receiver (`proposalLayoutFrameUsesTheTypedProposalWrapper`).
- The native `HStack` and `VStack` defaults are both **probe-described** at
  8pt. The source hard-codes `spacing: Pixels = Pixels(8)`
  (`NativeElements.swift:16, 58`), and the kernel's own default is 0
  (`LayoutTree.swift:245`).
  - The vertical probe, per the doc comment on
    `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`, hosts 20×10
    and 20×30 children in a fitting `VStack` and measures 20×48.
  - Its source is not in the repository, and it covers one pair of rectangles.
    SwiftUI's default spacing depends on the adjacent views, which is
    unprobed.
  - Explicit-zero controls pin both defaults separately
    (`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` and its
    vertical twin).
  - *History as of 2026-09-16 (task 6):* `spacing: nil` is the platform
    default decided per adjacent pair — 8, none at a spacer's edge (`CN-H`,
    `docs/probes/swiftui-stack-algorithms.swift` S, SP, K3, V); text edges
    remain 8 (divergence 51).
- The proposal path has an explicit `aspectRatio(_:contentMode:)` wrapper with
  deterministic fit/fill proposal and placement tests. A macOS SwiftUI custom
  `Layout` probe observes a 2:1 child offered 100×80 responding 100×50 for
  `.fit` and 160×80 for `.fill`, matching the native tests. It is measured
  task-7 migration evidence; advanced sizing beyond aspect ratio remains open.
  - The native tests (`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
    `aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`)
    use a *fixed 20×10* leaf, which the wrapper stores at the ratio size
    (100×50 / 160×80). The probe's child is described as responding at the
    ratio, so the two agree on the wrapper's size but not on what a smaller
    child does.
  - Only the both-axes-finite branch is tested. The single-axis branch, which
    ignores the content mode, and the unspecified branch, which fits inside
    the intrinsic size, are unpinned (`LayoutTree.swift:753-781`).
- A proposal `HStack`/`VStack` now distributes a constrained main-axis proposal
  by priority before compressing flexible children. The macOS SwiftUI custom
  `Layout` probe gives two 80pt-flexible children 50pt each inside a 100pt
  `HStack`, while a priority-one first child receives 80pt and its sibling the
  remaining 20pt; deterministic native tests cover both observations. This is
  deliberately the measured flexible-child slice of task 7, not a claim that
  arbitrary view compression, expansion, grids, or custom layouts are done.
  - **Mechanism** (`LayoutTree.swift:685-713`). Priority groups are visited in
    descending order. A group that fits gets its natural sizes; otherwise every
    member gets an equal share and lower groups get 0. An unused share is not
    redistributed.
  - **When it runs.** The step runs only when the stack overflows **and has no
    spacer** (`:689`). An overflowing stack that contains a `Spacer` therefore
    compresses nothing.
  - **Expansion.** Non-spacer children never receive surplus, so by reading,
    `.frame(maxWidth: .infinity)` inside an `HStack` does not expand.
  - **Tests.** Coverage is element-level only (`hStack…`/`vStack…` in
    `NativeLayoutIntegrationTests.swift`). `NativeLayoutTests.swift` has no
    priority test.
  - *History as of 2026-09-16 (task 6):* the mechanism, the no-spacer gate and
    "non-spacer children never receive surplus" are refuted and replaced by
    SwiftUI's distribution (`CN-B`: lower minimums reserved, least flexible
    first, the sum of the answers), pinned in
    `NativeStackDistributionTests.swift`; the 80/20 and 50/50 figures still
    hold.
- A proposal `Spacer(minLength:)` retains that minimum when a stack receives a
  smaller main-axis proposal, matching a macOS SwiftUI probe: the stack reports
  its overflowing minimum rather than compressing the spacer away.
  - `Spacer()` with a nil `minLength` means 0 in the kernel
    (`LayoutTree.swift:234`). That default is unpinned and unprobed, because
    every test passes an explicit minimum.
  - A spacer also takes the proposal on the **cross** axis
    (`LayoutTree.swift:397-401`), pinned as-is by
    `aNativeLinearStackDividesConcreteSurplusBetweenSpacers`. SwiftUI's
    behaviour here is unprobed.
  - *History as of 2026-09-16 (task 6):* a nil `minLength` is 8 and a spacer
    answers 0 on its stack's cross axis, both probed (`CN-C`, SP1, SPB1–SPB6).
- All nine `ProposalAlignment` positions are deterministically covered at the
  native overlay placement boundary; each named case has a distinct expected
  position rather than relying on independent horizontal/vertical factor tests.
  - `HStack`/`VStack` accept the same nine-case type but read only its
    cross-axis factor (`LayoutTree.swift:594-606`). `HStack(alignment: .leading)`
    places like `.center` with no diagnostic. This is deliberate, not an
    oversight: `newNativeLinearStack`'s doc comment says so
    (`LayoutTree.swift:240-243`), and
    `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly`
    (`NativeLayoutTests.swift:364`) pins it. That is the test a main-axis
    alignment change must redden.
  - SwiftUI types these as `VerticalAlignment`/`HorizontalAlignment`.
  - *History as of 2026-09-16 (task 6):* so do `HStack`/`VStack` now
    (`CN-I`, guards G1–G3); the nine-case initializer is deprecated.
- `ProposalScrollView` is the proposal-layout migration path for scrolling:
  it measures content with an unspecified scrolling axis, retains a concrete
  parent viewport proposal, and reuses MetalUI's clipped wheel-routing and
  indicator behaviour. macOS SwiftUI pixel probes measure direct content
  children with an 8pt **vertical** gap for both scroll axes, so multiple
  proposal children lower to a vertical native stack while a single composed
  child remains transparent. A fake-platform integration test proves a wheel
  event reaches its registered proposal viewport and updates its stable offset;
  a second proves prepaint writes an overrun offset back clamped to content.
  The source-compatible CSS-era `ScrollView` remains in place until the public
  container migration can replace it without mixing layout engines.
  - **Hard-coded stack.** The lowered stack is `spacing: 8`, `.center`,
    regardless of axis (`ProposalScrollView.swift:59-60`).
    *History as of 2026-09-16 (task 6):* default spacing (`spacing: nil`,
    SC3, SC5), and the viewport answers its content's size on the
    non-scrolling axis (`CN-M`).
  - **Hit-testing gate.** `.allowsHitTesting(false)` does not gate a scroll
    region: `registerScrollRegion` bypasses the depth check
    (`Frame.swift:501-503` vs `:655`). The only test is
    `allowsHitTestingFalsePreventsDescendantOnTapDispatch`.
  - **Divergence 16.** An `.onTap` inside a `ProposalScrollView` swallows the
    wheel by the same mechanism as a legacy `onClick` inside `ScrollView`. That
    is by reading and untested.
  - **Second `requestAnotherFrame()` caller.** Its indicator fade calls
    `pass.requestAnotherFrame()` (`ProposalScrollView.swift:106`), copying
    `ScrollView.swift:431`. CLAUDE.md's Animation section says
    `wantsAnotherFrame`'s "one caller is `ScrollView`'s indicator fade"; at
    `7cfcddc` there are two.
- A proposal frame now reports a clamped ideal dimension on an unspecified axis,
  matching a macOS SwiftUI probe: a 20pt child in `.frame(idealWidth: 80)` is
  offered and reports 80pt, while a concrete parent proposal still takes
  precedence. Horizontal and vertical deterministic tests cover the result.
  - A frame grows toward a larger finite proposal only when `maxWidth` or
    `maxHeight` is `.infinity` (`LayoutTree.swift:734-736`). A finite max does
    not grow it, as `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`
    pins: min 40 and max 80 at a proposal of 100 with a 20pt child give 40.
  - No SwiftUI probe for that case is recorded.
  - *History as of 2026-09-16:* a finite maximum now grows (`FR-A`, `FR-M`);
    the test pins 80 and the probe is saved
    (`docs/probes/swiftui-frame-semantics.swift`).
- The canonical no-argument `Rectangle` is now proposal-responsive: a macOS
  SwiftUI custom-Layout probe measures a 10pt ideal on each unspecified axis
  and the offered value on each concrete axis. The existing explicit
  `Rectangle(width:height:color:)` initializer remains the fixed-size
  migration convenience.
  - The proposal-responsive form answers `proposal ?? 10` per axis
    (`NativeElements.swift:415-422`), so an infinite proposal gets an infinite
    answer. Nothing validates it.
- Proposal containers and stored proposal wrappers now require
  `ProposalElementGroup` content at construction. This keeps **built-in**
  legacy CSS elements out of `HStack`/`VStack`/`ZStack`, proposal frames and
  outer wrappers before registration.
  - **Coverage.** Paired positive and negative compile guards cover all eleven
    content-taking constructors (`proposalLayoutConstructorsRequireProposalContent`,
    `ElementGroupTrapTests.swift:73`), plus `.overlay` and `.onTap` (`:20`,
    `:48`).
  - **What the guards miss.** No guard puts legacy content on the overlay
    side: neither the `content:` closure of `.overlay(alignment:content:)`
    (`NativeOverlayModifier.swift:56-57`) nor the `overlay:` closure of
    `OverlayModifier.init(content:alignment:overlay:)` (`:13-14`). Both
    rejection cases put legacy content on the primary side only
    (`ElementGroupTrapTests.swift:32-37, 135-139`).
  - **Boundary 1: the marker has no requirements.** `ProposalElementGroup` is
    public (`ProposalElementGroup.swift:8`), and the demo retro-conforms a
    `Component` and a hand-written `Element` to it (`main.swift:907, 938`). Any
    such conformer that registers legacy nodes compiles, then traps at
    `LayoutTree.nativeNode` ("native layout subtree contains a legacy node",
    `LayoutTree.swift:382`). No test pins that trap.
  - **Boundary 2: node count.** Single-child wrappers trap by precondition
    when proposal content yields zero or several nodes, e.g. an
    `OptionalGroup` whose condition is false.
  - **Boundary 3: the reverse direction.** A proposal subtree inside a legacy
    `Column`/`Row`/`Box` compiles and is not rejected. `newNode` validates only
    generations (`LayoutTree.swift:89-90`), and the root switch reads only the
    root. By reading, its nodes lay out as `Style.default` CSS nodes whose
    native measures never run: a native leaf is a childless default node,
    while a native container keeps its children, because every native
    registrar passes them to `newNode` (`LayoutTree.swift:125, 138, 159, 248`)
    and `FlexEngine` walks `tree.children` (`FlexEngine.swift:180`). No test or
    run confirms it.
  - **Boundary 4: if/else.** `EitherGroup` has no `ProposalElementGroup`
    conformance, so `if`/`else` inside a proposal stack presumably does not
    compile. This has not been typechecked.
- Proposal `Color` follows the same measured SwiftUI 10pt unspecified-axis
  ideal while continuing to fill every concrete proposal; all four proposal
  combinations are pinned in its native integration test.
- `Text.proposalLayout()` is the explicit bridge for proposal stacks while
  legacy `Text` retains its existing styled modifiers. It uses the same font
  resolution, shaping cache and width-driven wrapping as `Text`.
  - **Painting is not the same.** It paints glyphs only, with no background
    or hover/focus chain.
  - **The conversion is lossy.** It copies only `string`, `fontFamily`,
    `fontSize` and `foregroundColor` (`ProposalText.swift:93-99`), silently
    dropping style, decoration, handlers and `elementID`.
  - **Measurement differs.** It uses `shaped(wrappingAt:)` with
    `proposal.width.map { max($0, smallestWrapWidth) }`, with no min-content
    probe and no baselines (`ProposalText.swift:80-88`). That clamp is why
    `smallestWrapWidth` lost `private` (`Text.swift:21`).
  - **Wrap width is unpinned.** Its paint wraps at the native node's recorded
    measured width (`:65`), which no test asserts.
  - **Main-actor assumption.** Its measure closure uses an unguarded
    `MainActor.assumeIsolated` (`:49`), sound only while native layout runs
    synchronously on the main actor.
  - **Overload guard is one-sided.**
    `proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`
    typechecks only the proposal spelling and never compiles legacy
    `Text(…).background(…)`.
- Ordinary element padding now wraps its content (`f1944f8`): `StyledElement.padding`
  returns `Box<Self>` (`Box.swift:640-650`). `Component` padding remains a
  separately measured distribution case (`Component.swift:391-393`). Task 5
  decides the complete modifier matrix.
  - **Source break.** `Text(s).padding(4).font(…)` no longer resolves `font`.
  - **Chains nest.** Chained paddings accumulate
    (`chainedPaddingCreatesNestedWrappers`) instead of the later one winning.
  - **Later modifiers hit the wrapper.** Each wrapper is a default-`Style()`
    `Box`, and modifiers written after `.padding` configure it rather than the
    padded element.
  - **Identity moves.** The padded element sits one identity level deeper, so
    `.id(_:)` must be outermost.
  - **The default demo regressed, and was fixed by reordering** (window
    captures, 2026-09-14, record §03): container modifiers plus an inner
    `.flexGrow(1)` now precede `.padding`; size, background and corner radius
    follow it. Any other legacy caller that padded a container needs the same
    reorder, and nothing diagnoses one that does not.
  - **Tests updated.** `ModifierTests` dropped its two padding rows
    (`cases.count == 38`), and `ElementLayoutTests` was reordered and now
    expects 7 nodes.
  - **Demo not revisited.** The legacy demo still writes `.alignItems(.stretch)`,
    `.background` and `.cornerRadius` after `.padding` at its sidebar, root,
    main pane and modal (e.g. `main.swift:486-490, 859-866`). By reading, its
    layout changed. No look or capture has been taken since.
- Direct `width`/`height` still mutate style. Do not convert them before task
  3 establishes a composition representation that works across stored generic
  element trees **and** task 2 can propagate a frame's fixed proposal to its
  child. A trial wrapper conversion preserved concrete types but left the old
  CSS engine unable to offer that constraint to leaves; it broke list
  virtualization, hit testing, and text measurement. Keep `.frame` as the
  structural migration path until the native layout kernel owns proposals.
  - That trial is `4aaca40`, reverted by `d0a04d3`, and `Box.swift:593-599`
    still mutates `Style`.
  - *Corrected 2026-09-16 by `FR-F`:* two of the three breakage claims are
    refuted by measurement (a frame layer's width reaches a measured leaf and
    re-wraps it; a framed `List` paints the same rows) and the third is
    SwiftUI's own behaviour. What blocks the conversion is the type-level blast
    radius and the 0-warning gate. `width`/`height` still write `Style`, by
    ruling; task 7 owns the conversion.
  - The breakage it names is recorded only here, unverified.
- *Added 2026-09-14.* Native root behaviour. `Frame.computeRootLayout` selects
  the kernel when the root node is native (`Frame.swift:1166`). It proposes
  and places the root at the full content size and discards the root's
  measurement. A native root is therefore stretched to the window rather than
  sized to its answer, pinned by
  `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`.
  *History as of 2026-09-16 (task 6):* a native root is placed centred at its
  own answer (`CN-J`, probe R1/R2, `aNativeRootIsCentredAtItsAnswer`).
- *Added 2026-09-14.* Kernel robustness. The native path has:
  - no recursion-depth guard;
  - no `beginLayout`/`endLayout` re-entrancy check;
  - no cache work counters, so no count-the-work performance test is possible
    yet;
  - no input validation beyond the ratio and priority preconditions.

  *Closed 2026-09-14 (task 2, `feat/kernel-completion`):* all four now exist
  (`SA-I`, `SA-J`, `SA-L`, `SA-M`); see task 2's entry.
- *Added 2026-09-14.* Overlay identity hazard. `OverlayModifier.requestLayout`
  starts two independent cursors at 0 under one id
  (`NativeOverlayModifier.swift:28-33`), and each group's element takes
  `GlobalElementID.child(of: id, at: 0, …)` (`ElementGroup.swift:111`). So by
  reading the primary element and the overlay element themselves share one
  `GlobalElementID` unless one carries an `elementID`. That would share hover,
  press dispatch, `@State` and `ScrollState` between them. No test places a
  stateful or tappable element on both sides.
- *Added 2026-09-14.* Proposal interaction coverage. On the proposal path:
  - **Accessibility.** No element emits an AX node.
  - **Identity.** No element accepts `.id(_:)`; only `ProposalScrollView`
    takes an `elementID`.
  - **Focus.** No element takes focus.
  - **Tap tests.** There is no positive `.onTap` dispatch test.
    `onTapRegistersTheResolvedNativeBoundsAsAHittableTarget` asserts only that
    a hitbox exists.

## Definition of done

The project may say it is SwiftUI-aligned only for its declared platform and
API scope when the closeout has no unclassified public behaviours, every claim
has measured evidence and a regression proof, each unsupported or intentional
divergence is prominent in the public documentation, and no production layout
request reaches the CSS-derived engine.
