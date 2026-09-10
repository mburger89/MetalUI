# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written
as idiomatic Swift. macOS and iOS.

**This file is the rules. The reasoning, the measurements and the history live
in `docs/record/`** — the pre-2026-09-09 `CLAUDE.md`, moved there verbatim
(4,172 lines) and split by section. Every test name, ruling id, divergence
label and grep cited there still resolves. When something here is not enough,
read the matching record file before re-deriving it. New milestones append
their record to `docs/record/` and put only the rule here.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`.
  Per-milestone specs and plans sit beside it in `specs/` and `plans/`.
- **Decisions docs** (`docs/superpowers/<date>-<milestone>-decisions.md`), one
  per milestone, each ruling with its reasoning and what it costs if wrong.
  Read the "Carried…" sections before starting new work. Ruling ids are
  namespaced by milestone prefix:

  | prefix | milestone | form |
  |---|---|---|
  | `F-`, `PF-`, `C-` | m0 / m1a (a bare `F-1` is ambiguous: three docs have one) | numbered |
  | `FS-`, `AL-`, `BM-`, `WR-`, `EP-` | flex sizing, alignment, box model, wrapping, element pipeline | numbered (`EP-2`/`EP-4` never assigned, never reuse) |
  | `CS-`, `SI-`, `TX-`, `CL-`, `ST-`, `AP-`, `MP-`, `IN-`, `SZ-` | content sizing … sizing | **lettered** (`CS-A`…; `MP-L`…`MP-N` and `SZ-O` are real) |
  | `TB-`, `RX-`, `CO-` | tombstones (`TB-A`…`TB-AH`), reactivity (`RX-A`…`RX-R`), Component (`CO-A`…`CO-Z`, next is `CO-AA`) | lettered, two-letter tails are deliberate |

  A bare `CS-3`, `TB-3`, `CO-3` etc. is a typo, not a citation. Sweep for stray
  citations case-insensitively. The animation milestone (M4 spec 3, in progress
  on `feat/animation`) is specced at
  `docs/superpowers/specs/2026-09-03-animation-design.md` and planned at
  `docs/superpowers/plans/2026-09-03-animation.md`; its decisions doc is not
  yet written.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests. Sixteen numbered shapes of test that cannot fail, seven ways a
  record goes wrong, all observed here.
- **Full record:** `docs/record/README.md` indexes the eight sections.

## Build and test

```bash
swift build
swift test --no-parallel
# suite total — swift test prints ONE summary line PER TEST TARGET (six); sum them:
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc
# the env-gated 100k-row cold-frame test (~42 s debug / ~17 s release):
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
swift run MetalUIDemo            # and: swift run -c release MetalUIDemo
```

- **Counts, dated:** 861 tests, 87 browser-fixture goldens, 35 `swiftc
  -typecheck` guards, warning-free — measured 2026-09-10 on `feat/animation`
  at `54f2bb5`, on a `swift package clean` build (`master` at the Component
  milestone's end was 811 / 87 / 34; this branch read 843 at `6591360` before
  the animation milestone's Tasks 4b and 5).
  A count is stale the moment a test lands; re-measure rather than trust.
  Two tests are gated and **count toward the total** while being skipped
  (`regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`).
- **Read the printed counts, never the exit status.** The last summary line
  alone reads 22 (`MetalUICoreTests`) on every healthy run.
- **Goldens must not move** on any milestone that does not touch
  `Sources/MetalUILayout/`; a moved golden means something reached the engine.
  `find Tests -name "*.json" | wc -l` is the count. WebKit is the layout oracle;
  the corpus has **no text fixture and must not gain one** (ruling TX-B).
- **Guards:** count with per-file `grep -c canTypecheck` across
  `PhaseSeparationTests`, `ErasureCompileGuards`, `ElementGroupTrapTests`,
  `MetalUICoreTests/UnitSafetyTests` (one hit is a comment) and
  `MetalUITests/AXNodeTests`. `Tests/MetalUITestSupport/Typecheck.swift` also
  matches and holds only the declaration — count guards, not files. Guards
  skip silently whenever `.build/<triple>/debug/Modules` is not where
  `#filePath`-relative resolution expects (`--scratch-path`, `-c release`,
  moved checkout): the total does not move and the run passes.
