# Interaction — decisions (plan task 12, part 1)

Rulings for plan task 12's **interaction half** — gesture composition, button
semantics, disabled behaviour and looks, keyboard focus, pointer hit testing
and content shapes. Spec:
[`specs/2026-09-29-interaction-design.md`](specs/2026-09-29-interaction-design.md).
Evidence: [`../probes/swiftui-interaction.swift`](../probes/swiftui-interaction.swift)
(new; arm ids `G…`, `H…`, `B…`, `PX…`, `F…`, `C…`, and the critic round's
`X1`–`X4` (`IX-O`); its header carries the recorded output), and two existing probes **re-run this session**, compiled,
reading their recorded values: `swiftui-disabled-interaction.swift` (P, K, R)
and `swiftui-disabled-ancestor-and-order.swift` (N, O), and
`swiftui-content-shape-hit-region.swift` (H, P, N, X). Record:
`docs/record/62-interaction.md` (written by the Record phase).

Prefix **`IX-`**, lettered. **Next unused: `IX-Q`.** (This line moves in the
commit that appends a ruling; read the last `## IX-` heading.)

The probes ran with the screen **locked** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). The synthesized click
and key harness (`FirstMouseHost`, a run-loop spin between down and up) works
locked — every positive control passes (`G0`, `K0`, `C0`, `PX0`). What the
harness cannot see is recorded as **unmeasured** below, and each such rule is
stated as MetalUI's choice, never as SwiftUI's: label and text ink (the
offscreen capture draws no text — `PX11`, a bare `Text`, reads pure white, so
every `PX` ink column is blind), the bordered bezel and its pressed and
disabled looks (`PX1`, `PX2`, `PX21`), the focus ring (`F7` = `F8`), and a real
key window (the process is never the active application: `PX23` reads
`inactive`).

---

## IX-A — scope: the collection, part 1 and part 2, and the tick

