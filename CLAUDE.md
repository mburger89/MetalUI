# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written
as idiomatic Swift. **macOS only today** — `Package.swift` declares
`platforms: [.macOS(.v14)]`, `grep -rn UIKit Sources/ Tests/` returns zero
hits, and `App.swift:37` constructs `AppKitPlatform` unguarded. The platform
seam exists (`PlatformWindow`, `Platform`, `RenderSurface` — 17 requirements;
`PlatformWindow`'s `onAccessibilityRequest` and `publishAccessibilityTree(_:)`
have **no default implementations**, `AB-R`) but has no non-macOS conformer, and `InputEvent` has no `.touch` case. The
spec's §1 target of macOS **and iOS/iPadOS** is unmet, not delivered.

**This file is the rules. The reasoning, the measurements and the history live
in `docs/record/`** — `01`–`08` began as the pre-2026-09-09 `CLAUDE.md`
(4,172 lines, recoverable with `git show 6591360:CLAUDE.md`) split by section,
but they have been edited since and carry 2026-09-14 errata, so they are no
longer verbatim (`docs/record/README.md`). Their test names, ruling ids,
divergence labels and greps were **not** re-checked after the 79
SwiftUI-alignment commits (`a15ec83..7cfcddc`), which removed some (e.g. the
two `padding` `ModifierCase` rows) and changed others
(`Frame.computeRootLayout`); verify a citation before relying on it. When
something here is not enough, read the matching record file before
re-deriving it. New milestones append their record to `docs/record/` and put
only the rule here.

`AGENTS.md` is a byte-identical copy of this file for Codex. Edit `CLAUDE.md`,
never `AGENTS.md`, then `cp CLAUDE.md AGENTS.md`; nothing regenerates it
automatically (`.codex/` holds only session hooks), so check with `cmp
CLAUDE.md AGENTS.md` before committing.

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
  | `AN-` | animation (`AN-A`…`AN-W`, next is `AN-X`) | lettered |
  | `SA-` | SwiftUI alignment, native kernel completion (`SA-A`…`SA-U`, next is `SA-V`) | lettered |
  | `MC-` | modifier composition, plan task 3 (`MC-A`…`MC-S`, next is `MC-T`) | lettered |
  | `EV-` | environment and disabled state, plan task 9 (`EV-A`…`EV-Z`, next is `EV-AA`) | lettered |
  | `AB-` | accessibility bridge, plan task 12's bridge half (`AB-A`…`AB-AG`, next is `AB-AH`) | lettered |

  A bare `CS-3`, `TB-3`, `CO-3`, `AN-3`, `SA-3`, `MC-3`, `EV-3`, `AB-3` etc. is a typo, not a citation. Sweep
  for stray citations case-insensitively. The animation milestone (M4 spec 3,
  on `feat/animation`) is specced at
  `docs/superpowers/specs/2026-09-03-animation-design.md`, planned at
  `docs/superpowers/plans/2026-09-03-animation.md`, and its decisions doc is
  `docs/superpowers/2026-09-03-animation-decisions.md`. **Its `AN-` letters do
  NOT track its ledger's**, unlike `CO-A`…`CO-O`; that ledger lettered twice
  and half its rulings were about dispatch.
- **SwiftUI alignment (in progress; task 2's completion on
  `feat/kernel-completion`):** plan
  `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`, inventory
  `docs/superpowers/2026-09-12-swiftui-layout-replacement-inventory.md`, specs
  `specs/2026-09-12-native-layout-kernel-design.md`,
  `specs/2026-09-12-typed-modifier-composition-design.md` and
  `specs/2026-09-14-native-kernel-completion-design.md`. The two 2026-09-12
  specs describe types that were never built (`NativeLayoutEngine`,
  `LayoutContext`-threaded algorithms, `ModifiedElement`/`ElementModifier`);
  **the source is the authority**. Decisions doc (task 2's completion only,
  with per-ruling mutation records):
  `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`, prefix `SA-`.
  SwiftUI probes: `docs/probes/`, their headers carry the recorded output and
  how to run them (`SA-O`). The earlier range `a15ec83..7cfcddc` has no
  decisions doc and no mutation record. Record:
  `docs/record/09-swiftui-alignment.md`.
- **Tasks 3, 9 and 12 (three parallel tracks, integrated 2026-09-15 on
  `integrate/tasks-3-9-12`)**, each with a spec in `specs/`, a decisions doc
  in `docs/superpowers/` and a record file:
  - modifier composition (task 3, `MC-`): `specs/2026-09-15-modifier-composition-design.md`,
    `2026-09-15-modifier-composition-decisions.md`, record §10;
  - environment (task 9, `EV-`): `specs/2026-09-15-environment-design.md`,
    `2026-09-15-environment-decisions.md`, record §11;
  - accessibility bridge (task 12, `AB-`): `specs/2026-09-15-accessibility-bridge-design.md`,
    `2026-09-15-accessibility-bridge-decisions.md`, record §12;
  - the integration itself (merge resolutions, the interaction fix, the
    cross-track tests and the demo stand-in): record §13.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests. Sixteen numbered shapes of test that cannot fail, seven ways a
  record goes wrong, all observed here.
- **Full record:** `docs/record/README.md` indexes the sections; `01`–`08`
  are the split pre-2026-09-09 file, `09` is the SwiftUI-alignment record,
  `10`–`12` the task 3/9/12 tracks and `13` their integration.

## Build and test

```bash
swift build
swift test --no-parallel
# suite total — sums every "Test run with N tests" line (one on this machine today; six in earlier readings here, cause of the change unrecorded):
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc
# the env-gated 100k-row cold-frame test (~42 s debug / ~17 s release):
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
swift run MetalUIDemo            # and: swift run -c release MetalUIDemo
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # proposal-layout preview window (value must be exactly "1")
```

- **Counts, dated:** **1226 tests**, **97** browser-fixture goldens, **61**
  `swiftc -typecheck` guards, 0 `error:`, 0 `warning:` — measured 2026-09-15
  on `integrate/tasks-3-9-12` at `2456c69`, unfiltered `swift test
  --build-system native --no-parallel` after `swift build --build-system native
  --build-tests` (one summary line; only the two gated tests skipped), and again
  1226 / 0 / 0 under the default build system. Delta from 1084 / 97 / 45:
  **+142 tests** (composition +32, environment +49, bridge +57, integration +4),
  **0 goldens, +16 guards** (composition +8, environment +8); record §13.
  Guards per file: `PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
  `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6,
  `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `AXNodeTests` 3,
  `UnitSafetyTests` 2 (3 hits, one a comment), `ModifiedElementCompileGuards` 2.
  Before that: 1084 / 97 / 45 at `553b980` (2026-09-14, task 2). Before that:
  923 / 97 / 35 at `7f58db9` (2026-09-11). Earlier: 861 (47 + 448 + 50 + 6 + 288 + 22) on
  `feat/animation` at `b869253`; `master` at the Component milestone's end was
  811 / 87 / 34. **The per-target split is no longer printed on this
  machine** — SwiftPM now emits ONE summary line for the whole run, not six.
  A count is stale the moment a test lands; re-measure rather than trust.
  Two tests are gated and **count toward the total** while being skipped
  (`regenerateAllGoldens`, `aListsWorkIsTheSameFor100kRowsAsFor500`).
  **`--build-system native` prints ONE summary line, not six** — it read the
  same 861 — and its lone `warning:` is SwiftPM's own deprecation notice, not a
  compiler warning.
- **Read the printed counts, never the exit status.** Under the older
  per-target output the last summary line alone read 22 (`MetalUICoreTests`)
  on every healthy run.
- **Goldens must not move** on any change that does not touch
  `Sources/MetalUILayout/`; a moved golden means something reached the CSS
  engine. `find Tests -name "*.json" | wc -l` is the count. WebKit is the
  oracle **for the CSS engine only**. The proposal kernel's algorithms are not
  run by any golden, but they live in `LayoutTree.swift` and share its storage
  with the CSS engine — `newNode`, `reset(generation:)` (which now also clears
  `nativeNodes`) and `roundLayout` (`Rounding.swift`, called by both
  `FlexEngine.swift` and `roundNativeStoredRects`), plus the `SA-G`/`SA-I`
  preconditions in `newNode`, `appendNode`, `setStyle`, `reset` and (in
  `FlexEngine.swift`) `computeLayout` — so a proposal-path edit there **can**
  move a golden; run
  the fixtures. The corpus has **no text
  fixture and must not gain one** (ruling TX-B).
- **Guards:** count with per-file `grep -c canTypecheck` across
  `PhaseSeparationTests`, `ErasureCompileGuards`, `ElementGroupTrapTests`,
  `ProposalLayoutCompileGuards`, `ModifiedElementCompileGuards`,
  `ProposalNodeIDCompileGuards`, `EnvironmentCompileGuards`,
  `MetalUICoreTests/UnitSafetyTests` (one hit is a comment) and
  `MetalUITests/AXNodeTests`.
  `Tests/MetalUITestSupport/Typecheck.swift` also matches and holds only the
  declaration — count guards, not files. **Two helpers:** 40 guards (the 39
  older ones and one of `EnvironmentCompileGuards`') use
  `typecheck(_:importing:)`, which wraps the fixture in a function in
  Swift 5 mode, so every fixture type is local and no `public` or file-scope
  `extension` compiles; the other 21 — `ProposalLayoutCompileGuards`'
  six, `ModifiedElementCompileGuards`' two, `ProposalNodeIDCompileGuards`' six
  and seven of `EnvironmentCompileGuards`' — use
  `typecheckFile(_:importing:)` (whole file, `-swift-version 6`), pinned by
  its own instrument guard `typecheckFileChecksInTheSwift6LanguageMode`. A
  guard about what an **external module** can write uses `typecheckFile`
  (`SA-P`). Guards
  skip silently whenever `.build/<triple>/debug/Modules` is not where
  `#filePath`-relative resolution expects (`--scratch-path`, `-c release`,
  moved checkout): the total does not move and the run passes.
