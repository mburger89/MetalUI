# Tombstones and AX nodes — decisions taken during execution

Rulings from the milestone that made `StateTable.sweep()` retain unmarked
entries as **tombstones**, reap them on a generation policy, closed
divergences 12 and 17 as **bounded**, and landed the first accessibility node
registry. Prefixed **`TB-`** and **lettered** (`TB-A`, `TB-B`, …) per this
repo's convention — **a bare `TB-3` is a typo, not a citation**, the same note
every other milestone's decisions doc carries.

Read alongside
`docs/superpowers/specs/2026-09-01-tombstones-and-ax-design.md` (§1 has the
one-mechanism-four-consequences argument, §7 the exit criteria, §8 the risks
recorded up front) and
`.superpowers/sdd/2026-09-01-tombstones-and-ax/progress.md`, the execution
ledger these rulings are drawn from.

## How to read the letters, because they are not all the same kind of thing

**`TB-A` through `TB-AD` carry the ledger's own letters `A` through `AD`, one
for one, deliberately.** The ledger lettered thirty rulings during execution;
renumbering them here would make every citation written during the milestone
ambiguous, which is the hazard `EP-2`/`EP-4` and the sizing milestone's
`SZ-B`/`SZ-M` collision both exist to prevent. So ledger ruling `M` is `TB-M`
here, and nothing else is.

**`TB-AE` through `TB-AH` are new, and they are the four decisions a reader
should start with.** They were never lettered in the ledger because they were
settled in prose — in the spec, in task briefs, in task reports — rather than
adjudicated as controller rulings. They are also the four this milestone is
actually *about*: what a tombstone is, what bounds it, where AX data lives,
and what "closed" means for divergences 12 and 17. **Read AE–AH first, then
A–AD for the execution findings.**

Not every letter is an engine decision. Several are findings about the
*record* — a claim that turned out unmeasured, a review whose silence was read
as coverage — and they are kept because this repo's own practices document is
assembled from exactly those. Five of them are carried into
`docs/practices/verifying-tests-can-fail.md` and say so.

---

# The four foundational decisions

## TB-AE — a tombstone is an entry RETAINED WITH ITS VALUE, flagged not-live; not a value-less marker

**The choice.** `sweep()` stops deleting unmarked entries. Every `Entry`
keeps its `value` past the frame that stopped producing it, and gains
`isLive` (was the owning element produced by the most recent frame) and
`lastSeenGeneration` (which frame last marked it). `StateTable.isLive(_:)` is
the validity flag; `peek(_:as:)` returns a tombstone's value exactly as it
returns a live one.

**Reasoning, and it is a reading of the spec rather than a mechanism choice.**
Design spec §9 asks for "a tombstone that **reports itself invalid**".
Divergence 12 needs the opposite observable: a `List` row scrolled out and
back must find its `@State` **intact**. A placeholder that only reports
invalidity gives that row nothing, so under the value-less reading the two
requirements are different mechanisms that happen to share a name. Under the
retained-value reading they are one structure with two readings: an AX handle
asks `isLive` and sees "invalid"; a returning element re-marks the entry and
reads its value back. That unification is what lets one sweep change close
four separate items in this repo's record — AX identity, exit transitions,
divergence 12 and divergence 17.

**The alternative was considered and rejected up front** (spec §1): a
value-less marker satisfies §9 and exit transitions and closes neither
divergence — half the value for most of the work.

**What it costs if wrong.** Memory. A value-less marker is a `Set` membership
per dead element; a retained value is the whole `Any` box. `TB-AF` is the
policy that bounds it, and `TB-K` is the number that says why bounding it was
not optional.

---

## TB-AF — both reaping constants, and the threshold is sized against the COLD FRAME rather than the steady state

**The choice.** `StateTable.staleAfterGenerations: UInt64 = 2` and
`StateTable.sweepThreshold = 256`, on `ShapingCache`'s model. `sweep()`
advances `generation`, re-marks liveness for every entry, and *then* — only
when `storage.count > sweepThreshold` — removes entries that are both
unmarked and satisfy `lastSeenGeneration + staleAfterGenerations < generation`.

**`staleAfterGenerations = 2` is copied from `ShapingCache`, and the copy is
argued rather than assumed.** That constant's own story is a grace period for
a caller that touches a key on a slightly different frame from the one right
before it — a windowed `List` re-touching a row it dropped one frame and
picked back up the next. Divergences 12 and 17 are the state and focus
versions of exactly that re-touch pattern, so the tuning story transfers
intact. No measurement in this milestone argues for a different number, and
inventing one without a measurement would be worse than copying one with a
reason.

