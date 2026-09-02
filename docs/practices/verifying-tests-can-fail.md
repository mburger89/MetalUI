# Verifying that tests can fail

Across Milestones 0 and 1a, **every defect found during execution was in the plan
or the spec — none in an implementation.** Fourteen defects, zero from the code
that was written.

That is not because the implementations were flawless. It is because reading code
finds the bugs you are looking for, and the bugs that survive are the ones nobody
thought to look for. Every one of the fourteen was found the same way: **break
something on purpose and see whether the suite notices.**

Reading the tests never once revealed one of these. Mutation revealed all of them.

## The method

For each behaviour you are about to trust:

1. **Break it** — delete the term, swap the operand order, transpose two fields,
   change the constant, drop the filter.
2. **Run the whole suite.**
3. **If it stays green, the behaviour is unguarded.** Not "under-tested" —
   unguarded. Nothing in the repo would notice if it broke tomorrow.
4. **Restore, and verify with `git status --short`.**

Three traps worth knowing before you start:

- **`git checkout <file>` cuts both ways, and both halves have bitten here.**
  On an **untracked** file it silently restores nothing, so the mutant survives
  into your next run — and nearly into a commit, once. On a **tracked** file it
  restores rather too well: it discards *every* uncommitted change in that file,
  including edits that have nothing to do with your mutation. That second half
  bit twice on one branch, both times destroying a doc-comment fix that was
  written mid-mutation-round.

  Commit before mutating. If you must mutate a file that carries uncommitted
  work, **revert from a backup copy of the file rather than from git** — `cp`
  the file aside first and `cp` it back. Verify either way with a grep for your
  mutation marker *and* a grep for your own edit, not by assuming.