- **Adding an AppKit or WebKit test? Run the whole suite unfiltered.** All
  targets share one process and one main run loop; `--filter` is a different
  program. `AppKitWindow.init` sets `isReleasedWhenClosed = false` for this
  reason.
- **`swift package clean` when the impossible happens.** Two mechanisms: the
  shader header `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` reaches
  its C target through an untracked symlink; and adding a case/stored property
  to a public type that crosses a module boundary (`Scene` twice, `Display`)
  leaves incremental builds disagreeing about layout. Symptoms: SIGSEGV or a
  truncated run with no summary line, or an assertion whose *expected* side
  holds a value its own source cannot produce. Clean before debugging.
- **Targets:** eight one-way-dependent non-test targets (`MetalUICore`,
  `MetalUILayout`, `MetalUIText`, `MetalUIShaderTypes`, `MetalUIRender`,
  `MetalUIPlatform`, `MetalUI`, `MetalUIDemo`) plus `MetalUITestSupport`
  under `Tests/`. Spec §3.1's "seven" excludes the demo; do not reconcile.

Four constraints that fail silently:

- `MetalUILayout` imports only `MetalUICore` (check with an anchored grep).
- Every `LayoutTree` that could exchange ids with another needs a distinct
  `generation` (ruling C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` — compositing is gamma-space by
  design (§7.8).
- Percentage `padding`/`border` resolve against the **containing block's
  width** on every edge. `Style.inset` is the exception: horizontal against
  width, vertical against height (ruling AP-D).

## Architecture rules that a reader will otherwise get wrong

**Three phases, and paint-only queries are compile-time guarded.**
`requestLayout` → `prepaint` → `paint`. `isHovered` (both spellings),
`isActive` and `isFocused` exist only on `PaintPass`; each has a typecheck
guard because a prepaint-time answer would compile and lie. A fifth such query
gains a guard and a bullet in `PhaseSeparationTests.swift`'s header in the same
change.

**Identity is structural and universal; `.id()` overrides a position, never
joins it.** Consequences (record §01):
- A vanishing `if` makes the **trailing sibling adopt** the vanished element's
  state, focus and even click dispatch — a release can run the wrong `onClick`.
  Remedy: name the **trailing sibling**, not the conditional content. Not a
  divergence; it is the one notion of sameness `StateTable`, focus and hover
  share.
- `GlobalElementID.cachedHash` and `==` are safe alone and unsafe together; do
  not simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ above the engine
  (ruling EP-5); WebKit stays the oracle for the engine itself.

**Containers.** `Column`/`Row` centre on the cross axis, `Box` stretches
(EP-8, set in the inits, not in `Style`) — so a childless `Box` with no cross
size paints nothing; declare a size or `.alignItems(.stretch)`. `Stack` layers
(`Stack.swift`; `Column`/`Row` live in `Flex.swift`), last child on top; its
paint order is invisible to every rect test. There is no `display: contents`.

**`List` is a windowed `Box`, not a container.** Four load-bearing
requirements: `Identifiable` data, a uniform `rowHeight`, an enclosing
`ScrollView`, and **being that scroller's only layout-contributing child** —
the last degrades to a blank list (divergence 14). Frame 0 builds every row
(MP-I: ~76 ms release at 500 rows, ~17 s at 100k). A row scrolled out for more
than two generations loses `@State` and focus once the table exceeds 256
entries (TB-AH); values a long scroll must keep belong in the data. Rows emit no
AX nodes; the `List` emits one with `logicalCount`. Off-screen rows' model reads
are not tracked (RX-P, not a divergence).

**`Deferred` is a portal: one child, no layout node, hoists to the root layer
and resets clip and scroll offset together** (AP-I). No z-index. Absolute
positioning is separate: `.position(.absolute)` + `.inset(...)` against the
nearest non-static ancestor, root fallback. A tooltip needs the portal; a modal
needs both.

**`Component` is layout-transparent and identity-opaque.** It contributes no
layout node, consumes one cursor index, and its `@State` hangs off its own id.
Modifiers **distribute** to each top-level node (measured against SwiftUI,
CO-U), so a caller's `.width(70)` overwrites internal sizing and `.padding()` on
a single-`Text` component is inert (leaf box model, below). `.background()`
deliberately does not compile on one (use a `Box`); there is no `.id()` —
declare `var elementID`. `Deferred` and `List` reject a component. No
production caller yet (CO-Y).

**`@State` is a box seeded by reflection, per element per frame.** Slot ids
are `.named("$state<mirror-index>")` under the element's id. Seven reserved
names, none guarded: `$state<n>`, `$focus`, `$ax`, `$anim`, `$anim-color`, and
the prefixes `$anim-content`/`$anim-viewport` (`ScrollView`'s two nodes). A `List` datum
whose id describes to one of these collides. Seeding marks, so a declared,
unread `@State` is never swept. **A write marks the window dirty via
`StateTable.onWrite`; write from input, never from a phase** — a phase-time
`@State` write keeps the link awake forever. `@State` inside `AnyElement` is
inert (see the inert table).

**`@Observable` is a second dirty source: the whole frame build is tracked.**
Any model read in content, `requestLayout`, `prepaint` or `paint` is a
dependency. A private `RedrawSentinel` bounds the observer set (RX-K — the
spec's "re-register every frame is ideal" was wrong: observers accumulate one
per frame and there is no cancellation API). In `drawFrameIfNeeded` the flush
sits inside the dirty branch, precedes `needsRedraw = false`, and the sentinel
is read inside the tracked closure; the `isFlushing` guard and that ordering
are deliberately redundant and neither may go. `markDirtyFromObservation` has a
synchronous main-thread branch and a `Task { @MainActor }` hop; collapsing to
the hop dirties every frame, collapsing to `assumeIsolated` SIGTRAPs the suite.
**A phase-time `@Observable` write is the opposite failure from a `@State`
one: silently stale, the link pauses immediately** (observers install after
the closure returns). Same advice, two failure modes; unpinned by any test.

**One hitbox list; a scroll region is a hitbox with an axis.** Ranking is
`topmostOpaqueHitbox(in:at:)` — do not add a second copy. `onClick` is the
only thing that makes an element an opaque pointer target; the keyboard gate
(`onKey || isFocusable || actions || keyContext`) is separate and must stay
so, or focusable rows stop scrolling. Hover resolves once at the
prepaint/paint boundary. Handlers outlive the frame (`Window.lastHitboxes`), so
`.onClick { window.x() }` is a retain cycle — capture weak or capture state.

**`StyledElement` has four requirements — `style`, `decoration`, `elementID`,
`handlers`** — and a conformer must also call `registerHandlers` in its own
`prepaint` (nothing enforces it;
`onClickIsLiveOnEveryConformerThatCanRegisterOne` is the guard). `Handlers` is
not `Equatable`; `HandlerShape` in `ModifierTests.swift` must gain a field in
the same change `Handlers` gains a member — it has fallen behind twice.

**Focus: `Window.focus(_:)` is the only mover; clicking does not focus.** Keys
resolve against the `Keymap` first, then bubble raw `onKey` up the focused id's
parent chain; an unhandled `Action` does not claim the keystroke. Focus on an
unproduced element is retained through a `$focus` slot (needs one confirming
frame), so a dismissed subtree's ancestors keep claiming its keystrokes and
below-threshold retention is indefinite. Focus is drawn by `focusBackground`
token swap; nothing above the renderer can draw a border (`Frame.fill`
hard-codes zero widths). Focus outranks hover.

**Text.** Never key anything on a font family or PostScript name — `FontKey`
identifies the resolved `CTFont`. Min-content is the longest word from
`CFStringTokenizer`, not the typesetter (TX-F). `Text.paint` wraps at the width
layout measured (the retired divergence 8). Colour glyphs render as tinted
silhouettes. The glyph atlas is grow-only and silently drops glyphs when full;
`evictUnusedSince` has no caller and calling it would strand pixels.

**Renderer.** No semaphore on the live path; the atlas texture is written only
while `atlasTextureWasEncoded` is false, otherwise replaced — an invariant, not
a lock, pinned by `aDirtyUploadAfterEncodingReplacesTheTextureRatherThanWritingIntoIt`.
`Text.requestLayout`'s measure closure uses `MainActor.assumeIsolated` with no
guard and is sound only because `computeLayout` runs on the caller's thread;
moving layout off the main actor rewrites it first. The other two
`assumeIsolated` calls (`Window.markDirtyFromObservation`, the demo's
`atexit_b`) are guarded.

**Animation (M4 spec 3, Tasks 1–5 landed — production animates).**
`withAnimation` writes **two** slots with one value: `pendingTransaction`,
restored in its own `defer` and therefore alive only for the closure's lexical
duration, and `parkedTransaction`, which survives the closure **only if `body`
asked for a redraw** and is then taken by the next `Window.drawFrameIfNeeded`
and handed to the `Frame` as ambient `pass.transaction` (spec §3). **The park survives only if a frame build is
coming** — `Window.redrawRequests` moved across `body`, or
`Window.aFrameBuildIsPending` (a weak registry asking whether any live window
is dirty) was already true and the slot was free. Both halves
are fixes with measurements behind them: without the first, a
`withAnimation { if cond { … } }` with a false `cond` parked a transaction no
frame could consume and animated an unrelated change 400 s later; without the
second, `withObservationTracking`'s **one-shot** session meant the *second*
`@Observable` write between two frames moved no counter, so
`model.count += 1; withAnimation { model.width = 200 }` silently snapped. **The parked one is the whole hand-off**: until
Task 5 there was only the lexical slot, the frame build runs later from the
display link, and every field snapped — four wired sites, none of which could
ever start an animation (ruling V). Consumed by exactly ONE build. Spec §3 says
"on the `Window`" and it is a module-global instead, because `withAnimation`
has no window in scope; with two windows live the first to build wins.

One shared helper in `AnimatedStyle.swift` compares each registering site's
resolved `Style`/`Decoration` against the element's `$anim` slot and
substitutes interpolated values. **Colour is a second helper in a second
phase** (`AnimatedColor.swift`): only `PaintPass` has a theme, so `Box.paint`
animates the resolved result of its
`focusBackground`/`hoverBackground`/`background` `??` chain — one value, not
three fields — through a `$anim-color` slot, and hover and focus fades fall out
free. `Stack.paint` and `Text.paint` call the same helper on their plain
`decoration.background` (Task 5; `Text`'s glyph colour and its measured *style*
are still spec §8's holes). Interpolation is per-component **RGB, never hue**
(measured against SwiftUI and CoreAnimation probes; the encoding is
CoreAnimation's gamma sRGB, SwiftUI's is cube-root-of-linear and is recorded at
the line).

**One notion of "an animation is live", and it is not `wantsAnotherFrame`.**
Both helpers call `Frame.noteActiveAnimation()`; `Window` copies
`frame.hasActiveAnimations` after the whole render and the idle guard is
`needsRedraw || hasActiveAnimations`. It keeps the loop running **without**
dirtying the window, so a window mid-fade reports `needsRedraw == false`.
`Frame.wantsAnotherFrame` still means "mark the window dirty next frame" and
its one caller is `ScrollView`'s indicator fade; after Task 5 **nothing raises
both**, deliberately — two signals for one claim would have kept each other
green under mutation.

Constraints from its plan: no golden may move or be added, no
test may sleep (drive `simulateTick(timestamp:)`), `aspectRatio` must not
become animatable, no Reduce Motion / exit transitions / transforms.

## Practices — the short form

Read `docs/practices/verifying-tests-can-fail.md`; the rules below are the
ones that cost a round of rework each. History in record §02.

- **Findings come from mutation, not inspection.** Before committing a
  fixture, change the declaration it is named for, regenerate, confirm the
  numbers move — by running it, not predicting it. Require the arms of a
  comparison to **disagree** before believing they agree (shape 15).
- **A mutation that reddens nothing is a broken instrument or the finding**;
  prove the mutant behaves differently before banking a coverage gap. Name the
  tests a mutation reddens, not only the count; counts go stale by the end of
  the task.
- **Any count a later loop indexes on is `try #require`, not `#expect`**
  (shape 13: a wrong implementation truncated ~200 tests with no summary).
- **A `@testable` test cannot prove an access-level narrowing** (shape 16);
  use a plain-import typecheck guard.
- **Walk every measurement back to the mutated line in the same pass**, and
  when a claim is refuted, grep for everywhere it was copied — spec, plan,
  source comment, this file — not only where it was found.
- **Staleness is systematic: re-take the whole table**, not the rows a
  reviewer sampled. Silence in a review is scope not covered.
- **A confident "cannot" that was not measured is the tell** (shape 14).
- **Reviewer dispatches must say not to invoke the `code-review` skill**; a
  subagent reporting an "accidentally launched" agent is reporting a live
  process that may mutate `Sources/`. **Run mutation testing in an isolated
  `git worktree`** whenever another agent is live in the checkout; discard and
  re-take anything measured in a contended window.
- **Performance tests count work (tokenizer calls, cache entries), never wall
  clock**, are written first and must be red on arrival; measure on a
  branching tree, never a chain, and in a configuration where the code under
  test is reachable.
- **Write typecheck guards in the change that introduces the hazard.** The
  guard count and the suite count are independent.

## Human verification — what is closed and what stays open

Full entries, quoted reports and the standing scripts are in record §03.
Nothing in the suite can see paint order, portal hoisting, scroll direction,
drawable presentation, the display link, hover from a real `NSTrackingArea`,
or any of text's three §4.2 failure modes; these are looks.

| milestone | status |
|---|---|
| M0, M1 element pipeline, EP-8 centring, M2 text, clipping/scroll, Stack, absolute positioning (failures 1–2), measure performance (release), input/state, sizing | **closed** by a human look on the dated build |
| absolute positioning failures 3–4 (modal stays put while scrolling; wheel over scrim must **not** scroll the list — inverted since IN-W) | open |
| measure performance in **debug**; row missing/blank at the bottom edge; reaching row 500; launch hitch | not reported either way |
| tombstones-and-AX §7 item 9 (regression check; the demo cannot exercise its subject) | open, nobody has run the build |
| reactivity §8 item 7: run the demo, idle 30 s, press **M** twice, quit with **Q**, report `frames drawn` / `pauses entered` / `observation dirtyings` — a measurement, not a judgement | open |
| animation §9's "whether the motion looks right" (spec exit criterion 9) | open, and **not yet reachable**: the hand-off ships, but `grep -rn withAnimation Sources/` finds no caller outside `Animation.swift`'s own comments, and nothing animates without a transaction. Needs a demo interaction first — a key bound to a model property a `Box` declares as `width`/`background`, toggled inside `withAnimation`; the modal, theme and counter keys are all wrong subjects (appearance/disappearance snaps, a theme swap deliberately never fades, and text content is not animatable) |
| VoiceOver navigating the AX tree | permanently open until M4's bridge exists |

Demo keys: **M** modal (translucent scrim, gated so other looks stay
undimmed), **Space** theme, **F**/**Escape** focus the counter, **=**/**-**
count (context `"Counter"`), **Q** quit. The demo's sidebar shrinks below its
196pt declaration and WebKit does the identical thing (SZ-L); it is not a bug.
Dark-on-dark dimming is hard to judge by eye — measure a "no scrim" report
before believing it.

## Known divergences — expected, measured, not defects

Eleven entries; labels are stable ids. Retired and never reused: 3, 5, 6
(sizing, fixed), 7 (renumbering), 8 (`Text.paint` wrap, fixed), 12 and 17
(tombstones, closed for a **bounded** two-generation window above 256
entries). Full entries with repro and pins in record §04.

| # | kind | one line |
|---|---|---|
| 1 | vs oracle | Layer colorspace is Display P3; hex colours render more saturated. |
| 2 | vs WebKit | Flex §9.7.4.b sub-one scaling: spec and Blink say 50, WebKit says 100; engine follows the spec. No fixture encodes it. |
| 4 | vs CSS | An `auto` root axis takes the definite space offered instead of shrink-wrapping (CS-I); `.maxContent` gets CSS's answer. |
| 9 | vs CSS | All-`auto`-inset absolute box sits at its containing block's origin, not its static position (AP-F). |
| 10 | design | `Deferred` escapes every ancestor clip regardless of containing block; no way to ask for CSS's answer. |
| 11 | design | An absolute box inside a `ScrollView` is still clipped and scrolled by it (can draw nothing); the escape is `Deferred`. |
| 13 | `List` limit | Window computed against a one-frame-stale viewport extent; wrong for one frame on resize, bounded by 2 rows of overscan. |
| 14 | `List` limit | Window placed against the scroller's origin: a `List` with a flow sibling above it renders **blank**. Pinned wrong on purpose. |
| 15 | unfixed defect | A `ScrollView` inside a scrolled `ScrollView` gets an empty content mask (`pushClip` ignores `activeOffset`). One-line fix, deferred to a paint milestone; pinned wrong on purpose. |
| 16 | design | An `onClick` inside a `ScrollView` swallows the wheel over its rect. Fix named in `Window.applyScroll`'s doc (compare layers). Demo keeps its counter out of the list. |
| 18 | vs SwiftUI | `@State` behind a removed `if` is retained, not reset; indefinitely below 256 entries. Reset explicitly or keep the value in data. Element-level consequence is unpinned. |

## Declared but inert — verify, do not remember

The most likely bug here is an API that exists, compiles and does nothing.
When you implement one, delete its row; when you add a property you cannot
implement, add one. Full mechanisms and the grep for each row in record §05.

| declared | reality |
|---|---|
| `AlignItems.baseline` / `AlignSelf.baseline` | falls back to the start edge in flex and in `Stack`; needs baselines in the measure protocol |
| `aspectRatio`, `overflow` | zero reads (`overflow` has one write, in `ScrollView`, that nothing consumes) |
| `margin: .auto` | resolves to 0 on both axes; unreachable from modifiers, reachable via `Style` |
| `MUIRect.borderColor`/`borderWidths` | drawn by the shader, settable by nothing above the renderer; `borderWidth(_:)` shrinks the content box and paints nothing |
| `Position.relative`'s offset | makes a containing block, does not shift the box |
| `Style.alignSelf` on a `Stack` child | ignored entirely |
| `padding`/`border`/`margin` on a **leaf** (`Text`) | ignored entirely, including via a distributing `Component` modifier |
| `hidden()` on a subtree that draws or is focusable | layout filters it, paint does not: glyphs stack at the window's top-left; a hidden focusable still claims keystrokes. Use a builder `if` instead |
| `AnyElement` | works when hand-written; the builder never produces one and must not |
| `@State` inside `AnyElement` | silently inert |
| `PaintPass.isActive` | correct, pinned, consulted by no built-in element — nothing paints a pressed state |
| colour glyphs | tinted luminance silhouettes |
| `GlyphAtlas.evictUnusedSince`, `LayoutTree.reset(generation:)` | zero callers; guards kept for whoever calls them |
| `Frame.scrollRegions` / `Window.lastScrollRegions`, `StateTable.isDirty`, `StateTable.writeCount` | test observables with no production reader |
| `AXNode.children`, `AXNode.logicalCount`, `Frame.axNodes`/`axNode(for:)` | always empty / one writer no reader / built before the M4 bridge exists; `axNode(for:)` validity lags one frame |

## Performance — the numbers to reason from

Record §07 has the tables and machines. `computeLayout` is ~40 µs/node debug,
~5 µs/node release, flat 8k–88k nodes (content sizing's §4.5 automatic-minimum
probe multiplied it ~4.9x; whoever optimises starts there). The demo's warm
release frame is ~1.3 ms at 40 and at 500 rows; scrolling adds 0.1–0.3 ms. The
cold first frame builds every `List` row: ~76 ms release / ~188 ms debug at
500, ~17 s release at 100k — M3's "100k scrolls smoothly" is met for scrolling
and not for appearing. Identity path construction is ~0.4% of a frame. Hitbox
registration is ~0.01 ms.

## When CI lands

Three guarantees lapse silently and must be required, non-gateable jobs: the
ABI probe skips without a Metal device; `committedGoldensMatchTheBrowser` is
the only live-WebKit consumer; and every typecheck guard skips when `.build`
is not where `#filePath` resolution expects. The honest fix for the third is
resolving the modules directory from the test binary's own location.
