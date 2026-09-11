# `@State`, hit testing and input dispatch — decisions taken during execution

Rulings from the milestone that gave this framework element state, one hitbox list,
hover and active, click dispatch, a focus tree, actions, keymaps, context predicates
and two-stroke sequences. Prefixed **`IN-`** and **lettered** (`IN-A`, `IN-B`, …) per
this repo's convention — **a bare `IN-3` is a typo, not a citation.**

Read alongside `docs/superpowers/specs/2026-08-29-input-and-state-design.md` (§7 is
the exit criteria, §8 the risks recorded up front) and
`.superpowers/sdd/2026-08-29-input-and-state/progress.md`, the execution ledger these
rulings are drawn from. Where a ruling was *made before* the work and then either
confirmed or contradicted by measurement, that is said rather than smoothed over —
three of them below were settled the opposite way from how they were framed.

**Eleven tasks, 609 → 736 tests, 81 goldens unmoved throughout.** No golden moved at
any point in the milestone, which was exit criterion 2 and is the standing check that
input never reached the layout engine. (609 is the branch's baseline, from the
execution ledger's own first line; 729 → 736 is Task 11 alone, and this sentence said
that until it was checked — the same class of error this milestone caught and
annotated for the 577-vs-609 confusion in CLAUDE.md's Build section.)

---

## IN-A — `State` is `@MainActor` as a whole struct, not just its accessors

**The choice.** `@propertyWrapper @MainActor public struct State<Value>`, rather than
annotating `wrappedValue` alone.

**Reasoning.** `StateTable` is `@MainActor`, so `wrappedValue`'s accessors — which
call straight into `peek`/`write` — cannot be un-annotated at all; that half was
forced, and measured with `swift build` rather than argued (the plan's sketch did not
compile). The narrow alternative, annotating only `wrappedValue`, *does* compile and
leaves `State.bind(to:id:slot:)` independently callable from a nonisolated context —
a compiler-invisible data race on the shared `Box`, since `bind`'s writes would race
`wrappedValue`'s isolated reads. Whole-struct annotation closes that.

**It constrains nothing new.** `Element` is already `@MainActor`, so constructing any
conformer from a nonisolated context already fails, the compiler's own note citing
"isolation … inferred from conformance to protocol 'Element'". The local precedent is
`Passes.swift`, where `LayoutPass`/`PrepaintPass`/`PaintPass` are whole-type
`@MainActor` structs wrapping `StateTable` calls.

**What it costs if wrong.** An isolation annotation that turns out unnecessary — and
it is load-bearing on the `bind` path, so the cost is bounded to reading as heavier
than needed. It also **resolved a pre-dispatch ruling about Task 2's per-type cache
before that task started**: with `State` and `Element` both main-actor isolated, the
reflection cache can be too, so the `nonisolated(unsafe) static var` shape that
shipped a real data race in the previous milestone never arose.

---

## IN-B — the per-type reflection cache is a plain `@MainActor enum`, and `BindableState` itself must be `@MainActor`

**The choice.** `StateBinder` is a `@MainActor enum` with ordinary `static` state. The
existential `BindableState` carries `@MainActor` on the **protocol**, not only on the
conformance.

**Reasoning.** The protocol annotation is not stylistic: `extension State:
BindableState {}` alone fails with "conformance of `State<Value>` to protocol
`BindableState` crosses into main actor-isolated code". No `unsafeBitCast`, no
workaround. And the cache is read and written only from main-actor call sites, so the
compiler — not a comment — is what rules out a concurrent increment.

**What it costs if wrong.** If layout ever moves off the main actor, this cache and
`Text`'s `MainActor.assumeIsolated` measure closure are the two things that break, and
the second one *terminates the process* rather than reddening (CLAUDE.md records it).
Neither is a silent failure.

---

## IN-C — `StateTable.isDirty` is a pure test observable; the production mechanism is the `onWrite` hook

**The choice.** `StateTable` gained **both** an `isDirty` flag and an `onWrite`
closure. `Window` points `onWrite` at `setNeedsRedraw()` and reads `isDirty` nowhere.

**Reasoning.** `drawFrameIfNeeded` begins `guard needsRedraw` and *pauses the display
link* when clean. A flag only that method consults is unreachable while the link is
paused — which is exactly the state an idle window sits in, and idle-then-click is the
counter demo's whole interaction. The flag alone would leave the window frozen after
the first `@State` write from a paused state.

**And `isDirty` was deliberately NOT given a production reader afterwards.** Making
`Window` consult it would manufacture load-bearing-ness: every write fires `onWrite →
setNeedsRedraw()`, so `isDirty` can never be true while `needsRedraw` is false and the
branch would be unreachable by construction. An honest inert flag with a row in
CLAUDE.md's declared-but-inert table beats an unreachable branch.

**What it costs if wrong.** Two mechanisms for one fact, which can disagree. Mitigated
by making `setNeedsRedraw` the only consumer that matters. Kept rather than deleted
because it is the observable four verified tests read and two of them construct no
`Window` at all.

---

## IN-D — a `@State` write goes through `StateTable.write`, never through `withState`

**The choice.** `State`'s setter calls a new `write(_:_:)` that marks the table dirty.
`withState` is untouched.

**Reasoning.** `ScrollView` writes its offset through `withState` during prepaint,
every scrolled frame. Raising the dirty flag inside `withState` would mark the window
dirty on every such frame, so the display link would never pause — which is milestone
4's exit criterion, sabotaged from inside milestone 3.

**A finding the ruling produced rather than anticipated.** `write`'s own
`marked.insert(id)` is unguarded and deleting it leaves the whole suite green, because
`StateBinder.bind` marks every slot every frame anyway. It becomes load-bearing for a
write made on a frame where the element is *not* produced — the out-of-band
click-handler write `onWrite` exists to serve. Now pinned by
`writeMarksTheSlotLiveSoItSurvivesTheNextSweep`.

**What it costs if wrong.** An idle window burns a frame forever, which the test the
ruling names catches.

**Correction to a sibling ruling, recorded rather than quietly dropped.** The dirty
flag is cleared *before* `renderRoot` rather than after, and the original reasoning
("clearing after swallows a write made during the frame") is **wrong**: a write during
render fires `onWrite` and sets `needsRedraw`, which nothing clears again before the
function returns, so the write is unswallowable either way. Clear-before-render is
coherence maintenance for the test observable, not a production behaviour, and
`drawFrameIfNeeded`'s comment now says so.

---

## IN-E — a hitbox record carries BOTH the element id and a per-frame index, and it is a struct

**The choice.** `insertHitbox(_ bounds:id:opaque:)` takes the owning element's
`GlobalElementID` and returns a `HitboxID`, a dense index into this frame's list.
`Hitbox` is a struct, not a tuple.

**Reasoning.** The two ids answer different questions and neither substitutes. A
`HitboxID` cannot persist — the list is rebuilt every frame — so active state and the
scroll payload both need the `GlobalElementID`; and requiring the element id *at
registration* is exactly what let scroll regions fold into this list without losing
their key. The struct rather than the four-tuple `scrollRegions` used to be, because a
fifth positional field reads badly and the fold added a sixth.

**The record has four fields, not the ruling's five.** The fifth candidate was the
registration index, which is already the array position — storing it too would be
redundant state free to desync.

**What it costs if wrong.** `insertHitbox` takes an argument some caller has no
natural value for. Mitigated by every prepaint site already having its element id in
hand.

---

## IN-F — scroll regions unify on `insertHitbox`'s translating convention (a bug fix, not a behaviour change)

**The choice.** `Frame.registerScrollRegion` delegates to `insertHitbox` and therefore
translates its bounds by `activeOffset`. No per-record "which convention" flag.

**Reasoning.** The two registrations disagreed: `insertHitbox` translated,
`registerScrollRegion` did not, and the fold forced a choice. The only production
configuration the unification moves is the one that is wrong today — a `ScrollView`
nested inside a **scrolled** `ScrollView`, whose region was recorded where the engine
stored it rather than where it paints. A flag would have preserved a defect as a
feature.

**The trap this ruling had to be defended against, and it is MP-J's shape.** Adding
`+ activeOffset` reddened **nothing** in a 631-test suite: every routing fixture in
the repo either had no ancestor scroller or had one sitting at offset 0, so the
translation was provably inert in all of them. The task was therefore required to add
a nested-and-scrolled fixture and to report the red-before / green-after observation.
It did: three distinct failures, on the registered rect, on the inner scroller's
offset, and on the outer's — so the fixture distinguishes the two conventions three
ways.

**A generalisation that was measured false and is recorded as an error.** Task 5's
review reported that under the old convention "a nested scroller receives no wheel
events at all". Re-measured: moving the wheel point from `(100, 120)` to `(100, 170)`
reaches the inner scroller fine. It loses *part* of its hit area, not all of it. "None
at all" was true of one degenerate probe whose ancestor clip cut the misplaced rect to
zero height, and was over-generalised from it — while the same file said the opposite
in another comment. **A generalisation is hardest to see when every instance of it was
individually measured.**

**What it costs if wrong.** A nested `ScrollView` keeps receiving no wheel events over
part of itself, which is the status quo rather than a regression.

---

## IN-G — `Frame.pushClip`'s untranslated clip is RECORDED, not fixed — divergence 15

**The choice.** The sibling defect found by the same probe as `IN-F` — `pushClip`
intersecting its incoming rect into `activeClip` without translating it first — is not
fixed in this milestone. It is CLAUDE.md's divergence 15, pinned by
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`, which asserts today's
wrong answer on purpose and says so in its own failure message.

**Reasoning.** `IN-F` is a routing fix inside the milestone that owns routing. This is
a **paint**-space change whose blast radius is every clipped subtree in the framework,
found inside a milestone whose entire test surface is input. Fixing it here means
re-validating the clipping-and-scroll milestone's work from an input milestone, and
this repo has shipped two intermittent scroll defects that only a human found.

**Measured at the end of the milestone, on the finished suite**: applying the
one-line fix (`+ activeOffset` on `pushClip`'s incoming bounds) reddens the pin and
**nothing else across 736 tests**. So the fix looks regression-free against today's
assertions — which is exactly what `IN-F`'s trap says not to trust on its own, since
no other fixture in the repo puts a scroller inside a scrolled scroller and reads its
mask back.

**What it costs if wrong.** A nested scroller routes correctly and still draws
nothing, which is a strange half-state to ship. Accepted, and it blocks nothing here:
the demo has one `ScrollView`, not nested ones.

---

## IN-H — `StyledElement` gains a fourth requirement, `handlers: Handlers`

**The choice.** Input callbacks live in a new `Handlers` struct, added as a
**requirement** on `StyledElement` alongside `style`, `decoration` and `elementID` —
not as a defaulted extension property, and not on either of the other two.

**Reasoning.** `Style` lives in `MetalUILayout`, which may import only `MetalUICore`,
and it is compared field-by-field on whole-value equality by
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` — a closure field takes that
test with it. `Decoration` is paint data. A *requirement* rather than a default,
because a default of `{ get { Handlers() } set {} }` lets a conformer that stores
nothing compile, and `.onClick { … }` on it would silently throw the handler away.

**The cost came in lower than predicted.** No compile guard enumerated the protocol,
so the typecheck-guard count did not move for it; six production conformers and seven
test probes changed.

**What it costs if wrong.** Every `StyledElement` conformer gains a stored property it
may not use, and storing it is only half the job — a conformer must also *call*
`registerHandlers` in its own `prepaint`, which nothing can enforce.
`onClickIsLiveOnEveryConformerThatCanRegisterOne` is the guard, one case per
conformer.

**`Handlers` has FIVE members and it is not `Equatable`**, so `ModifierTests` projects
it through a hand-built `HandlerShape`. That projection must grow whenever `Handlers`
does — it did not, once, in this milestone, and two modifiers escaped the table for a
whole task as a result.

---

## IN-I — click dispatch reads `active` BEFORE `updatePointerState` clears it

**The choice.** `Window`'s input closure captures `let pressed = self.active` on the
line *above* `updatePointerState(event)` and passes it into `dispatchClick`.

**Reasoning.** Verified at the source rather than assumed: `updatePointerState` runs
first and unconditionally, its `.mouseUp` case sets `active = nil`, and
`self.onInput?(event)` only sees the event afterwards. A dispatcher reading
`Window.active` at release time therefore reads `nil` **every time** and no click ever
fires — a green implementation that does nothing, this repo's most-recorded bug shape.

**The hazard was reached in practice, which is the strongest outcome available for a
ruling like this.** The implementer wrote the wrong version first and it left all eight
click tests red with every hitbox and every registration correct.

**What it costs if wrong.** Silent total failure of the milestone's exit criterion.

---

## IN-J — an `onClick` hitbox registers OPAQUE, and therefore swallows the wheel — divergence 16

**The choice.** Accepted and recorded, not fixed. CLAUDE.md's divergence 16, pinned by
`aClickTargetInsideAScrollViewSwallowsTheWheel`, which asserts the wrong answer on
purpose.

**Reasoning.** A wheel event stops at the topmost opaque hitbox and scrolls only if
that record is itself a scroller — which is what closes exit criterion 4 (a `Deferred`
scrim swallowing a wheel). The same rule makes a button inside a `ScrollView` block
that scroller, where a browser scrolls. Non-opaque was rejected because it would stop
a scrim swallowing *clicks* aimed underneath it, undoing criterion 4's sibling
property.

**The fix is named rather than left as a mystery.** A wheel should stop at an opaque
hitbox only when that hitbox is on a **higher layer** than the topmost scroller under
the same point. `Deferred` hoists a scrim to the root layer; a button inside a
`ScrollView` shares its scroller's layer — so the `layer` key already on every
`Hitbox` separates the two cases with no ancestor walk. Not implemented, because
`applyScroll` is the site of two shipped intermittent defects that only a human found
and does not get an unreviewed refinement bolted on during a task about clicks.

**What it costs if wrong.** A button inside a scroller blocks it. Mitigated by ruling
that the counter demo's panel goes in the main pane — see `IN-U`.

---

## IN-K — the `NSTrackingArea` is in this milestone; pointer-leaves-window is left sticky

**The choice.** `MetalHostView` gains an `NSTrackingArea` through
`updateTrackingAreas()`, reinstalled on every AppKit geometry change. No
`InputEvent.mouseExited` is added.

**Reasoning.** Found by a mutation, not by the plan: `mousePosition: lastMousePosition
→ nil` in `drawFrameIfNeeded` reddened **nothing** across 637 tests, and the far end
of the same wire carried a source comment saying "`mouseMoved` only fires once a
tracking area exists … M3 adds it with hit testing". This *was* M3 and no task in the
plan added it. Hover that never fires is not hover: §3.3 promises it works and exit
criterion 7 asks a human to look at it, so omitting it ships a dead feature and an
unanswerable criterion.

The exit half was left sticky — `lastMousePosition` is never cleared — because adding
a case to a public enum crossing `MetalUIPlatform → MetalUI` is the stale-incremental
hazard CLAUDE.md records four times, and the consequence (a hover highlight that stays
lit after the pointer leaves the window) is visible rather than silent.

**What it costs if wrong.** This milestone is the largest the project has run and the
spec named a cut point right where this landed; the AppKit work spends some of that
margin. Accepted, because the alternative is a feature nobody can verify. **And
whether the tracking area actually makes `mouseMoved` fire in a running app is not
assertable here** — no AppKit mouse-tracking harness exists — so it is on the human
list.

---

## IN-L — key events bubble the focused id's own parent chain; no second tree

**The choice.** Dispatch walks the focused `GlobalElementID`'s `PathComponent` chain
outward, consulting a per-frame registry of which ids asked for something on the
keyboard. No parallel containment structure.

**Reasoning.** The structural-identity milestone already bought a persistent
parent-linked id at ~0.4% of a frame, so an element's ancestors are derivable from its
id alone.

**What it costs if wrong.** A parallel structure to keep in sync with the tree, which
is the class of bug that has no test.

---

## IN-M — focus is cleared at the frame boundary when the focused element was not produced

**The choice.** `Frame.resolveFocus()` runs between prepaint and paint and clears the
window's focus when the focused id is not in this frame's focus registry. No
tombstones.

**Reasoning.** Design spec §4.3 records that tombstones do not exist, and the
alternative — a dangling focus id that key events dispatch into nothing — is worse and
silent.

**The consequence is recorded rather than discovered: divergence 17.** A focused
`List` row scrolled out of the window loses focus and does not get it back, exactly as
divergence 12 says of its `@State`. It is worse than 12, and the reason is stated
there: `@State` is recoverable from the datum and focus is not.

**What it costs if wrong.** Focus that vanishes when a user did not move it. Bounded
by the fact that the element genuinely stopped being produced.

**SUPERSEDED IN PART on 2026-09-01, and the part that expired is the REASONING rather
than the choice** (rulings `TB-J`, `TB-AH`;
`docs/superpowers/2026-09-01-tombstones-decisions.md`). This ruling's stated reason —
"Design spec §4.3 records that tombstones do not exist" — was true when written and is
false now: the tombstones-and-AX milestone built them, and §4.3 carries a correction
block saying so. **The choice above still stands verbatim**: `resolveFocus()` still runs
at the prepaint/paint boundary and still clears focus the frame an element stops being
*focusable*. What changed is the other branch. An element that stops being **produced**
now falls back to `StateTable`'s retention: `Frame.registerHandlers` writes a `$focus`
child slot for the focused id, and focus survives while that entry does — bounded by
`staleAfterGenerations` (**2**) generations and gated on `sweepThreshold` (**256**), so
a windowed row scrolled out and back within two generations keeps focus and one gone
three generations on a large table does not. **Divergence 17 is retired as a bounded
closure**, and the "produced" / "focusable" distinction this ruling relied on became
load-bearing rather than incidental: it is now carried by a separate signal,
`focusedElementProducedThisFrame`, set independently of `handlers.isFocusable`, and
collapsing the two reddens `anElementThatStopsBeingFocusableLosesFocus` plus two
pre-existing tests. Recorded here rather than left standing, because a reader tracing
divergence 17's retirement backwards lands on this ruling and would otherwise read a
false premise as current.

---

## IN-N — clicking does not focus

**The choice.** A `mouseDown` on an element with an `onClick` moves `active` and does
**not** move focus. Focus moves only through `Window.focus(_:)`.

**Reasoning.** Focus-by-click is policy, the spec requires none, and the third
dispatch case ("with nothing focused it reaches the window") is what lets a keymap
binding work with nothing focused at all — which is what the counter demo relies on.

**What it costs if wrong.** A caller who wants click-to-focus writes it in a handler,
and the counter demo has to move focus explicitly (`IN-U`). A framework that later
wants the SwiftUI behaviour adds it in one place.

---

## IN-O — `isFocused`'s phase guard is added on a MEASUREMENT; `isActive`'s turns out to be insurance

**The choice.** `PaintPass.isFocused(_:)` gets a `swiftc -typecheck` guard proving a
prepaint-time call does not compile. The question of whether to add it was
deliberately left open in the brief, with a prohibition on adding it "by symmetry".

**Reasoning, and it went the opposite way from how it was framed.** The framing was
"focus is window state fully known before the frame starts, so a guard would be cargo
cult". Measured: an element that stops being focusable reads `prepaint=true /
paint=false` **in the same frame**, precisely because `resolveFocus()` clears at the
boundary. A prepaint-time `isFocused` really would compile and lie — returning a wrong
`true`. Reproduced character-for-character by an independently rebuilt fixture.

**And answering it honestly for the new guard answered it for an old one, in the
opposite direction.** `isActive`'s guard turns out **not** to be a measured lie:
`Frame.activeElement` is a `let` assigned once in `init`, so a prepaint-time
`isActive` would answer correctly. Its guard is kept as *placement insurance* — active
is the one of the three that could plausibly acquire a boundary-resolution step later
— and the shared comment now says so instead of implying one measurement covers all
three. **A prohibition aimed at preventing a bad addition surfaced a pre-existing
false justification.**

**Task 11 added a fourth guard on the same footing.** The element-keyed
`isHovered(_ id: GlobalElementID)` overload is a *second spelling* of a guarded call,
and the existing hover guard probes the `HitboxID` one. Guards 28 → 29.

**The differential was CLAIMED and then measured, and the claim was wrong** — which
is this milestone's own practices mechanism 2 landing on the commit that added it.
The claim was that adding only the `GlobalElementID` overload to `PrepaintPass`
"would leave that guard green". Running that mutation:

| guard | result under the hazard |
|---|---|
| `queryingHoverDuringPrepaintDoesNotCompile` (`HitboxID`) | **fails, 1 issue** — `!result.succeeded` still *passes*, and the message assertion breaks because the diagnostic becomes `cannot convert value of type 'HitboxID' to expected argument type 'GlobalElementID'` |
| `queryingElementKeyedHoverDuringPrepaintDoesNotCompile` | **fails, 2 issues** — both assertions |

So the older guard is a **tripwire** that reports the hazard as its own probe having
become ill-typed, and the new one is the **detection**. The suite is not silently
green under the hazard; the second probe buys a red that names the defect rather than
a red complaining about a fixture. The narrower claim is the true one, and it is
still a reason to keep both.

**What it costs if wrong.** A guard that is symmetry rather than mechanism, which is
what this ruling exists to prevent. **All three guards whose justification is
contingent now name a deletion condition in their own docs** — `isFocused`'s if
`resolveFocus()` stops clearing at the frame boundary, and both hover guards if
`resolveHover(at:)` ever runs before `prepaint` *and* the hitbox list is complete
before `prepaint` begins. `isActive`'s is the fourth, and it is insurance rather than
contingent, so it names none.

---

## IN-P — the chain is keystroke → binding → action → handler, and the keymap bubble runs BEFORE the raw `onKey` bubble

**The choice.** A bound keystroke resolves to an `Action` type, which bubbles the
focus chain to the first element registering a handler for it. Raw `onKey` bubbling is
unchanged and runs second. **Two separate bubbles, and they must not collapse.**

**Reasoning.** A keymap is the declaration of intent; a raw handler is the escape
hatch. Swapping the two makes every raw handler shadow every binding on the same
keystroke. Pinned by `aBoundActionRunsBeforeARawOnKeyHandler`, whose fixture sends a
bound *and* an unbound keystroke to the same element.

**A clause the ruling did not ask for and should have.** An action nobody handles does
**not** claim the keystroke — it falls through to `onKey` and then to `onInput`.
Without that, binding a key and forgetting the handler would silently swallow it,
which is the exact failure the two-bubble split exists to avoid.

**What it costs if wrong.** Either raw handlers become unreachable, or bindings are
shadowed by whatever raw handler is nearest the leaf — both silent.

---

## IN-Q — key contexts are contributed by any element, focusable or not

**The choice.** `keyContext(_:_:)` goes through the *keyboard* gate (`isKeyTarget`)
and not through focusability.

**Reasoning.** An ancestor pane contributes `Editor` while the focused leaf knows
nothing about contexts — that is the whole point of matching innermost-first *from the
chain*. Gating it on focusability would make `.keyContext(_:_:)` an API that compiles
and does nothing on exactly the elements that use it.

**And it must not go through the POINTER gate either**, which is the same separation
one field over: `isPointerTarget` is `onClick` alone, because an opaque hitbox for
every focusable or context-contributing element would stop a list of focusable rows
scrolling (`IN-J`).

**What it costs if wrong.** A context-scoped binding that never fires, with no
diagnostic.

---

## IN-R — `KeyEvent.timestamp` gets no default value

**The choice.** Every construction site states a timestamp. Seven sites: two
production, five test, and `MetalUIDemo` constructs none.

**Reasoning.** A default is the low-churn choice and it would make the two-stroke
timeout test **vacuous**: two events defaulting to the same instant have an age of
zero, so a prefix never expires and the test passes against an unimplemented timeout.

**What it costs if wrong.** Churn across every `KeyEvent` construction, which is
compile-time and visible, against a silently vacuous test, which is not.

---

## IN-S — a stale prefix is dropped and the ARRIVING keystroke is processed as a fresh first stroke

**The choice.** When a second stroke arrives after the timeout, the pending prefix is
discarded and the new key starts a new sequence.

**Reasoning.** Framework spec §8.3 says the prefix is dropped; it does not say what
happens to the key that found it stale. Discarding both silently eats a keypress.
"The prefix is dropped" and "the new key still works" are two assertions and the
second is the one that fails quietly.

**What it costs if wrong.** A keystroke vanishing with no diagnostic — the shape this
whole milestone kept finding.

**A neighbouring boundary this ruling did not cover, found in review.** The one-second
timeout was **bracketed, not pinned**: `= 2` and `= 0.4` each reddened three tests
while `= 0.5` and `= 1.49` both passed, so a 0.5-second chord timeout would have
shipped green under a test whose own title names one second. Now pinned from both
sides by `theTimeoutIsExactlyOneSecondOnBothSidesOfTheBoundary` — and the *first*
attempt at that fix shipped a test whose doc claimed to pin the `>` comparison and did
not, because `>` and `>=` agree at 0.999 and 1.001. Only running the mutation the
claim implied caught it.

---

## IN-T — a malformed context predicate is a visible parse failure: never a trap, never an indistinguishable `false`

**The choice.** `parse` returns `Optional`; an unparseable predicate is never
evaluated and its binding is skipped.

**Reasoning.** A keymap is data, so trapping on a typo would kill the app — but
"returns false" is this repo's most-recorded bug shape, and a test asserting only
`evaluate("&&|| bad") == false` is satisfied by a parser that returns false for
everything (taxonomy shape 1). The pin asserts `nil` for thirteen malformed sources
**and** non-`nil`-evaluating-`false` for a well-formed one, so no constant-answer
implementation satisfies both halves. Both constant-answer mutants were written and
both redden it.

**What it costs if wrong.** A binding that compiles, parses and silently never fires —
which is what `Keystroke.init?` returning `nil` for an unknown key name exists to
prevent one level down.

---

## IN-U — the counter demo: state written on input only, the panel outside the `ScrollView`, and focus moved explicitly

**The choice.** `CounterPanel` in `Sources/MetalUIDemo/main.swift` holds one `@State`,
sits in the **main pane** rather than inside the demo's `ScrollView`, writes its state
only from handlers, and focuses itself exactly once on its first layout.

**Reasoning, three separate constraints.**

- **Not in the `ScrollView`**, because `IN-J`: an `onClick` hitbox is opaque and would
  stop the list scrolling over the button's own rect. This is that ruling's own stated
  mitigation, not a layout preference.
- **`@State` on input only.** A write marks the window dirty (`IN-C`), so an element
  that wrote its own state every frame would pin the display link awake — milestone
  4's exit criterion, sabotaged from the demo. The same reasoning gives the
  `didFocusCounter` flag: `Window.focus(_:)` also marks the window dirty.
- **Focus moved explicitly**, because `IN-N` — nothing focuses anything on its own.
  The panel publishes its own `GlobalElementID` from `requestLayout`, which is the only
  place one exists: identity is structural, so a caller outside the tree cannot
  construct it correctly by hand.

**This bullet shipped INERT and was fixed in the fix wave — see `IN-X`.** The
`focus(_:)` call is made from inside a frame's render, and `Window`'s read-back
overwrote it every frame, so the counter was never focused at launch and the two
`context: "Counter"` bindings were dead until a human pressed **F**. The demo is
unchanged; the mechanism was wrong, not this ruling.

**The space and M keys moved onto the keymap** and the ad-hoc `onInput` switch is
gone, which is the milestone dogfooding its own subsystem; `=`/`-` carry
`context: "Counter"` so the two counter bindings exist only while the counter is
focused, which exercises §4.3's predicate matching in the demo rather than only in
tests.

**What it costs if wrong.** A demo that stutters (a per-frame dirty), or a list that
silently stops scrolling. Both are visible; neither is silent.

---

## IN-V — hover and focus are made visible by a `Decoration` token swap, not by a ring

**The choice.** `Decoration` gains `hoverBackground` and `focusBackground`, with two
public modifiers; `Box.paint` picks between them and `background` in one expression.
`Frame` gains `hoveredElement` and `PaintPass` an element-keyed `isHovered` overload.

**Reasoning.** Exit criterion 7 asks a human whether focus is *visible*, and nothing
drew it. A focus **ring** is not cheap and the blocker is one CLAUDE.md already
records: `Frame.fill` hard-codes zero border widths, so nothing above the renderer can
draw a border at all. A token swap on the existing fill is what is reachable in a
small change, and it is driven by the real `isFocused`/`isHovered` state rather than
by something that merely looks like focus.

**The element-keyed `isHovered` overload exists because `registerHandlers` returns
nothing.** The `HitboxID`-keyed query is the precise one, but the path every
`StyledElement` takes hands back no index; adding a return value there would change
`Box.PrepaintState` and ripple through every container's associated types.

**Focus outranks hover**, and it is a decision: hover follows the pointer and a user
recovers it by moving; focus is where the keyboard is pointing and has no other
indication. Reversing them makes a focused element lose its only affordance exactly
when a user is about to type. Pinned by `focusOutranksHoverWhenAnElementIsBoth`.

**What it costs if wrong.** Two more `Decoration` fields, and two modifiers that are
**inert on their own** — `hoverBackground` without an `onClick` registers no hitbox
and never resolves as hovered; `focusBackground` without `focusable()` and something
that moves focus never paints. Both are stated at the modifiers and the first is
pinned by `hoverBackgroundWithoutAClickHandlerNeverPaints`.

**Measured cost on the frame: ~0.01 ms.** The counter panel adds ~0.22 ms to the
demo's release frame, and stripping *every* handler from it (click, focusable, key
context, both actions) recovers only ~0.01 of that — so hitbox, focus and action
registration are ~0.5% of a frame, and the panel's cost is its three `Text` leaves.
Row-count flatness is untouched: 1.571 ms at 40 rows against 1.570 at 500.

---

## IN-W — the demo's modal scrim registers a click target, which INVERTS a human-verification answer

**The choice.** The demo's `Deferred` scrim gains `.onClick { showModal = false }`,
and the modal panel inside it gains a no-op `.onClick {}` to absorb its own clicks.

**Reasoning.** Spec exit criterion 4 — a `Deferred` scrim swallows a wheel event — was
closed by the fold, but the *demo's* scrim registered no hitbox at all, so the demo
could not show it: `Deferred` and `Box` contribute no `insertHitbox` call on their
own. Giving the scrim a click handler is what makes it an opaque hit target on the
hoisted root layer, which is both the idiomatic modal behaviour (click outside to
dismiss) and the thing a human can see.

**The consequence is that CLAUDE.md's absolute-positioning failure 4 inverts.** Three
milestones of that entry told a human to expect the list to keep scrolling under the
modal. It must now **not**. A human reporting that it still scrolls is reporting a
regression rather than confirming a known limitation, and both CLAUDE.md and the
demo's own `showModal` doc now say so.

**The panel's absorber is not decoration.** A container registers *before* descending
and both sit on the same hoisted layer, so the panel's own hitbox registers later and
wins the registration-index tie-break. There is no chaining, so the scrim never sees a
click that landed on the panel.

**What it costs if wrong.** A modal that dismisses when a user clicks inside it. That
is the failure the absorber prevents, and it is loud rather than silent.

---

## IN-X — the focus read-back applies the frame's DECISION, not its value

**Made in the whole-branch fix wave, on a bug the per-task reviews could not see.**

**The choice.** `Window.drawFrameIfNeeded` records `focusedElement` before building
the `Frame` and assigns the frame's answer back **only if the property is still that
same value**. A `focus(_:)` call made during `renderRoot` is left alone; the next
frame validates it, exactly as it validates a call made between frames.

**Reasoning.** `focusedElement` is the only window-owned input state handed into a
`Frame` and read back out, which makes the pair a read-modify-write spanning the whole
render. `Window.focus(_:)` is **public** and `MetalUIDemo`'s `CounterPanel` calls it
from its own `requestLayout` (`IN-U`), so a concurrent write is a supported thing to
do rather than a hypothetical. An unconditional read-back discarded it — and discarded
it forever, since set-during-render and clobber-at-end alternate: measured `nil` after
frames 1, 2 and 3, with and without the demo's once-flag.

`frame.focusedElement` is only ever the value handed in or `nil` (`resolveFocus()`
clears and nothing else writes it), so "unchanged since the hand-in" is exactly the
condition under which the frame's answer is still about the current focus. That is why
the guard is a decision test and not merely "never clear".

**Why the mechanism and not the demo.** Moving the demo's call out of `requestLayout`
would fix the demo and leave the next caller of a public API to rediscover the trap —
and there is nowhere else to move it to, since the id is a parameter of that phase and
identity is structural (`IN-U`'s own third bullet).

**Why no per-task review caught it.** Task 9 built the read-back; Task 11 wrote the
only in-frame caller. Neither diff contained both halves, and every focus test written
before the fix wave calls `window.focus(…)` *after* a `drawFrameIfNeeded()` — the
composition existed in the code and in no test, taxonomy shape 9.

**What it costs if wrong.** Either direction is silent. Too-permissive (never applying
the frame's answer) leaves a dangling focus id that key events dispatch into nothing —
reddens `anElementThatStopsBeingFocusableLosesFocus`,
`focusOnAnElementThatStopsBeingProducedIsCleared`,
`isFocusedDuringPaintTracksTheWindowsFocus` and
`focusingFromInsideAFrameIsStillValidatedByTheNextFrame`. Too-strict (the
unconditional copy) makes an in-frame `focus()` impossible — reddens
`focusingFromInsideAFrameSurvivesThatFrame` and
`focusingFromInsideAFrameIsStillValidatedByTheNextFrame`. Both guarded.

**The neighbouring question, answered.** `active` and `lastMousePosition` are handed
in and never read back, and that is **correct for both** — checked rather than
assumed. `Frame.activeElement` and `Frame.mousePosition` are `let`, so no in-frame
decision about either exists to be discarded; the compiler is the guarantee. On the
window's side both are written only by `updatePointerState`, which runs from the input
path between frames, and neither has a public mutator (`active` is `private(set)`
internal, `lastMousePosition` is `private`), so nothing in a tree can write them
mid-render either. The asymmetry is real and load-bearing: focus is the only one of
the three the *frame* discovers something about.

---

## OPEN — press-and-drag hover: keep AppKit's freeze, or follow the pointer? (review item B-13, awaiting the owner)

**Deliberately no ruling id: the owner has not decided. The next free letter is
`IN-Y`; assign it only when a choice is made.**

**The gap.** `MetalHostView` overrides `mouseMoved` and not `mouseDragged(with:)`, and
`InputEvent` has no drag case. So between `mouseDown` and `mouseUp`,
`Window.updatePointerState` gets no position: `lastMousePosition` holds the press
point, and a `hoverBackground` stays where it was at press time until `mouseUp` (which
writes the position and dirties the window). `active` is unaffected.
`PaintPass.isActive` is consulted by no built-in element anyway.

**Evidence, replica-measured.** Standalone probes, not in the repo, macOS 26.6.2
(25G83). Each is an `NSView` whose `NSTrackingArea` carries MetalUI's exact options
(`[.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]`), two such
views A|B side by side, driven by `CGEvent`s posted to the HID event tap.

- No-button control: A.entered, A.moved, A.exited, B.entered as the pointer crosses.
- Press in A and drag into B: only `A.down`, four `A.dragged` (all delivered to A, the
  press view, even over B), then `A.up`. **No exited or entered during the drag, and
  none at mouseUp either.** `A.exited` and `B.entered` arrive on the first free move
  afterwards. Apple's doc for `.enabledDuringMouseDrag` says the no-option owner gets
  entered events "on mouseUp events after a mouse drag"; measured, that did not happen.
- **SwiftUI** (`NSHostingView`, `.onHover` and `.onContinuousHover` on two `Color`
  views), same drag: no hover callback during the drag; `A.onHover(false)` and
  `B.onHover(true)` arrive on the first move after release.
- Adding `.enabledDuringMouseDrag` changed **nothing** in seven variants (press on a
  view or on bare background; `.activeInKeyWindow` or `.activeAlways`; 30pt steps or
  5pt steps with deltas and pressure). That arm never disagreed with the no-option arm,
  so this probe does not establish what the option does, and a synthetic drag the
  window server does not track would produce the same log. **A real hand drag is the
  confirming look.**
- Instrument notes: `NSEvent(cgEvent:)` plus `NSApp.sendEvent` delivers nothing (the
  event has `window == nil`). `NSEvent.mouseEvent` plus `sendEvent` delivers down, drag
  and up but **no** tracking callback even on the control, and so does
  `CGEvent.postToPid`. Tracking is window-server driven, and no windowless or
  in-process test can pin it.

**Option A: keep the freeze (no override).** Matches measured AppKit with MetalUI's
options, and matches measured SwiftUI, the EP-5 authority above the engine. MetalUI
already corrects one event earlier than both: it corrects at `mouseUp`, they wait for
the next move. Cost: when a real drag gesture (slider thumb, scrollbar drag, both
currently 'Out, deliberately' in the clipping spec) is specced, that milestone must add
the override anyway and re-decide hover then. Pin: a windowless `MetalUIPlatformTests`
test that requires
`class_getMethodImplementation(MetalHostView.self, #selector(NSResponder.mouseDragged(with:)))`
to equal `NSView`'s, so adding the override reddens until this ruling is revisited.
Plus a human look: press a demo button, drag onto the other and hold; the highlight
should stay on the pressed one until release.

**Option B: follow the pointer (add `mouseDragged`).** The web's semantics, per the
review; not measured here. It is the reverse of EP-5's usual direction, and the
measured AppKit and SwiftUI arms disagree with it: B lights while A is pressed and
`active`. Forwarding as `.mouseMoved` needs no public enum change. A new drag case on
`InputEvent` is the cross-module stale-incremental-build hazard CLAUDE.md records, and
needs `swift package clean`. Either way, every drag event dirties a frame. Pin: a
windowless test that calls
`view.mouseDragged(with: NSEvent.mouseEvent(with: .leftMouseDragged, …))` on a
`MetalHostView` and requires `onInput` to receive the converted position. That should
be red on arrival (no override exists) but was not run against `MetalHostView` here.
Add a `FakePlatformWindow` test in which mouseDown on A then a drag-sourced move to B
resolves hover to B with `active` still A, plus the same human look with the opposite
expected answer.

**Recommendation: A**, recorded as a ruling. Both platform authorities measured the
freeze. The only visible cost is a highlight held for the length of a press, which
self-corrects. And B decides a question (hover during a gesture) that belongs to the
milestone that first builds a gesture. Revisit if the hand-drag look contradicts the
replica.
