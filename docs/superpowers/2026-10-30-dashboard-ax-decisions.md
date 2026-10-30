# Dashboard accessibility identifiers - decisions

Rulings for three identifier bugs MetalFlow's Dashboard found. Prefix `DA-`. Branch `fix/mfd-ax`. Code: `Sources/MetalUI/AccessibilityTreeBuilder.swift` (unchanged), `Sources/MetalUI/AXNode.swift` (`fillControl`), `TextField.swift`, `TextEditor.swift`; tests `Tests/MetalUITestingTests/IdentifierPropagationTests.swift`; probe
`docs/probes/swiftui-accessibility-identifier-nesting.swift` (header carries the recorded output). **Next unused: `DA-D`.** No divergence label taken.

## DA-A - refuted: SwiftUI overwrites a descendant's identifier; use `.contain`

**Evidence (probed).** `docs/probes/swiftui-accessibility-identifier-nesting.swift`: `VStack { Text(a).id(a); Button(b).id(b) }.accessibilityIdentifier(screen)` publishes both children
as `id=screen` (X1, X3) and the container has no element; with `.accessibilityElement(children: .contain)` the container is a group `id=screen` whose children keep `a` and `b` (X2).
**Ruling.** An earlier DA-A made a plain container yield to descendants' own identifiers. **Withdrawn**: SwiftUI is the design authority, so `IX-W` item 2 / N5 distribution stands exactly as on
the base, the source change and divergence 207 were reverted (207 never merged, so it is unused). An app wanting a findable container with identified children writes `.accessibilityElement(children: .contain)`.
**Pins.** `aContainedContainerIsAGroupWhoseChildrenKeepTheirIdentifiers` (X2; MetalUI's `.contain` already behaves like SwiftUI, no source change) and
`withoutContainTheContainerIdentifierOverwritesTheChildrenAsInSwiftUI` (X1/X3).

## DA-B - modifier order: not reproduced as an identifier loss

**Finding.** Probed against MetalUI on this base with the harness: `.disabled(true).accessibilityIdentifier("x")` and the reverse both publish the identifier, over stacks of text/buttons,
`ProposalText`, `Color`/`Rectangle`, `Spacer`, an empty stack, proposal components, and across a runtime toggle of the disabled flag. SwiftUI keeps it in both orders (M1, M2). The wrapper
modifiers `.opacity`, `.help`, `.onHover`, `.contextMenu`, `.padding`, `.frame`, `.background`, `.clipped`, `.allowsHitTesting`, `.shadow`, `.blur`, `.onTapGesture`, `.onAppear`, `.task`,
`.focusable`, `.id` between a proposal element and the identifier all keep it. Spellings that cannot work are compile errors, not silent: on a legacy element (`Button`, `Text`) `.disabled(_)`
returns `EnvironmentScope<Self>`, which has no `accessibilityIdentifier` (write the identifier first), and `keyboardShortcut` exists on `Button` only (returns `Self`).
**One real asymmetry, not changed.** An identifier wrapper written *outside* a disabled scope registers enabled (its record is not under the scope), so a leaf with no element of its own
(a `Color` marker) reads `isEnabled == true` for `.disabled(true).accessibilityIdentifier` and `false` for the reverse. The identifier is intact; the flag differs; fixing it needs the outer
wrapper to read an inner scope.
**Ruling.** No source change; the order is pinned by `disabledThenIdentifierEqualsIdentifierThenDisabled` (over interactive content) and `anIdentifierSurvivesAWrapperWrittenBeforeIt`
(17 wrappers). If MetalFlow has a failing spelling, it needs the exact expression.

## DA-C - an identified text field keeps its role and text

**Cause.** `TextField` and `TextEditor` published their `.textField`/`.textArea` node (placeholder label, text as value) only `if handlers.axNode.isEmpty`; any declaration (an identifier,
a label, a hint) made the node non-empty, so the element fell back to a generic group with no value. **Ruling.** `AXNode.fillControl(role:label:value:)` fills `role` while `.generic` and
`label`/`value` while `nil`, keeping declarations. So `TextField(...).accessibilityIdentifier("x")` is the `.textField` element, `.value` its text, and `.accessibilityLabel` overrides the
placeholder label. `TextEditor` likewise (`.textArea`). **`SecureField` does not exist in MetalUI** (no secure text rule to follow); nothing is exposed for it, and one added later must pass
`value: nil`. `List` has the same `isEmpty` gate (`AXNode(role: .container)`) and was left alone.
**Pin.** `anIdentifiedTextFieldPublishesItsTextAsValue`. **Cost if wrong.** A declared value on a field is still respected (never overwritten).

## Mutations

Each applied to the declaration named, against `IdentifierPropagationTests`.

| # | Mutation | Reddened |
|---|---|---|
| DA-M8 | `ProposalElementGroup.accessibilityElement(children:)` no longer writes `childBehavior` (the `AccessibilityModifier` chained overload is a second site, not mutated) | `aContainedContainerIsAGroupWhoseChildrenKeepTheirIdentifiers` (an earlier mutation of `StyledElement.accessibilityElement` reddened nothing: a stack takes the proposal overload) |
| DA-M9 | distribution skips nodes that already have an identifier | `withoutContainTheContainerIdentifierOverwritesTheChildrenAsInSwiftUI` |
| DA-M6 / DA-M7 | `isEmpty` gate restored in `TextField` / `TextEditor` | `anIdentifiedTextFieldPublishesItsTextAsValue` (one test covers both) |

Withdrawn-rule history: the old DA-M1, M3, M4 belonged to the withdrawn container rule and are dropped.

## Carried

- Rule for `docs/rules/input-focus.md`: an `accessibilityIdentifier` on a plain container is distributed over its descendants, overwriting theirs, as SwiftUI does (N5, X1); to identify a container and keep the
  children's identifiers write `.accessibilityElement(children: .contain)` (X2). A control that fills its own node (`TextField`, `TextEditor`) uses `AXNode.fillControl` so a declaration never costs it its role or text (`DA-C`).
- DA-B asks MetalFlow for the failing expression; the outer-wrapper-outside-a-disabled-scope enabled flag is open.
- `List`'s `axNode.isEmpty` gate has the same shape as DA-C's cause; `SecureField` must expose no value if added.
