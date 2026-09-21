# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift. **macOS only today** (`platforms: [.macOS(.v14)]`, no UIKit,
`App.swift` builds `AppKitPlatform` unguarded, no `.touch` input). The spec's
iOS target is unmet. `PlatformWindow`'s `onAccessibilityRequest` and
`publishAccessibilityTree(_:)` have no default implementations (`AB-R`).

**This file is rules only.** The full pre-2026-09-21 version (120 KB: every
test name, divergence row, inert row, human-verification row, performance
figure and CI hazard) is `docs/record/19-claude-md-full-2026-09-21.md`; below,
"§19 <section>" points into it. Reasoning and history live in `docs/record/`
(`README.md` indexes it). Citations in the record were not all re-checked after
later refactors — verify a test name or grep before relying on it. New
milestones append their record to `docs/record/` and put only the rule here.

`AGENTS.md` is a byte-identical copy for Codex: edit `CLAUDE.md`, then
`cp CLAUDE.md AGENTS.md`; check `cmp CLAUDE.md AGENTS.md` before committing.

## Where things are

- **Design spec (binding):** `docs/superpowers/specs/2026-08-24-metalui-design.md`;
  per-milestone specs and plans beside it in `specs/` and `plans/`.
- **Decisions docs:** `docs/superpowers/<date>-<milestone>-decisions.md`, one
  per milestone; read their "Carried…" sections before new work. Ruling ids
  are namespaced by prefix — numbered: `F-`/`PF-`/`C-` (m0/m1a; bare `F-1` is
  ambiguous), `FS-`, `AL-`, `BM-`, `WR-`, `EP-` (`EP-2`/`EP-4` never
  assigned); lettered: `CS-`, `SI-`, `TX-`, `CL-`, `ST-`, `AP-`, `MP-`, `IN-`,
  `SZ-`, `TB-`, `RX-`, `CO-` (next `CO-AA`), `AN-` (next `AN-X`; its letters do
  not track its ledger's), `SA-` (next `SA-V`), `MC-` (next `MC-T`), `EV-`
  (next `EV-AA`), `AB-` (next `AB-AH`), `FR-` (next `FR-W`), `OM-` (next
  `OM-AN`), `CN-` (next `CN-V`), `LR-` (next `LR-AB`). A numbered citation of a
  lettered prefix (`CS-3`, `LR-3`) is a typo; sweep case-insensitively.
- **SwiftUI-alignment plan:** `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`.
  Its 2026-09-12 kernel/modifier specs describe types never built; **the
  source is the authority**. Per task: spec in `specs/`, decisions doc, record
  file — task 2 `SA-` (§09), 3 `MC-` (§10), 9 `EV-` (§11), 12 `AB-` (§12),
  3/9/12 integration (§13), 4 `FR-` (§14), 5 `OM-` (§15), 4/5 integration
  (§16), 6 `CN-` (§17), 7 stage 1 of 14 `LR-` (§18, spec
  `specs/2026-09-17-engine-replacement-design.md`).
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.

## Build and test

```bash
swift build
swift test --no-parallel
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc   # suite total
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # proposal preview (value exactly "1")
```

- **Counts (2026-09-17, `feat/engine-replacement`): 1409 tests, 97 goldens,
  71 typecheck guards**, 0 `error:`, 0 `warning:`, taken after `swift package
  clean` with `swift build --build-system native --build-tests` then
  unfiltered `swift test --build-system native --no-parallel`. History: record
  §06, §19 "Build and test". A count is stale the moment a test lands; re-measure.
- **Read the printed counts, never the exit status.** `--build-system native`
  prints ONE summary line; the default build system may print six (sum them).
  Two gated tests count toward the total while skipped. The lone `warning:`
  under native is SwiftPM's deprecation notice.
- **Goldens must not move** on a change outside `Sources/MetalUILayout/`
  (`find Tests -name "*.json" | wc -l`). WebKit is the oracle for the CSS
  engine only. The proposal kernel shares `LayoutTree.swift` storage
  (`newNode`, `reset`, `roundLayout`, the `SA-G`/`SA-I` preconditions), so a
  proposal-path edit there can move a golden — run the fixtures. No text
  fixture, ever (TX-B).
- **Guards:** `grep -c canTypecheck` per file across `PhaseSeparationTests`,
  `ErasureCompileGuards`, `ElementGroupTrapTests`, `ProposalLayoutCompileGuards`,
  `ModifiedElementCompileGuards`, `ProposalNodeIDCompileGuards`,
  `EnvironmentCompileGuards`, `FrameSizingCompileGuards`,
  `DecorationCompileGuards`, `ContainerCompileGuards`,
  `LayoutAuthorityCompileGuards`, `UnitSafetyTests` (one hit is a comment),
  `AXNodeTests`; `Typecheck.swift` holds only the declaration. Two helpers:
  `typecheck(_:importing:)` wraps the fixture in a function (Swift 5, nothing
  `public`/file-scope compiles); `typecheckFile(_:importing:)` is whole-file
  Swift 6. A guard about what an external module can write uses
  `typecheckFile` (`SA-P`). **Guards skip silently** when
  `.build/<triple>/debug/Modules` is not where `#filePath` expects
  (default swiftbuild system, `--scratch-path`, `-c release`, a worktree) —
  the total does not move and the run passes.
- **Adding an AppKit or WebKit test? Run the whole suite unfiltered** (shared
  process and run loop; `--filter` is a different program).
- **`swift package clean` when the impossible happens**: SIGSEGV, a truncated
  run with no summary line, an expected value its source cannot produce, or
  `Undefined symbols … direct field offset`. Causes: the untracked shader
  header symlink (`Sources/MetalUIShaderTypes/include/`), and any new
  case/stored property on a public type crossing a module boundary.
- **Targets:** nine one-way-dependent (`MetalUICore`, `MetalUILayout`,
  `MetalUIText`, `MetalUIShaderTypes`, `MetalUIRender`, `MetalUIPlatform`,
  `MetalUI`, `MetalUIDemoContent`, `MetalUIDemo`) plus `Tests/MetalUITestSupport`.
  `MetalUIDemoContent` holds the demo tree so tests can import it (`LR-S`).

Four constraints that fail silently:

- `MetalUILayout` imports only `MetalUICore` (anchored grep).
- Every `LayoutTree` that could exchange ids needs a distinct `generation`
  (C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` (gamma-space compositing, §7.8).
- Percentage `padding`/`border` resolve against the containing block's
  **width** on every edge; `Style.inset` is horizontal-vs-width,
  vertical-vs-height (AP-D).

## Architecture rules

Detail and pinning tests for every paragraph: §19 "Architecture rules", record §01.

**Phases.** `requestLayout` → `prepaint` → `paint`. `isHovered`, `isActive`,
`isFocused` exist only on `PaintPass`, each typecheck-guarded; a new
paint-only query gains a guard and a bullet in `PhaseSeparationTests.swift`'s
header in the same change.

**Identity is structural; `.id()` overrides a position, never joins it.**
- A vanishing `if` makes the **trailing sibling adopt** its state, focus and
  click dispatch. Remedy: name the trailing sibling.
- `.padding(_:)` and every legacy `.frame(...)` return one flat
  `ModifiedElement<LayerBase>` (`MC-A`); each modifier is one layer = one node
  = one id level; outermost layer takes the parent's slot, inner layers are
  `positional(0)`, content numbers from 0 under the innermost (`MC-C`).
  **`.id()` must be the outermost modifier.** Changing layer COUNT resets the
  wrapped element's `@State`/focus/`$anim`/AX node; changing VALUES does not.
  A decoration/handler written after a wrapper configures the outermost layer
  (`.padding(8).background` fills the padded box, `OM-C`).
- An `.overlay`'s primary numbers under the modifier's id, the overlay under
  `.child(of: id, at: -1)` (`MC-P`); nothing else may mean `-1`.
- `GlobalElementID.cachedHash` and `==` are safe alone, unsafe together; do not
  simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ above the engine (EP-5).

**Legacy containers.** `Column`/`Row` centre on the cross axis, `Box`
stretches (EP-8, set in inits) — a childless `Box` with no cross size paints
nothing. **Modifier order decides which box a modifier reaches**: container
modifiers (`.alignItems`, `.gap`, `.justifyContent`) and item modifiers
(`.flexGrow`, `.alignSelf`, `.margin`) go **before** `.padding`; size,
background and corner radius **after** it. All wrong orders compile. Chained
`.padding` accumulates. They keep their CSS algorithms (`CN-A`, `CN-P`):
`Row`/`Column` gap 0 vs `HStack`/`VStack` 8; `Stack` offers fit-content vs
`ZStack` its proposal; porting `Row {}` → `HStack {}` changes behaviour
silently. `Stack` layers last-on-top; no `display: contents`, no z-index.

**Legacy `.frame`** has SwiftUI's full parameter surface and lowers to one
`Style` in `FrameLayer.swift` `FrameSpec.style()` (`FR-C`): fixed axes pinned
by `size` + axis-named `minSize` (never `flexShrink = 0`, `FR-P`); fill only
when BOTH maximums are infinite (`FR-O`). Over exactly one node it lowers to a
one-cell `display: .stack` (`CN-N`) — the child overflows, and `.flexGrow`/
`.alignSelf` on it do nothing (`width(fraction: 1)` fills); `lowered` must
keep `display: .none`. Over 0 or ≥2 nodes it stays a flex row. `idealWidth`/
`idealHeight` trap at legacy registration (`LR-H`). `.frame()` with no args is
a deprecated no-op on both paths. **`ElementGroup` keeps exactly ONE fixed
`frame` overload** (`FR-S`). The two hand-spelled `frameStyle` oracles in
`ModifiedElementTests`/`ModifierCompositionProofTests` must change with the
lowering.

**Sizing modifiers** (`width`, `height`, `min/max…`, `width(fraction:)`,
`height(fraction:)`) write the element's own box and return `Self`; `.frame`
wraps (`FR-F`). Not deprecated (`FR-I`). `.minHeight(0)` is the only way to
cancel flex's automatic minimum (`FR-G`). `fraction: 0.5` is half; `percent:`
is a deprecated rename that still takes a fraction (`CN-O`).

**`List`** is a windowed `Box`: needs `Identifiable` data, uniform `rowHeight`,
an enclosing `ScrollView`, and being that scroller's **only**
layout-contributing child (else blank, divergence 14). Frame 0 builds every
row. Rows out of window >2 generations lose `@State` once the table exceeds
256 entries (TB-AH) — keep durable values in data. Publishes an `AXTable` of
realized rows only.

**`Deferred`** is a portal: one child, no layout node, hoists to the root
layer, resets clip and scroll offset (AP-I) but **not opacity** (`OM-AA`).
One element contributes one opacity scope (divergence 46). Absolute
positioning is `.position(.absolute)` + `.inset(...)`. A tooltip needs the
portal; a modal needs both.

**`Component`** is layout-transparent and identity-opaque: no layout node, one
cursor index, `@State` under its own id. Its `.padding` wraps each top-level
node (`OM-D`); `.width`/`.height` **overwrite** each member (divergence 48);
`.frame` wraps the body in one layer. No `.background`/`.id()` (declare `var
elementID`) — by type only, and `anyComponent.frame(...)` is a side door. A
caller's modifier on a component never animates (B-7): declare animated sizes
inside it. Over proposal content declare `some ProposalElementGroup`.

**`@State`** is a box seeded by reflection per element per frame; slots are
`.named("$state<n>")`. Seven reserved names (`$state<n>`, `$focus`, `$ax`,
`$anim`, `$anim-color` slots; `$anim-content`/`$anim-viewport` id prefixes),
pinned by `theSevenRetentionSlotsAreMutuallyDistinct`. **Write from input,
never from a phase** (keeps the link awake forever). Inert inside
`AnyElement`. `prepaintGroup`/`paintGroup` re-bind, so a group-entry bind is
observable only at layout time. One element VALUE placed twice shares one box
(divergence 19) — build two values.

**`@Observable`**: the whole frame build is tracked. The `RedrawSentinel`, the
flush ordering in `drawFrameIfNeeded`, the `isFlushing` guard and
`markDirtyFromObservation`'s two branches are all load-bearing (RX-K);
collapsing either branch breaks the suite. A phase-time `@Observable` write is
silently stale.

**Hit testing.** One hitbox list; ranking is `topmostOpaqueHitbox(in:at:)` —
no second copy. `onClick` alone makes an opaque pointer target; the keyboard
gate (`onKey || isFocusable || actions || keyContext`) stays separate.
`allowsHitTesting(false)` gates only `registerHandlers`' pointer hitbox —
scroll regions and raw `insertHitbox` bypass it (`OM-AK`); it is per layer
(divergence 44). `contentShape(inset:)` moves the pointer region only and
needs an `onClick` on its layer (`OM-J`, `OM-AB`). Default hit region is the
whole frame (41). Handlers outlive the frame: `.onClick { window.x() }` is a
retain cycle.

**`StyledElement`** has four requirements (`style`, `decoration`, `elementID`,
`handlers`). A conformer calls `registerAndScope(handlers, decoration, …) {
content }` in `prepaint` and `paintDecoration(decoration, in:, for:) { content
}` in `paint` (background before content, border after, `OM-V`). Sites: `Box`,
`Stack`, `Text`, `ModifiedElement` (per layer). Each helper half has its own
per-site guard (`OM-AI`) — doing the work outside the closure passes one and
fails the other. `registerHandlers` holds the hitbox, focus, AX record and the
disabled gate; skipping it makes an element ungated and invisible to
VoiceOver. **Any hook added to `Element`'s group defaults must be mirrored per
layer in `ModifiedElement` and in `AnyElement`'s group entry** (`MC-B`,
`LR-AA`). `Handlers` has eight members; `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) each gain a field when it
gains one.

**Environment (`EV-`).** `EnvironmentScope` is layout- and
identity-transparent; nearest writer wins; transforms run once per frame in
layout and are re-pushed (`EV-V`). Readable in every phase except `theme`
(`PaintPass` only). `@Environment` binds like `@State`; unbound it silently
reads defaults. `Window.environment` writes always dirty — write from input.
`theme`/`pixelLength` are re-stamped each frame. **A modifier written after a
scope sits outside it** (`EV-X`). `.disabled(d)` is
`transformEnvironment(\.isEnabled) { $0 = $0 && !d }` (`EV-D`); the one gate
is in `Frame.registerHandlers`' **5-argument** implementation. Disabled: no
hitbox, nothing in the focus registry, still published to AX as disabled.
Scroll regions are outside the gate. A new handler-registering site gains an
arm in the D2 guard. `Binding` is a deprecated alias of `KeyBinding`, deleted
by task 10.

**Accessibility (`AB-`).** Nothing recorded until a client activates the
window (sticky). Synthesized nodes are records (`Frame.axEmissions`), never
`axNodes` or `$ax` (`AB-U`). Geometry is not structure (`AB-K`). Every
`NSAccessibility` override answers through `mainActorAnswer(_:fallback:_:)`,
never a bare `assumeIsolated` (`AB-AE`). A `display: none` layer suppresses
everything inside via `Frame.suppressingAccessibilityIfHidden` (`AB-O`). A
text-painting conformer passes `accessibleText:`. Qualify
`MetalUIPlatform.AccessibilityRequest` in files importing AppKit.

**Focus:** `Window.focus(_:)` is the only mover; clicking does not focus. Keys
go to the `Keymap` first, then bubble raw `onKey` up the parent chain.
`focusBorder(_:width:)` is the (opt-in) ring; background and border resolve
`focus ?? hover ?? plain`.

**Text.** Never key a cache on a family or PostScript name — `FontKey` reads
four components off the resolved `CTFont` (and still conflates shaping
behaviour, pinned wrong on purpose). `FontKey` stores its hash; `==` uses it
as early reject only; to force collisions under mutation make the **stored**
hash constant. `FontResolver.resolve` traps on non-finite/non-positive sizes.
`fonts` and `resolvedFonts` are never swept, deliberately — move both or
neither. Min-content is `CFStringTokenizer`'s longest word (TX-F); the public
`unbreakableRuns(of:)` must create a tokenizer per call; every path bumps
`Shaper.runCallCounter`. Max-content is one line per hard break (TX-K). The
glyph atlas is grow-only; `evictUnusedSince` has no caller and would strand
pixels.

**Renderer.** No semaphore; the atlas texture is written only while
`atlasTextureWasEncoded` is false, else replaced. `Text.requestLayout` and
`ProposalText`'s measure closures use unguarded `MainActor.assumeIsolated` —
layout must stay synchronous on the main actor.

**Animation (`AN-`).** `withAnimation` writes `pendingTransaction` (lexical)
and `parkedTransaction` (handed to exactly one frame build). The park rolls
back unless a frame build is coming; both clauses are measured fixes.
Layout-phase helper `animated(_:_:for:pass:)` (`AnimatedStyle.swift`); colour
helper `animatedBackground` in paint (`AnimatedColor.swift`, needs the theme).
A site that skips its helper is silently unanimated — guards
`everyRegisteringSiteAnimatesItsStyle`, `everyBackgroundPaintingSiteAnimatesItsColour`.
Interpolation is per-component RGB, never hue; slots store tokens. "Live" is
`Frame.noteActiveAnimation()` → `hasActiveAnimations`, copied after the whole
render; **not** `wantsAnotherFrame` — never raise both. **Snaps:** any
`Dimension`/`Length` case change (incl. anything touching `.auto` — declare a
real baseline), the five paint-only `Decoration` fields, a caller's modifier
on a `Component`, everything on the proposal path. Tests never sleep: drive
`simulateTick(timestamp:)`.

## SwiftUI alignment — the proposal layout path

A propose/measure/place engine sits beside the CSS engine. Detail: §19
"SwiftUI alignment", record §09, §17, §18.

- **Two engines, chosen by the window root alone**
  (`tree.isNativeLayoutNode(root)`). A native root is placed centred at its own
  answer (`CN-J`). The kernel is the private `NativeNode` enum in
  `LayoutTree.swift` (eleven cases + `custom(any ProposalLayout)`); a new case
  must choose its zero-spacing edges.
- **Layout authority (task 7, `LR-`):** `Frame.layoutAuthority`, `.legacy` in
  production, internal until stage 6b. Under `.proposal` every legacy site
  checks the authority itself and lowers (border-box: content → padding →
  fixed frame, built from the **animated** style, checked against the
  declared); unlowerable fields trap naming `<site>.<field>` or, with
  `reportsUnlowerableFields`, report. **A new legacy registration site gains
  its own check and an arm in `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.**
  A branch lowering from a style needs an animated arm. Differential harness:
  `LayoutDifferential.compare` under `DifferentialRoot`; never a wrapping
  `Text` or greedy child directly under the root; a window test under
  `.proposal` pre-flights under diagnostics with `try #require` on an empty
  report. The bounds log is recorded at four sites; a new group entry records
  too.
- **`ProposalLayout`** (`SA-A`…`SA-F`): `sizeThatFits` + `placeSubviews`, no
  cache. Measurement cannot place (compile-time); `place` only records, last
  wins, unplaced is centred. Migration: leaf → `requestNativeLeaf`; algorithm
  → `ProposalLayout`; container with paint/input → `requestGroupLayout` +
  `requestNativeLayout`.
- **Stacks are SwiftUI's** (`CN-B`…`CN-I`, probe
  `swiftui-stack-algorithms.swift`): priority groups, least-flexible-first,
  overflow counted; `Spacer` priority −∞, default min 8; default spacing per
  adjacent pair (`CN-H`); typed alignment (`CN-I`); `ZStack` places each child
  at its own size in the union (`CN-E`); infinite proposal answered with ∞ by
  infinite-max frames, spacers, scroll axes (`CN-F`). Flexible frame is greedy
  (`FR-A`, `FR-M`; test is on the minimum's presence).
- **One authority per root, no adapter** (`SA-G`): native-under-legacy,
  legacy-under-native, a `Style` on a native node, `computeLayout` on a native
  root all trap. `ProposalElementGroup` has one requirement returning
  `[ProposalNodeID]`; `ProposalNodeID`'s init is internal (`MC-G`). One id
  registered under two parents traps (`CN-L`). **A copy of a pinned entry is
  unpinned**: the typed builder-group entries and `EnvironmentScope`'s are
  line-for-line copies, each with its own pin; a new group gets its own.
  Single-child proposal wrappers precondition exactly one node.
- **Invalidation** (`SA-H`, `SA-I`): the cache lives for one call; answers
  assumed pure; `setLayout` traps during measurement; **one `isLayingOut` flag
  guards both engines — do not split it.**
- **Validation** (`SA-J`, `SA-K`): reject a parameter only if SwiftUI rejects
  it or it would make a node non-finite at a finite proposal. Measurements may
  be infinite, stored rects may not, nothing may be NaN. Relaxing a trap into a
  clamp later is additive; the reverse breaks callers.
- **Depth guard** `NativeLayoutRun.maxDepth` = 88 (`SA-L`); raise only after
  re-bisecting all four node kinds. **Work counters:**
  `LayoutTree.lastNativeLayoutWork` (`SA-M`) on a branching tree, literals
  derived before the run.
- **Vocabulary.** Proposal types: `HStack(alignment:spacing:)`,
  `VStack(alignment:spacing:)`, `ZStack`, `Spacer`, `Rectangle`, `Color`,
  `ProposalFrame` (not `Frame`), `Padding`, `Background`, `FixedSize`,
  `ProposalScrollView`, `ProposalText`, `ProposalLayoutContainer`. Modifiers
  on `ProposalElementGroup` return `ModifiedContent`. `Native…` types and
  `native…` methods are deprecated aliases (except the two `nativeFrame`
  overloads — deprecating them breaks the 0-warning baseline); the kernel's
  `requestNative*`/`newNative*`/`computeNativeLayout` are primary API.
  `.padding` splits by argument type (no proposal `.padding(Pixels)`).
  `Text.proposalLayout()` silently drops background, handlers, id and
  hover/focus colours. `ProposalScrollView`'s clamp and indicator are private
  copies of `ScrollView`'s — fix both.

## Workflows and subagents — token budget

A five-lane stage has cost 6–12M tokens (~25 Opus 1M-context agents at
0.2–0.5M each; every agent loads this file). When writing a workflow:

- **Two or three lanes, not five.** Split only where lanes touch disjoint
  files; each lane pays to load the same code.
- **Model by job:** Opus for design, implementation and mutation
  verification; `model: 'sonnet'` for record, docs, count re-takes, greps and
  first-pass checks.
- **Merge adjacent agents over the same material:** critique + revise in one
  agent, record + docs in one agent.
- **Re-verify only on a finding.** No fix/re-verify round when the verifier
  returned `ok`.
- **Pass paths, not content.** Prompts name the files, rulings and record
  sections an agent needs; agents return conclusions (a verdict, a mutation
  table, a diff summary), not file dumps.
- Stay under the session's workflow size guideline unless the user asks for
  more.

## Practices — the short form

Read `docs/practices/verifying-tests-can-fail.md`; history in record §02.

- **Findings come from mutation, not inspection.** Change the declaration a
  test is named for and confirm it reddens — by running it. Require the arms
  of a comparison to disagree before believing they agree (shape 15).
- **A mutation that reddens nothing is a broken instrument or the finding**;
  prove the mutant differs. Name the tests it reddens, not a count.
- **Any count a later loop indexes on is `try #require`** (shape 13).
- **A `@testable` test cannot prove an access-level narrowing** (shape 16);
  use a plain-import typecheck guard, written in the change that introduces
  the hazard.
- **When a claim is refuted, fix everywhere it was copied** — spec, plan,
  source comment, this file, the record. Re-take whole tables, not sampled rows.
- **A confident "cannot" that was not measured is the tell** (shape 14).
- **Reviewer dispatches say not to invoke the `code-review` skill.** Run
  mutation testing in an isolated `git worktree` when another agent is live.
- **Performance tests count work, never wall clock**, are red on arrival, and
  use a branching tree in a configuration where the code is reachable.
  Allocation counts (`malloc_logger`) are taken in the suite's configuration.
- **A probe must have a separating arm** before a ruling rests on it (`FR-M`);
  a rule read from one arm is unprobed for node kinds that arm lacks.
- **A helper with two halves needs two per-site guards** (`OM-AI`); an order
  test needs a two-layer chain (`OM-AD`).
- **A copy of a pinned implementation is unpinned** — mutate each copy.
- **Parallel tracks owe tests for the merge**; only the merged suite runs them.
- **A green mutant may be the correct spelling** (`LR-X`).
- **A window test in a mode that traps pre-flights in a mode that reports.**

## Reference tables (moved to the record)

Consult before changing the behaviour they describe; each is a table of
expected, measured facts:

- **Known divergences** (48 live, stable labels; retired labels never reused:
  3, 5–8, 12, 15, 17, 36, 37, 40) — §19 "Known divergences", record §04.
  Many are *pinned wrong on purpose*; a test named for one reddening may be
  a fix, not a bug.
- **Declared but inert** APIs (compile and do nothing: `AlignItems.baseline`,
  `Style.aspectRatio`/`overflow`, `margin: .auto`, `Style.border` on a
  container, `Position.relative` offset, `hidden()` on drawing/focusable
  subtrees, `AnyElement`'s `@State`, `PaintPass.isActive`, `onInput`'s `->
  Bool`, colour glyphs, baselines, `LayoutAuthority.proposal` in production,
  `locale`/`layoutDirection`/`dynamicTypeSize`, …) — §19 "Declared but
  inert", record §05. Implementing one: delete its row; adding an
  unimplementable property: add one.
- **Human verification** status per milestone, demo keys (**M** modal,
  **Space** theme, **F**/**Esc** focus, **=**/**-** count, **A** animation,
  **Q** quit) and open looks — §19 "Human verification", record §03. Nothing
  in the suite sees paint order, portals, scroll direction, presentation, the
  display link or real hover; those are looks. Padded legacy container rule:
  container modifiers and `.flexGrow(1)` before `.padding`; size, background,
  corner radius after.
- **Performance** figures (µs/node, warm frame, cold `List`, native work
  counts) — §19 "Performance", record §07. Most are stale since `f1944f8`;
  re-measure before reasoning from them.
- **CI hazards** — §19 "CI", record §08. Key ones: guards skip under the
  default build system (take guard counts under `--build-system native`, and
  grep logs for `FR-J no-argument frame: succeeded=` to know guards ran); the
  freeze-loop allocation pin checks only half itself on Apple toolchains
  (`FREEZE-ALLOC: strict per-pass bound NOT CHECKED`); `malloc_logger` tests
  need `--no-parallel`; E24 hard-fails under the root locale; seven
  `AnimationTests` hard-fail without a display device.
