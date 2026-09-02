# Tombstones and AX Nodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `StateTable`'s sweep retain entries as tombstones rather than deleting them, then emit accessibility nodes on top of that identity — closing design spec §12 milestone 3's remaining subsystem and CLAUDE.md's divergences 12 and 17.

**Architecture:** One mechanism, four consequences. `StateTable` entries gain a last-seen generation and a live flag; `sweep()` marks unmarked entries not-live instead of deleting them, and a generation sweep reaps what is stale — with the threshold sized against the **cold frame**, which builds every row, rather than the 19-entry steady state. AX nodes then ride that identity, emitted in `prepaint` beside hitboxes and focus.

**Tech Stack:** Swift 6, SwiftPM, `swift-testing`.

**Spec:** `docs/superpowers/specs/2026-09-01-tombstones-and-ax-design.md`

## Global Constraints

- **Baseline:** `master` at `89984e1` → branch `feat/tombstones-ax` at `9aafde8`. **755 tests**, **87 goldens**, **29** `swiftc -typecheck` guards, warning-free including `MetalUIDemo`.
- **Read the test summary line, never the exit status.** `swift test --no-parallel`, unfiltered; `--filter` is a different program and cannot be trusted for a count.
- **No golden may move. 87.** Nothing here touches layout; a moved golden means something reached the engine that should not have — stop and report, do not regenerate.
- **A fixture must be able to express its defect** (ruling MP-J, ruling `SZ-B`). Two shapes here cannot, and both are named in the spec: a steady-state retention test cannot see a policy that never reaps, and a `List` fixture whose rows hold no `@State` cannot see divergence 12 at all.
- **Counts, not timings**, for every performance property.
- **Any count a later loop or subscript depends on must be `try #require`, not `#expect`** — this once truncated ~200 tests with `Index out of range` and no summary line.
- **Do not `git add -A`** — add the specific files you changed. A stray `.orig` was swept into a commit that way in a previous milestone and produced a build warning contradicting its own report.
- **Mutation discipline:** name the tests each mutation reddens rather than counting them; if a mutation reddens nothing, prove the mutant behaves differently with a probe before banking it as a gap; walk anything a mutation teaches back to the mutated **line** in the same pass.
- **`MetalUILayout` may import only `MetalUICore`.** Nothing in this milestone should touch `MetalUILayout` at all.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/MetalUI/StateTable.swift` | the tombstone: entry wrapper, generation, live flag, retaining sweep, generation reap (Tasks 1-2) |
| `Sources/MetalUI/Frame.swift` | `resolveFocus()` consults the table (Task 4); the AX registry and its per-frame reset (Task 5) |
| `Sources/MetalUI/AXNode.swift` | **new** — `AXNode`, `AXRole`, `AXTraits`, and the registry type (Task 5) |
| `Sources/MetalUI/Passes.swift` | `PrepaintPass.emitAXNode(_:at:id:children:)` (Task 5) |
| `Sources/MetalUI/Box.swift` | the public modifiers that populate an `AXNode` (Task 5) |
| `Sources/MetalUI/List.swift` | the virtualized logical count (Task 7) |
| `Tests/MetalUITests/TombstoneTests.swift` | **new** — Tasks 1, 2, 3 |
| `Tests/MetalUITests/AXNodeTests.swift` | **new** — Tasks 5, 6, 7 |
| `Tests/MetalUITests/FocusTests.swift` | divergence 17 (Task 4) |
| `Tests/MetalUITests/MeasurePerformanceTests.swift` | the cold-frame and 100k assertions (Tasks 2, 8) |
| `docs/superpowers/2026-09-01-tombstone-decisions.md` | **new** — rulings, `TB-` prefixed and lettered (Task 9) |
| `CLAUDE.md` | divergences 12 and 17 retired; the inert-table and Build sections (Task 9) |

---

## Task 1: An entry survives the sweep with its value

**Files:**
- Modify: `Sources/MetalUI/StateTable.swift`
- Test: `Tests/MetalUITests/TombstoneTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `StateTable.isLive(_ id: GlobalElementID) -> Bool`, `StateTable.generation: UInt64`, and the changed `sweep()` semantics every later task depends on.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import MetalUICore
@testable import MetalUI

