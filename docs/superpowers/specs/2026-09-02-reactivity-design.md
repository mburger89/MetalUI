# Reactivity — `@Observable` Integration, Dirty Tracking and the Idle Pause — Design

**Milestone:** M4, spec 1 of 4.
**Binding authority above this document:** `docs/superpowers/specs/2026-08-24-metalui-design.md`,
§4.4 (*Redraw and scheduling*) and §12 row 4.

M4 is one milestone delivered as four specs in dependency order — reactivity, `Component` +
result builders, animation & easing, then the `ElementGroup` child-id change and the AX platform
bridge. This is the first. It is separable because the other three each consume the dirty-marking
contract this one establishes and none of them change it.

**Exit criterion this spec owns:** M4's *"no frames built and display link paused while idle"*.
It does **not** own M4's other two — "a real small app" and "VoiceOver navigates it" — which
belong to specs 2 and 4.

---

## 1. What is already built, and what the gap actually is

Stating this first because three of M4's row-4 words are already in the tree, and a reader who
assumes otherwise will re-plan work that exists.

**Display-link scheduling exists and pauses.** `Window.setNeedsRedraw()` sets the flag and calls
`platformWindow.setDisplayLinkPaused(false)`; `Window.drawFrameIfNeeded()` calls
`setDisplayLinkPaused(true)` and returns when the window is clean. `AppKitPlatform` drives it
through `NSView.displayLink(target:selector:)`, which is what §4.4 specifies.

**Dirty tracking exists for `@State`.** `StateTable.onWrite` is wired to `setNeedsRedraw()` in
`Window.init` and is the entire production mechanism; input, resize and appearance change each
mark dirty at their own call sites.

**The gap is exactly one thing:** `grep -rn "withObservationTracking" Sources/` returns **nothing**.
No `@Observable` model can dirty a window today. Everything in this spec exists to close that.

**The idle pause itself is already pinned**, which the first draft of this document got wrong —
`FakePlatformWindow.pauseCalls` and `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt` exist and
pass today. §6.1 records that correction and what it means for the plan: this spec inherits its
instrument, and two of its seven assertions are existing coverage rather than new work.

`hasActiveAnimations`, named in §4.4's guard, is **deliberately not introduced here**. See §5.

---

## 2. The measurement this design is sized against

§4.4's pseudocode wraps the frame build in `withObservationTracking` and relies on its one-shot
nature, calling that "normally an annoyance, here ideal, since we re-register every frame."

**Measured, and the second half of that sentence is wrong.** `withObservationTracking` installs an
observer per tracked property per call and removes it only when `onChange` fires. Re-registering
every frame therefore accumulates one observer per *drawn frame* on every property that has not
changed. A standalone probe (`swiftc -O -swift-version 6`, Swift 6.3.3), reading one `@Observable`
property in a loop and then writing it once:

| frames tracked | `onChange` calls for ONE write |
|---|---|
| 1 | 1 |
| 2 | 2 |
| 10 | 10 |
| 100 | 100 |
| 1000 | 1000 |

Linear, with no plateau. **MetalUI's common case is the pathological one**: scrolling a list draws
frames continuously while the document model is static, so the accumulation is bounded only by
frames-drawn-since-that-property-last-changed. A minute of 120 Hz scrolling leaves ~7,200 stale
registrations that all fire on the next write.

**There is no public cancellation API.** `withObservationTracking` returns nothing and exposes no
handle; `ObservationRegistrar`'s install path is not public for arbitrary models.

### The mitigation, measured

A private `@Observable` sentinel, read inside every tracking session and written at the top of each
frame, fires — and therefore *removes* — every previously armed session. Same probe shape, sentinel
added:

| frames tracked | flush callbacks | `onChange` calls for ONE real write |
|---|---|---|
| 1 | 0 | 1 |
| 10 | 9 | 1 |
| 1000 | 999 | 1 |
| 10000 | 9999 | 1 |

**Constant, at every frame count.** Exactly one session is outstanding at any moment; each frame
pays exactly one flush callback, which is O(1) amortized.

