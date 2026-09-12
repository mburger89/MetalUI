# Sizing — decisions taken during execution

Rulings from the milestone that closed four sizing divergences a root
percentage falling back to the offered extent instead of resolving against
it, an over-constrained box refusing to grow its border box (BM-4), an item's
automatic minimum ignoring its specified size (FS-3), and an item's cross size
being measured before §9.7 flexes it (TX-H). Prefixed **`SZ-`** and
**lettered** (`SZ-A`, `SZ-B`, …) per this repo's convention — **a bare `SZ-3`
is a typo, not a citation**, the same note every other milestone's decisions
doc carries.

Read alongside `docs/superpowers/specs/2026-08-30-sizing-design.md` (§2 has
the four fixes with their WebKit numbers, §8 the exit criteria, §9 the risks
recorded up front) and `.superpowers/sdd/2026-08-30-sizing/progress.md`, the
execution ledger these rulings are drawn from. As with the input-and-state
milestone's own doc, where a plan's stated reason turned out wrong under
measurement, that is said rather than smoothed over — three rulings below
correct a plan claim that a prior ruling in this same milestone had already
gotten wrong once.

**This document was written while the milestone was still in flight, and
Tasks 8 and 11 have both landed since.** `SZ-A` through `SZ-L` were settled
first, from Tasks 1 through 7 and 9. `SZ-M` and `SZ-N` were placeholders for
Task 8's own rulings and are now filled in below, from Task 8's landed
report — not guessed ahead of the work.

**`SZ-M` carries a second identity worth recording, because two tasks
collided on it.** Task 8 ran in a worktree, in parallel with Task 10 writing
this very document, and neither could see the other; Task 8 labelled its own
ruling `SZ-B`, which Task 10 had already assigned (below) to "a fixture's
declared numbers are verified against the live oracle". Task 11 renumbered
Task 8's citation — in both `Sources/MetalUILayout/FlexEngine.swift` and this
document — to `SZ-M`, the letter actually reserved for it. If a citation of
`SZ-B` is ever found describing the `ownCross`/`itemFitContentCrossSize`
re-run choice rather than the fixture-verification rule, it is the collision,
not a third ruling — this is the hazard CLAUDE.md's own `EP-2`/`EP-4` note
exists to prevent.

---

## SZ-A — a root percentage resolves against the offered extent, per axis; `auto` is deliberately untouched

**The choice.** `resolveRootSize`'s `declared` helper gains a second,
axis-scoped basis parameter. The root's own `width`/`height` percentage now
resolves against `definiteExtent(offered)` on the **same** axis — `width`
against `available.width`, `height` against `available.height` — instead of
against `nil`.

**Reasoning.** CSS resolves a percentage against the containing block; this
engine's root previously could not, because `declared` was called with no
basis at all, so a percentage `width`/`height` silently fell back through the
`auto` branch to the offered extent untouched. Measured against WebKit:
`#root { width: 50%; height: 25% }` inside an 800×600 offered space is
**400 × 150**, where the unfixed engine gave 800 × 600.