- **A stale build makes a mutation "pass" for the wrong reason.** In this repo,
  editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` re-copies the
  resource bundle but does **not** rebuild Swift's view of the C struct. Use
  `swift package clean` after header edits — `rm -rf .build` is not always enough.

### A mutation that reddens nothing is a broken instrument, or it is the finding

Step 3 above says a green suite means the behaviour is unguarded. That is the
usual case and it is not the only one: sometimes the edit you made **did not
mutate anything**, and reading it as a coverage gap banks a finding that is not
there. Telling the two apart is part of the method, not an afterthought — the
text milestone hit both, three times each way, in one branch.

**Broken instrument.** Two spellings that look like mutations and are not:

- **Replacing a stored property with a computed one over surviving storage does
  not mutate synthesized `Hashable`/`Equatable` at all.** Dropping `size` from
  `FontKey` by making it computed from the font left the derived conformances
  keying on exactly the same storage. Nothing changed, so nothing reddened.
- **"Make the sort unstable" is not a mutation where the sort is already
  stable** — Swift's sort is recorded as stable at every size measured in this
  repo, so `glyphs.sort { $0.order < $1.order }` cannot be destabilised by
  wishing. Reversing the tiebreaker, and deleting the sort, each redden
  `finalizeSortsGlyphsStablyByOrder` alone.

**The finding.** Three in the same branch, each on code everyone was sure of:

- Deleting `!isRow` — the single operator carrying a whole CSS axis distinction
  (inline versus block) — left **all 395 tests green**. The measurement that
  would have caught it existed, in a comment, and had never been pinned.
- Turning font subpixel *quantization* back on left the suite green at 412,
  because quantization collapses four variants onto two positions and the test
  compared the only equal-sized pair, straddling the surviving boundary.
- Storing `left: 0, top: 0` in the glyph atlas while still *returning* the real
  bearings from the miss path left all 442 green: every test in the repo drew
  each glyph once against a fresh atlas, so the **cache-hit path the seam exists
  for had no coverage at all.** On screen that is text correct on the frame it
  appears and displaced on every frame after.

**The discriminator, and it is cheap:** before banking a green mutation as a
coverage gap, prove the mutant *behaves* differently — print the two values, or
mutate one step further out. A mutation you cannot show changed an observable
quantity has told you nothing about the tests.

### Five ways a *record* goes wrong, all paid for in rework

These are not shapes of untestable test — they are ways the written record stops
matching what was measured. The first three were found the expensive way on
the input-and-state milestone; **4 and 5 were added by the tombstones-and-AX
milestone**, which also amended 1 and 3 with their own converses. Nobody should
read the numbering as a priority order: 5 is the one that has fired most often.

**1. A measurement recorded in the report is not a measurement applied to the
source.** Three consecutive tasks shipped a comment their *own report*
contradicted, in the same commit. A register guard's comment said the early
return was "not an optimisation" while the same report's mutation table recorded
that deleting it changes nothing; a phase-guard comment said `isActive` would
"lie by returning a wrong `false`" while the same report's item 3 said it would
answer correctly; a test helper's comment said `Handlers` has three members while
the report that added the fourth and fifth counted five. In each case the report
became where true things went, and the comment kept its draft-time belief.

> **The rule is one sentence wide: anything a mutation teaches must be walked
> back to the mutated LINE in the same pass.** Not to the report, not to the
> ledger — to the line. A comment is read by the next person to touch the code;
> a report is read by nobody.

**And its converse, added by the tombstones-and-AX milestone (ruling `TB-AA`):
anything a measurement did NOT establish must not appear at the line as though
it had.** A doc comment carried a parenthetical — "(measured on a scrolling
500-row and a scrolling 100,000-row list alike…)" — that was true of the number
it was written for and got attached, unqualified, to a *derived* successor that
nothing had measured that way. The implementer flagged that its own figures
could not be independently reproduced from the original harness, which is the
only reason it was caught; the report said so honestly and one committed doc
line did not.

> A line saying "19" reads as a measurement whatever the report says. **The fix
> is not to delete the number — deleting it would have destroyed the argument
> that needed it — but to say at the line which half was measured and which half
> was derived.** An inherited base, a re-measured delta and their sum are three
> different epistemic statuses wearing one typeface.

**2. A fix round is exactly as capable of producing an unmeasured claim as the
round it fixes.** A review found a timeout that was bracketed rather than pinned
(`= 2` and `= 0.4` reddened, `= 0.5` and `= 1.49` passed). The first attempt at
the fix shipped a test whose doc said it pinned the `>` comparison — and it did
not, because `>` and `>=` agree at 0.999 and at 1.001. Only a gap of *exactly*
the timeout separates them.

> Re-reading the fix did not catch it. **Running the mutation the claim implied**
> did. A fix round gets the same discipline as the work it is fixing: state what
> the new test pins, then mutate exactly that and watch it go red.

**3. Staleness is systematic, not local — re-take the whole table.** An amendment
to ruling SI-H. A review flagged two mutation-table rows as measured before the
last tests landed; re-taking *everything* found a third the reviewer had not
sampled, and then a fourth that had moved for a different and better reason (one
new test turned out to catch two distinct mutants).

> A review **samples**. A count taken before the last test landed is stale across
> *everything* measured in that window, not at the two places somebody happened to
> check. **Re-take the whole table, do not patch the flagged rows** — and name the
> tests each row reddens, which is what makes a stale row visible at all.

**Sharpened by the tombstones-and-AX milestone (ruling `TB-AC`), where the same
mechanism fired inside a single fix round rather than across a milestone.** A
review handed over four stale numbers. Taking the whole *file* instead of the
four found **two more**: one in a function's own doc comment, a fifth site
entirely outside the reviewer's set, and one **twenty-six lines below a line
the fix round had itself just corrected** — so proximity to a corrected line is
not evidence of having been looked at.

> **A set of stale sites handed over by a review is a SAMPLE, not an
> inventory.** The instruction that works is "sweep the file and adjudicate
> every hard-coded count", which also means recording the ones you *leave*
> alone and why — that round left four (a fixture parameter, another type's
> figures, an unrelated historical suite count, and lines already framed
> correctly), and saying so is what stops the next sweep re-litigating them.

**4. Silence in a review is scope not covered, not coverage.** An implementer
wrote a false claim about a function's call sites and explained afterwards
exactly how the belief formed:

> "I'd assumed `withState`'s callers were homogeneous with `mark`'s because the
> review had confirmed `mark`'s and `write`'s call graphs and said nothing about
> `withState`. **I read that silence as coverage rather than as scope not
> covered.**"

The claim was false — one caller runs from raw scroll-wheel handling, entirely
outside frame construction — and no shipped behaviour was wrong, but the stated
*reason* for a load-bearing decision was undercut. **This is distinct from 1, 2
and 3, all of which are about a claim the author never measured.** This is about
a claim the author believed because a reviewer had verified its *neighbours*.

> A review returns findings, not a map of what it looked at. **The shape of what
> was sampled is not stated in what comes back**, so "the reviewer didn't
> mention it" carries no information at all about whether it is true.

**5. Knowing a rule, quoting a rule, and having a controller record a ruling
about a rule are all weaker than running the mutation.** This one has three
instances and they escalate.

- A controller wrote a ruling *specifically to pre-empt* a comment shipping the
  wrong claim about a redundant guard. The shipped comment asserted the
  **converse**, and the same report claimed the nuance was "recorded in the
  doc comment now" — which a `grep` showed it was not. Three layers of control
  were in play: this document names the mechanism, the ruling pre-empted this
  exact instance, and **the implementer's own report quoted the rule two
  paragraphs above the violation.** All three failed; a reviewer running a grep
  caught it.
- `HandlerShape` (`Tests/MetalUITests/ModifierTests.swift`) is a hand-built
  projection standing in for `Handlers`, which cannot be `Equatable` because it
  carries escaping closures. It fell behind the struct **for the second time,
  for the same reason** — a new stored member added without a matching field —
  while CLAUDE.md names *that exact projection and that exact failure* in
  advance, citing the first occurrence.
- Both were closed only when someone mutated: for the second, widening the
  projection proves nothing on its own, and the closure was judged by whether a
  modifier that also writes the new field now reddens the test. It does, alone,
  1 issue of 782.

> **The only control that fires is the one that executes something.** A rule in
> a primer, a rule quoted in a report, and a ruling in a ledger the implementer
> does not read are all documentation about a hazard, not detection of it. And
> a corollary for controllers: **a ruling that must survive into a source
> comment has to be stated in the DISPATCH**, because the ledger is not
> something the implementer reads.

## The taxonomy — sixteen shapes, all found in this repo

Use this as a checklist when writing tests, and as a hit list when mutating.

### 1. Uniform values on both sides of an assertion

`Edges(all: 4.0) == Edges(top: 4, right: 4, bottom: 4, left: 4)` passes against an
init that **transposes every field**. The test cannot fail for the bug it exists
to catch.

Same shape, three more times:
- A symmetric `gap: 12px` fixture sets both axes equal, so it **cannot detect the
  engine reading the wrong axis**. Only an asymmetric `Axes(horizontal: 20,
  vertical: 5)` catches it.
- Renderer tests using only white and black are **symmetric under a red↔blue
  swap** — a channel transposition passed the entire suite.
- A converter test where `contentMask` was never asserted: `MUIRect.init` could
  pass `bounds` twice and every assertion still passed.

**Rule: distinct values per field, and assert each field individually.**

### 2. Fixtures too shallow to distinguish two models

Every layout fixture was single-level, so **relative and absolute coordinates
coincide**. Removing the origin term from `computeLayout` passed both WebKit
comparisons *and* both hand-written packing tests. Only a deliberately nested test
caught it.

**The browser-generated corpus is structurally blind to that entire class.** More
fixtures would not have helped; deeper ones would.

### 3. Artifacts that are written and never read

Four browser-generated golden files sat committed in the repo, looking exactly
like a validated corpus. `loadGolden` had **zero callers**. Every comparison
regenerated from live WebKit instead, so hand-editing or rotting a golden failed
nothing — while still paying the cost of needing a browser on every run.

**Rule: grep for callers of anything that looks like infrastructure.** Zero
callers means it is decoration.

### 4. Fields that are live but unread

Things that look implemented and are not:
- `SurfaceView.projection` was carried through the API and never applied — a
  stereo backend would have rendered **identical output for both eyes**, which is
  exactly what the seam existed to prevent.
- `contentMask` round-trips the whole CPU/GPU ABI and the fragment shader never
  reads it.
- `resolveEdges` is fully unit-tested and has **no engine caller** — so
  `padding`, `border` and `margin` are silently ignored.
- `isReverse` is defined with zero consumers, so `.rowReverse` silently produces
  `.row` geometry.

**Rule: when you cannot implement it yet, say so at the definition.** A comment
is the whole fix. Silence reads as "implemented".

### 5. Constants with no assertion

`Renderer.pixelFormat` flipping from `.bgra8Unorm` to `.bgra8Unorm_srgb` passed
**all 39 tests** — because the offscreen test target reads the same constant, so
both sides flipped together, and nothing blended translucent-over-opaque.

This was the constraint emphasised in *every single dispatch brief* as
"load-bearing". **The loudest-stated constraint is the most likely to be
unguarded, precisely because everyone assumes something emphasised that much must
already be checked.**

### 6. Guards that are themselves unguarded

`EmptyMeasurementError` and `FixtureHygieneError` are implemented and have no
test. Either guard could be **deleted with the suite green**. A guard nobody
proved can fire is a comment with a runtime cost.

### 7. Guarantees that lapse under configuration

Two in this repo, and both look like reasonable cleanups:
- The **ABI probe skips** when no Metal device is present, so CPU/GPU struct
  agreement is unguarded on a headless runner.
- **`committedGoldensMatchTheBrowser` is the only live-WebKit consumer**, so
  env-gating it — "the browser test is slow, make it opt-in" — turns the goldens
  self-confirming.

Neither would fail a test. **A guarantee that quietly turns itself off is worse
than no guarantee, because the green suite now asserts something it has stopped
checking.** Both must be required, non-gateable CI jobs.

### 8. Assertions that pin an accident

`resolveLength(.percent(0.1), against: 200) == 20` passes — but `9%` of `300`
gives `27.000001907348633` under the same implementation. The test pinned **which
decimal happened to be chosen**, not an invariant. The next person to add a 9%
fixture hits a mystifying red and "fixes" settled arithmetic.

**Rule: if an exact assertion holds, ask whether it holds for the general case or
just for your example.**

### 9. Compositions that exist in the code and not in the corpus

The first four milestones of this project ended with the same result: every defect
found was in a plan, a test, a fixture or a comment, and **none in an
implementation**. The fifth broke that — three real correctness bugs, none visible
to a 153-test suite:

- a reverse container put `margin-left` on the item's physical *right* (WebKit
  `a.x=320`, engine `340`);
- a stretched item's cross size ignored cross margins, overflowing its container
  (WebKit `50x65`, engine `50x100`);
- percentage padding resolved against the box's **own** width rather than its
  containing block's (WebKit `27`, engine `20`).

None of the three is exotic. Each lives where **two shipped features meet**:
reverse x margins, stretch x margins, padding x nesting. And the corpus contained
neither pair, because it had been grown one feature at a time — every fixture added
by the task that added the feature.

That is why the earlier streak was not luck, and why it ended exactly when it did.
A one-feature-deep task gives an implementation little room to be subtly wrong; the
likeliest error really is in the plan. A task whose feature multiplies against
three already-shipped ones has a combinatorial surface, and the fixture list
inherited from single-feature work covers none of it.

**The check:** when a task adds a feature, list the features already shipped that
it interacts with, and name a fixture for each pair. Then ask of every pair you did
not fixture: *is this untested, or untested-and-correct-by-construction?* Both of
the first two bugs above were sitting in the second category the day before someone
probed them — as were two further compositions a reviewer checked by hand and found
correct, which then got fixtures rather than a footnote.

**The tell in a review:** a mutation that reddens nothing, in code you are sure is
right, usually means the composition it lives in has no fixture — not that the
mutation is harmless.

### 10. Claims whose scope quietly expired

The nine shapes above are all defects in code or in tests. This one is a defect in
what the repo **believes about itself** — and on the wrapping branch three
instances turned up in a single afternoon, all found the same way.

Each was a comment that was **true when written**, whose *arithmetic is still
right*, and which became false in its **reach** as the engine grew around it:

- `Resolve.swift` said the `Float` percentage error is "~1e-4pt … roughly 130x
  below WebKit's 1/64 quantum, **so it never reaches a fixture**". The arithmetic
  is correct. The conclusion is not: cumulative rounding amplifies it at a `.5`
  boundary, and WebKit says 286/328 where the engine says 285/327.
- `CLAUDE.md` said content-based cross sizing affects only a **non-stretched**
  item and that "**no fixture can catch this** — every fixture in the corpus is an
  empty div … needs the M2 text system". Both halves false: the size is lost in
  §9.4.8 line measurement, which runs *before* stretch, and a **nested flex
  container** has a content cross size with no text in it.
- The `margin: auto` row scoped the gap to the main axis and `justify-content`.
  WebKit also centres a `margin-block: auto` item within its line on the **cross**
  axis.

**Why this shape is hard to see.** A wrong claim about code gets caught the moment
someone tests the code. A wrong claim about *what testing would reveal* is
self-sealing: it tells the reader not to look, so nobody looks, so nothing
disproves it. The three above had survived one, four and two milestones
respectively.

**The tell:** any sentence of the form *"no fixture can catch this"*, *"needs
M2"*, *"unreachable"*, *"never reaches"*, *"0 uses"*, or *"only affects X"*. Each
is a prediction about measurement, dressed as a fact about the code.

**The check, and it is cheap:** periodically **measure the thing the comment says
not to bother measuring**. All three were found by probe agents told to sweep
compositions, not by anyone reading the comments. Grep the codebase for those
phrases and spend an afternoon falsifying them; the yield here was 3 for 3 on the
first sweep.

**When you write one**, name the *mechanism* that makes it unreachable, not the
milestone you expect to fix it — a mechanism can be checked, a milestone cannot.
"Needs M2" was wrong because the gate was never text metrics; it was recursive
subtree measurement, which nobody had written down.

### 11. A run that did not happen and reported success

Shapes 1-9 are tests that cannot fail; shape 10 is a belief that outlived its
truth. This one is a *suite that never ran* — and it is the only shape here that
a green exit status actively conceals.

A test in `PlatformTests.swift` ended with `defer { nsWindow.close() }`. That is
the ordinary, correct habit — clean up the window you opened. But `App.openWindow`
wires the window's `onClose` to `NSApplication.terminate`, so the close killed the
test process from inside a passing test. **`swift test` exited 0 having silently
skipped 94 of 302 tests, and printed no summary line at all.**

Nothing in the taxonomy would have caught it: every remaining test was
well-formed and capable of failing. They simply were not run. The exit status
said green, the CI convention that reads exit status would have said green, and
the 94 unrun tests included the ones guarding this milestone's own work.

**What caught it was comparing the test count to the previous run.** Nothing else
would have. So:

- **Read the summary line, not the exit code.** `Test run with N tests … passed`
  is the only evidence the suite ran; its *absence* is the signal, and an absent
  line is easy to miss in a scrollback.
- **Treat a falling test count as a failure** until you can name the tests you
  deleted. A count that drops without a deletion is this shape.
- **In this repo specifically**, any test that opens a real window owes you a
  note on whether closing it terminates the process. `AppKitPlatform.openWindow`
  sets no `onClose` and is safe to close; `App.openWindow` is not. The
  distinction is invisible at the call site — both hand back an `NSWindow`.

The general form: **a cleanup path that can end the process turns a passing test
into a truncated run.** Timeouts, `exit()` in a fatal-error handler, and anything
that tears down a shared host have the same signature.

#### The second instance, and the first that no per-test review could catch

The element-pipeline branch produced the same shape from the opposite direction,
and the difference is the lesson. In the first instance the offending test's own
`defer` ended the process, so reading that one test could in principle have found
it. In the second, **every test involved passed alone, and the crash needed two
test targets in one process**:

- `swift test` → **SIGSEGV, 297 of 303 tests reported, no summary line**.
- `--filter MetalUIPlatformTests` → 5 passed, summary present.
- `--filter committedGoldensMatchTheBrowser` → 2 passed, summary present.
- Both filters together → **crash**.

Two of the five AppKit tests were implicated — exactly the two ending in
`defer { nsWindow.close() }`. A third mutates `NSApplication.shared.appearance`
globally and does *not* crash, which ruled out "the test leaks global state"
before anyone could settle on it.

**The mechanism, from `lldb`, main thread:**

```
frame #0  libobjc      objc_release
frame #1  AppKit       -[_NSWindowTransformAnimation dealloc] + 492
frame #5  libobjc      AutoreleasePoolPage::releaseUntil(objc_object**)
frame #7  QuartzCore   CA::Context::commit_transaction
frame #9  QuartzCore   CA::Transaction::flush_as_runloop_observer(bool)
frame #12 CoreFoundation __CFRunLoopRun
frame #17 libswift_Concurrency swift_task_asyncMainDrainQueue
```

`NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to **true**, a
pre-ARC convention. `AppKitWindow` holds the window in a strong stored property,
so `close()` was an over-release. **The crash is not at `close()`**: AppKit defers
the window's close animation into an autorelease pool that CoreAnimation pops
from a run-loop observer, so the dangling release fires the next time the main
run loop spins a CA commit. `MetalUIPlatformTests` contains no `async` test, so
the process exits first; the WebKit oracle tests `await` for seconds, so the
observer runs and the process dies — taking the rest of the suite with it.

