# Animation and Easing (M4 spec 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `withAnimation(.easeOut(0.2)) { model.isOpen = true }` makes every animatable value that changed as a result interpolate over that curve, and the display link stays awake exactly as long as something is moving.

**Architecture:** `withAnimation` parks an `Animation` on the `Window`; the next frame build carries it as ambient context on the passes. Each site that registers a styled layout node calls one shared helper, which compares the resolved `Style`/`Decoration` against the values stored in that element's `$anim` slot, starts animations for fields that differ while a transaction is in flight, and substitutes the interpolated values. `Frame` reports `hasActiveAnimations`; `Window` widens its idle guard with it.

**Tech Stack:** Swift 6.3, `CADisplayLink` (via `NSView.displayLink`), Swift Testing. No new dependencies, no engine change.

**Spec:** `docs/superpowers/specs/2026-09-03-animation-design.md`

## Global Constraints

- **Read the test summary lines — plural.** This toolchain splits `swift test` across **six** per-target summaries; sum them. `swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc`. The last line alone reads 22 and means nothing.
- **Baseline is 811 tests, 87 goldens, 34 `swiftc -typecheck` guards, warning-free.**
- **No golden may move and none may be added.** Animation substitutes values *into* the existing layout path; it must not change the engine. `git diff --name-only <base>..HEAD -- Sources/MetalUILayout/` must be **empty** for the whole branch.
- **Assert counts and values, never wall-clock time. No test may sleep.** Drive the clock by feeding timestamps, as `FrameClockTests` does with `simulateTick(timestamp:)`.
- **A mutation that reddens nothing is a broken instrument or it is the finding.** Where a task says "run this mutation", run it and report the real output — never predict it.
- **Anything a mutation teaches must be walked back to the mutated LINE in the same pass.**
- **Run mutations in an isolated `git worktree`** whenever another agent may be live in the checkout; a result from a contended tree is unattributable.
- **`aspectRatio` must not become animatable.** It is in the declared-but-inert table; animating a property nothing reads is that table's trap doubled.
- **Do not add Reduce Motion**, exit transitions, transforms, or `MetalDrawContext.time`. Spec §8 names each and why.
- Do not dispatch subagents. Do not invoke the `code-review` skill.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Sources/MetalUI/Animation.swift` (create) | The `Animation` value type, the curve evaluators (duration + spring), and `withAnimation`. Pure maths and a transaction store — no framework coupling. | 1 |
| `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift` (modify) | One line: the display-link callback passes `targetTimestamp`. | 2 |
| `Sources/MetalUI/AnimatedStyle.swift` (create) | The shared helper: compare, start, interpolate, substitute. Owns the `$anim` slot and the animatable/snapping field split. | 3 |
| `Sources/MetalUI/Box.swift`, `Stack.swift`, `ScrollView.swift` (modify) | Each registering site calls the helper. | 4 |
| `Sources/MetalUI/Frame.swift`, `Window.swift` (modify) | `hasActiveAnimations`, the widened idle guard, the transaction hand-off. | 5 |
| `Tests/MetalUITests/AnimationTests.swift` (create) | Everything in spec §9. | 1, 3, 4, 5 |
| `CLAUDE.md`, `docs/superpowers/2026-09-03-animation-decisions.md` (create) | The record. | 6 |

---

### Task 1: `Animation`, the curves, and `withAnimation`

**Files:**
- Create: `Sources/MetalUI/Animation.swift`
- Create: `Tests/MetalUITests/AnimationTests.swift`

**Interfaces:**
- Produces: `public struct Animation: Sendable, Equatable` with static factories `linear(duration:)`, `easeIn(duration:)`, `easeOut(duration:)`, `easeInOut(duration:)`, `timingCurve(_:_:_:_:duration:)`, `spring(duration:bounce:)`, and `static let `default``. A method `public func value(at elapsed: Double, from: Double, to: Double, initialVelocity: Double) -> (value: Double, velocity: Double, isFinished: Bool)`. Plus `withAnimation(_:_:)`, whose store lands in Task 5 — in this task it is a plain `@MainActor` global the tests can read.

This task is pure maths plus a transaction store. It touches no element, no pass and no `Frame`, so it can be reviewed on its own terms.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MetalUITests/AnimationTests.swift`:

```swift
import Testing
import MetalUICore
@testable import MetalUI

// M4 spec 3. Curve maths first, with no framework coupling — an `Animation`
// answers "where is this value at time t" and nothing else. Every assertion
// below feeds an explicit elapsed time; nothing sleeps and nothing reads a
// clock, which is what makes these deterministic on a loaded machine.

@Test func aLinearCurveIsExactlyProportional() {
    let a = Animation.linear(duration: 1)
    #expect(a.value(at: 0.00, from: 0, to: 100, initialVelocity: 0).value == 0)
    #expect(a.value(at: 0.25, from: 0, to: 100, initialVelocity: 0).value == 25)
    #expect(a.value(at: 0.50, from: 0, to: 100, initialVelocity: 0).value == 50)
    #expect(a.value(at: 1.00, from: 0, to: 100, initialVelocity: 0).value == 100)
}

/// Termination is EXACT for a duration curve, which is what lets
/// `hasActiveAnimations` have a precise answer and the display link pause on
/// the frame the last animation ends rather than one frame later.
@Test func aDurationCurveIsFinishedExactlyAtItsDuration() {
    let a = Animation.easeInOut(duration: 0.5)
    #expect(!a.value(at: 0.499, from: 0, to: 1, initialVelocity: 0).isFinished)
    #expect(a.value(at: 0.500, from: 0, to: 1, initialVelocity: 0).isFinished)
    #expect(a.value(at: 0.500, from: 0, to: 1, initialVelocity: 0).value == 1)
    // Past the end it stays pinned rather than extrapolating.
    #expect(a.value(at: 9.999, from: 0, to: 1, initialVelocity: 0).value == 1)
}

/// The eases must actually differ from linear and from each other, or the API
/// offers four names for one curve. Asserting the DIRECTION of the difference
/// at the midpoint is what discriminates: ease-in is behind linear, ease-out is
/// ahead of it.
@Test func theEasesDifferFromLinearInTheDirectionTheirNamesClaim() {
    let t = 0.5
    let linear = Animation.linear(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value
    let easeIn = Animation.easeIn(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value
    let easeOut = Animation.easeOut(duration: 1).value(at: t, from: 0, to: 1, initialVelocity: 0).value

    #expect(linear == 0.5)
    #expect(easeIn < linear, "ease-in starts slow, so at the midpoint it is behind")
    #expect(easeOut > linear, "ease-out starts fast, so at the midpoint it is ahead")
}

/// Spec §7. A spring is NOT finished merely because it is at its target — one
/// at the target with velocity still in it is mid-overshoot. Both halves of the
/// settling test are needed and they fail under different mistakes.
@Test func aSpringIsNotFinishedWhileItStillHasVelocity() {
    let s = Animation.spring(duration: 0.5, bounce: 0.4)

    // Early: neither settled nor still.
    let early = s.value(at: 0.05, from: 0, to: 100, initialVelocity: 0)
    #expect(!early.isFinished)

    // Late: both position and velocity within threshold.
    let late = s.value(at: 5.0, from: 0, to: 100, initialVelocity: 0)
    #expect(late.isFinished)
    #expect(abs(late.value - 100) < 0.5, "settled means at the target, got \(late.value)")
}

/// A bouncy spring must actually overshoot, or `bounce` is decorative and the
/// settling-on-velocity rule above has nothing to catch.
@Test func aBouncySpringOvershootsItsTarget() {
    let s = Animation.spring(duration: 0.4, bounce: 0.5)
    let samples = stride(from: 0.0, through: 1.0, by: 0.01).map {
        s.value(at: $0, from: 0, to: 100, initialVelocity: 0).value
    }
    #expect(samples.contains { $0 > 100.5 },
            "a bounce of 0.5 must overshoot 100; max was \(samples.max() ?? -1)")
}

/// Spec §7. Interruption re-targets from the current value and velocity rather
/// than restarting — a spring handed a non-zero initial velocity does not begin
/// from rest.
@Test func aSpringHandedInitialVelocityDoesNotStartFromRest() {
    let s = Animation.spring(duration: 0.5, bounce: 0.2)
    let atRest = s.value(at: 0.02, from: 0, to: 100, initialVelocity: 0).value
    let moving = s.value(at: 0.02, from: 0, to: 100, initialVelocity: 500).value
    #expect(moving > atRest,
            "inbound velocity must carry the value further; \(moving) vs \(atRest)")
}

/// `withAnimation` parks a transaction and clears it. The clearing half is what
/// stops every later frame animating.
@MainActor
@Test func withAnimationParksATransactionForTheDurationOfItsBodyOnly() {
    #expect(Animation.pendingTransaction == nil)
    var sawInside: Animation?
    withAnimation(.linear(duration: 1)) {
        sawInside = Animation.pendingTransaction
    }
    #expect(sawInside == .linear(duration: 1))
    #expect(Animation.pendingTransaction == nil, "the transaction must not outlive its body")
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --no-parallel --filter AnimationTests 2>&1 | tail -20`
Expected: the file does not compile — `cannot find 'Animation' in scope`.