**`auto` is byte-identical, and that is the load-bearing half of the
decision.** `declared` returns `nil` for a literal `.auto` regardless of what
basis it is given, so the `auto` branch — the one CLAUDE.md already records a
*reverted* attempt against, because changing it reddened six element-pipeline
and frame-loop tests — is untouched by this change. Ruling CS-I (an `auto`
root axis takes the offered extent rather than shrink-wrapping) and divergence
4 both **survive this milestone by decision**, not by oversight; see `SZ-C`'s
companion note for the other place this milestone touched the same function
and stopped short. (This read `SZ-B` until the fix wave. `SZ-B` is the rule
that a fixture's numbers come from the live oracle rather than an engine
probe — nothing to do with `resolveRootSize`. `SZ-C` is the root's percentage
`min`/`max` clamps keeping the no-basis form, which is literally the other
place in that function this milestone touched and stopped short. Corrected
rather than silently fixed, per this repo's rule about false claims.)

**What it costs if wrong.** Reddens nothing in the existing 741/742-test
corpus by design — the suite was blind to root percentages before Task 1 added
`rootPercentageMatchesWebKit`, which is the only test that can see this rule
at all. A regression here is invisible to every other test in the repository.
Confirmed by mutation: reverting the basis to `nil` reddens **only**
`rootPercentageMatchesWebKit`, both the width and height fields, and nothing
else in the 742-test suite.

---

## SZ-B — a fixture's declared numbers are verified against the live oracle before the comparison test is written, never derived from an engine probe

**The choice.** Every fixture-first task in this milestone (1, 3, 5, 7) must
generate its golden and read it back **before** writing the Swift comparison
test, and report a mismatch against the brief rather than silently adjusting
the test to fit.

**Reasoning.** Task 1's own brief got this wrong on its first draft: the
plan's fixture HTML omitted `html, body { height: 100% }`, and without it CSS
2.1 §10.5 makes a percentage `height` fall back to `auto` — the real oracle
measured the root's height at **40** (hugging its 40px child), not the 150 the
brief's numbers claimed. The 150 was correct about *this engine's own probe*
(which uses `available:` directly with no `html`/`body` at all) and wrong
about the browser it was meant to pin. The implementer caught it by running
the oracle rather than by trusting the brief, added the missing rule with an
explanatory comment, and regenerated: **400 × 150**, matching the brief's
intent.

**Named because it is not the first instance.** Task 3's engine-side
prediction was independently wrong for a different reason (see `SZ-G`), Task 6
found a third case of the same family — a fixture's HTML and its Swift tree
describing two different trees (`SZ-I`) — and Task 7 found a fourth: the
brief predicted three issues (`.a`'s height plus both second-line items
landing at the wrong `y`) and the fixture delivered **one**, because the
outer freeze loop shrinks `.a`'s width by ordinary main-axis flexing before
`ownCross` ever runs, so its children wrap correctly and land at the right
absolute positions regardless of TX-H's defect — only `.a`'s own reported
height is wrong. That reasoned about the *visual* consequence (text spilling
its box) and assumed the geometry would follow the same story, when the
geometry is computed from a width the defect does not touch. All four are one
shape: an artifact written from reasoning about the engine, never actually run
through the instrument it is meant to pin — and the fourth instance is the
sharpest one, because a single-number failure is a *better* fixture than the
three-way one the brief designed, isolating the defect rather than letting a
regression elsewhere hide in the noise.

**What it costs if wrong.** Had the brief's original, unverified numbers been
committed, Task 2's fix would produce 400×150 and fail against a
wrong-but-committed golden — a fixture silently encoding the wrong rule into
the corpus, indistinguishable from a real regression to every later reader.

---

## SZ-C — the root's percentage `min`/`max` clamps deliberately keep the no-basis form

**The choice.** `resolveRootSize` grows a two-arity `declared(_:axis:)` for
the root's own declared size (`SZ-A`), but the `min`/`max` clamp callers at
the end of the same function are left calling the original one-arity,
no-basis `declared(_:)`.

**Reasoning.** This task implements the root's percentage **size**; whether a
percentage `min-width`/`max-width`/`min-height`/`max-height` on the root
should also take a basis is a genuinely separate question, and — unlike the
size case — has no fixture behind it in this milestone. Extending the basis to
those callers on the strength of the size fix's own reasoning would be
implementing an untested rule under cover of a tested one.

**What it costs if wrong.** A root percentage `min`/`max` still resolves
against `nil` and is silently unresolvable, exactly as the size case was
before `SZ-A` — the same failure mode `SZ-A` fixes, left open on one more
property. Nothing in the 12-task plan or the shipped corpus exercises it, so
the cost is bounded to "a future caller of a percentage root `min`/`max` gets
the pre-`SZ-A` behaviour and no test says so" — visible the moment someone
writes the fixture, and recorded here so that fixture's author knows this is
open rather than an oversight to route around silently.

---

## SZ-D — BM-4's border-box floor applies AFTER the min/max clamp, settled against the live oracle rather than chosen

**The choice.** Every site that turns a node's declared size into a used
border-box size computes `max(clamp(resolved, min: …, max: …), floor)`, never
`clamp(max(resolved, floor), min: …, max: …)`. The floor is applied last.

**Reasoning.** The two orderings differ only when a `max-*` is smaller than
the box's own padding + border, and the plan required this be settled by the
oracle rather than by taste. Measured with a throwaway probe (deleted before
commit):

| probe | declaration | floor-then-clamp | clamp-then-floor | **WebKit** |
|---|---|---|---|---|
| cross axis of a row item | `height: 80; max-height: 40; padding: 60px 0; border-width: 10px 0` (140 of vertical edges) | 40 | 140 | **140** |
| main axis of a row item | `width: 100; min-width: 0; max-width: 40; padding: 0 50px; border-width: 0 10px` (120 of horizontal edges) | 40 | 120 | **120** |

A `max-*` smaller than the box's own padding + border does not win in either
axis — the clamp is applied first, and the floor is what survives. Implemented
as `max(clamp(…), floor)` at every one of the five call sites (`SZ-E`).

**What it costs if wrong.** The reverse ordering (`clamp(max(…), …)`) is
mechanically distinguishable and is exactly what `borderBoxFloor`'s own
mutation testing checks for: inverting the ordering at the `resolveNodeSize`
site reddens `anItemsCrossSizeGrowsToFitItsPaddingAndBorderEvenPastItsMax` by
itself, so a regression here is caught rather than silent. Get the order wrong
and a box whose padding and border exceed a `max-*` clamps down to the
`max-*` instead of growing past it — the opposite of what BM-4 exists to fix,
shipped under BM-4's own name.

---

## SZ-E — BM-4's floor lands at five call sites, and `contentBox`'s own zero-clamp stays because it is still live in the engine

**The choice.** `borderBoxFloor(_:_:containingBlockWidth:rootFontSize:)`
(padding + border per axis, resolved against the containing block's **width**
on every edge) is applied at `resolveRootSize`, `resolveNodeSize` (a flex
item's cross axis), `flexBaseSize`'s size-property branch (a flex item's main
axis, see `SZ-F`), `layOutStack` and `placeAbsolute`. `contentBox`'s
pre-existing `max(0, …)` content-box clamp is **not** removed.

**Reasoning.** BM-4's brief named one site (`resolveNodeSize`) but the rule —
"the used size is `max(specified, padding + border)`" — applies everywhere a
node's declared size becomes a used border-box size, which is five distinct
places rather than one. Each was measured against WebKit independently rather
than assumed to share an answer: `width: 100px; height: 80px;
padding: 60px 50px; border-style: solid; border-width: 10px` is **120×140**
as the root, as a flex item's cross axis, as an absolutely-positioned box, and
as a grid item — CSS's closest analogue to this engine's `display: .stack`,
since CSS has no `display: stack`.

**`contentBox`'s `max(0, …)` was reported as dead and is not.** The
implementer's own mutation — deleting it — reddened nothing in the suite that
existed at the time, which reads as a coverage gap to bank. Proving the mutant
actually behaves differently first (this repo's standing discriminator) found
that it is still live: a §9.7-shrunk container can hand a stretched child a
**stored height of −80**, which `contentBox`'s clamp is the only thing
preventing from reaching paint. It is kept, and now has its own pin rather
than relying on the suite's silence to justify it.

**What it costs if wrong.** Removing the `contentBox` clamp on the strength of
"nothing reddens" ships a real bug the corpus happened not to reach — a
negative content-box size flowing into paint. Missing one of the five
`borderBoxFloor` call sites means an over-constrained box grows everywhere
except through that one path, which is a silent, site-specific regression of
exactly the kind BM-4 exists to close.

---

## SZ-F — a definite `flex-basis` IS floored too, and the engine follows 120 rather than the disagreeing 100

**The choice.** `flexBaseSize`'s size-property branch also applies
`borderBoxFloor`. A definite `flex-basis` (or a `width` feeding an item's
main-axis base size) is floored by its padding + border exactly like every
other declared size.

**Reasoning, and the two-agent disagreement it resolves.** The first
measurement of this claim (by the implementer) found WebKit answering
**100** for `flex: 0 0 100px; min-width: 0` with 120 of horizontal padding +
border — i.e. *not* floored, unlike every other axis BM-4 touches. An
independent reviewer measured the same declaration at **120** on four
spellings, with a `content-box` control at 220 proving the edges were live.
Both measurements were real; a third measurement (the implementer,
re-verifying rather than accepting the relay) found the discriminant: **WebKit's
answer depends on whether the box has an in-flow sibling.**

| spelling (120 of horizontal padding + border) | alone in its row | with an in-flow sibling |
|---|---|---|
| `flex: 0 0 100px; min-width: 0` | 100 | **120** |
| `flex-basis: 100px; grow:0; shrink:0; min-width:0` | 100 | **120** |
| `flex-basis: 100px; grow:0; shrink:0` | 100 | **120** |
| `width: 100px; flex: 0 0 auto; min-width: 0` | 120 | **120** |
| same, `box-sizing: content-box` (control) | 220 | **220** |

**The engine follows 120, and the discriminator is why the 100 answers do not
count.** They are geometrically impossible — a 100 border box cannot contain
120 of padding and border, padding being inside the border box by definition —
and the trigger that produces them is arbitrary: an absolute sibling or a bare
text node also produces 120, and two padded probes together give 100 *each*.
This is WebKit answering something the spec and geometry both refuse, and it
is a **second instance of the shape divergence 2 already records** — WebKit's
own flex sub-one clause is the first, where the engine also follows the spec
over an inconsistent browser answer. CSS Flexbox §7.2.3 settles it directly:
`box-sizing` applies to `flex-basis`.

**What it costs if wrong.** The engine disagrees with WebKit for a lone padded
flex item with no in-flow sibling — the one configuration whose own browser
answer is self-contradictory across near-identical spellings. Recorded rather
than hidden, on divergence 2's own footing: no fixture or golden encodes the
100-alone answer, and none should, because a future WebKit fix (or a future
engine reader "correcting" this) would otherwise have something to move
against.

---

## SZ-G — the specified size suggestion is the USED preferred size, not the declared one, because floors compose by `max` and BM-4's floor cannot be undone by FS-3's

**The choice.** FS-3's automatic minimum is
`min(specifiedMain, contentMain)`, where `specifiedMain` is read from the
node's **used** size after BM-4's border-box floor has already applied —
`own.width`/`own.height` from `resolveNodeSize`'s output — not from the raw
declared `Style.size`. `specifiedMain` is `nil` (and the automatic minimum is
the content suggestion alone) exactly when the declaration is `auto`.
**Amended by the post-merge review (finding B2): the automatic minimum is then
clamped by a definite max main size, and ruling BM-4's floor is re-applied after
that clamp.** §4.5 says the content size suggestion is 'further clamped by the
maximum main size if that is definite'; the engine did not, so an `auto`-width
`display: flex; max-width: 50px` item around a 200-wide `flex: none` child was
200 against WebKit's 50. Clamping alone is wrong: `width: 100px; max-width: 40px`
with 120 of padding and border is 120 in WebKit and becomes 40. So `collectItems`
returns `max(maxMain, main-axis borderBoxFloor)` where the clamp bites. A measured
leaf takes no floor, because `measureNode` excludes its (inert) padding. Pinned by
`sizing_max_clamps_content_suggestion`,
`sizing_max_below_floor_keeps_automatic_minimum` and three `BoxModelTests` pins.

**Reasoning — worked through in Task 3, before either BM-4 or FS-3 had
landed, because the fixture built to pin BM-4 turned out to exercise both
rules at once and nobody had recorded that they compose.** `.box`, a flex
item, declares `width: 100px` with 120px of padding + border and a 10px
child. Its **width is its main axis**, and this engine's pre-existing
*content* half of the automatic minimum was already floring it at its own
min-content — padding 100 + border 20 + the 10px child = **130** — which
overrides the declared 100 before BM-4's floor is ever reached. So even
before this milestone touched anything, the engine answered 130, not the
100 a reading of BM-4 in isolation would predict.

**The floors compose by `max`, and BM-4 cannot lower a floor.** After BM-4
alone, the box's border-box floor is `max(100, 120) = 120` — but the
pre-existing content-only automatic minimum still floors the item at its own
min-content, **130**, and that floor sits *on top of* BM-4's: `max(130, 120) =
130`. Only once FS-3 replaces the automatic minimum's specified half with the
node's **used** (post-BM-4) size does the arithmetic become
`min(120, 130) = 120`, agreeing with WebKit. Using the raw **declared** 100
instead would give `min(100, 130) = 100`, which is wrong on this exact
fixture — WebKit's answer is 120, not 100.

**What it costs if wrong.** Reading FS-3's specified suggestion as the
declared size rather than the used one reddens this milestone's own BM-4 ×
FS-3 composition fixture (`sizing_over_constrained_grows`) on its width axis,
and the failure looks like a BM-4 regression rather than what it actually is —
an FS-3 misreading of which value "specified" means once another rule has
already resolved it. See `SZ-H` for the measured discovery that this
particular fixture, despite carrying the composition, does *not* in fact
discriminate the declared-vs-used choice — that took a second fixture.

---

## SZ-H — the plan's claim that `sizing_over_constrained_grows` guards the used-vs-declared choice was measured FALSE; the real guard needed a shrinking sibling

**The choice.** `theSpecifiedSizeSuggestionIsTheUsedSizeMatchesWebKit`
(`SizingFixtureTests.swift:167`, fixture
`sizing_specified_suggestion_is_used_value`) is the test that actually pins
`SZ-G`'s used-vs-declared reading. `sizing_over_constrained_grows` does not,
despite carrying the BM-4 × FS-3 composition.

**Reasoning.** The plan's own ruling (recorded during Task 3) predicted that
implementing FS-3 with the **declared** reading instead of the used one "would
re-break `sizing_over_constrained_grows` back to 100." Mutation testing —
implement the declared reading, run the full suite — measured this **false**:
it reddens **nothing** at 750 tests. The reason is exact: an automatic
minimum can only **raise** a floor, never lower one, and `borderBoxFloor` has
already put that item's flex base size at 120 by the time the automatic
minimum is computed. `min(100, 130)` sits *below* 120 and never binds, so
both the declared reading and the used reading give the same 120 on this
particular tree — the fixture cannot see the difference between the two
rules it was meant to discriminate.

**Closing it needed a fixture where the floor actually binds**, which means a
**shrinking sibling** — nothing in `sizing_over_constrained_grows` shrinks.
The new fixture `sizing_specified_suggestion_is_used_value` gives `.a` a
declared 100 with 120 of edges (used 120, per BM-4) holding a 200-wide child
(content suggestion 320), with a sibling `.b` that forces `.a` to shrink.
Generated through the live oracle: **WebKit says `a = 120, b = 30`.** The
declared reading gives `a = 100, b = 50` — a real, measurable difference on
this tree, unlike the first one. The mutation (declared instead of used)
reddens exactly this one test, three issues, at the milestone's then-current
751-test suite — and nothing else.

**Carried, not new here:** CLAUDE.md's claim that implementing FS-3 "must
redden exactly" `aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit` is
itself now false and stale — that count predates `ScrollView` and this
milestone's own two new fixtures. Reverting FS-3 entirely (dropping the `min`
and returning the content suggestion alone) reddens **three** tests at the
751-test suite, and possibly more once Task 7/8 add another. Task 11 owns the
correction in CLAUDE.md.

**What it costs if wrong.** Trusting a plan-stated guard without re-measuring
it banks a coverage gap as a real regression test — exactly the failure this
repo's whole method exists to catch (the discriminator rule: prove the mutant
behaves differently before banking a finding). Here it did not merely fail to
redden a decorative test; it would have shipped the wrong reading of FS-3
(declared instead of used) with the milestone's own regression suite reporting
green.

---

## SZ-I — a fixture's HTML and its Swift tree must describe the SAME tree; `Style.display`'s `.flex` default is the worked example, and it is why one golden legitimately moved

**The choice.** `sizing_over_constrained_grows.html`'s `.box` now declares
`display: flex` explicitly. The fixture's golden was regenerated against this
corrected HTML, and `kid`'s expected width moved from 10 to **0**.

**Reasoning.** `.box` originally declared no `display` at all. In CSS that
makes it a **block** container, and `.kid` — with no `display` of its own
either — is an ordinary block-level box that keeps its declared 10px width
and overflows its 0-wide content box. `Style.display` defaults to `.flex` in
this engine, which has no block layout at all, so the Swift tree the fixture
actually exercises makes `.kid` a **flex item** in a 0-wide content box, with
an automatic minimum of `min(10, 0) = 0` — it shrinks to 0. **The two
languages were describing two different trees**, and no spelling of this
engine's rules can produce the original golden's 10, because the rule that
would produce it (block layout) does not exist here.

Measured through the oracle on the corrected HTML before the golden was
regenerated, per this milestone's standing rule that a golden move must be
explained against WebKit rather than assumed: root 400×300, box 120×140,
**kid 0×10 at (60, 70)** — the browser's own answer to the corrected fixture,
not a regeneration to match the engine's prior output.

**Why this golden move is the legitimate kind, and the distinction is the
whole of the ruling.** This milestone's standing rule is that a pre-existing
golden that moves is a finding to chase, never a regeneration to accept
quietly. This one moved because the **fixture** changed — the HTML now
describes the tree the Swift side always did — and the new golden is what the
browser says about the corrected fixture, checked against the oracle before
being committed. It is the one case in this milestone where a moved golden is
correct rather than a red flag.

**This is the third instance of one family in this milestone** — Task 1's
missing `html, body { height: 100% }` (`SZ-B`) and Task 3's engine-side
misprediction (`SZ-G`'s ancestor) are the other two. All three are an
artifact written from reasoning about one side (the engine, or CSS in the
abstract) and never checked against the other before being trusted.

**What it costs if wrong.** Leaving the fixture's HTML block-level while the
Swift tree is flex pins a golden this engine cannot reach for any correct
implementation — a permanently red or permanently silently-wrong test that
teaches nothing to whoever finds it, and cannot be fixed without either
regenerating against the wrong tree (accepting the engine's answer as correct)
or discovering, as this milestone did, that the fixture itself was the
mismatch.

---

## SZ-J — the border-box floor has three compositions it does not reach, and ALL THREE are left open by this milestone

**The choice.** `borderBoxFloor`'s own doc comment in `FlexEngine.swift`
records three compositions the floor does not reach, all measured against
WebKit. **None of the three is fixed by this milestone. All three are recorded
and left open.**

**This heading and this paragraph said the opposite until the fix wave, and
the correction is worth reading before the list.** They said "only the third is
this milestone's to fix" and "only the third is fixed by this milestone (as
part of Task 8)". That was written by Task 10 while Task 8 was still running
in a parallel worktree — a *prediction* recorded as a fact, with nothing
between the prediction and the reader. Task 8 changed *when* `ownCross`'s
measurement is taken (ruling `SZ-M`); it did not touch the `clamp` that
composition 3 is about, and `borderBoxFloor`'s own doc comment has said so
explicitly the whole time ("**Still nobody's task.**"), which is the source
this document exists to summarise and disagreed with.

Re-measured in the fix wave through the live oracle, on composition 3's own
declaration (`width: 100px; height: auto; max-height: 40px; padding: 60px 0;
border-width: 10px 0`, `border-style: solid`, inside a 400x300
`align-items: flex-start` row):

| | engine | WebKit |
|---|---|---|
| `.box` | 100x**40** | 100x**140** |

Unfixed, to the pixel, at this milestone's last commit.

1. `width: 100px; min-width: 0; max-width: 40px` with 120 of padding+border is
   **120** in WebKit and **40** here — the size property is floored correctly,
   but `collectItems`' `hypothetical` clamp then re-shrinks it back down to
   the `max-*`. This needs the floor applied to the item's **used** main size,
   after the clamp that currently undoes it — not the same site `SZ-D`
   already fixed.
2. Two `width: 500px; min-width: 0` items with 120 of padding+border each,
   shrinking into a 200-wide row, are **120** each in WebKit (overflowing the
   container) and **100** each here — §9.7's freeze loop shrinks an item below
   its own floor. Same site as 1.
3. An `auto` cross size clamped by a `max-*` below the floor —
   `height: auto; max-height: 40px; padding: 60px 0; border-width: 10px 0` is
   **140** in WebKit and **40** here. This is `collectItems`' `ownCross`,
   whose measured branch ends in a `clamp` the floor never sees. **It shares a
   FUNCTION with TX-H and not a line.** Task 8 (`SZ-M`) moved *when*
   `ownCross`'s fit-content measurement is taken — from the item's
   hypothetical main size to its used one — and the fix wave (`SZ-O`) moved
   when the result is consumed. Neither goes near the `clamp` that discards
   the floor, and neither could: this composition's failure is visible with no
   flexing at all, on a lone item whose main size never moves. **Still open.**

**Reasoning for leaving all three open.** 1 and 2 are `collectItems`'
main-axis freeze loop (`hypothetical`/§9.7), a different site from `ownCross`
and from every site `SZ-E` already touched; 3 is a `clamp` inside `ownCross`
that no task in this plan was scoped to. None of the three has a fixture, a
task, or a ruling anywhere in this milestone's plan. Fixing any of them now
would be doing undispatched work behind no review at all — the exact thing
task-scoping exists to prevent. They are recorded here, rather than left to be
rediscovered as a surprise, because `borderBoxFloor`'s own doc comment already
states them as a checked, exhaustive-as-of-Task-4 list; a decisions doc that
did not carry them forward would be quietly worse than the source comment it
is meant to summarize.

**What it costs if wrong (i.e., if left unfixed indefinitely).** A box whose
size is clamped by an explicit `max-*` below its own padding and border does
not grow to fit them, in three shapes — a definite main-axis
`max-width`/`max-height` smaller than the edges (1), an item shrunk below its
floor by the freeze loop (2), and an `auto` CROSS size clamped by a `max-*`
below the floor (3). All three are BM-4's own failure mode, reappearing at
sites BM-4's four fixed call sites do not cover. No fixture or golden encodes
any of them, on the same footing as divergence 2 and `SZ-F` — a future fix
should move nothing in the corpus, and a future reader should not "correct"
any of the three toward the engine's current answer.

---

## SZ-K — `.minHeight(Pixels(0))` in the demo is permanent, not an FS-3 workaround, because `flexBasis` is not a specified size suggestion

**The choice.** `Sources/MetalUIDemo/main.swift` keeps
`.minHeight(Pixels(0))` on the box wrapping the scroll list. Task 9 did not
remove it, despite the plan (and CLAUDE.md, and this milestone's own spec §5)
predicting it would become unnecessary the moment FS-3 landed.

**Reasoning.** Measured directly: removing the modifier after FS-3 landed
takes the scroll viewport from **89/89/73pt** (at windows 1200/920/700, with
the modifier present) to **14000pt** at every width — the whole 500 × 28
`List`, unbounded. The box in question declares no `.height(_:)` at all, only
`.flexGrow(1)` and `.flexBasis(Pixels(0))`. FS-3's specified-size half reads
`Style.size` — an explicit `.width(_:)`/`.height(_:)` — and is `nil` whenever
that dimension is `.auto`, which it is here: **`flexBasis` is a different
`Style` property that FS-3's code path never reads.** So `specifiedMain ==
nil`, FS-3's `min(specifiedMain, content)` falls straight through to
`content` alone, and the floor is exactly what the pre-FS-3, content-only
implementation already gave — 14000, unbounded. FS-3 fixes the case where an
item declares an explicit, smaller size; this box declares none, so it was
never in FS-3's scope, and **no future change to FS-3 itself can bring this
composition into scope** without FS-3 also reading `flexBasis`, which is a
different, unimplemented rule.

**What it costs if wrong.** Removing the modifier on the strength of the
plan's unmeasured prediction ships a demo whose scroller is 14000pt tall —
i.e., no scrolling at all — under the description of a cleanup. This was
caught only because Task 9's brief required measuring the viewport height
before and after, rather than trusting the prediction and deleting the
modifier and its explaining comment together.

---

## SZ-L — CLAUDE.md's attribution of the demo's sidebar squeeze to FS-3 is wrong, and the real cause is now MEASURED: ordinary flex shrinking, which WebKit does identically

**The choice.** CLAUDE.md's divergence 6 paragraph, which attributes the
demo sidebar rendering at 97/73/70pt against its declared 196pt to ruling
FS-3, is corrected rather than left standing (Task 11's to land in the file
itself; this ruling is the record of why).

**Reasoning.** Re-measured post-FS-3 at the same three window widths
(1200/920/700): **97 / 73 / 70** — identical to the pre-FS-3 numbers CLAUDE.md
already recorded, to the pixel. The attribution cannot be right regardless of
that identity, because the arithmetic makes it impossible in principle: the
sidebar declares `.width(Pixels(196))`, so its specified-size suggestion is
196; its content-size suggestion (the min-content width of its label and
boxes) is well under 196; **`min(196, content) == content` whichever half of
§4.5's automatic minimum is implemented**, content-only (the old behaviour)
or `min(specified, content)` (FS-3's fix). Since the specified suggestion
never binds either way, FS-3 mathematically cannot move this number, before
or after. The main pane, the sidebar's sibling in the same `Row`, has no
declared width at all (only `.flexGrow(1)`), so its own floor is equally
unaffected — the whole row's shrink distribution is provably unchanged by
FS-3, confirmed by reading `FlexEngine`'s `specifiedMain` directly rather
than only by the black-box measurement.

**The real cause was recorded here as a hypothesis, explicitly unverified.
THE FIX WAVE MEASURED IT AND IT IS CONFIRMED: it is ordinary flex arithmetic,
a browser does the identical thing, and it is not a divergence and never
was.** The hypothesis was that the sidebar is a flex item with an unset
`flexShrink`, so it shrinks to its content floor regardless of §4.5.

Measured on the demo's body-row shape through both engines in one pass — a
1168-wide row, `gap: 16`, holding a `flex-direction: column;
align-items: stretch; width: 196px; padding: 14px; gap: 12px` sidebar (a
41-wide label stand-in above four 26-tall rows) and a `flex-grow: 1` main pane
whose content demands more width than the row can give:

| sidebar's `flex-shrink` | engine | WebKit |
|---|---|---|
| `1` — the unset default, what the demo has | **69** | **69** |
| `0` | **196** | **196** |

**Exact agreement in both arms**, and 69 is precisely the content floor:
`41 + 14 + 14`. The remedy is `.flexShrink(0)` or a `minWidth` on the sidebar
column. **This is a demo declaration that does not say what its author meant,
not an engine defect.**

**Read the measurement at its strength, which is about the MECHANISM and not
about the demo's three numbers.** The probe is a stand-in for the body row —
a rigid 41-wide box where the demo has a real `Text`, and a rigid wide filler
where the demo has its actual main pane — so it establishes that the shrink is
ordinary flex arithmetic that WebKit performs identically, and it does **not**
re-derive 97 / 73 / 70 on the real tree. Those three numbers depend on the
main pane's own width-dependent content demand and were not re-measured here.
The claim being promoted is "not a divergence", not "the demo measures 69".

So CLAUDE.md's original divergence-6 paragraph was wrong twice over, as this
ruling anticipated: wrong about the cause (FS-3, which provably cannot move
the number), and wrong that there was an engine divergence to describe.

**What it costs if wrong.** Leaving the FS-3 attribution standing sends
whoever next touches FS-3 (or the sidebar) chasing a rule that provably cannot
move this number, and closes off the question — what actually constrains the
sidebar — because the paragraph reads as already explained. And now that the
answer is measured, the cost points the other way too: leaving it filed as an
**open question** sends a human hunting an explained thing, which is why the
demo's comment and CLAUDE.md's human-verification record were both re-framed
in the same pass rather than only this ruling.

**The demo's declaration is deliberately NOT changed.** The sidebar's width
feeds the whole layout, this is the last commit before review, and the brief
for this fix wave required that any such change be shown to move nothing
else. Documenting the remedy costs nothing; applying it un-reviewed on the
last commit does.

**One methodological note worth carrying, because it nearly produced a wrong
answer here.** The first version of this probe gave the main pane no content,
so nothing forced the sidebar to shrink and **both engines answered 196 in
both arms** — a clean, symmetric, entirely uninformative agreement that would
have read as "confirmed" to anyone not checking that the `flex-shrink: 0` arm
differed. It is practices-doc shape 15 again, one milestone after `SZ-N`
found it: a measurement of a configuration in which the mechanism under test
cannot fire. The discriminator is the same one — require the two arms to
*disagree* before believing either.

---

## SZ-M — `ownCross` (now `itemFitContentCrossSize`) is RE-RUN only for the item the freeze loop actually moved, not moved wholesale after `resolveFlexibleLengths`

**The choice.** Task 8 extracted `collectItems`' `ownCross` closure into a
standalone `itemFitContentCrossSize(...)`, parameterized on `mainSize` rather
than closing over `hypothetical`. `collectItems` still calls it once, with
the item's *hypothetical* main size, exactly as before — a line's own
pre-flex cross extent has to be measured from something before §9.7 can even
run. `layOutChildren`'s per-line loop then calls it a **second** time, after
`resolveFlexibleLengths` has run, but only for items where
`!item.stretchEligible && item.targetMainSize != item.hypotheticalMainSize` —
re-deriving whether the item's cross size is even `auto` from
`tree.style(item.node)`, since a definite cross size was never measured by
`collectItems` in the first place and must not be measured here either.

**Reasoning.** This is choice (2) of the two the spec (§2.4) required be
decided explicitly and recorded: **re-run**, not **move**. The alternative —
recomputing every auto-cross item's fit-content cross size unconditionally
after `resolveFlexibleLengths`, for every item on every line — is strictly
more work for the same answer. Most items freeze at their hypothetical main
size (`ResolveFlexibleLengths.swift`'s freeze loop is a no-op the moment
nothing violates a min/max), and for those the first measurement, from
`collectItems`, already **is** the answer CSS wants: a frozen item's
hypothetical and used main sizes are numerically equal, and the fit-content
formula is a pure function of that one number. Only an item whose target
actually *moved* needs re-measuring. The "did this item move" comparison the
spec flagged as needing new machinery turned out to need none: `FlexItem`
already stores both `hypotheticalMainSize` and `targetMainSize` as separate
fields, so the comparison is free.

A stretch-eligible item is excluded from the recompute guard entirely, for a
different reason than "it didn't move": its cross size was just set, two
blocks up in `layOutChildren`, to the line's own extent minus its cross
margins — that is what "stretch" means, and it does not depend on the item's
main size or its content at all. Recomputing it from content would be wrong,
not merely wasteful.

**What it costs if wrong.** Confirmed by two mutations, both reverted after
verification. Disabling the recompute loop entirely reddens exactly
**2 tests** — `anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit`
and `crossSizeAfterFlexingMatchesWebKit` — confirming the fix's blast radius
is exactly the one item class its fixture was built to isolate. Dropping the
`!item.stretchEligible` guard alone (recomputing every non-frozen auto-cross
item regardless of whether it was just stretched) reddens **16 distinct
tests / 36 issues** across `FreezeLoopTests.swift`,
`ContentSizingFixtureTests.swift`, `ElementLayoutTests.swift` and
`FlexEngineTests.swift` — the ordinary "an item takes its cross size from the
LINE it was stretched to, not from its content" fact the whole
stretch/default-`align-items` corpus depends on. Choosing "move" over
"re-run" would not have failed either mutation, but would cost real work on
every layout for items that were always going to answer the same number.

---

## SZ-N — a benchmark of TX-H's cost is only meaningful under a NON-default `alignItems`, because CSS's `stretch` default makes the new code path unreachable

**The choice.** Task 8's committed cost measurement
(CLAUDE.md's layout-cost section) uses `alignItems: .flexStart` on every
interior node of the two branching trees CLAUDE.md's own cost table already
uses, not the trees' default style.

**Reasoning.** The first attempt measured the trees with no `alignItems` set
at all. `Style.alignItems == nil` resolves to CSS's initial `stretch`
(`resolvedAlignment`, `Alignment.swift:119`), and a stretch-eligible item is
excluded outright by the new recompute guard (`SZ-M`) — its cross size comes
from the line, never from content, so TX-H's whole recompute path never fires
for it. Under the default-stretch tree the "cost" measured was just the price
of one skipped `Bool`/`Double` comparison per item, and the numbers showed it:
noise-level deltas in both directions (debug 8,191-node tree **-2.1%**,
88,573-node **+1.2%**; release 8,191-node **+9.6%** — noisy at that small an
absolute time — 88,573-node **+1.2%**). Re-measured with `alignItems:
.flexStart` on every interior node, so every auto-cross item is a recompute
candidate whenever its main size actually moves (pervasive in this tree
shape, which shrinks heavily at nearly every level under an 800x600 offer),
the 88,573-node tree — the larger, more stable sample — shows a consistent
**+2.4% (debug) / +3.2% (release)** cost, a worse case than most real trees
will hit since most flex layouts are not universally `flexStart` with
universal shrinking. Full figures are in CLAUDE.md's layout-cost section.

**This is the measure-performance milestone's "measure on a BRANCHING tree,
never a chain" lesson arriving one level up, in a new costume.** That
lesson was about tree *shape* hiding a cost by collapsing cache keys; this
one is about container *style* hiding a cost by never entering the branch
under test at all. Both produce a confident number about nothing, and both
were caught the same way — by noticing the number was suspiciously flat and
re-deriving what configuration the code path actually requires, rather than
trusting the first measurement because it ran without error.

**What it costs if wrong.** Reporting the first attempt's numbers as TX-H's
cost — as the task's own draft nearly did — would have banked a "TX-H is
essentially free" finding that is true of exactly one container style and
silently false of every other. A later reader sizing a tree with
`align-items: flex-start` (or any non-`stretch` value; `Row`/`Column`'s own
default is `center`, per ruling EP-8, which is also stretch-ineligible for a
declared cross size) would hit the un-measured +2.4%/+3.2% cost with no
warning it existed. Carried into
`docs/practices/verifying-tests-can-fail.md` as its own mechanism — see
that document's newest numbered section.

---

## SZ-O — TX-H's re-measure has to run BEFORE the line and container cross extents, not after; §9.7 moves above them, and nothing else moves

**The choice.** `layOutChildren`'s per-line loop is split in two. The flex step
(§9.7) and TX-H's fit-content re-measure (§9.4 step 7) run first, in their own
loop over the lines; then each line's cross size (§9.4.8) and the container's
`contentCross` are computed from the item cross sizes that loop has just
finalised; then `align-content`; then a second per-line loop does §9.4's item
stretch and records where each line starts. That is CSS Flexbox's own step
order — 6, 7, 8, 9, 11 — where the engine previously ran 8, 9, 11, 6, 7.

**Reasoning: TX-H shipped a regression, and it is worse than the divergence it
closed.** Task 8 wrote the re-measure into the per-line loop *after* the line
extents had already been fixed, so it corrected `item.crossSize` and left every
consumer of that number holding the pre-flex one. Measured against live WebKit,
both probes reproduced from the fix wave's own harness:

| probe | before `SZ-O` | after | WebKit |
|---|---|---|---|
| A — `#outer { display: flex; width: 120px; align-items: flex-start }` (auto height) wrapping a `flex-wrap: wrap` child of four 50x20 | `outer` 120x**20**, `.a` 120x40 | `outer` 120x**40** | `outer` 120x**40** |
| B — a wrapping row 120 wide: `.a` declared 200 (shrinks to 120, becomes 40 tall), then `.b` 120x30 on the second line | `.b` at y=**20** | `.b` at y=**40** | `.b` at y=**40** |

Probe A puts a 40-tall child inside a 20-tall parent. **Probe B overlaps `.a`
and `.b` by 20pt — a visible rendering defect, not a wrong number.**

**Both were NEW, and that is what makes this a regression rather than a
surviving divergence.** With the re-measure disabled (`guard false, …`) the engine gives
`.a` = 20, `outer` = 20 and `.b` at y = 20: internally consistent and uniformly
wrong. TX-H made the item right and left everything above it stale, so the tree
became incoherent where it had merely been divergent.

**The spec anticipated this and the evidence was misread.** Spec §5 says
"Recomputing cross sizes after the freeze loop changes each line's cross extent,
which `align-content` consumes. The `flex_wrap_*` fixtures are the ones most
likely to move." Task 8's report treated "no `flex_wrap_*` golden moved" as the
risk not materialising. **The actual reason none moved is that the line extent
was never recomputed at all** — the risk was unaddressed, and its absence was
read as its resolution. Same shape as `SZ-N`: a green result from a
configuration in which the thing being checked cannot happen.

**Why the reorder is safe, stated as a checkable fact rather than as
confidence.** `layOutChildren`'s header comment warns that its phase orderings
are "circular or wrong if reversed", and that warning still stands — but every
ordering it names is a *cross-axis* one (break before line measurement,
`align-content` growth before item stretch), and none of them moved. §9.7 was
never in that chain: it reads `containerMain`, each item's base and hypothetical
main sizes and their main-axis min/max, and **no cross-axis field appears in
`ResolveFlexibleLengths.swift` at all** — verified with
`grep -n "crossSize\|marginCross\|minCross\|maxCross\|stretchEligible"
Sources/MetalUILayout/ResolveFlexibleLengths.swift`, which returns nothing.
Symmetrically, `itemFitContentCrossSize` takes the *container's* cross extent
and never the line's, so step 7 does not depend on step 8 either. The one thing
the split forces is that item stretch now runs after the flex step rather than
before it, which is CSS's order and is required anyway: stretch reads the line's
cross size, which now depends on §9.7.

**The evidence that nothing else moved.** The whole suite passed unchanged
(752 pre-existing tests, 0 issues), and **all 87 goldens were regenerated
against live WebKit and produced a zero `git diff`** — so every committed
golden, `flex_wrap_*` included, is exactly what the browser says with the
reorder in place. No golden moved and none needed to.

**Pinned by two tests, and they discriminate rather than merely covering.**
`crossSizeAfterFlexPropagatesToAnAutoContainer` reads the *container's* height
where the existing TX-H pin reads the item's;
`crossSizeAfterFlexPropagatesToTheLine` reads the second line's `y`. Three
mutations, all on the ordering itself:

| mutation | reddens |
|---|---|
| both the line-size loop and `contentCross` moved back above the flex loop (a full revert) | both pins, 2 issues, nothing else |
| `contentCross` alone moved above the flex loop | **only** `crossSizeAfterFlexPropagatesToAnAutoContainer`, 1 issue |
| the line-size loop alone moved above the flex loop | **only** `crossSizeAfterFlexPropagatesToTheLine`, 1 issue |

The second and third are the discriminating pair: each pin covers exactly one
half, so neither is redundant with the other or with the item-level TX-H pin.
And no pre-existing test reddens under any of the three, which is the direct
measurement of the fix wave's premise that nothing in the 752 could see either
half.

**What it costs if wrong.** The reorder is the load-bearing change of this fix
wave and it moves a phase boundary in the function every flex item in the tree
passes through. If some ordering *not* named above turns out to matter, the
symptom is a wrong cross size somewhere in a wrapped or auto-cross container —
and the corpus is the instrument: 87 goldens covering wrapping, `align-content`,
`wrap-reverse`, margins and nested percentage padding all still agree with a
live browser, which is a stronger statement than "the suite is green". The
alternative considered and rejected was recording the overlap as a numbered
divergence with a deliberately-wrong pin, on divergences 14 and 15's footing;
that was the fix wave's explicit fallback and it was not needed, because the
move turned out to be an ordering change and nothing more.

---

## Running task tally, for a reader orienting against the ledger

Baseline (start of milestone, from `.superpowers/sdd/2026-08-30-sizing/progress.md`'s
own first line): **741 tests, 81 goldens, 29 typecheck guards, warning-free.**

| task | suite after | goldens after | notes |
|---|---|---|---|
| 1 (root % fixture, RED) | 742 tests, 2 issues | 82 | intentionally red; `SZ-B` |
| 2 (root % fix) | 742 passing | 82 | `SZ-A`, `SZ-C` |
| 3 (BM-4 fixture, RED) | 743 tests, 2 issues | 83 | found the BM-4 × FS-3 composition (`SZ-G`'s ancestor) |
| 4 (BM-4 fix) | 749 tests, 1 issue (ruled residual) | 83 | `SZ-D`, `SZ-E`, `SZ-F`, `SZ-J` |
| 5 (FS-3 fixture, RED) | 750 tests, 5 issues | 84 | both predictions held |
| 6 (FS-3 fix) | 751 tests, 0 issues | 85 | `SZ-G`, `SZ-H`, `SZ-I` |
| 9 (demo fallout, parallel with Task 6's review) | 751 passing | 85 | `SZ-K`, `SZ-L` |
| 7 (TX-H fixture, RED) | 752 tests, 1 issue (ruled) | 86 | landed as this doc was being written; see `SZ-B`'s fourth instance |
| 8 (TX-H fix) | 752 tests, 0 issues | 86 | `SZ-M`, `SZ-N`; all four sizing divergences closed |
| whole-branch fix wave | 755 tests, 0 issues | 87 | `SZ-O`; +2 pins for the propagation regression, +1 fixture closing FS-3's uncovered percentage branch |

Both rows above were filled in after the fact rather than re-derived from a
fresh run; re-derive rather than trust either one — that is this document's
own standing rule, restated by `SZ-B` above, not suspended for its own table.

**The fix wave's row is the exception and was taken from its own run**, not
reconstructed: `swift test --no-parallel`, unfiltered, reading the summary
line rather than the exit status. It also re-measured five claims made
elsewhere in this document and in the source, and **two of them were wrong** —
`SZ-J`'s "only the third is fixed by this milestone" (none of the three is)
and `SZ-A`'s citation of `SZ-B` where it meant `SZ-C`. Both are corrected in
place above, with the correction stated rather than smoothed over.
