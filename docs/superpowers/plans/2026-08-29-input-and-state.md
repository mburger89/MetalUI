# `@State`, Hit Testing and Input Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the framework interactive — `@State` for cross-frame values, a general hitbox list with hover and active, and focus-driven keymaps dispatching typed actions — ending in a working counter demo.

**Architecture:** `@State`'s storage and key already exist (`StateTable` keyed by `GlobalElementID`); the wrapper is a `final class` box seeded through `Mirror`, whose copies share it. Hitboxes generalise `Frame.scrollRegions`, which is already a hitbox list in miniature, so scroll becomes one payload among several rather than a parallel mechanism. Focus and keymaps sit on top, registered in prepaint alongside hitboxes.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, AppKit, Metal. macOS.

**Spec:** `docs/superpowers/specs/2026-08-29-input-and-state-design.md`

## Global Constraints

- **Read the test summary line, never the exit status.** `swift test --no-parallel`, unfiltered. Baseline at plan start: **609 tests**.
- **No golden may move. 81 today.** Input touches no layout, so a moved golden means something reached the engine that should not have — **STOP and report, do not regenerate.**
- Build warning-free, **including `MetalUIDemo`** — no test target imports it, so only `swift build` catches a broken demo.
- **Any count a later loop indexes on must be `try #require`, not `#expect`** — `#expect` records and continues, so a short array sends the next loop past its own end and truncates the suite with no summary line.
- **Performance properties are asserted as counts, never wall-clock.** Committed timing baselines are machine-specific and rot.
- **A mutation that reddens nothing is a broken instrument or it is the finding.** Prove the mutant behaves differently before banking a coverage gap.
- **Nothing may be keyed on a property name.** Declaration ordinal only (spec §2.3).
- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored pattern.
- Comments explain mechanism, not task or milestone history.
- **Stale-incremental hazard:** adding a stored property to a public struct crossing module boundaries has produced a `SIGSEGV` with no summary line, and an assertion whose *expected* value contained something its own source could not construct. Run `swift package clean` before debugging either as a logic bug. `InputEvent`, `KeyEvent` and `Frame` are all such types.
- If a plan step conflicts with what you measure, **STOP and report.**

---

### Task 1: The `State` wrapper and its slot id

Storage contract only. Seeding is Task 2; nothing reflects yet.

**Files:**
- Create: `Sources/MetalUI/State.swift`
- Test: `Tests/MetalUITests/StateTests.swift`

**Interfaces:**
- Consumes: `StateTable` (`Sources/MetalUI/StateTable.swift`), `GlobalElementID.child(of:at:name:)` (`Sources/MetalUI/ElementID.swift:76`), `ElementID.init(_:)`.
- Produces: `@propertyWrapper public struct State<Value>` with `init(wrappedValue:)`, `wrappedValue` (`get` / `nonmutating set`), and an internal `bind(to:id:slot:)` that Task 2 calls.

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func anUnboundStateReturnsItsInitialValueAndDiscardsWrites() throws {
    // An unbound wrapper must not trap — an element constructed outside a
    // frame is legal, and a trap there would make `List(data) { Row($0) }`
    // crash at the point the closure is *built* rather than run.
    let s = State(wrappedValue: 7)
    #expect(s.wrappedValue == 7)
    s.wrappedValue = 9
    #expect(s.wrappedValue == 7, "an unbound write has nowhere to go")
}

@Test
func aBoundStateReadsAndWritesTheTableUnderItsOwnSlotID() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let s = State(wrappedValue: 0)
    s.bind(to: table, id: owner, slot: 0)

    s.wrappedValue = 5
    #expect(s.wrappedValue == 5)

    let slotID = GlobalElementID.child(of: owner, at: 0,
                                       name: ElementID("$state0"))
    #expect(table.peek(slotID, as: Int.self) == 5)
}

/// Two slots on one element must not share an entry. The ordinal lives in the
/// NAME, not in `at:` — a name replaces a position rather than joining it
/// (`ElementID.swift:79`), so `at:` is ignored whenever a name is supplied.
@Test
func twoSlotsOnOneElementGetDistinctEntries() throws {
    let table = StateTable()
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let a = State(wrappedValue: 1), b = State(wrappedValue: 2)
    a.bind(to: table, id: owner, slot: 0)
    b.bind(to: table, id: owner, slot: 1)

    a.wrappedValue = 10
    b.wrappedValue = 20
    #expect(a.wrappedValue == 10)
    #expect(b.wrappedValue == 20)
}