/// **An entry unmarked by a frame is retained, not deleted** — the whole of
/// spec §3, and the line every other task in this milestone stands on.
///
/// Before this change `sweep()` was `storage.filter { marked.contains($0.key) }`
/// and the value was gone. `peek` must still return it, and `isLive` must report
/// that the element was not produced — an AX handle reads that as invalid, a
/// returning element re-marks it and reads its value back.
@MainActor
@Test func anUnmarkedEntryIsRetainedAsATombstoneWithItsValue() {
    let table = StateTable()
    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("row"))

    table.write(id, 42)
    #expect(table.isLive(id), "an entry written this frame is live")

    table.sweep()

    #expect(table.peek(id, as: Int.self) == 42, "the value must survive the sweep")
    #expect(!table.isLive(id), "an entry no frame marked must report itself not live")
    #expect(table.count == 1, "the entry is retained, not deleted")
}

/// A tombstoned entry that is marked again is live again, with its value.
@MainActor
@Test func markingATombstonedEntryMakesItLiveAgain() {
    let table = StateTable()
    let id = GlobalElementID.child(of: nil, at: 0, name: ElementID("row"))
    table.write(id, 7)
    table.sweep()
    #expect(!table.isLive(id))

    table.mark(id)
    #expect(table.isLive(id), "re-marking resurrects the entry")
    #expect(table.peek(id, as: Int.self) == 7, "and its value was never lost")
}
```

- [ ] **Step 2: Run and confirm both fail**

Run: `swift test --no-parallel --filter anUnmarkedEntryIsRetainedAsATombstoneWithItsValue`
Expected: FAIL — `isLive` does not exist, and once it does, `peek` returns `nil` after the sweep.

- [ ] **Step 3: Implement**

Replace `storage`'s element type with an entry carrying the generation and liveness, and make `sweep()` retain:

```swift
    private struct Entry {
        var value: Any
        var lastSeenGeneration: UInt64
        var isLive: Bool
    }

    private var storage: [GlobalElementID: Entry] = [:]

    /// Advanced by `sweep()`. An entry's `lastSeenGeneration` is compared
    /// against this to decide staleness — see Task 2.
    private(set) var generation: UInt64 = 0

    /// Whether `id`'s element was produced by the frame now being built.
    ///
    /// **`false` does NOT mean "gone".** A tombstoned entry keeps its value and
    /// is resurrected by the next `mark`; this reports only that the element was
    /// not produced, which is what an AX handle reads as invalid (spec §9).
    func isLive(_ id: GlobalElementID) -> Bool { storage[id]?.isLive ?? false }
```

`sweep()` becomes: advance `generation`; for every entry, set `isLive` to whether
it was marked, and set `lastSeenGeneration = generation` for the ones that were;
then clear `marked`. **Do not reap here** — that is Task 2, and keeping them
separate is what lets Task 2's assertion be red on arrival.

`mark(_:)` must set `isLive = true` on an existing entry. `write`/`withState`
already mark; check they go through the same path rather than a second one.

- [ ] **Step 4: Run the full suite**

Run: `swift test --no-parallel`

**Expect existing tests to redden, and that is information rather than failure.**
`stateIsSweptWhenTheElementStopsBeingProduced` and anything asserting `count`
drops after a sweep are asserting the *old* contract. **Do not delete them** —
each is a decision: either it pins something this change deliberately alters (in
which case invert it, keeping its comment's history), or it caught a real
regression. **Report every test you changed and into what.**

- [ ] **Step 5: Mutate**

Make `sweep()` delete unmarked entries again. Confirm both new tests redden, and name anything else.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/StateTable.swift Tests/MetalUITests/TombstoneTests.swift
git commit -m "feat: the sweep retains unmarked entries as tombstones"
```

---

## Task 2: Reaping, sized against the cold frame — RED on arrival

**Files:**
- Modify: `Sources/MetalUI/StateTable.swift`
- Test: `Tests/MetalUITests/TombstoneTests.swift`

**Interfaces:**
- Consumes: Task 1's `generation`, `isLive`, retaining `sweep()`.
- Produces: `StateTable.staleAfterGenerations`, `StateTable.sweepThreshold`.

**This is the task the spec exists to get right.** Steady state is **19** entries
and flat at any list size; the cold frame is **100,001**, because ruling MP-I's
frame 0 builds every row. A policy validated on the 19 retains 100k and is
indistinguishable from a leak.

