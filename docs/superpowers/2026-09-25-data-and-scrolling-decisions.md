# Data and scrolling decisions (plan task 10, part 1)

Rulings for [`specs/2026-09-25-data-and-scrolling-design.md`](specs/2026-09-25-data-and-scrolling-design.md),
on `feat/data-and-scrolling` from `e7bc2e7`. Ids are **lettered**,
`DD-A`…`DD-M`; next unused is **`DD-N`**. A bare `DD-3` is a typo, not a
citation. **A round that appends a ruling moves this line in the same commit.**

**Status, 2026-09-25: DESIGNED, then CRITICISED AND REVISED** (the critic
round appended `DD-K`…`DD-M` and amended `DD-A`, `DD-B`, `DD-D`, `DD-F` and
`DD-G` in place, each amendment marked "critic round"). Plan task 10 is split in two by the
workflow that runs it: **part 1** (this doc) is `ForEach` and identified data,
a SwiftUI `Binding`, the `List`/`ScrollView` limitations that blank a layout,
and scroll position, indicators and programmatic scrolling; **part 2** (the
next run) is the common controls and selection, plus every item this doc
re-owns to it by name (`DD-J`). The plan's task 10 box stays **unticked** after
part 1.

**Evidence, cited below by arm id:**

- `docs/probes/swiftui-data-and-scrolling.swift` (**new**, this design): arms
  F0–F12 (`ForEach` identity), B1–B6 (`Binding`), L0–L3 (a `List` and a
  `LazyVStack` beside a header in a `ScrollView`), W0–W2 (wheel under
  `.disabled` — **no working positive control**, see `DD-I`), T0–T15 with T12b
  (`scrollTo(_:anchor:)`), P1–P2 (`scrollPosition(id:)`), I0–I5 (indicator
  visibility), and K2 (a typecheck: no `for` in a view builder). Script form and
  compiled form byte-identical (58 lines), exit 0, stderr empty, macOS 27.0
  (26A428), Apple Swift 6.4, screen locked. Output in its header.
- `docs/probes/swiftui-scrollviewreader-scope.swift` (**new**, the critic
  round): arms S0–S2 (a proxy's reach: S2, the key only under ANOTHER reader,
  moves nothing), S3–S5 (`scrollTo` compares keys by value, not description)
  and S6–S7 (two `ForEach` ids equal in description, different in value, are
  two elements). Script and compiled forms byte-identical (11 lines), exit 0,
  stderr empty, screen locked. Output in its header.
- **The critic round re-ran `swiftui-data-and-scrolling.swift`'s compiled
  form**: 58 lines, byte-identical to its header (`diff` empty), exit 0, stderr
  empty, screen locked.
- `docs/probes/swiftui-composition-identity.swift` — V6 and V10, which F9 and
  F2/F3 re-run with ids and agree with.
- The SDK's own interfaces (`SwiftUICore.swiftmodule`/`SwiftUI.swiftmodule`,
  `arm64e-apple-macos.swiftinterface`, Xcode-beta, macOS 27.0 SDK) for every
  public spelling ruled below: `Binding<Value>` (`init(get:set:)`,
  `constant(_:)`, `wrappedValue`, `projectedValue`, `init(projectedValue:)`,
  `subscript(dynamicMember:)`, `init<V>(_: Binding<V>) where Value == V?`,
  `init?(_: Binding<Value?>)`), `ForEach`'s three initialisers,
  `ScrollViewReader`, `ScrollViewProxy.scrollTo<ID: Hashable>(_:anchor:
  UnitPoint? = nil)`, `ScrollIndicatorVisibility`.
