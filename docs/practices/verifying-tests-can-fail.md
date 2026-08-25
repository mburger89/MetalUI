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

## The taxonomy — eight shapes, all found in this repo

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
