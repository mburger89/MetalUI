# 92 — Overlays and coordinates, `anchoredOverlay` and named spaces

Branch `feat/overlays-coords` from `ebcf3c7`, merged with master `280d706`
(C12 §89, item 8 §91; §90 is the shadow cache already in the base). **Not a
plan task**: item C15 of the gpui-gap priority list, user request 2026-10-02,
for MetalCreator's editor polish (`docs/metalui-gaps.md` EP-a and EP-b, checked
on `c62d6ba`). Spec `docs/superpowers/specs/2026-10-10-overlays-coords-design.md`;
rulings `OV-A`…`OV-T` in the new decisions doc
`docs/superpowers/2026-10-10-overlays-coords-decisions.md` (next unused
`OV-U`); probes `docs/probes/swiftui-overlays-coords.swift` (arms A, B, G, W)
and `swiftui-overlays-coords-typecheck.sh` (T0–T16).

**Numbering.** Written as §92 from the start (§89 and §91 were reserved by the
parallel `fix/smk-port-gaps` and `feat/test-harness`, both merged before this
record; §90 was already in the base); no renumbering. Divergence labels were
reserved 225–234; **only 225 is used**. The human-checks group is **OV**; its
section sits between `PF` and `SG` because the branch wrote it before the merge
(the merge kept all three). The divergences header's "live" count and next
label were left for the merge to settle, as the brief said: 225 is the row this
branch adds.

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group OV, §8). Two lanes, A
(coordinates) then B (presentation), each red first against a stub, each with a
review round, both verified `ok: true`. The session was paused by the weekly
limit during lane B; lane B's implementer committed the red (`5755b93`) and the
implementation (`9e32b2b`), and the continuation verified it (§5).

## §0 Baseline, design session, critic round

- **Baseline** at `ebcf3c7`: **3204 tests in 3 suites**, 0 goldens, 203 typecheck
  guards, 133 live divergences.
- **Probe, SwiftUI's side** (run twice, byte-identical): a point anchor is a
  zero-size rect and the popover **centres across `arrowEdge`** on it — no arm
  puts a corner at the point (A1–A7); `.presentationBackground(.clear)` keeps
  the popover frame, glass and shadow (B1 = B0; `.red` recolours, the separating
  arm), and there is no `popoverStyle` (T15): SwiftUI has no chrome-less
  popover. Named spaces are nearest-ancestor, a missing or sibling name is
  `.global`, and the space moves with its container's effects (G1–G7). Its
  `CoordinateSpace` has exactly `local`/`global`/`named` (T9/T10) and is
  `~Sendable`; there is **no window size in the environment** (W0/W1, T5–T8);
  `onContinuousHover(coordinateSpace:)` exists but hover is a recorded broken
  instrument (`SV-N`), so only the signature is probed.
- **gpui's side** where SwiftUI has nothing: `anchored()` (`Anchor::TopLeft`,
  `SwitchAnchor`, a window-space `position`) plus `on_mouse_down_out` is
  exactly EP-b.
- **Critic round** (`OV-L`…`OV-P`): `AnyHashable` refuses in a `Sendable` enum
  under Swift 6 (measured), so both types are `@unchecked Sendable` with the
  hole named, and `named(_:)` takes `some Hashable` exactly; a named frame
  **composes the maps before boxing** — the draft's "box the global frame, map it
  back" was wrong at 30° (arm G6; G4's 90° could not separate) and the
  presentation inherits the declarer's stack (G7, `OV-M`); an overlay's `.local`
  point is the declarer's own space with its effects (`OV-N`); `windowSize` is
  the frame's `contentSize`, drawn chrome included (`OV-O`); lane A owns every
  `Frame`/`Window` hook lane B reads (`OV-P`).

## §1 What landed

**Lane A — coordinates** (`OV-D`…`OV-H`, `OV-L`, `OV-M`, `OV-O`…`OV-R`):

- **`CoordinateSpace.named(AnyHashable)`**, `NamedCoordinateSpace.named(_:)`
  (`SpatialGestures.swift`), the `CI-AC` migration sentence in the doc comment.