- Three scratch measurements of MetalUI at `e7bc2e7` (one throwaway test file
  through a real `Window`, run and deleted; the Record phase copies them to
  record §57):
  - **DD14** (divergence 14 through a real `ScrollView`): header 300, `List` of
    40 at `rowHeight` 28, viewport 112, one wheel to offset 300 → rows built
    **8…16** (9), where rows 0…3 are on screen. `needsRedraw` true after (the
    indicator fade).
  - **DD13** (divergence 13's effect): a `ScrollView { List }` of 100 rows, the
    window grown from 112 to 560 tall with no input → the first frame builds
    rows **0…5** (the stale 112 window), `needsRedraw` **false**, and the next
    `drawFrameIfNeeded()` builds **0 rows** (no frame is drawn) — rows 6…21 stay
    blank until some input.
  - The existing pins read as they say: `aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone`'s
    C2.4b arm (divergence 74) reads **2**; `aDisabledScrollViewStillScrollsOnTheWheel`
    (EV-Q) green.
- Baseline at `e7bc2e7` in this worktree: `swift build --build-system native
  --build-tests`, then `swift test --build-system native --no-parallel` →
  see the spec §1 (re-taken by the design session).

---

## DD-A — scope: the items addressed to plan task 10, and three lanes

**The collection** (grep for "task 10" over `docs/record/` and
`docs/superpowers/*.md` and `specs/`, 2026-09-25, filtered for plan task 10 —
the 2026-08 "Task 10"s are m-milestone tasks, not plan tasks). Every item is
in the spec's §2 audit table with its disposition; in summary:

| item | source | disposition |
|---|---|---|
| `ForEach`/identified data | plan task 10 text | **this run**, `DD-B` |
| divergence 74 (a `for` loop's dropped element keeps its state) | record §55; `ID-R` item 4 | **retires**, `DD-C` |
| a SwiftUI `Binding`, deleting the `KeyBinding` alias in the same change | plan note 2026-09-15; `EV-N` | **this run**, `DD-D` |
| `TextField`/`TextEditor` binding initialisers | the workflow's part-1 brief | **this run**, `DD-E` |
| divergence 14 (a `List` with a flow sibling above it is blank) | record §04; `MP-L` | **retires**, `DD-F` |
| divergence 13 (the window is one frame stale) | record §04 | **amended, kept**, `DD-F` |
| `ProposalScrollView` publishing a `ScrollContext`; its animation | `LR-BF`, `LR-BJ`, `LR-GG` | **disposed**, `DD-I` |
| wheel scrolling under `.disabled` | `EV-Q` | **unmeasured, kept**, `DD-I` |
| scroll position, indicators, programmatic scrolling | plan task 10 text | **this run**, `DD-G`, `DD-H` |
| two-axis scrolling | `CN-M`, `LR-BJ` | **part 2**, `DD-J` |
| divergence 54 (a `ScrollView` takes its cross axis from its parent) | `LR-BC`, `LR-GA` item 5 | **part 2**, `DD-J` |
| `List` semantics beyond layout: selection, non-uniform rows, scrolling itself, divergence 32 | `CN-Q` (containers doc) | **part 2**, `DD-J` |
| accessibility: scroll areas, scrolling to unrealised rows | `AB-` deferral table | **part 2**, `DD-J` |
| common controls (`Button` existence, `controlSize` consumers, divergence 76) | `EV-AE`, `EV-AF` | **part 2** (its own brief) |

**Three lanes, disjoint files** (the spec's §4 names every file):

1. **Lane 1 — `ForEach` and loop identity** (`DD-B`, `DD-C`): `ForEach.swift`
   (new), `ElementGroup.swift` and `ProposalElementGroup.swift` (the two
   `ArrayGroup` copies), `StateTable.swift`.
2. **Lane 2 — `Binding`** (`DD-D`, `DD-E`): `Binding.swift` (new),
   `State.swift`, `Keymap.swift`, `TextField.swift`, `TextEditor.swift`.
3. **Lane 3 — `List`/`ScrollView` and the scroll APIs** (`DD-F`…`DD-I`):
   `List.swift`, `ScrollView.swift`, `ProposalScrollView.swift`,
   `ScrollChrome.swift`, `Passes.swift`, `Frame.swift`, `Window.swift`,
   `ScrollViewReader.swift` and `UnitPoint.swift` (new).

Lanes run one at a time in the order 1, 2, 3: lane 3's `scrollTo` test of a
two-view `ForEach` item (3.10) needs lane 1's `ForEach`.

**Amended by the critic round (`DD-M` item 1):** lane 3 as designed carried
fifteen tests, two guards, three new public types and nine source files, while
lane 2 carried ten tests over five small files. **`DD-F` (the `List` origin,
the follow-up frame and the `ScrollerFrame` stack it needs — tests 3.1–3.5,
their ids kept) moves to lane 2**, which therefore also owns `List.swift`,
`ScrollView.swift`, `ProposalScrollView.swift`, `Passes.swift` and
`Frame.swift`'s scroller stack. Lane 3 then **edits** `List.swift` (the
pending-request scan), `Frame.swift` (the request match and resolution),
`ScrollView.swift` (the two enum cases) and lane 1's `ForEach.swift` (typed keys
while a request is pending, `DD-K`) on top of lane 2's commit. The lanes
are sequential, so the overlap costs no merge; a red during lane 3 is
attributed by commit (`git stash`/checkout lane 2's head and re-run), which is
what "disjoint" bought. Lanes 1 and 2 still share no file.

**What it costs if wrong.** A lane that needs another's file serialises the
two and a verifier cannot attribute a red to one lane; the spec lists every
file so the overlap is checkable before a lane starts.

---

## DD-B — `ForEach`: SwiftUI's three initialisers, one slot, one identity level per element

**Ruling.**

1. **The public surface is SwiftUI's**, spelled from the SDK interface:

   ```swift
   public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: ElementGroup>: ElementGroup {
       public var data: Data
       public var content: (Data.Element) -> Content
       public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                   @ElementBuilder content: @escaping (Data.Element) -> Content)
   }
   extension ForEach where ID == Data.Element.ID, Data.Element: Identifiable {
       public init(_ data: Data, @ElementBuilder content: @escaping (Data.Element) -> Content)
   }
   extension ForEach where Data == Range<Int>, ID == Int {
       public init(_ data: Range<Int>, @ElementBuilder content: @escaping (Int) -> Content)
   }
   extension ForEach: ProposalElementGroup where Content: ProposalElementGroup {}
   ```

   `@ElementBuilder` is the builder every MetalUI container already takes
   (SwiftUI's is `@ViewBuilder`). The two stored properties are public as
   SwiftUI's are. **Not in this run**: `ForEach(_: Binding<C>)` (SwiftUI's
   `@_disfavoredOverload` binding form) — it needs `Binding` to be a
   `MutableCollection` view, crosses lanes 1 and 2, and its natural consumer is a
   row of controls (part 2, `DD-J`).
2. **One structural slot for the whole `ForEach`** in its container's cursor
   space, exactly as a `for` loop's `ArrayGroup` takes one (`ID-B`, probe F9:
   the trailing sibling keeps its state when the `ForEach` shrinks).
3. **One identity level per element: a scope named by the element's id**,
   `GlobalElementID.child(of: slot, at: offset, name: ElementID(String(describing: key)))`,
   under which the element's content numbers from 0 — the shape a `GridRow`
   already has (`GR-`, "the one proposal group with an identity level of its
   own"). State therefore follows the id through a reorder (F1) and a middle
   removal (F6), stays with the position when the ids are indices (F5), and is
   scoped to its `ForEach`: an element moved into another `ForEach` is new
   (F10). An element of two members is one scope (F8). The scope is **noted**
   like every named id (`StateTable.noteNamed(_:at:)`, `ID-R` item 3 — a new
   minting site, so a new copy with its own pin).
4. **Keys** are described into the name with `String(describing:)` as
   `List`'s rows already are. **Superseded in part by `DD-L` (critic round):**
   the design said two distinct keys that describe the same string "share one
   identity" and that the dedupe "never drops them" — which put two members at
   one `GlobalElementID`, the aliasing `ID-F` exists to repair, and answered a
   SwiftUI question (S6: SwiftUI evaluates both) without an arm. `DD-L` rules
   the dedupe on the name as well as the value.
5. **A later element whose id (by value, or by minted name — `DD-L`) already
   appeared this frame is not produced**
   (probe F7: with two elements sharing an id, the second's content is never
   evaluated). SwiftUI's own documentation calls duplicate ids undefined; the
   probe is what it does, and producing both would put two members at one id —
   the aliasing `ID-F` exists to repair.
6. **The content closure runs during layout, once per element per frame, and
   what it built is threaded to prepaint and paint in the group layout** — not
   re-run and not stored on `self`, the rebuilt-between-phases hazard
   `EitherGroup.mismatch` documents.

**Why an identity level rather than naming the members.** A member-naming
`ForEach` (each element's single member renamed to the key, as `.id` does)
cannot express an element of two members — both would take one name — and
SwiftUI's F8 keeps the two members' states apart. The level costs one id
component per element; no existing id path moves, because `ForEach` is new.

**Evidence.** F0–F11 and K2 (probe header); the SDK interface for spellings.

**What it costs if wrong.** An id path is permanent user-visible state
identity: if a later task needs members named directly, every `ForEach`
element's state resets once on upgrade (a migration note, never silent).

---

## DD-C — an element a loop stops producing is reset (divergence 74 retires, for `ForEach` and `for` alike)

**Ruling.**

1. **Fixed to SwiftUI's answer** (`EP-5`): an element a `ForEach` stops
   producing starts fresh if it comes back — Identifiable data (F2), a range
   (F3), an element of two members (F8). **A `for` loop gets the same answer**:
   SwiftUI has no `for` in a view builder (K2), and its nearest spelling,
   `ForEach` over a range, resets (F3); an unnamed `for` iteration's identity is
   its position, which is exactly `ForEach(0..<n)`'s. Divergence 74 retires.
2. **The mechanism — one rule, both loops.** A loop notes its slot and the
   inner-cursor extent it consumed, `StateTable.noteLoop(_ slot:, extent:)`,
   from each of its three minting copies: `ArrayGroup`'s untyped and typed
   `requestGroupLayout`s and `ForEach`'s (and its typed copy — four calls, each
   pinned on its own). At `sweep()`, for every slot noted **this** frame:
   - **positional** children of the slot at an index at or past this frame's
     extent and below last frame's (a tail an unnamed `for` loop dropped) are
     reset, the child's own id included;
   - **named** children the slot held last frame (`previousNamedPositions`
     whose parent is the slot) that this frame produced **nowhere** are reset —
     a `ForEach` element dropped anywhere, a `for` iteration carrying `.id()`
     dropped at the tail. (A name whose position a *different* name now holds
     was already departed by `ID-R`; the loop rule adds the positions nothing
     evaluates, which `ID-R` item 4 left out.)

   Both go through the one reset pass `ID-R` item 8 built
   (`resetQueuedEntries`), `$focus`/`$ax` exempted as there.
3. **Only an evaluated loop resets.** A loop inside an element that is not
   produced, or inside an `if` that went false (whose own `noteAbsent` already
   resets everything under it), notes nothing; when it is evaluated again with
   no previous extent recorded, nothing is compared. **Only the loop's direct
   children are considered**: a `List` inside a surviving element keeps
   `TB-AH`'s retention for its rows (which are not the loop's children), and
   `List`'s own rows are not a loop (`ListRows` builds them; `noteWindowedParent`
   is unchanged).
