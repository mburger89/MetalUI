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

Prefix **`IX-`**, lettered. **Next unused: `IX-AH`.** (This line moves in the
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
   target's id, **in the target's own hit layer** (*added by `IX-Q`*: a
   `Deferred` presentation's press never joins its declarer's arena), and whose
   region contains the point (`Hitbox.contains(_:)`, one
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
| V2 (*`IX-Q`*) | `GestureModifier.prepaint` registers through `pass.frame.insertHitbox`, past the gates | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` (arm `gesture`), 1.19 (its proposal arm) |
| V3 (*`IX-Q`*) | an ancestor joins without `Hitbox.contains(point)` | 1.25 |
| V4 (*`IX-Q`*) | an ancestor of any hit layer joins (the lane's first code) | 1.24 |
| V5 (*`IX-Q`*) | `registerHandlers` passes no `origin:`, so a drag reads the inset region's space | 1.27 |
| V6 (*`IX-Q`*) | a press elsewhere drops the arena without `abandon()` | 1.26 |
| V7 (*`IX-Q`*) | a tap's release skips the region check | 1.28 |
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

---

## IX-Q — lane 1's fix round: a presentation keeps its own press, and five unpinned clauses pinned

**Ruling.**

1. **An arena's ancestors join only from the target's own hit layer.** A
   `Deferred` presentation hoists its content to a higher layer while its id
   stays under its declarer's; `Window.makeGestureArena` walked `id.parent`
   without reading `layer`, so a declarer's `highPriorityGesture` took a
   modal's `onClick` (a scratch window read `["root-high"]`) and its
   `simultaneousGesture` ran on every press inside the modal. Now an ancestor
   hitbox joins only when its `layer` equals the target's (`IX-D` item 1
   amended). **Evidence**: new probe
   `docs/probes/swiftui-gesture-presentation-arena.swift`, run twice,
   byte-identical, screen locked (the synthesized-click harness works locked;
   the presentation's own hosting view needed its `acceptsFirstMouse(for:)`
   replaced, without which every S/V arm — controls included — read `-`, a
   broken instrument discarded rather than read). An `.overlay` is in its
   presenter's arena (P1 `presenter-high`, P2 `presenter-sim,modal`); a
   `.sheet`'s or `.popover`'s content is not (S1/S2 and V1/V2 read exactly
   their controls S0/V0, `modal`). A MetalUI `Deferred` is the presentation
   shape (a portal to the root layer, the scrim and modal's spelling), not the
   overlay's (`.overlay` is `OverlayModifier`, same layer, unaffected). An
   in-flow `Deferred` (a tooltip) takes the same rule: it too is hoisted.
   Nothing in the repository's trees attaches a gesture yet, so no existing
   behaviour moves; the demo has none (0 px by construction).
2. **Five clauses the lane stated and no test saw are pinned**, each by a test
   its mutation reddens (table in `IX-P`, rows V2–V7): the arena's region
   clause (1.25, a child overflowing a 50-wide gesture-carrying `.frame`);
   `IX-P` item 4's abandon clause (1.26, a single tap beside a double ends at
   a press on another target within the deferral); `Hitbox.origin` for a
   content-shape inset (1.27, a drag's `startLocation` is the element's
   (100, 100), not the inset region's (80, 80)); a tap released outside its
   element inside the slop (1.28, pressed at x 248 and released at 252 on a
   root ending at 250).
3. **`GestureModifier` is a handler-registering site with its own gate arm**:
   `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` gains `gesture`
   (the proposal `GestureModifier`) and `gesture-legacy` (a `Box`'s
   `onTapGesture`, which rides the layer's `Handlers` and is gated centrally),
   and 1.19 gains a proposal `allowsHitTesting(false)` arm with its enabled
   control — as CLAUDE.md "Environment" requires of a new site.

**Red first.** 1.24 was committed red (`573ef7e`: high priority read
`["root"]`, simultaneous `["root", "modal"]`) and greened by the layer check
(`ee92939`). 1.25–1.28 and the gate arms pin behaviour lane 1 already had;
each was shown red by its mutation (V2–V7), each applied to `ee92939`,
restored from a copy, the whole suite run unfiltered (1803 each time), `git
status --short` empty after every one; no mutation reddened a test it was not
aimed at.

**Counts.** `swift build --build-system native --build-tests`: 0 `error:`,
the one `warning:` SwiftPM's deprecation notice. Unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1803 tests in 3 suites
passed`** (1798 + 1.24–1.28; the gate arms extend two existing tests), the log
carrying `FR-J no-argument frame: succeeded=`. Guards unmoved (110). `swift build --build-tests` under the default build system: 0 `warning:`.

**Cost if wrong.** One comparison in `makeGestureArena`; if a presentation
should join its declarer's arena after all, delete `$0.layer == hit.layer` and
invert 1.24's two modal expectations.

---

## IX-R — lane 2 landed: buttons, shortcuts, the looks and content shapes (and eleven clauses the design left open)

**Ruling.** Lane 2 (`IX-E`, `IX-F`, `IX-G` item 2, `IX-H`, `IX-L`) landed on
`feat/interaction`: red `fb0053b`, green `68a33ec`. New
`ButtonStyle.swift` (`ButtonRole`, the closed `ButtonStyle`),
`KeyboardShortcut.swift` (`KeyEquivalent`, `KeyboardShortcut`,
`EventModifiers = Modifiers`, the matcher, `ShortcutTarget`,
`Window.dispatchShortcut`), `ControlLook.swift` (`controlAccent(_:)`,
`controlRing(_:)`, `PaintPass.paintControl(disabled:_:)`); `Button`'s two role
initialisers, `.buttonStyle`, the three `.keyboardShortcut` overloads, the
pressed look; `Handlers.keyboardShortcut` (in `isKeyTarget`) and
`Handlers.contentShape` (a `ContentShape` class box); `FocusRegistry`'s
shortcut table in registration order; one `Window.onInput` call between the
raw `onKey` bubble and Tab; `Hitbox.shape` (window space) tested by
`Hitbox.contains`; `ShapeGeometry.contains(_:)`/`offsetBy`; `contentShape(_:)`
on `StyledElement`, `OnTapModifier` and `GestureModifier`; the disabled scope,
key-window accent and focus ring on `Button`, `Toggle`, `Slider`, `Stepper`
and `Picker`; doc comments of `EnvironmentValues.controlActiveState` and
`ControlActiveState` (they now have consumers).

**Clauses decided here** (each MetalUI's, none a SwiftUI claim):

1. **`.plain`/`.borderless` drop the chrome at layout, by value**: a
   decoration field still equal to the chrome's own (`.surfaceSecondary`,
   radius 5, the 1-pt `.separator` border) is dropped, so a caller's
   `.background` survives in either order relative to `.buttonStyle`; a caller
   who writes the chrome's own value explicitly cannot be told from it. The
   strut stays (0 × 0) so the label is index 0 and the strut 1 in every style.
2. **The pressed wash is painted after the chrome's content** — over the label
   and border, not between the fill and the label (`Box.paint` has no seam
   there); rounded to the chrome's corner radius.
3. **The focus ring is on every `Button` style**, `.plain` included, and while
   focused it replaces the chrome's 1-pt border (`focus ?? hover ?? plain`,
   `OM-L`); a caller's own `focusBorder` wins on every control.
4. **A segmented `Picker` has no accent to remove** (its selected segment is
   `.surface`); only the radio group's selected circle follows
   `controlActiveState`.
5. **The key compares lower-cased** with `charactersIgnoringModifiers` (AppKit
   reports a shifted letter upper-case there); the modifiers exactly. Pinned
   by 2.4's ⌘⇧K arm (fix round, V6).
6. **A focused `TextField` with no `.onSubmit`** does not claim Return: its
   editing stage returns unhandled on a submit with no handler (`TI-B`, as
   before), so the default button fires. Unmeasured in SwiftUI (`X2` had an
   `.onSubmit`); unpinned, stated. A focused `TextEditor` inserts `\n` and
   claims it.
7. **A shortcut runs whatever a click runs** (`composed.onClick ?? action`,
   so a caller's `.onClick` replaces it too), dispatched under
   `StateDispatch` to the button's id (`ID-F`). The dispatch half is pinned
   by 2.4b, `aShortcutWritesTheStateOfTheOccurrenceThatOwnsItsButton` (fix
   round, V7).
8. **The shortcut is registered whatever `hidden()` says** — lane 3's hidden
   condition must gate the focus half only (`X1`, spec 3.14b).
9. **A content shape composes with `contentShape(inset:)`**: the shape's
   geometry is taken in the inset rect. It rides the layer's `Handlers`, so a
   shape written before a wrapping modifier does not reach a click written
   after it — `contentShape(inset:)`'s S1 divergence, unchanged in kind.
10. **`Hitbox.contains` tests the clipped rect first, then the shape** (the
    shape is never clipped itself), so a content shape only shrinks a region
    the clip already bounds (divergence 43 as amended by `IX-L` item 2).
11. **The looks read `environmentTop` in place** (`isEnabled`,
    `controlActiveState`), costing no counted snapshot (`EV-O`); `Button`
    keeps its one `pass.environment` read in layout, as before.

**Red first — and one harness finding.** At `fb0053b` the test target
compiled against the stored-but-unread surface: 2.2–2.16 red (15 tests — the first write-up read "13"; a `git archive` build of `fb0053b` filtered to the lane's files reads `Test run with 20 tests … failed`, 15 of them 2.2–2.16, the commit message of `74d1022` keeps the old figure); 2.1,
2.17, 2.18, G2.1, G2.2 and the extended `ModifierTests` row green (2.1 pins an
absence, 2.17/2.18 pin today's behaviour, written first). **Four shortcut
tests discarded their `Window`** (`let (_, platform) = …`); the fake platform
window holds it weakly, so no event reached it — 2.5, 2.6, 2.8's hit-testing
arm and 2.9 were red at `fb0053b` for that reason as well as the missing
dispatch, and **2.8's disabled arm read green vacuously**. Fixed in `68a33ec`
(`withExtendedLifetime`, also added to `ContentShapeTests`' helpers), and the
fixed tests re-shown red without the dispatch: mutation **M2x** (the one
`dispatchShortcut` call removed) reddens all seven shortcut tests.

**Tests.** 2.1–2.3 `ButtonSemanticsTests.swift`, 2.4–2.9 and 2.13
`KeyboardShortcutTests.swift`, 2.10–2.12 `ControlLookTests.swift`,
2.14–2.18 `ContentShapeTests.swift`, G2.1 `ButtonCompileGuards.swift`, G2.2 a
new `@Test` in `DecorationCompileGuards.swift`. Existing tests extended,
answers unchanged for every existing row: `ModifierTests`' table gains
`contentShape(_:)` (50 → 51) and `HandlerShape` gains `keyboardShortcut` and
`contentShape`; `OuterModifierMatrixTests`' `HandlerFingerprint` gains both.

**Mutations** (each applied to `68a33ec`, restored from a copy, the whole
suite run unfiltered — 1823 tests each time — `git status --short` empty
after every one):

| id | mutation | tests reddened |
|---|---|---|
| M2a | `.cancel` binds Escape | 2.1 |
| M2b | `.plain` keeps the padding | 2.2, 2.15 (its `Button` arm's geometry) |
| M2c | pressed = `isActive` alone | 2.3 |
| M2d | modifiers compared as a superset | 2.4 |
| M2e | `defaultAction`/`cancelAction` swapped | 2.5, 2.13 |
| M2f | the last registered shortcut wins | 2.6 |
| M2g | shortcut stage before the raw `onKey` bubble | 2.7 |
| M2h | shortcut registered outside the `isEnabled` gate | 2.8 |
| M2i | shortcut skipped under decoration opacity 0 | 2.9 |
| M2j | disabled scope gated on `!isFocused` (all five call sites, whole-file) | 2.10, 2.11, 2.3 (its `.plain` arm), `aTogglesIndicatorColourAnimatesUnderWithAnimation` |
| M2k | accent on `!= .inactive` | 2.11 |
| M2l | ring token `.separator` always | 2.12 |
| M2m | shortcut stage before a focused field's editing keys | 2.13, 2.7 |
| M2x | the `dispatchShortcut` call removed | 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.13 |
| M3i | `Hitbox.contains` ignores the shape | 2.14, 2.15, 2.16 |
| M3j | the shape tested in `dispatchClick` only (a second copy) | 2.16, 2.15 (its gesture arm) |
| M3k | a hit intersected with the clip's rounded geometry (own `clipShape` as a content shape; an ancestor clip's radii) | 2.17 |
| M3l | a hitbox for every painted element (a filled legacy box, a bare `Shape`) | 2.18 and 21 more: `aClosureStepperRunsItsClosuresAndANilOneDisablesItsDirection`, `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority`, `aContentShapeWithoutAClickHandlerRegistersNothing`, `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`, `aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick`, `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset`, `aLoweredContainerPaddingSitsInsideItsDeclaredSize`, `aLoweredWindowDispatchesClicksFocusAndKeys`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt`, `aStepperClampsIntoItsRangeAndWritesNothingWhenTheValueWouldNotMove`, `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`, `anOutOfRangeStepperStepsFromItsClampedValue`, `anUnboundedStepperDoesNotClamp`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `hoverBackgroundWithoutAClickHandlerNeverPaints` |
| V5 | `Frame.insertHitbox` stores `shape` untranslated by `activeOffset` (fix round, applied to `4e8492b`, 1825 tests) | 2.16b `aContentShapeInsideAScrolledScrollerFollowsTheScroll` (1 issue); green in the 1823-test suite before 2.16b |
| V6 | both `.lowercased()` removed from `KeyboardShortcut.matches` (fix round, `4e8492b`) | 2.4 `aShortcutFiresItsButtonWithoutFocusOnAnExactModifierMatch` (its ⌘⇧K arm, 1 issue); green before that arm |
| V7 | `StateDispatch.dispatching(to: id) { target.action() }` → `_ = id; target.action()` (fix round, `4e8492b`) | 2.4b `aShortcutWritesTheStateOfTheOccurrenceThatOwnsItsButton` (2 issues); green before 2.4b |
| V10 | the ring `BorderStyle(.accent, …)` in place of `controlAccent(environment)` (fix round, `4e8492b`) | 2.12 `aFocusedControlDrawsItsRingAndAnUnfocusedOneDoesNot` (its `.inactive` arm, 10 issues — two per control); green before that arm |
| G2.1 | `ButtonStyle.borderless` made internal | `theButtonSpellingsCompileFromAPlainImport` (positive arm failed) |
| G2.2 | `contentShape(_:)` declared on `ProposalElementGroup` | `aProposalElementCannotSpellContentShapeBeforeItsTap` |

**Fix round** (review of lane 2): four unpinned clauses gained pins, each
shown red by the mutation that removes it (V5, V6, V7, V10 above; restored
from a copy, `git status --short` empty after each): a content shape under a
scrolled scroller (2.16b, new), a ⌘⇧K shortcut on the upper-case event (2.4,
an arm), a shortcut's occurrence under `StateDispatch` (2.4b, new) and the
focused ring's `.separator` colour in a non-key window (2.12, an arm). The
suite reads **`Test run with 1825 tests in 3 suites passed`** (1823 + 2),
guards unchanged at 112; the projected close moves to 1837 tests.

**Recorded greps** (2026-09-29, `68a33ec`): `grep -rn "bounds.contains(" Sources/MetalUI`
→ one hit, `Hitbox.swift:139` (`Hitbox.contains`); the `(layer, offset)`
comparison → one hit, `Hitbox.swift:200` (`topmostOpaqueHitbox`);
`grep -h '^import' Sources/MetalUILayout/*.swift | sort -u` → `import MetalUICore`.

**Counts.** After `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation notice;
`swift build --build-tests` under the default build system: 0 `warning:`),
then unfiltered `swift test --build-system native --no-parallel`: **`Test run
with 1823 tests in 3 suites passed`** (1803 + 18 + 2), the log carrying `FR-J
no-argument frame: succeeded=`; guards **110 + 2 = 112**. Spec §9's "1825
tests" did not count the guards' own `@Test`s and predates `IX-Q`'s five:
the projected close is 1823 + lane 3's net 11 + 1 guard = **1835 tests, 113
guards**. `everyProductionTreeBuildsOnAOneMegabyteThread`,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
`theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `Expected.swift`
unedited. **Pixels**: `docs/probes/demo-pixels/compare.sh` `31f2e7a` →
`68a33ec`: 0 differing, scene identical, in all fourteen images; controls as
recorded (light vs dark 1048576, default vs modal 1031003, default vs
animation 454895, prod default vs modal 491221). `Backends/SDL` builds
(`PKG_CONFIG_PATH=.accesskit swift build --build-tests`, 0 `error:`; its
`sdl` pkg-config rpath warning is the machine's). A `swift:6.4-noble`
container (a `git archive` of `68a33ec`) builds with 0 `error:`/`warning:`
and runs 199 + 10 + 22, all passing.

**Windows stack budget** (`IX-N`; a scratch file of literal-size exit tests
in `MetalUICrossPlatformTests`, deleted after, debug, macOS arm64, 16 KB
steps):

| | before (`d0de2e4`) | after (`68a33ec`) |
|---|---|---|
| `MemoryLayout<Handlers>.size` | 416 | 432 |
| smallest thread building every production tree | fails 592 KB, passes **608 KB** | fails 592 KB, passes **608 KB** |

**Real-window capture**: not taken — the lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` (11:58 PDT).

**Not done here** (unchanged owners): the hidden condition and `@FocusState`
(lane 3); `TextField`/`TextEditor` take no disabled look (`IX-G` item 2);
`List` and text selection keep their accent (`IX-H` item 1); the
`METALUI_CONTROLS_DEMO` additions spec §7 allows were not made (no pixel exit
needs them); the looks (pressed, disabled, inactive, ring) are owed to the
human list beside a native SwiftUI window.

**Cost if wrong.** Each clause is one comparison or one call site, pinned by
the test its mutation reddens; the chrome-by-value rule (clause 1) becomes an
explicit "caller wrote it" flag if a caller ever needs the chrome's own colour
under `.plain`.

---

## IX-S — lane 3 stopped on a finding: `IX-I`'s reset closes the `if` route of the `$focus` hazard, and D13's instrument arm reddens

**Status.** Lane 3's tests (spec §6, 3.1–3.14, 3.14b, 3.20, G3.1) were written
red first (`48f0394`) and the implementation (`IX-I`, `IX-J`, `IX-K` item 3)
turns every one green, but the unfiltered suite reads **`Test run with 1837
tests in 3 suites failed … with 1 issue`**: a test **not** in spec §6's list
reddens. Per spec §6 ("a test `MRk′`'s inverse or 3.13's gate reddens that is
not in this list is a finding the lane records and stops on") the lane stops
here; the test is **not** edited.

**The finding.** `aFocusRequestWhileDisabledLeavesNoRetentionSlot` (D13,
`DisabledTests.swift:803`, `EV-F`), its **instrument arm, pinned wrong on
purpose**: "a non-focusable enabled element's slot makes the second request
stick" — `Expectation failed: hazard`. The arm reaches the known hazard in
`Frame.registerHandlers`' `$focus` paragraph (a `Window.focus` on a produced,
enabled, non-focusable element writes a stray `$focus` slot; after the element
is removed, a second `Window.focus` on its id sticks, because `resolveFocus`'s
fallback only asks `peek != nil`). The arm removes the element **with an
`if`** — an evaluated reset — and `IX-I` no longer exempts `$focus` from that
reset, so the stray slot is deleted with the element and the second request
is cleared: **the hazard's `if` route is closed by `IX-I`**, and the
instrument no longer sees a sticky focus. Measured: restoring the exemption
(mutation `MRk′`, `StateTable.isWindowRetained` `|| id.component ==
focusRetentionName`) and running the test alone turns it green again; the
disabled arm (its subject) is green either way.

**The hazard is not gone**, only its reset routes: an element that stops being
produced **without** an evaluated reset keeps its `$focus` slot (a `List` row
windowed out, `TB-AH`), so the same sequence over a windowed-out row still
sticks (by reading, not measured here).

**Options for the continuation** (not decided by this lane):

1. **Re-derive D13's instrument arm** onto a route `IX-I` does not reset — a
   `List` row focused while produced, then windowed out, then `Window.focus`
   again — keeping the arm's purpose (proving the instrument can see a sticky
   focus) and recording it as a T row; or
2. **retire the instrument arm** with a row naming `IX-I` as the change that
   closed its route, and amend the `registerHandlers` paragraph and
   `aFocusRequestWhileDisabledLeavesNoRetentionSlot`'s doc to say the hazard
   survives only for an unevaluated subtree.

**Everything else measured at this commit.** After `swift package clean`
(`Handlers` gains a stored member, `focusBinding`), `swift build
--build-system native --build-tests`: 0 `error:`, the one `warning:` SwiftPM's
deprecation notice; unfiltered `swift test --build-system native
--no-parallel`: **1837 tests** (1825 + lane 3's net 11 + G3.1), 1836 passing,
the one failure above; the log carries `FR-J no-argument frame: succeeded=`.
**Not yet done** (the lane stopped): the named mutations (MRk′, MRl, M3a–M3h,
M3m, M3n, M3g′) with their reddened sets, G3.1 mutated red once, the
fourteen-image offscreen comparison against `31f2e7a`, the `Backends/SDL`
and container builds, the Windows stack-budget re-measure (`Handlers` +8
bytes), the source docs that still describe `$focus` as exempt or the
hidden-focus hazard as live (`Frame.resolveFocus`'s three measured
consequences, `registerHandlers`' `$focus` paragraph; `Box.focusable()`'s is
corrected), and the migration note's own text in this doc.

**Implementation as landed** (for the continuation to verify, not re-design):

- `StateTable.isWindowRetained` keeps `$ax` only; `removeEntries` reports a
  deleted `$focus` slot in `resetFocusSlots` (emptied at the start of each
  `sweep()`, so a mid-frame `noteProduced` reset is never reported; the reap is
  not a reset). `Frame.render` clears `focusedElement` right after the sweep
  when its slot is in that set — the frame whose sweep deletes it (`IX-I`).
- `Frame.disablingHitTestingIfHidden` — the one helper `Element.prepaintGroup`,
  `ModifiedContent.prepaintLayer` and `Frame.render`'s root already call —
  also bumps a keyboard-hidden depth; `registerHandlers`' one gate registers
  the keyboard half only while enabled **and** not hidden, a hidden element
  registering its shortcut alone (`FocusRegistry.registerShortcut`, arm X1),
  and the `$focus` retention write is gated on both (`IX-K` item 3). M3g′ is
  therefore "`ModifiedContent.prepaintLayer` calls the pointer scope alone".
- `@FocusState` (`Sources/MetalUI/FocusState.swift`): a box seeded by
  `StateBinder` at the `$state<n>` sibling (no new reserved name), storing
  `FocusStateValue { value, pending }`; `.focused(_:)`/`.focused(_:equals:)`
  set a new internal `Handlers.focusBinding` (one reference; `HandlerShape`
  and `HandlerFingerprint` gain the field), recorded in the focus registry
  **ungated**. `Window.drawFrameIfNeeded` applies pending writes **before** the
  frame is built — a value moves focus to the last frame's element bound with
  it **only if that element was focusable on the last frame**, else focus stays
  (this refines `IX-J` item 2's "focuses nothing": the previous focus is kept,
  and M3a/M3e are one site, that check); `false`/`nil` clears only a focused
  element bound to that state — and, after the frame's focus read-back, writes
  each bound state's implied value **only where it changed** (a dirtying write
  between frames, never in a phase). A focused element retained but not
  produced this frame (a windowed-out `List` row) has no binding recorded, so
  its state reads the default until it returns — stated, unpinned.


---
## IX-T — D13's instrument arm re-derived onto a windowed-out `List` row; the `$focus` hazard docs; the migration note; lane 3's exits and corrected figures

**Ruling (`IX-S` option 1).** `aFocusRequestWhileDisabledLeavesNoRetentionSlot`
(D13, `DisabledTests.swift`, `EV-F`) keeps both arms and its subject, and both
arms move to the route `IX-I` does not reset: a **`List` row windowed out of its
scroller** (`TB-AH`: nothing evaluates it, so nothing resets it). Tree:
`ScrollView { List(12 rows, rowHeight 20) { Box { subject } } }`, driven
through `Frame` with `focusedElement` threaded forward as `Window` does
(`aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`'s idiom): a cold
frame; focus row 4's subject and render at offset 80 (rows 2..<7 built — the
first request, `try #require`d cleared); two frames at offset 0 (rows 0..<3,
row 4 out); focus its id again and render at offset 0. **Instrument arm**
(subject `Box()`, enabled, not focusable): the second request **sticks**,
pinned wrong on purpose as before. **Subject arm** (subject
`Box().focusable().disabled(true)`): it does **not** stick. Both below
`StateTable.sweepThreshold` (`try #require`d). **A T row naming `IX-I`**: the
test's answer is unchanged in both arms; only its route moved, because `IX-I`
closed the `if` route by deleting the stray `$focus` slot with the removed
element. The reviewer's temporary measurement (table 43/42 entries) and this
test agree.

**Pinned both ways by running, full unfiltered suite each time** (committed
`96d5874` first, `Frame.swift` restored from a copy, `git status --short`
empty after each):

| mutation | reddens |
|---|---|
| MD1: the `$focus` retention write ungated on `enabled` (`if keyboardVisible`) | D13 only (`!disabled`, 1 issue) |
| MD2: `resolveFocus`'s retention fallback always clears | D13 (`hazard`), `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `theSevenRetentionSlotsAreMutuallyDistinct` (3 issues) |

So each arm can fail, and the arms disagree on the unmutated tree.

**Source docs corrected** (`96d5874`): `Frame.registerHandlers`' `$focus`
paragraph now says the hazard is reached only through an unevaluated subtree
(an `if`, a loop's dropped tail or a departed `.id` deletes the stray slot in
that frame's `sweep()`) and points at D13's `List`-row route;
`Frame.resolveFocus`'s three measured consequences now hold only for a subtree
nothing evaluates (retained while out of the window, its ancestors keep
claiming keys, restored on return), the `if` route dropping focus in the frame
whose sweep resets the slot (probe arm F2), naming
`focusDropsWhenAnIfRemovesItsElement` (renamed from
`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`).
`FocusRegistry.shortcut(matching:)`'s doc line is back above it.

**Migration note (`IX-I`, for the record and CLAUDE.md's Identity paragraph).**
Before this task, a focused element that an evaluated reset removed — an `if`
that went false, a `for`/`ForEach` that stopped producing it, a position whose
`.id` changed — kept focus while away (below the sweep threshold,
indefinitely), its still-produced ancestors kept receiving its keystrokes, and
focus came back when it returned. **Now focus is cleared in the frame that
removes it and does not come back** (SwiftUI's answer, probe arms F1, F2): a
key typed after the removal reaches the nearest remaining handler through
`Window.onInput`, not the removed subtree's ancestors, and a returning
`TextField` is unfocused. **To keep the old effect, refocus on return**:
`Window.focus(id)` from input, or write the `@FocusState` the element is bound
with (`.focused($state)`, `IX-J`), which applies before the next frame is
built. **Unchanged**: a `List` row scrolled out of its window keeps focus and
gets it back (`TB-AH`), every `GlobalElementID`, the seven retention slots,
`MC-A`/`MC-C`/`MC-P` numbering and `.id()`'s outermost rule; only which entries
a reset deletes changes (`$ax` stays exempt).

**Windows stack budget** (`IX-N`; a scratch file of literal-size exit tests in
`MetalUICrossPlatformTests`, deleted after, debug, macOS arm64, 16 KB steps):

| | before (`68a33ec`, `IX-R`; no `Sources/` change to `d50d001`) | after (`96d5874`) |
|---|---|---|
| `MemoryLayout<Handlers>.size` | 432 | **440** |
| smallest thread building every production tree | fails 592 KB, passes **608 KB** | fails 608 KB, passes **624 KB** |

Still well inside the 1 MB Windows thread;
`everyProductionTreeBuildsOnAOneMegabyteThread` green.

**Container.** A `swift:6.4-noble` container (a `git archive` of `96d5874`)
builds with 0 `error:`/`warning:` and runs **199 + 10 + 22**
(`MetalUILayoutTests`, `MetalUICrossPlatformTests`, `MetalUICoreTests`), all
passing.

**Suite.** At `96d5874` (an incremental build over `53e09d3`'s clean one; no stored property changed since): `swift build --build-system native
--build-tests` 0 `error:`, the one `warning:` SwiftPM's deprecation notice;
unfiltered `swift test --build-system native --no-parallel` reads **`Test run
with 1837 tests in 3 suites passed`**, the log carrying `FR-J no-argument
frame: succeeded=`.

**Corrected figures** (spec §8, §9, edited in this commit): `Handlers` members
**10 → 14** (lane 3's `focusBinding` is the fourteenth; the design read 13);
the measured close is **1837 tests** (1773 + lane 1's 30 + lane 2's 22 + lane
3's 12 = net 11 and G3.1), not the 1825 the design projected, and **113
guards** by the lanes' counting method (108 → 113, +5; a
`.enabled(if: canTypecheck` occurrence count reads 106 → 111, the same +5).

**Still owed by lane 3** (not in this fix round's brief): the named mutations
of `IX-S` (MRk′, MRl, M3a–M3h, M3m, M3n, M3g′) with their reddened sets, G3.1
mutated red once, the fourteen-image offscreen comparison against `31f2e7a`,
and the `Backends/SDL` build.

---

# Part 2 — the accessibility half (plan task 12, part 2)

Rulings `IX-U` onward are **part 2's**: the accessibility half of plan task
12's second sentence. Spec:
[`specs/2026-09-29-accessibility-design.md`](specs/2026-09-29-accessibility-design.md).
Evidence: [`../probes/swiftui-accessibility-part2.swift`](../probes/swiftui-accessibility-part2.swift)
(**new**; arm ids `C…`, `E…`, `H…`, `T…`, `M…`, `N…`, `A…`, `B…`, `G…`, `X…`,
`F…`, `L…`, `I…`, `P…`; header carries the recorded output, run twice
byte-identical, 308 filtered lines, screen locked, every read in-process) and
`swiftui-controls-and-selection.swift` **re-run this session**, compiled
(`xcrun swiftc -o`; its `/usr/bin/swift` JIT form fails to link on macOS 27,
`Symbols not found: ___isPlatformVersionAtLeast`), its LA0–LB3 lines
byte-identical to its header. Record: `docs/record/63-accessibility.md`
(written by the Record phase). Baseline `31d3565`: **1837** tests, **113**
guards, **69** live divergences, next label **95**, `Backends/SDL` 22 + 27.

---

## IX-U — part 2's scope: the collection, and what stays open

**Ruling.** Part 2 disposes of every row part 1 assigned it (record §62 §7:
rows 27–37) and every accessibility item owned by plan task 12 in the
decisions docs' carried tables (`AB-Q`, `DD-U`/`DD-Z` 8/`DD-AB` 4/`DD-AD` 1/
`DD-AE` 2, `TE-O`/`TE-AL`, the grids doc's `AB-Q` rows, `EV-AE`) and in
`Sources/` doc comments (`Image.swift`, `GestureModifiers.swift`,
`NativeTappable.swift`, `Button.swift`) — spec §2's table, 44 rows including
the brief's own items (button role and shortcut, gestures, truncation, the
part-1 controls on both bridges, focus after `IX-I`). Each row is **built**,
**pinned as SwiftUI's**, **amended**, **kept with an owner**, or **routed to
the VoiceOver script**; none is left unclassified.

**What part 2 cannot close.** The plan's text is "validate it with
VoiceOver". An agent can build, probe, pin and write the script; it cannot run
VoiceOver or claim the result. **Task 12's box stays unticked** until a human
runs `docs/verification/voiceover-script.md` and the Record phase re-reads it
(`IX-AE`).

**Not task 12's by their own tables, unchanged**: `Stack` order (divergence
34, owner `AB-P`), row indices for a third-party virtualized container
(unowned, `AB-Q`), system accessibility settings (task 13), iOS (task 14).

**Evidence.** The grep of 2026-09-29; record §62 §7, §9.

**Cost if wrong.** A missed item is found by plan task 15's inventory and
lands as a row there; the table is the list to check it against.

---

## IX-V — `accessibilityElement(children:)`: `.ignore`, `.combine`, `.contain`

**Ruling.** Offered on `StyledElement` and `ProposalElementGroup` with
SwiftUI's spelling and default (`children: .ignore`). `AccessibilityChildBehavior`
is a **closed enum** (`ignore`, `combine`, `contain`) where SwiftUI's is a
struct with static members — `PickerStyle`'s precedent (`DD-V`): nothing
outside can add a behaviour, and `AccessibilityChildBehavior.ignore` spells
the same.

1. **`.ignore`**: one node at the element's id, its declared label, value,
   hint, identifier and traits, **no children, and no text taken from them**
   (E1, E2, E12). Role `.group` where SwiftUI publishes `AXUnknown` —
   divergence **33 amended**, the same reason (`AB-F`: an unknown role reads
   worse to VoiceOver than a group).
2. **`.combine`**: one node. Its text is every non-interactive descendant's
   text plus the **first** interactive descendant's label, tree order, joined
   `", "`, then resolved as a static text is (`AB-F`): a value for a plain
   text, a label where a descendant carries a value (E3, E10, E11); a declared
   label replaces the join (E8). With interactive descendants, the node takes
   the **first** one's role and actions (E6 button, E7 check box, E14 runs
   `A`), and **every** interactive descendant becomes a custom action named by
   its label, tree order (E6 `["B"]`, E14 `["A", "B"]`). The builder returns
   `redirects[combined] = [first, second, …]`: a press or adjustment on the
   combined id runs the first's, custom action `i` runs the `i`-th's press.
   Children are dropped. A gesture written outside adds no press (E13).
3. **`.contain`**: a `.group` node that keeps its declared label and its
   children, and **does not distribute** its label (E5). Over a text leaf it
   is a group with one synthesized static-text child (E9), keyed
   `AccessibilityNodeID(ContainedText(id))` — a key no request resolves, so
   the text child has no actions, as SwiftUI's has none.

**Why implement `.combine`'s custom actions rather than record a
divergence.** The design's first reading (E6/E7 only) was to omit them; E14
showed they are how SwiftUI keeps a second button reachable once combined,
and `IX-Y`'s custom actions make them one table entry each. Omitting them
would make a combined row with two buttons lose one to VoiceOver.

**Evidence.** E1–E14.

**Cost if wrong.** A wrong join rule is one function (`combine`'s text); a
wrong redirect is one dictionary; both are pinned by 2.2/2.3/2.22.

---

## IX-W — `accessibilityHidden`, `accessibilityHint`, `accessibilityIdentifier`

**Ruling.**

1. **`accessibilityHidden(true)`** opens the existing suppression scope
   (`Frame.withAccessibilitySuppressed(except: nil)`, `AB-O`'s mechanism) around
   the element's own registration **and its content**, in
   `PrepaintPass.registerAndScope` and in the proposal wrapper's prepaint —
   nothing inside records (H1, H2), a hidden child contributes nothing to a
   button's fold (H3), an inner `(false)` cannot un-hide (H5: suppression is a
   depth), and on one element the **outer** write wins (H4: `handling` writes
   one field, last write wins — the outer modifier is written last). It does
   **not** touch `hidden()`'s layout, focus or hit behaviour (`IX-K`), and it
   is not a hitbox or focus gate: a hidden button is still clickable, as
   SwiftUI's is.
2. **`accessibilityHint(_:)`** publishes `AccessibilityNode.hint` → AppKit
   `accessibilityHelp` (N1, N3) and AccessKit `description`;
   **`accessibilityIdentifier(_:)`** publishes `identifier` → AppKit
   `accessibilityIdentifier` (N2) and AccessKit `author_id`. Both are
   **distributed** from a plain container exactly as a label is (N4, N5;
   `AB-T`). SwiftUI's `.help(_:)` also publishes `AXHelp` (N6) but is a
   tooltip API and is **not offered** here (owner none).

**Evidence.** H1–H5, N1–N6; `AB-O`, `AB-T`.

**Cost if wrong.** The scope is one call site per conformer family (two:
`registerAndScope`, the proposal wrapper), each pinned by 2.5/2.17.

---

## IX-X — traits, modal isolation, and the demo's modal

**Ruling.**

1. **`AccessibilityTraits`** (SwiftUI's name, an `OptionSet`) offers
   `.isButton`, `.isHeader`, `.isSelected`, `.isLink`, `.isImage`,
   `.isStaticText`, `.isModal`, `.updatesFrequently`, through
   `accessibilityAddTraits(_:)`/`accessibilityRemoveTraits(_:)`. Every other
   SwiftUI trait is **not offered** (guard G2.3), owner none: none has a macOS
   reading in the probe that MetalUI could reproduce.
2. **Each trait sets the role only** (the probe's consistent reading):
   `.isHeader` → `.heading` (`AXHeading`, AccessKit `HEADING`) with the text as
   **label** (T1, T8), distributed from a container (T9), never over a button
   (T11); `.isButton` → `.button` with **no** press (T2, G5); `.isLink` →
   `.link` (T6); `.isImage` → `.image` (T5); `.isStaticText` → `.text`;
   `.isSelected` → `isSelected` on any role (T4, T7). **Removing** `.isButton`
   from a clickable element changes its role to `.group` **after** the
   button fold ran — the folded label and the press stay (T3, T3p).
   `.updatesFrequently` is carried and published nowhere (T10: SwiftUI's is
   invisible on macOS) — a declared-but-inert row, by design.
3. **Modal isolation.** A kept record declaring `.isModal` makes the builder
   publish **only** that record's subtree — the one with the greatest
   `(layer, order)` when there are several — and drop everything else (M1,
   M3; over an overlay's primary, M2); `focused` publishes only inside it.
   This is also **press occlusion's** answer: a client cannot navigate to what
   the modal covers. What a client already **holds** is `IX-Z` item 3's.
4. **The demo's modal** (lane 3, `DemoContent.swift`'s `demoModal()`): the
   scrim gains `.accessibilityAddTraits(.isModal)`; the panel's click absorber
   gains `.accessibilityRemoveTraits(.isButton)` — the "non-button click
   absorber" of `AB-Q`'s table, answered with SwiftUI's own spelling rather
   than a new API. With a client active the modal reads as one root (`Close
   modal`, a button) holding a group labelled with the modal's two texts;
   nothing behind the scrim is published until it closes. **Named state-table
   change**: the panel now declares an `AXNode`, so while the modal is up it
   writes one more `$ax` slot (`AB-U`) — no id path moves, and the demo
   reaches no `TB-AH` threshold with it. **0 px** in all fourteen offscreen
   images; `Expected.swift` unedited (accessibility modifiers draw nothing).

**Evidence.** T1–T11, T3p, M0–M4; `AB-U`, `AB-V`.

**Cost if wrong.** A trait's role is one `switch` arm; isolation is one pass
in the builder (2.10); the demo change is two modifiers (3.8).

---

## IX-Y — declared and named actions; gestures; `AXNode.actions`

**Ruling.**

1. **`accessibilityAction(_:)`** registers an `AccessibilityDefaultAction`
   handler through `onAction` (stored in `Handlers.actions`, reached through
   the focus registry exactly as `accessibilityAdjustableAction`'s
   `AccessibilityAdjustment` is — no hitbox, not focusable, refused when
   disabled or hidden). The node gains `.press` and, when generic, the
   `.button` role (A1), distributed from a container (A5). **On an element
   with its own `onClick` the declared action replaces the click's press**
   (A4) — a mouse click still runs `onClick`. Disabled refuses (A7).
2. **`accessibilityAction(named:_:)`** chains into one
   `AccessibilityNamedAction` handler that dispatches by name, and prepends
   the name to the declared list, so the later-written action publishes
   first (A6). Published as `AccessibilityNode.customActions`; a
   `.customAction(id, index)` request runs it (A2); a button's own press is
   untouched (A3).
3. **Gestures publish no press** — `TapGesture`, count-2 taps, `LongPressGesture`,
   `DragGesture`, `onTapGesture` (G1–G5, G7): SwiftUI's answer, and already
   MetalUI's (`AB-Y`, `synthesizesAccessibility: false`), now pinned (2.14).
   **Divergence 27 amended**: it is now only that MetalUI's own `onClick` is
   pressable; SwiftUI has no `onClick` to compare. `OnTapModifier`'s
   ("an `onTap` control's VoiceOver presence", `TE-O`) answer is the same:
   its content publishes, the tap does not, and `.accessibilityAction {}` is
   the remedy SwiftUI's G6 shows (it runs the action, not the tap).
4. **`AXNode.actions` and `AXActionKind` are deprecated** toward
   `accessibilityAction(_:)`/`accessibilityAdjustableAction(_:)` — actions are
   derived from live handlers (`AB-H`), so the declared field could never mean
   anything; no in-repo caller writes it (the `actions: [.press]` hits are the
   platform `AccessibilityNode`'s), so the 0-`warning:` baseline holds.
   `AXNode.init`'s `actions:` moves to a deprecated overload. The inert row
   stays (amended) until plan task 15 removes the field.

**No `Handlers` member is added**: both handlers ride `Handlers.actions`; the
names ride `AXNode`'s box. The declarations cost `Handlers` at most one
pointer (2.19).

**Evidence.** A1–A7, G1–G7; `AB-H`, `AB-I`, `AB-Y`.

**Cost if wrong.** If VoiceOver users prefer a button's own press to survive a
declared action, it is the press order's first line (§6); the named-action
order is one prepend.

---

## IX-Z — the press: under `allowsHitTesting(false)`, its order, focus, and occlusion

**Ruling.**

1. **Divergence 28 retires.** SwiftUI presses a `Button` under
   `allowsHitTesting(false)` (B6, P1 re-run). MetalUI now does too: when the
   hit-testing gate withholds a hitbox from an enabled element with an
   `onClick`, `Frame.registerHandlers` records the handler in
   `Frame.accessibilityPressOnly` — **only while collecting**, so a window with
   no client pays nothing — the builder advertises `.press`, and `Window` runs it. A
   mouse click at the same point still finds nothing (`OM-T`, `OM-AK`
   unchanged). `aPressIsRefusedWhereHitTestingIsDisabled` is **renamed**
   `aPressIsRunWhereHitTestingIsDisabled`, its answer flipped by this ruling.
   A tap gesture under the gate does not press (B8) — gestures never press
   (`IX-Y` 3). Disabled refuses (B7).
2. **The press order**: a declared `AccessibilityDefaultAction`; a combined
   node's redirect; the last `onClick` hitbox; the press-only handler. Each
   through `Window.runClick`, so a press keeps `ClickDispatch.modifiers == []`
   and honours a handler's focus request (`DD-AE` item 2's "if task 12 rules
   that a press must not focus": **it is ruled to keep focusing** — one path
   with the click, so the two cannot drift; SwiftUI's answer needs a key
   window and is unmeasured, so this is MetalUI's choice, with a script step).
3. **Occlusion of a held element — divergence 95, added.** When the last
   published tree was built under modal isolation, a request naming an id it
   does not contain is **refused** (and the AppKit element for it is already
   detached, `AB-D`). SwiftUI's held element still presses after an `.isModal`
   cover appears (M5). Kept, owner none: VoiceOver cannot reach an unpublished
   element through navigation, only a client that cached a handle can, and
   refusing is the safe side (`AB-H`'s own principle: never let a client
   operate what the user cannot see offered).

**Evidence.** B6, B7, B8, M5; P0/P1; `AB-D`, `AB-H`, `DD-AE`.

**Cost if wrong.** Item 1 is one dictionary and one lookup; item 3 one guard
(2.24).

---

## IX-AA — settable selection, and the `List`'s AppKit role

**Ruling.**

1. **Divergence 83 retires on the AppKit bridge.** A selectable row
   (`AccessibilityNode.isSelectable`, a row of a `List(selection:)`) accepts
   `setAccessibilitySelected(true)` → `.select(row)`, which **replaces** the
   selection with that row in a single or a multi list (LA2, LB3); the outline
   accepts `setAccessibilitySelectedRows(_:)` → `.selectRows(table, rows)`,
   which sets exactly those rows, and a single-selection list **ignores** a
   request for more than one (LA3, LB2, LA4). `(false)` sends nothing (the
   probe has no arm deselecting; MetalUI's choice). `Window` routes both to the
   list's `AccessibilityRowSelection` handler, registered by `List.swift` beside
   the click selection and gated as every action is (a disabled list refuses).
   `anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly`
   is **renamed** `settingAXSelectedOnARowReplacesTheSelection`, its AppKit half
   flipped by this ruling; its press half is kept.
2. **AccessKit**: 0.23's action enum (header lines 72–146) has **no select
   action**, so an AccessKit client selects a row by `Click` (the press, as
   today), and a selectable row now publishes `selected` **false** as well as
   true — AccessKit's "selectable, not selected". Not a divergence: SwiftUI has
   no AccessKit side to compare.
3. **Divergence 32 amended.** The AppKit bridge publishes a `List` as
   `AXOutline` with `AXRow`/`AXOutlineRow` rows (L1, R16, LA0) — SwiftUI's
   role — where it published `AXTable`; the neutral role stays `.table` and
   AccessKit keeps `TABLE`/`ROW`. **What stays**: only realized rows are
   published (SwiftUI's 500 are all reachable through `AXRows`, L1) — kept,
   owner none: publishing unrealised rows would mean elements with no
   geometry and no element under them, against `List`'s windowing, which the
   plan keeps. The VoiceOver script records what VoiceOver does at the last
   realized row.

**Evidence.** LA0–LB3 (re-run), L1, R16; `accesskit.h`.

**Cost if wrong.** A role mapping is one `switch` arm (AppKit's role table is
a T row); the selection semantics are the list's handler (1.12–1.14 —
renumbered from 2.25–2.27 and moved to lane 1 by `IX-AF` item 1).

---

## IX-AB — the proposal path, grids and images

**Ruling.** `AB-Q`'s "proposal-path emission" is closed:

1. **`ProposalText` records its string** as a text leaf in prepaint through a
   new internal `Frame.recordAccessibility(text:declared:at:id:)` — gated on
   `collectsAccessibility` alone, registering no hitbox, focus entry or
   `StateTable` slot, reading `isEnabled` and the suppression as
   `registerHandlers`' record does. So an `HStack`/`VStack`/`ZStack`/`Grid`'s
   texts publish in reading order, a grid row by row, and the container itself
   publishes nothing (P1, P2, P4) — SwiftUI's answer. `Text.proposalLayout()`
   keeps its string, so a legacy `Text` converted into a proposal stack
   publishes too.
2. **`AccessibilityModifier<Content>`** carries the proposal modifiers: one
   cursor index, its one child numbered from 0 under it (`GestureModifier`'s
   shape), registering its declared node and actions through
   `registerHandlers` (a declared node writes one `$ax` slot, `AB-U`, as the
   legacy modifiers do). Additive: only a caller who writes it gains the
   level (P3, P5).
3. **Images.** `Image(decorative:scale:)` publishes nothing, even labelled or
   tapped (I2, I4, I5) — SwiftUI's answer and already MetalUI's.
   `Image(_ bitmap: ImageBitmap, scale: Float, label: Text)` — SwiftUI's
   `Image(_:scale:label:)` with `ImageBitmap` for `CGImage` and `Float` for
   `CGFloat` (`TE-AQ` item 9) — records an `.image` node labelled by the
   text's string (I1, I3).

**Evidence.** P1–P5, I1–I5; `AB-Q`, `TE-AL`, `GR-K`.

**Cost if wrong.** Each is one internal call site (2.15, 2.18) or one wrapper
(2.16, 2.17).

---

## IX-AC — buttons, truncation and focus, pinned as SwiftUI's

**Ruling.** Three concepts the brief names need no new behaviour, only pins:

1. **`Button(role:)`, `.keyboardShortcut`, `.buttonStyle`** publish nothing
   but the button's label and press (B1–B5). A keyboard shortcut has no
   accessibility attribute in SwiftUI or in AppKit's own `NSButton` (C2), so
   neither bridge publishes one — AccessKit's `keyboard_shortcut` stays unset
   (`IX-AD`). `ButtonRole`'s inert row gains this evidence.
2. **A truncated or line-limited `Text` publishes its whole string** (X1–X4),
   on both `Text` and `ProposalText` and inside a `Button`.
3. **Focus and accessibility after `IX-I`**: an accessibility focus request
   (`.focus`) moves window focus and, on the next frame, the `@FocusState`
   bound to it (F2, arm 13); a `@FocusState` write is the tree's `focused`
   (F1); focus leaves the tree when its identity is renamed (`IX-I`), and
   AppKit posts `.focusedUIElementChanged` on the host. **Divergence 31 is
   untouched**: F4 answered the host where arm 13 (unlocked, 2026-09-15)
   answered its first focusable node — the arms differ in screen state, so F4
   separates nothing.

**Evidence.** B1–B5, C2, X1–X4, F1–F4, arm 13.

**Cost if wrong.** Each is a pin (3.1–3.5); a later SwiftUI change reddens a
probe re-run, not the suite.

---

## IX-AD — bridge parity

**Ruling.** Both bridges translate **every** field of the neutral
`AccessibilityNode` (14 after this part) and every role; parity is enforced
mechanically: each bridge's test file holds a field → attribute table whose
entry count must equal a `Mirror` of `AccessibilityNode` (1.4 AppKit, 1.8
AccessKit), so a new neutral field with no arm in either bridge reddens that
bridge's test. The platform vocabularies differ by design, one row each:

| neutral | AppKit | AccessKit |
|---|---|---|
| `hint` | `accessibilityHelp` | `description` |
| `identifier` | `accessibilityIdentifier` | `author_id` |
| `customActions` | `accessibilityCustomActions` (`NSAccessibilityCustomAction`, index-keyed handler) | `push_custom_action` (id = index) + `CUSTOM_ACTION` |
| `isSelectable` | the two selection setters allowed | `selected` false as well as true |
| `.heading` / `.link` | `AXHeading` / `AXLink` | `HEADING` / `LINK` |
| `.table` / `.row` | `AXOutline` / `AXRow` + `AXOutlineRow` | `TABLE` / `ROW` |

The controls demo's tree translates on both (3.7 against 3.6's table).
AccessKit's own `modal` flag is not set: the tree is already isolated.

**Evidence.** `accesskit.h` (0.23.0); the AppKit SDK.

**Cost if wrong.** A mapping is one arm per bridge, pinned by name.

---

## IX-AE — lanes, the VoiceOver script, and the tick

**Ruling.**

*(Item 1's cut and item 2's markers are amended by `IX-AF` items 1 and 7.)*

1. **Three lanes, disjoint files, run in order**: lane 1 the neutral tree and
   both bridges (hand-built trees, as the existing bridge tests are); lane 2
   every `Sources/MetalUI` file — modifiers, builder, proposal path, dispatch,
   `List` selection; lane 3 the audit tests, the demo modal's two modifiers
   and the script. **One declared exception**: lane 1 adds a single refusing
   arm to `Window.handleAccessibilityRequest` for its new request cases (the
   `switch` is exhaustive), replaced by lane 2. Opus for lanes 1–2, the script
   and audit lane may run on Sonnet only where it writes docs.
2. **The script** (`docs/verification/voiceover-script.md`, spec §9) walks the
   demo, the controls demo and the text-input demo; every step's expected
   output comes from a tree 3.8/3.9 pins, carried in a machine-checked
   `<!-- ax: … -->` marker (3.10), with VoiceOver's usual spoken order stated
   as an expectation, never as a measurement. Every "if task 12's VoiceOver
   validation prefers…" cost (`DD-U` item 3, `DD-AD` item 1, `DD-AE` item 2,
   divergences 32, 82, 95) is one step naming its ruling. Each step has an
   **observed (human)** column, pass/fail and notes; a header takes the
   tester, date, macOS and VoiceOver versions.
3. **The tick.** Part 2 landing does **not** tick plan task 12. The Record
   phase writes a dated progress note: part 2 delivered, and **the box stays
   unticked until a human has run the script, recorded every step, and the
   Record phase has re-read it**. No agent writes an observed result.

**Evidence.** Spec §7, §9; record §12's first script, never run.

**Cost if wrong.** A step whose expectation is wrong is corrected when the
human reports it — which is the script's purpose.

---

## IX-AF — the critic round: seven amendments, two rejections

**Ruling.** The design critic (2026-09-29, one agent, after `50809ed`)
re-ran `swiftui-accessibility-part2.swift` with the header's own command —
all 308 filtered lines **byte-identical** to the recorded run (arms E14, M5,
B6, A4 and T3p diffed individually, each identical), screen locked — and
attacked the design. Amendments, each written into the spec:

1. **Lane 2 was too large; the cut moves** (`IX-AE` item 1 amended). Lane 2
   held 27 tests and 3 guards over fifteen files, lane 1 eight. The settable
   selection and the press under `allowsHitTesting(false)` need no new
   modifier — each is the dispatch end of a request case lane 1 adds — so
   old 2.13, 2.21, 2.25, 2.26, 2.27 move to lane 1 as **1.10–1.14** (1.11 and
   1.12 are still the two renamed pins, flipped by `IX-Z` and `IX-AA`). The
   lanes are no longer file-disjoint (`Frame.swift`,
   `AccessibilityTreeBuilder.swift`, `Window.swift`, `WindowAccessibility.swift`
   are shared), so they run **strictly in order**; lane 1's stub arm shrinks to
   `.customAction`. Lane 1 fetches AccessKit into this worktree first (none is
   present). Totals move to **1880** tests (below).
2. **`AXNode.actions`' deprecation mechanics** (`IX-Y` item 4 amended): the
   deprecated initialiser's `actions:` takes **no default** (with one,
   `AXNode(role:label:)` is ambiguous — G2.2's control arm pins it); the
   stored property keeps `= []` so the undeprecated initialiser never names
   it; the synthesized `==`/`isEmpty` must build with 0 `warning:`, else `==`
   is hand-written inside a deprecated helper — the deprecation is not
   dropped.
3. **A declared action is a declaration** (`IX-Y` item 1, `IX-AB` item 2
   amended). `registerHandlers`' `hasSomethingToSay` gated every
   handler-derived record on `synthesizesAccessibility`; a declared action or
   named action is added **outside** that gate, or `HStack{}.accessibilityAction {}`
   and G6 on a non-synthesizing conformer publish nothing (mutation M2n′).
   And, explicitly: every `AXDeclarations` field counts toward
   `AXNode.isEmpty`, so a caller of any new modifier declares a node and
   writes one `$ax` slot with or without a client, as `accessibilityLabel`
   does — no existing call site writes one, so no retention moves beyond the
   demo panel's named slot (`IX-X` item 4). A combined node that also declares
   named actions lists the declared ones first — MetalUI's choice, no arm has
   both.
4. **`ProposalText`'s record changes an answer**, so it is not "must stay
   green, unedited" by assertion (`IX-AB` item 1 amended): lane 2 greps for
   every test building proposal text with a client active and runs it at its
   stub commit; any that moves is a named T row in its landing ruling. The
   main demo holds no proposal element, so 3.8 is unaffected; the preview's
   tree gets its own pin, **3.11**, and the script a preview step — `AB-Q`'s
   "the preview toggle is silent" cost, which the design's script omitted.
5. **Overload resolution is pinned**: no type conforms to both
   `StyledElement` and `ProposalElementGroup` (grep), so
   `Box().padding(1).accessibilityLabel(_:)` stays `Self` and gains no identity
   level; G2.1 asserts both results' static types. `AccessibilityModifier`
   preconditions exactly one child node (`SA-G`), pinned by an exit test in
   2.16. 2.14 runs every gesture arm on **both** spellings
   (`StyledElement.onTapGesture`/`.gesture` and the proposal
   `GestureModifier`/`OnTapModifier`).
6. **`AB-AE` for the new overrides** (`IX-AD` amended): the existing exit test
   covers label, children, the selector check and the press only; new **1.9**
   (`theNewAppKitOverridesAnswerNothingOffTheMainThread`, an exit test) pins
   help, identifier, custom actions and the three selection overrides, each
   through `mainActorAnswer`.
7. **The script's markers carry every fact a step speaks** (`IX-AE` item 2
   amended): 3.10 compared role, label and value only, while the steps name
   selected state, row counts, custom actions and "cannot reach behind the
   modal". Markers now carry every such field, an `ax-absent` marker asserts
   the modal's isolation, and a spoken claim no tree can carry (a
   `.valueChanged` announcement, VoiceOver at the last realized row, a VO
   key's effect) is labelled **(VoiceOver behaviour, not pinned)** and counted
   by 3.10 — never presented as derived.

**Rejected, with reasons:**

- *"Divergence 95 should be avoided by letting a held element press, as
  SwiftUI does (M5)."* Rejected: `IX-Z` item 3's reason stands — only a client
  that cached a handle can reach it, and `AB-H`'s principle is never to let a
  client operate what the user is not offered. The divergence is recorded,
  not hidden.
- *"Record rejections as `LR-` rulings."* The dispatch's template names
  `LR-`, the engine-replacement prefix, whose doc this task does not own;
  part 2's rulings live under `IX-` in this doc (`IX-U`), so rejections are
  recorded here.

**Checked and found sound** (no change): the probe (above); `.combine`'s
redirect indexing against E6/E14; `IX-AA`'s AccessKit reading (0.23's action
enum has no select action; a row selects by `Click`); the neutral field count
(10 at `31d3565` + 4 = 14, `AccessibilityTree.swift`); `ContainedText`'s key
through AccessKit's id table (`AccessKitTree.swift`'s `numbers` map accepts any
`AccessibilityNodeID`); the neutral `.table` role, so every root test reading
`role == .table` is unaffected and only `AppKitAccessibilityTests`' role table
is a T row; `IX-AE` item 3 — no agent claims the VoiceOver validation.

**Counts after this ruling**: lane 1 +8 root (1845) and SDL +4; lane 2 +22
tests and +3 guards (1870, 116); lane 3 +10 (1880) and SDL +1. Expected close
**1880 tests, 116 guards, SDL 22 + 32**.

**Evidence.** The probe re-run of 2026-09-29; `Frame.swift`
`registerHandlers` (`hasSomethingToSay`); `AXNode.swift`'s initialiser;
`AppKitAccessibilityTests.anOffMainThreadQueryAnswersNothingAndDoesNotTrap`;
`AB-Q`'s cost list.

**Cost if wrong.** Each amendment is one test or one clause; the lane move is
reversible by renumbering.

---

## IX-AG — lane 1 landed: the neutral tree through both bridges, the press under `allowsHitTesting(false)`, and a client's selection (and eight clauses the design left open)

**Ruling.** Lane 1 of part 2 (spec §7 "Lane 1", tests 1.1–1.14) landed in two
commits: `9da8d45` (red: the neutral types as stubs, every test, the two
renamed pins and the two T rows) and `dcd6339` (green). What it built is the
spec's §4 neutral tree and §6 bridges and requests as written, plus these
clauses, each MetalUI's choice unless a probe arm is named:

1. **The parity tables found two fields with no arm** (`IX-AD` amended; spec
   §6 amended). AccessKit translated neither `rowCount` nor `rowIndex`: they
   now reach `accesskit_node_set_row_count`/`set_row_index` (snapshot fields
   `rowCount`/`rowIndex`, part of `Node.==` so a change publishes). **T row**:
   `aMetalUITreeTranslatesToAccessKitsVocabulary`'s table and row literals
   gain `rowCount: 1`/`rowIndex: 0` — its answer changed by this ruling, not a
   retirement. AppKit read `isFocusable` nowhere: `isAccessibilitySelectorAllowed`
   for `setAccessibilityFocused(_:)` now answers `isFocusable` (attached only),
   so `AXFocused` is settable exactly where `Window` would honour the `.focus`
   request (AB-J); before, `NSAccessibilityElement`'s default allowed it on
   every element and the window refused. No dispatch moves.
2. **A row answers subrole `AXOutlineRow`** (L1, LA0), every other node none;
   `.heading` is spelled `NSAccessibility.Role(rawValue: "AXHeading")`
   (`NSAccessibilityHeadingRole` is macOS 26 API; the package targets 14);
   a node with no identifier answers `""` (the protocol's non-null
   `NSString`), a node with no hint `nil`.
3. **A custom action's handler is built in a `nonisolated static` function**
   (`customActionHandler`), so the closure AppKit calls carries no main-actor
   isolation and reaches the element only through `mainActorAnswer` — a
   closure formed inside the `@MainActor` element would carry that isolation,
   and a held handler called off the main thread would trap instead of
   answering `false` (1.9 calls one off the main thread). It holds its
   element weakly and sends nothing once the element is detached or the index
   is out of range.
4. **`isSelectable` is derived by the builder, not declared**: a `.row` whose
   published parent registered an `AccessibilityRowSelection` handler this
   frame. So `AXNode` (lane 2's file) gains no hint, and a disabled or hidden
   list's rows are not offered as selectable (1.14 asserts it).
5. **Selection semantics beyond the arms**: `setAccessibilitySelected(false)`
   sends nothing (`IX-AA` item 1); a `.selectRows` naming a row the table did
   not publish, or a non-table as the table, is refused; an empty `.selectRows`
   sets `nil`/`[]` (unprobed); a single list ignoring two rows (LA4) still
   answers `true` — the list answered the request, as a press whose handler
   writes nothing does; an accessibility selection **asks for no focus**
   (a row click does, `DD-Z` item 5 — setting `AXSelected` is not a press)
   and stores the lead and anchor as a click does. The handler runs under
   `StateDispatch.dispatching(to: list)` (`ID-F`).
6. **The press-only record** (`Frame.accessibilityPressOnly`, surfaced as
   `Window.lastAccessibilityPressOnly`) skips a suppressed subtree (it records
   no node, so it advertises nothing) and keeps the last registration per id.
   The builder takes it as `pressOnly:` (default empty, so every other caller
   is unchanged). `Window`'s press tries the last `onClick` hitbox, then the
   press-only handler, both through `runClick` (`IX-Z` item 2); lane 2 adds
   its two arms ahead of these.
7. **`.customAction` is refused** by a stub arm naming lane 2 (the `switch`
   is exhaustive), exactly as an unknown id is refused today.
8. **Two test defects found at green, fixed in the tests**: 1.4's `rowCount`
   arm asserted `accessibilityRowCount() == 0` on a row, but the existing
   override answers the neutral field for any role (rewritten to `== 7`, the
   field's own answer); and 1.13/1.14 discarded their `Window`s with `_`, so
   `FakePlatformWindow` (which holds its window weakly) sent requests to
   nothing — 1.13's multi arm failed and 1.14's disabled refusal **passed for
   the wrong reason**. Every window is now kept alive to the test's end
   (`withExtendedLifetime`). A refusal assertion needs a live receiver; M1n
   below is the mutation that proves 1.14's does.

**Red before** (`9da8d45`, full unfiltered suite): `Test run with 1845 tests
in 3 suites failed … with 41 issues` — exactly the ten lane-1 tests red: 1.1
(`accessibilityRole() == AXHeading`, `accessibilityHelp() == "The page
title"`, `accessibilityIdentifier() == "page.title"`, `.link`, `.outline`,
`.outlineRow`), 1.2 (`mail.accessibilityCustomActions()` nil), 1.3 (the
setter not allowed, no `.select`/`.selectRows`, `selectedRows` empty), 1.4 (five
arms and the focusable control), 1.9 (`.signal(SIGTRAP)`: the control arm's
precondition on the main thread), 1.10 (`actions == [.press]`, the map
empty), 1.11 (`actions == [.press]`, the press refused, `count == 1` twice),
1.12 (no request reached the window, `multiWrites`/`singleWrites`), 1.13 and
1.14 (the stub refuses); the AppKit role table T row (`accessibilityRole() ==
role`, line 211) filtered separately. SDL: `31 tests … failed with 22 issues`
— 1.5 (roles, description, author id, custom actions), 1.6 (`off.has_value &&
!off.value`), 1.7 (`queued == .customAction(number, 1)`, the request, the
no-data arm), 1.8 (seven arms), plus the translation T row (two `got == want`).

**Green** (`dcd6339`, after `swift package clean` at the red commit — three
public types changed shape): `swift build --build-system native --build-tests`
0 `error:`, the one `warning:` SwiftPM's deprecation notice; `swift build
--build-tests` (default system) 0 `error:`/`warning:`; unfiltered `swift test
--build-system native --no-parallel` → **`Test run with 1845 tests in 3 suites
passed after 112.771 seconds`**, the log carrying `FR-J no-argument frame:
succeeded=` (guards ran; **113** unmoved). `Backends/SDL`
(`PKG_CONFIG_PATH=Backends/SDL/.accesskit`, fetched into this worktree with
`fetch-accesskit.py`): **22 + 31** passed. `MetalUILayout` imports
`MetalUICore` alone. **0 px against `31d3565` in all fourteen offscreen
images, every scene identical** (`compare.sh … 31d3565 dcd6339`; its controls
read as at `31d3565` itself). The real-window capture was **not taken**: the
lock probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`.

**Mutations** (each applied from `dcd6339` with the spec edit the only
uncommitted change, restored from a copy, the whole suite run unfiltered —
root 1845 or SDL 22 + 31 — `git status --short` clean of source after each;
**every** test reddened named; `noConformerEmitsAnAXNodeItDidNotDeclare` green
under all):

| id | mutation | reddened |
|---|---|---|
| M1a | the hint answered as `accessibilityLabel` (help `nil`) | `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline`, `everyAccessibilityNodeFieldHasAnAppKitArm`, `theNewAppKitOverridesAnswerNothingOffTheMainThread` |
| M1a′ | `.table` back to `AXTable` | `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline`, `rolesLabelsValuesAndTraitsMapOneToOne` (the T row) |
| M1b | custom-action handlers numbered from 1 | `theAppKitBridgesCustomActionsRequestByIndex`, `theNewAppKitOverridesAnswerNothingOffTheMainThread` |
| M1c | the selected setter allowed on every row | `anOutlineRowAcceptsAXSelectedOnlyWhenSelectable` |
| M1d | the identifier answer dropped (`""`) | `everyAccessibilityNodeFieldHasAnAppKitArm`, `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline`, `theNewAppKitOverridesAnswerNothingOffTheMainThread` |
| M1i | `accessibilityHelp` through a bare `MainActor.assumeIsolated` | `theNewAppKitOverridesAnswerNothingOffTheMainThread` (child traps) |
| M1j | the press-only record removed | `aPressIsAdvertisedWhereHitTestingIsDisabled`, `aPressIsRunWhereHitTestingIsDisabled` |
| M1j′ | recorded without a client | `aPressIsAdvertisedWhereHitTestingIsDisabled` |
| M1k | the press-only map not consulted by `Window` | `aPressIsRunWhereHitTestingIsDisabled` |
| M1l | `.select`/`.selectRows` add to a multi selection | `settingAXSelectedOnARowReplacesTheSelection`, `settingTheOutlinesSelectedRowsSetsThemAndASingleListIgnoresTwo`, `aDisabledListRefusesAnAccessibilitySelection` (its enabled control) |
| M1m | a single list takes the first of two | `settingTheOutlinesSelectedRowsSetsThemAndASingleListIgnoresTwo` |
| M1n | the row-selection handler registered past the disabled gate | `aDisabledListRefusesAnAccessibilitySelection` |
| M1e | (SDL) the description not set | `theAccessKitSnapshotCarriesHintIdentifierHeadingLinkAndCustomActions`, `everyAccessibilityNodeFieldHasAnAccessKitArm` |
| M1f | (SDL) `selected = false` not set | `aSelectableRowPublishesSelectedFalseToAccessKit`, `everyAccessibilityNodeFieldHasAnAccessKitArm` |
| M1g | (SDL) the custom action's index ignored (always 0) | `anAccessKitCustomActionMeansACustomActionRequest` |
| M1h | (SDL) custom actions not pushed | `theAccessKitSnapshotCarriesHintIdentifierHeadingLinkAndCustomActions`, `everyAccessibilityNodeFieldHasAnAccessKitArm` |

**Counts**: root **1837 → 1845** (+8: 1.1–1.4, 1.9, 1.10, 1.13, 1.14; 1.11
and 1.12 renames; the AppKit role table a T row), guards **113** unmoved, SDL
**22 + 27 → 22 + 31** (1.5–1.8; the translation test a T row). No test
removed; `goldensUnchanged`: every retained test's answer is unchanged except
the four ruled (the two renamed pins, `IX-Z` item 1 and `IX-AA` item 1; the two
T rows, `IX-AA` item 3 and item 1 above). Spec §11's expected figures hold.

**Evidence.** The logs above; `accesskit.h` 0.23.0 (`row_count`, `row_index`,
`custom_action`, `ACCESSKIT_ACTION_DATA_CUSTOM_ACTION`); the SDK's
`NSAccessibilityConstants.h` (`NSAccessibilityHeadingRole` macOS 26).

**Cost if wrong.** Items 1–2 are one arm each per bridge, pinned by the parity
tables; item 5's choices are one line each in `List.accessibilityRowSelection`.