- [ ] **Step 1: Write the assertion that must be RED on arrival**

```swift
/// **The cold-frame spike must FALL, and this is the only assertion that can
/// see it.** Ruling MP-I: a `ScrollView`'s viewport is not measured until its
/// own `prepaint` has run once, so frame 0 builds every row — 100,001 entries
/// for a 100k list against a steady state of 19. Task 1 made the sweep retain,
/// which turns that transient into a permanent one until something reaps it.
///
/// A steady-state test cannot see this: 19 never approaches any threshold, so a
/// policy that never reaps at all passes it.
@MainActor
@Test func theColdFrameSpikeIsReapedRatherThanRetainedForever() {
    let table = StateTable()
    let ids = (0..<100_000).map {
        GlobalElementID.child(of: nil, at: $0, name: ElementID("row\($0)"))
    }
    for id in ids { table.write(id, 1) }
    #expect(table.count == 100_000, "the cold frame really did create them all")

    // Steady state: only the last 19 are produced from here on.
    let live = Array(ids.suffix(19))
    for _ in 0..<(StateTable.staleAfterGenerations + 2) {
        for id in live { table.mark(id) }
        table.sweep()
    }

    #expect(table.count <= StateTable.sweepThreshold, """
            the cold-frame spike was retained: \(table.count) entries survive a \
            steady state of \(live.count). A policy sized against the steady set \
            passes every other test in this file and leaks the whole list here.
            """)
    for id in live {
        #expect(table.peek(id, as: Int.self) == 1, "a live entry must not be reaped")
    }
}
```

- [ ] **Step 2: Run it and CONFIRM IT FAILS**

Run: `swift test --no-parallel --filter theColdFrameSpikeIsReapedRatherThanRetainedForever`
Expected: **FAIL** — `staleAfterGenerations`/`sweepThreshold` do not exist yet, and once they do, 100,000 entries survive.

**A pass here is a broken instrument, not a fix.** Report it rather than proceeding.

- [ ] **Step 3: Implement the generation reap**

Copy `ShapingCache`'s shape (`Sources/MetalUIText/ShapingCache.swift:141,188` — `staleAfterGenerations = 2`, `sweepThreshold = 256`), but **choose both numbers against §2's measurements and justify each in a comment**: the steady set is 19, so a threshold in the hundreds never fires in normal use; the cold frame is the whole list, so the reap must actually run when it does.

Reap inside `sweep()`, after the liveness pass, and **only when `storage.count > sweepThreshold`** — so the steady state pays nothing. Drop entries that are not live **and** whose `lastSeenGeneration` is more than `staleAfterGenerations` behind.

- [ ] **Step 4: Run the full suite**

Run: `swift test --no-parallel`. Task 1's tombstone tests must still pass — a tombstone is retained *and* eventually reaped, and if the reap is too eager Task 1's tests catch it.

- [ ] **Step 5: Mutate, three ways, naming what each reddens**

1. Never reap (drop the reap call) — the cold-frame test must redden.
2. Reap every sweep regardless of threshold — Task 1's `markingATombstonedEntryMakesItLiveAgain` and Task 3's window test are the ones to watch.
3. Reap live entries too — the `peek` assertions in the cold-frame test must redden.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/StateTable.swift Tests/MetalUITests/TombstoneTests.swift
git commit -m "feat: reap stale tombstones past a threshold sized against the cold frame"
```

---

## Task 3: Divergence 12 — a `List` row keeps its state across an excursion

**Files:**
- Test: `Tests/MetalUITests/TombstoneTests.swift`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: nothing; this task is the divergence's closure and its bound.

**The demo's rows carry no `@State` — measured live set 1 — so this fixture is constructed, not observed.** A `List` fixture whose rows are stateless cannot see this divergence at all.

- [ ] **Step 1: Write both halves**

The closure and its **bound** are two assertions and the second is the one that keeps the claim honest:

```swift
/// **Divergence 12, closed as BOUNDED.** A `List` row scrolled out of the window
/// and back keeps its `@State` — *within the retention window*. Outside it the
/// state is gone, and that is the honest claim: "fixed" and "fixed for
/// `staleAfterGenerations` generations" are different, and the second is true.
```

Build a `List` of rows that each hold `@State` (the demo's do not — see
`Tests/MetalUITests/StateTests.swift`'s `CounterElement` for the shape), drive
the enclosing `ScrollView`'s stored offset so a row leaves the window, bring it
back **within** the window, and assert its value survived. Then repeat with an
excursion **longer** than `staleAfterGenerations` and assert it did not.

- [ ] **Step 2: Run and confirm the first half fails before Tasks 1-2 and passes after**

Because Tasks 1-2 have landed, this should pass on arrival. **That makes it a
regression guard rather than a red-first test, and you must say so in its
comment** — a reader who assumes every test here was red first will draw the
wrong conclusion about what it proves.

- [ ] **Step 3: Mutate**

Revert `sweep()` to deleting. The "within the window" half must redden and the "outside the window" half must not — if both redden, the second half is not testing what it claims.

- [ ] **Step 4: Commit**

```bash
git add Tests/MetalUITests/TombstoneTests.swift
git commit -m "test: a List row keeps its state across a bounded excursion (divergence 12)"
```

---

## Task 4: Divergence 17 — focus survives on the same table

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`
- Test: `Tests/MetalUITests/FocusTests.swift`