4. **Migration note (user-visible, ruled):** a `for` loop's iteration, or a
   `ForEach` element, that disappears and returns now has fresh `@State`, a
   fresh scroll offset and fresh `$anim` slots — where until this change it got
   its old ones back. Focus and the accessibility node are kept. Keep durable
   values in data, as `List`'s doc already asks.

**Why not leave the `for` loop alone.** Divergence 74 is *the `for` loop's*
row (record §04), and its retirement is what the workflow asked for. A `for`
loop that retained while `ForEach` reset would put two answers to one question
in one framework, with no SwiftUI spelling to arbitrate for the `for` side.

**Evidence.** F2, F3, F8 (and V10); DD's scratch reading of C2.4b (2).

**What it costs if wrong.** A caller who relied on a shrunk-then-regrown loop
keeping its state (the retained behaviour, pinned as a divergence, never
documented as a feature) sees it reset. The sweep does one extra pass over
`previousNamedPositions` per frame in which a loop was noted — measured by the
lane's work counter, not by wall clock.

---

## DD-D — `Binding<Value>`: SwiftUI's spelling, main-actor isolated; the `KeyBinding` alias is deleted

**Ruling.**

1. **The public surface** (SDK interface, less `Transaction`):

   ```swift
   @MainActor @propertyWrapper @dynamicMemberLookup
   public struct Binding<Value> {
       public init(get: @escaping @MainActor () -> Value,
                   set: @escaping @MainActor (Value) -> Void)
       public static func constant(_ value: Value) -> Binding<Value>
       public var wrappedValue: Value { get nonmutating set }
       public var projectedValue: Binding<Value> { get }
       public init(projectedValue: Binding<Value>)
       public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> { get }
       public init<V>(_ base: Binding<V>) where Value == V?
       public init?(_ base: Binding<Value?>)
   }
   extension State { public var projectedValue: Binding<Value> { get } }
   ```

