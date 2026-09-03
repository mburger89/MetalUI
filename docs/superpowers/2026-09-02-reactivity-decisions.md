# Reactivity — decisions taken during execution

Rulings from the milestone that wrapped the frame build in
`withObservationTracking`, so that any `@Observable` property read during a
frame becomes a dependency of that frame with no opt-in; bounded the observer
registrations that follow from doing so with a per-frame sentinel; and moved
the demo's `showModal` onto an `@Observable` model. **M4, spec 1 of 4.**

Prefixed **`RX-`** and **lettered** (`RX-A`, `RX-B`, …) per this repo's
convention — **a bare `RX-3` is a typo, not a citation**, the same note every
other milestone's decisions doc carries.

Read alongside `docs/superpowers/specs/2026-09-02-reactivity-design.md` (§2 has
the accumulation measurement this whole design is sized against, §4 the
mechanism and its three load-bearing orderings, §8 the exit criteria) and
`.superpowers/sdd/2026-09-02-reactivity/progress.md`, the execution ledger these
rulings are drawn from.

## How to read the letters, because they are not all the same kind of thing

**`RX-A` through `RX-J` carry the ledger's own letters `A` through `J`, one for
one, deliberately.** The ledger lettered ten rulings during execution;
renumbering them here would make every citation written during the milestone
ambiguous, which is the hazard `EP-2`/`EP-4` and the tombstones milestone's
`TB-A`…`TB-AD` mapping both exist to prevent. So ledger ruling `H` is `RX-H`
here, and nothing else is.

**`RX-K` through `RX-R` are new, and they are the eight decisions a reader
should start with.** They were never lettered in the ledger because they were
settled in prose — in the spec, in task briefs, in task reports — rather than
adjudicated as controller rulings. They are also the eight this milestone is
actually *about*: what the sentinel is for, what the tracked region is, why a
behaviourally-invisible guard is kept, why one of two hop branches is
load-bearing, what is deliberately absent, what a windowed `List` does with
all of it, why the demo changed the way it did, and what does **not** get an
inert-table row. **Read K–R first, then A–J for the execution findings.**

Not every letter is a mechanism decision. Several are findings about the
*record* — a spec claim that turned out unmeasured, an assertion that turned
out unobservable — and they are kept because this repo's own practices document
is assembled from exactly those.

**Everything numeric below was measured in this tree at commit `9ea6062`
unless the ruling says otherwise, and where a figure came from a standalone
prototype rather than from the suite the ruling says so at the number.** That
distinction is `TB-AA`'s rule and this milestone had to apply it twice — see
`RX-F`. Two further labels appear at their own numbers: a figure **derived**
from a measured relationship rather than observed (`RX-K`'s ~7,200), and a
claim about **SwiftUI** derived from documentation rather than probed (`RX-P`).

**Where the authoritative copy of each in-tree number lives, so a future editor
knows which to update first.** The three mutation figures — **1 vs 200** for the
sentinel, **0 vs 199** for the `isFlushing` guard, and the off-by-one's reason —
now appear in three places apiece: the source doc comments, this document, and
`CLAUDE.md`'s reactivity bullet. **The source is authoritative**, because it is
the copy a mutation is run against and the one `RX-F` exists to keep honest:
`Sources/MetalUI/Window.swift`'s `observationDirtyings` comment for 1-vs-200 and
its `isFlushing` comment for 0-vs-199. Re-measure there, correct there first,
then propagate here and to `CLAUDE.md`. The §2 prototype table in
`Sources/MetalUI/RedrawSentinel.swift` and in the reactivity spec is a
*different* measurement (the standard library's behaviour, not this tree's) and
must not be reconciled with these.

---

# The eight foundational decisions

## RX-K — the sentinel exists because design spec §4.4's "here ideal" is measurably wrong, and the correction lands in the binding-authority spec

**The choice.** A private `@Observable` `RedrawSentinel`
(`Sources/MetalUI/RedrawSentinel.swift`) holding one `Int` `tick`, read inside
every tracking session and written at the top of every drawn frame. It is
`internal`, never `public`: a mechanism, not API.

**What §4.4 says and why it is wrong.**
`docs/superpowers/specs/2026-08-24-metalui-design.md` §4.4 lists three
properties of `withObservationTracking` that "make it fit a full-rebuild
model", the second being that it is *"**one-shot**; normally an annoyance, here
ideal, since we re-register every frame."* Measured on a standalone probe
(`swiftc -O -swift-version 6`, Swift 6.3.3) reading one `@Observable` property
across N frames and then writing it once, the `onChange` count for that single
write is 1 at N = 1, 10 at N = 10, 100 at N = 100 and **1000 at N = 1000** —
linear, with no plateau. Re-registering every frame does not exploit one-shot
semantics; it *accumulates* one observer per drawn frame on every property that
has not changed, and removes them only when a write finally fires them all
together.

**And there is no public cancellation API.** `withObservationTracking` returns
nothing and exposes no handle; `ObservationRegistrar`'s install path is not
public for arbitrary models. So the accumulation cannot be undone directly —
only *fired*.

**MetalUI's common case is the pathological one**, which is what makes this a
design problem rather than a curiosity: scrolling a list draws frames
continuously while the document model is static, so the accumulation is bounded
only by frames-drawn-since-that-property-last-changed. A minute of 120 Hz
scrolling leaves ~7,200 stale registrations that all fire on the next write —
**that figure is DERIVED (60 × 120) from the measured linear relationship above,
not itself measured**, and is stated as an illustration of the bound's shape
rather than as an observation of a running window.

**The mitigation, and its measurement.** With the sentinel read inside every
session and written at the top of each frame, every previously armed session
fires — and is thereby removed — on the next frame. The same probe gives
**1** `onChange` for one write at every N up to 10,000, with N−1 flush
callbacks: exactly one session outstanding at any moment, one flush callback
per frame, O(1) amortized.

**Both probes were throwaway and are deliberately not committed**, on the
footing this repo already uses for oracle probes (divergence 2, divergence 9): a
committed version would pin the *standard library's* behaviour rather than this
framework's. What is committed is the consequence —
`theObserverSetIsBoundedRegardlessOfFramesDrawn` — and its in-tree figures are
in `RX-F`, not the prototype's.

**§4.4 is corrected in place with the original claim visible**, in a `>`-quoted
block matching the one §4.3 already carries, because that document is named
binding authority in `CLAUDE.md`'s "Start here" and a false claim there is worse
than the same claim downstream.

**What it costs if wrong.** If the sentinel is removed by a later
"simplification", the accumulation returns and **nothing behavioural changes** —
a redundant dirty-marking draws no extra frame and moves no rect. The only
guard is a counter assertion, which is `RX-F`'s subject.

---

## RX-L — the tracked region is the WHOLE frame build, all three phases, with no opt-in

**The choice.** `withObservationTracking` wraps the entire `renderRoot(frame)`
call in `Window.drawFrameIfNeeded` — the content closure plus `requestLayout`,
`prepaint` and `paint`. Any `@Observable` property read anywhere in a frame
build is a dependency of that frame. No annotations, no registration, no
dependency declarations.

**Reasoning.** This is SwiftUI's semantics, and this project's standing rule
takes SwiftUI's answer where it and CSS differ (ruling `EP-5`, and the user's
own recorded preference). Tracking `paint` as well as `requestLayout` is the
half a narrower design would drop: a model read only during paint — a colour, a
label — is a real dependency, and a region ending at layout would silently miss
it.

