# Sizing — Design

**Status:** approved in brainstorming 2026-08-30. Follows the divergence-8 fix
(merged as `a98bd8a`). Closes the four sizing deferrals CLAUDE.md has been
naming "a sizing milestone" since the box-model branch.

**Baseline at the time of writing** (`master` at `a98bd8a`): **741 tests**, **81
goldens**, **29** `swiftc -typecheck` guards, warning-free including
`MetalUIDemo`. Every number in this document was measured on 2026-08-30 unless
it is attributed to CLAUDE.md; re-measure rather than quoting these.

Four fixes, one subsystem. Each is a CSS clause this engine knowingly does not
implement, each was deferred for the same stated reason — it moves a node's
**stored** size, which every ancestor consumes and 81 goldens sit downstream of
— and each is already measured against WebKit and pinned by a test asserting
the wrong answer on purpose.

---

## 1. Why now, and what makes this one milestone rather than four commits

**The four have the same reach and the same blocker.** Every one of them
changes `resolveNodeSize` / `flexBaseSize` / `collectItems` — the sizing path —
and the reason each was deferred is written identically in four places: it
moves a stored size. Doing them one per branch means paying that risk four
times and re-verifying the corpus four times.

**They also compose, and the composition is where this repo finds its bugs.**
FS-3 is why an item ends up narrower than it asked for; TX-H is why its height
does not follow. `Row { Text(…) }` shows both at once. Fixing one alone leaves
a half-corrected sizing path whose remaining half is harder to reason about
than the whole was.

**What is already built and must not be re-derived.** All four are measured
against the live oracle and recorded with WebKit's numbers; three carry a test
asserting today's wrong answer deliberately, with the browser's answer named in
its comment. The oracle harness, the fixture generator and
`committedGoldensMatchTheBrowser` all exist. This milestone adds fixtures and
changes four rules; it builds no infrastructure.

**One entry is already stale and this milestone corrects it regardless.**
Divergence 6 carries a paragraph describing "a second spill with the same
symptom and an UNIDENTIFIED site". Measured 2026-08-30: it is **gone**, and it
was divergence 8 all along — `"Library"` has a max-content of **42.2436**, the
enclosing column is floored to 70.24 and rounds to 70, the text's box rounds
**down** to 42, and paint character-broke at 42 (ruling TX-F:
`CTTypesetterSuggestLineBreak` breaks inside a word it cannot fit). The
divergence-8 fix closed it. Re-measured: 7 glyphs on one baseline, ink 13.5pt
tall.

---

## 2. The four fixes

### 2.1 A percentage `width`/`height` on the root

**CSS:** a percentage resolves against the containing block. **Today:** the
root's percentages resolve against `nil` and fall back to the offered extent.

| | WebKit | this engine |
|---|---|---|
| `#root { width: 50%; height: 25% }` in 800×600 | **400 × 150** | 800 × 600 |

**Site:** `withoutMeasuring` inside `resolveRootSize` (`FlexEngine.swift`),
which today calls `declared(dim)` with a `nil` percentage basis.

**Measured during brainstorming, and it is the whole change:** giving
`declared` the axis's offered extent as its basis produces **400 × 150**
exactly, and reddens **nothing** in 741 tests. That second half is the finding,
not the first — the suite is blind to root percentages, so this fix cannot be
validated by anything that exists.

**`auto` is untouched, and that is load-bearing.** CLAUDE.md records that
implementing CSS's answer for the root was tried and reverted because it
reddened six element-pipeline and frame-loop tests. That attempt changed the
**`auto`** branch. This one does not reach it: `declared` returns `nil` for
`auto` whatever basis it is given, so the `auto` path is byte-identical and
ruling CS-I survives.

**Divergence 4 (CS-I) therefore stays open by decision, not by oversight.** An
`auto` root axis still takes the space it was offered where CSS shrink-wraps
the block one. Only the percentage case changes. A reader who sees "root sizing
fixed" and assumes both is wrong, which is why this is stated twice.

**It has no pin at all** — unlike the other three, this divergence lives only in
the inert table. This milestone gives it one.