**`sweepThreshold = 256` is the same numeral and was RE-DERIVED, not copied,
and the derivation is the whole contribution of the spec's §2
measurement.** Two numbers bracket it. A windowed `List`'s steady-state
resident set is **20** entries; the cold frame — frame 0, before a
`ScrollView`'s own `prepaint` has measured a viewport (ruling MP-I) — is
**100,002** on a 100k-row list. (Both are derivations: 19 and 100,001 are the
spec's original measurement, inherited and not re-run, plus 1 that this
milestone's Task 7 directly re-measured on two harnesses. `TB-AA` is the
ruling that forced that distinction to be written at the line.) A threshold
sized to the steady state alone would be validated by a test that passes
against a policy that never reaps at all, which is spec §3's stated trap. 256
is two orders of magnitude above 20 and three below 100,002, so the reap never
evaluates a single entry on an ordinary frame and always engages on the cold
one.

**`ShapingCache`'s 256 sits close to *its* measured resident set (207) on
purpose and this table's does not, which is why "same numeral" is not "same
reason".** The cache's cost model is that an eviction which turns out to be
live re-shapes every frame forever, so thrashing near the threshold is
expensive. Nothing here recomputes anything on a reap: a reaped `@State` slot
that comes back is a fresh `initial()`, which is what a never-before-produced
element gets anyway. So this table has no reason to sit close to its steady
state and every reason not to — the margin is for a second list or a handful
of ordinary stateful elements coexisting with the first.

**Underflow was a real hazard the brief did not mention.** `generation` is a
`UInt64` starting at 0, so the subtracting form
(`generation - staleAfterGenerations`) traps on the first sweeps of the
table's life; the reviewer confirmed it by **crashing it** (signal 5) rather
than by reading it. The addition form asks the identical question and cannot
underflow. `ShapingCache` never had this hazard because its analogous constant
is a plain `Int` — a genuine distinction, not a copied comment.

**What it costs if wrong.** A threshold too low makes the reap loop run every
frame over the whole table; too high leaves the cold-frame spike resident and
indistinguishable from a leak until someone opens a large list. Pinned in two
places that catch different mutants:
`theColdFrameSpikeIsReapedRatherThanRetainedForever` catches "never reaps",
and `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`
catches "reaps regardless of size" — see `TB-H` for why the realistic fixture
cannot catch the second.

---

## TB-AG — AX data lives on `Handlers.axNode`, NOT as a fifth `StyledElement` requirement

**The choice.** `Handlers` gains a sixth stored member, `public var axNode:
AXNode`. `StyledElement`'s requirement list stays at four (`style`,
`decoration`, `elementID`, `handlers`).

**Reasoning, and it is concrete rather than aesthetic.** AX emission is read
in `prepaint`, at exactly the registration call `registerHandlers` already
makes from `Box.prepaint` — the same phase and the same call site `Handlers`
already occupies. `Decoration` would be the wrong home for the same reason
read backwards: it is paint-phase data, read by each conformer's own `paint`.
And a fifth *requirement* is not free: `Stack`, `List` and `Text` each store
their own `Handlers` rather than forwarding to an internal `Box` the way
`Column`/`Row` do, so a fifth requirement costs a stored property on each of
them plus a forwarding property in `Flex.swift` — for data that would then
travel beside `handlers` anyway.

**A consequence worth stating because it is the shape CLAUDE.md's inert table
exists for: there is no public `.axNode(_:)` modifier.** `Handlers.axNode` is
`public var` on a `public struct`, and `List.requestLayout` sets it directly
rather than through a modifier. So the field is reachable and the modifier
surface is not there yet — deliberately, since nothing consumes an AX node in
production until M4's bridge.

**What it costs if wrong.** `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`
projects `Handlers` through a hand-built `HandlerShape`, and that projection
fell behind by exactly this field — see `TB-Y`, which is the second time the
same projection has fallen behind the same struct for the same reason.

---

## TB-AH — divergences 12 and 17 are closed as BOUNDED, and the wording is part of the ruling

**The choice.** Both divergences are retired. Their retirement notes, the
entries' own doc comments, and every place the claim appears say **"for N
generations"** rather than "fixed".

**What the bound actually is, stated precisely because "N generations" alone
under-describes it.** An entry survives being unmarked for
`staleAfterGenerations` (2) generations; an excursion of exactly 2 survives
(`lastSeenGeneration + 2 < generation` is a strict `<`), an excursion of 3 does
not. **And the reap only engages at all once `storage.count > sweepThreshold`
(256)** — below that, a stale entry is retained indefinitely. So the honest
form is: *state and focus survive a windowed row's excursion of up to two
generations, and survive indefinitely while the table holds 256 entries or
fewer.*

**Reasoning.** "Fixed" and "fixed for N generations" are different claims and
the second is the true one (spec §3, §8 risk 2). A reader who takes the first
will design against a guarantee the framework does not make — a row's `@State`
is still not a place to keep anything a long scroll must not lose, which is
what divergence 12's own remedy (keep it in the data) said and still says for
excursions past the bound.