**The framework knows nothing about the model type**, which is the point and is
pinned by construction: `ObservationTests.ProbeModel` is declared in the test
file and no framework type mentions it. Its sibling
`mutatingAnUnreadPropertyDoesNotDirtyTheWindow` is what keeps the positive test
from being explained by "any observable write anywhere dirties the window" —
`model.untouched += 1` leaves `needsRedraw` false and `observationDirtyings` at
0.

**What it costs if wrong.** A narrower region drops paint-only dependencies
silently — a label that never updates, with no error anywhere. A wider one does
not exist: this is already the whole build.

---

## RX-M — the `isFlushing` guard is kept although deleting it changes no behaviour, and the pin is a COUNTER rather than a behavioural assertion

**The choice.** `Window.isFlushing` is set true only for the duration of the
sentinel write, and `markDirtyFromObservation` returns early while it is set.
It stays in the tree despite being behaviourally invisible today.

**What the spec's first draft claimed and what measurement gave instead.**
The reactivity spec's §6.2 assertion 4 originally said deleting the guard must
redden the pre-existing idle test. **It reddens nothing behavioural.** With the
guard gone, `needsRedraw`, `framesDrawn` and the pause record are byte-identical,
because §4.1's ordering already absorbs the spurious dirty on the very next line
(`needsRedraw = false`). The guard is observable *only* in `observationDirtyings`.

**So the pin is written as a counter assertion** —
`aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying`: a frame that
changes no observed property reports zero observation-dirtyings, across 200
frames. **Measured in this tree by Task 3, with the guard deleted: 199, against
0 with it.** Not 200, and the off-by-one is the mechanism rather than noise — a
session is armed only by a preceding `withObservationTracking` call reading
`redrawSentinel.tick`, so frame 1's flush has no prior session to trip and only
frames 2 through 200 fire. Task 3's reviewer derived that 199 independently from
the mechanism before reading the report, which is what makes it a check rather
than a transcription.

**Why keep it.** The flush runs on the main thread, so it takes the synchronous
branch and its `setNeedsRedraw()` lands *before* the clear on the next line —
harmless. But that safety rests on **thread affinity** rather than on anything
stated, and under an always-hop implementation it fails outright: a
`Task { @MainActor }` callback lands *after* `needsRedraw = false`, re-dirtying
the window on every frame forever. The guard makes the correctness independent
of which branch fires.

