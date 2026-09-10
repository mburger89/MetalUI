# Animation and Easing — Design

**Milestone:** M4, spec 3 of 4.
**Binding authority above this document:** `docs/superpowers/specs/2026-08-24-metalui-design.md`,
§4.4 (*Redraw and scheduling* — the timebase and `hasActiveAnimations`) and §12 row 4.

M4 is one milestone delivered as four specs in dependency order — reactivity (merged,
`d0aca58`), `Component` (merged, `59ec337`), animation & easing, then the `ElementGroup`
child-id change and the AX platform bridge. This is the third.

**Exit criterion this spec owns:** none of M4's three outright. Animation is a prerequisite
for "a real small app" and it is the change that finally makes `hasActiveAnimations` real —
which M4 spec 1 deliberately refused to declare without a writer. Said plainly up front so a
green suite here is not read as closing a criterion.

---

## 1. What exists, and what the gap is

**Nothing.** `grep -rn "hasActiveAnimations" Sources/` returns **0**; there is no `Animation`
type, no easing, no interpolation, and no animation state anywhere.

**The design spec has no animation section either**, which makes this the only genuinely
greenfield piece of M4. Animation appears in the binding spec four times and never as a
design: §4.4's timebase sentence and its `hasActiveAnimations` guard, §4.3's note that
animation progress is state that must survive a rebuild, §9's Reduce Motion requirement, and
the §12 row. This document is the design those references assume.

**Two things M4 spec 1 deliberately left for this spec** (ruling `RX-O`): the
`hasActiveAnimations` property itself, and the widened guard
`needsRedraw || hasActiveAnimations`. That spec implemented the `needsRedraw` half only, on
the grounds that an always-`false` stored property with no writer is the declared-but-inert
trap. This spec introduces the property, its writer, the widened guard **and** the timebase
fix in one change.

---

## 2. The timebase is currently WRONG, and this spec fixes it

§4.4 says: *"All animation and `MetalDrawContext.time` derive from the display link's **target
presentation timestamp**, never wall clock — required for correct 120 Hz ProMotion and
variable-refresh behavior."*

**Measured: the code uses `CADisplayLink.timestamp`, not `targetTimestamp`.**
`AppKitPlatform.displayLinkFired` passes `displayLink?.timestamp ?? 0`, and
`grep -rn "targetTimestamp" Sources/ Tests/` returns **nothing** — the correct clock has never
been referenced in any code this project ships. (Scope that grep to `Sources/` and `Tests/`:
widening it to `docs/` now matches this document, which is a claim that invalidates itself the
moment it is written down.)

`timestamp` is when the **previous** frame was displayed; `targetTimestamp` is when the frame
being built is **expected** to be displayed. `Window.swift` already half-knows this: a comment
there describes `lastTick` as "the *previous* frame's instant" and uses it anyway.

**Harmless today, load-bearing the moment animation ships.** The only consumer of the tick
value is the scroll indicator's fade age (`age = timestamp - lastScrollTime`), where one frame
interval is immaterial. An animation evaluated at `timestamp` is one whole frame interval
behind where it should be when the frame is actually presented — 8.33 ms at 120 Hz — which is
a uniform lag and a subtly wrong velocity at the ends of a curve.

**The fix is one line in `AppKitPlatform`**, plus honesty about what it moves: the scroll
fade's age shifts by one frame interval, which no assertion checks and no human can see.
Whether it is a *divergence* that the framework ran on the wrong clock for five milestones is
not worth a label — nothing observable depended on it. It is recorded here because a reader
who finds `timestamp` in the git history should find the reason it changed.

---

## 3. The transaction model

```swift
@MainActor
public func withAnimation(_ animation: Animation = .default,
                          _ body: () -> Void)
```

`withAnimation` stores a pending `Animation` on the `Window`, runs `body`, and clears it. The
mutation inside marks the window dirty through whichever path it already uses — `@State`'s
`onWrite` hook or `@Observable`'s tracking — and this spec changes neither.

The **next frame build** carries that animation as ambient context on the passes, the way
`LayoutPass.scrollContext` already is. Any animatable value that differs from the one stored
for its element adopts it.