**Three things this taught that the first instance did not.**

1. **Serializing the two groups would not have fixed it.** That was the obvious
   fix and it is wrong, and the probe that showed so took ten minutes: a *single*
   test, under `--no-parallel`, that opens a window, closes it, and then drives
   the oracle crashes just as hard. There is no interleaving there at all. The
   run loop does not care which test asked it to spin. **A cross-target mutex
   would have reordered the crash, not removed it** — and would have left a real
   over-release shipping in `MetalUIPlatform` for whoever first closes a window
   in an app rather than quitting.
2. **"Passes alone" is not evidence about a suite.** Both tests were reviewed,
   both were well-formed, both were capable of failing, and both were correct.
   The defect was in production code that only a *composition of test targets*
   reached. This is shape 9 wearing shape 11's clothes: the untested pair was
   `AppKit window teardown x a spinning main run loop`, and neither target's
   fixtures contained the other half.
3. **The guard has to be a property, not the behaviour.** The behavioural failure
   is a process crash, and a crash is a truncated run rather than a red test —
   reporting it is precisely what the bug prevents. So
   `closingAWindowDoesNotOverReleaseTheOneARCAlreadyOwns` asserts
   `isReleasedWhenClosed == false` directly. Verified by mutation: deleting the
   line in `AppKitWindow.init` reddens that test and nothing else.

