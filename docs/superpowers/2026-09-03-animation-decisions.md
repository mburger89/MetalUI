# Animation and easing — decisions taken during execution

Rulings from the milestone that added `withAnimation`, two interpolation
helpers in two phases, `hasActiveAnimations` and the widened idle guard.
**M4, spec 3 of 4.**

Prefixed **`AN-`** and **lettered** (`AN-A`, `AN-B`, …) per this repo's
convention — **a bare `AN-3` is a typo, not a citation**, the same note every
other milestone's decisions doc carries. Next unused letter is `AN-AJ`
(`AN-X`…`AN-AH`: plan task 13, 2026-09-30, at the end of this document;
`AN-AH` is its critic round, `AN-AI` its lane 1).

Read alongside `docs/superpowers/specs/2026-09-03-animation-design.md` (its §3,
§5 and §6 are corrected in place by rulings recorded here), the binding design
spec `docs/superpowers/specs/2026-08-24-metalui-design.md` §4.4, and
`.superpowers/sdd/2026-09-03-animation/progress.md`, the execution ledger these
rulings are drawn from.

## How to read the letters, because they do not carry the ledger's

**The ledger lettered its own rulings `A`…`M` twice** — once before the session
break and once after — and several of them are about *dispatch* (run mutations
in a worktree, hold this fix round until that one commits) rather than about the
framework. Carrying those letters here would make `AN-H` ambiguous between two
different ledger rulings and would fill a decisions doc with process. **So the
letters below are new**, and where a ruling restates a ledger one the ledger's
letter is named in the text. This is the opposite call from `CO-A`…`CO-O`, which
carried the Component ledger's letters one for one; that ledger lettered once
and its rulings were about the code.

`AN-A` through `AN-R` are the decisions a reader consults about the *code*.
`AN-S` through `AN-W` are findings about the *record* and the practice — a claim
measured and found false, a mutation that reddened nothing, a count that was
never taken the way it was reported. They are kept because this repo's own
practices document is assembled from exactly those, and because two of them are
standing hazards rather than history.

## Where each number was measured, and which copy is authoritative

**Most figures below are carried from the execution ledger AS OBSERVED by the
task round that took them, not re-run for this document — and saying which is
which is the point of this section, because a document that implies it re-took
everything is committing the defect `AN-S` is about.**

**Re-taken at `b869253` while writing this document:** the suite figures below;
the guard count and its per-file breakdown; **both directions of `AN-V`'s
build-system behaviour**; `AnimatedStyle.swift`'s current line count; the
`displayLink?.timestamp` and `aspectRatio` greps; the four `pass.fill` sites and
`AN-R`'s plumbing trace; the seven device-dependent tests; **mutation 33's
`112.0`**, run twice in an isolated `git worktree`; and a check that every test
name and commit sha cited anywhere in this document resolves.

**Everything else names the round it came from and is stated as that round
observed it**, including where a later round moved the number — those rows say
"then", and a row whose *attribution* was corrected without its count moving says
that too.

A figure that came from a throwaway probe *outside* the repo — the two colour
oracles in `AN-G`, and the memory measurements in `AN-L`, which ran in isolated
processes rather than in the suite — says so at the number, which is `TB-AA`'s
rule and `CO-U`'s precedent. Those probes are deliberately uncommitted (`CO-E`'s
footing): a committed version would pin SwiftUI's and CoreAnimation's behaviour
rather than this framework's.

**The source is authoritative for every in-tree mutation figure.**
`Sources/MetalUI/Animation.swift`, `AnimatedStyle.swift` and `AnimatedColor.swift`
carry these counts at the lines they belong to, and that is the copy a mutation
is re-run against. Re-measure there, correct there first, then propagate here.
That ordering is not decorative: `AN-L` exists because a projected figure sat in
`Sources/` under the word "Measured" for a whole fix round while the real
measurement lived only in a report.

**The suite figures in this document were re-taken for it**, not carried from a
task report: **861 tests** (six per-target summary lines, 47 + 448 + 50 + 6 +
288 + 22), **0 `error:`**, **0 `warning:`**, **87 goldens**,
`git diff --name-only master..HEAD -- Sources/MetalUILayout/` **empty**, at
commit `b869253` on `feat/animation`. The guard count is **35**, and how it must
be taken is `AN-V`.

---

# The decisions

## AN-A — the transaction model is ambient and there is NO causality tracking, because SwiftUI does not have one either

**The choice.** `withAnimation(_:_:)` sets an ambient transaction; the next
frame build carries it, and **any** animatable value that differs from the one
stored for its element adopts it. Nothing traces which values changed *because
of* the mutation inside the closure.

**Why that is a design and not a shortcut.** The alternative looks necessary and
is not. SwiftUI does not trace causality either — it sets an ambient transaction
for the duration of the closure and the resulting render interpolates whatever
animatable properties differ. This framework can do the same thing because it
already has the two things that make it work: it **rebuilds the entire tree
every frame**, and it has **per-element cross-frame storage keyed by
`GlobalElementID`** (`StateTable`). Neither had to be built for animation.

**The cost is inherited too, and it is stated rather than discovered.** A value
that changed in the same frame for an *unrelated* reason also animates. Spec §3
says so up front. Ruling `AN-C` is about a much sharper version of the same
shape — a transaction reaching a change in a *different, arbitrarily distant*
frame — and that one is a defect rather than an accepted quirk, which is the
distinction to keep.

**What it costs if wrong.** A dependency tracer is machinery this framework has
none of, and building one would key animation to *why* a value changed rather
than to *that* it changed. Recovering from the ambient model means writing that
tracer; the model itself is one line of state and a comparison.

---

## AN-B — `withAnimation` writes TWO slots with one value, and until Task 5 production animated NOTHING

**The observable, and it is the milestone's largest finding.** As Task 1 shipped
it, `withAnimation` stored the transaction in `Animation.pendingTransaction` and
restored it in its own `defer`. That slot therefore lives for the **lexical
duration of the closure body**. `animated(_:_:for:pass:)` runs during the frame
build, which happens **later, from the display link, entirely outside that
body**. So a production `withAnimation { model.x = 1 }` marked the window dirty,
the next frame built, every animatable field found `pendingTransaction == nil`,
and **every field snapped**. All four sites Task 4 wired ran, and none of them
could ever start an animation.

**Every animating test passed anyway, and that is why nobody saw it.** Each one
calls `animated(...)` **lexically inside** a `withAnimation` body — a
configuration production cannot reach. They are correct about the *helper* and
silent about the *hand-off*. That is taxonomy shape 15 (a fixture in which the
code under test is not reachable in the shape it ships in) pointed at tests
rather than at a benchmark, and it is the sharpest instance this repo has.
(The finding was written up against "the 13 `withAnimation` sites in
`AnimationTests.swift`"; that was a count of sites at the time and a **lower
bound** on the property. What settled it is the instrumentation under the
mutation table: **every** direct-helper site parks nothing, measured, not 13 of
them.)

**Spec §3 already specified the fix and Task 1 did not build it.** §3 reads
"`withAnimation` stores a pending `Animation` on the `Window`" and, in the very
next sentence, "the next frame build carries that animation as ambient context
on the passes, the way `LayoutPass.scrollContext` already is." A `defer`-scoped
static satisfies the first clause read alone and defeats the second. Task 1 and
its review both read the first clause.

**What shipped.** Two slots, two lifetimes, one value, written in the same
statement so they cannot disagree about *which* animation, only about *when*:

- `Animation.pendingTransaction` — the **lexical** ambient. Restored on the way
  out to whatever was parked before, not to `nil`, so a nested `withAnimation`
  leaves the outer one in effect once the inner body returns.
- `Animation.parkedTransaction` — the **parked** one. Survives the call under
  `AN-C`'s rule, and is then taken by the next `Window.drawFrameIfNeeded` and
  handed to the `Frame` as ambient `pass.transaction`. Consumed by **exactly
  one** build (`aParkedTransactionIsConsumedByExactlyOneBuild`).

`animated`/`animatedColor` prefer the frame-carried value and fall back to the
lexical one, which is what keeps both configurations working off one
implementation: production only ever reaches the parked slot (a production
`withAnimation` body never contains a frame build), and the direct-helper tests
only ever reach the lexical one (they never build a frame).

**The pin is what makes this ruling checkable.**
`aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd` drives a **real
frame build** with no `animated()` call inside the body and asserts a mid-flight
interpolated width read out of `Window.lastScene`, not off the helper. The
mutation that restores the pre-fix behaviour is mutation 5 in Task 5's table.

**What it costs if wrong.** Nothing is left of the feature. This is the ruling
that separates "the helpers work" from "the framework animates", and every other
ruling here is downstream of it.

---

## AN-C — the parking rule: park eagerly, roll back only when the counter did not move AND (no build was pending OR the slot was already claimed)

**The rule as shipped**, in `withAnimation`'s own `defer`:

```swift
if Window.redrawRequests == redrawsBefore
    && (!buildAlreadyPending || previouslyParked != nil) {
    Animation.parkedTransaction = previouslyParked
}
```

**Each clause closes a measured failure. None of them is tidiness, and the rule
took two fix rounds precisely because each clause was added after the previous
version was run and found wrong.**

**Clause 1 — the counter — exists because parking unconditionally leaks a
transaction forever.** `withAnimation(.linear(duration: 1)) { }` with a
non-dirtying body — `withAnimation { if cond { model.x = 1 } }` with a false
`cond` is ordinary code — parks a transaction no frame ever consumes, because
`takeParkedTransaction` runs only on a *drawn* frame and no frame is drawn.
Measured by the task review, reproduced rather than reasoned: **400 seconds
later**, an unrelated `model.width = 200` with no `withAnimation` anywhere read a
mid-flight **150** instead of snapping to **200**. Spec §3 accepts collateral
animation *in the same frame*; this was an arbitrarily distant one about
something else. Pinned by
`aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`.

**Clause 2 — "a build was already pending" — exists because the counter-only
rule silently DISCARDS legitimate animations, and the reason is not asynchrony.**
The counter answers "did *this* body dirty a *clean* window", which is narrower
than "will there be a next build". `@State` is genuinely covered — `StateTable.write`
fires `onWrite` unconditionally and `Window` wires it straight to
`setNeedsRedraw()`. `@Observable` is not, and the fix round asked the wrong
question first (is the dirty path asynchronous? it is not — the
`markDirtyFromObservation` main-thread branch is synchronous). The real
mechanism is that `withObservationTracking`'s `onChange` is **one-shot** and the
session is re-armed only by the next *drawn* frame, so the second and every
later `@Observable` mutation between two frames fires no `onChange` and moves no
counter. Measured: `model.width = 120` then
`withAnimation(.linear(duration: 1)) { model.width = 200 }` parked `nil` and
**snapped to 200** where the animation reads **150** — a legitimate animation,
silently discarded, no diagnostic, and **invisible to all 860 tests and to all
four of the mutations the previous round had just written**, because every
existing fixture's animated write was the first of its interval. Pinned by
`anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`,
whose two `try #require`s establish the *fixture* (the first write of an
interval moves the counter; this one does not) rather than the conclusion —
verified by the re-reviewer running the mutant and watching both requires pass
while the failures landed on the width and `hasActiveAnimations` assertions.

**Clause 3 — "or the slot was already claimed" — exists because taking the
re-review's suggestion bare FAILED A TEST.** Park whenever a build is pending,
with no regard for what is already in the slot, and a dirtying
`withAnimation(.linear(duration: 1)) { model.width = 200 }` followed by an empty
`withAnimation(.linear(duration: 4)) { }` hands the **empty** one the build —
because the first call's own dirty made a build pending for the second.
Measured, by running it: **112.0** where the first transaction reads **150**. So
a counter-silent body keeps the slot only when the slot was **free**; if it was
already claimed, the claimant's body demonstrably dirtied a clean window and has
the stronger claim.

**`hasActiveAnimations` is deliberately NOT in the predicate, and that refusal is
pinned.** Mutating it in reddened 0 of 861, so the mutant was **made to show its
behaviour** rather than banked as a gap: mid-fade it parks `linear(4)` where the
shipped code parks `nil` — clause 1's bug again, bounded by the fade's lifetime.
And it can never be *needed*: a counter-silent write implies the session is
spent, which implies an earlier write ran `setNeedsRedraw()`, which implies
`needsRedraw` is still true, since it is cleared only by the draw that re-arms
the session. Measured cost against structurally zero benefit. Arm 4 of the
`aTransactionWhoseBodyDirtiesNothing…` test pins it so it cannot come back
silently (**1 issue, got 100.0**).

**`Window.aFrameBuildIsPending` asks a WEAK REGISTRY of live windows** rather
than keeping a count, because a count needs decrementing from an isolated
`deinit` and a count that drifts upward once parks forever with no diagnostic.
Measured sound: a window leaving scope drops out (pending goes true → false),
and instrumented across the whole suite the registry took **129 registrations
with a maximum array length of 2, ending at 1** — bounded, and incidentally
proof that the suite leaks no window.

**The residual, stated rather than discovered.** Two `withAnimation` calls in one
frame interval where the *second* one's writes are unobserved give the build the
**first** one's curve. Only one ambient transaction reaches one build in any
case, so this is which-curve-wins rather than a dropped animation. Unpinned.

**What it costs if wrong.** The two directions are opposite and both were shipped
at some point in this milestone: too eager parks a transaction that ambushes an
unrelated change an arbitrary time later, and too strict throws away an animation
the caller explicitly asked for. Neither has a diagnostic. That is why every
clause here carries a test rather than a comment.

---

## AN-D — the parking slot is a MODULE-GLOBAL, not on the `Window`, against spec §3's explicit wording

**The choice.** `Animation.parkedTransaction` and `Window.redrawRequests` are
`@MainActor static`. Spec §3 says "`withAnimation` stores a pending `Animation`
**on the `Window`**".