- [ ] **Step 3: Implement `Animation`**

Create `Sources/MetalUI/Animation.swift`. Requirements, not a transcription — write the code:

- **`Animation` is a value type** carrying a case (`.duration(curve, seconds)` or `.spring(duration, bounce)`) and nothing mutable. It is `Equatable` so the transaction test above can compare one.
- **Duration curves** are unit-Bézier evaluations of the standard control points; `linear` is the identity. `timingCurve(x1, y1, x2, y2, duration:)` is the general form and the four named eases are it with fixed points. Solve the Bézier for `t` given `x` by bisection or Newton — say which and why in a comment.
- **Springs** take SwiftUI's `duration`/`bounce` spelling and convert internally to the damped-harmonic parameters. `bounce == 0` is critically damped; `bounce > 0` underdamped (overshoots); `bounce < 0` overdamped. **Derive the conversion in a comment** rather than transcribing constants.
- **`isFinished` for a spring needs a threshold on BOTH position and velocity**, and spec §7 forbids picking one because it looks settled. Derive it from a stated criterion — a displacement below half a device pixel at a plausible scale factor, and a velocity that cannot move it more than that within one 120 Hz frame — and **write the derivation at the constant**. A reviewer will ask where the number came from.
- **`withAnimation`** stores into a `@MainActor static var pendingTransaction: Animation?` on `Animation`, runs the body, and restores the previous value (restore, not nil — so a nested `withAnimation` behaves).

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --no-parallel --filter AnimationTests 2>&1 | tail -20`
Expected: all seven PASS.

- [ ] **Step 5: MUTATION — declare a spring finished on position alone**

Delete the velocity term from the spring's `isFinished`.

Run the suite. Expected: `aSpringIsNotFinishedWhileItStillHasVelocity` FAILS. **Report the actual output.** If it stays green, the fixture's spring does not overshoot enough to have velocity at the target — that is a fixture defect, not a passing implementation, and `aBouncySpringOvershootsItsTarget` should have caught it. Say which. Restore.

- [ ] **Step 6: Run the full suite and commit**

Run the summed-total command from Global Constraints. Expected: **818** (811 + 7).

```bash
git add Sources/MetalUI/Animation.swift Tests/MetalUITests/AnimationTests.swift
git commit -m "feat: Animation — duration curves, springs, and the transaction

Pure curve maths plus a transaction store; no element, pass or Frame is
touched, so this is reviewable on its own terms.

A spring's isFinished tests BOTH position and velocity, because a spring at
its target with velocity in it is mid-overshoot rather than settled. The
threshold is derived from a stated perceptual criterion at the constant, not
picked."
```

---

### Task 2: the timebase

**Files:**
- Modify: `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift` — `displayLinkFired`
- Modify: `Tests/MetalUITests/AnimationTests.swift`

**Interfaces:** consumes nothing; changes what value reaches `Window.lastTick`.

Spec §2. `displayLinkFired` passes `displayLink?.timestamp` — when the **previous** frame was displayed. §4.4 of the binding spec mandates the **target presentation** timestamp.

- [ ] **Step 1: Confirm the defect yourself**

Run: `grep -rn "targetTimestamp" Sources/ Tests/` (expect nothing) and read `displayLinkFired`. Report both.

- [ ] **Step 2: Make the change**

`tick?(displayLink?.targetTimestamp ?? 0)`.

**Write a comment saying what it moves**: the only existing consumer is `ScrollView`'s indicator-fade age, which shifts by one frame interval — immaterial, unasserted, invisible. And say why the old value was wrong: an animation evaluated at `timestamp` is one whole frame interval behind where it will be when the frame is presented.

- [ ] **Step 3: Decide honestly whether this is testable here, and report either way**

`CADisplayLink` cannot be driven from a test in this repo — `FakePlatformWindow.simulateTick(timestamp:)` supplies whatever the test chooses, so no assertion can distinguish the two clocks. **Do not fake a test that appears to check this.** Either find a real observable and say what it is, or state plainly in your report and at the line that the change is unpinned and why, on the footing CLAUDE.md already uses for the display-link pause and `NSTrackingArea`.

- [ ] **Step 4: Full suite and commit**

Expected: **818**, unchanged. Goldens 87.

```bash
git add Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift
git commit -m "fix: the display link's target presentation timestamp, per spec 4.4