> **Corrected in place on 2026-09-10, with the original above kept visible because the design
> leaned on it and because reading only its first clause is what caused this milestone's largest
> defect. Rulings `AN-B`, `AN-C`, `AN-D` in
> `docs/superpowers/2026-09-03-animation-decisions.md`.**
>
> **"stores … runs `body`, and clears it" and "the next frame build carries that animation" are
> in tension, and Task 1 implemented the first sentence only.** A single slot restored in
> `withAnimation`'s own `defer` satisfies "clears it" read alone and **defeats the sentence after
> it**: the helpers run during the frame build, which happens later, from the display link,
> entirely outside the closure body. So for four tasks a production
> `withAnimation { model.x = 1 }` marked the window dirty, the next frame built, and **every
> field snapped** — with all thirteen animating tests green, because each of them called the
> helper *lexically inside* a `withAnimation` body, a configuration production cannot reach
> (taxonomy shape 15).
>
> **What ships is TWO slots, two lifetimes, one value**, written in the same statement so they
> cannot disagree about which animation, only about when: `Animation.pendingTransaction` is the
> lexical ambient (restored on the way out to whatever was parked before, so nesting leaves the
> outer one in effect), and `Animation.parkedTransaction` is the hand-off, taken by the next
> `Window.drawFrameIfNeeded` and consumed by **exactly one** build. The helpers prefer the
> frame-carried value and fall back to the lexical one.
>
> **The park is CONDITIONAL, and neither clause is an optimisation.** It survives only if
> `Window.redrawRequests` moved across `body`, **or** a build was already pending when the call
> started and the slot was free. Without the first, a body that dirties nothing parks a
> transaction no frame consumes and ambushes an unrelated change an arbitrary time later
> (measured at 400 s). Without the second, `withObservationTracking`'s **one-shot** session means
> the second `@Observable` write between two frames moves no counter, so a legitimate animation
> is **silently discarded**. `AN-C` records both measurements.
>
> **"on the `Window`" is NOT what shipped, and it is unsatisfiable as written.** The slot is a
> `@MainActor static` module-global. `withAnimation` is a free function with no window in scope,
> and this framework has no window registry and no ambient "current window" to give it one —
> checked rather than assumed. The cost is stated rather than discovered: with two windows live,
> whichever builds first consumes the transaction and the other snaps. Unreachable today;
> nothing constructs two live windows that both build. The fix, when a second window exists, is a
> per-window slot plus a way for `withAnimation` to name its window — a signature change, not a
> redesign (`AN-D`).
>
> **What this correction does NOT change.** The ambient model itself, the absence of causality
> tracking, one-transaction-per-build, and "not re-entrant across frames" all shipped exactly as
> §3 specifies them.

### There is no causality tracking, and none is needed

This is the design's central simplification and it is worth stating because the alternative
looks necessary and is not. **SwiftUI does not trace which values changed *because of* the
mutation either.** It sets an ambient transaction for the duration of the closure, and the
resulting render interpolates whatever animatable properties differ. This framework can do the
same thing for two reasons it already has: it rebuilds the entire tree every frame, and it has
per-element cross-frame storage keyed by `GlobalElementID`.

**The cost is inherited too, and it is stated rather than discovered.** A value that changed
in the same frame for an *unrelated* reason also animates. That is SwiftUI's behaviour and a
known quirk of it; it is not a defect here either, and it is the price of not building a
dependency tracer.

**`withAnimation` is NOT re-entrant across frames.** The pending animation is consumed by the
next build and cleared. Calling it from inside a phase is the same hazard the `@State` and
`@Observable` bullets already record — write from input, never from a phase.

---

## 4. What animates, and what snaps

**Animatable — numeric, from `Style`:** `inset`, `size`, `minSize`, `maxSize`, `margin`,
`padding`, `border`, `gap`, `flexGrow`, `flexShrink`, `flexBasis`.

**Animatable — from `Decoration`:** `background`, `cornerRadius`, and the pointer-state
variants `hoverBackground` / `focusBackground`.

**Snapping — discrete, no meaningful midpoint:** `display`, `position`, `overflow`,
`flexDirection`, `flexWrap`, `justifyContent`, `alignItems`, `alignContent`, `justifyItems`,
`alignSelf`. There is no value between `.flex` and `.stack`, and inventing one would be worse
than snapping.

