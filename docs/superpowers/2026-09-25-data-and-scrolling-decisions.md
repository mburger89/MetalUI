# Data and scrolling decisions (plan task 10, parts 1 and 2)

Rulings for [`specs/2026-09-25-data-and-scrolling-design.md`](specs/2026-09-25-data-and-scrolling-design.md),
on `feat/data-and-scrolling` from `e7bc2e7` (part 1, `DD-A`…`DD-P`), and for
[`specs/2026-09-26-controls-and-selection-design.md`](specs/2026-09-26-controls-and-selection-design.md),
on `feat/controls-and-selection` from `27b2fcc` (part 2, `DD-Q` onward). Ids
are **lettered**, `DD-A`…`DD-AI`; next unused is **`DD-AJ`**. A bare `DD-3`
is a typo, not a citation. **A round that appends a ruling moves this line in
the same commit.**

**Part 2 status, 2026-09-28: DELIVERED** (`DD-Q`…`DD-AB` designed;
`DD-AC` the critic round's fixes, amending `DD-S`, `DD-T`, `DD-U`, `DD-V`,
`DD-Y`, `DD-Z`, `DD-AA` and `DD-AB` in place; `DD-AD`/`DD-AE` the lanes' own
mutation tables and readings, `DD-AF`/`DD-AH` two verifier fix rounds,
`DD-AG` lane 3's own readings, `DD-AI` the Record phase's close — the
guard-count reading corrected and the optional-`@State` bug named divergence
85, owner plan task 15; evidence
`docs/probes/swiftui-controls-and-selection.swift`, new, arm ids cited as
`BT0`, `SA3`, `KY6c` …, re-run unlocked and extended with PK2/PK3 by the
critic round). **Plan task 10 is ticked** (record §58 §9). Part 1's status
follows.

