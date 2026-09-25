## When CI lands

**Erratum 2026-09-14 (at `7cfcddc`; record §09), three corrections.** (a) **CI has
landed.** `.github/workflows/swift.yml` (`00f6b2c`, 2026-09-10, an ancestor of
`a15ec83`) runs `swift build -v` and `swift test -v --no-parallel` on
`macos-latest` for pushes and pull requests to `master`. None of the guarantees
below is a separate required job. Under that workflow's default build system,
whether any typecheck guard executes at all is **unmeasured**; item 3's
swiftbuild paragraph predicts that none does. (b) **The guard count's eighth
move: 39** = 19 + 10 + **5** + 2 + 3. `ElementGroupTrapTests` went from 1 to 5
with four proposal-surface guards. **Only one of the four was written in the
change that introduced its hazard** (the text bridge's, `4bda3d3`): the overlay,
tap and constructor wrappers first shipped over unconstrained
`Content: ElementGroup` (`fdf5ce0`, `140d2d2`, `1823698`) and gained their
guards later, in `16744b9`, `21b8fcc` and `b8ba46d` — the first break in the
"written in the change that could have introduced the hazard" pattern this file
records for every earlier move. Per-file `grep -c canTypecheck` across the five
guard files reads 40, one hit being `UnitSafetyTests`' comment. Every "35" below
is dated `b869253`, and every "34" (item 3's opening line included) is the
Component milestone's count at suite 811, as item 3's note on the fifth and sixth moves says.
(c) **The list below is short one item.** Item 5, the freeze loop's allocation
pin, was added to `CLAUDE.md` on 2026-09-11 and never reached this file; it is
appended at the end, so "Three guarantees" below now reads five.

Three guarantees silently lapse under plausible configurations and must be
required, non-gateable jobs. All three are detailed in the decisions docs:

1. The ABI probe **skips** without a Metal device.
2. `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
3. **The 34 `swiftc -typecheck` guards skip whenever `.build` is not where
   `#filePath`-relative resolution expects it.** `canTypecheck`
   (`Tests/MetalUITestSupport/Typecheck.swift`) walks three directories up from
   its own `#filePath` and looks for `.build/<triple>/debug/Modules` holding the
   module; a `--scratch-path`, a CI that builds elsewhere, a moved checkout, or
   `swift test -c release` all make that miss and every guard becomes a skip.
   **That set is this milestone's headline deliverable and both of its
   compile-time exit criteria** — `PhaseSeparationTests` (**19**),
   `ErasureCompileGuards` (**9**), `ElementGroupTrapTests` (1), `UnitSafetyTests` (2,
   in `Tests/MetalUICoreTests/`, where a bare `grep -c` reads 3 because one is a
   comment) and `AXNodeTests` (**3**, in `Tests/MetalUITests/`, added by the
   tombstones-and-AX milestone — see the last block of this item)
   — and none of them has a runtime equivalent, by construction: each asserts
   that something must *not* compile, so a regression makes the offending code
   compile and leaves every ordinary test green.

   **Taxonomy shape 11's count heuristic does not catch this one.** Measured, by
   forcing `canTypecheck` to `false`: exactly 25 tests report as skipped, the
   total does not move, and the run passes. **The 25 is dated — it is the guard
   count at the time, and the guard count is 34 today.** The load-bearing half
   is the other two clauses, "the total does not move" and "the run passes",
   which are properties of `.enabled(if:)` rather than of any count; that a
   skip counts toward the total was independently re-measured at the
   tombstones milestone (see the Build section). Nobody has re-forced
   `canTypecheck` to `false` since, so **do not read 34 into this sentence** —
   the number that would appear has not been run. The 25 was first taken at
   `Test run with 304 tests`, re-measured at 358 on the structural-identity
   branch, and **re-counted at the end of M2 (suite 444): still 25 — 15 + 7 + 1
   + 2 across the four files**, where `grep -c canTypecheck` reads 3 in
   `UnitSafetyTests` because one is a comment. **Re-counted again at the end of
   the clipping-and-scroll milestone (suite 488), again at the end of the
   stack milestone's review round (suite 538), and again at the end of absolute
   positioning (suite 577): still 25. Re-counted again at the end of
   measure-performance (suite 604), and once more after that milestone's
   whole-branch fix round (suite 609): still 25 — by grep both times (15 + 7 + 1
   + 2 across the four files) rather than by forcing `canTypecheck` to `false`,
   which is the weaker of the two methods and is said so rather than implied.**
   The suite has
   moved 304 → 358 → 444 → 488 → 538 → 577 → 604 → 609 and the guard count has not moved at
   all, which is the paragraph's point arriving as eight data points rather than as
   one delta — the argument is that the two numbers are independent, so do not
   restate it as "the suite grew by N and the 25 held", which rots the moment N
   changes. **The guard count does not track the suite count and neither number
   implies the other.** A falling suite count
   is the signal shape 11 tells you to watch, and this failure does not move it.

   **It finally DID move, at the input-and-state milestone's Task 6 fix round
   (suite 640): 27 — 17 + 7 + 1 + 2, by grep.** `PhaseSeparationTests` gained
   two, `queryingHoverDuringPrepaintDoesNotCompile` and
   `queryingActiveDuringPrepaintDoesNotCompile`, for `theme`'s own reason
   stated sharper: a colour read during prepaint simply fails to compile, but
   `isHovered`/`isActive` would **compile and lie** if reachable there —
   returning a silently wrong `false` from a syntactically fine call. Two
   independent things make it wrong, and the guard is worth having for the
   second even more than the first: `Frame.hoveredHitbox` is still `nil`
   because `resolveHover(at:)` runs *after* prepaint returns, **and** the
   hitbox list is still being built, since `PrepaintPass.insertHitbox` is
   what fills it. So a prepaint-time answer would be wrong even if hover
   had somehow already resolved — it would rank against a partial list,
   which is exactly §3.3's reason for resolving once at the boundary
   rather than during registration: "topmost wins" is not knowable until
   every hitbox is registered. (This sentence said the opposite when first
   written — "every hitbox has already registered by the time
   `PrepaintPass` runs" — which inverts the mechanism the guard exists
   for.) **This does not contradict "the guard count does not track the
   suite count" above — it is the other half of the same claim, not an
   exception to it.** Every prior re-count held 25 steady while unrelated
   tests were added elsewhere; this one moved because a guard was
   *deliberately written* in the same change that could have introduced the
   hazard it guards against, which is what a compile-time guard is for. The
   two numbers still do not imply one another: 640 does not say 27, and nothing
   here claims it does.

   **It then moved twice more in the same milestone, to 28 and to 29 — and
   both times for that same reason, which is the pattern to recognise rather
   than a count to memorise.** Task 9 added
   `queryingFocusDuringPrepaintDoesNotCompile` (**28** = 18 + 7 + 1 + 2) and
   Task 11 added `queryingElementKeyedHoverDuringPrepaintDoesNotCompile`
   (**29** = 19 + 7 + 1 + 2). Both are guards written in the same change that
   could have introduced the hazard. **Re-counted by grep at the whole-branch
   fix wave (suite 739): still 29** — 19 + 7 + 1 + 2 across the four files,
   where `grep -c canTypecheck Tests/MetalUICoreTests/UnitSafetyTests.swift`
   reads 3 because one of them is a comment. The fix wave added three tests and
   no guard, which is the paragraph's own claim arriving once more.

   **The focus one is the case worth reading, because its brief FORBADE adding
   it by symmetry and the measurement went the other way from how the question
   was framed.** The framing was "focus is window state fully known before the
   frame starts, so `isActive`'s justification may not apply". Measured: an
   element that stops being focusable reads `prepaint=true / paint=false` in
   the **same frame**, because `Frame.resolveFocus()` clears at the boundary —
   so a prepaint-time `isFocused` returns a wrong `true`. And answering that
   honestly for the new guard answered it for an old one **in the opposite
   direction**: `isActive`'s guard is *not* a measured lie, because
   `Frame.activeElement` is a `let` assigned once in `init` and a prepaint-time
   `isActive` would answer correctly. Its guard is kept as placement insurance,
   and the shared comment says so instead of implying one measurement covers
   all three. The paragraph above still describes `isHovered` correctly; it
   described `isActive` wrongly until this was measured.

   **Task 11's is a second SPELLING rather than a second member.** The
   element-keyed `isHovered(_ id: GlobalElementID)` overload landed for
   `Box.paint` to reach (ruling IN-V), and the existing hover guard probes the
   `HitboxID` spelling — so adding *only* the new one to `PrepaintPass` would
   leave that guard green while shipping the identical hazard. Two spellings
   need two probes.

   **It moved a fourth time, at the tombstones-and-AX milestone: 32, and for
   the FIRST time across a fifth FILE** — 19 + 7 + 1 + 2 + **3**, the three new
   ones in `Tests/MetalUITests/AXNodeTests.swift`. Re-counted by grep per file
   at that milestone's last commit (suite **782**), both counting methods
   agreeing where they can. **This is the paragraph's own claim arriving a
   fourth time, not an exception to it**: the suite has now moved 304 → 358 →
   444 → 488 → 538 → 577 → 604 → 609 → 640 → 739 → 782 → **791** → 810 → **811** and
   the guard
   count has
   moved six times, at commits that had nothing to do with the suite's size.
   782 does not say 32 and nothing here claims it does — nor does 791, which is
   the reactivity milestone's count, **re-counted by grep per file at its last
   commit and still 32** while nine tests were added. The two numbers moved
   independently one more time, which is this item's whole argument.

   **The fifth and sixth moves are both the `Component` milestone's, at suites
   810 then 811: 33 then 34** — `ErasureCompileGuards`'
   `backgroundCannotBeCalledOnAComponent` (ruling `CO-W`) in the task round,
   and `layoutPassStyleAccessorsAreNotPublic` in the fix wave, for the
   `public` → `internal` narrowing of `LayoutPass.style`/`setStyle`. **The
   sixth is the WEAKEST data point this item has, and it is recorded as such**:
   a compile guard is a `@Test`, so it moved the suite count and the guard count
   together, by one each — the only move in the series that did. The
   independence claim rests on the other five and on every milestone where the
   suite grew while this number held. Same pattern as the five before it — a guard written in the same
   change that could have introduced the hazard, not a guard that tracked a
   growing suite. **And it adds a counting trap the item above does not
   describe.** `grep -rl canTypecheck Tests/` now returns **six** paths and only
   five carry guards: the sixth is
   `Tests/MetalUITestSupport/Typecheck.swift`, whose single hit is
   `canTypecheck`'s own **declaration**. Summing per-file `grep -c` across every
   matching path reads **36**, not 34. Count guards, not files, and check what
   each hit actually is.

   **The reason these three exist is a new hazard rather than a new phase
   guard, and it generalises past this repo (ruling `TB-N`).** Task 5 narrowed
   `AXNode.frame`/`children` from `public var` to `public internal(set)`.
   `AXNodeTests.swift` uses **`@testable import`, which widens `internal` — so
   no test in that file could demonstrate the narrowing closed anything at
   all.** The tool that gives a test its reach is the tool that hides the
   change. Proving it needed guards against a **plain** import of the built
   module, on `ErasureCompileGuards.swift`'s pattern; Task 6 added a third for
   `isValid`, confirmed by mutation (widening `isValid` to `public var` reddens
   exactly the new guard and nothing else in 777). **And the first draft of one
   guard was passing on its weaker half only**: it asserted the diagnostic
   contained `"Cannot assign"` where the real text is lowercase
   `"cannot assign"`, so `!result.succeeded` held and the message assertion
   never matched — caught by printing the real diagnostic before trusting it,
   which is the same two-assertion hazard the `HitboxID`/`GlobalElementID`
   hover probes above record from the other direction.

   **Re-count by grep, and note the DIRECTORIES — there are now two of them.**
   (**The totals in this paragraph are the tombstones milestone's**, when the
   count was 32; the fifth-move note above carries today's 34 and the six-path
   trap. The claim being made here is about directories, not about either
   number.)
   `Tests/MetalUICoreTests/UnitSafetyTests.swift`, not `MetalUITests`; and
   `Tests/MetalUITests/AXNodeTests.swift`, not `MetalUICoreTests`. A recheck
   that greps the wrong directory silently reads 26 instead of 32 — or misses
   the AX file entirely and reads 29, which is exactly the number this
   paragraph carried for eight milestones and would therefore look right.
   `UnitSafetyTests` still reads 3 by a bare `grep -c` because one occurrence
   is a comment; `AXNodeTests`' 3 are all real guards.

   **Not converted to a hard failure, and the reason is a configuration rather
   than a preference.** The obvious rule — fail rather than skip when `.build`
   exists at all — reddens `swift test -c release` on a clean checkout, where
   `.build` exists and only `release/Modules` is populated. It also does not fire
   in the `--scratch-path` case it is aimed at: a checkout that has ever been
   built normally still has a populated `.build/…/debug/Modules`, so
   `canTypecheck` returns *true* and the guards run against **stale** modules,
   which is a worse failure than the skip and a different bug. The fix that
   actually closes it is to resolve the modules directory from the **running
   test binary's** own location rather than from `#filePath`, which is correct
   under every configuration above; it was out of scope here.

   **The seventh move, and a SECOND configuration that fires this item — the
   default build system. Animation milestone, 2026-09-10, ruling `AN-V`
   (`docs/superpowers/2026-09-03-animation-decisions.md`).** The count is **35**,
   re-taken by per-file `grep -c canTypecheck` at `b869253`: 19 + **10** + 1 + 2
   + 3, the new one being `pendingTransactionIsNotPublic` in
   `ErasureCompileGuards` (so that file reads 10, not 9) for
   `Animation.pendingTransaction`'s `public` → `internal` narrowing — a guard
   written in the same change that could have introduced the hazard, which is the
   pattern all six earlier moves share. Summing per-file `grep -c` across the six
   matching paths now reads **37**, not 35; the two extra are
   `Typecheck.swift`'s own declaration and `UnitSafetyTests`' comment. **Count
   guards, not files, and check what each hit actually is.**

   **And the paragraph above predicted the stale-modules failure for
   `--scratch-path`; it now fires on an ordinary developer machine with no
   flags at all, for a reason this item did not name.** SwiftPM's default build
   system is `swiftbuild`, which writes modules **flat** into
   `.build/out/Products/Debug/` (reached by the `.build/debug` symlink) with **no
   `Modules` subdirectory anywhere**. `modulesDirectory` looks for
   `<entry>/debug/Modules` and finds none — so under swiftbuild alone **all 35
   guards skip**, the total does not move, and the run passes. **But
   `--build-system native` writes `.build/<triple>/debug/Modules` and that
   directory survives**, and `canTypecheck` scans every `.build` entry — so once
   a checkout has *ever* been cross-checked under native, the guards run under
   the **default** build system too, **against those leftover native-built
   modules rather than against what swiftbuild just built**. Measured both ways
   at `b869253`: with `.build/arm64-apple-macosx/` present, two named guards
   report `started`/`passed` under the default build system and the full default
   run skips only the two env-gated tests; with the identical command and that
   one directory moved aside, both report `skipped` carrying `canTypecheck`'s own
   message, and the total is **861 either way**. **So the cross-check that
   established the skip is what stops it being true**, and a guard count is not
   evidence that any guard ran.

   **Two consequences for CI, and one deadline.** Every mutation run in an
   isolated `git worktree` — this project's standing practice — happens where no
   `.build/<triple>/debug/Modules` exists, so **no guard executes in any of
   them**; that is immaterial for a round touching only prose or test content
   and material for one touching a module boundary or an access level. And
   `--build-system native`, the workaround the count is taken under, prints
   `'--build-system native' has been deprecated and will be removed in a future
   release`. **The `#filePath` fix named above is therefore a dated obligation
   rather than a preference.**

4. **Six — now SEVEN — device-dependent window tests HARD-FAIL rather than skip
   on a runner with no display device**, and they belong beside the ABI probe in
   item 1 rather than sharing its treatment silently. The animation milestone
   added `makeFakeWindowOnDefaultDevice` (`Tests/MetalUITests/Fakes.swift`),
   which `throw`s `NoMetalDevice` where the surrounding convention is
   `try #require(MTLCreateSystemDefaultDevice())`. **Both fail rather than skip**,
   so this is not a behaviour change and not a new class of hazard — the branch
   simply added tests in that shape. Task 5's review counted **six** at suite
   859; **re-counted for the record task at `b869253` it is seven**, the extra
   being `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`,
   which fix round 2 added after that review. The seven are
   `aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd`,
   `theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds`,
   `aParkedTransactionIsConsumedByExactlyOneBuild`,
   `anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting`,
   `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`,
   `aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning` and
   `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`,
   all in `AnimationTests.swift`. **This count is dated like every other count in
   this file** — it is a property of how the fixture is written, not of the
   suite, so re-take it by greping for the helper rather than trusting the seven.

5. **The freeze loop's allocation pin checks only half of itself on a swiftlang
   toolchain, and says so in the log.** (Added 2026-09-14, at `7cfcddc`, from
   `CLAUDE.md`'s "When CI lands" bullet as it stood at `a15ec83` and from the
   test source; the measurements below are the test's own comment, not re-taken
   here.) Under Apple's swiftlang build of Swift — Xcode, and every GitHub macOS
   runner — a bare `for i in items.indices { sum += items[i].baseSize }`
   registers **one allocation per element** in a debug build, where a swift.org
   toolchain registers none: measured 2026-09-11 on Swift 6.3.3
   (swift-6.3.3-RELEASE) and 6.4 (swiftlang-6.4.0.34.1), 0 vs 67 at 67 items,
   and 16 known buffers read as 16 and as 33
   (`Tests/MetalUILayoutTests/FreezeLoopAllocationTests.swift:161-169`). So an
   absolute per-pass bound there measures the toolchain, not
   `resolveFlexibleLengths`.
   `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine` (`:153`, final shape
   from `37f8d3e`) measures that floor in the same run (`loopFloor`), always
   checks a relative half against the allocating reference spelling
   (`referenceResolveFlexibleLengths`: `growMany * 2 <= refMany`, and the saving
   must widen with the line), and checks the strict half — equal counts at
   7 and 67 items, at most `passesPerLine` (2) per line — **only when the floor
   at 67 items is 0** (`if floorMany == 0`). Otherwise it prints, and asserts
   nothing strict:
   `FREEZE-ALLOC: strict per-pass bound NOT CHECKED on this toolchain` (`:241`).
   **On a swiftlang toolchain a per-item regression of about one allocation is
   invisible to it**; grep a CI log for that line, and run the suite under a
   swift.org toolchain to get the strict half. The workflow in (a) runs on
   `macos-latest`, so by reading its runs take the relative half only; no CI log
   was read for this entry, so whether the line is printed there is
   **unverified**.

---

## 2026-09-15: items added at the task 3/9/12 integration

The guard count the default-build-system skip hides is now 61. New items, in
`CLAUDE.md`'s CI section: the solver-threshold flag of
`aTwentyFourModifierChainTypechecksWithinASolverWorkBudget`; two `malloc_logger`
tests needing `--no-parallel`; E24's hard failure on a root-locale runner; the
accessibility arm-Q pin and signal test depending on the runner's accessibility
clients and `isVoiceOverEnabled` (`AB-AC`).

## 2026-09-24: item 5 retired at engine replacement stage 7b

Record §49; rulings `LR-EC`…`LR-EP`. **Item 5 above (the freeze loop's
allocation pin checking only half itself on a swiftlang toolchain) is
retired**, not amended: `Tests/MetalUILayoutTests/FreezeLoopAllocationTests.swift`
— the file item 5 cites throughout — is deleted whole, one of the seventeen
non-golden CSS-engine files stage 7b retires (record §49 §4, rows 183–184; no
replacement pin, since the fact is toolchain accounting for a CSS-engine-only
loop, not a fact the proposal engine has). `ModifiedElementTests.swift`
remains the suite's only `malloc_logger` installer (record §49 §6.2's
"Comments" paragraph), so the two-installer race item 5's neighbouring
`malloc_logger` note (2026-09-15, above) used to describe is now moot — one
installer cannot race itself. `FREEZE-ALLOC: strict per-pass bound NOT
CHECKED` no longer appears in any CI log; a reader grepping for it after this
stage finds nothing, which is retirement, not a broken instrument.

## 2026-09-24: one item added at engine replacement stage 10

Record §52; rulings `LR-FM`…`LR-FT`. **New item: the closing check is
compiled out on Windows.** `Tests/MetalUICrossPlatformTests/LegacyEngineSymbolTests.swift`
(`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, `N2.1`) is gated
`#if canImport(Darwin) || canImport(Glibc)` — it runs on macOS and Linux,
where `dlsym` resolves each mangled name against the test process, and does
not exist on Windows at all, which has neither C library. `root-windows` CI
therefore never runs this test and its absence there is by design, not a
skip to investigate; a reader who greps a Windows CI log for its name and
finds nothing has not found a regression. Confirmed independently in this
stage's Record phase (record §52 §6.2 item 6) on a `swift:6.4-noble` (Linux
aarch64) container, where the test does compile and pass, and by reading the
`#if` line itself.
