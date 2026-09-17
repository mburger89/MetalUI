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
  | `FR-` | frame and sizing, plan task 4 (`FR-A`…`FR-V`, next is `FR-W`) | lettered |
  | `OM-` | outer modifiers, plan task 5 (`OM-A`…`OM-AM`, next is `OM-AN`) | lettered, two-letter tails are deliberate |
  | `CN-` | containers, plan task 6 (`CN-A`…`CN-U`, next is `CN-V`) | lettered |

  A bare `CS-3`, `TB-3`, `CO-3`, `AN-3`, `SA-3`, `MC-3`, `EV-3`, `AB-3`, `FR-3`, `OM-3`, `CN-3` etc. is a typo, not a citation. Sweep
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
- **Tasks 4 and 5 (two parallel tracks, integrated 2026-09-16 on
  `integrate/tasks-4-5`)**:
  - frame and sizing (task 4, `FR-`): `specs/2026-09-15-frame-sizing-design.md`,
    `2026-09-15-frame-sizing-decisions.md`, record §14; probes
    `docs/probes/swiftui-frame-semantics.swift` (54 arms),
    `…-frame-negative-sizes.swift` (17), `swift-frame-overload-resolution.swift`
    (the compiler), `appkit-screen-lock-state.swift` (the pre-capture check);
  - outer modifiers (task 5, `OM-`): `specs/2026-09-15-outer-modifiers-design.md`,
    `2026-09-15-outer-modifiers-decisions.md`, record §15; probes
    `swiftui-outer-modifier-order.swift`, `…-border-clip-paint.swift`,
    `…-content-shape-hit-region.swift`, `…-allows-hit-testing-side-effects.swift`,
    `…-component-distribution.swift`;
  - the integration (merges, eight cross-track tests and their mutations,
    probe arms S0–S3, the demo stand-in): record §16.
- **Containers (plan task 6, `CN-`; on `feat/containers`, still open by
  `CN-T`)**: `specs/2026-09-16-containers-design.md`,
  `2026-09-16-containers-decisions.md`, record §17; probes
  `docs/probes/swiftui-stack-algorithms.swift` (revision 9, the V1–V8 spacing
  arms among them) and `swiftui-overlay-presentation.swift` (compiled form
  only).
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests. Sixteen numbered shapes of test that cannot fail, seven ways a
  record goes wrong, all observed here.
- **Full record:** `docs/record/README.md` indexes the sections; `01`–`08`
  are the split pre-2026-09-09 file, `09` is the SwiftUI-alignment record,
  `10`–`12` the task 3/9/12 tracks and `13` their integration, `14`–`15`
  the task 4/5 tracks and `16` their integration, `17` task 6 (containers).

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