**The check, for the next AppKit or WebKit test:** a test that touches a
process-wide host — AppKit windows, WebKit, CoreAnimation, the main run loop —
must be run *against the whole suite*, not only under its own `--filter`, and the
**summary line and count** read afterwards. `--filter <one target>` is a
different program from `swift test`.

### 12. The oracle is the code under test

A test whose **expected value is produced by the code under test** moves with
the mutation and cannot fail. It is not shape 1 (uniform values on both sides of
one assertion) and not shape 9 (a composition with no fixture): the mechanism is
that both sides of the comparison are computed from the same source, so any edit
to that source changes them together.

**Four instances on the text milestone**, and the range is the point:

- `noWrappedLineExceedsTheOfferedWidth` asserted that no wrapped line is wider
  than the width — against line widths the wrapper itself had produced. Caught
  by its author and re-oracled on raw `CTTypesetterSuggestLineBreak`.
- **`FontMetrics.lineHeight`, under a shape-10 banner.** Both shaping assertions
  read `abs(totalHeight - lineHeight) < 0.001`, where `totalHeight` is
  `lines × lineHeight` — so `lineHeight { ascent }`, dropping two of its three
  terms, left the **whole suite green at 371**. The fix is an independent oracle:
  `metricsMatchCoreText` compares against `CTFontGetAscent`/`Descent`/`Leading`
  directly, and the same mutation now reddens that test alone.