- **`coordinateSpace(_:)`** → `CoordinateSpaceScope` (new
  `CoordinateSpaceScope.swift`): transparent (no node, no id level; typed and
  untyped entries, each pinned); in prepaint it pushes a `NamedSpace`
  (`toSpace`, `toWindow`; `nil` `toSpace` when degenerate) built by
  `Frame.localSpace(of:)` from the content's scrolled union under the open
  effects' composed map. **A degenerate innermost entry reads `.global` and
  never falls through to an outer space of the same name** (`OV-Q` item 1).
- **`Frame.namedSpaces`/`namedSpace(_:)`**; hitboxes registered under a scope
  snapshot the stack (`hitboxNamedSpaces`, work counter `namedSpaceSnapshots`) —
  **nothing when no scope is open**, so a tree without one does no new work;
  `PrepaintPass.deferred` keeps the stack (a presentation inherits).
- **`GeometryProxy.frame(in: .named)`** maps the scrolled union through
  `toSpace ∘ composed` and boxes once (`OV-M`).
- **`onContinuousHover(coordinateSpace:perform:)`** on both vocabularies
  (default `.local`; a later `onHover` keeps the space).
- **Gestures**: `ArenaLeaf.point(_:in:)` is an exhaustive switch over the
  snapshot taken at arena formation, **per owner id and at each joining
  ancestor's index** (`OV-Q` item 2, `OV-R`); the draggable-above snapshot was
  dropped as dead (`OV-R` item 2: a bare `.draggable` never calls `point`).
- **`EnvironmentValues.windowSize`** (M, `public internal(set)`), stamped by
  `Window` beside `titleBarInsets` from the frame's `contentSize`, and by the
  headless `renderFrame` (`OV-R` item 3).
- **Hooks for lane B**: `Frame.presentationSpaces`,
  `recordPresentationSpace(_:for:)`, `previousPresentationSpaces`,
  `Window.lastPresentationSpaces`.

**Lane B — presentation** (`OV-A`, `OV-B`, `OV-K`, `OV-N`, `OV-S`, `OV-T`):

- **`anchoredOverlay(isPresented:at:in:anchor:content:)` and `(item:…)`** on
  both vocabularies (new `AnchoredOverlay.swift`; M): the content's `anchor`
  corner (default top-leading) at a point in `.local`, `.global` or a named
  space; **no panel, border, shadow or padding**; `OverlayPlacement` flips
  **per axis** (`SwitchAnchor`) then clamps, margin 0; replaced on a resize.
- **`PopoverAttachmentAnchor`** (`.rect(.bounds)` default, `.rect(.rect(r))` in
  the declarer's own space, `.point(_:)`) on the four `.popover` overloads
  (`attachmentAnchor:`, SwiftUI's argument order; divergence 225, the nested
  `Source` struct). The old overloads are replaced by the defaulted ones.
- **Dismissal**: the popover stage already sees every press of every button
  before the context-menu, text-input and value-track stages, so a left, right
  or other press anywhere outside dismisses and **still lands** on its target
  (a field, a slider, a context menu opens on the same press); a press on the
  declarer dismisses and reaches the declarer (`consumesAnchorPress` false for
  an overlay, true for a `.popover`); a press or wheel on the overlay stays on
  it; Escape closes the topmost overlay with a field inside it focused; the
  popover stage claims no key, so typing reaches the field (`OV-A` items 3–5).
- **`PopoverKind`**, an overlay's point resolved fresh at layout (`.global` as
  is, `.local`/`.named` through `previousPresentationSpaces[id].toWindow`; one
  more frame while the declarer has no recorded space, `OV-S`); prepaint
  records the declarer's `localSpace` or `namedSpace`. `PopoverModifier`'s
  stored properties changed: `swift package clean` was taken.
- **Demo** `OverlaysDemo.swift` (`METALUI_OVERLAYS_DEMO=1`, one `main.swift` line,
  each section its own function, an arm in `DemoStackBudgetTests`).
- Not built, by ruling: `presentationBackground(_:)` (`OV-C`), a window-size
  key anywhere but MetalUI's (`OV-G`).

No `PlatformWindow`/`Platform`/`WindowRenderer` requirement, no shader, no
`Backends/SDL` change: AppKit and SDL behave identically (the drawn
presentation), and the SDL and Linux-image runs are not owed
(`git diff ebcf3c7..HEAD -- Backends` lists nothing from this branch).

## §2 Tests and guards

