# Tombstones and AX Nodes — Design

**Status:** approved in brainstorming 2026-09-01. Follows the sizing milestone
(merged as `89984e1`). Closes design spec §12 milestone 3's remaining subsystem,
§9's "nodes and identity with M3".

**Baseline** (`master` at `89984e1`): **755 tests**, **87 goldens**, **29**
`swiftc -typecheck` guards, warning-free including `MetalUIDemo`. Every number in
this document was measured on 2026-09-01 unless attributed; re-measure rather
than quoting.

One mechanism, four consequences. `StateTable`'s sweep deletes every unmarked
entry outright, and that single line is what blocks accessibility identity, exit
transitions, and two recorded divergences.

---

## 1. Why one mechanism closes four things

The sweep is three lines:

```swift
func sweep() {
    storage = storage.filter { marked.contains($0.key) }
    marked.removeAll(keepingCapacity: true)
}
```

Four separate items in this repo's record end at it:

| blocked | recorded at |
|---|---|
| AX identity — a retained handle must not dangle | spec §9; `StateTable`'s own doc, "the mechanism that would provide it does not exist here" |
| Exit transitions | spec §4.3, "impossible until that mechanism exists" |
| **Divergence 12** — a `List` row loses its `@State` when scrolled out | CLAUDE.md |
| **Divergence 17** — a focused `List` row loses focus and never regains it | CLAUDE.md, "worse than 12: focus is not recoverable from the datum" |

**§9's wording and divergence 12's remedy are only the same mechanism under one
reading, and choosing that reading is this design's first decision.** §9 asks for
"a tombstone that **reports itself invalid**". Divergence 12 needs the opposite
observable: a row scrolled out and back must find its state **intact**. A
placeholder that only reports invalidity gives that row nothing.

They unify if a tombstone is **an entry retained with its value, flagged
not-currently-live**. An AX handle sees "invalid"; a returning element re-marks
the entry live and reads its value back. One structure, two readings.

**The alternative was considered and rejected**: a value-less marker satisfies §9
and exit transitions and closes neither divergence — half the value for most of
the work.

---

## 2. The measurements this design is sized against

Measured 2026-09-01 with a probe (written, run, deleted) that drove a windowed
`List` of rows **each holding `@State`**, advancing the scroller's stored offset
per frame:

| scenario | live entries, steady state | **peak** |
|---|---|---|
| 500 rows, static | 17 | **501** |
| 500 rows, scrolling 28pt/frame | 19 | **501** |
| 100,000 rows, scrolling 28pt/frame | 19 | **100,001** |
| 100,000 rows, flinging 450pt/frame | 19 | **100,001** |

**Steady state is 19 and flat.** Identical at 500 rows and 100,000, and
unmoved by scroll speed — the windowed rows plus the scroller's own offset. A
retention policy has almost nothing to hold during normal use.

**The peak is the entire list, and it lands on frame 0.** That is ruling MP-I: a
`ScrollView`'s viewport extent is not measured until its own `prepaint` has run
once, so the first frame builds every row. Today the sweep drops all but 17
immediately and the transient is invisible.

**Tombstones convert that transient into a persistent one.** This is the design's
central risk and the reason the policy is sized where it is.

**A second measurement, and it changes what the milestone must build:** the same
probe against the demo's actual rows gives a live set of **1** — the scroller's
offset. `demoLikeRows` carries no `@State` at all. **Divergence 12 describes a
cost nothing in the tree currently pays**, so its fixture is something this
milestone constructs rather than observes.

---

## 3. The tombstone

`StateTable`'s entries gain a **last-seen generation**. `sweep()` stops deleting
unmarked entries; it marks them **not-live** and retains their value.

- An element that returns re-marks its entry live and reads its value back.
- An AX handle to a not-live entry reports invalid rather than dangling.
- `peek`/`withState` from an element see a not-live entry as live again on the
  frame that re-marks it. Whether a *read* alone resurrects an entry, or only
  the seeding `mark`, is an implementation ruling to record — the two differ for
  a conditionally-read `@State` and this repo already has a rule about that
  (spec §2.4: seeding marks, so a declared-but-never-read `@State` is not swept).

### Reaping

A **generation sweep**, on `ShapingCache`'s model — that type already carries
`staleAfterGenerations = 2` and `sweepThreshold = 256`, with tests and a tuning
story.

**The threshold is sized against the cold frame, not the steady state**, and that
is the whole contribution of §2's measurement. Steady state never approaches any
plausible threshold; frame 0 exceeds every one. A policy validated on the 19
retains 100,001 entries and is indistinguishable from a leak until someone opens
a large list.