**What it costs if wrong.** A reader who deletes it as dead code on the evidence
of a green behavioural suite gets a green suite and a latent trap. That is
exactly what the counter assertion is for, and its failure message names
`isFlushing` by name so the red says what is wrong. See `RX-N` for the second,
deliberately redundant mechanism, and `RX-G` for why the redundancy itself
cannot be pinned.

---

## RX-N — the SYNCHRONOUS branch is load-bearing for the idle criterion, and the off-thread branch's guarantee cannot be an `#expect`

**The choice.** `markDirtyFromObservation` is `nonisolated` — forced, not
chosen, because `withObservationTracking`'s `onChange` is `@Sendable` and fires
on the mutating thread — and re-enters the main actor two different ways:

```swift
if Thread.isMainThread { MainActor.assumeIsolated { … } }
else                   { Task { @MainActor [weak self] in … } }
```

**The synchronous branch is not an optimisation.** The per-frame sentinel flush
runs on the main thread and fires this method. Under an always-hop
implementation that callback lands *after* `drawFrameIfNeeded`'s
`needsRedraw = false`, marking the window dirty on every single frame forever —
the display-link pause this milestone exists to deliver, destroyed by the very
mitigation that fixes the accumulation. **Measured by Task 4: collapsing both
branches to the hop alone fails SIX tests.** (`RX-H` records which test the spec
wrongly predicted would be among them.)

**The off-thread branch's guarantee is that it does not TRAP, and that cannot be
written as an assertion.** A bare `MainActor.assumeIsolated` called from a
non-main thread terminates the process. **Measured by Task 4's fix round, and it
is the sharpest result on this branch: collapsing `markDirtyFromObservation` to
the synchronous branch alone does not redden anything — it crashes the suite
with SIGTRAP, signal 5, and no summary line at all**, reproduced
deterministically both in a full unfiltered run and filtered to
`anOffThreadMutationMarksTheWindowDirtyAfterAHop` alone.

That is **CLAUDE.md's taxonomy shape 13 arriving as a live result**: a wrong
implementation truncating the run instead of failing a test. It is also why the
guarantee lives in that test's doc comment as prose rather than as an `#expect`
— *reaching the end of the test* is the evidence, and no assertion can state
"the process did not die".

**`Thread.isMainThread` is a heuristic for "already on the main actor", not a
proof**, and this is stated rather than assumed. The `isFlushing` guard (`RX-M`)
is what makes correctness independent of it; the branch itself only affects
latency.

**What it costs if wrong.** A wrong predicate costs one hop of latency. A
missing off-thread branch costs the process. A missing synchronous branch costs
the milestone's exit criterion.

---

## RX-O — `hasActiveAnimations` is deliberately NOT declared, and the reason is this repo's own inert table

**The choice.** Design spec §4.4's guard reads `needsRedraw || hasActiveAnimations`
and its pause condition reads `needsRedraw == false && !hasActiveAnimations`.
This spec implements **only the `needsRedraw` half** and does not declare
`hasActiveAnimations` at all. Verified at this milestone's last commit:
`grep -rn "hasActiveAnimations" Sources/` returns **0**.

**Reasoning.** Declaring it now ships a stored property that is always `false`,
has no writer and changes no behaviour — precisely the failure mode CLAUDE.md's
*Declared but inert* table exists to prevent, and which the practices doc
records as taxonomy shape 4: **silence at a declaration reads as
"implemented".** A caller finding `hasActiveAnimations` in the public surface
would reasonably conclude animations are supported.

**M4 spec 3 (animation & easing) introduces the property, its registration site
in `prepaint`, the timebase from the display link's target presentation
timestamp, and widens both conditions in ONE change.** A declaration and its
writer landing together is the same rule the inert table states from the other
end ("when you implement one, delete its row").

**What it costs if wrong.** A reader of §4.4 goes looking for a property that
is not there and reads its absence as an oversight — which is why CLAUDE.md
carries a sentence saying it does not exist and why. That note is the cost being
paid deliberately.

---

## RX-P — the windowed-`List` consequence is DOCUMENTED BEHAVIOUR and explicitly not a divergence

**The observable.** A `List` builds only the rows intersecting the viewport, so
an off-screen row's builder never runs and its model reads are never tracked.
**Mutating row 199's datum while row 199 is off-screen marks nothing dirty.**
Pinned by `anOffScreenListRowsModelReadIsNotTracked` (`ObservationTests.swift`).

**Why it is correct.** There is nothing on screen to redraw, and scrolling to
the row rebuilds it and re-reads the model, so it self-heals. The state is not
lost — it lives in the datum, which `List` re-reads every frame.

**Why it is not a divergence.** Every entry in CLAUDE.md's divergence list is
either a disagreement with an oracle, a design choice a CSS or SwiftUI reader
would misfile as a bug, or an accepted limitation with a named blocking
mechanism. **This is none of those: SwiftUI's `List` behaves the same way for
the same reason, so no oracle disagrees.** Recording it as a divergence would
say the framework is out of step with something, and it is not.

