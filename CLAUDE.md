# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written as
idiomatic Swift. macOS and iOS.

## Start here

- **Design spec (binding authority):** `docs/superpowers/specs/2026-08-24-metalui-design.md`
- **Decisions taken during execution:** `docs/superpowers/2026-08-25-m0-decisions.md`,
  `docs/superpowers/2026-08-25-m1a-decisions.md`,
  `docs/superpowers/2026-08-25-flex-sizing-decisions.md`,
  `docs/superpowers/2026-08-25-alignment-decisions.md`,
  `docs/superpowers/2026-08-25-box-model-decisions.md`,
  `docs/superpowers/2026-08-25-wrapping-decisions.md`,
  `docs/superpowers/2026-08-26-element-pipeline-decisions.md`,
  `docs/superpowers/2026-08-26-content-sizing-decisions.md`,
  `docs/superpowers/2026-08-27-structural-identity-decisions.md`,
  `docs/superpowers/2026-08-27-text-m2-decisions.md` — each ruling with
  its reasoning and what it costs if wrong. Read the "Carried..." sections before
  starting new work.

  **Ruling IDs are namespaced by milestone.** `PF-3` and `C-3` belong to m1a;
  `FS-n` to flex sizing, `AL-n` to alignment, `BM-n` to the box model, `WR-n` to
  wrapping, `EP-n` to the element pipeline, `CS-n` to content sizing, `SI-n`
  to structural identity and `TX-n` to text (M2) (the last three are
  **lettered** — `CS-A`…`CS-O`, `SI-A`…`SI-H` and `TX-A`…`TX-J` — so a bare
  `CS-3`, `SI-3` or `TX-3` is a typo rather
  than a citation) (**`EP-2` and `EP-4` were never
  assigned** and must not be reused — a new ruling taking one would silently
  rebind any citation written against the gap). Sweep for stray citations **case-insensitively** — a `Ruling F-3` survived two branches' greps for lowercase `ruling`. A bare `F-1` is ambiguous — m0, m1a and flex sizing each
  had one, and three code comments on the flex-sizing branch cited the wrong
  document before this was fixed. Prefix new milestones' rulings the same way.