**Both halves are pinned, and the pins are asymmetric on purpose.**
`aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (`TombstoneTests.swift`)
and `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`
(`FocusTests.swift`) each assert a 2-generation excursion surviving and a
3-generation excursion not surviving. The asymmetry is the evidence: reverting
`sweep()` to deleting reddens **only** the short-excursion half, and making
`resolveFocus` a no-op reddens **only** the long half. If a single mutation
reddened both, the second half would be proving nothing about boundedness.

**What it costs if wrong.** A closure written as absolute would be a documented
guarantee the code does not make, in the one document this repo treats as
binding. That is worse than the divergence it replaces, because a divergence is
at least honest.

---

# The ledger's rulings, A through AD

## TB-A — Task 1's blast radius is a REPORT deliverable, not a plan gap

Changing the sweep reddens every existing test asserting that state
disappears, and no plan can enumerate them in advance. The dispatch required
the list, and required each reddened test to be treated as a **decision** —
inverted with its history kept, or investigated as a real regression — never
deleted. **Cost if wrong:** a genuine regression is inverted into a test
asserting the bug. Mitigated by requiring the *reason* per test, not just the
disposition. **Discharged:** seven tests reddened, all one category, none a
regression, each inverted in place with its comment history preserved.

## TB-B — Task 3 passes on arrival and stays a task anyway

Tasks 1–2 closed divergence 12 before Task 3's test was written, so its first
half is a regression guard rather than a red-first proof. It stays because the
divergence needs an explicit pin and because its **second half** — state gone
*outside* the window — is genuinely new behaviour nothing else asserts. Its
comment must say which half is which. **Cost if wrong:** a reader over-reads it
as red-first evidence. Cheap, and the comment now says so in as many words.

## TB-C — a fixture-first task producing a GREEN test is a stop, not a pass

Applied to Task 2. Its report had to contain the RED output. **Cost if
wrong:** none — an already-correct engine would be a finding worth having.
**Discharged:** the assertion was red on arrival, first as a compile error
(the two constants did not exist) and then on the count once they did.

## TB-D — `write` sets `isLive` directly but does NOT join `marked`, and that is a real semantic distinction

The brief's pseudocode had `write` join the same `marked` set `withState`/`mark`
do. Followed literally, `write(id, 42); sweep()` then reports `isLive == true`,
contradicting the brief's **own** Step 1 test. The implementer implemented the
literal version, watched it fail, and diagnosed it rather than assuming the
pseudocode was authoritative.

**The correction and its grounding in the call graph, not in the outcome.**
`marked` means "produced by the frame being built". `mark`'s only path in is
`StateBinder.bind`, which runs exclusively from inside frame construction.
`write` has exactly one caller — `@State`'s `wrappedValue` setter — and can run
from anywhere, most often a click handler between frames, with no relationship
to whether its element still exists. Treating a write as production would let an
element that was never rendered masquerade as live for exactly one sweep, which
is wrong for what `isLive` promises AX: **produced, not merely poked.**

**Cost if wrong:** an entry written from outside a frame counts as produced and
never tombstones — silently defeating the mechanism for exactly the elements
input touches. Verified load-bearing by mutation: making `write` join `marked`
reddens exactly the two `TombstoneTests` and nothing else.

## TB-E — silence in a review read as coverage, which is a failure shape distinct from every one already recorded

The implementer's own account, kept in its own words because it is worth more
than the correction it produced:

> "I'd assumed `withState`'s callers were homogeneous with `mark`'s because the
> review had confirmed `mark`'s and `write`'s call graphs and said nothing about
> `withState`. **I read that silence as coverage rather than as scope not
> covered.**"

The claim in the comment — that `withState` "runs only from inside a frame's
own construction" — is false: `Window.applyScroll` calls it directly from raw
scroll-wheel handling, outside `Frame.render` entirely. No shipped behaviour
was wrong, but the stated *reason* for excluding `write` from `marked` was
undercut, so the reasoning was rewritten to the narrower, actually-true
distinction (see `TB-D`).

**This is distinct from every documentation-integrity mechanism already in
`docs/practices/verifying-tests-can-fail.md`.** Those are about a claim the
author never measured. This is about a claim the author believed *because a
reviewer had verified its neighbours*. **A review samples, and the shape of
what it sampled is not stated in what it returns.** **Cost if wrong:** none —
it is an observation about how a false belief formed, and the correction it
produced is independently verified. **Carried into the practices doc.**

## TB-F — the `!entry.isLive` conjunct in `sweep()`'s reap is REDUNDANT BY CONSTRUCTION, and is kept with an honest label

The brief expected "reap live entries too" to redden the cold-frame test. It
does not, and the reason is a proof rather than an observation: `sweep()`'s
liveness pass sets `isLive := isMarked` and, exactly when marked, stamps
`lastSeenGeneration := generation` — in the same pass, unconditionally, for
every key. So by the time the reap loop runs,
`isLive == true ⟺ lastSeenGeneration == generation` is an invariant of the loop,
and substituting it makes a live entry's staleness test read
`generation + staleAfterGenerations < generation`, false for any positive
constant. The mutant is **provably equivalent** — dead to any possible test,
not merely to this suite — and empirically gives a byte-identical run.

**Ruling: keep the guard, and require its comment to say it is redundant by
construction and to name what would make it live** — a liveness pass that stops
stamping `lastSeenGeneration` alongside `isLive`, or a reap moved ahead of the
liveness loop. That is the `contentBox` `max(0, …)` shape from the sizing
milestone: a guard that cannot be shown to matter today and that a future
ordering change makes load-bearing. **Cost if wrong:** a line that can never
execute survives with an honest label, against the alternative of deleting a
guard whose absence becomes silent the moment the ordering changes.

## TB-G — knowing a rule, quoting a rule, and recording a ruling about a rule are all weaker than running the mutation

`TB-F` required the comment to say "redundant by construction". The shipped
comment asserted the **converse** — that the conjunct was "the line that
promise rests on" — and the report claimed the nuance was "recorded in
`sweep()`'s own doc comment now", which a grep showed it was not.

**Three layers of control failed on one comment.** The practices doc names the
mechanism ("a measurement recorded in the report is not a measurement applied
to the source"); the controller's `TB-F` pre-empted this specific instance
before the task started; and the implementer's own report **quoted that rule
two paragraphs above the violation**. It still shipped, and a reviewer running
a grep caught it.

**The process conclusion, and it is not a writing tip.** A controller ruling in
a ledger the implementer does not read is not a control. The rulings that must
survive into source comments have to be stated in the **dispatch**, not only in
the ledger. And of the four controls in play, the only one that fired was the
one that executed something. **Cost if wrong:** none — it is an observation
about which controls actually fire, drawn from a case where three did not and
one did. **Carried into the practices doc, alongside `TB-E` and `TB-Y`.**

## TB-H — a fixture that keeps a guard's condition permanently true cannot test whether the guard exists

Task 2's carried gap was that "reap on every sweep, ignoring `sweepThreshold`"
reddened nothing, and the controller assigned Task 3's `List` fixture as its
catch. **That fixture cannot catch it, by construction**: its padding
deliberately keeps `storage.count` above the threshold throughout, which makes
the gate always-true, so whether the gate is consulted at all is unobservable
in it. Proven empirically — the mutation reddens **0** tests with only the
`List` fixture present.

The implementer wrote a second, minimal test whose fixture stays at **one
entry** — `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`
— and that is the one that reddens.

**This is ruling MP-J's shape a third time in three milestones: the assertion
was fine and the FIXTURE could not express the defect.** The specific form is
worth naming on its own, because it is counter-intuitive: Task 3's `List`
fixture is realistic *because* it holds many entries, and that realism is
exactly what blinds it. The test that sees the gate is the unrealistic one.
**Cost if the second test had not been written:** the threshold constant ships
unpinned behind a test that appears to cover it — worse than shipping it
visibly unpinned, which is what Task 2's report at least did honestly.

## TB-I — Task 8 ran early, in a worktree, and the reason it could is a file-overlap argument rather than a dependency one

Task 8's stated dependency (Tasks 1–7) was conservative: what it needs is the
tombstone mechanism and its reaping policy, both landed at Task 2. The AX work
moves none of the numbers it measures, and it edits only
`MeasurePerformanceTests.swift` — zero overlap with Task 4's
`Frame.swift`/`FocusTests.swift`.

**Task 5 was the tempting one and was deliberately NOT parallelised**, and the
distinction matters: both it and Task 4 touch `Frame.swift`, so separate
worktree branches would merge-conflict in the file holding this milestone's
riskiest changes. **The blocker is a merge, not a dependency** — a different
reason from the `.build` contention that governed the previous milestone's
parallelism. **Cost if wrong:** if a later task changed the entry accounting,
Task 8's numbers need re-taking. It did (`TB-S`, `TB-X`), and they were.

## TB-J — spec §5 assumed a `StateTable` entry that does not exist

Spec §5 says `resolveFocus()` should "consult the same table" and keep focus
while the id is retained. **That assumed the focused id has a `StateTable`
entry to consult. It does not.** A focusable element with no `@State` has
nothing in the table at all, so "still retained" was unanswerable for most of
the elements the rule is about. See `TB-P`, which is this defect recurring a
third time and the reason it is now written into `StateTable`'s own doc.

**The fix, and the collision it had to avoid.** `Frame.registerHandlers` writes
a dedicated **`$focus` retention slot** whenever it sees `id == focusedElement`,
keyed as a *distinct child* of the id — distinct specifically so it cannot
collide with a `ScrollView`'s own `withState(id, …)` entry, which **is** keyed
on the element's own id and typed `ScrollState`; writing a `Bool` there would
silently clobber it. It rides the same `sweep()`/reap mechanism `@State` uses,
so focus inherits divergence 12's bound by construction rather than by a
parallel policy — which was the spec's actual intent, now achievable.

**The collision impossibility is STRUCTURAL, which is stronger than a test.**
`GlobalElementID.==` walks the parent chain to `nil` on both sides, and a child
id has one more component than its parent, so the walk cannot terminate equal.
A child can never equal its own parent by construction.

**Cost if wrong:** one slot written per focused element per frame, only while
focused. **And the trap this had to avoid was proven avoided:** "stopped being
focusable" is kept apart from "stopped being produced" by a second signal,
`focusedElementProducedThisFrame`, set independently of `handlers.isFocusable`
— collapsing the distinction reddens
`anElementThatStopsBeingFocusableLosesFocus` and two other pre-existing tests.

## TB-K — the cold frame at 100,000 rows is 16.84 s in RELEASE, and that is a finding, not a footnote

Measured: **41.86 s debug / 16.84 s release** for frame 0 at 100,000 rows,
reproduced at **16.53 s** release on a second, later run — the same number
twice on different runs, which is what makes it a measurement rather than a
sample.

Ruling MP-I already records that the cold frame builds every row, because a
`ScrollView`'s viewport extent is not measured until its own `prepaint` has run
once. At 500 rows that is 76 ms release; at 100k it scales roughly linearly to
sixteen and a half seconds.

**So M3's exit criterion — "a 100k-row virtualized list scrolling smoothly" —
is met for SCROLLING and not for APPEARING.** The list scrolls at the same cost
as a 500-row one, which is the property windowing exists to buy; it also hangs
for ~17 seconds the first time it is shown. Both are true and only the first is
what the criterion literally asks about.

**Ruling: record it, do not fix it here.** The cause is MP-I, whose own recorded
remedy is a two-pass layout or a resolved viewport in a phase defined to run
before geometry exists — a different layout architecture, explicitly larger
than this milestone. **Cost if wrong:** a milestone declared complete against a
criterion a reader would take to mean "usable at 100k", which it is not.

## TB-L — a milestone deliverable that costs 49 s of suite time is gated, and the gate's precondition is that its command is written down

Task 8's tests took the debug `--no-parallel` suite from ~14 s to **66.8 s**,
and every later task, review and fix round in this and every future milestone
pays that. This repo already has the pattern: `regenerateAllGoldens` is
env-gated precisely because it is a deliberate act rather than a per-run guard.

**Ruling: the 100k cold-frame *timing* test goes behind the same kind of gate;
the cheap assertions stay ungated.** The reviewer verified the premise before
treating the ruling as binding, and the answer was better than the ruling
predicted: the resident-set test's body at **n = 10,000** gives
**byte-identical checkpoints** in 0.181 s against ~1.3–1.9 s, because those
checkpoint counts depend on the **window size and `staleAfterGenerations`**,
not on total row count. The 100k in that test bought nothing but wall clock.
The cold-frame timing test genuinely needs 100k, because it is measuring
`TB-K`'s real number.

**Result: 66.833 s → 14.790 s, reproduced twice more (14.837, 14.774).**
**Cost if wrong:** a milestone deliverable becomes opt-in and could rot unrun —
mitigated by naming the exact command in CLAUDE.md's Build section, as
`regenerateAllGoldens` already is. That mitigation is the gate's precondition,
not a nicety.

## TB-M — `AXNode.children` stays a stored field, because order-from-keys is PROVABLY AMBIGUOUS

`Box`'s call site cannot enumerate its children's ids:
`ElementGroup.requestGroupLayout` returns `[LayoutNodeID]`, not per-child
`GlobalElementID`s. So every emitted node has `children == []` and design spec
§9's "ordered children" is unmet as literally written. The question put to the
review was whether the field should exist at all, since `GlobalElementID.parent`
is public and `Frame.axNodes` is keyed by id — so a bridge could reconstruct
parent/child by walking chains.

**Structure is fully derivable. Order is not.**
`GlobalElementID.child(of:at:name:)` is
`name.map(PathComponent.named) ?? .positional(index)` — **the index is discarded
whenever a name is given.** So

```
Row { Box(); Box().id("x"); Box().id("y"); Box() }
Row { Box(); Box().id("y"); Box().id("x"); Box() }
```

produce the **identical set** of four ids, because the cursor value that would
disambiguate them is thrown away at construction. No algorithm over the key set
alone can recover sibling order.

That kills "derive in the M4 bridge and delete the field" outright — it is not
a cost trade, it is **wrong** on a case that occurs the moment a container mixes
named and unnamed children, which this codebase's own vanishing-`if` idiom makes
routine. And a wrong AX order is invisible to every rect-based test in this repo.

**Ruling: keep the field, keep Task 5's shape, and filling it properly is a
FOLLOW-UP outside this milestone** — an `ElementGroup` associated-type change
threading `GlobalElementID` alongside `LayoutNodeID` through `EmptyGroup`,
`Pair`, `OptionalGroup`, `EitherGroup`, `ArrayGroup`, `AnyElement` and
`Element`'s default. **Tasks 6 and 7 were forbidden from attempting an
order-from-keys reconstruction.** **Cost if wrong:** the field ships empty for
this milestone and the bridge cannot build a hierarchy until the follow-up
lands. See `TB-W` for the measurement of what that leaves §9 at.

## TB-N — `@testable import` widens `internal`, so a `@testable` test file cannot prove an access-level narrowing

Task 5's fix closed `AXNode.frame`/`children` from `public var` to
`public internal(set)`. **`AXNodeTests.swift` uses `@testable import`, which
makes `internal` visible — so no test in that file could demonstrate the fix
closed anything at all.** Proving it needed compile guards against a **plain**
import of the built module, matching `ErasureCompileGuards.swift`'s pattern.

**And the first draft of the negative guard was passing on its weaker half
only:** it asserted the diagnostic contained `"Cannot assign"` where the real
text is lowercase `"cannot assign"`, so the message assertion never matched and
only `!result.succeeded` held. Caught by **printing the real diagnostic before
trusting it**.

**It generalises past this repo: a test file that imports `@testable` cannot
verify *any* access-level narrowing, because the tool that gives it reach is the
tool that hides the change.** The remedy is a plain-import compile guard, which
this repo already has machinery for. **Cost if wrong:** an access-level change
ships with a green suite that could not have gone red. **Carried into the
practices doc as taxonomy shape 16.**

## TB-O — the typecheck-guard count moved, and Task 9 owns the paragraph rather than the implementer

Recounted directly during Task 5, the guard count reached 31 across **five**
files where CLAUDE.md's "When CI lands" item 3 tracked 29 across four. The
implementer flagged it rather than resolving it unilaterally, which was right:
that paragraph is a standing record with its own re-count discipline, and
quietly bumping a number it tells the reader to verify by grep is the exact
failure it exists to prevent. Task 6 added a third guard to the new file,
taking it to 32 (confirmed by the reviewer by mutation, not by counting).

**Ruling: the documentation task owns it** — update the count, add the fifth
file, and keep the paragraph's own re-count-by-grep instruction and directory
caveat intact. **Cost if wrong:** a documented count that under-reports by
three, in the one paragraph a CI author would act on.

## TB-P — `StateTable` is keyed by SLOT, not by element, and three implementers rediscovered that independently

The spec's §5 assumed a table entry for a focused element's own id; Task 4 hit
it and fixed it with a `$focus` child slot (`TB-J`); Task 6's brief inherited
the same wrong assumption and hit it again. **Three instances of one defect is a
pattern rather than three accidents.**

The root cause is a sentence that reads as though `StateTable` is keyed by
element. It is keyed by *slot*, and every slot this framework mints —
`$state\(n)`, `$focus`, `$ax` — is a **child** of the element's
`GlobalElementID`. (The one exception is a `ScrollView`'s own `ScrollState`,
which really is keyed on the element's bare id — which is precisely why the
retention slots had to be children, so they could not clobber it.)

**Cost if wrong:** none *here*, since each task discovered it independently;
the cost already paid is three implementers re-deriving the same fact from the
source. **Ruling: it is written into `StateTable`'s own doc**, so a fourth does
not.

## TB-Q — the three slot-name collision risks are recorded TOGETHER, not guarded

A hand-written `.id("$ax")` on the right child would collide with the AX
retention slot. So would `.id("$focus")`, and so would `.id("$state0")` — the
last of which is already recorded as design spec §8 risk 1 rather than
prevented. **Adding a guard for `$ax` alone would leave the framework with one
namespace defended and two open, which reads as though the other two were
safe.** **Cost if wrong:** a caller writing a literal `.id("$ax")` gets a silent
collision with no diagnostic — the same cost the existing two already carry, and
now stated as one risk with three instances rather than three unrelated
footnotes. Recorded in CLAUDE.md's `@State` bullet;
`theThreeRetentionSlotsAreMutuallyDistinct` is what pins the three apart from
*each other*.

## TB-R — the slot-distinctness test is worth more than its size, and the measurement is why

Renaming `"$ax"` to `"$focus"` reddened **0 of 777**. The reviewer measured the
consequence rather than assuming it: the `AXNode` clobbers the `Bool`,
`resolveFocus`'s `peek(…, as: Bool.self)` returns `nil`, and **focus is
silently dropped — divergence 17 regressing with nothing able to see it.**
`"$state0"` is name-pinned in five tests; `"$focus"` and `"$ax"` in none.

**Ruling: one test pinning the three as mutually distinct**, which
retroactively guards Task 4 as well as Task 6. **Cost if wrong:** a test
pinning string literals, which is cheap and slightly brittle — against an
invisible focus regression, plainly worth it.

## TB-S — the retention slot's footprint is a forward cost Task 7 inherits, not a Task 6 defect

The AX retention slot doubles `StateTable`'s per-element footprint *if* AX
emission is broad. Measured by forcing broad emission,
`theResidentEntrySetStaysBoundedWhileScrolling10kRows` goes `10001` → `20003`
and thirteen further `table.count == N` assertions redden. Nothing emitted at
Task 6, so nothing was broken then. **Task 7's brief had to carry it** —
otherwise Task 7 discovers fourteen reddened assertions and reads them as its
own regression, and weakening them is not the fix. **Cost if wrong:** Task 7
spends a round diagnosing a cost this milestone already knew about.

**`TB-S` was right about the mechanism and wrong about the scale, which is the
correct way for a forward-cost warning to fail** — see `TB-X`.

## TB-T — the reaped-to-`nil` boundary stays unpinned and says so at the doc line

`Frame.axNode(for:)` returns `nil` once the retention slot is actually reaped —
true, and the reviewer measured it at sweep 4. **The obvious test shape cannot
reach the reap**: it needs `storage.count > sweepThreshold` sustained across
generations, which a focused AX fixture does not naturally produce. That is
ruling MP-J's exact trap, and `TB-H`'s form of it. **A test that cannot reach
the reap is worse than no test, because it reads as coverage.** The doc line
names the mechanism that would reach it instead. **Cost if wrong:** a real
boundary goes unguarded — accepted, because the alternative is a test that
passes against a policy that never reaps.

## TB-U — a finding with no source line is reported as having none, rather than satisfied by editing something

Review finding 7 described a `.id("$focus")` collision narrowed to "a focused
element's **first** child". The narrowing existed only in the report: a name
replaces a position, so any index collides. The implementer said so rather than
editing a source comment that did not carry the claim, and the re-review
confirmed it by grep rather than on trust. **Cost if wrong:** the opposite
failure to `TB-G`'s — a source comment edited to satisfy a finding it never
made, which is how a document acquires a claim nobody ever believed.

## TB-V — Task 7 observes the realized set from `Frame.axNodes`, not from `AXNode.children`

Task 7's brief said to assert the node's "realized children are ~17". Following
it literally means either filling `children` in violation of `TB-M` or writing a
one-sided test that checks only the logical 500. **Ruling: observe the realized
set from `Frame.axNodes`** — the row nodes actually emitted into the frame,
which is what a bridge would walk. Both halves must be asserted and must be
*different* numbers; a fixture whose viewport shows every row cannot express the
defect. **Cost if wrong:** the realized half is observed one level away from the
node itself, so a bridge walking `children` would see nothing — accepted, because
`children` is empty by design until the follow-up `TB-M` names.

## TB-W — design spec §9's "full logical count **with realized children**" is HALF met, and the half that is missing is measured

Dispatched as the review's primary question, because a `List` emitting one
container node while its rows emit none would make `TB-V`'s two-sided assertion
trivially satisfiable rather than discriminating.

**Measured through the real three-phase pipeline on a production-shaped 500-row
`List`:** `totalAXNodes=1, rowNodes=0, children=0, logicalCount=500`. With the
demo's own row shape: `totalAXNodes=1, hitboxes=17` — **seventeen rows realized
as hit targets, none as AX nodes.** `Box.prepaint` is the sole production
`emitAXNode` caller and always passes `children: []`.

**So the count is exposed correctly and there is nothing to expose it with.**
**Disposition: deferred with a named mechanism** (`TB-M`'s `ElementGroup`
associated-type change), written at `AXNode`, at `List`'s type doc, and in
CLAUDE.md's declared-but-inert table. **A deferral with a named mechanism is an
acceptable answer; a silent gap is not** — taxonomy shape 4, silence at a
declaration reads as "implemented". **Cost if wrong:** an M4 bridge reads a
correct count and finds no children to attach it to.

The realized half of the *test* is separately not vacuous: the number comes from
production `visibleRange`, windowed → 17 against unwindowed → 500, and disabling
windowing reddens it.

## TB-X — changing a pre-existing assertion's expected number is the move that hides a regression, so it is verified by SCALING

Task 7's emission moved `theResidentEntrySetStaysBoundedWhileScrolling10kRows`
from `n + 1` to `n + 2`. Editing an exact-count assertion that was this
milestone's own instrument is exactly how a regression gets absorbed, so the
claim ("growth is per-`List`, not per-row") was checked by varying row count
rather than by reading the diff: reverting only the emission gives `10001`
against an expected `10002`; the delta is **+2 at 50, 200 and 800 rows** and
**+3 with two `List`s**. Flat in row count, per-`List`. The assertion stayed
`==` rather than being loosened to a range. **Cost if wrong:** an exact-count
assertion becomes a rubber stamp.

## TB-Y — a documented hazard repeated VERBATIM, which is why it was elevated from a low finding to a required fix

`HandlerShape` (`ModifierTests.swift`) projects `Handlers` for
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField`, which cannot compare
`Handlers` by whole-value equality because it carries escaping closures. It
projected five fields; `Handlers` had six from Task 5's `axNode`.