- **Counts, dated:** **1355 tests**, **97** browser-fixture goldens, **70**
  `swiftc -typecheck` guards, 0 `error:`, 0 `warning:` — measured 2026-09-16
  on `feat/containers` (plan task 6) after `swift package clean`, unfiltered
  `swift test --build-system native --no-parallel` after `swift build
  --build-system native --build-tests` (one summary line; only the two gated
  tests skipped; the lone `warning:` is SwiftPM's deprecation notice). Goldens
  unmoved against `9e439cb`. Delta from 1303 / 97 / 66: **+52 tests** (lane 1
  +13, lane 2 +7, lane 3 +10, lane 4 +15, lane 5 +7), **0 goldens, +4 guards**
  (all `ContainerCompileGuards`); record §17. Guards per file:
  `PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
  `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6,
  `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5,
  `ContainerCompileGuards` 4, `AXNodeTests` 3, `DecorationCompileGuards` 3,
  `UnitSafetyTests` 2 (3 hits, one a comment), `ModifiedElementCompileGuards` 2,
  `FrameSizingCompileGuards` 2.
  Before that: 1303 / 97 / 66 on `integrate/tasks-4-5` (2026-09-16, tasks 4/5;
  six summary lines under the default build system, record §16).
  Before that: 1226 / 97 / 61 at `2456c69` (2026-09-15, tasks 3/9/12).
  Before that: 1084 / 97 / 45 at `553b980` (2026-09-14, task 2). Before that:
  923 / 97 / 35 at `7f58db9` (2026-09-11). Earlier: 861 (47 + 448 + 50 + 6 + 288 + 22) on
  `feat/animation` at `b869253`; `master` at the Component milestone's end was
  811 / 87 / 34. **The per-target split is no longer printed on this
  machine** under `--build-system native` — it emits ONE summary line for the
  whole run; the default build system printed six again on 2026-09-16.
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
  `FrameSizingCompileGuards`, `DecorationCompileGuards`,
  `ContainerCompileGuards`, `MetalUICoreTests/UnitSafetyTests` (one hit is a comment) and
  `MetalUITests/AXNodeTests`.
  `Tests/MetalUITestSupport/Typecheck.swift` also matches and holds only the
  declaration — count guards, not files. **Two helpers:** 40 guards (the 39
  older ones and one of `EnvironmentCompileGuards`') use
  `typecheck(_:importing:)`, which wraps the fixture in a function in
  Swift 5 mode, so every fixture type is local and no `public` or file-scope
  `extension` compiles; the other 30 — `ProposalLayoutCompileGuards`'
  six, `ModifiedElementCompileGuards`' two, `ProposalNodeIDCompileGuards`' six,
  `FrameSizingCompileGuards`' two, `DecorationCompileGuards`' three,
  `ContainerCompileGuards`' four and seven of `EnvironmentCompileGuards`' — use
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
  2026-09-10, both cleaned before testing (record §06), and again with
  `Decoration` (nine stored properties) and `Handlers` (eight) on 2026-09-16
  (record §15). Turning a stored
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
- **`.padding(_:)` and every legacy `.frame(...)` spelling return ONE
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
  does not compile (guard). A decoration or handler modifier written after a
  wrapper configures the **outermost layer**, which is why
  `.padding(8).background` fills the padded box and `.background.padding(8)`
  the inner one (`OM-C`, probe A1/A2).
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
wrapper configures the outermost layer. **The legacy frame has SwiftUI's
whole parameter surface** — `.frame(width:height:alignment:)` and
`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`
on `ElementGroup` — and lowers to ONE `Style` in `FrameLayer.swift`'s
`FrameSpec.style()` (`FR-C`): a flex container on `.row`,
`justifyContent`/`alignItems` switched over the nine `ProposalAlignment` cases
(`aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`); a fixed axis pinned by
`size` AND an axis-named `minSize`, never `flexShrink = 0`, which is axis-blind
(`FR-P`: `aLegacyFixedFrameDoesNotShrinkAsAFlexItem`,
`aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`); `minSize`/`maxSize`
for the bounds; `flexGrow = 1` + `alignSelf = .stretch` only when BOTH
maximums are infinite (`FR-O`). It sizes itself and does not impose that size
on its content: a content-sized child is centred (a 0×0 mark at (30, 20) in a
60×40 frame), a measured `Text` re-wraps at the frame's width
(`aLegacyFrameProposesItsWidthToAMeasuredLeaf`), a fixed frame never shrinks as
a flex item, chained frames give the outer the size and let the inner overflow
(`chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`). **A legacy frame over
exactly ONE node then lowers to a one-cell `display: .stack`**
(`ModifierLayer.lowered(_:childCount:)`, per layer, `CN-N`): the child keeps its
own size and overflows both axes, SwiftUI's A5
(`aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`, inner layers
included). Over zero or several nodes — a multi-member `Component` — it stays
`FR-C`'s flex row and shrinks them, where SwiftUI frames each member (G7,
divergence 56); a conditional that moves the count between 1 and 2 switches
the lowering at run time. **A stack reads neither `.flexGrow` nor `.alignSelf`,
so on the only child of a legacy frame both compile and do nothing** (inert
table; `width(fraction: 1)` fills). **`lowered` keeps a `display: .none`**:
`.hidden()` written directly after a one-node frame (either overload, as the
outermost or an inner layer) hides it from layout and from an accessibility
client — a regression the branch checker found in `CN-N` and the closeout
fixed (`hiddenAfterASingleChildLegacyFrameStillHidesTheElement`,
`aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`; record §17,
"Closeout"). **Two legacy divergences stay pinned wrong
on purpose**, owner now task 7 (`CN-Q`): a finite maximum clamps but never
grows (35); a single-axis infinite maximum is inert (inert table). `idealWidth`/`idealHeight` **trap** on the legacy path
(`FR-D`, exit test). `.frame()` with no arguments is a deprecated no-op on both
paths (`FR-J`, guard). **`ElementGroup` must keep exactly ONE fixed `frame`
overload** (`FR-S`): a second compiles, and only `MC-A`'s solver-budget guard
says so. The two hand-spelled `frameStyle` oracles in `ModifiedElementTests`
and `ModifierCompositionProofTests` duplicate the lowering and will not tell
you they have drifted; change them with it. A decoration, handler or scope
written after a frame acts on the frame's box, before it on the child's
(record §16, tests 1–3 and 8, probe `swiftui-outer-modifier-order` B1/B2/D1/D2). `Stack` layers
(`Stack.swift`; `Column`/`Row` live in `Flex.swift`), last child on top; its
paint order is invisible to every rect test. A `Stack` child's `auto` width is
fit-content against the stack, as a column item's cross size is (ST-H, TX-H);
its height is measured at that width. There is no `display: contents`.

**The legacy containers keep their CSS algorithms** (`CN-A`, `CN-P`): no legacy
container is lowered onto the proposal kernel, and `SA-G` allows no adapter.
`Row`/`Column` default to gap 0 where `HStack`/`VStack` default to 8; a `Stack`
offers a child fit-content where a `ZStack` offers its proposal; a legacy
`ScrollView` takes its cross axis from its parent where a `ProposalScrollView`
takes its content's; compression is flex-shrink by base size, not flexibility
order (divergences 52–55, task 7). Porting a `Row {}` to an `HStack {}`
changes all four silently.

**`width`, `height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight`,
`width(fraction:)` and `height(fraction:)` write THIS element's own CSS box and
return `Self`; `.frame(...)` wraps** (`FR-F`, `FR-G`;
`theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` counts the
nodes). They are not deprecated (`FR-I`): the 0-`warning:` gate makes a
`renamed:` hint a migration of every caller (`git grep -oE '\.(width|height)\('
-- Sources Tests`, several hundred) and task 7 owns it (`FR-F` holds the
recipe). **`.minHeight(0)` is the only way to cancel flex §4.5's automatic
minimum; a frame layer's `minSize` cannot reach its child** (`FR-G`).
**Fractions are spelled `width(fraction:)`, `height(fraction:)` and
`flexBasis(fraction:)`** (`CN-O`): `fraction: 0.5` is half. The `percent:`
spellings are deprecated renames that forward unchanged — they always took a
fraction, so `percent: 50` is still 5000% (guard
`thePercentSizingModifiersAreDeprecatedRenamesOfFraction`; divergence 40
retired). There is no rem sizing modifier; `Length.rems` is reachable through
`padding(_ edges:)`, `margin(_ edges:)` and `inset(_ edges:)` and resolves
against the per-frame `rootFontSize` (`FR-Q`, less the deleted `borderWidth`).

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
and resets clip and scroll offset together** (AP-I) — **not opacity**, which a
faded subtree's portal inherits (`OM-AA` b,
`aDeferredPortalInsideAFadedSubtreeIsStillFaded`). Legacy `.opacity` scopes
multiply (`Frame.activeOpacity`), but an element contributes ONE scope, so
`.opacity(0.5).opacity(0.5)` on one element reads 0.5 where SwiftUI reads 0.25
(divergence 46); a nested `Box` or a layer between them reads 0.25. No z-index. Absolute
positioning is separate: `.position(.absolute)` + `.inset(...)` against the
nearest non-static ancestor, root fallback. A tooltip needs the portal; a modal
needs both.

**`Component` is layout-transparent and identity-opaque.** It contributes no
layout node, consumes one cursor index, and its `@State` hangs off its own id.
Its `.padding` **wraps each top-level node** in its own padding node,
accumulating on a chain (`OM-D`, `OM-E`; probe `swiftui-component-distribution`
G2/G10–G12: a one-`Text` component measures 13x16 bare and 53x56 padded, as the
element path does); `.width`/`.height` still **distribute** as an amend that
overwrites each member's own value (divergence 48, `OM-F`; SwiftUI's `.frame`
wraps). Ops apply in declaration order (`StyledComponent.ops`;
`aModifierOnAComponentAppliesInTheOrderItIsWritten`), and only to members that
contribute a node: `.padding` on a `Deferred` or a false `if` member is dropped
(by reading, unpinned). `.padding` means the same thing **in layout** on both
receiver types; only `width`/`height` keep two layout meanings. It is still not
the same modifier: a component's padding node is a bare `requestNode` with no
id and no `$anim` slot, so it adds no id level and **snaps** inside
`withAnimation`, where an element's padding layer has both
(`everyRegisteringSiteAnimatesItsStyle`'s `Component` arm, re-measured by
`OM-D`'s lane 4).
`.frame(width:height:)` on a component wraps its body in one `ModifiedElement`
layer without overwriting its children
(`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`). A caller's
modifier on a component — `width`, `height` or `padding` — never animates
(review finding B-7; see the Animation section's snap list). `Component` itself
has no `.background()` (use a `Box`) and no `.id()` — declare `var elementID`;
nor `border`/`focusBorder`/`opacity`/`clipped`/`contentShape`. That absence is
by type only (they live on `extension StyledElement`): no guard pins it, and
`decorationBackedModifiersAreNotOfferedOnAComponent`, despite its name, checks
only that `.padding` returns a `StyledComponent`.
**Both holes have side doors (no typecheck guard):**
`anyComponent.frame(...)` returns a `ModifiedElement`, a `StyledElement`, so
`.frame(…).background(…)` compiles on any component, and `.opacity`,
`.clipped()` and `.border` through it scope the members without distributing
(measured, `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`); and a component retro-conformed to `ProposalElementGroup` picks
up that extension's `.background(ColorToken)`, `.padding(Edges<Pixels>)`,
`.frame(…)` and the rest (`NativeModifiedContent.swift:157`), so on it
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
topmost-opaque slot (`OM-AK`). The legacy **`StyledElement.allowsHitTesting(false)`**
is a prepaint-only scope on the layer it is written on, covering the
receiver's own hitbox and its subtree's (`OM-T`, probe N1/N2), leaving focus,
`onKey`, actions and the accessibility payload untouched; **per layer**, so
written before a wrapping modifier that carries the `onClick` it does not reach
that click (divergence 44). Hover follows the hitbox.
**`contentShape(inset:)`** moves the pointer region only — not the
accessibility frame, not the focus registration — applied in
`Frame.registerHandlers` through `Frame.hitRegion` (`OM-J`); a negative inset
grows the region as SwiftUI's does and is still intersected with the active
clip (divergence 43); with no `onClick` on its layer it registers nothing
(`OM-AB`), so written before a wrapper that carries the click it is inert
(divergence 50). **MetalUI's default hit region is the element's whole frame**
where SwiftUI's is content-derived (divergence 41), so a padded click target is
hittable in its padding (42). Hover resolves once at the
prepaint/paint boundary. Handlers outlive the frame (`Window.lastHitboxes`), so
`.onClick { window.x() }` is a retain cycle — capture weak or capture state.

**`StyledElement` has four requirements — `style`, `decoration`, `elementID`,
`handlers`** — and a conformer calls
**`registerAndScope(handlers, decoration, …) { content }`** in its `prepaint`
(it opens the `allowsHitTesting` scope around the receiver's own registration
AND its content, pushes `.clipped()`'s clip, then calls `registerHandlers`) and
**`paintDecoration(decoration, in:, for:) { content }`** in its `paint` (the
opacity scope, the background before the content, the border **after** it,
`OM-V`). Four sites: `Box`, `Stack`, `Text`, `ModifiedElement` (per layer).
**Each helper has two halves and each half its own per-site guard** (`OM-AI`):
`everyDecorationPaintingSiteDrawsItsBorder` and
`everyDecorationScopingSiteContainsItsOwnContent` (paint);
`everyHandlerRegisteringSiteHonoursAllowsHitTesting`,
`everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` and
`clippedAlsoClipsTheHitboxesInsideIt` (prepaint); the hover/focus border chain by
`everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`. A site that
calls a helper with an empty closure and does its work after it passes the
first guard of the pair and fails the second. `registerHandlers` registers the hitbox, focus, a declared
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
not `Equatable` and has **eight** stored members; `HandlerShape`
(`ModifierTests.swift`) **and `HandlerFingerprint`**
(`OuterModifierMatrixTests.swift`) must each gain a field in the same change
`Handlers` gains a member — the first has fallen behind twice. `ModifierTests`'
tripwire is 47 against `grep -c "public func" Sources/MetalUI/Box.swift`'s 50.

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
and/or **`focusBorder(_:width:)`, the focus ring** (`OM-L`); background and
border each resolve through one `focus ?? hover ?? plain` selector
(`effectiveForPointerState`, `AnimatedColor.swift`), so focus outranks hover for
both, on the layer the modifier was written on. Nothing in the demo declares a
`.focusBorder`; the ring is opt-in.

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
off the main actor rewrites both first. The other three `assumeIsolated` calls
(`Window.markDirtyFromObservation`, the demo's `atexit_b`, and the bridge's
`mainActorAnswer`, behind `Thread.isMainThread`, `AB-AE`) are guarded.

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
outermost layer's `animatedBackground` and the inner layers'), all through
`paintDecoration`. `grep -rn "pass\.fill(" Sources/MetalUI` reads eight, none
animating: the two scroll indicators (drive themselves by dirtying) and the six
proposal-path fills. The legacy sites fill inside `paintDecorationBody`
(`AnimatedColor.swift`): one background fill from `animatedBackground`, one
border fill that does not animate. **The five paint-only `Decoration` fields
(`border`, `hoverBorder`, `focusBorder`, `opacity`, `clipsContent`) snap**
(`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`; task 13). A settled
`$anim` entry now carries an 80-byte `Decoration`; the per-entry end-to-end
figures are not re-taken.
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
`Frame.computeRootLayout` checks only `tree.isNativeLayoutNode(root)`. A
native root is measured at the window proposal and **placed centred at its own
answer** (`CN-J`, probe R1/R2) by
`LayoutTree.computeNativeLayout(root:proposal:centredIn:)`
(`aNativeRootIsCentredAtItsAnswer`); a greedy root still fills the window.
`computeNativeLayout(root:proposal:in:)` still places at the caller's bounds,
and a `ZStack` placed in bounds larger than its answer puts the union of its
children at their origin (`CN-E`, divergence 58). Both entries share one
private `runNativeLayout`; `measureNativeLayout` keeps its own bracket. The
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
- **Proxies expose `priority`, `isSpacer` and a cached `sizeThatFits`**:
  `priority` by the built-in stack's rule (a spacer −∞, a single-child stack
  its child's); `isSpacer` is read by no built-in since `CN-B`.
- **Migration** (`SA-F`, under `SA-R`'s amended criterion; every registrar
  now returns `ProposalNodeID`):
  - a leaf uses `requestNativeLeaf`;
  - an algorithm uses `ProposalLayout`;
  - a container with its own paint or input uses `requestGroupLayout` +
    `requestNativeLayout`;
  - a legacy root is unchanged, and no legacy container is deprecated (only
    the `percent:` sizing spellings are, as renames, `CN-O`).
- **Sufficiency.** The plain-import `ReferenceLinearStack` must match the
  built-in stack's rects. It compares a transposed vertical tree too (`CN-B`;
  record §09's green mutation F1 now reddens it, re-run 2026-09-16), and spacers' main extents only (a
  `ProposalLayout` cannot mark a spacer).

**The kernel's stacks are SwiftUI's** (`CN-B`…`CN-I`, probe
`swiftui-stack-algorithms.swift`).
- **Distribution** (`solveLinearStack`, one function for measurement and
  placement). At a finite main proposal a linear stack takes spacing off,
  groups children by priority highest first, offers each group what remains
  **minus every lower-priority child's answer at main 0**, serves each group
  **least flexible first** (answer at main ∞ minus answer at main 0; ties in
  declaration order) at `max(0, remaining / left)`, and **answers the sum of
  the answers, overflow included**. At a nil or ∞ main proposal every child
  gets that value. At a nil cross proposal it places after a second pass at
  its own cross size. So a greedy `.frame(maxWidth: .infinity)` takes surplus
  and a stack holding a spacer still compresses.
- **`Spacer`** has priority −∞, a nil `minLength` of **8**
  (`ProposalSpacing.platformDefault`), answers ∞ at ∞, and answers **0 on the
  cross axis of the stack that marks it** (`markSpacers`): the mark passes
  `layoutPriority`, `padding`, `frame`, `fixedSize`, `aspectRatio` and both
  sides of an overlay attachment, and stops at a `ZStack`, a nested stack, a
  scroll viewport and a custom layout.
- **A single-child `HStack`/`VStack`/`ZStack` passes its child's priority
  through** (`CN-D`); a custom layout reads 0.
- **Default spacing (`spacing: nil`) is decided per adjacent pair** (`CN-H`):
  0 if either facing edge is a zero-spacing edge, else 8. `zeroSpacingEdges` is
  an exhaustive switch: a spacer along its marking axis (or unmarked); wrappers
  pass through, padding only on a 0 inset, an overlay attachment its primary's;
  a same-axis stack its first child's leading and last child's trailing edge; a
  cross-axis stack or custom layout zero if ANY child is; a `ZStack` if EVERY
  child is; an empty container both; a leaf or scroll viewport neither. A new
  `NativeNode` case must choose its edges. An explicit spacing is used
  verbatim, beside a spacer too.
- **Alignment is typed** (`CN-I`): `HStack(alignment: VerticalAlignment,
  spacing:)`, `VStack(alignment: HorizontalAlignment, spacing:)`, SwiftUI's
  argument order; the wrong axis does not compile (guards G1–G3).
- **`ZStack`** measures children at its proposal and places each at **its own
  size** as the proposal, aligned within the union of those answers (`CN-E`).
- **`.aspectRatio`** answers **its child's** answer to the ratio-shaped
  proposal, ∞ counting as a concrete axis (`CN-G`).
- **An infinite proposal is answered with ∞** by a frame with an infinite
  maximum, a spacer and a scroll viewport's scrolling axis (`CN-F`, reversing
  `FR-B`); a custom layout placing a child there traps at checkpoint 3.
- Every rule is pinned against a probe arm in `NativeStackDistributionTests`
  and `ContainerIntegrationTests`, except a same-axis stack's trailing
  zero-spacing edge (mutation F leaves the suite green; below).

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
errors, each guarded (`ProposalNodeIDCompileGuards`). **Holes the type leaves**
(`ProposalNodeID.swift`'s header, seven numbered, two closed at run time): two
entry points can disagree; a legacy node or subtree registered on the side of a
typed entry is not rejected; `unsafeBitCast` or `@testable` can mint an id; a
legacy style modifier on a proposal `Component` compiles, then traps; an id
stored from an earlier frame traps (C-3). **One id used twice now traps**: a
native node registered under a second parent traps at every registrar with
children (`CN-L`, hole 4, exit tests); `reset` clears that record, and losing
the clear truncates the unfiltered suite at
`aResetTreeMeasuresItsNewRegistrationsFromScratch`. **A precondition closing
the orphan hole truncates the suite** unless its pinning test becomes an exit
test first. **The builder groups' typed entries are line-for-line copies of the
untyped ones** (and so is `EnvironmentScope`'s), each pinned on its own; a new
group gets its own pin.
Single-child proposal wrappers (`ProposalFrame`, `Padding`, `Background`,
`FixedSize`, `ModifiedContent`, `OnTapModifier`) precondition exactly one node,
so `ProposalFrame { if flag { … } }` traps when `flag` is false. `.overlay` and
`.background(alignment:content:)` precondition one PRIMARY node; their content
may be zero nodes (no attachment, the primary alone), one, or several (a
`.center` kernel `ZStack` positioned by the modifier's alignment) (`CN-K`). A
background's content prepaints and paints before its primary, so a click over
both reaches the primary. `ProposalScrollView` lowers zero children to an empty stack.
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

**Vocabulary.** Proposal types (`MetalUI`): `HStack(alignment:
VerticalAlignment = .center, spacing: Pixels? = nil)`, `VStack(alignment:
HorizontalAlignment = .center, spacing:)` (`CN-I`; the nine-case spacing-first
initializers are deprecated), `ZStack`, `Spacer(minLength:)` (nil = 8),
`Rectangle(color:)`
(proposal-responsive) and `Rectangle(width:height:color:)` (fixed), `Color`,
`ProposalFrame` (not `Frame`: `public final class Frame` exists), `Padding`,
`Background`, `FixedSize`, `ProposalScrollView`, `ProposalText`. Modifiers on
`extension ProposalElementGroup` return `ModifiedContent` over a closed
`LayoutModifier` enum — `.frame(width:height:alignment:)` and
`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)`,
`.padding(Edges<Pixels>)`, `.fixedSize`, `.background`,
`.clip(cornerRadius:)`, `.border`, `.opacity`, `.allowsHitTesting`,
`.aspectRatio(_:contentMode:)`, `.layoutPriority` — plus `.overlay`,
`.background(alignment:content:)` and `.onTap(hoverColor:)`;
`ProposalLayoutContainer` carries a custom layout. Kernel types
(`MetalUILayout`): `ProposedSize`, `LayoutMeasurement`, `ProposalAlignment`
(nine), `ProposalStackAxis`, `AspectRatioContentMode`,
`ProposalMeasureFunction`, `ProposalLayout` and its four proxy types,
`ProposalSpacing` (`platformDefault`), and
`computeNativeLayout(root:proposal:centredIn:)`. **The `Native…` types and
`native…` modifier methods are deprecated aliases** — 26 of the 34
`@available(*, deprecated` hits (the others are task 9's `Binding` alias for
`KeyBinding`, task 4's `frame()` on each protocol, task 6's two spacing-first
stack initializers and three `percent:` sizing modifiers): 17 typealiases (14 in `MetalUI`, 3 in
`LayoutTree.swift`) and 9 methods — except the two `nativeFrame(...)`
overloads, live undeprecated duplicates of `.frame` used by six test call
sites; deprecating them breaks the 0-warning baseline. **The kernel's own
`Native` names are not aliases and are not deprecated**: the 12
`LayoutPass.requestNative*`, the 12 `LayoutTree.newNative*` (each set
including the custom-layout registrar), `computeNativeLayout` and
`isNativeLayoutNode` are the primary API. Shared spellings
resolve by receiver: every `.frame` spelling on a proposal value picks the
proposal overload
(`everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`, seven
inference rows; `swift-frame-overload-resolution.swift`), on anything else
`ModifiedElement`; `.frame()` is deprecated on both; `.background(ColorToken)` exists on both
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
with the scrolling axis unspecified, answers `proposal ?? content` on its
scrolling axis (∞ at ∞) and **its content's answer on the other** (`CN-M`,
SC2); small content sits at the leading edge of the scrolling axis. It shares `ScrollView`'s wheel routing (`registerScrollRegion`, `ScrollState`
under its bare id). Its prepaint clamp and its indicator (alpha fade,
`requestAnotherFrame`, thumb maths, clip) are **private copies**
(`ProposalScrollView.swift:97-171`), so a fix to `ScrollView`'s does not reach
it. It takes `elementID:` in its
init, has no `$anim-content`/`$anim-viewport` nodes and never animates;
multiple direct children lower to a centred **vertical** stack at default
spacing (8, none beside a spacer: SC3, SC5) on either axis; two-axis scrolling
does not exist (task 10). `ScrollView` is unchanged and remains `List`'s only scroller. Divergence
16 applies to `.onTap` inside a `ProposalScrollView` (by reading).

**Probe-backed values.** The stack, spacer, spacing, alignment, `ZStack`,
overlay-content, root and scroll-axis rules above have a saved, re-runnable
probe with controls, `docs/probes/swiftui-stack-algorithms.swift`. The frame rule (child proposal, response, alignment,
chaining, negative sizes) has two saved, re-runnable probes with positive
controls, `docs/probes/swiftui-frame-semantics.swift` and
`…-frame-negative-sizes.swift`; the frame-sizing spec's "The rule, in one place"
block is the 71-arm summary. For the rest, SwiftUI macOS probes. **The values in this list have
no saved probe source** (prose in the plan and in test doc comments only), so
none can be re-run, and most record no positive control. Task 2's completion
committed two re-runnable probes, `docs/probes/swiftui-layout-protocol-contract.swift`
and `…-input-validation.swift`, with positive controls; they back the `SA-`
rulings above and `SA-N`'s findings below, not this list.
- `Rectangle()`/`Color` answer 10pt on an unspecified axis and the offer on a
  concrete one (`rectangleUsesSwiftUIShapeProposalSizing`) — including
  `.infinity` for an infinite offer.
- A frame's `ideal` on an unspecified axis reports `clamp(ideal, min, max)`
  (`anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `…Height…`).