**`aspectRatio` is deliberately NOT animatable.** It is in CLAUDE.md's declared-but-inert
table — read by no production code — and offering animation for a property that does nothing
is that table's exact trap, doubled. It becomes animatable in the same change that makes it
live, and not before.

### Three rules the type system does not enforce

- **Any transition touching `Dimension.auto` snaps.** `.auto` carries no number, so
  `.auto → .length(100)` has no midpoint. Interpolating from a *resolved* size instead would
  make the animation depend on layout output that does not exist yet at the point the style is
  resolved. Snap, and say so at the line.
- **A `percent` and a `length` do not interpolate with each other** — the percentage's basis
  is not known where the comparison happens. Same case, same answer: snap.
- **`Decoration.background` is a `ColorToken`, not a colour.** Two tokens interpolate through
  their theme-*resolved* `Hsla`. So a theme change mid-animation moves the endpoints
  underneath a running interpolation. The animation re-resolves both ends every frame rather
  than caching resolved colours, which makes a theme switch during a colour animation produce
  a continuous result rather than a jump.

---

## 5. Where the comparison happens — one choke point

**This section claimed a single choke point and that was WRONG — corrected before it shipped,
and the original claim is kept because the design leaned on it.**

The draft said: *"`Row`, `Column` and `Stack` each hold a `Box` internally, so
`Box.requestLayout` is the single site every styled layout flows through."* `Row` and `Column`
do hold a `Box` (`Flex.swift`). **`Stack` does not** — it is its own `Element, StyledElement`
with its own `requestLayout` calling `requestNode` directly (`Stack.swift:102`).

Enumerated rather than assumed — `grep -rn "requestNode\|newLeaf" Sources/MetalUI/` — there are
**four** sites that register a styled node, not one:

| site | what it registers |
|---|---|
| `Box.swift:79` | every `Box`, and therefore every `Row` and `Column` |
| `Stack.swift:102` | every `Stack` |
| `ScrollView.swift:270`, `:279` | the content node and the viewport node |
| `Text` via `newLeaf` (`Frame.swift:980`) | text leaves |

**So the mechanism is a shared helper that each site calls, not a single site that covers
everything.** The helper takes the element's `GlobalElementID` and its resolved `Style`, and
returns the style with animated fields substituted:

```swift
// in the animation layer, called from each registering site
func animated(_ style: Style, for id: GlobalElementID, pass: inout LayoutPass) -> Style
```

That is a weaker guarantee than the draft claimed and it must be said so: **an element that
registers a node without calling the helper is silently unanimated**, with no diagnostic —
the same shape as `StyledElement`'s `registerHandlers` requirement, which CLAUDE.md records as
enforceable by nothing and guarded only by
`onClickIsLiveOnEveryConformerThatCanRegisterOne`, one case per conformer. **This spec owes an
equivalent guard**: one case per registering site, so a fifth site added later fails a test
rather than quietly animating nothing.

At each site the framework:

1. resolves the element's declared `Style` and `Decoration` as it does today,
2. reads the previous frame's values from the element's `$anim` slot,
3. starts an animation for each animatable field that differs **while a transaction is in
   flight**,
4. substitutes the current interpolated value before calling `pass.requestNode(style:children:)`.

**Why a helper rather than making `requestNode` itself do it:** `requestNode(style:children:)`
does not take the element's `GlobalElementID`, and animation state is keyed by it. Widening
that signature would touch every registering site anyway — the same four — and would put
animation into the layout pass's own surface rather than beside it. The helper keeps the
coupling one-directional.

**`Text` is in the table above and is still NOT animated by this spec.** It registers through
`newLeaf` with a `MeasureFunction`, and its style participates in measurement rather than only
in layout — animating it means re-measuring text every frame, which is a different cost
question from substituting a number. Named in §8 rather than left to be discovered.