**CLAUDE.md names this exact hazard in advance**, at that exact projection:
*"That projection must gain a field in the same change `Handlers` gains a member
— it did not, once, and `onAction(_:_:)` and `keyContext(_:_:)` escaped the
table entirely for a whole task."* It has now happened a **second** time, to the
same projection, for the same reason, with the warning already written in the
repo's own primer.

**Cost if wrong:** a modifier that also writes `axNode` ships uncaught, exactly
as two modifiers did before. **And the fix is judged by mutation, not by field
count** — see `TB-AB`. **Carried into the practices doc**, alongside `TB-E` and
`TB-G`, as the third and sharpest instance of the same conclusion: knowing a
rule, quoting a rule, and having it written in the repo's own primer are all
weaker than running the mutation.

## TB-Z — stale doc numbers are re-taken as a whole set, not patched where a review flagged them

The review supplied corrected values for four stale figures; the fix round was
instructed to take the whole set fresh instead. This is `SI-H`'s own amendment
applied to a fix round rather than to a milestone: **staleness is systematic
rather than local — a review samples, and a count taken before the last change
landed is stale across everything measured in that window.** **Cost if wrong:**
the flagged rows get right and the unflagged ones stay wrong, which is the state
that reads as "reviewed". See `TB-AC` for what the whole-file sweep then found.