- `widestLine` was unpinned as a *maximum*: `lines.first?.advance` was green
  across 371 tests, and a min-content probe consumed exactly that value.
- **Inside a byte-exact per-pixel comparison**, which is the instance worth
  remembering. A test read back every pixel a real `Renderer` drew and compared
  it to the glyph atlas — indexing into the atlas **through the sprite's own
  `atlasBounds`**. A one-texel source shift left it green, because the
  expectation moved with the mutation. It reads as the strongest assertion in
  its file: hundreds of bytes, exact equality, a real GPU. Rewritten to take its
  expectation from a locally rasterized bitmap, both one-texel shifts now redden
  exactly it.

**The generalisation is the useful part: a hand-built fixture escapes this and
production-built input does not.** The earlier version of that same pixel test
built its sprites *by hand* and had no problem — the atlas coordinate was on one
side of the comparison only. The moment the sprites came from production code,
the coordinate appeared on both sides and the assertion went hollow. So the
hazard arrives exactly when a test is made more end-to-end, which is when it
feels like it is getting stronger.

**The check:** for every expected value in a test, name where it came from. If
the answer is "the thing I am testing", or "a function that calls the thing I am
testing", the test cannot fail for the bug it exists to catch. An independent
oracle — the platform API, a hand-computed constant with its arithmetic in the
comment, a second implementation — is the whole fix.

