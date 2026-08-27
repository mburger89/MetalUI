# Content sizing — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-26-metalui-content-sizing.md`, in order. Each
says what was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `CS-`.** `PF-`/`C-` belong to m1a, `FS-` to flex
sizing, `AL-` to alignment, `BM-` to the box model, `WR-` to wrapping. A bare
`F-n` is ambiguous across three documents — sweep for stray citations
**case-insensitively**, since a `Ruling F-3` survived two branches' greps for
lowercase `ruling`.

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| CS-A | **`collectItems` and `flexBaseSize` do not take `LayoutContext` yet.** Task 4 wires the four constant-substituting sites and needs `ctx` at both to recurse; Task 2 does not, and adding a parameter one task early means a task's worth of code where it exists and is unused — this repo's most-repeated bug shape (taxonomy shape 4). Task 2's `layOutChildren` calls both with their existing `rootFontSize:` signature. *(Task 2 did change `collectItems`' `containerSize:` from `SizeD` to `OptionalSizeD`, which CS-D forced and which is not what this ruling is about.)* | A parameter that exists and does nothing reads, from outside, exactly like an implemented one. |
| CS-B | **A predicted test count is a prediction, never a target.** The Task 2 brief predicted 309 → 314; Task 1's fix round had already made it 310, and the task shipped at 318. The measured number wins, always, and a test is never adjusted, added or deleted to reach a predicted one. What *is* load-bearing is the direction: a count that **falls** without a deletion you can name is taxonomy shape 11 — a truncated run — and must be treated as a failure until explained. | A number in a plan quietly becomes an instruction, and someone deletes a real test to hit it. |
| CS-C | **A test that asserts something does NOT trap must run in a subprocess** — `await #expect(processExitsWith: .success) { … }`, matching `usingAnIdAgainstItsOwnTreeDoesNotTrap`. Task 1 shipped `layoutClearsTheGuardWhenItFinishes` with a bare `setStyle` call after `computeLayout`; mutating the guard it protected killed the test process with signal 5, printing **no summary line at all** and destroying every other test's result (taxonomy shape 11). In-process, the mutation's diagnosis is "the suite vanished"; in a subprocess it is one red test. `#expect(processExitsWith:)` bodies are non-capturing, so each call site is written out in full rather than sharing a helper. | The mutation that proves a guard works also destroys the evidence that anything else does. |
| CS-D | **An indefinite axis is `nil`. Never `.infinity`, never a large finite stand-in.** `measureNode`'s first version probed an unbounded axis with `.infinity`; `layOutChildren` then did arithmetic on it. Three ten-line containers — a `flex-grow: 1` child, a `width: 50%` child, and a percentage `gap` — each drove §9.7's freeze loop past its pass cap and `assertionFailure`d the **process**, signal 5, no summary line. `inf - inf` and `inf * 0` are NaN, every comparison against a NaN is false, so no item registers a violation and nothing ever freezes. The fix is CSS's own rule **for the definite-vs-indefinite question**: percentages against an indefinite basis are unresolvable and already resolve to `nil` in `resolveDimension`, and §9.4 step 8 / §9.4.8's single-line clause are keyed on the word *definite* in the spec itself. **What replaces §9.7 is a substitute, not a citation** — every item keeps its hypothetical main size, which equals §9.9.1's answer only while the chosen flex fraction is ≤ 0. See the carried risk below; that difference is the finding, and confusing the two halves of this ruling is how it would get lost. The one place a missing extent still becomes a number is `collectLines`' budget, where `.infinity` is a *comparison bound* and no arithmetic touches it. | The engine kills the process on a shape as ordinary as a `flex-grow` child — and in a release build, where the assertion is compiled out, silently returns NaN rects instead. |

**CS-D was found by a reviewer's ten-line probe, not by the 318-test suite**, and
the reason is worth keeping: every test in `MeasureNodeTests.swift` at the time
sized its children in pixels with no gap and no margin, which is the one
configuration for which `.infinity` and "indefinite" agree. The task's own report
had even written the failure down as a limitation — "reports an infinite content
size … no test here can see it" — which was wrong in both halves and is exactly
taxonomy shape 10: a prediction about measurement, dressed as a fact about the
code, that tells the reader not to look.

