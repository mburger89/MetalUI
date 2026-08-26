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

## The taxonomy — eleven shapes, all found in this repo

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

### A fixture hazard worth knowing before you write goldens

WebKit quantizes to 1/64 of a pixel. Where the engine computes an exact `x.5`,
WebKit may land on `112.484375` — and cumulative rounding then sends the two to
different integers. Five probes on the wrapping branch appeared to differ by 1px
for this reason alone and agreed exactly once re-cut with divisible geometry.

**Choose fixture geometry so no box edge or line origin falls on `x.5`.**
Otherwise the golden encodes a rounding coin-flip rather than the behaviour the
fixture is named for — and it will look like a real disagreement to whoever
inherits it.

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