### 13. A test whose own structure truncates the suite

Shape 11 is a *run that did not happen*, and every instance of it so far came
from a **cleanup path** — a `defer { close() }` that reached
`NSApplication.terminate`, an over-released window that crashed a run-loop
observer. This one is new to this project and arrives from the opposite
direction: **the test body itself**, and only when the implementation is wrong.

Swift Testing's `#expect` **records and continues**. So:

```swift
#expect(placed.count == word.count)     // records the failure, keeps going
for i in 0..<word.count {
    #expect(placed[i].x == ctPenX(line, i))   // Index out of range
}
```

A mutation that made the emitter produce one glyph per *run* instead of per
glyph made the first `#expect` fail, the loop run anyway, and the subscript go
off the end of the implementation's own array: `Fatal error: Index out of
range`, **no summary line, ~200 tests never run.** A **wrong implementation
truncated the suite instead of reddening it**, which is the worst available
response to a defect — the report is exactly what the bug suppresses.

**The rule, and it costs one word: any count a later loop indexes on must be
`try #require`, not `#expect`.** `#require` throws out of the one test and
leaves the suite reporting.

```swift
try #require(placed.count == word.count)
```

The general form is wider than arrays: any `#expect` whose failure leaves the
rest of the test body operating on invalid state — an index, a force-unwrap
guard, a precondition on a count, a loop bound — belongs in a `#require`. Assert
with `#expect` where a failure is *survivable*, with `#require` where the next
line depends on it.

### 14. A confident wrong reason closes the question before it is asked