- **Identity is structural and universal, and `.id()` is an override rather than
  a source.** Every element has a `GlobalElementID` — a persistent linked list of
  `PathComponent`, each either `.positional(Int)` (the element's index in its
  container's **flat** child list) or `.named(ElementID)`. **A name replaces a
  position; it never joins it**, so a named item keeps its state through a
  reorder. `nil` is gone from the identity a phase receives, so "every element
  has identity" is a compile-time fact rather than a rule to remember. Two
  consequences a reader will otherwise get wrong:

  - **A vanishing `if` makes the trailing sibling ADOPT the vanished element's
    state, not reset it** — measured, and the remedy is the half intuition gets
    backwards: naming the **trailing sibling** carries its state through, while
    naming the **conditional content** removes the inheritance and still leaves
    the reset. Both pinned (`anElementAfterAVanishingIfAdoptsTheVanishedElementsState`,
    `namingTheLaterSiblingIsWhatSurvivesAVanishingIf`).
  - **`cachedHash` and `==` are safe individually and unsafe only together.**
    Dropping the parent from the hash reddens exactly one test; a hash-shortcut
    `==` reddens nothing; do both and two unrelated elements silently share a
    `StateTable` entry. The load-bearing line is **`==`'s chain walk**, which no
    test can guard — a 64-bit collision is not constructible against a
    per-process-seeded `Hasher` — so the mechanism is stated at `==` per
    taxonomy shape 6. Do not "simplify" it on the evidence of a green suite.

  **Tombstones and exit transitions are untouched** by this: §4.3 still records
  that AX identity needs entries surviving the sweep as invalid-reporting
  tombstones and that exit transitions are impossible until that exists.
  Universal identity makes tombstones *more* useful and no easier — it is a
  change to the **sweep**, not to the key.

- **`Column` and `Row` centre on the cross axis; `Box` stretches. Ruling EP-8,
  2026-08-27, and this closes what was open.** SwiftUI's `VStack`/`HStack`
  centre, CSS stretches, and EP-5 takes SwiftUI's answer where the two differ.
  EP-6 held `stretch` on a *mechanism* — an `auto` cross size resolved to 0, so
  a centred child with no cross size would have painted nothing — and named that
  mechanism as "a prerequisite, not an application"; content sizing built the
  prerequisite, and EP-8 is the application. EP-6's other half, **no invented
  default `gap`, still stands**.

  **The change is in `Column.init`/`Row.init`, not in `Style`.** `Style`'s
  `alignItems` default is still `nil`, the engine still reads that as CSS's
  `stretch`, `Box` is untouched, and **no golden moved** — WebKit stays the
  oracle for the flex algorithm and the split is what makes that true. If a
  golden ever moves for a stack-default change, something reached the engine
  that should not have. The split is a checked property, not a convention:
  `aStackCentresOnTheCrossAxisWhereABoxStretches` asserts the `Column` answer
  (70) and the `Box` answer (0) side by side, so moving the default down into
  `Style` reddens its second half while leaving the first green.

  **The cost, and it is real: a childless `Box` measures 0, so a box with no
  cross size now paints nothing** where `stretch` silently filled its container.
  That is a *louder* failure than the one it replaces — a missing rectangle is
  visible, a wrongly-filling one is not — but it has to be paid in writing. The
  remedy is a declared cross size, or `.alignItems(.stretch)` on the container
  where "these fill their parent" is what the code means;
  `Sources/MetalUIDemo/main.swift` pays it in **five** places (root column, body
  row, sidebar, main pane, the row of weights) and says so at each.

  **Two sentences have now expired here in two commits, and the second was
  written by the commit that retired the first.** The original — "a leaf still
  has no production `MeasureFunction`, so a `Column` of text-shaped leaves will
  measure 0 on the cross axis" — expired with M2 Task 4. Its replacement said a
  centred `Text` took its **max-content** width and was laid out 270 wide in a
  120-wide `Column`; that was divergence 6, and **it is fixed** (ruling TX-H): a
  column's cross axis is the inline axis, so an `auto` cross size shrink-wraps
  and the label is 120 wide at `x = 0`, agreeing with WebKit. **`Column { Text }`
  now needs no remedy at all.** What the bullet above still costs is the
  *childless* `Box`, which measures 0 because it has no content to wrap — the
  demo's five `.alignItems(.stretch)` are paying for that and not for text.

- **`Text` measures and draws, and three things about it are load-bearing.**
  M2 landed `MetalUIText` (CoreText, no Metal), a shaping cache and a glyph
  atlas on the `Window`, and a `Text` element that attaches a
  `MeasureFunction` through `newLeaf` — the framework's first production leaf.

  - **Nothing may be keyed on a font family or PostScript name** (spec §6.1 and
    §3.2 — a design decision, not a ruling): requesting `"SFMono-Regular"` by name on the
    machine this was measured on returns a font whose PostScript name is
    `Helvetica`. `FontKey` identifies the *resolved* `CTFont`, variation
    coordinates and matrix included, and the atlas key adds `size`,
    `subpixelVariant` and `scaleFactor`. A key collision is one of three
    failure modes **no assertion in this repo can see** (spec §4.2) — the
    others being a missing subpixel variant and eviction mid-frame — because
    the CPU and the GPU agree on a wrong answer together.
  - **Min-content is the longest WORD, and it does not come from the
    typesetter** (ruling TX-F). `CTTypesetterSuggestLineBreak` breaks *inside*
    a word it cannot fit, so "typeset narrow and take the widest line" answers
    the widest **character** — 11.489 against CSS's 110.348 on the sample in
    `Shaper.unbreakableRuns`. `CFStringTokenizer(kCFStringTokenizerUnitLineBreak)`
    is the width-independent API that gives the right answer, and ruling TX-G
    records that it also removes M6's reason for a hand-rolled UAX #14 subset.
  - **The corpus has no text fixture and must not gain one** (ruling TX-B).
    WebKit shapes with its own font stack, so a text golden would pin the
    browser's typography rather than this engine's rule. A moved golden on a
    text change therefore means something reached the engine's *container*
    path — stop and report, do not regenerate.

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
catalogues **thirteen** shapes of test that cannot fail, all observed in this repo,
plus the method for finding them and the cases where adding a test is the wrong
answer. Count the `###` headings rather than trusting that number.

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

## Verified on real hardware

`swift run MetalUIDemo` was run and inspected on a Retina display: the window
shows the centred rounded rect with its antialiased border, and the close button
quits the process.

**Re-verified on 2026-08-27 after ruling EP-8 made `Column`/`Row` centre on the
cross axis**, because that ruling's failure mode is an *invisible rectangle* and
no test in this repo can see one: a human ran the demo and reported it looks
right — nothing vanished, the sidebar rows and the separator still fill their
containers through their new explicit `.alignItems(.stretch)`, and resize and the
light/dark toggle still work.

**That was M0's demo, and it is not what `MetalUIDemo` draws today.** The demo
was replaced by the element pipeline's — a four-level nested flex layout of
themed, rounded, background-filled boxes with a light/dark switch — and **it was
run and inspected by a human on 2026-08-26, who reported it works as expected**:
the nested layout renders, it reflows live while the window is dragged, and the
light/dark switch works. That closes milestone 1's exit criterion. Two specifics
of the M0 sentence above are stale rather than wrong: the rect it describes was
inserted as an `MUIRect`
directly, through an `App.openWindow` overload that no longer exists,
and **no element can draw a border at all.** `Frame.fill` is the only production
path into a `Scene` and it hard-codes `borderColor: .transparent,
borderWidths: 0`; the blocker is the resolved *width*, not the colour, and it is
recorded at `Frame.fill`. The renderer primitive still supports borders — M0's
demo is the proof — but nothing above the renderer can ask for one.

**What the human check establishes is a property of `AppKitPlatform`, not of
what the demo draws — and no test can establish it.** `MetalLayerSurface` vends drawables whether its `CAMetalLayer` is
attached to the view or orphaned, so reversing the `layer` / `wantsLayer`
assignment order in `AppKitPlatform` renders perfect pixels into a texture nobody
sees — and the whole suite still passed when that was measured, at 342 tests
(**444 today**; the count is quoted so the measurement can be dated, not because
342 is a property of anything). If you touch that ordering, re-run the demo
and look at it; the suite will not tell you.

**Text draws, and the demo now contains it — a single-line label in the
sidebar, a 22pt heading, and a paragraph that re-wraps on resize
(`Sources/MetalUIDemo/main.swift`). **No sentence in this file yet says a human
has looked at it**, and until one does the milestone's exit criterion is open —
the criterion is the look, not the presence of the code, because the three failure
modes spec §4.2 names (wrong glyph from a
key collision, wobble from a missing subpixel variant, intermittent blanks from
eviction) are all key failures that no assertion here can see. What *was*
established, and is worth knowing before that look: a `Text("Hi Wag")` at 22pt
rendered through a real `Renderer` into a real `Window`'s drawable and read back
produces **legible glyph shapes in the right order at the right advances** — the
readback was printed as ASCII art and the word was readable. That rules out the
gross failures (nothing drawn, every glyph stacked, the atlas sampled at the
wrong scale) and rules out none of §4.2's three. The assertable half of that
technique is kept as a test —
`theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor`, which compares
every unambiguously covered byte of the drawable against the glyph's own
rasterized bitmap — and its doc comment names the three failures it still cannot
see, and why each one hides from it.

**A second thing no test can establish, and this one is a live release trap.**
The `MeasureFunction` a `Text` attaches (`Text.requestLayout`) reduces to
`SizeD` inside `MainActor.assumeIsolated`, because the shaping cache is
`@MainActor` and a `ShapedText` may not cross an isolation boundary. That is
sound **only because `computeLayout` runs synchronously inside
`Frame.computeRootLayout`, which is `@MainActor`** — the engine is non-isolated
code executing on the caller's thread, not a hop. Drive layout over a tree
holding a text leaf from **any other executor** — a background actor, a
`Task.detached`, the 4 MB worker thread `LayoutContext`'s depth test already
spins up — and `assumeIsolated` terminates the process. Nothing in the repo can
notice: every existing off-main-actor layout builds its own leafless tree, and
a test that got this wrong would crash the run rather than redden. If layout
ever moves off the main actor, the measure closure is the first thing to
rewrite.

## Six known divergences — expected, measured, not defects

**1. Colour.** The layer's colorspace is Display P3 (spec §7.8) while
`Hsla.rgb(_:)` authors in sRGB, so `0x38BDF8` renders somewhat more saturated
than the hex implies.

**2. WebKit's flex sub-one clause.** The layout corpus treats WebKit as the
oracle, and there is exactly one place the engine knowingly does not follow it:
CSS Flexbox §9.7.4.b's magnitude test, in `ResolveFlexibleLengths.swift`.

Reproduce with:

```html
#root { display: flex; flex-direction: row; width: 400px; }
.a { flex: 0.25 1 0; min-width: 350px; }
.b { flex: 0.25 1 0; }
```

The spec says `b` is **50** — the sub-one scaling may only reduce the remaining
free space, never enlarge it, and on the second pass the scaled 100 exceeds the
remaining 50. **Blink says 50. WebKit says 100** and overflows the container to
450. Two engines and the specification against one: this is a WebKit bug, and
the engine follows the spec.

The divergence is narrower than it looks — it needs positive free space *and* a
min/max violation to force a second pass. `flex_row_fractional_shrink` exercises
the identical `abs` guard with negative free space and WebKit agrees with us
there.

**No fixture or golden encodes WebKit's answer.** The probe above was generated
against the oracle and then deliberately not committed, precisely so that a
future WebKit fix moves nothing in the corpus and changes no test. Do not add
one, and do not "correct" `subOneScalingNeverExceedsTheRemainingFreeSpace`
towards WebKit — it is pinning the settled answer, not a provisional guess.

**3. Ruling BM-4 — an over-constrained box does not grow to fit its padding
and border.** CSS's `box-sizing: border-box` defines a box's used size as
`max(specified, padding + border)`: when padding and border together exceed
the specified width or height on an axis, the browser **grows the border box**
to fit them rather than letting the content box go negative. This engine does
not do that. `contentBox` (`FlexEngine.swift`) only clamps the *content* box
to zero with `max(0, …)`; the border box stays exactly what the style
specified.

Reproduce with `width: 100px; height: 80px; padding: 60px 50px;
border-style: solid; border-width: 10px` and one auto-sized child: **WebKit
renders the root at 120×140**. `border-style` is not optional here — without it
`border-width` is inert and the same snippet measures 100×120 instead, which is
how this paragraph was wrong when first written
(120 = 50+50+10+10 horizontal, 140 = 60+60+10+10 vertical, both exceeding the
100×80 specified). This engine keeps the root at the specified **100×80**.

Implementing WebKit's answer belongs in sizing (`resolveNodeSize`/
`flexBaseSize`), not in `contentBox`: it would change a node's *stored* size,
which the freeze loop and every ancestor then consume — too much reach for a
style (padding/border larger than the box) that is already a mistake. Pinned
by `containerDoesNotGrowToFitOverconstrainedPaddingUnlikeWebKit` in
`BoxModelTests.swift`, with WebKit's numbers named in its comment so a future
change here is a decision, not a surprise.