**Interfaces:**
- Consumes: Task 1's `isLive` and the retained entry.
- Produces: the changed `resolveFocus()` contract.

**Use the table, not a focus-specific grace period.** CLAUDE.md offers both; a second notion of "still exists" can disagree with the first, which is what the identity bullet's `dispatchClick` case already costs this framework.

- [ ] **Step 1: Write the failing test**

A focusable element inside a windowed `List`, focused, scrolled out of the window, scrolled back — focus must survive. And the bound: outside the retention window it must not.

`Frame.resolveFocus()` today is:

```swift
    func resolveFocus() {
        guard let focused = focusedElement else { return }
        if !focusRegistry.isFocusable(focused) { focusedElement = nil }
    }
```

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement**

`resolveFocus()` keeps focus when the id is **retained in the state table** — live or tombstoned — and clears it only when the entry is gone. **An element that stops being `.focusable()` while still being produced must still lose focus**; that is the existing behaviour and `anElementThatStopsBeingFocusableLosesFocus` pins it. Do not trade one for the other.

- [ ] **Step 4: Run the full suite**

Watch `focusOnAnElementThatStopsBeingProducedIsCleared` — it pins the old contract and is a decision, not a casualty. Invert it or explain why it stands.

- [ ] **Step 5: Mutate**

Make `resolveFocus` ignore the table again. The new test reddens; name anything else.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/Frame.swift Tests/MetalUITests/FocusTests.swift
git commit -m "fix: focus survives a windowed row's excursion (divergence 17)"
```

---

## Task 5: `AXNode` and emission in prepaint

**Files:**
- Create: `Sources/MetalUI/AXNode.swift`
- Modify: `Sources/MetalUI/Passes.swift`, `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Box.swift`
- Test: `Tests/MetalUITests/AXNodeTests.swift` (create)

**Interfaces:**
- Consumes: Task 1's identity guarantees.
- Produces: `AXNode`, `PrepaintPass.emitAXNode(_:at:id:children:)`, `Frame.axNodes`, and the `StyledElement` modifiers Task 7 populates.

- [ ] **Step 1: Write the failing test**

An element emitting a node; the node is retrievable by its `GlobalElementID`; its `frame` is the resolved bounds; children are in declaration order.

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement**

`AXNode` carries **role, label, value, traits, actions, frame, and ordered children** (spec §9's list). Emission is in **`prepaint`**, where bounds are resolved and culled content is naturally excluded — the same phase and the same registration path `insertHitbox` and `registerHandlers` already use (`Passes.swift:238,278`).

**Follow `Handlers`' precedent for where the data lives** (ruling IN-H): input callbacks went on a fourth `StyledElement` requirement rather than onto `Style` (wrong module, field-compared by an existing test) or `Decoration` (paint data). Decide where AX data lives on the same grounds and **record the decision** — if it is a fifth requirement, say why; if it rides `Handlers`, say why.

**`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` must cover every new modifier.** `Handlers` is not `Equatable`, so that test compares it through a hand-built `HandlerShape` projection — **the projection must gain a field in the same change the struct does**, or a modifier escapes the table silently. That has already happened once in this repo.

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate**

For each new modifier: have it write a second field as well. `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` must redden. Then make emission a no-op and confirm the new tests redden.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/AXNode.swift Sources/MetalUI/Passes.swift Sources/MetalUI/Frame.swift Sources/MetalUI/Box.swift Tests/MetalUITests/AXNodeTests.swift
git commit -m "feat: AX nodes emitted in prepaint, keyed by GlobalElementID"
```