Shape 9 is a composition that exists in the code and in no test. This is the
*cause* of one, and it is worth its own entry because the failure happens in
prose, before any test is written or not written.

A task report's out-of-scope section asserted that two new modifiers "cannot" be
covered by `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`, because
`Handlers` holds closures and is therefore not `Equatable`. **The premise is
true.** The conclusion is false: that file already carries `HandlerShape`, a
hand-built `Equatable` *projection* invented two tasks earlier for exactly this
problem. Nobody looked, because the reason sounded finished. Both modifiers then
shipped with no coverage, and both mutants — a `keyContext(_:_:)` that also set
`isFocusable`, an `onAction(_:_:)` that also registered a pointer hitbox — stayed
green.

**The precedent this repeats is in CLAUDE.md's history**, and it is worth
reading as the canonical instance, even though the entry that once carried it
(divergence 5, ruling FS-3) is now retired: a task concluded the demo's
`ScrollView` wrapper needed a literal width because "width has no equivalent
escape" to `.minHeight(_:)`. `.minWidth(_:)` exists, one line below it in the
same file (`Sources/MetalUIDemo/main.swift`, where the correction now lives).
The conclusion happened to be right and the stated reason was wrong in two
directions at once, which is why nobody caught it for a milestone.

> **The tell is a "cannot" that was not measured.** A true observation is being
> used to close a question rather than to answer it. When a report says a test is
> impossible, the cheap check is to grep the test file for the problem's name
> before believing it — the machinery that solves it is usually already there,
> written by whoever hit it first.

### 15. A benchmark of a configuration in which the code under test is unreachable

This is shape 2's own lesson — "fixtures too shallow to distinguish two
models" — one level up, applied to a *performance* measurement instead of a
correctness one, and it is worth its own entry because the failure looks
identical to a clean result: the benchmark runs, produces numbers, and the
numbers are flat. Nothing about the run itself signals that the code under
test never executed.

The sizing milestone's TX-H fix re-runs an item's fit-content cross-size
measurement only for items whose used main size differs from their
hypothetical one, after `resolveFlexibleLengths` has run. Its first cost
measurement drove two branching trees under their **default** style — no
`alignItems` set. `Style.alignItems == nil` resolves to CSS's initial
`stretch`, and a stretch-eligible item is excluded from the new recompute
guard outright, by construction: its cross size comes from the line it was
stretched to, never from its own content, so the new code path is a no-op for
every item in a default-style tree. The numbers came back essentially flat —
some negative, one +9.6% at too small an absolute time to trust — which reads
exactly like "the fix is nearly free" and is actually "the fix never ran".