2. **Semantics, each from an arm.** `$state` reads and writes the owner's state,
   through any number of `@Binding` hops (B1); `.constant` ignores a write
   (B2); a key-path binding writes one field and leaves the rest (B3);
   `init(get:set:)` calls the setter once per write (B4 — the getter count is
   not specified: SwiftUI's own reads 3 for two reads and a write, and nothing
   should depend on it); `init?(Binding<Value?>)` is nil over nil and writes
   through over a value, and `init(Binding<V>)` as `V?` **ignores** a nil write
   (B5); a binding kept after its body ran reads and writes the **current**
   state — live, not a snapshot (B6). An unwrapped binding whose base later
   goes nil returns the last non-nil value it read (unprobed; SwiftUI traps on
   a related shape, measured while writing B5 and not made an arm).
3. **`State.projectedValue` goes through the box**, so a write resolves the
   slot at call time: the dispatching occurrence during input (`ID-F`), the
   last-bound one outside it (divergence 71, unchanged).
4. **Main-actor isolated, where SwiftUI's is nonisolated and `Sendable` with
   `@isolated(any)` closures.** `State` is `@MainActor` in MetalUI and a
   binding's whole job is to reach it; `Element`, `Component` and every handler
   are main-actor already. **Divergence 78, added**: a `Binding` cannot be
   created or read off the main actor. Pinned by guard G2.3.
5. **No `transaction`/`animation(_:)`** on `Binding`: they are transaction
   semantics, **plan task 13**'s; adding them later is additive.
6. **The deprecated `typealias Binding = KeyBinding` is deleted in the same
   change** (`EV-N`: a module cannot hold both), with its guard
   `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding` (a
   retirement row). `Binding("m", ToggleModal())` now fails to typecheck
   (guard G2.1) — the source break `EV-N` announced a task ahead.
7. **(Critic round.) A binding write is a `@State` write** — `$state`'s
   setter is `State.wrappedValue`'s, so it dirties the window and fires
   `onWrite`. `@State`'s rule carries over unchanged: **write through a binding
   from input, never from a phase** (a phase-time write keeps the display link
   awake). `TextField`/`TextEditor`'s binding initialisers write from the edit
   dispatch, which is input. No new mechanism; stated so a reviewer does not
   read `Binding` as a second, unguarded path.

**Evidence.** B1–B6; the SDK interface; `EV-N`.

**What it costs if wrong.** An external keymap still spelled `Binding(…)`
stops compiling, as `EV-N` said it would. If a later task wants SwiftUI's
nonisolated `Binding`, relaxing `@MainActor` is additive for callers; the
reverse would not be.

