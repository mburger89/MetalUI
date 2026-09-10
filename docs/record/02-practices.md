## Practices

**`docs/practices/verifying-tests-can-fail.md` — read this before writing tests.**

For three milestones, every defect found during execution was in a plan, a spec,
a test or a comment — **none in an implementation**. **The box-model milestone
ended that**: three real engine bugs, all of them found by mutation or by a new
fixture's first generation, none by reading the code. Two were margin
compositions (reverse × margins, stretch × margins); the third was percentage
insets resolved against the wrong box, which had been green through two whole
tasks. What did not change is *how* they were found — essentially every finding
across all four milestones came from **mutation, not inspection**.

The flex-sizing milestone alone produced nineteen findings, four of them the same
shape: a fixture too uniform to distinguish the thing it claimed to pin. Before
committing a fixture, change the declaration it is named for — a percentage to a
pixel, an inset to 0 — regenerate, and confirm the numbers move. That document
catalogues **sixteen** shapes of test that cannot fail, all observed in this repo,
plus the method for finding them and the cases where adding a test is the wrong
answer. Count the `### <n>.` headings rather than trusting that number
(`grep -cE "^### [0-9]+\." docs/practices/verifying-tests-can-fail.md` reads 16) —
a bare `grep -c "^### "` reads **19**, because **three** sections in that document
are unnumbered. Both numbers have now moved three times: the input-and-state
milestone added shape 14 and one unnumbered section (13 and 15 before it,
unnumbered count 2 before that); the sizing milestone added shape 15 — "a
benchmark of a configuration in which the code under test is unreachable", found
while measuring TX-H's own cost (ruling `SZ-N`); and the tombstones-and-AX
milestone added shape 16, **"a `@testable` test file cannot prove an
access-level narrowing"** (ruling `TB-N`) — neither of the last two changing the
unnumbered count. **This paragraph itself said "fifteen" and "18" while the
document held fifteen numbered and eighteen total, which was correct — but the
document's own taxonomy HEADING said "fourteen shapes" from the moment the
sizing milestone added the fifteenth and was still saying it when this
milestone arrived.** Corrected to sixteen here. The lesson is the one the
paragraph already teaches, arriving inside the document that teaches it: a
count is written in more than one place, and updating the one you were looking
at is not updating the count.

**Shape 15 then fired AGAIN inside the same milestone, in its whole-branch fix
wave, on an unrelated question — which is the argument for it being a shape
rather than an anecdote.** The wave set out to settle whether the demo's
sidebar squeeze is a divergence by measuring the same declaration in both
engines. Its first probe gave the main pane no content, so nothing forced the
sidebar to shrink and **both engines answered 196 in both the `flex-shrink: 1`
and `flex-shrink: 0` arms** — a clean, symmetric agreement that says nothing,
because the mechanism under test could not fire. With a demanding sibling the
arms separate (69/69 against 196/196) and the question is actually answered.
The discriminator generalises past benchmarks: **require the arms of a
comparison to DISAGREE before believing that they agree.**

**And that wave produced a fresh instance of the practices doc's second
record-mechanism — "a fix round is exactly as capable of producing an
unmeasured claim as the round it fixes".** A doc comment written for one of
its new pins asserted that removing `align-content: flex-start` "leaves it
green under the pre-SZ-O engine". Running that mutation instead of re-reading
it gave **295**, not green: under the default `stretch` the two lines absorb
the container's leftover space and the engines still differ, by half the
error. The claim was corrected at the mutated line in the same pass, which is
the doc's first mechanism doing its job on top of the second.

The recurring lesson of the last two tasks has a sharper form: **a feature that
works alone and a feature that works alone can be wrong together.** All three
engine bugs above lived in a composition that existed in the engine and in no
fixture. When you implement something, ask what it now composes with, and check
that pair against the browser.

**The wrapping milestone's third task is the counter-example that proves the
method rather than the streak.** It committed eleven composition fixtures at
once and every one of their goldens matched the engine on first generation — no
engine bug. But of the sixteen sibling-swap differentials their comments
claimed, **four were wrong**, every one of them hand-derived; running the swaps
through the live oracle is what caught them. "Change the declaration and confirm
the numbers move" is not satisfied by predicting which numbers move. Run it.