The implementer caught it themselves, before it reached the report as a
finding: the deltas were suspiciously close to zero given the change touches
every non-frozen auto-cross item on every line, and re-deriving what
configuration the new code actually requires (a non-`stretch` `alignItems`,
so at least one item both keeps an `auto` cross size and has its main size
change under flexing) is what explained why. Re-measured with `alignItems:
.flexStart` on every interior node — so the recompute guard is a live
candidate wherever an item's main size actually moves, which is pervasive in
a wide, deep, shrinking tree — the same two trees showed a consistent
**+2.4% (debug) / +3.2% (release)** cost on the larger sample. Recorded as
ruling `SZ-N`, `docs/superpowers/2026-08-30-sizing-decisions.md`, and in
CLAUDE.md's layout-cost section, which keeps both tables: the default-style
one (confirming the canonical flat per-node figures are unmoved, because that
tree shape genuinely never reaches TX-H's code) and the `flexStart` one
(measuring the fix's actual cost where it fires).

**This is the measure-performance milestone's "measure on a BRANCHING tree,
never a chain" lesson (CLAUDE.md's layout-cost section) arriving in a new
costume, and the parallel is exact enough to name.** A chain hides a cost by
collapsing every probe onto the same few cache keys, so the measurement looks
linear and cheap while never exercising the case that matters. `stretch`
hides a cost by skipping the changed branch entirely, so the measurement
looks free while never exercising the changed code at all. Different
mechanism, same shape: a tree or a style chosen for convenience turns out to
be the one configuration that cannot see the thing being measured, and a
confident number comes back about nothing.

> **Before trusting a flat or near-zero delta, ask what property of the input
> would make the changed code a no-op — then check the benchmark doesn't have
> that property.** A tree shape can collapse a cache; a container style can
> skip a branch; a fixture value can equal its own default. Each is invisible
> from the number alone, and each is cheap to rule out once named: change the
> one input the diff actually reads and confirm the number moves.

### 16. A `@testable` test file cannot prove an access-level narrowing

**The tool that gives a test its reach is the tool that hides the change.**
`@testable import` raises `internal` to be visible from the test module, so a
test file that imports that way sees an `internal(set)` property exactly as it
saw a `public var` — and every assertion it can write is green before the
change, after it, and with the change reverted.

The instance. The tombstones-and-AX milestone narrowed two `AXNode` properties
from `public var` to `public internal(set)`, closing a demonstrated footgun (a
stray write to one of them flipped an `isEmpty` check and would have emitted a
real but empty node). `AXNodeTests.swift` uses `@testable import MetalUI`.
**Nothing in that file — the file whose whole subject is the type — could
demonstrate the fix closed anything.** The narrowing is not observable at
runtime at all: it is a compile-time property, and the only instrument that can
see it is a compiler invoked against a **plain** import of the built module.

The remedy is machinery this repo already has:
`Tests/MetalUITestSupport/Typecheck.swift`'s `canTypecheck`, used the way
`ErasureCompileGuards.swift` uses it — write a snippet that assigns to the
narrowed property, compile it against a non-`@testable` import, and assert it
fails *with the expected diagnostic*.

**And the guard itself needed the same discipline it exists to enforce.** The
first draft asserted the diagnostic contained `"Cannot assign"` where the real
text is lowercase `"cannot assign"`. `!result.succeeded` still held, so the
test passed — on one of its two assertions, with the half that says *why* it
failed to compile never matching anything. It was caught by **printing the real
diagnostic before trusting it**, not by re-reading the string.

> **Before writing a test for a visibility, access-level or module-boundary
> change, check the import line.** If it says `@testable`, the test cannot see
> the change and a green result means nothing. This generalises past `AXNode`
> and past this repo: it applies to any narrowing — `private`, `internal`,
> `fileprivate`, `internal(set)`, and to `@_spi` — and the tell is that the
> change has no runtime behaviour to assert on at all.

### A fixture hazard worth knowing before you write goldens

WebKit quantizes to 1/64 of a pixel. Where the engine computes an exact `x.5`,
WebKit may land on `112.484375` — and cumulative rounding then sends the two to
different integers. Five probes on the wrapping branch appeared to differ by 1px
for this reason alone and agreed exactly once re-cut with divisible geometry.

**Choose fixture geometry so no box edge or line origin falls on `x.5`.**
Otherwise the golden encodes a rounding coin-flip rather than the behaviour the
fixture is named for — and it will look like a real disagreement to whoever
inherits it.

#### The differential is necessary and not sufficient

Changing the declaration a fixture is named for and watching the numbers move
proves the *browser* is sensitive to that declaration. It does not prove the
*engine site* the fixture exists to pin is load-bearing for the golden — a
downstream rule (stretch, a clamp, a single line taking its cross size from the
container) can overwrite the measured value before it reaches any number, and
then the fixture is green before the feature, after it, and with the feature
deleted. Measured: the content-sizing plan's `flex_nested_auto_cross` gave
WebKit `mid 120x200`, moved to `120x10` under its own differential, and produced
the identical layout in the engine with the entire milestone reverted.
**Close the loop with a mutation: revert the site the fixture names and confirm
that fixture reddens.** The differential is a fixture-authoring check; mutation
is the coverage check. They are not substitutes.

**It is not a one-off.** The mechanism recurs wherever a downstream rule
overwrites the measured value, and the corpus already held a prior instance
before anyone looked for one: `flex_wrap_stretch_auto_cross` is *named* for the
auto cross size, and its `.b`/`.d`/`.f` are empty divs stretched by their line —
which is why the content-sizing re-baseline found that site reddening **zero**
goldens while a fixture bearing its name sat in the corpus.

## When *not* to add a test

Not every unguarded behaviour should be forced into a test. The trailing-gap fix
in `FlexEngine` has no killing test because `cursor` is loop-local and never read
— **no input can distinguish the two spellings.** Manufacturing an assertion there
would produce a test that passes because it tests nothing, which is the disease,
not the cure.

The honest move is to route the pin to where the behaviour becomes observable: the
justify-content task must read the cursor as content size, so its first test
asserts a 3×50 row with `gap: 12` reports **174, not 186**.

**Add a test when the behaviour is observable. Document the gap when it is not.**

## Where this pays off most

- Anything described as "load-bearing", "critical", or "the whole point" (§5)
- Any guard, probe, or safety net — prove it fires (§6)
- Any committed artifact — prove something reads it (§3)
- Any constant that encodes a decision (§5)
- Any API surface carried for a future backend (§4)
- Before trusting a green suite on work you did not watch being written
