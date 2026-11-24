# 399: `Text.textSelection(_:)` (`TXS-A`..`TXS-I`)

Class `A` for the API, `D` for the behaviour, four divergences (1125-1128). Branch `feat/text-selection`, base master `595c474a`. Alloy's request: a plugin's stderr log (at most 64 KiB) is one `Text` in a disclosure and users must drag-select and copy it; `CodeView` read-only is too heavy. Decisions `docs/superpowers/2026-11-23-text-selectability-decisions.md`, design `docs/superpowers/specs/2026-11-23-text-selectability-design.md`, probe `docs/probes/swiftui-text-selection-enabled.swift` (macOS 27.2.1). Human checks: group TXS of `docs/verification/human-checks.md`.

**Numbering.** Open PRs hold records 396 (two) and 398 and master ends at 395, so this record is 399. If another line publishes 399 first, the later merge renumbers and says so in its header.

## Change

- **API** (`TextSelectability.swift`): `TextSelectability`, `EnabledTextSelectability`, `DisabledTextSelectability`, `.enabled`, `.disabled` and `ElementGroup.textSelection(_:)`, writing the **stored internal** `EnvironmentValues.textSelectionEnabled` (SwiftUI publishes no key). It is a field of the retained fingerprint and has its named difference row (`theRetainedFingerprintCarriesTheSelectionFlag`; the field-count guard counts 36).
- **Registration** (`SelectableText.swift`, `Text.prepaint`): with the flag on, `Text.prepaint` reads it in place (one load, no counted snapshot) and registers, inside the decoration's own scope, one opaque hitbox **under the `Text`'s own id** plus one `SelectableTextRegion(id, hitbox index, string)` in an array reserved from last frame's count. No closure, class box or geometry: an idle selectable `Text` allocates nothing. The `Text`'s string is read once by a selectable `Text` and exactly as before by every other.
- **Geometry** (`SelectableTextGeometry.make`): the lines of `styledTextLines` (the call paint and layout share), each line's boundary x from the text system's `caretOffsets`, one call per run the line crosses, offsets clamped to the line's width; UTF-16 to grapheme through a binary search over the string's boundary table (`SelectableTextIndex`, built once per session). `boundary(at:)`, `lineRange(at:)`, `rects(for:)`. Built **once per press**, at the first prepaint of the pressed `Text` (it has the environment and the frame's text system), then cached by (width, height).
- **Session** (`TextSelectionSession`, `Window.textSelectionSession`; never `StateTable`): a `TextEditState` over the string's graphemes. A press is recorded in the `Text`'s local space (the hitbox's `elementLocalPoint`) and applied at once when the geometry exists, else at that first prepaint; a drag applies at once. `TextEditing.press`/`drag` gained `characters:` overloads so the 64 KiB string is split once, not per pointer event. A double click takes a word, a triple click the visual line, a fourth click the paragraph (provisional, `HC-TXS-2`).
- **Window stage** (`Window.dispatchTextSelection`, right after the text-field stage): a primary press over a region **blurs a focused element**, starts or continues the session and claims the event, so the opaque selection hitbox wins over a tap or a link on the `Text` (`TXS-C`, provisional until `HC-TXS-4`; the skip-when-own-handlers rule is one function, `Frame.skipsRegistration(forHandlers:)`, returning `false`). The session ends on a focus move to an element (the `focusedElement` observer), on another selectable `Text` being pressed, and when the adopted frame did not produce its `Text` with its string (`settleTextSelection`; a string change is dropped in the `Text`'s own prepaint, the frame that shows it). It survives a press on empty space and the window losing key.
- **Commands**: the primary C and A as a fallback after the focus chain and `dispatchClipboardKey` decline (`dispatchTextSelectionKey`); copy writes the range of the **whole string** (a `lineLimit(1)` `Text` copies all of it, probe `T1`) and is declined when empty; `ClipboardCommands.selectAll` (new, the platform seam) is sent while the session exists and `.copy` while it has a range, so AppKit's Edit menu (`validateMenuItem`) and the drawn menu bar enable them. A right-click with no declared `.contextMenu` opens `[Copy, Select All]` (`openSelectionContextMenu`, from `dispatchContextMenu`); a declared one on the `Text` or an ancestor is found first and wins (divergence 1128).
- **Paint**: the selected `Text` fills one rect per selected line before its glyphs (`PaintPass.fillSelection`): the accent at 0.3 in a key window, `.separator` otherwise (unmeasured, `HC-TXS-6`). Every other `Text` pays one nil check.
- **Retained** (`SB-X`): `retainedSubtreeHasPointerPressOrFocus` is true for a subtree holding the selected `Text` (`Frame.textSelection`), so that occurrence paints in full every frame; **an occurrence holding any selectable `Text` leaves no prepaint ledger** (`prepaintLog.taint("textSelection")`), because the region array is not a journal channel and replaying the hitbox alone would orphan the region (a deviation from the design's "carried by the prepaint log", ruled `TXS-I` item 3). Its paint record still replays while nothing is selected. No `withState` write is made anywhere.
- **Accessibility**: `AccessibilityNode.textSelection: AccessibilityTextSelection?` (`range: Range<Int>?` in UTF-16), carried on the record (`AXEmission.textSelection`, like a table's), set in the `Text`'s own record only while a client collects. AppKit answers `accessibilitySelectedTextRange` (`{NSNotFound, 0}` with none), `accessibilitySelectedText` and `accessibilityNumberOfCharacters` on **every** selectable `Text`, read-only (divergence 1127). AccessKit publishes none (divergence 1125). Role stays `AXStaticText`. The node-field guards count 25.
- **Demo**: `METALUI_TEXT_SELECTION_DEMO=1 swift run MetalUIDemo` (`TextSelectionDemo.swift`): a 1 200-line log `Text` in a scroller, a field, a tapped selectable `Text` and a plain one.

## Measured and carried

The probe could not make SwiftUI's selectable `Text` select (its `NSTextInteraction` recognisers ignore a synthetic event), so drag, double and triple click, the right-click word, click-to-focus, click-to-clear, the selection colour and the cursor are the person's: eight checks, `TXS1`..`TXS8` (and `TXS9`, VoiceOver, Orca and Narrator). Every ruling resting on them is provisional and names the one place that reverses it.

Cost, the contract `TXS-H` (all pinned, no existing number moved):

| arm | what it pins |
|---|---|
| `aTextWithoutTextSelectionCostsWhatItCost` | a tree with no modifier: 20 rows = 40 requests, 41 prepaints, 60 paints, 1 build, 0 layout work, 0 hitboxes, 0 regions (the literals master draws for the tree); a flag-false twin equals it counter for counter except for the modifier's own layer |
| `anEnabledIdleTextCostsOneHitboxAndTheModifierLayer` | enabled against the flag-false twin, 10 and 100 rows: `FrameWork` equal, hitboxes exactly +rows, regions = rows |
| `anEnabledIdleTextAllocatesNothingPerRow` (Darwin) | the enabled-minus-disabled allocations of one steady frame: +2 at 10 rows and +2 at 100 (a constant; the hitbox and region arrays are reserved) |
| `aSelectedIdleTextFillsOnlyItsRects` | a settled selected frame: the same requests and builds as an unselected one, no layout work, one fill per selected line |
| `aDragBuildsNoSecondGeometry`, `aLogsGeometryCoversItAndMeasuresEachGraphemeOnce` | the geometry is built once per press and measures every grapheme once (counted `caretOffsets` work: 4 KiB and 16 KiB alike) |

The harness opens windows **with an accessibility client by default**, whose tree walks the hitbox list (one iteration allocation per hitbox in a debug build) and whose emission scan was the first cost found (`lastIndex(where:)` per `Text`, 4 allocations a row): the cost arms open their windows with `accessibilityClientActive: false` and the mark tests the newest emission in place. A three-way `switch` in a row Component nests its arms one identity deeper each, 2 allocations a row of the fixture's own (found by diffing the allocation stacks of the two twins, not by reading); the twins are an `if`/`else`. A 64 KiB log was measured once: opening the window at all costs 57 s in the portable debug harness before this feature (the `Text` is typeset once at layout), and the press adds one styled measurement, 28 s there (the same shaping again, not cached under the styled call); CoreText in a release build is two orders faster. The press is the only O(string) step, and the portable typesetter is itself superlinear (4 KiB 0.06 s, 16 KiB 0.9 s), which is not this feature's.

## Tests

`TextSelectionTests` (portable harness, `Modifiers.primary`, `runUntilIdle()` then `tick()`, summed `frameWork`; the allocation arm is `#if canImport(Darwin)`), `aSelectableTextAnswersItsRangeAndRefusesToSetIt` and the `textSelection` arm of `everyAccessibilityNodeFieldHasAnAppKitArm` (AppKit), the `textSelection` arm of `everyAccessibilityNodeFieldHasAnAccessKitArm` (asserts the documented absence), the fingerprint-field and frame-channel guards (`selectableTextRegions: prepaintOnly`, `textSelection: keyed`). The mutation round ran from a committed tree with one build and an environment-selected mutation per run (instrumentation removed after, `git diff` of `Sources` empty apart from the commits): every row below reddened the named tests, restored.

| mutation | red tests |
|---|---|
| `textSelection(_:)` writes `true` whatever `allowsSelection` says | `textSelectionIsInheritedAndTheNearestWriterWins`, `aTextWithoutTextSelectionCostsWhatItCost`, `anEnabledIdleTextCostsOneHitboxAndTheModifierLayer` |
| `boundary(at:)` ignores `y` | `aPressLandsOnTheNearestBoundaryOfTheLineUnderIt`, `aDragBuildsNoSecondGeometry` |
| `originX` dropped from `boundary(at:)` and `rects(for:)` | `anAlignedLineKeepsItsOffset` |
| every run measured in the first run's font | `aStyledTextMeasuresEachRunInItsOwnFace` (**survived round 1**: the test's bold run is the regular face in the one-font harness; the arm now has a 26 pt run) |
| `offsets(of:)` measures `index.string(0..<end)` for each line | `aLogsGeometryCoversItAndMeasuresEachGraphemeOnce` |
| `enqueue` clears the geometry | `aDragBuildsNoSecondGeometry` (**survived round 1**: a rebuilt geometry has the same lines; `geometryBuilds` now counts) |
| `Text.prepaint`'s flag read `true` whatever the environment says | `aTextWithoutTextSelectionCostsWhatItCost`, `anEnabledIdleTextCostsOneHitboxAndTheModifierLayer`, `textSelectionIsInheritedAndTheNearestWriterWins`, `theSelectedTextPublishesItsRange`, and two field-selection tests that press a `Text` |
| a second hitbox per selectable `Text` | `anEnabledIdleTextCostsOneHitboxAndTheModifierLayer` and 17 behaviour arms (the pointer lands on the second one) |
| a derived `GlobalElementID` per selectable `Text` | `anEnabledIdleTextAllocatesNothingPerRow` |
| the `registersPointerHitboxes` gate dropped; the `isEnabled` gate dropped | `aSelectableTextBehindAGateRegistersNoRegion` (each) |
| copy writes the whole string | `dragSelectsAndPrimaryCCopies` |
| a press delivered with `clickCount: 1` | `doubleClickSelectsAWord`, `aSelectedIdleTextFillsOnlyItsRects` |
| a triple click taken as select-all (threshold 99) | `doubleClickSelectsAWord`, `aSelectedIdleTextFillsOnlyItsRects` (**survived** with a one-line `Text`, whose line is its whole text: the arm wraps) |
| the primary A claimed with no session | `selectAllSelectsOnlyThatText`, `tabbingIntoAFieldPublishesItsSelectAll` (**the first spelling, in the key function, was unreachable**: the call site guards on the session; moved to the call site) |
| `selectAll` one grapheme short | seven behaviour arms |
| the `focusedElement` observer does not drop the session | `focusLeavingTheTextDropsTheSelection` |
| `settleTextSelection` does nothing | `aStringChangeDropsTheSelection`, `focusLeavingTheTextDropsTheSelection` |
| a press off every region drops the session | `aPressOnEmptySpaceKeepsTheSelection` |
| the press does not blur a focused field | `aPressOnTheTextBlursAFocusedField` |
| the session kept across a changed string | `aStringChangeDropsTheSelection` |
| the stage declines a press | 18 arms, among them `aSelectableTextWithATapSelectsAndDoesNotFireIt` |
| a drag that leaves the region is dropped | `aDragPastTheTextSelectsToItsEnd` |
| copy limited to the characters the kept line shows | `aTruncatedTextCopiesItsWholeString` |
| `.copy` added whatever the range | `editCopyIsEnabledWhileSelected` |
| the selection menu opened before a declared one is looked for | `aDeclaredContextMenuWinsOverTheCopyMenu` |
| `rects(for:)` fills every line whatever the range | `aSelectedIdleTextFillsOnlyItsRects`, `anAlignedLineKeepsItsOffset` |
| `retainedSubtreeHasPointerPressOrFocus` ignores the session | `aRetainedSubtreeRepaintsTheHighlight` (**survived round 1**: the pointer was still on the card, which the hover rule already refuses; the arm moves it off) |
| the accessibility mark only on the selected `Text` | `theSelectedTextPublishesItsRange`, `theTextAreaStateIsRecordedOnlyForAClient` |
| `retainedFingerprint` carries `false` for the flag | `theRetainedFingerprintCarriesTheSelectionFlag` (**survived round 1**: no test read the extraction; added) |
| the fingerprint's difference row dropped | `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` |
| AppKit: `{0, 0}` for no range; the length answered for a plain node; the setter allowed; the selected text always `""` | `aSelectableTextAnswersItsRangeAndRefusesToSetIt` (each; the last also `everyAccessibilityNodeFieldHasAnAppKitArm`) |
| AccessKit: a node with a selection published with another value | `everyAccessibilityNodeFieldHasAnAccessKitArm` |

Not mutated, observed red when the guard met the new property: `everyFrameChannelIsClassified` (the two `Frame` stores) and the node-field counts of both parity tests (24 to 25) failed until their rows and arms were added. **A mutation no test can see**: marking the accessibility record without testing `collectsAccessibility` leaves a quiet window identical (there is no record to patch); the gate is `registerHandlers`', and `theTextAreaStateIsRecordedOnlyForAClient` says so.

## Verified

`swift build --build-system native --build-tests && swift test --build-system native --no-parallel`: **7270 tests in 79 suites, green** (7242 at base: +27 `TextSelectionTests`, +1 `aSelectableTextAnswersItsRangeAndRefusesToSetIt`; the two node-field parity tests and the fingerprint-field guard gained an arm or a count, none loosened). No existing cost test, allocation ceiling or count moved. `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. `Backends/SDL` (`swift test` with `fetch-accesskit.py`'s flags): builds; the 28 `AccessKit` tests pass, the new arm among them; the full run is ended by the main-run-loop guard after 309 passes and no failure in this sandbox, `windowServerTrafficNeverStopsTheMainRunLoop` and three shader-library tests that cannot write the toolchain's `pm` directory fail here as on master. The demo builds and opens (`METALUI_TEXT_SELECTION_DEMO=1`, twelve seconds without a crash); `everyProductionTreeBuildsOnAOneMegabyteThread`'s list (`DemoStackBudgetTests`) gained `buildTheTextSelectionDemo`.

## Carried

`HC-TXS-1`..`8` (and 9); the triple-click and fourth-click units; whether a real click fires a tap or a link on a selectable `Text` (one function); the inactive colour; the right-click word; the cursor; `Text` in a `Markdown` view (`ProposalText`, out of scope, the same helper); an AccessKit text-run tree for a selectable `Text` (1125).
