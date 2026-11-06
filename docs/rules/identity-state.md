# Identity, state, environment, lifecycle, animation

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Phases.** `requestLayout` → `prepaint` → `paint`. `isHovered`, `isActive`,
`isFocused` exist only on `PaintPass`, each typecheck-guarded; a new
paint-only query gains a guard and a bullet in `PhaseSeparationTests.swift`'s
header.

**Identity is structural; `.id()` overrides a position, never joins it.**
- An `if` with no `else` and a `for` loop/`ForEach` each take **one**
  structural slot whether or not they produce content (`ID-B`). Content an
  evaluated conditional or loop removes is **reset on return** (`ID-C`,
  `DD-C`), except `$focus`/`$ax`. An **unevaluated** conditional (a `List` row
  out of window) keeps its state (`TB-AH`).
- `.id(_:)` works on every element group via `IdentifiedGroup` (`ID-G`); a
  `StyledElement`'s own `id(_:) -> Self` wins where both apply. **`.id()` must
  be the outermost modifier.** A name an evaluated position leaves is reset
  unless produced elsewhere this frame (`ID-R`). **A new site that mints a
  named id owes a `StateTable.noteNamed` call and an arm in
  `everyNamingSiteStartsAReturningNameFresh`.** All resets run in one pass per
  `sweep()` (E3.13).
- **An `AnyElement` is keyed by its wrapped type** (`ER-A`, record §201, divergence 210 retired): its group entry runs the wrapped element, in all three phases, under `child(of: position, at: 0, name: ElementID(name: "$erased", key: IdentityKey(ObjectIdentifier(E.self))))` and notes it with `noteNamed`, so a changed type departs the old level through `ID-R` (state, focus, `.task`, lifecycle keys and memos reset, a swap back is fresh); an element's recorded bounds stay at the position, everything it registers sits on the level, and **a direct `AnyElement.requestLayout(_:pass:)` caller owns its id** (`ER-B`). A legacy decoration returning `Self` is not a type change (`ER-C`, 211); the swap appears before it disappears (212). A new erased entry owes the level and its `noteNamed`.
- Modifiers are one flat `ModifiedContent<Content, Modifier>` (stage 11;
  `ModifiedElement` is its legacy typealias): each modifier is one layer = one
  node = one id level; outermost takes the parent's slot, inner layers
  `positional(0)` (`MC-A`, `MC-C`). Changing layer **count** resets the
  wrapped element's state; changing values does not. A decoration written
  after a wrapper configures the outermost layer (`OM-C`).
- `.overlay`/`.background(alignment:content:)`: primary under the modifier's
  id, attachment under `.child(of: id, at: -1)` (`MC-P`, `ID-J`); nothing else
  may mean `-1`. A primary of zero or several nodes traps (divergence 73).
- `GlobalElementID.cachedHash` and `==` are safe alone, unsafe together; do
  not simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ (EP-5).

**`Component`** is layout-transparent and identity-opaque: one cursor index,
`@State` under its own id. `.padding` wraps each top-level node (`OM-D`);
`.width`/`.height` frame each member; `.frame` wraps the body in one layer
(divergence 56). Token `background`/`onClick`/`focusable` are not offered —
declare them on members. Over proposal content declare
`some ProposalElementGroup`.

**`@State`** is a box seeded by reflection per element per frame; slots
`.named("$state<n>")`. **Seven reserved names** (`$state<n>`, `$focus`, `$ax`,
`$anim`, `$anim-color`; `$anim-content`/`$anim-viewport` prefixes), pinned by
`theSevenRetentionSlotsAreMutuallyDistinct` — new animation state goes in
`AnimationStore`, not an eighth slot. **Write from input, never from a phase**
(keeps the display link awake forever; a phase-time `@Observable` write is
silently stale). `$state` projects a `Binding`. **A `@State` keeps its default's first
evaluation** (`FV-A`, overturns `LC-S` item 1): `State.bind` calls `StateTable.mark(_:seeding:)`, which stores the
default on a slot with no entry, so a re-evaluated default (`@State var owner = UUID()`, a parameter-seeded `init`) is
discarded after the first and the table holds one entry per declared `@State`; a seed is not a write and journals
as a plain `.mark` (`retained.md`, `FV-B`); an `AnyElement` type swap is a new element (`ER-A`, below). One element value placed
twice resolves its own occurrence under input dispatch (`ID-F`); outside
dispatch it reaches the last-bound one (divergence 71).

**`Binding<Value>`** is SwiftUI's surface but `@MainActor` (divergence 78). A
binding write is a `@State` write. `Binding.animation`/`.transaction` apply
only when the source is `State.projectedValue`; a `Binding(get:set:)` snaps
(`AN-Z`).