**It is easier to hit by accident than "padding larger than the box" sounds**,
because percentage padding resolves against the *containing block*, which is
usually wider than the box. `flex_percent_padding_nonsquare`'s first draft used
`padding: 10% 5% 4% 15%` on a 400×100 root inside an 800-wide body: that is 80
+ 32 = 112 of vertical padding against a 100px height, and WebKit duly grew the
root to 112 tall. If a new fixture's golden shows a root taller or wider than
its declared size, this is why — shrink the percentages rather than encoding
the divergence into the corpus.

**4. Ruling CS-I — an `auto` root axis takes the space it was offered, where
CSS shrink-wraps the block one.** The root is a block-level box in the initial
containing block, so a browser fills its inline axis and shrink-wraps its block
axis. Measured: an 800×600 viewport holding `#root { display: flex }` with one
100×40 child gives WebKit **800 × 40**. This engine gives **800 × 600**.

**The justification is `computeLayout`'s contract, not a ruling from a layer
above.** The engine's root is not a block box in a CSS initial containing
block; it is a node whose size its host supplies, and `.definite(w)` on an axis
of `available:` is the host saying "this axis is w". A browser has no
equivalent — its root's containing block is the viewport by construction, and
it is never *told* a size. **Do not cite EP-5 here**: that ruling ends "the
WebKit corpus stays the oracle for the engine; this ruling binds everything
above it", and `resolveRootSize` is inside the engine.

The evidence is behavioural. CSS's answer was implemented and reverted, and it
reddens six element-pipeline and frame-loop tests at once, all for one reason —
a `Row { … }` rendered into a `Frame` declares no height, so the window's root
would collapse to its content and every `flexGrow(1)` child would stretch into 0.

**The engine can still express CSS's answer**, which is what makes this "we
interpret one call shape differently" rather than "we disagree with WebKit": a
host that offers `.maxContent` on the block axis takes the measuring branch and
gets the shrink-wrapped 40. Only the meaning of a *definite* offered extent on
an `auto` axis differs.

**A fixture could hold this one; the corpus deliberately has none.**
`#root { display: flex }` with no `width` or `height` is perfectly expressible,
and its golden would say 800×40 and fail — same footing as WebKit's flex
sub-one clause above. That all 67 roots declare both axes explains why no
*existing* fixture notices, not why one could not exist;
`FixtureHygieneError` does not enforce it, it only checks the root lands at
(0, 0).

What content sizing *did* change here is the other constant in the same branch
— an `auto` axis with **no offered extent at all** was a hardcoded 0 and is now
the subtree's own size, pinned by
`anAutoRootWithNoOfferedExtentMeasuresItsContent`.

**5. Ruling FS-3 — an item is floored by its content even when its own
`width` says it may be smaller.** CSS Sizing §4.5's automatic minimum (what
`min-width: auto`, the default on every flex item, resolves to) is
`min(specified size suggestion, content size suggestion)`. This engine
implements the **content** half only. That was dormant while nothing measured
content; content sizing made the content half live for containers, and the
missing half became measurable in the same stroke.

Reproduce with:

```html
#root { display: flex; width: 150px; height: 60px; }
.a { display: flex; width: 100px; }   /* holds a 200px child */
.b { width: 100px; height: 20px; }
```