---

## DD-E — `TextField` and `TextEditor` gain binding initialisers; nothing else about them moves

**Ruling.** `TextField(_ placeholder: String, text: Binding<String>)` and
`TextEditor(_ placeholder: String = "", text: Binding<String>)`, each
forwarding to the controlled initialiser with `text: binding.wrappedValue` and
`onChange: { binding.wrappedValue = $0 }`. SwiftUI spells these two
(`TextField(_:text:)`, `TextEditor(text:)` — compiled in the probe's `Shapes`);
MetalUI's `TextEditor` keeps its placeholder parameter, defaulted, as its
controlled initialiser already has. The controlled initialisers, the editing
table, `Window.editedText`, caret offsets and every pixel are unchanged
(`TI-`, must-not-move). A field bound to `.constant` shows its text and drops
every edit.

**Why cheap.** The element already rebuilds each frame from its `text` and
reports each edit through `onChange`; a binding is exactly that pair.

**What it costs if wrong.** Nothing a controlled caller can see: both
initialisers build the same element (test 2.10 compares the scenes).

---

## DD-F — a `List` windows against its own origin, and asks for one more frame when its window went stale

**Ruling.**

1. **Divergence 14 retires.** `MP-L`'s blocker — `requestLayout` has no
   position — is met the way `ScrollState.viewportExtent` already meets the
   viewport: **last frame's measurement**. In `prepaint`, a `List` inside a
   scroller stores its origin within the scroller's content (its own bounds'
   origin minus the content node's, on the scroller's axis, both layout-space
   rects) in `StateTable` at **its own id** (`withState(id, …)`, `ScrollView`'s
   precedent — no new reserved name, so `theSevenRetentionSlotsAreMutuallyDistinct`
   is unmoved), and `visibleRange` windows the rows that intersect
   `[offset − origin, offset − origin + viewport)` within `[0, count × rowHeight)`.
   With no stored origin (the list's first frame) it windows as today (origin
   0). **(Critic round.) This is a phase-time `StateTable` write, and
   deliberately not a "write from a phase" in `@State`'s sense**: `withState`
   raises no `isDirty` and fires no `onWrite` (the `AnimatedStyle` ruling H
   precedent, and `ScrollChrome.resolvedOffset`'s own prepaint write-back), so
   it cannot keep the display link awake; the only redraw a list asks for is
   item 3's explicit, self-limiting `requestAnotherFrame()`. The origin must
   **never** be written through `StateTable.write` — lane 2's test 3.4 is the
   pin that an unbounded frame asks for nothing. Probe L2 is the answer being matched: the rows on screen (0…3 at offset
   300 below a 300 header), which SwiftUI's lazy stack realises and MetalUI's
   `List` — its analogue inside a `ScrollView`, not SwiftUI's self-scrolling
   `List` (L0/L1, part 2) — did not (DD14: 8…16).
2. **The scroller publishes a prepaint frame for this.** `ScrollView` and
   `ProposalScrollView` push, around their content's prepaint, an internal
   `ScrollerFrame` (scroller id, axis, content-node origin, viewport bounds,
   resolved offset) on a `Frame` stack; `List` reads the innermost. **A
   `Deferred` resets it** (`PrepaintPass.deferred`), as it resets the layout
   context and the clip (`AP-I`) — a list in a portal has no scroller.
3. **One more frame when the window went stale, and only then.** In
   `prepaint`, the list computes the window this frame's fresh inputs (measured
   origin, this frame's viewport, the resolved offset) would give; when that
   window is **not contained** in the one it built, it calls
   `requestAnotherFrame()`. That closes divergence 13's *effect* (DD13: a grown
   viewport stayed blank until input) and a header whose height changed. A
   frame that built every row (the unbounded first frame, `MP-I`) contains any
   window and asks for nothing, so the frame loop's idle behaviour and `AB-X`'s
   capped retry are untouched; the next frame builds exactly the fresh window,
   so the request cannot repeat.
4. **Divergence 13 is amended, kept.** The first frame after a resize still
   windows against last frame's extent — the two rows of overscan are still the
   only cover for it — but the next frame is now drawn and correct.
5. **Unchanged**: `ScrollContext` and its publication (`LR-BF`), the
   unbounded escape hatches (no context, a horizontal one, zero viewport, zero
   `rowHeight`), row identity, `TB-AH` retention, `AB-X`'s rules, `MP-I`'s cold
   frame and the 100 000-row test.

**Evidence.** DD14, DD13; L2/L3.

**What it costs if wrong.** One frame of a stale window after a resize or a
header change, then correct; a second `requestAnotherFrame()` caller beside the
indicator fade — `Frame`'s doc that "nothing raises both" it and
`noteActiveAnimation()` still holds, because a list raises only the first.

---

## DD-G — programmatic scrolling is `ScrollViewReader` and `scrollTo(_:anchor:)`; scroll position stays state

**Ruling.**