## TB-AA — anything a measurement did NOT establish must not appear at the line as though it had

The converse of the practices doc's first record-mechanism. That mechanism says
anything a measurement teaches is walked back to the mutated line. Its converse
is the one this milestone needed.

**The instance.** `StateTable.swift`'s `sweepThreshold` comment carried a
parenthetical — "(measured on a scrolling 500-row and a scrolling 100,000-row
list alike…)" — that was true of the **19** the spec inherited, and got attached,
unqualified, to a derived **20** that nothing measured that way. The implementer
flagged that its own "19→20" figures could not be independently reproduced from
the original harness, and that flag is what made the re-review substantive.

**The adjudication splits the claim in half, which is the useful part.** The
**+1 delta is genuinely re-measured on two independent harnesses** — reverting
`List.swift`'s AX-emission lines drops the cold frame 10002→10001 and the
checkpoints 77/127/99→76/126/98, flat −1 everywhere. The **base absolutes (19,
100,001) are not** re-measured and no harness reproducing them exists today. The
report said so honestly; **one committed doc line did not.**

**Deleting the numbers would have been worse than qualifying them** — the
threshold argument in `TB-AF` needs them — so the fix corrects the framing at
the line: 19 as the original measurement explicitly not re-run, +1 as directly
re-measured, and 20 as a **derivation** rather than a fresh measurement of the
sum. **Cost if wrong:** a derived or assumed number enters the record
indistinguishable from a measured one, which is how three of this repo's five
recorded mutation counts went stale undetected. **Carried into the practices
doc.**

