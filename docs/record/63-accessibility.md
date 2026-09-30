# 63 — Accessibility (plan task 12, part 2)

Branch `feat/accessibility-bridge` from `31d3565` (master, plan task 12 part 1
landed, record §62). Spec `docs/superpowers/specs/2026-09-29-accessibility-design.md`;
rulings `IX-U`…`IX-AE` appended to part 1's decisions doc,
`docs/superpowers/2026-09-29-interaction-decisions.md`, amended by the critic
round's `IX-AF` (next unused `IX-AG`).
Probes: `docs/probes/swiftui-accessibility-part2.swift` (new) and
`docs/probes/swiftui-controls-and-selection.swift` (re-run, compiled).

**Status: DESIGNED, critic round applied (`IX-AF`); lane 1 landed (`IX-AG`);
lane 2 landed (`IX-AH`, fix round `IX-AI`); lane 3 landed (`IX-AJ`); Record
phase close applied (§6 below) — LANDED, the accessibility half of plan
task 12.** Task 12's box stays **unticked**: `docs/verification/voiceover-script.md`
is written, not run. **An agent cannot run VoiceOver or claim the
validation** (`IX-AE`); the box is ticked only after a human runs every step
and the Record phase re-reads the file.

## §1 Design (2026-09-29)

**Baseline re-taken at `31d3565`** in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1837 tests in 3 suites passed after 113.321 seconds`, the
`FR-J no-argument frame: succeeded=true` line present. 113 guards, 0 goldens,
69 live divergences, next label 95. AccessKit 0.23.0 fetched
(`Backends/SDL/scripts/fetch-accesskit.py`, checksum matched) to read
`accesskit.h`.

**Probe.** `swiftui-accessibility-part2.swift` (new; groups `C` controls, `E`
children behaviour, `H` hidden, `T` traits, `M` modal, `N` hint/identifier,
`A` actions, `B` buttons, `G` gestures, `X` truncation, `F` focus, `L` list,
`I` images, `P` proposal containers): run twice with `/usr/bin/swift`,
filtered stdout byte-identical (308 lines), exit 0, filtered stderr empty,
screen **locked** (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`).
Every read is in-process (KVC on `NSHostingView`'s tree after
`AXEnhancedUserInterface`), so the lock blinds nothing but `F4`, recorded as
non-separating. Positive controls C0 (arm 11's `label=vol value=5`), C1 (two
static texts), C2 (AppKit's own `NSButton` publishes no key-equivalent
attribute) all read as expected. Three instrument fixes before the recorded
run, none changing an arm: `L1`'s rows are AppKit `NSOutlineRow`s, not
KVC-compliant for the accessibility keys, so `kv` guards on `responds(to:)`
and rows read through the informal attribute API; `F2`'s two `@FocusState`
writes arrived in either order across runs, so they print sorted; `E14` and
`T3p` were added after the first reading (the `.combine` custom-action rule
and whether removing `.isButton` keeps the press).

`swiftui-controls-and-selection.swift` re-run the same session: the
`/usr/bin/swift` JIT form fails to link on macOS 27 (`Symbols not found:
___isPlatformVersionAtLeast`); compiled with `xcrun swiftc -o` it runs, exit
0, and its LA0–LB3 lines are byte-identical to its header.

**The audit** (spec §2, `IX-U`): 44 rows — part 1's rows 27–37 split where one
row named several concepts, plus the brief's own items and every carried
accessibility item. Built: `accessibilityElement(children:)`,
`accessibilityHidden`, hint, identifier, eight traits, modal isolation,
declared and named actions, settable selection on AppKit, the proposal path's
emission, a labelled `Image`, both bridges' new fields. Pinned as SwiftUI's:
gestures publish no press, button role/shortcut/style publish nothing,
truncated text publishes its whole string, focus/`@FocusState` interplay.
Divergences: 28 and 83 retire, 95 added, 27/32/33 amended, 82 kept for the
human run; live 69 → 68, next label 96 (expected, spec §10).

**Lanes** (spec §7, `IX-AE`): 1 the neutral tree and both bridges; 2 every
`Sources/MetalUI` file (modifiers, builder, proposal path, dispatch, `List`
selection); 3 the audit tests, the demo modal's two accessibility modifiers
and the VoiceOver script. Disjoint files, one declared stub arm. Expected
close 1878 tests, 116 guards, `Backends/SDL` 22 + 32 (1880 after §2).

**Demo** (spec §8, `IX-X` item 4): 0 px expected in all fourteen offscreen
images; the modal panel's new declaration adds one `$ax` slot while the modal
is up (named).

**Lock probe at design time**: locked, so the real-window capture is owed, as
at every task since stage 6b.

## §2 Critic round (2026-09-29)