- **Adding an AppKit or WebKit test? Run the whole suite unfiltered.** All
  targets share one process and one main run loop; `--filter` is a different
  program. `AppKitWindow.init` sets `isReleasedWhenClosed = false` for this
  reason.
- **`swift package clean` when the impossible happens.** Two mechanisms: the
  shader header `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h` reaches
  its C target through a symlink SwiftPM does not track for changes
  (`Sources/MetalUIShaderTypes/include/`; git does track it, so a fresh
  `git worktree` gets it); and adding a case/stored property to a public type
  that crosses a module boundary leaves incremental builds disagreeing about
  layout — observed with `Scene` twice and `Display`, and a hazard again when
  `Scene`'s storage and `FontKey` (`MetalUIText` → `MetalUI`) changed on
  2026-09-10, both cleaned before testing (record §06). Turning a stored
  property on a public class into a computed one fails the incremental **link**
  instead (`Undefined symbols … direct field offset`; record §12). Symptoms: SIGSEGV or a
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
- **`.padding(_:)` and `.frame(width:height:)` on a legacy element return ONE
  flat `ModifiedElement<LayerBase>`** (`MC-A`). Each modifier appends a layer;
  each layer is one node and one id level. The outermost layer takes the
  parent's cursor slot, each inner layer is `positional(0)` (or its name) under
  the next one out, and the content numbers from 0 under the innermost layer
  (`MC-C`) — the path nested `Box`es produced. `.id()` names the layer it
  follows, so **`.id()` must still be the outermost modifier**
  (`anIDAfterAChainsLastWrapperNamesTheOutermostLayer`). Changing the layer
  COUNT resets the wrapped element's `@State`, focus, `$anim` and its
  accessibility element; changing a layer's VALUES does not. A layer added at
  run time is adopted by the new outermost layer, which keeps the old outermost
  id, `$anim` baseline, hitbox id and accessibility node (divergence 20). A
  stored type spells one level, `ModifiedElement<Text>`; the nested spelling
  does not compile (guard).
- **An `.overlay`'s primary numbers from 0 under the modifier's id; the overlay
  numbers from 0 under `.child(of: id, at: -1)`** (`MC-P`), so the overlay's
  state does not depend on the primary's shape, as in SwiftUI
  (`docs/probes/swiftui-overlay-primary-shape.swift`). No cursor produces `-1`;
  do not give it another meaning.
- `GlobalElementID.cachedHash` and `==` are safe alone and unsafe together; do
  not simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ above the engine
  (ruling EP-5); WebKit stays the oracle for the CSS engine itself.

**Containers.** `Column`/`Row` centre on the cross axis, `Box` stretches
(EP-8, set in the inits, not in `Style`) — so a childless `Box` with no cross
size paints nothing; declare a size or `.alignItems(.stretch)`. **Modifier
order now decides which box a modifier reaches**: since `.padding` adds an
outer layer, a container modifier written after it (`.alignItems`, `.gap`,
`.justifyContent`, `.background`) configures the one-child wrapper, and an item
modifier written before it (`.flexGrow`, `.alignSelf`, `.margin`) lands on
something that is no longer the parent's flex item. All of it compiles.
Chained `.padding` accumulates (4 then 8 pads 12,
`chainedPaddingCreatesNestedWrappers`); a `Self`-returning modifier after a
wrapper configures the outermost layer. `.frame(width:height:)` is a centring
flex container (a frame layer, `ModifiedElement.swift`'s `frame`,
`justifyContent = .center`) that sizes itself and does **not
stretch or impose** that size on its content: `Box().background(…)
.frame(width: 40, height: 40)` paints a 0×0 box (by reading; untested). Its
content box is still the child's available space, so a long `Text` or a
shrinkable child is bounded by the frame's width (flex-shrink down to
min-content; by reading). `Stack` layers
(`Stack.swift`; `Column`/`Row` live in `Flex.swift`), last child on top; its
paint order is invisible to every rect test. A `Stack` child's `auto` width is
fit-content against the stack, as a column item's cross size is (ST-H, TX-H);
its height is measured at that width. There is no `display: contents`.

**`List` is a windowed `Box`, not a container.** Four load-bearing
requirements: `Identifiable` data, a uniform `rowHeight`, an enclosing
`ScrollView`, and **being that scroller's only layout-contributing child** —
the last degrades to a blank list (divergence 14). Frame 0 builds every row
(MP-I: ~76 ms release at 500 rows, ~17 s at 100k). A row scrolled out for more
than two generations loses `@State` and focus once the table exceeds 256
entries (TB-AH); values a long scroll must keep belong in the data. Rows emit no
`axNodes`; while an accessibility client is active the `List` publishes an
`AXTable` whose `AXRowCount` is `logicalCount`, and each **realized** row a
`.row` with `AXIndex` = its logical index; rows outside the window are not
elements. **An unbounded window (no scroll context, a scroller with no measured
viewport, or `rowHeight <= 0`) publishes no rows**, and one inside a scroller
asks for one more frame, capped window-wide (`AB-L`, `AB-X`). Off-screen rows'
model reads are not tracked (RX-P, not a divergence).

**`Deferred` is a portal: one child, no layout node, hoists to the root layer
and resets clip and scroll offset together** (AP-I). No z-index. Absolute
positioning is separate: `.position(.absolute)` + `.inset(...)` against the
nearest non-static ancestor, root fallback. A tooltip needs the portal; a modal
needs both.

**`Component` is layout-transparent and identity-opaque.** It contributes no
layout node, consumes one cursor index, and its `@State` hangs off its own id.
Its `.padding`/`.width`/`.height` **distribute** to each top-level node
(measured against SwiftUI, CO-U; `StyledComponent`), so a caller's `.width(70)`
overwrites internal sizing, chained `.padding` replaces rather than
accumulates, and `.padding()` on a single-`Text` component is inert while that
leaf is content-sized (leaf box model, below). **The same spelling on an
ordinary element wraps and accumulates** — two meanings by receiver type.
`.frame(width:height:)` on a component wraps its body in one `ModifiedElement`
layer without overwriting its children
(`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`). A caller's
distributing modifier never animates (review finding B-7; see the Animation
section's snap list). `Component` itself has no `.background()` (use a `Box`)
and no `.id()` — declare `var elementID`. **Both holes have side doors, by
reading only (no typecheck guard):** `anyComponent.frame(width:height:)` returns
a `ModifiedElement`, a `StyledElement`, so `.frame(…).background(…)` compiles on
any component; and a component retro-conformed to `ProposalElementGroup` picks
up that extension's `.background(ColorToken)`, `.padding(Edges<Pixels>)`,
`.frame(…)` and the rest (`NativeModifiedContent.swift:187`), so on it
`.padding(Pixels)` distributes while `.padding(Edges<Pixels>)` wraps.
A `Component` over proposal content declares `some ProposalElementGroup`;
`some ElementGroup` does not conform to the marker (guard 3,
`ProposalNodeIDCompileGuards`).
`Deferred` and `List` reject a component. No production caller yet (CO-Y); the demo's opt-in
proposal preview has one (`PreviewToggle`, retro-conformed to
`ProposalElementGroup`).

**`@State` is a box seeded by reflection, per element per frame.** Slot ids
are `.named("$state<mirror-index>")` under the element's id. Seven reserved
names, none guarded: `$state<n>`, `$focus`, `$ax`, `$anim` and `$anim-color`
are slots; `$anim-content`/`$anim-viewport` are **id prefixes, not slots** —
`ScrollView` registers two nodes from one element id, so each gets a named
child and the `$anim` slot hangs off *that*, putting the value at a
**grandchild**. All seven are pinned apart by
`theSevenRetentionSlotsAreMutuallyDistinct`, one test extended in place three
times. A `List` datum whose id describes to one of these collides.
Seeding marks, so a declared,
unread `@State` is never swept. **A write marks the window dirty via
`StateTable.onWrite`; write from input, never from a phase** — a phase-time
`@State` write keeps the link awake forever. `@State` inside `AnyElement` is
inert (see the inert table). **`Element.prepaintGroup`/`paintGroup` re-bind
`@State`**, so the group entry's bind (`GroupMember.swift`'s
`enteringGroupMember`, the one helper the untyped default and both typed
defaults call, `MC-H`) is observable only by a LAYOUT-time read; a test of an
entry's bind must read during layout.

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
so, or focusable rows stop scrolling. `PrepaintPass.allowsHitTesting(false)`
(and the proposal `.allowsHitTesting(false)`) gates only `registerHandlers`'
pointer hitbox (`Frame.hitTestingDisabledDepth`); **scroll regions and raw
`insertHitbox` bypass it**, so a scroller inside still takes the wheel and the
topmost-opaque slot. Hover resolves once at the
prepaint/paint boundary. Handlers outlive the frame (`Window.lastHitboxes`), so
`.onClick { window.x() }` is a retain cycle — capture weak or capture state.