**Status, 2026-09-25: DESIGNED, then CRITICISED AND REVISED** (the critic
round appended `DD-K`…`DD-M` and amended `DD-A`, `DD-B`, `DD-D`, `DD-F` and
`DD-G` in place, each amendment marked "critic round"), **then DELIVERED** (lanes 1–3
appended `DD-N`…`DD-P`; record §57). Plan task 10 is split in two by the
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
   no previous extent recorded, nothing is compared. The half that makes this
   true is `sweep()` clearing `loopExtents` after the swap, so a loop noted in
   an earlier frame never reads as evaluated in this one; pinned by
   `aLoopInsideAWindowedListRowKeepsItsStateWhileTheRowIsOut` (1.14b: a
   `ForEach` and a `for` loop inside a windowed `List` row keep their state
   while the row is out — mutation V11, that clear deleted, resets both to 1).
   **Only the loop's direct
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
   a related shape, measured while writing B5 and not made an arm). That is
   MetalUI's own answer, pinned in test 2.5 (base 9 → 5 reads 5, then nil
   reads 5; V5, the getter no longer updating the last value, reddens only
   `theOptionalBindingInitialisersMatchSwiftUI`, 2 issues). A key-path
   binding's write reads the base's **current** value, pinned by test 2.3b
   (`twoKeyPathBindingsMadeTogetherEachWriteOverTheOthersWrite`: two derived
   bindings made before either writes, both fields land); V6, the subscript
   snapshotting the base when the derived binding is made, reddens only that
   test (1 issue: the second write reverted the name).
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
   pin that an unbounded frame asks for nothing. **The subtraction is pinned
   by test 3.6** (`aListInAScrollerBelowTheWindowOriginWindowsTheRowsOnScreen`,
   the verifier's round): the scroller 88pt below the window origin, the list
   at the top of its content, wheeled to 300 — rows 10…14 on screen, built
   ⊇ 10…14 and ⊆ 8…16. Under V3 (the origin taken as the list's bounds alone)
   it built 5…13, row 14 on screen and blank; it is the only test V3 reddens
   (full unfiltered run, 1542 tests, 2 issues, both in 3.6) — every other
   `DD-F` fixture puts the scroller at the window origin or clamps the origin
   with a 300pt header. Probe L2 is the answer being matched: the rows on screen (0…3 at offset
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

---

## DD-N — lane 1: a second changed answer `DD-C` owes, which the design did not list

**Ruling.** `DD-C`'s loop reset changes the answer of **one more existing
test** than the design named (the design named only C2.4b, test 1.11):
`AnimationTests.swift`'s `aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop`,
whose second arm — an animating subject, `.id("subject")`, inside
`for _ in 0..<(show ? 1 : 0)`, vanishing mid-flight and returning — pinned
divergence 74's **tombstone resumption** (the `$anim` baseline survived, the
return frame read **175** on the original trajectory). Under `DD-C` the loop
resets the dropped named iteration, `$anim` included, so the return frame
snaps to the declared **200**, exactly as the `if` arm already did (`ID-C`).
This is `DD-C` item 4's migration note ("a fresh `$anim` slot") measured, not
a new behaviour.

1. **The arm is inverted** (175 → 200) and the test is **renamed**
   `aReturningAnimatingElementSnapsInsideAnIfAndInsideALoop` — the old name
   states the retired behaviour. A rename, not a retirement: the test count
   does not move and every assertion is kept, the loop arm's value changed by
   ruling. **Red before: 175** (lane 1's red run, `0d52013`).
2. **Where tombstone resumption still exists**: nowhere a loop or conditional
   evaluates — only a `List` row out of the window (`TB-AH`, bounded), which no
   test pins for `$anim`. Recorded, not added.

**Why the design missed it.** The design grepped for divergence 74's pin
(C2.4b) and the source comments citing it; the animation test cites
"divergence 74, owner plan task 10" in a doc comment the grep did not reach
(the Record phase copies this finding to record §57 as a design-time miss).

**Evidence.** Lane 1's red run (`175.0`), and the green run after the loop
rule (`200`); mutation M1h (the named half of the loop rule removed) reads 175
here again.


---

## DD-O — lane 2: two changed answers `DD-F` owes, and the window's clamp, which the design did not list

**Ruling.** `DD-F`'s stored origin changes the answer of **two existing
tests** the design did not name, and its window formula keeps one clamp the
ruling's wording left out.

1. **`ListLoweringTests`' `aLoweredListLaysOutEveryWindowedShape`, arm B4** —
   a `List` under a 10pt `.padding` layer in a scroller at offset 50 — built
   rows **3…16** while the window ignored the list's origin; the list sits 10pt
   down its scroller's content, so the list-local band is 40…140 (rows 4…13)
   and the window is now **2…15**. This is divergence 14's retirement measured
   on a second shape, not a new behaviour. The arm's expected window and its
   per-row bounds loop move to 2…15; every other arm (B1–B3, B6…) is at origin
   0 and unmoved. **Red before** (lane 2's first full run with `DD-F`):
   `lRealizedIndices(b4.lowered) → [2, …, 15]` against `Array(3...16)`, and
   `B4 row 16: nil`.
2. **`MeasurePerformanceTests`' `theResidentEntrySetStaysBoundedWhileScrolling10kRows`**:
   the cold frame's `StateTable` count moves **`2n + 5` → `2n + 6`**. The
   stored `ListOrigin` is one more fixed entry for a `List` inside a vertical
   scroller (at the list's own id, `DD-F` item 1 — no new reserved name, so
   `theSevenRetentionSlotsAreMutuallyDistinct` is unmoved). **`TB-AH`'s rule is
   unchanged** — rows out of the window past two generations lose their state
   once the table exceeds 256 entries — but a table holding a scrolled `List`
   reaches that bound **one entry sooner**. Recorded, not hidden: this is the
   only retention-visible consequence of `DD-F`, and it is per list, not per
   row. **Red before**: `table.count == 2 * n + 5` failed at 20 006 + 1.
3. **The window keeps the pre-`DD-F` clamp on its list-local top**
   (`List.window(count:rowExtent:offset:viewport:origin:)`): the top of the
   visible band, `offset − origin`, is clamped into `0…max(0, count × rowHeight
   − viewport)` before rows are counted, exactly as the raw offset was clamped
   before. At origin 0 that is the old window bit for bit (so every origin-0
   test is unmoved); with an origin it makes the window a **superset** of the
   rows `DD-F` item 1's "intersecting" wording names whenever the list is only
   partly inside the viewport (a band starting above row 0 is served by rows
   0…, one running past the last row by the last viewport's worth) — never an
   empty window for a list scrolled past, which would otherwise draw one blank
   frame when the content shrinks under a stale offset.

4. **Two guard instruments differ from the design's table.** G2.1's negative
   arm is the bare `Binding("cmd-k", A())` inside a whole-file `@MainActor`
   function, not `Keymap([Binding("cmd-k", A())])` in a function body: the
   Keymap-wrapped spelling stays an error under M-G2.1 (a value `Binding` is
   never a `KeyBinding`), and a nonisolated function body rejects a main-actor
   initialiser for its isolation — the first version of the guard read green
   under M-G2.1 for exactly that reason (measured). G2.2's named mutation
   (`State.projectedValue` made `internal`) does not compile — the compiler
   requires a wrapper's projection at the wrapper's access level — and a
   rename breaks the in-module tests' `$n`, so the run mutation is the
   `TextField` binding initialiser made `internal` (M-G2.2b).

5. **Verifier round: three mutations that read green now redden.** V3
   (`DD-F`'s subtraction dropped) reddens test 3.6 only; V6 (the key-path
   binding's snapshot) reddens test 2.3b only; V5 (the unwrapped binding's
   last value never updated) reddens test 2.5 only. Each was taken as a full
   unfiltered run (1542 tests) with the source restored from a copy after.

**Evidence.** Lane 2's full unfiltered run after `DD-F` (4 issues in these two
tests, nothing else); the green run after this ruling; the guard mutation runs.

**What it costs if wrong.** A table sized within one entry of 256 retains or
reaps one row's state differently than before; nothing else moves.

## DD-P — lane 3: its mutation table, one redundant clamp, and a second copy of the scope check

**Ruling.** Lane 3 (`DD-G`, `DD-H`, `DD-K`) records its mutations here; three
of the readings change what the lane's tests claim to pin.

1. **The table.** Each row is a full unfiltered run with the source restored
   from a copy after. "Implementer" rows are the readings lane 3's test docs
   name; "verifier" rows were re-taken by the verifier round; "fix" rows by
   the fix round.

   | Mutation | Change | Reddens | Taken by |
   |---|---|---|---|
   | M3f | `scrollTo`'s formula reads the target's `maxY` | 3.6 (reads 330, 295, 260, 312.5) | implementer |
   | M3g | a nil anchor treated as `.top` | 3.7, first two arms (300, 30) | implementer |
   | M3h | unresolved requests kept pending | 3.8, second arm (reads 450) | implementer |
   | M3h-clamp | the clamp in `Frame.scrollOffset(bringing:into:anchor:)` removed | **nothing**: redundant (item 2) | verifier |
   | M3i | `List`'s pending-request scan removed | 3.9 (reads 1) | implementer |
   | M3j | the target is the union of a `ForEach` element's members | 3.10 (`.bottom` reads 340) | implementer |
   | M3k | resolved against the outermost scroller frame | 3.11 (outer 200, inner 0) | implementer |
   | M3l | `ProposalScrollView` pushes no scroller frame | 3.12, second arm (reads 0) | implementer |
   | M3m | the scope check dropped from `Frame.matchScrollRequests` | 3.13, S2 arm (B moves to 300) | implementer, verifier |
   | V-ListScope | the scope check dropped from `Frame.unresolvedScrollRequests(enclosing:)` | before the fix round: **nothing** (1555 passed); after: 3.13b `scrollToIsScopedToItsReaderOnTheListPath`, its separating `offset(window, "b") == 0` only (1556, 1 issue) | verifier, fix |
   | M3n | the reader takes no slot (both entries) | 3.14, **both** arms: the two entries share the `proxy(under:at:pass:)` helper | verifier |
   | M3n′ | the same in the typed entry only | 3.14, typed arm only | implementer |
   | M3o | `.never` falls through to the automatic path | 3.15 | implementer |
   | M3p | keys matched by `String(describing:)` | 3.16, the negative arms | implementer |
   | M3q | typed keys noted with no request pending | 3.16, the counter arm | implementer |
   | MG4 | a plain `gridCellAnchor(_: UnitPoint)` overload | does not build (item 4) | verifier |
   | MG4c | the same overload, `@_disfavoredOverload` | `aGridCellAnchorIsNinePoint` (`4 unit point: succeeded=true`) | verifier |

2. **The clamp in `scrollOffset(bringing:into:anchor:)` is redundant, not a
   pin.** Test 3.8's row-19 arm reads 500 with it removed, because
   `ScrollChrome.resolvedOffset` re-clamps the stored offset on its next read
   and writes the clamped value back. The spec asked for this to be measured;
   M3h-clamp is that measurement. The clamp stays, so the resolution value is
   correct at the point it is computed. Nothing claims it as a pin.
3. **The scope check exists twice, and only one copy had a pin** (the
   copy-of-a-pinned-implementation shape). `.id` elements are matched in
   `Frame.matchScrollRequests`; `List` rows are matched through
   `Frame.unresolvedScrollRequests(enclosing:)`, which carries its own
   `isStrictDescendant(id, of: scope)` clause. 3.13's S2 arm uses only `.id`
   elements, so V-ListScope read green. **3.13b** (fix round) is S2's shape
   with two readers over `ScrollView { List }`: row id 150 exists only in
   reader B's `List`. Its control is B's own proxy moving B to 1500. Its
   separating arm is reader A's proxy moving neither scroller. The mutation
   reddens only that arm.
4. **`UnitPoint` and the grid anchor.** Since `DD-G` MetalUI has a public
   `UnitPoint`, but `gridCellAnchor` still takes the nine-case
   `ProposalAlignment` (divergence `GR-O` 4; task 11 owns it). The obvious
   mutation, a plain `UnitPoint` overload, does not build: `UnitPoint`'s
   statics (`.top`, `.trailing`, `.topLeading`) make every existing
   leading-dot call site ambiguous (`Grid.swift`,
   `ModifierCompositionProofTests`, `GridElementTests`). Task 11 will hit the
   same ambiguity when it adds the real overload. The guard's named mutation
   is now the `@_disfavoredOverload` spelling (MG4c).
5. **Red-first figure.** At `f656270` (the red-first commit) the unfiltered
   suite read **10 of 13** new tests failing with 25 issues (3.6–3.13, 3.15,
   3.16). 3.14 and both guards passed over the skeleton. The commit message's
   "12 of 13" is wrong and stays unamended; this is the figure record §57
   carries.

**Evidence.** The verifier round's mutation logs (M3h-clamp, M3n at
`ScrollToTests.swift` lines 527 and 556 before 3.13b moved them, MG4, MG4c,
V-ListScope at 1555 passed). The fix round's V-ListScope run: `Test run with
1556 tests in 3 suites failed … with 1 issue`, the one issue being 3.13b's
`offset(window, "b") == 0`.

**What it costs if wrong.** Without 3.13b, a proxy from one reader could
scroll a `List` under another reader with the suite green.

---

# Part 2 — controls and selection (`DD-Q` onward)

**Evidence, cited below by arm id:**

- `docs/probes/swiftui-controls-and-selection.swift` (**new**, part 2's design):
  SIZE arms BT0–BT5 (`Button`, and a `Text` label under each `controlSize`),
  TG0–TG2 (`Toggle`), SL0 (`Slider`), ST0 (`Stepper`), PK0/PK1 (`Picker`), LS0;
  AX arms BA0–BA3, TA0–TA3, SA0–SA9 (with SA1–SA7 the adjustment rules),
  STA0–STA7, PA0–PA4, LA0–LD0 (`List(selection:)`); CK0–CK4 (clicks — **no
  working SwiftUI control**, CK0 reads nothing while CK1, an `NSButton`,
  reads its action), WH0/WH1 (wheel — **no working control**, WH0 reads 0),
  KY0–KY8g (keys — KY0's control passes; `NSApp.isFullKeyboardAccessEnabled
  = false`). Compiled form run twice, stdout byte-identical (172 lines), exit
  0, stderr empty, macOS 27.0 (26A428), Apple Swift 6.4, screen **locked**
  (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). **The script
  form does not run on this machine** (`JIT session error: Symbols not found:
  [ ___isPlatformVersionAtLeast ]` before `main`, with and without an
  explicit `-target`), so `SA-O`'s second form is recorded as unavailable,
  not as agreeing. Output and reading in the header.
- The existing probes `swiftui-environment-control-state.swift` (Z2/Z3: Z3
  measured `Button("OK")` at 30/36/43/47/55 wide and 13/20/24/28/36 tall
  across the five sizes; BT4 re-measures with "Go" — the same heights, 28/35/
  41/45/53 wide — and BT5 adds that label's own size, so the padding can be
  derived rather than guessed) and
  `swiftui-data-and-scrolling.swift` (L0/L1, K6 via CLAUDE.md's `List`
  paragraph; W0, the failed wheel control WH0 repeats).
- Baseline at `27b2fcc` in this worktree, re-taken by this design session:
  `Test run with 1556 tests in 3 suites passed`, guards ran, 0 `error:`.

---

## DD-Q — part 2's scope: every item addressed to it, and three lanes

**The collection** (grep for "task 10" and "part 2" over `docs/record/`,
`docs/superpowers/*.md` and `specs/`, 2026-09-25, filtered to plan task 10 —
the 2026-08 "Task 10"s are m-milestone tasks — plus `DD-J`'s table and every
decisions doc's "Carried…" section, none of which names task 10):

| item | source | disposition |
|---|---|---|
| `Button`, `Toggle`, `Slider`, `Stepper`, `Picker` | plan text; `DD-J` | **built**: `DD-R`, `DD-S`, `DD-V`, `DD-W`, `DD-X` |
| a `Button` control's existence | `EV-AE`/`EV-AF`; the `AB-` doc's `AB-G` "no `Button` until task 10" | **built**, `DD-R` |
| keyboard activation, focusability, disabled, accessibility per control | the brief | **built**, `DD-T`, `DD-U` |
| `controlSize`'s consumers, divergence 76 | `EV-AC`, `EV-AE`; record §05, §56 | `Button`'s chrome reads it (`DD-R` item 4); the rest → plan task 11 (`DD-AB` item 2) |
| `controlActiveState`'s consumers | `EV-AE` | plan task 12, unchanged |
| `List(selection:)`, single and multi, pointer, keyboard, accessibility | plan text; `DD-J`; `CN-Q` | **built**, `DD-Z` |
| the controls' selection | `DD-J` | **built** (`Picker(selection:)`), `DD-V` |
| divergence 16 | record §04 | **retires**, `DD-Y` |
| `ForEach(_: Binding<C>)` | `DD-J` | **built**, `DD-AA` |
| `TextField`/`TextEditor` binding initialisers | the brief | part 1 delivered them (`DD-E`); nothing left |
| `List` scrolling itself/greedy, non-uniform rows, `List { … }` | `DD-J`, `CN-Q` | divergence 84, owner none (`DD-AB` item 3) |
| divergence 32; accessibility scrolling to unrealised rows | `DD-J`, `AB-Q` | plan task 12 (`DD-AB` item 4) |
| two-axis scrolling, divergence 54 | `DD-J`, `CN-M`, `LR-BJ`, record §25/§54 | kept, owner none (`DD-AB` item 5) |
| `scrollPosition(id:)` | `DD-J` | not built, additive (`DD-AB` item 6) |
| style protocols, other styles, `Button(role:)`, `.keyboardShortcut` | the brief | plan task 12 (`DD-AB` item 7) |

**Three lanes**, run in order 1, 2, 3 (the spec's §9 names every file):
**1** `Button`, `Toggle`, `Picker` and every accessibility change (the five
roles on both bridges, the folds, the selection hint) — the roles are needed
by lanes 2 and 3, so they land first; **2** `Slider`, `Stepper` and every
`Window`/`Handlers` change (`valueTrack`, divergence 16's wheel rule,
`ClickDispatch`) — all of `Window.swift` in one lane; **3** `List(selection:)`,
`ForEach(_: Binding<C>)` and the controls demo, which consume lanes 1 and 2.
**Source files are disjoint**; the one overlap is append-only arms in shared
registry tests (D2, the per-conformer click list, the legacy-site list,
`HandlerShape`/`HandlerFingerprint`), each added by the lane adding its site.

**Cost if wrong.** A lane needing another's source file serialises them and
a red cannot be attributed; sequential order and per-commit attribution cover
the registry arms, as `DD-A`'s critic-round amendment accepted for part 1.

---

## DD-R — `Button`: SwiftUI's two initialisers over a `Box`; `onClick` stays the gesture primitive

**Ruling.**

1. **Spelling** (SwiftUI's, less `role:`): `Button(action:label:)` and
   `Button(_ title: String, action:)` (`Label == Text`). A `StyledElement`, so
   every modifier works on it.
2. **Relation to `onClick`.** `Button` **is** an `onClick` plus focusability,
   keyboard activation (`DD-T`) and the automatic (bordered) chrome; `onClick`
   on any `StyledElement` stays what it is — the tap-gesture-level primitive,
   SwiftUI's `onTapGesture`, **not deprecated**. Accessibility needs nothing
   new: a clickable generic node is already a button that folds its label
   (`AB-G`), which BA0 and BA2 read (one `AXButton`, label "Go"/"A", kids=0,
   whatever its style, BA3). A caller's `.onClick` on a `Button` **replaces**
   its action (the one-field rule, `Handlers.onClick`'s doc); a caller's
   `.onKey` runs **before** the activation and can claim the key.
3. **Chrome** (BT0): an outer `Box` row, label centred, horizontal padding
   12, 24 tall by a zero-width strut `Box` whose height is **declared** (no
   item field: a `minSize` on an internal node would be reported
   `…unconsumed` under a proposal parent, `LR-AQ`), `cornerRadius` 5,
   background `.surfaceSecondary`, border `.separator` 1. `Button("Go")` is
   `textW + 24` wide, `max(textH, 24)` tall — at the default size SwiftUI's
   41×24 over its 17×16 label.
4. **`controlSize` reaches the chrome** (divergence 76 **amended, kept**):
   heights 13/20/24/28/36 and paddings 8/10/12/14/18 for mini…extraLarge
   (BT4 − BT5: 28−12, 35−15, 41−17, 45−17, 53−17, halved). The **label's font
   does not shrink** — that is a `Text`'s default font, plan task 11 — so at
   mini and small a MetalUI button is its unshrunk label in the smaller chrome
   (e.g. mini: `textW + 16` × `max(textH, 13)` where SwiftUI's is 28×13).
5. **Only the automatic look.** `.plain`/`.borderless`/`.link` (BT1: the
   label alone) and `ButtonStyle` are not offered (`DD-AB` item 7): a style's
   `isPressed` needs the active state, which is paint-only (`PaintPass.isActive`),
   a phase question for task 12. A plain-looking button today is
   `.onClick` on the label itself. No pressed look, no hover, no focus ring
   (task 12).

**Evidence.** BT0–BT5, BA0–BA3; `AB-G`, `EV-AE`.

**Cost if wrong.** If `Button` should have been a plain `onClick` sugar, the
chrome is one `Box`'s decoration to drop; the public spelling is SwiftUI's and
survives either way. A caller who relied on `.onClick` adding to a button's
action gets the replacement the modifier has always documented.

---

## DD-S — `Toggle(isOn:)`: the macOS checkbox, and nothing else

**Ruling.** `Toggle(isOn:label:)` and `Toggle(_ title: String, isOn:)`. The
automatic style on macOS **is** the checkbox (TG0 = TG1 `.checkbox`, 53×16 =
label 32 + 21), so that is the one look: a 14×14 indicator, gap 7, the label
(`14 + 7 + textW` × `max(14, textH)`). A click, a focused Space and an
accessibility press each write `!isOn` once (TA0: `on set true`). Published
as `.checkBox`, labelled by its label (the full fold, `DD-U`), value `"1"`/
`"0"`; disabled publishes disabled and writes nothing (TA3). The indicator is
a `Box`, so its colour animates under `withAnimation` through
`animatedBackground` with no new code. `.switch` and `.button` (TG1: 94×24,
56×24, and a different tree — TA1 publishes a sibling static text and an
unlabelled switch) and `ToggleStyle` are not offered (`DD-AB` item 7).

**Critic round.** Only the sum 21 (indicator + gap) is measured (TG0: 53 −
32; the radio row's 21, PK2/PK3, agrees); the 14/7 split is MetalUI's and
moves no size. An **empty-label** toggle is 21 × 19 in SwiftUI (TG0) where
MetalUI's is 21 × `max(14, textH(""))` (SwiftUI's own empty `Text` is 0 × 14,
PK2, so its 19 is the checkbox cell's) — not matched, folded into divergence
76's control-metrics remainder (plan task 11, `DD-AB` item 2).

**Evidence.** TG0–TG2, TA0–TA3, PK2.

**Cost if wrong.** A port that asked for `.toggleStyle(.switch)` fails to
compile, not silently; the checkbox is SwiftUI's own default on this
platform.

---

## DD-T — every control is focusable, and takes its keys when focused (divergence 80)

**Ruling.**

1. `Button`, `Toggle`, `Slider`, `Stepper`, `Picker` and a selectable `List`
   set `isFocusable`, so `Window.focus(_:)` and an accessibility focus request
   reach them. **A click focuses none of them** (the focus rule stands),
   except a selectable `List` (`DD-Z` item 5).
2. Keys, through the control's `onKey` after the `Keymap` and after a
   caller's own `onKey`: Button Space (Apple) / Space and Return (elsewhere);
   Toggle Space; Slider ←↓/→↑ by the accessibility step (`DD-W`); Stepper ↓/↑;
   Picker ←↑/→↓ to the previous/next option, **no wrap**; List per `DD-Z`
   item 6. One internal table, `ControlKeys.swift`, keyed on
   `TextEditing.platform` (the precedent `TI-D` set for the editing keys).
3. **Divergence 80, added**: SwiftUI's controls take none of these keys here —
   `NSApp.isFullKeyboardAccessEnabled = false`, and a focused `Button`, a
   `.focusable()` `Button`, `Toggle` and `Slider` ignore Space, Return and the
   arrows (KY1, KY4, KY4b, KY5, KY7), while KY0's focused `onKeyPress` view
   receives its key, so the events are delivered. MetalUI's key table is its
   own convention and reads no system setting; what SwiftUI does **with**
   Full Keyboard Access on is unmeasured, so no claim is made about it
   (critic round: the design said MetalUI "behaves as SwiftUI would" there,
   an unprobed SwiftUI claim). Only `List`'s arrows are SwiftUI's measured
   behaviour (KY6/KY8). KY3 (Return runs a `.keyboardShortcut(.defaultAction)`
   button without focus) is task 12's (`DD-AB` item 7).

**Evidence.** KY0–KY8g and the printed setting.

**Cost if wrong.** *(Erratum at the `feat/text-page` merge, 2026-09-28: Tab
traversal now exists — `TI-J`, record §60 §Merge — and visits every control
this ruling made focusable; the sentence below describes the tree before it.)*
MetalUI has no Tab traversal (task 12), so focus reaches a
control only programmatically or through an accessibility client; a control
that answers keys it was focused for costs nothing when nobody focuses it.
If task 12 rules focus to follow the system setting, it removes
`isFocusable` in one place per control.

---

## DD-U — accessibility: five roles on both bridges, two folds, and a selection hint (divergence 82)

**Ruling.**

1. `AXRole` and `MetalUIPlatform.AccessibilityRole` gain `.checkBox`,
   `.radioButton`, `.radioGroup`, `.slider`, `.incrementor` — the roles the
   probe reads (TA0 AXCheckBox, PA1/PA2 AXRadioGroup/AXRadioButton, SA0
   AXSlider, STA0 AXIncrementor). AppKit maps them one to one and answers
   `accessibilityValue` with an `NSNumber` for the four valued roles when the
   string parses (the probe's values are numbers: 0/1, 5, 1); AccessKit maps
   them to check box, radio button, radio group, slider, spin button, with a
   toggled state from `"1"`/`"0"` and a numeric value. **Adding a case to
   either public enum breaks an exhaustive `switch` outside the module** —
   `Backends/SDL`'s two switches are updated in lane 1.
2. **Full fold** (`AB-G` step C) now applies to `.checkBox` and
   `.radioButton` as to `.button`: kids=0, label from the descendants (TA0,
   PA1, PA2).
3. **Partial fold**, new, for `.incrementor` and `.radioGroup`: their
   non-interactive descendants' text becomes the label (when none is
   declared) and is not published; their interactive descendants stay as
   children. So a `Stepper`'s title labels its incrementor and a `Picker`'s
   its radio group. **Divergence 82, added**: SwiftUI publishes the title as a
   **sibling** static text beside an **unlabelled** control (STA0; PA0, PA1,
   PA2; SA8 for a slider's label). MetalUI's answer gives the control an
   accessible name, which SwiftUI's lacks; a `.button` with an interactive
   descendant still keeps its children and its label (divergence 29 unmoved).
   *Critic round (`DD-AC` item 9):* divergence 82 also names two measured
   shapes MetalUI does not publish — a slider's `AXValueIndicator` child
   (SA0, kids=1) and a stepper's arrow buttons marked DISABLED while the
   stepper is enabled (STA0).
4. **`AXNode.selectionHint`** (internal): published as `isSelected`, and
   stripped before `Frame.registerHandlers`' emptiness test exactly as
   `logicalIndex` is (`AB-L`), so a selected `List` row records and writes
   neither `axNodes` nor a `$ax` slot (`AB-U`) — retention and `TB-AH` do not
   move. A `Picker` option declares the public `.selected` trait instead (it
   declares a node anyway).
5. Actions stay derived (`AB-H`): press from the hitbox, increment/decrement
   from the `AccessibilityAdjustment` handler. A disabled control publishes
   disabled with no actions (BA1, TA3, SA9, STA7, PA4 all DISABLED).

**Evidence.** The AX arms; `AB-G`, `AB-H`, `AB-L`, `AB-U`.

**Cost if wrong.** If VoiceOver validation (task 12) prefers SwiftUI's
sibling title, the partial fold is one branch in `combine` to narrow; the
roles and values are SwiftUI's own.

---

## DD-V — `Picker(selection:)`, `.tag(_:)`, and a closed `PickerStyle` (divergence 81)

**Ruling.**

1. **Spelling**: `Picker(_ title: String, selection: Binding<V>, content:)`,
   options marked with `.tag(_:)` on any `Element` — SwiftUI's. A title-string
   initialiser only; a label builder is additive later.
2. **Options are found through a picker scope**, not by walking the content
   (an `ElementGroup` cannot be introspected): `Picker` pushes an internal
   scope (a `@MainActor` static stack in `Picker.swift`, balanced by `defer`)
   around its content's **layout only** (amended by `DD-AD` item 6: an
   option carries its chrome to prepaint and paint in its layout state); a
   `TaggedElement` reads the innermost,
   appends its tag in `requestLayout` (so the picker knows the order for its
   arrows) and builds its option chrome.
3. **Selection is by value equality** of the tag with the binding's value.
   A press writes the option's tag (PA1: `pick set 2`; PA2: `pick set 0`); a
   selection matching no tag selects nothing and writes nothing (PA3).
4. **`PickerStyle` is a closed struct with static members**, `.automatic`,
   `.segmented`, `.radioGroup`, so the call site reads SwiftUI's
   (`.pickerStyle(.segmented)`); turning it into SwiftUI's protocol later
   keeps every such call site compiling. **`.menu` is not offered and
   `.automatic` is segmented** — **divergence 81, added**: SwiftUI's automatic
   picker on macOS is a pop-up menu (PK0 = PK1 `.menu`, 139×24; PA0
   AXPopUpButton). A menu is a presentation with its own keyboard and dismiss
   rules — task 12's (`DD-AB` item 7). `.inline` (PK1: the radio group's look
   here) is not offered either.
5. **Layout**: title, 8, the control (PK0/PK1 sums: 37 + 8 + 94, 37 + 8 +
   211, 37 + 8 + 67). Segmented: **every segment as wide as the widest** (PA1:
   70, 70, 70 for Alpha/Beta/Gamma) — an internal `EqualWidthRow:
   ProposalLayout` over the consumed and planned option records, the shape
   `ListRows` uses; each segment `textW + 24` before equalising (PK2: Gamma
   46 → 70), 24 tall by strut. Radio group: a leading-aligned column, gap 6,
   each row a 14-pt circle, **7**, the label — `textW + 21`, the checkbox's
   21 (critic round, PK2/PK3: 55, 67, 141 over 34, 46, 120; the design's
   "14, 6" gave 20, which no arm supports). **Not matched, folded into
   divergence 81** (critic round): SwiftUI's segmented control is `n·w + 1`
   (PK1 211 = 3·70 + 1, PK3 289 = 2·144 + 1) where MetalUI's is `n·w`, and
   its radio rows sit 6.5 apart in PK1 where MetalUI's gap is 6 (PK3 reads
   6).
6. **A tag outside a picker is transparent** (`TaggedElement` forwards its
   content at the content's own id): record §05 gains the row — `.tag(_:)`
   is stored and read by nothing outside a `Picker`. (Critic round: the
   design's aside about what SwiftUI's `List` does with tags was unprobed and
   is withdrawn.) **`TaggedElement` forwards every `Element` requirement**,
   not only the three phases, so a legacy item record or any other hook
   passes through it unchanged; `DD-AC` item 5 pins it with a container
   field, not only a leaf. It is public only because `.tag` returns it
   (SwiftUI's returns `some View`); its initialiser is internal.

**Evidence.** PK0–PK3, PA0–PA4.

**Cost if wrong.** A port using the default style gets segments where it had
a menu — visible, not silent; `.menu` fails to compile (guard G1.2). The
static-member struct can become a protocol without breaking a call site.

---

## DD-W — `Slider(value:in:step:)`: a greedy leaf with SwiftUI's stepping rules

**Ruling.**

1. **Spelling**: `Slider(value:in:)` (default `0...1`) and
   `Slider(value:in:step:)` over any `BinaryFloatingPoint` whose `Stride` is
   one — SwiftUI's; no label, no `onEditingChanged` (additive later).
2. **Layout** (SL0): greedy on the width (the finite proposed width, else
   30 — SL0's ideal), 16 tall. A leaf through `lowerLegacyLeaf(site:
   .slider)`, `TextField`'s shape; `LoweringSite.slider` is new and gains its
   arm in `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.
3. **An adjustment** (accessibility increment/decrement, and the arrows):
   start from the value clamped into the bounds (SA5: 15 − → 9; SA6: −3 + →
   1); with no step move 10% of the span (SA1 +1 on 0…10, SA7 +20 on 0…200);
   with a step move one step and land on the grid `lower + k·step`, rounding
   half up (SA3: 5 +2 → 8), clamped to the last grid point inside the bounds
   (SA4: 9 +3 → 9 on 0…10). **Every adjustment writes, changed or not** (SA2:
   `value set 10.0` at the maximum).
4. **Display**: an out-of-range value is drawn clamped and **not written
   back** (SA5, SA6: no write on appear).
5. **Pointer** (unmeasured in SwiftUI — CK0 failed): a press on the slider
   writes the value under the pointer — `lower + clamp01((x − minX −
   thumb/2) / (W − thumb))·span`, onto the grid when stepped — and a drag
   while pressed writes again; the press does not focus. Through the
   internal `Handlers.valueTrack` (the tenth member, `TI-B`'s `textInput`
   precedent), dispatched by `Window` ahead of click dispatch; it rides the
   hitbox, so `.disabled` and `allowsHitTesting(false)` remove it.
   `HandlerShape` and `HandlerFingerprint` gain the field.
6. **Accessibility**: `.slider`, value the number without a trailing `.0`
   (SA0 `5`), no label (SA0), increment/decrement from its
   `AccessibilityAdjustment` handler.
7. **Validation** (`SA-J`): a step that is not finite and positive, or
   bounds that are not finite, **trap** — each would make the thumb's
   position non-finite. Equal bounds do not trap (the fraction is 0).
8. **Animation**: the thumb is drawn by the slider's own `paint`, so a value
   written under `withAnimation` **snaps** — added to CLAUDE.md's snaps list
   by the Record phase. SwiftUI's is unmeasured.

**Evidence.** SL0, SA0–SA9; `SA-J`, `TI-B`.

**Cost if wrong.** The rounding and last-grid-point rules are SwiftUI's
measured ones; a caller reading its value after a keyboard or accessibility
adjustment gets SwiftUI's number. The pointer rule is MetalUI's until a
human looks (record §03).

---

## DD-X — `Stepper`: three initialisers, SwiftUI's clamp, and no write when nothing moves

**Ruling.**

1. **Spelling**: `Stepper(_:value:in:step:)`, `Stepper(_:value:step:)` over
   any `Strideable`, and `Stepper(_:onIncrement:onDecrement:)` — SwiftUI's
   title-string forms. No `onEditingChanged`, no label builder (additive).
2. **A step** (either arrow half, a focused ↑/↓, an accessibility
   increment/decrement): `new = clamp(clamp(value) ± step)` — clamped both
   before (STA4: 5 on 0…3 shows 3 and steps from 3) and after (STA3: 2 +2 →
   3, 1 −2 → 0); **no write when `new == value`** (STA1: at 3, + writes
   nothing; STA2: at 0, − writes nothing), a write otherwise (STA4: 5 + → 3).
   With no range, no clamp (STA5 reaches −1). Where `Slider` writes an
   unchanged value (SA2), `Stepper` does not — both measured.
3. **Closures**: `onIncrement`/`onDecrement` run on their direction; a nil
   one makes that direction do nothing (STA6), and its half is no click
   target.
4. **Layout** (ST0): title, 8, a 20×24 control of two 20×12 halves — the 8
   kept with an empty title (28×24).
5. **Accessibility**: the outer node `.incrementor`, value the clamped value
   (STA4 shows 3), labelled by its title through the partial fold (`DD-U`,
   divergence 82), the two halves `.button` children with no label (STA0's
   arrows have none either).

**Evidence.** ST0, STA0–STA7.

**Cost if wrong.** The write-suppression and double clamp are measured; a
caller observing writes sees SwiftUI's sequence.

---

## DD-Y — divergence 16 retires: the wheel passes a click target to its enclosing scroller

**Ruling.** In `Window.applyScroll`, when the topmost opaque hitbox under the
pointer is not a scroller, the wheel goes to the **nearest ancestor** of that
hitbox's id (`GlobalElementID.parent`) that registered a scroll region
containing the point **on the same layer**; with none it stops, as before.
The multi-line editor's own branch stays first. So a button, a toggle, a
slider, a selectable `List` row **or a single-line `TextField`** (a pointer
target through `Handlers.textInput`; critic round, `DD-AC` item 3 — a
changed `TextField` answer the design did not list) inside a `ScrollView`
no longer blocks the wheel over itself; a click target **overlaid on** a scroller but not inside
it (a `Stack` sibling) still stops it (the ancestry clause), and a scrim
hoisted by `Deferred` still stops it even when declared inside the
scroller's content (the layer clause — `Deferred` content is on layer 1,
`Frame.rootLayer`, ordinary content on 0).

**Why now.** A selectable `List` is a column of click targets
(`DD-Z`): under divergence 16 it could be wheel-scrolled only between rows —
not at all, with rows edge to edge. The fix is the one divergence 16's own
entry named (a layer test), narrowed by an ancestry test so the overlay case
keeps today's answer; it needs no new state (the parent chain and the layer
are already on every hitbox).

**Evidence.** **SwiftUI's and AppKit's answers are unmeasured** here: WH0,
the wheel control over an `NSScrollView`'s own document, reads 0 (as part
1's W0 did), so WH1 means nothing. The ruling rests on divergence 16's own
statement (a browser scrolls) and on the composition this task adds; a human
look is owed (record §03).

**Pins.** `aClickTargetInsideAScrollViewSwallowsTheWheel` is **renamed**
`aClickTargetInsideAScrollViewPassesTheWheelToItsScroller` with its first arm
inverted (0 → 37) — a changed answer its own doc invited ("whoever
implements that gets a red test here and should invert it"). The ancestry
and layer clauses gain one pin each (spec 2.19, 2.20); the existing scrim
pins stay green.

**Cost if wrong.** If SwiftUI's disabled or overlaid cases differ once
measured, each clause is one condition to change with a pin to invert. The
demo is unaffected (its counter sits outside its `ScrollView`).

---

## DD-Z — `List(selection:)`: single and multi selection over identified rows (divergence 83)

**Ruling.**

1. **Spelling**: `List(_:selection:rowHeight:row:)` with `Binding<ID?>` or
   `Binding<Set<ID>>`, `ID = Data.Element.ID` — SwiftUI's argument order
   (`selection:` after the data), MetalUI's existing `rowHeight:`.
2. **The selection is the binding's.** The list reads it fresh each frame and
   never prunes it: removing a selected datum writes nothing, and its row is
   selected again when it returns (LA5). A disabled list shows its selection
   (LD0) and changes nothing.
3. **What a row shows**: a selected row's `Box` has background `.accent` and
   the internal selection hint (`DD-U` item 4) — `isSelected` for a client
   (LA1, LB1), no `$ax` write. Nothing is added to a list without
   `selection:`.
4. **Pointer** (unmeasured in SwiftUI — CK0 failed; AppKit's table
   convention): a click (`onClick`, press and release on the row) selects
   exactly that row (in a multi list it **replaces** the set, as LB3's
   accessibility select does); the platform's shortcut modifier (⌘ on Apple,
   ctrl elsewhere — `ControlKeys`) toggles the row in a multi list; ⇧ selects
   the range from the anchor to the row in a multi list; a single list
   selects the clicked row whatever the modifiers. Modifiers come from
   `ClickDispatch.modifiers` (`DD-Z` item 9).
5. **A press on a row focuses the list** (through `ClickDispatch.focusRequest`)
   — the second exception to "clicking does not focus", after `TextField`
   (`TI-B`), so the arrows work after a click, as a table's do.
6. **Keyboard** (a focused list; KY6, KY8 — SwiftUI's measured behaviour):
   ↓/↑ select the next/previous row; with nothing selected ↓ selects the first
   and ↑ the last (KY6c, KY6e); at the last/first row nothing is written in a
   single list (KY6d, KY6f). In a multi list a plain arrow collapses to one
   row — at the end, to the lead alone, a write (KY8, KY8g) — and ⇧+arrow
   extends or shrinks from the anchor (KY8b, KY8e, KY8f); ⌘A and Space do
   nothing (KY8c, KY8d). ⇧ in a single list acts as a plain arrow
   (unmeasured). A write happens only when the selection changes. **The new
   lead row is revealed** through part 1's scroll-request queue (`DD-G`,
   anchor nil), so ↓ past the window scrolls.
7. **Lead and anchor** live in `ListOrigin`, the list's one `StateTable`
   entry (`DD-F`; the table keys by id alone, so a second type at the list's
   id would overwrite it), written with `withState` from input only — no new
   reserved name, and a list gains no entry until it is interacted with (the
   origin entry a scrolled list already had is the same one). A lead no
   longer in the selection (set by the model) is re-derived as the first
   selected row in data order.
8. **Divergence 83, added**: an accessibility client selects a row by
   **pressing** it (rows are click targets, so `AXPress` is derived); setting
   `AXSelected` on a row or `AXSelectedRows` on the table changes nothing,
   where SwiftUI's accept both (LA2, LA3, LB2, LB3; a single list ignores a
   two-row request, LA4). A settable-selection request is a new
   `AccessibilityRequest` case on both bridges — **plan task 12**'s, with the
   VoiceOver script.
9. **`ClickDispatch`** (lane 2): while `Window.dispatchClick` runs an
   `onClick`, `ClickDispatch.modifiers` holds the completing mouse event's
   modifiers (`[]` otherwise, and for an accessibility press), and a handler
   may set `ClickDispatch.focusRequest`, which `Window` passes to `focus(_:)`
   after the handler returns. Internal; a public tap-with-modifiers API is
   gesture composition, task 12.

**Critic round.** Items 3, 6 and 7 are amended by `DD-AC` items 1, 2 and 4
(a selected row's colour slot, the lead-reveal key, per-frame work), and
the unbounded window's row role by `DD-AC` item 6.

**Evidence.** LA0–LD0, KY6–KY8g; `DD-F`, `DD-G`, `TI-B`, `AB-L`.

**Cost if wrong.** The pointer rules are MetalUI's until a human looks; a
wrong modifier rule is a table entry. If AppKit selects on mouse-down, the
selection lands one event later here, with the same result.

---

## DD-AA — `ForEach(_: Binding<C>)`: one binding per element, safe when stale

**Ruling.** `ForEach($items) { $item in … }` over a `MutableCollection &
RandomAccessCollection` of `Identifiable` elements — SwiftUI's spelling —
hands each element a `Binding<C.Element>` reading and writing
`items[index]`, identified by the element's id (`DD-B`'s identity, unchanged).
**A binding kept past a change of the collection** (a handler captured last
frame) checks that the element at its index still has its id: if not, a write
is dropped and a read returns the last value it read. SwiftUI's answer for
a stale element binding is **unprobed**, so this is MetalUI's own rule and
no divergence is claimed (critic round: the design asserted what SwiftUI's
binding does, with no arm).
`ForEachBindingSlot<C>` (index and id) is the `Data` element, opaque outside.

**Evidence.** `DD-B`, `DD-D`; the SDK's `ForEach` interface for the spelling.

**Cost if wrong.** A caller relying on a stale binding writing through gets
nothing, which is the safer failure.

---

## DD-AB — what part 2 does not build, by name; and when task 10 is ticked

1. **Tick.** The plan's task 10 box is ticked in the Record phase if every
   lane is verified: its text's clauses — `ForEach`/identified data,
   bindings, common controls and selection (part 1 and this part); the
   `List`/`ScrollView` limitations that make a layout blank or destroy state
   (part 1's divergences 14 and 13, this part's 16); scroll position,
   indicators and programmatic scrolling (part 1's `DD-G`, `DD-H`) — are then
   closed, and each item below is either not one of those clauses or is
   re-owned by name. Otherwise a dated note names what is open.
2. **`controlSize`'s other consumers** → **plan task 11**: a `Text`'s default
   font (Z2, BT5), and with it `TextField`/`TextEditor` (whose height follows
   their font, Z3) and every other control's metrics — each follows its
   label's font, which is one text-model change, not one per control.
   Divergence 76 stays, amended to "reaches `Button`'s chrome only";
   `controlSizeReachesNoBuiltInMeasurement` (T1.7) keeps its `Text` and
   `TextField` arms and is **not** flipped by this part.
3. **Divergence 84, added**, owner **none**: a `List` answers its content
   height (`rowHeight × count`) and needs an enclosing `ScrollView`; its rows
   share one declared `rowHeight`; it is data-driven only (no `List { … }`).
   SwiftUI's is greedy and scrolls itself (L0; K6), is **blank** inside a
   `ScrollView` beside a header (L1), and takes any rows. None of these makes
   a MetalUI layout blank or destroys state — the task's clause — while
   adopting SwiftUI's greedy list would **blank** the demo's own
   `ScrollView { List }` (L1's shape) and change its pixels; the uniform row
   height is how the list stays virtualized, which the task's text keeps
   "as an internal implementation choice". Pinned by the existing `List`
   layout tests.
4. **Divergence 32 and accessibility scrolling to unrealised rows** →
   **plan task 12**: both are the bridge's (SwiftUI's list publishes an
   `AXOutline`, LA0), to settle with the VoiceOver script. Divergence 83 joins
   them.
5. **Two-axis scrolling (`CN-M`) and divergence 54** → kept, owner **none**:
   neither is a clause of task 10's text ("scroll position, indicators and
   programmatic scrolling" were specified by `DD-G`/`DD-H`), and both reshape
   `ScrollView`'s axis API and move pixels. Plan task 15's inventory lists
   them.
6. **`scrollPosition(id:)`** → not built, owner **none**: `DD-G` specified
   scroll position as the scroller's own state plus `scrollTo`; the
   binding-driven form is additive (P1/P2 measured it) and needs a
   topmost-element query no consumer asks for yet.
7. **Styles and semantics** → **plan task 12** ("button semantics", gesture
   composition): `ButtonStyle`/`PrimitiveButtonStyle` (and `isPressed`, a
   paint-only state), `.buttonStyle(.plain/.borderless/.link)`,
   `ToggleStyle` and `.switch`/`.button`, `.pickerStyle(.menu)` and a pop-up
   menu, `Button(role:)`, `.keyboardShortcut` (KY3), a pressed look, the focus
   ring, a disabled look, an inactive-window look (`controlActiveState`).
8. **Additive, owner none**: `Slider`'s label and `onEditingChanged`,
   `Stepper`'s label builders and `onEditingChanged`, `Picker`'s label
   builder, `.tag(_:includeOptional:)` and optional-selection wrapping,
   `.pickerStyle` as an environment value (SwiftUI's is a `View` modifier,
   per the SDK interface; MetalUI's is a `Picker` method, and calling it
   elsewhere fails to compile — critic round: the design's "propagates to
   nested pickers" was unprobed and is withdrawn). **The generic signatures differ where a label builder is
   missing**: SwiftUI's `Picker<Label, SelectionValue, Content>`,
   `Slider<Label, ValueLabel>` and `Stepper<Label>` against MetalUI's
   `Picker<SelectionValue, Content>`, `Slider` and `Stepper`; only a caller
   who names the concrete type (not `some Element`) sees it, and adding the
   label builders later changes those spellings.

**Cost if wrong.** If a reviewer reads "rework `List` limitations" as
including divergence 84, the tick is early; this item names exactly what was
not done and why, so the note can be re-opened without archaeology.

---

## DD-AC — the critic round: fixes, and the attacks rejected

The design (`f4bc700`) was attacked against the source at `27b2fcc` and the
probe re-run. The screen was **unlocked** this time (lock probe: no
`CGSSessionScreenIsLocked` line, `displayAsleep main: 0`): the design's
compiled probe reproduced all 172 recorded lines byte for byte, twice — so
the failed click and wheel controls (CK0, WH0) are **not** the lock's doing,
and every pointer rule stays MetalUI's own. Two arms were added (PK2 bare
label sizes, PK3 a segmented and a radio picker over labels of 9 and 120
points); that revision ran twice, 182 lines byte-identical, its other 172
lines unchanged. Rejections are recorded here under this doc's own prefix,
as part 1's `DD-M` did, rather than as `LR-` rulings: `LR-` is the engine
replacement's decisions doc, and none of these touches the engine.

**Fixed (each amends the ruling it names; the spec is revised to match):**

1. **A selected row's background mints a `$anim-color` slot** (`DD-Z` item 3;
   spec 3.15 was red by construction). `animatedColor` writes a baseline
   `AnimatedColorState` on first sight of any non-nil token
   (`AnimatedColor.swift`, `animatedColor(_:for:pass:)`), so every selected
   *realised* row adds one `StateTable` entry at its first paint — with or
   without input, since the model can select. The fill stays a row-`Box`
   background (it then animates under `withAnimation` like any `Box`'s, and
   no second paint path exists to drift), and the claim is corrected: a
   selectable list with nothing selected adds **no** entry; each selected
   realised row adds **exactly one**, its colour slot, and **no** `$ax`.
   `TB-AH`'s crossing for a selectable list is `2n + 6 + s` (`s` the selected
   realised rows) — a new list, so no existing pin moves. Spec 3.15 is renamed
   `aSelectableListAddsOneColourSlotPerSelectedRowAndNoAXSlot`; M3m (the hint
   as a declared trait, writing `$ax`) still reddens it. `DD-Z` item 7's "a
   list gains no entry until it is interacted with" is read the same way: no
   entry beyond the `ListOrigin` that a list inside a vertical scroller
   already writes in every `prepaint` (`DD-F`), which lead and anchor share.
2. **The keyboard reveal cannot use a caller-visible key** (`DD-Z` item 6).
   Part 1's queue matches a request by key, first match wins, within the
   request's scope (`Frame.unresolvedScrollRequests(enclosing:)` needs the
   list to be a **strict** descendant of the scope). Enqueued with the lead's
   own `datum.id`, a sibling declared before the list with an equal `.id`
   (or an earlier `ForEach` key) would take the scroll. The list enqueues
   instead, from its key handler (input), a request whose scope is the list's
   `id.parent` and whose key is an **internal** `ListLeadReveal(list: id,
   row: AnyHashable(datum.id))`, which only that list's
   `resolveScrollRequests` matches; the queue is captured from
   `frame.scrollRequestQueue` when the handler is built in `prepaint`. No
   public key type, no change to `DD-G`/`DD-K`'s matching. Pinned by 3.12
   and by the new arm 3.12b (a sibling `.id` equal to the lead's id above the
   list does not scroll to itself). **Erratum (`DD-AH` item 2):** neither of
   those sees the `reveal.list == id` conjunct — 3.12b's sibling is an `.id`,
   not a list — and V4 (the conjunct dropped) left the suite green; the
   "matched only by the list it names" clause is pinned since the lane-3 fix
   round by arm 3.12c (a second selectable list with the same datum ids
   above the focused one does not take the reveal).
3. **`DD-Y` moves a `TextField` answer the design did not list.**
   `Handlers.isPointerTarget` is `onClick != nil || textInput != nil`, so a
   single-line `TextField` registers an opaque hitbox and today swallows its
   scroller's wheel; under `DD-Y` the wheel passes to the scroller. That is a
   changed, user-visible `TextField` answer — ruled here (a text field is a
   click target like any other; the multi-line editor keeps its own branch)
   and pinned by new spec test 2.24. No existing test asserts the old answer
   (grep: no `TextField` fixture sends a wheel), so nothing is retired.
   Comments citing divergence 16 as live — `Box.swift`, `Passes.swift`,
   `Handlers.swift`, `Window.swift`, `FocusTests.swift` (two, including
   `aFocusableRowInsideAScrollViewDoesNotSwallowTheWheel`'s "the differential
   is the neighbouring file's test", which stops disagreeing and is reworded
   to name `focusabilityAndKeyHandlingRegisterNoPointerHitbox` as the
   mechanism pin) and `Sources/MetalUIDemoContent/DemoContent.swift` (three;
   comment-only, 0 px) — are lane 2's to update.
4. **Per-frame work of a selectable list stays O(window)** (`DD-Z` item 7).
   The design left open *when* a lead missing from the selection is
   re-derived; a data scan in `requestLayout` would make a 100 000-row list's
   warm frame O(n), which `aListsWorkIsTheSameFor100kRowsAsFor500` cannot see
   (its list has no `selection:`). Ruled: per frame, a selectable list touches
   only its realised rows (one `contains`/`==` each); finding the lead's
   index, re-deriving it and every range computation happen in the key and
   click handlers (input). New spec test 3.21 counts element accesses through
   a counting `RandomAccessCollection` over a warm frame at 500 and 5 000
   rows with a selection whose lead is absent — equal; mutation M3r
   (re-derive the lead in `requestLayout`) reddens it. Lane 3 also runs the
   gated `METALUI_RUN_100K_LIST_TEST=1` test.
5. **`TaggedElement`'s transparency was pinned by a leaf only** (`DD-V` item
   6). A fixture of fixed-size leaves cannot see a forwarding gap in an item
   record or a group hook (Practices, "a fixture of fixed-size leaves").
   `TaggedElement` forwards every `Element` requirement; spec 1.20 gains a
   container arm — `Box().flexGrow(1).tag(1)` beside a fixed box in a `Row`
   keeps its grown width — and mutation M1q′ (forward only the three phases)
   must redden it.
6. **An unbounded selectable list publishes its rows as buttons** (`DD-Z`
   item 3, `DD-U`). A row carries `logicalIndex` only while a client is
   active **and** the window is bounded (`List.swift`, `indexesRows`); with
   an `onClick` and no index, `AccessibilityTreeBuilder` resolves a row as a
   `.button` and folds its content (step B/C). Ruled, not hidden: while the
   window is unbounded (no vertical scroller, or the scroller's first frame)
   a selectable row publishes as a button labelled by its content, with
   `.press` and, when selected, `isSelected`; bounded, it is a `.row` with
   its index, `.press` and `isSelected`. Folded into divergence 83's text.
   New spec test 3.20 pins both arms.
   *Amended by `DD-AG` item 1 (lane 3): "or the scroller's first frame" is
   withdrawn — that frame keeps AB-X rule 1 (the table, no rows); only a
   window that can never be bounded publishes button rows. Pinned by 3.20b.*
7. **Two disabled controls had no test.** `Picker` (PA4) and `Stepper`
   (STA7) were covered by D2 arms for their clicks only, not their keys or
   their published state. New spec tests 1.24
   `aDisabledPickerWritesNothingAndPublishesDisabled` and 2.23
   `aDisabledStepperStepsNothingAndPublishesDisabled`; M1g re-run on each.
8. **Measured metrics corrected** (`DD-S`, `DD-V` item 5): a radio row is
   `textW + 21`, not `+ 20`; segmented `n·w + 1`, radio gap 6.5 (PK1) and the
   empty-label toggle's 19 are named as not matched (divergences 81 and 76).
   Spec 1.18's literal becomes `14 + 7 + textW_i`.
9. **Unprobed SwiftUI claims withdrawn** (`DD-T` item 3, `DD-V` item 6,
   `DD-AA`, `DD-AB` item 8), each amended in place. Divergence 82's text
   also names two measured AX shapes MetalUI does not match: a slider's
   `AXValueIndicator` child (SA0 kids=1; MetalUI publishes none) and a
   stepper's arrow buttons published DISABLED by AppKit even when enabled
   (STA0; MetalUI's are enabled). Neither is a clause of the task.
10. **Native depth is measured, not assumed.** Every control lowers to
    several native levels (a `Picker` segment: outer row, options `Box`,
    `OptionRow`, segment `Box`, content — each a padded, sized legacy node of
    up to five levels). Lane 3 records each control's deepest native level
    and the controls demo's through a real `Window` (the record §41 §5
    instrument), and the demo must stay at or below the default demo's 30 +
    10, well inside `NativeLayoutRun.maxDepth` (72); 3.19 through a real
    `Window` traps if not.

**Attacks rejected (with the reason):**

- *Focusable controls and their keys are task 12's scope.* The brief asks for
  keyboard activation per control; no Tab traversal, focus ring or
  gesture composition is built, and `DD-T`'s cost paragraph names the one
  place per control task 12 would change.
- *`ClickDispatch` is a gesture API.* It is internal, set only during
  `dispatchClick`, with one consumer; the public tap-with-modifiers API stays
  task 12's (`DD-Z` item 9).
- *Divergence 54 and two-axis scrolling were the plan's hand-offs to task 10
  and `DD-AB` item 5 drops them.* Kept: task 10's text does not name them,
  task 15 requires every remaining difference documented, which divergence
  54's row and `CN-M` do; both move pixels and reshape `ScrollView`'s axis
  API, a run of their own.
- *`EqualWidthRow` under a legacy `Box` is an `SA-G` violation.* There is one
  engine since stage 7b; a `ProposalLayout` child of a lowered container is
  `Grid`'s and `ListRows`' shape. `OptionRow` consumes its options' records
  (`LR-AQ`).
- *`justifyContent: .center` on the unsized `Button` reports.* Only the
  `space-*` distributions report on an undeclared main size
  (`LegacyLowering.swift`); `.center` is a factor.
- *Lanes are too large.* Three sequential lanes over disjoint sources; lane 1
  carries the roles the other two need, and moving `Picker` would put a
  second author on `ControlKeys.swift`.
- *Run the 100k test now.* The branch holds no source change yet, so it would
  measure `27b2fcc`; item 4 adds the discriminating test and hands the gated
  run to lane 3.
- *Linux/Windows/`Backends/SDL` break.* `ControlKeys`, `ClickDispatch` and the
  controls use `TextEditing.platform` and `MouseEvent.modifiers`, both
  portable (SDL fills the modifiers); the five roles are added to both
  bridges' exhaustive switches in lane 1, the change `DD-U` item 1 names.

**Totals.** 1556 + 26 + 24 + 22 = **1628 tests** (lane 1 24 + 2 guards; lane
2 23 new + 1 guard, the rename adding none; lane 3 21 + 1 guard), guards
**100**, `Backends/SDL` `MetalUISDLTests` 22 → 23 on macOS.

**Cost if wrong.** Items 1–7 each change a test's literal or add a test
before any code exists; the rejected attacks each name the ruling that would
move.

---

## DD-AD — lane 1 (part 2): a disabled control survives the partial fold; its mutation table; two readings the spec had wrong

**Ruling.** Lane 1 (`DD-R`, `DD-S`, `DD-T`, `DD-U`, `DD-V`) records its
mutations here; three readings change what the design said.

1. **The partial fold keeps a disabled control** (amends `DD-U` item 3). As
   designed — "their interactive descendants stay as children" — a disabled
   picker's options, which have no derived action (no hitbox, `EV-E`) and are
   not focusable, were **folded into the group's label and not published**:
   spec 1.24 read `radios.count → 0`. PA4 has SwiftUI's disabled radio
   buttons published DISABLED. So the partial fold keeps a descendant that is
   interactive **or** resolves to a control role (anything but static text
   and group — a declared `.radioButton`, a clickable node that step B made a
   `.button`, which a disabled stepper half still is, since `isClickable` is
   recorded ungated); only the rest contributes text and is dropped. The full
   fold (`.button`, `.checkBox`, `.radioButton`) is unchanged. Pinned by 1.24
   (M1t below).
2. **1.20's container arm is not M1q′'s discriminator** (amends `DD-AC` item
   5). Measured: M1q′ (`TaggedElement` forwarding only the three phases, the
   `Element` defaults taking the group entry and `elementID`) leaves the
   container arm green — a lowered record is keyed by node and passes through
   any wrapper that registers the content's node — and M1q (option chrome
   with no scope) leaves it green too, because a greedy child makes the
   wrapping chrome greedy. What M1q′ does break is the content's `.id` (the
   default `elementID` is `nil`) and its `@State` (the default entry binds the
   wrapper, whose mirror holds no `State`), so 1.20 gained two arms, a named
   content and a tagged element whose `@State` survives a click; M1q′ reddens
   exactly those two. The container arm stays as a regression pin.
3. **M1c does not redden 1.4** (the spec's "also reddens 1.4"): the button's
   activation key runs the action directly, not through its hitbox, so 1.4 is
   pinned by M1d and M1e.
4. **Site.** `OptionRow` (the segmented options' group) plans its options as
   a column's children under `parentSite: .box` and records its node at site
   `box`: it is part of the options `Box`, which consumes the record, and its
   options are internal `Box`es declaring no item field, so no report is
   reachable through it. No `LoweringSite` is added (`LayoutAuthority.swift`
   is lane 2's).
5. **The table.** Each row is a full unfiltered run (1582 tests) with the
   source restored from a copy after, `git status --short` empty after each;
   `Backends/SDL` rows are that package's full `swift test` on macOS.

   | Mutation | Change | Reddens |
   |---|---|---|
   | M1a | regular padding 12 → 11 | 1.1, 1.2 |
   | M1b | the chrome reads `.regular` whatever the environment | 1.2 |
   | M1c | `Button` leaves `onClick` unset | 1.3, 1.5, 1.7, 1.8, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `onClickIsLiveOnEveryConformerThatCanRegisterOne` |
   | M1d | Return activates on Apple | 1.4 |
   | M1e | `isFocusable` false | 1.4, 1.5, 1.6 |
   | M1f | the activation replaces the caller's `onKey` | 1.6 |
   | M1g | the `enabled` conjunct dropped from `Frame.registerHandlers`' focus registration and hitbox insert | 1.8, 1.12, 1.24 and 20 existing tests (D2, `aDisabledElementCannotAcquireFocus`, `aDisabledFieldTakesNoFocusAndNoText`, `aDisabledGridRegistersNoCellHitbox`, …; 23 in all) |
   | M1h | toggle gap 7 → 8 | 1.9 |
   | M1i | the toggle writes `isOn`, not `!isOn` | 1.10 |
   | M1j | `.checkBox` left out of the full fold | 1.11 |
   | M1k | the indicator filled by `Toggle.paint`, not a `Box` | 1.13 |
   | M1l | `EqualWidthRow` places each at its own ideal width | 1.14 |
   | M1m | an option writes its position | 1.15 (all three arms) |
   | M1n′ | an unmatched selection writes the first tag | 1.16, D2 (the segment arm's picker matches no tag) |
   | M1n | the partial fold removed | 1.17, 1.22 |
   | M1o | radio gap 6 → 8 | 1.18 |
   | M1o′ | the radio row's indicator gap 7 → 6 | 1.18 |
   | M1p | wrap-around | 1.19 |
   | M1q | option chrome built with no scope | 1.20 (leaf bounds and ids, `@State`) |
   | M1q′ | forwards only the three phases | 1.20 (`.id`, `@State`) |
   | M1r | `.checkBox` → AppKit `.button` | 1.21 |
   | M1s | the hint not stripped before the emptiness test | 1.23 |
   | M1t | the partial fold keeps only interactive descendants | 1.24 |
   | MG1.1 | `Toggle.init(_:isOn:)` internal | G1.1 |
   | MG1.2 | `public static let menu` added | G1.2 |
   | MS1 | AccessKit `toggled` dropped | `theFiveControlRolesMapToAccessKitWithToggledAndNumericValues` |
   | V16 | `Button`: `let activate = action` (a caller's `onClick` overwritten) | 1.6b `aCallersOnClickReplacesTheButtonsAction` |
   | V9 | `Toggle`: the write ignores a caller's `onClick` | 1.10c `aCallersOnClickReplacesTheTogglesWrite` |
   | V8 | `Toggle`: the caller's `onKey` not consulted | 1.10b `aCallersOnKeyRunsBeforeTheTogglesSpace` |
   | V15 | `Picker`: the caller's `onKey` not consulted | 1.19b `aCallersOnKeyRunsBeforeThePickersArrows` |
   | V18 | the option chrome takes no `elementID` | 1.20b `anOptionInsideAPickerTakesItsContentsIDAndKeepsItsState` |
   | V10 | `behindBarrier` pushes no `nil` | 1.20c `aTagNestedInsideAnOptionIsNotASecondOption` |
   | V12 | Return also toggles a `Toggle` | 1.10 |
   | V14 | → from no selection writes index 1 | 1.19 |

   The eight `V` rows are the verifier's mutants, each green at 1582; the
   fix round added 1.6b, 1.10b, 1.10c, 1.19b, 1.20b and 1.20c and extended
   1.10 (a Return arm) and 1.19 (an unmatched-selection arm). Each row is a
   full unfiltered run of **1588** tests, restored from a copy, `git status
   --short` empty after, and each reddened exactly the one test named.

6. **Two spec sentences corrected to the code** (amends `DD-V` item 2 and
   `DD-AC` item 10's wording). The picker scope is pushed around the
   content's **layout only**, not "each phase": an option's choice of chrome
   rides in its layout state, which is what `PickerScope`'s doc says; and
   the segmented options' group is `OptionRow`, not `SegmentRow`. Every copy
   (spec §4, `DD-V` item 2, `DD-AC` item 10 and its `SA-G` rejection) now
   reads the code's spelling; `grep SegmentRow` over the spec and this doc
   returns only this item.

**Cost if wrong.** Item 1 is one clause in `combine`; if task 12's VoiceOver
script prefers disabled options folded, it narrows back and 1.24 inverts.


---

## DD-AE — lane 2 (part 2): its mutation table; a registry arm, one fixture order and two readings the spec left open

**Ruling.** Lane 2 (`DD-W`, `DD-X`, `DD-Y`, `DD-Z` item 9) records its
mutations here; the items below say where the lane went past, or chose
inside, what the design said.

1. **The owner table gains `slider`** (a registry arm spec §10 did not list).
   `LoweringSite.slider` is a leaf lowered through `lowerLegacyLeaf` as
   `textField` is, so it is a tenth recording site of
   `everyReportNamesALiveOwnerOrIsRefusedByName`'s table: +4 leaf, +11 item
   and +9 unconsumed rows, **241 → 265** — `TI-H`'s precedent for
   `textEditor`. `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` gains
   its `Slider` arm (10 → 11 arms) as the spec said.
2. **An accessibility `.press` runs through the same `Window.runClick` as a
   mouse click** (amends spec §6, which named `dispatchClick` only): both set
   `ClickDispatch` — the mouse-up's modifiers for a click, `[]` for a press
   (2.21) — and both honour a `focusRequest` after the handler returns. One
   path, so the two cannot drift. The press's focus request is **not pinned
   by this lane** (2.22 clicks); lane 3's 3.16 presses a row and may pin it.
   *(Superseded by `DD-AF` item 5: 2.22b pins it in lane 2.)*
3. **A slider publishes its clamped value** (spec §4 said `<value>`), as
   SwiftUI's does — **measured**: SA5 publishes `value 10` for 15 on 0…10 and
   SA6 `value 0` for −3, and `Stepper` publishes its clamped value too
   (STA4). *Erratum (`DD-AF` item 3): this item first said what SwiftUI's
   slider publishes out of range was "unmeasured"; the probe header's SA5/SA6
   lines measured it. Pinned by 2.4's published-value line (V2).*
4. **2.1's nil-width arm reads `Slider.size(proposedWidth:)` directly.** No
   legacy container offers a leaf a nil width, and a legacy element cannot be
   a proposal stack's child to take `.fixedSize()`; the leaf's measure closure
   calls exactly this function, and the 300-proposal arm goes through a real
   frame. M2a (height 20) reddens it through the frame arm.
5. **Two fixture corrections before green, neither an implementation
   change.** 2.18's two arms each run in a fresh window, so the off-button arm
   reads its own 37 rather than a cumulative 74; 2.24 presses the field
   **before** the wheel — after the wheel it scrolls out of the 100-point
   viewport and its clipped hitbox is empty (measured: the press-after arm
   read `focusedElement == nil`).
6. **Stepper's shape inside the design.** The hairline is the lower half's
   top border (a paint-only `Decoration` border with per-edge `widths`), not
   a node; the increment mark is a `Stack` of two bars. The public
   requirements spell the full nested types rather than adding public
   typealiases, so no name joins the public API.

**The table.** Each row is a full unfiltered run of **1612** tests
(`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`), the source restored from a copy after,
`git status --short` empty after each (26 of 26). Applied to the lane's
implementation commit.

| Mutation | Change | Reddens |
|---|---|---|
| M2a | slider height 16 → 20 | 2.1, 2.4 (its 20×16 thumb lookup) |
| M2b | unstepped adjustment 10% → 5% | 2.2, 2.4, 2.7 |
| M2c | grid rounding half down | 2.3, 2.6 |
| M2c′ | no last-grid-point clamp | 2.3 |
| M2d | the clamp written back in `prepaint` | 2.4 |
| M2e | an unchanged adjustment not written | 2.3, 2.5 |
| M2f | `mouseDragged` not dispatched to `valueTrack` | 2.6 |
| M2g | ↑/↓ dropped from `ControlKeys.sliderStep` | 2.7 |
| M2h | the slider's adjustment handler not registered | 2.2, 2.3, 2.4, 2.5, 2.8 |
| M2i | the track's hitbox inserted through `pass.frame.insertHitbox` directly, bypassing the gate | 2.9, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` |
| M2j | the slider's preconditions removed | 2.10 |
| M2k | stepper gap 8 → 6 | 2.11 |
| M2l | an unchanged step written | 2.12 |
| M2m | stepping from the raw value | 2.13 |
| M2n | an unbounded stepper clamped at 0 | 2.14 |
| M2o | a nil `onDecrement` falls back to `onIncrement` | 2.15 |
| M2p | ↑/↓ swapped in `ControlKeys.stepperStep` | 2.15, 2.17 |
| M2q | the `DD-Y` rule reverted (no ancestor scroll) | 2.18, 2.24 |
| M2r | ancestry dropped (any scroller on the layer under the point) | 2.19 |
| M2s | the layer clause dropped | 2.20, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel` |
| M2t | `ClickDispatch.modifiers` not reset | 2.21 |
| M2u | the focus request ignored | 2.22 |
| M2v | a `textInput` target excluded from the ancestor walk | 2.24 |
| MG2.1 | `Slider.init(value:in:step:)` internal | G2.1 |
| M1g (re-run) | the `enabled` conjunct dropped from `Frame.registerHandlers`' focus registration and hitbox insert | 2.9, 2.23, 1.8, 1.12, 1.24, D2 and 19 more (25 tests) |
| M1n (re-run) | the partial fold removed | 2.16, 1.17, 1.22 |

M2p reddening 2.15 too is expected: its ↓ arm, with ↑/↓ swapped, runs the
closure stepper's increment. M2s reddening the demo-modal test is the layer
clause's second pin: the demo's scrim is declared inside a scroller's
subtree, so without the layer clause its wheel passes to that scroller.

**Cost if wrong.** Item 2 is one call site; if task 12 rules that a press
must not focus, `handleAccessibilityRequest` passes a discarding closure.
Item 3 is one `clamp` call.

## DD-AF — lane 2 (part 2) verifier fix round: the unpinned copies, the clamp, the scroll offset, the nearest scroller, the press's focus request

**Ruling.** The verifier found eleven lane-2 mutants green at 1612 (V1, V2,
V4b, V5, V6, V7, V13, V14, V15, and by the same shape the stepper's `onKey`
and declared-value copies). Nine tests were added and 2.4 gained a line; each
mutant now reddens exactly one test. No `Sources/` line moved.

1. **The caller-composition copies are pinned per control** (CLAUDE.md "A
   copy of a pinned implementation is unpinned"), as `DD-AD` pinned lane 1's:
   `Slider`'s and `Stepper`'s `onKey` precedence (2.7b, 2.17b), and each
   one's declared role, value and adjustment handler (2.8b, 2.16b — a caller
   declares `.image` through `handling`, `.accessibilityValue` and
   `.accessibilityAdjustableAction`).
2. **The pointer formula's `clamp01` and `ValueTrackTarget.minX`'s scroll
   offset are pinned**: 2.6b presses and drags an **unstepped** slider past
   both ends (it writes exactly 0 and 10 — 2.6's step re-clamps through
   `onGrid` and could not see the clamp); 2.6c presses a slider inside a
   horizontal `ScrollView` scrolled by 50 (offset written through the
   `StateTable`, then a redraw) and reads the value under the window x.
3. **DD-AE item 3's evidence is corrected in place** (quoted erratum there,
   and in record §58 §2.2): SA5/SA6 measured SwiftUI publishing the clamped
   value. 2.4 asserts `"10"` for 15 on 0…10.
4. **`DD-Y`'s "nearest ancestor" is pinned** by 2.19b (a click target inside
   an inner `ScrollView` inside an outer one, both covering the point: only
   the inner offset moves, 37).
5. **The press's focus request is pinned in this lane** (2.22b: an
   accessibility `.press` whose handler sets `ClickDispatch.focusRequest`
   moves focus), rather than left to lane 3's 3.16 as `DD-AE` item 2 said.
   2.21's press arm cannot see a bypass, since `ClickDispatch.modifiers`
   defaults to `[]`. **`allowsHitTesting(false)` removing the track** is
   pinned by 2.9b.
6. **2.18's changed answer gets its row** in record §58 §2.5 (old name, new
   name, first arm 0 → 37, `DD-Y`), which spec §10 said the record lists.

**The table.** Each row a full unfiltered run of **1621** tests (`swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel`), applied to the fix round's test commit, the source restored
from a copy after, `git status --short` empty after each (14 of 14).

| Mutation | Change (spelling applied) | Reddens |
|---|---|---|
| V1 | `ValueTrackTarget.minX` drops `offset.x` (`Slider.prepaint`) | 2.6c |
| V2 | the slider publishes `read()` unclamped | 2.4 |
| V4b | `Frame.registerHandlers`' hitbox condition `hitTestingDisabledDepth == 0 \|\| handlers.valueTrack != nil` | 2.9b |
| V5 | `clamp01` removed from `ValueStepping.sliderValue` | 2.6b |
| V6 | the `.press` case calls `StateDispatch.dispatching(to: id) { onClick() }`, not `runClick` | 2.22b |
| V7 | `enclosingScroller` keeps walking and returns the outermost match | 2.19b |
| V13 | the slider's arrows before the caller's `onKey` | 2.7b |
| V14 | the slider's role written unconditionally | 2.8b |
| V19 | the slider's value written unconditionally | 2.8b |
| V20 | the slider's adjustment handler written unconditionally | 2.8b |
| V15 | the stepper's adjustment handler written unconditionally | 2.16b |
| V16 | the stepper's arrows before the caller's `onKey` | 2.17b |
| V17 | the stepper's role written unconditionally | 2.16b |
| V18 | the stepper's value written unconditionally | 2.16b |

**Cost if wrong.** Tests only; each is one fixture.

## DD-AG — lane 3 (part 2): the scroller's first frame keeps AB-X rule 1; its mutation table; the counts; one pre-existing `@State` finding

**Ruling.** Lane 3 (`DD-Z`, `DD-AA`, `DD-AC` items 1, 2, 4, 6 and 10) records
its mutations here; the items below say where the lane went past, or chose
inside, what the design said.

1. **A selectable list publishes button rows only while its window can
   NEVER be bounded** (amends `DD-AC` item 6): no vertical scroller, or a
   zero `rowHeight`. On an enclosing scroller's **first** frame (the viewport
   not yet measured, `windowAwaitsViewport`) it keeps AB-X rule 1 — the
   table, no rows, one retry frame — exactly as a list without `selection:`
   does, so a client active at frame 0 is not handed one button per datum
   and then told they were all destroyed on the next frame (AB-X's own
   reason). `List.prepaint`: `if !selection.isNone, !windowIsBounded,
   !windowAwaitsViewport` publishes the rows unsuppressed; every other
   unbounded frame is suppressed as before. **This clause was unpinned at
   `f1f9683`** (M3t green over the whole suite); 3.20b, an arm of 3.20
   (`0bfb915`), pins it — no test is added to the count.
2. **The stale element binding is MetalUI's own rule** (`DD-AA`, unprobed):
   a `ForEachBindingSlot` keeps its index, its id and a `LastRead` box; its
   binding reads `data[index]` while that element still carries the id and
   otherwise returns the last value it read, and a write to a stale slot is
   dropped — no trap, no write to whatever element now sits at the index.
   No divergence is claimed.
3. **A pre-existing `@State` bug, found by the controls demo, not fixed
   here** (state retention must not move unless ruled): an optional `@State`
   with a non-`nil` initial value (`@State var picked: Int? = 2`) reads `nil`
   until its first write. `State.wrappedValue` is
   `table.peek(slotID, as: Value.self) ?? initialValue`, and with `Value ==
   Int?` the cast `storage[id]?.value as? Int?` of an absent entry succeeds
   as `.some(nil)` (measured with a standalone `swiftc` program: `peek` of
   an empty dictionary as `Int?` prints `Optional(nil)`, and `?? 2` gives
   `nil`), so the initial value never runs. The demo uses a `Set<Int>`
   instead. **Owner: the Record phase decides, before task 10 is ticked**
   (`DD-AH` item 4: either fixed under its own ruling with a red-first test
   and a migration note, or an owning plan task named in record §58 and the
   divergence or inert table) — it is a one-line fix in
   `StateTable.peek` or `State.wrappedValue` (distinguish an absent entry
   from a present `nil`) and a behaviour change to every optional `@State`
   with a non-`nil` default, so it wants its own ruling and test, not a
   lane-3 edit.
4. **Counts.** `swift package clean`, then **`Test run with 1643 tests in 3
   suites passed`** — not the spec's 1628: lane 1's fix round (+6, `DD-AD`)
   and lane 2's (+9, `DD-AF`) added 15 the critic round's arithmetic did not
   carry, so 1556 + 26 + 6 + 24 + 9 + 22 = **1643**. Guards +1 (G3.1:
   `SELECTION GUARD G3.1 positive: succeeded=true`, `control:
   succeeded=false`).
5. **Native depth, measured through a real `Window`** (`DD-AC` item 10; each
   control alone in the controls' own root, printed by 3.19): `Button` 6,
   `Toggle` 5, `Slider` 3, `Stepper` 10, `Picker` segmented 10, `Picker`
   `.radioGroup` 7, a `List(selection:)` in a `ScrollView` 13; the controls
   demo **15** — all at most 40, against `maxDepth` 72.

**The table.** Each row a full unfiltered run of **1643** tests (`swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel`), the source restored from a copy after, `git status --short`
empty after each (28 of 28). Applied to `f1f9683` (the lane's implementation
plus 3.8's caller arm), except M3t's second run and MG3.1′, applied to
`0bfb915` (3.20b).

| Mutation | Change (spelling applied) | Reddens |
|---|---|---|
| M3a | a plain multi click inserts (`next = current; next.insert(row)`) | 3.1, 3.16 |
| M3b | the shortcut toggle replaces (`next = [row]`) | 3.2 |
| M3c | the ⇧-click range drops the anchor's row | 3.3 |
| M3d | ⌘ on the selected row deselects in single mode | 3.4 |
| M3e | `ClickDispatch.focusRequest = list` removed from the row click | 3.5 |
| M3w | the list's `isFocusable = true` removed | 3.5, 3.6, 3.7, 3.8, 3.12 |
| M3f | the arrows wrap at the ends (`% count`) | 3.6, 3.7 |
| M3g | ⇧+arrow extends from the lead where the anchor is stored | 3.7 |
| M3h | ⌘A selects every row of a multi list | 3.8 |
| M3v | the list's arrows before the caller's `onKey` | 3.8 |
| M3i | the selection hint never set | 3.9, 3.10, 3.11, 3.19, 3.20 |
| M3j | a single selection naming an absent id pruned to `nil` in `requestLayout` | 3.10 |
| M1g (re-run) | the `enabled` conjunct dropped from `Frame.registerHandlers`' focus registration and hitbox insert | 3.11 and 25 more (26 tests) |
| M3k | the reveal never enqueued (`if false, let scope = id.parent`) | 3.12 |
| M3k′ | the reveal keyed by the bare `datum.id` | 3.12 (its 3.12b arm) |
| M2q (re-run) | the `DD-Y` rule reverted (no ancestor scroll) | 3.13, 2.18, 2.19b, 2.24 |
| M3l | the selected row's `.accent` background removed | 3.14, 3.15, 3.11 |
| M3m | the hint declared as a `.selected` trait (writes `$ax`) | 3.15 |
| M3n | the rows' `onClick` set only while no client is active | 3.16, 3.20, 3.11 |
| M3o | every binding slot at the collection's first index | 3.17, 3.18 |
| M3p | the stale-binding id check removed | 3.18 |
| M3q | the demo's list built without `selection:` | 3.19 |
| M3s | `logicalIndex` set on unbounded rows too | 3.20 |
| M3r | the lead re-derived by a data scan in `requestLayout` | 3.21 |
| M3t | the `windowAwaitsViewport` clause dropped (item 1) | **none** at `f1f9683`; 3.20 (its 3.20b arm) at `0bfb915` |
| MG3.1 | the `Set` initialiser `internal` | does not build: `ControlsDemo.swift` (another module, a plain import) calls it — a compile error in production code is its own pin |
| MG3.1′ | the single-selection initialiser `internal` | G3.1 |
| V3 (fix round) | the origin write resets the entry (`{ $0 = ListOrigin(offset: origin) }`) | 3.3 (its 3.3b arm), 3.7 (its 3.7b arm, at its control line: the second ⇧↑ already reads `[1, 2]`) |
| V4 (fix round) | the `reveal.list == id` conjunct dropped from `resolveScrollRequests` | 3.12 (its 3.12c arm: 20, not 220) |
| V5 (fix round) | a multi click always writes (`binding.wrappedValue = next`) | 3.1 (its 3.1b arm) |
| V6 (fix round) | a multi arrow always writes (`binding.wrappedValue = selected`) | 3.7 (its 3.7c arm) |

M3l reddening 3.11 is its background line (the disabled list still paints
its selection); M3n reddening 3.11 is its every-row-publishes line (a
disabled row with no `onClick` resolves as no button). 3.13's re-run of M2q
reddens it alone among lane 3's tests, as the joint test should.

**Cost if wrong.** Item 1 is one conjunct; item 3 is deferred, not changed.

## DD-AH — lane 3 (part 2) verifier fix round: the anchor under the origin write, the reveal's list, the multi no-write guards

**Ruling.** The verifier found four clauses of `DD-Z`/`DD-AC` that no test
saw (its V3–V6, each green over the whole 1643-test suite at `2dcb05e`, each
shown to behave differently by a scratch test). Each is now pinned by an arm
of an existing test — **no test is added, the count stays 1643** — and the
four mutations join `DD-AG`'s table, re-run on `7c478d6` (the arms), each a
full unfiltered run, the source restored from a copy, `git status --short`
empty after.

1. **Lead and anchor survive the scroller's per-frame origin write**
   (`DD-Z` item 7). Every ⇧-click and ⇧-arrow test used the unbounded
   fixture, where `noteOriginAndStaleness` returns before writing, and every
   anchor there was also the first selected row in data order, which is
   exactly what a reset entry re-derives. Arms 3.3b (click 3, ⇧-click 1 →
   `[1, 2, 3]`, ⇧-click 4 → `[3, 4]`) and 3.7b (click 3, ⇧↑ ⇧↑ → `[1, 2, 3]`,
   ⇧↓ → `[2, 3]`) run in the scrolled fixture with an anchor that is not the
   first selected row. V3 reddens both.
2. **The lead reveal is taken only by the list it names** (`DD-AC` item 2,
   whose "pinned by" sentence carries an erratum). Arm 3.12c: two single
   lists in one 100-pt scroller, 10 rows above 100 rows with selection 4;
   the lower list focused, ↓ → offset **220** (the lower list's row 5). V4
   reads 20 (the upper list's row 5).
3. **A multi list writes only a changed selection** (`DD-Z` items 4 and 6).
   Arm 3.1b: multi `[2]`, a plain click on row 2 writes nothing (V5 writes
   `[2]`). Arm 3.7c: multi `[4]` with the lead at the end, a plain ↓ writes
   nothing (V6 writes `[4]`). The latter rests on `DD-Z`'s general rule,
   unprobed: the probe measured only KY8g's `[2, 3, 4]` → `[4]`.
4. **The optional-`@State` finding (`DD-AG` item 3) is not fixed here**: it
   is a behaviour change to every optional `@State` with a non-`nil`
   default, so it wants its own ruling, test and migration note. **Task 10
   is not ticked until the Record phase has either fixed it that way or
   named an owning plan task in record §58 and the divergence or inert
   table.**

**Cost if wrong.** Test arms only; no source line moves.

---

## DD-AI — the Record phase's close: the guard-count reading corrected; the optional-`@State` bug named divergence 85, owner plan task 15

**Ruling.**

1. **Lane 1's issue 5 is retracted, not the design.** `grep -c canTypecheck`
   summed over `Tests/MetalUITests` alone reads 94 at `27b2fcc` and 98 at
   `87e3f9c` — a narrower sum than the one CLAUDE.md's own "Guards" bullet
   defines, which spans `Tests/MetalUITests` **and**
   `Tests/MetalUICoreTests/UnitSafetyTests.swift` (discounting one comment
   hit there). Summed the canonical way: **96** at `27b2fcc`, **100** now.
   The design's "96 + 4 = 100" (spec line 495) was right throughout; nothing
   in the spec or this doc needs correcting for it. Record §58 §4 carries the
   arithmetic.
2. **`DD-AG` item 3's optional-`@State` bug is disposed of, not fixed, per
   `DD-AH` item 4's own condition.** A one-line fix
   (`StateTable.peek`/`State.wrappedValue` casting an absent entry to an
   optional `Value` as `.some(nil)` before `?? initialValue` runs) changes the
   observable answer of every optional `@State` with a non-`nil` default
   across the framework — a behaviour change wanting its own ruling,
   red-first test and migration note, not a docs-phase edit made without a
   fix round to verify it. It is named **divergence 85**, added, kept, owner
   **plan task 15** (closeout) — record §04's 2026-09-28 section and record
   §58 §5 carry the same wording. The controls demo's `Set` workaround
   (`DD-AG` item 3) is unchanged.
3. **Task 10 is ticked** (`DD-AB` item 1): items 1 and 2 above were the two
   things standing between "every lane verified `ok`" and "every clause of
   the task's text closed" — record §58 §9's table closes the rest by
   citation, none of it newly found here.

**Evidence.** The guard sums in record §58 §4; `DD-AG` item 3, `DD-AH` item 4.

**Cost if wrong.** Item 1 is a reading, not a fact — the total (100) does not
move either way. Item 2 is deferred work with a named owner; if plan task 15
finds a different owner more fitting, this ruling's "plan task 15" is one
citation to move, not a behaviour to undo.