Both probes were throwaway and are not committed, on the footing this repo already uses for oracle
probes: a committed version would pin the standard library's behaviour rather than this
framework's. What is committed is the *consequence* — §6's accumulation-bound assertion, which
fails if the sentinel is removed.

---

## 3. The tracked region

Wrap the whole `renderRoot(frame)` call — the content closure plus all three phases — as §4.4's
pseudocode does. Any `@Observable` property read anywhere in a frame build becomes a dependency of
that frame. No opt-in, no annotations, no dependency declarations: this is SwiftUI's semantics and
this project's standing rule takes SwiftUI's answer where it and CSS differ (ruling EP-5).

Tracking `paint` as well as `requestLayout` is deliberate. A model read only during paint — a colour,
a label — is a real dependency, and a narrower region would silently drop it.

### The consequence a windowed `List` produces, recorded rather than discovered

A `List` builds only the rows intersecting the viewport, so an off-screen row's builder never runs
and its model reads are never tracked. **Mutating row 400's datum while row 400 is off-screen marks
nothing dirty.**

That is correct — there is nothing on screen to redraw, and scrolling to the row rebuilds it and
re-reads the model — but it is the same "not produced ⇒ not seen" mechanism that produced
divergences 12 and 17, arriving in a third place. It is recorded at `List`'s own type doc and in
this section so that a reader who finds it has found a documented property rather than a bug.

**Not a divergence**, because no oracle disagrees: SwiftUI's `List` behaves the same way for the
same reason.

---

## 4. The mechanism

### 4.1 Frame-loop order

`Window.drawFrameIfNeeded()` becomes, with the existing early-out and existing `needsRedraw` clear
in place:

```swift
guard needsRedraw else {
    platformWindow.setDisplayLinkPaused(true)
    pausesEntered += 1
    return
}

isFlushing = true
redrawSentinel.tick &+= 1     // fires, and thereby removes, every armed session
isFlushing = false

needsRedraw = false           // absorbs any dirty the flush produced
stateTable.clearDirty()

withObservationTracking {
    renderRoot(frame)         // reads redrawSentinel.tick, then the app's model
} onChange: { [weak self] in
    self?.markDirtyFromObservation()
}
```

Three orderings are load-bearing and each is stated with what breaks if it moves:

- **The flush is inside the dirty branch, after the guard.** A clean, paused window must keep its
  one armed session — that session is what wakes it. Flushing before the guard would disarm the
  window and it would never redraw again.
- **The flush precedes `needsRedraw = false`.** Any dirty the flush produces is absorbed by the
  clear on the next line. Moving the clear above the flush leaves the window permanently dirty.
- **The sentinel is read inside the tracked closure.** That is what arms the *next* flush. A frame
  that does not read it cannot be flushed and rejoins the accumulating case.

`&+=` rather than `+=`: the tick is a liveness token, never a quantity, and a window running for
weeks must not trap on overflow.

### 4.2 The dirty callback

```swift
private func markDirtyFromObservation() {
    guard !isFlushing else { return }
    if Thread.isMainThread {
        MainActor.assumeIsolated { setNeedsRedraw() }
    } else {
        Task { @MainActor [weak self] in self?.setNeedsRedraw() }
    }
}
```

**The `isFlushing` guard is required for correctness, not tidiness, and this is the sharpest thing
in the spec.** `onChange` fires on the mutating thread. The flush runs on the main thread, so it
would take the synchronous branch and its `setNeedsRedraw()` would land *before* the clear on the
next line — harmless. But that safety would rest on thread affinity rather than on anything stated,
and **under the always-hop alternative it fails outright**: a `Task { @MainActor }` callback lands
*after* `needsRedraw = false`, re-dirtying the window on every frame forever. The idle exit
criterion would be destroyed by the very mitigation that fixes the accumulation. The guard makes
the correctness independent of which branch fires.

**The two hop branches are separately observable, which is the requirement.** A main-thread
mutation sets `needsRedraw` synchronously — assertable immediately after the write, with no
`await`. A background mutation does not — assertable as still-false immediately, and true after a
yield. A branch that cannot be reddened by mutating it is not pinned; both can.