The callback passed CADisplayLink.timestamp — when the PREVIOUS frame was
displayed. Design spec 4.4 mandates targetTimestamp, which had never appeared
anywhere in Sources or Tests. Harmless while the only consumer was a
scroll-fade age; a uniform one-frame lag the moment animation reads the clock."
```

---

### Task 3: the shared helper

**Files:**
- Create: `Sources/MetalUI/AnimatedStyle.swift`
- Modify: `Tests/MetalUITests/AnimationTests.swift`

**Interfaces:**
- Consumes: `Animation` (Task 1); `StateTable` and `GlobalElementID.child(of:at:name:)`.
- Produces: `func animated(_ style: Style, _ decoration: Decoration, for id: GlobalElementID, pass: inout LayoutPass) -> (Style, Decoration)`, and the `$anim` slot name.

- [ ] **Step 1: Write the failing tests**

Append to `AnimationTests.swift` tests for: a field that differs under a transaction begins animating and reads an intermediate value on the next frame; the same field changed with **no** transaction snaps; `display` changed under a transaction snaps; a `Dimension.auto → .length` transition snaps; a `.pixels → .percent` transition snaps; and two elements animate independently.

**The interpolation rule generalises the spec's two stated cases and you should implement it as one rule:** `Length` has three cases (`.pixels`, `.rems`, `.percent`) and `Dimension` adds `.auto`. **Same case interpolates; different case snaps.** `.auto` carries no number and a percent has no basis at this point, so both fall out of the single rule rather than being special.

- [ ] **Step 2: Run to verify they fail. Step 3: Implement. Step 4: Run to verify they pass.**

The helper: read the `$anim` slot (`.child(of: id, at: 0, name: "$anim")`), compare each animatable field, start an animation where one differs **and** `Animation.pendingTransaction != nil`, advance every live animation to `pass.frame.timestamp`, substitute, and write the slot back.

Animatable and snapping field lists are spec §4 — **`aspectRatio` is not animatable**, and a comment at the list must say why.

- [ ] **Step 5: MUTATION — ignore the transaction and animate every difference**

Remove the `pendingTransaction != nil` condition. Expected: the "no transaction snaps" test FAILS. Report the real output; restore.

- [ ] **Step 6: MUTATION — interpolate across `Length` cases instead of snapping**

Expected: the `.pixels → .percent` test FAILS. If it stays green the fixture cannot express it. Report; restore.

- [ ] **Step 7: Full suite and commit.** Report the summed total.

---

### Task 4: wire the four registering sites

**Files:**
- Modify: `Sources/MetalUI/Box.swift` (`:79`), `Stack.swift` (`:102`), `ScrollView.swift` (`:270`, `:279`)
- Modify: `Tests/MetalUITests/AnimationTests.swift`

**Interfaces:** consumes `animated(_:_:for:pass:)` from Task 3.

**Spec §5, and read its correction block before starting.** An earlier draft claimed `Box.requestLayout` was the single site every styled layout flows through. **It is not** — `Row` and `Column` hold a `Box`, but `Stack` registers its own node, and `ScrollView` registers two. There are four sites.

- [ ] **Step 1: Re-enumerate the sites yourself**

Run `grep -rn "requestNode\|newLeaf" Sources/MetalUI/ | grep -v "///"`. **Report what you find.** If there are more than the four this plan names, that is the finding and the plan is stale — say so rather than wiring only the four.

- [ ] **Step 2: Write the per-site guard first**

One test case per registering site, asserting that a styled node from that site animates. Name it for the property — `everyRegisteringSiteAnimatesItsStyle` — on the model of `onClickIsLiveOnEveryConformerThatCanRegisterOne`, which exists because nothing can enforce that a conformer calls `registerHandlers`.

**This test must be red on arrival for every site**, and go green one site at a time as you wire them. Report the intermediate counts.

- [ ] **Step 3: Wire each site. Step 4: Run the guard to green.**

- [ ] **Step 5: MUTATION — un-wire one site at a time**

Four mutations, one per site. Each must redden exactly its own case of the guard and nothing else. **If un-wiring a site reddens nothing, that site's case is not reaching it** — report which, because that is the guard failing at its whole purpose. Restore after each.

- [ ] **Step 6: Full suite and commit.** Report the summed total.

---

### Task 5: `hasActiveAnimations` and the drive loop

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Window.swift`
- Modify: `Tests/MetalUITests/AnimationTests.swift`