**`StyledElement` has four requirements — `style`, `decoration`, `elementID`,
`handlers`** — and a conformer must also call `registerHandlers` in its own
`prepaint` — that one call registers the hitbox, focus, a declared
`handlers.axNode`, AND, while an accessibility client is active, the element's
accessibility record; it is also where the disabled gate lives (nothing
enforces the call; skipping it makes the element ungated and invisible to
VoiceOver. `onClickIsLiveOnEveryConformerThatCanRegisterOne`,
`aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` and
`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` are the guards).
`ModifiedElement` has an inner-layer and an outermost-layer arm in every
per-site guard (`MC-I`). **Any hook added to `Element`'s group defaults
(`requestGroupLayout`/`prepaintGroup`/`paintGroup`) must be mirrored per layer
in `ModifiedElement`** (`MC-B`): a layer gets no group default of its own. The
one such hook today, `AB-O`'s `display: none` suppression, was missed by both
tracks and caught only by the merged suite (record §13). `Handlers` is
not `Equatable`; `HandlerShape` in `ModifierTests.swift` must gain a field in
the same change `Handlers` gains a member — it has fallen behind twice.

**Environment (task 9, `EV-`).** `EnvironmentScope` (`.environment(_:_:)`,
`.transformEnvironment`, `.disabled`, `.dynamicTypeSize`, `.theme`) is layout-
and identity-transparent: no node, no cursor index, no id, so a changing value
keeps the `@State` below it. Nearest writer wins; `.transformEnvironment`
composes with the inherited value; nothing cascades.
- A scope's transform runs **once per frame, in layout**; prepaint and paint
  re-push the stored result, so all three phases read identical values
  (`EV-V`). Its typed `requestProposalGroupLayout` is a copy of the untyped
  entry and pinned on its own (record §13).
- Every value is readable in every phase through `pass.environment`, so there
  is **no phase-only query and no `PhaseSeparationTests` guard** — except
  `theme`: `PaintPass.theme` only, unreachable through any public key path,
  `\.self` included.
- `@Environment` is bound like `@State`, by reflection, per element per phase,
  to a snapshot; unbound it reads `EnvironmentValues()`'s defaults silently
  (locale `''`); inside `AnyElement` it is inert. A type declaring it must be
  main-actor isolated (every `Element` and `Component` is).
- `Window.environment` is the root. **Every write dirties, a no-op included**
  — write from input, never from a phase. `theme` and `pixelLength` are
  re-stamped from `Window.theme` and the surface scale, so writing either
  through `window.environment` or `rootEnvironment` does nothing.
  `Frame.rootEnvironment` traps if set during `render` (`EV-Z`). A `Frame`
  built without a window roots at `EnvironmentValues()` (locale `''`); `Window`
  stamps `Locale.current` (pinned, `EV-Y`).
- **A modifier written after a scope sits outside it** (`EV-X`), on both
  paths: `.disabled(true).frame(…).onClick {}` fires, and a proposal
  `.padding`/flexible frame/`.onTap` after a scope paints and registers with
  the enclosing values (`aProposalModifierWrittenAfterAScopeSitsOutsideIt`).
  Over legacy content `.padding` and handler modifiers do not compile directly
  on a scope. A `Deferred` inside a scope keeps its declaring scope's values.

**`.disabled(d)` is `transformEnvironment(\.isEnabled) { $0 = $0 && !d }`** — a
raw `.environment(\.isEnabled, true)` overrides it, and the gate reads the
value, not the modifier (`EV-D`). **One gate, in `Frame.registerHandlers`'
5-argument implementation** (the 3-argument overload is a bare forward: `Text`
and `OnTapModifier` reach the 5-argument one directly, so a gate in the
3-argument method leaves them ungated). A disabled element registers **no
hitbox** (neither hovered nor pressed; its click reaches an enabled ancestor or
an enabled sibling under it), **nothing in the focus registry** (no
`isFocusable`, `actions`, raw `onKey` or `keyContext`), no `$focus` slot, and
its declared AX node gains `.disabled`. For an accessibility client it is still
published — presence and role read the ungated `handlers` — with
`isEnabled` false and no actions, and every request is refused
(`aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`).
A click needs the target enabled at press and at release. **Scroll regions are
outside the gate**: a `.disabled` `ScrollView` still scrolls on the wheel
(`aDisabledScrollViewStillScrollsOnTheWheel`; SwiftUI unmeasured, `EV-Q`). A
site that registers handlers without that method is ungated with no diagnostic;
a new site gains an arm in the D2 guard in the same change. `KeyBinding` is the
keymap's type; `Binding` is a deprecated alias that plan task 10 deletes **in
the change that introduces a SwiftUI `Binding`**.

