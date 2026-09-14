## SwiftUI alignment — a proposal engine beside the CSS engine (2026-09-11 … 2026-09-14)

**The record for `a15ec83..7cfcddc` on `feat/review-fixes`: 79 commits, authored
with Codex, that start the migration in
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`.** They add a second
layout engine to `Sources/MetalUILayout/LayoutTree.swift`: SwiftUI's
propose / measure / place model. They also add a public element and modifier
surface that only that engine lays out, and they change what the legacy
`.padding(_:)` returns. This file was written after the fact, on 2026-09-14,
from the source at `7cfcddc`, the commits, and four reader passes. The readers
were checked against the source before anything here relied on them. **The
source is the authority.** The two 2026-09-12 specs describe types that were
never built. Where they disagree with the code, see "Documents this range left
stale" below.

**Three things every earlier milestone had and this range does not:**

- a decisions doc (`ls docs/superpowers/*decisions*` ends at the animation
  milestone's);
- a ruling prefix (none is assigned, so there is nothing to cite, and a
  sentence below that sounds like a ruling is a description);
- a mutation record. The kernel spec's Verification section says "Record the
  named tests that fail". No such record exists for any kernel claim.

Everything this file calls **pinned** is pinned by a named test that exists and
passed in the orchestrator's run. **None of those pins has been
mutation-tested**, so "pinned" means "asserted", not "proven able to fail"
(practices shapes 1–16). Everything called **by reading** was derived from the
source and not executed. Nothing in this file was measured by running code:
the suite, the build and the demo were off limits while it was written.

### Counts at `7cfcddc`

| | at `a15ec83` (as last recorded, `7f58db9`) | at `7cfcddc` | how taken |
|---|---|---|---|
| tests | 923 | **993** | orchestrator: `swift test --no-parallel`, one summary line, 2026-09-14 |
| goldens | 97 | **97** | `find Tests -name "*.json" \| wc -l` |
| typecheck guards | 35 | **39** | per-file `grep -n canTypecheck`, each hit read |
| `error:` / `warning:` in the test run | 0 / 0 | **0 / 0** | orchestrator |

**+70 tests, all additions.** `git diff a15ec83..HEAD -- Tests` adds 70 `@Test`
lines and removes none, and 923 + 70 = 993. By file:

| file | new tests |
|---|---|
| `Tests/MetalUILayoutTests/NativeLayoutTests.swift` (new) | 18 |
| `Tests/MetalUILayoutTests/ProposedSizeTests.swift` (new) | 3 |
| `Tests/MetalUITests/NativeLayoutIntegrationTests.swift` (new) | 41 |
| `ComponentTests.swift` | 4 |
| `ElementGroupTrapTests.swift` | 4, all typecheck guards |

`ElementLayoutTests.swift` and `ModifierTests.swift` were rewritten in place,
with no new tests.

**The guard count's eighth move, 35 → 39, and it moved in one file.**

| file | guards | notes |
|---|---|---|
| `PhaseSeparationTests` | 19 | |
| `ErasureCompileGuards` | 10 | |
| `ElementGroupTrapTests` | **5** | was 1 |
| `UnitSafetyTests` | 2 | 3 hits; line 13 is a comment |
| `AXNodeTests` | 3 | |

The four new `ElementGroupTrapTests` guards are
`@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))` attributes at
lines 20, 48, 73 and 145. The old guard is at 318 (it was at 178):

- `proposalOverlayAcceptsProposalContentAndRejectsLegacyContent` (`16744b9`)
- `proposalOnTapAcceptsProposalContentAndRejectsLegacyContent` (`21b8fcc`)
- `proposalLayoutConstructorsRequireProposalContent` (`b8ba46d`; one test holds
  one positive probe and a negative probe per constructor, and `8e80657` added
  `ProposalScrollView`'s)
- `proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`
  (`4bda3d3`)

**Unlike the seven earlier moves (record §08), three of the four guards were
NOT written in the change that introduced their hazard.** The overlay, tap and
constructor wrappers first shipped over unconstrained `Content: ElementGroup`
(`NativeOverlayModifier<Content: ElementGroup, Overlay: ElementGroup>` at
`fdf5ce0`, `NativeTappable<Content: ElementGroup>` at `140d2d2`,
`HStack<Content: ElementGroup>` at `1823698`), so by reading legacy content
compiled inside them; the guards arrived only with the restricting commits
`16744b9`, `21b8fcc` and `b8ba46d`. Only the text-bridge guard shipped with
its feature (`4bda3d3` touches
`ProposalText.swift` and `ElementGroupTrapTests.swift` together), and
`ProposalScrollView`, which postdates the restriction, brought its negative
probe with it (`8e80657`). **The goldens did not move, although
`Sources/MetalUILayout/` changed.** That does not break the rule; it is the
reason the rule needs rewording. The new code sits behind
`isNativeLayoutNode(root)`, and no fixture builds a native node, so no golden
can reach it. A moved golden still means the *CSS* engine moved. A proposal-engine
regression can never move one.

### What landed, by theme, in commit order within each

#### 1. The kernel — `ProposedSize`, a closed node enum, one root switch

`a250043` added `Sources/MetalUILayout/ProposedSize.swift`:

- `ProposedSize`, whose `width`/`height` are `Double?`. `nil` means unspecified.
  It has `.unspecified`, `.zero`, `.infinity` and
  `replacingUnspecifiedDimensions(by:)`.
- `LayoutMeasurement`: a `size` plus optional `firstBaseline`/`lastBaseline`.
- Three `ProposedSizeTests`.

`389dbbc` added the store and the overlay. `007af42` routed roots.
`2e2e0d7`…`2b1e544` added a node kind per commit, and `a4ace1e` added rounding.
`fdf5ce0`, `ee56284`, `d250743` and `8e80657` added the attachment,
aspect-ratio, priority and scroll-viewport kinds.

**What exists is not what the kernel spec describes.** There is no layout
protocol, no `LayoutContext`-threaded algorithm, no type-erased algorithm and
no `NativeLayoutEngine`. Instead:

- **A `private enum NativeNode` with eleven cases** (`LayoutTree.swift:835-849`):
  `leaf`, `overlay`, `overlayAttachment`, `frame`, `padding`, `fixedSize`,
  `aspectRatio`, `layoutPriority`, `spacer`, `scrollViewport`, `linearStack`.
  It is held in a separate `nativeNodes: [Int: NativeNode]` dictionary, which
  `reset(generation:)` also clears (`:362`).
- **Two private recursive functions**, `measureNative` (`:387`) and
  `placeNative` (`:492`), that `switch` on that enum.
- **Eleven public `LayoutTree.newNative*` registrars** (`:110-266`), plus
  `computeNativeLayout(root:proposal:in:)` (`:275`) and `isNativeLayoutNode(_:)`
  (`:285`). They are mirrored one-to-one by eleven public
  `LayoutPass.requestNative*` methods (`Passes.swift:60-129`).
- **Shared storage, not a separate tree.** Every native node still goes through
  `newNode(style: .default, …)`, so it appends a `Style.default`, a `nil`
  measure, a rect and a `measuredWidth` to the legacy parallel arrays.
  Generation stamping (ruling C-3) therefore covers native ids for free.

**Users can add leaves, not algorithms.** `NativeNode` is private, so an
external container cannot register a layout of its own. The inventory's task-2
exit item, "a compile-time migration story for external custom elements", has
no answer yet. The legacy `requestNode`/`requestLeaf` (`Passes.swift:32`, `:49`)
are not deprecated, which follows the inventory's own ordering.

**The root switch is one `if`, on the root alone** (`Frame.swift:1165-1184`).
`computeRootLayout` asks `tree.isNativeLayoutNode(root)`:

- If the root is native, it runs `computeNativeLayout` with
  `proposal = contentSize` and `bounds = (0, 0, contentSize)`, then **discards
  the measurement** (`_ =`).
- Otherwise it runs `computeLayout` unchanged. `isNativeLayoutNode` has no other
  caller.
- The doc comment above the function still says only "Runs the flex engine".

Pinned by `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`.
Its root overlay measures 40×20, but its prepaint bounds are the whole 140×90
window, and the leaf's closure runs exactly once. **The test counts no
flex-engine work.** Its name promises more than its assertions show: a
flex-engine run would call the native closure zero times, so `== 1` is what
discriminates.

**A native root always gets the whole window, whatever it measured.**
`placeNative` stores `bounds` before it switches (`:495`). By reading, then:

- a root `Rectangle(width: 20, height: 10)` fills the window;
- a root `HStack` packs from x = 0, where a hosting view would centre a
  measured view. `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`
  asserts only the trailing child's x in a 100pt window (28 with the default
  spacing, 20 with explicit zero; `NativeLayoutIntegrationTests.swift:407-410`),
  which implies a leading child at x = 0 without asserting it — the probe
  records bounds for the child named "trailing" alone (`:57`).

No probe covers what a SwiftUI root does here.

**The measurement cache lives for one call and has no counters.** It is keyed
on `NativeMeasurementKey(id, proposal)` (`:863-866`). The dictionary is a local
created in `computeNativeLayout` (`:277`) and threaded `inout`, so it dies when
the call returns: no sweep, no hit/miss counters, nothing kept across frames.
Placement re-asks `measureNative` and hits the cache. Pins:

- `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`
  and `aNativeScrollViewportLeavesItsScrollingAxisUnspecifiedForContent`, one
  closure call each.
- The proposal half of the key is exercised only indirectly:
  `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild` expects a
  second call at a second proposal.
- The one-call lifetime is unpinned.

**The practices rule "performance tests count work, never wall clock" cannot
yet be applied to this engine**, because it exposes no work to count.

**Rounding reuses the legacy engine's function in the legacy engine's order**
(`a4ace1e`). `roundNativeStoredRects` (`:786-792`) matches `FlexEngine.swift`'s
`roundStoredRects` line for line: `setMeasuredWidth` with the pre-rounding
width, then `roundLayout`'s cumulative-edge `round(x + w) - round(x)`, root
first. Measurements stay fractional.
`nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement` pins a first child
at width 31 from x = 13.25, w = 30.4; per-width rounding would give 30. **No
test asserts a native node's `measuredWidth`, yet `ProposalText.paint` wraps at
it** (see §7).

**Not built, and silent about it:**

- **No validation.** The spec says "a finite proposal must be non-negative; an
  answer is always finite and non-negative", and nothing enforces either half.
  `Rectangle(color:)` and `Color` answer `.infinity` to an infinite proposal
  (`NativeElements.swift:419-420`, `:454-455`). Nothing rejects `min > max`, a
  fixed axis with min/max (fixed silently wins), negative spacing, a negative
  `minLength` or negative insets. A NaN proposal misses the cache every time,
  because it is unequal to itself. Only the ratio and the priority have
  preconditions (`:206`, `:220`).
- **No depth guard.** The legacy engine has `LayoutContext`'s `maxDepth` 64.
  Here `measureNative`, `placeNative` and `roundNativeStoredRects` recurse with
  no equivalent. Depth grows with nesting and with chains of the five
  node-registering modifiers (`frame`, `padding`, `fixedSize`, `aspectRatio`,
  `layoutPriority`); `background`, `clip`, `border`, `opacity` and
  `allowsHitTesting` return the child's node (`NativeModifiedContent.swift:128-142`)
  and `.onTap` returns its child's (`NativeTappable.swift:28`), so those add no
  depth. Cycles cannot be built, because a child always
  has a lower index and `LayoutNodeID.init` is internal.
- **No re-entrancy guard.** `computeNativeLayout` never calls
  `beginLayout`/`endLayout`, so `isLayingOut` stays false throughout. Its
  `setStyle` precondition therefore cannot fire during native layout.
- **`ProposedSize.zero` and `.infinity` have no production caller.** No
  container asks a child for its minimum or maximum response, although both
  constants' doc comments say that is what they are for.

#### 2. Typed modifiers and `.frame` — two unrelated `.frame`s

**The legacy `.frame(width:height:)` came first, and it is a CSS node**
(`11ed79e`, `24da5ea`, `c4c2f19`, `0b835b1`). `extension ElementGroup` returns
`FrameModifier<Self>` (`FrameModifier.swift:62-67`). That is a `StyledElement`
with all four requirements. Its init sets the non-nil sizes and centres both
axes (`:17-28`), and it registers one `requestNode` around its content's nodes.
Pins: `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` (on a
`Component`, one extra node, children keep their own sizes) and
`chainedFramesRemainConcreteAndNestTheirLayoutNodes` (node count 5). **It is
live in three places the per-site guards were written to watch:**

- `animated(…)` in `requestLayout` (`:40`), a fifth layout site;
- `registerHandlers` in `prepaint` (`:48`);
- `animatedBackground(…)` + `pass.fill` in `paint` (`:55-57`), a fourth
  background site.

`grep -rn FrameModifier Tests` finds it only in `ComponentTests` and one
overload-selection test. So `everyRegisteringSiteAnimatesItsStyle`,
`everyBackgroundPaintingSiteAnimatesItsColour`,
`everyBackgroundPaintingSiteHonoursHoverAndFocus`,
`onClickIsLiveOnEveryConformerThatCanRegisterOne` (six arms: box, column, row,
stack, text, list) and
`aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` **have no
`FrameModifier` arm**. By reading, deleting any of those three calls reddens
nothing. Not mutation-tested.

**By reading, `.frame` centres its content and does not propose its size.**
`Box().background(.accent).frame(width: 40, height: 40)` gives an inner box of
0×0, which paints nothing; `Box().onClick {}.frame(…)` gets a 0×0 hitbox.
Because the method is on `ElementGroup`, it also compiles on `ScrollView`,
`List` and `Deferred`. `ScrollView { List(…).frame(…) }` makes the `List` no
longer its scroller's only child (divergence 14's precondition). None of these
shapes is tested.

**The `width`/`height` trial, reverted after twelve minutes** (`4aaca40`, then
`d0a04d3`). `4aaca40` routed `StyledElement.width/height` through
`FrameModifier`. `d0a04d3` put `Box.swift` and `main.swift` back byte for byte:
`git diff 4aaca40^ d0a04d3 -- Sources/MetalUI/Box.swift Sources/MetalUIDemo/main.swift`
is empty. The plan (task-list "Current starting point", last bullet) gives the
reason as "it broke list virtualization, hit testing, and text measurement".
**That breakage is the plan's statement; no test or measurement of it is in the
repo.** `width`/`height` still mutate `Style` (`Box.swift:593-599`).

**The native frame kernel** (`2e2e0d7` fixed, `7d9fa05` alignment, `17b5908`
min/max, `27286f1` ideal, `ae19660` flexible expansion, `aa353ec` ideal sizing,
`3b4668e` doc). Its semantics, from `LayoutTree.swift:416-428`, `:521-530`,
`:722-740`:

- **Child proposal:** the fixed value if one is given. Otherwise
  `(parent ?? ideal)` clamped to `max(min, min(p, max))`, or `nil` when both
  are `nil`.
- **Frame response:** a fixed value wins outright, ignoring the child and any
  min/ideal/max on that axis. Otherwise:
  - with a `nil` proposal and an ideal, the clamped ideal;
  - with a finite proposal and `max == .infinity` exactly, `max(min ?? 0, proposal)`;
  - in every other case, the child clamped to `[min ?? 0, max]`.
- **Baselines** shift by `(frameHeight − childHeight) × verticalFactor`.
- **Placement:** the child sits at its measured size, aligned inside the
  frame's bounds.

Pins in `NativeLayoutTests`:

- `aNativeFrameProposesItsFixedAxesAndCentresTheChildResponse`
- `aNativeFrameForwardsAnOptionalAxisAndAdoptsThatChildResponse`
- `aNativeFramePlacesItsChildAtTheRequestedAlignment`
- `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`: min 40 / max 80
  at proposal 100, with a 20pt child, **gives 40**
- `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`
- `aNativeFrameWithInfiniteMaximumExpandsToItsFiniteProposal`

Pins in `NativeLayoutIntegrationTests`:

- `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified` and its
  height twin
- `chainedNativeFramesPreserveTheirDeclarationOrder`
- `builderNativeFrameExposesTheSharedFlexibleSizingSurface`

**Open, and material:** does a SwiftUI flexible frame with a *finite* `maxWidth`
grow toward a larger proposal? The kernel grows only at `.infinity`, so the
clamp test reads 40. The commonly cited reconstruction of SwiftUI's frame gives
80, and the test cites no probe for this case.

**The typed modifier is a closed enum, not the spec's protocol** (`388b43e`,
then per-modifier commits, then `3b3cfe8`). The typed-modifier spec asked for
`ModifiedElement<Content, Modifier>` and `protocol ElementModifier`, and
neither exists anywhere in `Sources/` or `Tests/`. What shipped is
`ModifiedContent<Content: ProposalElementGroup>` holding a
`public enum LayoutModifier` (`NativeModifiedContent.swift:9-23`) with ten
cases: `frame`, `padding`, `fixedSize`, `aspectRatio`, `layoutPriority`,
`background`, `clip`, `border`, `opacity`, `allowsHitTesting`.

- **The first five register a native wrapper node.** The last five return the
  child's node unchanged and act only in prepaint or paint (`:101-142`).
- **The spec's required proof is missing.** It asked that "two chained
  modifiers … preserve distinct `@State` slots", and there is no test of it
  (`grep @State NativeLayoutIntegrationTests.swift` finds nothing).
- **The proposal `.frame` overload** arrived with `ProposalElementGroup` in
  `1823698` (`NativeModifiedContent.swift:250`). A proposal receiver picks it
  over `ElementGroup.frame` because it is the more refined protocol extension.
  Pinned by an explicitly stored type in
  `proposalLayoutFrameUsesTheTypedProposalWrapper`.
- **`nativeFrame(…)` (`:147`) is the one `native…` spelling with no
  `@available(*, deprecated)`.** Its nine siblings have one, and so do fourteen
  `Native…` typealiases (fourteen in `MetalUI`, plus `NativeMeasureFunction`,
  `NativeStackAxis` and `NativeAlignment` in `MetalUILayout/LayoutTree.swift:853-861`). The tests use `nativeFrame` six times, which is why the
  run prints no deprecation warning. Deprecating it breaks the 0-warning
  baseline.

#### 3. Proposal wrappers, paint modifiers and interaction

**The surface, all public, all `Element`, every generic constrained to
`Content: ProposalElementGroup`:**

| type | what it is | cite |
|---|---|---|
| `HStack` / `VStack` | `spacing: Pixels = 8`, `alignment: ProposalAlignment = .center` | `NativeElements.swift:11`, `:53` |
| `ZStack` | `alignment:` | `:95` |
| `ProposalFrame`, `Padding`, `Background`, `FixedSize` | builder wrappers | `:148`, `:216`, `:257`, `:301` |
| `Spacer` | `minLength:` | `:351` |
| `Rectangle` | `(width:height:color:)` is fixed; `(color:)` answers the proposal, with a 10pt ideal | `:379-397` |
| `Color` | fills the proposal, with a 10pt ideal | `:438` |
| `ProposalScrollView` | see §8 | |
| `ProposalText` | see §7 | |

The modifiers are the `LayoutModifier` set above, plus two separate wrapper
types: `OverlayModifier` (`.overlay(alignment:content:)`, `fdf5ce0`) and
`OnTapModifier` (`.onTap(hoverColor:_:)`, `140d2d2`, `0c56942`).

- **Canonical renames** (`5910cce` through `de8b56c`) moved each `Native…` name
  to its SwiftUI spelling and kept the old name as a deprecated alias.
  `ProposalFrame` is not called `Frame` because `public final class Frame`
  already exists.
- **`3b3cfe8` moved the modifiers** from `ElementGroup` to
  `ProposalElementGroup`.

**Three renderer-facing changes arrived with them. Two of them retire claims
this record made:**

- **`Frame.fill` and `PaintPass.fill` take `borderColor:` and `borderWidths:`**
  (`7c71996`). The proposal `.border` sets them, so something above the
  renderer can now draw a border. No legacy element passes one, so focus is
  still a token swap and `borderWidth(_:)` still paints nothing. See the
  errata in §01 and §05.
- **An opacity stack** (`a04de2f`: `Frame.swift:222-225`, applied at fill and
  glyph emission). `PaintPass.opacity(_:_:)` preconditions `0...1` at paint
  (`Passes.swift:579-580`), but the `.opacity(_:)` modifier checks nothing. So
  `.opacity(1.5)` builds and traps on first paint, where `.aspectRatio` and
  `.layoutPriority` trap at construction.
- **A hit-testing gate** (`14bd93d`). `PrepaintPass.allowsHitTesting(_:_:)`
  (`Passes.swift:422`) raises `Frame.hitTestingDisabledDepth` (`:516-520`), and
  **the depth gates exactly one line**: the pointer-hitbox insert in
  `registerHandlers` (`:655`). `registerScrollRegion` (`:501`) and a raw
  `PrepaintPass.insertHitbox` bypass it, and focus registration and AX emission
  stay live.

**Participation.** Proposal elements take part in the framework's cross-cutting
systems far less than legacy ones do:

| concern | proposal path |
|---|---|
| `@State` | bound for every `Element` by `StateBinder.bind`. No built-in proposal element declares any; the demo's lives in a retro-conformed `Component` |
| hitboxes | only `OnTapModifier` (`onClick` only) and `ProposalScrollView` (scroll region) |
| hover | only `OnTapModifier`'s `hoverColor`, a 0.22-opacity fill gated by `pass.isHovered(id)` (`NativeTappable.swift:42-46`) |
| focus, keys, `.id()` | none. `ProposalScrollView` is the only proposal type with an `elementID` (an init parameter) |
| AX | none |
| animation | **none.** No proposal file calls `animated`, `animatedBackground` or `noteActiveAnimation`, so every frame, padding, background, border, opacity and colour change on this path snaps under `withAnimation` |

Pins:

- `nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent`
- `builderNativeBackgroundPaintsBeneathItsNativeChild`
- `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt`
- `nativeClipMasksOverflowingContentToItsOuterFrame`
- `nativeBorderPaintsOverContentWithoutChangingItsFrame`
- `opacityMultipliesItsDescendantsPaintAlpha`
- `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`
- `onTapRegistersTheResolvedNativeBoundsAsAHittableTarget`
- `onTapPaintsItsHoverOverlayOnlyWhenThePointerIsOverItsResolvedBounds`, through
  a real `Window`, cold against hovered
- `allowsHitTestingFalsePreventsDescendantOnTapDispatch`

**No test clicks an enabled `.onTap` and asserts that its action ran.** The
first tap test asserts only that a hitbox exists. In the last one, `count == 0`
would hold for an `onTap` that never runs anything; only its
`lastHitboxes.isEmpty` half discriminates.

**The compile-time boundary** (`16744b9`, `21b8fcc`, `b8ba46d`).
`ProposalElementGroup` is a requirement-free public marker refining
`ElementGroup` (`ProposalElementGroup.swift:8`), conformed to by:

- `EmptyGroup`;
- conditionally, `Pair`, `OptionalGroup` and `ArrayGroup`;
- every proposal type.

**`EitherGroup` is not conformed.** By reading, an `if`/`else` inside a proposal
stack does not compile; this has not been typechecked. The runtime backstop is
`LayoutTree.nativeNode(_:)`'s
`preconditionFailure("native layout subtree contains a legacy node")` (`:379-385`),
reached from every container registrar. **No test pins that message.**

#### 4. Stacks, priority, spacer

`b8330d0` added the linear stack, `98ed80f` its alignment and `2b1e544` the
spacer. `39a5e23` and `4f7f006` set HStack's and VStack's default spacing to
8pt. `d250743` and `e213088` added priority, `a85242d` spacer-through-priority,
`64a81b3` the spacer minimum, and `24aa410`/`ca8207c` the `Rectangle`/`Color`
10pt ideal.

**Kernel default spacing is 0 (`LayoutTree.swift:245`); the public inits default
to 8** (`NativeElements.swift:16`, `:58`). Pinned per axis, each against an
explicit-zero control:
`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` and
`vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`. The inventory
said "default spacing must be probe-backed rather than hard-coded". It is a
constant, backed by one probe per axis with rectangles. SwiftUI's `nil` spacing
depends on the pair of adjacent views, so the probe supports 8pt for that pair
only. That limit on scope is by reasoning; nobody has probed another pair.

**Measure** (`:464-486`). Children are proposed `nil` on the main axis and the
parent's value on the cross axis. The main axis is `natural = Σ children + gaps`,
which becomes:

- `max(natural, proposal)` if the stack has a spacer;
- `min(natural, proposal)` if it does not;
- `natural` if the proposal is `nil` or not finite.

The cross axis is the largest child's cross size **at the `nil`-main
measurement**.

**Place** (`:573-608`). Children pack from the leading edge; `alignment` is read
**only on the cross axis**. Two adjustments come first:

- **Spacers share the surplus.** Surplus = `max(0, placedMain − natural)`,
  divided equally among spacers (`:579-581`). A spacer is recognised by node
  kind, directly or through any depth of nested `.layoutPriority` wrappers
  (the check recurses, `:636-645`), but
  never through frame, padding or fixedSize.
- **Priority allocation happens only when there is no spacer and the stack
  overflows** (`stackMainAllocations`, `:685-708`). `remaining = available − gaps`.
  Priority groups are visited highest first, and each group either:
  - fits: every member gets exactly its natural size; or
  - does not fit: every member gets `remaining / count`, and remaining drops
    to 0, so every lower group is proposed 0.

  There is no flexibility ordering and no min/max probing, and an unused share
  is not handed back.

Pins:

- `hStackDividesAConstrainedProposalAmongEqualPriorityFlexibleChildren` and its
  `vStack` twin: 50/50 in a 100pt stack
- `hStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling` and its
  `vStack` twin: 80/20
- `layoutPriorityPreservesASpacersFlexibleExpansion`
- `spacerMinimumLengthSurvivesAConstrainedStackProposal`
- `aNativeLinearStackDividesConcreteSurplusBetweenSpacers`
- `aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder` and
  its vertical twin
- `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer`

**No priority test exists at the kernel level**; all four are integration tests.

**What a reader will get wrong, all by reading and none tested:**

- **A flexible child that is not a spacer never expands.** Only spacers get
  surplus. `HStack { Color(.a); Color(.b) }` in 100pt places two 10pt colours.
  `.frame(maxWidth: .infinity)` inside a stack does not expand either: a stack
  child is proposed `nil` on the main axis, and the frame's expand branch needs
  a finite proposal. A framed or padded `Spacer` loses its flexibility.
- **A stack with any spacer never compresses.** `stackMainAllocations` returns
  all-`nil` when `hasSpacer` (`:689`), so an overflowing
  `HStack { long; Spacer(); long }` spills out of its bounds. The spacer test
  above uses fixed leaves, so compression could not show.
- **Measurement and placement can disagree.** The stack reports its cross size
  from `nil`-main measurements, then places children at their allocations. A
  wrapping text compressed in an `HStack` grows taller than the height the stack
  reported.
- **A spacer claims the cross axis.** `spacerLength` applies to both axes
  (`:397-401`), so in an `HStack` a spacer's height is the proposed height, and
  the stack's measured height becomes the full proposal.
  `aNativeLinearStackDividesConcreteSurplusBetweenSpacers` **pins this as
  current behaviour**: spacer height 40 beside 10pt leaves. Whether SwiftUI
  agrees is unprobed.
- **`Spacer()` means `minLength` 0** (`:234`, `nil ?? 0`). That is unpinned,
  because every test passes an explicit `minLength`. The surplus test does not
  distinguish `minLength` 10 from 0, since both give a 40pt spacer.
- **`HStack(alignment: .leading)` places exactly like `.center`**, and
  `VStack(alignment: .top)` like `.center`. The nine-case `ProposalAlignment` is
  accepted, and the main-axis factor is never read. SwiftUI types these
  parameters as `VerticalAlignment`/`HorizontalAlignment`, where such a call
  would not compile. This is a silent no-op, and a candidate row for CLAUDE.md's
  inert table.

#### 5. Alignment

`7d9fa05` added frame alignment, `98ed80f` stack alignment, `17398b7` overlay
alignment, `65a0e0f` all nine positions and `d35b13c` its doc.

`ProposalAlignment` (`LayoutTree.swift:813-833`) has nine cases and internal
`horizontalFactor`/`verticalFactor` values of 0 / 0.5 / 1. It is read by:

- overlay and overlay attachment: both axes;
- frame: both axes;
- linear stack: the cross axis only.

It defaults to `.center` everywhere. **Padding, fixedSize, aspectRatio and
scrollViewport place the child at the bounds origin.** The kernel spec said
"Alignment enters with the `Stack` port, not this kernel proof", and it entered
anyway, with no `Stack` port; legacy `Stack` is untouched.

Pins:

- `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition`: nine arms,
  each with a distinct expected point
- `aNativeOverlayPlacesEveryChildAtTheRequestedAlignment`
- `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly`
- `aNativeFramePlacesItsChildAtTheRequestedAlignment`

**There are no alignment guides and no baseline alignment.** Baselines are
carried and never produced:

- `grep -n "firstBaseline\|lastBaseline" Sources/MetalUI` finds nothing.
- `ProposalText` returns a size only (`ProposalText.swift:87`).
- Frame, padding and aspectRatio propagate baselines, adjusting them
  (`LayoutTree.swift:416-456`). `fixedSize`, `layoutPriority` and
  `overlayAttachment` return the child's (for an attachment, the primary's)
  measurement as-is, so they propagate too (`:410-415`, `:438-443`, `:457-458`).
  The public `.overlay(…)` modifier registers `overlayAttachment`
  (`NativeOverlayModifier.swift:36`), so it keeps its primary's baselines; only
  the `ZStack`-style `.overlay` node kind (`NativeElements.swift:115`), linear
  stack and scroll viewport drop them.

`ProposedSize.swift:39` still says text leaves "will supply them when the native
layout path is introduced". It has been introduced, and they supply none.

#### 6. Aspect ratio

`ee56284` added it and `07e8615` recorded its probe. Its semantics, from
`:444-456`, `:550-560` and `:753-781`:

1. Precondition: the ratio is finite and greater than 0.
2. **The child is measured once at the parent's proposal**, the "intrinsic"
   probe, which always runs.
3. `aspectRatioSize` picks a size:
   - both axes finite: `.fit` inscribes, `.fill` circumscribes;
   - one axis finite: the other is derived, and `contentMode` is ignored;
   - neither axis finite: the ratio is fitted inside the intrinsic size whatever
     the mode, or the answer is `.zero` if that size is degenerate.
4. The child is re-measured at the chosen size.
5. **The wrapper reports that size and places the child at it**, not at the
   child's own answer.

Pins, **both-axes-finite only**:
`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild` and
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`. In each,
a fixed 20×10 leaf is **stored at** 100×50 and at 160×80. The single-axis and
unspecified branches are unpinned. The probe cited is of a child that
*answers* 100×50. Whether SwiftUI would place a child that answers 20×10 at
100×50 is not what the probe observed, so this test's placement half is not
probe-backed.

#### 7. The text bridge

`4bda3d3` added it and `bfdab1e` showed it in the preview.
`Text.proposalLayout()` returns `ProposalText` (`ProposalText.swift:90-99`).
The file-scope global `smallestWrapWidth` in `Text.swift` (`:21`, not a member
of `Text`) went from `private` to `internal` so the bridge could
use it. That one-line change is the whole diff to `Text.swift`.

- **Measure** (`:82-88`) wraps at `max(proposal.width, smallestWrapWidth)`
  through the shared `ShapingCache`. A `nil` width shapes one line per hard
  break. The height proposal is ignored.
- **There is no min-content probe.** Legacy `Text` takes its min-content from
  the `CFStringTokenizer` longest word (TX-F); nothing here asks for one, which
  matches no container ever proposing `.zero`.
- **Paint** (`:62-75`) wraps at `pass.measuredWidth(of: layout.node)`, the same
  convention as the retired divergence 8.

Pins: `proposalTextUsesWidthDrivenSwiftUIMeasurement`,
`proposalTextParticipatesInANativeStackAndPaintsGlyphs`, and the guard
`proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`.

**What a reader will get wrong:**

- **A fourth `MainActor.assumeIsolated`, and the second unguarded one**
  (`ProposalText.swift:49`). It is sound only because `computeNativeLayout` runs
  synchronously inside `@MainActor` `Frame.computeRootLayout`: the argument
  record §03 makes for `Text.swift:237`, applied to the other engine. See the
  erratum in §03.
- **The conversion keeps four fields and drops the rest.** It copies `string`,
  `fontFamily`, `fontSize` and `foregroundColor`.
  `Text("x").background(.accent).onClick {}.id("n").proposalLayout()` compiles
  and loses the background, the handler and the name. The plan says the bridge
  "uses the same … glyph painting as `Text`". The glyph path is shared; the
  background and hover/focus chain are not.
- **`measuredWidth` recording is unpinned for native nodes.** By reading,
  deleting `setMeasuredWidth` from `roundNativeStoredRects` leaves 0, which
  clamps to 0.5 and wraps text about one glyph per line.
  `proposalTextParticipatesInANativeStackAndPaintsGlyphs` asserts only
  `!glyphs.isEmpty` and would stay green.
- **The guard's second half is unasserted.** It typechecks
  `Text("proposal").proposalLayout().background(.accent)`, and never compiles
  legacy `Text("x").background(.accent)`.

#### 8. `ProposalScrollView`

`8e80657` added it and `02ecfd4` the horizontal case. `4d72663` and `1419804`
settled how direct children compose, and `11ed169` added a demo corner radius.
`b757622` and `7cfcddc` are test-only: they added tests of wheel routing and of
offset clamping for behaviour already in `ProposalScrollView.swift`, which
changed only in `8e80657`, `4d72663` and `1419804`.

- **Kernel** (`scrollViewport`, `:459-463`, `:565-572`, `:619-634`): content is
  proposed the parent's size with the scrolling axis `nil`. The viewport reports
  each finite proposal axis, and otherwise the content's size. Content is placed
  at its measured size at the origin, and the element applies the offset.
- **Element** (`ProposalScrollView.swift`) shares `ScrollView`'s input plumbing:
  - `registerScrollRegion(bounds, id:, axis:)` outside its clip (`:73`), so
    `Window.applyScroll` routes to it;
  - a `ScrollState` keyed on its bare id, clamped and written in prepaint
    (`:119-130`), read and clamped in paint;
  - an indicator driven by `requestAnotherFrame()` (`:106`), which makes it
    `wantsAnotherFrame`'s second caller.

  It uses no `$anim-content`/`$anim-viewport` ids and no animation helper.
- **Several direct children become a vertical native stack with a hard-coded
  spacing of 8, whatever the axis** (`:56-61`). The source comment cites pixel
  probes with 20pt and 30pt children.

Pins:

- `aNativeScrollViewportLeavesItsScrollingAxisUnspecifiedForContent` and
  `aNativeHorizontalScrollViewportLeavesItsWidthUnspecifiedForContent`
- `aProposalScrollViewMeasuresContentWithAnUnspecifiedScrollingAxis`
- `aProposalScrollViewForwardsItsHorizontalAxisToTheNativeViewport`
- `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing`
- `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`
- `aProposalScrollViewsCornerRadiusMasksItsScrollingContent`
- `aWheelEventInsideAProposalScrollViewUpdatesItsOffset`, through a fake
  platform
- `aProposalScrollViewClampsAnOffsetPastItsContentEndOnPrepaint`

**Two legacy divergences reach this path by reading, and neither is tested
here:**

- **Divergence 16:** an `.onTap` inside a `ProposalScrollView` registers an
  opaque non-scroll hitbox after the scroll region, so `applyScroll`'s
  `guard let axis = region.scroll else { return true }`
  (`Window.swift:1067`) swallows the wheel over it.
- **`.allowsHitTesting(false)` does not stop a scroller inside it.** The scroll
  region bypasses the gate (§3), so the scroller still scrolls and still takes
  the topmost-opaque slot over whatever lies beneath.

#### 9. The legacy `.padding` change — the one commit that moved existing behaviour

`f1944f8`, the second commit in the range and the only one that changes what an
existing public call does. **`StyledElement.padding(_:)` now returns
`Box<Self>`** (`Box.swift:640-650`): a new outer `Box` with default `Style()`
whose `style.padding` holds the edges. It no longer writes the receiver's
`Style.padding` and returns `Self`.

Pins: `paddingWrapsAnElementAndExpandsItsOuterFootprint` (leaf 0 → 4, one more
node) and `chainedPaddingCreatesNestedWrappers` (4 then 8 puts the leaf at
x = 12, node count 4). The same commit rewrote existing tests to follow the
wrap:

- `ModifierTests` dropped its two padding rows (`cases.count` 40 → 38,
  `ModifierTests.swift:289`) and reworded its header line
  (`ModifierTests.swift:6`, "The direct-style modifier surface: `StyledElement`'s
  thirty-seven and `Box`'s one"). 37 + 1 = 38, so the header is now right; it
  was the `a15ec83` header ("The public modifier surface", same 37 + 1) that
  disagreed with that commit's 40 cases.
- `ElementLayoutTests`' direct-engine fixture grew from 5 nodes to 7, and three
  rect literals moved.
- `paddingEdgesAreNotTransposed` reordered its modifiers so that
  `.alignItems/.width/.height` come before `.padding`.

**`Component.padding` did not change.** It still distributes (CO-U) and still
replaces rather than accumulates (`chainedPaddingReplacesRatherThanAccumulates`).
**So one spelling now means two things, depending on the receiver.**
`decorationBackedModifiersAreNotOfferedOnAComponent`'s own doc names that as the
shape to avoid, and the plan defers the decision to task 5.

**Consequences, none measured:**

- **Source break.** A stored `Box<Text>` built with `.padding` stops compiling,
  and so does `Text(s).padding(4).font(size:)`, because `.font` exists only on
  `Text`. The fix is to reorder, and reordering changes semantics.
- **Modifier order now decides which box a modifier reaches.**
  - A container modifier written after `.padding` (`.alignItems`, `.gap`,
    `.justifyContent`, `.background`, `.cornerRadius`) configures the one-child
    wrapper.
  - An item modifier written before it (`.flexGrow`, `.alignSelf`, `.margin`)
    lands on something that is no longer the parent's flex item.
  - Handlers and focus attach to whichever side of `.padding` they are written.

  All of it compiles.
- **Identity gains a level.** The wrapper takes the element's cursor slot, and
  the element becomes `positional(0)` under it. Adding or removing a `.padding`
  (or a `.frame`) therefore re-seeds `@State`, `$focus` and `$anim`.
  `X().id("n").padding(4)` names the inner element under a positional wrapper,
  so **the "name the trailing sibling" remedy (record §01) works only when
  `.id()` is the outermost modifier.** No test covers either order.
- **The default demo no longer looks the way record §03 and §07 measured it —
  predicted by reading below, then confirmed by a window capture on
  2026-09-14 (record §03's table: header an 84pt centred card, hairline and
  sidebar bars gone, sidebar 224pt, list rows centred and shrunk), and fixed
  the same day by reordering `demoContent`'s modifiers; the re-capture matches
  `a15ec83` pixel for pixel.** `demoContent` did not change in this range; the diff to
  `main.swift` only adds the preview. Its padded containers now wrap:
  - The sidebar is `.width(…).padding(14).alignItems(.stretch).background(…)`
    (`main.swift:487`). So `.alignItems(.stretch)` and the background land on
    the wrapper, and the inner `Column` keeps EP-8's centring. Its four
    childless `Box().height(26)` bars get zero width, which the demo's own
    comment at `:426-431` predicts.
  - The root (`.padding(16)` at `:874`, then `.alignItems(.stretch)` at
    `:876`), header (`.height(72).padding(16)` at `:396-397`, then
    `.alignItems(.center)`), main pane (`:859`), modal (`:749`) and list rows
    (`:840`) have the same shape.
  - The root's case costs the most. Its `.alignItems(.stretch)` now configures
    the one-child wrapper, so the root `Column(gap: 12)` (`:382`) keeps EP-8's
    centring. The hairline `Box().height(Pixels(1))` (`:411-413`) declares no
    width and relies on that stretch, as its own comment at `:408-410` says,
    so by reading it gets zero width and paints nothing; the header and body
    bands lose their full-width stretch the same way.
  - Each list row gains one registering `Box`.

  **The only looks since `f1944f8` are those two 2026-09-14 captures.** The 2026-09-10 animation
  readings (114 / 113 / 73pt), SZ-L's sidebar numbers, §07's 1.652 / 1.637 ms
  warm frame and its 165 / 63 resident `StateTable` entries were all taken on
  the pre-wrap tree. See the errata in §03 and §07.
- **Tests that may no longer be able to fail**, unmeasured:
  - `ListTests`' `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` and
    `aScrolledListsSpacerDoesNotShrinkUnderPadding` forced negative free space
    inside the `List`'s own padded box. With the padding outside, that deficit
    probably no longer exists.
  - `paddingEdgesAreNotTransposed` now fixes the size by literal, so a
    right ↔ bottom transposition in the engine's resolution of the edges may
    reach no asserted number. A transposition inside the modifier is still
    caught: `f1944f8` also added a direct assertion on the wrapper's stored
    `row.style.padding == Edges(top: 4, right: 8, bottom: 12, left: 16)` ("each
    edge must be stored on the outer padding wrapper unchanged",
    `ElementLayoutTests.swift:694-696`).
  - `aNestedLayoutMatchesTheEngineRunDirectly` no longer exercises `gap`.

  Each needs a mutation run in an isolated worktree.

#### The opt-in preview window

`d7ab072`, `e74097f`, `b1a15b9`, `ba59223`, `c739eb8`, `bfdab1e`, `11ed169`.
`METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo` opens "MetalUI — Native
Layout Preview" (920×560, root `ZStack`) in place of the milestone demo. The
value must be exactly `"1"` (`main.swift:1008`). Its contents (`:880-1003`):

- stacks of rectangles;
- a rewrapping `ProposalText`;
- a vertical `ProposalScrollView`;
- two 480pt-ideal `PriorityPreviewPanel`s, a custom native leaf retro-conformed
  at `:938`;
- `PreviewToggle`, a `Component` with `@State`, retro-conformed at `:907`;
- a 0.35-opacity tappable under `.allowsHitTesting(false)`;
- the paint modifiers.

**`PreviewToggle` is the first `Component` a demo uses**, in the opt-in window
only; CO-Y's "no production caller" still holds for the default demo. The
keymap is unchanged. In the preview only **Space** and **Q** have a visible
effect. **No human look at the preview is recorded.**

Also in `11ed79e`, hidden behind its test-only subject line: `AGENTS.md` (a copy
of `CLAUDE.md` for Codex), `.codex/config.toml`, `.codex/hooks.json`,
`.codex/environments/environment.toml` and `.agents/skills/cdb-scan/SKILL.md`.
`.codex/config.toml` (one) and `.codex/hooks.json` (three) contain absolute
home-directory paths, and
`.gitignore` does not cover `.codex/` or `.agents/`.

### SwiftUI probes — recorded as sentences, reproducible from nothing in the repo

**No probe source is committed.**

- `git ls-files | xargs grep -l "NSHostingView\|import SwiftUI"` returns prose
  documents only: record §01, two decisions docs, the component spec and this
  range's plan.
- `07e8615`, "Record SwiftUI aspect ratio probe", touched only a test's doc
  comment and the plan.

The plan's own rule is "a small, **versioned** SwiftUI probe with a positive
control". Every observation below is a sentence in the plan or in a doc comment,
and none can be re-run from this repository. Most of them record no positive
control. The table quotes what was written, not what was verified.

| observation as recorded | where | the MetalUI test that encodes it |
|---|---|---|
| `HStack` default spacing 8pt | plan; test doc | `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` |
| `VStack`: fitting `NSHostingView`, 20×10 and 20×30 children, measures 20×48 | plan; test doc | `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` |
| `.frame(idealWidth: 80)` on an unspecified axis proposes 80 to a 20pt child and reports 80; its `idealHeight` twin likewise | test docs | `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `…HeightBecomes…` |
| custom `Layout`: a 2:1 `.fit` child offered 100×80 answers 100×50; `.fill` answers 160×80 | plan; test docs | `aspectRatioFit…`, `aspectRatioFill…` (the placement half is not what was probed; §6) |
| custom `Layout`: two 80pt-flexible children in a 100pt zero-gap `HStack` get 50/50; priority 1 gets 80, its sibling 20 | plan; test docs | the four `h`/`vStack…Priority`/`…EqualPriority…` tests |
| `HStack { 10pt; Spacer(minLength: 30); 10pt }` offered 20 answers 50 | plan; test doc | `spacerMinimumLengthSurvivesAConstrainedStackProposal` |
| custom `Layout`: `Rectangle` is 10pt on an unspecified axis and the offered value otherwise | plan; test doc | `rectangleUsesSwiftUIShapeProposalSizing` |
| `Color` follows the same 10pt rule | plan only | `aNativeFillAcceptsEachWindowsCurrentProposal` (all four combinations) |
| custom `Layout`: `Text` is intrinsic when the width is unspecified, rewraps at a concrete width, and ignores the height proposal | test doc; `ProposalText.swift:80-81` | `proposalTextUsesWidthDrivenSwiftUIMeasurement` |
| pixel probes: `ScrollView` direct children (20pt red, 30pt blue) sit 8pt apart **vertically on both axes** | plan; `ProposalScrollView.swift:49-53` | `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing`, `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` |

**Unprobed, and material to behaviour this range pins:**

- whether a finite `maxWidth` frame grows (§2);
- whether `Spacer` claims the cross axis, and what `Spacer()`'s `nil`
  `minLength` means (§4);
- whether a root view is centred or stretched (§1);
- whether a child that answers smaller than its aspect-ratio size is placed at
  that size (§6);
- whether `.opacity(0)` still hit-tests.

### Hazards this range introduced, in one place

Each is described above, where its mechanism is. They are gathered here so none
is missed. **All are by reading unless marked.**

1. **A native subtree inside a legacy container is accepted silently.**
   `LayoutTree.newNode` checks generation only (`:89-97`), and the root switch
   looks at the root alone. So `Column { HStack { … } }`,
   `Row { Spacer() }` and `Box { Text("x").proposalLayout() }` all compile,
   because `Column`/`Row`/`Box` take any `ElementGroup`. The CSS engine then
   sees `Style.default` nodes with no measure function, and a native leaf is
   answered by `measureNode`'s closed form for a childless node
   (`FlexEngine.swift:1934`): zero content size, and the native closure never
   runs. There is no trap, no diagnostic, no test and no guard. The kernel spec
   says "There is no mixed subtree path", and the inventory says mixing "is
   prohibited". That holds in one direction only.
2. **The marker protocol is opt-in and unchecked.** Any type can declare
   `ProposalElementGroup`; the demo does, for a `Component` and a custom leaf. A
   legacy-content type that declares it compiles inside `HStack` and traps at
   registration, with a message no test pins. Wrappers that need exactly one
   node also trap when proposal content yields 0 or 2+, for example
   `ProposalFrame { if flag { Rectangle() } }` with `flag` false
   (`NativeElements.swift:187`, `:235`, `:273`, `:323`;
   `NativeModifiedContent.swift:102`; `OnTapModifier`,
   `NativeTappable.swift:27`; and `OverlayModifier`, which needs exactly one
   node in each slot, `NativeOverlayModifier.swift:34`). The guards cover built-in constructors
   with legacy *content*. `OverlayModifier`'s `overlay:` argument has no
   negative probe.
3. **`OverlayModifier` gives its primary and its overlay the same child id.** It
   calls `requestGroupLayout(under: id, …)` twice, with two cursors that both
   start at 0 (`NativeOverlayModifier.swift:28-33`), so both first elements are
   `GlobalElementID.child(of: id, at: 0, name: nil)`. The consequences:
   - one `.onTap(hoverColor:)` on each side lights both;
   - a press on one released on the other dispatches;
   - a stateful `Component` on each side shares `$state<n>` slots;
   - two `ProposalScrollView`s share one `ScrollState`.

   Nothing tests a stateful or tappable element on both sides; the preview puts
   a plain `Rectangle` in the overlay. Legacy containers thread one cursor
   through the whole group.
4. **Every stored rect may differ from the node's own measurement.** Root nodes
   get the window. Padding stores bounds minus insets, not its child's measured
   size (`:535-540`). AspectRatio stores the ratio size. `layoutPriority` and an
   attachment's primary pass their bounds straight through. A `pass.fill(bounds)`
   paints the imposed rect.
5. **Nothing animates on the proposal path, and `FrameModifier` animates with no
   guard watching.** Together these break the Animation section's per-site
   accounting in both directions (§2, §3).
6. **`.allowsHitTesting(false)` does not gate scroll regions** (§3, §8).
7. **A second unguarded `assumeIsolated`** (§7).
8. **The legacy `.padding` wrap**: identity, modifier order, the source break,
   the unlooked-at default demo, and possibly weakened tests (§9).
9. **The same child id can be passed to two containers.** No registrar checks
   uniqueness. Measurement stays consistent through the cache; the last
   placement wins. The legacy path has the same shape, and its registrars are
   public too (`LayoutTree.newNode`/`newLeaf`, `LayoutTree.swift:89`, `:99`;
   `LayoutPass.requestNode`/`requestLeaf`, `Passes.swift:32`, `:49`), so this
   is not new exposure; the native path simply adds more public registrars of
   the same unchecked kind.

### Documents this range left stale

Recorded so a reader does not trust them. The files named here are other lanes'
to correct:

- **`2026-09-12-native-layout-kernel-design.md`**:
  - its Non-goals ("Changing public modifiers, text shaping, scrolling, input,
    or animation", line 18 at `HEAD`) and its Verification section's "no
    existing element is migrated in this slice" (lines 128-129 at `HEAD`);
  - its API (a type-erased algorithm, `measure(_:in: inout LayoutContext)`,
    `NativeLayoutEngine`, a legacy compatibility root);
  - its deferral of alignment to a `Stack` port;
  - "zero and infinity are explicit proposals for containers that need" them;
  - its promise of text baselines;
  - "Record the named tests that fail", which has no record.
- **`2026-09-12-typed-modifier-composition-design.md`**: `ModifiedElement`,
  `ElementModifier`, and "Port `.frame(width:height:)` onto `ModifiedElement`".
  None of the three was built.
- **The inventory**: "their default spacing must be probe-backed rather than
  hard-coded"; "arbitrary mixing … is prohibited" (one direction only); "Carry
  first/last baselines" (none carried).
- **The plan's "Current starting point"**:
  - "paired external compile guards cover every constructor" (the overlay's
    second argument has no negative probe);
  - "the same … glyph painting as `Text`" (§7);
  - "`Native…`/`native…` predecessors remain deprecated" (`nativeFrame` is not);
  - it omits `FrameModifier`'s animation and handler surface, the scroll-region
    bypass, the preview's environment variable and the unlooked-at default demo.
- **Source doc comments**:
  - `Frame.swift`'s "Runs the flex engine" and "`borderColor` … there is no way
    to set it";
  - `Box.swift:20-24` and `:666-669` (`Frame.fill` borders);
  - `Component.swift:387-390` and `:418-423` (padding signatures "match
    exactly"; "a second `.padding(_:)` on a `Box` simply overwrites"; its line
    citations);
  - `NativeElements.swift`'s `HStack` doc ("traps when the layout pass registers
    the stack") and its ``` ``ElementGroup/nativeFixedSize`` ``` symbol link
    (`:298`);
  - `LayoutTree.swift:804`'s ``` ``ElementGroup/aspectRatio(_:contentMode:)`` ```
    symbol link;
  - `ProposedSize.swift:39`;
  - the demo's comments at `main.swift:426-431`, `:577-585` and `:759`
    ("320pt content width").
- **`CLAUDE.md` and the old `AGENTS.md` copy**, where the rules lane owns the
  fix: the guard count, the border sentence, the `assumeIsolated` paragraph,
  "seven registering points" and "four `pass.fill` sites", the leaf-padding and
  `aspectRatio` inert rows, the Component snap sentence, and "When CI lands".
  `.github/workflows/swift.yml` has run `swift test --no-parallel` on
  `macos-latest` since `00f6b2c` (2026-09-10), before this range began. Whether
  any guard executes under it is unmeasured.

### What remains open, per the plan

The plan's checklist has **task 1 ticked and tasks 2–15 unticked**, and that is
accurate: every slice above is migration evidence on a **parallel** API, and
none completes a task.

- **Task 2 (kernel):** not done:
  - a layout *protocol* (it is a private enum);
  - an invalidation contract (the cache is per call);
  - a compatibility adapter (mixing is unsupported both ways and unrejected one
    way);
  - replacing `Style` resolution;
  - a migration story for external custom containers;
  - a depth guard, validation and work counters.
- **Task 3 (typed composition):** a closed enum exists for the proposal path.
  The legacy direct-mutating modifiers are untouched, and the `@State`
  preservation proof is missing.
- **Task 4 (frame):** the proposal frame has min/ideal/max and alignment. The
  legacy `.frame` is a separate CSS node, `width`/`height` still mutate `Style`
  after the reverted trial, and the finite-`max` rule is unprobed.
- **Task 5 (outer modifiers):** legacy padding wraps, and `Component` padding
  distributes. The matrix, including focus drawing and content shape, is
  undecided.
- **Task 6 (containers):** `HStack`/`VStack`/`ZStack`/`Spacer`/`ProposalScrollView`
  exist beside `Row`/`Column`/`Stack`/`ScrollView`, which are not ported. `List`
  and `Deferred` have no proposal counterpart.
- **Task 7 (advanced layout):** only aspect ratio, and priority between equally
  flexible fixed-ideal children. There is no expansion of non-spacer children,
  no grids and no custom layouts, and all 97 goldens remain.
- **Tasks 8–15:** no evidence in this range, except that the preview is the
  first `Component` in a demo (task 8) and `.allowsHitTesting`/`.onTap` exist
  (task 12).

**Owed before this work is cited as done:**

- a decisions doc with a ruling prefix;
- committed, re-runnable SwiftUI probes, each with a positive control;
- a mutation pass over the kernel that names the tests it reddens;
- `FrameModifier` arms in the five per-conformer and per-site guards;
- a positive `.onTap` dispatch test;
- a test for the overlay id collision, and for the native-under-legacy
  direction;
- a human look at both the default demo and the preview.