All new files; "red before" is the stub run in each red commit's message.

| File | Tests | Notes |
|---|---|---|
| `CoordinateSpaceTests.swift` | A1–A21 (A4 at 30°, A4b, A17, A18, A19–A21 from the review) | frame in a named space, fallback, offset, rotated, effect between, scroll, no node/level, snapshot work counter, typed/untyped entries, hover global/named/default, drag and tap in a named space, `windowSize` first frame and resize, once-and-on-change, presentation inheriting, presentation spaces carried, ancestor's gesture, degenerate space, `renderFrame` stamp |
| `CoordinateSpaceCompileGuards.swift` | GA1–GA3 | `windowSize`'s setter is not public (MG-A1); `.named` takes `some Hashable`, `CoordinateSpace` is not accepted (MG-A2); `coordinateSpace:` on hover (MG-A3a) and the factory (MG-A3b) |
| `AnchoredOverlayTests.swift` | B6–B24 | corner at the point, per-axis flip, neither way, anchor unit point, no chrome, any-button dismissal, field/slider/context-menu presses, declarer press, Escape, press and wheel swallowed, keys into a field, binding/point write, global/named (B18, with a `.scaleEffect` `.local` arm), resize, identity level (B20), published popover node (B21), proposal path, item overlay, the demo (B24) |
| `PopoverTests.swift` | B1–B5 | point anchor centres on all four edges, rect source in the anchor's space, flip and clamp, declarer press consumed, default `.rect(.bounds)` |
| `AnchoredOverlayCompileGuards.swift` | GB1–GB2 | the `attachmentAnchor:` spellings (separating arm: the anchor written after `arrowEdge:` does not compile) and `anchoredOverlay`'s (`at:` required) |
| `PopoverCompileGuards.swift` | G3.2 re-spelled (`OV-T`) | `.popover` takes only a `PopoverAttachmentAnchor` |
| `DemoStackBudgetTests.swift` | one arm | the overlays demo builds on a 1 MB thread |