**Structural identity added two variations, both about the record rather than
the code.** First, **"pinned as deliberate" is a claim to grep for, not to
believe**: a plan's risk list and a spec section both asserted the vanishing-`if`
behaviour was already pinned, and no test pinned it — one inaccurate sentence
standing in for two claimed pins, and the behaviour it described (reset) was not
the behaviour the code had (adoption). Second, **a mutation count measured
mid-task is stale by the end of the task** (ruling SI-H): three of this
milestone's five recorded counts were taken before a fix round added two tests
sensitive to the same line, and each under-counted by exactly those two. The two
that survived re-measurement were the two that **named** the tests they reddened
instead of only counting them — which is CS-N's rule with a reason attached.

**The text milestone added two shapes and sharpened the method itself.**
**Shape 12, "the oracle is the code under test"** — four instances on one
branch, the sharpest of them inside a *byte-exact per-pixel* comparison of a
real drawable that indexed into the atlas through the sprite's own
`atlasBounds`, so a one-texel source shift left it green. It reads as the
strongest assertion in its file. The generalisation is the part to carry: **a
hand-built fixture escapes this and production-built input does not** — the
earlier version of that same test built its sprites by hand and had no problem,
and the hazard arrived exactly when the test was made more end-to-end.
**Shape 13, a test whose own structure truncates the suite**: `#expect` records
and continues, so a wrong implementation returning fewer elements sent the next
loop past the end of its own array — `Index out of range`, **no summary line,
~200 tests never run.** A wrong implementation truncated the run instead of
reddening it. The rule is one word wide: **any count a later loop indexes on
must be `try #require`, not `#expect`.** And **a mutation that reddens nothing
is a broken instrument or it is the finding** — three of each on that branch,
so the discriminator (prove the mutant behaves differently before banking a
coverage gap) is now written into the method section.

**And its fix round produced the branch's only taxonomy-shape-9 pair**, found by
mutating every line of new code rather than by reading any of it: `EitherGroup`'s
`cursor += 2` and `AnyElement`'s `cursor += 1` each reddened **nothing** on a
358-test suite while being asserted as a property in two documents apiece. Both
now have a test. The `+= 2` one carries the sharper lesson: **the composition the
stated property suggests does not fail.** `Row { if flag { C() } else { C() };
C() }` keeps the trailing element's state under `+= 1` — the cursor advances
before the branch is chosen, so the shift is identical on both frames. Only a
sibling that lands on the *untaken* slot and then goes one level deeper breaks,
which took three candidate compositions and a probe to find. The property the
comment claimed was not the property the line bought.

**The measure-performance milestone added one shape and one method, both about
performance work specifically.** The method: **write the counting assertions
first and require them to be RED on arrival.** Two of that milestone's three
harness assertions failed the day they were committed — and **they did not go
green together, which is the part to state precisely**: the tokenizer-count one
went green at the memo task, and only the "a 160-row list costs what a 40-row
one costs" assertion stayed red through four tasks, until windowing. That one
is the only reason anyone can say the windowing task did anything — a
performance test written after the optimisation cannot distinguish "fast" from
"measuring the wrong thing". Crediting both to the last task is the same shape
of error this milestone started from: a true sentence about one half, read as a
claim about both. They count work (tokenizer calls, cache
entries) rather than timing it, so they fail identically on a loaded CI box
where a committed millisecond baseline would flake. The shape: **a test can be
inert because the FIXTURE cannot express the defect, not because the assertion
is weak.** That milestone's drafted cache-growth test swept the outer frame's
width over a fixture whose every internal width is pinned, so the cache reached
a warm-up value and then read byte-identically forever — measured
`distinct=[207]` across 120 frames **with no bound and no sweep implemented at
all**. It passed against a stub. The assertion was fine; the fixture could not
move the key the assertion read. Ruling `MP-J` carries it.