**`@Observable`**: the whole frame build is tracked. The `RedrawSentinel`,
the flush ordering in `drawFrameIfNeeded`, the `isFlushing` guard and both
branches of `markDirtyFromObservation` are load-bearing (RX-K).

**`StyledElement`** has four requirements (`style`, `decoration`, `elementID`,
`handlers`). A conformer calls `registerAndScope(...)` in `prepaint` and
`paintDecoration(...)` in `paint`, doing its work **inside** the closures —
each half has its own per-site guard (`OM-AI`). `registerHandlers` holds the
hitbox, focus, AX record and disabled gate; skipping it makes an element
ungated and invisible to VoiceOver. **Any hook added to `Element`'s group
defaults must be mirrored per layer in `ModifiedContent` and in
`AnyElement`'s group entry** (`MC-B`, `LR-AA`). `Handlers` has **nineteen**
members (the eighteenth, `pointer`, one box for the wheel closure and the style, `CI-Q`; the nineteenth, `keyboard`, one box for the `onKeyPress` handlers, the focus interactions and the key-region flag, `KF-I`); `HandlerShape` (`ModifierTests`) and `HandlerFingerprint`
(`OuterModifierMatrixTests`) each gain a field when it gains one.

**Environment (`EV-`).** `EnvironmentScope` is layout- and
identity-transparent; nearest writer wins; **a modifier written after a scope
sits outside it** (`EV-X`). `theme` is readable only in `PaintPass`.
`@Environment` unbound silently reads defaults. `Window.environment` writes
always dirty — write from input. `theme`, `displayScale`,
`controlActiveState` and `accessibilityReduceMotion` are stamped by
`Window`/`Frame`, not sourced from `Window.environment`.
`accessibilityReduceMotion` is `public internal(set)`. **Display-accessibility keys (`AD-`, record §194):** `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`, `accessibilityInvertColors`, `accessibilityShowBorders` (alias `accessibilityShowButtonShapes`), `accessibilityDimFlashingLights` and `accessibilityPlayAnimatedImages` are `public internal(set)` views of one internal `EnvironmentValues.accessibilityDisplay`, stamped by `Window` from `PlatformWindow.accessibilityDisplaySettings` (never from `Window.environment`); `legibilityWeight` is writable, bare `nil`, never stamped. No built-in view reads any of them (divergences 1076, 1078, 1079). `.disabled(d)` is an
`isEnabled` transform; the one gate is `Frame.registerHandlers`' 5-argument
implementation — **a new handler-registering site gains an arm in the D2
guard**. Scroll regions are outside the gate. `KeyBinding` (the keymap's
type) is unrelated to `Binding<Value>`.

**`ForEach` identity (`FI-`, record §95).** A `ForEach` element is identified by its id's **Hashable
value**, as SwiftUI: ids that print alike and differ in value are two elements with separate `@State`
(divergence 79 is retired). For an id type that is not a `DescriptionInjectiveID` (Int family, String,
UUID, Bool, Character, Double, Float) every element's `ElementID` also carries an internal
`IdentityKey` (`ElementID(name:key:)`, never public, plain-import guard G1); injective types mint
today's description-only names, byte for byte (`FI-B`). `GlobalElementID.==`/`cachedHash` are
untouched (`FI-C`); a floating-point id keeps the name dedupe because a NaN is unequal to itself
(`FI-K`). `ElementID` is 24 bytes, a `GlobalElementID` the same 64-byte malloc bucket (`FI-G`).
**`List` rows name by value too** (`LH-`, record §145; divergence 255 retired): `ElementID.forRow(_:keyed:)` is
`ElementID(name:key:)` with `keyed` decided once per build at the row, the `DD-K` scroll note and the AX selection map
(three sites); injective ids are byte-identical and pay nothing, `Frame.listIdentityWork` counts per realised row.