### 2.2 BM-4 — an over-constrained box does not grow to fit its padding and border

**CSS:** `box-sizing: border-box` defines the used size as
`max(specified, padding + border)`; when they exceed the specified size the
**border box grows**. **Today:** `contentBox` clamps the *content* box to zero
with `max(0, …)` and leaves the border box at whatever was specified.

Reproduce with `width: 100px; height: 80px; padding: 60px 50px;
border-style: solid; border-width: 10px` and one auto-sized child.
**`border-style` is not optional** — without it `border-width` is inert and the
same snippet measures 100×120, which is how CLAUDE.md's paragraph was wrong
when first written.

| | WebKit | this engine |
|---|---|---|
| the root | **120 × 140** | 100 × 80 |

**Site:** `resolveNodeSize` / `flexBaseSize`, **not** `contentBox` — CLAUDE.md
is explicit that the local `max(0, …)` is the wrong place, because the fix must
change the node's *stored* size, which the freeze loop and every ancestor then
consume.

**Pinned by** `containerDoesNotGrowToFitOverconstrainedPaddingUnlikeWebKit`
(`BoxModelTests.swift:134`).

**It is easier to reach by accident than it sounds**, because percentage
padding resolves against the containing block, which is usually wider than the
box: `padding: 10% 5% 4% 15%` on a 400×100 root inside an 800-wide body is 112
of vertical padding against a 100px height, and WebKit grows the root to 112.
Any new fixture showing a root taller than its declared size is this, not a bug.

### 2.3 FS-3 — an item is floored by its content even when its own `width` says it may be smaller

**CSS Sizing §4.5:** the automatic minimum (what `min-width: auto` resolves to,
the default on every flex item) is
`min(specified size suggestion, content size suggestion)`. **Today:** this
engine implements the **content** half only.

```html
#root { display: flex; width: 150px; height: 60px; }
.a { display: flex; width: 100px; }   /* holds a 200px child */
.b { width: 100px; height: 20px; }
```

| `.a`'s style | WebKit | this engine |
|---|---|---|
| `width: 100px` | `a` **100**, `b` **50** | `a` **200**, `b` **0** (overflows) |
| `width: 130px` | `a` **130**, `b` **20** | `a` **200**, `b` **0** |
| `width: 100px; min-width: 0` | `a` 75, `b` 75 | `a` 75, `b` 75 — agree |

**The middle row is the discriminating one** — WebKit's floor tracks the
specified width and this engine's does not move, because it is the child's 200
in both cases. The third row names the cause: an explicit `min-width: 0`
replaces the automatic minimum and the two engines agree exactly.

**Site:** `collectItems`' automatic minimum.

**Pinned by** `aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit`
(`FlexEngineTests.swift:535`).

### 2.4 TX-H — an item's cross size is measured before §9.7 flexes it

**CSS Flexbox §9.4 step 7:** determine each item's hypothetical cross size "by
performing layout with the **used** main size" — i.e. *after* step 6 has
resolved the flexible lengths. **Today:** `collectItems` computes `ownCross` in
the same pass as the hypothetical main size, so an item about to shrink keeps
the cross size it had at its unshrunk width.

Measured on a 120×600 root holding one `display: flex; flex-wrap: wrap` child
of four 50×20 items:

| container | WebKit | this engine |
|---|---|---|
| `row; align-items: flex-start` | `120 × 40` | **`120 × 20`** |
| `row` (stretch) | `120 × 600` | `120 × 600` — agree |

**The user-visible form, re-measured 2026-08-30:**
`Row { Text("The quick brown fox jumps over the lazy dog") }` in a 120×600
frame gives the text a box **120 × 16** while its glyph ink spans **45.5pt** —
three lines in a one-line box. §4.5's automatic minimum shrinks it to three
lines' worth of width and the height it keeps is the one line it had before
shrinking.

**Do not clamp this in paint.** The box is what is wrong and the glyphs are
where the box says; a clamp moves the defect somewhere nothing can see it. This
is the same rule the divergence-8 fix obeyed from the other side.