> **Corrected 2026-09-02 during execution (rulings `RX-H` and `RX-I`;
> `docs/superpowers/2026-09-02-reactivity-decisions.md`). The always-hop argument above is
> CONFIRMED; two things stated around it are wrong and are corrected in place rather than
> rewritten.**
>
> **1. The example derived from the always-hop argument named the wrong test — this branch's THIRD
> wrong prediction about which test catches what**, after §6.1's original "nothing observes
> `setDisplayLinkPaused`" and §6.2 assertion 4's "deleting the guard reddens assertion 1" (both
> already corrected in place in their own sections). The plan derived from this section
> (`docs/superpowers/plans/2026-09-02-reactivity.md`, Task 4 step 3) predicted that collapsing both
> branches to the hop alone would fail "the idle tests … including the pre-existing
> `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`". **Measured: that mutation failed SIX tests,
> and that one stayed GREEN.** It is structurally blind to the mutation rather than insensitive to
> the hazard — it draws only two frames, frame 1 has no armed session to flush, and frame 2 returns
> at the `guard needsRedraw` before reaching the flush, so it never triggers a flush at all; and it
> dirties via a direct `setNeedsRedraw()`, never through `@Observable`, so it is not on
> `markDirtyFromObservation`'s path in either direction. Verified independently twice, by the
> implementer and then by the reviewer against `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`
> (`FrameLoopTests.swift`) and `Window.drawFrameIfNeeded`'s idle guard and sentinel flush. **The test that DOES mirror this hazard is
> `anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame`** (`ObservationTests.swift`) — it
> wakes a genuinely paused window through an `@Observable` write, draws exactly one frame, and
> confirms the window idles again with `pausesEntered` advancing by exactly one. It is among the six
> that failed. **Cite that one, not the pre-existing idle test.** The general claim is untouched.
>
> **2. "A background mutation … assertable as still-false immediately" is FALSE, and asserting it
> was pinning the scheduler rather than the code.** Measured: the off-thread branch *is* taken
> (`Thread.isMainThread == false`, instrumented, 5/5 deterministic) and the "still clean" assertion
> failed 5/5 anyway. `await done.value` is itself a suspension point on the main actor — it hands
> the thread back to the scheduler, which is free to run the hop's already-enqueued `Task` before
> this function's continuation resumes. **There is no difference in kind between that suspension and
> an explicit `await Task.yield()`.** The branch's two genuinely observable guarantees are that it
> **does not trap** and that it **does eventually dirty** after a yield, and the first cannot be an
> `#expect`: collapsing to a bare `MainActor.assumeIsolated` crashes the suite with **SIGTRAP,
> signal 5, and no summary line**, reproduced deterministically in the full suite and in isolation —
> CLAUDE.md's taxonomy shape 13 as a live result. That crash, not a red assertion, is the evidence,
> which is why it is carried in the test's doc comment as prose.

The synchronous branch is the overwhelmingly common one (the demo, every test, any main-actor
model) and costs zero added latency. The hop branch cannot crash, which is why it is the fallback
rather than a bare `assumeIsolated` — this repo already carries one live `assumeIsolated` release
trap in `Text.requestLayout`, recorded in CLAUDE.md, and does not want a second.

### 4.3 The two counters, declared once

`Window` gains two `public private(set)` counters beside the existing `framesDrawn`:

- **`pausesEntered`** — incremented at the one site that calls `setDisplayLinkPaused(true)`.
- **`observationDirtyings`** — incremented in `markDirtyFromObservation()` *after* the `isFlushing`
  guard, so a flush is not counted. This is the observable §6.2 assertion 3 reads, and it is the
  reason that assertion can distinguish "one dirty-marking per write" from "N of them" at all —
  `needsRedraw` is a `Bool` and cannot.

They are read-only, are test and debug observability rather than API, and are deleted in the same
change that lands a real profiling story. Recorded here so a reader does not add a third.

### 4.4 What `@State` does, unchanged

`@State` keeps its own path: element-local storage, `StateTable.onWrite` → `setNeedsRedraw()`. The
observation path is a **second, independent** dirty source, not a replacement. They compose without
interacting: `StateTable` holds no `@Observable` properties, so a `@State` write registers nothing
with the observation machinery, and an observation change touches no `StateTable` entry.