1. **Surface** (SDK interface):

   ```swift
   public struct ScrollViewReader<Content: ElementGroup>: ElementGroup {
       public init(@ElementBuilder content: @escaping (ScrollViewProxy) -> Content)
   }
   extension ScrollViewReader: ProposalElementGroup where Content: ProposalElementGroup {}
   @MainActor public struct ScrollViewProxy {
       public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil)
   }
   public struct UnitPoint: Hashable, Sendable {
       public var x: Double; public var y: Double
       public init(x: Double, y: Double)
       // zero, center, leading, trailing, top, bottom, topLeading, topTrailing,
       // bottomLeading, bottomTrailing
   }
   ```

   `ScrollViewProxy` has **no public initialiser** (guard G3.2), as SwiftUI's.
   A reader takes **one slot with an identity level of its own** (`DD-B`'s
   shape), so its content numbers from 0 under it and a proxy's reach is its
   subtree. **(Critic round.)** The design asserted the reach without an arm;
   probe S0–S2 now measures it: with the key only under another reader, a
   proxy moves nothing (S2).
2. **Semantics, each from an arm.** The target is **the first element recorded
   at or under a name equal to `String(describing: id)`** within the reader's
   subtree (keys compared by value, `DD-K`) — a `.id`'d element (T13) or a `ForEach` element's **first** member
   (T12/T12b: 330, not the whole element's 340). With an anchor, the target
   lands at `minY − anchor.y × (viewport − height)` on a vertical scroller
   (`x`/`width` on a horizontal one): `.top` 300, `.center` 265, `.bottom` 230,
   `y: 0.25` 282.5 (T1–T3, T9, T11). With **no** anchor it scrolls the least
   distance: below → bottom-aligned (230), visible → unmoved (0), above →
   top-aligned (60) (T4–T6). The offset is clamped to the content (T7). An
   unknown id does nothing, and the request does not persist (T8). An
   unrealised `List` row is reachable (T15; `List` computes its rect from its
   index, rows being uniform). **Only the nearest enclosing scroller** of the
   target moves (T14).
3. **Mechanism.** `scrollTo` enqueues a request (scope, key, anchor) on a
   window-owned queue the proxy holds weakly, and dirties the window. The next
   frame's prepaint resolves it: `Frame.recordElementBounds` (already called
   at the four element-bounds sites) matches a pending key against the id's
   own component and its ancestors up to the reader's scope, taking the first
   match and the innermost `ScrollerFrame` (`DD-F` item 2) at that moment;
   `List.prepaint` resolves a key among its data (by value, `DD-K`). After prepaint the frame
   writes each resolved scroller's `ScrollState.offset` (`withState`, as
   `applyScroll` does) and calls `requestAnotherFrame()`; unresolved requests
   are dropped. The request is visible one frame after it is made — the frame
   that resolves it paints the old offset.
4. ~~Keys are compared by description~~ — **superseded by `DD-K` (critic
   round)**: SwiftUI compares by value (S3–S5), and so does MetalUI.
5. **Not in this run**: `scrollPosition(id:)` — the two-way binding reports
   nothing for a platform scroll (P2) and its set path scrolls the least
   distance (P1, the nil-anchor rule already delivered); it needs lane 2's
   `Binding` and a "topmost visible element" query, and is part 2's (`DD-J`).
   Animated scrolling (`withAnimation { proxy.scrollTo }`) snaps: transaction
   semantics, **plan task 13**.
6. **Scroll position, specified**: a scroller's offset is `StateTable` state at
   its own id — kept across frames, reset when an evaluated conditional
   removes the scroller (`ID-C`) or a loop drops it (`DD-C`), clamped on read
   and written back in prepaint (`ScrollChrome`), moved by the wheel
   (`applyScroll`) and by `scrollTo`. Unchanged except for the second writer.

**Why `ScrollViewReader` rather than `scrollPosition(id:)`.** It works with
every scroller shape the probe tried — plain, lazy, `List`, horizontal, nested
(T1–T15) — is called from a handler, which is MetalUI's input model ("write
from input"), and needs neither `Binding` nor a scroll-target layout. P1/P2
show the binding form's report half doing nothing offscreen.