**Site:** the `ownCross` computation in `collectItems`. There are two shapes
and **the plan must choose one explicitly and record why**, because they differ
in cost rather than in answer: *move* the computation to after
`resolveFlexibleLengths`, or *re-run* it there only for items the freeze loop
actually changed. The second is strictly less work — most items are frozen at
their hypothetical size and their cross size is already right — but it needs a
"did this item move" test the freeze loop does not expose today. Do not leave
this to the implementer to decide silently.

**Pinned by** `anItemsCrossSizeIsMeasuredBeforeFlexingUnlikeWebKit`
(`FlexEngineTests.swift:1146`), and referenced from `TextMeasureTests.swift:328`.

---

## 3. Order, and why this order

**Root % → BM-4 → FS-3 → TX-H.**

Each later fix's fixtures are generated against an engine the earlier fixes
have already corrected, so **a red fixture never has two candidate causes**.
The order runs from most isolated to most entangled:

1. **Root %** touches one function and cannot affect an item's sizing at all.
2. **BM-4** changes a node's own used size from its own style — no dependence
   on siblings or on flexing.
3. **FS-3** changes an item's *floor*, which the freeze loop consumes.
4. **TX-H** changes what happens *after* the freeze loop, so it is the only one
   whose input is the output of another fix on this list.

FS-3 before TX-H specifically: FS-3 is what shrinks an item below its
max-content, and TX-H is the rule about what its cross size should be *once
shrunk*. Doing TX-H first means measuring cross sizes against main sizes FS-3 is
about to change.

---

## 4. Verification — the part that makes this a milestone

**Every one of these four fixes lands green against today's corpus.** That is
measured for the root percentage (741 green) and expected for the others: the
existing fixtures were built for other rules. So the corpus, unaided, cannot
tell a correct fix from a wrong one.

**Therefore: fixture-first, and RED on arrival.** For each divergence, in
order:

1. Generate fixtures against **live WebKit** for the case the divergence
   describes.
2. **Run them and confirm they are RED.** A fixture that is green before the
   fix cannot see the defect, and is a fixture bug — redesign it, do not
   accept it.
3. Implement.
4. Confirm green, and confirm the deliberately-wrong pin reddened.
5. Confirm **no pre-existing golden moved**, or explain every one that did.

This is the measure-performance milestone's own instrument, restated: a test
that passes before the work is done is measuring nothing.

**Two standing rules for the whole milestone.**

- **A pre-existing golden that moves is a FINDING, not a regeneration.** Unlike
  every recent milestone, these fixes change stored sizes, so a moved golden is
  *possible*. It must be chased to a WebKit comparison and explained before
  anything is regenerated. "Regenerate and move on" is the one forbidden
  response.
- **A fixture must be able to express its defect.** A box with no content, or
  whose min-content equals its max-content, can see neither FS-3 nor TX-H —
  which is exactly why the earlier `ownCross` fix's "no golden moved" is
  recorded as **weak** evidence: all 61 fixtures preceding it were empty divs.
  Each new fixture states, in its own comment, which clause it would fail
  under.

**The three deliberately-wrong pins must each redden, and each is the check
that its fix is real** — they name WebKit's answer in their own comments, so
inverting them is mechanical. **`aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit`
carries a claim that must be re-measured rather than trusted**: CLAUDE.md says
implementing FS-3 "must redden exactly it", and that count was taken before
`ScrollView` existed.

---

## 5. Known interactions, recorded before they are discovered

**FS-3 × `ScrollView` is the sharpest, and CLAUDE.md already wrote the
warning.** Three things follow from the specified-size suggestion landing:

- `Sources/MetalUIDemo/main.swift` sets `.minHeight(Pixels(0))` on the box
  wrapping the scroll list *because* an explicit height is silently overridden
  back up to the content height. That becomes unnecessary — and its explaining
  comment becomes wrong — the moment FS-3 lands.