**Lifecycle (`LC-`, record §76).** `.onAppear`/`.onDisappear`/
`.onChange(of:initial:_:)` are one transparent `LifecycleScope` on every
`ElementGroup` (no node, no id level, `Handlers` unchanged; since `ES-A` a
legacy decoration after it lands on its content and it can be a window root —
divergence 120 retired by `ES-J`). **Presence is membership in a build, keyed in the
window-owned `LifecycleStore` (`AnimationStore`'s), never a `StateTable` slot**
(`$lifecycle<depth>` is a store key, no `noteNamed`; the seven slots unmoved);
a modifier on a group fires once while it has content. **Actions run after
`buildAndAdoptFrame`, outside every phase and `withObservationTracking`, under
`StateDispatch`** (`Window.drainLifecycle`, not re-entrant); a write dirties
the window and costs one settle build, so an `onAppear` write is in the first
frame — never run an action from `Frame.render`. Order: changes, appears,
disappears, each reverse pre-order (`LC-F`). A disappearance under a removal
ghost is parked until it ends, and re-insertion cancels both callbacks
(`LC-H`); `onDisappear` reads departed `@State` through `StateTable`'s overlay,
only while an `onDisappear` exists (`LC-I`). A `@State` default keeps its
first evaluation (`FV-A`, divergence 125 retired): `@State var monitor = Monitor()` starts and stops one instance.
A window close runs every `onDisappear` once (`App`'s `onClose` →
`runDisappearancesForClose`); a headless `renderFrame` runs nothing.
**`.task { }`/`.task(id:priority:_:)` are built** (`PX-F`, record §80):
one more `LifecycleWrite` — started with `Task.immediate` as an appearance
(macOS 14–25: `Task`, one frame late, divergence 137), cancelled as a
disappearance (parked under a removal ghost, the box carried back on
re-insertion), an id change cancels the old task **then** starts the new one
in the change bucket; `LC-L`'s blocker went with `SV-H`. A steady frame costs 3K for K scopes and 0
with none. **A key returning from a removal ghost compares its `task(id:)` id and
`onChange` value against the entry it left with** (`TF-A`, record §84; the
departed entry is parked, not dropped; a value read from the content's own reset
`@State` still compares fresh, divergence 123). `.task` under SDL in CI's Linux
image is tested through `@_spi(Checks)` `SDLPlatform(offscreenRenderers:)`, which
renders each window offscreen so frames and the lifecycle drain run with no
presented frame (`TF-C`, `TF-E`; test 3.20b). Consumer test 1.7 refuses every
`warning:` line (`TF-B`).

**`@GestureState` and `phaseAnimator` (`GS-`, record §135).** `GestureState<Value>` is a `@MainActor` wrapper over a `State<Value>` plus a dirty set: a **`$state<n>` slot, no eighth
reserved name** (`BindableState`, `StateTable.write`/`peek`, so the memo, retained and prepaint logs already see its writes), get-only `wrappedValue`, itself its `projectedValue`. `updating(_:body:)` is on
the concrete gestures (a tap's compiles and never runs; none on a composition), returns the receiver's own type and runs in declaration order with `onChanged`. **The reset is one `finished` hook on the
arena leaf, queued in `fail(_:)` and in `act(_:)` before the ended callback and handed back by `cancel()`/`abandon()` (`owesFinish`)**: a new exit from an arena owes a pin that the state resets once
(`everyCancelPathResetsOnce`). Every body of one event starts from the value committed before it; two simultaneous writers resolve in declaration order (divergence 645, probe arms `G7`/`G7e` not re-taken). The
update's transaction applies only when the body set an animation, the reset's only when it animates (divergence 99's one root). `phaseAnimator`/`PhaseAnimator` are `keyframeAnimator`'s transparent scope
with a `PhaseRecord` in `AnimationStore` at **`$phase<depth>`** (never a `StateTable` slot, `keyframeDepth`'s counter shared): no trigger cycles forever, a trigger runs once through the phases back to the
first, each held for `Animation.nominalDuration`; it calls `noteActiveAnimation()`, **never `requestAnotherFrame()`**; Reduce Motion is not changed (`GS-K`, unmeasured); it is refused by the retained paths by
name while cycling. No `Retained*.swift` edit, no `Handlers` change, no seam requirement. Demos: `METALUI_CANVAS_DEMO=1` chips, `METALUI_LOOKS_DEMO=1` pulse. Pins count work and values.

**Animation (`AN-`).** `withAnimation` = `withTransaction`; the frame's
transaction is a stack; `.transaction`/`.animation(_:value:)` are transparent
scopes. One root transaction per build (divergence 99). Legacy fields animate
in `animated(_:_:for:pass:)` (layout) and `animatedBackground`/`animatedColor`
(paint) — **a site that skips its helper is silently unanimated**; guards
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
`everyBackgroundPaintingSiteAnimatesItsColour`. Proposal `LayoutModifier`s
animate through the window-owned `AnimationStore`. "Live" is
`Frame.noteActiveAnimation()` → `hasActiveAnimations`, **not**
`wantsAnotherFrame` — never raise both. **Clock-driven work never marks the
window dirty** (`HT-Z`): a time-driven fade (the scroll indicator) is
`noteActiveAnimation()`, a pending gesture or tooltip timer is
`Window.awaitsATimer`; `wantsAnotherFrame`/`setNeedsRedraw()` are for a
change, or a one-shot correction. In-flight values are clamped;
declared values never. Structure snaps, values interpolate (`LR-AS`); a new
read of `Style` in the lowering owes an animated arm. Interpolation is
per-component RGB. Transitions: only the outermost group transitions;
insertion needs the conditional evaluated last frame; removal draws a ghost,
**the first thing in the run of its container** (`TransitionStore.resolveAnchors`: the nearest ancestor of the ghost's position that
passed `recordElementBounds`, drawn by `Frame.paintAnchoredGhosts(at:)` from `Element.paintGroup`, `paintDecoration`'s content, a
modifier chain's innermost layer, `AnyElement`'s entry and the root; a hook that draws taints the paint recorders, `ghostInRun`, since
a direct insert bypasses them; `XF-F`), and a ghost always exists, so empty content still parks `onDisappear` (`XF-G`);
**a builder `if`, `if`/`else` branch and non-lazy `ForEach` element fades by default** (`XF-H`, record 206; divergence 98 narrowed: a unit notes its scene sequence range at paint, a removal slices the previous frame's scene by it, an insertion opens a non-capturing `.fade` scope; a framework slot is `OptionalGroup(_:)`, never `OptionalGroup(builder:)`; **a new conditional site decides whether it is a unit and notes the range**; a mixed unit carves its annotated members out; nothing is captured at rest, and the retained records carry the ranges, `XF-I`). Reduce Motion changes only
transitions (to a cross-fade). **`matchedGeometryEffect` is a paint map, not a relayout** (`MG-A`): a window-owned
`MatchedGeometryStore` (never a `StateTable` slot), a newcomer takes a *source* leaver's drawn frame under the transaction at it, none from an explicit
`.transition(.identity)` leaver; **the leaver moves toward the source as it fades** (`XF-M`, record 207, row 897 narrowed: its sequence range is carved into a ghost of its own with `[.opacity, .translate]` on the ghost's one curve; a replay re-notes `displayed` and the group's range from the retained record, `XF-N`, record 211); hit testing keeps the laid-out frame; an occurrence with a matched group is graft-refused as `matchedGeometry`. A custom
`Transition` returns a `TransitionContent` (opacity/scale/offset), never a view (`MG-F`). **A `Component & Animatable` interpolates its data into `self` in `requestGroupLayout`** (`VA-I`, record 209), after its id and before the `@State` bind, through `interpolateAnimatableComponent` and `animatedVector` (never a `StateTable` slot, never `requestAnotherFrame()`); `.equatable()` interpolates before `==` and inside its build window (`VA-K`); a non-`Animatable` component pays nothing (`aNonAnimatableComponentPaysNoTrack`). **Tests never sleep: drive
`simulateTick(timestamp:)`.**

**Decorations after transparent scopes (`ES-`, records §167, §168, §169, §172).** `EnvironmentScope`, `LifecycleScope`, `PresentationScope`, `ToolbarScope` (`ES-A`), `ModifierKeysScope`, `GlassTagScope` (`ES-D`) and `TransitionGroup` (`ES-E`) are an `Element` over an `Element` and a `StyledElement` over a `StyledElement`, forwarding every requirement to their content, so a decoration written after one lands inside it and any modifier order compiles; each declares its own `id(_:) -> IdentifiedGroup<Self>` so `.id` still wraps the scope (`ES-C`). `CoordinateSpaceScope`, `TransactionScope` and `GeometryChangeScope` must not forward (a forwarded decoration was measured inside the space, the transaction or the measurement): their accessors configure a `.padding(0)` `ModifierLayer` of their own, and a scope holding one runs as `ModifiedElement<Self>` over itself without it, so the decoration sits outside, SwiftUI's order (`ES-H`, `ES-J`; divergence 120 retired). A new scope decides which it is by measuring a decoration after it against the same one before it. A scope's `Element` extension answers `content.elementID` (`ES-K`): the `StyledElement` conformance's `elementID` cannot satisfy the wider `Element` requirement, and the default `nil` hid a named element's name when it was entered as an element. The `style`/`elementID` forwards are observable through the public protocol requirements and pinned (`ScopeForwardTests`).

**`ViewThatFits` candidates (`VF-C`..`VF-F`, record 217).** Every candidate is built under the view's id every frame, so its `@State` is live and survives a switch (divergence 220), but `Frame.applyFitChoices()` (after layout, before `transitions.afterLayout`) elides the unchosen ones from prepaint and paint, **retracts the lifecycle entries and presentation records noted inside them** (`FitNote` intervals; `LifecycleStore.retract`; divergence 219 for the window metadata it does not retract) and `resolveFocus` clears a focused element inside one. A new build-time channel written under a view owes a `FitNote` and a retraction.
