# Dashboard accessibility identifiers - decisions

Rulings for three identifier bugs MetalFlow's Dashboard found. Prefix `DA-`. Branch `fix/mfd-ax`. Code: `Sources/MetalUI/AccessibilityTreeBuilder.swift` (`distribute`,
`declaresIdentifier(below:)`), `Sources/MetalUI/AXNode.swift` (`fillControl`), `TextField.swift`, `TextEditor.swift`; tests `Tests/MetalUITestingTests/IdentifierPropagationTests.swift`; probe
`docs/probes/swiftui-accessibility-identifier-nesting.swift` (header carries the recorded output). **Next unused: `DA-D`.** Divergence 207.

## DA-A - a container identifier never replaces a descendant's own

**Evidence (probed).** SwiftUI on macOS does overwrite: `VStack { Text(a).id(a); Button(b).id(b) }.accessibilityIdentifier(screen)` publishes both children as `id=screen` (X1, X3), and
the container has no element at all. Only `.accessibilityElement(children: .contain)` gives a group with the children's own ids (X2). So `IX-W` item 2 ("distributed exactly as a label is", N5)
was faithful, and the app's report is SwiftUI's behaviour, which MetalFlow's tests cannot live with.
**Ruling.** In step A (`distribute`), a plain container that would hand its identifier down is **not** distributed through when any kept node below it publishes an identifier of its own (declared,
or `derivedIdentifier`; an `.ignore` element's children do not count). It stays a node, a group carrying the identifier, and its descendants are published beneath it unchanged; nothing is
handed down, so a sibling without an identifier does not inherit it either (it is findable inside the identified group). Label, value and hint the container declared are then also not distributed
(it keeps them, as `.contain` does). With no descendant identifier, distribution is as before (N5). The depth is the whole subtree, because a plain stack is flat but an element with a node
(`.contain`, a button) is not.
**Pins.** `aContainerIdentifierNeverReplacesADescendantsOwn`, `theContainerIdentifierStaysFindableAsAGroupHoldingItsDescendants`, `aSiblingWithoutItsOwnIsContainedNotRelabelled`,
`withoutDescendantIdentifiersTheContainerIdentifierStillDistributes`.
**Cost if wrong.** An app that relied on one identifier reaching every text of a container now finds the container instead, only when a descendant also declares one.
**Divergence 207** (SwiftUI overwrites, MetalUI keeps).

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
| DA-M1 | `keepsItsIdentifier = false` (old distribution) | `aContainerIdentifierNeverReplacesADescendantsOwn`, `theContainerIdentifierStaysFindableAsAGroupHoldingItsDescendants`, `aSiblingWithoutItsOwnIsContainedNotRelabelled` |
| DA-M3 | subtree check looks at direct kids only | `theContainerIdentifierStaysFindableAsAGroupHoldingItsDescendants` (nested `.contain` arm; a first version of the fixture, with only plain stacks, did not redden: plain stacks are flat) |
| DA-M4 | always a group, the descendant check replaced by `true` | `withoutDescendantIdentifiersTheContainerIdentifierStillDistributes`, `disabledThenIdentifierEqualsIdentifierThenDisabled` |
| DA-M6 | `TextField.prepaint` back to the `isEmpty` gate | `anIdentifiedTextFieldPublishesItsTextAsValue` |
| DA-M7 | `TextEditor.prepaint` back to the `isEmpty` gate | `anIdentifiedTextFieldPublishesItsTextAsValue` |

## Carried

- Rule for `docs/rules/input-focus.md`: an `accessibilityIdentifier` on a plain container distributes to its descendants only when none of them publishes an identifier of its own; otherwise the
  container is a group carrying it and descendants keep theirs (`DA-A`, divergence 207); a control that fills its own node (`TextField`, `TextEditor`) uses `AXNode.fillControl` so a
  declaration never costs it its role or text (`DA-C`).
- DA-B asks MetalFlow for the failing expression; the outer-wrapper-outside-a-disabled-scope enabled flag is open.
- `List`'s `axNode.isEmpty` gate has the same shape as DA-C's cause; `SecureField` must expose no value if added.