**Interfaces:** consumes Tasks 1-4. Produces `Frame.hasActiveAnimations: Bool` and the widened guard.

M4 spec 1 deliberately did not declare `hasActiveAnimations` without a writer (ruling `RX-O`). This task introduces the property, its writer, the widened guard and the transaction hand-off **in one change**.

- [ ] **Step 1: Write the failing tests**

- The display link stays running while an animation is live and pauses on the frame **after** the last one ends — against `FakePlatformWindow.pauseCalls`, the recorder `ObservationTests` already uses.
- A frame with no animations reports `hasActiveAnimations == false`.
- An animation started inside `withAnimation` survives into the next frame build (the transaction hand-off works end to end).
- An animating element that vanishes and returns within the retention window **resumes** rather than restarting (spec §6's free consequence of `StateTable` tombstones).
- The four reserved slot names are mutually distinct — extend the existing `theThreeRetentionSlotsAreMutuallyDistinct` to four rather than adding a second test.

- [ ] **Step 2-4: Run red, implement, run green.**

The guard at `Window.swift:571` becomes `guard needsRedraw || hasActiveAnimations else { … }`.

- [ ] **Step 5: MUTATION — never clear `hasActiveAnimations`**

Expected: the pause test FAILS — the window never idles. **If it stays green, the idle criterion is not being observed** and that is the finding. Report; restore.

- [ ] **Step 6: MUTATION — widen the guard but never set the flag**

Expected: the "stays running while animating" half FAILS. The two mutations must redden **different** halves; if one reddens both, one half is proving less than it claims. Report; restore.

- [ ] **Step 7: Full suite and commit.** Report the summed total.

---

### Task 6: the record

**Files:**
- Create: `docs/superpowers/2026-09-03-animation-decisions.md`
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-08-24-metalui-design.md`

- [ ] **Step 1: Decisions doc.** Rulings prefixed `AN-` and **lettered** (`AN-A`, `AN-B`, …), matching this project's convention that a bare `AN-3` is a typo. Follow `2026-09-03-component-decisions.md`'s shape. At minimum: the transaction model and why no causality tracking is needed; the timebase fix and what it moved; the four-sites correction and the per-site guard it forced; the spring settling threshold **with its derivation**; the same-case-interpolates rule; `aspectRatio` deliberately excluded; and every mutation result **as observed**, not as this plan predicted.

- [ ] **Step 2: Correct design spec §4.4 in place.** It says `hasActiveAnimations` "is set when an animation is registered during `prepaint`" — check whether that is where it actually ends up being set, and if not, correct it with the original visible. It is also the section that mandated `targetTimestamp`; note that the code did not comply for five milestones and now does.

- [ ] **Step 3: `CLAUDE.md`.** An animation bullet beside the reactivity one; `$anim` added to the three reserved slot names with the collision risk stated as inherited; the timebase correction; the four registering sites and the guard; and the Build-section climb with the per-task figures **each task actually read**.

- [ ] **Step 4: Verify every claim by running it.** Every grep and count in the record — including the ones in this plan. Report anything that turned out wrong.

- [ ] **Step 5: Commit.**

---

## Expected final state

- Roughly **830** tests (811 plus this plan's additions — report the real number; do not carry this estimate into the record), 87 goldens, 34 guards, warning-free.
- `grep -rn "displayLink?.timestamp" Sources/` returns nothing.
- `grep -rn "hasActiveAnimations" Sources/` returns hits in both `Frame` and `Window`.
- `git diff --name-only master..HEAD -- Sources/MetalUILayout/` is **empty**.
- `aspectRatio` is not animatable and keeps its inert-table row.
- No Reduce Motion, no exit transitions, no transforms.
