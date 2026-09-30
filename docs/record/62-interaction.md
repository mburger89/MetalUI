# 62 — Interaction (plan task 12, part 1)

Branch `feat/interaction` from `31f2e7a` (master, task 11 closed, record §61).
Spec `docs/superpowers/specs/2026-09-29-interaction-design.md`; rulings
`IX-A`…`IX-T` in a new decisions doc,
`docs/superpowers/2026-09-29-interaction-decisions.md` (next unused `IX-U`).
Probes: `docs/probes/swiftui-interaction.swift` (new), `docs/probes/swiftui-gesture-presentation-arena.swift`
(new, lane 1's fix round), and three existing probes re-run this session,
compiled, reading their recorded values: `swiftui-content-shape-hit-region.swift`,
`swiftui-disabled-interaction.swift`, `swiftui-disabled-ancestor-and-order.swift`.

**Status: DESIGNED, critic round applied (`IX-O`); lane 1 landed (`IX-P`, fix
round `IX-Q`); lane 2 landed (`IX-R`, fix round inline); lane 3 landed
(`IX-S`, stopped on a finding; continued by `IX-T`); Record phase close
applied (§6 below) — LANDED, the interaction half of plan task 12.** Task
12's box stays **unticked**: the second sentence of the task's text — deliver
and validate the native accessibility bridge with VoiceOver — is part 2, not
begun by this branch.

## §1 Design (2026-09-29)

**Baseline re-taken at `31f2e7a`** in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1773 tests in 3 suites passed after 110.836 seconds`, the
`FR-J no-argument frame: succeeded=true` line present. 108 guards, 0 goldens,
68 live divergences, next label 94.

**Probe.** `swiftui-interaction.swift` (new, 156 lines at design time, groups
`G` gestures, `H` composition precedence, `B` buttons, `PX` looks, `F`/`K0`
focus, `C` content shapes): compiled and run twice, stdout byte-identical,
exit 0, stderr empty, screen **locked** (`CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`). The synthesized click/key harness (`FirstMouseHost`,
`NSEvent`s through `NSWindow.sendEvent` with a run-loop spin) works locked —
every positive control passes (`G0`, `K0`, `C0`, `PX0`). Its blind spots —
label/text ink, the bordered bezel's pressed and disabled looks, the focus
ring, a real key window — are recorded in its header and every rule resting
on one is stated as MetalUI's own choice, never a SwiftUI claim (`IX-E` item
3, `IX-G` item 2, `IX-H` item 2). Three existing probes re-run the same
session and read their recorded values: `swiftui-content-shape-hit-region.swift`,
`swiftui-disabled-interaction.swift`, `swiftui-disabled-ancestor-and-order.swift`.

**The audit** (spec §2, `IX-A`): every item addressed to "task 12" across
`docs/superpowers/`, `docs/record/` (excluding frozen §19), `Sources/`,
`Tests/` and the plan — 38 rows. Nineteen dispose **this run** (gestures,
button roles/styles/shortcuts/pressed look, the disabled and inactive looks,
divergences 21/22, focus ring, `@FocusState`/`.focused`, the identity-rename
focus fix, Full Keyboard Access (amended, kept), click-to-focus (a new
divergence), `hidden()` and focus/keys/wheel, `contentShape(_:)` taking a
`Shape`, `clipShape`'s hit behaviour, divergence 57, a shape's default hit
region); eight are **not offered**, owner none (a public tap-with-modifiers,
`sequenced`/`@GestureState`/`GestureMask`/custom gestures, `ButtonStyle`/
`PrimitiveButtonStyle` protocols/`.borderedProminent`/`.link`, menus and
`.contextMenu`, `ToggleStyle` variants, proposal-path focus); eleven are
**part 2** (the VoiceOver script and every accessibility item: `AXSelected`,
`accessibilityElement(children:)`, the `AB-H` press question/divergence 28,
modal isolation, divergence 32, divergence 82, `AB-Q` proposal accessibility,
an `onTap`/image's VoiceOver presence, `AXNode.actions`); one item
(`controlSize`'s consumers) reads "nothing left here" — tasks 10/11 already
delivered it.

**Lanes** (spec §6, re-cut by the critic round): 1 gestures and the arena, 2
buttons/shortcuts/looks/content shapes (content shapes moved here from lane 3
by `IX-O`), 3 focus; run in order, each red first, each mutated, each with
its own `Handlers`-member Windows-stack measurement (CLAUDE.md "Lanes and the
Windows budget", `IX-N`). Lock probe at design time: locked, so the
real-window capture is owed, as at every task since stage 6b.

## §2 Critic round (2026-09-29)

Ruling `IX-O`; next unused (at the time) `IX-P`. **Four new probe arms**
(group `X`, X1–X4) added to `swiftui-interaction.swift` and the whole re-run
twice: stdout byte-identical (161 lines), exit 0, stderr empty; lines 1–156
unchanged from the design's reading. X1: a `.hidden()` button's shortcut
still fires (as an opacity-0 one already did, B4j). X2: Return in a focused
`TextField` submits it and does not fire a beside `.defaultAction` `Button`.
X3/X4: a plain `Button` child keeps its own press against a parent's normal
`DragGesture`, even across a 30 pt move inside it, and the parent's drag
reports no change at all — the withheld-member clause (spec §5) needed this
separating arm before `IX-D` item 3 could rest on it.

**Eleven corrections, two rejections** (`IX-O`, full list in the ruling):
audit row 18b added (a hidden scroll region still takes the wheel, kept,
`OM-AK`); content shapes moved from lane 3 to lane 2 (so `contentShape(_:)`
lands beside the `Hitbox`/`Handlers` work that already touches the region
test, rather than splitting `Hitbox.contains` across two lanes); `IX-D` item
3's withheld-member clause pinned by X3/X4 rather than left unmeasured;
`IX-K` item 3's hidden-focus fix scoped to the keyboard half only, X1
confirming the shortcut half stays live; three more of the same shape (each
narrowing a clause from "as designed" to "as X1–X4 show"). **Rejected**:
splitting gestures and buttons further (the design's two-or-three-lane
budget, CLAUDE.md "Workflows and subagents"), and numbering divergence 81
(menus) now rather than leaving it re-owned with no number, since nothing
here builds a menu to diverge from.

## §3 Lane 1 — gestures and the arena (2026-09-29)

Commits: red `0d661fd`, green `95765d6`; fix round red `573ef7e`, green
`ee92939`; ruling `IX-P` (the landing) and `IX-Q` (the fix round).

**New public API** (`IX-B`): `Gesture` (a closed, `@_spi`-gated protocol —
see clause 1 below), `TapGesture`, `LongPressGesture`, `DragGesture`,
`ExclusiveGesture`/`SimultaneousGesture`, `.exclusively(before:)`/
`.simultaneously(with:)`, and on `StyledElement`: `onTapGesture(count:perform:)`,
`onLongPressGesture(...)`, `.gesture(_:)`, `.simultaneousGesture(_:)`,
`.highPriorityGesture(_:)` — each appending and returning `Self`; the same
five on `ProposalElementGroup`, each producing a `GestureModifier<Content>`.
`onClick` is unchanged (`IX-D` item 2): its doc comment is corrected from
"SwiftUI's `onTapGesture`" to state Button semantics (press and release on
the same element, an excursion allowed) — the two are different contracts,
not synonyms.

**Files.** New `Sources/MetalUI/Gesture.swift` (the protocol, the five
gesture types, recognizers, the pure `GestureArena`), new
`Sources/MetalUI/GestureModifiers.swift` (the `StyledElement`/proposal
modifiers, `GestureModifier`), `Handlers.swift` (`gestures`, joining
`isPointerTarget`), `Hitbox.swift` (`contains(_:)`, `origin`), `Window.swift`
(the arena in the pointer path, the tick advance), `Frame.swift`
(`insertHitbox`'s `origin:` argument only), doc corrections to `onClick`
(`Box.swift`), `Handlers`, `ClickDispatch`, `StateDispatch` and one sentence
in `Button.swift` (it too called `onClick` "SwiftUI's `onTapGesture`").
Tests: new `Tests/MetalUITests/GestureTests.swift` (through a real `Window`
on a `FakePlatformWindow` with `simulateTick`) and `GestureCompileGuards.swift`;
the spec's separate `GestureArenaTests.swift` was not needed — every arena
rule is reached through the window.

**Seven clauses decided here, none a SwiftUI claim** (`IX-P`):

1. `Gesture`'s one requirement is `@_spi(MetalUIGesture)` — a public
   protocol cannot have an internal requirement, so an outside conformer is
   blocked at the type, not merely the method (measured in a two-module
   scratch: without SPI on the *result type* too, a fabricated
   `_recognizers() -> _GestureRecognizers` would satisfy it).
2. A tap's count is `clickCount − (the arena's first press's clickCount) +
   1` — equal to the raw platform count for every probe arm, differing only
   when a new arena starts mid platform-double-click.
3. The tick advance runs in the display-link callback, ahead of
   `drawFrameIfNeeded`, so a stamp is always a real tick (a direct
   `drawFrameIfNeeded()` call from a test or a resize stamps nothing); the
   window re-dirties only while `GestureArena.needsTicks`.
4. The arena lives from press to release, and past it only while a tap
   sequence waits; a press on the same target continues it, a press
   elsewhere or on nothing abandons it (every undecided member fails, a
   waiting tap fires if it was waiting only on them).
5. The larger-count tap deferral is arena-wide, simultaneous members
   included, so a smaller tap ahead of a larger one yields to it.
6. `LongPressGesture.onChanged` reports `true` at the press (SwiftUI's own
   withholding here is unmeasured).
7. `enclosingScroller(of:at:)` calls `Hitbox.contains` in this lane
   (correction 6 from the critic round), so `grep -n "bounds.contains("
   Sources/MetalUI` already finds only `Hitbox.contains`;
   `topmostOpaqueHitbox` remains the only `(layer, offset)` comparison.

**Red first** (`0d661fd`): the test target did not compile before `Gesture`
etc. existed; once the surface stored attachments with no hitbox and no
arena, all 23 tests were red — 22 at the geometry requirement (a
gesture-only element registers no hitbox), 1.20 at `taps.count == 2`. 1.18
was therefore red too, not green-first (its child, a gesture-only element,
could not exist before the surface); 1.24 (the presentation clause) did not
exist yet. G1.1/G1.2 were green once the surface existed and each was
mutated red once. `ModifierTests`' `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`
gained the five modifiers (45 → 50 rows), `OuterModifierMatrixTests`'
`HandlerFingerprint` gained `gestureCount` — both existing tests extended,
every existing row's answer unchanged.

**Mutations** (each on the green tree, restored from a copy, whole suite —
1798 tests each time — `git status --short` clean after every one):

| id | mutation | reddened |
|---|---|---|
| M1a | a tap ends at its press | 1.1–1.6, 1.16, 1.17, 1.21 |
| M1b | slop 5 → 6 | 1.2 |
| M1b′ | slop check removed | 1.2, 1.3, 1.16 |
| M1c | `taps == count` → `taps >= 1` | 1.4, 1.5, 1.6 |
| M1d | deferral 0.33 → 0 | 1.5 |
| M1e | arena-wide deferral removed | 1.6 |
| M1f | a long press matures only at release | 1.7, 1.8, 1.9, 1.16, 1.17, 1.22 |
| M1g | maximum distance unchecked | 1.8 |
| M1h | no `pressing=false` on a failed press | 1.9 |
| M1i | `distance >= minimum` → `>` | 1.10, 1.21 |
| M1i′ | drag values in window coordinates | 1.10, 1.12, 1.21 |
| M1i″ | a never-started drag still ends | 1.11, 1.16, 1.18, 1.23 |
| M1j | a drag ends only inside its element | 1.12 |
| M1k | normal members outermost-first | 1.13, 1.16 |
| M1l | high priority treated as normal | 1.14, 1.21 |
| M1m | simultaneous callbacks after the winner's | 1.15 |
| M1n | only an *ended* member ahead blocks | 1.16, 1.23 |
| M1o | `simultaneously` resolved exclusively | 1.17 |
| M1p | ancestors' `onClick` join the arena | 1.18 |
| M1q | gestures registered outside the gates | 1.19 |
| M1r | callbacks run without `StateDispatch` | 1.20 |
| M1s | `GestureModifier` stores no attachment | 1.21 |
| M1t | frames requested while pressed, not only pending | 1.22 |
| M1u | a withheld drag's changes reported anyway | 1.23 |
| G1.1 | `@_spi` removed from the requirement and its type | `anOutsideTypeCannotConformToGesture` (fabricated arm compiled) |
| G1.2 | `highPriorityGesture` made internal | `theGestureSpellingsCompileFromAPlainImport` |

No mutation reddened a test outside `GestureTests`/`GestureCompileGuards`.

**Counts** (after `swift package clean`): `Test run with 1798 tests in 3
suites passed` (1773 + 23 + 2); guards **108 → 110**
(`GestureCompileGuards`, both whole-file `typecheckFile`).
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `Expected.swift`
unedited. **Pixels**: 0 differing, scene identical, in all fourteen images,
controls non-zero as recorded. `MetalUILayout` imports only `MetalUICore`.
`Backends/SDL` builds (0 `error:`); a `swift:6.4-noble` container builds with
0 `error:`/`warning:` and runs 199 + 10 + 22.

**Windows stack budget**: `MemoryLayout<Handlers>.size` 408 → 416; smallest
thread building every production tree 592 → **608 KB**.
`everyProductionTreeBuildsOnAOneMegabyteThread` green. (Spec §6's carried
"528 KB at `31f2e7a`" figure was already stale before this lane — record §59
had measured 592 KB; corrected here rather than repeated.)

### §3.1 Lane 1's fix round (`IX-Q`)

**Finding, and its fix.** `Window.makeGestureArena` walked `id.parent`
without reading `layer`, so a `Deferred` presentation's content — hoisted to
a higher hit layer while its id stays under its declarer's — joined its
declarer's arena: a declaring ancestor's `highPriorityGesture` took a
modal's `onClick`, and its `simultaneousGesture` ran on every press inside
the modal (a scratch window read `["root-high"]`). **Fixed**: an ancestor
hitbox joins only when its `layer` equals the target's. New probe
`docs/probes/swiftui-gesture-presentation-arena.swift` (12 lines recorded,
compiled and run twice, byte-identical, screen locked; its presentation host
needed `acceptsFirstMouse(for:)` replaced, without which every `S`/`V` arm
read "-", a broken instrument discarded rather than read) shows the two
SwiftUI shapes disagree: an `.overlay` (same layer) **is** in its
presenter's arena (P1 `presenter-high`, P2 `presenter-sim,modal`); a
`.sheet`'s or `.popover`'s content (a new window) is **not** (S1/S2, V1/V2
read exactly their controls, `modal`). A MetalUI `Deferred` is the
presentation shape (the portal, the scrim, the modal's own spelling), so it
takes the sheet/popover rule; an `.overlay` is `OverlayModifier`, same
layer, unaffected. An in-flow `Deferred` (a tooltip) takes the same rule —
it too is hoisted. Nothing in the repository's own trees attaches a gesture
yet, so no existing behaviour moves (0 px by construction).

**Five more clauses, each pinned by a mutation that had none**: the arena's
region clause (1.25: a child overflowing a 50-wide gesture-carrying
`.frame`); the abandon clause (1.26: a single tap beside a double ends at a
press on another target within the deferral); `Hitbox.origin` for a
content-shape inset (1.27: a drag's `startLocation` reads the element's own
(100,100), not the inset region's (80,80)); a tap released outside its
element inside the slop (1.28). `GestureModifier` also gains its own gate
arm in `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` (`gesture`
and `gesture-legacy`) and 1.19 gains a proposal `allowsHitTesting(false)`
arm — CLAUDE.md "Environment"'s rule for a new handler-registering site.

**Mutations** (V2–V7, each on `ee92939`, restored, whole suite — 1803 tests
each time):

| id | mutation | reddened |
|---|---|---|
| V2 | `GestureModifier.prepaint` registers past the gates | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` (arm `gesture`), 1.19 |
| V3 | an ancestor joins without `Hitbox.contains(point)` | 1.25 |
| V4 | an ancestor of any hit layer joins (the lane's original code) | 1.24 |
| V5 | `registerHandlers` passes no `origin:` | 1.27 |
| V6 | a press elsewhere drops the arena without `abandon()` | 1.26 |
| V7 | a tap's release skips the region check | 1.28 |

**Counts**: `Test run with 1803 tests in 3 suites passed` (1798 + 1.24–1.28;
two existing tests extended); guards unmoved (110).

**Real window**: lock probe 10:17 PDT and 11:xx PDT — locked at both checks;
`capture.sh` not run; owed, as at every task since stage 6b.

## §4 Lane 2 — buttons, shortcuts, the looks, content shapes (2026-09-29)

Commits: red `fb0053b`, green `68a33ec`; fix round `4e8492b`; ruling `IX-R`.

**New public API** (`IX-E`, `IX-F`): `ButtonRole` (closed: `.destructive`,
`.cancel`, `.confirm`, `.close`), `Button(role:action:label:)`,
`ButtonStyle` (closed: `.automatic`, `.bordered`, `.borderless`, `.plain`),
`.buttonStyle(_:)`, `KeyEquivalent`, `KeyboardShortcut`
(`.defaultAction`/`.cancelAction`), three `.keyboardShortcut` overloads,
`EventModifiers = Modifiers` (narrower than SwiftUI's, `IX-F` item 1); and,
moved here from lane 3 by the critic round (`IX-L`): `contentShape<S: Shape>(_:)`
on `StyledElement`, `OnTapModifier` and `GestureModifier`.

**Files.** `Button.swift`, new `ButtonStyle.swift`, new
`KeyboardShortcut.swift` (`KeyEquivalent`, `KeyboardShortcut`,
`EventModifiers`, the matcher, `ShortcutTarget`, `Window.dispatchShortcut`),
new `ControlLook.swift` (`controlAccent(_:)`, `controlRing(_:)`,
`PaintPass.paintControl(disabled:)`); `Handlers.swift`
(`keyboardShortcut`, joining `isKeyTarget`; `contentShape`, a `ContentShape`
class box); `FocusRegistry`'s shortcut table in registration order; one
`Window.onInput` call between the raw `onKey` bubble and Tab; `Hitbox.shape`
(window space, tested by `Hitbox.contains`); `ShapeGeometry.contains(_:)`/
`offsetBy`; the disabled scope, key-window accent and focus ring on
`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`; doc comments on
`EnvironmentValues.controlActiveState`/`ControlActiveState` (they now have
consumers). Tests: new `ButtonSemanticsTests.swift`,
`KeyboardShortcutTests.swift`, `ControlLookTests.swift`,
`ContentShapeTests.swift`, `ButtonCompileGuards.swift`;
`DecorationCompileGuards.swift` gains one `@Test` (G2.2).

**Eleven clauses decided here, none a SwiftUI claim** (`IX-R`):

1. `.plain`/`.borderless` drop the chrome **at layout, by value**: a
   decoration field still equal to the chrome's own is dropped, so a
   caller's `.background` survives in either order relative to
   `.buttonStyle`; the strut stays (0×0) so the label is index 0, the strut
   1, in every style.
2. The pressed wash paints **after** the chrome's content (over label and
   border, not between fill and label — `Box.paint` has no seam there),
   rounded to the chrome's corner radius.
3. The focus ring is on every `Button` style, `.plain` included, and while
   focused replaces the chrome's 1-pt border (`focus ?? hover ?? plain`,
   `OM-L`); a caller's own `focusBorder` still wins.
4. A segmented `Picker` has no accent to remove (its selected segment is
   `.surface`); only the radio group's selected circle follows
   `controlActiveState`.
5. The key compares **lower-cased** (AppKit reports a shifted letter
   upper-case via `charactersIgnoringModifiers`); the modifiers exactly
   (pinned by 2.4's ⌘⇧K arm, fix round V6).
6. A focused `TextField` with no `.onSubmit` does not claim Return — its
   editing stage returns unhandled, so a beside `.defaultAction` button
   fires (as before `TI-B`; unmeasured in SwiftUI, unpinned, stated). A
   focused `TextEditor` inserts `\n` and claims it.
7. A shortcut runs whatever a click runs (`composed.onClick ?? action`, a
   caller's `.onClick` replaces it too), dispatched under `StateDispatch` to
   the button's id (pinned by 2.4b, fix round V7).
8. A shortcut registers **whatever `hidden()` says** — lane 3's hidden
   condition gates the focus half only (`X1`, spec 3.14b).
9. A content shape composes with `contentShape(inset:)`: the shape's
   geometry is taken in the inset rect; it rides the layer's `Handlers`, so
   a shape written before a wrapping modifier does not reach a click
   written after it (`contentShape(inset:)`'s existing S1 divergence,
   unchanged in kind).
10. `Hitbox.contains` tests the clipped rect first, then the shape (the
    shape is never itself clipped) — a content shape only shrinks a region
    the clip already bounds (divergence 43, amended).
11. The looks read `environmentTop` in place (`isEnabled`,
    `controlActiveState`), costing no counted snapshot (`EV-O`); `Button`
    keeps its one `pass.environment` read in layout.

**Red first, and one harness finding.** At `fb0053b`, 2.2–2.16 were red (15
tests, not the design's carried "13" — `74d1022`'s own commit message keeps
the stale figure, corrected here); 2.1, 2.17, 2.18, G2.1, G2.2 and the
extended `ModifierTests` row were green (2.1 pins an absence, 2.17/2.18 pin
today's behaviour, written first). **Four shortcut tests discarded their
`Window`** (`let (_, platform) = …`, held weakly by the fake platform, so no
event reached it): 2.5, 2.6, 2.8's hit-testing arm and 2.9 were red for that
reason as well as the missing dispatch, and **2.8's disabled arm read green
vacuously**. Fixed in `68a33ec` (`withExtendedLifetime`), and the fixed
tests re-shown red without the dispatch by mutation M2x (below).

**Mutations** (each on `68a33ec`, restored, whole suite — 1823 tests each
time):

| id | mutation | reddened |
|---|---|---|
| M2a | `.cancel` binds Escape | 2.1 |
| M2b | `.plain` keeps the padding | 2.2, 2.15 |
| M2c | pressed = `isActive` alone | 2.3 |
| M2d | modifiers compared as a superset | 2.4 |
| M2e | `defaultAction`/`cancelAction` swapped | 2.5, 2.13 |
| M2f | last registered shortcut wins | 2.6 |
| M2g | shortcut stage before the raw `onKey` bubble | 2.7 |
| M2h | shortcut registered outside the `isEnabled` gate | 2.8 |
| M2i | shortcut skipped under decoration opacity 0 | 2.9 |
| M2j | disabled scope gated on `!isFocused` | 2.10, 2.11, 2.3, `aTogglesIndicatorColourAnimatesUnderWithAnimation` |
| M2k | accent on `!= .inactive` | 2.11 |
| M2l | ring token `.separator` always | 2.12 |
| M2m | shortcut stage before a focused field's editing keys | 2.13, 2.7 |
| M2x | `dispatchShortcut` call removed | 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.13 |
| M3i | `Hitbox.contains` ignores the shape | 2.14, 2.15, 2.16 |
| M3j | the shape tested in `dispatchClick` only (a second copy) | 2.16, 2.15 |
| M3k | a hit intersected with the clip's rounded geometry | 2.17 |
| M3l | a hitbox for every painted element | 2.18 + 21 more existing tests |
| G2.1 | `ButtonStyle.borderless` made internal | `theButtonSpellingsCompileFromAPlainImport` |
| G2.2 | `contentShape(_:)` declared on `ProposalElementGroup` | `aProposalElementCannotSpellContentShapeBeforeItsTap` |

**Fix round** (four unpinned clauses gained pins): V5 (a content shape under
a scrolled scroller followed the scroll, 2.16b new), V6 (⌘⇧K on the
upper-case event, 2.4 an arm), V7 (a shortcut's occurrence under
`StateDispatch`, 2.4b new), V10 (the ring's `.separator` colour in a
non-key window, 2.12 an arm) — each shown red by the mutation that removes
it. `Test run with 1825 tests in 3 suites passed` (1823 + 2); guards
unchanged (112).

**Recorded greps**: `grep -rn "bounds.contains(" Sources/MetalUI` → one hit
(`Hitbox.contains`); the `(layer, offset)` comparison → one hit
(`topmostOpaqueHitbox`).

**Counts** (after `swift package clean`): `Test run with 1823 tests in 3
suites passed` (1803 + 18 + 2); guards **110 → 112**.
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `Expected.swift`
unedited. **Pixels**: 0 differing, scene identical, in all fourteen images.
`Backends/SDL` builds; a `swift:6.4-noble` container builds with 0
`error:`/`warning:` and runs 199 + 10 + 22.

**Windows stack budget**: `MemoryLayout<Handlers>.size` 416 → 432; smallest
thread building every production tree stays **608 KB** (the new member is
one reference-sized field, absorbed inside the 16 KB step already crossed by
lane 1).

**Real-window capture**: lock probe 11:58 PDT — locked; not taken; owed.

**Not done here** (unchanged owners): the hidden condition and
`@FocusState` (lane 3); `TextField`/`TextEditor` take no disabled look;
`List` and text selection keep their accent; the `METALUI_CONTROLS_DEMO`
additions spec §7 allowed were not made (no pixel exit needs them); the
looks (pressed, disabled, inactive, ring) are owed to the human list beside
a native SwiftUI window.

## §5 Lane 3 — focus (2026-09-29)

Commits: red `48f0394`, feature `53e09d3` (stopped on a finding, `IX-S`),
instrument fix `96d5874` + docs `aba2698` + `f77756f` (`IX-T`).

**New public API** (`IX-J`): `@propertyWrapper FocusState<Value: Hashable>`
(`init()` where `Value == Bool`, `init<T>()` where `Value == T?`,
`wrappedValue`, `projectedValue: FocusState<Value>.Binding`), and on
`StyledElement`: `.focused(_ condition: FocusState<Bool>.Binding)`,
`.focused<Value>(_ binding:equals:)`.

**Files.** `StateTable.swift` (`isWindowRetained` keeps `$ax` only; the
cleared-focus report set, `resetFocusSlots`), `Frame.swift`
(`resolveFocus`, the frame-boundary `@FocusState` reconciliation, the hidden
condition on the one gate in `registerHandlers`'s 5-argument
implementation, `disablingHitTestingIfHidden`'s keyboard-hidden depth),
`Element.swift`, `ModifiedElement.swift`, `AnyElement.swift` (the hidden
scope's keyboard counter, mirrored per `MC-B`), new
`Sources/MetalUI/FocusState.swift`, `StateReflection.swift` (seeding the
box), `Box.swift` (`.focused`; `focusable()`'s doc, whose `hidden()` hazard
is fixed). Tests: new `FocusStateTests.swift`, `FocusIdentityTests.swift`,
`FocusStateCompileGuards.swift`; edits to `ConditionalIdentityTests.swift`
(C2.8, C2.12 re-derived; C2.13 retired), `FocusTests.swift`
(`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
re-derived and renamed `focusDropsWhenAnIfRemovesItsElement`) and
`AccessibilityTreeTests.swift` (a focus control re-derived).

**`IX-I` — focus leaves with its identity (`ID-R` item 9, fixed, not
numbered).** Before this task, a focused element that an evaluated reset
removed (an `if` gone false, a `for`/`ForEach` that stopped producing it, a
position whose `.id` changed) kept focus while away — below the sweep
threshold, indefinitely — its still-produced ancestors kept receiving its
keystrokes, and focus came back when it returned. **Fixed to SwiftUI's
answer** (probe arms F1, F2): `$focus` is no longer exempt from `ID-C`'s and
`ID-R`'s evaluated-position resets, so a reset that deletes the position's
`StateTable` entries also deletes its `$focus` retention slot; focus is
cleared **in the frame that removes it and does not come back**. **A
migration note** (for any caller relying on the old behaviour): a key typed
after the removal reaches the nearest remaining handler through
`Window.onInput`, not the removed subtree's ancestors, and a returning
`TextField` is unfocused; to keep the old effect, refocus on return —
`Window.focus(id)` from input, or write the `@FocusState` the element is
bound with, which applies before the next frame builds. **Unchanged**: a
`List` row scrolled out of its window (an *unevaluated* subtree, `TB-AH`)
keeps focus and gets it back; every `GlobalElementID`, the seven retention
slots, `MC-A`/`MC-C`/`MC-P` numbering and `.id()`'s outermost rule; `$ax`
stays exempt.

**`@FocusState` implementation** (`IX-J`, as landed): a box seeded by
`StateBinder` at the `$state<n>` sibling (no new reserved name), storing
`FocusStateValue { value, pending }`; `.focused`/`.focused(equals:)` set a
new internal `Handlers.focusBinding` (one reference), recorded in the focus
registry **ungated**. `Window.drawFrameIfNeeded` applies pending writes
**before** the frame is built — a value moves focus to the last frame's
bound element only if that element was focusable last frame, else focus
stays; `false`/`nil` clears only a focused element bound to that state; and
after the frame's focus read-back, writes each bound state's implied value
only where it changed (a dirtying write between frames, never in a phase).
A focused element retained but not produced this frame (a windowed-out
`List` row) has no binding recorded, so its state reads the default until
it returns — stated, unpinned.

**`IX-K` item 3 — hidden, keyboard-only.** `Frame.disablingHitTestingIfHidden`
now also bumps a keyboard-hidden depth; `registerHandlers`'s one gate
registers the keyboard half only while enabled **and** not hidden — a hidden
element still registers its **shortcut** alone (`FocusRegistry.registerShortcut`,
arm X1, lane 2's clause 8), and the `$focus` retention write is gated on
both. `ModifiedContent.prepaintLayer` calls the pointer scope alone (its own
copy, `MC-B`).

### §5.1 Stopped on a finding (`IX-S`)

Lane 3's tests (3.1–3.14, 3.14b, 3.20, G3.1) were written red first
(`48f0394`) and turned green by the implementation, but the unfiltered suite
read **`Test run with 1837 tests in 3 suites failed … with 1 issue`**: a
test not in the spec's list reddened, so — per spec §6's own rule — the
lane stopped without editing it.

**The finding.** `aFocusRequestWhileDisabledLeavesNoRetentionSlot` (D13,
`DisabledTests.swift`, `EV-F`), its **instrument arm, pinned wrong on
purpose** ("a non-focusable enabled element's slot makes the second request
stick"): `Expectation failed: hazard`. The arm reaches the known hazard in
`Frame.registerHandlers`'s `$focus` paragraph (a `Window.focus` on a
produced, enabled, non-focusable element writes a stray `$focus` slot; once
the element is removed, a second `Window.focus` on its id used to stick,
because `resolveFocus`'s fallback only asked `peek != nil`). The arm removes
the element **with an `if`** — an evaluated reset — and `IX-I` no longer
exempts `$focus` from that reset, so the stray slot is now deleted with the
element and the second request clears instead of sticking: **`IX-I` closed
the hazard's `if` route**. Measured: restoring the exemption (mutation
`MRk′`) and running the test alone turns it green again; the disabled arm
(D13's actual subject) is green either way. **The hazard is not gone**, only
its reset routes — an element that stops being produced *without* an
evaluated reset (a `List` row windowed out, `TB-AH`) still keeps its
`$focus` slot, so the same sequence over a windowed-out row still sticks.

### §5.2 Continued (`IX-T`): D13 re-derived, docs corrected, migration note

**D13 keeps both arms and its subject**, moved onto the route `IX-I` does
not reset: a `ScrollView { List(12 rows, rowHeight 20) { Box { subject } } }`
driven through a real `Frame`. Cold frame; focus row 4's subject at offset
80 (rows 2..<7 built); two frames at offset 0 (row 4 out of window); focus
its id again at offset 0. **Instrument arm** (`Box()`, enabled, not
focusable): the second request **sticks**, as designed. **Subject arm**
(`Box().focusable().disabled(true)`): it does **not** stick. Both below
`StateTable.sweepThreshold`. A **T row**, naming `IX-I`: the test's answer
is unchanged in both arms — only its route moved.

**Pinned both ways** (`96d5874`, full unfiltered suite each time):

| mutation | reddens |
|---|---|
| MD1: `$focus` retention write ungated on `enabled` | D13 only |
| MD2: `resolveFocus`'s retention fallback always clears | D13, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `theSevenRetentionSlotsAreMutuallyDistinct` |

So each arm can fail on its own, and the two arms disagree on the unmutated
tree.

**Source docs corrected**: `Frame.registerHandlers`'s `$focus` paragraph now
says the hazard is reached only through an unevaluated subtree, pointing at
D13's `List`-row route; `Frame.resolveFocus`'s three measured consequences
now hold only for a subtree nothing evaluates, naming
`focusDropsWhenAnIfRemovesItsElement` for the evaluated case.
`FocusRegistry.shortcut(matching:)`'s doc line moved back above the function
it belongs to.

**The lane's remaining mutations, run and verified during this Record
phase's close** (§6 below, closing the "still owed" list `IX-T` left): all
twelve named mutations (`MRl`, `M3a`–`M3h` less `M3e`, `M3m`, `M3n`) plus the
two already pinned by `96d5874` (`MD1`, `MD2`) and the guard (`G3.1`), each
applied on `f77756f`, restored from a copy, the whole 1837-test suite run
unfiltered, `git status --short` clean after every one:

| id | mutation | reddens |
|---|---|---|
| MD1 | `$focus` retention write ungated on `enabled` | D13 only (1 issue) |
| MD2 | `resolveFocus`'s retention fallback always clears | D13, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `theSevenRetentionSlotsAreMutuallyDistinct` (3 issues) |
| MRk′ | `StateTable.isWindowRetained` restores `\|\| id.component == focusRetentionName` | `focusDropsWhenItsElementIsRenamedAndDoesNotReturn` (3.1), `focusDropsWhenAnIfRemovesItsElement` (3.2), `aResetKeepsTheAccessibilitySlotButNotFocus` (3.3), `aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh` (3.4), `aForEachThatDropsItsFocusedElementDropsFocus` (3.5), `aFocusStateReadsTheWindowsFocusAfterEveryMover` (3.8) (6 issues) |
| MRl | `ListRows.requestGroupLayout`'s `noteWindowedParent(parent)` call dropped | `aConditionalInAWindowedListRowIsNotResetByAnExcursion`, D13 (the instrument arm), 3.6 `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `aSurvivingForEachElementsListKeepsItsWindowedRowsState`, `aLoopInsideAWindowedListRowKeepsItsStateWhileTheRowIsOut` (2 issues), `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (7 issues total) |
| M3a | `applyPendingFocusStateWrites`'s `lastFocusRegistry.isFocusable(target)` check dropped | 3.7 `aFocusStateWriteFromInputMovesFocusOnTheNextFrame` (2 issues), 3.11 `aFocusStateWriteNamingADisabledElementFocusesNothing` (2 issues) — the same code location answers M3e too (below), so one run pins both |
| M3b | the `reconcileFocusStates()` call at the frame boundary dropped entirely | every `FocusStateTests` case that reads a state back after a mover: 3.7–3.12, 3.20 (16 issues) |
| M3c | `applyPendingFocusStateWrites`'s clear branch made unconditional (`focusedElement = nil` whatever slot holds it) | 3.9 `writingFalseOrNilClearsFocusOnlyIfItsElementHoldsIt` (3 issues) |
| M3d | `.focused(_:)` also sets `$0.isFocusable = true` | 3.10 `focusedDoesNotMakeAnElementFocusable` (6 issues) |
| M3e | same location as M3a (`applyPendingFocusStateWrites`'s `isFocusable` check is the one gate a disabled element's focus-state write must pass) | 3.11, confirmed together with M3a's own run — no separate mutation exists to write |
| M3f | `FocusState.Box.reconcile`'s change guard dropped, writes every frame | 3.12 `aFocusStateNeverWritesFromAPhase` (4 issues) |
| M3g | `Frame.registerHandlers`'s `if keyboardVisible { register } else { registerShortcut }` collapsed to an unconditional `register` | 3.13 `aHiddenFocusableElementCannotTakeFocusOrKeys`, all three arms (6 issues), plus the `AccessibilityTreeTests` focus control (1 issue) |
| M3g′ | `ModifiedContent.prepaintLayer`'s own `disablingHitTestingIfHidden` wrapping dropped (its copy only, `ElementGroup.swift`'s left intact) | 3.13's arm 3 only (2 issues), plus the existing `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer` (2 issues) — sharing the one call site's *pointer* half too, as the source doc's "both scopes" note predicts |
| M3h | `dispatchClick` focuses a focusable target before checking whether it is the pressed one | 3.14 `clickingAFocusableElementDoesNotFocusIt`, plus the existing `aButtonIsFocusableButAClickDoesNotFocusIt` and `reEnablingRestoresClicksButNotFocus` (3 issues) |
| M3m | `AnyElementBox.requestLayout`'s `StateBinder.bind` call dropped (the `prepaint`/`paint` copies alone do not seed a `FocusState` box — its `table`/`slotID` must be set once, at `requestLayout`) | 3.20 `aFocusStateSurvivesInsideAComponentAndAnAnyElement`, plus three existing `ID-E` tests (`anEnvironmentPropertyInsideAnyElementReadsItsScope`, `stateInsideAnAnyElementPersistsAcrossFrames`, `stateInsideAnAnyElementIsReboundForPrepaintAndPaint`) (5 issues) |
| M3n | `Frame.registerHandlers`'s hidden `else { registerShortcut }` branch dropped | 3.14b `aHiddenButtonsShortcutStillFires` (2 issues) |
| G3.1 | `.focused(_:)` made internal | `theFocusStateSpellingsCompileFromAPlainImport` (1 issue) |

Every mutation reddened the test or tests it was designed for; none reddened
nothing, and every reddened test outside the target is a pre-existing test
of the same fact (never a false positive elsewhere in the suite).
`Sources/MetalUI/StateTable.swift`'s own doc comment at `isWindowRetained`
is corrected in this same commit to name all six tests `MRk′` reddens
rather than the narrower "3.1–3.5" the verifier round's first pass wrote (a
minor leftover the verify pass caught: the mutation's true reddened set is
six tests, one of them 3.8, not five consecutive-numbered ones).

**Windows stack budget**: `MemoryLayout<Handlers>.size` 432 → **440**
(`focusBinding`, one reference); smallest thread building every production
tree 608 → **624 KB**. Still well inside the 1 MB Windows thread;
`everyProductionTreeBuildsOnAOneMegabyteThread` green.

**Retirement rows** (the `goldensUnchanged` field): `C2.13`
`focusOutlivesARenameAndAnIfUntilItsElementReturns` retired, replaced by 3.1
and 3.2; `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
renamed 3.2, its focus clause inverted (T row); C2.8 renamed
`aResetKeepsTheAccessibilitySlotButNotFocus`, its focus clause inverted
(3.3); C2.12 renamed `aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh`,
its focus clause inverted (3.4); `hiddenContentIsNotPublishedButA…`'s focus
control re-derived, keeping its name (T row, `IX-K` item 3). No other test
changed its answer.

## §6 Record phase close (2026-09-29)

All three lanes verified `ok: true`. This section is an independent
re-take of the suite, guard and golden counts, the pixel comparison,
`Backends/SDL`, a `swift:6.4-noble` container, `Tests/PortableTests`, and
the one leftover the verifier round's minor finding named.

**Suite**, from a clean tree (`swift package clean` — `Handlers` gained
`gestures`, `keyboardShortcut`, `contentShape` and `focusBinding` across the
three lanes, a public type crossing the test-module boundary): `swift build
--build-system native --build-tests` → 0 `error:`, the one SwiftPM
deprecation `warning:`; `swift build --build-tests` (default build system)
→ 0 `error:`, 0 `warning:`. Unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1837 tests in 3 suites passed after
113.205 seconds`**, one summary line, the `FR-J no-argument frame:
succeeded=true` line present (guards ran). **1837 = 1773 + 30 + 22 + 12**:
lane 1 (23 tests + 1.24–1.28 + 2 guards = 30), lane 2 (18 tests + 2.16b/2.4b
+ 2 guards = 22), lane 3 (12 new/net-changed rows + G3.1 = 12; net +11 over
C2.13's retirement, +1 guard) — matching each lane's own close, re-verified
rather than re-derived. `goldensUnchanged` for the whole part: 0 goldens
throughout (`find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0);
one test retired (C2.13, replaced by 3.1/3.2, both rows above); three tests
renamed with an inverted answer, each a T row naming its ruling
(`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow` → 3.2;
C2.8 → 3.3; C2.12 → 3.4); one test's focus control re-derived, name
unchanged (`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`).
No other `@Test` was added, removed or changed its answer beyond the three
lanes' own tables. `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS` and
`theSevenRetentionSlotsAreMutuallyDistinct` all green. `MetalUILayout`
imports only `MetalUICore` (one line); `MetalUIScene` imports only
`MetalUIShaderTypes` (one line).

**Guards**: `grep -c canTypecheck` across every guard file CLAUDE.md names
(31 files including the three this task adds, plus
`Tests/MetalUICoreTests/UnitSafetyTests.swift`) reads 114 raw hits, less
`UnitSafetyTests`'s one comment hit = **113**. New this task: `GestureCompileGuards`
(2, both whole-file `typecheckFile`), `ButtonCompileGuards` (1, whole-file
`typecheckFile`), `FocusStateCompileGuards` (1, whole-file `typecheckFile`);
`DecorationCompileGuards` gains one `@Test` (G2.2, whole-file
`typecheckFile`) in place, no new file. **113 = 108 + 2 (lane 1) + 2 (lane
2: G2.1 + DecorationCompileGuards' G2.2) + 1 (lane 3)**, matching every
lane's own close. The `typecheckFile`-based helper count moves **69 → 74**
(GestureCompileGuards' 2, ButtonCompileGuards' 1, DecorationCompileGuards'
1, FocusStateCompileGuards' 1 — every guard this task added uses
`typecheckFile`, none `typecheck`); the `typecheck`-based helper count stays
**39**; 39 + 74 = 113.

**The remaining lane-3 mutations, applied at this close** (owed by `IX-T`,
full table in §5.2): `MRl`, `M3a`–`M3h` (`M3e` sharing `M3a`'s location),
`M3m`, `M3n` and the guard `G3.1` — twelve mutations, each applied on
`f77756f`, restored from a copy, the whole suite run unfiltered, `git status
--short` empty after every one — plus `MD1`, `MD2` (already pinned by
`96d5874`, re-verified here) and `MRk′` (six tests). Every one reddened
exactly the test or tests its clause names, and nothing else. This closes
every item `IX-T` left "still owed" but the fourteen-image offscreen
comparison and the `Backends/SDL` build, both also taken in this section
(above). `Sources/MetalUI/StateTable.swift`'s doc comment at
`isWindowRetained` is corrected to name the six tests `MRk′` actually
reddens (§5.2) rather than the narrower five-test range a first pass had
written — the one minor finding the verifier round returned, now closed;
`ok: true` stood already, and this closes its sole leftover.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 31f2e7a HEAD` —
controls exactly as recorded since stage 9 (light vs dark 1048576, default
vs modal 1031003, default vs animation 454895, f0 vs f3 0, chrome pair 0,
distinct 544 and 216, prod default vs modal 491221, prod distinct 529,
indicator rects 0); **0 differing pixels, scene identical, in all fourteen
images**, independently re-taken against the branch's own base and tip.
This matches the spec's own prediction (§7): no gesture, `Button`, control,
`.focused` binding or `contentShape` is in the demo tree, and the one
`.focusable()` panel is never inside a conditional that goes false in the
fourteen captured states.

**`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`): `swift build
--build-tests` → 0 `error:` (the `sdl` pkg-config rpath warning and the
SDL3-dylib version notice are the machine's, unrelated to this task — the
same on an unmodified checkout). `swift test --skip-build` → **`Test run
with 22 tests in 0 suites passed`** then **`Test run with 26 tests in 0
suites passed`** — **22 + 26**, matching CLAUDE.md's own merge entry for
`0714528` (record §61 §9: `SDLMainRunLoopTests`, the run-loop fix
(`SDLPlatform` now runs `NSApp.run()` once), landed at the merge itself, so
the branch's base `31f2e7a` already carries it — record §61's own body text
("22 + 25") describes the branch *before* that merge fix, not this task's
base. No lane of this task touches any file under `Backends/SDL`
(`git diff --stat 31f2e7a HEAD -- Backends/SDL` is empty); **22 + 26 is
this task's own unmoved baseline**, exactly as CLAUDE.md already records
it.

**A `swift:6.4-noble` (aarch64) container** (`docker run --rm -v "$PWD":/work
-w /work swift:6.4-noble …`): the root package builds with 0
`error:`/`warning:` and runs `MetalUILayoutTests` **199**,
`MetalUICrossPlatformTests` **10**, `MetalUICoreTests` **22** — **199 + 10 +
22**, unmoved since record §61 (no lane of this task touches a portable
target — `MetalUILayout`, `MetalUIScene`, `MetalUICore`, `MetalUICrossPlatformTests`
all imports read as before). `Tests/PortableTests` (a separate package, run
on macOS): `swift test` → **`Test run with 21 tests in 7 suites passed`**,
**`Test run with 6 tests in 1 suite passed`**, **`Test run with 5 tests in 1
suite passed`** — **21 + 6 + 5**, unaffected (no `MetalUIPortableText`/
`MetalUITextSystem`/`MetalUIFreeType`/`MetalUIHarfBuzz` source touched by
any of the three lanes).

**Real window**: lock probe at this close, well after 12:00 PDT —
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — locked at every
check across design, the critic round and all three lanes, and now at this
close too; the real-window capture stays owed, joining (not reopening or
closing) the still-open items from every prior task since stage 6b. This
task adds a long list of its own looks to that debt (§8 below).

**`_reserved` and other pre-existing greps unaffected**: this task touches
no renderer primitive, no `Style` field and no proposal-kernel case, so
none of record §61's or earlier stages' recorded greps move.

## §7 The audit, disposed (spec §2, `IX-A`)

Of the 38 rows the design's audit table collected:

- **19 built or fixed this run** (rows 1, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14,
  15, 16, 17, 18, 18b, 19, 21, 22 — see §1's short list above for what each
  is).
- **8 not offered, owner none** (rows 2, 3, 6, 20, 24, 25, 26 and half of
  row 24 — a public tap-with-modifiers, `sequenced`/`@GestureState`/
  `GestureMask`/custom `body` gestures, `ButtonStyle`/`PrimitiveButtonStyle`
  protocols and `.borderedProminent`/`.link`, `contentShape(kind:)`/`eoFill`,
  menus/`.contextMenu`/`.pickerStyle(.menu)`/divergence 81, `ToggleStyle`
  variants, proposal-path focus).
- **1 row (23) an amendment with owner none**: a shape's default hit region
  is its frame (divergence 41, amended).
- **11 rows (27–37) are part 2**: the VoiceOver script (a human); settable
  `AXSelected`/divergence 83; `accessibilityElement(children:)` and the rest
  of the `AB-` table; the `AB-H` press question/divergence 28; modal
  isolation and press occlusion; divergence 32 (accessibility scrolling);
  divergence 82; `AB-Q` proposal-path accessibility; an `onTap` control's
  and an image's VoiceOver presence; `AXNode.actions`'s inert row; the
  `DD-` rulings' costs contingent on task 12's VoiceOver validation.
- **1 row (38) needs no owner**: `controlSize`'s consumers were already
  delivered by tasks 10 and 11.

Nothing on this list is left unclassified.

## §8 Divergences, declared-but-inert, and human looks (for CLAUDE.md and records 03/04/05)

**Divergences** (record §04's own dated section, added by this task):
**94 added** (click never focuses a `.focusable()` view — a policy decision,
kept, `IX-K` item 2); **80 amended** (Full Keyboard Access, now measured —
F5, F6 — rather than merely carried from the text-page merge); **43
amended** (`clipShape`'s hit behaviour — the clip rect intersects, `IX-L`
item 2); **41 amended** (a shape's default hit region is its frame); **57
pinned, owner none** (a non-clickable primary passing a click through to
its background, previously unpinned, now pinned by 2.18); **81 re-owned**
(menus, still no number, still no owner); **21 and 22 re-owned, kept**
(focus retention on disable; raw keys on a disabled ancestor — both decided
as MetalUI's own choice, owner none). Live **68 → 69**, next label **95**.
`ID-R` item 9's unnumbered difference is **closed** (fixed to SwiftUI's
answer, `IX-I`), not numbered — it never reaches a live-count row.

**Declared but inert** (record §05's own dated section): `EnvironmentValues.controlActiveState`'s
row is **deleted** — the disabled and inactive looks now read it (`IX-H`);
`PaintPass.isActive`'s row is **deleted** — the pressed look now reads it
(`IX-E` item 3, pinned by 2.3); `ButtonRole`'s row is **added** — it
compiles, binds a key correctly (`.cancel` → Escape), and changes nothing
else drawn (`IX-E` item 1, "role reads nothing" beyond the shortcut — an
inert row by design, not a gap); the `hidden()`-on-focusable hazard
(`focusable()`'s doc comment, record §05's earlier row) is **deleted** — a
hidden focusable element can no longer take focus or keys (`IX-K` item 3).

**Human looks owed** (record §03's own dated section): gestures on a
trackpad (tap slop, double-tap timing, long press) against Finder/SwiftUI;
the pressed, disabled and inactive looks and the focus ring beside a native
SwiftUI window; a real key window's accent and ring behaviour (`PX23`
always read "inactive" in this synthesized harness). None of this reopens
or closes the still-owed real-window capture from stage 6b onward, or task
9's two looks, task 10 part 1's wheel-under-`.disabled` look, task 10 part
2's controls-demo and accessibility looks, or task 11 part 1/2's paragraph
look and drawn-`controlSize` look — all stay owed, unioned with this task's
own additions.

## §9 Deferred, with owners

- **A public tap-with-modifiers, `sequenced(before:)`, `@GestureState`,
  `GestureMask`, custom `body` gestures, location taps** — owner none
  (`IX-B`); `Gesture`'s SPI requirement keeps the door shut until one of
  these is designed.
- **`ButtonStyle`/`PrimitiveButtonStyle` as open protocols,
  `.borderedProminent`, `.link`** — owner none (`IX-E` item 2); `ButtonStyle`
  stays a closed value type, `PickerStyle`'s precedent.
- **`contentShape(kind:)`, `eoFill`** — owner none (`IX-L` item 1).
- **Menus, `.contextMenu`, `.pickerStyle(.menu)`, divergence 81** — owner
  none (`IX-M`); not built, not numbered further than the existing
  re-owning.
- **`ToggleStyle` variants, proposal-path focus** — owner none (`IX-M`).
- **Part 2 (the accessibility half)**: `AXSelected`/divergence 83,
  `accessibilityElement(children:)`, the `AB-H` press question/divergence
  28, modal isolation and press occlusion, divergence 32, divergence 82,
  `AB-Q` proposal-path accessibility, an `onTap`/image's VoiceOver presence,
  `AXNode.actions`, and the human VoiceOver script itself — none of this is
  begun by this branch (spec §2, rows 27–37).
- **Lane 1's remaining test-coverage notes carried from prior tasks'
  practice** (none blocking, `ok: true` throughout): none new this task —
  every clause lane 1 stated is pinned by a test (`IX-P` item "cost if
  wrong").

## §10 CLAUDE.md, plan and record updates made alongside this record

See the commit that carries this file for the full diff. In short: CLAUDE.md
gains the `IX-` prefix (lettered, next `IX-U`) in the ruling-id list; a
record-map line for `docs/record/62-interaction.md`; the counts entry below;
"Hit testing" gains the gesture arena and `contentShape(_:)` taking a
`Shape`; a new "Gestures" paragraph describes the arena, the tick advance
and the withheld-member rule; "Focus" gains `@FocusState`/`.focused`, the
identity-rename fix and its migration note, and the hidden-keyboard-only
gate; "Environment" notes `controlActiveState` now has consumers;
"StyledElement" corrects `Handlers`'s member count 10 → 14 (`gestures`,
`keyboardShortcut`, `contentShape`, `focusBinding`); the guard list gains
`GestureCompileGuards`, `ButtonCompileGuards`, `FocusStateCompileGuards`.
`docs/record/04-divergences.md`, `05-declared-but-inert.md` and
`03-verified-on-real-hardware.md` each gain a dated 2026-09-29 section (§8
above is their content). `docs/record/README.md` gains a row for this file.
The plan's task 12 entry gains a dated progress note (part 1 delivered,
part 2's items named, the VoiceOver run still needing a human); its box
stays unticked.

## §11 Counts (final, this task)

**1837 tests, 0 goldens, 113 typecheck guards**, 0 `error:` on both build
systems, the one `warning:` SwiftPM's deprecation notice under native (0
under the default one). `1837 = 1773 + 30 + 22 + 12` (lane totals above).
`Backends/SDL` **22 + 26** on macOS (unmoved by this task; CLAUDE.md's own
merge-entry figure for `31f2e7a`, §6). A `swift:6.4-noble`
container: root package 0 `error:`/`warning:`, runs **199 + 10 + 22**;
`Tests/PortableTests` **21 + 6 + 5**. 0 px against `31f2e7a` in all fourteen
offscreen images. Windows stack budget: `MemoryLayout<Handlers>.size` 408 →
440 across the three lanes; smallest thread building every production tree
592 → 624 KB, well inside 1 MB. Live divergences **68 → 69**, next label
**95**. Task 12's box: **unticked** — part 2 (the accessibility half) and
the human VoiceOver run remain.

## §12 Adversarial branch check (2026-09-29, `31f2e7a..dcbcb73`)

Independent of every lane and of §6. **Verdict: merge.** No code defect found.

- **Suite**, after `swift package clean`: `swift build --build-system native
  --build-tests` → 0 `error:`, the one SwiftPM deprecation `warning:`;
  `swift build --build-tests` (default) → 0 `error:`, 0 `warning:`. Unfiltered
  `swift test --build-system native --no-parallel` → **`Test run with 1837
  tests in 3 suites passed after 113.741 seconds`**, `FR-J no-argument frame:
  succeeded=true` present. `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` (`Expected.swift` untouched by
  the branch) and `theSevenRetentionSlotsAreMutuallyDistinct` passed.
- **Goldens 0, guards 113** (114 raw `canTypecheck` hits less
  `UnitSafetyTests`' comment). `cmp CLAUDE.md AGENTS.md` identical.
  `MetalUILayout` imports only `MetalUICore`.
- **Citations**: all 115 backticked identifiers of 26+ characters added to the
  record, the decisions doc, the spec, CLAUDE.md and records 03/04/05 resolve
  in `Tests/`, `Sources/` or `Backends/SDL/Tests`; every `IX-` id cited
  resolves (`IX-A`…`IX-T`; `IX-U` appears only as the next-unused label,
  `IX-3` only in CLAUDE.md's typo-sweep list).
- **Removed `@Test`s**: four names leave the tree, each with a row — C2.13
  retired (§5), and three renamed with the focus clause inverted, each naming
  `IX-I` (`focusDropsWhenAnIfRemovesItsElement`,
  `aResetKeepsTheAccessibilitySlotButNotFocus`,
  `aFocusedTextFieldInsideAToggledIfLosesFocusAndStartsFresh`). The other
  pre-existing test edits (`ModifierTests`/`OuterModifierMatrixTests`
  fingerprints gaining fields, the `AccessibilityTreeTests` focus control, D13's
  re-derivation) are the rows §4–§6 name; no other retained assertion changed.
- **One hit ranking**: `topmostOpaqueHitbox(in:at:)` is the only ranking
  (`Hitbox.swift`); the arena's ancestor membership, wheel routing and the
  ranking all test a point through the one `Hitbox.contains`.
- **Mutation A** (`Hitbox.contains` ignores the shape — M3i re-run on
  `dcbcb73`, restored from a copy): 1837 tests, 13 issues, reddening
  `aCircularContentShapeRefusesTheCornerAndTakesTheCentre`,
  `aContentShapeWrittenAfterAProposalTapShapesItsHit`,
  `hoverActiveAndTheGestureArenaFollowTheContentShape` **and**
  `aContentShapeInsideAScrolledScrollerFollowsTheScroll` (2.16b) — the M3i row
  in §4 was taken before 2.16b existed and names three; on this tip it reddens
  four.
- **Mutation B** (new: the target's `onClick` leaf placed **ahead** of the
  high-priority members in `GestureArena.init`, `IX-D` item 3): 1837 tests,
  3 issues, reddening `anOuterHighPriorityGestureBeatsTheInnerOneAndAButton`
  (1.14, its H8 arm) and `anOverflowingChildsPressOutsideItsAncestorLeavesTheAncestorOut`
  (1.25). `git status --short` clean after each restore.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 31f2e7a HEAD` —
  controls as recorded (light/dark 1048576, preview 1048576, f0/f3 0, chrome
  pair 0, distinct 544/216), **0 differing, scene identical in all fourteen**.
- **Real window**: lock probe read `CGSSessionScreenIsLocked = 1`,
  `displayAsleep main: 1`; `capture.sh` not run — still owed.
- **`Backends/SDL`** (`PKG_CONFIG_PATH=Backends/SDL/.accesskit`): 22 + 26
  passed, 0 `error:`. **`swift:6.4-noble`** (aarch64, `git archive HEAD`): 0
  `error:`/`warning:`, `MetalUILayoutTests`/`MetalUICrossPlatformTests`/
  `MetalUICoreTests` **199 + 10 + 22**.
- **Audit and plan**: spec §2's 38 rows each carry an arm or "unmeasured", a
  verdict and an owner; every SwiftUI claim cites a `swiftui-interaction.swift`
  (or `swiftui-gesture-presentation-arena.swift`, `swiftui-disabled-interaction.swift`)
  arm, the probe's header listing its locked-screen blind spots as unmeasured.
  Task 12's box is **unticked** with a dated 2026-09-29 progress note naming
  part 2 and the human VoiceOver run.