- `Spacer(minLength:)` is a floor even when the stack overflows
  (`spacerMinimumLengthSurvivesAConstrainedStackProposal`).
- `.aspectRatio` fit/fill at 100×80 on 2:1 proposes 100×50 / 160×80 and
  answers the child (AR1)
  (`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`, `…Fill…`);
  the two-axis branch at zero and negative axes is probed (P8c) and pinned
  (`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`); the
  single-axis branch is unpinned.

**Probed, and the kernel disagrees** (`SA-N`; `Spacer()`'s 8pt minimum,
`aspectRatio` at nil×nil and a single-child stack's priority closed by `CN-C`,
`CN-G`, `CN-D`):
- padding places its child at the child's own size; the kernel stores bounds
  minus insets, pinned wrong on purpose (task 7, `CN-Q`); it no longer shows at
  a centred root (`CN-J`).

**The kernel's flexible frame is greedy** (`FR-A`, `FR-M`, closing the two
task-4 `SA-N` items): with a maximum and a finite proposal it answers the
proposal clamped into `[min, max]` when a minimum is declared, and
`max(proposal, child)` clamped when none is — the test is on the minimum's
PRESENCE, not its value (`aFrameWithoutAMinimumNeverAnswersLessThanItsChild`).
An ideal is used only on an axis with no proposal. Declared negative bounds
floor at 0 and an absent minimum forwards a negative proposal (`FR-L`,
`aFrameNeverAnswersANegativeSize`). An infinite maximum answers ∞ at an infinite
proposal (`CN-F`, retiring divergence 37). A `VStack(alignment: .leading)` is the one container in which
a frame's answer is observable as an x
(`aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`).