`StateTable.isDirty` keeps its existing status as inert test observability and gains no reader here.

---

## 5. `hasActiveAnimations` is deliberately not introduced

§4.4's guard reads `needsRedraw || hasActiveAnimations` and its pause condition reads
`needsRedraw == false && !hasActiveAnimations`. This spec implements **only the `needsRedraw`
half** and does not declare `hasActiveAnimations` at all.

Adding it now means shipping a stored property that is always `false`, has no writer, and changes
no behaviour — which is precisely the failure mode CLAUDE.md's *Declared but inert* table exists to
prevent, and which that table records as taxonomy shape 4: silence at a declaration reads as
"implemented". A caller reading `hasActiveAnimations` in the public surface would reasonably
conclude animations are supported.

Spec 3 (animation & easing) introduces the property, the registration site in `prepaint`, the
timebase from the display link's target presentation timestamp, and widens both conditions **in one
change**. Until then the guard is `needsRedraw` alone and says so at the call site.

---

## 6. Testing

Every assertion below counts events rather than timing them, per this project's standing rule.

### 6.1 The pause is ALREADY pinned — a correction, kept rather than quietly fixed

The first draft of this section asserted that nothing observes `setDisplayLinkPaused`, and that the
`PlatformWindow` test double would need a recorder. **Both halves are false**, and the claim came
from a `grep` truncated by `head -20` rather than from reading the file — the instrument defect this
project's practices doc names, arriving inside the spec that cites it.

What is actually there: `FakePlatformWindow.pauseCalls` (`Tests/MetalUITests/Fakes.swift:83`)
records every argument in call order, and **nine assertions across four files read it** —
`FrameLoopTests`, `ScrollIndicatorTests` and `StateTests`. In particular
`idleWindowPausesTheDisplayLinkAndDirtyingResumesIt` (`FrameLoopTests.swift:109`) already pins both
directions: an idle tick appends exactly `[true]` and draws no frame, and `setNeedsRedraw()` appends
exactly `[false]`.

**So this spec inherits its instrument rather than building one**, and the consequence is that
§6.2's first two assertions are *existing coverage*, not new work. Stating that plainly matters more
than the paragraph it replaces: a reader who plans work against the original text would write a
recorder that exists and two tests that pass before they are written — and would then have no way to
tell whether their new tests were sensitive to anything, which is exactly the "red on arrival"
discipline this repo requires of a counting assertion.

### 6.2 Assertions

Numbered 1 and 2 exist today and are listed so the boundary is visible; 3 through 7 are this spec's.

1. **(exists)** An idle tick draws no frame and pauses —
   `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`. No change.
2. **(exists)** A dirty-marking resumes the link — same test's second half. What is *new* is that an
   **observable write** must reach it: assertion 5 below covers the path, and this assertion is
   extended with an `@Observable` mutation as its trigger rather than a bare `setNeedsRedraw()`.
3. **The accumulation bound.** A model property is read across N drawn frames and then written
   once; the observation-dirty counter advances by exactly **one**, at N = 1 and at N = 1000.
   *This is the assertion that would rot silently* — removing the sentinel leaves every other test
   in this spec green, because a redundant dirty-marking is behaviourally invisible. It must be
   demonstrated red with the sentinel removed by running that mutation, not by asserting here that
   it is sensitive.
4. **The flush does not dirty — and this assertion was CORRECTED by running its own mutation.**
   The first draft said deleting the `isFlushing` guard must redden assertion 1. **Measured on a
   standalone prototype of this exact shape: it reddens nothing behavioural.** With the guard gone,
   `needsRedraw`, `framesDrawn` and the pause record are byte-identical, because §4.1's ordering
   already absorbs the spurious dirty on the very next line. The guard is observable *only* in
   `observationDirtyings`: 0 across 1000 drawn frames with the guard, **999** without it.

   So the pin is a counter assertion and must be written as one: **a frame that changes no observed
   property reports zero observation-dirtyings**, across N frames. That is semantically meaningful
   in its own right rather than a mutation trap, which is why it is the right shape.

   **The guard is kept despite being behaviourally redundant today**, on §4.2's argument: it makes
   the correctness independent of thread affinity rather than resting on the flush happening to run
   on the main thread. A reader who deletes it as dead code should find this paragraph and the
   counter assertion, not a green suite.