**The input-and-state milestone added one shape and three mechanisms, and every
one of the four is about the RECORD rather than about a test.** The shape is
**14, "a confident wrong reason closes the question before it is asked"**: a
report asserted two new modifiers "cannot" be covered by
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField` because `Handlers` is not
`Equatable` — true — and concluded no test was possible, which is false, since
`HandlerShape` in that same file had solved exactly that two tasks earlier.
Nobody looked, because the reason sounded finished. Both modifiers shipped
uncovered and both mutants stayed green. **The precedent it repeats already
existed in this file, in the now-retired divergence 5 (ruling FS-3)**: a
task's report claimed `.minWidth(_:)` "has no equivalent escape" for a demo
`ScrollView` wrapper, when `.minWidth(_:)` existed and the real blocker was
`ScrollView` having no modifier surface at all — a stated reason wrong in two
directions at once while its conclusion happened to be right. (The correction
now lives at `Sources/MetalUIDemo/main.swift`, where the wrapper is declared,
since divergence 5's own entry is gone.) The tell is a **"cannot" that was not
measured**.

The three mechanisms are new sections under "The method" in the practices doc,
and each cost a round of rework. **That section is titled "SEVEN ways a record
goes wrong" today** — the tombstones-and-AX milestone added 4 and 5 below and
amended 1 and 3 with their own converses, and the `Component` milestone added 6
and 7; the numbering is stable, so a citation of mechanism 1, 2 or 3 still
resolves:

1. **A measurement recorded in the report is not a measurement applied to the
   source.** Three consecutive tasks shipped a comment their own report
   contradicted *in the same commit* — the report became where true things went
   while the comment kept its draft-time belief. The rule is one sentence wide:
   **anything a mutation teaches must be walked back to the mutated LINE in the
   same pass.**
2. **A fix round is exactly as capable of producing an unmeasured claim as the
   round it fixes.** The first attempt at pinning a one-second timeout shipped a
   test whose doc said it pinned the `>` comparison and did not — `>` and `>=`
   agree at 0.999 and 1.001. Re-reading the code did not catch it; running the
   mutation the claim implied did.
3. **Staleness is systematic, not local — re-take the whole table.** An
   amendment to `SI-H`. A reviewer flagged two stale mutation rows; re-taking
   *everything* found a third they had not sampled, and a fourth that had moved
   for a better reason. A review samples; a count taken before the last test
   landed is stale across everything measured in that window.

**The tombstones-and-AX milestone added one shape and two mechanisms, and
amended two more — five contributions, every one of them about the RECORD.**
The shape is **16, "a `@testable` test file cannot prove an access-level
narrowing"** (ruling `TB-N`): `@testable import` widens `internal`, so the test
file whose whole subject is the type could not demonstrate that narrowing two
properties to `internal(set)` closed anything at all. The tool that gives a test
its reach is the tool that hides the change; the evidence has to be a
`swiftc -typecheck` guard against a **plain** import, which is what took the
guard count from 29 to 32. The two new mechanisms are:

4. **Silence in a review is scope not covered, not coverage** (ruling `TB-E`).
   An implementer wrote a false claim about a function's call sites and named
   the cause exactly: *"the review had confirmed `mark`'s and `write`'s call
   graphs and said nothing about `withState`. I read that silence as coverage
   rather than as scope not covered."* Distinct from 1–3, which are all about a
   claim nobody measured; this is a claim believed **because a reviewer verified
   its neighbours**. A review returns findings, not a map of what it looked at.
5. **Knowing a rule, quoting a rule, and having a controller record a ruling
   about a rule are all weaker than running the mutation** (rulings `TB-G`,
   `TB-Y`). Three instances, escalating. A controller ruling written
   *specifically to pre-empt* a wrong comment did not stop that comment
   shipping the converse — with the implementer's own report quoting the rule
   two paragraphs above the violation. And `HandlerShape` (`ModifierTests.swift`)
   fell behind `Handlers` for the **second** time, for the same reason, while
   **this very file names that exact projection and that exact failure in
   advance**, citing the first occurrence. The only control that fired in either
   case was a reviewer executing something. Corollary for controllers: a ruling
   that must survive into a source comment has to be stated in the **dispatch**,
   because the ledger is not something the implementer reads.

Mechanisms 1 and 3 also gained converses in the same milestone. **1's** (ruling
`TB-AA`): anything a measurement did **not** establish must not appear at the
line as though it had — a parenthetical "(measured on a scrolling 500-row and a
100,000-row list alike)" that was true of one number got attached, unqualified,
to a derived successor nothing had measured that way, and the fix was to say at
the line which half was measured and which derived, not to delete the number.
**3's** (ruling `TB-AC`): a set of stale sites handed over by a review is a
**sample, not an inventory** — sweeping the whole file found a fifth site in a
function's own doc comment and a sixth **twenty-six lines below a line the fix
round had just corrected**.

**And the milestone's own best evidence for the method is a ruling that was
answered the OPPOSITE way from how it was framed.** A brief deliberately left
open whether `isFocused` needed a phase guard and *forbade* adding one by
symmetry with `isActive`'s. Measuring it found that a prepaint-time `isFocused`
really does lie — and, incidentally, that `isActive`'s guard is **not** the
measured lie its shared comment claimed, since `Frame.activeElement` is a `let`.
A prohibition aimed at preventing a bad addition surfaced a pre-existing false
justification. Forbid the reasoning shortcut, not only the outcome.

**The `Component` milestone added two mechanisms and they are the FIRST two that
are about the PROCESS producing the record rather than about a claim inside
it.** Both were paid for in this session rather than reasoned about:

6. **A subagent reporting that it "accidentally launched" another agent is
   reporting a LIVE PROCESS, not a closed incident.** Two reviewers invoked the
   `code-review` **skill** by name — out of habit, instead of reading the
   task-reviewer method file they were pointed at — and each spawned a
   background multi-agent review. One of those had reported, a milestone
   earlier, that it had accidentally launched such an agent and was
   *disregarding its findings*; disregarding them was right, and not stopping
   the agent left it running against the shared checkout, where it forked eight
   more and **at least one applied live mutations to `Sources/`**, clobbering an
   implementer's in-progress edit. "I disregarded its output" is not "I stopped
   it." The dispatch-side control is one sentence: **reviewer dispatches must
   say explicitly not to invoke the `code-review` skill.**
7. **Mutation testing belongs in an isolated `git worktree` whenever another
   agent is live in the checkout** (rulings `CO-M`, `CO-K`). **A mutation
   result taken from a contended tree is unattributable, and an unattributable
   result is worse than none, because it still looks like evidence.** The
   companion rule is what to do on finding out afterwards: discard every
   measurement taken during the contended window and re-take it. One extra
   suite run is the whole cost.

**And that milestone's own best evidence for the method is a claim the SPEC made
that measurement reversed.** §5 specified that a modifier on a component wraps
it in a `Box`, on the stated grounds that this is what SwiftUI's
`ModifiedContent` does, and the implementing task was written to build it. A
throwaway probe with a passing positive control measured **120×26** where
wrapping predicts 96–104: SwiftUI **distributes**. The design was rewritten
before it shipped (ruling `CO-U`). The tell is the same one shape 14 names — a
confident reason, stated as settled, that nobody had run — arriving this time in
a design document rather than in a task report.

**And the fix wave added the sharper half of that, which is what a refuted claim
does AFTER it is refuted.** The spec was corrected the day it was measured; the
shipped comment in `Sources/MetalUI/Component.swift` was not, and neither were
**four** sites in the plan — including two Task 4 *instructions* reading "State
that modifiers wrap, and that a modified component is layout-opaque" and
"labelled as derived and not measured". So the branch shipped with the corrected
account in the spec, the refuted account in the source a reader actually opens,
and a standing instruction to write the refuted account into `CLAUDE.md` next
time. **A refuted claim has a blast radius, and correcting where it was
DISCOVERED is not correcting where it was COPIED TO.** The remedy is a
grep-for-the-sentence sweep at the moment of refutation, not at the end of the
branch — the same shape as mechanism 3's "staleness is systematic, not local",
pointed forward instead of backward. This is also why the plan was corrected in
place rather than preserved as history the way the reactivity plan's own false
claim was: nothing cites these four, and two of them are live instructions.
Preserving an instruction is not preserving a record.