/// A slot id can never collide with a positional child's, because positional
/// children carry no name.
@Test
func aSlotIDCannotCollideWithAPositionalChild() throws {
    let owner = GlobalElementID.child(of: nil, at: 0, name: nil)
    let slot0 = GlobalElementID.child(of: owner, at: 0, name: ElementID("$state0"))
    let child0 = GlobalElementID.child(of: owner, at: 0, name: nil)
    #expect(slot0 != child0)
}
```

- [ ] **Step 2: Run and confirm they fail**

```
swift test --no-parallel --filter StateTests 2>&1 | tail -3
```

Expected: compile failure — `State` does not exist.

- [ ] **Step 3: Implement**

```swift
/// A value that survives the fresh tree each frame, keyed by its element's
/// identity.
///
/// **Nothing durable is stored in the element struct.** The value lives in the
/// window's ``StateTable`` under a slot id derived from the element's own
/// ``GlobalElementID``; the wrapper holds only a box the framework seeds with
/// that location each frame. That indirection is what makes the wrapper
/// possible in public Swift at all: `Mirror` hands back *copies* of a struct's
/// stored properties, so it cannot write into them — but a copy shares the
/// same box.
@propertyWrapper
public struct State<Value> {
    final class Box {
        var table: StateTable?
        var slotID: GlobalElementID?
    }

    let box = Box()
    let initialValue: Value

    public init(wrappedValue: Value) { self.initialValue = wrappedValue }

    public var wrappedValue: Value {
        get {
            guard let table = box.table, let slotID = box.slotID else {
                return initialValue
            }
            return table.peek(slotID, as: Value.self) ?? initialValue
        }
        nonmutating set {
            guard let table = box.table, let slotID = box.slotID else { return }
            table.withState(slotID, initial: initialValue) { $0 = newValue }
        }
    }
}
```

Plus the binding entry point:

```swift
extension State {
    /// Seeds the box. Called by the framework once per frame per element.
    ///
    /// The ordinal goes in the NAME rather than in `at:` — a name replaces a
    /// position rather than joining it, so `at:` is ignored whenever a name is
    /// supplied, and a named slot cannot collide with a positional child.
    func bind(to table: StateTable, id: GlobalElementID, slot: Int) {
        box.table = table
        box.slotID = GlobalElementID.child(of: id, at: slot,
                                           name: ElementID("$state\(slot)"))
    }
}
```

`StateTable.withState` and `.peek` are `internal`; `State` lives in the same module, so no access change is needed. **Verify that before assuming it** — if `State` must be public and `StateTable` is not, report rather than widening `StateTable`'s access.

- [ ] **Step 4: Run and confirm they pass, then the full suite**

**No golden may move.**

- [ ] **Step 5: Mutate**

Change `"$state\(slot)"` to a constant `"$state"`. Confirm `twoSlotsOnOneElementGetDistinctEntries` reddens. Revert; confirm `git diff --stat Sources/` is empty.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/State.swift Tests/MetalUITests/StateTests.swift
git commit -m "feat: State wrapper backed by the state table"
```

---

### Task 2: Per-type reflection, seeding at both sites, and marking