**Ruling.** Every item addressed to "plan task 12"/"task 12" in the records,
decisions docs, specs, plan and `Sources/`/`Tests/` comments (grep of
2026-09-29, 110 hits outside the frozen §19) is disposed of in spec §2's audit
table: **this run** (built or ruled here), **part 2** (plan task 12's
accessibility half: the VoiceOver script, which needs a human; `AXSelected`
setting, divergence 83; `accessibilityElement(children:)` and the other
accessibility modifiers `AB-`'s table sends here; `AB-H`'s press question,
divergence 28; divergence 32 and scrolling to unrealised rows; divergence 82;
`AB-Q`'s proposal-path accessibility; an `onTap` control's and an image's
VoiceOver presence, `TE-O`; modal isolation and press occlusion, `AB-H`'s
"not checked"; `AXNode.actions`' inert row), or a **ruled owner** (named,
usually **none** for additive API no clause of the task's text requires).

**Plan task 12's box stays unticked** after this run: part 2 and the human
VoiceOver run remain. The Record phase writes a dated progress note.

**Why the accessibility half is part 2's and not this run's.** The plan's task
text is two sentences: "Specify gesture composition, button semantics, disabled
behaviour, keyboard focus, pointer hit testing and content shapes" (this run)
and "Deliver the missing native accessibility bridge and validate it with
VoiceOver" (part 2). The second needs a human at an unlocked screen; nothing an
agent does closes it.

**Cost if wrong.** An item assigned to part 2 that is really interaction stays
open one run longer; the table names each so it cannot be lost.

---

## IX-B — gestures: SwiftUI's spellings, a closed recognizer set

**Ruling.** MetalUI gains SwiftUI's gesture surface, spelled as SwiftUI spells
it (the SDK's `SwiftUICore`/`SwiftUI` interfaces, read this session):

- `TapGesture(count: Int = 1)`, `LongPressGesture(minimumDuration: Double =
  0.5, maximumDistance: Pixels = 10)`, `DragGesture(minimumDistance: Pixels =
  10)` with `DragGesture.Value` (`startLocation`, `location`: `Point<Pixels>`;
  `translation`: `Size<Pixels>`), each with `onEnded(_:)` and (tap excepted)
  `onChanged(_:)`;
- `exclusively(before:)` and `simultaneously(with:)`;
- attachment: `gesture(_:)`, `simultaneousGesture(_:)`, `highPriorityGesture(_:)`,
  `onTapGesture(count:perform:)`, `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`,
  on every `StyledElement` (returning `Self`, appending — never replacing) and,
  on the proposal path, on every `ProposalElementGroup` (returning a
  `GestureModifier<Self>` wrapper built exactly as `OnTapModifier` is).

**`Gesture` is a public protocol an outside module cannot conform to**: its one
requirement produces an internal recognizer description. SwiftUI lets a caller
compose a custom gesture through `body`; MetalUI does not (owner **none**,
additive). **Not offered** (owner **none**, additive, no clause of the task's
text requires them): `sequenced(before:)`, `@GestureState`/`updating(_:body:)`,
`GestureMask`/`including:`, `isEnabled:`/`name:` attachment overloads,
`TapGesture` with a location (`onTapGesture(count:coordinateSpace:perform:)`
taking a point), `coordinateSpace:` (every value is in the gesture's
element's local space, SwiftUI's default `.local`), `SpatialTapGesture`,
`MagnifyGesture`/`RotateGesture` (no platform delivers them), and
`TapGesture().modifiers(_:)` — the public tap-with-modifiers `DD-Z` item 9 sent
here stays internal (`ClickDispatch`).

`onEnded`/`onChanged` return the gesture's own type with the callback stored,
not SwiftUI's `_EndedGesture`/`_ChangedGesture` wrappers: the spelling is
identical; only a caller naming the wrapper type sees the difference.

**`onClick` stays**, unchanged and undeprecated — see `IX-D`.

**Evidence.** SDK interfaces (`TapGesture.init(count:)`, `LongPressGesture.init(minimumDuration:maximumDistance:)`,
`DragGesture.init(minimumDistance:coordinateSpace:)`, the three attachment
modifiers with `including:`); probe arms G, H.

**Cost if wrong.** A missing combinator is additive; the closed protocol can be
opened later without breaking a caller.

---

## IX-C — how each gesture recognizes (measured)

**Ruling.** Each rule is the probe's answer; the numbers are MetalUI's where the
probe gives a bracket.

1. **Tap.** Ends on the **release**, never the press (`G1`: `|down,tap`). It
   **fails once the pointer moves 5 pt or more** from the press (`G2g`: 2, 3,
   4 pt pass; `G2b`: 5 pt fails; `G2a`, `G2c`, `G2d`: any larger move fails,
   including out-and-back). A release outside its element has moved, so it
   fails too.
2. **Tap count.** `TapGesture(count: n)` ends on the release whose platform
   `clickCount` is `n` (`G3b`); a single click does not end a count-2 tap
   (`G3a`). A pending tap sequence expires `IX-C`'s deferral (item 3) after its
   last release with no further press.
3. **A tap that a larger-count tap could still pre-empt waits.** A count-1 tap
   sharing an arena with a count-2 tap does not end at its release: it ends
   when the count-2 tap fails — **at the first frame tick at least 0.33 s after
   the release** (`G5e`: fired between 0.31 and 0.35 s; `G5d`: between 0.25 and
   0.45 s; `NSEvent.doubleClickInterval` read 0.5, so it is **not** that
   value) — and it is cancelled if the count-2 tap ends. This holds **whichever
   is attached inner** (`G4a`/`G4b` and `G5a`/`G5b` agree: a double click runs
   only the double) and inside `exclusively(before:)` (`H15a`, `H15b`).
4. **Long press.** Ends **while still held**, at the first frame tick at least
   `minimumDuration` after the press (`G6a`: `long,|held`); a quick click ends
   nothing (`G6b`); it fails once the pointer moves `maximumDistance` (10 pt)
   or more (`G6c`, 30 pt, fails; `G6d`, 5 pt, ends). `onLongPressGesture`'s
   `onPressingChanged` reports `true` at the press and `false` at the release
   or failure, and `perform` runs at the duration (`G6e`:
   `pressing=true,perform,|held,pressing=false`; `G6f`: `pressing=true,pressing=false`).
   **The press is stamped at the first tick after it** — `MouseEvent` carries
   no timestamp. (*Corrected by `IX-O`*: `ScrollEvent` does carry one, so a
   `MouseEvent.timestamp` with a defaulted initialiser parameter would be
   source-compatible; it is declined because both backends' mouse paths would
   have to fill it for it to mean anything, and the tick stamp's error is at
   most one frame, inside `G5e`'s own 0.31–0.35 s bracket.) The window keeps
   requesting frames only while a long press or a deferred tap is pending.
   Every duration in this ruling (the 0.33 s deferral, `minimumDuration`) is
   measured from that **stamp tick**, not from the event, and the tests state
   their tick times relative to it.
5. **Drag.** Reports `onChanged` from the first move whose distance from the
   press is **at least** `minimumDistance` (`G8a`: the first change is
   `(10,0)`), then on every move; `onEnded` at the release **wherever it lands,
   window edge included** (`G8f`). A drag that never reaches its minimum reports
   nothing (`G8c`, 6 pt; `G8d`, a click); `minimumDistance: 0` reports a change
   and an end for a click (`G8e`). Values are in the element's **local** space,
   **y down** (`G8b`: an upward drag reads `(0,-50)`), `startLocation` the
   press point (`(100,100)` at a 200×200 element's centre).

**Evidence.** Arms G1–G9 (G2e/G2f/G2g and G5d/G5e added to bracket items 1 and
3), H15, H16; the harness's `G0` control.

**Cost if wrong.** A slop or deferral constant is one literal each, pinned by a
named test; nothing else moves.

---

## IX-D — composition: one arena per press, from the ONE ranking

**Ruling.**

1. **The arena.** At a `mouseDown`, `topmostOpaqueHitbox(in:at:)` — the one
   ranking, unchanged — picks the target, as today. The arena is the target's
   recognizers followed by its **ancestors'** gesture recognizers: every hitbox
   in `lastHitboxes` whose `GlobalElementID` is a proper ancestor of the
   target's id and whose region contains the point (`Hitbox.contains(_:)`, one
   helper that `topmostOpaqueHitbox` also calls). The ancestry comes from the
   id itself, as `focusChain(from:)`'s does — no parent link, no second list,
   no second ranking.
2. **`onClick` keeps Button semantics and joins only on the target.** It fires
   on press-and-release on the same element with any excursion between
   (unchanged; SwiftUI's `Button`, `B1`), where SwiftUI's `onTapGesture` fails
   on any move (`G2d`) — so `onClick` is **not** `onTapGesture` and its doc
   comment stops saying so. The target's `onClick` is the arena's innermost
   normal-priority member; **an ancestor's `onClick` never joins** — a
   parent's `onClick` still never sees a press whose target is a child, exactly
   as today. With no gesture anywhere in the arena, dispatch is exactly today's
   `dispatchClick`.
3. **Exclusive order.** High-priority members first (outermost first), then
   normal members innermost first; on one element, declaration order is inner
   to outer (a later modifier is an outer layer, as a parent is — `H12`–`H14`
   read exactly as `H1`–`H3`). A member may **end** only when every exclusive
   member ahead of it has **failed**; when one ends, every exclusive member
   behind it is cancelled. So: an inner tap beats a parent's (`H0`, `H1`,
   `H12`); a parent's high-priority tap beats the child (`H2`, `H8`, `H11`,
   `H14`); a child drag that fails hands a click to the parent's tap (`H4a`),
   one that ends keeps it (`H4b`); a child tap that fails by moving hands the
   drag to the parent (`H5b`, `H6b`); a parent's high-priority drag that fails
   at the release lets the child's tap end (`H6a`); an inner tap beats an outer
   long press even when held (`G7b`: `|held,tap`), and an inner tap beats an
   outer drag on a click (`G9a`) and loses it on a drag (`G9b`).
   **A member behind a pending one neither ends nor reports a change** (*added
   by `IX-O`*, arm `X4`: a parent `.gesture(DragGesture())` over a child
   `.plain` `Button`, dragged 30 pt inside the child, logs `button` and no
   `chg`). So the target's `onClick` — which does not fail on a move (`B1`) —
   holds a parent's normal drag off for the whole press and wins it at a
   release inside (`X3`, `X4`); the parent's drag reports nothing. **MetalUI's
   choice, unmeasured**: when the member ahead fails only **at the release**
   (an `onClick` released outside its element), a drag behind it whose changes
   were withheld is cancelled with no callback — it never activated during the
   press — while a tap behind it ends on that release as `H6a` measured for a
   failed high-priority drag. `onPressingChanged` of a withheld
   `onLongPressGesture` is withheld the same way (MetalUI's extension of `X4`;
   SwiftUI's is unmeasured).
4. **Simultaneous members** stand outside the exclusive order and end on their
   own; **when a simultaneous member and the exclusive winner end on the same
   event, the simultaneous one's callback runs first** (`H3`: `p,c`; `H7`:
   `p,button`; `H10`: `sim,button`; `H13`: `outer,inner`). `simultaneously(with:)`'s
   members are independent (`H16b`: `long,|held,tap`).
5. **Gates.** A gesture rides its element's hitbox: under `.disabled` or
   `allowsHitTesting(false)` it is gone with the hitbox, so a disabled child's
   parent receives the press (`H17`, re-measured `N1`/`N2`). Every callback runs
   under `StateDispatch.dispatching(to:)` its owner (`ID-F`), from input or a
   tick before the frame builds — never inside a phase.
6. **Claiming.** A `mouseUp` is claimed when some callback ran on it (today's
   rule for `onClick`); a `mouseDown`/`mouseDragged` is never claimed by the
   arena, so `Window.onInput` still sees them as today.
7. **Text fields and slider tracks keep their own dispatch, ahead of the
   arena** (`dispatchTextInput`, `dispatchValueTrack`), unchanged.

**Why not "every hitbox joins".** An ancestor's `onClick` joining would make a
press that leaves a child and releases elsewhere on the parent click the
parent — a behaviour change for every tree with nested `onClick`s and no
gesture at all. Restricting ancestors to the new API moves nothing that exists.

**Evidence.** Arms H0–H17, G7, G9; `swiftui-disabled-ancestor-and-order.swift`
N0–N4 re-run.

**Cost if wrong.** An ordering rule is one comparison in the arena, pinned by
the H tests; the one-ranking rule is guarded by `hoverActiveAndTheGestureArenaFollowTheContentShape`
(lane 2, spec 2.16), which reddens if hit regions are tested in two places.

---

## IX-E — `Button`: roles, three styles, a pressed look

**Ruling.**

1. **`ButtonRole`** — SwiftUI's struct with `.destructive`, `.cancel`,
   `.confirm`, `.close` (the macOS 27 SDK's four) — and `Button(_:role:action:)`,
   `Button(role:action:label:)`. **A role binds no key** (`B4c`: `.cancel`
   alone ignores Escape; `B4d`: `.destructive` alone ignores Return) and
   changes neither layout nor clicks (`B5`). SwiftUI's role **look** is
   unmeasured (the capture draws no text, `PX3`, `PX13`, `PX14`), and MetalUI's
   theme has no destructive colour, so **a role changes no pixel**: the role is
   stored and read by nothing — a declared-but-inert row (owner: part 2 for its
   accessibility reading; the look, owner **none** until a theme token exists).
2. **`.buttonStyle(_:)`** on `Button`, taking a closed `ButtonStyle` struct
   (`PickerStyle`'s precedent, `DD-V`): `.automatic` (= `.bordered`, today's
   chrome), `.bordered`, `.borderless`, `.plain`. `.borderless` and `.plain`
   draw the label alone at the label's size (BT1: both 17×16, the bare
   `Text("Go")`'s size, BT2); their difference in SwiftUI (a tint) is
   unmeasured, so MetalUI draws them identically. **Not offered** (owner
   **none**): `.borderedProminent` (needs a contrasting on-accent label colour
   the theme lacks), `.link`, the `ButtonStyle`/`PrimitiveButtonStyle`
   protocols and `configuration.isPressed` for custom styles.
   **The type name differs from SwiftUI's, ruled** (*added by `IX-O`*):
   SwiftUI's `ButtonStyle` is a protocol (with `PrimitiveButtonStyle` holding
   `.bordered`/`.plain` as `where Self ==` statics); MetalUI's is a closed
   struct. Every `.buttonStyle(.plain)` call site spells identically, but
   **adding the protocols later is a source break** for code that names the
   type (`let s: ButtonStyle = .plain`), not an additive change — the same
   break `DD-V`'s `PickerStyle` already carries. Migration spelling when that
   happens: the statics move to `PrimitiveButtonStyle where Self ==
   PlainButtonStyle` (SwiftUI's own shape), so a call site keeps compiling and
   a stored value is re-typed to the concrete style.
3. **Pressed** is SwiftUI's rule, measured: true from the press while the
   pointer is over the button, false while it is outside, true again on return,
   false at the release (`B0`–`B3`) — which is exactly `PaintPass.isActive(id)
   && PaintPass.isHovered(id)`, both already paint-only. The bordered chrome
   paints a `.textPrimary` wash at 12 % over its fill while pressed; `.plain`
   and `.borderless` paint their label at 60 % opacity. **The look is MetalUI's
   choice** (`PX21`/`PX22` are blind). `PaintPass.isActive`'s declared-but-inert
   row is deleted: `Button` is its first built-in reader.

**Evidence.** SDK `ButtonRole`; arms B0–B5, PX1–PX14, PX21–PX22; BT0–BT3 of
`swiftui-controls-and-selection.swift`.

**Cost if wrong.** A look is one decoration; a role's look is additive once a
token exists.

---

## IX-F — `.keyboardShortcut`: on `Button`, from the focus registry

**Ruling.**

1. **API**: `KeyEquivalent` (a character; `.return`, `.escape`, `.space`,
   `.tab`, `.delete`, `.deleteForward`, `.upArrow`, `.downArrow`,
   `.leftArrow`, `.rightArrow`, `.home`, `.end`, `.pageUp`, `.pageDown`,
   `.clear`; expressible by a character literal), `KeyboardShortcut` (`key`,
   `modifiers`; `.defaultAction` = Return, `.cancelAction` = Escape, both with
   no modifiers), `public typealias EventModifiers = Modifiers`, and on
   `Button`: `keyboardShortcut(_:modifiers:)` (default `.command`),
   `keyboardShortcut(_ shortcut: KeyboardShortcut)` and `keyboardShortcut(_:
   KeyboardShortcut?)`. **`EventModifiers` is narrower than SwiftUI's**
   (*ruled by `IX-O`*): it is `Modifiers` — `.shift`, `.control`, `.option`,
   `.command` — with no `.capsLock`, `.numericPad`, `.function` or `.all`,
   which no platform event MetalUI receives reports; adding them is additive
   (owner none). **Offered on `Button` only**: SwiftUI's is a `View`
   modifier that a non-button ignores (`B4k`); MetalUI's does not compile
   there (guard) — same behaviour, narrower surface. Its `localization:`
   overload is not offered (owner none).
2. **Matching.** The key compared with `charactersIgnoringModifiers`
   (lower-cased), the modifiers **exactly** (`B4e` fires on ⌘K; `B4f` plain K
   does not; `B4g` a `modifiers: []` shortcut fires on plain K).
3. **Focus is not needed** (`B4e`, `B4a`, `B4b`: no button focused). **The
   first button in tree order wins a shared shortcut** (`B4h`: `A`).
4. **Dispatch stage.** After the keymap, a focused field's editing keys and the
   raw `onKey` bubble; before Tab traversal. A focused element's handler claims
   the key first (`B4i`: the focused view's `onKeyPress` ran, the button did
   not). **The keymap ahead of the shortcut is MetalUI's choice** (a keymap
   binding is the app's declared intent, as a menu item's is); SwiftUI has no
   keymap to compare.
5. **Gates.** The shortcut rides `Handlers` into the focus registry, so the
   **one** disabled gate removes it (`B4l`, re-measured `K4`: a disabled button's
   shortcut is silent) and `allowsHitTesting(false)` does not (`swiftui-allows-hit-testing-side-effects`
   K1). An invisible (opacity 0) button's shortcut fires (`B4j`), and so does
   a **`.hidden()`** button's (*added by `IX-O`*, arm `X1`: `k`) — so `IX-K`
   item 3's hidden condition gates the keyboard **focus** half of the registry
   and never the shortcut table.
6. **A focused text field claims Return** (*added by `IX-O`*, arm `X2`: a
   focused `TextField` beside a `.defaultAction` button, Return →
   `submit`, and the button does not fire). MetalUI's order already gives
   this — a focused field's editing keys run before the shortcut stage, and
   `TextEditing` handles `\r` (a `TextField` submits, a `TextEditor` inserts a
   newline) — and it is pinned, not assumed. A printable shortcut with no
   command modifier is silent while a field is focused for the reason
   `Keymap` bindings are (the key arrives as `.textInput`, `TI-B`); a
   command-modified one fires.

**Evidence.** SDK `keyboardShortcut` overloads, `KeyboardShortcut`,
`KeyEquivalent`; arms B4a–B4l; K3/K4 re-run.

**Cost if wrong.** The dispatch stage is one line in `Window.onInput`, pinned by
two order tests.

---

## IX-G — disabled: two divergences kept, a disabled look

**Ruling.**

1. **Divergence 21 is kept** (a focused element that becomes disabled loses
   focus at once) and **divergence 22 is kept** (a disabled ancestor's raw
   `onKey` sees no key), owner **none**: re-measured this session, SwiftUI is
   unchanged (`K2`: focused before 1, after 1, `onKeyPress` after disabling 1
   while the view reads `isEnabled` 0; `K6`/`K8`: the disabled parent's handler
   runs). `EV-F`'s reasons stand: the disabled gate is MetalUI's one
   "out of the keyboard" rule, and `K2` delivers keys to a control that reports
   itself disabled while `K4` refuses its shortcut — SwiftUI disagrees with
   itself there.
2. **A disabled look** for the built-in controls — `Button` (every style),
   `Toggle`, `Slider`, `Stepper`, `Picker` — : under `isEnabled == false` the
   control paints its whole subtree inside one `PaintPass.opacity(0.5)` scope.
   SwiftUI's disabled look is **unmeasured** (`PX2`, `PX6`, `PX8`, `PX10`,
   `PX12` blind), so this is MetalUI's choice. `TextField`/`TextEditor` are
   **not** given the look (owner **none**: they are outside this run's
   must-not-move set, and their disabled behaviour is `EV-`'s, unchanged); a
   `Text` has no disabled look in either framework's API.

**Evidence.** `swiftui-disabled-interaction.swift` re-run (P, K, R identical to
its header); `EV-F`.

**Cost if wrong.** Re-owning 21/22 later is a gate change with its own pins
(`aFocusedElementThatBecomesDisabledLosesFocusAtOnce`,
`aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`); the look is one scope.

---

## IX-H — the inactive-window look and the controls' focus ring

**Ruling.**

1. **A control draws its accent only in the key window** (`EV-AE`'s consumer).
   Measured: SwiftUI's `.borderedProminent` button and an on `Toggle` paint
   accent blue with `controlActiveState` `.key` (`PX17`: (1,122,255); `PX19`:
   (6,126,255)) and **no** accent pixel with `.inactive` (`PX18`, `PX20`).
   `.active` (application active, window not key) is unmeasured — the process
   is never active — and MetalUI treats it as not key. So `Toggle`'s on
   indicator, `Slider`'s filled track and `Picker`'s selected segment/radio
   paint `.accent` when `controlActiveState == .key` and `.separator`
   otherwise. `List` selection and a field's text selection are **not**
   changed (owner **none**: unmeasured, and outside the controls this rule was
   measured on). Every offscreen harness and every fake window reads `.key`,
   so no existing pixel moves.
2. **A focused control draws a focus ring**: `Button`, `Toggle`, `Stepper`,
   `Picker` and `Slider` carry a 2-pt `focusBorder` (or paint the same ring
   where their chrome is painted by hand) in the item-1 accent colour.
   SwiftUI's ring is **unmeasured** (`F7` = `F8`, and with Full Keyboard
   Access off its controls cannot be focused at all, `F6`); MetalUI's controls
   are focusable (divergence 80), so without a ring keyboard focus is invisible.
   A disabled control is never focused (`EV-F`), so it never draws one.

**Evidence.** Arms PX15–PX20, PX23, F6–F8.

**Cost if wrong.** A token swap per control; the helper is one function.

---

## IX-I — focus leaves with its identity (`ID-R` item 9 fixed)

**Ruling.** **Focus is dropped when its element's identity goes away through an
evaluated reset** — a name an evaluated position departs (`ID-R`), content an
evaluated conditional removes (`ID-C`), a loop's dropped element (`DD-C`) —
and it does **not** come back when the identity returns. Measured: `F1` (a
focused `.id("a")` renamed `b`: `focused=false`; keys go nowhere; renamed back
to `a`: still unfocused) and `F2` (a focused view removed by an `if` and
returned: the same). Mechanism: the `$focus` retention slot is no longer
exempt from those resets (`$ax` stays exempt — accessibility is part 2's), and
the frame whose sweep deletes the focused element's `$focus` slot clears
`Window.focusedElement` **in that same frame** — so an input event between
frames never reaches a dead id.

**Unchanged, by design**: a subtree nothing evaluates keeps its retention — a
focused `List` row scrolled out of its window keeps focus and its `@State`
until `TB-AH`'s bound (`TB-J`); a focused element not produced for a frame with
no reset keeps the tombstone path (`resolveFocus`'s fallback to a live
`$focus` slot). **Named by `IX-O`, not left to the lane**:
`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
(`FocusTests`) removes its element with an `if` — an evaluated reset — so its
answer **inverts** (its own comment says the `$focus` exemption "is what keeps
this test's answer unchanged"); it is re-derived and renamed
`focusDropsWhenAnIfRemovesItsElement` (spec 3.2). The unevaluated half is
pinned by the existing `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`
(spec 3.6), unedited; `focusSetWithNoConfirmingFrameHasNothingToRetain` and
`focusSurvivesAFrameInWhichTheFocusedElementIsRebuilt` are unaffected.

**User-visible behaviour change, with a migration note**: a focused element
(a `TextField` included) inside an `if` that goes false, a `ForEach` that drops
it, or under an `.id` that changes, is unfocused and stays unfocused when it
returns. Code that relied on focus returning with the element refocuses it
(`Window.focus(_:)` or a `@FocusState` write, `IX-J`). **No id path moves**:
every `GlobalElementID`, `theSevenRetentionSlotsAreMutuallyDistinct`, `MC-A`/
`MC-C`/`MC-P` numbering and `.id()`'s outermost rule are untouched; only which
entries a reset deletes changes.

**Evidence.** Arms F1, F2, K0 (control).

**Cost if wrong.** Restoring the exemption is one line in
`StateTable.isWindowRetained` — mutation `MRk′`, which the lane's tests redden.

---

## IX-J — `@FocusState` and `.focused(_:)`

**Ruling.** SwiftUI's spelling: `@FocusState var isFocused: Bool` and
`@FocusState var field: Field?` (`Value: Hashable`), with `.focused($isFocused)`
and `.focused($field, equals: .name)` on every `StyledElement`, returning
`Self`. Semantics:

1. **Reading** the wrapped value in a body reads the window's focus as of the
   last completed frame: `true` / the bound value iff the focused element
   carries the matching `.focused` binding.
2. **Writing** from input moves focus at the next frame to the element that
   registered the written value (or `true`); writing `false`/`nil` clears focus
   **only if** the focused element is bound to this `FocusState`. A write naming
   an element that is not focusable, or disabled, focuses nothing (`K1`).
3. **`.focused` does not make an element focusable** — it binds one that is
   (`.focusable()`, a control, a `TextField`), as SwiftUI's does.
4. **It follows every other focus mover** — Tab, a `TextField` press,
   `Window.focus(_:)`, `IX-I`'s drop (`F1`: `focused=false` after a rename) —
   updating its value on the frame after the move, and **it never writes from a
   phase**: the reconciliation happens at the frame boundary, the one place
   `Frame.resolveFocus()` already runs, and writes only on a change.

`@FocusState` is a new box type seeded by reflection exactly as `@State` is
(its slot a `$state<n>` sibling — **no new reserved name**; the seven stay
seven). `@FocusedValue`, `focusedSceneValue`, `defaultFocus`, `focusScope`,
`prefersDefaultFocus` and `focusSection` are **not offered** (owner none).

**Evidence.** SDK `FocusState`, `focused(_:equals:)`, `focused(_:)`; arms K0,
F1, F2, F4.

**Cost if wrong.** The box is additive; reconciliation is one function at the
frame boundary.

---

## IX-K — Full Keyboard Access, click-to-focus, `hidden()` and focus

**Ruling.**

1. **Divergence 80 is kept and amended**, owner **none**: MetalUI reads no
   system keyboard-navigation setting; every control is focusable, Tab visits
   every focusable element, a focused control takes its keys. **Now measured**:
   with `NSApp.isFullKeyboardAccessEnabled == false`, SwiftUI's Tab moved focus
   nowhere — not from one `.focusable()` view to another, not to a `Button`
   (`F5`) — and a clicked `Button` takes no focus (`F6`). Reading the setting
   would need a `PlatformWindow` member on both backends and SDL platforms have
   no such setting; following it would make every control keyboard-unreachable
   on a default macOS install.
2. **Divergence 94 is added** (kept, owner **none**, pinned wrong on purpose):
   **a click does not focus a `.focusable()` element**; SwiftUI's click focuses
   one (`F3`: `focus=left`), and a click elsewhere — a tappable or a plain view —
   does not take it away (`F3`, `F4`). MetalUI's focusable element registers no
   pointer hitbox (`Handlers`' two gates), and making it one would make every
   focusable element opaque to the pointer — a hit-testing change for every
   focusable container. Remedy: an `onTapGesture` writing a `@FocusState`.
3. **A hidden element is out of the keyboard** (the `LR-AV`/`LR-DH` item "focus
   and keys under `hidden()`", SwiftUI unprobed until now — **aligned**):
   SwiftUI's `.focusable().hidden()` view never takes focus and its key handler
   never runs (`F9`: nothing logged, against `K0`'s passing control). MetalUI's
   `.focusable().onKey { }.hidden()` box today registers, takes focus and claims
   keys (the hazard `focusable()`'s doc comment records). Now a node in
   `Frame.hiddenNodes` (or under `display: .none`) contributes nothing to the
   keyboard half of the focus registry — no focusability, no `onKey`, no
   actions, no key context — through the **same** gate as `isEnabled` in
   `Frame.registerHandlers`' 5-argument implementation (one gate, two
   conditions, **keyboard half only**: the pointer hitbox is already withheld
   under `hidden()` by the pointer-disable scope, `ElementGroup.swift`, and is
   not re-gated), so a focused element that becomes hidden loses focus at the
   next frame boundary as a disabled one does. **A keyboard shortcut is NOT
   removed under `hidden()`** (*corrected by `IX-O`*: the design's first text
   said "no shortcut"; arm `X1` measured a `.hidden()` button's shortcut
   firing), so the shortcut table is gated by `isEnabled` alone.
   Accessibility suppression and hit testing under `hidden()` are unchanged.
   **A hidden scroll region still takes the wheel** (`LR-AV` item 5's inert
   row, `OM-AK`): kept, owner **none** — SwiftUI's side is unmeasured (the
   harness cannot read a scroll offset) and scroll regions stay outside every
   gate, `.disabled`'s included (`EV-E`).
   **One existing test changes its answer** (*named by `IX-O`*):
   `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`
   (`AccessibilityTreeTests`) requires, as a control, that "the hidden
   focusable box kept focus"; under this item it does not. Its control is
   re-derived (`frame.focusedElement == nil`, the hidden box refused focus) and
   its subject clause (`tree.focused == nil`) holds; the lane records it as a
   T row, not a retirement.

**Evidence.** Arms F3–F6, F9; `NSApp.isFullKeyboardAccessEnabled` printed.

**Cost if wrong.** Click-to-focus is a pointer-gate change with its own ruling;
the setting is a platform API.

---

## IX-L — content shapes, and what a clip does to a hit

**Ruling.**

1. **`.contentShape(_ shape: some Shape)`** on every `StyledElement` (returning
   `Self`) and on the proposal tap/gesture wrappers (`OnTapModifier`,
   `GestureModifier`) — so it is written **after** the tap on the proposal
   path; a proposal element that spells it before its tap does not compile
   (guard, extending the existing `contentShape(inset:)` refusal). The hit
   region is the shape's geometry in the element's (inset) hit rect: a circle
   refuses the corner and takes the centre (`C1`, `C2` — both orders agree —
   `C10`, `C11`, `C13`). `Hitbox` gains the geometry and `Hitbox.contains(_:)`
   tests it, and **every** consumer — click, the gesture arena, hover, active,
   wheel routing — reads that one helper through `topmostOpaqueHitbox`,
   **and** `Window.enclosingScroller(of:at:)`'s candidate filter, which today
   calls `region.bounds.contains(point)` itself (*found by `IX-O`*: the one
   region test outside `topmostOpaqueHitbox`), calls `Hitbox.contains(_:)` too
   — a consistency edit with no reachable difference (a scroll region carries
   no content shape), pinned by a recorded grep rather than by a mutation that
   could not redden. A
   `.continuous` rounded rectangle hit-tests circular, as it draws (divergence
   90). Focus registration and the accessibility frame keep the element's own
   box, as `contentShape(inset:)`'s do. `contentShape(_:eoFill:)`'s `eoFill`
   and the `kind:` forms are not offered (owner none).
2. **A clip's corner radii do not shape a hit.** SwiftUI's `clipShape` and
   `cornerRadius` do not restrict hit testing at all (`C3`, `C4`, `C9`: the
   corner outside a circular/rounded clip is hit). MetalUI intersects a hitbox
   with the active clip's **rect** (unchanged): at the corners of a same-sized
   clip the two agree, and that agreement is pinned; where a smaller clip cuts
   the hit region MetalUI's is smaller — **divergence 43 amended** (its row
   gains `clipShape`, `C3`/`C4`, beside `.clipped()`'s `H6`), no new number.
3. **Divergence 57 is kept and pinned**, owner **none**: a drawn element with
   no pointer target does not block a click beneath it in MetalUI, where
   SwiftUI's drawn content is hit-testable (`H18`, `C12`: a gesture-less
   circle over a tappable swallows the centre and passes the corner). Pinned
   by `aDrawnElementWithoutAPointerTargetDoesNotBlockAClickBeneathIt`, wrong on
   purpose. Making drawn content hit-testable reverses `OM-I` for every element.
4. **Divergence 41 is amended**, no new number: SwiftUI's filled shape is hit
   by its shape (`C5`, `C6`), a stroked one only on its stroke (`C7`, `C7b`);
   MetalUI's tappable shape is hit over its frame unless it declares
   `.contentShape(_:)`.

**Evidence.** Arms C0–C13; `swiftui-content-shape-hit-region.swift` re-run
(H, P, N, X identical to its header).

**Cost if wrong.** The geometry test is one function on `ShapeGeometry`.

---

## IX-M — menus, and the other items this run does not build

**Ruling.** **Menus are not built** — `Menu`, `.contextMenu`, a pop-up
`.pickerStyle(.menu)`: each needs a platform menu (an `NSMenu` on AppKit, a
drawn menu with its own focus and dismissal on SDL, where no native menu
exists) and a `PlatformWindow` API on both backends — not cheap. Owner
**none** (additive; no clause of plan task 12's text names menus). Divergence
**81** (`PickerStyle.automatic` is segmented where SwiftUI's is a pop-up) is
re-owned from "plan task 12" to **none**. The other not-built items are named
in `IX-B`, `IX-E` item 2, `IX-F` item 1 and `IX-J`, each owner **none**.
Proposal-path focus (a `.focusable()` on a `ProposalElementGroup`) is not
offered either (owner none; additive).

**Cost if wrong.** A later menu task starts from this list.

---

## IX-N — three lanes, in order, and the exits

**Ruling.** Lanes **1** (gestures and the arena), **2** (buttons, shortcuts,
the disabled and inactive looks, the focus ring; **content shapes and the
pointer divergence pins**, moved here from lane 3 by `IX-O`), **3** (focus only:
the `IX-I` drop, `@FocusState`, `hidden()` and the keyboard, divergence 94),
run in that order, one
agent at a time, each owning the files spec §6 lists; a file two lanes touch
names each lane's region. Exits for every lane: the whole suite unfiltered,
one summary line, 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
each new guard mutated red once; every mutation spec §6 names applied from a
commit, restored from a copy, the reddened tests named; **0 px against
`31f2e7a` in all fourteen offscreen images** (no demo tree uses a gesture, a
`Button`, a control or a `.focused` binding — every look here is outside
them); `DemoFrameDeterminismTests`' `Expected.swift` unedited;
`everyProductionTreeBuildsOnAOneMegabyteThread` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green; `MetalUILayout`
imports only `MetalUICore`; `Backends/SDL` builds (no source there is touched).
**The Windows stack budget** (*added by `IX-O`*): every lane that adds a
`Handlers` member records `MemoryLayout<Handlers>.size` before and after
(each new member is one reference, array or small optional — a `Shape` is
held in a class box, never an existential stored inline) and re-measures the
smallest thread that builds every production tree (528 KB, CLAUDE.md "CI
hazards" — *stale: 592 KB at `31f2e7a`, re-measured by lane 1, `IX-P`*); `everyProductionTreeBuildsOnAOneMegabyteThread` green is the exit,
the measured figure the record.

**Cost if wrong.** A lane that needs another's file says so in its record
section.

---

## IX-O — the critic round: four new probe arms, eleven corrections, two rejections

**Ruling.** The committed design (`b8d7da9`) was attacked before any lane ran.
**Re-run**: `swiftui-interaction.swift` compiled and run with the screen
**locked** (lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`):
all 156 recorded lines byte-identical to the header (every arm, not two). Four
arms were then **added** (group `X`), the whole probe run twice more,
byte-identical, 161 lines, exit 0, stderr empty; the first 156 lines unchanged:

- `X1` `keyboardShortcut("k")` on a `.hidden()` `Button`, ⌘K: `k`.
- `X2` a focused `TextField` (with `.onSubmit`) beside a `.defaultAction`
  button, Return: `focused=true,|start,submit`.
- `X3` a `.plain` `Button` child under a parent `.gesture(DragGesture())`,
  click on the child: `button`.
- `X4` the same, dragged 30 pt inside the child: `button` (no `chg`).

**Corrections applied** (each marked in its ruling):

1. `IX-K` 3 removed shortcuts under `hidden()` — refuted by `X1`; the hidden
   condition gates the keyboard focus half only (`IX-F` 5, `IX-K` 3), with a
   pin (spec 3.14b).
2. `IX-D` 3 said when a member may **end**, not when it may **change** — `X4`
   rules both, and the `onClick`-over-a-parent-drag interaction is stated and
   pinned (spec 1.23), its one unmeasured corner ruled as MetalUI's.
3. `IX-F` had no rule for Return in a focused field — `X2` measured it; pinned
   (spec 2.13).
4. `IX-K` 3 reddens an accessibility test's control
   (`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`)
   that spec §6 did not name — named, re-derived (T row).
5. `IX-I` left `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
   as "a candidate" — it is an `if` removal and inverts; named, renamed to spec
   3.2. Spec 3.6 is the existing `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`.
6. `IX-L` 1's "one region test" missed `Window.enclosingScroller(of:at:)`'s
   own `bounds.contains` — routed through `Hitbox.contains(_:)`.
7. `IX-E` 2's cost was wrong: a closed struct named `ButtonStyle` makes the
   protocols a source break later, not additive — ruled with a migration
   spelling.
8. `EventModifiers` is narrower than SwiftUI's — ruled (`IX-F` 1).
9. `IX-C` 4's reason for not timestamping `MouseEvent` was half wrong
   (`ScrollEvent` has one) — corrected; durations run from the stamp tick.
10. `hidden()`'s wheel (`LR-AV` item 5, "a hidden scroll region still takes
    the wheel") was missing from the audit table — added, kept, owner none.
11. The design named no Windows stack budget exit although it adds three
    `Handlers` members to every `StyledElement` — added (`IX-N`).

**Lanes re-cut** (`IX-N`): lane 3 carried focus **and** content shapes — two
subsystems, 20 tests, and the run's one id-adjacent behaviour change (`IX-I`).
Content shapes and the two pointer-divergence pins (43, 57) move to lane 2,
which already owns `Handlers` and runs after lane 1's `Hitbox.contains`; lane 3
is focus alone.

**Rejected** (recorded here, under this task's prefix, not as `LR-` rulings:
`LR-` is plan task 7's, closed at stage 11):

- *"Make a click focus a `.focusable()` element (`F3`) instead of numbering
  divergence 94."* Rejected: `IX-K` 2's reason holds — a focusable element is
  not a pointer target, and making it one makes every focusable container
  opaque to the pointer, a hit-testing change outside this run's
  must-not-move set. The remedy (`onTapGesture` writing a `@FocusState`) is
  spellable once lanes 1 and 3 land.
- *"Read `NSApp.isFullKeyboardAccessEnabled` (`F5`/`F6`)."* Rejected: `IX-K`
  1's reason holds, and following it would leave every control unreachable
  from the keyboard on a default install, with no SDL equivalent.

**Unchanged by this round**: every other ruling. No SwiftUI claim here rests
on a locked-screen blind spot (`X1`–`X4` are dispatch logs, which the harness
sees, read against `G0`/`K0`); the VoiceOver script is still part 2's and a
human's; the real-window capture stays owed (screen locked).

**Cost if wrong.** Each correction is one clause and one pin; the lane re-cut
moves files between two agents, not behaviour.

---

## IX-P — lane 1 landed: gestures and the arena (and seven clauses the design left open)

**Ruling.** Lane 1 (`IX-B`, `IX-C`, `IX-D`, `IX-O`'s `X4` rule) landed on
`feat/interaction`: red `0d661fd`, green `95765d6`. `Gesture.swift` (the closed
protocol, `TapGesture`/`LongPressGesture`/`DragGesture`, `ExclusiveGesture`/
`SimultaneousGesture`, the pure `GestureArena`), `GestureModifiers.swift` (the
five `StyledElement` modifiers, appending and returning `Self`; the proposal
`GestureModifier`), `Handlers.gestures` (joins `isPointerTarget`),
`Hitbox.contains(_:)` and `Hitbox.origin`, `Frame.insertHitbox`'s `origin:`,
`Window.dispatchGestures`/`advanceGestures`, and doc corrections to `onClick`
(`Box.swift`), `Handlers`, `ClickDispatch`, `StateDispatch` and — one sentence,
doc only, in lane 2's file — `Button.swift` (it too called `onClick` "SwiftUI's
`onTapGesture`", which `IX-D` item 2 refutes).

**Clauses decided here** (each MetalUI's, none a SwiftUI claim):

1. **"An internal requirement" is spelled SPI.** A public protocol cannot have
   an internal requirement; `Gesture`'s one requirement,
   `_recognizers() -> _GestureRecognizers`, and its result type are
   `@_spi(MetalUIGesture)`. A plain importer can neither see the requirement
   nor name the type, so it can neither implement nor forward it (guard G1.1;
   measured first in a two-module scratch: without SPI on the *type* too, an
   outside `func _recognizers() -> _GestureRecognizers { fatalError() }`
   would satisfy the requirement). An `@_spi(MetalUIGesture) import` opens
   it — underscored, not API.
2. **A tap's count is counted from the arena's first press**:
   `clickCount − (the first press's clickCount) + 1`. For every probe arm this
   is the platform `clickCount` (`IX-C` item 2's wording); it differs only
   when a new arena starts on the second click of a platform double click —
   a lone `onTapGesture { }` clicked twice quickly then taps twice, where
   comparing the raw `clickCount` would miss every second click.
3. **The tick advance runs in the display-link callback, ahead of
   `drawFrameIfNeeded`** — "at the start of `drawFrameIfNeeded`" (spec §5) in
   effect, but a direct `drawFrameIfNeeded()` call (tests, a resize) advances
   and stamps nothing, so a stamp is always a real tick, as `IX-C` item 4
   requires. After each frame the window re-dirties itself only while
   `GestureArena.needsTicks` (a tap sequence or an unmatured long press is
   pending).
4. **The arena lives from the press to the release, and past it only while a
   tap sequence waits.** A press on the same target continues it (taps re-arm;
   anything else still undecided is cancelled); a press on any other target —
   or on nothing — abandons it first: every undecided member fails, and a
   ready tap that was waiting only on them ends then.
5. **The larger-count tap deferral is arena-wide**, simultaneous members
   included (`IX-C` item 3 says "sharing an arena"), and a smaller tap ahead of
   a larger one yields to it, so the two cannot hold each other off.
6. **`LongPressGesture.onChanged` reports `true` when the press begins**, on
   the same withholding as `onPressingChanged` (SwiftUI's is unmeasured).
7. **`enclosingScroller(of:at:)` calls `Hitbox.contains` in this lane**
   (`IX-O` correction 6), so `grep -n "bounds.contains(" Sources/MetalUI`
   already finds only `Hitbox.contains` (recorded 2026-09-29, one hit,
   `Hitbox.swift:129`). `topmostOpaqueHitbox` remains the only function
   comparing `(layer, offset)` (one hit, `Hitbox.swift:174`); the arena's own
   ordering compares `(depth, attachment index)`, which is declaration order,
   not a second hit ranking.

**Tests.** 1.1–1.23 and G1.1–G1.2 are all in
`Tests/MetalUITests/GestureTests.swift` and `GestureCompileGuards.swift`,
through a real `Window` on a `FakePlatformWindow` with `simulateTick`; the
spec's separate `GestureArenaTests.swift` was not needed (every arena rule is
reached through the window, which also covers the formation from the one
ranking). **Red first**: before the surface existed the test target did not
compile ("cannot find 'TapGesture' in scope"); with the surface storing
attachments but no hitbox and no arena (`0d661fd`), all 23 were red — 22 at
their geometry requirement ("the fixture's hitboxes: []", a gesture-only
element registering nothing), 1.20 at `taps.count == 2`. **1.18 was
therefore red too, not green-first**: its behaviour (a parent's `onClick`
never sees a child's press) is today's, but its child is a gesture-only
element, which cannot exist before the surface. G1.1/G1.2 were green once
the surface existed; each was mutated red (below). `ModifierTests`'
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` gains the five
modifiers (45 → 50 rows, `HandlerShape.gestureCount`) and
`OuterModifierMatrixTests`' `HandlerFingerprint` gains `gestureCount` — both
existing tests extended, answers unchanged for every existing row.

**Mutations** (each applied to the green tree from `95765d6`, restored from a
copy, the whole suite run unfiltered — 1798 tests each time — `git status
--short` empty after every one):

| id | mutation | tests reddened |
|---|---|---|
| M1a | a tap ends at its press | 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.16, 1.17, 1.21 |
| M1b | slop 5 → 6 | 1.2 |
| M1b′ | slop check removed (move and release) | 1.2, 1.3, 1.16 |
| M1c | `taps == count` → `taps >= 1` | 1.4, 1.5, 1.6 |
| M1d | deferral 0.33 → 0 | 1.5 |
| M1e | arena-wide deferral removed (`if count > 0 { return false }`; the first spelling, `return false` before the unwrap, did not compile) | 1.6 |
| M1f | a long press matures only at its release | 1.7, 1.8, 1.9, 1.16, 1.17, 1.22 |
| M1g | maximum distance unchecked | 1.8 |
| M1h | no `pressing=false` for a failed press | 1.9 |
| M1i | `distance >= minimum` → `>` | 1.10, 1.21 |
| M1i′ | drag values in window coordinates | 1.10, 1.12, 1.21 |
| M1i″ | a drag that never started (or never activated) ends | 1.11, 1.16, 1.18, 1.23 |
| M1j | a drag ends only inside its element | 1.12 |
| M1k | normal members outermost first | 1.13, 1.16 |
| M1l | high priority treated as normal | 1.14, 1.21 |
| M1m | simultaneous roots resolved after the exclusive order | 1.15 |
| M1n | only an *ended* member ahead blocks | 1.16, 1.23 |
| M1o | `simultaneously` built as exclusive | 1.17 |
| M1p | ancestors' `onClick` join (as normal members, ready on a release inside) | 1.18 |
| M1q | a gesture-carrying element registers its hitbox outside the gates | 1.19 |
| M1r | gesture callbacks run without `StateDispatch` | 1.20 |
| M1s | `GestureModifier` stores no attachment | 1.21 |
| M1t | frames requested while pressed, not only while pending | 1.22 |
| M1u | a withheld drag's changes reported anyway | 1.23 |
| G1.1 | `@_spi(MetalUIGesture)` removed from the requirement and its type | `anOutsideTypeCannotConformToGesture` (fabricated arm compiled) |
| G1.2 | `StyledElement.highPriorityGesture` made internal | `theGestureSpellingsCompileFromAPlainImport` (positive arm failed) |

No mutation reddened a test outside `GestureTests`/`GestureCompileGuards`.

**Counts.** After `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation notice;
`swift build --build-tests` under the default build system: 0 `warning:`),
then unfiltered `swift test --build-system native --no-parallel`: **`Test run
with 1798 tests in 3 suites passed`** (1773 + 23 + 2), the log carrying `FR-J
no-argument frame: succeeded=true`; guards **108 + 2 = 110**
(`GestureCompileGuards`, both whole-file `typecheckFile`).
`everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `Expected.swift`
unedited. **Pixels**: `docs/probes/demo-pixels/compare.sh` against
`31f2e7a` → `95765d6`: 0 differing, scene identical, in all fourteen images,
controls non-zero as recorded (light vs dark 1048576, default vs modal
1031003, default vs animation 454895, prod default vs modal 491221).
`MetalUILayout` imports only `MetalUICore`. `Backends/SDL` builds
(`PKG_CONFIG_PATH=.accesskit swift build --build-tests`, 0 `error:`; its
existing SDL-dylib deployment `ld: warning`s are the machine's, untouched).
A `swift:6.4-noble` container (a `git archive` of `95765d6`) builds with 0
`error:`/`warning:` and runs 199 + 10 + 22, all passing (no portable test
added by this lane).

**Windows stack budget** (`IX-N`; a scratch exit-test file in
`MetalUICrossPlatformTests`, deleted after, debug, macOS arm64, 16 KB steps):

| | before (`31f2e7a`) | after (`95765d6`) |
|---|---|---|
| `MemoryLayout<Handlers>.size` | 408 | 416 |
| smallest thread building every production tree | fails 576 KB, passes **592 KB** | fails 592 KB, passes **608 KB** |

Spec §6's "528 KB at `31f2e7a`'s recorded figure" was stale: record §59 had
already measured 592 KB, re-measured here. `everyProductionTreeBuildsOnAOneMegabyteThread`
green.

**Real-window capture**: not taken — the lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` (10:17 PDT).

**Cost if wrong.** Each clause is one comparison or one call site in
`Gesture.swift`/`Window.swift`, pinned by the test its mutation reddens.