**That SwiftUI claim is DERIVED, not measured, and this milestone declined to
measure it — read the label before citing it.** It follows from SwiftUI's
documented laziness (a `List` row's `body` is not evaluated until the row is
realized, so nothing in it can be read, so nothing in it can be tracked), and
**no probe was run against SwiftUI here.** That is a deliberate scope call, on
the same footing as this repo's prototype figures being labelled as prototype
figures (`RX-F`, `TB-AA`): confirming it needs a SwiftUI test harness this
repository does not have and should not grow for one claim, and the alternative
to labelling it was either an unrun assertion or silence.

**Labelling it rather than deleting it is the point.** A derived claim with its
derivation stated is more useful than nothing, and this repo's own precedent —
divergences 2 and 9, both of whose oracle claims were measured through a
throwaway probe before being written — is exactly the standard this one does not
meet, which is why the shortfall is named rather than glossed. **It is also the
one thing that could reopen the question**: if SwiftUI turns out to differ, the
divergence label is still available, nothing here is foreclosed, and the
observable to compare is whether a mutation to an unrealized row's model
schedules an update at all. **Cost if wrong:** a real disagreement with the
framework this project takes its answers from (ruling EP-5) goes unrecorded —
which is taxonomy shape 14, a confident reason closing a question before it is
asked, and is why the reason is now labelled instead of stated flat.

**It is recorded anyway, and the reason is the pattern rather than the
behaviour.** It is the same "not produced ⇒ not seen" mechanism that produced
divergences 12 and 17, arriving in a **third** place. A reader who finds it
should find a documented property, at `List`'s own bullet in CLAUDE.md and in
the spec's §3, rather than a surprise.

**The test carries its own positive control, and that was a review finding
rather than the original design.** `rows[0]` is mutated first, on the same
window and the same fixture, and confirmed to dirty. Without it, a `List` that
stopped tracking row builders *entirely* — memoizing built rows instead of
rebuilding them from `visibleRange` — would pass the off-screen half vacuously.
That row 0 is always inside the built window was derived from
`List.visibleRange`'s source (`rawFirst` is negative at offset 0 and clamped by
`max(0, …)`), not guessed, and the reviewer re-derived it independently.

**What it costs if wrong.** An assertion of absence with no positive control is
taxonomy shape 4 from the test side: it stays green when the mechanism it
observes disappears. Fixed before merge.

---

## RX-Q — the demo moves `showModal` onto a model rather than gaining a new affordance, and the plan's stated reason for it was FALSE

**The choice.** `Sources/MetalUIDemo/main.swift`'s top-level
`var showModal = false` becomes `@Observable final class DemoModel { var showModal = false }`
plus a `let demoModel`. No new visible element is added.

**Reasoning.** This one file carries every milestone's exit criteria, and
CLAUDE.md already records — from the modal-scrim decision — that a per-look
affordance taxes every future look. Converting an existing control demonstrates
the integration at zero cost to every other criterion this demo has to serve.

**The plan's and spec's stated mechanism was wrong, and the correction is
recorded rather than quietly applied.** Both said the keymap action called
`Window.setNeedsRedraw()` explicitly and that moving `showModal` onto a model
would *delete* that call. **There was no such call anywhere in `main.swift`** —
verified at the branch's base commit, where
`git show aab0e6a:Sources/MetalUIDemo/main.swift | grep -n setNeedsRedraw`
returns nothing at all. The redraw came **structurally**, from
`Window.swift:464-465`'s `dispatchAction` path, which calls `setNeedsRedraw()`
after any action a keymap dispatches. Task 5's implementer reported it and Task
5's reviewer verified it independently against the source rather than taking it.

**The demonstration's wording changes, and so does its strength — the second
half is a correction to the first version of this ruling.** The modal now
dirties *through observation* as well as through dispatch, which is a real
second dirty source. It is **not** "an explicit dirty-marking was removed", and
repeating that framing would put a third unmeasured prediction into this
branch's record (see `RX-H` for the second).

**But "and the modal still appears" is NOT a discriminating observable, and
calling the move "a real integration proof" overstated it.** `main.swift`'s
`ToggleModal` case (`case is ToggleModal:` in the demo's `window.onAction`
handler) toggles `demoModel.showModal`, and the `platformWindow.onInput`
closure installed in `Window.init` calls `setNeedsRedraw()` unconditionally
whenever `dispatchAction` returns `true` — i.e. after **any** action a keymap
dispatches. So pressing **M** dirties the window **twice**, and **the modal
would still appear with observation entirely broken.** Its appearance is
evidence about `dispatchAction`, not about this milestone.

**The discriminating observable is `Window.observationDirtyings`**, which is why
the exit summary prints it and why `CLAUDE.md`'s human-verification entry asks
for three counts rather than for a look — that entry already had this right
while this ruling denied it. **This is the branch's own discriminator applied to
a demo instead of a benchmark**: *require the arms of a comparison to disagree
before believing that they agree.* The demo's two arms — observation working and
observation broken — are indistinguishable by eye, and a human reporting "the
modal appeared" has confirmed nothing about reactivity. What the *counter*
separates is a small number (roughly two, for two presses) from zero.