5. **The hop, both branches.** A main-thread mutation leaves `needsRedraw == true` with no `await`.
   A background mutation leaves it `false` at the same point and `true` after a yield.
6. **`@State` and `@Observable` compose.** A frame dirtied by a `@State` write and a frame dirtied
   by a model write each draw exactly one frame; neither suppresses the other.
7. **An off-screen `List` row's model read marks nothing dirty** (§3's recorded consequence),
   asserted as the documented behaviour it is.

### 6.3 What no test here can see

- **Whether the real `CADisplayLink` actually pauses.** Every assertion above is against the test
  double. `AppKitPlatform.setDisplayLinkPaused` sets `displayLink?.isPaused`, and nothing in this
  repo can drive real AppKit display-link scheduling — the same boundary CLAUDE.md already records
  for `NSTrackingArea` and for drawable presentation. §7's instrumented demo run is the instrument
  for this, and it is a printed count rather than a human judgement.
- **Whether an idle window actually permits display downclocking.** A property of the OS
  compositor, outside this process entirely. Not claimed and not measured.
- **Observer accumulation inside the standard library.** Assertion 3 observes this framework's
  dirty-marking, which is a proxy. The direct measurement is §2's probe and it is not committed.

---

## 7. The demo, and the instrumented run

**The demo hook is free — no affordance is added.** `Sources/MetalUIDemo/main.swift:44` declares
`var showModal = false` as a top-level mutable global. It redraws today only because the keymap
action path happens to call `setNeedsRedraw()` afterwards; the variable itself marks nothing.

Moving `showModal` onto a small `@Observable` model proves the integration **by removing an explicit
dirty-marking**: the keymap action mutates the model and nothing else, and the modal still appears.
That is a stronger demonstration than adding a new control would be, and it costs the demo no new
visible element — which matters, because this one file carries every milestone's exit criteria and
CLAUDE.md records that a per-look affordance taxes every future look.

> **Corrected 2026-09-02 during execution (ruling `RX-Q`;
> `docs/superpowers/2026-09-02-reactivity-decisions.md`). Two claims in the paragraph above are
> false — one about what was removed, one about what the modal demonstrates — and the conclusion
> survives both.**
>
> **1. There was no explicit dirty-marking to remove.** The paragraph *above* this one gets it
> right — "the keymap action path happens to call `setNeedsRedraw()`" — and then this one restates
> it as though the call lived in the demo. It did not:
> `git show aab0e6a:Sources/MetalUIDemo/main.swift | grep -n setNeedsRedraw` returns **nothing at
> all**. The redraw came **structurally**, from `Window.swift:464-465`'s `dispatchAction` path,
> which calls `setNeedsRedraw()` unconditionally after any action a keymap dispatches. Verified
> independently by Task 5's implementer and again by its reviewer against the source. **Nothing was
> deleted**, and the same false framing shipped in `main.swift`'s own comment until this correction.
> What the move actually buys is a *second, independent* dirty source for the same state.
>
> **2. "And the modal still appears" discriminates nothing.** Pressing **M** dirties the window
> twice — once through `dispatchAction`, once through observation — so **the modal would still
> appear with observation entirely broken.** Its appearance is therefore not evidence about this
> spec at all. The discriminating observable is `Window.observationDirtyings`, which is exactly why
> §7's instrumented run prints it and why the human-verification entry in `CLAUDE.md` asks for the
> three counts rather than for a look. This is the branch's own rule — *require the arms of a
> comparison to disagree before believing that they agree* — arriving in a demo instead of a
> benchmark.
>
> **What survives.** The choice itself: converting an existing control rather than adding a new one
> costs the demo no new visible element, which is the whole reason it was preferred, and that
> argument does not depend on either false claim.