## TB-AB — a widened projection is judged by whether it gains POWER, not by whether it gains a field

Widening `HandlerShape` from five projected fields to six proves nothing on its
own. The test only gains power if a modifier that also writes `axNode` now
reddens `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`. **Closed the
right way:** mutating `Box.onClick(_:)` to also write `axNode` reddens that test
alone, 1 issue of 782. **Cost if wrong:** the projection is enlarged, the row
looks covered, and the third recurrence of `TB-Y`'s gap ships behind a green
suite.

## TB-AC — a set of stale sites handed over by a review is a SAMPLE, not an inventory

`TB-Z`'s re-take was instructed to grep the same files for a site neither pass
had caught. **Vindicated: two more `"19"`s survived** — one in `sweep()`'s own
doc comment, a **fifth** site outside the original review's set, and one
**twenty-six lines below a line the fix round had itself just corrected.** The
final round swept the whole file, corrected four sites, and left four alone with
stated reasons (a fixture parameter, `ShapingCache`'s own figures, an unrelated
historical suite count, and checkpoint lines already framed correctly).

**Cost if wrong:** the reviewer's list is treated as the inventory, the sweep is
skipped, and the file ships with stale numbers a reader has no reason to
distrust. **Carried into the practices doc as an amendment to `SI-H` and to the
third record-mechanism.**

## TB-AD — the ledger caught a near-duplicate dispatch, and that is evidence rather than a near-miss

Task 8's brief was extracted alongside Task 7's on the assumption that numbering
was sequential; the ledger's own grep for completed tasks showed Task 8 already
merged, with a review and a fix round behind it. Re-dispatching it would have
re-run the milestone's most expensive test task. **Controller-lost-its-place
re-dispatch is the single most costly observed failure of this process, and the
cost of checking was one `grep`.** **Cost if wrong:** ~50 s of suite time per
run for the rest of the milestone, plus a duplicate commit — recorded because
the mechanism working is as worth writing down as the mechanism failing.