**And what the move genuinely buys is unaffected**: a second, independent dirty
source for the same state, and no new visible element in a file that carries
every milestone's exit criteria. That is the reason it was chosen, and it does
not rest on either corrected claim.

**The instrument that comes with it.** A `Q` binding and an `atexit_b` hook
print `framesDrawn`, `pausesEntered` and `observationDirtyings` on quit. It is
registered once rather than called from `QuitDemo`'s handler and the close
button separately, so both exits print through the identical hook. **`atexit`
handlers run on the thread that calls `exit()`, and both quit paths go through
`NSApplication.shared.terminate(nil)` on the main thread**, which is what makes
the `MainActor.assumeIsolated` inside it safe (ledger ruling J, `RX-J`).

**What it costs if wrong.** The summary would print from a non-main thread and
terminate the process at exit — cosmetic, since the print is the last thing that
happens, but it would be a further instance of the trap CLAUDE.md records for
`Text.requestLayout`. The site is recorded there regardless; see `RX-R`'s
neighbour note and CLAUDE.md's release-trap section, which now names **four**
`assumeIsolated` sites where it named one.

---

## RX-R — `pausesEntered` and `observationDirtyings` get NO inert-table row, and the distinction is what that table is for

**The choice.** `Window` gains two `public private(set)` counters beside the
existing `framesDrawn`. Neither gets a row in CLAUDE.md's *Declared but inert*
table.

**Reasoning, and it is a test rather than a preference.** That table's shape is
"exists, compiles, and does nothing" — a declaration with **no reader at all**.
`StateTable.isDirty` is the closest precedent and it is in the table precisely
because `grep` finds no production read anywhere. These two are the opposite:

| | writer | production reader | test reader |
|---|---|---|---|
| `pausesEntered` | `Window.drawFrameIfNeeded`'s idle guard | `main.swift`'s `printReactivitySummary` | `ObservationTests.swift`, `anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame` |
| `observationDirtyings` | `Window.markDirtyFromObservation`, both branches | `main.swift`'s `printReactivitySummary` | **ten** `#expect`s in `ObservationTests.swift` (`grep -c "#expect(window.observationDirtyings"`) |

**Symbol names, not line numbers, and the reason is this ruling's own
history.** The table cited `main.swift:904` and `:905` and was **correct when
written, at `3881f65`** — then `966cc84`, the very commit that last edited this
document, added a net +10 lines to `main.swift` and did not re-run its own
citations, so both were off by ten before the branch was finished. That is the
hazard CLAUDE.md's `Frame.scrollRegions` row already records twice over and
concludes "No line numbers, on purpose"; applied here after this fix wave found
five stale citations across this file and CLAUDE.md, all from that one commit.

**The sentence that stood here — "Re-verified by grep at this milestone's last
commit rather than carried from the ledger" — was therefore FALSE as written**,
and is corrected rather than deleted because it is the same class of error as
everything else this wave fixed: it was true at the commit the verification was
run against and untrue at the commit that shipped it, and nothing re-ran it.
A verification is dated to the commit it was run at, not to the document that
quotes it. `pausesEntered` was flagged during Task 1+2's review as having a
writer and no reader — **true at that commit** — and Task 3's
`anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame` gave it one
(`pausesEntered == pausesBefore + 1`). Adding a row now would document a gap
that was closed two tasks before this document was written.

**They are debug and test observability, not API**, and are deleted in the same
change that lands a real profiling story — the same rule that governs the inert
table from the other side. Recorded so a reader does not add a third.

**What it costs if wrong.** A row in that table for something with three readers
teaches the table's own criterion wrongly, which is worse than the missing row
would be: the table's value is entirely in a reader trusting that a row means
"nothing reads this".

---

## RX-S — an observation change arriving DURING the frame build is lost, the spec's risk table said the opposite, and the fix is in the record rather than in code

**The correction.** Design spec §9's risk table raised "an observation change
arriving during the frame build is lost" and dismissed it — "**It is not**:
`onChange` sets `needsRedraw` and nothing clears it again before
`drawFrameIfNeeded` returns". That dismissal is wrong at its first step, and
the same false claim had been copied to `Window.drawFrameIfNeeded`'s ordering
comment and to CLAUDE.md's `@State` bullet. All three are corrected.

**The mechanism.** `withObservationTracking` installs its observers **after**
the apply closure returns, not during it. A property written inside the closure
— after being read there — fires **no** `onChange` for that session. So there is
no `needsRedraw` for the ordering argument to protect: the failure mode is a
**lost dirty**, not a swallowed one. The `@State` half of the original argument
is sound and untouched; `onWrite` fires synchronously at the write, which is
precisely what observation does not do.

**Measured twice, and neither number is carried from a report.**

