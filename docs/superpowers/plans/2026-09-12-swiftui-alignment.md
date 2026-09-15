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
  - the reference stack compares the horizontal path only;
  - the `measureDepth` bracket around built-in bodies;
  - `measureNativeLayout`'s flag, active-run and work-record assignments;
  - padding's right-inset term;
  - checkpoint 2's height and `lastBaseline`, and checkpoint 3's rect height.

  **Owned by later tasks** (`SA-N`):
  - a finite-`maxWidth` frame grows to its proposal, and argument-less
    `.frame()` is deprecated in SwiftUI (task 4);
  - padding places its child at the child's size (task 5);
  - `Spacer()`'s 8pt default minimum, and a single-child stack passing its
    child's priority through (task 6);
  - `aspectRatio` at nil×nil (task 7).

  Not in this task: replacing `Style` resolution and the legacy engine
  (task 7).

- [ ] **3. Build a typed modifier-composition foundation.**
  Introduce a modifier wrapper representation that can nest without forcing
  callers to expose ever-growing concrete types such as `Box<Box<Box<Text>>>`.
  It must preserve structural identity, `@State`, handler registration,
  layout/prepaint/paint ordering, and stored subtrees. This is the prerequisite
  for converting the legacy direct-mutating size modifiers; plain return-type
  changes already break concrete `Box<T>` boundaries in the demo.
  *Progress 2026-09-14 (at `7cfcddc`), still open.* Proposal content has a
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

- [ ] **4. Finish frame and sizing semantics.**
  Specify and implement `.frame(width:height:alignment:)`, optional axes,
  min/ideal/max constraints, alignment within an offered proposal, and the
  ordering rules for chained frames. Move `width`, `height`, min/max sizing and
  alignment-facing convenience APIs onto that representation; deprecate APIs
  whose observable meaning cannot match SwiftUI. The additive
  `.frame(width:height:)` API exists; this task makes it the single semantic
  path.
  *Progress 2026-09-14 (at `7cfcddc`), still open.* The proposal
  `.frame(width:height:minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`
  exists, with deterministic tests. Legacy `.frame(width:height:)` has no
  min/ideal/max or alignment, and `width`/`height` still mutate `Style`.
  There are two semantic paths, not one.

- [ ] **5. Finish outer modifiers and modifier order.**
  Complete the padding migration, then audit background, overlay, border,
  corner/clip shape, opacity, hit testing, focus drawing and content shape.
  Pin whether each wraps, distributes through a `Component`, or affects only
  paint. Test order-sensitive chains such as padding/background/frame/clip.
  *Progress 2026-09-14 (at `7cfcddc`), still open.*
  - **Proposal path.** Background, border, clip, opacity, allowsHitTesting,
    onTap and overlay exist, and none of them animates.
  - **Legacy path.** Element padding wraps. Component padding distributes.
  - **Not done.** Focus drawing and content shape are absent, and no written
    wrap/distribute/paint-only matrix exists.

- [ ] **6. Replace containers with SwiftUI-style algorithms.**
  Audit `Row`, `Column`, `Stack`, `Box`, `Spacer`, `ScrollView`, `List`, and
  `Deferred` against `HStack`, `VStack`, `ZStack`, `Spacer`, `ScrollView`,
  `List`, and overlay/presentation patterns. Port stack, overlay and spacer
  algorithms directly to the new proposal system. Cover proposal propagation,
  explicit versus platform-default spacing, all nine `Alignment` positions,
  frame alignment, and scroll axes. Preserve the existing centred stack
  defaults only where probes confirm them.
  *Progress 2026-09-14 (at `7cfcddc`), still open.* No listed legacy container
  was ported. What was built instead is a parallel set: `HStack`, `VStack`,
  `ZStack`, `ProposalScrollView`, and a nine-case `ProposalAlignment`. A
  proposal `Spacer` was also added, but it is new rather than parallel: no
  legacy `Spacer` existed at `a15ec83` (`git grep -n Spacer a15ec83 -- Sources`
  finds nothing), and `NativeElements.swift:351` is the only definition, so
  this task's "Audit … `Spacer`" names a type the legacy path never had.
  `List` and `Deferred` have no proposal counterpart.

- [ ] **7. Port advanced layout, then remove the legacy engine.**
  Implement the proposal-system equivalents of unspecified, ideal, min/max,
  fixed-size, layout priority, compression, expansion, grids and custom
  layouts. Migrate the remaining elements off `FlexEngine`, delete the CSS
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

- [ ] **10. Align data-driven controls and scrolling.**
  Define `ForEach`/identified-data semantics, bindings, common controls and
  selection. Rework `List` and `ScrollView` limitations that make ordinary
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
  - The breakage it names is recorded only here, unverified.
- *Added 2026-09-14.* Native root behaviour. `Frame.computeRootLayout` selects
  the kernel when the root node is native (`Frame.swift:1166`). It proposes
  and places the root at the full content size and discards the root's
  measurement. A native root is therefore stretched to the window rather than
  sized to its answer, pinned by
  `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`.
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