## The depth guard's ceiling — a measurement, not a ruling

`LayoutContext.maxDepth` was 256 and is now **64**. This is not a ruling because
nothing was decided: the number was measured, and 256 failed.

Raising the constant out of the way and laying out N nested nodes gives, by
bisection: **196 levels lay out and 197 dies with SIGBUS** on a Swift Testing
exit-test task; review measured ~110 on an explicit 256 KB thread, and the main
thread's 8 MB reaching 256 and trapping properly. So at 256 the guard fired on
the main thread alone, and on every other stack the `placeNode` →
`positionItems` recursion exhausted the stack first — the exact unattributed
crash the guard exists to prevent.

**The lapse was invisible to the tests that existed**, and that is the part to
carry: both depth tests entered the context by hand, so neither ever ran a real
recursion and neither could see how far one gets.
`layingOutATreeDeeperThanTheLimitTraps` now lays out `maxDepth + 1` **real**
nested nodes and asserts the guard's own message on stderr — green at 64, red at
256 — so the next change to the constant is a measurement rather than a claim.
The boundary moves with frame size, and Task 4's measurement recursion adds
frames per level.

## Carried risk

- **Under intrinsic sizing the engine skips §9.7 where CSS runs §9.9.1, and
  §9.9.1 applies `flex-grow`.** This is the one place the engine is knowingly
  not CSS after CS-D, and it is the item Task 4 inherits.

  The spec's own worked example, measured against this engine
  (`flex-basis: 100px`, `min-width: 0`, a `MeasureFunction` returning 200 wide,
  measured at `.maxContent`):

  | | engine | CSS §9.9.1 |
  |---|---|---|
  | `flex-grow: 0` | 100 | 100 |
  | `flex-grow: 1` | **100** | **200** |

  CSS Flexbox §9.9.1.1 says it outright: *"when the item is `flex-grow: 0`, the
  flex container is 100px wide, but when the item is `flex-grow: 1` or higher,
  the flex container (and flex item) is 200px wide."* The mechanism is that CSS
  does not run §9.7 under intrinsic sizing at all — it runs §9.9.1, which sums
  each item's max-content **contribution** and *does* let a flex fraction grow
  them. `layOutChildren`'s "keep the hypothetical main size" substitute equals
  that only while every item's max-content contribution is at most its outer
  flex base size, i.e. while the chosen flex fraction is ≤ 0.

  **Unreachable in production by a nameable mechanism, not by a milestone:**
  `flexBaseSize`'s content branch is the only route to a max-content
  contribution larger than the base size, and it needs `tree.measure(item)` to
  be non-nil — `newLeaf` is the only thing that populates it and has no
  production caller. It is reachable from a test today (the table above is
  one), and Task 4 is what puts it in the path.

- **`measureNode` cannot tell `.minContent` from `.maxContent` for a
  container.** Both leave the axis indefinite and `layOutChildren` does not wrap,
  so a `wrap` container answers max-content under either. Only a leaf's own
  `MeasureFunction` distinguishes them. Design §5.2 lists "`.minContent` and
  `.maxContent` swapped at a call site" as a mutation that must redden a
  fixture; it cannot until this closes.
- **`measureNode`'s purity is not enforced by the type system.** A `setLayout`
  anywhere beneath it returns the right size and passes every golden;
  `measuringWritesNoLayout` is the only thing that sees it, and it asserts on
  the stored rects of *every* node in the subtree, not just the container's.
- **`contentMain` is a fourth independent re-derivation** of "outer main sizes
  with gaps between", after `lineContentSize`, `positionItems`' `content` and
  `ResolveFlexibleLengths`' `totalGap`. Carried forward from FS's and AL's own
  carried-risk sections, which now say so.
- **`ResolveFlexibleLengths`' pass cap is reachable without a bug in
  §9.7.4.e** — hand it a non-finite `containerMain` and nothing freezes. CS-D
  closed the one caller that did; the comment and the assertion message now name
  the mechanism, and in a release build that path returns NaN silently.
- **Two guarantees still lapse under plausible CI configurations** — the ABI
  probe skips without a Metal device, and `committedGoldensMatchTheBrowser` is
  the only live-WebKit consumer. Both must be required, non-gateable jobs.