**Unprobed kernel behaviour that fails silently** (by reading):
- A custom `ProposalLayout` that answers ∞ at both main 0 and main ∞ gets a NaN
  flexibility and an inconsistent order within its priority group
  (`solveLinearStack`; unprobed, unpinned).
- A custom layout has no spacing preference: it spaces as SwiftUI's default
  `Layout.spacing` does (V3).
- A same-axis nested stack's trailing zero-spacing edge comes from its last
  child's trailing edge by symmetry with V1k; no probe arm or test has a last
  child whose two edges differ, and mutating it leaves the suite green (record
  §17, mutation F).
- `.opacity` out of 0…1 traps at **paint**, not at registration (outside
  `SA-J`'s scope).
- No built-in proposal type or modifier wrapper has `.id()`; only
  `ProposalScrollView` takes an id, so the trailing-sibling remedy cannot name
  a built-in proposal element. A custom element or `Component` conformed to
  `ProposalElementGroup` can still declare `var elementID` (the demo's
  `PreviewToggle` does, `main.swift:921`). `@State`
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
- **A probe whose every arm agrees with two candidate rules has not
  distinguished them.** The 54-arm frame probe fitted `base = proposal`
  because every arm with a maximum proposed MORE than its child answered; a
  second probe with the separating arm refuted it (`FR-M`). Write the
  separating arm before ruling.
- **A rule read from one arm is unprobed for every node kind that arm does not
  contain.** `CN-H`'s "none for anything else" rested on K3h, a cross-axis
  stack; probe revision 8's V group refuted it for same-axis stacks, custom
  layouts and empty containers.
- **An arm green on arrival cannot see the ruling it is named for; write the
  separating arm** (G4 → G4r/G4f; K2c → K2f–K2j).
- **An instrument that passes can be the finding**: a scratch test written to
  check an inventory claim (`FR-Q`'s "three entry points") passed at x = 32 and
  found a fourth.
- **A helper with two halves needs two per-site guards**: a site that keeps
  the call and does its work outside the closure passes a guard that looks for
  the helper's own emission (`OM-AI`). A `distributes` witness reads each
  member's SIZE, and an order test needs a TWO-layer chain before a per-layer
  mutation can bite (`OM-AD`).
- **A copy of a pinned implementation is unpinned.** Mutate each copy on its
  own. Three typed builder-group entries left the whole suite green (`MC-H`,
  P2–P4) until each had its own test.
- **Parallel tracks each owe tests for the merge, and only the merged suite
  runs them.** Merge red first where a track wrote such a test; the
  `AB-O` × `ModifiedElement` interaction was invisible on both branches
  (record §13). A per-layer mutation that reddens only the integration tests
  is the finding that the tracks' own suites could not see it (record §16,
  M1).

## Human verification — what is closed and what stays open

Full entries, quoted reports and the standing scripts are in record §03.
Nothing in the suite can see paint order, portal hoisting, scroll direction,
drawable presentation, the display link, hover from a real `NSTrackingArea`,
or any of text's three §4.2 failure modes; these are looks.

| milestone | status |
|---|---|
| M0, M1 element pipeline, EP-8 centring, M2 text, clipping/scroll, Stack, absolute positioning (failures 1–2), measure performance (release), input/state, sizing | **closed** by a human look on the dated build — every one of them **before** `.padding` became a wrapper (`f1944f8`) |
| the legacy demo after `f1944f8` | **regressed, then fixed 2026-09-14** (record §03). `.padding` became a wrapper, so the `.alignItems(.stretch)`/`.background`/`.flexGrow` written after it in six `demoContent` sites configured the wrapper: header an 84pt centred card, hairline and sidebar bars gone, list rows centred. **Fixed 2026-09-14** by reordering `demoContent`'s modifiers around `.padding` (container settings and an inner `.flexGrow(1)` before it; size, background and corner radius after it), in the commit after `4e46c8f`. A window capture of the release demo now matches `a15ec83`'s pixel for pixel: 35 of 2,178,560 pixels differ, all desktop outside the window's top-left rounded corner. **Rule for any padded legacy container:** container modifiers and `.flexGrow(1)` before `.padding`, the item size, background and corner radius after it. Not re-taken: the modal (**M**) and the animation look (**A**) |
| the proposal preview (`METALUI_NATIVE_LAYOUT_PREVIEW=1`): text rewraps with window width, the `layoutPriority(1)` panel keeps its width as the window narrows, wheel scrolls the `ProposalScrollView`, the toggle flips colour on click, the dimmed tap under `.allowsHitTesting(false)` does nothing | open, no look recorded. Since task 6 the preview looks different on purpose: the bottom row's toggle is 168×95, the scroll view is as wide as its content (520 at 1024), and at 560×560 the content answers 696×604 and overflows, centred (record §17) |
| absolute positioning failures 3–4 (modal stays put while scrolling; wheel over scrim must **not** scroll the list — inverted since IN-W) | open |
| wheel-mouse scroll distance: run the demo with a **conventional (non-precise) wheel mouse**, not a trackpad or Magic Mouse, and scroll the 500-row list one detent at a time. Report roughly how far one click moves it, in rows (rows are 28pt): about a third of a row per click at a one-line detent means the conversion is live; a thirtieth of a row means it is not. Also report whether it feels comparable to scrolling a native app (e.g. a Finder list) with the same mouse | open. `MetalHostView.scrollDelta(x:y:precise:)` converts lines to points at 10pt per line (`NSScrollView`'s default), verified only with **synthesized** `CGEvent(...units: .line)` events. A real wheel's per-detent line count after the window server's acceleration is **unmeasured**, so the on-screen distance per click is not established. Record §03 |
| measure performance in **debug**; row missing/blank at the bottom edge; reaching row 500; launch hitch | not reported either way |
| tombstones-and-AX §7 item 9 (regression check; the demo cannot exercise its subject) | open, nobody has run the build |
| reactivity §8 item 7: run the demo, idle 30 s, press **M** twice, quit with **Q**, report `frames drawn` / `pauses entered` / `observation dirtyings` — a measurement, not a judgement | open |
| animation §9's "whether the motion looks right" (spec exit criterion 9): press **A**. The sidebar's width (196pt ↔ 320pt, the layout-phase helper) and its background (`.surface` ↔ `.accent`, the paint-phase helper) both read `DemoModel.animationDemoActive` inside one `withAnimation(.spring(duration: 0.6, bounce: 0.2))`, so one keystroke drives both and they can be reported separately | **run 2026-09-10, release, at `b869253` — BOTH animate; the paint-phase helper is confirmed live in production.** Read first as "width slides, colour snaps" and corrected on a second look, so the fade is **not obvious at a glance**. **Overshoot and reverse direction closed 2026-09-10 by a scripted measurement, not a human look** (the running release demo, scripted keystrokes, window captures): the forward press peaks at 114pt and settles at 113pt on screen — the declared 196→320 spring's 1.88pt overshoot at t = 0.500 s, computed from the real `springValue`, lands as a 2-device-pixel rebound because the sidebar is flex-shrunk (SZ-L); the colour overshoots too, (97,167,253) against a (96,165,250) target; and the reverse press animates width and colour 113→73pt. Record §03. **These pixel readings describe the pre-`f1944f8` sidebar** (padding inside the 196pt column); the background now paints from the padding layer (`ModifiedElement`), so they need re-taking |
| accessibility bridge: record §12's VoiceOver script, items 1–9 (activation in both orders, static text, buttons, the list by ear and by Inspector, focus, frames while scrolling, theme and modal, animation noise, identity adoption) | open, nobody has run it |
| tasks 4 and 5 integrated (frame and sizing; outer modifiers): release-window capture of the default demo AND the preview window against a build of `c4b5853`, by `MC-J`'s method | **open**: the display was locked at every capture moment of both tracks and at integration (`IOConsoleLocked` `<true/>` 2026-09-16 09:29; `FR-V`: it has also read `false` on a locked, asleep display, and `docs/probes/appkit-screen-lock-state.swift`'s CGS check has no positive control yet). Stand-in: offscreen `FakePlatformWindow` pixels, ten images, merged vs `c4b5853`, **0 differing pixels and identical scene dumps in all ten**, with an instrument (element padding doubled plus the kernel's frame proposal less 10) that moves every image including the preview (record §16). At 920×560 the preview's content is 594pt tall, centred, overflowing 17pt top and bottom (`FR-U`): a look would report a clipped border |
| containers (plan task 6, `feat/containers`): release-window capture of the default demo and the preview against `9e439cb` | **open**: `IOConsoleLocked` read `<true/>` at every lane and at the record pass. Stand-in: offscreen `FakePlatformWindow` pixels, legacy images 0 differing in all nine, preview 1 109 per 1024 image (three rects: `CN-G`'s toggle and the `CN-M` scroll view) and 65 449 at 560 (every rect: `CN-B`'s distribution and `CN-J`'s centred, overflowing root as well), re-taken by the branch checker with identical figures (record §17). The lock check itself should be the CGS probe (`FR-V`), which no lane ran |
| the focus ring (`focusBorder`) reads as a focus affordance | open: the demo declares none, so a look needs a demo-only commit first |
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

Forty-seven entries; labels are stable ids. Retired and never reused: 3, 5, 6
(sizing, fixed), 7 (renumbering), 8 (`Text.paint` wrap, fixed), 12 and 17
(tombstones, closed for a **bounded** two-generation window above 256
entries), 15 (nested scroll mask, fixed by `OM-U`: `pushClip` adds
`activeOffset`), 36 (legacy frame squeezing an oversized child, fixed by
`CN-N` for a frame over one node), 37 (the kernel frame answering its child at
an infinite proposal, reversed by `CN-F`), 40 (`percent:` taking a fraction,
now spelled `fraction:` with `percent:` deprecated, `CN-O`). Full entries with repro and pins in record §04.

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
| 35 | vs SwiftUI | A legacy frame's finite maximum clamps but never grows into the proposal: `.frame(maxWidth: 80)` over a 20pt child reads 20, SwiftUI 80 (`FR-E`, D4). Pinned wrong on purpose by `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`; task 7 (`CN-Q`). |
| 38 | vs SwiftUI | A negative fixed size or maximum on the proposal path traps at registration (`SA-J`) where SwiftUI diagnoses and floors it at 0 (H6, H10); a negative minimum is floored as SwiftUI does (`FR-L`, `FR-R`). Task 7. |
| 39 | vs SwiftUI | `idealWidth`/`idealHeight` on a legacy frame trap; SwiftUI uses them on an unspecified axis (`FR-D`, C1). Pinned by `anIdealDimensionOnTheLegacyFrameTraps`; task 7. |
| 41 | vs SwiftUI | The default hit region is the element's whole frame; SwiftUI's is content-derived — a stack's empty middle reads 0 (`OM-I`, H1). Pinned by `metalUIsDefaultHitRegionIsTheElementsWholeFrame`. |
| 42 | vs SwiftUI | A padded click target is hittable in its padding, and only when the `onClick` is written after the padding; SwiftUI reads edge 0 in both orders (`OM-K`, P1/P2). Pinned by `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`. |
| 43 | vs SwiftUI | A grown (negative-inset) content shape is intersected with an ancestor's clip; SwiftUI's hits through `.clipped()` (`OM-AJ`, H6). Pinned by `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`. |
| 44 | vs SwiftUI | An inner layer's `allowsHitTesting(false)` does not reach a click on a layer written after it; SwiftUI reads 0/0 in both orders, and a later `.contentShape` restores it (`OM-AL`, X1–X3). Pinned wrong on purpose by `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`. |
| 45 | vs SwiftUI | `.opacity` fades a background written after it, so on the legacy path it fades the receiver's own fill in both orders; SwiftUI (and the proposal path) in one (`OM-N`, `OM-AA` a, G3/G4). Pinned by `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`. |
| 46 | vs SwiftUI | A second `.opacity` on one element replaces the first (0.5); SwiftUI multiplies (0.25) (`OM-AH`, G1/G2). Pinned by `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`. |
| 47 | vs SwiftUI | `.cornerRadius` rounds the fill and border and does not clip the children, `.clipped()` clips; SwiftUI's clips (`OM-G`, C1). Pinned by `aBareCornerRadiusDoesNotClipTheChildren`; the C3/D1 orders are unpinned. |
| 48 | vs SwiftUI | A `Component`'s `width`/`height` overwrite each member's own size; SwiftUI's `.frame` wraps and keeps it (`OM-F`, G7/G8). Pinned by `aComponentsWidthStillOverwritesItsMembersDeclaredWidth`; task 7 (`FR-F`). |
| 49 | vs SwiftUI | `.border.cornerRadius` draws a rounded stroke that follows the arc; SwiftUI draws a square border clipped by the radius (`OM-W`, D2 vs M1). Pinned by `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`. |
| 50 | vs SwiftUI | `.contentShape(inset:)` written before a wrapping modifier, with the `onClick` after it, is inert: the padded layer is hittable over its whole frame (centre/band/edge 1/1/1) where SwiftUI honours the inset (1/0/0); the reverse order agrees (probe S1/S2, record §16). Pinned wrong on purpose by `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`. |
| 51 | vs SwiftUI | `ProposalText` beside `ProposalText` in a `VStack` is 8pt apart; SwiftUI's text edges are font-derived (text\|text 0, rect\|text 4.74, text\|rect 8.15; probe S, `CN-H`). Pinned by `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing`; task 11. |
| 52 | vs SwiftUI | Legacy `Row`/`Column` default to gap 0; `HStack`/`VStack` to 8 (probe S, `CN-P` 1). Pinned by `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`; task 7. |
| 53 | vs SwiftUI | A legacy `Stack` offers a child fit-content; `ZStack` offers its proposal (A5: a greedy child fills 100×80; a childless `Box` is 0×0) (`CN-P` 2). Pinned by `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal`; task 7. |
| 54 | vs SwiftUI | A legacy `ScrollView` takes its cross axis from its parent; SwiftUI's takes its content's (SC2, `CN-P` 3). Pinned by `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`; task 7. |
| 55 | vs SwiftUI | Legacy `Row`/`Column` compress by flex-shrink in proportion to base size and expand only by `flexGrow`, with no `Spacer`; a SwiftUI stack serves least flexible first (G1, `CN-P` 4). Covered by the CSS goldens; task 7. |
| 56 | vs SwiftUI | A legacy `.frame` over a multi-member `Component` lays the members out as a flex row; SwiftUI frames each member (G7, `CN-N`). Pinned as it stands by `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` and `chainedFramesRemainConcreteAndNestTheirLayoutNodes`; task 7. |
| 57 | vs SwiftUI | A non-clickable proposal primary does not block a click to its `.background` content; SwiftUI's does (overlay-presentation H3, `CN-K`). Unpinned; task 12. |
| 58 | design | A `ZStack` placed by a kernel caller in bounds larger than its answer puts the union of its children at the bounds' origin (`CN-E`); SwiftUI has no such placement. Pinned by `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`. |
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
| `Style.border` on a container | shrinks the content box and paints nothing (the engine discards the resolved edges; `paintDecoration` reads only `Decoration`'s borders). Unreachable from modifiers since `borderWidth(_:)` was deleted (`OM-M`), reachable via `Box(style:)`, on `margin: .auto`'s footing. Not the paint-only `.border(_:width:)`. By reading, unpinned |
| `Position.relative`'s offset | makes a containing block, does not shift the box |
| `Style.alignSelf` on a `Stack` child | ignored entirely |
| `Style.padding`/`border`/`margin` on a **leaf** (`Text`) | **not** the `.padding(_:)` modifier on an element, which now wraps in a `ModifiedElement` layer: it offsets and enlarges the outer footprint of a fixed-size custom `StyledElement` (`paddingWrapsAnElementAndExpandsItsOuterFootprint`, whose `Leaf` is not a `Text`); that it does the same for a `Text` is by reading, unpinned. Holds for `Style.padding`/`Style.border` set directly and `.margin`: ignored on a **content-sized** leaf: no size moves, and it stays out of §9.7.4.c's shrink weight (`aContentSizedMeasuredLeafsPaddingDoesNotComeOffItsShrinkWeight`). **Not inert once the leaf declares a main size**: ruling BM-4 puts the padding inside that base, so it comes off the shrink weight as CSS says — a 200 row of two `width: 200px` measured leaves, one with `padding: 0 40px`, lays out 125 / 75 (`aMeasuredLeafWithADeclaredSizeIsWeightedByItsInnerBaseSize`) |
| `hidden()` on a subtree that draws or is focusable | layout filters it, paint does not: glyphs stack at the window's top-left; a hidden focusable still claims keystrokes. Use a builder `if` instead. Directly after a one-node legacy `.frame` it filters layout and accessibility as anywhere else (`CN-N`'s regression, fixed: `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`, `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`) |
| `AnyElement` | works when hand-written; the builder never produces one and must not |
| `@State` inside `AnyElement` | silently inert |
| `PaintPass.isActive` | correct, pinned, consulted by no built-in element — nothing paints a pressed state |
| `PlatformWindow.onInput`'s `-> Bool` | `Window` computes it and `AppKitWindow` forwards it one hop; all seven `MetalHostView` event overrides discard it (`_ = onInput?(…)`, no `super`), so AppKit never sees it and an unhandled event never continues down the responder chain. Only the fake reads it. Do not wire `super.keyDown` in without an `NSMenu`: every unbound key beeps |
| colour glyphs | tinted luminance silhouettes |
| `HStack(spacing:alignment:content:)` / `VStack(spacing:alignment:content:)`, the deprecated spacing-first initializers | take a nine-case `ProposalAlignment` and read only its cross-axis factor: `.leading` on an `HStack` places as `.center`. The current `init(alignment:spacing:content:)` takes `VerticalAlignment` / `HorizontalAlignment` and rejects the other axis at compile time (`CN-I`, guards G1–G3); delete this row with the deprecated initializers |
| `LayoutMeasurement.firstBaseline`/`lastBaseline` | no producer (`ProposalText` reports none) and no consumer; frame, padding, aspect-ratio, `.fixedSize`, `.layoutPriority` and the `.overlay` modifier (`overlayAttachment`, which returns its primary's measurement) carry them; `ZStack` (the `.overlay` node), linear stacks and the scroll viewport drop them (`LayoutTree.swift` `measureNative`). No baseline alignment exists |
| `ProposedSize.zero` / `.infinity` | no container proposes them on both axes; linear stacks do ask each child for its main-axis minimum and maximum (main 0 and main ∞, cross proposal kept, `CN-B`) |
| `.allowsHitTesting(false)` over a scroller, on either path | gates click hitboxes only; a `ScrollView`/`ProposalScrollView` inside still scrolls and still wins topmost-opaque (the legacy modifier: `OM-AK`, `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`) |
| `contentShape(inset:)` on an element with no `onClick` | writes `Handlers.contentShapeInset`, registers nothing (`OM-AB`, `aContentShapeWithoutAClickHandlerRegistersNothing`); on a chain, `contentShape(inset:)` or `allowsHitTesting(false)` on an inner layer reaches no click written on a later layer (divergences 44, 50) |
| a single-axis `.frame(maxWidth: .infinity)` or `.frame(maxHeight: .infinity)` on a legacy element | a layer that costs a node, an id level and a `$anim` entry and does not fill; only the both-axes spelling lowers to `flexGrow = 1` + `alignSelf = .stretch` (`FR-O`, `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite`); task 7 (`CN-Q`) |
| `.flexGrow` / `.alignSelf` on the only child of a legacy `.frame` | the one-node frame is a `display: .stack`, which reads neither; both compile and do nothing, the fill idiom `.flexGrow(1).frame(maxWidth: .infinity, maxHeight: .infinity)` included; `width(fraction: 1)`/`height(fraction: 1)` fill (`CN-N`, `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`) |
| `ElementGroup.frame()` / `ProposalElementGroup.frame()` with no arguments | deprecated no-ops returning `self` (`FR-J`, guard `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`); declared on BOTH protocols on purpose — on `ElementGroup` alone the proposal call resolves to the all-defaulted fixed overload and builds a layer silently |
| `GlyphAtlas.evictUnusedSince`, `LayoutTree.reset(generation:)` | zero callers; guards kept for whoever calls them |
| `Frame.scrollRegions` / `Window.lastScrollRegions`, `StateTable.isDirty`, `StateTable.writeCount`, `LayoutTree.lastNativeLayoutWork`, `MeasurementSubview.isSpacer` / `PlacementSubview.isSpacer` | test observables with no production reader (`isSpacer`: read by no built-in since `CN-B`) |
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
`NativeLayoutWorkTests.swift` one call is 64 measure calls, 51 hits, 90 misses
(`CN-B`: stacks probe children at main 0 and ∞; 16 / 27 / 25 before); nested
alternating stacks cost up to ~11 leaf calls per leaf, and a `ProposalText` in
a stack is shaped at 4 widths per cold frame, not 2.
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
  `Modules` directory, so under it alone **all 70 guards skip**, the total does
  not move and the run passes. `--build-system native` writes
  `.build/<triple>/debug/Modules`, **and that directory survives**: once a
  checkout has ever been built that way the guards run under the default system
  too, against those **leftover** modules rather than what swiftbuild just
  built. Both halves measured at `b869253`. **So take the guard count under
  `--build-system native`, and know the number does not tell you whether any
  guard ran** — a mutation run in a `git worktree` executes none of them at all.
  Some guards print their fixture result: grep a log for `FR-J no-argument
  frame: succeeded=`, `FR-S overload resolution: succeeded=` and
  `OM-B/OM-N/OM-T collision` to know those ran.
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