- **Standalone** (`swiftc -swift-version 6`, `import Observation`, three arms).
  A write inside the apply closure: `onChange` fired **0** times. The identical
  write after the closure returned: **1**. And the discriminating third arm — an
  in-closure write *followed by* a post-apply write on the same session — fired
  **1**, which is what proves the session is armed and simply never saw the
  first write. Without that third arm the result is also consistent with "the
  session was never armed at all", which is a different and less useful finding.
- **In-tree**, through a real `Window` and `makeFakeWindow`, with the content
  closure reading `model.n` and then writing it during the build:
  `observationDirtyings == 0` on that frame. Across 21 subsequent ticks:
  `needsRedraw == false`, **0** frames drawn, **21** pauses entered,
  `pauseCalls.last == true`. A post-build write on that same window then
  dirties it normally (`needsRedraw == true`, `observationDirtyings == 1`),
  which is the in-tree twin of the standalone third arm.

**So the symptom is the OPPOSITE of what CLAUDE.md recorded**, and that is the
worse half of this finding. CLAUDE.md's "SECOND door" paragraph said the display
link "never pauses" and folded the `@Observable` case together with the
`@State`-write-from-a-phase hazard as "one hazard with two spellings". They are
opposite failure modes: `@State` from a phase leaves the window permanently
dirty and the link never pauses; `@Observable` from a phase leaves it silently
stale and the link pauses **immediately** — on the very next tick, in the
measurement above. One window never sleeps and the other never wakes, and a
debugger following the old note would look for a spinning window while the real
one is asleep. What genuinely is shared is the **advice**, and only that is now
presented as common: *write from input, never from a phase.*

**The real gap is wider than an author error, and it was documented as
impossible.** The unarmed interval runs from `drawFrameIfNeeded`'s sentinel
flush to the end of the apply closure — essentially the whole frame build. A
**background** write landing in that interval, after the property has been read,
is lost the same way: the window renders stale, goes clean, and pauses. It
self-heals only if some other cause draws another frame. This is on a path the
branch explicitly supports and tests
(`anOffThreadMutationMarksTheWindowDirtyAfterAHop`), so it is a known limitation
of a supported path rather than a hazard confined to misuse.

**Not fixed in code, and the reason is structural rather than effort.** Closing
it means keeping a session armed across the build, which is exactly what the
flush ordering exists to prevent: the flush is what bounds registrations at one
outstanding session, and an always-armed window re-enters the per-frame
accumulation `RedrawSentinel` was built to stop (`RX-K`, and §6.2 assertion 3).
Trading a bounded-registration guarantee for a narrow latency window is the
wrong trade to make inside a fix wave, and it is not a one-line change. It is
therefore stated as a **known limitation** at `markDirtyFromObservation`, which
is where a reader chasing a lost dirty will be looking — **not** as a risk that
was ruled out, which is how it was recorded before.

**Probably not a divergence, and the qualifier is load-bearing.** By `RX-P`'s
own test — a divergence needs an oracle that disagrees — SwiftUI's tracking has
the same install-after-body semantics, so nothing disagrees and this is the
platform's behaviour rather than this framework's. **That claim is DERIVED from
documented semantics and was not measured against SwiftUI**, exactly as `RX-P`'s
own SwiftUI claim is, and it is labelled as derived at all three sites for the
reason `RX-F`/`TB-AA` give: a derived figure must not appear at a line as though
it had been observed.

**Cost if wrong.** If SwiftUI does arm across the body, this is a divergence and
belongs in CLAUDE.md's numbered list rather than in a limitation note —
recoverable by writing the SwiftUI harness `RX-P` already says this repo lacks.
If the interval turns out to be reachable in ordinary use rather than rare, the
remedy is the two-session design this ruling declines, not a re-run of the
argument above.

**Taxonomy note.** This is shape 14 — "a confident wrong reason closes the
question before it is asked" — in its purest observed form: the hazard was
raised **by name**, dismissed with a reason nobody ran, and the question closed
in the one document a later reader would consult instead of re-deriving it. The
dismissal is struck through in place rather than deleted, per this project's
rule, so the shape stays visible at the site where it did its damage.

---

# The ledger's rulings, A through J

## RX-A — Tasks 1 and 2 are dispatched as ONE unit, because Task 1's diff is dead code by construction

Task 1 adds a type, three stored properties and a flag that nothing reads. No
reviewer can meaningfully answer "is this storage correct?" without the frame
loop that uses it, and the task-sizing rule is that a task must be one a
reviewer could reject while approving its neighbour. **Cost if wrong:** one
review sees a diff spanning a new file plus the frame loop instead of two
smaller ones — outweighed by a guaranteed false-positive dead-code finding.
**Discharged:** commits `b1e7deb` and `2b616e3`, reviewed together, review
clean.

## RX-B — a test that is GREEN on arrival is correct here, and pre-judging the finding is forbidden