**Why the spec's wording is unsatisfiable as written.** `withAnimation` is a free
function with no window in scope and **no way to name one**. There is no ambient
"current window" anywhere in `Sources/` and no window registry that predates this
milestone — the task review checked for both rather than accepting the claim.
Inventing an ambient current-window to satisfy the letter of §3 would be a larger
global than the one being avoided.

**The cost is a multi-window one and it is stated rather than discovered:** with
two windows live, whichever builds first consumes the transaction and the other
snaps. `Window.redrawRequests` is global for the same reason, so the parking rule
is cross-window too. **Unreachable today** — nothing in `Sources/` or `Tests/`
constructs two live windows that both build.

**The fix, when a second window ever exists**, is a per-window parking slot plus
a way for `withAnimation` to name its window: a signature change, not a redesign
of anything in `AN-C`.

**What it costs if wrong.** A second window arriving before this is fixed
produces an animation that runs in one window and snaps in the other, with no
diagnostic. That is why it is a named narrowing in three places — this ruling,
`Animation.parkedTransaction`'s doc, and CLAUDE.md — rather than a silent one.

---

## AN-E — FOUR registering sites, not one choke point; the spec's §5 premise was wrong on site count and Task 4b showed it was wrong on PHASE count too

**What §5 originally claimed.** "`Row`, `Column` and `Stack` each hold a `Box`
internally, so `Box.requestLayout` is the single site every styled layout flows
through."

**Wrong on site count, and enumerated rather than argued.** `Row` and `Column` do
hold a `Box` (`Flex.swift`). **`Stack` does not** — it is its own
`Element, StyledElement` calling `requestNode` directly. There are **four** sites
that register a styled node: `Box.swift`, `Stack.swift`, and `ScrollView`'s
**two** (content node and viewport node). §5 was corrected before the milestone
started; this ruling records that the correction held under execution — Task 4
re-enumerated and found no fifth, and so did its review, independently.

**Wrong on PHASE count as well, and that was found later** (`AN-F`). Colour
cannot be interpolated from `LayoutPass` at all, so the mechanism is not one
helper called from four sites; it is **two helpers in two phases**, called from
four layout sites and three paint sites.

**So the guarantee is weaker than a choke point and must be said so: an element
that registers a node without calling the helper is silently unanimated, with no
diagnostic.** Same shape as `StyledElement`'s `registerHandlers` requirement.
The guard is `everyRegisteringSiteAnimatesItsStyle`, one case per site — and
**it was genuinely red on arrival**, which is the whole reason that task exists.
With all four `Sources/` edits stashed it recorded **6 issues**, and it went green
one site at a time, **6 → 4 → 2 → 1 → 0**. That sequence is what proves the test
reaches each site rather than the sites its author remembered. All four un-wiring
mutations then reddened **exactly their own sub-case (2 / 2 / 1 / 1)** and
nothing else. `everyBackgroundPaintingSiteAnimatesItsColour` is the paint-side
equivalent (`AN-Q`).

**`ScrollView` registers two nodes from one element id**, so it was given two
**named child ids** rather than letting both nodes collide on the element's own
`$anim` slot — see `AN-P`.

**What it costs if wrong.** A fifth registering site added later animates nothing
and no ordinary test can see it. The per-site guard is the only thing that turns
that into a failure, and a guard written *after* wiring cannot tell "this site is
covered" from "this test cannot see any site" — which is why red-on-arrival was a
requirement of the task rather than a nicety.

---

## AN-F — colour animates at PAINT, in a SECOND helper, on the RESOLVED value rather than on three fields

**The choice.** `AnimatedColor.swift`'s `animatedColor(_:for:pass:)` runs during
`paint`, keyed by a `$anim-color` slot, and is a separate mechanism from
`AnimatedStyle.swift`'s `animated(_:_:for:pass:)`.

**The phase split is structural, not a shortcut.** `Decoration`'s three
`ColorToken?` fields cannot be interpolated from `LayoutPass`, because spec §4's
own third rule requires two tokens to interpolate "through their theme-resolved
`Hsla`", **re-resolved every frame**, and **only `PaintPass` has a theme**. What
stays at layout is all of `Style` plus `Decoration.cornerRadius`, which is a
plain `Pixels` and needs no theme.

**One value, not three fields, and this is the better decomposition.**
`Box.paint` already selects among `focusBackground` / `hoverBackground` /
`background` by pointer state before drawing. Animating the **resolved result of
that `??` chain** is what makes hover and focus transitions use the same path;
animating the three fields separately would animate values that are not on
screen. This is a deliberate departure from the spec's own field list.

**Amended 2026-09-10 (review finding B-9):** the `focusBackground` / `hoverBackground` / `background` chain this passage places in `Box.paint` now lives in `animatedBackground(_:for:pass:)` (`AnimatedColor.swift`), called by `Box.paint`, `Stack.paint` and `Text.paint`. Until then both modifiers compiled on `Stack` and `Text` and painted nothing. The substance is unchanged — one resolved value is animated, not three fields; pinned per site by `everyBackgroundPaintingSiteHonoursHoverAndFocus`.

**The phase choice is PINNED, not merely argued.** Without a test, "colour lives
in paint because only `PaintPass` has a theme" is an assertion nothing can see.
`aThemeChangeMidFlightMovesBothOfTheAnimationsEndpoints` is the pin, and the
mutation that decides it (resolve once and store) was **split per endpoint**:
it reddens that test's `to` arm (**4 issues**) and its `from` arm (**3**) and
nothing else in the suite.