---

## Task 6: A handle to a vanished element reports invalid

**Files:**
- Modify: `Sources/MetalUI/AXNode.swift`
- Test: `Tests/MetalUITests/AXNodeTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 5.
- Produces: the validity query an M4 bridge will call.

**This is §9's actual requirement** — "a node an AX client still holds survives the sweep as a tombstone that reports itself invalid, rather than vanishing and leaving a dangling reference."

- [ ] **Step 1: Write the failing test**

Emit a node, hold its id, stop producing the element, sweep, and assert the handle reports **invalid** rather than trapping, returning stale data, or vanishing.

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement**

Validity is `StateTable.isLive` — **do not add a second liveness notion.** That is Task 4's rule applied again, and the reason both are on one table.

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate**

Report every handle valid. The new test reddens. Then report every handle invalid — a *different* test must redden, or the assertion is one-sided.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/AXNode.swift Tests/MetalUITests/AXNodeTests.swift
git commit -m "feat: an AX handle to an unproduced element reports invalid"
```

---

## Task 7: Virtualized content reports its full logical count

**Files:**
- Modify: `Sources/MetalUI/List.swift`, `Sources/MetalUI/AXNode.swift`
- Test: `Tests/MetalUITests/AXNodeTests.swift`

**Interfaces:**
- Consumes: Task 5's `AXNode`.
- Produces: the logical-count field an M4 bridge reads.

**Spec §9: virtualized content "exposes the full logical count with realized children, so VoiceOver reports '3 of 500' correctly".** A `List` builds ~17 rows of 500; a node reporting what it built says "3 of 17" and is wrong in a way no rect assertion can see.

- [ ] **Step 1: Write the failing test**

A `List` of 500 with a viewport showing ~13: its AX node's logical count is **500**, its realized children are ~17, and the two are different numbers. **Assert both** — a test that only checks 500 passes against a node that realizes everything, which is the bug windowing exists to prevent.

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement**

`List` already knows `data.count` (`List.swift:197` sizes itself by it). Carry it on the node.

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate**

Report the realized count as the logical count. The test must redden — and if it does not, the fixture's viewport is showing every row and the fixture cannot express the defect.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/List.swift Sources/MetalUI/AXNode.swift Tests/MetalUITests/AXNodeTests.swift
git commit -m "feat: a virtualized List reports its full logical count"
```

---

## Task 8: M3's exit criterion — a 100k-row list

**Files:**
- Modify: `Tests/MetalUITests/MeasurePerformanceTests.swift`

**Interfaces:**
- Consumes: Tasks 1-7.
- Produces: the milestone's headline measurement.

Design spec §12 milestone 3's exit criterion is "a 100k-row virtualized list scrolling smoothly". The `List` windows, so the steady frame should cost what 500 costs — **measured flat at 40 vs 500 in a previous milestone, and this task extends that to 100k with tombstones live.**

- [ ] **Step 1: Assert the shape, not the time**

A 100k list's steady-state work equals a 500-row list's — **counts, not milliseconds**, so it cannot flake on a loaded machine. The instrument exists: `MeasurePerformanceTests.swift`'s `demoLikeRows(_:)` and `render(_:states:shapingCache:)`.

- [ ] **Step 2: Measure the cold frame separately and report it**

Ruling MP-I: frame 0 builds every row — **76.26 ms at 500 rows in release, 188.30 in debug**. At 100k that is the number to report, not to assert, and it is the one a human will feel at launch.

- [ ] **Step 3: Confirm the resident entry set stays bounded while scrolling 100k**

This is Task 2's policy under the real workload rather than a synthetic one.

- [ ] **Step 4: Run the full suite and commit**

```bash
git add Tests/MetalUITests/MeasurePerformanceTests.swift
git commit -m "test: a 100k-row list costs what a 500-row one costs (M3 exit criterion)"
```

---

## Task 9: Documentation

**Files:**
- Create: `docs/superpowers/2026-09-01-tombstone-decisions.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: The decisions doc**

