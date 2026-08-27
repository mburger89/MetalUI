# Structural identity — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-27-metalui-structural-identity.md`, in order.
Each says what was decided, why, and what it costs if wrong.

**Ruling IDs here are prefixed `SI-` and are LETTERED, `SI-A`…`SI-H`.** A bare
`SI-3` is therefore a typo, not a citation. `PF-`/`C-` belong to m1a, `FS-` to
flex sizing, `AL-` to alignment, `BM-` to the box model, `WR-` to wrapping,
`EP-` to the element pipeline, `CS-` to content sizing. A bare `F-n` is
ambiguous across three documents — sweep for stray citations
**case-insensitively**, since a `Ruling F-3` survived two branches' greps for
lowercase `ruling`.

**Spec:** `docs/superpowers/specs/2026-08-27-structural-identity-design.md`.
**Parent spec:** `docs/superpowers/specs/2026-08-24-metalui-design.md` §4.3.
**Ruling this milestone serves:** EP-5 — where CSS and SwiftUI answer a design
question differently, take SwiftUI's answer.

## During execution

| # | Ruling | Cost if wrong |
|---|---|---|
| SI-A | **Task 2's call-site shim was deliberate and temporary, and the sentence justifying it was false.** The shim passed `at: 0` at every call site so the type could change one task before the cursor arrived. The pre-flight note said siblings would therefore collide for one task, with the surviving separator being the nil short-circuit. **They did not collide.** `child(of:at:name:)` spells the component `name.map(PathComponent.named) ?? .positional(index)`, and the shim's call sites all had a non-`nil` name, so `.positional` was never built in production and `at: 0` was **dead code** — a type-level fact, confirmed behaviourally by an `at: 99` probe that left 349/349 green. The shim stays justified on its real ground: the task is behaviour-preserving by construction, so the gate is "all 342 stay green", and a broken shim reddens the suite immediately. | A reader believes a collision window existed and goes looking for what closed it. Worse in the other direction: a dead parameter that a comment says is load-bearing is exactly taxonomy shape 4 with the sign flipped. |
| SI-B | **A predicted test count is a prediction, never a target.** The plan predicted 342 → 348 for Task 1 and an additive total for Task 2. Task 1 shipped at **349**, Task 2 at **358**, and Task 2 *rewrote* three tests rather than adding them, so its total was never additive. The measured number wins; no test is added, adjusted or deleted to reach a predicted one. What is load-bearing is the direction: a count that **falls** without a deletion you can name is taxonomy shape 11 — a truncated run — and is a failure until explained. (Content sizing's CS-B, restated because it bit twice there.) | A number in a plan quietly becomes an instruction, and someone deletes a real test to hit it. |
| SI-C | **A type replacement cannot be staged behind its own call sites.** The plan's Task 1 added the linked-list `GlobalElementID` "beside" the existing struct and gated on all 342 tests staying green, leaving the call sites to Task 2. **Swift cannot have a struct and a class share one name in a module**, so the gate was unreachable by construction. Measured before stopping: **10 `error:` diagnostics, all three at the sites the dispatch predicted** (`ElementGroup.swift:81`, `:421`, `Frame.swift:188`), **zero inside `ElementID.swift`**; `swift build --build-tests` failed the same way, so no test count existed to report. Tasks 1 and 2 merged, the shim became a step rather than a task, and Tasks 3-5 renumbered to 2-4. **The implementer reported rather than quietly doing the neighbouring task's work** — the third time on this project that a refusal was the finding. | A task whose exit criterion cannot be evaluated is executed on faith, and the "green" it reports is a build that never happened. |
| SI-D | **A test of a deleted API moves with the API; a test of behaviour stays until the behaviour changes.** After the shims fixed production (`swift build` clean), `swift build --build-tests` still failed with **84 errors across three test files**, none of them touched. The gate — "all 342 stay green including the four that assert the nil-poisoning rule" — was wrong for two of the four: they call `GlobalElementID.child(of:_:)` **directly** and assert it returns `nil`, and a signature with no `Optional` in that return position cannot keep them compiling. The split that resolved it: **category A (6 sites)** — old array-literal `GlobalElementID([...])` building *expected* values for `==`, mechanically translated, no assertion's outcome changed; **category B (2 tests)** — direct calls to the removed optional-returning API, rewritten one task early, renamed to what they check, each commented with what it used to assert and where the surviving coverage is. **The behavioural reversal stayed visible**: `anIdentifiedChildOfAnUnnamedContainerStillHasNoIdentity` reaches nil-poisoning through the *shim* rather than the static method, so it stayed green and untouched until Task 2 deliberately reversed it. | Deferring category B means committing a branch that does not build. Conflating the two categories means a behavioural reversal disappears into a mechanical translation and nobody reviews it. |
| SI-E | **`cachedHash` and `==` are safe individually and unsafe only together — and the spec's central safety claim named the wrong line.** The design called omitting the parent from `cachedHash` "the single most dangerous line in the milestone" and claimed a test whose mutation is exactly that omission. Measured, `--no-parallel`, re-confirmed in Task 4 at **358 tests**: dropping the parent from `cachedHash` reddens **exactly one** test (`theHashItselfDistinguishesPathsDifferingOnlyInAnAncestor`, the guard added for it); replacing the whole of `==` with `l.cachedHash == r.cachedHash` reddens **nothing at all**. Neither is dangerous alone. `==` uses the hash as a fast *reject*, so a collision falls through to the chain walk, which hash quality does not affect, and `Set`/`Dictionary` correctness resolves through `==` rather than through distribution. A degraded hash alone is a **performance** defect — a sharp one *because of this milestone*, since once every node is identified most components are `.positional(k)` and every node at the same index in the tree hashes into one bucket, taking `StateTable` quadratic per frame. **The load-bearing line is `==`'s chain walk.** The hash half *is* guardable and got a six-line test asserting on the public `hashValue` (no visibility change needed: `hash(into:)` is `hasher.combine(cachedHash)`). The `==` half is **not** guardable — a 64-bit collision is not constructible against a per-process-seeded `Hasher` — so taxonomy shape 6 requires the mechanism be **stated at `==`**, which it is, and the exit criteria ask for that statement rather than an impossible test. **Narrowed in the fix round:** it is the hash-shortcut *spelling* that no test can reach (green at 349/356/358/360 every time), not the chain walk as such — discarding the walk outright (`return l.component == r.component`) fails two tests and then traps the process on a `Set` invariant, which is loud but has no reproducible count. See the fix-round section below. | Two unrelated elements silently share one `StateTable` entry, with nothing in layout or paint able to see it. And in the direction this actually went: the milestone's stated worst failure mode was guarded by a test that could not fail for it, while the line that mattered had no comment at all. |
| SI-F | **`EitherGroup`'s taken branch gets a path level of its own; a flat pair of indices is wrong.** The brief specified `.positional(cursor)` for the first branch, `.positional(cursor + 1)` for the second, advancing the outer cursor by 2. That separates the branches only while each holds **one** element. Measured against that spelling on `if flag { C(); C() } else { C() }` across a flip: the `else` element found the second if-branch element's entry and incremented it to 2 — **an inheritance, not a reset.** The shipped form gives the taken branch its own `GlobalElementID` and numbers its members from 0 *inside* it: one allocation per `if`/`else`, correct at any branch size. Spec §3.5 carried the same defect one level worse — literal `0`/`1` rather than `cursor`/`cursor + 1`, which collides between two sibling `if`s in one container — and is corrected. **The outer cursor advances by 2 because the branch RESERVES both slots — and this ruling originally gave the wrong reason.** It said "so a later sibling's index does not depend on which branch was taken", which is true under `cursor += 1` as well: the advance happens *before* the switch. Measured in Task 4's fix round — `Row { if flag { C() } else { C() }; C() }` across a flip puts the trailing element at `.positional(1)` on **both** frames under `+= 1` and it counts 2 either way, so its state survives. What `+= 2` actually buys is that nothing else in the container may occupy the slot the **untaken** branch would have used. `EitherGroup` can afford to reserve two only because its width is bounded at two. Pinned by `flippingAnEitherBranchResetsTheBranchesState` and `aBranchWithTwoMembersDoesNotLeakStateIntoAOneMemberBranch` for the component, and by `aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne` for the advance; giving both branches the same component reddens **exactly the first two and nothing else** (re-measured Task 4, `--no-parallel`, 358 tests, edit: `.positional(branchIndex)` in place of `.positional(branchIndex + 1)`), and `cursor += 1` reddens **exactly the third** (360 tests). | Flipping an `if`/`else` hands the new branch the old branch's scroll offset, hover and animation progress — a wrong frame with no diagnostic, on a construct as ordinary as an `if`. |
| SI-G | **A vanishing `if` makes the trailing sibling ADOPT the vanished element's state, not reset — and the remedy is naming the trailing sibling, not the conditional content.** `OptionalGroup`'s comment said an `if` going false "shifts every later sibling's index and **resets** their state", and the plan's risk list and spec §5 both asserted the behaviour was "pinned as deliberate" while `grep` found no such test — one inaccurate sentence standing in for two claimed pins. Measured on `Row { if flag { C() }; C() }` across a flip: the trailing element lands on the vanished element's `.positional(0)` and reads **2**, not 1. Both halves of the remedy were measured rather than transcribed: naming the **conditional content** removes the inheritance and still leaves the reset (trailing element reads 1); naming the **trailing sibling** carries its state through intact (reads 2). The hazard is about later siblings, so naming *them* is the answer — which is the half the advice in the brief got wrong. Pinned by `anElementAfterAVanishingIfAdoptsTheVanishedElementsState` and `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`. **Why shifting is right at all**, beyond "SwiftUI does it": the alternative is reserving a slot for an absent `if`, which makes the container's index space depend on branch *width*, and that width is unbounded. | A reader's intuition says "reset", the comment agreed with the intuition, and the code did something strictly more surprising. The consequence is a trailing sibling that inherits an unrelated element's state — the same failure SI-E guards at the key, arriving through the cursor instead. |
| SI-H | **A mutation count measured mid-task is stale by the end of the task, and three of this milestone's five were.** Task 2's measurements were recorded in `f5305ea` against a **356**-test suite; the fix commit `02bf010` then added two tests (`anElementAfterAVanishingIfAdoptsTheVanishedElementsState`, `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`) that are sensitive to the same cursor arithmetic. Re-measured in Task 4, `--no-parallel`, 358 tests: deleting `cursor += 1` reddens **five**, not the three recorded; folding the index into the name reddens **six**, not five; `child(of: nil, …)` in `Element.requestGroupLayout` reddens **ten**, not eight. Every under-count is by exactly those two tests. The two counts that reproduced unchanged are SI-E's and SI-F's, both of which name their reddened tests individually rather than only counting them. **So the rule is CS-N's, sharpened: record which tests moved, and re-measure at the task's final commit rather than at the commit that took the number.** | A count that is quoted as a coverage measurement is off by whatever the fix round added, and the next person to mutate the same line concludes their edit differed — which is exactly the review cycle CS-N exists to prevent. |

## The design decisions this milestone rests on

These were settled in the design rather than during execution, but each is
load-bearing enough that a future change will want the reasoning.

### A name REPLACES a position; it never joins it

`PathComponent` is an either/or — `.positional(Int)` or `.named(ElementID)` —
which makes the rule enforceable by the type rather than by convention. Inside a
list keyed by id, the id *is* the identity, so reordering carries each item's
state with it. If the index were also in the key, an item moving from index 0 to
1 would mint a new key and lose its scroll offset, hover and animation progress
on every move — the opposite of what `.id()` exists for. Outside such a list,
structural position is the identity, which is what gives an unnamed element
state at all.

`child(of:at:name:)` takes the index **unconditionally** even when a name is
present, so no call site ever decides which of the two to supply: the decision
lives in one function.

**Measured:** folding the index into the name —
`name.map { PathComponent.named(ElementID("\($0.name)#\(index)")) }` — reddens
six tests (`--no-parallel`, 358: `reorderingANamedListCarriesEachItemsState`,
`aNameReplacesThePositionRatherThanJoiningIt`,
`childOfAnUnnamedParentStillHasAnIdentity`,
`aContainerGivesItsChildrenPathsBuiltFromItsOwn`,
`twoSiblingsWithTheSameIDShareOneStateEntry`,
`namingTheLaterSiblingIsWhatSurvivesAVanishingIf`).

### Two siblings with the same `.id()` collide, deliberately — not pending

They share one `StateTable` entry. That is SwiftUI's documented duplicate-id
hazard, and it is **pinned rather than trapped**: trapping would forbid an
`ArrayGroup` whose data genuinely contains duplicate keys, turning a data bug in
a shipping app into a crash. `twoSiblingsWithTheSameIDShareOneStateEntry` lost
its "for now" when this was decided, and the name is the record — a test called
`…ForNow` reads as a placeholder for work someone still owes.

### A persistent linked list, not an array

Before this milestone `child(of:_:)` did `GlobalElementID(parent.path +
[component])` — an array copy per level, O(depth) per node — and only *named*
subtrees paid it. Universal identity makes every node pay it every frame, in a
framework that rebuilds every element every frame. Sharing the tail makes a
child **one allocation regardless of depth**: O(n) per frame rather than
O(n·depth). The figures are in the next section.

The class brings one hazard the struct did not: `===` becomes spellable
alongside `==`, and they differ — two structurally identical paths built on
different frames are `==` and never `===`. **Only `==` may be used for lookup.**
`StateTable` is keyed on `Hashable` so it uses `==` by construction; the hazard
is a hand-written comparison elsewhere, and no production code compares ids
outside the table.

Retention is unchanged in substance: a `StateTable` key holds its whole ancestor
chain alive, bounded by live entries and released by the sweep. The array
representation held the same components.

### The index space is FLAT, and deliberately does not inherit the builder's nesting

`Column { A; B; C }` has the type `Column<Pair<A, Pair<B, C>>>` — pinned at the
type level by `aThreeChildBlockNestsPairsRatherThanFlattening` — but identity is
`A=0, B=1, C=2`, not `A=[0], B=[1,0], C=[1,1]`. Flat is SwiftUI's model (a
`TupleView`'s children are positionally flat whatever the tuple shape) and it is
more stable: under nesting, changing *how* the builder groups children could
shift paths when the visible child order did not. `Pair` therefore hands the
**same** cursor to both halves in order. Pinned by
`theIndexSpaceIsFlatRatherThanNested`.

**Only `requestGroupLayout` carries a cursor**, and the three phases cannot
disagree about an index rather than merely agreeing by convention:
`SingleElementLayout` and `AnyElement.GroupLayout` **store** the id built during
layout, so `prepaintGroup` and `paintGroup` read `layout.id` and never re-derive
one. That is deliberate — an element is a value the container may mutate, and a
path recomputed in `paint` from a changed `elementID` would silently address a
different entry than the one `requestLayout` marked.

## The measurement: path construction on branching trees

**Measured 2026-08-27 on the machine that ran this milestone. Debug unless a
column says release. Throwaway spike, deleted with the task — a spike's output
is a number, not code. Re-measure before deciding anything on these; a
performance figure drifts more quietly than a behavioural one.**

The counterfactual is the pre-milestone array representation reconstructed
beside the shipping one (`(parent?.path ?? []) + [component]`), so the two are
measured on the same trees in the same process. Best of five, one path
constructed per node.

| tree | nodes | avg depth | linked µs/node | array µs/node | ratio |
|---|---|---|---|---|---|
| 13 levels, branch 2 | 8,191 | ~12 | **0.154** / 0.093 rel | 0.697 / 0.300 rel | 4.5× / 3.2× rel |
| 11 levels, branch 3 | 88,573 | ~10 | **0.150** / 0.088 rel | 0.660 / 0.272 rel | 4.4× / 3.1× rel |
| 3 levels, branch 90 | 8,191 | ~3 | **0.144** / 0.084 rel | 0.501 / 0.141 rel | 3.5× / 1.7× rel |

**The third row is the control and it is what makes this a measurement of the
claim rather than of the tree.** It holds the node count at exactly 8,191 and
drops the average depth from ~12 to ~3.

**Read the RELEASE column for the O(1) claim; the debug column does not separate
the two models.** In release the linked list moves 0.093 → 0.084 µs/node (−10%)
against the array form's 0.300 → 0.141 (−53%) — 2.1× for a ~4× depth difference,
with the remainder being the array allocation a shallow path still pays. In
debug the linked list's own sensitivity is of the same order as the array's
(−6% against −28% here; an independent re-run of the same spike measured −25%
against −18%, i.e. the two swapped rank), because allocation and retain/release
traffic dominate both. The debug figures are the honest absolute cost and the
release figures are the evidence for the complexity claim; quoting the debug
control as "flat" overstates it, which an earlier draft of this section did.

**A branching tree is required and a chain cannot show this** — content sizing's
Task 6 made that mistake and had to correct it. Here the reason is different but
the conclusion is the same: a chain of depth *d* has *d* nodes, so total cost
and per-node cost cannot be separated from depth at all.

### End to end, the improvement is NOT visible above noise on the smaller tree

`Frame.render` on the same trees, three iterations each:

| tree | nodes | debug (best / spread) | release (best / spread) |
|---|---|---|---|
| 13 levels, branch 2 | 8,191 | **369.5 ms** / 7.2 ms | **51.6 ms** / 3.2 ms |
| 11 levels, branch 3 | 88,573 | **3,540 ms** / 19 ms | **520.7 ms** / 3.3 ms |

Path construction is **0.3-0.4% of a debug render and ~1.5% of a release
render**. The saving over the array form is 4.5 ms on the 8,191-node tree
against a 7.2 ms run-to-run spread — **below noise**, and it stays below noise
in release (1.7 ms against 3.2 ms). On the 88,573-node tree it is 45 ms against
a 19 ms spread in debug and 16 ms against 3.3 ms in release: measurable, and
still ~1.3% of the frame.

**Reported plainly because that is worth more than a number nobody can
reproduce.** The data structure is 3-4.5× cheaper at the thing it does, and at
today's costs that thing is a rounding error next to `computeLayout`. The
decision still stands on its own terms — it removes a depth factor from a
per-frame cost for one allocation's price, and the layout constant is the part
expected to fall.

**These render figures also re-confirm CLAUDE.md's layout table on this
machine**: 369.5 ms and 3,540 ms against the 372.0 ms and 3,504.4 ms recorded
during content sizing, for the same node counts.

## What this milestone falsified

Four committed tests encoded the old rule **in their names**. All were rewritten
to the opposite assertion, never deleted, each carrying a comment naming what
changed:

| was | is | file |
|---|---|---|
| `anIdentifiedChildOfAnAnonymousParentHasNoIdentity` | `childOfAnUnnamedParentStillHasAnIdentity` | `StateTableTests.swift` |
| `twoAnonymousSiblingsChildrenCannotCollideBecauseNeitherHasIdentity` | `childrenOfDistinctUnnamedParentsDoNotCollide` | `StateTableTests.swift` |
| `anIdentifiedChildOfAnUnnamedContainerStillHasNoIdentity` | `anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition` | `ElementLayoutTests.swift` |
| `twoSiblingsWithTheSameIDShareOneStateEntryForNow` | `twoSiblingsWithTheSameIDShareOneStateEntry` — the collision is deliberate, not pending | `ElementGroupTrapTests.swift` |

The centrepiece is the third. It renders the **same tree** its predecessor did,
so the two assertions can be read against each other, and it now asserts the
full three-component path `root → .positional(0) → named` **plus** a `!=`
against the two-component path a "borrow the parent's id" container would
produce — strictly more than the `== .some(nil)` it replaced. A new
`GlobalElementIDTests.swift` carries seven further tests for the key itself.

**`nil` left the identity a phase receives.** `Element`'s three phases,
`ElementGroup`'s three, and `StateTable.withState` all take a non-optional
`GlobalElementID`, and `StateTable.withState`'s `guard let id else { …scratch… }`
branch is **deleted rather than unreachable**. The optional survives at **six**
code sites, and they are not all the same kind. Five are forced by a root having
no parent: `GlobalElementID.parent`, `init`'s and `child`'s `parent` parameters,
and two locals inside `==`. The sixth — **`requestGroupLayout`'s `parent`**, on
all eight conformances — is **not forced, it is inert**: `Frame.render` builds
the root id itself and never calls `requestGroupLayout`, so every production call
site passes a non-optional and nothing would break if the parameter lost its `?`.
It is left as-is rather than tightened because doing so touches eight signatures
and every hand-built test group for no behavioural gain, and it is recorded here,
at its declaration, in spec §6 and in the plan's exit criterion so that the four
agree. **They did not agree**: the plan named two sites, spec §6 named four, and
this paragraph named five while calling them all root-forced.

**`prepaintGroup` and `paintGroup` lost `under parent:`, and it was inert by
demonstration rather than by argument.** Task 2 established that twice without
setting out to: `EitherGroup` forwarded `under: parent` where `under: branch`
was correct, and the suite was **358 green with the wrong value and 358 green
with the right one**. A parameter whose wrong value changes nothing is dead.
Task 1's `at: 99` probe is the same shape.

## Two lines the branch shipped unguarded, closed in the fix round

Whole-branch review measured every mutation in the new code. **Exactly two
reddened nothing**, and both are index arithmetic asserted as a property in two
documents each — taxonomy shape 9, an untested composition rather than untested
code.

| edit | before the fix round | after |
|---|---|---|
| `EitherGroup.requestGroupLayout`: `cursor += 2` → `cursor += 1` | **358 green, 0 red** | reddens exactly `aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne`, 360 tests, 3 issues |
| `AnyElement.requestGroupLayout`: delete `cursor += 1` | **358 green, 0 red** | reddens exactly `twoErasedSiblingsDoNotShareOneStateEntry`, 360 tests, 3 issues |

**Finding the first composition took three candidates and a probe, and the
obvious one does not work.** The natural reading of the `+= 2` property — "a
later sibling's index must not depend on the branch taken" — suggests
`Row { if flag { C() } else { C() }; C() }`. Measured under `+= 1`: the trailing
element moves from `.positional(2)` to `.positional(1)` but sits at the *same*
index on both frames of a flip and **counts 2 either way**. It cannot pin the
line. What breaks is a sibling that lands on the untaken slot and then goes one
level deeper — `Row { if flag { C() } else { C() }; Row { C() } }` collapses two
entries into one reading **3** — or two sibling `if`/`else`s, spec §3.5's own
collision, which collapses into one reading **2**. The first is the shipped test.

**The second was invisible for a structural reason worth naming:**
`AnyElement.requestGroupLayout` is a hand-copied duplicate of `Element`'s
default, and its doc comment said "identical to `Element`'s default" — which is a
claim about two separate lines. `Element`'s tests cannot reach the copy, and no
test in the repo had ever put two `AnyElement`s with cross-frame state in one
container.

**One further absolute was narrowed.** `==`'s doc said "nothing in the suite
guards this loop, and nothing can". Losing the chain walk outright *is* caught:
replacing the body with `return l.component == r.component` fails
`pathsDifferingOnlyInAnAncestorAreNotEqual` and
`differentDepthsWithTheSameTailAreNotEqual` and then **traps the process** —
`Fatal error: Duplicate elements of type 'GlobalElementID' were found in a Set.`
That mutation therefore has **no reproducible count**: it is a truncated run with
no summary line (taxonomy shape 11), and two runs of it reported four failing
names and three. What is genuinely unguardable is the *hash-shortcut* spelling,
which stays green with a summary line. The doc now says which.

## Deliberately not done

- **Tombstones and exit transitions** (§4.3, §14). Universal identity makes
  tombstones *more* useful and no easier — it is a change to the **sweep**, not
  to the key. Both consequences §4.3 records stand unchanged.
- **A `ForEach` element.** `ArrayGroup` already exists and is what a builder's
  `for` loop produces.
- **Trapping on duplicate sibling ids.** See above — it would turn a data bug
  into a crash.
- **Any change to mark-and-sweep.** Only the key changed.
- **EP-6's re-decision** (`Column`/`Row` centring by default). Unblocked by
  content sizing, untouched here, and still open.
- **A production `MeasureFunction` on a leaf.** `newLeaf` still has no caller in
  `Sources/`; that is M2 and nothing here moves it.

## A process note worth keeping

**A malformed plan does not fail loudly — it fails as a missing task.** A
scripted edit left the plan with an odd number of code fences, so everything
after it read as inside a code block and the brief tool reported "no heading
matching 'Task 3'" against a file that plainly contains one. Balance the fences
after any scripted edit to a plan: `awk '/^```/ {n++} END {print n%2}'` must
print 0.