**Why it was implemented rather than deferred to a named hole.** A
`withAnimation` around `.background()` that compiles and does nothing is exactly
the declared-but-inert trap CLAUDE.md keeps a table for, on the property most
commonly animated in any UI — and it is the affordance CLAUDE.md already records
a human being unable to read as a static token swap ("a judgement about two dark
greys").

**What it costs if wrong.** It grew the milestone by a task (4b) and grew Task 5,
which had to make paint able to contribute to `hasActiveAnimations` (`AN-M`). The
fallback was cheap and reversible throughout: drop the paint-side helper and
record colour as a named hole beside `Text`'s.

---

## AN-G — colour interpolates per-component RGB, NEVER hue, in CoreAnimation's gamma-sRGB encoding

**The choice.** Two `Hsla` endpoints are converted to `Rgba`, interpolated
per-component, and converted back. No hue lerp, no shortest-arc rule, no
linearization.

**Both oracles were MEASURED rather than assumed, each with a positive control,
and one of the controls failed twice and was fixed rather than believed.**
Throwaway probes outside the repo (`CO-E`'s footing, deliberately uncommitted):

| oracle | what it interpolates | encoding |
|---|---|---|
| SwiftUI (`Color.Resolved.animatableData`) | **RGB** | cube-root-of-linear — matched `srgbEncode(t³)` at four fractions to four decimals |
| CoreAnimation (a real presentation layer) | **RGB** | **gamma sRGB exactly** |

**Neither interpolates hue.** The wrap-around case is what makes that a
measurement rather than a preference: a pair whose midpoint the two oracles agree
on reads **h = 0.9995**, where a hue lerp gives **cyan**.

**They disagree on encoding, and CoreAnimation's was taken, for a reason this
repo already has on the books.** `Rgba` *is* gamma sRGB, and design spec §7.8
forbids linearizing — the pixel format is `bgra8Unorm`, never `_sRGB`, because
compositing here is gamma-space by design. Taking SwiftUI's cube-root-of-linear
would mean linearizing on every interpolated frame, against §7.8, to match an
encoding no other part of this framework uses. This is the one place in the
milestone where `EP-5` ("prefer SwiftUI's answer") is *not* followed, and the
reason is that a lower-level, already-binding rule decides it.

**Pinned twice, and the second pin was not noticed by the task that shipped it.**
Mutating the helper to interpolate in HSL reddens **23 issues across five tests**
— that pins RGB-vs-hue. And the task review found that **test 1's midpoint
independently pins the gamma encoding**, which the task's own report did not
claim.

**The overshoot clamp is the best work in the task and it came from a mutation
that reddened NOTHING.** Dropping the clamp reddened **0 of 848**. Instead of
banking a coverage gap, the implementer made the mutant show its behaviour: a
bouncy spring peaks at **saturation 1.2846** — not a colour — and that value is
handed to the shader. It closed the gap with a test. That test's own first draft
then reddened **14 times with the clamp present**, because `Rgba.toHsla` returns
**1.0000001** for a legitimately saturated colour; the vacuity guard is
`s >= 1 - slack` with `slack = 1e-3`, and **both numbers the slack separates are
measured**: `1e-3` is **8,388.6 ULPs** of `Float(1.0)` (whose `ulp` is
`1.1920929e-07`), and `1.0000001` is **exactly one** ULP — a **284.6×** margin.
The comment at that line says out loud that this is the *second* unmeasured
number the same line has carried.

**What it costs if wrong.** A hue interpolation would take the visually
"correct-looking" arc through unrelated colours and would need a shortest-arc
rule nobody asked for; a linear-light interpolation would disagree with every
other colour operation in this framework. The clamp's absence would hand the
shader values outside the colour space with no assertion able to see it.

---

## AN-H — the slot stores TOKENS, not resolved colours — and the brief that forbade it contradicted itself

**The choice.** `$anim-color` stores the baseline and the `to` endpoint as
`ColorToken`s. Both ends re-resolve through the theme every frame.

**Why resolved-colour storage does not work.** It makes a **theme swap
indistinguishable from a declaration change**, so a theme switch during a fade
snaps it — exactly the discontinuity spec §11's last risk row exists to prevent,
and the opposite of spec §4's third rule.

**The implementer deviated from its brief on this point and was RIGHT, and the
brief was internally inconsistent.** The task review settled it: brief test 4 and
brief step 6 **both require token storage**, so the brief's resolved-`Hsla`
instruction was never satisfiable. The controller's brief was wrong, not the
implementer — recorded because a deviation reported and then vindicated is worth
more in the record than a deviation nobody questioned.

**Tokenness is pinned, and it needed its own test.** Storing resolved `Hsla` in
the baseline comparison reddened **0 of 849** and was proved non-equivalent by
probe: a settled element spuriously raises `hasActiveAnimations` for a full
animation duration after a theme swap. Closed by
`aThemeSwapAloneNeverStartsAFadeOnASettledElement` — **2 issues, that test
alone**. What makes the two implementations distinguishable at all is having a
transaction in flight; without one, both snap.

**One end is narrower than spec §4 promises, and it is pinned as such.** After an
**interruption**, the `from` end is a fixed colour rather than a re-resolving
token: re-resolution survives only when the transition began from a declared
baseline. `anInterruptedFadeFreezesItsFromEndAgainstALaterThemeSwap` pins it with
a **control** — an un-interrupted fade taking the identical swap at the identical
elapsed time *must* move, because without that arm "did not move" is satisfied by
a helper that re-resolves nothing. Justifying mutation (freeze `to` on the
interrupt path only): **3 issues, the new test alone**, and the pre-existing
theme test cannot see it because it never interrupts.

**What it costs if wrong.** A theme swap mid-fade produces a visible jump —
which is precisely the failure spec §11 predicted, arriving through an
optimisation that looks free.

---

## AN-I — the spring settling threshold is DERIVED, twice, and the second derivation exists because the first was measured wrong on half its input space

**The rule as shipped.**

```swift
let scale = max(abs(x0), abs(v0) / omega)
let positionThreshold = min(0.001 * scale, absoluteCeiling)   // absoluteCeiling = 1/6
let velocityThreshold = positionThreshold * 120.0
let isFinished = abs(displacement) <= positionThreshold && abs(velocity) <= velocityThreshold
```

**First derivation, in points.** `0.5 / 3.0` is half a device pixel at a
plausible high-density (3×) scale factor; `× 120` is the velocity that could
cover exactly that distance within one 120 Hz frame. Dimensional analysis
confirmed by the review: multiplying by 120 is right, dividing would be 14,400×
too strict.

**It was measured WRONG for every normalized property, and the measurement is
the reason it changed.** `value(at:)` is unit-agnostic. On `spring(0.5, 0.4)`
a 100pt travel settled at **99.8%** complete, a 2pt travel at **91.8%**, and a
0→1 opacity at **83.6%** — it **snaps the last 16%**. Worse, that spring's peak
velocity is ~6.2/s against a 20/s threshold, so **the velocity half of
`isFinished` could never gate for a normalized property** — and colour animates
in `Hsla` on 0..1. The exact guarantee the milestone's own required mutation
exists to protect was dead for opacity.

**Second derivation, relative with an absolute ceiling.** Scaling by the travel
makes a 0→1 opacity and a 0→100pt slide settle at the same fraction: re-measured
after the fix, **99.900% at travel 1, 2 and 100 alike**, against the flat rule's
99.8 / 91.7 / 83.3. `min(0.001 * scale, 1/6)` is a **ceiling** on the threshold —
a floor on *precision* — and the comment clauses that called it an "absolute
floor capping how much precision is ever demanded" said the opposite of what
`min` does; corrected at the line.

**`scale` is the motion that REMAINS, not the travel, and that third correction
came from the other half of the input space nobody had measured.** `travel` is
the correct scale only when `v0 == 0`. With a `travel == 0` special case, a
spring interrupted **at its target** with `v0 = 19.9` reported finished at
`t = 0` and then travelled **0.79** — for a 0→1 opacity, 79% of the range
declared settled before it moved. And there was no lower bound: travel `1e-12`
with `v0 = 6` stayed unfinished **4.35 s** where the flat threshold took ~0.2 s —
discontinuous with `travel == 0`, which finished instantly at the same momentum.
`|v0| / omega` is the displacement an inbound velocity produces in the undamped
case, so it is dimensionally a length and is the natural companion term; taking
the max of the two subsumes both failures and is continuous in `(travel, v0)`
together. Re-measured after: interrupted-at-target settles at **~0.62 s**, and
travel 0 and travel `1e-12` at identical momentum settle **identically**.

**`omega` is the UNDAMPED natural frequency (`2π / duration`), not the damped
`omegaD`, and that choice is load-bearing rather than incidental.** The round-2
re-review reimplemented the spring from scratch as an RK4 integration of the raw
ODE in Python and reproduced every headline number; its control run substituting
the damped frequency gives **0.6147 s against 0.6209**, so the two are
distinguishable and the right one was used.

**The `<=` in `isFinished` is NECESSARY and UNPINNABLE by mutation alone — this
is the milestone's cleanest instance of "a mutation that reddens nothing".**
Reverting `<=` to `<` reddened **nothing**: 16/16 tests passed and `isFinished`
has no other reader. Stopping there gives "cosmetic", which is wrong. The
reviewer instead built the case the code's own comment names — genuinely at rest,
`from == to`, `v0 == 0` — and found that under `<` the spring reports
`!isFinished` at `t = 0` **and forever**, since `scale` is exactly 0, so
`positionThreshold` is exactly 0, and `0 < 0` never holds. Deleting the
`travel == 0` special case had removed the only thing routing that case through a
nonzero constant. **Without the swap, the relative-threshold fix would have
shipped a spring created at its target that can never finish — a permanently
awake display link the moment `isFinished` reached `hasActiveAnimations`.** Now
pinned by `aSpringAlreadyAtRestIsFinishedImmediately`, which the `<` mutation
reddens with exactly **1 issue**.

**`bounce` gets a `precondition`, not a clamp** — `bounce == 1.0` gives
`zeta == 0`, undamped, `isFinished` never true (verified out to t = 30 s), and
`bounce <= -1.0` divides by zero into NaN with no diagnostic. It is programmer
error, not a runtime condition, and this repo already uses a precondition for
that shape at `LayoutTree.setStyle`; a clamp would silently animate something
other than what was asked for. Both boundaries pinned with
`#expect(processExitsWith: .failure)`. `timingCurve` clamps `x1`/`x2` to `[0,1]`
and leaves `y1`/`y2` free, which is CSS's own rule for CSS's own reason —
measured: `timingCurve(2.0, 0, -1.0, 1.0)` yields **three roots at u = 0.5** and
the solver returns the lowest (0.0352 vs 0.5). And all five arguments get a
finiteness precondition, because `min(max(.nan, 0), 1)` is `.nan` in Swift, so
the clamp passed NaN through silently while a loud precondition sat one screen
away.

**What it costs if wrong.** A threshold that is too loose declares a spring
finished while it is visibly moving and the value snaps; too tight, and
`hasActiveAnimations` never goes false and the display link never pauses — M4's
own idle criterion, sabotaged from a call site. Both directions are pinned.

**Amended 2026-09-10 (review B-12): `duration` is finite-preconditioned on
`linear(duration:)` and `spring(duration:bounce:)` too.** AN-I covered `bounce` and
all five `timingCurve` arguments and never mentioned the other two constructors'
`duration`. Both evaluators' `> 0` guard snaps 0, negatives and NaN, but lets
`.infinity` through. Measured on the unfixed source: `linear` and a bounce-0 `spring`
sat at `from` with `isFinished == false` at elapsed 0 through 1e6, and a bounce-0.2
`spring` returned NaN forever, so the display link never paused. The rule is
`isFinite`, not `> 0`: 0 and negatives still snap and 1e9 still animates. NaN, which
used to snap, now traps, to match `easeIn`/`easeOut`/`easeInOut`, which already
trapped through `timingCurve`. Pinned by `AnimationDurationTrapTests.swift`.

---

## AN-J — same case interpolates, different case snaps, and `.auto` always snaps

**The rule.** `Dimension`/`Length` interpolate only when both endpoints are the
same case: `px → px`, `rem → rem`, `pct → pct` interpolate; `px → rem`,
`px → pct`, `auto → px`, `px → auto` snap. Verified on all seven pairs by the
reshape's re-review, run rather than read.

**Why `.auto` cannot interpolate.** It carries no number. Interpolating from a
*resolved* size instead would make the animation depend on layout output that
does not exist yet at the point the style is resolved.

**Why a `percent` and a `length` cannot.** The percentage's basis is not known
where the comparison happens.

**A caller's most likely first attempt hits this and nothing says so.** **Five
`Style` fields default to `.auto`** — `inset`, `size`, `minSize`, `maxSize` and
`flexBasis` — which is **11 of the 28 animatable keys** once the multi-component
ones are expanded (`inset` ×4, `size`/`minSize`/`maxSize` ×2 each, `flexBasis`
×1), leaving the 17 that default to a real length or number. Re-counted against
`Style.swift`'s declarations and `animated(...)`'s key table for this document.
**Every one of those 11 silently snaps on its first transition** — an element
that has never had an explicit `size` and is given one animates nothing on the
first change and animates normally on every change after. The demo's own sidebar
declares `Pixels(196)` rather than relying on `.auto` for exactly this reason,
and says so at the line (`AN-R`). Named here rather than left to be discovered.

**Detecting a MID-FLIGHT case change is why `caseTag` survives the storage
reshape** — see `AN-L`.

**What it costs if wrong.** Interpolating across cases produces a number with no
meaning (halfway between `50%` and `100px`), which is worse than snapping and
would be invisible until a rect was read.

---

## AN-K — `aspectRatio` stays inert, and the constraint was UNGUARDED BY 843 TESTS until Task 4's third fix round

**The choice.** `aspectRatio` is not animatable. `newStyle.aspectRatio` is simply
never assigned in `animated(...)`, so it carries through unchanged.

**The reason is the inert table's own trap, doubled.** `aspectRatio` has **zero
production reads** — re-verified for this document: `grep -rn "aspectRatio" Sources/`
finds its declaration in `Style.swift` and nothing but comments elsewhere.
Offering animation for a property that does nothing is that table's exact
failure mode with an extra layer. It becomes animatable in the same change that
makes it live, and not before.

**It was a plan-level Global Constraint and NOTHING ENFORCED IT.** Wiring
`aspectRatio` into `animated()` ran **green at 843** — measured, twice, in a
worktree with the rebuild verified in the log so it was not a stale-build
artifact. The key-set assertion that was supposed to catch it could not fire,
because `aspectRatio` was `nil` in both fixtures and the three colour fields sat
at `Decoration()` defaults, so its `unexpected` half had nothing to compare.

**Closed by making the fixture per-field-distinct.** After that change the same
mutation gives **1 issue reading `unexpected ["aspectRatio"]`** — a failure
message that names the field.

**What it costs if wrong.** An inert property gains an animation nobody can use
and the inert table's row silently becomes half-true. The cost of the guard is a
fixture whose 28 fields carry distinct values, which `AN-T` shows was needed
anyway.

---

## AN-L — ruling U's storage reshape, and its reason (c) was REFUTED BY ITS OWN IMPLEMENTATION

**The choice.** One `Style` + `Decoration` **baseline snapshot** per element,
plus an `inFlight` dictionary holding an `AnimatedFieldState` for **only** the
fields genuinely still interpolating. Not one field state per animatable field.

**Why it changed mid-milestone, and the numbers are the whole argument.** Wiring
the helper into `Box` gives **every** rendered `Box`/`Stack`/`ScrollView` node a
permanent `StateTable` entry from its first frame. The first shape cost
**~7.5 KB per element**, measured four independent ways (7533 / 7427 / 7559 /
7503 bytes) — the payload is only 28 × 88 B, but Swift's `Dictionary` rounds 28
entries to capacity 64. Cold frame, release, `phys_footprint`, base `a359727`
against head `562488f`:

| n | before | after | delta |
|---|---|---|---|
| 10,000 | 48.4 MB | 122.7 MB | +74.3 MB (2.5×) |
| 100,000 | 664.3 MB | 1,420.2 MB | +755.9 MB (2.1×) |

Time was the **smaller** cost: the gated 100k test went **16.60 s → 17.47 s**
(median of three, +5.3%), and on a text-free fixture of the same shape, where
string shaping does not dilute it, **+44% at 100k and +49% at 10k**.

**The spike DOES reap — it is transient, not a leak.** Checkpoints 256 / 256 /
150 against base's 77 / 127 / 99, and at 100k the process falls from **1.43 GB
back to 164 MB within ten scroll frames**. `AN-O`'s `mark` is what makes that
work. But 1.42 GB transient is still a ship-blocker on the exact M3 criterion
CLAUDE.md already records as "met for scrolling and not for appearing".

**The reshape, measured on the SHIPPED shape rather than on the projection:
7,636 → 643 bytes per entry, ~91.6%**, at n = 20,000 in isolated processes, with
a bare-`Int` control at 187. At 100k the animation overhead falls from ~756 MB to
~51 MB. **Entry count did not change** — `2n + 6` on the cold frame, measured at
20,006 for n = 10,000 — only each entry's payload.

**Reason (c) was refuted by the implementation, inside the round that shipped
it.** The ruling gave three reasons and called the third "the one that makes it
not a cost trade": that the `caseTag` 0/1/2/3 space and its `preconditionFailure`
would disappear, removing 60–80 lines from a 323-line file. **None of that
happened.** `caseTag`, `decomposeLength`, `decomposeDimension`, `recomposeLength`,
`recomposeDimension` and the `preconditionFailure` all survive; the native case
comparison landed as a **fast path in front of** the tag machinery rather than as
a replacement; and the file went **322 lines at `562488f` → 416 at the reshape
commit `6f7f7d7` → 444 at the end of that round**, 122 added where 60–80 were
predicted removed. (It is longer still today — 547 at `b869253` — partly because
the correction block recording this is itself part of the cost of the prediction
having been wrong.)

**The decision STANDS on (a) memory and (b) containment alone, and keeping
`caseTag` is CORRECT.** Detecting a **mid-flight** case change needs the running
animation's own case, and a native `Style` baseline does not carry it: once a
field is in `inFlight`, `existing.style.<field>` is the last *declared* value,
while what a case change must be tested against is what the animation is
currently interpolating between. Removing the tag space means storing
`Length`/`Dimension` natively inside `AnimatedFieldState` — a second, larger
change, not a deletion.

**And a projected number sat in `Sources/` under the word "Measured" for a whole
round.** The line read "7,503 → 509 … a 93% reduction", which is the
controller's dispatch-time projection for the *proposed* shape; the implementer
measured the shipped shape at **7,636 → 643** and that figure reached the round's
report and never reached `Sources/`. **509 against a real 643 is a 26% gap.**
Corrected at the line, with the original visible.

**What it costs if wrong.** Shipping the first shape would have made M3's
already-failing "appearing" half materially worse — 1.42 GB of transient
allocation and ~5% slower — on a criterion this project already flags. The cost
of the reshape was a contained rewrite of one file plus two `ScrollView` guard
sub-cases.

---

## AN-M — there is ONE notion of "an animation is live", and it is `hasActiveAnimations`, not `wantsAnotherFrame`

**The choice.** Both helpers call `Frame.noteActiveAnimation()`. `Window` copies
`frame.hasActiveAnimations` **after the whole render** — layout *and* paint — and
the idle guard is `needsRedraw || hasActiveAnimations`.

**Task 4b proposed `Frame.wantsAnotherFrame` as the paint-side signal and Task 5
moved the carrier rather than taking it, deliberately.** Two signals for one
claim would have kept each other green under mutation. `wantsAnotherFrame` still
means "mark the window dirty next frame" and retains exactly one raiser,
`ScrollView`'s indicator fade; after Task 5 **nothing raises both**.

**It keeps the loop running WITHOUT dirtying the window**, so a window mid-fade
reports `needsRedraw == false` — which is the difference between an animation and
a dirty window and is what makes the pause criterion meaningful.

**It must not be computed from layout alone**, or a fade on a style-static
element stops the instant input stops. That is why `Window` copies the flag after
the whole of `render` rather than after the layout walk, and why the pin
`aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning` uses a subject whose
width and height are literals — so `animated(...)` leaves `inFlight` empty on
every frame and the layout half is silent by construction.

**Both halves are pinned and they redden disjoint assertion sets.** Cutting
`Window.swift`'s `hasActiveAnimations = frame.hasActiveAnimations` gives **21
issues**; emptying `Frame.noteActiveAnimation()` gives **24**, and the difference
is exactly the three assertions that read `Frame.hasActiveAnimations` directly.
Both readings are legitimate and the mutation row names both rather than picking
one — that ambiguity is what a reviewer's independent count found first.

**This discharges `RX-O` the way it asked to be discharged**: the property
arrives with a writer and a reader in the same change, and there is no
always-`false` stored property at any point in the diff.

**What it costs if wrong.** A second liveness signal is the classic way two
mechanisms keep each other green: mutate one and the other still answers, so
neither is ever shown to be load-bearing.

---

## AN-N — the timebase fix ships UNPINNED, and that is correct rather than an omission

**The change.** `AppKitPlatform.displayLinkFired` passes
`displayLink?.targetTimestamp` where it passed `displayLink?.timestamp`.
Design spec §4.4 has required the target presentation timestamp since M0; the
code did not comply **for five milestones** and now does. Re-verified for this
document: `grep -rn "displayLink?.timestamp" Sources/` returns **0**.

**No assertion in this repo can distinguish the two, and this was established
rather than assumed.** `FakePlatformWindow.simulateTick(timestamp:)` supplies
whatever the test chooses and **bypasses `displayLinkFired` entirely for every
consumer**; no test constructs a real `AppKitWindow` or fires a real
`CADisplayLink`. This is the same boundary CLAUDE.md already records for the
display-link pause and for hover from a real `NSTrackingArea`. Writing a test
that *appears* to check it was forbidden by the plan and refused by the
implementer, which is the right call: a fake pin here is worse than none.

**Availability was verified by reading the SDK header** against the
`.macOS(.v14)` floor, plus a clean build — not by assuming `targetTimestamp`
exists. The consumer chain was traced end to end
(`ScrollView.paintIndicator` → `pass.timestamp` → `Frame(timestamp: lastTick)`
→ the tick closure) rather than taken from a comment.

**The structural pin is the grep, and it is named as structural.** Exit criterion
4 is `grep -rn "displayLink?.timestamp" Sources/` returning nothing. That is a
shape check, not a behaviour check, and the difference is stated rather than
implied.

**The change INVERTED an existing comment, at the exact site the implementer read
and quoted as corroboration.** `Window.applyScroll` said the event's own time "is
also simply more current than `lastTick`, which is the *previous* frame's
instant, even when not idle." Before the change `lastTick` held the previous
frame's **presented** timestamp, always behind "now", so the claim held
trivially. After it, `lastTick` holds the **upcoming** presentation instant,
about one frame interval *ahead* of now, so an event arriving between ticks
typically has `event.timestamp < lastTick` — the reverse. The comment's
*conclusion* survives on its other justification (staleness while the link is
paused); only the "even when not idle" clause inverted. **Practices mechanism 1
exactly: the one site in the codebase most likely to be falsified by this change
was read and not swept.** The fix-round sweep then found **zero** additional
sites beyond that one and a weaker sibling in `ScrollView.swift`, and correctly
left a *historical* doc quote alone rather than "correcting" a record of what was
believed at the time.

**What it costs if wrong.** A future edit reverts the clock and nothing reddens.
The grep is the only thing standing between this and a silent regression, and
saying so is the point of this ruling.

---

## AN-O — a baseline is stored on FIRST SIGHTING; the helper peeks, MARKS, and writes only when dirty

**Three constraints, and the third was found by measurement after the first two
shipped.**

**Store via `withState`, never `write`.** `write` raises `isDirty` and fires
`onWrite` → `Window.setNeedsRedraw()`; `withState` does neither. The helper runs
in `requestLayout` on **every frame at every registering site**, so `write` would
re-dirty the window every frame and the display link would **never pause** —
precisely the hazard CLAUDE.md's `@State` bullet forbids, and it would silently
sabotage the idle criterion M4 spec 1 had just delivered. `$focus` and `$ax`
already store via `withState`. Pinned by a tree whose style never changes,
rendered N frames, producing zero dirtyings; the `withState` → `write` mutation
reddens **20 issues on exactly one test** and nothing else.

**Peek before writing, or a 500-row `List` mints 500+ entries.** `withState`
inserts on access. The tombstones milestone measured the cold-frame resident set
at `n + 2` and `sweepThreshold` is 256, so any real tree would cross the gate and
turn the reap on for everything. Pinned by
`aSettledFieldStopsIncrementingTheWriteCount`, which is what
`StateTable.writeCount` exists for — an inert-table row added by the task that
made it inert (`AL-6`'s rule), not deferred to this document.

**But an entry the helper declines to write is never MARKED, and that is a
SILENT MISS rather than mere churn.** A continuously-produced but *unchanging*
element was never marked at all, so it would go stale and be reaped **while being
produced every frame** — the steady state for any element that sits still for two
generations. The next `animated()` call then peeks `nil`, takes the
first-sighting path, mints the baseline equal to the **new** value, detects no
difference, and the change **snaps silently**. `StateTable.mark(_:)` is the
existing API for exactly this: it marks without reading or creating an entry,
fires no `onWrite`, sets no `isDirty`, and is a no-op when there is no entry — so
it costs nothing the first two constraints care about.

**The controller's own stated mechanism for that bug was WRONG and the
implementer measured the real one.** The controller described a persistent churn
cycle in which the baseline is repeatedly minted equal to the new value. In fact
a reaped entry is silently **repaired by the very next `animated()` call**,
because the first-sighting path calls `withState`, which marks — so the entry
lacks a baseline for exactly **one frame**, not continuously. The conclusion
(change the value *during* the window) was right; the mechanism was wrong, and
the difference is what had made the original test blind: it changed the value ten
frames later, long after a one-frame hole had closed.

**The test therefore SELF-DISCOVERS the vulnerable frame** — it renders settled
frames one at a time, breaks the instant a peek on the `$anim` slot returns
`nil`, and injects the change on that exact next call. Checked for vacuity rather
than trusted: `#expect(!reaped, …)` is asserted unconditionally and both the
found and not-found paths fall through to the same real assertions. Under the fix
the loop exhausts its bound of 20 with `reaped == false`; under the mutation it
breaks at frame 3. Removing **only** `mark` reddens that one test with **3
issues** — `!reaped` fails, transaction-start reads 100 instead of 0, mid-flight
reads 100 instead of 50. The silent snap, fully reproduced.

**Storing a baseline on first sighting is accepted, and the trade is real.**
Without it the first change on any field is undetectable. Storing it only under a
transaction does not work either: the transaction is pending on the frame the
change is **observed**, so the previous value must already have been stored on an
earlier frame when none was pending. `mark` is what makes the cost acceptable —
it is what turns the cold spike into something that reaps (`AN-L`).

**What it costs if wrong.** An animation that silently does not happen is the
worst failure this subsystem can have, and every one of the three constraints
above has a version that produces exactly that with no diagnostic.

---

## AN-P — `$anim` and `$anim-color` are the sixth and seventh reserved slot names; `$anim-content`/`$anim-viewport` are id PREFIXES, not slots

**The names.** `$state\(n)`, `$focus`, `$ax`, `$anim`, `$anim-color`, and the two
`ScrollView` prefixes `$anim-content` / `$anim-viewport`. **Seven**, none
guarded against a hand-written `.id(…)` or a `List` datum whose id *describes* to
one of them — the same unguarded collision risk CLAUDE.md already recorded for
the first three.

**The two `ScrollView` names are a different shape from the other five and the
record described them wrongly until a re-review caught it.** `ScrollView`
registers **two** nodes from **one** element id, and `animRetentionSlot(for:)`
derives exactly one `$anim` slot per id it is given — so passing the element's own
id twice would collide both nodes' fields under one slot. Each node gets a named
child id instead, and the `$anim` slot then hangs off *that*: the value lives at
`child(child(id, "$anim-content"), "$anim")`, a **grandchild**. So they are
prefixes, not slots. The conclusion (they must be counted and kept distinct) was
right the whole time; the described mechanism was not.

**Those two ids are exposed as FUNCTIONS rather than inlined, and that is
load-bearing.** A test that reconstructs the two strings as its own literals
cannot catch a rename at the real call site — measured, by making exactly that
mistake first: a test built from its own copy of the strings stayed green under a
rename of the real literal. `ScrollView.swift` and `AXNodeTests.swift` call the
same two functions, so a rename in either can only ever be a rename in one place.

**One test, extended in place three times, not four rival tests.**
`theThreeRetentionSlotsAreMutuallyDistinct` → four (Task 3) → six (Task 4's fix
round) → **`theSevenRetentionSlotsAreMutuallyDistinct`** (Task 4b). That test
exists because renaming `"$ax"` to `"$focus"` once reddened **0 of 777** while
silently dropping focus (`TB-R`), and the new names arriving unguarded is the
same hazard with more ways to collide.

**Extending it in FORM was not enough, and the review measured that.** As Task 3
first wrote it, renaming `"$anim"` to `"$focus"` reddened **0 of 837** — a rename
without a guard, `TB-R`'s exact failure reproduced on the fourth slot. The
mechanism: the test asserted a **settled** value, and a fully clobbered slot
produces the same settled value, because the helper treats a `nil` peek as a
first sighting and returns the declared value. Its own comment recorded choosing
the settled shape to avoid threading a timestamp; that simplification is what
removed its power. **The fix is to assert a value only an intact slot can
produce**: start a real animation and read back **mid-flight** — 50.0 intact
against 100.0 collided. The rename mutation then reddens **1 issue** on that test
and nothing else.

**Renaming it left four live citations of a test that no longer existed**
(`StateTable.swift`, `AnimatedStyle.swift` twice, `docs/record/01-start-here.md`)
against CLAUDE.md's own promise that every cited test name resolves. Swept
**case-insensitively** rather than fixing the four that were named, the sweep
found exactly those four and no fifth, and the record entry now carries the old
name as an explicit **alias** so a citation of any generation resolves.

**What it costs if wrong.** Two slot names colliding drops one subsystem's state
into another's with no diagnostic — the failure `TB-R` measured at 0 of 777.

---

## AN-Q — `Stack.paint` and `Text.paint` were WIRED in Task 5 rather than left as named holes

**The choice.** Three of the four `pass.fill` sites animate their background
through `animatedColor`: `Box.paint`, `Stack.paint`, `Text.paint`. The fourth is
`ScrollView`'s indicator, which drives itself by dirtying and is deliberately
left alone (`AN-M`).

**Task 4b left `Stack` and `Text` unwired and both of its reviews accepted the
exclusion on one stated ground: "not live today", because ruling `AN-B`'s
hand-off did not exist yet.** Task 5 is the commit that removes that ground.
Leaving them would ship a `Box` that fades beside a `Stack` that snaps, with no
diagnostic — so they were wired in the same change, and the implementer's reason
for exceeding its brief is the right one.

**`everyBackgroundPaintingSiteAnimatesItsColour` is the per-site guard**,
`AN-E`'s paint-side equivalent: un-wiring `Stack` reddens only the `Stack` arm,
`Text` only the `Text` arm. The reviewer re-enumerated the sites independently —
exactly four `pass.fill` sites exist, three wired, the fourth named.

**Two holes remain and they are spec §8's, not oversights.** `Text`'s **glyph
colour** and its **measured style** are not animated. `Text` registers through
`newLeaf` with a `MeasureFunction`, and its style participates in *measurement*
rather than only in layout — animating it means re-measuring text every frame,
which is a different cost question from substituting a number.

**What it costs if wrong.** Wiring a paint site that should not have been wired
shows up immediately in a golden or a rect; leaving one unwired shows up as a
container that snaps beside identical containers that fade, which is the kind of
inconsistency a user reports as "sometimes it animates".

---

## AN-R — the human look got its own task (5b), dispatched BEFORE the record rather than after it

**The gap.** Spec exit criterion 9 — "a human runs the demo and reports whether
the motion looks right" — was delivered by **no task in the plan**. `grep -n MetalUIDemo`
over the plan returned nothing, and the documentation task is docs-only. So the
milestone as planned ended with nothing in the demo to animate and no
human-verification entry, while spec §9's own "what no test here can see" names
the motion's look as the one thing only a human instrument reaches.

**And it was measured unreachable rather than assumed so.** Task 5's implementer
checked: nothing animates without a transaction, and `grep -rn withAnimation Sources/`
found no caller outside `Animation.swift`'s comments. All three existing demo
keys are the **wrong subjects** — the modal is an *appearance* (which snaps), the
theme deliberately never fades, and the counter is text content. This also
corrected the controller's own closing claim in the dispatch that preceded it.

**Why it ran BEFORE this document.** Step 4 of the record task verifies every
claim in the record by running it, and "the human look is now reachable" is
exactly such a claim. Writing the record first and the demo second would put an
unverifiable sentence in the record of the milestone whose whole practice is that
unmeasured claims are the defect.

**What shipped: two subjects, one element, one transaction.** Key **A** toggles
`DemoModel.animationDemoActive` inside
`withAnimation(.spring(duration: 0.6, bounce: 0.2))`. The sidebar `Column`'s
declared width (196 ↔ 320, the **layout**-phase helper) and its background token
(`.surface` ↔ `.accent`, the **paint**-phase helper) both read that one Bool, so
one keystroke drives both helpers **and a human can report them separately** — if
the width slides but the colour snaps, that pins which helper is actually live in
production rather than only in tests.

**A spring rather than a duration curve**, because the overshoot is what visibly
distinguishes a spring from a fast fade, where this milestone's own `.default`
(bounce 0) would look like a plain move.

**Off by default, behind a key**, on `CO-Y`'s and the modal scrim's precedent:
that one file carries every past milestone's human-verification criteria, and
always-on motion near M2's contrast judgement would corrupt it.

**A hover-driven fade was considered and REJECTED with a reason** — see `AN-U`.

**IT WAS RUN, on 2026-09-10, and it PASSED — and the first reading was the
opposite.** The project's owner built with `swift build -c release`, launched
`./.build/release/MetalUIDemo` at `b869253`, and pressed **A**. The first report
was *"the width slides but the colour snaps"* — **exactly** the discriminating
outcome this row was constructed to produce, and, if it had held, it would have
meant the **paint-phase helper was not live in production despite 861 tests**.
On a second look it was corrected: *"no it does appear to be working."* **Both
properties animate; the paint-phase helper is live in production.**

**The first-then-corrected reading is kept rather than tidied away, and it is
itself the finding.** A milestone whose whole practice is that unmeasured claims
are the defect does not get to record only the conclusion of its one human
observation. What the ambiguity says about the artefact is that **the fade is
not obvious at a glance** — the two subjects were designed to be separately
reportable and, on first viewing, one of them read as absent. That is
information about the motion, not about the observer.

**Two things the look did NOT establish, and no row may claim them.** The
spring's **overshoot past 320pt** was not separately confirmed, and **no second
press was reported**, so the **reverse direction is unobserved**. The honest
statement is: both properties observed animating on the outbound press;
overshoot and reverse unconfirmed.

**A systematic-debugging pass ran against the first report before the correction
arrived. It found no defect, and the trace is kept as confirmation** — re-checked
line by line for this document rather than transcribed:

- `LayoutPass.transaction` and `PaintPass.transaction` are the **same
  expression**, `frame.transaction` (`Passes.swift:149` and `:457`), so one
  frame's transaction is visible to both phases. There is no path by which layout
  sees a transaction that paint does not.
- There are exactly **four** `pass.fill` sites — `Box.swift:142`,
  `Stack.swift:148`, `ScrollView.swift:441` (the indicator, deliberately
  unwired), `Text.swift:301` — matching Task 5's review's own independent
  enumeration, taken at a different time by a different agent.
- `Column` delegates to `Box`, so the sidebar's background reaches `Box.paint`'s
  effective `??` chain and therefore `animatedColor`.
- The demo declares both subjects off the same `Bool` inside one transaction,
  at `main.swift:485` (`.width`) and `:488` (`.background`).

**What it costs if wrong.** One ~15-line demo change. The alternative was
shipping a milestone whose one human criterion had nothing to exercise — and, as
it turned out, the criterion was worth having: it produced an ambiguous first
reading that no assertion in the suite could have produced, which is the whole
argument for keeping a human instrument at all.

---

# Findings about the record and the practice

## AN-S — the recurring defect was a CLAIM WRITTEN WITHOUT RUNNING THE THING THAT WOULD REFUTE IT, at least SIX times, the last found while writing this document

This is the milestone's real lesson and it is not a code fact. Practices shapes
**14** ("a confident *cannot* that was not measured is the tell") and **15** ("a
fixture in which the code under test cannot be reached") are the names for it.
The occurrences, in order, each as observed:

1. **Task 1's `Animation.default` doc** claimed the value was "SwiftUI's own
   default shape". Measured false — SwiftUI's `.default` is `DefaultAnimation()`
   and compares unequal; the chosen value is exactly SwiftUI's `.smooth`.
2. **Task 3's implementer skipped a mutation with a stated reason**: "dropping
   the whole else-if branch is exactly the unconditional mutation both C2 pins
   already cover, so a third isolated run would have been redundant." **False, and
   measured to be** — it is a materially weaker mutation and neither pin catches
   it. The control that fired was a reviewer executing it (`AN-O`).
3. **Ruling U's reason (c)**, refuted by the very round that shipped it, with the
   file growing 122 lines where 60–80 were predicted removed (`AN-L`).
4. **The 28-field test's doc claimed it could detect a cross-wired field.** It
   could not: every field got the identical 0/100/50, so swapping two baseline
   reads, two declared reads, two key strings or two assignment targets each
   changed nothing (`AN-T`).
5. **`slack: Float = 1e-3` was documented in both source and report as "one ULP
   of `Float`".** Measured, it is **8,388.6 ULPs** (`AN-G`).
6. **`112.5` — found by THIS document's own verification pass, which is the
   sixth occurrence and the reason this ruling is not written in the past
   tense.** `Animation.swift` says *"Measured, by running it: `112.5`"* and
   `AnimationTests.swift` derives the same number by hand twice. Re-run in a
   worktree at `b869253`, the mutant reads **112.0**, twice. The ledger had this
   as a deferred minor about a *report*; the sweep found three further copies,
   one of them in `Sources/` under the word "Measured" — `AN-L`'s exact shape,
   in a different file, one milestone-task later. See the note under the
   mutation table.

**One of these appeared INSIDE the round convened to fix two of the others**,
which is the detail worth keeping: knowing the rule, quoting the rule, and having
a controller rule about the rule are all weaker than running the mutation. And
the pattern reappeared one more time from the *correcting* side — an implementer
refuting a reviewer's suggested fix with "`l` cannot serve at all", which the
re-review measured to be **insufficient rather than wrong** (`l > 0.60` fires on
102/240 samples at bounce 0.6 and 0/240 at bounce 0.0, so the suggestion *would*
have discriminated). That comment now says out loud that it was this branch's own
shape-14 pattern appearing in the paragraph that corrected someone else.

**What it costs if wrong.** Nothing here is a code defect. What it costs is the
record: a false claim at a line has a blast radius, because the next reader cites
it rather than re-running it — which is the lesson the *predecessor* milestone
added to the practices doc, and which this one then demonstrated five times.

---

## AN-T — a mutation that reddens nothing is a FINDING or a BROKEN INSTRUMENT, and this branch produced both

**Telling them apart requires making the mutant show its behaviour**, not
reasoning about it. Both categories occurred here, repeatedly.

**Real gaps, found because a mutation reddened nothing and somebody kept going:**

| mutation | reddened | what it turned out to be |
|---|---|---|
| drop the overshoot clamp | **0 of 848** | real — a bouncy spring peaks at **saturation 1.2846**, handed to the shader (`AN-G`) |
| the whole interruption / re-target branch | **0 of 849** | real — probe shows the post-interrupt midpoint moves **s 0.575 → 0.700** |
| store resolved `Hsla` in the baseline comparison | **0 of 849** | real — a settled element raises liveness for a full duration after a theme swap (`AN-H`) |
| delete 25 of the 28 field assignments | **841 green** | real — only 3 of 28 fields were pinned; positive control reddens **6 tests / 19 issues**, so the instrument worked and the zero was the finding |
| wire `aspectRatio` into `animated()` | **green at 843** | real — the plan's Global Constraint was unguarded (`AN-K`) |
| cross-wire `minSize.width` / `maxSize.width` | **green at 843** | real — the fixture was all-identical and blind to it |
| delete `inFlight[key] = nil` on settle, and delete all three fast-path gates | **0 of 841 each** | real — and the gate one was a **time bomb**: value-equivalent only while the transaction was lexical, and once `AN-B` made it ambient the ungated mutant would put all 28 fields of every element into `inFlight` on every transaction frame, reinstating exactly the allocation `AN-L` removed |
| roll the parked slot back to `nil` rather than to `previouslyParked` | **0 of 860** | real — the mutant reads 200 where the fix reads 150; closed by a third arm with a different-duration second animation, separating **150 / 200 / 112.5** |
| revert `<=` to `<` in `isFinished` | **nothing, 16/16** | real, and the *most* consequential (`AN-I`) |

**Broken instruments that looked EXACTLY like rich findings, at least twice:**

- A coarse mutation produced **413 tests over five targets with 2 `error:`
  lines** — a truncated run, not a 13-test finding.
- An instrumentation attempt failed to **build** and produced a **54-line log
  with 0 issues** — indistinguishable from "reddens nothing" unless the summary
  lines are read.

Both were discarded and re-taken. **The only thing that separates the two
categories is reading the six per-target summary lines and the `error:` count**,
which is CLAUDE.md's "read the printed counts, never the exit status" arriving as
a live result twice on one branch rather than as advice.

**A third instrument failure worth naming**: one reviewer's mutation pass was
contaminated by a `set -e` abort that skipped a restore, so mutations 2–4 ran on
an un-wired `Box`. It **discarded that run and re-took everything** rather than
reporting it — `CO-K`'s rule applied by a reviewer to itself, unprompted.

**What it costs if wrong.** Banking an unexamined zero records a coverage gap
that may not exist; treating a truncated run as a finding records one that
definitely does not. Both put a false number in the record, which is `AN-S`'s
blast radius by another route.

---

## AN-U — "hover and focus fades fall out free" is HALF true: the PATH is free, the TRANSACTION is not

**What was recorded.** `AN-F`'s decomposition — animating the resolved result of
`Box.paint`'s `focusBackground` / `hoverBackground` / `background` chain rather
than the three fields — means a hover or focus change flows through the same
interpolation path as any other colour change. That is true and it is why the
decomposition is right.

**Amended 2026-09-10 (review finding B-9):** the `focusBackground` / `hoverBackground` / `background` chain this passage places in `Box.paint` now lives in `animatedBackground(_:for:pass:)` (`AnimatedColor.swift`), called by `Box.paint`, `Stack.paint` and `Text.paint`. Until then both modifiers compiled on `Stack` and `Text` and painted nothing. The substance is unchanged — one resolved value is animated, not three fields; pinned per site by `everyBackgroundPaintingSiteHonoursHoverAndFocus`.

**What was NOT recorded, and it is the half a caller needs.** **Nothing parks a
transaction around pointer-move handling.** A hover change with no active
transaction takes the snap branch explicitly. So a hover fade needs a framework
change — parking a transaction on the hover-resolution path — not merely a call
site.

**Found by Task 5b rejecting a hover-driven demo affordance with a reason**, and
resolved by its review rather than merely logged: 4b's "come free" describes the
shared code **path**, not a claim that hover alone starts a transaction. Both
statements are true, and the permanent record carried only the first while the
resolution lived in a task report. Corrected in CLAUDE.md by this document's own
task.

**What it costs if wrong.** A reader wraps nothing in a transaction, hovers,
sees a snap, and concludes the colour helper is broken — when what is missing is
a transaction nobody parked.

---

## AN-V — every typecheck-guard count on this branch was taken under a build system that changes whether the guards RUN, and the mechanism is not what it was reported as

**The count is 35**, re-taken for this document by per-file `grep -c canTypecheck`
at `b869253`: `PhaseSeparationTests` 19 + `ErasureCompileGuards` **10** +
`ElementGroupTrapTests` 1 + `UnitSafetyTests` 2 (a bare `grep -c` reads 3; one is
a comment) + `AXNodeTests` 3. That is `34 → 35` for the branch — the guard count's
**seventh** move — and the new one is `pendingTransactionIsNotPublic`, added by
Task 1's first fix round for `Animation.pendingTransaction`'s `public → internal`
narrowing, which a `@testable` test cannot demonstrate (shape 16, `TB-N`).

**Two agents reported that this checkout's default build system silently skips
all 35, and that report was true when taken and is NOT true of the checkout
today. Both halves were measured for this document.**

- **`canTypecheck` looks for `.build/<something>/debug/Modules` holding the
  module.** The default build system (`swiftbuild`) writes modules **flat** into
  `.build/out/Products/Debug/`, reached by the `.build/debug` symlink; there is no
  `Modules` subdirectory anywhere in that layout. With only swiftbuild output
  present, **every guard skips**, the suite total does not move, and the run
  passes.
- **But `--build-system native` writes `.build/arm64-apple-macosx/debug/Modules`,
  and that directory SURVIVES.** `canTypecheck` scans every `.build` entry, so
  once a checkout has *ever* been cross-checked under native, the guards run
  under the **default** build system too — **against those leftover native-built
  modules rather than against what swiftbuild just built.** Measured here at
  `b869253`: with the directory present, two named guards report
  `started` / `passed` under the default build system and the full default run
  skips only the two env-gated tests; with the same directory moved aside, the
  identical command reports both as `skipped` with `canTypecheck`'s own message
  and the total does not move.

**That second half is record §08's own predicted failure — "the guards run
against *stale* modules, which is a worse failure than the skip and a different
bug" — arriving under a configuration §08 did not name.** It also means the
cross-check that established the skip is the thing that stopped it being true.

**Under `--build-system native` the whole suite runs 861 with all 35 guards
live**, 0 `error:`, only the two env-gated tests skipped — and SwiftPM prints
`'--build-system native' has been deprecated and will be removed in a future
release`. **So the workaround every guard count on this branch depends on is
itself going away.** The honest fix has been named since M2: resolve the modules
directory from the **running test binary's** own location rather than from
`#filePath`.

**One more consequence, stated because it changes what a green mutation run
means.** Every mutation on this branch that ran in an isolated `git worktree` ran
where **no** `.build/<triple>/debug/Modules` exists, so **no guard executed in
any of them**. That was judged immaterial for the rounds it was raised in — both
concerned doc prose and test content, nothing touching module boundaries or
access-level narrowing — but it is a standing property of the practice rather
than a one-off.

**What it costs if wrong.** A guard that skips is a guard that is not there, and
the suite total is identical either way — which is exactly the signal shape 11's
count heuristic cannot catch, and the reason all three CI items exist.

---

## AN-W — what this milestone did not measure, stated so nobody cites it as though it had

- **The spring's OVERSHOOT, and the REVERSE direction.** The human look (`AN-R`)
  confirmed that both the width and the colour animate on the outbound press.
  It did **not** separately confirm the overshoot past 320pt that distinguishes
  a spring from a fast fade, and no second press was reported, so the inbound
  direction is unobserved. Whether the motion looks right *in general* remains a
  perceptual judgement no assertion reaches.
- **Whether `targetTimestamp` removes the one-frame lag on real hardware.** Every
  test drives a synthetic clock (`AN-N`).
- **Multi-window behaviour** (`AN-D`). Nothing constructs two live windows that
  both build; the narrowing is argued from the absence of a window registry, not
  observed.
- **Nesting.** `withAnimation(fast) { withAnimation(slow) { a = 1 }; b = 2 }`
  animates both with `slow`. Reasoned from one-transaction-per-build, stated at
  the line, **exercised by nothing in the suite**.
- **Which curve wins when two transactions land in one frame interval and the
  second's writes are unobserved** (`AN-C`'s residual). Unpinned.
- **Whether SwiftUI and CoreAnimation still behave as `AN-G` measured.** Both
  probes are throwaway and deliberately uncommitted, so nothing in the suite
  re-checks them.
- **The five `.auto`-defaulting fields' first transition** (`AN-J`) is stated at
  the line and in CLAUDE.md; no test asserts the snap.

---

# The mutation table, as actually measured

**Re-taken as a whole at each round rather than patched at the flagged row**,
which is practices mechanism 3 — and on this branch it earned its keep twice.
Where a figure moved between rounds the table says which, and where an
*attribution* was wrong while the count was right it says that too.

## Layout-side helper and curves

| # | mutation | result as observed |
|---|---|---|
| 1 | delete the velocity term from the spring's `isFinished` | **0 issues** against the original two-sample fixture — a fixture defect, caught by the implementer; **1 issue** once a mid-flight sample (t = 0.22, position ~99.94, velocity ~240) was added; **20** after fix round 1, **21** after fix round 2 |
| 2 | `easeInOut` → `.linear`; `timingCurve` → `.linear` ignoring all four control points; duration-curve velocity → always 0 | all three **green** — three regions with zero coverage. Instrument proven first: `easeIn ≡ easeOut` gives **1**, removing the `.linear` fast path gives **3** |
| 3 | `timingCurve` → `.linear`, re-taken after the ease refactor | **4 issues across 3 tests** (not 1) — the eases now route through `timingCurve`, so the x-clamp is universal. Self-reported as a deviation from the review's framing, then confirmed |
| 4 | `<=` → `<` in `isFinished` | **0**, then **1 issue** on `aSpringAlreadyAtRestIsFinishedImmediately` once the at-rest case was pinned (`AN-I`) |
| 5 | weaken the finiteness precondition to `x1.isFinite && duration.isFinite` | **3 issues**, all on `timingCurveTrapsOnANonFiniteArgument`'s `y1`/`x2`/`y2` sub-cases |
| 6 | rename `"$anim"` to `"$focus"` | **0 of 837**, then **1 issue** on the mutual-distinctness test once it asserted a mid-flight value (`AN-P`) |
| 7 | delete the `if dirty` guard (unconditional `withState`) | **0 of 837**, then **9 issues** on `aSettledFieldStopsIncrementingTheWriteCount` |
| 8 | `withState` → `write` | **20 issues on exactly one test**, nothing else |
| 9 | remove only `mark` | **0 of 839**, then **3 issues** on the self-discovering ballast test (`AN-O`) |

## Wiring the four registering sites

| # | mutation | result as observed |
|---|---|---|
| 10 | all four `Sources/` edits stashed (red-on-arrival) | **6 issues**, one per sub-assertion; green one site at a time, **6 → 4 → 2 → 1 → 0** |
| 11 | un-wire each of the four sites in turn | each reddens **only its own sub-case**: **2 / 2 / 1 / 1** |
| 12 | un-wire `Box` alone | **13 pre-existing tests** across `IdentityTests`, `ElementGroupTrapTests` and `MeasurePerformanceTests`; all 13 updated with measured counts, cold-frame formula `n + 2` → **`2n + 6`** (20,006 at n = 10,000) |
| 13 | discard the `Decoration` half: `(style, _) = animated(...)` at both sites | **0 of 840**, then **4 issues** in one test (both `Box` and both `Stack` sub-cases) |
| 14 | delete `inFlight[key] = nil` on settle | **0 of 841** — real gap (`AN-T`) |
| 15 | delete all three fast-path gates | **0 of 841** — real gap, and a time bomb (`AN-T`) |
| 16 | delete 25 of the 28 field assignments | **841 green**; positive control **6 tests / 19 issues** |
| 17 | cross-wire `minSize.width` / `maxSize.width` | **green at 843**; after the per-field-distinct fixture, **2 issues in 1 test** naming `minSize.width` (expected 56, got 58) and `maxSize.width` (expected 58, got 56) |
| 18 | wire `aspectRatio` into `animated()` | **green at 843**; after the fixture change, **1 issue** reading `unexpected ["aspectRatio"]` |
| 19 | delete the three fast-path gates (re-taken at the new fixture) | **3 issues / 1 test** — count reproduces, **attribution corrected**: the three are `atStart`, `atMid` (checkpoint 2) and checkpoint 4; **checkpoint 3 never reddens** though the row had credited it. Wrong when written, not made wrong by the fixture change |

## Paint-side colour helper

| # | mutation | result as observed |
|---|---|---|
| 20 | interpolate in HSL instead of RGB | **23 issues across five tests** |
| 21 | resolve the endpoints once and store them | split per endpoint: test 4's `to` arm **4**, its `from` arm **3**, nothing else — the phase choice is pinned (`AN-F`) |
| 22 | mis-key the animation while the fill keeps the effective token | reddens **only** test 3 in 849 — which is what shows test 3 earns its place beyond the existing hover/focus tests |
| 23 | drop the overshoot clamp | **0 of 848**, then **42 issues** in that test alone once the clamp test existed; the vacuity guard is live (a `bounce: 0.0` fixture makes it fire, **1 issue**) |
| 24 | `from: .fixed(current.value)` → `running.from`, and `velocity: current.velocity` → `.zero` | **0 of 849**, then **6 issues** in the new test alone; split for a differential — `from` half alone **6**, `velocity: .zero` alone **2**, no-transaction snap alone **7** |
| 25 | store resolved `Hsla` in the baseline comparison | **0 of 849**, then **2 issues** in `aThemeSwapAloneNeverStartsAFadeOnASettledElement` alone |
| 26 | freeze `to` on the interrupt path only | **3 issues**, the new test alone; the pre-existing theme test cannot see it because it never interrupts |
| 27 | store a token at the interrupt site | **12 issues**, **6 in each** interruption test — reported unprompted as the honest overlap: the new test's marginal coverage is the `to`-freeze case, not the `from` half |

**`112.0`, not `112.5` — and three live sites still say `112.5`. This is
`AN-S`'s defect for a SIXTH time and it is recorded rather than quietly
substituted.** The third arm's "the no-op one won" outcome is stated as **112.5**
in `Sources/MetalUI/Animation.swift` (*"Measured, by running it: `112.5`"*) and
twice in `AnimationTests.swift` — once in the comment deriving it by hand
(*"0.5 s of `linear(duration: 4)` over the same 100 → 200 would read 112.5"*) and
once inside the assertion's own failure message. **Run, in an isolated worktree
at `b869253`, the mutant reads `Optional(112.0)` — twice, identically.** The
hand arithmetic that produced 112.5 is what is wrong; the assertion itself is
`== 150` and is unaffected, so this is a false number at a line rather than a
behavioural defect, which is exactly why nothing reddened for it. **The
mechanism producing 112.0 rather than 112.5 was not chased** — this document
measured the value, not the cause. The ledger carried this as a deferred minor
scoped to *the round-2 report*; the sweep for this document found it had been
copied into `Sources/` and into the test twice as well, which is practices
mechanism 1's "correct where it was **copied to**". Fixing those three lines is a
code change and therefore belongs to the whole-branch review, not to the record
task.

**The velocity half of mutation 24 needed a SPRING interrupt to be visible at
all**, since `Animation.value`'s `.duration` arm calls
`durationValue(curve:seconds:elapsed:from:to:)`, which takes no `initialVelocity`
parameter — verified at the source by the re-review. A linear-only fixture would
have been **structurally blind to half the reviewer's own mutation**.

## The hand-off and the idle guard

| # | mutation | result as observed |
|---|---|---|
| 28 | restore the pre-fix `defer` (park nothing beyond the body) | reddens `aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd` alone (`AN-B`) |
| 29 | park unconditionally | **4 issues**, that test alone |
| 30 | never park / freeze the counter | **20 issues across six tests** each, byte-identical breakdowns |
| 31 | roll back to `nil` instead of to `previouslyParked` | **0 of 860**, then **1 issue** that test alone once a three-way discriminator existed — three separable outcomes, **150 / 200 / 112.0** (see the note below the table) |
| 32 | restore the counter-only rule; "pending always false"; "registration removed" | **3 issues**, that test alone, for all three |
| 33 | drop `\|\| previouslyParked != nil` | **1 issue**, arm 3, **got 112.0** — re-run twice for this document in an isolated worktree at `b869253`, identical both times |
| 34 | put `\|\| hasActiveAnimations` back into the predicate | **1 issue**, arm 4, **got 100.0** |
| 35 | cut `Window.swift`'s `hasActiveAnimations = frame.hasActiveAnimations` (**7W**) | **21 issues** |
| 36 | empty `Frame.noteActiveAnimation()` (**7F**) | **24 issues** — the difference from 7W is exactly the three assertions reading `Frame.hasActiveAnimations` directly |
| 37 | silence the paint half of the liveness signal | reddens; is what forced the extra `x`-drive-loop pin (`AN-M`) |
| 38 | un-wire `Stack.paint` / `Text.paint` colour | each reddens **only its own arm** of `everyBackgroundPaintingSiteAnimatesItsColour` |

**Instrumentation, not mutation, settled one question the mutations could not**:
instrumenting the two `defer` branches across the whole suite recorded **44
invocations, 37 rollbacks, 7 kept parks**, and the 7 correlate to exactly the six
window-driven tests — so **every** direct-helper site parks nothing, which is
stronger than the "13+" the report claimed. No assertion moved: the test-file
hunks contain no `-` lines.

---

# Carried forward — what the next milestone must not get wrong

- **`AN-B` is the sentence to carry.** Two slots, two lifetimes. A change to
  either that keeps the direct-helper tests green proves nothing about
  production; the end-to-end test that drives a real frame build is the one that
  does.
- **`AN-C`'s three clauses each close a measured failure.** Simplifying the
  predicate on a green suite reproduces one of two opposite bugs, both silent.
- **`AN-D` and `AN-U` are the two narrowings a caller will hit first**: a second
  window, and a hover fade. Both are named, neither is guarded.
- **`AN-V` is a live hazard, not history.** Take the guard count under
  `--build-system native` *and* know that the number does not tell you whether
  the guards ran; the deprecation makes fixing `canTypecheck` a dated
  obligation rather than a preference.
- **The one human look RAN and passed, partially** (`AN-R`): both properties
  animate on the outbound press, and the paint-phase helper is confirmed live in
  production. **Overshoot and reverse are unobserved**, so the row is not fully
  closed — and its first reading was the opposite of its second, which is the
  detail to carry rather than the verdict.

---

# Plan task 13 — transactions and animation (2026-09-30)

Rulings `AN-X`…`AN-AG`, taken by the plan-task-13 design session on
`feat/transactions-animation` from `2de0973`. Spec:
`specs/2026-09-30-transactions-animation-design.md`. Evidence:
`docs/probes/swiftui-transactions-animation.swift` (arm ids as the spec's §4;
recorded output in its header). Every SwiftUI claim below names its arm; a
claim with no arm is MetalUI's own choice and says so.

## AN-X — the evidence method, and SwiftUI animates GEOMETRY, not the inputs; MetalUI keeps interpolating inputs (divergence 96)

**Ruling.** Which wrapper animates, and as what, is read from a
`CustomAnimation` recorder: SwiftUI hands each animatable value it animates to
the transaction's animation, so the recorder's lines name the attribute (its
type) and its delta for every arm. It ticks in-process with the screen locked
(control C0), and C1/C2/X1n/T11c record nothing, so a recorded line is the
change's own. The finding that shapes everything else: **SwiftUI lays out once
at the final values and interpolates each view's placed geometry and its render
effects** — a `.frame(width:)` change animates a geometry pair (W1), a child
`Layout` inside it is proposed only the final width (P1), a re-wrapping `Text`
interpolates its geometry and cross-fades its content (P2), and a sibling below
a removed view slides (X00). **MetalUI keeps interpolating the declared input
and re-running layout each frame** (`AN-E`'s model, now extended to proposal
layers): for a wrapper's own rectangle both give the same rectangle at the same
instant; they differ where a child re-lays out or a sibling moves. **Divergence
96, kept, owner none.**

**Why not switch to geometry interpolation.** It would animate *everything* on
the proposal path at once (stacks, grids, leaves) and is SwiftUI's model, but
every hitbox, accessibility frame, clip and scroll region is registered from
the laid-out geometry in prepaint: interpolating placed rectangles means
choosing, per consumer, whether it sees the final or the presented rectangle —
hit testing, accessibility and focus are on this task's must-not-move list,
and SwiftUI's own mid-animation hit behaviour is unmeasured here (no probe arm
reaches it headless). Input interpolation reaches the wrappers the plan names
with no consumer moved.

**Cost if wrong.** A caller animating a container's width watches its wrapped
text reflow every frame where SwiftUI's cross-fades (P2), and siblings of an
inserted/removed element jump where SwiftUI's slide (X00). Visible, bounded,
and the row names it; the switch, if ever made, is its own task.

## AN-Y — `Transaction`, `withTransaction`, `.transaction(_:)`, `.animation(_:value:)`: a transaction STACK in layout and paint, transparent scopes, one root transaction per build (divergence 99)

**Ruling.** (1) `Transaction { animation, disablesAnimations }` and
`withTransaction(_:_:)`; `withAnimation` becomes `withTransaction(Transaction(animation:))`
with SwiftUI's generic, `rethrows`, optional-animation signature — every
existing call compiles. (2) **`AN-C`'s parking predicate is untouched**; the
`disablesAnimations` flag parks beside the animation under the same predicate
and is consumed by the same `takeParkedTransaction`, and
`Animation.parkedTransaction` keeps its type. (3) The frame's transaction
becomes a stack whose root is the parked transaction; `pass.transaction` reads
the top. (4) `.transaction(transform)` and `.animation(anim, value:)` return one
layout- and identity-transparent `TransactionScope<Content>` (`EnvironmentScope`'s
shape), pushing in layout and paint. `.transaction` transforms every frame,
root animation or not (T6, T7, **T7c**); `.animation(_:value:)` overrides the
top's animation when its value changed since last frame and
`disablesAnimations` is false (T1, T2, T4, T4n, T8, T8b), and never touches the
root's explicit animation otherwise (T8c). Its content is what it wraps: a
sibling and a modifier written after it are outside (T3, T3b) — `EV-X`'s
existing rule, unchanged. (5) Its previous value lives in the `AnimationStore`
(`AN-AB`), keyed by its position and the stack depth; a first sighting stores
and does not animate.

**One root transaction per build stays.** T9 (`withAnimation(A) {
withAnimation(B) { a }; b }` → `a` with B, `b` with A) and T10 (two calls in one
interval → each its own) measure `AN-W`'s two unmeasured items for the first
time: SwiftUI attributes each write to its own call. MetalUI cannot — a frame
rebuilds the whole tree from the model, and nothing records which write moved
which field — so it animates both with the one parked curve (`AN-C`'s
residual). **Divergence 99, kept, owner none**; `.animation(_:value:)` is the
per-value remedy and matches SwiftUI.

**Why transparent, not an identity level.** SwiftUI's modifiers carry no
identity, and a transaction scope is added and removed around content that
holds state; an identity level would reset that state on every toggle of the
modifier (`MC-C`'s cost), for no benefit the store key does not already give.

**Cost if wrong.** A scope that failed to pop would animate its siblings (1.4
pins it); a paint phase that skipped the push would fade a colour on a
different curve from the width it moves with (1.8).

## AN-Z — `Binding.animation`/`.transaction` apply to a write whose source is `@State`, and a `Binding(get:set:)` ignores them

**Ruling.** `Binding.transaction` (get/set), `animation(_:)` and
`transaction(_:)`, SwiftUI's surface. A write through a binding whose source is
`State.projectedValue` — and every binding derived from one by dynamic member
or the optional initialisers — runs inside `withTransaction` when its
transaction carries an animation. **A `Binding(get:set:)` ignores its
transaction**: SwiftUI animates a write through `$state.animation(A)` and
`$state.transaction(…)` (T11s, T12s) and snaps the same write through a closure
binding over an observable model (T11), with a plain `$state` write the control
(T11c). Implemented by a source flag the derived bindings inherit, not by
wrapping every setter (which would animate T11).

**Cost if wrong.** A closure binding that should animate snaps — which is what
SwiftUI does, so the cost is only to a caller expecting otherwise; the reverse
choice would make MetalUI animate where SwiftUI does not.

## AN-AA — the legacy paint-only decoration fields animate: opacity and border widths in the layout helper, border colour in paint on an EIGHTH reserved slot; `clipsContent` snaps

> **Amended by `AN-AH` item 3**: the border colour's track lives in the
> `AnimationStore`, not on an eighth `StateTable` slot; the reserved names
> stay seven and `theSevenRetentionSlotsAreMutuallyDistinct` is untouched.
> The text below is the design session's, kept as written.

**Ruling.** Outer-modifiers' deferral closes. (1) **`Decoration.opacity` and the
widths of `border`/`hoverBorder`/`focusBorder` interpolate in
`animated(_:_:for:pass:)`**, from the `$anim` baseline that already stores the
whole `Decoration` — the `cornerRadius` precedent; no new entry. (2) **The
resolved border COLOUR interpolates in paint** on a new retention slot,
**`$anim-border`**, a line-for-line mirror of `$anim-color` (minted only when a
border resolves, tokens stored and re-resolved per frame, the pointer/focus
winner resolved first, interrupt from the current colour and velocity). The
reserved names become **eight**: `theSevenRetentionSlotsAreMutuallyDistinct`
is renamed `theEightRetentionSlotsAreMutuallyDistinct` with the new arm.
(3) **`clipsContent` snaps**: a `Bool` has no midpoint, and SwiftUI's only
animation of an added clip is the default cross-fade of a structure change
(W10), which is divergence 98's, not a clip value.
`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate` is renamed
`thePaintOnlyDecorationFieldsAnimateAndClipSnaps` and its answer flipped, its
background control kept.

**The phase rule, stated so it holds.** "Paint-only values animate in paint"
is not what `AN-F` established: it established that a value needing the
**theme** or the **pointer/focus state** is interpolated in paint, where both
exist. A number needing neither (a radius, an opacity, a width) is interpolated
where it is already stored — the layout helper — and read in paint, off the
same frame timestamp, so its value at every frame is the one SwiftUI's
render-effect animation shows (W3, W5). The plan's "retain the existing
distinction between layout and paint animation" is this rule, kept.

**Why not store the border colour under `$anim-color`.** The outer-modifiers
doc names the hazard: one baseline under one name would make a border change
retarget the background's fade (2.14 pins its absence).

**Cost if wrong.** `$anim-border` adds one `StateTable` entry per bordered
element — a count some tests pin (lane 2 re-reads each, and a moved literal is
ruled at its line, never silent); an opacity in the layout baseline that paint
failed to read would leave the scope at its declared value (2.13's arm).

## AN-AB — proposal modifier layers animate, and their state lives in a window-owned `AnimationStore`, not in `StateTable`

**Ruling.** Record §10's "task 13: proposal animation" and the
modifier-composition doc's "wrappers joining transactions" close for
`LayoutModifier`: `.frame(width:height:)`, the finite bounds of
`.flexibleFrame`, `.padding`, `.opacity`, `.clip(cornerRadius:)` and the
border's width interpolate in layout (the layer rewrites its own case, which
prepaint and paint read); `.background` and the border's colour interpolate
in paint as tokens (`AN-F`/`AN-H`'s recipe). `nil` ↔ value, finite ↔ infinite,
`fixedSize`, `layoutPriority`, `aspectRatio`, `allowsHitTesting`, alignment and
a `clipShape`'s shape snap. Every in-flight layer notes an active animation.

**Their state is not `StateTable` state.** A window-owned `AnimationStore`
holds it, every entry dropped at the end of a frame that did not touch it. So:
(a) no `StateTable` entry is added — no `TB-AH` threshold, pinned table count
or reserved name moves (the legacy `$anim` mints one per registering element
unconditionally, `AN-O`; minting one per proposal layer would move every
proposal-bearing count); (b) content that leaves and returns starts fresh,
`ID-C`/`DD-C`'s answer, with no reset hook; (c) a `List` row out of its window
drops its entries and returns as a first sighting, which snaps — the answer
proposal content has today. The same store holds `.animation(_:value:)`'s
values (`AN-Y`), the component ops (`AN-AC`) and, through a seam lane 1 stubs,
the transition store (`AN-AE`).

**Why not the geometry model** — `AN-X`.

**Cost if wrong.** A second storage mechanism beside `StateTable`, with a
different retention answer (drop on one unproduced frame, not `TB-AH`'s two
generations above 256): a proposal layer that disappears for one frame and
returns under a transaction snaps where a legacy element would resume. That is
SwiftUI's answer for a removed view, and it is stated at the store.

## AN-AC — B-7 is fixed: a caller's modifier on a `Component` animates, through the store

**Ruling.** `StyledComponent` interpolates each op (`.padding`, `.width`,
`.height`) per member in the `AnimationStore`, keyed by its own id, the member
index and the op index. B-7's doc named two unsound fixes — rewriting the
member's `$anim` baseline with an empty `Decoration`, or leaving an amendment on
the pass for a grandchild — and this is neither: the member's own baseline is
never read or written, and nothing is left on the pass. Arm (c) of
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` changes
its answer by this ruling (snap → animates), cited at the arm. SwiftUI animates
any view's geometry, a custom view's included (W1's shape).

**Cost if wrong.** A member added or removed shifts the next member's key, so
its op animates from the departed member's value — the same shift a positional
`@State` has, and the same remedy (identity). 2.18 pins that two members
animate independently.

## AN-AD — Reduce Motion: a get-only environment value from the platform; property animations unchanged, transitions become a cross-fade

**Ruling.** (1) `EnvironmentValues.accessibilityReduceMotion`,
`public internal(set)` — SwiftUI's key path is get-only (the header's
typecheck), so a scope cannot write it (guard). (2) The source is
`PlatformWindow.accessibilityReduceMotion` plus
`onAccessibilityReduceMotionChange`, **with no default implementation**
(`EV-AB`/`AB-R`'s reason: a conformer that forgets it fails to compile), read
at construction, updated by the callback (which dirties the window), and
stamped over the root environment beside `controlActiveState`. (3) **AppKit**
reads `NSWorkspace.accessibilityDisplayShouldReduceMotion` and re-reads it on
`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` — exactly what
SwiftUI does (R1: a swizzled getter is not re-read on its own; R2: it is after
the notification). (4) **SDL** answers `false` and never fires, documented;
SDL3 has no query, and the per-OS reads are a roadmap item. (5) **What it
changes, measured**: property animations, `withAnimation`,
`.animation(_:value:)` and `.transaction` are unchanged (R3, R4, R6, R7); every
transition except `.identity` becomes an opacity cross-fade on the same
animation (R5, R5r, R5s, R5l, R5o, R5p, R5a, R5c; R10 the control; R5i).

**What was not measured.** The real system toggle: the probe swizzled the
getter in-process rather than write `com.apple.universalaccess` (a protected
user preference). R2's reading shows SwiftUI takes its value from that getter
and that notification, which is what MetalUI's AppKit conformer reads.

**Cost if wrong.** If SwiftUI also reads another source, a MetalUI window
could disagree with a SwiftUI one on a machine where the two sources differ —
no such source is known, and the AppKit test swizzles the same getter.

## AN-AE — the transition surface: supported, unsupported, and how removal is drawn

> **Amended by `AN-AH` items 1, 2, 4 and 6**: `.scale` and
> `.scale(scale:anchor:)` are **supported** (item 2's "the renderer has no
> transform" was refuted); insertion is detected only against a conditional
> evaluated last frame (X17); `TransitionGroup` is identity-**transparent**
> (item 3 below is withdrawn); 3.13's mutation is re-named. The text below
> is the design session's, kept as written.

**Ruling.** (1) **Supported**, each probe-backed: `.identity` (X7),
`.opacity` (X1), `.move(edge:)` by the element's own size (X2, X3, X3t, X3b),
`.slide` (X5), `.offset(x:y:)` (X9), `.push(from:)` (X10),
`.asymmetric(insertion:removal:)` (X6), `.combined(with:)` (X8), for an `if`'s
content, an `if`/`else`/`switch` branch and a `ForEach`/`for` element (X11,
X12). (2) **Unsupported, listed on `AnyTransition`'s doc comment**: `.scale`
and `.scale(scale:anchor:)` (the renderer has no transform; a glyph cannot
scale without a re-rasterized atlas entry), `.blurReplace`,
`.modifier(active:identity:)` and custom transitions, `AnyTransition.animation(_:)`,
`matchedGeometryEffect`, `contentTransition`; a guard pins `.scale`'s absence.
(3) **`TransitionGroup` takes one identity level** (`IdentifiedGroup`'s shape):
it needs a key for its captures, and a transparent key would collide with the
content's own. (4) **Only the outermost group of inserted or removed content
transitions** (X15, X15b). (5) **The transaction is the conditional's** (X13,
X14), recorded when the conditional notes its slot; none → instant (X1n).
(6) **Insertion and removal are the evaluated ones `ID-C`/`DD-C` already
compute** — the "distinction" the binding spec §4.3's correction said exit
transitions lacked now exists: an evaluated removal is `noteAbsent`'s slot, a
loop's dropped tail or name, a departed name; a `List` row leaving its window
is none of these (`TB-AH`) and runs no transition. Removal is read before
paint through a non-mutating `StateTable` query. (7) **Removal draws a ghost**:
the group's last captured primitives, re-emitted at their last place with the
transition applied until the animation ends — no hitbox, focus, accessibility
node or state. **Insertion** paints the live content from the active state to
identity with opacity and a paint-time translation; **hitboxes are never
translated** (MetalUI's choice; SwiftUI's mid-transition hit behaviour is
unmeasured). (8) **No default transition** — SwiftUI cross-fades an
unannotated insertion and removal (X0, W10); MetalUI inserts and removes
instantly. **Divergence 98, kept, owner none**: a default would make every
conditional in every tree capture its primitives every frame for a ghost it
almost never draws.

**Why a primitive ghost, not the retained element.** The removed element value
is gone from the builder's output, its state is reset by `ID-C`/`DD-C`, and
re-running its layout would re-mint that state. Its last painted primitives are
exactly what SwiftUI shows during a removal (the view at its last geometry,
X00), and replaying them touches nothing else.

**Cost if wrong.** A ghost is frozen: it does not follow a scroll that moves
under it, or a theme swap mid-removal. Both are sub-second and stated at the
store. The capture costs one copy of each transitioning group's primitives per
frame (3.16 counts it, and pins zero for a tree without `.transition`).

## AN-AF — every item addressed to plan task 13, disposed

**Ruling.** The spec's §3 table is the disposition, row by row: built
(proposal animation, the paint-only fields, Reduce Motion, the `Binding`
surface, `AN-W`'s nesting and two-call items measured into divergence 99);
re-owned to **plan task 15** with a reason each (Increase Contrast and the
other system accessibility settings, an animated scroll offset — SwiftUI
unmeasured, the isolated-process per-entry memory harness, the guards'
default-build-system hazard); and the seven follow-ups of the animation
milestone (project memory, 2026-09-10) each closed or assigned — the
`try #require`, the registry prune, `112.5` → the measured value with its
mechanism measured (hypothesis: whole-point layout rounding, divergence 77),
mutation 16 re-taken and row 16 corrected, the spec §3 caveat, the
`CLAUDE.md` line already gone with the 2026-09-21 rewrite, and the "also open"
overshoot and reverse closed by the 2026-09-10 scripted measurement (record
§19's row, with its own pre-`f1944f8` caveat).

**Cost if wrong.** An item missed by the grep stays silently owned by a task
that has closed. The grep and its date are in the spec, so a later reader can
re-run it.

## AN-AG — three lanes in order, the demo unchanged, and when task 13 is ticked

**Ruling.** Lane 1 (transactions, the store, Reduce Motion, the platforms),
lane 2 (modifier wrappers at their phase), lane 3 (transitions and the
surface), run in that order on disjoint files, with one deliberate seam: lane
1 creates `TransitionStore.swift` as a stub with the frame's three call sites
and lane 3 owns it thereafter. Lane 1 carries Reduce Motion because the
environment, the platforms and the window stamp share `Window.swift` and
`RenderFrame.swift` with the transaction plumbing; lane 3 reads the value.
**The demo is unchanged**: 0 px against `2de0973` in all fourteen offscreen
images, `Expected.swift` unedited. **Task 13 is ticked by the Record phase
only if all three lanes land** — the wrappers in their phase, the
environment-driven Reduce Motion and the documented transition surface are
the plan text's three clauses, the layout/paint distinction is `AN-AA`'s rule,
and every test drives timestamps; otherwise a dated progress note names what
is open. Human looks (the transitions and Reduce Motion's cross-fade on a real
display) go to record §03 and do not gate the tick: the plan's text asks for
no look, and every behaviour here is pinned headless.

## AN-AH — the critic round: `.scale` supported, first render is not an insertion, the border track in the store, `TransitionGroup` transparent, SwiftUI's conformances, a pin that could not be red

**Taken** by the plan-task-13 critic round, 2026-09-30, on
`feat/transactions-animation` over `e46a21d`. The probe re-ran **byte for
byte**: all 223 recorded lines (`diff` against the header's recording empty,
twice), before the round appended arms X17/X17c at the file's end
(revision 2, 227 lines, two runs `cmp`-identical). Each item amends the spec
in place; `AN-AA` and `AN-AE` carry a pointer here.

1. **`.scale` and `.scale(scale:anchor:)` are supported** (X4, X4a; R5s under
   Reduce Motion). The design omitted them because "the renderer has no
   transform — a glyph cannot be scaled without a re-rasterized atlas entry".
   That was an unmeasured "cannot" (shape 14): `glyph_vertex` in
   `Sources/MetalUIRender/Shaders/shaders.metal` interpolates
   `atlasPosition` from `atlasBounds` independently of the destination
   `bounds`, through a `filter::linear` sampler, so a scaled glyph quad
   resamples its atlas slot; rects and images scale by their `bounds`, radii
   and border widths. The mechanism is a post-transform of the scene range the
   group emitted (entry clip kept, inner clips scaled) — spec §6.5. The task
   text names `.scale`; the plan's "document the supported surface" is better
   served by building it than by listing it with a wrong reason. Lane 3 reads
   `Backends/SDL`'s glyph shader first and stops on a mismatch. The
   unsupported guard (3.19) now pins `.blurReplace`.
2. **Content present in the first render, or under a newly evaluated parent,
   is not an insertion** (probe **X17**: the first render under a `.transaction`
   forcing an animation runs no transition; **X17c** separates — the same tree
   toggled after appearing records opacity +1). The design's "not produced by
   the last completed frame" would have faded in every `.transition`ed
   conditional on a window's first frame under T7c's mechanism, and every one
   in a `List` row scrolled into its window. Insertion now needs the
   conditional to have been evaluated last frame (spec §6.5); pinned by 3.22,
   with every recording copy pinned by 3.23 (a copy of a pinned
   implementation is unpinned).
3. **The legacy border-colour track lives in the `AnimationStore`, not on an
   eighth `StateTable` slot.** The design's `$anim-border` minted a table
   entry per bordered element, which moves `TB-AH`'s eviction point and every
   pinned table count, and renamed `theSevenRetentionSlotsAreMutuallyDistinct`
   — both on this task's must-not-move list — for no behaviour the store
   cannot give; `AN-AB` already rejects `StateTable` for proposal tracks on
   exactly this ground, so the design contradicted itself. Cost, stated: an
   element whose paint is skipped for a frame loses the track (the store's
   one-frame drop), so its next colour change from there snaps where
   `$anim-color` would resume. Test 2.15 becomes
   `theBorderColourTrackMintsNoStateTableEntry`.
4. **`TransitionGroup` is identity-transparent.** `AN-AE` item 3 gave it an
   identity level because "a transparent key would collide with the content's
   own"; that holds only for `StateTable` keys. Its captures live in the
   `AnimationStore` under `.named("$transition")` at its position — the
   keying `.animation(_:value:)` already uses (`AN-Y`) — so no collision, and
   adding `.transition` no longer resets the content's `@State`/focus/`$anim`
   (SwiftUI's modifiers carry no identity, `AN-Y`'s own argument). No id path
   moves; no migration note is owed. 3.20 becomes `aTransitionTakesNoIdentityLevel`,
   with a proposal arm for the typed entry.
5. **SwiftUI's conformances** (typecheck, recorded in the probe header):
   `Transaction` is neither `Equatable` nor `Sendable`; `AnyTransition` is not
   `Sendable`. MetalUI's `Transaction` **drops `Equatable`** (adding it later
   is additive; removing it would break callers — `SA-K`'s asymmetry) and
   **keeps `Sendable`** on both, additive beyond SwiftUI and required for
   Swift 6 `static let`s (`AnyTransition.opacity`) and the value-typed stack.
6. **A pin that could not be red.** 3.13 (divergence 98's pin) named 3.12's
   mutation ("let every group inside inserted content transition"), which
   changes nothing in a tree with no `.transition`. Its mutation is now "give
   an unannotated conditional's content a default `.opacity` transition".
7. **Migration spelling for `PlatformWindow`'s new pair** (`AN-AD`): a
   conformer outside this repository adds `var accessibilityReduceMotion:
   Bool { false }` and `var onAccessibilityReduceMotionChange: ((Bool) ->
   Void)?` — `EV-AB`'s announced-break precedent; the four in-repo conformers
   (`AppKitWindow`, `SDLWindow`, `FakePlatformWindow`,
   `ControlStateCompileGuards`' `Conformer`) are lane 1's, found by grep.

**Considered and rejected** (recorded here under this doc's own prefix rather
than as `LR-` rulings: `LR-` is the engine-replacement doc's):

- *T11 has no separating arm* — rejected: T5 (`withTransaction` around the
  same model write animates) separates it, so a closure binding dropping its
  transaction is measured, not inferred.
- *Switch to geometry interpolation so the proposal path animates wholesale* —
  rejected for `AN-X`'s reason (every hitbox, AX frame, clip and scroll region
  would choose between presented and final geometry; must-not-move).
- *Lane 1 is too large* — kept: its platform half shares `Window.swift` and
  `RenderFrame.swift` with the transaction plumbing, and three lanes is the
  cap; splitting would put two lanes on one file.
- *The `AnimationStore`'s one-frame drop differs from `TB-AH`* — kept, as
  `AN-AB` states: it is SwiftUI's answer for a removed view.
- *`hasActiveAnimations` and `wantsAnotherFrame` both raised* — not found:
  every new in-flight path (layers, ops, insertions, ghosts) notes only
  `noteActiveAnimation()`; no new path requests another frame.

**Cost if wrong.** Item 1 is the largest: if the SDL shader cannot scale a
glyph, `.scale` is macOS-only until it can, and lane 3 stops to rule it.

## AN-AI — lane 1 landed: transactions, the store, Reduce Motion, the platforms; `112.5` reads 112 by edge rounding; `AN-C`'s mutations re-taken

**Taken** by plan task 13's lane 1, 2026-09-30, on `feat/transactions-animation`
(tests `58ff4ff`, implementation `f35ecf3`). Spec §7 lane 1 as written, with
these amendments and measurements; nothing in `AN-Y`, `AN-Z`, `AN-AB`'s store or
`AN-AD` changed.

1. **Built as designed.** `Transaction` (`Sendable`, not `Equatable`),
   `withTransaction`, SwiftUI's generic `withAnimation`, both through one
   `parkTransaction` (AN-C's predicate byte-for-byte, `disablesAnimations`
   parked and rolled back beside the animation); the frame's transaction stack
   (`Frame.transactionTop`, `withTransactionScope`) read by both passes'
   `transaction`; `TransactionScope` (transparent, pushes in layout and paint,
   its typed entry a separate copy); `.animation(_:value:)` keyed
   `.named("$anim-value<depth>")` under `.child(of: parent, at: cursor)` in the
   `AnimationStore`; the store (drops untouched entries at the frame's end;
   **a read marks as a write does**, so an unchanged value survives without a
   rewrite); `TransitionStore`'s stub and the frame's three calls (after
   `computeRootLayout`; after the tree's paint, before `glyphAtlas.endFrame()`;
   before `AnimationStore.endFrame()`); `Binding.transaction`/`animation(_:)`/
   `transaction(_:)` with a source flag (`Binding.stateSource`, used only by
   `State.projectedValue`) that derived bindings inherit and whose setters
   write through the base's raw setter, so the derived binding's own
   transaction is the one applied; `accessibilityReduceMotion`
   (`public internal(set)`), the defaultless pair on AppKit (`NSWorkspace`, its
   display-options notification on `NSWorkspace.shared.notificationCenter`,
   injectable as `workspaceNotificationCenter`) and SDL (`false`), stamped by
   `Window` beside `controlActiveState`, `false` stamped by `renderFrame`.
2. **1.16's R4 arm is a background fade, not an opacity.** A legacy
   `.opacity` snaps until lane 2 (`AN-AA`), so a render-effect animation under
   Reduce Motion is read through the paint helper's colour instead; lane 2's
   2.4/2.13 own opacity itself.
3. **1.19's red is the mutation, not a pre-run.** Every lane 1 test is of new
   API, so the committed tests did not compile before the implementation (the
   record's "does not compile" lines); 1.19's "reads the pruned count" is
   M1.19 — the pre-fix getter put back — which reddens it alone.
4. **A scope that pushes `animation = nil` falls back to the lexical slot.**
   The helpers read `pass.transaction ?? Animation.pendingTransaction`
   (`AnimatedStyle.swift`, `AnimatedColor.swift`, lane 2's files, untouched);
   in a production build the lexical slot is always `nil` (`AN-B`), so T6 holds.
   Only a test that builds a frame INSIDE a `withAnimation` body could see the
   fallback override a scope's `nil`; none does.
5. **`112.5` → 112, measured** (`AN-AF` item 9). Mutation 33 re-run on this tree
   reads **`got Optional(112.0)`**, as the table's row 33 said. The mechanism,
   instrumented at `roundLayout` under mutation 33 (not committed): the
   interpolated width is exactly **112.5** (linear(4) at 0.5 s over 100 → 200),
   the fixture's `Column` centres it at **x = 93.75**, and layout rounds each
   EDGE — 93.75 → 94, 206.25 → 206 — so the scene's width is 112. Divergence
   77's whole-point rounding; the hypothesis held. `Animation.swift`'s comment
   now reads 112.0 with this mechanism; the two test lines are lane 2's.
6. **Lane 1's mutation table** (each on the committed tree, restored from a
   copy, full unfiltered suite, `git status --short` clean after every one;
   1898 tests):

| # | mutation | reddens |
|---|---|---|
| M1.1 | `withTransaction` parks `nil` | `withTransactionAnimatesAChangeAsWithAnimationDoes` (1), `disablesAnimationsSuppressesOnlyTheAnimationModifier` (2), `aBindingAnimationAnimatesAStateWrite` (3) — 6 issues |
| M1.2 | a `nil` animation parks `.default` | `aTransactionWithNoAnimationSnaps` (4), `disablesAnimations…` (1, its T8b arm) |
| M1.3 | always push the modifier's animation | `anAnimationModifierAnimatesOnlyWhenItsValueChanges` (2), `twoAnimationScopesAtOnePositionKeepSeparateValues` (2) |
| M1.4a | never pop the pushed transaction | `anAnimationModifierReachesOnlyItsContent` (4), `anAnimationModifierOverridesTheExplicitTransaction` (1), `aTransactionModifierRewritesItsSubtreesAnimation` (1) |
| M1.4b | skip the typed entry's push | `anAnimationModifierReachesOnlyItsContent` alone (1 — its proposal arm) |
| M1.5 | keep the explicit animation when the root has one | `anAnimationModifierOverridesTheExplicitTransaction` (2) |
| M1.6a | ignore `disablesAnimations` | `disablesAnimations…` (2: T8, T8b) |
| M1.6b | `disablesAnimations` also clears the explicit animation (both passes) | `disablesAnimations…` (2: T8, T8c) |
| M1.7 | transform only when the root has an animation | `aTransactionModifierRewritesItsSubtreesAnimation` (1: T7c) |
| M1.8 | skip the push in `paintGroup` | `theAnimationModifierAppliesInPaintAsInLayout` (1: the colour), `anAnimationModifierReachesOnlyItsContent` (2: its paint readings) |
| M1.9 | `animation(_:)` returns `self` | `aBindingAnimationAnimatesAStateWrite` (3), `aClosureBindingIgnoresItsTransaction` (1: the carried-transaction check) |
| M1.10 | apply the transaction to every binding | `aClosureBindingIgnoresItsTransaction` (2) |
| M1.11 | drop the depth from the store key | `twoAnimationScopesAtOnePositionKeepSeparateValues` (2) |
| M1.12 | store the value in `StateTable` | `anAnimationScopeStoresNoStateTableEntry` (2) |
| M1.13a | omit the window's stamp | `theWindowStampsReduceMotionFromItsPlatformWindow` (2), `propertyAnimationsRunUnchangedUnderReduceMotion` (1: its set-up `#require`) |
| M1.13b | do not wire the callback | `theWindowStampsReduceMotionFromItsPlatformWindow` (3) |
| M1.16 | snap both helpers under Reduce Motion | `propertyAnimationsRunUnchangedUnderReduceMotion` (3) |
| M1.17 | observe `NSWorkspace.didWakeNotification` instead | `theAppKitWindowReadsReduceMotionFromNSWorkspace` (5) |
| M1.18 | SDL answers `true` (`Backends/SDL`, 22 + 33) | `anSDLWindowReportsNoReduceMotion` (2) |
| M1.19 | the prune back in `aFrameBuildIsPending` | `aFrameBuildIsPendingDoesNotPruneTheRegistry` (1) |
| MG1.14 | the setter `public` | `aScopeCannotWriteReduceMotion` alone |
| MG1.15 | a protocol-extension default for the pair | `aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile` alone |

7. **`AN-C`'s mutations 28–34 re-run** (the must-not-move check). The three
   that name a figure reproduce it exactly: **31** 1 issue,
   `aTransactionWhoseBodyDirtiesNothing…` alone, got 200.0; **33** 1 issue, arm
   3, got 112.0; **34** 1 issue, arm 4, got 100.0; **32** 3 issues,
   `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`
   alone. **28, 29 and 30 redden MORE than the table says, and that is the
   suite's growth, not a regression**: the table was taken at `b869253`, when
   six window-driven tests existed. **28** (always roll back) 76 issues in 22
   tests and **30** (never park) 75 issues in the same 22 — every window-driven
   animation test since added (lowering, toggle, Reduce Motion, this lane's own)
   plus the original six; **29** (park unconditionally) 6 issues:
   `aTransactionWhoseBodyDirtiesNothing…` (5) and
   `withAnimationParksATransactionForTheDurationOfItsBodyOnly` (1), where the
   table read 4 issues in the first alone. The full lists are record §64's.
   Every clause still has a mutation that reddens it.

**Cost if wrong.** Item 4 is the only behaviour stated rather than pinned: a
future production path that builds a frame inside a `withAnimation` body would
let the lexical slot override a scope's `nil`.