Rulings **`TB-` prefixed and LETTERED** (`TB-A`, `TB-B`, …), each with its reasoning **and what it costs if wrong**, following `docs/superpowers/2026-08-30-sizing-decisions.md`. Note that lettering means a bare `TB-3` is a typo rather than a citation.

At minimum: the retained-value reading of §9's tombstone; both reaping constants and why each was chosen against the cold frame; where AX data lives on `StyledElement` (Task 5); and divergence 12's closure being **bounded**.

- [ ] **Step 2: Retire divergences 12 and 17**

**Divergence 12's retirement note must say the closure is bounded**, not absolute. Re-count the section by grep (`grep -c "^\*\*[0-9]\+\. " CLAUDE.md`) and update the header, which states both the entry count and the highest label and explains every retired gap. **Divergences 13 and 14 remain** — they are `List` windowing limitations with different causes, and retiring their neighbours must not imply they went too.

- [ ] **Step 3: Update `StateTable`'s own doc comment**

It currently says a tombstone mechanism "does not exist here" and tells the reader to grep for `tombstone` to confirm. **That grep now finds the implementation.** Rewrite the paragraph and the "Exit transitions are impossible until that mechanism exists" one — exit transitions are now *possible* and *unbuilt*, which is a different claim.

- [ ] **Step 4: Update the Build section and re-verify every count by grep**

- [ ] **Step 5: Commit**

---

## Task 10: Human verification, written OPEN

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Build and confirm the demo launches**

- [ ] **Step 2: Write the record so the criterion reads as OPEN**

**Do not describe how the demo looks or feels.** Name what a human must report. And state plainly what this milestone's tests cannot see:

- **Whether VoiceOver actually navigates the tree.** That needs M4's platform bridge and a human with a screen reader. **Record it as permanently open** rather than implying the node tree settles it.
- **The demo exercises almost none of this** — its rows carry no `@State` (measured live set: 1), so the divergence-12 path is not on screen unless something was added.

- [ ] **Step 3: Commit**

---

## Self-Review

**Spec coverage.** §1 (one mechanism, four consequences) → Tasks 1-2 with 3, 4, 6 as the consequences. §2 (measurements) → Task 2's threshold and Task 8. §3 (the tombstone, reaping, the bounded cost) → Tasks 1, 2, 3. §4 (AX nodes, virtualized count, bridge out of scope) → Tasks 5, 7. §5 (divergence 17 on one table) → Task 4. §6 (testing; no oracle; fixtures that cannot express their defect) → Global Constraints and each task's mutation step. §7 exit criteria 1-9 → Tasks 2, 3, 4, 6, 7, 8, 10. §8 risks 1-4 → Task 2 (cold frame), Task 3 and Task 9 Step 2 (bounded), Task 10 (VoiceOver, and the demo's lack of `@State`).

**Known gap, stated rather than hidden.** Tasks 3-8 give test *names*, required assertions and the exact shape each fixture must have, but not full bodies. That is deliberate: they depend on `Frame`'s real test idiom and on protocol shapes an implementer must read, and a previous milestone recorded **six API signatures written from memory that were wrong**, plus a fixture whose HTML and Swift tree described different trees. Tasks 1 and 2 carry literal code because their surfaces were read at the source (`StateTable.swift:40-41,101-190`) and Task 2's assertion is the milestone's centrepiece.

**Type consistency.** `StateTable.isLive(_:) -> Bool`, `.generation: UInt64`, `.staleAfterGenerations`, `.sweepThreshold` are defined in Tasks 1-2 and used by 3, 4, 6, 8. `GlobalElementID.child(of:at:name:)` matches the existing signature. `resolveFocus()` is quoted verbatim from `Frame.swift`. `ShapingCache`'s constants are cited at `ShapingCache.swift:141,188`, verified.

**One risk the plan cannot remove.** Task 1 changes the sweep every element passes through, and its blast radius is every test asserting that state disappears. The plan says to treat each reddened test as a decision rather than a casualty — but it cannot enumerate them in advance, so Task 1's report is where that list has to be produced.