**Counts** (2026-10-12, after the merge with master `280d706`: `swift package clean`, native
build 0 `error:`, the only `warning:` SwiftPM's deprecation notice, then the unfiltered `--no-parallel`
run): **3363 tests in 3 suites** (master's 3312 + this branch's 51: CoordinateSpaceTests 22 incl. A4b,
AnchoredOverlayTests 19, PopoverTests 5, five compile guards), 5 issues — exactly
`AppKitPresentationTests`' five sheet failures on a locked screen (`CI-AF`; lock probe
`CGSSessionScreenIsLocked = 1`), nothing else; `FR-J no-argument frame: succeeded=true`; 0 goldens; **213
typecheck guards** (master's 208 + GA1–GA3 + GB1–GB2; `G3.2` is re-spelled, not new — summed from the
files, the default-build-system guards skip silently); public census **3392** (master's 3356 + 36),
`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (two inventory families
`named-coordinate-space` A and `window-size` M, plus `popover-attachment-anchor` D 225 and `anchored-overlay`
M); the default build system's 0 `warning:` was taken on `508c02c` and the merge changed no
source of this branch. `Backends/SDL` and the Linux image not re-taken (no Backends change on this
branch).

## §3 Red runs

- **Lane A** (`4ce0ab0`): the file does not compile at `ebcf3c7`; against a
  marked STUB (the scope pushes no space, named frame/hover/gesture read
  `.global` or `.local`, `windowSize` unstamped, `previousPresentationSpaces`
  never handed in) A1, A3, A4, A4b, A5, A7, A8, A9, A10, A11, A12, A13, A14,
  A16, A17 and A18 were red; A2, A6, A15 and GA1–GA3 are green on the stub by
  design (their mutations are the instrument).
- **Lane B** (`5755b93`): against a stub that ignored the anchor and drew a
  chromed bounds popover above its declarer, 50 tests ran with 35 issues; B1–B3,
  B6–B10, B12, B13, B15, B17–B19 and B22–B24 were red; B4, B5, B11, B14, B16,
  B20, B21, GB1, GB2 and G3.2 are shared-behaviour pins green on the stub, each
  owed a mutation (§4).

## §4 Mutation tables

**Lane A.** Each test's doc comment names its mutation (site and spelling); the
verifier's confirmations for the first round are in lane A's commits
(`629003e`, `e607833`, which re-spelled A8/A16's sites to ones that exist).
The review round's three instruments, each a full unfiltered native suite
(`39c4871`):

| Mutation (spelling) | Reddened |
|---|---|
| X1: `Window.makeGestureArena`, `noteSpaces(index)` for a joining ancestor replaced by `_ = index` (3229 tests, 3 issues) | `anAncestorsGestureResolvesItsNamedSpaceWhenAChildIsPressed` (A19) — before A19 existed the same edit left the suite green (3226 passed): the finding that added it |
| X3: `NamedSpace.resolve`, `stack.last(where: { $0.name == name && $0.toSpace != nil })` (1 issue) | `aDegenerateInnermostSpaceReadsGlobalAndNeverFallsThrough` (A20) — likewise unpinned before |
| `RenderFrame.swift`, `environment.windowSize = size` deleted (2 issues) | `renderFrameStampsWindowSize` (A21) |
| X2: the draggable-above snapshot | not a mutation: `d709a34` removed the line, and the suite is green without it (3229); the equivalence is argued in `OV-R` item 2 from `Handlers.isPointerTarget` and `GestureAttachment.isDraggable` |

**Lane B** (continuation verifier, native, full unfiltered runs, `git status
--short` empty after each):

| Mutation (spelling) | Reddened |
|---|---|
| MV1 `Popover.swift`: `consumesAnchorPress` false on the `.popover` kind (B4) | `aPressOnAPointAnchoredPopoversDeclarerIsStillConsumed` (B4), `aPressOnTheAnchorDismissesThePopoverAndIsConsumed`, `theAnchorPressesReleaseIsConsumedToo` (both arms) |
| MV2 `.rightMouseDown` removed from the `dispatchPopovers` mouseDown arm | `anOutsidePressOfEveryButtonDismissesAnOverlay` (button 1, B11), `aPressIntoAFieldASliderOrAContextMenuDismissesAndStillLands` (menu arm, B12) |
| MV3 the `.otherMouseDown` arm `return false` with no dismissal | `anOutsidePressOfEveryButtonDismissesAnOverlay` (button 2), `anOtherPressDismissesAPopoverAndAnOpenInWindowMenuTakesItAndPinches` |
| MV4 the Escape arm disabled (`&& false`) | `escapeDismissesTheTopmostOverlayEvenWithAFieldInsideFocused` (B14), `escapeDismissesTheTopmostPopoverBeforeTheKeymap`, `escapeClosesThePanel` |
| MV5 `AnchoredOverlay.swift`: `.rect(.bounds)` resolves to the centre point (44 issues) | `theDefaultAttachmentAnchorIsTheBounds` (B5), `theDefaultArrowEdgeIsTop`, `thePopoverSitsOnItsArrowEdgeOfTheAnchor` (all four edges) |
| MV6 `Popover.swift`: the stage claims every `.keyDown`/`.textInput` while one is open | `keysReachAFocusedTextFieldInsideTheOverlay` (B16), `theHexFieldAcceptsTheFourForms`, `squareAndBarKeysStepByOneHundredthAndShiftByATenth`, `theHueSurvivesSaturationZeroWhileDragging` |
| MV7 the slot laid out at cursor 0 in both `requestLayout` sites | `anOverlayAddsOneIdentityLevelOnlyForItsCaller` (B20), `aPopoverAddsOneIdentityLevelOnlyForItsCaller`, `aPopoverWritesNoStateTableEntry`, `anOverlayWritesNoStateTableEntryAndPublishesAPopoverNode`, `aPopoverIsAPresentationOnAHigherLayer`, `aPopoverFollowsItsAnchorWithinOneFrame`, `aProposalPathPopoverPresentsPlacesAndDismisses`, `thePopoverChromeIsARoundedPanelWithNoArrow` |
| MV8 `popoverHint` dropped for overlays (`= padding != 0`), alone in a filtered run to separate it from MV7 | `anOverlayWritesNoStateTableEntryAndPublishesAPopoverNode` (B21) |
| MV9 an extra `popover(isPresented:attachmentAnchor: Int, content:)` overload | `aPopoversAttachmentAnchorTakesOnlyAPopoverAttachmentAnchor` (G3.2) |
| MG-B1 drop `attachmentAnchor:` from the proposal `item:` overload | `thePopoverAttachmentAnchorSpellingsCompile` alone ("extra argument attachmentAnchor in call") |
| MG-B2 drop `in:`'s default on the legacy `item:` overload (dropping it on `isPresented:` breaks the unit tests' own compile) | `theAnchoredOverlaySpellingsCompile` alone ("missing argument for parameter in") |

One run of MV1's set stopped with no summary line at the first
`AppKitPresentationTests` sheet test, no trap text; the identical build rerun
finished normally (28 issues). That is the known mid-run exit on a locked
screen with other workflows active, not a lane defect — **a no-summary run on a
locked screen is rerun** before it is read.

## §5 Verification

- **Lane A** (clean build of `39c4871`): 0 `error:`, the only `warning:`
  SwiftPM's deprecation notice; unfiltered native **3229 tests in 3 suites
  passed**; `FR-J no-argument frame: succeeded=true`; `swift build --build-tests`
  (default) 0 warnings.
- **Lane B** (clean build of `508c02c`): unfiltered native **3255 tests in 3
  suites**, 5 issues — exactly `AppKitPresentationTests`' sheet failures
  (`CI-AF`, screen locked: `CGSSessionScreenIsLocked=1`, `displayAsleep main:
  1`); FR-J present; default build 0 warnings; inventory check and
  undocumented check silent. The implementer had not built the doc-comment
  commit `508c02c`; the verifier did, and it is clean.
- **Fourteen images**: `docs/probes/demo-pixels/compare.sh <scratch> ebcf3c7
  HEAD` — all 14 `differing=0`, scene identical, controls non-zero.
- Not run (not owed): `Backends/SDL` and the Linux image (no Backends file
  changed); a real-window capture (the screen was locked).

## §6 Merge with master `280d706`

Master moved past `ebcf3c7` by C12 (§89) and item 8 (§91). Two conflicts, both
docs: `docs/verification/human-checks.md` (kept PF, **OV**, SG, HT in that order)
and `docs/probes/closeout-public-api.tsv` (regenerated by the script, not
hand-merged: 3392 rows). No source conflict. The merge's own risks, each
checked: master's `HeadlessPlatform` implements every platform requirement and
this branch adds none; `Window.swift`/`Frame.swift` auto-merged beside master's
`drawnChromeHeight` and menu-bar strip, whose cursor index 2 and named root
`$menubar` a `CoordinateSpaceScope` does not touch (a transparent scope numbers
nothing, `coordinateSpaceAddsNoNodeAndNoIdentityLevel`).

## §7 Hazards and deferrals

- **A press on the declarer** dismisses and reaches the declarer, so an
  overlay opened from a click handler on the declarer reopens at the new point
  in one press (the demo does this on purpose); a caller who wants the press to
  close it only must declare the overlay on a different element (`OV-A` item 3).
- **A `.local`/`.named` overlay waits one frame** for its declarer's space (the
  first presented frame carries it only after one settle build, `OV-S`); a
  `.global` point is placed in the first frame.
- **`@unchecked Sendable`** on `CoordinateSpace`/`NamedCoordinateSpace` (`OV-L`):
  a reference-typed non-`Sendable` name moved across actors by app code is not
  checked.
- **Exhaustive `switch` over `CoordinateSpace`** outside the package no longer
  compiles (`docs/migration.md`, `CI-AC`'s sentence).
- **Deferred, no owner assigned**: `presentationBackground(_:)` (`OV-C`);
  hover's coordinate-space behaviour against real SwiftUI (only the signature is
  probed — hover is a recorded broken instrument, `SV-N`); a named space across
  a `Deferred` that is not a presentation.
- **Divergences header**: "134 live, next label 206" was not edited on this
  branch (the brief leaves it to the merge); row **225** is added, so the live
  count after this branch is one more than the header reads.

## §8 Looks owed

`docs/verification/human-checks.md` group **OV** (OV1–OV5), none performed (an
agent cannot): the palette's corner at the pointer and its per-axis flip; a
right or middle click outside closing it as the context menu opens; typing and
Escape with the field focused; the crosshair under the pointer in a named space;
`windowSize` through a live resize. Recorded in record §03 (2026-10-12).