**So the load-bearing assertion is that the cold spike FALLS**, measured at
100,000 rows, and not that steady state is small. A test that only pins the
steady state passes against a policy that never reaps.

### What the retention window costs, stated plainly

**Divergence 12 is closed as *bounded*, not absolute.** A row scrolled out and
back within the window keeps its state; a row scrolled far away does not.
Whichever N is chosen, the entry's doc and the divergence's retirement note must
say so, because "fixed" and "fixed for N generations" are different claims and
the second is the true one.

---

## 4. AX nodes

Emitted during **`prepaint`** (§9): bounds are resolved and culled content is
naturally excluded. This rides the registration path hitboxes and focus already
use — `PrepaintPass` is where an element already registers what outlives its own
frame.

A node carries **role, label, value, traits, actions, frame, and ordered
children** (§9's list, taken as given).

**Identity derives from `GlobalElementID`** — which is what makes §3 the
prerequisite rather than a neighbour.

### Virtualized content is the requirement most likely to be got wrong quietly

§9: virtualized content "exposes the **full logical count** with realized
children, so VoiceOver reports '3 of 500' correctly". A `List` builds ~17 rows of
500; a node tree that reports what it built says "3 of 17" and is wrong in a way
no rect assertion can see.

### Not in scope

**The platform bridge.** §9 puts `NSAccessibilityElement`/`UIAccessibilityElement`
in M4, and building it here means bridging a node shape still being settled.
**AX focus unification** (§9: "the bridge reflects one into the other") is
likewise the bridge's job; M3 records focusability on the node and stops.

---

## 5. Divergence 17 — one notion of "still exists", not two

CLAUDE.md offers two mechanisms: tombstones, or "a cheaper focus-specific grace
period".

**Take the first.** `Frame.resolveFocus()` today clears a focused id this frame
did not produce; it will instead consult the same table and keep focus while the
id is **retained**, live or tombstoned.

**A focus-specific grace period would be a second notion of "still exists" that
can disagree with the first.** This repo already records what that costs: the
identity bullet's `dispatchClick` case, where a second notion of sameness would
disagree with the one `StateTable`, focus and hover share. Do not introduce one
here to save a dictionary lookup.

---

## 6. Testing

**No oracle exists for accessibility**, exactly as none existed for input:
nothing arbitrates "what should VoiceOver say". But **an AX node tree is plain
data and is directly assertable** — a stronger position than input's, where the
question was about a rendered window under a live pointer.

**Counts, not timings**, for the retention policy — the measure-performance
milestone established the instrument and this milestone's numbers are all counts
already.

**A fixture must be able to express its defect** (ruling MP-J, and the sizing
milestone's `SZ-B`). Two shapes here cannot:

- A steady-state retention test cannot see a policy that never reaps — §3.
- A `List` fixture whose rows hold no `@State` cannot see divergence 12 at all,
  which is what the demo's rows do today — §2.

**No golden may move. 87.** Nothing here touches layout; a moved golden means
something reached the engine that should not have.

---

## 7. Exit criteria

1. `swift package clean`, warning-free build **including `MetalUIDemo`**, full
   `swift test` **summary line** read — never the exit status.
2. **No golden moved. 87.**
3. AX nodes emitted with stable identity across frames; a retained handle to a
   vanished element reports **invalid** rather than dangling.
4. A virtualized `List` exposes its **full logical count** with realized
   children.
5. **Divergence 12 closed**, with the bounded nature of the closure pinned — a
   row scrolled out and back **within the window** keeps its `@State`, and a test
   says what happens outside it.
6. **Divergence 17 closed**, on the same table rather than a second policy.
7. **The cold-frame spike is measured falling at 100,000 rows** — the assertion
   the steady state cannot make.
8. **M3's own exit criterion: a 100k-row virtualized list scrolling smoothly.**
9. A human runs the demo and reports whether anything regressed.

---

## 8. Risks recorded up front

1. **The cold frame is the whole memory story** (§2). Ruling MP-I's frame 0
   builds every row; tombstones make that persistent until reaped. A policy that
   looks correct in steady state is not evidence.
2. **Divergence 12 is closed as bounded**, not absolute (§3). The claim must be
   written as "for N generations" everywhere it appears.
3. **VoiceOver actually navigating the tree cannot be tested here** and is not an
   exit criterion — it needs M4's bridge and a human with a screen reader. Record
   it as permanently open rather than implying the node tree settles it.
4. **The demo has almost no `@State`** (§2), so this milestone's fixtures are
   constructed rather than observed, and the demo will not exercise the
   divergence-12 path unless something is added to it.