> **Corrected in place on 2026-09-10. This section was wrong about the choke point TWICE — the
> block above corrects the SITE count, and this one corrects the PHASE count. Rulings `AN-E`,
> `AN-F`, `AN-Q` in `docs/superpowers/2026-09-03-animation-decisions.md`.**
>
> **There are two helpers in two phases, not one helper called from four sites.** Colour cannot
> be interpolated from `LayoutPass` at all: §4's own third rule requires two `ColorToken`s to
> interpolate through their **theme-resolved** `Hsla`, re-resolved every frame, and **only
> `PaintPass` has a theme**. So:
>
> | phase | helper | sites |
> |---|---|---|
> | `requestLayout` | `animated(_ style: Style, _ decoration: Decoration, for: GlobalElementID, pass: inout LayoutPass)` | `Box`, `Stack`, `ScrollView` ×2 — the four in the table above |
> | `paint` | `animatedColor(_ token: ColorToken?, for: GlobalElementID, pass: inout PaintPass)` | `Box.paint`, `Stack.paint`, `Text.paint` — three of the four `pass.fill` sites |
>
> The shipped layout signature also takes and returns the `Decoration`, not the `Style` alone as
> sketched above: `Decoration.cornerRadius` is a plain `Pixels` and needs no theme, so it stays
> at layout while the three colour fields do not.
>
> **The paint helper animates ONE value, not three fields.** `Box.paint` already selects among
> `focusBackground` / `hoverBackground` / `background` by pointer state before drawing, so what
> is animated is the **resolved result of that chain**. Animating the three fields separately
> would animate values that are not on screen. This is a deliberate departure from §4's own
> field list and is a better decomposition than the one this document specifies.
>
> **§5's demand for "one test case per registering site" is met TWICE, once per phase** —
> `everyRegisteringSiteAnimatesItsStyle` and `everyBackgroundPaintingSiteAnimatesItsColour`. The
> first was **red on arrival** (6 issues with all four `Sources/` edits stashed, going green one
> site at a time, 6 → 4 → 2 → 1 → 0), which is what distinguishes "this site is covered" from
> "this test cannot see any site".
>
> **The fourth `pass.fill` site is `ScrollView`'s indicator and it is deliberately unwired** — it
> drives itself by dirtying the window rather than through the animation path (`AN-M`). **And
> `Text`'s own paragraph above is now only half true**: `Text.paint`'s *background* is animated
> as of this milestone; its **glyph colour** and its **measured style** remain §8's named holes,
> for exactly the re-measurement reason that paragraph gives.

---

## 6. Storage

Animation state is per-element and must survive the rebuild, which is what `StateTable` is
for. A reserved `$anim` child slot under the element's own `GlobalElementID` holds a map of
property key → `{ from, to, startTime, animation, velocity }`.

**This makes four reserved slot names**, joining `$state\(n)`, `$focus` and `$ax`. CLAUDE.md
records those three as carrying an identical, unguarded collision risk — a hand-written
`.id("$focus")`, or a `List` datum whose id *describes* to one of them, mints the same
`GlobalElementID`. **`$anim` inherits that risk exactly**, and the existing test
`theThreeRetentionSlotsAreMutuallyDistinct` must become four. Guarding one name while leaving
three open would read as though the others were safe.

> **Corrected in place on 2026-09-10: it is SEVEN names, not four, and the test is
> `theSevenRetentionSlotsAreMutuallyDistinct` — the same test, extended in place three times
> (three → four → six → seven), never replaced. Ruling `AN-P`.** `ScrollView` registers **two**
> nodes from one element id, so each got a named child id (`$anim-content`, `$anim-viewport`) —
> those two are id **prefixes**, not slots: the `$anim` slot hangs off them, so the value lives
> at a **grandchild**. `$anim-color` is the paint-side colour helper's own slot (§5's
> correction). **Extending the test in FORM was not enough**: as first written it asserted a
> *settled* value, and renaming `"$anim"` to `"$focus"` reddened **0 of 837**, because a fully
> clobbered slot produces the same settled value — the helper treats a `nil` peek as a first
> sighting and returns the declared value. It now asserts a **mid-flight** value, which only an
> intact slot can produce (50.0 intact against 100.0 collided), and the rename mutation reddens
> **1 issue** on that test alone. This paragraph's claim about *why* the test matters was right;
> its assumption that widening it would carry the guarantee was not.

