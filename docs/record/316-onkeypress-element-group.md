# 316 - `onKeyPress` on any `ElementGroup` (`KF-AC`)

Branch `feat/onkeypress-element-group` from master `324686be`. Class `A`, no divergence. Requested by Alloy: a helper returning `some ElementGroup` could not attach `.onKeyPress`, which SwiftUI offers on any `View`.

**What.** The five spellings (`_:action:`, `_:phases:action:`, `keys:phases:action:`, `characters:phases:action:`, `phases:action:`) as `extension ElementGroup` in `Sources/MetalUI/ElementGroupKeyPress.swift`, each returning `ModifiedElement<LayerBase>`.

**How.** Each wraps the group once through `_wrap(ModifierLayer(style: Style()))` (what `.padding(0)` makes: one node, one identity level, a default flex-row style) and calls that `StyledElement`'s own `onKeyPress`, so handlers, filters, phases and order are `KF-B`/`KF-C`'s and the result is a `StyledElement` whose later keyboard modifiers join the same layer (`KF-AC` items 1 and 2). The proposal path's `KeyboardModifier` was not reused: it needs a proposal content with exactly one native child, which a plain group has not.

**Routing.** The layer is an ancestor of whatever inside holds focus; it hears a key on the focus chain outermost first, so it runs before a focused descendant's handler and a `.handled` answer from it shadows the descendant (the existing `StyledElement` order; the task's "does not hear when the descendant handles it" is not MetalUI's order and is not changed here). It does not make the group focusable, as on a `StyledElement` and in SwiftUI.

**Overload resolution.** `StyledElement`, `ProposalElementGroup` and `KeyboardModifier` keep their own, more specific spellings (`Self`, `KeyboardModifier<Self>`, `Self`); a legacy `ModifiedElement` returns `Self`. No ambiguity arises.

**Tests** (`Tests/MetalUITests/ElementGroupKeyPressTests.swift`, 5): a plain-group helper hears a key its focused descendant does not handle; its handler runs before the descendant's and `.ignored` lets the descendant hear it; its key filter ignores other keys; each of the five spellings routes (as the first modifier, which is the one that reaches the new overload) hearing what it filters for; `existingConformersKeepTheirOverload` (compile-time `accept(_, as:)` type assertions for `Box`, a padded `Box`, `MetalView`, a `KeyboardModifier` chain and a plain group, and the chain on the result staying one layer). The windows must be held alive by the test (`withExtendedLifetime`): a discarded `Window` makes every key test pass or fail vacuously.

**Mutations shown red** (each applied, run, restored): `_:` spelling's key to `"z"` (tests 1 to 3); `phases: phases` to `.down` in `_:phases:`; `keys: keys` to `[.escape]`; `characters: characters` to `.letters` (the routing test). The first routing test written chained all five on one group and was green under three mutations: only the first call reaches the `ElementGroup` overload, the rest are the layer's `StyledElement` spellings, so each spelling is now first on its own group.

**Docs.** Inventory family `key-press-element-group` (class A, arm `K2v`) and its `M` row; ruling `KF-AC`; the rule in `docs/rules/input-focus.md`.

**Full run** (`swift test --build-system native --no-parallel`, unfiltered, on `feat/onkeypress-element-group`): 6114 tests in 32 suites passed (the 5 new included). The three docs checks print nothing.
