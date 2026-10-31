# Scope decorations - decisions

Rulings for modifiers written after a transparent scope (`.lineLimit`, `.disabled`, `.onAppear`, `.alert`, `.toolbar`, `.navigationTitle`...). Prefix `ES-`.
Branch `fix/scope-decorations` from master `63cc5af1`. **Next unused: `ES-D`.**
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

## Mutations

Applied to the declaration named, against `ScopeDecorationTests` (after `swift build --build-system native --build-tests`).

| # | Mutation | Reddened |
|---|---|---|
| 1 | `EnvironmentScope: StyledElement`'s `handlers` setter dropped | `aLineLimitedTextTakesPaddingAndAnIdentifierAfterTheScope`, `aDisabledButtonKeepsItsIdentifierAndIgnoresClicks`, `aHandlerAfterDisabledIsDisabledToo` (`accessibilityIdentifier` is stored in `Handlers`, so each loses its element) |
| 2 | the `decoration` setter dropped | `aBackgroundWrittenAfterAScopeIsPainted` |
| 3 | `EnvironmentScope.prepaint(_:bounds:layout:pass:)` without the `withEnvironment` push | `aScopeOnTheRootElementStillScopesItsEnvironment` |
| 4 | the conformance deleted (any of the four scopes) | the test target does not compile; per scope the guard `decorationsChainAfterTransparentScopes` is refused for `onClick`/`padding` |
| 5 | the `style` setter dropped | **nothing** - every `Style`-writing modifier is refused by name under the proposal layout authority (`LR-FO`), so a forwarded `style` write is unobservable from a window; forwarded for completeness |
| 6 | the `elementID` setter dropped | **nothing** - no `StyledElement` method writes `elementID` (`.id` is an `ElementGroup` wrapper); forwarded for completeness |

## Carried

- **Shard rule (for the area shard when the integration lands):** a transparent scope (`EnvironmentScope`, `LifecycleScope`, `PresentationScope`, `ToolbarScope`) is an `Element` over an `Element` and a `StyledElement`
  over a `StyledElement`, forwarding every requirement to its content, so a decoration written after it lands inside it (`ES-A`); a scope that measures its content (`GeometryChangeScope`) must not (`ES-B`), and a new
  scope decides which of the two it is.
- `WindowPreferences.swift` scopes (`navigationTitle`, `navigationDocument`, `onOpenURL`) are `EnvironmentScope`s and chain with it; `onOpenURL` on the `Element` path owns its handler by the element's id, not by the
  group position (no test distinguishes them: the owner is only a dispatch key).
- Other `-> …Scope` modifiers outside the four (`AnimationScope`, `CoordinateSpaceScope`, `TaskModifier`, `ModifierKeysChange`, `TransitionGroup`...) were not converted: none is named by divergence 120 and the report
  did not hit them. The same two extensions apply to each that forwards cleanly; `.task` and `.coordinateSpace` would need the geometry question (`ES-B`) answered first.
- The `style` and `elementID` forwards have no observable pin (mutations 5 and 6).