**Files:**
- Create: `Sources/MetalUI/StateReflection.swift`
- Modify: `Sources/MetalUI/ElementGroup.swift:107-115` (`Element`'s default `requestGroupLayout`)
- Modify: `Sources/MetalUI/Frame.swift` (`render`, around the root's `requestLayout`)
- Modify: `Sources/MetalUI/StateTable.swift` (a mark-without-read entry point)
- Test: `Tests/MetalUITests/StateTests.swift`

**Interfaces:**
- Consumes: `State.bind(to:id:slot:)` from Task 1.
- Produces: `StateBinder.bind(_ element:table:id:)` and `StateBinder.reflectionCount` (internal, for the count assertion); `StateTable.mark(_:)`.

**There are TWO seeding sites, and missing the second is the likely bug.** `Element`'s default `requestGroupLayout` (`ElementGroup.swift:111`) computes the id for every non-root element — but `Frame.render` calls the **root** element's `requestLayout` **directly** (`Frame.swift:630`), bypassing it entirely. A root element with `@State` would never be seeded. Both sites call the same helper.

- [ ] **Step 1: Write the failing tests**

```swift
private struct CounterElement: Element {
    @State var count = 0
    var elementID: ElementID?
    // Fill in the rest against the real `Element` protocol — read
    // `Sources/MetalUI/Box.swift` for the minimal conforming shape.
}

@Test
func stateSurvivesAcrossFramesForTheSameElement() throws { /* render twice, increment between */ }

/// The root element is seeded too. `Frame.render` calls the root's
/// `requestLayout` directly rather than through `requestGroupLayout`, so a root
/// with `@State` takes a different path from every other element.
@Test
func aRootElementsStateIsSeededAndSurvives() throws { /* … */ }

/// Reflection is per TYPE, not per instance. 40 elements of one type must
/// reflect once, not forty times, or this undoes the previous milestone.
@Test
func reflectionRunsOncePerTypeNotOncePerElement() throws {
    StateBinder.resetReflectionCount()
    // render a tree containing many CounterElements across two frames
    #expect(StateBinder.reflectionCount == 1)
}

/// Seeding MARKS, so a conditionally-read `@State` is not swept. `StateTable`
/// marks on access and `sweep()` drops the unmarked; without this a counter
/// whose value is read only on some frames silently resets.
@Test
func aStateThatIsNeverReadInAFrameIsStillNotSwept() throws { /* … */ }
```

Write the bodies against the real `Frame` API — `Tests/MetalUITests/DeferredTests.swift` is the established idiom for driving a real `Frame`, and `Frame.init` is `Frame(contentSize:scaleFactor:rootFontSize:stateTable:shapingCache:glyphAtlas:theme:timestamp:)`.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement the per-type cache**

```swift
enum StateBinder {
    /// Ordinals of the `State` wrappers a type declares, computed once.
    ///
    /// **Keyed by type, not by instance.** `Mirror` over every element every
    /// frame would cost more than the whole layout pass; a type's shape cannot
    /// change at runtime, so one reflection answers for every instance forever.
    nonisolated(unsafe) private static var shapes: [ObjectIdentifier: [Int]] = [:]

    nonisolated(unsafe) private(set) static var reflectionCount = 0

    static func resetReflectionCount() { reflectionCount = 0 }

    static func bind<E>(_ element: E, table: StateTable, id: GlobalElementID) {
        // Look up by type; reflect only on a miss.
        // On a hit with an empty ordinal list, return immediately — the common
        // case is an element with no `@State` at all.
    }
}
```

Fill in the body: on a cache miss, `Mirror(reflecting: element)` once, record which children are `State` wrappers and at which ordinals, then for each ordinal call `bind(to:id:slot:)` on that child cast to a bindable protocol.

**A `State<Value>` is generic, so a `Mirror` child cannot be cast to `State<Int>` without knowing `Value`.** Introduce an internal existential — `protocol BindableState { func bind(to:id:slot:) }` with `State` conforming — and cast to that. Verify this works before building on it; if it does not, report rather than reaching for `unsafeBitCast`.

- [ ] **Step 4: Seed at both sites**

In `ElementGroup.swift`'s default `requestGroupLayout`, immediately after `let id = …` and before `requestLayout`. In `Frame.render`, immediately after `let rootID = …` and before the root's `requestLayout`.

- [ ] **Step 5: Add `StateTable.mark(_:)`**

```swift
/// Mark without reading.
///
/// `withState` marks on access because an element that never touches its
/// state has nothing worth keeping. That rule is wrong for `@State`: a value
/// read only inside an `if` would go unmarked on frames where the branch is
/// not taken, and the next `sweep()` would discard it — a counter that
/// silently resets. Declaring `@State` is sufficient intent to keep it.
func mark(_ id: GlobalElementID) { marked.insert(id) }
```

Call it from `bind`, for every slot, every frame.

- [ ] **Step 6: Run the full suite**

**No golden may move.** Every existing test must pass — seeding runs for every element in the tree, so a mistake here is not local.

- [ ] **Step 7: Mutate — three of them**

(a) Skip the root seeding site → `aRootElementsStateIsSeededAndSurvives` must redden.
(b) Reflect per instance instead of per type → `reflectionRunsOncePerTypeNotOncePerElement` must redden.
(c) Drop the `mark` call → `aStateThatIsNeverReadInAFrameIsStillNotSwept` must redden.

Report what each reddened. Revert each; `git diff --stat Sources/` empty before the final run.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: seed @State by per-type reflection at both element sites"
```

---

### Task 3: Writing `@State` marks the window dirty

**Files:**
- Modify: `Sources/MetalUI/State.swift`, `Sources/MetalUI/StateTable.swift`
- Test: `Tests/MetalUITests/StateTests.swift`

Minimal invalidation — a flag the window consults. Real subtree dirty tracking is milestone 4 and stays there.

- [ ] **Step 1: Write the failing test**

```swift
@Test
func writingStateMarksTheTableDirtyAndReadingDoesNot() throws {
    // A read must NOT set the flag, or every frame invalidates itself and the
    // display link never pauses — which is milestone 4's exit criterion.
}
```

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement** — a `private(set) var isDirty` on `StateTable`, raised by the `nonmutating set` path only, cleared by whoever consumes it. Wire `Window` to consult and clear it after a frame.

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate** — set the flag on read as well. Confirm the "reading does not" half reddens.

- [ ] **Step 6: Commit**

---

### Task 4: Pin the existing scroll routing — a safety net, not TDD

**These tests must PASS on today's code.** They characterise behaviour before Task 7 puts hitboxes underneath it. **If one fails now, STOP and report** — that is a pre-existing defect and not this task's to fix.

**Files:**
- Test: `Tests/MetalUITests/ScrollRoutingTests.swift`

The clipping milestone shipped two intermittent defects here that no test caught and only a human found: an offset clamped on read but unbounded on write that banked 740 units of dead band, and a fade clock read from a display-link tick that freezes while the link is paused.

- [ ] **Step 1: Read what is already pinned**

Several properties are already covered. **Do not duplicate them** — a test that catches nothing its neighbour does not catch is not coverage. List what exists before writing anything.

- [ ] **Step 2: Add only what is missing**

At minimum, confirm these have a pin and add one where they do not: the topmost overlapping region wins and the other does not move; a `Deferred` scroller outranks one it paints over; within one layer the last-registered wins; overscroll does not bank.

- [ ] **Step 3: Run — they must all pass**

- [ ] **Step 4: Commit**

```bash
git commit -m "test: pin scroll routing before hitboxes subsume it"
```

---

### Task 5: The hitbox list

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Passes.swift`
- Create: `Sources/MetalUI/Hitbox.swift`
- Test: `Tests/MetalUITests/HitboxTests.swift`

**Interfaces:**
- Produces: `PrepaintPass.insertHitbox(_ bounds:opaque:) -> HitboxID`; `Frame.hitboxes: [(bounds, id, layer, opaque)]`; `Frame.topmostHitbox(at:) -> HitboxID?`.

Model it on `Frame.registerScrollRegion` (`Frame.swift:378`), which already intersects with `activeClip` and carries `activeLayer`. **Read it first.**

- [ ] **Step 1: Write the failing tests**

Cover: the topmost opaque hit wins; a non-opaque hitbox does not stop the walk; a hitbox is clipped by the active clip so a point outside the clip misses even when inside the bounds; layer beats registration order; a `Deferred` hitbox outranks one it paints over.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the full suite. No golden may move.**

- [ ] **Step 5: Mutate** — walk forward instead of reverse; ignore `opaque`; drop the clip intersection. Each must redden something. **If one reddens nothing, that is the finding** — report it and add the test.

- [ ] **Step 6: Commit**

---

### Task 6: Hover and active

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Window.swift`, `Sources/MetalUI/Passes.swift`
- Test: `Tests/MetalUITests/HitboxTests.swift`

**Hover resolves once, at the prepaint/paint boundary.** In `Frame.render` that is between the `prepaint` call (`Frame.swift:637`) and `glyphAtlas.beginFrame()` (`:653`). "Topmost wins" is not knowable until every hitbox is registered, so resolving during registration would give an answer that depends on declaration order.

- [ ] **Step 1: Write the failing tests**

Cover: `isHovered` is true for the topmost hitbox under the cursor **in the same frame it was registered** (§8.1's no-lag promise); a hitbox beneath an opaque one is not hovered; active is set on `mouseDown` and held until `mouseUp`; a press that leaves the hitbox and returns is still active.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement** — hover resolved at the boundary; active keyed by `GlobalElementID` on the window so it survives frames.

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate** — resolve hover *before* all hitboxes register; clear active on `mouseMoved` rather than `mouseUp`. Each must redden.

- [ ] **Step 6: Commit**

---

### Task 7: Scroll regions become hitboxes

**Files:**
- Modify: `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/ScrollView.swift`, `Sources/MetalUI/Window.swift`
- Test: `Tests/MetalUITests/ScrollRoutingTests.swift`, `Tests/MetalUITests/HitboxTests.swift`

**Task 4's pins must still pass, unchanged.** They are the whole reason this task is safe to attempt.

- [ ] **Step 1: Write the failing test — the limitation three milestones recorded**

```swift
/// A `Deferred` scrim swallows a wheel event that reaches it.
///
/// Before hitboxes, a non-scrolling `Deferred` registered no region at all, so
/// `Frame.scrollRegions` — the only hitbox list that existed — could not see it
/// and the list underneath scrolled through the modal.
@Test
func anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath() throws { /* … */ }
```

- [ ] **Step 2: Run and confirm it fails**

- [ ] **Step 3: Implement** — one list; a scroll region becomes a hitbox carrying a scroll payload. `Window.applyScroll` walks hitboxes.

**Do not disturb the offset arithmetic, the clamp, the write-back, or the axis mapping.** Those are where both shipped defects lived.

- [ ] **Step 4: Run the full suite — Task 4's pins especially**

- [ ] **Step 5: Mutate** — make the scrim non-opaque. Confirm the new test reddens and the old routing tests do not.

- [ ] **Step 6: Commit**

---

### Task 8: Handlers and `onClick`

**Files:**
- Modify: `Sources/MetalUI/Passes.swift`, `Sources/MetalUI/Box.swift`, `Sources/MetalUI/Window.swift`
- Test: `Tests/MetalUITests/InputDispatchTests.swift`

**Interfaces:**
- Produces: `StyledElement.onClick(_ handler: @escaping () -> Void)`; dispatch against the most recent frame's handler set (§8.2).

Bubble only — capture is out of scope (spec §3.5), because an opaque hitbox already swallows, which is the case §8.2 names for capture.

- [ ] **Step 1: Write the failing tests**

Cover: a click inside the bounds runs the handler; a click outside does not; the topmost of two overlapping handlers runs and the lower does not; a handler registered on frame N runs for an event arriving before frame N+1.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate** — dispatch to all hits rather than the topmost. Confirm the overlap test reddens.

- [ ] **Step 6: Commit**

---

### Task 9: The focus tree

**Files:**
- Create: `Sources/MetalUI/Focus.swift`
- Modify: `Sources/MetalUI/Passes.swift`, `Sources/MetalUI/Window.swift`
- Test: `Tests/MetalUITests/FocusTests.swift`

Focus handles register in prepaint, alongside hitboxes. The focused id is **window** state — focus is singular per window.

- [ ] **Step 1: Write the failing tests**

Cover: a key event dispatches to the focused node; an unhandled event bubbles to its ancestors in order; with nothing focused it reaches the window; focus survives a frame in which the focused element is rebuilt; focus on an element that stops being produced is cleared rather than dangling.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement**

- [ ] **Step 4: Run the full suite**

- [ ] **Step 5: Mutate** — bubble outermost-first instead of innermost-first. Confirm the ordering test reddens.

- [ ] **Step 6: Commit**

---

### Task 10: Actions, keymaps, context predicates, two-stroke

**Files:**
- Create: `Sources/MetalUI/Action.swift`, `Sources/MetalUI/Keymap.swift`, `Sources/MetalUI/KeyContext.swift`
- Modify: `Sources/MetalUIPlatform/InputEvent.swift` (`KeyEvent` gains `timestamp`), `Sources/MetalUIPlatform/AppKit/AppKitPlatform.swift`
- Test: `Tests/MetalUITests/KeymapTests.swift`

**`KeyEvent` gains a timestamp, and the reason is a bug this repo already shipped.** §8.3's two-stroke timeout is 1 second; `ScrollEvent` already carries a timestamp and its doc comment records why — the clipping milestone read a fade clock from the display link's last tick, **which freezes while the link is paused**, so an event arriving after idle computed a nonsense age. A keystroke timeout reading the display link reproduces that exactly. Source it from `NSEvent.timestamp`.

`KeyEvent` is a public struct crossing a module boundary — if the suite crashes or truncates with no summary line after this step, run `swift package clean` before debugging it as a logic bug.

- [ ] **Step 1: Write the failing tests for the predicate parser first**

It is a pure function with no engine coupling and carries the heaviest test load. Cover: a bare identifier; `key == value`; `&&`; `||`; `!`; precedence between `&&` and `||`; an unknown identifier is false, not an error; malformed input.

- [ ] **Step 2: Write the failing tests for matching and two-stroke**

Cover: matching uses `charactersIgnoringModifiers`, not `characters` (§8.3's Dvorak rule — a test with the two differing is what pins it); innermost context wins; an unmatched binding bubbles; a two-stroke sequence fires on the second stroke; **a prefix older than 1 second is DROPPED, not dispatched**; the timeout reads the event's timestamp, not a display-link tick.

- [ ] **Step 3: Run and confirm they fail**

- [ ] **Step 4: Implement**

- [ ] **Step 5: Run the full suite**

- [ ] **Step 6: Mutate** — match on `characters` instead of `charactersIgnoringModifiers`; dispatch the prefix on expiry instead of dropping it; match outermost-first. Each must redden.

- [ ] **Step 7: Commit**

---

### Task 11: The counter demo, documentation, human verification

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift`, `CLAUDE.md`
- Create: `docs/superpowers/2026-08-29-input-decisions.md` (`IN-` prefixed, **lettered**)

- [ ] **Step 1: Build the counter**

A `@State` count, a `+` and a `−` the mouse can click, hover feedback, and a keymap binding that increments. That is design spec §12's milestone-3 exit criterion.

The demo already gates its modal behind **M** and toggles theme on **space** — read `main.swift`'s `onInput` before adding a third path, and prefer moving the existing ad-hoc keys onto the new keymap if that is clean.

- [ ] **Step 2: Re-measure every number**

Suite count from the **summary line**; golden count; the demo's release frame cost, to confirm hitbox registration did not undo the previous milestone. **Re-measure rather than copying any number from this plan.**

- [ ] **Step 3: Update `CLAUDE.md`**

`@State` and the hitbox list both need entries. Two rows leave the declared-but-inert table if anything in it is now live — check rather than assume. Record any new divergence at the **next free label**: labels are 1-6 and 8-14, thirteen entries, highest 14, **7 permanently unused**, so the next is **15**. Verify the section's self-description afterwards.

Spec §8's three recorded risks need entries: the `$state` id collision, the vanishing-`if` adoption, and seeding-marks keeping entries `withState` would drop.

- [ ] **Step 4: Write the decisions doc** — `IN-` prefixed and lettered, each ruling with its reasoning **and what it costs if wrong**. Follow `docs/superpowers/2026-08-28-measure-performance-decisions.md`'s format.

- [ ] **Step 5: Human verification — do NOT claim it**

Build and confirm the demo launches. **Do not describe how it looks or feels.** Write the record so the criterion reads as **open**, naming what a human must report: whether clicking feels responsive, whether hover reads correctly, whether focus is visible, and whether the keymap binding works.

- [ ] **Step 6: Commit**

---

## Self-Review

**Spec coverage.** §2.2 wrapper → Task 1. §2.3 slot ids → Task 1. §2.4 marking → Task 2. §2.5 per-type reflection → Task 2. §2.6 dirty → Task 3. §2.7 hazard → Task 11 Step 3. §3.1 subsumption → Tasks 4 and 7. §3.2 registration → Task 5. §3.3 hover → Task 6. §3.4 active → Task 6. §4.1 actions → Task 10. §4.2 focus → Task 9. §4.3 predicates → Task 10. §4.4 timestamp → Task 10. §6 testing → throughout. §7 exit criteria → Tasks 7, 11.

**Known gap, stated rather than hidden.** Tasks 4–10 give test *names* and coverage requirements but not full bodies, because they depend on `Frame`'s real test idiom and on protocol shapes an implementer must read. Every such step names the file to copy the idiom from. This is a deliberate trade against the no-placeholders rule: **six API signatures written from memory on the previous milestone were wrong**, and a confidently wrong signature costs more than an instruction to go read the real one.

**Type consistency.** `State.bind(to:id:slot:)` (Task 1) called by `StateBinder.bind` (Task 2). `StateTable.mark(_:)` (Task 2) called from `bind`. `insertHitbox`/`topmostHitbox` (Task 5) used by Tasks 6, 7, 8. `KeyEvent.timestamp` (Task 10) used by the two-stroke timeout in the same task.

**One risk the plan cannot remove.** Task 2 touches the path *every* element takes. A defect there is not local, and the full suite is the instrument — which is why Task 2's Step 6 says so explicitly rather than relying on its own new tests.
