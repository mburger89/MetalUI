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
  `docs/superpowers/2026-08-26-element-pipeline-decisions.md` — each ruling with
  its reasoning and what it costs if wrong. Read the "Carried..." sections before
  starting new work.

  **Ruling IDs are namespaced by milestone.** `PF-3` and `C-3` belong to m1a;
  `FS-n` to flex sizing, `AL-n` to alignment, `BM-n` to the box model, `WR-n` to
  wrapping, `EP-n` to the element pipeline (**`EP-2` and `EP-4` were never
  assigned** and must not be reused — a new ruling taking one would silently
  rebind any citation written against the gap). Sweep for stray citations **case-insensitively** — a `Ruling F-3` survived two branches' greps for lowercase `ruling`. A bare `F-1` is ambiguous — m0, m1a and flex sizing each
  had one, and three code comments on the flex-sizing branch cited the wrong
  document before this was fixed. Prefix new milestones' rulings the same way.

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
catalogues eleven shapes of test that cannot fail, all observed in this repo, plus
the method for finding them and the cases where adding a test is the wrong answer.

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

## Verified on real hardware

`swift run MetalUIDemo` was run and inspected on a Retina display: the window
shows the centred rounded rect with its antialiased border, and the close button
quits the process.

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
sees — and all 303 tests still pass. If you touch that ordering, re-run the demo
and look at it; the suite will not tell you.