Animation state gets tombstone retention for free, with the bound the tombstones milestone
established: `staleAfterGenerations` is 2, above a `sweepThreshold` of 256 entries. **An
element that vanishes and returns within the window resumes its animation rather than
restarting** — which is correct, and is a consequence nobody has to build.

---

## 7. Curves

Two models, because a duration and a spring answer different questions and neither subsumes
the other.

**Duration curves.** `linear`, `easeIn`, `easeOut`, `easeInOut`, and a general cubic-Bézier,
each with an explicit duration. State is fixed and small; termination is exact
(`elapsed >= duration`), so `hasActiveAnimations` has a precise answer and the display link
pauses on the frame the last one ends.

**Springs**, in SwiftUI's modern spelling — `duration` and `bounce` rather than raw
mass/stiffness/damping, because the latter is a physics API and the former is a design one.
Springs re-target gracefully when a value changes mid-flight, which is the interruption case
that makes motion feel responsive rather than queued.

**A spring has no exact end, and that is the hard part.** Termination needs a settling
threshold on **both** position and velocity — a spring at its target with velocity still in it
is not finished. That threshold is a tuned constant, and this project does not accept tuned
constants without a justification: it must be derived from a stated criterion (a
sub-perceptual-pixel displacement at the surface's scale factor, say) rather than picked
because it looked settled, and it must be pinned by a test that fails if the spring is
declared finished while still visibly moving.

**Interruption re-targets from the current value and, for springs, the current velocity.** A
value that changes mid-animation does not restart from the declared `from`; it animates from
where it currently is. Restarting is the wrong behaviour and the easy implementation, which is
why it is called out here.

---

## 8. Not in scope, named rather than left open

- **Reduce Motion.** §9 requires that it suppress animation, and it should. It needs the
  system-settings plumbing that §9's own status block records as **not built** — the whole
  "system settings propagate into the frame context" bullet. This spec must not fake it with a
  one-off read; it is one bullet of a subsystem, and it lands with that subsystem.
- **Exit transitions.** §4.3's correction block is explicit: the prerequisite (tombstones)
  exists, and what is missing is a *distinction* nothing yet draws between "gone, keep
  animating out" and "gone, ordinary tombstone". That is a design question about identity, not
  an animation feature, and §14 still lists it as out of v1.
- **Animating a `Text`'s own style** (§5). `Text` is a leaf that goes through `newLeaf` rather
  than `Box`, so it is outside the one choke point. Animating text colour is a real want and it
  needs either a second site or a shared helper both call.
- **`MetalDrawContext.time`.** §4.4 names it alongside animation as deriving from the same
  timebase. There is no `MetalView` and no draw context yet — that is M5.
- **Transforms.** `MUIRect` carries bounds, colour, corner radii and border edges; there is no
  transform in the shader ABI, so there is nothing to animate. Scale and rotation are a
  renderer change, not an animation one.

---

## 9. Testing

Counts and values, never wall-clock time. Every animation test drives the clock explicitly by
feeding timestamps, exactly as `FrameClockTests` already does with `simulateTick(timestamp:)` —
**no test may sleep.**

1. **A value changed inside `withAnimation` interpolates; the same change outside it snaps.**
   Both halves in one test — the asymmetry is the evidence, and the second half is what rules
   out "everything animates always".
2. **Interpolation is evaluated at the frame's timestamp**, not at a wall clock: two frames
   fed the same timestamp produce the same value.
3. **Termination is exact for a duration curve** — the value equals the target at
   `startTime + duration`, and `hasActiveAnimations` is false on that frame.
4. **The display link stays running while an animation is live and pauses on the frame after
   the last one ends.** This is the criterion M4 spec 1 could not test because the property
   did not exist; it is testable now against the same `FakePlatformWindow.pauseCalls` recorder.
5. **A spring settles**, and the settling threshold is pinned from both sides: a spring within
   the threshold reports finished, and one still visibly moving does not.
6. **Interruption re-targets rather than restarting**: change the target mid-flight and the
   value must be continuous across that frame — no jump back to the original `from`.
7. **A snapping field does not interpolate**: `display` changed inside `withAnimation` takes
   its new value on the first frame.
8. **`.auto` snaps**, both directions.
9. **An animating element that vanishes and returns within the retention window resumes**
   rather than restarting (§6's free consequence).
10. **The four reserved slot names are mutually distinct** — the existing three-way test
    extended to four. *(Delivered as **seven** names in
    `theSevenRetentionSlotsAreMutuallyDistinct`, extended in place three times — §6's
    correction block and ruling `AN-P` have the reason and the mutation count.)*

### Mutations that must be run, not predicted

- **Feed `timestamp` instead of `targetTimestamp`.** Must redden assertion 2 or a dedicated
  timebase test. If it reddens nothing, the timebase is untested and the §2 fix is unpinned.
- **Declare a spring finished on position alone, ignoring velocity.** Must redden assertion 5.
  This is the mutation most likely to redden nothing on a fixture whose spring is critically
  damped — choose one that overshoots.
- **Restart an interrupted animation from its declared `from`.** Must redden assertion 6.
- **Never clear `hasActiveAnimations`.** Must redden assertion 4 — and if it does not, the
  idle criterion is not actually being observed.

### What no test here can see

- **Whether the motion looks right.** Easing is a perceptual judgement and no assertion
  reaches it. A human look is the only instrument, and it belongs in the milestone's
  human-verification entry rather than in a test comment.
- **Whether `targetTimestamp` actually removes the one-frame lag on real hardware.** Every
  test drives a synthetic clock. The real `CADisplayLink` is outside this repo's reach, which
  CLAUDE.md already records for the display-link pause itself.

---

## 10. Exit criteria

1. `withAnimation` exists; a value changed inside it interpolates over the declared curve and
   the same change outside it snaps.
2. Both curve models work: a duration curve terminates exactly, and a spring settles against a
   justified, pinned threshold.
3. `hasActiveAnimations` is real — declared, written, and read by the widened guard — and the
   display link runs while an animation is live and pauses on the frame after the last ends.
4. The timebase is `targetTimestamp`, and `grep -rn "displayLink?.timestamp" Sources/` returns
   nothing.
5. Every assertion in §9 passes and every mutation in §9 has been **run**, with its actual
   result recorded at the mutated line.
6. **No golden moves and none is added.** Animation substitutes values *into* the existing
   layout path; it does not change the engine. `git diff --name-only <base>..HEAD --
   Sources/MetalUILayout/` must be empty.
7. `aspectRatio` is still not animatable and still has its row in the inert table.
8. **Every site that registers a styled node calls the animation helper**, with one test case
   per site (§5), so a fifth site added later fails a test rather than silently animating
   nothing.
9. **A human runs the demo and reports whether the motion looks right** — the one thing no
   test here can establish.

---

## 11. Risks recorded up front

| Risk | Standing |
|---|---|
| The spring settling threshold is picked rather than derived | §7 forbids that explicitly. It must come from a stated perceptual criterion and be pinned from both sides; a constant that only makes tests pass is the failure this row exists for |
| An unrelated value changing in the same frame animates too | Inherited from the transaction model and from SwiftUI. Stated in §3 rather than discovered; the alternative is a dependency tracer this framework has no machinery for |
| `Text`'s own style is not animated | §5's named hole. A caller animating text colour will find nothing happens, with no diagnostic — the shape CLAUDE.md's inert table exists to prevent, which is why §8 names it rather than leaving it silent |
| `$anim` collides with a hand-written or data-supplied `.id("$anim")` | Fourth instance of a risk CLAUDE.md already records for three names. Unguarded, as the other three are; the mutual-distinctness test goes to four so the names cannot collide with *each other* |
| Animating layout costs a full `computeLayout` per frame | Measured on the demo tree at 1.27 ms release against an 8.33 ms budget, so it fits — but that figure is for *that* tree, and this project has been bitten before by a per-node cost that held only for the shape it was measured on. A large tree animating one property still pays for the whole tree |
| A theme change mid-animation moves a colour animation's endpoints | Deliberate (§4): both ends re-resolve every frame, so the result is continuous rather than a jump. Recorded because the alternative — caching resolved colours — looks like an optimisation and would produce a visible discontinuity |