**Accessibility is a tree pushed through a two-requirement seam, and it costs
nothing without a client** (task 12's bridge half, `AB-`).
- Nothing is recorded until a client activates the window — a host-view query
  **other than** the focused-element query, or VoiceOver running (`AB-B`) —
  and activation is sticky. An inactive frame pays, by reading, a `Bool` read
  and one `handlers.axNode` copy per `registerHandlers` call and a few `Bool`
  stores per frame and per `List` (`AB-M`).
- **Synthesized nodes are records (`Frame.axEmissions`), never `Frame.axNodes`
  and never a `$ax` slot** (`AB-U`); only declared nodes
  (`accessibilityLabel`/`accessibilityValue`, `List`) emit, every frame, client
  or not.
- **Geometry is not structure** (`AB-K`): an animation tick publishes geometry
  only, posts nothing and touches no element; do not compare frames in
  `hasSameStructure`.
- Elements are created only when a client reads them, one per id while
  published, detached on first absence and never revived (`AB-D`, `AB-X`);
  notifications post only for vended elements, `.layoutChanged` once per client
  read.
- **Every `NSAccessibility` override is nonisolated in practice** (`AB-AE`):
  answer through `mainActorAnswer(_:fallback:_:)`, never a bare
  `assumeIsolated`; its `-typecheck` probe proves nothing, compile to SIL.
- A press runs `onClick` through the last frame's hitboxes, so it is refused
  under `allowsHitTesting(false)` and when disabled; `onTap` publishes nothing
  but still presses (`AB-H`, `AB-Y`). Increment/decrement are the
  `AccessibilityAdjustment` action. Focus is `Window.focus` only; nothing
  focused reports the host view (`AB-J`).
- Hit testing ranks `(layer, order)` on the **clipped** `visibleFrame`,
  half-open, as click dispatch does (`AB-W`); `accessibilityFrame()` is the
  **unclipped** frame converted at read time (`AB-E`).
- Labels: a plain container or wrapper **distributes** its label and value to
  its children, outer declaration winning; a click target is a button that
  folds its non-interactive descendants' texts, joined `", "`; a focusable or
  adjustable labelled container keeps its node (`AB-F`, `AB-G`, `AB-T`).
- A conformer that paints text passes `accessibleText:` through the internal
  `registerHandlers` overload, or it is silent. A layer with `display: none`
  suppresses everything inside it — one check,
  `Frame.suppressingAccessibilityIfHidden`, called by `Element.prepaintGroup`
  and by each inner `ModifiedElement` layer (`AB-O`, `AB-AD`, record §13).
- `AccessibilityRequest` is ambiguous in any file importing `AppKit`; qualify
  it (`MetalUIPlatform.AccessibilityRequest`) until renamed.

**Focus: `Window.focus(_:)` is the only mover; clicking does not focus.** Keys
resolve against the `Keymap` first, then bubble raw `onKey` up the focused id's
parent chain; an unhandled `Action` does not claim the keystroke. Focus on an
unproduced element is retained through a `$focus` slot (needs one confirming
frame), so a dismissed subtree's ancestors keep claiming its keystrokes and
below-threshold retention is indefinite. Focus is drawn by `focusBackground`
token swap. `PaintPass.fill` now takes `borderColor:`/`borderWidths:` (the
proposal `.border` uses them), but no legacy element or focus path passes a
border. Focus outranks hover.

**Text.** Never key a glyph, shape or metrics cache on a font family or
PostScript name — `FontKey` reads its four components (PostScript name, size,
variations, matrix) off the **resolved** `CTFont`. Those four do **not**
identify shaping behaviour: `Text(s)` and `Text(s).font(family: "System Font",
size: 13)` produce equal keys, are not `CFEqual`, and shape Arabic, Devanagari,
CJK and emoji to different widths, so `ShapingCache` serves whichever shapes
first to both (`font(for:)` returns the last registration). Nothing in
`Sources/` spells that name; unfixed, pinned wrong on purpose by
`twoRequestsWithEqualFontKeysShareOneShapeThoughTheyShapeDifferently`. The one
request-keyed map is `ShapingCache.resolveFont(family:size:)`'s memo
(`resolvedFonts`), which caches the resolution itself; it and `fonts` are never
swept, deliberately (see `fonts`' doc comment), and the two must move into
`endFrame()`'s sweep together if either ever does. `FontResolver.resolve` traps
on a size that is not finite and positive: CoreText otherwise substitutes 12 or
13pt, or keeps a NaN that makes `FontKey` unequal to itself. `FontKey` stores
its hash (`precomputedHash`, computed once in `init(resolved:)`) and `==`
compares all four components with that hash as an early reject only —
`GlobalElementID`'s pair, safe alone and unsafe together. Unlike
`GlobalElementID` it is guarded: `aForgedHashCollisionIsSettledByTheComponents`
forges a collision per component and is the only test that sees an `==`
answering from the hash. To force collisions under mutation, make the **stored**
hash constant, not `hash(into:)` — `==` reads the stored `Int`, so a constant
`hash(into:)` proves nothing. Min-content is the longest word from
`CFStringTokenizer`, not the typesetter (TX-F). The min-content miss path
re-points ONE `@MainActor` tokenizer
(`Shaper.unbreakableRunsReusingTokenizer(of:)`); the public
`unbreakableRuns(of:)` is nonisolated and must keep creating one per call,
since a `CFStringTokenizer` is not thread-safe. Both bump
`Shaper.runCallCounter`; a path that skips the bump turns the warm-frame and
160-vs-40 count tests into `0 <= 40` and `0 == 0`. Max-content is one line per
**hard** line break, not one line (TX-K): `Shaper.shape(_:font:wrappingAt:)`
with a `nil` width is the typesetter loop at `+infinity`, byte-identical to a
whole-string `CTLine` for break-free text; a finite stand-in width soft-breaks
a long string. `Text.paint` wraps at the width
layout measured (the retired divergence 8). Colour glyphs render as tinted
silhouettes. The glyph atlas is grow-only and silently drops glyphs when full;
`evictUnusedSince` has no caller and calling it would strand pixels.

**Renderer.** No semaphore on the live path; the atlas texture is written only
while `atlasTextureWasEncoded` is false, otherwise replaced — an invariant, not
a lock, pinned by `aDirtyUploadAfterEncodingReplacesTheTextureRatherThanWritingIntoIt`.
Two measure closures use `MainActor.assumeIsolated` with no guard —
`Text.requestLayout` (`Text.swift:237`) and `ProposalText`'s
(`ProposalText.swift:49`) — sound only because `computeLayout` and
`computeNativeLayout` run synchronously on the caller's thread; moving layout
off the main actor rewrites both first. The other two `assumeIsolated` calls
(`Window.markDirtyFromObservation`, the demo's `atexit_b`) are guarded.

**Animation (M4 spec 3, complete — production animates; decisions doc `AN-`).**
`withAnimation` writes **two** slots with one value. `pendingTransaction` is
restored in its own `defer` and so is alive only for the closure's **lexical**
duration; `parkedTransaction` is **the whole hand-off** — taken by the next
`Window.drawFrameIfNeeded` and handed to the `Frame` as ambient
`pass.transaction`, consumed by exactly ONE build. Until Task 5 there was only
the lexical slot: the frame build runs later, from the display link, so every
field snapped and all four wired sites were unreachable while every test passed
(they call the helper *inside* the body — a shape production cannot reach).

**The park is rolled back unless a frame build is coming: the counter moved, or
one was already pending and the slot was free.** Both clauses are fixes with
measurements behind them. Without the first, `withAnimation { if cond { … } }`
with a false `cond` parked a transaction no frame could consume and animated an
unrelated change **400 s later**. Without the second,
`withObservationTracking`'s **one-shot** session means the *second*
`@Observable` write between two frames moves no counter, so
`model.count += 1; withAnimation { model.width = 200 }` **silently snapped** —
a legitimate animation discarded, invisible to all 860 tests then passing.
`Window.aFrameBuildIsPending` asks a weak registry of live windows. Spec §3
says "on the `Window`"; it is a module-global instead, because `withAnimation`
has no window in scope — with two windows live the first to build wins.

**Two helpers, two phases, nine registering points.** `AnimatedStyle.swift`'s
`animated(_:_:for:pass:)` runs in `requestLayout` and compares the resolved
`Style`/`Decoration` against the element's `$anim` slot. **Colour is a second
helper in a second phase** (`AnimatedColor.swift`), because two `ColorToken`s
interpolate through their theme-resolved `Hsla` and **only `PaintPass` has a
theme**. Layout sites: `Box`, `Stack`, `ScrollView` ×2, `ModifiedElement`
(one `animated` call per layer).
`Component` is not a site (it contributes no node);
`everyRegisteringSiteAnimatesItsStyle` carries a `Component` arm whose control
half animates and whose caller-modifier half is pinned wrong on purpose. Paint
sites: `Box.paint`, `Stack.paint`, `Text.paint`, `ModifiedElement.paint` (the
outermost layer's `animatedBackground` and the inner layers'). Of the thirteen
library `pass.fill` sites five animate (`ModifiedElement.paint` holds two); the
other eight never animate: the two scroll indicators (drive themselves by
dirtying) and the six proposal-path fills.
A site that skips its helper is silently unanimated with no diagnostic; the two
per-site guards are `everyRegisteringSiteAnimatesItsStyle` and
`everyBackgroundPaintingSiteAnimatesItsColour`; both carry `ModifiedElement`
inner- and outermost-layer arms, and deleting either layer's `animated` or
`animatedBackground` reddens them (record §10, mutations I1, I2, V1, V11).
Neither of those guards can see
the hover/focus chain: the colour guard's arms declare no `onClick` or
`focusable()`. The chain is pinned per site by
`everyBackgroundPaintingSiteHonoursHoverAndFocus` and
`everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`
(`BackgroundChainTests.swift`), whose arms are genuinely hovered and focused
through a real `Window`.

`animatedBackground(_:for:pass:)` (`AnimatedColor.swift`), called by all four
background sites — `Box.paint`, `Stack.paint`, `Text.paint`,
`ModifiedElement.paint` — resolves the
`focusBackground`/`hoverBackground`/`background` `??` chain and animates the
result — **one value, not three fields**. Until 2026-09-10 the chain lived in
`Box.paint` alone, so both modifiers compiled on `Stack` and `Text` and painted
nothing. **Hover and focus fades use that same path for free, but the
PATH is the only free half: nothing parks a transaction around pointer-move
handling**, so a colour change with no live transaction takes the snap branch
and a real hover fade needs a framework change. Interpolation is per-component
**RGB, never hue** (SwiftUI and CoreAnimation probes both; the encoding is
CoreAnimation's gamma sRGB — SwiftUI's is cube-root-of-linear and taking it
would mean linearizing, against §7.8). Slot storage is **tokens**, so a theme
swap mid-fade stays continuous. `Text`'s glyph colour and its measured *style*
are still spec §8's holes.

**One notion of "an animation is live", and it is not `wantsAnotherFrame`.**
Both helpers call `Frame.noteActiveAnimation()`; `Window` copies
`frame.hasActiveAnimations` **after the whole render** — layout *and* paint, or
a fade on a style-static element stops the instant input stops — and the idle
guard is `needsRedraw || hasActiveAnimations`. It keeps the loop running
**without** dirtying the window, so a window mid-fade reports
`needsRedraw == false`. `Frame.wantsAnotherFrame` still means "mark the window
dirty next frame" and its two callers are the `ScrollView` and
`ProposalScrollView` indicator fades; **nothing
raises both**, deliberately — two signals for one claim would have kept each
other green under mutation.

**What snaps rather than animates:** any transition between two different
`Dimension`/`Length` cases (`px → rem`, `px → pct`, and **anything touching
`.auto`**). Five `Style` fields default to `.auto` — `inset`, `size`, `minSize`,
`maxSize`, `flexBasis`, which is **11 of the 28 animatable keys** — so **their
first transition snaps**; declare a real baseline value if it must animate.
**A caller's modifier on a `Component` always snaps, whatever the cases**
(review finding B-7): `MyComponent().width(196)` → `.width(320)` inside
`withAnimation` reads 320 at t = 0 and t = 0.5, where the same width declared
*inside* the component reads 196 then 258. `StyledComponent` amends node styles
after each member's `animated(_:_:for:pass:)` has stored its `$anim` baseline,
and it cannot reach that slot until `ElementGroup` gains the associated type
ruling TB-M names. To animate a component's size, declare it inside the
component. Pinned wrong on purpose by `everyRegisteringSiteAnimatesItsStyle`'s
`Component` arm. `.frame(width:height:)` is not a distributing modifier: it is
its own `ModifiedElement` layer with its own `$anim` slot, so by reading it
animates on a component too (no test drives it).
**Everything on the proposal path snaps**: no `HStack`/`VStack`/`ZStack`,
`ModifiedContent` wrapper, `Background`, `Rectangle`, `Color`, `ProposalText`
or `ProposalScrollView` calls either helper.
`Style.aspectRatio` is deliberately never animated (it is inert; see the table).
Constraints from its plan: no golden may move or be added, no test may sleep
(drive `simulateTick(timestamp:)`), no Reduce Motion / exit transitions /
transforms.

## SwiftUI alignment — the proposal layout path (in progress)

The plan intends to replace the CSS engine; today a SwiftUI-style
propose/measure/place engine and API sit **beside** it. Record §09; task 2's
completion rulings are `SA-` (decisions doc above).

**Two layout authorities, chosen by the window root alone.**
`Frame.computeRootLayout` checks only `tree.isNativeLayoutNode(root)` (its doc
comment still says "runs the flex engine"). A native root runs
`LayoutTree.computeNativeLayout(root:proposal:in:)` with the content size as
proposal and the window rect as bounds, **discarding the root's measurement**:
the root is stored at the full window
(`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`, an overlay
root) and a root stack packs from the leading edge rather than centring
(`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`: a 58pt
`HStack` root in a 100pt window puts its trailing item at x = 28). The
kernel is a private `NativeNode` enum in `LayoutTree.swift`: eleven built-in
cases, which stay cases, plus `custom(any ProposalLayout)` (`SA-B`). Each
native node still appends a placeholder `Style.default` row to the legacy
arrays, through the private `appendNode`. Rounding is the legacy
`roundLayout`, cumulative-edge.

**`ProposalLayout` is the public algorithm protocol** (`SA-A`…`SA-F`):
`sizeThatFits(proposal:subviews:)` and `placeSubviews(in:proposal:subviews:)`,
`Sendable`, no cache. Register it with `newNativeLayout`/`requestNativeLayout`
or `ProposalLayoutContainer(layout) { … }` (also `MyLayout { … }`).
- **Measurement cannot place.** `MeasurementSubview` has no `place`, and no
  proxy can be constructed publicly; both are compile-time. A stashed
  `PlacementSubview`'s `place` traps outside its own `placeSubviews` or during
  any measurement body; its `priority`, `isSpacer` and `sizeThatFits` check
  only that the run is live. Any proxy traps after its run ends.
- **`place(at:anchor:proposal:)` only records.** After `placeSubviews`
  returns, each subview is stored at its answer to the recorded proposal, and
  its subtree is placed once, in index order. The last record wins. An unplaced
  subview is centred at the parent's proposal.
- **Proxies expose `priority`, `isSpacer` and a cached `sizeThatFits`**, each
  by the built-in stack's own rule.
- **Migration** (`SA-F`, under `SA-R`'s amended criterion; every registrar
  now returns `ProposalNodeID`):
  - a leaf uses `requestNativeLeaf`;
  - an algorithm uses `ProposalLayout`;
  - a container with its own paint or input uses `requestGroupLayout` +
    `requestNativeLayout`;
  - a legacy root is unchanged, and nothing legacy is deprecated.
- **Sufficiency.** The plain-import `ReferenceLinearStack` must match the
  built-in stack's rects. It proves the **horizontal** path only (verifier
  mutation F1).

**One layout authority per root, no adapter** (`SA-G`). Each of these traps:
- a native node under a legacy node;
- a legacy node under a native registrar;
- a `Style` written onto a native node (a legacy style modifier on a proposal
  `Component` reaches this);
- `computeLayout` on a native root.

Migration is root by root. **`ProposalElementGroup` has one requirement**,
`requestProposalGroupLayout(under:at:pass:) -> ([ProposalNodeID], GroupLayout)`,
and `ProposalNodeID`'s initializer is internal (`MC-G`, delivering `SA-R`). An
element conforms as a `ProposalElement` writing
`requestProposalLayout(_:pass:) -> (ProposalNodeID, LayoutState)`, and the
native registrars take and return `ProposalNodeID`. Five lies are compile
errors, each guarded (`ProposalNodeIDCompileGuards`). **Seven holes stay**
(`ProposalNodeID.swift`'s header): two entry points can disagree; a legacy node
or subtree registered on the side of a typed entry is not rejected;
`unsafeBitCast` or `@testable` can mint an id; one id used twice does not trap;
a legacy style modifier on a proposal `Component` compiles, then traps; an id
stored from an earlier frame traps (C-3). **A precondition closing the orphan
or duplicate hole truncates the suite** unless its pinning test becomes an exit
test first. **The builder groups' typed entries are line-for-line copies of the
untyped ones** (and so is `EnvironmentScope`'s), each pinned on its own; a new
group gets its own pin.
Single-child proposal wrappers (`ProposalFrame`, `Padding`, `Background`,
`FixedSize`, `ModifiedContent`, both `.overlay` slots, `OnTapModifier`)
precondition exactly one node, so `ProposalFrame { if flag { … } }` traps when
`flag` is false. `ProposalScrollView` lowers zero children to an empty stack.
`EitherGroup` does not conform. The overlay's `overlay:` argument has no
negative guard.

**Invalidation** (`SA-H`, `SA-I`).
- **The cache lives for one call.** It sits in a `NativeLayoutRun` for one
  `computeNativeLayout` or `measureNativeLayout` call, so every frame
  re-measures every native leaf. SwiftUI's memo survives passes; that
  divergence is deliberate, and it reopens only with a work count.
- **Answers are assumed pure.** A layout's answer must depend only on its
  value, its proposal and its subviews' answers; nothing detects a violation.
- **`setLayout` traps during a measurement body.** A rect written from
  `placeSubviews` is not checked.
- **One `isLayingOut` flag guards both engines; do not split it.** While either
  engine runs, `setStyle`, every registration, `reset` and re-entry all trap.
  `measureNativeLayout`'s bracket is unpinned.

**Validation** (`SA-J`, `SA-K`).
- **The rule.** Reject a parameter, with a `precondition` naming it, only if
  SwiftUI rejects it (a diagnostic, a trap, a hang, or no spelling), or if it
  would make the node non-finite at a proposal with no infinite axis.
- **Accepted as SwiftUI accepts them:** negative spacing, negative padding
  (the response clamps at 0 per axis), a negative frame minimum, a +∞ maximum,
  a negative `minLength`, ±∞ priority, a negative ratio, and any non-NaN
  proposal.
- **Three checkpoints.** A measurement may be infinite, a stored rect may not,
  and nothing may be NaN.
- **The proposal frame is split** into SwiftUI's fixed and flexible spellings,
  and combining them does not compile.
- **Relaxing a trap into a clamp later is additive.** The reverse breaks
  callers.

**Depth guard** (`SA-L`). `NativeLayoutRun.maxDepth` is **88 native nodes**,
one counter across measurement and placement. It is 0.60 of the smallest debug
ceiling on a 1 MB thread, rounded down to a multiple of 8. It is not
`LayoutContext.maxDepth` and claims no parity with it. Raise it only after
re-bisecting all four node kinds.

**Work counters** (`SA-M`). Count native work with the internal
`LayoutTree.lastNativeLayoutWork` (`measureCalls`, `cacheHits`,
`cacheMisses`, assigned per call). Use a branching tree, and compare against
literals derived by hand before the run.

**Unpinned sub-clauses, found by verifier mutations that stayed green** (record
§09):
- the `measureDepth` bracket around built-in bodies;
- `measureNativeLayout`'s flag, active run and work record;
- padding's right inset;
- checkpoint 2's height and `lastBaseline`, and checkpoint 3's rect height.

**Vocabulary.** Proposal types (`MetalUI`): `HStack`/`VStack(spacing: 8,
alignment: .center)`, `ZStack`, `Spacer(minLength:)`, `Rectangle(color:)`
(proposal-responsive) and `Rectangle(width:height:color:)` (fixed), `Color`,
`ProposalFrame` (not `Frame`: `public final class Frame` exists), `Padding`,
`Background`, `FixedSize`, `ProposalScrollView`, `ProposalText`. Modifiers on
`extension ProposalElementGroup` return `ModifiedContent` over a closed
`LayoutModifier` enum — `.frame(width:height:alignment:)` and
`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`,
`.padding(Edges<Pixels>)`, `.fixedSize`, `.background`,
`.clip(cornerRadius:)`, `.border`, `.opacity`, `.allowsHitTesting`,
`.aspectRatio(_:contentMode:)`, `.layoutPriority` — plus `.overlay` and
`.onTap(hoverColor:)`; `ProposalLayoutContainer` carries a custom layout.
Kernel types (`MetalUILayout`): `ProposedSize`, `LayoutMeasurement`,
`ProposalAlignment` (nine), `ProposalStackAxis`, `AspectRatioContentMode`,
`ProposalMeasureFunction`, `ProposalLayout` and its four proxy types. **The
`Native…` types and `native…` modifier methods are deprecated aliases** — 26
`@available(*, deprecated` hits: 17 typealiases (14 in `MetalUI`, 3 in
`LayoutTree.swift`) and 9 methods — except the two `nativeFrame(...)`
overloads, live undeprecated duplicates of `.frame` used by six test call
sites; deprecating them breaks the 0-warning baseline. **The kernel's own
`Native` names are not aliases and are not deprecated**: the 12
`LayoutPass.requestNative*`, the 12 `LayoutTree.newNative*` (each set
including the custom-layout registrar), `computeNativeLayout` and
`isNativeLayoutNode` are the primary API. Shared spellings
resolve by receiver: `.frame(width:height:)` on a proposal value picks the
proposal overload (`proposalLayoutFrameUsesTheTypedProposalWrapper`), on
anything else `ModifiedElement`; `.background(ColorToken)` exists on both
`StyledElement` and `ProposalElementGroup` and is unambiguous only because no
built-in type is both; `.padding` splits by argument type (there is no proposal
`.padding(Pixels)`).

**`Text.proposalLayout()`** returns a `ProposalText` carrying only the string,
font family/size and foreground colour — a background, handlers, `elementID`
and hover/focus colours are **silently dropped**. It measures by
`shaped(wrappingAt: proposal.width)` (no tokenizer min-content), reports no
baselines, and paints wrapped at `measuredWidth`, whose native recording no
test pins.

**`ProposalScrollView` vs `ScrollView`.** `ProposalScrollView` measures content
with the scrolling axis unspecified, reports each finite proposal axis, and
shares `ScrollView`'s wheel routing (`registerScrollRegion`, `ScrollState`
under its bare id). Its prepaint clamp and its indicator (alpha fade,
`requestAnotherFrame`, thumb maths, clip) are **private copies**
(`ProposalScrollView.swift:93-165`), so a fix to `ScrollView`'s does not reach
it. It takes `elementID:` in its
init, has no `$anim-content`/`$anim-viewport` nodes and never animates;
multiple direct children lower to a **vertical** stack at spacing 8 on either
axis. `ScrollView` is unchanged and remains `List`'s only scroller. Divergence
16 applies to `.onTap` inside a `ProposalScrollView` (by reading).

**Probe-backed values.** SwiftUI macOS probes. **The values in this list have
no saved probe source** (prose in the plan and in test doc comments only), so
none can be re-run, and most record no positive control. Task 2's completion
committed two re-runnable probes, `docs/probes/swiftui-layout-protocol-contract.swift`
and `…-input-validation.swift`, with positive controls; they back the `SA-`
rulings above and `SA-N`'s findings below, not this list.
- `HStack`/`VStack` default spacing 8 — a hard-coded constant, probed for one
  view pair (`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
  `vStack…`); `ProposalScrollView` direct children 8pt vertical on both axes
  (`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`).
- `Rectangle()`/`Color` answer 10pt on an unspecified axis and the offer on a
  concrete one (`rectangleUsesSwiftUIShapeProposalSizing`) — including
  `.infinity` for an infinite offer.
- A frame's `ideal` on an unspecified axis reports `clamp(ideal, min, max)`
  (`anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `…Height…`).
- Priority, only when the stack overflows and has no spacer: descending groups
  take their natural sum if it fits, else equal shares of the rest, and lower
  groups get 0; shares are not redistributed (80/20 and 50/50:
  `hStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling`,
  `hStackDividesAConstrainedProposalAmongEqualPriorityFlexibleChildren`).
- `Spacer(minLength:)` is a floor even when the stack overflows
  (`spacerMinimumLengthSurvivesAConstrainedStackProposal`).
- `.aspectRatio` fit/fill at 100×80 on 2:1 → 100×50 / 160×80
  (`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`, `…Fill…`);
  the two-axis branch at zero and negative axes is probed (P8c) and pinned
  (`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`); the
  single-axis branch is unpinned.

**Probed, and the kernel disagrees** (`SA-N`; owned by later tasks):
- a finite-`maxWidth` frame grows to the proposal in SwiftUI: min 40 / max 80
  at 100 around a 20pt child answers 80, the kernel 40
  (`aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`; task 4);
- `Spacer()` has an 8pt default minimum between two views; the kernel's `nil`
  is 0 (task 6);
- `aspectRatio` at nil×nil answers the child's own size; the kernel's
  intrinsic branch does not (task 7);
- padding places its child at the child's own size; the kernel stores bounds
  minus insets, pinned wrong on purpose (task 5);
- a single-child stack passes its child's priority through (task 6);
- argument-less `.frame()` compiles; SwiftUI deprecates it (task 4).

**Unprobed kernel behaviour that fails silently** (by reading):
- Only a type-recognised `Spacer` (bare or under any depth of `.layoutPriority`) takes
  surplus: two `Color`s in a 100pt `HStack` are 10pt each, `.frame(maxWidth:
  .infinity)` in a stack does not expand (stack children get a nil main
  offer), a padded or framed `Spacer` loses its flexibility, and a stack with
  any spacer never compresses. A `Spacer` also claims the proposed cross axis.
- A stack measures children at a nil main axis but places them at their
  allocations, so wrapping text can outgrow the height the stack reported.
- `.opacity` out of 0…1 traps at **paint**, not at registration (outside
  `SA-J`'s scope).
- No built-in proposal type or modifier wrapper has `.id()`; only
  `ProposalScrollView` takes an id, so the trailing-sibling remedy cannot name
  a built-in proposal element. A custom element or `Component` conformed to
  `ProposalElementGroup` can still declare `var elementID` (the demo's
  `PreviewToggle` does, `main.swift:892`). `@State`
  binds, but no built-in proposal element declares any; `.onTap` is the only
  pointer handler (hover via `hoverColor`); nothing is focusable, handles keys
  or emits an AX node, and nothing publishes to accessibility — `onTap` still
  presses (`AB-Q`, `AB-Y`). `.onTap` has no positive dispatch test.

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
  test is reachable. Heap allocations are countable too:
  `FreezeLoopAllocationTests.swift` counts them on the calling thread through
  libmalloc's `malloc_logger` hook, and calibrates the counter against known
  buffers before believing a zero. Take such counts in the configuration the
  suite runs: a debug build allocates per element inside closure-taking stdlib
  algorithms (`reduce`, `contains(where:)`) over large structs, and `-O` does
  not.
- **Write typecheck guards in the change that introduces the hazard.** The
  guard count and the suite count are independent.
- **A copy of a pinned implementation is unpinned.** Mutate each copy on its
  own. Three typed builder-group entries left the whole suite green (`MC-H`,
  P2–P4) until each had its own test.
- **Parallel tracks each owe tests for the merge, and only the merged suite
  runs them.** Merge red first where a track wrote such a test; the
  `AB-O` × `ModifiedElement` interaction was invisible on both branches
  (record §13).

## Human verification — what is closed and what stays open

Full entries, quoted reports and the standing scripts are in record §03.
Nothing in the suite can see paint order, portal hoisting, scroll direction,
drawable presentation, the display link, hover from a real `NSTrackingArea`,
or any of text's three §4.2 failure modes; these are looks.

| milestone | status |
|---|---|
| M0, M1 element pipeline, EP-8 centring, M2 text, clipping/scroll, Stack, absolute positioning (failures 1–2), measure performance (release), input/state, sizing | **closed** by a human look on the dated build — every one of them **before** `.padding` became a wrapper (`f1944f8`) |
| the legacy demo after `f1944f8` | **regressed, then fixed 2026-09-14** (record §03). `.padding` became a wrapper, so the `.alignItems(.stretch)`/`.background`/`.flexGrow` written after it in six `demoContent` sites configured the wrapper: header an 84pt centred card, hairline and sidebar bars gone, list rows centred. **Fixed 2026-09-14** by reordering `demoContent`'s modifiers around `.padding` (container settings and an inner `.flexGrow(1)` before it; size, background and corner radius after it), in the commit after `4e46c8f`. A window capture of the release demo now matches `a15ec83`'s pixel for pixel: 35 of 2,178,560 pixels differ, all desktop outside the window's top-left rounded corner. **Rule for any padded legacy container:** container modifiers and `.flexGrow(1)` before `.padding`, the item size, background and corner radius after it. Not re-taken: the modal (**M**) and the animation look (**A**) |
| the proposal preview (`METALUI_NATIVE_LAYOUT_PREVIEW=1`): text rewraps with window width, the `layoutPriority(1)` panel keeps its width as the window narrows, wheel scrolls the `ProposalScrollView`, the toggle flips colour on click, the dimmed tap under `.allowsHitTesting(false)` does nothing | open, no look recorded |
| absolute positioning failures 3–4 (modal stays put while scrolling; wheel over scrim must **not** scroll the list — inverted since IN-W) | open |
| wheel-mouse scroll distance: run the demo with a **conventional (non-precise) wheel mouse**, not a trackpad or Magic Mouse, and scroll the 500-row list one detent at a time. Report roughly how far one click moves it, in rows (rows are 28pt): about a third of a row per click at a one-line detent means the conversion is live; a thirtieth of a row means it is not. Also report whether it feels comparable to scrolling a native app (e.g. a Finder list) with the same mouse | open. `MetalHostView.scrollDelta(x:y:precise:)` converts lines to points at 10pt per line (`NSScrollView`'s default), verified only with **synthesized** `CGEvent(...units: .line)` events. A real wheel's per-detent line count after the window server's acceleration is **unmeasured**, so the on-screen distance per click is not established. Record §03 |
| measure performance in **debug**; row missing/blank at the bottom edge; reaching row 500; launch hitch | not reported either way |
| tombstones-and-AX §7 item 9 (regression check; the demo cannot exercise its subject) | open, nobody has run the build |
| reactivity §8 item 7: run the demo, idle 30 s, press **M** twice, quit with **Q**, report `frames drawn` / `pauses entered` / `observation dirtyings` — a measurement, not a judgement | open |
| animation §9's "whether the motion looks right" (spec exit criterion 9): press **A**. The sidebar's width (196pt ↔ 320pt, the layout-phase helper) and its background (`.surface` ↔ `.accent`, the paint-phase helper) both read `DemoModel.animationDemoActive` inside one `withAnimation(.spring(duration: 0.6, bounce: 0.2))`, so one keystroke drives both and they can be reported separately | **run 2026-09-10, release, at `b869253` — BOTH animate; the paint-phase helper is confirmed live in production.** Read first as "width slides, colour snaps" and corrected on a second look, so the fade is **not obvious at a glance**. **Overshoot and reverse direction closed 2026-09-10 by a scripted measurement, not a human look** (the running release demo, scripted keystrokes, window captures): the forward press peaks at 114pt and settles at 113pt on screen — the declared 196→320 spring's 1.88pt overshoot at t = 0.500 s, computed from the real `springValue`, lands as a 2-device-pixel rebound because the sidebar is flex-shrunk (SZ-L); the colour overshoots too, (97,167,253) against a (96,165,250) target; and the reverse press animates width and colour 113→73pt. Record §03. **These pixel readings describe the pre-`f1944f8` sidebar** (padding inside the 196pt column); the background now paints from the padding layer (`ModifiedElement`), so they need re-taking |
| accessibility bridge: record §12's VoiceOver script, items 1–9 (activation in both orders, static text, buttons, the list by ear and by Inspector, focus, frames while scrolling, theme and modal, animation noise, identity adoption) | open, nobody has run it |
| tasks 3, 9, 12 integrated: release-window capture of the default demo AND the `METALUI_NATIVE_LAYOUT_PREVIEW=1` window against a build of `f64e58a`, by `MC-J`'s method (`CGWindowListCopyWindowInfo` bounds, `screencapture -x -R…`, no input) | **open**: the session was locked at every track and at integration. Stand-in: offscreen `FakePlatformWindow` pixels of `demoContent()` (light/dark, f0/f3, modal, settled **A**) and the preview, merged vs `f64e58a`, **0 differing pixels in all ten**, with a paint-order instrument that differs (record §13). It cannot see the drawable, the real window, input, hover, focus or a mid-flight animation |

Demo keys: **M** modal (translucent scrim, gated so other looks stay
undimmed), **Space** theme, **F**/**Escape** focus the counter, **=**/**-**
count (context `"Counter"`), **A** the animation look above, **Q** quit. The
same keymap is installed in the proposal preview window, where only **Space**
and **Q** have a visible effect. The demo's sidebar shrinks below its 196pt
declaration and WebKit does the identical thing (SZ-L); it is not a bug — as
measured on the pre-wrap sidebar, and on 2026-09-14 after the demo's modifier
reorder (88pt at the 920pt default window, identical to `a15ec83`).
Dark-on-dark dimming is hard to judge by eye — measure a "no scrim" report
before believing it.

## Known divergences — expected, measured, not defects

Twenty-seven entries; labels are stable ids. Retired and never reused: 3, 5, 6
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
| 19 | unfixed defect | **One element VALUE placed twice shares one `@State` box.** `let sep = Ctr(); Row { sep; sep }` — reads were fixed 2026-09-10 by re-binding in `prepaintGroup`/`paintGroup`, but a **handler** registered by one occurrence still writes the other's slot, because the closure captures the class box and one box holds one slot. Measured: occurrence 0 clicked once reads 1, occurrence 1 never clicked reads 102. Pinned wrong on purpose; counted by `StateTable.aliasedStateBoxes`. Build two values, don't reuse one. |
| 20 | design | A layer added to a legacy modifier chain at run time is adopted by the new outermost layer (old outermost id, `$anim` baseline, hitbox id, accessibility node), while the wrapped element moves one level down and resets (`MC-C`). SwiftUI's modifiers carry no such state. Pinned by `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` and, for accessibility, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`. |
| 21 | vs SwiftUI | A focused element that becomes disabled loses focus at once and re-enabling does not restore it; SwiftUI keeps it (probe K2, `EV-F`). Pinned by `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`. |
| 22 | vs SwiftUI | A disabled ancestor's raw `onKey` and `keyContext` are removed; SwiftUI runs a disabled parent's `.onKeyPress` (K6, `EV-F`). Pinned by `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`, `aDisabledPaneContributesNoKeyContext`. |
| 23 | vs SwiftUI | A disabled click target passes the click to an enabled sibling under it, where SwiftUI's shape blocks (P2f/P2g, `EV-E`) — the difference every non-clickable MetalUI overlay already has. Pinned by `aDisabledClickTargetPassesTheClickToWhatIsUnderIt`. |
| 24 | vs SwiftUI | No `displayScale`; `pixelLength` is tied to the device, so no scope changes it and a `\.self` reset does not reset it (`EV-J`, `EV-U`). |
| 25 | vs SwiftUI | `layoutDirection` is carried and no container mirrors (probe H, `EV-K`). Pinned wrong on purpose by E17. |
| 26 | vs SwiftUI | Key handlers bubble outward from the focused element; SwiftUI runs an ancestor's `.onKeyPress` first (K5). Pre-existing, measured in task 9. |
| 27 | vs SwiftUI | `onClick` is pressable through accessibility; a SwiftUI tap gesture is not, even with `.isButton` (`AB-G`, arms 7, 8). |
| 28 | vs SwiftUI | Under `allowsHitTesting(false)` a button publishes with no `.press` and refuses one; SwiftUI still presses (`AB-H`, P0/P1). Pinned by `aPressIsRefusedWhereHitTestingIsDisabled`. |
| 29 | vs SwiftUI | A button over an interactive descendant stays an unlabelled button with its children; SwiftUI collapses it (`AB-G`, R7). |
| 30 | vs SwiftUI | A focusable or adjustable labelled container keeps a labelled group; SwiftUI distributes the label and copies the adjustable action to each child (`AB-T`, C1, C5, C5i). Pinned by arm 7 of `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`. |
| 31 | vs SwiftUI | Nothing focused reports the host view; SwiftUI reports the first focusable node (`AB-J`, arm 13). |
| 32 | vs SwiftUI | A `List` is an `AXTable` of realized rows; SwiftUI publishes an `AXOutline` (`AB-L`, R16); rows beyond the window are unreachable. |
| 33 | vs SwiftUI | A labelled generic node is `AXGroup`, not `AXUnknown` (`AB-F`, 10b, R6, R11). |
| 34 | vs SwiftUI | `Stack` publishes declaration order, not front to back (`AB-P`, arm 4). Unpinned. |
| 18 | vs SwiftUI | `@State` behind a removed `if` is retained, not reset; indefinitely below 256 entries — but 256 is easier to reach than it reads, since every registering element mints a `$anim` entry unconditionally (measured on the committed `demoLikeRows(_:)` test fixture, which has no `.padding`: `2n + 7`, crossing at **125 rows**, 1007 at 500; the demo's own 500-row list is not that fixture and, since each row's `.padding` became a wrapper in `f1944f8` (now a `ModifiedElement` layer), holds more by an unmeasured amount). Reset explicitly or keep the value in data. Element-level consequence is unpinned. |

## Declared but inert — verify, do not remember

The most likely bug here is an API that exists, compiles and does nothing.
When you implement one, delete its row; when you add a property you cannot
implement, add one. Full mechanisms and the grep for each row in record §05.

| declared | reality |
|---|---|
| `AlignItems.baseline` / `AlignSelf.baseline` | falls back to the start edge in flex and in `Stack`; needs baselines in the measure protocol |
| `Style.aspectRatio`, `Style.overflow` | zero reads (`overflow` has one write, in `ScrollView`, that nothing consumes). The proposal `.aspectRatio(_:contentMode:)` modifier is a different, live API — do not delete it with this row |
| `margin: .auto` | resolves to 0 on both axes; unreachable from modifiers, reachable via `Style` |
| legacy `borderWidth(_:)` | shrinks the content box and paints nothing; no legacy element passes a border to `PaintPass.fill(borderColor:borderWidths:)`, which only the proposal `.border` uses (`Frame.fill`'s and `Box.swift`'s doc comments still say it cannot be set) |
| `Position.relative`'s offset | makes a containing block, does not shift the box |
| `Style.alignSelf` on a `Stack` child | ignored entirely |
| `Style.padding`/`border`/`margin` on a **leaf** (`Text`) | **not** the `.padding(_:)` modifier on an element, which now wraps in a `ModifiedElement` layer: it offsets and enlarges the outer footprint of a fixed-size custom `StyledElement` (`paddingWrapsAnElementAndExpandsItsOuterFootprint`, whose `Leaf` is not a `Text`); that it does the same for a `Text` is by reading, unpinned. Holds for `Style.padding` set directly, `.borderWidth`, `.margin`, and a `Component`'s distributed `.padding`: ignored on a **content-sized** leaf: no size moves, and it stays out of §9.7.4.c's shrink weight (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`). **Not inert once the leaf declares a main size**: ruling BM-4 puts the padding inside that base, so it comes off the shrink weight as CSS says — a 200 row of two `width: 200px` measured leaves, one with `padding: 0 40px`, lays out 125 / 75 (`aMeasuredLeafWithADeclaredSizeIsWeightedByItsInnerBaseSize`) |
| `hidden()` on a subtree that draws or is focusable | layout filters it, paint does not: glyphs stack at the window's top-left; a hidden focusable still claims keystrokes. Use a builder `if` instead |
| `AnyElement` | works when hand-written; the builder never produces one and must not |
| `@State` inside `AnyElement` | silently inert |
| `PaintPass.isActive` | correct, pinned, consulted by no built-in element — nothing paints a pressed state |
| `PlatformWindow.onInput`'s `-> Bool` | `Window` computes it and `AppKitWindow` forwards it one hop; all seven `MetalHostView` event overrides discard it (`_ = onInput?(…)`, no `super`), so AppKit never sees it and an unhandled event never continues down the responder chain. Only the fake reads it. Do not wire `super.keyDown` in without an `NSMenu`: every unbound key beeps |
| colour glyphs | tinted luminance silhouettes |
| `HStack`/`VStack`'s `alignment:` main-axis half | a stack reads only the cross-axis factor of the nine-point `ProposalAlignment`: `HStack(alignment: .leading)` places exactly as `.center` (SwiftUI's typed alignments would not compile) |
| `LayoutMeasurement.firstBaseline`/`lastBaseline` | no producer (`ProposalText` reports none) and no consumer; frame, padding, aspect-ratio, `.fixedSize`, `.layoutPriority` and the `.overlay` modifier (`overlayAttachment`, which returns its primary's measurement) carry them; `ZStack` (the `.overlay` node), linear stacks and the scroll viewport drop them (`LayoutTree.swift` `measureNative`). No baseline alignment exists |
| `ProposedSize.zero` / `.infinity` | no container ever proposes them; nothing asks a child for its minimum or maximum |
| `.allowsHitTesting(false)` over a scroller | gates click hitboxes only; a `ScrollView`/`ProposalScrollView` inside still scrolls and still wins topmost-opaque |
| `GlyphAtlas.evictUnusedSince`, `LayoutTree.reset(generation:)` | zero callers; guards kept for whoever calls them |
| `Frame.scrollRegions` / `Window.lastScrollRegions`, `StateTable.isDirty`, `StateTable.writeCount`, `LayoutTree.lastNativeLayoutWork` | test observables with no production reader |
| `AXNode.children`, `AXNode.actions`, `Frame.axNodes`/`axNode(for:)`, `AXEmission.synthesizes` | always `[]` (hierarchy comes from records, `AB-C`) / declared, never read (`AB-H`) / no production reader, the bridge reads records; `axNode(for:)` validity lags one frame / no reader |
| `ElementGroup.LayerBase` / `_wrap(_:)` on a custom conformer | a conformer that declares `LayerBase` and forwards `_wrap` to another value compiles, and its `.padding`/`.frame` silently drop the receiver (`MC-A`); no access-control spelling closes it |
| `EnvironmentValues.layoutDirection` | carried; no layout reads it (divergence 25) |
| `EnvironmentValues.locale` | carried; no tokenizer, typesetter or formatter receives it |
| `EnvironmentValues.dynamicTypeSize` | carried; no text size moves (aligned with SwiftUI on macOS, `EV-I`) |
| `EnvironmentValues.pixelLength` | no internal reader |
| `@Environment` inside `AnyElement`; an unbound `@Environment` | inert / reads `EnvironmentValues()`'s defaults silently |
| an in-module write to `theme`/`pixelLength` through `window.environment` or `Frame.rootEnvironment` | re-stamped every frame; does nothing |
| `.disabled` on a `ScrollView` | the wheel still scrolls: its scroll region bypasses the gate (pinned as it stands) |

## Performance — the numbers to reason from

Record §07 has the tables and machines. `computeLayout` is ~40 µs/node debug,
~5 µs/node release, flat 8k–88k nodes (content sizing's §4.5 automatic-minimum
probe multiplied it ~4.9x; whoever optimises starts there). A column item's
probe is keyed on its used width since 2026-09-10, which added misses
(1633 → 1723 on a 365-node column/wrap tree; record §07). A node with no
children and no measure function is answered in closed form inside
`measureNode` — no cache key, no `layOutChildren`, neither a hit nor a miss —
and sits below `ctx.enter`, or `measureNodeConsultsTheDepthGuard` fails.
Counted on a branching 4x5x3 tree of empty Boxes at three queries, cache misses
fell from 707 to 167. The µs/node figures above predate this and have **not**
been re-taken (the only timing available was on a contended machine). `Text`
leaves never take this path. The demo's warm
release frame is **1.652 ms at 40 rows and 1.637 at 500**, re-taken 2026-09-10
at `2457da8` after the animation milestone (stale; see below); scrolling adds 0.1–0.3 ms. The
+5% against the superseded 1.571/1.570 is **within the ~5% harness drift §07
already documents — do not read it as animation's cost**. Warm resident
`StateTable` entries are **165 at 40 rows and 63 at 500**: the smaller tree
holds more, because only the larger one crosses `sweepThreshold` and is reaped.
**The frame times and these entry counts were taken on a copy of the
pre-`f1944f8` `demoContent()`**; each demo list row's `.padding` now adds a
registering `ModifiedElement` layer (and a `$anim` entry) per built row, and
since the accessibility bridge the demo's three labels write `$ax` slots every
frame, so they are stale by an unmeasured amount. (Divergence 18's `2n + 7` is unaffected: it was measured on
the `demoLikeRows(_:)` fixture, which has no `.padding`; only its extrapolation
to the demo is stale.) The proposal engine has no timing. Count its work with
`LayoutTree.lastNativeLayoutWork` (`SA-M`): on the branching tree in
`NativeLayoutWorkTests.swift` one call is 16 measure calls, 27 hits, 25 misses.
The
cold first frame builds every `List` row: ~76 ms release / ~188 ms debug at
500, ~17 s release at 100k — M3's "100k scrolls smoothly" is met for scrolling
and not for appearing. Identity path construction is ~0.4% of a frame. Hitbox
registration is ~0.01 ms.

## CI — what lapses silently

CI exists: `.github/workflows/swift.yml` runs `swift build -v` and `swift test
-v --no-parallel` on `macos-latest` for pushes and PRs to `master`, and none of
the guarantees below is a separate required job. Whether the typecheck
guards run under that workflow's default build system is unmeasured. Record §08
has the mechanisms.

- The ABI probe **skips** without a Metal device.
- `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
- **Every typecheck guard skips when `.build` is not where `#filePath`
  resolution expects** — and that includes **the default build system**.
  `swiftbuild` writes modules flat into `.build/out/Products/Debug/` with no
  `Modules` directory, so under it alone **all 61 guards skip**, the total does
  not move and the run passes. `--build-system native` writes
  `.build/<triple>/debug/Modules`, **and that directory survives**: once a
  checkout has ever been built that way the guards run under the default system
  too, against those **leftover** modules rather than what swiftbuild just
  built. Both halves measured at `b869253`. **So take the guard count under
  `--build-system native`, and know the number does not tell you whether any
  guard ran** — a mutation run in a `git worktree` executes none of them at all.
  `--build-system native` is **deprecated** and prints so, which makes the
  honest fix — resolving the modules directory from the **test binary's** own
  location rather than from `#filePath` — a dated obligation.
- **The freeze loop's allocation pin checks only half of itself on CI, and
  says so in the log.** Under Apple's swiftlang toolchain — Xcode, and every
  GitHub macOS runner — a bare `for i in items.indices { sum += items[i].x }`
  registers **one allocation per element** in a debug build, where a swift.org
  toolchain registers none (measured 2026-09-11: 0 vs 67 at 67 items; 16 known
  buffers read as 16 and as 33). So an absolute per-pass bound there measures
  the toolchain, not `resolveFlexibleLengths`.
  `freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine` measures that floor in
  the same run and keeps its strict bound only when the floor is 0, falling
  back to a relative comparison against the allocating reference spelling.
  **On a swiftlang toolchain a per-item regression of about one allocation is
  invisible to it**; grep a CI log for `FREEZE-ALLOC: strict per-pass bound NOT
  CHECKED`. Run the suite under a swift.org toolchain to get the strict half.

- `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` passes
  `-Xfrontend -solver-scope-threshold=1000`; a toolchain that drops the flag
  fails or skips it. `aModifierChainAllocatesABoundedAmountOverNestedBoxes` and
  the freeze-loop test both install `malloc_logger`, so they need
  `--no-parallel`.
- `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne`
  (E24) **hard-fails on a runner whose current locale is the root locale**
  (unset `LANG`): its discriminating precondition is a `try #require`, not a
  skip.
- The accessibility arm-Q pin (`aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient`)
  assumes no out-of-process accessibility client on the runner, and the signal
  test reads the runner's `isVoiceOverEnabled` (`AB-AC`).

- **Seven device-dependent window tests HARD-FAIL rather than skip** on a
  runner with no display device: `makeFakeWindowOnDefaultDevice`
  (`Tests/MetalUITests/Fakes.swift`) throws where the surrounding convention is
  `try #require(MTLCreateSystemDefaultDevice())`. All seven are in
  `AnimationTests.swift`; re-count by greping for the helper, not by trusting
  the seven.