One agent, critic and reviser. **Probe re-run** with its header's command:
308 filtered lines, byte-identical to the recorded output (E14, M5, B6, A4,
T3p diffed arm by arm), screen locked. **Seven amendments** (`IX-AF`): lane 2's
five modifier-free dispatch tests (settable selection, the press under
`allowsHitTesting(false)`) moved to lane 1 as 1.10–1.14, lanes now sequential
over shared files; `AXNode.actions`' deprecation mechanics (no default on the
deprecated `actions:`); a declared action counts outside the
`synthesizesAccessibility` gate, and every new declaration writes a `$ax` slot
like a label; `ProposalText`'s record handled as possible T rows, the preview's
tree pinned (3.11) and scripted; overload resolution and the wrapper's
one-node precondition pinned, gestures on both spellings; a new `AB-AE` exit
test for the new overrides (1.9); the script's markers widened to every
spoken fact, `ax-absent` for the modal, unpinned VoiceOver behaviour labelled.
**Two rejections** recorded in `IX-AF`. Expected close **1880 tests, 116
guards, `Backends/SDL` 22 + 32**. Task 12's box stays unticked (`IX-AE`).

## §3 Lane 1 — the neutral tree, both bridges, the two modifier-free requests (2026-09-29)

Commits: red `9da8d45`, green `dcd6339`; ruling `IX-AG` (plus a follow-up
`IX-AG` commit recording the noble-container figure, `6c961e3`).