`mutatingAnUnreadPropertyDoesNotDirtyTheWindow` asserts the *absence* of a
behaviour, so it is vacuously true before the implementation and meaningful only
once its sibling passes. That is stated in the plan and the implementer was
instructed to record it rather than "fix" it. **The controller deliberately did
NOT tell the reviewer to skip it** — pre-judging a finding is forbidden, and if
a reviewer raises it the exchange is cheap. **Cost if wrong:** a reviewer flags
a test that asserts nothing; adjudicated then. **Discharged:** the control
behaved exactly as predicted — the dirty test failed pre-implementation and the
unread-property test passed vacuously.

## RX-C — every task that runs a mutation proves the tree is clean before committing

Tasks 3 and 4 each edit `Sources/` and restore. An unrestored mutation would
ship as production code and **its own test would be the thing that went green.**
Each dispatch carried the precondition: run `git diff --stat Sources/` and
confirm it is empty before `git add`. **Cost if wrong:** a mutated line ships,
caught by the review's diff read but only if the reviewer notices — so the cheap
precondition goes in the dispatch rather than relying on the expensive check.

## RX-D — a task step whose outcome is UNCERTAIN says so, and the implementer reports reality rather than the prediction

Task 4 step 3 predicted that collapsing both hop branches fails the pre-existing
idle test, and said in terms that a green result is a **finding against the
spec** rather than a reason to adjust the test. That is the practices doc's own
rule — "a mutation that reddens nothing is a broken instrument or it is the
finding" — applied in advance. **Cost if wrong:** nothing. **Discharged, and it
fired:** the prediction was wrong and the finding is `RX-H`.

## RX-E — the Task 1+2 review's two Important findings become Task 3 REQUIREMENTS rather than a fix round

The reviewer traced five mutations against the sentinel, the orderings and
`isFlushing`, and **all five stayed green** — on a single-frame fixture, which is
taxonomy shape 15 (a fixture in which the code under test cannot be reached)
arriving again. Both findings are brief-mandated deferrals the reviewer itself
says are not implementer failures: those mechanisms are pinned by Task 3, not by
Task 1+2's two tests. A fix round would either duplicate Task 3 or add a test
Task 3 replaces. **Cost if wrong:** the pin lands one task later than it could
have; nothing ships unpinned, because Task 3 is in the same branch and the final
review sees both. **Discharged at Task 3**, whose three tests cover all five.

## RX-F — a prototype figure attached to an in-tree line must be REPLACED by an in-tree measurement, not corroborated by one

Two doc comments carried planning-time prototype numbers, **both of them in
`Window.swift`**: `isFlushing`'s own comment said the guard gives "0 across 1000
drawn frames … 999 without", and `observationDirtyings`' comment said removing
the sentinel "takes it from 1 to N". Both were measured on a standalone
prototype at 1000 frames. **Task 3's fixture draws 200**, so the true in-tree
figures are **0 vs 199** and **1 vs 200**. (`RedrawSentinel.swift` was not one
of the two: it carries only the §2 prototype table, which is *correctly*
labelled a standalone probe and is the right evidence for the standard library's
behaviour rather than this tree's — see `RX-K`.)

**This is `TB-AA`'s converse applied to a fresh instance: a measurement taken on
one harness, attached to a line on another as though measured there.** The
ruling required replacement rather than a footnote, and Task 3 discharged it —
both doc comments now carry the 200-frame numbers, with the off-by-one explained
at the line (frame 1 has no prior session armed to trip).

**Cost if wrong:** a doc figure nobody can reproduce, which is the failure mode
CLAUDE.md spends a whole section on. The §2 prototype figures survive in the
**spec**, where they are labelled as a standalone probe and are the right
evidence for the standard library's behaviour — see `RX-K`.

## RX-G — ordering 2 is UNPINNABLE by construction, and is recorded rather than tested

`drawFrameIfNeeded`'s flush precedes `needsRedraw = false`. **With the
`isFlushing` guard present, moving the clear above the flush changes no
observable at all**: the flush marks nothing dirty, so there is nothing for the
clear to absorb and nothing for its position to matter to.

The two mechanisms are **deliberately redundant — either alone suffices.** A
test could only "pin" ordering 2 by *also* deleting the guard, which is not a
test of the ordering; it is a test of a two-line mutation, and it would go green
again the moment either line was restored.

**Ruling: record it, at the line and in CLAUDE.md, and state that NEITHER may be
removed on the evidence of a green suite.** The ordering comment in
`drawFrameIfNeeded` names all three orderings and what breaks if each moves;
`isFlushing`'s own doc says it is behaviourally redundant today and why it is
kept anyway (`RX-M`).

**Cost if wrong:** a future reader deletes *both* — the guard as dead code and
the ordering as arbitrary — and nothing reddens. That is the one composition
this milestone cannot test, and it is the reason this ruling exists rather than
a test.

## RX-H — spec §4.2's ARGUMENT is correct and its named example was wrong, which is this branch's third wrong prediction about which test catches what

The reactivity spec's §4.2 argues that an always-hop callback would destroy the
idle criterion. **The argument is confirmed.** What was wrong is the example
derived from it: the plan (`docs/superpowers/plans/2026-09-02-reactivity.md`,
Task 4 step 3, and the task-4 brief that carried it) predicted that the mutation
would fail "the idle tests … including the pre-existing
`idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`". **Measured by Task 4:
that test stayed GREEN. Six others failed.** (§4.2 itself names no test — the
prediction lives in the plan, which is why the correction block goes in §4.2
anyway: that is where a reader picks the argument up and would derive the same
wrong example again.)

**The reason, verified independently twice** — by the implementer and then by
the reviewer against `idleWindowPausesTheDisplayLinkAndDirtyingResumesIt`
(`FrameLoopTests.swift`) and `Window.drawFrameIfNeeded`'s idle guard and
sentinel flush —
is that the test is **structurally blind** to the mutation. It draws only two
frames: frame 1 has no armed session to flush, and frame 2 returns at the
`guard needsRedraw` before reaching the flush at all. It never triggers a flush,
so no mutation of `markDirtyFromObservation` can reach it. The reviewer added
the half the implementer's account did not: it dirties via a direct
`setNeedsRedraw()`, never through `@Observable`, so it is not on the path in
either direction.

**The general claim is untouched.** Always-hop does destroy the idle criterion,
and the test that structurally mirrors that hazard is
`anObservableWriteWakesAPausedWindowAndDrawsExactlyOneFrame` — which is among
the six that failed, confirmed by the reviewer.

**This is the branch's third wrong prediction about which test catches what**,
after §6.1's original "nothing observes `setDisplayLinkPaused`" (false;
`FakePlatformWindow.pauseCalls` exists and is read across `FrameLoopTests`,
`ScrollIndicatorTests` and `StateTests` — that claim came from a `grep`
truncated by `head -20`, the instrument defect this project's practices doc
names, arriving inside the spec that cites it) and §6.2
assertion 4's "deleting the guard reddens assertion 1" (false; `RX-M`). All
three were caught by running the mutation and none by re-reading the spec.
**Cost if wrong:** none to the code — the spec's §4.2 is corrected to name the
test that does mirror the hazard, which is what keeps this from becoming a
fourth.

