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

**This document is written while the milestone is still in flight.** Tasks 1
through 7 and 9 are landed as of this writing; Task 8 (the TX-H fix itself,
`ownCross`) has not started. `SZ-A` through `SZ-L` below are settled. `SZ-M`
and `SZ-N` are placeholders for Task 8's own rulings — do not fill them in
without measuring; that is the whole point of leaving them as placeholders
rather than guessing ahead of the work.

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
4 both **survive this milestone by decision**, not by oversight; see `SZ-B`'s
companion note for the other place this milestone touched the same function
and stopped short.

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

## SZ-J — the border-box floor has two further compositions it does not reach beyond the one Task 8 owns, and only the third is this milestone's to fix

**The choice.** `borderBoxFloor`'s own doc comment in `FlexEngine.swift`
records three compositions the floor does not reach, all measured against
WebKit. Only the third is fixed by this milestone (as part of Task 8); the
first two are recorded and left open.

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
   whose measured branch ends in a `clamp` the floor never sees. **This is
   TX-H's own site and this milestone's Task 8**; see `SZ-M`/`SZ-N` below.

**Reasoning for leaving 1 and 2 open.** Both are `collectItems`' main-axis
freeze loop (`hypothetical`/§9.7), a different site from `ownCross` and from
every site `SZ-E` already touched, and neither has a fixture, a task, or a
ruling anywhere in this milestone's plan. Fixing either now would be doing
undispatched work behind no review at all — the exact thing task-scoping
exists to prevent. They are recorded here, rather than left to be
rediscovered as a surprise, because `borderBoxFloor`'s own doc comment already
states them as a checked, exhaustive-as-of-Task-4 list; a decisions doc that
did not carry them forward would be quietly worse than the source comment it
is meant to summarize.

**What it costs if wrong (i.e., if left unfixed indefinitely).** An item whose
main-axis size is clamped by an explicit `max-*` below its own padding and
border does not grow to fit them, in two more shapes than composition 3
alone — a definite `max-width`/`max-height` smaller than the edges (1), and
an item shrunk below its floor by the freeze loop (2). Both are BM-4's own
failure mode, reappearing at a site BM-4's four fixed call sites do not cover.
No fixture or golden encodes either, on the same footing as divergence 2 and
`SZ-F` — a future fix should move nothing in the corpus, and a future reader
should not "correct" either compositions toward the engine's current answer.

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

## SZ-L — CLAUDE.md's attribution of the demo's sidebar squeeze to FS-3 is wrong, and the real cause is recorded as an unverified hypothesis rather than fact

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

**The real cause is unfound, and is recorded as a hypothesis, explicitly
unverified.** A candidate: the sidebar is a flex item with an unset
`flexShrink`, so it shrinks to its content floor by ordinary flex arithmetic
regardless of §4.5 — and a real browser would do the same in that case,
meaning this may not be a divergence from WebKit at all, only from the
demo author's expectation. **This was not measured and must not be recorded
as fact.** If it is confirmed later, divergence 6's paragraph in CLAUDE.md
is wrong twice over — wrong about the cause, and possibly not describing an
engine divergence at all.

**What it costs if wrong.** Leaving the FS-3 attribution standing sends
whoever next touches FS-3 (or the sidebar) chasing a rule that provably cannot
move this number, and closes off the real, still-open question — what
actually constrains the sidebar to ~97/73/70pt — because the paragraph reads
as already explained. Recording the hypothesis as fact rather than as
unverified would compound the error: a reader acting on "it's the unset
`flexShrink`" without having measured it could ship a fix for the wrong
mechanism and declare the divergence closed when it is not.

---

## SZ-M — [pending Task 8] the `ownCross` computation: move after `resolveFlexibleLengths`, or re-run only for items the freeze loop changed

Placeholder. The spec (§2.4) requires Task 8 to choose explicitly between
**moving** `ownCross`'s computation to after `resolveFlexibleLengths` (every
item's cross size recomputed from its `targetMainSize`) and **re-running** it
there only for items whose `targetMainSize` differs from their
`hypotheticalMainSize` (cheaper, but needs a "did this item move" comparison
the freeze loop does not expose today) — and to record the choice and its
reasoning as a `SZ-` ruling. Not yet made as of this document; do not infer an
answer from the surrounding rulings. The controller fills this in when Task 8
lands.

## SZ-N — [pending Task 8] whatever Task 8's own execution turns up

Placeholder, in the same spirit as `SZ-M`. Task 8 measures TX-H's cost on a
branching tree (per-node µs before/after, debug and release — CLAUDE.md's
layout-cost table is the one to update if the figures move) and mutates the
fix to confirm both the new fixture and the inverted pin
(`anItemsCrossSizeIsMeasuredBeforeFlexingUnlikeWebKit`,
`FlexEngineTests.swift:1146`) redden. Every milestone so far in this
repository has produced at least one finding during its implementation task
that no brief anticipated (see `SZ-G` through `SZ-I` for this milestone's
own). Whatever Task 8 finds belongs here, lettered, with its reasoning and its
cost if wrong — not folded into a `SZ-M` that was reserved for the ordering
choice alone.

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
| 8 (TX-H fix) | not started | pending | `SZ-M`, `SZ-N` |

Re-derive rather than trust this table once Tasks 7 and 8 land — it is a
snapshot taken mid-milestone, and this document's own header says so.