**What it costs if wrong.** A caller who expects the scroll in the same frame
sees it one frame later (not observable at 60 Hz, and SwiftUI's is also
asynchronous). (The design's description-collision cost is gone with `DD-K`.)

---

## DD-H — indicator visibility gains `.visible` and `.never`, each with its measured macOS behaviour

**Ruling.** `ScrollIndicatorVisibility` gains `case visible` (behaves as
`.automatic`: the fading overlay thumb) and `case never` (behaves as `.hidden`:
nothing painted, nothing requested). On overlay scrollers SwiftUI leaves the
`NSScrollView` identical under `.automatic` and `.visible`, and removes the
scroller under `.hidden`, `.never` and `showsIndicators: false` alike (I1–I5).
The enum's `EP-5` note ("a third case would be inert") is superseded: the new
cases are SwiftUI's spellings with SwiftUI's macOS answers, not stored-but-
unread state. Under the "always show scroll bars" system setting SwiftUI may
distinguish them; that is **unmeasured** and MetalUI reads no such setting
(owner none). Public enum, new cases: `swift package clean` before re-taking
counts.

**What it costs if wrong.** An exhaustive `switch` over the enum in a caller
stops compiling (two new cases). If the system setting does distinguish them, a
later task adds the reading without changing either spelling.

---

## DD-I — `ProposalScrollView`'s `ScrollContext` and animation; wheel scrolling under `.disabled`

**Ruling.**

1. **`ProposalScrollView` joins the prepaint scroller stack** (`DD-F` item 2) —
   `scrollTo` and a future reader need it — **and still publishes no layout-time
   `ScrollContext`**: `LR-BF`'s reason stands, since nothing that windows can be
   a `ProposalScrollView`'s content (`List` is not a `ProposalElementGroup`).
   Re-owned to whoever adds a windowed proposal element (the lazy stacks,
   `GR-L`'s G2); not a part-2 item.
2. **"Its animation" is closed as vacuous**: neither scroll type has an
   animatable surface of its own (`ScrollView`'s two animated styles are empty
   and discarded; `ProposalScrollView` has no `Style`), and the offset snaps on
   both. An animated offset is transaction semantics — **plan task 13**.
3. **Wheel scrolling under `.disabled` is unmeasured in SwiftUI, and MetalUI's
   answer is kept.** W0 (the enabled control) read 0 under five delivery
   strategies with the screen locked, so W1/W2 mean nothing; the only reading is
   indirect — `.disabled(true)` leaves the AppKit hit chain reaching the
   hosting scroll view unchanged. MetalUI's disabled `ScrollView` still scrolls
   (`EV-E`: scroll regions are outside the gate), pinned by
   `aDisabledScrollViewStillScrollsOnTheWheel`. **A human look is owed** (an
   unlocked screen, a trackpad, a SwiftUI `ScrollView { … }.disabled(true)`):
   the Record phase adds the row to record §03.

**What it costs if wrong.** If SwiftUI's disabled scroll view does not scroll,
MetalUI's differs until the look is taken; the fix is moving
`registerScrollRegion` inside the gate, one line with a pinned test to invert.

---

## DD-J — re-owned to part 2, and elsewhere

| item | why not part 1 | owner |
|---|---|---|
| common controls, `controlSize`'s consumers (divergence 76), a `Button` control's existence | the brief's split | plan task 10 part 2 |
| selection (`List(selection:)`, and the controls' selection) | the brief's split | part 2 |
| `List` scrolling itself and answering greedily (L0/L1, K6), non-uniform rows, `List { ForEach }` | changes `List`'s layout answer and the demo; wants selection beside it | part 2 |
| divergence 32 (`List` publishes a table whatever its role) and accessibility scrolling to unrealised rows | `List` semantics, with the above | part 2 |
| two-axis scrolling (`CN-M`) and divergence 54 (the cross axis) | reshapes `ScrollView`'s axis API and moves every legacy `ScrollView`'s cross axis — a pixel-moving change of its own | part 2 |
| `scrollPosition(id:)` | needs `Binding` (lane 2) and a topmost-element query; P1/P2 | part 2 |
| `ForEach(_: Binding<C>)` | crosses lanes 1 and 2; its consumer is a row of controls | part 2 |
| `Binding.transaction`/`animation(_:)`, animated `scrollTo` | transaction semantics | plan task 13 |
| a layout-time `ScrollContext` from `ProposalScrollView` | no windowed proposal element (`DD-I` 1) | the lazy stacks (`GR-L`'s G2); unscheduled |
| a `Hashable` `.id(_:)` overload | additive; description keys work | none |
| `.visible` vs `.automatic` under the "always show scroll bars" setting | unmeasured, no setting read | none |

---

## DD-K — `scrollTo` compares keys by value, as SwiftUI does (critic round)

**Ruling.** A `scrollTo(id)` request carries `AnyHashable(id)`. It matches:

- a **`ForEach` element scope** whose key `AnyHashable(key) == request`;
- a **`List` row** (realised or not) whose `AnyHashable(datum.id) == request`;
- any other **named** component (`.id(_:)`, which takes a `String`, `ID-G`)
  when `request == AnyHashable(name)` — so `scrollTo("x")` reaches `.id("x")`
  and `scrollTo(10)` does **not** reach `.id("10")`.

**Mechanism.** While the frame has a pending request (and only then — a
`Frame` flag read once per group), `ForEach` notes each element scope's typed
key and `List` each realised row's datum id in a per-frame
`[GlobalElementID: AnyHashable]`; `recordElementBounds`' ancestor walk looks an
id up there first and falls back to the `String` name. With no request pending
nothing is noted, so steady frames pay one flag read per loop (lane 1's test
1.15's counters must not move).

**Evidence.** S3 (`.id("10")` reached by `"10"`, 250; not by `10`, 0), S4
(`.id(10)` not reached by `"10"`, reached by `10`), S5 (a `ForEach` key `0`
reached by `0`, not by `"0"`). The design's description rule (`DD-G` item 4)
answered this without an arm and would have been a divergence.

**Test.** Lane 3's 3.16, `scrollToComparesKeysByValue` (S3–S5's three shapes).
**Mutation M3p**: match by `String(describing:)` — reddens 3.16's negative arms.

**What it costs if wrong.** Nothing measured; a caller who relied on
description matching never existed (the API is new). A `.id` taking any
`Hashable` stays additive (owner none).

---

## DD-L — a `ForEach` id colliding in description with an earlier one is not produced; divergence 79 (critic round)

**Ruling.** A `ForEach` element is **not produced** when its id's **value** or
its **minted name** (`String(describing: key)`) already appeared in this
`ForEach` this frame. SwiftUI evaluates both elements of ids equal in
description but different in value (S6: `AnyHashable(1)`, `AnyHashable("1")`),
and MetalUI cannot give them two identities: `ElementID` is a `String` (`ID-G`),
and producing both would put two members at one `GlobalElementID` — the
aliasing `ID-F` repairs for one element placed twice, and which here would be
silent. **Divergence 79, added** (pinned wrong on purpose): *a `ForEach` whose
ids collide in description produces only the first of them; SwiftUI produces
both.* The `List` rows already carry the same collision (its type doc) and are
not changed here.

**Evidence.** S6/S7 (`docs/probes/swiftui-scrollviewreader-scope.swift`); F7
for equal values.

**Test.** Lane 1's 1.16,
`aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst` (divergence 79's
pin): ids `AnyHashable(1)`, `AnyHashable("1")` → one node, the first element's
content. **Mutation M1l**: the name half of the dedupe removed — 1.16 reddens
(two nodes, or `ID-F`'s aliasing counter moves); 1.8 stays green (equal values
are still caught by the value half), which is what makes the two halves
separately pinned.

**What it costs if wrong.** A caller with such ids loses the second element
where SwiftUI shows it; the fix (type-qualified names) changes every `ForEach`
id path and so needs its own migration note — not taken now.

---

## DD-M — the critic round: fixes, and the attacks rejected

**Fixed** (each amended in place above or in the spec):

1. **Lane balance** — `DD-F` moved to lane 2 (`DD-A` amendment). Counts in the
   spec §6 re-derived.
2. **Two SwiftUI claims without an arm** — a proxy's reach (`DD-G` item 1,
   now S0–S2) and description-colliding `ForEach` ids (`DD-B` item 4, now S6,
   `DD-L`). **One claim contradicted by its arm's neighbour**: key matching by
   description (`DD-G` item 4) — S3–S5 show SwiftUI compares by value; `DD-K`.
3. **A mis-cited arm** — the spec's test 3.9 asserted 4500 for a `List` "(T15)",
   but T15 reads **3610** (SwiftUI's `List` rows are not 30 tall). The 4500 is
   T10's rule applied to MetalUI's uniform `rowHeight`; T15 is evidence only
   that an unrealised `List` row is reachable. Re-cited.
4. **Phase-time writes stated** — `DD-D` item 7 (a binding write is a
   `@State` write: input only) and `DD-F` item 1 (the origin through
   `withState`, never `write`).
5. **Test 3.13's scope arm could not separate** — both readers held the key,
   so a first-match-anywhere implementation that happened to find A's first
   passed. It gains S2's arm (the key only under reader B; A's proxy moves
   nothing), and mutation M3m is re-aimed at that arm.

**Rejected, with reasons** (the workflow brief says to record a rejection as
an "`LR-`" ruling; `LR-` is the engine track's prefix in another doc this
branch may not edit, so they are recorded here under `DD-`):

- *"Wheel under `.disabled` must be probed now."* The lock probe read
  `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` again at the critic
  round; W0's positive control cannot pass while locked. `DD-I` 3 stands (kept,
  human look owed).
- *"`.visible`/`.never` are inert synonyms (`EP-5`)."* They are SwiftUI's
  spellings with SwiftUI's measured macOS behaviour (I1–I5), not stored-but-
  unread state; `DD-H` stands.
- *"The alias deletion breaks a caller."* Grep over `Sources`, `Tests`,
  `Backends` and `Experiments` finds the alias, its doc line and its one guard
  only; nothing else spells `Binding(` for a key.
- *"`ForEach`/`ScrollViewReader` regress the one-megabyte-thread budget."* No
  production tree uses either (no demo source changes, spec §5), so
  `everyProductionTreeBuildsOnAOneMegabyteThread` measures nothing new; the
  lanes still run it.
- *"Part-2 creep."* `ScrollViewReader` is programmatic scrolling (part 1's
  text); `scrollPosition(id:)`, `ForEach(Binding)`, selection and controls are
  all in `DD-J`. No change.

