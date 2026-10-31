# Scope decorations - decisions

Rulings for modifiers written after a transparent scope (`.lineLimit`, `.disabled`, `.onAppear`, `.alert`, `.toolbar`, `.navigationTitle`...). Prefix `ES-`.
Branch `fix/scope-decorations` from master `63cc5af1`; `ES-D`…`ES-G` on `fix/remaining-scope-decorations` from master `c686d1ef` (record 168); `ES-H`, `ES-I` on `fix/lift-es-f-g` from master `d2797c5d` (record 169). **Next unused: `ES-J`.**
Why: MetalFlow wrote `Text("x").lineLimit(1).accessibilityIdentifier("x")` and `Button(...).disabled(true).accessibilityIdentifier("b")`; neither compiled, because the scope was an `ElementGroup`, not a `StyledElement`
(divergence 120). In SwiftUI any modifier follows any other.

## ES-A - a scope over an element is that element

**Ruling.** `EnvironmentScope`, `LifecycleScope`, `PresentationScope` and `ToolbarScope` gain two conditional conformances. `Element where Content: Element` implements the three `Element` phases as the scope's
own work around the content's (`EnvironmentScope`: the stored values pushed around the content's phases and the window-preference report in layout; the others: the lifecycle/presentation/toolbar note, owned by the
element's own `id`). `StyledElement where Content: StyledElement` forwards `style`, `decoration`, `elementID` and `handlers` to `content`. The group entry points (`requestGroupLayout` and its typed twin) are untouched,
so a scope in a container is still transparent to layout and identity (`EV-B`, `LC-B`): the `Element` path runs only where a scope is used as an element (a window root, `Deferred` content, a `List` row).
**What it means.** A `Self`-returning decoration after a scope lands on the content *inside* the scope, which is observably SwiftUI's order for a modifier that reads none of the scope's value (`.padding`,
`.background`, `.accessibilityIdentifier`). `.disabled(true).onClick {}` has the handler inside the disabled scope, so it does not fire, as in SwiftUI. `.frame` and the `ElementGroup` wrappers still wrap *outside* the
scope (`EV-X`, unchanged). `.padding` was never blocked (it is an `ElementGroup` wrapper, so it already sat outside the scope); the blocked ones were the `StyledElement` methods.
**Retired by it.** The `LC-B` item 4, `SV-K` item 1, `MD-S` item 1 and `AS-N` negatives (a decoration after the scope; the scope as a window root), and the `EV-B` clause "not directly before `.padding` or a handler
modifier". A window-preference scope as a window's root now sets the window title (pin `aNavigationTitleOnTheRootElementSetsTheWindowTitle`).
**Pins.** `decorationsChainAfterTransparentScopes` (plain-import guard), `aLegacyDecorationAfterALifecycleModifierCompiles`, `aLifecycleModifierCanBeAWindowRoot`, `aLegacyDecorationAfterAPresentationModifierCompiles`,
`aToolbarOnAnElementCanBeAWindowRootAndTakeDecorations`, `anOutsideModuleCanSpellTheAppShellAPI` (positives), and in `MetalUITestingTests`: `aLineLimitedTextTakesPaddingAndAnIdentifierAfterTheScope`,
`aDisabledButtonKeepsItsIdentifierAndIgnoresClicks`, `aHandlerAfterDisabledIsDisabledToo`, `aBackgroundWrittenAfterAScopeIsPainted`, `aScopeOnTheRootElementStillScopesItsEnvironment`.
**Cost if wrong.** A modifier that reads the scope's value and was written after it (say `.lineLimit(1)` then a text modifier that reads the limit) now sees it, where SwiftUI's outer modifier would not; none exists today
because the scope's values are read by the content's own phases, which is what the scope is for.

## ES-B - `.onGeometryChange` does not chain

**Ruling.** `GeometryChangeScope` gets no `StyledElement` (or `Element`) conformance. It measures the union of its content's nodes, and `.padding`, `.background` or `.offset` forwarded onto the content would be inside
that measurement; SwiftUI's modifier after `.onGeometryChange` is outside the measured size. Forwarding would be observably wrong, so the scope keeps divergence 120 (narrowed to it alone). Write the decoration first.
**Pin.** `aDecorationAfterOnGeometryChangeStillDoesNotCompile` (with a before-spelling control); `onGeometryChangeAndTimelineViewCompileOnBothVocabularies`' arm.