## Three known divergences — expected, measured, not defects

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
| `AlignItems.baseline` / `AlignSelf.baseline` | **Falls back to `flexStart`, not silently.** `crossAxisOffset` needs font metrics that arrive with the text system in M2; until then a `baseline`-aligned row lays out as a `flex-start` row. **Whoever implements it inherits a `wrap-reverse` clause**: CSS Flexbox §8.3 swaps first- and last-baseline alignment in a `wrap-reverse` container, and nothing in the flip `positionItems` does today expresses that — it flips an offset, and baseline alignment is not an offset. Ruling AL-6: the task that makes an API inert records it here; the task that makes one live deletes the row. **Task 4 made it reachable from the public API**: `StyledElement.alignItems(_:)` / `alignSelf(_:)` take the whole enum, so `.baseline` can now be written by a caller who will silently get `flexStart` — this row is the only thing guarding that, unlike `margin: .auto`, which the modifier's parameter type keeps out of reach. `justifyContent`, `alignItems` and `alignSelf` left this table when the alignment work implemented them and `alignContent` when wrapping's second task did; **a whole enum leaving is not the same as its every case leaving**, and this row is the standing counter-example |
| An `auto` cross size on **any** item, stretched or not | **Resolves to 0, not to content.** §9.4's stretch half is implemented; its content-sizing half is not, so an `auto` cross size measures 0 where CSS gives it the content's cross extent. **This row said two things that were false until ruling **WR-4**'s probe round disproved them, and the corrections matter more than the row.** (1) It scoped the gap to a **non-stretched** item. It is not so scoped: the size is lost in §9.4.8 **line measurement**, which runs *before* stretch, so a `stretch`-aligned item loses it too. (2) It said "no fixture can catch this — every fixture in the corpus is an empty div" and blamed the **M2 text system**. A **nested flex container** has a content cross size with no text in it, and two probe agents caught it independently today: a 200×200 `wrap` root holding a `width: 120px` nested flex container gives WebKit `120×50` and this engine `120×0`, collapsing the line and stacking the next one on top of it. M2 is not the gate; recursive subtree measurement is, and that is its own plan. `flex_row_stretch_mixed`'s `.c` still agrees with WebKit at 0 for the wrong reason — that part was true. **Wrapping raised the stakes**: a line whose items are *all* auto-cross now measures 0 tall, so the whole line collapses and every line after it shifts up, rather than one item within a line being wrong. **`align-content` raised them again, and out of the "silent" category**: a nested `wrap` container with `height: auto` has a cross extent of 0, so its lines' total cross is *negative* free space and `align-content` distributes it — `flex-end` places children at **y = −102** and `center` at **−51** where WebKit gives 0 and 50. That is internally consistent given `containerCross == 0`, and it was positionally invisible while lines packed from cross-start; it is not any more. Negative stored coordinates are the loudest symptom this divergence has ever had, and they are a symptom of the auto-cross gap, not of `align-content`. `wrap-reverse` neither helps nor worsens it: its flip is `containerCross - lineCrossStart - lineCross`, so a zero-height container simply gets the same wrong numbers with the sign structure inverted |
| `aspectRatio` | **0 uses** |
| `margin: auto` (`Style.margin`'s `.auto` case) | **Resolves to 0, not to CSS's answer.** Item margins landed in the box-model task's second step — `resolveMargin` in `Resolve.swift` shrinks the main-axis budget and offsets each item by its own margin — but `.auto` maps to 0 on the single line marked for it in that function, not to CSS's "absorb free space before `justify-content` distributes any." A `margin-left: auto` item that CSS would push to the far end of the line lays out at the line's start instead, silently. Pinned by `autoMarginsResolveToZeroForNow` in `BoxModelTests.swift`, with CSS's real answer named in its comment. **This row's scope was too narrow until the wrapping branch's final review measured it** — the third claim of that shape on this project, after ruling WR-4's and WR-5's. Auto margins are not only a main-axis/`justify-content` gap: WebKit **centres a `margin-block: auto` item within its line on the CROSS axis** and we give 0 (`b` at 90 vs our 0). That was already true under `nowrap`; `align-content: stretch` — the default this branch made reachable — grows lines and widened it (`d` at 255 vs our 225). Whoever implements auto margins owns both axes, not just the one `justify-content` sees. **Unreachable from the public modifier API since Task 4**, and by a type rather than by a convention: `StyledElement.margin(_:)` takes `Length`, not `Dimension`, so `.auto` cannot be written through it at all. `Style.margin` is still public, so the case is reachable by setting `style` directly |
| `MUIRect.borderColor` / `MUIRect.borderWidths` | **Round-trip the ABI, are drawn by `rect_fragment` — the M0 demo proved that end to end — and nothing in `MetalUI` can set either.** `Frame.fill` hard-codes `.transparent` and zero widths, and `Decoration` deliberately has no `borderColor`. The blocker is the **width**, not the colour: `Style.border` is an `Edges<Length>` whose percentage case resolves against the *containing block's* width, and the engine computes that inside `contentBox` and throws it away, so paint has no resolved width to pair a colour with. Re-resolving one at paint time against the box's own width is the exact mistake the percentage-inset constraint below records. Storing the resolved edges on `LayoutTree` is what unblocks it. Note the asymmetry this leaves: `StyledElement.borderWidth(_:)` is **live** and shrinks the content box, so a border affects sizing today and paints nothing |
| `MUIRect.contentMask` | Round-trips the whole CPU/GPU ABI; **`rect_fragment` never reads it.** No clipping. `grep contentMask Sources/` is not a clean 0 — `abi_probe` in `shaders.metal` reads `contentMask.size.width` to prove the field's offset survives the MSL boundary. That is the test harness, not rendering |
| A percentage `width`/`height` on the **root** | **Falls back to the offered space, not to the percentage.** `resolveRootSize` resolves the root's percentages against `nil` and then takes `available` — so `width: 50%` in an 800-wide space gives **800**. Measured in WebKit: **400**. The root's percentage *padding* does resolve against `available.width` (see `computeLayout`), so the two halves of "the root's containing block" disagree with each other today. Fixing it moves the root's stored size, which every descendant consumes; it belongs to a sizing plan, not the box model |
| `position`, `inset`, `overflow` | **0 uses each.** No absolute positioning, no clipping. Listed only so the count above reconciles with this table; there is nothing subtle about them, they are simply never read |
| `AnyElement` / `ElementObject` / `AnyElementBox` | **Fully implemented; reachable from a container, produced by nothing.** Task 4 gave it `extension AnyElement: ElementGroup`, so `Row { AnyElement(x); y }` compiles and lays out — that is §4.6's escape hatch, and it is the only conformance in `Sources/MetalUI` that boxes. **What still has zero callers is the *production of* an `AnyElement`**: nothing in `ElementBuilder` returns one, so a box exists only where an author wrote `AnyElement(…)` by hand, and today that is tests alone. **It must not become the default path** (§4.6 allocation mitigation 1): the builder preserves concrete types, so `Column { Label(…); Button(…) }` builds `Column<Pair<Label, Button>>`. The guard is `theBuilderPreservesConcreteTypesRatherThanBoxing` in `ElementLayoutTests.swift`, and it is **type-level on purpose** — no layout or paint assertion in the repo can see boxing. **Re-measured, with a mutation that compiles.** The number this row used to quote came from adding `buildExpression<E: Element>(_:) -> AnyElement` to `ElementBuilder`, and that mutation **no longer compiles**: `anExplicitAnyElementIsStillAcceptedAsAChild` — added by the same Task 4 commit — puts an `AnyElement` inside a builder block, so the generic overload demands `AnyElement: Element`, which it is not, and the suite fails to build with `error: static method 'buildExpression' requires that 'AnyElement' conform to 'Element'`. Pairing it with a non-generic `buildExpression(_ e: AnyElement) -> AnyElement` restores the measurement: **exactly the three type-level tests in that file redden, and no behavioural test at all, out of 303.** Delete this row when the static path demonstrably does not serve a real container |
| `MeasureFunction` / `tree.measure()` | **Two callers, never populated.** `flexBaseSize`'s content-size branch and `collectItems`' CSS Sizing §4.5 automatic-minimum probe both read it, but `newLeaf` — the only way to attach a measure function — has no production caller, so every production node's `tree.measure()` returns `nil`: `flexBaseSize` always takes its 0 fallback and `min-width: auto` always resolves to no floor. Both rules are therefore exercised **only by tests that build their own closures**, which is why `min-width: auto` has no browser fixture — see `automaticMinimumSizeUsesContentSizeNotFlexBasis` |
| `LayoutTree.reset(generation:)` | **Zero production callers.** `grep -rn "\.reset(" Sources/` matches only the string inside its own precondition message. The element pipeline's plan predicted a per-frame reset; `Frame` allocates a **fresh `LayoutTree` each frame** instead (spec §4.1), so the capacity-reuse path this method exists for is never taken. It is not inert in the sense the rows above are — it works, and its four guards in `LayoutTreeTests` prove the ruling C-3 staleness contract fires — but its doc comment reads as a live API, which is exactly the situation `newLeaf` is listed here for. **Keep the guards**: they pin the contract for whoever does call it, and C-3 is the hazard this repo has already been bitten by |
| CSS Sizing §4.5's **specified size suggestion** | **Not implemented** (ruling FS-3). The automatic minimum is `min(specified suggestion, content suggestion)`; only the content half exists. Indistinguishable until something measures content in production — M2 |

Re-check any row rather than trusting this table:

```bash
grep -rn "aspectRatio" Sources/ | grep -v "var aspectRatio"
```

**When you implement one, delete its row.** When you add a property you cannot
implement yet, add one — silence at a declaration reads as "implemented", and that
is taxonomy shape 4 in the practices doc.

## Build

`swift build` · `swift test` — 303 tests and 57 browser fixtures, warning-free.
**Seven** non-test targets with strictly one-way dependencies: `MetalUICore`,
`MetalUILayout`, `MetalUIShaderTypes`, `MetalUIRender`, `MetalUIPlatform`,
`MetalUI`, `MetalUIDemo`. **`MetalUITestSupport` is an eighth `.target` in
`Package.swift` and is not one of them** — it lives under `Tests/`, ships in no
product, and holds the single copy of the `swiftc -typecheck` machinery the
negative type-system guards shell out to (ruling EP-1). Count with
`grep -cE "^ +\.(target|executableTarget)\(" Package.swift`, which returns 8
(`.testTarget(` does not match), and subtract `MetalUITestSupport`.

**Spec §3.1 also says "seven targets", and it is a different seven.** Its list is
the module *layering* — `MetalUI`, `MetalUILayout`, **`MetalUIText`**,
`MetalUIRender`, `MetalUIPlatform`, `MetalUICore`, `MetalUIShaderTypes` — which
includes the text target that does not exist yet and excludes `MetalUIDemo`,
which is an executable rather than a layer. The two counts agreeing today is a
coincidence and it expires: when Text lands the package has eight non-test
targets against the spec's seven. Do not "reconcile" one list to the other.

Three constraints that are easy to violate silently:

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

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

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
   total stays `Test run with 303 tests`, and the run passes. A falling count is
   the signal shape 11 tells you to watch, and the count does not fall.

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