|`.a`'s style | WebKit | this engine |
|---|---|---|
| `width: 100px` | `a` **100**, `b` **50** | `a` **200**, `b` **0** (overflows) |
| `width: 130px` | `a` **130**, `b` **20** | `a` **200**, `b` **0** |
| `width: 100px; min-width: 0` | `a` 75, `b` 75 | `a` 75, `b` 75 — agree |

The middle row is the sharp one: **WebKit's floor tracks the specified width and
this engine's does not move**, because it is the child's 200 in both cases. The
third row is the differential that names the cause — an explicit `min-width: 0`
replaces the automatic minimum and the two engines agree exactly.

**Not implemented here, and the reason is reach rather than effort** — the same
one that kept BM-4 out of the box model. The specified size suggestion changes
an item's floor, which §9.7's freeze loop consumes and every ancestor then sees
as a different stored size; it belongs in a sizing plan with the corpus
regenerated behind it. Pinned by
`aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit` in `FlexEngineTests.swift`,
with WebKit's numbers and both differentials in its comment.

**No fixture and no golden encode it**, on the same footing as the sub-one
clause above: a golden would record this engine's answer as correct, and a
future fix should move nothing in the corpus. That test is the only pin, so
implementing FS-3 must redden exactly it.

**6. Ruling TX-H — an item's cross size is measured before §9.7 flexes it.**
CSS Flexbox resolves the flexible lengths (step 6) and *then* determines each
item's hypothetical cross size "by performing layout with the **used** main
size" (§9.4 step 7). `collectItems` computes `ownCross` in the same pass as the
hypothetical main size, so an item that is about to shrink keeps the cross size
it had at its unshrunk width.

Measured through the oracle on a 120x600 root holding one
`display: flex; flex-wrap: wrap` child of four 50x20 items:

| container | WebKit | this engine |
|---|---|---|
| `row; align-items: flex-start` | `120x40` | **`120x20`** |
| `row` (stretch) | `120x600` | `120x600` — agree |

`Row { Text(longLabel) }` is therefore **one line tall while being narrower than
one line**: §4.5's automatic minimum shrinks it to three lines' worth of width
and the height it keeps is the one line it had before shrinking. Pinned by
`anItemsCrossSizeIsMeasuredBeforeFlexingUnlikeWebKit`.

**The spill was a prediction and is now a measurement.** With the glyph emitter
landed, `Row { Text("The quick brown fox jumps over the lazy dog") }` in a
120x600 frame gives the text a box of **120 x 16 at y = 292** — one line tall,
centred on the row's cross axis by ruling EP-8 — while paint wraps it to the
box's 120pt width and lays glyphs from y = 294 down to **y = 339**. So roughly
two of the three lines hang below the box. **Do not clamp this in paint**: the
box is what is wrong, the glyphs are where the box says, and a clamp would move
the defect somewhere nothing can see it.

**A second spill with the same symptom and an UNIDENTIFIED site, measured while
putting text in the demo — read it as an open question, not as a second
instance of the rule above.** Being a flex item is by itself enough to give a
`Column`'s text child a one-line box, with no shrinking and no `auto` size
anywhere:

```
Column(gap: 10) { Text("Library"); Box().height(26) }
  .width(68).padding(14).alignItems(.stretch)
```

**As the root** the label's box is 40×31pt — two lines, correct, and the `Box`
follows at y = 55. **As the only item of a `Row`** the identical column gives it
42×**15**pt — one line — while the glyphs still occupy two (device baselines
32/33/38 and 69 at 2x), so the second line lands inside the `Box`, which has
moved up to y = 39. The label's height is the item's *main* size in a column,
not its cross size, so **this is not literally §9.4 step 7**, and the site was
not isolated. It is visible in the demo: at the 920pt default the sidebar's
`Text("Library")` is one line and correct, and by 620pt the body row has shrunk
the 196pt sidebar to ~70pt, the label wraps, and its second line overlaps the
row below it. Whoever fixes divergence 6 should check this against the same
edit before assuming one change closes both.

**Not fixed, and the reason is reach — BM-4's and FS-3's reason.** It moves an
item's stored cross size, which every ancestor consumes and 67 goldens are
downstream of, and it reorders the main algorithm. **No fixture and no golden
encodes it**, deliberately: a golden would record this engine's answer as
correct, and a future fix should move nothing in the corpus.

**This was divergence 7 of seven, and 6 is gone.** Divergence 6 was the other
half of the same tree — `ownCross` measured **max-content** on whichever axis
was the cross one, so a **column** (whose cross axis is the *inline* axis, where
CSS shrink-wraps) laid a wrapping child out 200 wide at `x = -40` inside a
120-wide centring column, and `Column { Text(…) }` 270 wide at `x = -75`. It is
fixed: `ownCross` now computes CSS's fit-content —
`min(max(min-content, available), max-content)` — on a column's cross axis and
still max-content on a row's, which is right there because a row's cross axis is
the block axis.

**Read the caveat that came with that fix before trusting any similar one.** The
change moved **no** existing golden, and that was weak evidence rather than
strong: every box in the 61 fixtures preceding it is an empty div whose
min-content and max-content widths are the **same number**, so the corpus could
neither regress under the change nor validate it. Six fixtures with **wrapping**
children were generated against the oracle to close that
(`flex_column_fit_content*` plus `flex_row_block_axis_max_content`,
`FitContentFixtureTests`), and two of the fix's
four clauses were wrong before they were measured: the available space is the
container's cross extent **minus the item's own cross margins** (WebKit 104, not
120, for a 120-wide column and `margin: 0 6px 0 10px`), and the `max` with
min-content is a real floor that overflows (four 50-wide items in a **30**-wide
centring column measure `50x80` at `x = -10`).

## Declared but inert — verified, not remembered

The single most likely way to write a bug in this repo is to use an API that
exists, compiles, and does nothing. `Style` has 21 stored properties; **four of
them are read by no production code** — `position`, `inset`, `overflow`,
`aspectRatio`. **`StyledElement` deliberately exposes no modifier for any of the
four** (`Box.swift`): a modifier for an inert property is worse than none,
because from outside it is indistinguishable from an implemented one. When one
becomes live, add its modifier in the same task that deletes its row. Re-count with the grep below rather
than trusting the number: it was nine before the box model wired `padding`,
`border` and `margin` in, six before wrapping wired `flexWrap`, and five before
`align-content` landed. Count the properties with an *anchored* pattern and
subtract nothing by eye: `grep -cE "^    public var " Sources/MetalUILayout/Style.swift`
returns **23**, because `FlexDirection.isRow` and `.isReverse` are computed
`var`s at the same indentation in the same file. They were declared so the model
matches CSS, and the algorithm that consumes them has not been written yet.