**Files.** `Sources/MetalUIPlatform/AccessibilityTree.swift` (the neutral
roles, fields, request cases), `Sources/MetalUIAppKit/AppKitAccessibility.swift`,
`Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift`,
`Backends/SDL/Sources/MetalUISDL/AccessKitAdapter.swift`, and — moved here
from lane 2 by the critic round (`IX-AF` item 1) — `Sources/MetalUI/List.swift`
(`AccessibilityRowSelection`, `isSelectable`), `Sources/MetalUI/Frame.swift`
(`registerHandlers`'s press-only record), `AccessibilityTreeBuilder.swift`,
`Window.swift`/`WindowAccessibility.swift` (the press-only arm, `.select`/
`.selectRows`, a stub `.customAction` arm lane 2 replaces). Tests: new
`Tests/MetalUIPlatformTests/AppKitAccessibilityPart2Tests.swift`, new
`Backends/SDL/Tests/MetalUISDLTests/AccessKitPart2Tests.swift`, new
`Tests/MetalUITests/AccessibilitySelectionAndPressTests.swift`; two existing
tests renamed with their answer flipped by ruling
(`aPressIsRefusedWhereHitTestingIsDisabled` →
`aPressIsRunWhereHitTestingIsDisabled`, `IX-Z`;
`anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly` →
`settingAXSelectedOnARowReplacesTheSelection`, `IX-AA`); one T row
(`aMetalUITreeTranslatesToAccessKitsVocabulary`'s literals gain `rowCount`/
`rowIndex`; the AppKit role table's `.table` → `.outline` literal).

**Eight clauses decided here, each MetalUI's choice unless a probe arm is
named** (`IX-AG`): the parity tables found two fields with no arm — AccessKit
never translated `rowCount`/`rowIndex` (now `set_row_count`/`set_row_index`),
and AppKit never read `isFocusable` for `setAccessibilityFocused(_:)` (now it
does, gating `AXFocused` exactly where `Window` would honour `.focus`); a row
answers subrole `AXOutlineRow`, `.heading` is spelled by raw string (the SDK
constant is macOS 26 API, the package targets 14); a custom action's handler
is a `nonisolated static` closure holding its element weakly, so an off-main
call answers `false` rather than trapping (1.9); `isSelectable` is derived by
the builder from a published parent's registered
`AccessibilityRowSelection` handler, not declared; `(false)` sends nothing,
an unpublished row/non-table is refused, an empty `.selectRows` is
unprobed, a single list ignoring two rows still answers `true`, and an
accessibility selection asks for no focus; the press-only record
(`Frame.accessibilityPressOnly`) skips a suppressed subtree and keeps the
last registration per id, tried by `Window` after the last `onClick` hitbox;
`.customAction` is refused by a lane-1 stub, exactly as an unknown id is
today; and two pre-existing test defects were found and fixed at green (1.4's
`rowCount` arm asserted the wrong literal; 1.13/1.14 discarded their
`Window`s, so their assertions ran against nothing — every window is now
kept alive with `withExtendedLifetime`).

**Red first** (`9da8d45`, full unfiltered suite): `Test run with 1845 tests
in 3 suites failed … with 41 issues` — exactly the ten lane-1 tests, each at
the field/role/request it exercises. SDL: `31 tests … failed with 22 issues`
— 1.5–1.8 and the translation T row.

**Green** (`dcd6339`, after `swift package clean` — three public types
changed shape): `swift build --build-system native --build-tests` 0
`error:`, the one SwiftPM deprecation `warning:`; unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1845 tests in 3
suites passed after 112.771 seconds`**, `FR-J` present; guards **113**
unmoved. `Backends/SDL` (AccessKit fetched fresh into this worktree):
**22 + 31**. `MetalUILayout` imports `MetalUICore` alone. A `swift:6.4-noble`
container builds with 0 `error:`/`warning:` and runs **199 + 10 + 22**. **0 px
against `31d3565` in all fourteen offscreen images**, scene identical.

**Mutations** (each restored from a copy, the whole suite run unfiltered,
`git status --short` clean after each; every reddened test named): sixteen
named in `IX-AG` — M1a/M1a′ (hint mapped wrong / `.table` reverted) redden
`theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline`,
`everyAccessibilityNodeFieldHasAnAppKitArm`,
`theNewAppKitOverridesAnswerNothingOffTheMainThread` and the role-table T
row; M1b (handlers numbered from 1) reddens the custom-action test; M1c (any
row's setter allowed) reddens 1.3; M1d (identifier answer dropped) reddens
three tests; M1i (a bare `assumeIsolated`) traps 1.9's child; M1j/M1j′/M1k
(the press-only record removed / recorded without a client / not consulted)
redden 1.10/1.11; M1l/M1m/M1n (a multi-select adds instead of replaces, a
single list keeps two, the disabled gate skipped) redden 1.12–1.14; M1e–M1h
(SDL: description/selected-false/custom-index/custom-actions each dropped)
redden the four SDL tests. `noConformerEmitsAnAXNodeItDidNotDeclare` stayed
green under every one.

**Counts**: root **1837 → 1845** (+8: 1.1–1.4, 1.9, 1.10, 1.13, 1.14; 1.11/
1.12 renamed; the role table a T row), guards **113** unmoved, SDL **22 + 27
→ 22 + 31**. No test removed; `goldensUnchanged`: every retained test's
answer unchanged but the two renames and the two T rows, each a ruling.

**The verifier round's eight further mutations** (this Record phase's own
lane-1 verdict), each restored from a copy, run against the branch's own tip
(after lane 3 landed): V1 (AXSelected write dropped) reddens the two
selection tests and 1.9; V2 (`isAccessibilitySelectorAllowed` for
`setAccessibilityFocused` answers `nil`, restoring the pre-`IX-AG` default)
reddens `everyAccessibilityNodeFieldHasAnAppKitArm`; V3 (the builder's
`pressable.formUnion(pressOnly.keys)` removed) reddens the two press-only
tests; V8 (the `enabled` clause dropped from the press-only condition)
reddens the same; V18 (`Window`'s `.select` refused) reddens the disabled-list
and the selection-replaces tests; V19 (`isSelectable` always false) reddens
the same two. **Three ran green, each a finding, not a false pin** (below):
V4 (a client's AX selection's lead/anchor write dropped), V7 (the press-only
record's suppression clause dropped) and V9 (first registration per id wins
instead of last) reddened nothing — each is a clause `IX-AG` states in prose
with no test naming it (§9).

## §4 Lane 2 — the modifiers, the builder, the proposal path, dispatch (2026-09-29)

Commits: red `2b2de97`, green `c179ad4`, a 2.14 arm `99a32bc`; fix round red
`cbf69af`/`8b96cf6`; rulings `IX-AH` (the landing) and `IX-AI` (the fix
round).

**New public API** (spec §4): `AccessibilityChildBehavior` (closed:
`.ignore`/`.combine`/`.contain`), `AccessibilityTraits` (closed OptionSet:
`isButton`/`isHeader`/`isSelected`/`isLink`/`isImage`/`isStaticText`/
`isModal`/`updatesFrequently`), on `StyledElement` and, new, on
`ProposalElementGroup` (through `AccessibilityModifier<Content>`, one
identity level, `GestureModifier`'s shape): `accessibilityElement(children:)`,
`accessibilityHidden(_:)`, `accessibilityHint(_:)`, `accessibilityIdentifier(_:)`,
`accessibilityAddTraits(_:)`/`accessibilityRemoveTraits(_:)`,
`accessibilityAction(_:)`/`accessibilityAction(named:_:)`; three modifiers
that existed only on `StyledElement` now also on `ProposalElementGroup`
(`accessibilityLabel`/`accessibilityValue`/`accessibilityAdjustableAction`);
`Image(_:scale:label:)` (SwiftUI's labelled init). `AXNode.actions`/
`AXActionKind` are **deprecated** toward the new actions (no in-repo caller,
0-`warning:` baseline held).

**Files.** `AccessibilityModifiers.swift`, new `ProposalAccessibility.swift`,
new `AccessibilityTraits.swift`, `AXNode.swift`, `AXEmission.swift`,
`AccessibilityTreeBuilder.swift` (the collect/isolate/actions/distribute/
ignore/combine/contain/emit pipeline, §5), `Frame.swift`
(`recordAccessibility`, the declared-action term outside
`synthesizesAccessibility`), `DecorationScope.swift`, `ProposalText.swift`,
`Image.swift`, `WindowAccessibility.swift`, `Window.swift`. Tests: new
`AccessibilityModifierTests.swift`, `ProposalAccessibilityTests.swift`,
`AccessibilityRequestTests.swift`, `AccessibilityCompileGuards.swift` (three
guards, all whole-file `typecheckFile`).

**Eight clauses decided here** (`IX-AH`): a declared action is a declaration,
not a synthesis — it records outside `synthesizesAccessibility`'s gate, so
`HStack{}.accessibilityAction {}` and a declared action over a tap both
publish (2.14 gains the arm that pins the term, since neither
`OnTapModifier`/`GestureModifier` alone reaches it); a chain of proposal
accessibility modifiers is **one** wrapper (later-written field wins, as on a
`StyledElement`); a decorative `Image` under the wrapper still publishes
nothing; adding a trait removes it from the removed set and vice versa,
`accessibilityHidden(false)` undoes an earlier `(true)` on the same element
but an inner `(false)` cannot un-hide; named actions chain by name,
later-written first; a combined node redirects its press (and an adjustment)
to its first interactive descendant, bounded at four hops; modal isolation
picks the greatest `(layer, record position)` among `.isModal` records, and
every request id is refused when the last published tree was isolated and
does not contain it (**divergence 95, added**); no existing test's answer
moved when `ProposalText` started recording (a grep-and-run check, no T row).

**Red first** (`2b2de97`, full unfiltered suite): `Test run with 1870 tests
in 3 suites failed … with 64 issues` — the 22 lane-2 tests and G2.2, each at
its first failing assertion.

**Green** (`99a32bc`): `swift build --build-system native --build-tests` 0
`error:`, the one SwiftPM deprecation `warning:` (the deprecated
`AXNode.actions`/`AXActionKind` and the synthesized `==` build silently);
unfiltered `swift test --build-system native --no-parallel` → **`Test run
with 1870 tests in 3 suites passed after 115.640 seconds`**, `FR-J` present;
guards **113 → 116**. **0 px against `31d3565` in all fourteen offscreen
images**, scene identical; `Backends/SDL` untouched (no file under
`Backends/` or `Sources/MetalUIPlatform` changed by this lane).

**Cost**: `MemoryLayout<AXNode>.size` 113 → 121, `MemoryLayout<Handlers>.size`
440 → 448 (one pointer each, as designed); smallest thread building every
production tree 608 → **624 KB**, unmoved from part 1's own figure —
`everyProductionTreeBuildsOnAOneMegabyteThread` green.

**Fix round** (`IX-AI`): the verifier found nothing pinned which interactive
child a `.combine` node takes its role, actions and value from when its
children are of **different kinds** — every landing fixture combined one
interactive child or two of one kind. Probe revision 2 (arms E15–E21, E18p,
340 filtered lines, the first 308 byte-identical) refutes the design's "the
first one's role and press, and its value" for mixed kinds and gives
SwiftUI's own answer: the role is the highest-ranked child's (slider >
checkbox > button > text field, tie to the first); the value is the
**last** valued child's; the lead — which supplies label, press and custom
actions — is the first child that **presses**, else the first that is not
adjustable, else the first; only a pressing child is a custom action; an
adjustable child's increment/decrement are added and an adjustment runs the
first redirect that takes one. On children of one kind every clause reduces
to the old rule (E6/E7/E14 unchanged). Fixed in `AccessibilityTreeBuilder.combineElements`
and `Window.adjust`.

**Mutations** (each on a commit, restored from a copy, the whole suite
unfiltered — 1870 — `git status --short` clean after each):

| id | mutation | reddened |
|---|---|---|
| G2.1 | `StyledElement.accessibilityHint` made internal | `theAccessibilityModifiersCompileFromAPlainImport` |
| G2.2 | `AXNode.actions`'s `@available(deprecated)` dropped | `anAXNodesActionsAreDeprecatedTowardAccessibilityAction` |
| G2.3 | `static let isToggle` added to `AccessibilityTraits` | `anUnofferedTraitOrActionKindDoesNotCompile` |
| M2n′ | the declared-action term back inside `synthesizesAccessibility &&` | `aGestureOrTapPublishesNoPressAndAnAccessibilityActionAddsOne` |
| M2t | the hitbox tried before the declared action in `Window`'s press | `anAccessibilityPressRunsADeclaredActionInsteadOfTheClick` |
| M2x | the isolation refusal removed | `aRequestForAnElementOutsideTheModalIsRefused` |
| M2c (lead → `pressing.last`) | `.combine`'s lead a wrong child | `aCombinedElementTakesTheFirstInteractiveChildsRoleAndListsEveryOneAsACustomAction`, `aCombinedElementsPressAndCustomActionsRunItsInteractiveChildren` |
| M2c-rank/-value/-adjust/-custom | ranking, value, adjustability, custom-action selection each wrong | `aCombinedElementTakesTheFirstInteractiveChildsRoleAndListsEveryOneAsACustomAction` |
| M2c-dispatch | `Window.adjust` runs redirect 0 unconditionally | `aCombinedElementsPressAndCustomActionsRunItsInteractiveChildren` |
| M2n on `GestureModifier` | flipped `synthesizesAccessibility: true` | **none — equivalent**, `IX-AI` item 5 |

The verifier's own scoped run of the rest of the landing's mutation column
(M2a–M2m, M2o–M2s, M2u–M2w) each reddened the test spec §7 names for it,
confirming every clause `IX-AH` left as "shown red against the stub, not a
scoped mutation".

**Counts**: root **1845 → 1870** (+25: 22 tests + 3 guards), guards **113 →
116**, SDL unmoved (**22 + 31**). No test removed or renamed;
`goldensUnchanged`: no retained test changed its answer — 2.3/2.14/2.22 are
this lane's own, unmerged when the fix round extended them.

## §5 Lane 3 — the audit's pins, the demo's modal, the VoiceOver script (2026-09-29)

Commits: red `d90bfc3`, green `d34605a`, a 3.11 fix `b96472f`; ruling `IX-AJ`.

**Files.** `Sources/MetalUIDemoContent/DemoContent.swift` — **accessibility
modifiers only**: the modal scrim gains `.accessibilityAddTraits(.isModal)`,
the panel `.accessibilityRemoveTraits(.isButton)`; new
`docs/verification/voiceover-script.md`; new
`Tests/MetalUITests/AccessibilityAuditTests.swift`; new
`Backends/SDL/Tests/MetalUISDLTests/AccessKitControlsParityTests.swift`. No
lane-1 or lane-2 file was found wrong (the "stop on a finding" rule, part 1's
`IX-S` precedent, was not triggered).

**Six clauses left open by the design, each MetalUI's choice unless a probe
arm is named** (`IX-AJ`): a press on a `Button` requests no focus, a press on
a `List` row focuses its list (3.9, amending its own spec row — `DD-AE` item
2's "the press keeps `runClick`'s focus request" is a request a handler
*makes*, and a row's click does, a button's does not); 3.7's AccessKit tree
is **transcribed** from 3.9's table, not rendered — the SDL test target has
no `MetalUI`/`MetalUIDemoContent` dependency; the script's trees are built at
the demo's own 920 × 560 window (the demo's `List` realizes 5 rows there, the
controls' list 7 — not the design draft's 18, a 1024-square assumption); 3.11
reads an unpublished window's tree as `.empty` (`WindowAccessibility.lastPublished`'s
own starting value), so M3k's mutation reddens only the preview arm, not
"the preview arm but not the text-input arm" as the spec's column had it;
the preview's whole tree is its two proposal texts (its grid publishes
nothing, `IX-Y` 3); the text-input demo binds no `@FocusState`, so the
script's focus section checks a `.focus` request instead and marks the
`@FocusState` step N/A.

**Red before** (`d90bfc3`, full unfiltered suite): `Test run with 1880 tests
in 3 suites failed after 115.479 seconds with 2 issues` — 3.8 (the modal
published all seven roots, no isolation yet) and 3.10 (no script existed).
3.1–3.6, 3.9, 3.11 and SDL 3.7 were written first and green (pinning today's
answer), each reddened only by its own mutation below.

**Green** (`b96472f`): `swift build --build-system native --build-tests` 0
`error:`, the one SwiftPM deprecation `warning:`; unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1880 tests in 3
suites passed`**, `FR-J` present; guards **116** unmoved. `Backends/SDL`
**22 + 32**. A `swift:6.4-noble` container builds with 0 `error:`/`warning:`
and runs **199 + 10 + 22**, unmoved. **0 px against `31d3565` in all
fourteen offscreen images**, scene identical (including `prod default vs
modal` non-zero, unmoved); `Expected.swift` unedited;
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green. The real-window
capture was **not taken** by this lane: the lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`.

**Mutations** (each on the working tree, restored, the whole suite
unfiltered — 1880; SDL its own suite — `git status --short` empty after
each):

| id | mutation | reddened |
|---|---|---|
| M3a | `Button.keyboardShortcut(_:)` publishes a hint | `aButtonsRoleShortcutAndStylePublishOnlyItsLabel` |
| M3b | `Text.prepaint` passes the truncated string | `aTruncatedTextPublishesItsWholeString` |
| M3c | `reconcileFocusStates` skipped once after an AX focus request | `anAccessibilityFocusRequestWritesAFocusStateBinding` |
| M3d′ | AppKit's `focusedElement()` answers `nil` | `aFocusStateWriteIsTheTreesFocusedElement`, `focusIsReportedFromTheTreeAndAFocusRequestIsSent` |
| M3e | `IX-I`'s focus reset removed | six focus-identity tests (§4's list) |
| M3f | `Toggle`'s value `"1"` → `"true"` | five tests including the combine test |
| M3g (SDL) | `.incrementor` mapped to `.button` | two AccessKit control-parity tests |
| M3h | the demo's `.isModal` removed | `theDemoPublishesTheTreeTheVoiceOverScriptReads`, `theVoiceOverScriptQuotesThePublishedTree` |
| M3i | the controls demo's list built without `selection:` | three tests |
| M3j / M3j′ | a script label changed / an absent-but-published `ax-absent` marker added | `theVoiceOverScriptQuotesThePublishedTree` |
| M3k | `ProposalText.prepaint` records nothing | nine tests, the preview arm of 3.11 only |

**Counts**: root **1870 → 1880** (+10: 3.1–3.6, 3.8–3.11), guards **116**
unmoved, SDL **22 + 31 → 22 + 32** (+1, 3.7) — the design's expected close,
exactly. No test removed or renamed; `goldensUnchanged`: no retained test
changed its answer.

**The verifier round's eight further mutations** (this Record phase's own
lane-3 verdict), on top of `IX-AJ`'s own table: V1 (the panel's
`.accessibilityRemoveTraits(.isButton)` removed, a claim the landing's own
table had no mutation for) reddens `theDemoPublishesTheTreeTheVoiceOverScriptReads`
and `theVoiceOverScriptQuotesThePublishedTree`; V2 (modal isolation
short-circuited off) reddens four tests; V3 (`.combine` ignored) reddens
four; V4 (AppKit's AXSelected write dropped) reddens three; V5 (SDL: press
→ click dropped) reddens four; V6 (AppKit role `.incrementor` → `.button`)
reddens `theFiveControlRolesReachTheAppKitBridge`; V7 (the neutral `.select`
request refused) reddens four; V8 (divergence 95's isolation-refusal guard
always true) reddens two. Every one of the eight reddened something.

## §6 Record phase close (2026-09-30)

All three lanes verified `ok: true`. This section is an independent re-take
of the suite, guard and golden counts, the pixel comparison, `Backends/SDL`,
a `swift:6.4-noble` container and the lock probe, plus a disposition of the
three lanes' own verdict issues.

**Suite**, from a clean tree (`swift package clean` — `AXNode` and `Handlers`
each grew a stored field across the branch, public types crossing the test-
module boundary): `swift build --build-system native --build-tests` → 0
`error:`, the one SwiftPM deprecation `warning:`; `swift build --build-tests`
(default build system) → 0 `error:`, 0 `warning:`. Unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1880 tests in 3
suites passed after 117.613 seconds`**, one summary line, `FR-J no-argument
frame: succeeded=true` present (guards ran). **1880 = 1837 + 8 + 25 + 10**
(lane 1, lane 2, lane 3 — matching each lane's own close, re-verified rather
than re-derived). `goldensUnchanged` for the whole part: 0 goldens throughout
(`find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0); no test
retired; four renamed with an inverted answer or literal, each a T row naming
its ruling (`aPressIsRefusedWhereHitTestingIsDisabled` →
`aPressIsRunWhereHitTestingIsDisabled`, `IX-Z`;
`anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly` →
`settingAXSelectedOnARowReplacesTheSelection`, `IX-AA`;
`aMetalUITreeTranslatesToAccessKitsVocabulary`'s two literals,
`AppKitAccessibilityTests`' role-table literal — both `IX-AG`). No other
`@Test` was added, removed or changed its answer beyond the three lanes' own
tables. `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS`,
`theSevenRetentionSlotsAreMutuallyDistinct` and
`noConformerEmitsAnAXNodeItDidNotDeclare` all green (independently re-run,
filtered, above). `MetalUILayout` imports only `MetalUICore` (one line); the
`Sources/MetalUILayout` and `Tests/MetalUICrossPlatformTests/Expected.swift`
diffs against `31d3565` are both empty.

**Guards**: `grep -c canTypecheck` across every guard file CLAUDE.md names
(34 files, including the new `AccessibilityCompileGuards`) reads **117** raw
hits, less `UnitSafetyTests`'s one comment hit = **116**, matching both
lanes' own close. New this task: `AccessibilityCompileGuards` (3, all
whole-file `typecheckFile`:
`theAccessibilityModifiersCompileFromAPlainImport`,
`anAXNodesActionsAreDeprecatedTowardAccessibilityAction`,
`anUnofferedTraitOrActionKindDoesNotCompile`). **116 = 113 + 3**. The
`typecheckFile`-based helper count moves **74 → 77**; the `typecheck`-based
helper count stays **39**; 39 + 77 = 116.

**The three lane verdicts' own findings, disposed** (no fix required —
`ok: true` stood on all three before this close; each is recorded here as a
hazard or a deferral, not fixed on this branch):

- **Lane 1's V4, V7, V9 reddened nothing** — each is a clause `IX-AG` states
  in prose with no test naming it: a client's accessibility selection stores
  the lead/anchor as a click's does (item 5); the press-only record skips a
  suppressed subtree (item 6); the press-only record keeps the **last**
  registration per id (item 6). None is a defect — SwiftUI has no positive
  control for any of the three (screen locked) and MetalUI's own choice was
  never claimed as pinned — but each is now a named gap for a later branch
  to close with a test, not a silent one. Deferred, owner none (§9).
- **Lane 1's `settingAXSelectedOnARowReplacesTheSelection` (1.12) does not
  keep its two `Window`s alive with `withExtendedLifetime`**, the same
  defect `IX-AG` item 8 fixed in 1.13/1.14 — it passes only because a debug
  build happens to keep the locals alive past their last use. Not fixed on
  this branch (a test-only hardening, not a behaviour question); flagged for
  the next task that touches `ListSelectionTests.swift`.
- **Lane 1's SDL red-before figure in `IX-AG` does not reproduce exactly**
  (31 tests failed with 24 issues on a re-check, not the recorded 22) — the
  five reddened tests are unchanged (1.5–1.8, the translation T row); only
  the issue count differs, a transcription slip in the ruling, not a finding
  about the code.
- **Lane 3's 3.7 pins a hand-transcribed tree, not the rendered controls
  demo** (`IX-AJ` item 2's own reason: the SDL test target has no `MetalUI`
  dependency). A controls-demo change that moves 3.9 but not 3.7 leaves 3.7
  green pinning a tree the demo no longer publishes — a known coupling, owner
  none (a later branch could add the dependency, or check 3.9's table
  against 3.7's copy of it).
- **T3p and probe arm T3p together are divergence 33's, not a separate
  gap**: removing `.isButton` from a clickable element changes its role to
  `.group` (SwiftUI's own `AXUnknown`, `IX-X` item 4's amendment) — the same
  reasoning as `.ignore`'s `AXUnknown` → `AXGroup` reading (`AB-F`: a group
  reads better to VoiceOver than an unknown role) covers this row too;
  divergence 33's text is read as covering both.
- **This record file's own header read "DESIGNED, Lanes 1–3 not begun" until
  this close** — corrected above (§0).

**Pixels**: `docs/probes/demo-pixels/compare.sh /tmp/scratch63 31d3565
1bb6aa2` (independently re-taken by this Record phase, zsh, not bash — the
script's `${0:A:h}` is zsh syntax): controls exactly as recorded since stage
9 (light vs dark 1048576, default vs modal 1031003, default vs animation
454895, f0 vs f3 0, preview 1048576, chrome pair 0, distinct 544 and 216,
prod default vs modal 491221, prod distinct 529, indicator rects 0); **0
differing pixels, scene identical, in all fourteen images**.

**`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`): `swift build
--build-tests` → 0 `error:` (the `sdl` pkg-config rpath warning and the
SDL3-dylib version notice are this machine's own, unrelated to the branch —
present on an unmodified checkout too); `swift test --skip-build` →
**`Test run with 22 tests in 0 suites passed`** then **`Test run with 32
tests in 0 suites passed`** — **22 + 32**, the design's expected close.

**A `swift:6.4-noble` (aarch64) container** (`docker run --rm -v "$PWD":/work
-w /work swift:6.4-noble …`): the root package builds with 0
`error:`/`warning:` and runs `MetalUILayoutTests` **199**,
`MetalUICrossPlatformTests` **10**, `MetalUICoreTests` **22** — **199 + 10 +
22**, unmoved since record §62 (no lane of this task touches a portable
target).

**Real window: taken, unlocked, during lane 1's own close** — the first
unlocked reading in several tasks. The lock probe read
`CGSSessionScreenIsLocked` absent and `displayAsleep main: 0` at `6c961e3`;
`docs/probes/window-capture/capture.sh <scratch> 31d3565 6c961e3` ran and
read **0 differing** for both the default and preview states against
`31d3565`, with every a-vs-b stability pair also 0 and the control (default
vs preview at `6c961e3`) reading 958986, non-zero as it must. The screen was
locked again by lane 3's own check and at this close (`CGSSessionScreenIsLocked
= 1`, `displayAsleep main: 1`), so no further real-window state was added
beyond `6c961e3`'s — but this is the **first positive real-window reading**
production has had since the still-open capture was first flagged at stage
6b, and it covers this task's own lane-1 and lane-2 changes (lane 2 painted
no pixel; lane 3's two demo modifiers post-date `6c961e3` and are covered
instead by the fourteen-image offscreen comparison above, 0 px). See record
§03's dated section (§8 below) for what this does and does not close.

## §7 The audit, disposed (spec §2, `IX-U`)

Of the spec's 44 rows (part 1's rows 27–37 split where one named several
concepts, plus the brief's own items and every carried accessibility item):

- **Built**: `accessibilityElement(children:)` (`.ignore`/`.combine`/
  `.contain`); `accessibilityHidden`; eight traits; hint/identifier; declared
  and named actions; the press under `allowsHitTesting(false)` (divergence 28
  retires); settable `AXSelected`/`AXSelectedRows` on AppKit (divergence 83
  retires on that bridge; AccessKit still selects by `Click`); modal
  isolation and press occlusion (divergence 95 added); the proposal path's
  emission (`ProposalText`, the accessibility modifier wrapper, grids
  flattening); a labelled `Image(_:scale:label:)`; both bridges' new fields,
  parity enforced by a `Mirror` count on each side.
- **Pinned as SwiftUI's, no new behaviour**: `Button(role:)`/
  `.keyboardShortcut`/`.buttonStyle` publish nothing (neither does AppKit's
  own `NSButton`); gestures publish no press (divergence 27 amended); a
  truncated `Text` publishes its whole string; an accessibility focus
  request writes a bound `@FocusState`, and a `@FocusState` write is the
  tree's focus.
- **Amended**: divergence 32 (AppKit publishes `AXOutline`/`AXRow`/
  `AXOutlineRow` now, not `AXTable`; unrealised rows stay unreachable, kept,
  owner none); divergence 33 (`.ignore`, a removed `.isButton`, a labelled
  `Rectangle` all read `AXGroup` for SwiftUI's `AXUnknown`).
- **Kept, owner the human VoiceOver run**: divergence 82 (the `.incrementor`/
  `.radioGroup` partial fold) — the script has a step for it.
- **Routed to the script, no code**: the `DD-` rulings' contingent costs
  (`DD-U` item 3/9, `DD-AD` item 1, `DD-AE` item 2) — one script step each,
  naming its ruling.
- **Untouched, not separating**: divergence 31 (nothing focused reports the
  host) — the probe's F4 and part 1's arm 13 differ only in screen state.
- **Not task 12's**: `Stack` order (divergence 34), row indices for
  third-party containers, system settings (task 13), iOS (task 14).

Nothing on this list is left unclassified.

## §8 Divergences, declared-but-inert, and human looks (for CLAUDE.md and records 03/04/05)

**Divergences** (record §04's own dated section, added by this task): **28
retires** (a press under `allowsHitTesting(false)` is now advertised and
runs, `IX-Z`); **83 retires on the AppKit bridge** (`AXSelected`/
`AXSelectedRows` are now settable and replace the selection, `IX-AA`;
AccessKit still selects by `Click`, not a divergence — SwiftUI has no
AccessKit side); **95 added, kept, owner none** (an isolated-out element a
client already holds refuses a request, where SwiftUI's held element still
presses, `IX-Z` item 3 — rejected as "avoid it" in the critic round,
`IX-AF`); **27 amended** (MetalUI's gestures publish no press, matching
SwiftUI's G1–G7 exactly; `onClick` stays the one pressable surface, `IX-Y`
item 3); **32 amended** (`AXOutline`/`AXRow`/`AXOutlineRow`, SwiftUI's own
role, in place of `AXTable`; unrealised rows stay unreachable, kept, owner
none, `IX-AA` item 3); **33 amended** (`.ignore`, a removed `.isButton` and
a labelled `Rectangle` all read `AXGroup`, SwiftUI's `AXUnknown`); **82
kept, owner the human VoiceOver run** (the script's step for the
`.incrementor`/`.radioGroup` partial fold, divergence 83's retirement seen
by a human too). Live **69 → 68**, next label **96**.

**Declared but inert** (record §05's own dated section): `AXNode.actions`'
row **amended** (deprecated toward `accessibilityAction`/
`accessibilityAdjustableAction`; still never read, `IX-Y` item 4); **added**:
`AccessibilityTraits.updatesFrequently` (published nowhere on either bridge,
as SwiftUI's on macOS, T10); `ButtonRole`'s row (from part 1) gains its
accessibility evidence — B1/B2 confirm nothing is published, as SwiftUI.

**Human looks owed** (record §03's own dated section): **the VoiceOver
script run itself** — this task's own exit, and task 12's own remaining
box — plus the still-owed real-window capture's remaining states (every one
but `6c961e3`'s default/preview pair, now taken, §6 above). None of the
looks named at part 1 or any earlier task are closed or reopened by this
one.

## §9 Deferred, with owners

- **A client's AX selection's lead/anchor write, and the press-only record's
  suppression and last-registration-wins clauses** — each stated in `IX-AG`
  with no test naming it (§6's verifier disposition); owner none, a pin for
  whichever branch next touches `List.accessibilityRowSelection` or
  `Frame.accessibilityPressOnly`.
- **3.7's AccessKit parity pin transcribes 3.9's table rather than rendering
  the controls demo** (`IX-AJ` item 2); owner none — a later branch could
  give the SDL test target a `MetalUIDemoContent` dependency, or check 3.9's
  table against 3.7's copy of it.
- **`SwiftUI.accessibilityAction(.default)`/`accessibilityAction(_ kind:)`
  (`.escape`/`.magicTap`)** — owner none (spec §4): `.default` is the
  unlabelled form already offered; the other kinds have no macOS client in
  the probe.
- **The VoiceOver script itself, and task 12's box** — owner the human. The
  Record phase re-reads `docs/verification/voiceover-script.md` once every
  step has an observed result.

## §10 CLAUDE.md, plan and record updates made alongside this record

See the commit that carries this file for the full diff. In short: CLAUDE.md
gains the counts entry below; the `IX-` prefix's next-unused letter moves to
`IX-AK`; the record map gains this file (§63); "Accessibility" is rewritten
for the new modifiers, children behaviour, traits, modal isolation, declared/
named actions, the press order, the proposal path's emission and the
neutral tree's new fields; "Hit testing" notes a press under
`allowsHitTesting(false)` is not a hitbox query; the guard list gains
`AccessibilityCompileGuards`; the "List" and shapes/rendering paragraphs are
corrected where divergence 83 and the labelled-image gap they named are now
built. `docs/record/04-divergences.md`, `05-declared-but-inert.md` and
`03-verified-on-real-hardware.md` each gain a dated 2026-09-30 section (§8
above is their content). `docs/record/README.md` gains a row for this file.
The plan's task 12 entry gains a dated progress note (part 2 delivered,
naming the VoiceOver script and that it needs a human); its box stays
unticked.

## §11 Counts (final, this task)

**1880 tests, 0 goldens, 116 typecheck guards**, 0 `error:` on both build
systems, the one `warning:` SwiftPM's deprecation notice under native (0
under the default one). `1880 = 1837 + 8 + 25 + 10` (lane totals above).
`Backends/SDL` **22 + 32** on macOS. A `swift:6.4-noble` container: root
package 0 `error:`/`warning:`, runs **199 + 10 + 22**. 0 px against `31d3565`
in all fourteen offscreen images. `MemoryLayout<AXNode>.size` 113 → 121,
`MemoryLayout<Handlers>.size` 440 → 448; smallest thread building every
production tree stays 624 KB. Live divergences **69 → 68**, next label
**96**. Real-window capture: `6c961e3`'s default/preview pair taken, 0
differing — the first unlocked reading since stage 6b; every other state
stays owed. Task 12's box: **unticked** — the VoiceOver script is written,
not run.