- `ScrollView.requestLayout`'s `contentStyle.flexShrink = 0` interacts: the
  automatic minimum is what floors the content node at min-content, and
  `flexShrink: 0` is what stops the freeze loop shrinking it from max-content
  down to that floor (ruling CL-C). A specified-size suggestion that *lowers*
  the floor changes what the freeze loop would do, not what it is allowed to do.
- `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport` is the test to watch.

**TX-H × wrapping.** Recomputing cross sizes after the freeze loop changes each
line's cross extent, which `align-content` consumes. The `flex_wrap_*` fixtures
are the ones most likely to move, and §8.3's `wrap-reverse` flip is downstream
of the same numbers.

**TX-H × `stretch`.** The oracle table above shows the two engines already
agreeing under `align-items: stretch` — the divergence is only visible when an
item's cross size comes from its own content. Any fixture for this must
therefore *not* stretch, or it pins nothing.

**BM-4 × percentage padding.** Percentage padding resolves against the
containing block, so an over-constrained box is easy to produce by accident;
`flex_percent_padding_nonsquare`'s first draft did exactly that. New fixtures
must be checked against this before their goldens are trusted.

---

## 6. Scope

**In:** the four fixes of §2; oracle fixtures for each; retiring divergences 3,
5 and 6 and the inert-table root-percentage row; correcting divergence 6's
stale "second spill" paragraph; re-measuring the demo's sidebar.

**Out, deliberately:**

- **Divergence 4 / ruling CS-I.** An `auto` root axis keeps taking the offered
  extent. Only the *percentage* case changes (§2.1).
- **WebKit's flex sub-one clause (divergence 2).** That is a WebKit bug the
  engine deliberately does not follow; nothing here touches it.
- **`margin: auto`.** Still resolves to 0 on both axes. It is a sizing-adjacent
  inert API but it is `justify-content`/`align-content` work, not §4.5 or §9.4.
- **Baseline alignment.** Named in the inert table with three missing
  mechanisms; unrelated to these four clauses.

---

## 7. Testing

**WebKit is the oracle and the corpus is the instrument.** Unlike the input
milestone, this one has an oracle for everything it changes — which is why the
verification section is strict rather than apologetic.

**No text fixture may be added** (ruling TX-B): WebKit shapes with its own font
stack, so a text golden pins the browser's typography rather than this engine's
rule. TX-H's user-visible form is text, but its *fixture* must be boxes.

**Counts, not timings**, for any performance property. Note that TX-H adds a
measure pass per item — `computeLayout` already costs ~40 µs/node in debug and
§4.5's automatic minimum already probes every item — so the milestone must
report the measured cost rather than assume it is free.

---

## 8. Exit criteria

1. `swift package clean`, warning-free build **including `MetalUIDemo`**, full
   `swift test` **summary line** read — never the exit status.
2. All four fixes landed; divergences 3, 5 and 6 deleted and their labels
   retired unused beside 7 and 8; the inert-table root row deleted.
3. **Each fix's fixtures demonstrated RED before that fix**, reported per
   divergence.
4. Each of the three deliberately-wrong pins reddened by its fix, and inverted.
5. **No pre-existing golden moved**, or every one that moved explained against
   WebKit in the milestone's record.
6. The root percentage gains a pin, it having had none.
7. The demo's sidebar re-measured at windows 1200 / 920 / 700 against its
   declared 196pt, and the numbers recorded.
8. **A human runs the demo and reports** whether the sidebar reads at its
   declared width and whether any text still spills its box.

---

## 9. Divergences and risks recorded up front

1. **Divergence 4 (CS-I) survives this milestone** — an `auto` root axis takes
   the offered extent where CSS shrink-wraps. Deliberate (§2.1).
2. **A moved golden is possible for the first time in several milestones**, and
   the response is to explain it, never to regenerate it (§4).
3. **TX-H costs a second cross measurement per item.** The measure path is
   already the dominant cost in `computeLayout`; the milestone reports the
   measured delta rather than assuming it is small.
4. **The demo's `.minHeight(Pixels(0))` and its comment become wrong** when
   FS-3 lands and must be removed in the same change (§5).
