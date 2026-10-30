# Segmented picker accessibility - decisions

Rulings for the per-segment accessibility elements of `Picker` (MetalFlow clicks a segment by identifier). Prefix `SE-`. Branch `feat/mf-segments`. Code: `Sources/MetalUI/Picker.swift`
(`PickerScope.identifier`, `TaggedElement.makeChrome`), `Sources/MetalUI/AXNode.swift` (`AXDeclarations.derivedIdentifier`), `Sources/MetalUI/AccessibilityTreeBuilder.swift`; tests:
`Tests/MetalUITestingTests/SegmentAccessibilityTests.swift` (plain imports). **Next unused: `SE-C`.** No divergence label was taken (SE-B).

## SE-A - segments were already elements; the gap was the identifier

**Ruling.** On the base, a segmented (and radio-group) `Picker` already published a `.radioGroup` node (the picker's label, its own identifier) with one `.radioButton` child per option: label from
the content's text, value `"1"`/`"0"`, `.selected` on the chosen one, a `press` action (the option's `onClick`, which writes the tag from input), the option chrome's rect as frame
(`DD-U`, test 1.17). That already matches AppKit (radio-button children). What was missing was an identifier: the content's `.accessibilityIdentifier` was folded away with the content, and the picker's
identifier reached the group only. Now an option publishes, in order: (1) the first identifier declared inside its content (put it on the content before `.tag`, e.g.
`Text("A").accessibilityIdentifier("a").tag(x)`; the fold is in `combine`, for the `.radioButton` role only, so `Button` and `Toggle` are unchanged); (2) `"<picker identifier>.<tag>"` where the
picker identifier is the one declared directly on the `Picker` and the tag is `String(describing: tag.base)` (an enum case is its name; `"mode.beta"`), carried as the internal
`AXDeclarations.derivedIdentifier` so it is a fallback an explicit identifier or a distributing ancestor beats; (3) none. Role: the existing `.radioButton` (not a new role). No public API
(the derivation is documented on `Picker`'s doc comment), so no inventory row.
**Pins.** `eachSegmentIsARadioButtonElementUnderTheGroup`, `aSegmentTakesTheIdentifierItsContentDeclared`, `aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag`,
`aPickerWithoutAnIdentifierDerivesNone`, `clickingASegmentFoundByIdentifierSelectsIt` (a `MetalUITesting` `element(identifier:)` then `click`), `pressingASegmentElementSelectsIt`.
**Cost if wrong.** An identifier string tests depend on. No new handler-registering site (the option's existing `onClick` and `axNode`), so no D2 arm.

## SE-B - no divergence

**Ruling.** AppKit exposes segments as radio-button children and so do we, so nothing differs; the derived `<picker>.<tag>` identifier is an addition (SwiftUI derives none), not a difference in
an existing behaviour. The content-identifier fold on a radio button is unprobed against SwiftUI. Label 207 is unused; the header count is untouched.

## Mutations

Each applied to the declaration named, one at a time, against the six tests above (the radio-group arguments run both styles).

| # | Mutation | Reddened |
|---|---|---|
| SE-M1 | option `axNode` role `.radioButton` -> `.generic` | `eachSegmentIsARadioButtonElementUnderTheGroup`, `aSegmentTakesTheIdentifierItsContentDeclared`, `aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag`, `aPickerWithoutAnIdentifierDerivesNone`, `clickingASegmentFoundByIdentifierSelectsIt` |
| SE-M2 | drop the radio-button fold of the content's identifier | `aSegmentTakesTheIdentifierItsContentDeclared`, `aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag`, `clickingASegmentFoundByIdentifierSelectsIt` |
| SE-M3 | never set `derivedIdentifier` | `aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag`, `clickingASegmentFoundByIdentifierSelectsIt`, `pressingASegmentElementSelectsIt` |
| SE-M4 | derived identifier wins over the content's | `aSegmentTakesTheIdentifierItsContentDeclared`, `aSegmentWithoutAnIdentifierDerivesOneFromThePickersAndItsTag`, `clickingASegmentFoundByIdentifierSelectsIt` |
| SE-M5 | option `onClick` writes nothing | `clickingASegmentFoundByIdentifierSelectsIt`, `pressingASegmentElementSelectsIt` |
| SE-M7 | option `value` always `"0"` | `eachSegmentIsARadioButtonElementUnderTheGroup` |

Not mutated: the frame (the existing `aSegmentedPickerMakesEverySegmentAsWideAsTheWidest` pins the rect arithmetic; the new test pins only distinct, ordered, non-empty rects).

## Carried

- `.accessibilityIdentifier` after `.tag(_:)` does not compile (`TaggedElement` is not a `StyledElement`); the identifier goes on the content first. SwiftUI accepts either order.
- The derivation reads the identifier declared directly on the `Picker`; one set by a wrapper around it (`.padding().accessibilityIdentifier(...)`) is not seen.
- Menu-style pickers record options without nodes (`SV-P`); no per-option element or identifier.
- A human VoiceOver run of `voiceover-script.md` C10a.
- `docs/rules/` and `CLAUDE.md` untouched (orchestrator); the rule to add: "a `Picker` option's identifier is the content's, else `<picker id>.<tag>`; the fold is `.radioButton` only".