**`wrap-reverse` left this table in wrapping's third task**, and it left as a
whole rule rather than a property: `flexWrap` was already live, and what was
missing was §8.3's cross-axis flip. Both halves are implemented now — the
`align-content` leading offset and each item's `crossAxisOffset` — in
`positionItems`, with three browser fixtures (`flex_wrap_reverse*`).

The table is wider than that count, because a property can be read and still
not do what its name promises — a stand-in value, or half a rule. Those rows
are the dangerous ones.

| Declared | Reality |
|---|---|
| `AlignItems.baseline` / `AlignSelf.baseline` | **Falls back to `flexStart`, not silently — and as of M2 the blocker this row used to name is GONE while the work is not done.** The row said `crossAxisOffset` "needs font metrics that arrive with the text system in M2". Those metrics exist: `MetalUIText`'s `FontMetrics` carries ascent, descent and leading, pinned against `CTFontGetAscent`/`Descent`/`Leading` by `metricsMatchCoreText`. Nothing is waiting on a milestone, so the three things that *are* missing are named as mechanisms at `crossAxisOffset` (`Alignment.swift`) instead — taxonomy shape 10's rule, applied to the row that motivated it. **(1) The engine cannot see a baseline at all**: a `MeasureFunction` returns a `SizeD`, so an item's first baseline never reaches `collectItems`, and the measure protocol has to carry it first. **(2) `crossAxisOffset`'s signature is the wrong shape**: baseline alignment is not an offset computed per item from `(itemCross, lineCross)` — a line's items must agree on a common baseline, which is a per-*line* quantity this function is never given. **(3) The `wrap-reverse` clause**: CSS Flexbox §8.3 swaps first- and last-baseline alignment in a `wrap-reverse` container, and nothing in the flip `positionItems` does today expresses that — it flips an offset, and baseline alignment is not an offset. Ruling AL-6: the task that makes an API inert records it here; the task that makes one live deletes the row. **The element pipeline's Task 4 made it reachable from the public API**: `StyledElement.alignItems(_:)` / `alignSelf(_:)` take the whole enum, so `.baseline` can now be written by a caller who will silently get `flexStart` — this row is the only thing guarding that, unlike `margin: .auto`, which the modifier's parameter type keeps out of reach. `justifyContent`, `alignItems` and `alignSelf` left this table when the alignment work implemented them and `alignContent` when wrapping's second task did; **a whole enum leaving is not the same as its every case leaving**, and this row is the standing counter-example |
| `aspectRatio` | **0 uses** |
| `margin: auto` (`Style.margin`'s `.auto` case) | **Resolves to 0, not to CSS's answer.** Item margins landed in the box-model task's second step — `resolveMargin` in `Resolve.swift` shrinks the main-axis budget and offsets each item by its own margin — but `.auto` maps to 0 on the single line marked for it in that function, not to CSS's "absorb free space before `justify-content` distributes any." A `margin-left: auto` item that CSS would push to the far end of the line lays out at the line's start instead, silently. Pinned by `autoMarginsResolveToZeroForNow` in `BoxModelTests.swift`, with CSS's real answer named in its comment. **This row's scope was too narrow until the wrapping branch's final review measured it** — the third claim of that shape on this project, after ruling WR-4's and WR-5's. Auto margins are not only a main-axis/`justify-content` gap: WebKit **centres a `margin-block: auto` item within its line on the CROSS axis** and we give 0 (`b` at 90 vs our 0). That was already true under `nowrap`; `align-content: stretch` — the default this branch made reachable — grows lines and widened it (`d` at 255 vs our 225). Whoever implements auto margins owns both axes, not just the one `justify-content` sees. **Unreachable from the public modifier API since the element pipeline's Task 4**, and by a type rather than by a convention: `StyledElement.margin(_:)` takes `Length`, not `Dimension`, so `.auto` cannot be written through it at all. `Style.margin` is still public, so the case is reachable by setting `style` directly |
| `MUIRect.borderColor` / `MUIRect.borderWidths` | **Round-trip the ABI, are drawn by `rect_fragment` — the M0 demo proved that end to end — and nothing in `MetalUI` can set either.** `Frame.fill` hard-codes `.transparent` and zero widths, and `Decoration` deliberately has no `borderColor`. The blocker is the **width**, not the colour: `Style.border` is an `Edges<Length>` whose percentage case resolves against the *containing block's* width, and the engine computes that inside `contentBox` and throws it away, so paint has no resolved width to pair a colour with. Re-resolving one at paint time against the box's own width is the exact mistake the percentage-inset constraint below records. Storing the resolved edges on `LayoutTree` is what unblocks it. Note the asymmetry this leaves: `StyledElement.borderWidth(_:)` is **live** and shrinks the content box, so a border affects sizing today and paints nothing |
| `MUIRect.contentMask` | Round-trips the whole CPU/GPU ABI; **`rect_fragment` never reads it.** No clipping. `grep contentMask Sources/` is not a clean 0 — `abi_probe` in `shaders.metal` reads `contentMask.size.width` to prove the field's offset survives the MSL boundary. That is the test harness, not rendering |
| A percentage `width`/`height` on the **root** | **Falls back to the offered space, not to the percentage.** `resolveRootSize` resolves the root's percentages against `nil` and then takes `available` — so `width: 50%` in an 800-wide space gives **800**. Measured in WebKit: **400**. The root's percentage *padding* does resolve against `available.width` (see `computeLayout`), so the two halves of "the root's containing block" disagree with each other today. Fixing it moves the root's stored size, which every descendant consumes; it belongs to a sizing plan, not the box model |
| `position`, `inset`, `overflow` | **0 uses each.** No absolute positioning, no clipping. Listed only so the count above reconciles with this table; there is nothing subtle about them, they are simply never read |
| `AnyElement` / `ElementObject` / `AnyElementBox` | **Fully implemented; reachable from a container, produced by nothing.** The element pipeline's Task 4 gave it `extension AnyElement: ElementGroup`, so `Row { AnyElement(x); y }` compiles and lays out — that is §4.6's escape hatch, and it is the only conformance in `Sources/MetalUI` that boxes. **What still has zero callers is the *production of* an `AnyElement`**: nothing in `ElementBuilder` returns one, so a box exists only where an author wrote `AnyElement(…)` by hand, and today that is tests alone. **It must not become the default path** (§4.6 allocation mitigation 1): the builder preserves concrete types, so `Column { Label(…); Button(…) }` builds `Column<Pair<Label, Button>>`. The guard is `theBuilderPreservesConcreteTypesRatherThanBoxing` in `ElementLayoutTests.swift`, and it is **type-level on purpose** — no layout or paint assertion in the repo can see boxing. **Re-measured, with a mutation that compiles.** The number this row used to quote came from adding `buildExpression<E: Element>(_:) -> AnyElement` to `ElementBuilder`, and that mutation **no longer compiles**: `anExplicitAnyElementIsStillAcceptedAsAChild` — added by that same commit — puts an `AnyElement` inside a builder block, so the generic overload demands `AnyElement: Element`, which it is not, and the suite fails to build with `error: static method 'buildExpression' requires that 'AnyElement' conform to 'Element'`. Pairing it with a non-generic `buildExpression(_ e: AnyElement) -> AnyElement` restores the measurement: **exactly the three type-level tests in that file redden, and no behavioural test at all — re-measured `--no-parallel` on 2026-08-27 after structural identity, out of 358 rather than the 303 first recorded, and the three are the same three.** Universal identity does not disturb it: `AnyElement`'s `requestGroupLayout` consumes one cursor index exactly as `Element`'s default does, so boxing every child moves no path and no `StateTable` entry. Delete this row when the static path demonstrably does not serve a real container |
| **Colour glyphs** (emoji, `COLR`/`sbix`) | **Wrong rather than absent, and now visibly so.** Spec §6.1 routes them to a *polychrome* atlas that skips tinting; there is no polychrome atlas in M2 and `GlyphRaster.rasterize` does not detect one either. So `CTFontDrawGlyphs` renders an emoji into the `DeviceGray` context as a **luminance silhouette**, it packs into the R8 atlas like any other glyph, and `glyph_fragment` multiplies it by the text colour — `Text("hi 🎉")` paints a flat blob in the text's colour where the emoji should be. It does not trap and it is not blank, which is exactly why it is written down: **nothing in this repo can see it**, there being no oracle for a rendered glyph at all (spec §4.2). The fix is a second atlas and a second draw path, not a branch in the rasterizer. Note that it was *invisible* rather than *wrong* until the glyph emitter landed — this row's status changed without its text changing, which is the shape ruling CS-E names |
| `GlyphAtlas.evictUnusedSince(_:)`, and the grow-only atlas it leaves | **Zero production callers — and a caller would make things WORSE, not better, until the packer can reclaim.** That is the mechanism, and it is checkable rather than a milestone to wait for: the shelf packer never revisits a closed shelf, so evicting a key frees a dictionary entry and **strands its pixels**; the next frame that wants that glyph packs a *second* copy further down. Calling eviction every frame therefore makes the atlas fill **faster**. `grep -rn "evictUnusedSince" Sources/` returns **nine** lines and **not one of them is a call**: the declaration, the string inside its own precondition message, and seven doc comments — the same shape as `LayoutTree.reset(generation:)` below. Re-count rather than trusting the nine; two of the doc comments were added by the emitter task, so this number moves with the prose and the "no call" half is the claim. The frame brackets it depends on *are* live: `Frame.render` calls `beginFrame`/`endFrame` around the paint phase, so the ordering guard is enforceable; what is absent is only the call. **These three facts are one story, so read them together:** eviction is unwired, the atlas is therefore **grow-only**, and when it is full `Frame.draw` **silently drops** the glyphs that will not fit — a window showing an unbounded stream of distinct glyphs loses text with no error anywhere. What unblocks it is a repacker or a whole-atlas rebuild, not a call site. Its guards (`evictingDuringFrameConstructionTraps`, `aGlyphUnusedSinceAnOlderGenerationIsEvicted`) stay for `LayoutTree.reset`'s reason: they pin the contract for whoever does call it |
| `Style.padding` / `Style.border` / `Style.margin` on a **leaf** | **Ignored entirely — for a `Text`, not "resolved wrongly".** `measureNode` returns a leaf's measure result unchanged where it adds a container's `edges` back on, and `contentBox` only ever runs on a node with children, so a leaf's border box *is* its content box. `Text(…).padding(Pixels(8))` therefore changes no size and moves no glyph, and `Text.paint` lays its glyphs from `bounds.origin` on exactly that basis. Consistent, and consistently wrong against CSS. **Reachable from the public API**, unlike the `Style` properties above: `StyledElement.padding(_:)`/`.borderWidth(_:)`/`.margin(_:)` are live modifiers that do the right thing on a `Box` and nothing on a `Text` — which is the shape this table exists for, an API that is implemented for one receiver and inert for another. Whoever implements a leaf's box model owns the paint half too: the glyph origin becomes the content box and must come from the engine rather than be re-resolved at paint time, for the percentage-inset reason recorded at `Frame.fill` |
| `LayoutTree.reset(generation:)` | **Zero production callers.** `grep -rn "\.reset(" Sources/` returns **two** lines and neither is a call: the string inside its own precondition message, and a doc comment on the method that quotes this very grep. (It matched one line when this row was written; the doc comment came later, so re-run it rather than counting — the claim is "no call", not "two".) The element pipeline's plan predicted a per-frame reset; `Frame` allocates a **fresh `LayoutTree` each frame** instead (spec §4.1), so the capacity-reuse path this method exists for is never taken. It is not inert in the sense the rows above are — it works, and its four guards in `LayoutTreeTests` prove the ruling C-3 staleness contract fires — but its doc comment reads as a live API, which is exactly the situation `newLeaf` is listed here for. **Keep the guards**: they pin the contract for whoever does call it, and C-3 is the hazard this repo has already been bitten by |
| CSS Sizing §4.5's **specified size suggestion** | **Still not implemented** (ruling FS-3), and it **left this table's premise behind**: content sizing made the *content* half live for containers, so the missing half is no longer inert-and-invisible but a measured disagreement with WebKit — **divergence 5 above** carries the repro, the numbers and the pin, and is the one place to update. Two claims expired here in one milestone, and the second was written by the commit that retired the first (ruling CS-E's shape, third occurrence on this project): "indistinguishable until M2", then "not yet a wrong answer anywhere". Kept as a row because the *declaration* half is what this table is for — the rule is half-implemented at `collectItems`' automatic minimum, and silence there would read as complete. `aContainerItemIsFlooredByItsChildrensWidth` cannot see it: its `.a` has no specified width to be floored by |

Re-check any row rather than trusting this table:

```bash
grep -rn "aspectRatio" Sources/ | grep -v "var aspectRatio"
```

**When you implement one, delete its row.** When you add a property you cannot
implement yet, add one — silence at a declaration reads as "implemented", and that
is taxonomy shape 4 in the practices doc.

## Build

`swift build` · `swift test` — **444 tests** and 67 browser fixtures, warning-free
(re-measured 2026-08-27 `--no-parallel` at the **end** of M2, on `feat/text-m2`
after `swift package clean`, per rulings CS-M/CS-N/SI-H: a count is stale the
moment a test is added, so it is taken at the milestone's last commit rather
than at the commit that first quoted it. Task 8 added no test — it is docs and
the demo — so the emitter's 444 reproduced exactly. Read the
summary line, never the exit status — shape 11. It was 429 before the emitter,
396 after the divergence-6 task, 365 after Task 1 and 360
before the branch, and that 360 measured 361 on the same checkout — so treat a
±1 as a stale doc rather than a missing test, and re-measure).
**Eight** non-test targets with strictly one-way dependencies: `MetalUICore`,
`MetalUILayout`, `MetalUIText`, `MetalUIShaderTypes`, `MetalUIRender`,
`MetalUIPlatform`, `MetalUI`, `MetalUIDemo`. **`MetalUITestSupport` is a ninth
`.target` in `Package.swift` and is not one of them** — it lives under `Tests/`,
ships in no product, and holds the single copy of the `swiftc -typecheck`
machinery the negative type-system guards shell out to (ruling EP-1). Count with
`grep -cE "^ +\.(target|executableTarget)\(" Package.swift`, which returns 9
(`.testTarget(` does not match), and subtract `MetalUITestSupport`.

**Spec §3.1 says "seven targets", and it is a different seven.** Its list is
the module *layering* — `MetalUI`, `MetalUILayout`, **`MetalUIText`**,
`MetalUIRender`, `MetalUIPlatform`, `MetalUICore`, `MetalUIShaderTypes` — which
excludes `MetalUIDemo`, an executable rather than a layer. **The two counts used
to agree and no longer do**: M2 Task 1 landed `MetalUIText`, which this section
had already named as the coincidence's expiry date. Eight here against §3.1's
seven is the expected state. Do not "reconcile" one list to the other.

Four constraints that are easy to violate silently:

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored
  pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Every `LayoutTree` that could ever exchange ids with another must have a
  distinct `generation`** (m1a ruling C-3, closed in the element pipeline's task
  4). `LayoutNodeID` carries the generation of the tree that issued it and every
  accessor rejects a foreign one, but the *uniqueness* of the generation is the
  constructor's obligation: `LayoutTree.init(generation:)` has no default
  precisely so that obligation is visible at each call site. In `Sources/` the
  only constructor is `Frame`, which draws from a `@MainActor` counter — check
  with `grep -rn "LayoutTree(" Sources/`. Layout tests pass `0` because their
  trees never exchange ids; a test that puts two trees in one function and moves
  an id between them must not.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** An `_sRGB` target makes the
  hardware blend in linear space; this framework composites in gamma-encoded sRGB
  by design (§7.8). It would look fine now and make text rendering wrong later.
- **A percentage inset resolves against the CONTAINING BLOCK's width — not the
  box's own width, and not a height.** Both halves of that sentence have been
  wrong in this repo, and neither failed a test at the time. `contentBox`
  resolved percentage `padding`/`border` against the box's own border-box width
  until the box model's third task; WebKit puts a 200-wide `.mid { padding: 10% }`
  inside a 270-wide content box at **27**, not 20. The vertical edges take the
  same *width* basis, which a square container cannot distinguish — that is why
  `flex_percent_padding_nonsquare` is 400×100 inside an 800×600 viewport, so
  that all three candidate bases give three different answers on every edge.
  `flex_nested_percent_padding` does the same one level down, where the
  containing block is not the viewport.

**Adding an AppKit or WebKit test? Run the WHOLE suite and read the summary
line — `--filter` is a different program.** Every test target runs in **one
process**, so an AppKit test and the WebKit layout-oracle tests share a main run
loop. That composition has already crashed the suite once: two
`MetalUIPlatformTests` cases ended in `defer { nsWindow.close() }`, and
`NSWindow(contentRect:…)` defaults `isReleasedWhenClosed` to **true** — an
over-release of a window ARC already owns, which AppKit defers into an
autorelease pool that CoreAnimation pops from a run-loop observer. Alone the
process exited before that pool popped; alongside a test that `await`s it landed
in `-[_NSWindowTransformAnimation dealloc]` as `EXC_BAD_ACCESS`, and `swift test`
died with **297 of 303 tests reported and no summary line**. Fixed at the source
(`AppKitWindow.init` now sets `isReleasedWhenClosed = false`) and pinned by
`closingAWindowDoesNotOverReleaseTheOneARCAlreadyOwns`. **Serializing the two
targets would not have fixed it** — a single `--no-parallel` test that closes a
window and then drives the oracle crashes with no interleaving at all. The full
write-up is under shape 11 in `docs/practices/verifying-tests-can-fail.md`; the
short rule is that a test touching a process-wide host (AppKit windows, WebKit,
CoreAnimation, the main run loop) is only verified by an unfiltered run whose
count you read.

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

## Layout cost — measured, and content sizing multiplied it by ~4.9x

`computeLayout` costs **~40 us per node in debug and ~5.3 us in release**, flat
from 8 k to 88 k nodes. The same trees cost ~8 us and ~1.2 us per node before
content sizing, so **the complexity is unchanged and the constant factor is
~4.9x**:

**Measured during the content-sizing milestone's Task 6 (2026-08-26), on that
machine; debug build unless a column says release.** A performance figure drifts
more quietly than a behavioural one — re-measure before deciding anything on
these.

| tree | nodes | debug before → after | release before → after |
|---|---|---|---|
| depth 12, branch 2 | 8,191 | 72.8 → **372.0 ms** | 10.2 → **45.0 ms** |
| depth 10, branch 3 | 88,573 | 708.4 → **3,504.4 ms** | 96.3 → **456.9 ms** |

**Corroborated 2026-08-27** on the structural-identity branch, and it is
corroboration rather than a re-run: a whole `Frame.render` — element walk,
`computeLayout`, prepaint and paint — over the same node counts cost **369.5 ms**
and **3,540 ms** in debug, **51.6 ms** and **520.7 ms** in release. Those bracket
the `computeLayout`-only figures above from the correct side, so the table has
not rotted on this machine; it has not been re-taken with the same harness.

**The cause is §4.5's automatic minimum, which now probes EVERY item** —
`min-width: auto` is CSS's default — and an `auto`-cross item probes again, so a
container's children are each measured up to three times per layout. Whoever
optimises this starts there: it is the probe that fires unconditionally. The
memo cache in `LayoutContext` is what keeps this a constant multiplier instead
of the depth-exponential ~700x the design spec predicted without it, and
`theCacheIsActuallyConsulted` is the only test that can see the cache working.

**Measure on a BRANCHING tree, never a chain.** A chain has one child per level,
so the three probes per item collapse onto the same few cache keys and the cost
looks linear and cheap — which is exactly what the during-task measurement
showed, and why this number went unrecorded until the milestone's last task.
Absolute figures are this machine's; the ratio is the part that transfers.
Release is ~8x faster in absolute terms with the same ratio. For scale, Yoga and
Taffy are quoted in the 0.1-0.5 us/node range.

### Identity path construction — measured 2026-08-27, and it is ~0.4% of a frame

**Measured 2026-08-27 on the structural-identity branch, debug unless a column
says release**, with a throwaway spike deleted in the same task. Re-measure
before deciding anything on these. The counterfactual is the pre-milestone array
representation (`(parent?.path ?? []) + [component]`) reconstructed beside the
shipping linked list and timed on the same trees in the same process; best of
five, one path per node.

**The `depth` column counts LEVELS here and EDGES in the table above** — the two
harnesses were written a day apart and disagree. The **node count** is the
unambiguous key, and it is deliberately the same 8,191 and 88,573, so the rows
line up despite the labels.

| tree | nodes | avg depth | linked us/node | array us/node | ratio |
|---|---|---|---|---|---|
| 13 levels, branch 2 | 8,191 | ~12 | **0.154** / 0.093 rel | 0.697 / 0.300 rel | 4.5x / 3.2x rel |
| 11 levels, branch 3 | 88,573 | ~10 | **0.150** / 0.088 rel | 0.660 / 0.272 rel | 4.4x / 3.1x rel |
| 3 levels, branch 90 | 8,191 | ~3 | **0.144** / 0.084 rel | 0.501 / 0.141 rel | 3.5x / 1.7x rel |

**The third row is the control**, and it is what makes this a measurement of the
O(1)-vs-O(depth) claim rather than of the tree: same 8,191 nodes, average depth
~3 instead of ~12.

**Release is the load-bearing column for the O(1) claim, and an independent
re-run is why this clause exists.** In debug the linked list's own depth
sensitivity across the control (−6% here, −25% in the re-run) is comparable to
the array form's (−28% here, −18% there), so the debug rows do not separate the
two models cleanly — allocation and retain/release traffic dominate both. In
release they do separate: array 0.300 → 0.141 against linked 0.093 → 0.084. Read
the release figures for the claim and the debug figures for the absolute cost.

**End to end the win is at or below noise, and that is the honest headline.**
Path construction is 0.3-0.4% of a debug `Frame.render` and ~1.5% of a release
one. The saving over the array form is 4.5 ms on the 8,191-node tree against a
7.2 ms run-to-run spread — **not visible above noise** — and 45 ms against a 19
ms spread on the 88,573-node tree, which is measurable and still ~1.3% of the
frame. The linked list is the right structure for the reason it was chosen (it
removes a depth factor from a per-frame cost for one allocation's price), but
nobody should expect a frame-time change from it while `computeLayout` costs
~40 us/node.

## When CI lands

Three guarantees silently lapse under plausible configurations and must be
required, non-gateable jobs. All three are detailed in the decisions docs:

1. The ABI probe **skips** without a Metal device.
2. `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
3. **The 25 `swiftc -typecheck` guards skip whenever `.build` is not where
   `#filePath`-relative resolution expects it.** `canTypecheck`
   (`Tests/MetalUITestSupport/Typecheck.swift`) walks three directories up from
   its own `#filePath` and looks for `.build/<triple>/debug/Modules` holding the
   module; a `--scratch-path`, a CI that builds elsewhere, a moved checkout, or
   `swift test -c release` all make that miss and every guard becomes a skip.
   **That set is this milestone's headline deliverable and both of its
   compile-time exit criteria** — `PhaseSeparationTests` (15),
   `ErasureCompileGuards` (7), `ElementGroupTrapTests` (1), `UnitSafetyTests` (2)
   — and none of them has a runtime equivalent, by construction: each asserts
   that something must *not* compile, so a regression makes the offending code
   compile and leaves every ordinary test green.

   **Taxonomy shape 11's count heuristic does not catch this one.** Measured, by
   forcing `canTypecheck` to `false`: exactly 25 tests report as skipped, the
   total does not move, and the run passes. The 25 was first taken at
   `Test run with 304 tests`, re-measured at 358 on the structural-identity
   branch, and **re-counted at the end of M2 (suite 444): still 25 — 15 + 7 + 1
   + 2 across the four files**, where `grep -c canTypecheck` reads 3 in
   `UnitSafetyTests` because one is a comment. **The guard count does not track
   the suite count and neither number implies the other.** A falling suite count
   is the signal shape 11 tells you to watch, and this failure does not move it.

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