**The instrumented run.** The demo prints a summary on quit: frames drawn, pauses entered,
observation-dirties. A human runs it, leaves the window untouched for a measured interval, presses
**M** twice, and quits. The expected report is that pauses entered is non-zero and that frames drawn
across the idle interval is small and bounded rather than proportional to the interval — a printed
number, not an impression.

This converts the one thing no test can reach into a measurement. It is not a human *judgement*, and
should not be recorded as one.

---

## 8. Exit criteria

1. `withObservationTracking` wraps the frame build; an `@Observable` mutation marks the window dirty
   and draws exactly one frame.
2. The observer-accumulation bound holds: one dirty-marking per real write, independent of frames
   drawn between.
3. Every assertion in §6.2 passes, with 3 through 7 demonstrated red before their implementation
   lands — 1 and 2 are pre-existing and cannot be, which §6.1 states rather than lets a reader
   assume.
4. `swift test --no-parallel` is green at the milestone's expected count, warning-free, with the
   summary line read rather than the exit status.
5. **No golden moves and none is added.** This spec touches no layout code; a moved golden means
   something reached the engine that should not have.
6. `hasActiveAnimations` does not exist in `Sources/` at this spec's last commit.
7. **A human runs the instrumented demo and reports the printed counts** — closing M4's
   "display link paused while idle" for the question it was written to answer, and closing none of
   the looks CLAUDE.md already lists as permanently open.

---

## 9. Risks recorded up front

| Risk | Standing |
|---|---|
| A later reader plans work against §6.1's original claim | That claim — that the pause recorder had to be built and nothing observed it — was false, and came from a `grep` truncated by `head -20`. The correction is kept in place with its cause named rather than silently replaced |
| The sentinel is removed by a later "simplification" and accumulation returns | §6.2 assertion 3 is the only guard, and it is the one whose failure is behaviourally invisible. It must be demonstrated red by mutation at implementation time, not asserted to be sensitive |
| A future `@Observable` conformance on `Window` itself creates a self-dirtying loop | The frame build reads `Window`'s own properties. Nothing here makes `Window` observable and nothing should; recorded because the loop would present as a window that never idles, which reads as a scheduling bug rather than a conformance one |
| `Thread.isMainThread` is the wrong predicate for main-actor isolation in some future runtime | It is a heuristic for "already on the main actor", not a proof. The `isFlushing` guard is what makes correctness independent of it; the branch itself only affects latency |
| The instrumented demo's counters are read once and then rot | They are debug output, not API. Delete them in the same change that lands a real profiling story, per the rule that governs the declared-but-inert table |
| An observation change arriving during the frame build is lost | ~~It is not: `onChange` sets `needsRedraw` and nothing clears it again before `drawFrameIfNeeded` returns — the same argument `Window.drawFrameIfNeeded`'s existing comment makes for a `@State` write during render. Recorded because the ordering looks unsafe on first reading~~ **THAT DISMISSAL IS WRONG AND THE HAZARD IS REAL — corrected 2026-09-03, ruling `RX-S`.** The struck text is kept visible because this row is what a later reader consults *instead of* re-deriving the answer, which is exactly how it did its damage: the hazard was raised, dismissed with a confident wrong reason, and the question closed — taxonomy shape 14. The reason is wrong at its first step: `onChange` **never fires** for such a change, so there is no `needsRedraw` for the ordering argument to protect. `withObservationTracking` installs its observers **after** the apply closure returns, so the window is unarmed from the sentinel flush to the end of the build. Measured twice: standalone, an in-closure write fires `onChange` **0** times against **1** for the identical write after apply returns; in-tree, a content closure that reads then writes a model property gives `observationDirtyings == 0` and then, across 21 ticks, `needsRedraw == false`, **0** frames drawn, 21 pauses entered, `pauseCalls.last == true` — **the window pauses on the very next tick and renders the pre-write value until some other cause draws a frame.** The `@State` half of the analogy is sound and unaffected; only its extension to `@Observable` was false. Not fixed in code — arming across the build is what the flush ordering exists to prevent — and recorded as a known limitation at `markDirtyFromObservation`. Probably not a divergence by `RX-P`'s test (SwiftUI has the same install-after-body semantics), **derived, not measured against SwiftUI** |