## ES-C - `.id` after a scope still wraps the scope

**Ruling.** A `StyledElement` has its own `id(_:) -> Self`, so after ES-A `Text("a").onAppear {}.id("k")` would have named the *content* inside the scope, whose lifecycle entry is keyed by position: a changed id stopped
being a new element to it (`aChangedIdRunsTheNewAppearBeforeTheOldDisappear` and `contentThatReturnsComparesAgainstNothing` went red on the first full run). Each of the four scopes declares `id(_:) -> IdentifiedGroup<Self>`
on the concrete type, which outranks the protocol extension's, so `.id` wraps the scope as before (`ID-G`). Any other `Self`-returning `StyledElement` modifier that has an `ElementGroup` twin with different
semantics needs the same member; the full suite found only `id` (and `.task`'s old negative guard).
**Pins.** the two tests above. Mutation: delete the member in `LifecycleScope` (both reddened).

## ES-D - `.onModifierKeysChanged`, `.glassEffectID` and `.glassEffectUnion` chain

**Ruling.** `ModifierKeysScope` and `GlassTagScope` take ES-A's two conditional conformances and ES-C's `id(_:) -> IdentifiedGroup<Self>`. Neither reads its content's geometry or decoration: the modifier-keys scope
notes the held modifiers in prepaint, and the glass tag is read only by the typed `glassEffect`'s registration with a container, which a legacy decoration (`.glassEffect` on `StyledElement` among them) never makes
(`LG-U`). So where a forwarded decoration sits is unobservable to the scope. On the `Element` path the modifier-keys scope owns its store entry by the element's own id (`$modkeys<depth>` under it, as ES-A's
lifecycle owner), and the tag is pushed around the content's prepaint.
**Pins.** `decorationsChainAfterTheRemainingForwardingScopes` (plain-import guard: decorations, roots, `.id` typed `IdentifiedGroup`), `aModifierKeysScopeTakesAnIdentifierAndAClickAfterIt`,
`aModifierKeysScopeAtTheRootStillReports` (`MetalUITestingTests`), `aGlassUnionTagKeepsTaggingWithADecorationAfterIt` (a union over a legacy `Box` holding a container joins two circles 120 apart, in a column and as
the frame's root; untagged they stay two).

## ES-E - `.transition` chains

**Ruling.** `TransitionGroup` takes the same conformances and `id` member. Measured: a background written after `.transition(.opacity)` on an `if`'s tile reads alpha ½ half-way through a `linear(1)` insertion and 1
settled, the same as the background written before; SwiftUI's transition is a trait of the whole view, so both orders fade together there too. The decoration lands inside the group, so the group stays the
outermost group of the inserted content and keeps its claim. A wrapper written after it (`.frame`, the padding layer, `.id`) still wraps the scope; whether a group under a wrapper claims is `AN-AH` item 4's rule, unchanged and not re-measured here. On the `Element`
path (a window root, `Deferred` content, a `List` row) no conditional inserts the element, so the transition is inert and the content is forwarded unchanged.
**Pins.** the guard above, `aBackgroundAfterATransitionTransitionsWithTheContent` (with the before control), `aTransitionAtTheRootIsInertAndKeepsItsDecoration`, `aTransitionTakesAnIdentifierAndAClickAfterIt`.

## ES-F - `.coordinateSpace` does not chain (lifted by `ES-H`)

**Ruling.** `CoordinateSpaceScope` gets no conformance, as ES-B. Measured with a temporary conformance (the ES-A shape, the space built from the element's node around its content's prepaint): a legacy `Box` holding a
40 x 20 leaf, `.coordinateSpace(.named("outer")).offset(x: 7, y: 9)`, reports the leaf at (7, 9) in the space - the same as the offset written *before* the scope - where SwiftUI's offset after `.coordinateSpace`
moves the space with the view and the leaf reads (0, 0) (probe arm G3, pinned for the typed spelling by `aNamedSpaceMovesWithAnOffsetOnItsContainer`). The forwarded render effect opens inside the content's
`registerAndScope`, after the space was built from the unmoved node. Divergence 120 names the scope.
**Pin.** `aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile` (its `space` negative, with the before control).

## ES-G - `.animation(_:value:)` and `.transaction` do not chain (lifted by `ES-H`)

**Ruling.** `TransactionScope` gets no conformance. Measured with a temporary conformance (the transaction pushed around the content's layout and paint): `Box().animation(linear(1), value: flag).background(c)`
changing `flag` and `c` together paints the mid colour (l 0.767 between surface and accent) half-way, as the background written before does; SwiftUI's modifier written after `.animation(_:value:)` is outside it and
snaps (probe arm T3b). A forwarded decoration is always inside the scope's transaction. Divergence 120 names both modifiers.
**Pin.** the same guard's `animation` and `transaction` negatives.

## ES-H - a decoration after `.coordinateSpace`, `.animation(_:value:)` or `.transaction` is a layer outside the scope

**Ruling.** `CoordinateSpaceScope` and `TransactionScope` become `StyledElement where Content: StyledElement`, but they do **not** forward: their four accessors read and write a legacy layer of the
scope's own (`outer: ModifierLayer?`, a `.padding(0)` layer, `ModifierLayer(style: Style())`), created by the first setter a decoration calls. A scope with a layer lays out, prepaints and paints as
`ModifiedElement<Self>` over itself without the layer (`withLayer`), so `X.coordinateSpace(s).offset(x: 7, y: 9)` is exactly `X.coordinateSpace(s).padding(0).offset(x: 7, y: 9)`, which already wrapped the scope
from outside. That is SwiftUI's structure: the modifier after the scope is a view around it. For the space, the layer's `registerAndScope` opens its offset (any render effect) before the undecorated scope builds
the space from the innermost open effect's composed map, so the space moves with the view; for the transaction, the layer's style is animated in `_requestLayout` and its colours in `_paint`, both outside the
scope's `withTransactionScope`, so the decoration resolves under the inherited transaction. The undecorated paths are byte-for-byte today's. Each scope keeps ES-C's `id(_:) -> IdentifiedGroup<Self>`.
**Measured** (`LayeredScopeDecorationTests`): the leaf in a legacy `Box` reads (0, 0) in the space with the offset after it and (7, 9) with the offset before (the control), its global frame moved (7, 9)
against the undecorated twin, in a column and as the window root; a 60 x 30 tile whose own background and an after-background both go surface to accent under `linear(1)` paints two rects half-way: the outer
exactly accent (snapped), the inner neither colour (animating) - for `.animation(_:value:)` and `.transaction` in a column, and `.animation(_:value:)` as the root. Naive forwarding (`ES-F`/`ES-G`'s temporary conformance) reddens
both (mutations 16, 17).
**Cost.** A decorated scope is one more node and one identity level (the content moves one level down), like any wrapper. Whether a scope has a layer is a property of the expression (a decoration call is
written or not), so it never appears at run time. Accessibility and handlers written after the scope land on the layer, not the content, as after `.padding` (`aLineLimitedTextTakesPaddingAndAnIdentifierAfterTheScope`'s shape).
**Lifts.** `ES-F` and `ES-G`; their negatives become the positive guard `decorationsChainAfterACoordinateSpaceAndATransaction`. Divergence 120 names `.onGeometryChange` alone again.
**Pins.** `anOffsetAfterACoordinateSpaceMovesTheSpaceWithTheView`, `aBackgroundAfterAnAnimationSnapsWhileTheContentAnimates`, `aBackgroundAfterATransactionIsOutsideIt`, `anAnimationScopeAtTheRootStillAnimates`
(`MetalUITests`), `identifiersAndClicksAfterACoordinateSpaceAndATransactionLand` (`MetalUITestingTests`), the guard above.

## ES-I - the two scopes on the `Element` path and the typed entry

**Ruling.** Both scopes are `Element where Content: Element` (a window root, `Deferred` content, a `List` row), with `ScopeLayerState<Plain>` (`ModifiedContent.swift`) as their element states: `plain` for an
undecorated scope (the space built from the element's own bounds around the content's prepaint; the transaction resolved by `scopedTransaction(applying:at:)` keyed at the element's own id and pushed around the
content's layout and paint), `layered` (an existential, since its type names the scope) for a decorated one, which is the layer as an element over the undecorated scope as its group content. The typed
entries (`requestProposalGroupLayout`) route a decorated scope to the untyped layer path; a decoration needs `Content: StyledElement`, which no proposal content is, so the arm is unreachable today.
**Unobservable.** An undecorated `.coordinateSpace` at a window root: the root's frame is the window's, so the named space equals `.global` there; dropping that push reddens nothing (mutation 20).

## Mutations

Applied to the declaration named, against `ScopeDecorationTests` (after `swift build --build-system native --build-tests`). Rows 16-25 (`ES-H`, `ES-I`) on `fix/lift-es-f-g` at `e7da6af7`, one at a time and reverted with `git checkout` (the source committed); behaviour rows filtered to `LayeredScopeDecorationTests`, `ScopeDecorationTests`, `RemainingScopeDecorationTests`, `CoordinateSpaceTests`, `TransactionTests` (59 tests); guard rows rebuilt the `MetalUI` module only. Rows 7-15 (`ES-D`…`ES-G`) on `fix/remaining-scope-decorations` at `477280cc` plus the
row-8 fix, in the worktree, one at a time and reverted; guard rows rebuilt the `MetalUI` module only and ran the built test binary; behaviour rows filtered to `ScopeDecorationTests`, `RemainingScopeDecorationTests`,
`ModifierKeysTests`, `TransitionTests`, `GlassTests` (69 tests).

| # | Mutation | Reddened |
|---|---|---|
| 1 | `EnvironmentScope: StyledElement`'s `handlers` setter dropped | `aLineLimitedTextTakesPaddingAndAnIdentifierAfterTheScope`, `aDisabledButtonKeepsItsIdentifierAndIgnoresClicks`, `aHandlerAfterDisabledIsDisabledToo` (`accessibilityIdentifier` is stored in `Handlers`, so each loses its element) |
| 2 | the `decoration` setter dropped | `aBackgroundWrittenAfterAScopeIsPainted` |
| 3 | `EnvironmentScope.prepaint(_:bounds:layout:pass:)` without the `withEnvironment` push | `aScopeOnTheRootElementStillScopesItsEnvironment` |
| 4 | the conformance deleted (any of the four scopes) | the test target does not compile; per scope the guard `decorationsChainAfterTransparentScopes` is refused for `onClick`/`padding` |
| 5 | the `style` setter dropped | **nothing** - every `Style`-writing modifier is refused by name under the proposal layout authority (`LR-FO`), so a forwarded `style` write is unobservable from a window; forwarded for completeness |
| 6 | the `elementID` setter dropped | **nothing** - no `StyledElement` method writes `elementID` (`.id` is an `ElementGroup` wrapper); forwarded for completeness |
| 7 | MES-3: `extension ModifierKeysScope: StyledElement` deleted | `decorationsChainAfterTheRemainingForwardingScopes` (refused for `padding`/`accessibilityIdentifier` on `ModifierKeysScope` only) |
| 8 | MES-4: `ModifierKeysScope.id(_:) -> IdentifiedGroup<Self>` deleted | `decorationsChainAfterTheRemainingForwardingScopes` (`cannot convert ModifierKeysScope<Text> to IdentifiedGroup<…>`). **The first spelling of the arm (`let _: IdentifiedGroup<…> = X.id("k")`) reddened nothing**: the annotation picks the `ElementGroup` overload with or without the member; the arm now assigns the unannotated result |
| 9 | MES-5: `CoordinateSpaceScope: Element, StyledElement` added (forwarding) | `aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile` (1 issue, the `space` negative) |
| 10 | MES-6: the same for `TransactionScope` | `aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile` (2 issues, the `animation` and `transaction` negatives) |
| 11 | `ModifierKeysScope: StyledElement`'s `handlers` setter drops the write | `aModifierKeysScopeTakesAnIdentifierAndAClickAfterIt`, `aModifierKeysScopeAtTheRootStillReports` (each loses its identifier) |
| 12 | `noteModifierKeys` dropped from `ModifierKeysScope.prepaint(_:bounds:layout:pass:)` | `aModifierKeysScopeAtTheRootStillReports` |
| 13 | `TransitionGroup: StyledElement`'s `decoration` setter drops the write | `aBackgroundAfterATransitionTransitionsWithTheContent`, `aTransitionAtTheRootIsInertAndKeepsItsDecoration` |
| 14 | `TransitionGroup: StyledElement`'s `handlers` setter drops the write | `aTransitionTakesAnIdentifierAndAClickAfterIt` |
| 15 | the `glassTags` push dropped from `GlassTagScope.prepaint(_:bounds:layout:pass:)` | `aGlassUnionTagKeepsTaggingWithADecorationAfterIt` (its root arm) |
| 16 | MES-7a: `CoordinateSpaceScope: StyledElement`'s four accessors forward to `content` (the naive ES-A shape, ES-F's temporary conformance) | `anOffsetAfterACoordinateSpaceMovesTheSpaceWithTheView` (the column arm and the root arm each read (7, 9)) |
| 17 | MES-7b: the same for `TransactionScope` | `aBackgroundAfterAnAnimationSnapsWhileTheContentAnimates`, `aBackgroundAfterATransactionIsOutsideIt`, `anAnimationScopeAtTheRootStillAnimates` (one mid-way rect where two are expected) |
| 18 | `CoordinateSpaceScope`'s `handlers` setter drops the write | `identifiersAndClicksAfterACoordinateSpaceAndATransactionLand` (no element "s") |
| 19 | `TransactionScope`'s `handlers` setter drops the write | `identifiersAndClicksAfterACoordinateSpaceAndATransactionLand` (no element "a") |
| 20 | the `withNamedSpace` push dropped from `CoordinateSpaceScope.prepaint(_:bounds:layout:pass:)`'s undecorated arm | **nothing** - at a window root the named space is `.global` (`ES-I`, unobservable) |
| 21 | the `withTransactionScope` push dropped from `TransactionScope.paint(_:bounds:layout:prepaint:pass:)`'s undecorated arm | `anAnimationScopeAtTheRootStillAnimates` (its plain arm snaps) |
| 22 | MES-5: `extension CoordinateSpaceScope: StyledElement` made a plain extension | `decorationsChainAfterACoordinateSpaceAndATransaction` (`offset(x:y:)` refused) |
| 23 | MES-6: the same for `TransactionScope` | `decorationsChainAfterACoordinateSpaceAndATransaction` (`background` refused) |
| 24 | MES-8: `CoordinateSpaceScope.id(_:) -> IdentifiedGroup<Self>` deleted | `decorationsChainAfterACoordinateSpaceAndATransaction` (`cannot convert CoordinateSpaceScope<Text> to IdentifiedGroup<…>`) |
| 25 | `TransactionScope.id(_:) -> IdentifiedGroup<Self>` deleted | `decorationsChainAfterACoordinateSpaceAndATransaction` (`cannot convert TransactionScope<Text> to IdentifiedGroup<…>`) |

## Carried

- **Shard rule:** in `docs/rules/identity-state.md` (`ES-` paragraph), updated for `ES-D`…`ES-G` and `ES-H`.
- `WindowPreferences.swift` scopes (`navigationTitle`, `navigationDocument`, `onOpenURL`) are `EnvironmentScope`s and chain with it; `onOpenURL` on the `Element` path owns its handler by the element's id, not by the
  group position (no test distinguishes them: the owner is only a dispatch key). The same holds for `ModifierKeysScope`'s owner on its `Element` path (`ES-D`).
- Every single-content modifier scope is now ruled: forwarding `EnvironmentScope`, `LifecycleScope` (`.task` included), `PresentationScope`, `ToolbarScope` (`ES-A`), `ModifierKeysScope`, `GlassTagScope` (`ES-D`),
  `TransitionGroup` (`ES-E`); layering `CoordinateSpaceScope`, `TransactionScope` (`ES-H`); refusing `GeometryChangeScope` (`ES-B`). Containers (`ScrollViewReader`, `GlassEffectContainer`, `IdentifiedGroup`) are
  out of scope. A new scope decides which it is, by measuring a decoration after it against the same decoration before it.
- `ES-F` and `ES-G` are lifted by `ES-H`'s own layer, not by either idea this item named (building the space inside the content's `registerAndScope` could not tell an offset before the scope from one after it: both land in one `Decoration`). The same layer would lift `ES-B` (`.onGeometryChange` measuring its content without the layer's padding or offset); not attempted, so divergence 120 stays.
- A decorated `CoordinateSpaceScope`/`TransactionScope` copies itself into a `ModifiedElement` and back once per phase (`withLayer`) and stores the layer's layout as an existential: cost paid only by decorated scopes, not measured.
- The `style` and `elementID` forwards have no observable pin (mutations 5 and 6), for the new scopes as for the first four.