## RX-I — an assertion that pins the SCHEDULER's ordering of two runnable jobs is replaced, not relaxed

`anOffThreadMutationMarksTheWindowDirtyAfterAHop`'s first assertion — that the
window is *still clean* immediately after `await done.value` — is **unobservable
by construction**, and the implementer proved that rather than assuming it: it
instrumented the branch, confirmed the off-thread path IS taken
(`Thread.isMainThread == false`, 5/5 deterministic), and the assertion still
failed 5/5.

The mechanism is that `await done.value` is itself a suspension point on the
main actor: it hands the main actor's thread back to the scheduler, which is
free to run the hop's already-enqueued `Task` before this function's own
continuation resumes. **There is no difference in KIND between that suspension
and the explicit `await Task.yield()` on the next line.** The plan asserted a
race outcome as if it were a guarantee.

**The replacement asserts the branch's two genuinely observable guarantees**: it
does not trap (prose, not `#expect` — see `RX-N` for the SIGTRAP measurement
that is the evidence), and it does eventually dirty, after an explicit yield.
**Cost if wrong:** a test pinning timing rather than behaviour, which is exactly
what this project's "assert counts, never wall-clock times" rule exists to
prevent. Discharged in Task 4's fix round (`0588863`).

## RX-J — `MainActor.assumeIsolated` inside the demo's `atexit_b` hook is safe, and the site is recorded regardless

Raised as a review ⚠️ and resolved by the controller. `atexit` handlers run on
the thread that calls `exit()`, and both of the demo's quit paths — the **Q**
binding and the window's close button — go through
`NSApplication.shared.terminate(nil)`, which runs on the main thread. The
reviewer verified both paths converge there rather than taking the claim.

**Recorded regardless of being safe**, because CLAUDE.md's release-trap section
named exactly one `assumeIsolated` site (`Text.requestLayout`) and a section
naming one of several reads as though the others were a different kind of thing.
**Re-counted during this documentation task and the number is FOUR, not the
three the task was briefed with**: `Text.swift:217` (the live, unguarded trap),
`UnbreakableRuns.swift:110` (**pre-existing**, guarded by `Thread.isMainThread`,
already documented at its own line with its own signal-5 measurement, and never
named in CLAUDE.md either), `Window.markDirtyFromObservation`'s synchronous
branch (new, guarded) and the demo's `atexit_b` hook —
`atexit_b { MainActor.assumeIsolated { printReactivitySummary() } }` in
`main.swift` — (new, this ruling). **Symbols rather than line numbers**, for
the reason `RX-R`'s table now records: the line numbers these two carried were
correct at `3881f65` and stale at `966cc84`. **Cost if wrong:** process termination at
exit — cosmetic, since the summary is the last thing that happens, but it would
be a further instance of a trap this repo already carries one live example of.
