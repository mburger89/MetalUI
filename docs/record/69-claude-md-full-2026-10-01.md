# MetalUI

A GPU-accelerated UI framework for Swift, modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui), written as
idiomatic Swift. **macOS with AppKit and Metal by default; the framework also
builds on Linux and Windows** (`XP-A`), drawing through `Backends/SDL`
(`App(platform:textSystem:)`, `XP-B`) with the portable text system — see
`plans/2026-09-23-cross-platform-roadmap.md` for what is left. **The
supported platforms are macOS, Linux and Windows — desktop windowing only.**
iOS, iPadOS, tvOS, watchOS and visionOS are an explicit product boundary, not
an unmet target (plan task 14, ruling `PB-A`,
`docs/superpowers/2026-09-30-platform-boundary-decisions.md`, record §65): no
UIKit platform conformer, no `.touch` input, no safe areas, no
`UIApplication`/scene lifecycle, no `UIAccessibility` bridge, none planned.
`PlatformWindow`'s `onAccessibilityRequest`,
`publishAccessibilityTree(_:)`, `controlActiveState`,
`onControlActiveStateChange` and, since drag and drop,
`beginExternalDrag(_:at:)` have no default implementations (`AB-R`, `EV-AB`,
`DN-C`); both existing conformers (`AppKitPlatform`/`AppKitWindow`,
`SDLPlatform`/`SDLWindow`) implement all five, and the test fakes too.

**This file is rules only.** The full pre-2026-09-21 version (120 KB: every
test name, divergence row, inert row, human-verification row, performance
figure and CI hazard) is `docs/record/19-claude-md-full-2026-09-21.md`; below,
"§19 <section>" points into it. **§19 is frozen at `cb2e708` and does not carry
plan task 7's stage 2 or its grids stage** — for those tables read the dated
sections at the end of records §03, §04 and §05, and the tracks themselves
(§21, §22, §23). Reasoning and history live in `docs/record/`
(`README.md` indexes it). Citations in the record were not all re-checked after
later refactors — verify a test name or grep before relying on it. New
milestones append their record to `docs/record/` and put only the rule here.
**Plan task 15 (2026-10-01) moved the accumulated counts history and the
three reference-table bullets (known divergences, declared-but-inert, human
verification) to `docs/record/67-claude-md-counts-history-2026-10-01.md`**
(verbatim, frozen); the current ones are `docs/divergences.md`, record §05's
closeout section and `docs/verification/human-checks.md`.

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
  `SZ-`, `TB-`, `RX-`, `CO-` (next `CO-AA`), `AN-` (next `AN-AL`; its letters do
  not track its ledger's), `SA-` (next `SA-V`), `MC-` (next `MC-T`), `EV-`
  (next `EV-AG`), `AB-` (next `AB-AH`), `FR-` (next `FR-W`), `OM-` (next
  `OM-AN`), `CN-` (next `CN-V`), `LR-` (next `LR-GH`), `GR-` (next `GR-AU`),
  `PS-` (next `PS-H`; rulings in its spec, no separate decisions doc), `FT-`
  (next `FT-L`; rulings in its spec, no separate decisions doc), `SH-` (next
  `SH-L`; rulings in its spec, no separate decisions doc), `PT-` (next `PT-K`;
  rulings in its spec, no separate decisions doc), `LB-` (next `LB-P`;
  rulings in its three specs: line breaking, lines emission, content sizes),
  `FN-` (next `FN-E`; rulings in its spec), `PC-` (next `PC-D`; rulings in
  its spec), `TS-` (next `TS-E`; rulings in its spec), `RS-` (next `RS-E`;
  rulings in its spec), `SP-` (next `SP-D`; rulings in its spec), `XP-`
  (next `XP-D`; rulings in its spec; `MP-` is the measure-performance one),
  `DC-` (next `DC-D`; rulings in its spec), `FB-` (next `FB-D`; rulings in
  its spec), `BD-` (next `BD-E`; rulings in its spec), `AX-` (next `AX-E`; rulings in
  its spec), `TI-` (next `TI-K`; rulings in its spec), `SF-` (next `SF-E`; rulings in its
  spec), `ID-` (next `ID-S`; rulings in its own decisions doc,
  `2026-09-25-composition-identity-decisions.md`), `DD-` (next `DD-AJ`;
  rulings in its own decisions doc, `2026-09-25-data-and-scrolling-decisions.md`,
  plan task 10, both parts), `TE-` (next `TE-AW`; rulings in its own
  decisions doc, `2026-09-28-text-semantics-decisions.md`, plan task 11,
  both parts), `IX-` (next `IX-AK`; rulings in its own decisions doc,
  `2026-09-29-interaction-decisions.md`, plan task 12, both parts —
  interaction and accessibility), `PB-` (next `PB-B`; rulings in its own
  decisions doc, `2026-09-30-platform-boundary-decisions.md`, plan task 14),
  `CX-` (next `CX-T`; rulings in its own decisions doc,
  `2026-09-30-closeout-decisions.md`, plan task 15), `DN-` (next `DN-AA`;
  rulings in its own decisions doc, `2026-10-01-drag-and-drop-decisions.md`,
  drag and drop — not a plan task).
  A numbered citation
  of a lettered prefix (`CS-3`, `LR-3`, `GR-3`, `SH-3`, `PT-3`, `LB-3`, `ID-3`, `DD-3`, `TE-3`, `IX-3`, `PB-3`, `CX-3`, `DN-3`) is a typo; sweep
  case-insensitively.
  **A decisions doc's "next unused" line moves in the commit that appends the
  ruling** — read the file's last `## <PREFIX>-` heading, not its header; the
  grids doc's header was a letter behind for a whole round (record §23 §7).
- **SwiftUI-alignment plan:** `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`.
  Its 2026-09-12 kernel/modifier specs describe types never built; **the
  source is the authority**. Per task: spec in `specs/`, decisions doc, record
  file — task 2 `SA-` (§09), 3 `MC-` (§10), 9 `EV-` (§11; task 9's closing
  half — `displayScale`, `controlActiveState`, `controlSize` — `EV-AA`…`EV-AF`,
  §56, spec `specs/2026-09-25-environment-control-state-design.md`), 12 `AB-`
  (§12),
  3/9/12 integration (§13), 4 `FR-` (§14), 5 `OM-` (§15), 4/5 integration
  (§16), 6 `CN-` (§17), 7 stage 1 of 14 `LR-` (§18, spec
  `specs/2026-09-17-engine-replacement-design.md`), 7 stage 2 `LR-AB`…`LR-BA`
  (§21, spec `specs/2026-09-17-engine-stage-2-design.md`, same decisions doc,
  probe `swiftui-engine-replacement-stage2.swift` revision 4), 7 stage 3
  `LR-BB`…`LR-BP` (§25, spec `specs/2026-09-22-engine-stage-3-design.md`, same
  decisions doc, probe `swiftui-engine-replacement-stage3.swift` revision 2),
  7 stage 4 `LR-BQ`…`LR-CG` (§27, spec
  `specs/2026-09-23-engine-stage-4-design.md`, same decisions doc; **no new
  probe** — its SwiftUI claims are `swiftui-stack-algorithms.swift`'s K6),
  7 stage 5 `LR-CH`…`LR-CS` (§29, spec
  `specs/2026-09-23-engine-stage-5-design.md`, same decisions doc, probe
  `swiftui-overlay-presentation.swift` revision 2 — group Q added, P and H
  re-run byte-identical), 7 stage 6a `LR-CT`…`LR-DE` (§38, spec
  `specs/2026-09-23-engine-stage-6a-design.md`, same decisions doc; **no new
  SwiftUI probe** — the stage's only probe,
  `swift-deprecated-witness-silence.sh`, is a compiler determinism check),
  7 stage 6b `LR-DF`…`LR-DR` (§41, spec
  `specs/2026-09-23-engine-stage-6b-design.md`, same decisions doc — the root
  switch: `Window`'s and `Frame`'s default authority is now `.proposal`,
  production runs the proposal engine; three probes re-run byte-identical
  (`swiftui-stack-algorithms.swift`'s R control/R1–R4 for `CN-J`,
  `swiftui-engine-replacement-stage1.swift`'s H0–H2,
  `swiftui-engine-replacement-stage2.swift`'s V0–V3), plus two new harnesses,
  `docs/probes/native-depth-ceiling/` (the release re-bisection) and
  `docs/probes/stage-6b-flip-instrument.patch`),
  7 stage 7a `LR-DS`…`LR-EB` (§48, spec
  `specs/2026-09-23-engine-stage-7a-design.md`, same decisions doc — the 97
  WebKit goldens retired, each with a row in record §48 §4 naming its native
  replacement arm or its deleted CSS-only concept; probe
  `swiftui-engine-stage-7a.swift` arms W, G, S, A, B; instrument
  `docs/probes/stage-7a-transcription-instrument.patch`),
  7 stage 7b `LR-EC`…`LR-EQ` (§49, spec
  `specs/2026-09-23-engine-stage-7b-design.md`, same decisions doc — the
  non-golden CSS-engine tests of spec §2.6's files and the element tests
  stages 6a/6b pinned `.legacy` with a 7b owner are retired, each with a row
  in record §49 §4 naming its native replacement or its deleted CSS-only
  concept; divergence 4 retires as a CSS-engine row (`LR-EH`, `LR-EP`); **no
  new SwiftUI probe** — its claims are arms of five existing probes, re-run
  2026-09-24 (`LR-EI`)),
  7 stage 8 `LR-ER`…`LR-FB` (§50, spec
  `specs/2026-09-24-engine-stage-8-design.md`, same decisions doc — the
  eight `StyledElement` sizing modifiers deprecated toward `.frame` in the
  same change (`FR-I`), every in-repo caller converted by class (F 129 sites
  to `.frame`, K 296 plus lane 2's 1115 kept as `Style` writes through
  `CSSSizing.swift`, D `ModifierTests`' eight rows into a deprecated
  witness), `LR-EV`'s framed absolute box discharging the two `…absolute`
  fields stage 5 left owned here; probe `swiftui-engine-stage-8.swift`
  groups F, P, T),
  7 stage 9 `LR-FC`…`LR-FL` (§51, spec
  `specs/2026-09-24-engine-stage-9-design.md`, same decisions doc — the
  CSS-engine files, the layout authority (`LayoutAuthority.legacy`,
  `Frame.layoutAuthority`, `computeRootLayout`'s legacy branch,
  `Frame.legacyRootLayoutCounter`) and the legacy registrars deleted; every
  legacy element (`Box`, `Row`, `Column`, `Stack`, `ScrollView`, `List`,
  legacy `.frame`) keeps working through the lowering, now its only path;
  **no new SwiftUI probe** — the stage claims no new SwiftUI behaviour
  (`LR-FH` item 4)),
  7 stage 10 `LR-FM`…`LR-FU` (§53, spec
  `specs/2026-09-24-engine-stage-10-design.md`, same decisions doc — `Style`'s
  CSS fields resolved field by field (deleted, narrowed to `package`, or
  moved into `MetalUI`), every inherited `Style`-field report made a
  permanent refusal by name, the mechanical closing check
  (`theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, three plain-import
  guards, a recorded grep); **no new SwiftUI probe** — the stage claims no
  new SwiftUI behaviour),
  7 stage 11 `LR-FV`…`LR-GG` (§54, spec
  `specs/2026-09-25-engine-stage-11-design.md`, same decisions doc —
  **task 7's last stage**: `ModifiedElement`/`ModifiedContent` unified into
  one flat `ModifiedContent<Content, Modifier>`, the second parameter a
  per-vocabulary witness (`ModifierLayerKind`), with `ModifiedElement` now a
  typealias for its legacy arm; the legacy `.overlay` generalized from
  `OverlayModifier<Content, Overlay>` over `ElementGroup` (both vocabularies,
  lowered like a frame layer's child through `AttachmentLowering.swift`); the
  write-order bug behind divergence 45 fixed on both paths
  (`Decoration.escapesOpacity`, one member per slot) so whatever is written
  after `.opacity` is outside it everywhere, retiring the divergence;
  `deferred.amended` now lowers exactly as a `.frame` layer already did
  (no report); `Component.width`/`height` and `.frame` reconciled by ruling,
  no API change; probes re-run byte for byte
  (`swiftui-outer-modifier-order.swift`, `swiftui-overlay-primary-shape.swift`)
  and extended (`swiftui-border-clip-paint.swift` group H); every id path,
  hit-testing, accessibility, animation and focus rule **unchanged** (measured,
  not merely asserted). **No production layout request passes through the
  legacy engine (stage 9), the CSS layout paths and dead `Style` fields are
  gone (stages 9–10), and the two modifier vocabularies are unified (this
  stage) — task 7's own three clauses all hold on this branch.**),
  7 stage G grids
  `GR-` (§22, spec `specs/2026-09-17-grids-design.md`,
  `2026-09-17-grids-decisions.md`, ten runnable probes), stage 2 / stage G
  integration (§23). **Lazy grids (`LazyVGrid`/`LazyHGrid`/`GridItem`) are out
  of scope**, proposed as stage G2 after stage 4 (`GR-L`) — **stage 4 has
  landed**, so the windowing they need exists (`WindowedRowsLayout`, `LR-BQ`)
  and G2 is unblocked rather than waiting. Seventeen record files are not tasks of
  this plan: §19 is the
  frozen `CLAUDE.md` snapshot, §20 the portable `MetalUIScene` move (`PS-`),
  §24 the FreeType rasterizer (`FT-`, spec
  `specs/2026-09-22-freetype-rasterizer-design.md`, rulings in that spec),
  §26 the HarfBuzz shaper (`SH-`, spec
  `specs/2026-09-22-harfbuzz-shaper-design.md`, rulings in that spec),
  §28 the portable text pipeline (`PT-`, spec
  `specs/2026-09-23-portable-text-design.md`, rulings in that spec), §30
  portable line breaking (`LB-`, spec
  `specs/2026-09-23-portable-line-breaking-design.md`) and §31 portable
  metrics and multi-line emission (`LB-F`, `LB-H`…, spec
  `specs/2026-09-23-portable-lines-emit-design.md`) and §32 portable min-
  and max-content (`LB-L`…, spec `specs/2026-09-23-portable-content-sizes-design.md`),
  §33 portable font resolution (`FN-`, spec
  `specs/2026-09-23-portable-font-resolver-design.md`), §34 Core and
  Layout off macOS (`PC-`, spec `specs/2026-09-23-portable-core-layout-design.md`),
  §35 the text seam (`TS-`, spec `specs/2026-09-23-text-seam-design.md`),
  §36 the render seam (`RS-`, spec `specs/2026-09-23-render-seam-design.md`),
  §37 the SDL3 platform (`SP-`, spec `specs/2026-09-23-sdl-platform-design.md`),
  §39 MetalUI off Apple (`XP-`, spec `specs/2026-09-23-metalui-portable-design.md`),
  §40 the demo on Linux and Windows (`DC-`, spec
  `specs/2026-09-23-demo-cross-platform-design.md`), §42 portable font
  fallback (`FB-`, spec `specs/2026-09-23-font-fallback-design.md`), §43
  portable bidi (`BD-`, spec `specs/2026-09-23-bidi-design.md`), §44
  accessibility off Apple through AccessKit (`AX-`, spec
  `specs/2026-09-23-accesskit-accessibility-design.md`) §45 text input
  and `TextField` (`TI-`, spec `specs/2026-09-23-text-input-design.md`) and
  §46 system font discovery (`SF-`, spec
  `specs/2026-09-23-system-fonts-design.md`). **Cross-platform work
  follows `plans/2026-09-23-cross-platform-roadmap.md`**, one item per branch,
  ticked in the PR that lands it.
  **§24 is FreeType and §25 is stage 3; §26 is HarfBuzz and §27 is stage 4**
  — each stage record was renumbered (24→25, 26→27) at its merge because the
  other line was pushed first (record §25's and §27's headers, and the
  precedent in record §23 §8). §28 was written as §27 and renumbered when
  stage 4 reached `master` first. **§29 (stage 5) was written as §28** on
  `feat/engine-stage-5` from `e5caefb` and renumbered 28→29 at its merge,
  because `master`'s portable-text line had already published §28 — the same
  shape as 24→25 and 26→27 (record §29's header). **§30 (line breaking) was
  written as §29** and renumbered when stage 5 reached `master` first.
  **§38 (stage 6a) was written as §30** on `feat/engine-stage-6a` from
  `b3c29b9` and renumbered 30→38 at its merge, because `master` had already
  published §30–§37 (PRs #11–#20, `64c5271`; record §38's header).
  **§41 (stage 6b) was written as §39** on `feat/engine-stage-6b` from
  `aef88ce` and renumbered 39→41 at its merge, because `master` had already
  published §39–§40 (PR #22, `654a503`; record §41's header).
  **§42 (font fallback) was written as §40**, renumbered 40→41 at the
  stage-6a merge and 41→42 when stage 6b reached `master` first; **§43
  (bidi) was written as §41** and moved with it, 41→42→43.
  **§48 (stage 7a) was written as §42** on `feat/engine-stage-7a` from
  `2cc763d` and renumbered 42→48 at its merge, because `master` had already
  published §42–§47 (font fallback through text undo, `6e01d9e`; record
  §48's header).
  **§53 (stage 10) was written as §52** on `feat/engine-stage-10` from
  `8095fd9` and renumbered 52→53 at its merge, because `master` had already
  published §52 (`TextEditor`, `TI-H`, PR #29, `0843866`; record §53's
  header). Master's own §52 citations are the text editor's. **§54 (stage
  11) needed no renumbering**: written directly on `feat/engine-stage-11`
  from `47c0d98` (stage 10's own merge tip), with no other line publishing a
  §54 first.
  **§61 (task 11 part 2, shapes and rendering) was written as §60** on
  `feat/shapes-and-rendering` from `ff2ae92` and renumbered 60→61 at its
  merge, because `master` had already published §60 (`TI-I`/`TI-J`, text
  page and Tab, PR #31, `0714528`; record §61's header). Master's own §60
  citations are the text-page record's.
  Task 8 `ID-` (§55, spec `specs/2026-09-25-composition-identity-design.md`,
  decisions doc `2026-09-25-composition-identity-decisions.md`, probe
  `swiftui-composition-identity.swift`) — audits `Group`, conditional
  content, explicit identity, `Component` and modifier placement against
  SwiftUI, disposing of every item task 7 stages 3, 4, 9, 11 and the grids
  track hand it (record §54 §10.3, `LR-GA`, grids record §22).
  Task 10, **part 1**, `DD-A`…`DD-P` (§57, spec
  `specs/2026-09-25-data-and-scrolling-design.md`, decisions doc
  `2026-09-25-data-and-scrolling-decisions.md`, probes
  `swiftui-data-and-scrolling.swift` and, from the critic round,
  `swiftui-scrollviewreader-scope.swift`) — `ForEach` and loop identity
  (divergence 74 retires, 79 added), a `Binding<Value>` (`KeyBinding`'s
  deprecated alias deleted, divergence 78 added), a `List`'s own scroller
  origin (divergence 14 retires, 13 amended) and `ScrollViewReader`/
  `scrollTo(_:anchor:)`/indicators. **Part 2**, `DD-Q`…`DD-AI` (§58, spec
  `specs/2026-09-26-controls-and-selection-design.md`, same decisions doc,
  probe `swiftui-controls-and-selection.swift`) — `Button`, `Toggle`,
  `Slider`, `Stepper`, `Picker`/`.tag(_:)`/`PickerStyle` and
  `List(selection:)` single and multi selection, each on `Binding`,
  `StyledElement`'s handler/focus/accessibility machinery and the
  `.disabled` gate; `ForEach(_: Binding<C>)`; divergence 16 retires (the
  wheel now passes to the nearest enclosing scroller, `DD-Y`); divergences
  80–84 added (control keys need no system setting, `DD-T`; the AX partial
  fold's accessible name where SwiftUI publishes a sibling title, `DD-U`;
  the automatic picker is segmented, not a pop-up menu, `DD-V`; a
  selection client presses a row rather than setting `AXSelected`, `DD-Z`;
  `List` stays virtualized and data-driven, `DD-AB`); divergence 76 amended
  (`Button`'s chrome reads `controlSize`, `DD-R`). Three lanes plus two
  verifier fix rounds, all verified `ok`; the Record phase's own close
  (`DD-AI`) resolves the one item the lanes left open — a pre-existing
  optional-`@State` bug the controls demo found (`StateTable.peek` reads an
  absent entry as a present `nil`) — as divergence 85, added (fixed at plan task 15, `CX-F`), owner **plan
  task 15** (closeout), not fixed on this branch. **Task 10 is ticked**:
  every clause of both parts is closed.
  Task 11, **part 1**, `TE-A`…`TE-AB` (§59, spec
  `specs/2026-09-28-text-semantics-design.md`, its own decisions doc
  `2026-09-28-text-semantics-decisions.md`, probes
  `swiftui-text-semantics.swift` and, from the critic round,
  `swiftui-controlsize-text-render.swift`/`swiftui-text-in-stacks.swift`, and
  from the lane fix rounds, `swiftui-truncation-edges.swift`/
  `swiftui-font-selection.swift`/`swiftui-baseline-offsets.swift`) — the
  text half of the task's first sentence: `.foregroundStyle`/
  `.foregroundColor`, `Font` (system sizes/weights/design, the eleven text
  styles) and font metrics, `.lineLimit`, truncation
  (`.truncationMode`/ellipsis) through the `TextSystem` seam on both text
  systems, `.multilineTextAlignment`, baseline alignment in the kernel
  (`VerticalAlignment.firstTextBaseline`/`.lastTextBaseline` in `HStack`,
  and the legacy `AlignItems.baseline`/`alignSelf.baseline` fields lowered
  or refused by name) and `dynamicTypeSize` ruled inert by construction
  (`Font`'s text-style table has no size column). `controlSize` reaches
  every text's default font, `TextField` and `TextEditor` too (divergence 76
  amended a third time). Three lanes plus a lane-1 fix round, a lane-2 fix
  round and a lane-3 fix round, all verified `ok`; the Record phase's own
  branch check (`TE-AB`) resolves the one item lane 2's fix round left open —
  a `GridRow`'s own baseline-alignment factor, left unpinned by 2.1c because
  none of its arms give a row an `alignment:` — with a new test (2.1d)
  against a new SwiftUI probe arm, not fixed code (the implementation was
  already right). Divergences 86–89 added, 76 amended a third time — part 1
  left task 11's box unticked pending part 2.
  Task 11, **part 2**, `TE-AC`…`TE-AV` (§61, spec
  `specs/2026-09-28-shapes-and-rendering-design.md`, the same decisions doc,
  probes `swiftui-shapes-and-rendering.swift` and, from the critic round's
  re-run, `swiftui-grid.swift`'s `GL14`) — **closes task 11**: SwiftUI's
  `Shape` protocol and five built-ins (`Rectangle`, now a `Shape`;
  `RoundedRectangle`, `Circle`, `Capsule`, `Ellipse`), `.fill`/`.stroke`/
  `.strokeBorder` with `ColorToken`s, `.clipShape`/`.clipped()`/
  `.cornerRadius` on the proposal path and a generalized legacy
  `StyledElement.clipShape` (the legacy `.cornerRadius` stays paint-only,
  divergence 47 kept — clipping it would move hit testing under every
  rounded legacy box), `.background(_:in:)`/`.background(in:)` beside the
  audited, unchanged `.overlay`/`.background(alignment:content:)`, `Image`/
  `ImageBitmap` (a textured quad on **both** renderers, Metal and SDL, with
  `.resizable()`/`.interpolation(_:)`/fit-fill), `aspectRatio(_:contentMode:)`
  with no ratio (`scaledToFit`/`scaledToFill`), and `gridCellAnchor(UnitPoint)`
  (divergence 64 retires). Two renderer primitives added — an ellipse kind on
  `MUIRect` (its unused `_reserved` word renamed `shape`, stride and every
  recorded scene's bytes unchanged) and `MUIImage` sampling a `Scene`-carried
  texture, cached by identity and released when a frame's scene no longer
  references it — both checked (frame 6) through the SDL replay-parity
  harness: 0 px on SDL's Metal backend, within `ParityTolerance` on Mesa
  llvmpipe, D3D12 re-confirming on push; everything else SwiftUI
  offers here (continuous corners, an ellipse clip, crossing rounded clips,
  `.interpolation(.high)`, `Path`, gradients, `StrokeStyle`, SF Symbols, a
  labelled image) is a documented renderer constraint (spec §9), divergences
  90–93 added for the four MetalUI still draws an answer for. Three lanes
  plus two fix rounds, all verified `ok`; the Record phase's own close
  re-took the suite, guard and golden counts, the fourteen-image comparison,
  the probe, `Backends/SDL` and a `swift:6.4-noble` container, found four
  lane-1 test-coverage gaps (owed, none blocking — an SDL texture-release
  count, three Metal shader facts pinned only by the parity job, and a
  latent per-window texture-cache note for a future multi-window image
  consumer) and corrected a part-1 documentation slip (`Tests/PortableTests`
  reads 21 + 6 + 5, not 20 + 6 + 5 — 18 + 3, not 18 + 2). Live divergence
  count 65 → 68, next label 94. Counts 1763 / 0 / 108 tests/goldens/guards;
  0 px against `ff2ae92` in all fourteen offscreen images; the real-window
  capture stays owed (screen locked at every check across design, the
  critic round and all three lanes). **Task 11 is ticked**: every row of the
  spec's collection table is built, kept with a numbered divergence, or an
  explicit renderer constraint the task's own text asks for.
  Task 12, **part 1** (the interaction half), `IX-A`…`IX-T` (§62, spec
  `specs/2026-09-29-interaction-design.md`, its own decisions doc
  `2026-09-29-interaction-decisions.md`, probes `swiftui-interaction.swift`
  and, from the lane-1 fix round, `swiftui-gesture-presentation-arena.swift`)
  — gesture composition (`TapGesture`/`LongPressGesture`/`DragGesture`,
  `.gesture`/`.simultaneousGesture`/`.highPriorityGesture`, one arena per
  press from the one ranking, a `Deferred` presentation joining its
  declarer's arena only through a same-layer `.overlay`, never a sheet or
  popover); `Button(role:)`, `.buttonStyle`, a pressed look and
  `.keyboardShortcut`; a disabled look, an inactive-window look
  (`controlActiveState`'s first built-in readers) and a focus ring on every
  control; `@FocusState`/`.focused(_:)`; focus now leaves with its identity
  and does not return (`IX-I`, fixing `ID-R` item 9 to SwiftUI's answer, a
  migration note); Full Keyboard Access measured (divergence 80 amended); a
  hidden element out of the keyboard's focus half but not its shortcut
  (`IX-K`); `contentShape<S: Shape>(_:)` on every element (`IX-L`); a click
  never focuses a `.focusable()` view or `Button` (divergence 94 added, kept
  by ruling). Three lanes; lane 3 stopped once on a finding mid-implementation
  (`IX-S`: `IX-I`'s own fix closed one route of a pre-existing `$focus`
  sticky-retention hazard, reddening an instrument test nobody's mutation
  table named) and continued after re-deriving that test onto the route the
  fix does not close (`IX-T`); all three verified `ok`, the Record phase's
  own close running lane 3's own remaining mutation table (twelve mutations,
  none reddening the wrong test) and both re-checks `IX-T` left owed (the
  fourteen-image comparison, `Backends/SDL`). Divergences 94 added; 43, 41,
  80 amended; 57 pinned; 81, 21, 22 re-owned — live count 68 → 69. Counts
  1837 / 0 / 113 tests/goldens/guards; 0 px against `31f2e7a` in all fourteen
  offscreen images; the real-window capture stays owed (screen locked at
  every check across design, the critic round and all three lanes), joined
  by this task's own new looks (gestures by hand, the pressed/disabled/
  inactive looks, the focus ring, a real key window's accent). **Task 12's
  box stays unticked**: part 2 (the accessibility half — settable
  `AXSelected`, `accessibilityElement(children:)`, the `AB-H` press
  question/divergence 28, modal isolation, the VoiceOver script itself) is
  the next run.
  Task 12, **part 2** (the accessibility half), `IX-U`…`IX-AJ` (§63, spec
  `specs/2026-09-29-accessibility-design.md`, part 1's own decisions doc
  `2026-09-29-interaction-decisions.md`, probe `swiftui-accessibility-part2.swift`
  and one existing probe re-run, `swiftui-controls-and-selection.swift`) —
  every accessibility row part 1's audit assigned here, built or pinned:
  `accessibilityElement(children:)` (`.ignore`/`.combine`/`.contain`, the
  proposal path too, through `AccessibilityModifier<Content>`);
  `accessibilityHidden`, `accessibilityHint`/`accessibilityIdentifier`, eight
  `AccessibilityTraits`; `accessibilityAction(_:)`/`accessibilityAction(named:_:)`
  (declared, not synthesized — `IX-AF` item 3); a press advertised and run
  under `allowsHitTesting(false)` (divergence 28 retires); settable
  `AXSelected`/`AXSelectedRows` on AppKit, replacing the selection
  (divergence 83 retires on that bridge; AccessKit still selects by `Click`,
  0.23 has no select action); modal isolation (`.isModal`, an isolated-out
  request refused — divergence 95 added); the proposal path's own emission
  (`ProposalText` records its string, a grid flattens row by row);
  `Image(_:scale:label:)`; both bridges' parity mechanically enforced (a
  `Mirror` count against a field → attribute table on each side); the demo's
  modal gains `.isModal` and drops `.isButton`'s press-folding role, and
  `docs/verification/voiceover-script.md` is written (walks the demo, the
  controls demo, the preview and the text-input demo, every step's expected
  output a machine-checked `ax`/`ax-absent` marker against the trees the
  tests pin). Three lanes (the neutral tree and both bridges; every
  `Sources/MetalUI` accessibility file; the audit, the demo, the script), run
  strictly in order over shared files; lane 2's fix round (`IX-AI`) found
  `.combine` over children of DIFFERENT kinds merges (highest-ranked role,
  last valued child's value, the first-pressing child the lead) where the
  design's "the first one's" held only for one kind. Divergences 28 and 83
  retire, 95 added, 27/32/33 amended, 82 kept (owner the human VoiceOver
  run) — live count 69 → 68, next label 96. Counts 1880 / 0 / 116
  tests/goldens/guards, `Backends/SDL` 22 + 32; 0 px against `31d3565` in all
  fourteen offscreen images. **The real-window capture's default/preview
  pair was finally taken, unlocked, mid-task (`6c961e3`), 0 differing** — the
  first unlocked reading since stage 6b; every other state stays owed.
  **`AXNode.actions`/`AXActionKind` are deprecated** toward the new actions
  (no in-repo caller). **An agent cannot run VoiceOver or claim the
  validation** (`IX-AE`): **task 12's box stays unticked** until a human
  runs the script and the Record phase re-reads it.
  Task 13, `AN-X`…`AN-AK` (§64, spec
  `specs/2026-09-30-transactions-animation-design.md`, the existing animation
  decisions doc `2026-09-03-animation-decisions.md`, probe
  `swiftui-transactions-animation.swift`) — **closes task 13**:
  `Transaction`/`withTransaction`/`.transaction(_:)`/`.animation(_:value:)`,
  a transaction stack transparent in layout and paint, one root transaction
  per build (divergence 99); `Binding.animation(_:)`/`.transaction(_:)`,
  applying to a write whose source is `@State`, ignored by a
  `Binding(get:set:)`; every proposal `LayoutModifier` now animates at its
  phase (`.frame`, `.flexibleFrame`'s finite bounds, `.padding`, `.opacity`,
  `.clip`'s radius and `.border`'s width in layout; `.background` and the
  border's colour in paint), state in a window-owned `AnimationStore`, not
  `StateTable`; the legacy paint-only fields (opacity, the three borders'
  widths) now animate in the layout helper, the resolved border colour in
  paint on a store track, `clipsContent` still snaps (a `Bool` has no
  midpoint); a `Component`'s caller modifier animates per member through the
  store, fixing B-7; environment-driven `accessibilityReduceMotion`
  (`public internal(set)`, AppKit's `NSWorkspace` with a change
  notification, SDL a documented `false`) changing only transitions (a
  cross-fade) and leaving property animations unchanged; `AnyTransition`
  (`.identity`/`.opacity`/`.move(edge:)`/`.slide`/`.offset`/`.scale`/
  `.push(from:)`/`.asymmetric`/`.combined`) and `.transition(_:)` for an
  `if`/`else`/`switch`/`ForEach` element, `TransitionGroup`
  identity-transparent, a removed element's ghost replayed from its last
  captured primitives. Three lanes, each red first, all verified `ok`, two
  fix rounds (lane 1's five previously-unpinned clauses; lane 2's clamps,
  `escapesOpacity`, the lexical fallback and hover/focus widths; lane 3's six
  green per-primitive mutations, a point-to-pixel conversion and two stacked-
  transition/insertion-during-removal rules). Divergences 96–99 added (68 →
  72 live, next label 100), none retired. Counts **1959 / 0 / 119** on this
  branch; 0 px against `2de0973` in all fourteen offscreen images. **Every
  clause of the plan's task-13 text closes and task 13 is ticked** — the
  still-open real-window capture (transitions, Reduce Motion's cross-fade,
  `.scale`'s soft mid-flight glyphs now owed alongside it) does not gate the
  tick, by the task's own ruling (`AN-AG`): the plan's text asks for no look,
  and every behaviour here is pinned headless.
  Task 14, `PB-` (§65, decisions doc
  `2026-09-30-platform-boundary-decisions.md`, no spec, no probe —
  the task claims no new SwiftUI behaviour) — **closes task 14**: the user
  decided (2026-09-30) to record the platform boundary rather than build
  iOS/iPadOS. Supported: macOS (AppKit/Metal, the default), Linux and
  Windows (`Backends/SDL`, `XP-A`/`XP-B`). Not supported, none planned: iOS,
  iPadOS, tvOS, watchOS, visionOS — no UIKit conformer, no `.touch` input, no
  safe areas, no `UIApplication`/scene lifecycle, no `UIAccessibility`
  bridge (`PB-A`, amending the design spec's §2 with a dated note, the old
  text kept as history). `PB-A` also names what lifting the boundary would
  need and the gaps a reader might otherwise assume are covered on the
  supported platforms (both conformers implement `AB-R`/`EV-AB`'s
  defaultless pair; VoiceOver has not yet been run by a human on any platform (the macOS script is unrun); the real-window
  capture debt has only ever been taken on macOS). Docs-only: 0
  `Sources:`/`Tests:` files changed, counts unmoved from task 13's **1959 /
  0 / 119**.
  Task 15, the closeout, `CX-A`…`CX-S` (§66, spec
  `specs/2026-09-30-closeout-design.md`, its own decisions doc
  `2026-09-30-closeout-decisions.md`, probe `swiftui-closeout.swift` groups
  O and SW) — **everything an agent can do is closed; the box stays
  unticked until a human runs `docs/verification/human-checks.md`**
  (`CX-M`). The inventory: `docs/probes/closeout-public-api.sh` censuses
  every public declaration (1872 at the time, 1940 since drag and drop), `closeout-inventory-map.tsv` maps each
  to a family of class A (SwiftUI-aligned: a probe arm and a discriminating
  test, mechanically checked to exist and to be asserted), D (divergence
  label), M (MetalUI-only by design), X (deprecated, with replacement) or R
  (documented absence), and `zsh docs/probes/closeout-inventory-check.sh`
  **prints nothing when complete** (`CX-A`, `CX-S`); **a new public
  declaration owes a map row.** Three public documents: `docs/divergences.md`
  (66 live at the time, 69 since drag and drop), `docs/migration.md`, `docs/api-overview.md`; every public
  declaration carries a doc comment (`zsh docs/probes/closeout-undocumented.sh`
  prints nothing, `CX-K`). Rulings: tasks 4 and 5 ticked clause by clause
  (`CX-B`, §66 §5); no deprecated spelling removed (`CX-C`),
  `flexBasis(fraction:)` deprecated; `Box`'s `style:` initialisers `package`,
  public `Box(decoration:)` forwarding (`CX-D`); divergence 52 kept (`CX-E`);
  **divergence 85 fixed** — an optional `@State` (and the public
  `withState`) reads its non-`nil` initial value before the first write,
  SwiftUI's probe O1 (`CX-F`, `CX-Q`; **migration note** there); divergences
  2, 35, 39, 53, 55 retire by re-reading (`CX-R`) — live 72 → 66, next label
  100; macOS CI builds `--build-system native` with `METALUI_REQUIRE_GUARDS=1`
  so a skipped guard fails (`CX-J`); `METALUI_LOOKS_DEMO=1` is the checklist's
  runnable surface (`CX-Q`). The retired engine and the goldens re-verified
  (`CX-N`): 0 goldens, `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  green. Counts **1976 / 0 / 121**; 0 px against `1b093b8` in all fourteen
  offscreen images; the real-window capture was taken at design time (0
  differing) and the screen was locked at every later check. Record §67 holds
  `CLAUDE.md`'s pre-closeout counts history and reference bullets, moved
  verbatim.
  **Drag and drop** (user request 2026-10-01, **not a plan task**; §68, spec
  `specs/2026-10-01-drag-and-drop-design.md`, its own decisions doc
  `2026-10-01-drag-and-drop-decisions.md`, rulings `DN-A`…`DN-Z`, probe
  `swiftui-drag-and-drop.swift` groups `T`/`R`/`A`/`P`) — `Transferable`/
  `ContentType` (MetalUI's own, synchronous, `Data`-based, portable),
  `.draggable(_:)`/`.draggable(_:preview:)`/`.dropDestination(for:action:isTargeted:)`
  on both vocabularies, in-window drags with a replayed translucent preview,
  drops in from Finder/other apps on AppKit and SDL, a drag leaving the window
  as an `NSDraggingSession` on AppKit only; divergences 100–102 added (66 →
  69 live, next label 103). Three lanes plus review rounds, all verified `ok`.
  Counts **2028 / 0 / 125**, `Backends/SDL` 22 + 41; 0 px against `053a3b3` in
  all fourteen offscreen images; the real-window capture not taken (screen
  locked) and **group N of `docs/verification/human-checks.md` is owed to a
  human** — an agent cannot drag. See "Drag and drop" under Architecture rules.
- **SwiftUI probes:** `docs/probes/`; headers carry recorded output and how to
  run them (`SA-O`). Window captures: `docs/probes/window-capture/capture.sh`.
- **Practices:** `docs/practices/verifying-tests-can-fail.md` — read before
  writing tests.
- **Public documents and the human checklist (plan task 15):**
  `docs/api-overview.md` (the surface by area), `docs/divergences.md` (every
  live difference), `docs/migration.md` (legacy → SwiftUI vocabulary and every
  breaking change since 2026-09-12), `docs/verification/human-checks.md` (the
  one list of looks only a person can check — **not run**).

## Build and test

- **Counts (2026-10-01, `feat/drag-and-drop` — drag and drop, from
  `053a3b3`): 2028 tests, 0 goldens, 125 typecheck guards**, 0 `error:` on both
  build systems, the one `warning:` SwiftPM's deprecation notice under native
  (0 under the default one), taken after `swift package clean` with `swift
  build --build-system native --build-tests` then unfiltered `swift test
  --build-system native --no-parallel` (**one summary line**, `Test run with
  2028 tests in 3 suites passed after 107.389 seconds`; the FR-J line
  present). **2028 = 1976 + 52**: lane 1 +30 and its review round +2, lane 2
  +15 and its review round +3, lane 3 +2; no test retired. Guards **125 = 121
  + 4**: `DragAndDropCompileGuards` (3) and `DragPreviewCompileGuards` (1), all
  whole-file `typecheckFile`. `Backends/SDL` 22 + 41 (`MetalUISDLTests` +8); a
  `swift:6.4-noble` aarch64 container builds with 0 `error:`/`warning:` and
  runs **199 + 22 + 14** (`MetalUICrossPlatformTests` 10 + the four portable
  `TransferableTests`); Windows and Linux x86_64 CI confirm on push. Public
  census **1940** declarations in **99** inventory families (record §68 §9).
  `MemoryLayout<Handlers>.size` 448 → 456; the smallest thread building every
  production tree 640 → 656 KB. Plan task 15's figures (**1976 / 0 / 121**)
  are record §66 §7; every earlier count line (one per branch, task 13 back
  to the CSS-engine era) is record §67 §1, frozen; history before that is
  record §06 and §19. A count is stale the moment a test lands; re-measure.

```bash
swift build
swift test --no-parallel
swift test --no-parallel 2>&1 | grep -oE "Test run with [0-9]+ tests" | grep -oE "[0-9]+" | paste -sd+ - | bc   # suite total
METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
swift run MetalUIDemo            # and -c release
METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo   # proposal preview (value exactly "1")
METALUI_TEXT_INPUT_DEMO=1 swift run MetalUIDemo         # two TextFields (TI-F's human looks)
METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo            # Button/Toggle/Slider/Stepper/Picker/List(selection:)
METALUI_DND_DEMO=1 swift run MetalUIDemo                 # drag and drop: chips, wells, a draggable List (human checks group N)
METALUI_LOOKS_DEMO=1 swift run MetalUIDemo               # texts by controlSize, shapes, images, gestures, transitions (human checks H-K)
```

- **Read the printed counts, never the exit status.** `--build-system native`
  prints ONE summary line even with three suites in the run (it says "in 3
  suites"); the default build system may print several (sum them).
  **Twelve** gated tests count toward the total while skipped (eleven before
  plan task 11 part 1's `measureTruncationDifferences`; twelve until
  stage 7a removed `regenerateAllGoldens` with the goldens) —
  `aListsWorkIsTheSameFor100kRowsAsFor500`, the
  FreeType oracle's `measure(file:)`, the HarfBuzz oracle's `measure()`
  (`METALUI_HARFBUZZ_MEASURE=1`) and the portable text oracle's
  `theMeasuredDifferences` (`METALUI_PORTABLE_ORACLE_MEASURE=1`) and the line
  breaking oracle's `measureWrapDifferences` (`METALUI_LINEBREAK_MEASURE=1`)
  and the lines emission oracle's `measureLineEmissionDifferences` and
  `measurePatchedFaceMetrics` (both `METALUI_LINES_EMIT_MEASURE=1`) and the
  content sizes oracle's `measureContentSizeDifferences`
  (`METALUI_CONTENT_MEASURE=1`), `recordDemoFrames`
  (`METALUI_CROSSPLATFORM_RECORD=1`), `measureFallbackDifferences`
  (`METALUI_FALLBACK_MEASURE=1`), `measureBidiDifferences`
  (`METALUI_BIDI_MEASURE=1`) and the truncation oracle's
  `measureTruncationDifferences` (`METALUI_TRUNCATION_MEASURE=1`). **Tests
  that register fonts with CoreText
  process-wide race under a parallel run** (measured with a filtered run:
  the resolver oracle and the seam test fail together) — `--no-parallel`.
  The lone `warning:`
  under native is SwiftPM's deprecation notice.
- **No goldens remain** (stage 7a, record §48):
  `find Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0 — not `find
  Tests`, where `Tests/PortableTests/.build/` holds JSON build artifacts. Each
  of the 97 was retired with a row in record §48 §4: 44 by a native arm that
  builds the golden's own tree and asserts its own boxes under the proposal
  authority (`GoldenReplacementFlexTests`, `GoldenReplacementStackTests`,
  through `goldenArm`), 53 with a named CSS-only concept and the native test
  that pins what the proposal authority does instead. **Do not add a golden
  or a WebKit fixture back**; a layout fact gets a native arm. The proposal
  kernel shares `LayoutTree.swift` storage (`newNode`, `reset`, `roundLayout`,
  the `SA-G`/`SA-I` preconditions), so a proposal-path edit there can move a
  CSS-engine test or a lowering differential — run the whole suite. No text
  fixture, ever (TX-B).
- **Guards:** `grep -c canTypecheck` per file across `PhaseSeparationTests`,
  `ErasureCompileGuards`, `ElementGroupTrapTests`, `ProposalLayoutCompileGuards`,
  `ModifiedElementCompileGuards`, `UnifiedModifiedContentCompileGuards`
  (stage 11), `ProposalNodeIDCompileGuards`,
  `EnvironmentCompileGuards`, `FrameSizingCompileGuards`,
  `DecorationCompileGuards`, `ContainerCompileGuards`,
  `LayoutAuthorityCompileGuards`, `GridCompileGuards`,
  `UnitSafetyTests` (one hit is a comment),
  `AXNodeTests`, `SceneBoundaryCompileGuards`, `StyleSurfaceCompileGuards`
  (stage 10), `ConditionalIdentityCompileGuards`,
  `ExplicitIdentityCompileGuards` (plan task 8),
  `ControlStateCompileGuards` (plan task 9), `ForEachCompileGuards`,
  `BindingCompileGuards` and `ScrollCompileGuards` (plan task 10 part 1),
  `ControlsCompileGuards`,
  `SliderStepperCompileGuards` and `SelectionCompileGuards` (plan task 10
  part 2), `TextSystemCompileGuards`,
  `BaselineCompileGuards` and `TextCompileGuards` (plan task 11 part 1),
  `ShapeCompileGuards` and `ImageCompileGuards` (plan task 11 part 2),
  `GestureCompileGuards`, `ButtonCompileGuards`
  and `FocusStateCompileGuards` (plan task 12 part 1), `AccessibilityCompileGuards`
  (plan task 12 part 2) and, new at plan task 13,
  `TransactionCompileGuards` and `TransitionCompileGuards`, and, new at
  plan task 15, `CloseoutCompileGuards` (`aPlainImportCannotPassBoxAStyle`
  whole-file, and `theTypecheckGuardsRanWhereTheyAreRequired`, which calls
  `canTypecheck` and neither helper), and, new at drag and drop,
  `DragAndDropCompileGuards` (three) and `DragPreviewCompileGuards` (one), all
  whole-file
  (`GridCompileGuards`' own count is unmoved — G3.1 renames its G4 in
  place);
  `Typecheck.swift` holds
  only
  the declaration. Two helpers, 40 and 84, plus one guard calling neither (40 and 80 before drag
  and drop's four; 39 and 80 before
  plan task 15's two; 39 and 77 before task 13's
  three; 39 and 74 before task 12 part 2's
  three; 39 and 69 before task 12 part 1's
  five; 39 and 66 before task 11 part 2's
  three; 39 and 61 before task 11 part 1's
  five; 57 before task 10 part 2's four;
  40 and 50 before task 10 part 1's
  net −1/+7; 48 before task 9's two; 44 before
  task 8's four; 42 before
  stage 11's two; 39
  before stage 10's three; 38
  before stage 8's N3.1, 37
  before stage 6a's): `typecheck(_:importing:)` wraps the fixture in a
  function (Swift 5, nothing `public`/file-scope compiles);
  `typecheckFile(_:importing:)` is whole-file
  Swift 6 — the six/two/six of `ProposalLayout`/`ModifiedElement`/
  `ProposalNodeID`, **two** `UnifiedModifiedContentCompileGuards` (stage 11,
  both whole-file: `aProposalModifierChainInfersOneFlatModifiedContent`,
  `anExternalModifierLayerKindCannotBuildAModifiedContent`), **three**
  `FrameSizing` (stage 8's N3.1 the
  third), three `Decoration`, four `Container`,
  four `Grid`, **two** `LayoutAuthority`, two `SceneBoundary`,
  **three** `StyleSurfaceCompileGuards` (stage 10, all three plain-import
  `typecheckFile` guards: `aPlainImportCannotWriteAStyleField`,
  `theDeletedStyleSpellingsDoNotCompile`, `theLayoutKernelDeclaresNoStyle`),
  **one** `ConditionalIdentityCompileGuards` (plan task 8, `G2.1`,
  `anIfElseAndASwitchCompileInEveryProposalContainer`), **three**
  `ExplicitIdentityCompileGuards` (plan task 8, `G3.1`–`G3.3`, all
  whole-file), **two** `ControlStateCompileGuards` (plan task 9, `T3.4`
  plain-import `import MetalUIPlatform`, `T3.5` plain-import `import MetalUI`,
  both whole-file), **all seven** of `EnvironmentCompileGuards`' (its one
  `typecheck`-based guard, `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`,
  is deleted this task with the alias it pinned, `DD-D` item 6 — every
  guard left in the file already used `typecheckFile`), and, new this task,
  **two** `ForEachCompileGuards` (`G1.1`/`G1.2`, both whole-file), **three**
  `BindingCompileGuards` (`G2.1`–`G2.3`, all whole-file) and **two**
  `ScrollCompileGuards` (`G3.1`/`G3.2`, both whole-file); new at plan task 10
  part 2, **two** `ControlsCompileGuards` (`G1.1`/`G1.2`), **one**
  `SliderStepperCompileGuards` (`G2.1`) and **one** `SelectionCompileGuards`
  (`G3.1`), all four whole-file; at plan task 11 part 1, **two**
  `TextSystemCompileGuards` (`G1.1` lane 1, `G1.2` lane 2's fix round, both
  whole-file), **one** `BaselineCompileGuards` (`G2.1`, whole-file) and
  **two** `TextCompileGuards` (`G3.1`/`G3.2`, both whole-file); new at plan
  task 11 part 2, **two** `ShapeCompileGuards` (`G2.1`
  `anOutsideShapeNeedsOnlyItsGeometry`, `G2.2`
  `theRectangleColorInitialiserIsDeprecatedTowardFill`, both whole-file) and
  **one** `ImageCompileGuards` (`G3.2`
  `anImageHasNoSystemNameOrAssetInitialiser`, whole-file) — `G3.1`, the
  `UnitPoint` grid-anchor guard, is `GridCompileGuards`' own `G4` renamed and
  answer-inverted in place, not a new file, so `GridCompileGuards`' count
  stays four; new at plan task 12 part 1, **two** `GestureCompileGuards`
  (`G1.1` `anOutsideTypeCannotConformToGesture`, `G1.2`
  `theGestureSpellingsCompileFromAPlainImport`, both whole-file), **one**
  `ButtonCompileGuards` (`G2.1` `theButtonSpellingsCompileFromAPlainImport`,
  whole-file — `DecorationCompileGuards`' own new `@Test`, `G2.2`
  `aProposalElementCannotSpellContentShapeBeforeItsTap`, is counted in that
  file's own total, not a new file) and **one** `FocusStateCompileGuards`
  (`G3.1` `theFocusStateSpellingsCompileFromAPlainImport`, whole-file); new
  at plan task 12 part 2, **three** `AccessibilityCompileGuards`
  (`theAccessibilityModifiersCompileFromAPlainImport`,
  `anAXNodesActionsAreDeprecatedTowardAccessibilityAction`,
  `anUnofferedTraitOrActionKindDoesNotCompile`, all whole-file); new at plan
  task 13, **two** `TransactionCompileGuards` (`aScopeCannotWriteReduceMotion`,
  `aPlatformWindowWithoutTheReduceMotionPairDoesNotCompile`, both whole-file)
  and **one** `TransitionCompileGuards`
  (`theUnsupportedTransitionsDoNotCompile`, whole-file — `MG3.19` pins
  `.blurReplace`'s absence). A
  guard about
  what an
  external module can write
  uses `typecheckFile` (`SA-P`). **Guards skip silently** when
  `.build/<triple>/debug/Modules` is not where `#filePath` expects
  (default swiftbuild system, `--scratch-path`, `-c release`) — the total
  does not move and the run passes. A worktree with its own `.build` at its
  root runs them (measured under `~/Developer/worktrees/`, record §28); grep
  the log for `FR-J no-argument frame: succeeded=` rather than assume.
- **Adding an AppKit test? Run the whole suite unfiltered** (shared
  process and run loop; `--filter` is a different program).
- **`swift package clean` when the impossible happens**: SIGSEGV, a truncated
  run with no summary line, an expected value its source cannot produce, or
  `Undefined symbols … direct field offset`. Causes: the untracked shader
  header symlink (`Sources/MetalUIShaderTypes/include/`), and any new
  case/stored property on a public type crossing a module boundary — the grids
  stage added six stored mark tables to `LayoutTree`, and the `MetalUIScene`
  move relocated `Scene`, `FontKey`, `GlyphImage` and the atlas types across
  three modules.
- **The manifest is two lists** (`PC-A`): targets that import no Apple
  framework are declared on every platform; everything else — and the
  portable oracles, which compare against CoreText — under `#if os(macOS)`.
  **A new target goes in the list its imports allow**; Linux and Windows CI
  (`scene-linux`, `root-windows`) build every portable target — `MetalUI`
  and `MetalUIDemoContent` included since `XP-A`, their Apple dependencies
  appended on macOS in the manifest — and run `MetalUILayoutTests`,
  `MetalUICoreTests` and `MetalUICrossPlatformTests` (**199 + 22 + 14** since
  drag and drop's four portable `TransferableTests`, measured in
  `swift:6.4-noble`; **199 + 22 + 10** as of plan task 12 part 1, independently measured in `swift:6.4-noble` by that
  task's own Record phase, unmoved by it — this sentence's own **188 + 22 +
  10** had gone stale across tasks 8 through 11 part 2 without being
  re-taken here; the intervening figure, **199 + 22 + 10**, already stood in
  CLAUDE.md's own task-11-part-1 Counts entry, corrected here to match
  rather than left to contradict it. **188 + 22 + 10** was the figure
  since stage 10, measured in `swift:6.4-noble` — `StyleTests.swift` moved
  from `MetalUILayoutTests` to `MetalUICrossPlatformTests` (`git mv`, its
  four tests following it, `LR-FT` §5.2) and `LegacyEngineSymbolTests`'
  `N2.1` joins the latter too: 192 − 4 = 188, 5 + 4 + 1 = 10; **192 + 22 + 5**
  since stage 9 met PR #30, measured in `swift:6.4-noble` at the merge —
  `DemoStackBudgetTests`' two join `MetalUICrossPlatformTests`; **192 + 22 +
  3** at stage 9 alone; **200 + 22 + 3** measured in `swift:6.4-noble` after stage 7b; the WebKit goldens' 96
  consumer tests and the two ungated corpus tests
  (`everyFixtureFileIsListedInTheCorpus`, `goldenFileRoundTripsThroughJSON`)
  were portable and counted in `MetalUILayoutTests`' figure, so retiring them
  at stage 7a drops it from 486 to 388 (486 − 96 − 2) — the 8 + 8 native
  replacements do not restore it, landing instead in `MetalUITests`, which
  depends on `MetalUIAppKit` and is macOS-only; **stage 7b drops it again,
  388 to 200** (388 − 189 + 1): 190 of `MetalUILayoutTests`' non-golden tests
  retired with the CSS engine's own suites, one of them already
  `#if canImport(Darwin)`-gated on this platform
  (`freezeLoopAllocationsDoNotGrowWithTheItemsOnTheLine`), plus one
  replacement (N1.2) — every other stage-7b replacement lands in
  `MetalUITests`, which Linux and Windows CI do not run (record §49 §6.1,
  `LR-EM` item 5); **stage 9 drops it again, 200 to 192**, lane 2's eight
  `MetalUILayoutTests` retirements, measured in `swift:6.4-noble` at the
  stage-9 head, record §51 §7.6 and §9); **stage 10 moves four from
  `MetalUILayoutTests` to `MetalUICrossPlatformTests` and adds one there**
  (`StyleTests.swift`'s `git mv`, `LegacyEngineSymbolTests`' `N2.1`), giving
  188 + 22 + 10 (record §53 §5.6, independently re-taken record §53 §6.2 item
  6), the last pinning the demo's
  whole frame byte-for-byte against
  macOS (`XP-C`). Inside `MetalUI`, CoreText stays behind `#if
  canImport(MetalUIText)`; off Apple a `Frame`/`Window` without a text system
  traps (`XP-B`). A test there that needs Darwin is compiled out by `#if
  canImport(Darwin)` per declaration (`PC-B`; stage 7a's golden removal also
  retired that rule's only WebKit example — `MetalUILayoutTests` needs no
  `#if canImport(WebKit)` gate anywhere now, since nothing there imports
  WebKit); typecheck guards read only this platform's `.build` (`PC-C`) and
  skip off macOS.
- **Targets:** twenty one-way-dependent (`MetalUICore`, `MetalUILayout`,
  `MetalUIScene`, `CFreeType`, `MetalUIFreeType`, `CHarfBuzz`, `CUnibreak`, `CSheenBidi`,
  `MetalUIHarfBuzz`, `MetalUITextSystem`, `MetalUIPortableText`, `MetalUIText`, `MetalUIShaderTypes`,
  `MetalUIPlatform`, `MetalUIPrimitives`, `MetalUIRender`, `MetalUIAppKit`, `MetalUI`,
  `MetalUIDemoContent`, `MetalUIDemo`) plus
  `Tests/MetalUITestSupport`. `MetalUIDemoContent` holds the demo tree so
  tests can import it (`LR-S`). `MetalUIScene` holds
  `Scene`/`DrawRun`/`PrimitiveKind`, the glyph atlas types and the `FontKey`
  struct; `MetalUIText` and `MetalUIRender` re-export it (`PS-B`), so its
  types need no new import. It is also a library product, consumed by
  `Backends/SDL` — a **separate package** (`MetalUISDL`, so the root never
  needs SDL3) holding `SDLWindowRenderer` and the replay parity harness
  (`RS-D`), and `SDLPlatform`/`SDLWindow`, the SDL3 `Platform` (`SP-A`;
  keys translated to AppKit's characters so `Keymap` works, `SP-C`; accessibility
  through AccessKit** — AT-SPI, UI Automation, and NSAccessibility for the SDL
  window on macOS, `AX-B`/`AX-C`, superseding `SP-B`). **`Backends/SDL`
  links AccessKit's C bindings, fetched, not vendored (`AX-A`)**: run
  `python3 Backends/SDL/scripts/fetch-accesskit.py` once, then build and test
  that package with `PKG_CONFIG_PATH=$PWD/.accesskit` (Windows: the `-Xcc`/
  `-Xswiftc` flags it prints); without it SwiftPM warns about pkg-config and
  the link fails on `accesskit_*`. The root package never needs it. AccessKit
  calls back on its own thread on Linux: callbacks only queue under a lock and
  wake SDL (`mui_wake_for_accessibility`); requests reach
  `onAccessibilityRequest` on the main thread, parked until it is set.
  **Windows draw through `PlatformWindow.renderer`, a
  `WindowRenderer`** (`RS-A`: `beginFrame() -> Float?`, then
  `finishFrame(scene:atlas:)`), declared in `MetalUIPlatform`, which is now
  portable (imports only `MetalUICore`, `MetalUIScene`). `MetalWindowRenderer`
  (`MetalUIRender`, which depends on `MetalUIPlatform` — the old edge
  reversed) is the Metal one over a `RenderSurface` (`RS-B`); the AppKit
  platform lives in `MetalUIAppKit` (`RS-C`) and shares one `Renderer`
  across windows. `Window` holds no `Renderer`. `CFreeType` is FreeType 2.14.3, vendored
  (`FT-A`; `Sources/CFreeType/VENDORED.md`), a C target with no Swift API.
  `MetalUIFreeType` is the FreeType-backed glyph rasterizer (`FreeTypeFont`,
  `FreeTypeRaster`, `FT-B`…`FT-E`) that matches `GlyphRaster`'s contract
  exactly; also a library product, for non-Apple backends. Nothing in
  production calls it — `GlyphRaster` stays the rasterizer on Apple platforms
  (`FT-I`). `CHarfBuzz` is HarfBuzz 14.5.0, vendored (`SH-A`;
  `Sources/CHarfBuzz/VENDORED.md`), a C++ target with no Swift API.
  `MetalUIHarfBuzz` is the HarfBuzz-backed shaper (`HarfBuzzFont`,
  `HarfBuzzShaper`, `SH-B`…`SH-E`), depending on `CHarfBuzz` only; also a
  library product. Nothing in production calls it — `Shaper` stays the shaper
  on Apple platforms (`SH-J`). `MetalUIPortableText` joins the two
  (`PT-A`…`PT-E`): `PortableFont` opens one file in both engines and **checks
  they agree** at construction (`PT-B`), and `PortableText.emit` turns one run
  on one line into `MUIGlyph`s plus atlas coverage with `Frame.draw`'s
  arithmetic (`PT-D`), taking the mask's corner radii, `order` and `layer`
  that `Frame.draw` reads from frame state (`PT-J`; defaults square/0/0) — no
  bidi, itemization or fallback. It also wraps:
  `PortableText.lines(_:font:wrappingAt:)` gives `Shaper.shape(wrappingAt:)`'s
  display lines (UAX #14 via `CUnibreak`, libunibreak 8.0 vendored, `LB-A`),
  equal to CoreText's over 13,464 cases; its four fitting rules are measured
  (`LB-D`: whitespace hangs, advance is the paragraph's share, cluster-then-
  grapheme emergency breaks, 28 pt tab stops) — do not simplify one without
  re-running the oracle. `PortableText.emitLines` draws the wrapped lines
  from a box's top-left with `PortableFont.metrics` (`LB-F`, `LB-H`), equal
  in placement to `ShapedText.placedGlyphs` over 26,928 cases (`LB-I`).
  **Four measured CoreText rules live there — do not simplify one without
  re-running the oracle**: metrics are `hhea`'s (not `FT_Face.ascender`,
  which follows OS/2 under `USE_TYPO_METRICS`; only patched faces see it),
  a TrueType metric is rounded to a 16.16 fraction of the em; design units
  scale `units × (size / unitsPerEm)` (`HarfBuzzFont.points`); and
  `drawnGlyph` drops default ignorables and draws the space glyph for a
  control or hard-break character (`emit` too). `unbreakableRuns`,
  `minContentWidth` and `maxContentWidth` give TX-F's and TX-K's answers
  (`LB-N`); **opportunities are libunibreak's under `"en-strict"`** — its
  English quote tailoring and strict small kana, equal to `CFStringTokenizer`
  over 4,418 class pairs (`LB-L`); Thai (no dictionary) and a German-quote
  typesetter heuristic differ, pinned (`LB-M`). `PortableFontResolver`
  answers `family:size:` from registered font files with
  `CTFontCreateWithName`'s rules — PostScript, family or full name, case
  folded and nothing else; `nil` and every unmatched name give the default
  face (`FN-A`…`FN-C`); its oracle runs once per default face, because a
  single default hides a wrong match on that face's own name. **Every
  shaping path goes through `shapeCascading`** (`FB-A`): a grapheme goes to
  the first face of the font's cascade (`PortableFont.fallbacks`; from the
  resolver, every other registered face, `FB-B`) that covers it, and glyphs
  carry their face to placement and the atlas — a new shaping call site that
  calls `HarfBuzzShaper` directly loses fallback. Runs also split by bidi
  level and script and are shaped in their direction (`BD-B`, SheenBidi,
  vendored as `CSheenBidi`); each line is laid out in UAX #9 visual order,
  a right-to-left line's trailing whitespace hung off its left edge, and a
  line starting inside a split lam-alef re-shaped (`BD-C`) — all measured
  against CoreText, 0 differences over 320 cases. Also a
  library product; nothing in production calls it (`PT-I`). The subpixel
  placement rule lives once, in `GlyphImage.subpixelPlacement(forDeviceX:)`
  (`PT-C`); `GlyphRaster` forwards — do not re-inline it on either side.
  `Experiments/SDLGPU`'s frame 4 is drawn from it (`PT-G`) and replayed by
  `Backends/SDL`; frame 5 is the demo's whole tree, which `Backends/SDL`'s
  `DemoCapture` rebuilds natively on Linux and Windows and checks against
  macOS (scene byte-for-byte, pixels within parity; `DC-B`).
  `renderFrame(_:size:scaleFactor:textSystem:atlas:)` renders a tree
  headless (`DC-A`).

Eight constraints that fail silently:

- `MetalUILayout` imports only `MetalUICore` (anchored grep; since `PC-A`
  an Apple import also fails the Linux and Windows builds), and since stage 10
  declares no `Style` (`LR-FM` item 3; plain-import guard
  `theLayoutKernelDeclaresNoStyle`, which skips silently where guards skip).
- `MetalUIScene` imports only `MetalUIShaderTypes` — no Foundation, CoreText,
  CoreGraphics or Metal (`PS-A`). macOS cannot see a violation; the Swift
  workflow's `scene-linux` job can (`PS-G`). An initialiser that must stay
  unspellable outside the package is `package`, with a plain-import guard
  (`FontKey`, `GlyphImage`: `PS-D`, `PS-E`).
- `MetalUIFreeType` imports only `MetalUIScene` and `CFreeType` — no
  Foundation, CoreText, CoreGraphics or Metal (`FT-K`). macOS cannot see a
  violation; the `scene-linux` job builds this target too, and
  `Tests/PortableTests` (a separate package depending on the root's
  `MetalUIFreeType` product) runs FreeType's own output through Linux and
  Windows CI, pinned byte-for-byte against macOS (`FT-J`).
- `MetalUIHarfBuzz` imports only `CHarfBuzz` — no Foundation, CoreText,
  CoreGraphics or Metal (`SH-K`). macOS cannot see a violation; the
  `scene-linux` job builds this target too, and `Tests/PortableTests` (a
  second test target, `HarfBuzzDeterminismTests`, depending on the root's
  `MetalUIHarfBuzz` and `MetalUIFreeType` products) pins HarfBuzz's glyph
  ids, clusters and design-unit positions byte-for-byte against macOS on
  Linux and Windows CI (`SH-I`).
- `MetalUITextSystem` imports only `MetalUIScene` (`TS-A`), and
  `MetalUIPortableText` only `MetalUIScene`, `MetalUIShaderTypes`,
  `MetalUIHarfBuzz`, `MetalUIFreeType`, `CUnibreak` and `MetalUITextSystem` — no Foundation, CoreText,
  CoreGraphics or Metal (`PT-A`). macOS cannot see a violation; the
  `scene-linux` job builds this target too, and `Tests/PortableTests`' third
  target, `PortableTextDeterminismTests`, pins its emitted rects, advance,
  atlas dirty rect and coverage byte-for-byte against macOS (`PT-H`). **That
  pin's Arabic case is the only test that sees a shaping offset**: the Apple
  oracle's Latin corpus has none (`noCorpusGlyphCarriesAShapingOffset`), so
  dropping `xOffset` from `emit`'s pen walk reddens nothing on macOS except
  the portable package. **`MetalUISystemFonts` is the exception by design**
  (`SF-A`): the one text target with a file system, importing Foundation
  (swift-corelibs-foundation off Apple), `MetalUIFreeType` and
  `MetalUIPortableText` — so discovery never leaks into the portable pipeline.
  A system face is **lazy** (`SF-B`) and, unless it is one of the platform's
  fallback families, **outside the cascade** (`SF-C`): registering a whole
  installation with the byte API instead would open every face when the first
  font resolves (`FB-B`).
- Every `LayoutTree` that could exchange ids needs a distinct `generation`
  (C-3); `Frame` is the only `Sources/` constructor.
- Pixel format is `bgra8Unorm`, never `_sRGB` (gamma-space compositing, §7.8).
- Percentage `padding` resolves against the containing block's
  **width** on every edge; `Style.inset` is horizontal-vs-width,
  vertical-vs-height (AP-D). (`Style.border` had the same rule; the field is
  deleted, `LR-FM` item 1, stage 10.)

## Architecture rules

Detail and pinning tests for every paragraph: §19 "Architecture rules", record §01.

**Phases.** `requestLayout` → `prepaint` → `paint`. `isHovered`, `isActive`,
`isFocused` exist only on `PaintPass`, each typecheck-guarded; a new
paint-only query gains a guard and a bullet in `PhaseSeparationTests.swift`'s
header in the same change.

**Identity is structural; `.id()` overrides a position, never joins it.**
- **An `if` with no `else` and a `for` loop each take ONE structural slot**
  (plan task 8, `ID-B`): `OptionalGroup`/`ArrayGroup` (both the untyped and
  typed copies) reserve one cursor index whether or not they produce
  content, numbering their content from 0 under it — the shape `EitherGroup`
  already had. **A vanishing `if`'s trailing sibling keeps its own state**,
  matching SwiftUI (probe V1); naming the trailing sibling is no longer a
  remedy anything needs. **Content an evaluated conditional removes is
  reset on return** (`ID-C`): when an `OptionalGroup`'s slot or an
  `EitherGroup`'s untaken branch was produced the previous frame, every
  `StateTable` entry under it is deleted, except a `.named("$focus")`/
  `.named("$ax")` component — focus and accessibility retention through a
  toggle are unaffected. **One retention is kept, by design**: a conditional
  that is **not evaluated** (a `List` row out of its window) is untouched
  (`TB-AH`). **A `for` loop's dropped tail is reset on return too, since plan
  task 10** (divergence 74 retired, `DD-C`) — the loop-level twin of `ID-C`'s
  rule: `StateTable.noteLoop` records the slot and the extent each loop
  consumed (four minting copies — `ArrayGroup`'s untyped and typed
  `requestGroupLayout`, `ForEach`'s untyped and typed entries), and `sweep()`
  resets a positional child past this frame's extent and below last frame's,
  or a named child the slot held last frame that this frame produced
  nowhere — `$focus`/`$ax` exempted as `ID-C` exempts them. `ForEach` (new,
  `DD-B`) gets the identical rule, and its own dedupe keeps a duplicate id
  (by value or by minted name) from being produced twice (divergence 79,
  added, `DD-L`). `if`/`else`/`switch` now compile inside every proposal
  container too (`ID-D`). **Migration note**: every element inside a bare
  `if` or a `for` loop moved one identity level deeper at plan task 8; code
  that built a `GlobalElementID` through one by hand needs the slot level.
- **`.id(_:)` now works on every element group**, not only a `StyledElement`
  (`ID-G`, plan task 8): `IdentifiedGroup<Content>` (`ExplicitIdentity.swift`)
  wraps a proposal element, `Grid`, `GridRow` or a `Component`, consuming one
  cursor index named after the string and numbering its content from 0 under
  it — layout-transparent, forwarding `prepaint`/`paint`. A `StyledElement`'s
  own `id(_:) -> Self` is untouched and still wins for `Box`/`Stack`/`Text`/
  `ModifiedElement` (more specific); a changed name resets exactly as the
  legacy spelling does, and `.id()` must still be the outermost modifier.
  **A name an evaluated position leaves is reset** (`ID-R`, the task-8
  closeout): every site that mints a named id notes it at `(parent, cursor
  index)` (`StateTable.noteNamed`); a position holding a different name than
  last frame departs the old one, and `sweep()` resets it (at and under its
  id, `$focus`/`$ax` kept) **unless the frame produced it elsewhere** — so
  `.id` over a, b, a starts the returning name fresh, as SwiftUI does (probe
  X9–X11), and a swap or a loop reorder keeps each name's state. Only an
  EVALUATED position departs a name **through this mechanism**: a name →
  no-name change depart nothing here, and **a `List`'s rows are exempt**
  (`noteWindowedParent`; a row out of its window is not evaluated, `TB-AH`).
  A loop shrinking at its tail is **not** this mechanism's business either —
  since plan task 10 it is reset by the loop-specific rule above
  (`StateTable.noteLoop`, `DD-C`), which retired divergence 74 rather than
  extending `ID-R`'s own position-departure scan to reach it. **A new site
  that mints a named id owes a
  `noteNamed` call and an arm in `everyNamingSiteStartsAReturningNameFresh`**
  — a site without one keeps a departed name's state silently. **Both resets
  (a departed name, `ID-C`'s absent slot) are queued and run in ONE pass over
  the table per `sweep()`** (`ID-R` item 8; `StateTable.lastResetScanWork`,
  pinned by E3.13 `theResetsScanTheTableOncePerSweep`): a per-name or
  per-slot scan costs (departures × table) — 3 002 000 entries a frame for
  1000 renamed rows — and the resets now run after the frame's
  `resolveFocus`, so an exemption test reads a SECOND away frame (C2.13).
  **Focus outlives both resets** (`$focus` is exempt): after `a` → `b` focus
  stays on `a`'s unproduced id and returns with `a`, where SwiftUI drops it —
  a known, unnumbered, unprobed difference owned by plan task 12 (`ID-R` item
  9).
- `.padding(_:)` and every legacy `.frame(...)` return one flat
  `ModifiedElement<LayerBase>` (`MC-A`); each modifier is one layer = one node
  = one id level; outermost layer takes the parent's slot, inner layers are
  `positional(0)`, content numbers from 0 under the innermost (`MC-C`).
  **`.id()` must be the outermost modifier.** Changing layer COUNT resets the
  wrapped element's `@State`/focus/`$anim`/AX node; changing VALUES does not.
  A decoration/handler written after a wrapper configures the outermost layer
  (`.padding(8).background` fills the padded box, `OM-C`). **Since stage 11,
  `ModifiedElement` is a typealias for the unified `ModifiedContent<Content,
  Modifier>`**, and the same recursion (one shared `innermostID`, `wrapLayers`,
  `prepaintLayerBody`, `paintLayer`) walks a proposal chain's `LayoutModifier`
  layers too — every id path above is unchanged and now measured on both
  vocabularies, byte-identical to before unification (`LR-FV`).
- An `.overlay`'s primary numbers under the modifier's id, the overlay under
  `.child(of: id, at: -1)` (`MC-P`); nothing else may mean `-1`. **Since
  stage 11 the legacy `.overlay` is `OverlayModifier<Content, Overlay>`
  generalized over `ElementGroup`** (both vocabularies), with the primary and
  overlay sides each lowered like a frame layer's child
  (`AttachmentLowering.swift`); the `-1` numbering is unmoved (`LR-FX`). **A
  legacy `.background(alignment:content:)` exists too** (plan task 8, `ID-J`):
  `BackgroundModifier<Content, Background>`, the overlay's recipe line for
  line — the background side numbered under `.child(of: id, at: -1)` too,
  painted and prepainted first. A primary of zero or several nodes traps
  naming the count (divergence 73) on both the overlay and the background.
- `GlobalElementID.cachedHash` and `==` are safe alone, unsafe together; do not
  simplify `==`'s chain walk on a green suite.
- Prefer SwiftUI's answer where SwiftUI and CSS differ above the engine (EP-5).

**Legacy containers.** `Column`/`Row` centre on the cross axis, `Box`
stretches (EP-8, set in inits) — a childless `Box` with no cross size paints
nothing. **Modifier order decides which box a modifier reaches**: container
modifiers (`.alignItems`, `.gap`, `.justifyContent`) and item modifiers
(`.flexGrow`, `.alignSelf`, `.margin`) go **before** `.padding`; size (a
`.frame`, since stage 8's deprecation), background and corner radius **after**
it. All wrong orders compile. Chained
`.padding` accumulates. Their defaults still differ from SwiftUI's stacks (`CN-A`, `CN-P`):
`Row`/`Column` gap 0 vs `HStack`/`VStack` 8 (divergence 52, kept by ruling,
`CX-E`); porting `Row {}` → `HStack {}` changes behaviour silently. A
`Stack` lowers to a stack that offers its child its proposal, as `ZStack`
does (stack-algorithms A5; divergence 53 retired, `CX-R`). `Stack` layers last-on-top; no `display: contents`, no z-index.

**Legacy `.frame`** has SwiftUI's full parameter surface and lowers to one
`Style` in `FrameLayer.swift` `FrameSpec.style()` (`FR-C`): fixed axes pinned
by `size` + axis-named `minSize` (never `flexShrink = 0`, `FR-P`); fill only
when BOTH maximums are infinite (`FR-O`). Over exactly one node it lowers to a
one-cell `display: .stack` (`CN-N`) — the child overflows, and `.flexGrow`/
`.alignSelf` on it do nothing (`.frame(maxWidth: .infinity)` fills —
`width(fraction: 1)`, the old remedy, is deprecated and traps, `LR-EY` item
8); `lowered` must
keep `display: .none`. Over 0 or ≥2 nodes it stays a flex row. `idealWidth`/
`idealHeight` lower since stage 9 and answer an unspecified axis (frame
probe C1; `anIdealFrameLowersAtANilProposal`; divergence 39 retired, `CX-R`). `.frame()` with no args is
a deprecated no-op on both paths. **`ElementGroup` keeps exactly ONE fixed
`frame` overload** (`FR-S`). The two hand-spelled `frameStyle` oracles in
`ModifiedElementTests`/`ModifierCompositionProofTests` must change with the
lowering.

**Sizing modifiers** (`width`, `height`, `min/max…`, `width(fraction:)`,
`height(fraction:)`) write the element's own box and return `Self`; `.frame`
wraps (`FR-F`). **Deprecated toward `.frame` since stage 8** (`FR-I`; the eight
`StyledElement` sizing modifiers — the six sizes and clamps plus the two
`fraction:` spellings — `LR-ER` item 1, `LR-EU`, with messages, not
`renamed:`): every in-repo caller converted in
the same change, `FR-I`'s one move, as stage 6a did for the public registrars
(the branch gates on 0 `warning:`). The recipe (`LR-ES`): one frame per run of
adjacent calls (R1); a decoration, handler, accessibility modifier, `hidden()`
or `.id()` on the sized element moves **after** the frame, onto the outer layer
(R2, `.id()` still outermost); a sized container's frame reproduces where its
content sat via `alignment:` (R3); an item field between the frame and its
nearest inner wrapper is the frame's child's record and is **dropped**, and
one written after the frame reports `modifierLayer.style` (a production trap) —
it is re-spelled in SwiftUI's vocabulary instead, e.g. `flexGrow(1)` on a fixed cross
axis → `.frame(<cross>: v).frame(max<Main>: .infinity)` (R4); a fixed axis and
a bound on the other axis are two frames, the flexible one inner, **both**
aligned where the content sat (R5); an absolute box's size is a frame
**before** `.position`/`.inset` (R6, `LR-EV` — a framed box over at most one
node can itself be a `Deferred`'s presentation content, discharging the two
`…absolute` fields stage 5 left here); a structural path used only to locate
state is re-derived, one asserted as a value keeps its site (R7); an animated
size interpolates as before, nothing snaps (R8). `Component.width`/`height`
and `StyledComponent.width`/`height` are **not** deprecated — they neither
write an element's own box nor return `Self`. **Reconciled at stage 11 by
ruling, with no API change** (`LR-FY` §6.2): `.width`/`.height` are one
native frame per member (`LR-BG`, SwiftUI's `Group` shape), `.frame` is one
layer over the members' row (`LR-BH`); they are different modifiers, both
stay undeprecated with their doc comments saying so, and making `.frame`
distribute per member (SwiftUI's `Group` answer) is plan task 8's, not a
sizing-vocabulary question. **There is no automatic minimum
to cancel** (`LR-ET`, amending `FR-G`): a greedy frame's lower bound is its
content unless it declares one, SwiftUI's rule (probe
`swiftui-engine-stage-8.swift` F), so a growing box that must answer below its
content is `.frame(minHeight: 0, maxHeight: .infinity)` — the minimum on the
greedy frame itself, not a `.frame(minHeight: 0)` layer inside it (`FR-G`'s
N9/N9b) — pinned by `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`.
The demo's own FR-G caller has been inert since stage 6b (its box holds a
lowered `ScrollView`, whose viewport fills its proposal, `LR-BB`). `fraction: 0.5` is half; `percent:` is a
deprecated rename that still takes a fraction (`CN-O`).

**`List`** is a windowed `Box`: needs `Identifiable` data and uniform
`rowHeight`, inside an enclosing `ScrollView`. **Since plan task 10 it windows
against its own measured origin, not the scroller's** (`DD-F`, divergence 14
retired): in `prepaint` it stores its bounds' origin within the scroller's
content at its own id through `withState` (never a dirtying `write`) and
reads `[offset − origin, offset − origin + viewport)` against it — a header
or any other sibling above it in the scroller no longer blanks it (the old
"must be that scroller's only layout-contributing child" requirement is
gone). It asks for exactly one more frame, via `requestAnotherFrame()`, when
a fresh origin, viewport or resolved offset would give a window not
contained in the one it built — closing divergence 13's *effect* (a grown
viewport staying blank with no input) while divergence 13 itself (the first
frame after a resize still windows against last frame's extent) is
**amended, kept**. Frame 0 builds every row. Rows out of window >2
generations lose `@State` once the table exceeds 256 entries (TB-AH; one
entry sooner per scrolled `List` since `DD-F` added its own `ListOrigin`
entry, `DD-O` item 2) — keep durable values in data. Publishes an `AXTable`
of realized rows only.

**A `List` lowers** (stage 4, `LR-BQ`…`LR-CG`; its only path since stage 9
deleted the legacy CSS engine): its rows are a `ListRows` group whose realized
rows are consumed, planned and wrapped by stage 2's item machinery and placed
by a `WindowedRowsLayout` at `(firstIndex + i) × rowHeight`; the layout
answers `rowHeight × logicalCount` on the height — **not** SwiftUI's greedy
answer (probe K6): a `List` is virtualized and its content height is the
point — and the proposal, or its widest realized row at a nil axis, on the
width. There is **no site check and no `.list` site report left**. The
leading spacer is a bare node, not a `Box` element: it mints no `$anim`
entry, records no `elementBounds` row and does not animate, one fewer
`StateTable` id per `List`. Row identity, `@State` and focus retention and
their loss past the bound, the `AXTable` and its `AXIndex`es, the
unbounded-window and one-more-frame rules, `MP-I`'s cold frame, wheel
routing, hit testing and the disabled gate are all measured against this
lowering (stage 9 collapsed the "both authorities" pins onto it alone); **divergence 13 survives, amended; divergence 14 retires** (`DD-F`).

**`List(selection:)`** (plan task 10 part 2, `DD-Z`, divergence 83): the
initialisers `List(_:selection:rowHeight:row:)` take `Binding<ID?>` or
`Binding<Set<ID>>`, `ID = Data.Element.ID`. The list reads the binding fresh
every frame and never prunes it (removing a selected datum writes nothing; it
re-selects when the datum returns). A selected row's `Box` gets `.accent`
(one `$anim-color` slot per selected *realised* row, `TB-AH`'s crossing
`2n + 6 + s`) and the internal `AXNode.selectionHint` (`isSelected` for a
client, no `$ax` write — `DD-U` item 4). A click selects the row (replacing
the set in a multi list); the platform shortcut modifier (⌘ on Apple, ctrl
elsewhere, via `ControlKeys`) toggles it; ⇧ selects the range from the
anchor; a single list always selects the clicked row. A click also focuses
the list (`ClickDispatch.focusRequest`, the second exception to "clicking
does not focus" after `TextField`), so its arrows work next. Lead and anchor
live in `ListOrigin`, the list's one `StateTable` entry (shared with `DD-F`'s
scroll origin, written with `withState` from input only); a lead the model
drops is re-derived as the first selected row in data order, and every range
or re-derivation happens in the input handlers, not `requestLayout`, so a
selectable list's warm frame stays O(window) at any row count. A focused
list's ↓/↑ move the lead (⇧ extends/shrinks from the anchor in a multi
list); the new lead is revealed through `ScrollViewReader`'s queue
(`ListLeadReveal(list:row:)`, an internal key scoped to the list's parent so
only that list's own reveal resolves it). **Since plan task 12 part 2, an
AppKit accessibility client can also set the selection directly**
(divergence 83 retires on that bridge, `IX-AA`): `setAccessibilitySelected(true)`
on a selectable row and `setAccessibilitySelectedRows(_:)` on the outline
reach `Window` through `.select`/`.selectRows`, dispatched to the list's own
`AccessibilityRowSelection` handler (registered beside the click selection,
gated as every action is); AccessKit still selects a row only by **pressing**
it (0.23 has no select action) and publishes a selectable row's `selected`
**false** as well as true. A row
carries `logicalIndex`, and publishes as `.row`, only while its window is
bounded; while it can never be bounded (no enclosing vertical scroller, or a
zero `rowHeight`) a selected row publishes as a `.button` labelled by its
content — **not** while a bounded scroller's viewport is merely still
unmeasured on frame 0, which keeps `AB-X` rule 1 (the table, no rows)
exactly as an unselected list does.

**Every control** (`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, a
selectable `List`; plan task 10 part 2, `DD-R`…`DD-AA`) is built on
`Binding<Value>` and today's element/handler machinery, not a new subsystem:
one hitbox (`onClick` for `Button`/`Toggle`/`Picker` options/`List` rows, the
internal `Handlers.valueTrack` — the tenth member, `TI-B`'s precedent — for a
`Slider`'s press/drag, dispatched by `Window` ahead of click dispatch and
riding the same hitbox, so `.disabled`/`allowsHitTesting(false)` remove it
too); `isFocusable` set on every one of them (**a click still does not focus
any of them**, `List`'s row click excepted, but Tab reaches every one,
`TI-J` — divergence 80: SwiftUI's own
controls take none of these keys without Full Keyboard Access, an
unmeasured setting, so no claim is made about that state); one keyboard
table, `ControlKeys.swift`, keyed on `TextEditing.platform` — Button
Space/Return (Apple)/Space and Return (elsewhere), Toggle Space, Slider
←↓/→↑ by the accessibility step, Stepper ↓/↑, Picker ←↑/→↓ with no wrap,
`List` per the paragraph above — each running **after** a caller's own
`onKey` declines and, for `Button`/`Toggle`, replacing rather than adding to
a caller's `onClick` (the one-field rule `Handlers.onClick`'s doc already
states); the `.disabled` environment gate in `Frame.registerHandlers` (no
hitbox, nothing in the focus registry, published to accessibility disabled
with no actions); accessibility through five new roles
(`.checkBox`/`.radioButton`/`.radioGroup`/`.slider`/`.incrementor`,
`AXNode`/`AccessibilityRole` on both bridges) with two folds (`AB-G`'s full
fold now covers `.checkBox`/`.radioButton`; a new **partial** fold for
`.incrementor`/`.radioGroup` makes a non-interactive, non-control descendant
the label and keeps an interactive-or-control one, disabled included, as a
child — `DD-U`); the existing animation helpers (a `Slider`'s thumb is drawn
in its own `paint`, so an animated value **snaps** — added to the snaps
list); theme colours. `controlSize`/`controlActiveState` are read only where
named (`Button`'s chrome reads `controlSize`, divergence 76 amended);
**since plan task 12 part 1 (`IX-H`), `controlActiveState` has its first
built-in readers**: an accent-carrying control (`Toggle` on, a `Slider`'s
fill, a segmented `Picker`'s selection) loses its accent to `.separator`
outside the key window, and every one of the five controls draws a focus
ring only while focused, `.separator` outside the key window there too
(`ControlLook.swift`). **`Button` gained a style surface and pressed look
the same task** (`IX-E`, `IX-F`): `ButtonRole` (`.destructive`, `.cancel`,
`.confirm`, `.close` — binds Escape/Return, changes nothing drawn),
`ButtonStyle` (`.automatic`/`.bordered`/`.borderless`/`.plain`, chrome
dropped **by value** for the last two so a caller's own `.background`
survives either way round `.buttonStyle`), a pressed wash painted after the
chrome's content while down and over the target, and `.keyboardShortcut`
(`KeyEquivalent`/`KeyboardShortcut`, matched exactly, case-folded, riding
`FocusRegistry`'s table in registration order, gated by `isEnabled` alone —
**a hidden button's shortcut still fires**, `hidden()`'s keyboard gate is
the focus half only). **Still not built**: `ButtonStyle`/`PrimitiveButtonStyle`
as open protocols, `.borderedProminent`, `.link`, `.toggleStyle`,
`.pickerStyle(.menu)` (still a closed `PickerStyle` struct, not SwiftUI's
protocol) — owner none (`IX-E`, `IX-M`). `PickerStyle`'s options are found through an
internal picker scope pushed around the content's layout phase only
(`Picker.swift`'s `@MainActor` static stack), not by walking the content;
`TaggedElement` (from `.tag(_:)`) forwards every `Element` requirement, and a
tag outside a `Picker` is transparent. `ClickDispatch` (internal) carries a
completing click's modifiers and a handler's optional focus request through
`Window.dispatchClick`/an accessibility `.press`, both paths honouring a
focus request the same way — a public tap-with-modifiers API (`sequenced`,
`@GestureState`, `GestureMask`, a custom `body` gesture, location taps) stays
owner none (`IX-B`); `TapGesture`/`LongPressGesture`/`DragGesture` and their
composition are built (see "Gestures" below), a different surface from
`onClick`, which is unchanged.

**`ScrollViewReader`/`scrollTo` (`DD-G`…`DD-I`, `DD-K`; plan task 10 part 1).**
`ScrollViewReader` is one slot with its own identity level, exactly as a
`GridRow` or a `ForEach` element is — its content numbers from 0 under it,
and a `ScrollViewProxy`'s reach is its own subtree only (probe S2: the key
only under another reader moves nothing). `scrollTo(_:anchor:)` enqueues a
request on a window-owned queue; the next frame's prepaint resolves it
against the **first** element recorded at or under a matching key within
the reader's scope — **keys compared by value** (`AnyHashable`, `DD-K`: SwiftUI
distinguishes `10` from `"10"`, so does MetalUI), matched against a
`ForEach` element's typed key, a `List` row's `datum.id`, or an `.id(_:)`
name, in that order, noted only while a request is pending so a steady
frame pays nothing. With an anchor the target lands at `minY − anchor.y ×
(viewport − height)`; with none, the least distance. Only the nearest
enclosing scroller moves, and the resolved offset lands one frame after the
call (`requestAnotherFrame()`), same as `scrollTo`'s own asynchrony in
SwiftUI. `ScrollIndicatorVisibility` gains `.visible` (SwiftUI's overlay
scrollers treat it as `.automatic`) and `.never` (as `.hidden`) — measured
macOS behaviour, not new inert state (`DD-H`).

**`Deferred`** is a portal: one child, no layout node, hoists to the root
layer, resets clip and scroll offset (AP-I) but **not opacity** (`OM-AA`).
One element contributes one opacity scope (divergence 46). Absolute
positioning is `.position(.absolute)` + `.inset(...)`. A tooltip needs the
portal; a modal needs both.

**A `Deferred` whose one content node is
`.position(.absolute)` is a presentation root** (stage 5, `LR-CH`…`LR-CS`;
unconditional since stage 9): the content lowers as element → greedy W on
each stretched axis (aliased as the element's rect) → padding for the given
insets → a window-sized frame aligned per axis, laid out in its own native
run **before** the root in `Frame.computeRootLayout` — so `SA-M`'s work
counters and `SA-L`'s depth still read the root's own run. The `Deferred`
hands its parent a 0×0 placeholder aliased to the content's element rect,
dropped by every lowered container. An **in-flow** `Deferred` is untouched.
The declaring scope's environment, escape from every clip (divergence 10) and
click-to-dismiss/wheel routing (`IN-W`) all still hold, pinned by
`PresentationWindowTests`. **The containing block is always the window,
whatever surrounds the presentation** — stage 9 deleted the
`deferred.containingBlock`/`.nested`/`.root` reports along with the legacy
engine whose containing block they protected (`LR-FF`;
`aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt`). An absolute
box **outside** a `Deferred` (`position`/`inset` at the consumer) and
`minSize`/`maxSize` on an absolute box's `auto` axis (`…absolute`, and only
on a `Style`-written box: a `.frame` written before `.position(.absolute)`
over at most one node answers SwiftUI's frame bounds and never reports,
`LR-EV`) are **permanent refusals since stage 10** (`LR-FO` item 2:
`owner: nil`, no lowering will ever answer them — the kernel's only absolute
layout is a presentation's) each **report by name** rather than lower to a
different answer. **A `Component`'s amend over a presentation member no
longer reports, since stage 11** (`deferred.amended` deleted, `LR-FY` §6.1):
it answers exactly as a legacy `.frame` **layer** over the same member
already did — the placeholder handed on and dropped, the presentation's
containing block the window whatever surrounds it.

**`Component`** is layout-transparent and identity-opaque: no layout node, one
cursor index, `@State` under its own id. Its `.padding` wraps each top-level
node (`OM-D`); `.width`/`.height` **frame** each member (one frame per
member, `LR-BG`), SwiftUI's own answer (`ID-K`, divergence 48 retired —
overwriting was the CSS engine's); `.frame` wraps the body in one layer,
one flex item in its parent rather than SwiftUI's per-member `Group`
distribution — kept, divergence 56 (`ID-I`). **`.id(_:)` now works** via
`IdentifiedGroup` (plan task 8, `ID-G`; `var elementID` is still how a
`Component` names itself by type). **`.background(alignment:content:)` is
now offered too, exactly as `.overlay { }` already was** (`ID-J`) — a
one-member component attaches, a multi-member one traps naming the count
(divergence 73). The decoration-backed `background(_ token:)`/`onClick`/
`focusable` are still **not** offered (declare them on the members) — by
type only, and `anyComponent.frame(...)` is a side door. A caller's modifier
on a component never animates (B-7): declare animated sizes inside it. Over
proposal content declare `some ProposalElementGroup`.

**`@State`** is a box seeded by reflection per element per frame; slots are
`.named("$state<n>")`. Seven reserved names (`$state<n>`, `$focus`, `$ax`,
`$anim`, `$anim-color` slots; `$anim-content`/`$anim-viewport` id prefixes),
pinned by `theSevenRetentionSlotsAreMutuallyDistinct`. **Write from input,
never from a phase** (keeps the link awake forever). **`@State`/`@Environment`
bind inside an `AnyElement`** (plan task 8, `ID-E`): `AnyElementBox` binds its
concrete element before `requestLayout`, `prepaint` and `paint` — no longer
inert. `prepaintGroup`/`paintGroup` re-bind, so a group-entry bind is
observable only at layout time. **One element VALUE placed twice, read or
written by a handler under input dispatch, resolves its own occurrence**
(`ID-F`, `StateDispatch.swift`, divergence 19 retired); a write from
**outside** dispatch — a phase, or a raw closure call — still reaches the
*last-bound* occurrence (divergence 71, kept) — build two values there.
**`$state` projects a `Binding<Value>`** through the box (`State.projectedValue`,
plan task 10, `DD-D`), so a write through any number of `@Binding` hops
resolves the slot at call time, exactly as a direct `$state` write does.

**`Binding<Value>`** (plan task 10, `DD-D`) is SwiftUI's own surface —
`init(get:set:)`, `.constant(_:)`, `wrappedValue`/`projectedValue`, the
dynamic-member subscript for a key-path-derived binding, and the two
optional initialisers (`init?(Binding<Value?>)` nil over nil; `init(Binding<V>)
as V?` ignores a nil write, returning the last non-nil value it read) — but
**`@MainActor`, where SwiftUI's is nonisolated and `Sendable`** (divergence
78, added: `State` is already main-actor-only in MetalUI and a binding's
whole job is to reach it). **A binding write is a `@State` write**: it
dirties the window and fires `onWrite` through `State.wrappedValue`'s own
setter, so the same rule applies — write from input, never from a phase.
`TextField`/`TextEditor` gain `Binding<String>` initialisers forwarding to
the controlled ones (`DD-E`); nothing controlled moves. **The deprecated
`typealias Binding = KeyBinding` is deleted in the same change** (`EV-N`);
`KeyBinding` is unrelated to it and unchanged — see "Environment" below.
**Since plan task 13, `Binding.transaction`/`.animation(_:)`/`.transaction(_:)`**
(`AN-Z`) apply only to a write whose source is `State.projectedValue` (and
every binding derived from it); a `Binding(get:set:)` over a closure or an
observable model ignores its transaction and snaps — see "Animation" below.

**`@Observable`**: the whole frame build is tracked. The `RedrawSentinel`, the
flush ordering in `drawFrameIfNeeded`, the `isFlushing` guard and
`markDirtyFromObservation`'s two branches are all load-bearing (RX-K);
collapsing either branch breaks the suite. A phase-time `@Observable` write is
silently stale.

**Hit testing.** One hitbox list; ranking is `topmostHitbox(in:at:where:)` —
`topmostOpaqueHitbox(in:at:)` is its `\.opaque` specialization, no second copy
(drag and drop's destination lookup uses it too, `DN-F`). `onClick`, a `TextField`'s `textInput` or a `Slider`'s
`valueTrack` makes an opaque pointer target (`Handlers.isPointerTarget`); the
keyboard gate (`onKey || isFocusable || actions || keyContext`) stays separate.
**A wheel over a non-scrolling opaque hitbox passes to its nearest ancestor
scroller on the same layer** (`DD-Y`, divergence 16 retired,
`Window.enclosingScroller(of:at:)`); an overlaid-but-not-enclosed target or a
`Deferred` scrim still stops it.
`allowsHitTesting(false)` gates only `registerHandlers`' pointer hitbox —
scroll regions and raw `insertHitbox` bypass it (`OM-AK`); it is per layer
(divergence 44). **Since plan task 12 part 2, a press is not a hitbox
query**: an enabled `onClick` the gate withholds a hitbox from is still
advertised to and run by an accessibility client (`Frame.accessibilityPressOnly`,
divergence 28 retired, `IX-Z`) — a mouse click at the same point still finds
nothing. `contentShape(inset:)` moves the pointer region only and
needs an `onClick` on its layer (`OM-J`, `OM-AB`). **Since plan task 12 part
1, `contentShape<S: Shape>(_:)` takes any `Shape`** (`IX-L`; on
`StyledElement`, `OnTapModifier` and `GestureModifier`), composing with
`contentShape(inset:)` (the shape's geometry is read in the inset rect) —
`Hitbox.contains` tests the clipped rect first, then the shape (the shape is
never itself clipped, so it can only shrink a region the clip already
bounds, divergence 43 amended). `clipShape`'s own hit behaviour intersects
with the clip's rect, not its rounded geometry (unmeasured against SwiftUI,
MetalUI's own choice). Default hit region is the whole frame (41, amended:
a bare `Shape`'s default hit region is its frame too). Handlers outlive the
frame: `.onClick { window.x() }` is a retain cycle.

**Gestures (plan task 12 part 1, `IX-B`…`IX-D`).** `TapGesture`,
`LongPressGesture`, `DragGesture`, `.exclusively(before:)`/
`.simultaneously(with:)`, and on every element `.onTapGesture`/
`.onLongPressGesture`/`.gesture`/`.simultaneousGesture`/`.highPriorityGesture`
— a surface beside `onClick`, not a replacement for it (`onClick`'s own doc
was wrongly calling itself "SwiftUI's `onTapGesture`"; it is Button
semantics — press and release on the same element, an excursion allowed).
`Gesture`'s one requirement is `@_spi`-gated, so it is closed to a plain
importer. **One arena per press, formed from the one ranking**
(`topmostOpaqueHitbox`) **and its target's proper ancestors in its own hit
layer** — a `Deferred` presentation's content is hoisted to a higher layer,
so a declaring ancestor's gesture does **not** reach a press inside a sheet,
popover or modal, though it does reach one inside a same-layer `.overlay`
(`IX-Q`). Inner beats outer for a normal gesture; outer high-priority beats
inner; simultaneous members fire too, and first; a lower-priority member
runs once every higher one has failed. A withheld member (behind one still
undecided) reports neither a change nor an end, so a target's `onClick`
holds an ancestor's normal `DragGesture` off for the whole press — `onClick`
never fails on a move. The tick advance runs in the display-link callback,
ahead of `drawFrameIfNeeded`, so a stamp is always a real tick; the window
re-dirties only while something is pending. A gesture callback runs under
`StateDispatch`, resolving the occurrence that dispatched it (`ID-F`).

**Drag and drop (`DN-`, `docs/record/68-drag-and-drop.md`).**
`Transferable` is MetalUI's own four synchronous members (`exportedContentTypes()`,
`static importedContentTypes()`, `exported(as:)`, `init?(importing:contentType:)`)
over `ContentType`s that carry their conformance — `String`, `URL` and `Data`
conform; SwiftUI's `transferRepresentation` and `visibility:` are not offered
(`DN-B`, `DN-S`), and `.onDrag`/`.onDrop`/`DropDelegate` and the `DropSession`
family are ruled out (`DN-A`). `.draggable`/`.dropDestination` return `Self` on
a `StyledElement` (no id moves) and wrap once on a `ProposalElementGroup`
(`DN-P`). **A draggable is a gesture-arena member, not a pointer target**: it
begins on the first pointer move (distance > 0), outranks a tap, long press or
click, yields to a `DragGesture` that outranks it, and registers a **non-opaque**
region joining the arena by identity — `Handlers.isPointerTarget` counts every
gesture except a draggable, so a draggable alone adds no opaque hit target
(`DN-D`, `DN-E`). **The destination is found by the one ranking**
(`topmostHitbox(in:at:where:)` over non-opaque destination regions, never a
second lookup, mutation R1): a covering view does not block a drop, a
presentation on a higher layer does (`DN-F`); the region is registered outside
the `allowsHitTesting` gate and **inside the disabled gate**, so a disabled
source does not drag and a disabled destination refuses (divergence 100,
`DN-G`). `isTargeted(false)` precedes the next `true` and the action; the
action gets destination-local points; Escape cancels ahead of the keymap
(`DN-H`, `DN-I`); a drag neither focuses nor adds a `StateTable` entry, and a
source that vanishes mid-drag still delivers (`DN-O`, 1.25, 1.27). **A new
`StyledElement` site must paint through `paintDecoration`** — the preview's
capture push lives there once, and the proposal side's in
`DraggableModifier.paint` (`DN-X` item 2, the `OM-AI` shape); a site that
skips it drags with no preview. The preview is the source's captured
primitives replayed above everything at 70% opacity, a clip pushed inside the
source kept; a `preview:` closure is a presentation root that registers **no
hitbox and publishes nothing** (`DN-J`, `DN-X`, `DN-Y`). **The platform split**:
drops arrive as `InputEvent.drop(DropEvent)` — AppKit's host view registers
for dragged types and maps `NSDraggingDestination` onto it, reading only the
imported type; SDL's five `SDL_EVENT_DROP_*` events become one session with
**types unknown until the drop** (divergence 102, optimistic highlight); a
drag leaving the window calls the defaultless
`PlatformWindow.beginExternalDrag(_:at:)` — an `NSDraggingSession` on AppKit
(divergence 101), `false` on SDL (SDL3 has no outgoing-drag API). A new
`PlatformWindow` conformer (and every test fake) implements it. Drops, like
every callback, run from input under `StateDispatch`. Accessibility publishes
nothing for either side, as SwiftUI's does not (`DN-N`). An SDL test takes
`SDL_EVENT_DROP_*` types from C-exported constants (the Windows `rawValue`
hazard) and arms `armMainRunLoopExitCheck()`. **Not measured against a real
pointer**: group N of `docs/verification/human-checks.md`.

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
`LR-AA`). `Handlers` has **fifteen** members (the ninth, `textInput`,
internal and set only by `TextField`, `TI-B`; the tenth, `valueTrack`,
internal and set only by `Slider`, `DD-W` item 5; the eleventh through
fourteenth, plan task 12 part 1: `gestures`, `keyboardShortcut`,
`contentShape` and `focusBinding`, each one reference or a small optional —
`MemoryLayout<Handlers>.size` moved 408 → 440 across the task's three
lanes, the smallest thread building every production tree 592 → 624 KB,
`IX-N`; the fifteenth, drag and drop's `dropDestination`, one reference — a
draggable is a `gestures` leaf, not a member — 448 → 456 bytes and 640 → 656
KB, `DN-V` item 5); `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) each gain a field when it
gains one.

**Environment (`EV-`).** `EnvironmentScope` is layout- and
identity-transparent; nearest writer wins; transforms run once per frame in
layout and are re-pushed (`EV-V`). Readable in every phase except `theme`
(`PaintPass` only). `@Environment` binds like `@State`; unbound it silently
reads defaults. `Window.environment` writes always dirty — write from input.
Only `theme` is re-stamped over a scope's write each frame; `displayScale`,
`controlActiveState` and `controlSize` are not (`EV-U`'s `pixelLength` half is
withdrawn by `EV-AA`). **A modifier written after a
scope sits outside it** (`EV-X`). `.disabled(d)` is
`transformEnvironment(\.isEnabled) { $0 = $0 && !d }` (`EV-D`); the one gate
is in `Frame.registerHandlers`' **5-argument** implementation. Disabled: no
hitbox, nothing in the focus registry, still published to AX as disabled.
Scroll regions are outside the gate — including under `.disabled` (`EV-E`;
whether SwiftUI's disabled `ScrollView` agrees is unmeasured, `DD-I` item 3,
a human look owed). A new handler-registering site gains an
arm in the D2 guard. `KeyBinding` is the keymap's own type, unrelated to
`Binding<Value>` (see "`Binding<Value>`" above) — **the deprecated
`typealias Binding = KeyBinding` alias is gone since plan task 10**
(`DD-D` item 6). **`displayScale`** is `public var`, 1 in a bare value;
`pixelLength` is now derived (`displayScale == 0 ? 1 : 1 / displayScale`),
never stored; `Frame` stamps the root's `displayScale` from its own
`scaleFactor` (`EV-AA`) — a scope can write it, and a write changes only the
number, never the scale `Frame.fill` draws at (S3, `EV-AA`). **`controlActiveState`**
(`key`/`active`/`inactive`, `MetalUICore`) comes from `PlatformWindow`'s
defaultless `controlActiveState`/`onControlActiveStateChange` pair, stamped
by `Window` over its own guarded copy at draw, before `Window.environment`
(`EV-AB`) — so `Window.environment`'s `controlActiveState`, like its `theme`
and `displayScale`, is **not** the root's source (three fields, not two).
**Since plan task 12 part 1 (`IX-H`), `controlActiveState` has built-in
readers too**: every control's accent (`Toggle`'s on state, a `Slider`'s
fill, a segmented `Picker`'s selected segment) and focus ring read it,
falling to `.separator` outside the key window — MetalUI's own choice, not a
measured SwiftUI answer (the harness never runs with a real key window).
**Since plan task 13, `accessibilityReduceMotion`** (`AN-AD`) is stamped by
`Window` the same way, from a defaultless `PlatformWindow` pair (AppKit's
`NSWorkspace`, SDL a documented `false`) — `public internal(set)`, so a
scope reads it but cannot write it. **`controlSize`** (SwiftUI's five sizes) is carried and scoped
(`.controlSize(_:)`); its built-in readers, added incrementally, are
`Button`'s chrome (plan task 10 part 2, `DD-R`) and every text's default
font — `Text`, `ProposalText`, `TextField`, `TextEditor`, and through
`Button`'s label — at 9/11/13 pt (plan task 11 part 1, `TE-F`; divergence
76, amended across both tasks). `TextField`'s own padding and every other
control's chrome still read nothing from it. **`dynamicTypeSize`** is
likewise carried and scoped but reaches no text style, by design —
`Font`'s text-style table has no size column to scale (`TE-E`).

**Accessibility (`AB-`; plan task 12 part 2, `IX-U`…`IX-AJ`).** Nothing
recorded until a client activates the window (sticky). Synthesized nodes are
records (`Frame.axEmissions`), never `axNodes` or `$ax` (`AB-U`). Geometry is
not structure (`AB-K`). Every `NSAccessibility` override answers through
`mainActorAnswer(_:fallback:_:)`, never a bare `assumeIsolated` (`AB-AE`). A
`display: none` layer suppresses everything inside via
`Frame.suppressingAccessibilityIfHidden` (`AB-O`). A text-painting conformer
passes `accessibleText:`. Qualify `MetalUIPlatform.AccessibilityRequest` in
files importing AppKit.

**`accessibilityElement(children:)`** (`IX-V`), SwiftUI's spelling and
default (`.ignore`), on `StyledElement` and, new, on `ProposalElementGroup`
through `AccessibilityModifier<Content>` (`GestureModifier`'s shape: one
identity level, its one child numbered from 0 under it). `.ignore` keeps the
node's own declarations, role `.group` (divergence 33 amended: SwiftUI's
`AXUnknown`), and drops the whole subtree, unmerged. `.combine` joins every
non-interactive descendant's text plus the **lead** interactive descendant's
label with `", "`; **children of one kind** take the first one's role,
actions and custom-action list; **children of different kinds merge**
(`IX-AI`): the role is the highest-ranked (slider > checkbox > button > text
field, tie to the first), the value the **last** carrying child's, the lead
the first child that **presses** else the first that is not adjustable else
the first, and only a pressing child is a custom action — an adjustable
child's increment/decrement are added and reach it. `.contain` keeps a real
group with its children, its own label **not** distributed, even over a bare
text leaf (a synthesized `.group` + one child). `accessibilityHidden(true)`
suppresses the element's own registration and its content (an inner
`(false)` cannot un-hide; the outer wins). Eight `AccessibilityTraits`
(closed OptionSet): `.isHeader` → `.heading` with its text as **label**,
distributed; `.isButton`/`.isLink`/`.isImage`/`.isStaticText` set only the
role; removing `.isButton` from a clickable element leaves its press and
folded label, role `.group` (T3p, the same `AXGroup`-for-`AXUnknown` reading
as `.ignore`'s); `.isSelected` on any role; `.isModal` (below);
`.updatesFrequently` published nowhere (declared-but-inert, as SwiftUI's on
macOS). `accessibilityHint`/`accessibilityIdentifier` distribute like a
label. **Declared and named actions** (`IX-Y`): `accessibilityAction(_:)`
makes a node a pressable `.button`, **replacing** a `Button`'s own press, a
declaration (not a synthesis — it records outside
`registerHandlers`'s `synthesizesAccessibility &&` gate, `IX-AF` item 3, so
`HStack{}.accessibilityAction {}` and a declared action over a gesture both
publish); `accessibilityAction(named:_:)` chains into custom actions,
later-written first; disabled refuses both. **`AXNode.actions`/
`AXActionKind` are deprecated** toward these (never read, `AB-H`; no
in-repo caller). **A press under `allowsHitTesting(false)` is advertised and
runs** (divergence 28 retires, `IX-Z`): `Frame.registerHandlers` records an
enabled `onClick` the hit-testing gate withheld in
`Frame.accessibilityPressOnly`, collecting only; `Window`'s press order is a
declared action, a combined node's redirect, the last `onClick` hitbox, then
the press-only handler, all through `runClick` (so a press keeps
`ClickDispatch`'s focus request — a row's click focuses its list, a
button's press does not, `DD-AE` item 2). **Modal isolation** (`IX-X`):
`.isModal` on the greatest `(layer, record position)` among declaring
records publishes only its subtree; a request naming an id outside it is
refused when the last published tree was isolated (**divergence 95, added**
— SwiftUI's held element still presses, kept, owner none, rejected as
avoidable in the critic round). **A `List` row is settable on AppKit**
(divergence 83 retires there, `IX-AA`): `setAccessibilitySelected(true)` →
`.select`, replacing the selection; `setAccessibilitySelectedRows(_:)` →
`.selectRows`, a single list ignoring more than one; `isSelectable` is
derived by the builder from a published parent's row-selection handler, not
declared. **AccessKit still selects a row by `Click`** (0.23 has no select
action) and publishes a selectable row's `selected` **false** as well as
true. **A `List` publishes `AXOutline`/`AXRow`/`AXOutlineRow`** on AppKit
(divergence 32 amended, SwiftUI's own role), realized rows only (kept, owner
none). **The proposal path publishes** (`IX-AB`): `ProposalText` records its
string through `Frame.recordAccessibility`, so a stack or grid's texts
flatten into reading order (a grid row by row) while the container itself
publishes nothing; `AccessibilityModifier` registers its declared node and
actions. `Image(_:scale:label:)` (SwiftUI's labelled init) records an
`.image` node; `Image(decorative:scale:)` still publishes nothing. Both
bridges translate every neutral field, enforced mechanically (a `Mirror`
count of `AccessibilityNode` against each bridge's field → attribute table).

**Focus:** `Window.focus(_:)` moves focus; clicking does not focus —
**except a `TextField`/`TextEditor`**, which a press focuses (`TI-B`), and a
selectable `List` (`DD-Z`) — a click on a plain `.focusable()` view or
`Button` does **not** focus it either (divergence 94, plan task 12 part 1,
`IX-K` item 2, kept — SwiftUI's own click does, F3). **`@FocusState`/
`.focused(_:)`** (plan task 12 part 1, `IX-J`) read the window's focus as of
the last completed frame and move it from input — a write follows every
other mover, applies before the next frame builds, only if the target was
focusable last frame, and never writes from a phase; `.focused` does **not**
make an element focusable. **Focus now leaves with its identity and does not
come back** (`IX-I`, fixing `ID-R` item 9 to SwiftUI's answer): an `if` gone
false, a `for`/`ForEach` that stops producing the focused element, or a
departed `.id` clears focus in the frame that removes it — where it used to
survive indefinitely and return. **Migration**: a caller relying on the old
behaviour refocuses on return, from input (`Window.focus(id)`) or by writing
the `@FocusState` the element is bound with. **Unchanged**: a `List` row
scrolled out of its window (unevaluated, `TB-AH`) keeps focus and gets it
back. **A hidden element is out of the keyboard's focus half** (`IX-K` item
3): `.hidden()` clears focus at the next boundary and blocks Tab/keys, but
**not** a registered keyboard shortcut (a hidden `Button`'s ⌘-key still
fires) — two different gates sharing one `enabled`/`hidden` condition for
focus, `isEnabled` alone for shortcuts. **Tab / shift-Tab (or `U+0019`)
traverse**
every focusable element in tree order, wrapping (`FocusRegistry.tabOrder`,
`TI-J`; tabbing into a field selects its text; ⌘/⌃/⌥-Tab is not traversal).
**Tab reaches every control too** (`Button`, `Toggle`, `Slider`, `Stepper`,
`Picker`, a selectable `List` — all focusable, `DD-T`): AppKit's Tab with
keyboard navigation on, since MetalUI reads no system setting — inside
divergence 80's scope, `TI-J`'s merge amendment, record §60 §Merge. Keys go
to the `Keymap` first, then to a focused field's editing keys, then bubble raw
`onKey` up the parent chain (a control's own `ControlKeys` run there, after a
caller's `onKey` declines), and only then does an unclaimed Tab traverse — so
a binding or `onKey` for Tab wins, and no control claims it. `onKey` bubbles
from the focused element, so with nothing focused it sees nothing.
`focusBorder(_:width:)` is the (opt-in) ring;
background and border resolve `focus ?? hover ?? plain`.

**Text input (`TI-`).** `TextField(_:text:onChange:)` is **controlled** and
one line; since plan task 10 it and `TextEditor` also take a
`Binding<String>` (`TextField(_:text:)`, `TextEditor(_:text:)`, `DD-E`),
forwarding to the controlled initialiser — nothing controlled moves, and a
field bound to `.constant` shows its text and drops every edit.
Its selection, composition and scroll live in `StateTable` under its own id.
While a field is focused, `Window` calls `PlatformWindow.setTextInputArea`
with its caret (nil otherwise), and a printable key arrives as
`.textInput`, not `.keyDown` — AppKit routes it through the input context,
SDL drops the key-down it also sends — so **plain-letter `Keymap` bindings are
silent while a field is focused**; command shortcuts are not. `Window.editedText`
carries an edit until the next frame: two edits between frames must compose
(a cut then a paste read `"pastedhello"` without it). Caret positions come
only from `TextSystem.caretOffsets` (`TI-E`), which follows the font's GDEF
ligature carets and puts a caret halfway through a kern, as CoreText does —
do not re-derive them from advances. `TextEditing` is pure and holds TI-D's
key table for both platforms' conventions (`TextEditing.platform`: control is
the shortcut and word key off Apple). **Undo and redo (`TI-G`) live in the
field's `TextEditState.history`**: ⌘Z / ⌘⇧Z on Apple, ctrl-Z / ctrl-Y /
ctrl-shift-Z elsewhere; typing and single deletes coalesce, and a caret move
ends the group. The history is valid only for the text its last edit
produced — a caller that changes the text itself drops it, rather than an
undo replaying over a text it never saw. **`TextEditor` (`TI-H`)** is the multi-line field: it
draws line by line from `TextSystem.lineRanges`, and its caret, presses and
up/down all read the same `TextLineModel`, so a caret at a wrap sits at the
next line's start. Up and down keep a remembered column (`goalX`), and return
inserts `\n`. Its vertical scroll follows the caret unless the wheel moved
it (`revealsCaret`). The wheel over an editor is routed in
`Window.applyScroll`, ahead of the opaque-hitbox stop. **Page Up/Down
(`TI-I`)** page an editor by its visible height less one line
(`TextLineModel.pageHeight`, from the heights `TextEditor` hands it): on a
Mac they scroll and leave the caret, as NSTextView does; elsewhere they move
the caret that many lines at its column. `TextField` does not claim them, and
neither field claims Tab.

**Text.** `Text` and `ProposalText` measure and draw **only through
`Frame.textSystem`** (`TS-A`): a `TextSystem` chosen once per app
(`App(device:textSystem:)`), CoreText over the frame's `ShapingCache` by
default (`TS-B`), `PortableTextSystem` otherwise (`TS-C`). A new text-drawing
element goes through the seam too — reaching `ShapingCache` or
`placedGlyphs` directly puts it on CoreText whatever the app chose, which
`TextSystemSeamTests` catches only for the elements it renders. Never key a cache on a family or PostScript name — `FontKey` reads
four components off the resolved `CTFont` (and still conflates shaping
behaviour, pinned wrong on purpose). `FontKey` stores its hash; `==` uses it
as early reject only; to force collisions under mutation make the **stored**
hash constant. `FontResolver.resolve` traps on non-finite/non-positive sizes.
`fonts` and `resolvedFonts` are never swept, deliberately — move both or
neither. **`TX-F`'s min-content rule (`CFStringTokenizer`'s longest word, the
public `unbreakableRuns(of:)` and `Shaper.runCallCounter`) is deleted at
stage 9** along with the flex engine's shrink-to-fit query that was its only
caller (`LR-FD`; `ShapingCache.swift`'s doc comment names it). `Text` and
`ProposalText` size an unspecified (nil) width proposal through
`proposalTextMeasurement` → `system.measure(_:font:wrappingAt: nil)` instead —
a SwiftUI-shaped intrinsic one-line width, not a shrink-min-content query; the
two concepts were never the same fact, and only the deleted one used the
tokenizer. Max-content is one line per hard break (TX-K, unaffected). The
glyph atlas is grow-only; `evictUnusedSince` has no caller and would strand
pixels.

**Text semantics (`TE-`, plan task 11 part 1).** The seam's `measure`,
`placeGlyphs` and `lineRanges` each gain an `options:` overload
(`TextLayoutOptions`: `maxLines`, `truncation`, `alignment`) on both text
systems, the old three-argument spellings a protocol extension passing
`TextLayoutOptions()` — a new conformer outside CoreText and
`PortableTextSystem` gets the defaulted spelling for free, but owes the
`options:` one for a caller that needs it (`TS-A` is unmoved: still only
through `Frame.textSystem`). Truncation is CoreText's own truncated line
(`Shaper.truncatedLine`) on both systems — the portable path shapes its `…`
token through `shapeCascading` too, so fallback still applies to the token
(divergence 87 owns the one measured gap, a middle truncation at some
widths). `Font` (`.system(size:weight:design:)`, the eleven text-style
statics, `.custom`, `.weight(_:)`, `.italic()`) and the environment's
`font`/`fontWeight`/`italic`/`foregroundStyle` resolve through **one**
function, `resolveTextStyle` (`TextStyleResolution.swift`), which every
text-drawing element calls for both measurement and paint — a new one that
resolves its own font a different way puts it outside `controlSize`'s reach
and outside `TE-AA`'s weight/italic precedence (the element's own value,
else the environment's, else the font's, else the text style's; italic is
additive, never a `false` override). **A finite height proposal now caps a
text's lines** (`textLines`: the `lineLimit` pair's upper bound, else
`max(1, ⌊height / lineHeight⌋)`) — refuting `ProposalText.swift`'s old,
unprobed doc comment that a height proposal does not truncate or scale text
(`TE-H` item 2, probe `swiftui-text-semantics.swift` L5/X9); the cap at
paint is re-derived from the placed node's rect with the same function, so
a text whose rect is its own measured answer draws exactly what it measured
(`TE-AA` item 4). `controlSize` reaches every text's default font (9/11/13
pt by size) and, through it, `TextField`/`TextEditor`'s and `Button`'s label
(divergence 76, amended across tasks 10 part 2 and 11 part 1); an explicit
or environment font ignores it. `dynamicTypeSize` stays carried and scoped
but reaches no text style — `Font`'s text-style table has no size column
(`TE-E`), a ruled inertness, not an oversight. `VerticalAlignment` gains
`.firstTextBaseline`/`.lastTextBaseline` (a public `enum`, so an exhaustive
external `switch` over it needs a `default:` case, `TE-K` item 1
migration note); the kernel's `NativeNode` measures and aligns by them in a
horizontal stack only — a vertical one traps, and `GridRow` traps naming
divergence 88. The legacy `alignItems.baseline` lowers (row → `baseline:
.first`, column → `flexStart`); `alignSelf.baseline` is consumed under a
baseline row; everywhere else (a `display: .stack` container, any other
`alignSelf` under a baseline row) both are **permanent refusals by name**
(`owner: nil`) — `UnlowerableField.owner`'s `"plan task 11"` branch is
gone, so no report in the kernel names this task as an owner any more.

**Shapes and images (`TE-`, plan task 11 part 2).** What the renderer draws
decides the surface, not the other way round (`TE-AD`): a new drawable
capability is added only when both `Sources/MetalUIRender/Shaders/shaders.metal`
and `Backends/SDL/Shaders/replay.hlsl` gain it identically, checked
through the SDL replay-parity harness (`ReplayFixture`,
`Experiments/SDLGPU`'s `Replay --portable --record`, `PortableReplay`,
`.github/workflows/sdl-gpu-linux.yml`'s `--expect N`) — 0 px on SDL's Metal
backend, within `ParityTolerance` on llvmpipe and D3D12 (CI, on push) —
**every new primitive renders identically on both renderers, or it
is a documented renderer constraint** (spec §9 of the relevant design,
`docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §9 for
this part's own table), never a silent approximation. `Shape` is
`ProposalElement, Sendable` with one main-actor requirement,
`geometry(in:) -> ShapeGeometry` (SwiftUI's `path(in:)` narrowed to what the
renderer draws — a rounded rectangle or an ellipse, nothing else, `TE-AG`),
and one `nonisolated` requirement, `sizeThatFits(_:)`, defaulted to the
proposal (nil → 10); an outside conformer writes `geometry(in:)` alone and
sits in an `HStack` like `Rectangle`. `RoundedRectangle`/`Circle`/`Capsule`/
`Ellipse` are the built-ins; `Circle` alone answers the square of the
smaller proposed side and draws centred. `ShapeView<S>` holds an ordered
list of `.fill`/`.stroke`/`.strokeBorder` layers, painted in declaration
order (a later layer paints over an earlier one); a bare shape fills with
`foregroundStyle ?? .textPrimary` (`TE-AH`). `strokeBorder(w)` is inside the
edge, `stroke(w)` is centred on it (`strokeBorder(w)` over the shape outset
by `w/2`); a width wide enough to meet itself fills the whole shape (K10);
an ellipse's stroke is the SwiftUI inset-band model, not a concentric hole
518 px apart (K8, `TE-AE`) — the same exact-distance algorithm, a trig-free
fixed-iteration closest-point method, in both shader languages, because the
analytic alternatives need transcendentals Vulkan and D3D specify loosely
(`TE-AQ` item 6). **Clipping precedence differs by vocabulary**: on the
proposal path `.clipShape(_:)`/`.clipped()`/`.cornerRadius(_:)` are one
`LayoutModifier` layer, exactly like `.clip(cornerRadius:)`, clipping
hitboxes to the geometry's bounding rect (square — MetalUI's own rule,
`activeClip` alone, not a measured SwiftUI fact, owner plan task 12,
`TE-AQ` item 4); on the legacy path `StyledElement.clipShape<S: Shape &
Hashable>` stores the shape on `Decoration` and **wins over
`clipsContent`** when both are set (`TE-AS` item 4) — but the legacy
`StyledElement.cornerRadius(_:)` itself stays paint-only, divergence 47
kept: making it clip would move hit testing under every rounded legacy box
in the demo, a frozen area (`TE-AJ` item 3). An ellipse geometry in a clip
traps naming divergence 91 (the mask is a rounded rect on every primitive);
two crossing rounded clips still intersect as the square box, divergence 92
— `Frame.intersect` gains one exact case (an inner rounded rect *contained*
in an outer one keeps its own radii, tested per corner disc against the
outer SDF) before that fallback, and only there. `Image`/`ImageBitmap`
stand in for SwiftUI's `Image`/`CGImage` (no Apple image type crosses the
portable seam, `TE-AL`): a decorative image answers `pixels ÷ scale` until
`.resizable()`; `aspectRatio(nil, contentMode:)`/`scaledToFit()`/
`scaledToFill()` measure the child at nil×nil and use its own ratio
(`TE-AM`); `.interpolation` is bilinear for `.low`/`.medium`/the default and
nearest for `.none` — `.high` also draws bilinear, divergence 93, kept.
`gridCellAnchor` now takes a plain `UnitPoint` too (the kernel's cell anchor
is a factor pair, `ProposalAnchor`), retiring divergence 64 (`TE-AN`).
**Not built, each a documented renderer constraint with an owner or
`owner: none`**: continuous corners drawn exactly (divergence 90 covers the
circular approximation), elliptical corners, `Path`, gradients,
`StrokeStyle`, SF Symbols, `colorScheme`/appearance as a readable environment
value, colour glyphs (spec §9's own table names each). **A labelled image's
accessibility is built** (plan task 12 part 2, `IX-AB` item 3):
`Image(_:scale:label:)` records an `.image` node through the label's string;
a decorative `Image` still publishes nothing.

**Renderer.** No semaphore; the atlas texture is written only while
`atlasTextureWasEncoded` is false, else replaced, and it is uploaded
**before** encode (`MetalWindowRenderer.finishFrame`; mutation R1 reddens the
blank-first-frame test). The SDL renderer keeps its atlas texture between
frames and re-uploads it whole when dirty; both clear the atlas' dirty rect
after a frame. **Never release an SDL GPU fence the GPU has not signalled**
(`retire_fence` in `SDLBridge.c` waits first): SDL pools a released fence
while its command buffer still points at it, the next submission re-arms it,
and Direct3D 12 then cleans the newer frame mid-flight — an intermittent
debug-layer crash in `D3D12_INTERNAL_DestroyBuffer`, pinned on macOS by
`backToBackFramesNeverReleaseAnUnsignaledFence` (record §61 §10).
`Text.requestLayout` and
`ProposalText`'s measure closures use unguarded `MainActor.assumeIsolated` —
layout must stay synchronous on the main actor. **`MUIRect.shape`** (plan
task 11 part 2, renamed from an always-zero `_reserved` word — the struct's
128-byte stride, the replay packing and every scene recorded before this
change are unchanged) selects a rounded rectangle (0) or an ellipse (1); the
ellipse fragment computes an exact signed distance, not an SDF gradient
approximation (`TE-AE`). **`MUIImage`** (`Scene.images`, 64 bytes, no
`_reserved` — four whole `float4` lanes) samples one `Scene.textures[texture]`
entry, an immutable `ImageTexture` (premultiplied RGBA8, sRGB gamma space,
no source rectangle — an image always samples its whole texture). **Each
renderer caches one GPU texture per `ImageTexture` identity** (an
`ObjectIdentifier`, the cache holding the object strongly so the identifier
cannot be reused), **uploads on first sight, and releases every cached
texture the frame's scene does not reference** — unlike the grow-only glyph
atlas, an image stream must not accumulate (`TE-AF`). On Metal the cache
belongs to one `Renderer`, shared across every window by `AppKitPlatform`
(`RS-C`); two windows showing different images evict each other's texture
every frame — no production code draws an image yet, so nothing regresses,
but a future multi-window image consumer needs its own answer here (record
§61 §6 item 4, owner: before one ships). `Scene.finalize()` breaks an image
run where the texture changes, so the run count stays the draw-call count.

**Animation (`AN-`; plan task 13, `AN-X`…`AN-AK`).** `withAnimation` writes
`pendingTransaction` (lexical) and `parkedTransaction` (handed to exactly one
frame build). The park rolls back unless a frame build is coming; both
clauses are measured fixes. **`Transaction` (not `Equatable`, as SwiftUI's is
not; `Sendable`, additive beyond SwiftUI's, `AN-AH` item 5) and `withTransaction`** are the general
form (`AN-Y`): `withAnimation(_:_:)` is `withTransaction(Transaction(animation:))`.
The frame's transaction is now a **stack** (`Frame.transactionTop`), read by
both passes as `pass.transaction`; `.transaction(transform)` and
`.animation(_:value:)` return one layout- and identity-transparent
`TransactionScope<Content>`, pushed in layout and paint — a sibling or a
modifier written **after** it is outside its scope (`EV-X`'s rule,
unchanged). `.transaction` rewrites every frame's animation, root animation
or not; `.animation(_:value:)` overrides the top's animation only when its
value changed since last frame and `disablesAnimations` is false, and never
touches an explicit root animation otherwise. **One root transaction per
build**: `withAnimation(A) { withAnimation(B) { a }; b }` animates `a` with B
and `b` with A, and two calls in one interval share the one parked curve —
MetalUI cannot attribute a write to the call that made it, only to the frame
(divergence 99, kept, owner none; `.animation(_:value:)` is the per-value
remedy). **`Binding.transaction`/`.animation(_:)`/`.transaction(_:)`** apply
to a write whose source is `State.projectedValue` (and every binding derived
from one by dynamic member or the optional initialisers, through a source
flag `Binding.stateSource`); a `Binding(get:set:)` over a closure or an
observable model **ignores** its transaction and snaps (`AN-Z`) — SwiftUI's
own behaviour. Layout-phase helper `animated(_:_:for:pass:)`
(`AnimatedStyle.swift`, the legacy `$anim` baseline — now also carrying
`Decoration.opacity` and the four widths of `border`/`hoverBorder`/
`focusBorder`, `AN-AA`); colour helper `animatedBackground`/`animatedColor`
in paint (`AnimatedColor.swift`, needs the theme; the shared decision moved,
unchanged, into `advanceColor(_:from:theme:now:transaction:)`, `AN-AJ`). A
site that skips its helper is silently unanimated — guards
`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` (which
replaced `everyRegisteringSiteAnimatesItsStyle` at stage 7b, record §49 row
241), `everyBackgroundPaintingSiteAnimatesItsColour`. **Every proposal
`LayoutModifier` now animates its numeric case at its own phase** (`AN-AB`):
`.frame`'s width/height, `.flexibleFrame`'s finite bounds, `.padding`'s
insets, `.opacity` and `.clip`'s radius and `.border`'s width interpolate in
layout (the layer rewrites its own case, which prepaint and paint read);
`.background` and the border's resolved colour interpolate in paint as
tokens. **Their state is a window-owned `AnimationStore`, not `StateTable`**
— no reserved-slot count moves, content that leaves and returns starts
fresh with no reset hook, a `List` row out of its window drops its entries
and returns as a first sighting (which snaps). The **legacy border colour**
runs on the same store, under a store key (`$anim-border`), **not** an
eighth `StateTable` slot — the reserved names stay **seven**
(`theSevenRetentionSlotsAreMutuallyDistinct`, `AN-AH` item 3). **A
`Component`'s caller modifier now animates** (B-7 fixed, `AN-AC`):
`StyledComponent` interpolates each op per member in the store, keyed by the
member's id, index and op index — the member's own `$anim` baseline is never
touched. Interpolation is per-component RGB, never hue; slots and store
colour tracks store tokens. "Live" is `Frame.noteActiveAnimation()` →
`hasActiveAnimations`, copied after the whole render; **not**
`wantsAnotherFrame` — never raise both. In-flight values are **clamped**
where a precondition would trip on an overshooting spring (opacity to
`0...1`, border widths and frame sizes to `≥ 0`, a flexible frame's bounds
re-ordered `min ≤ ideal ≤ max`) — a *declared* value is never clamped.
**Snaps:** any `Dimension`/`Length` case change (incl. anything touching
`.auto` — declare a real baseline); on the proposal path, `nil` ↔ value,
finite ↔ infinite, `fixedSize`, `layoutPriority`, `aspectRatio`,
`allowsHitTesting`, alignment and a `clipShape`'s shape (divergence 97,
`AN-AB`); `clipsContent` (a `Bool` has no midpoint — SwiftUI's only
animation of an added clip is the default cross-fade of a structure change);
`Grid`/`GridRow`/stacks/leaves (no modifier layer there); a `Component`'s
`.padding`/`.width`/`.height`/`.frame` structure (only each *op's value*
animates, `AN-AC`); an element returning inside an `if` **or a `for` loop or
`ForEach`** (its `$anim` baseline is reset with the rest of the removed
content, `ID-C`/`ID-P` item 1 for the `if`; the loop case matches since plan
task 10, `DD-C` — divergence 74's retirement, which changed one existing
animation test's own answer, `DD-N`), and a `Slider`'s thumb (drawn in its
own `paint`, so a value written under `withAnimation` jumps, `DD-W`). **An
animated flex-item field snaps its STRUCTURE** (`LR-AS`): the lowering reads
which wrappers exist from the *declared* style and only their values from
the animated one, so a grow that appears or vanishes mid-flight jumps and
two equal declared factors stay equal mid-flight
(`anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`). **SwiftUI
lays out once at the final values and interpolates each view's placed
geometry and render effects; MetalUI keeps interpolating the declared input
and re-runs layout every frame** (`AN-E`'s model, extended to proposal
layers by `AN-AB`) — the two agree for a wrapper's own rectangle and differ
where a child re-lays out or a sibling moves (divergence 96, kept, owner
none — switching to geometry interpolation is rejected: every hitbox,
accessibility frame, clip and scroll region is registered from laid-out
geometry in prepaint, `AN-X`). Tests never sleep: drive
`simulateTick(timestamp:)`.

**Reduce Motion (`AN-AD`).** `EnvironmentValues.accessibilityReduceMotion`
is `public internal(set)` (SwiftUI's own key path is get-only — a scope
cannot write it, guard `aScopeCannotWriteReduceMotion`), sourced from
`PlatformWindow.accessibilityReduceMotion`/`onAccessibilityReduceMotionChange`
— **both with no default implementation** (`EV-AB`/`AB-R`'s reason: a
conformer that forgets the pair fails to compile), stamped by `Window`
beside `controlActiveState`. AppKit reads
`NSWorkspace.accessibilityDisplayShouldReduceMotion` and re-reads it on its
display-options-changed notification — exactly SwiftUI's own source; SDL
answers `false` and never fires (documented; a per-OS read is a roadmap
item). **What it changes, measured**: property animations, `withAnimation`,
`.animation(_:value:)` and `.transaction` are **unchanged**; every
transition except `.identity` becomes an opacity cross-fade on the same
animation.

**Transitions (`AN-AE`…`AN-AK`).** `AnyTransition` supports, each
probe-backed: `.identity`, `.opacity`, `.move(edge:)` (by the element's own
size), `.slide`, `.offset(x:y:)`, `.scale`/`.scale(scale:anchor:)` (a
post-transform of the emitted scene range — the atlas sampling is
independent of the destination bounds on both Metal and SDL, so a glyph
resamples cleanly), `.push(from:)`, `.asymmetric(insertion:removal:)` and
`.combined(with:)`, for an `if`'s content, an `if`/`else`/`switch` branch
and a `ForEach`/`for` element. **Unsupported, listed on the doc comment**:
`.blurReplace` (guarded, `theUnsupportedTransitionsDoNotCompile`),
`.modifier(active:identity:)` and custom transitions,
`AnyTransition.animation(_:)`, `matchedGeometryEffect`, `contentTransition`,
and `.id(_:)` written outside `.transition` (an `IdentifiedGroup` renumbers
the content, so the `TransitionGroup`'s claim fails). `.transition(_:)` is
identity-**transparent** (`TransitionGroup`'s captures live in the
`AnimationStore` under `.named("$transition")`, not a `StateTable` level,
`AN-AH` item 4). **Only the outermost group of inserted or removed content
transitions**; two stacked at one position: the outer claims, the inner is
inert (MetalUI's choice, unprobed). **Insertion needs the conditional to
have been evaluated last frame** — content in the first render, or under a
newly evaluated parent, is not an insertion (`AN-AH` item 2). **Removal
draws a ghost**: the group's last captured primitives, re-emitted at their
last place with the transition applied until the animation ends — no
hitbox, focus, accessibility node or state; ghosts paint above everything
else on their own layer, in the order their removals began. **No default
transition** — an unannotated insertion/removal is instant (divergence 98,
kept, owner none: a default would make every conditional capture primitives
every frame for a ghost it almost never draws). An animated scroll offset
(`scrollTo`) stays unsupported, SwiftUI unmeasured — owner plan task 15.

## SwiftUI alignment — the proposal layout path

The CSS engine is deleted (stage 9, `LR-FC`…`LR-FL`); every element lays
out through the propose/measure/place kernel. Detail: §19
"SwiftUI alignment", record §09, §17, §18, §21, §22, §25, §27, §29, §38, §41, §48, §51.

- **One engine.** The kernel is the private `NativeNode` enum in
  `LayoutTree.swift` (twelve cases + `custom(any ProposalLayout)`); a new case
  must choose its zero-spacing edges. A root is placed centred at its own
  answer (`CN-J`) — unconditional since stage 9 deleted the second engine
  `CN-J` used to contrast with.
- **The layout authority is deleted** (stage 9, `LR-FC`…`LR-FK`):
  `Frame.layoutAuthority`, `Frame.defaultLayoutAuthority`,
  `LayoutAuthority.legacy`/`.proposal` and every per-site authority check are
  gone with the CSS engine they chose between. A legacy element (`Box`,
  `Row`, `Column`, `Stack`, `ScrollView`, `List`, legacy `.frame`) always
  lowers (border-box: content → padding → fixed frame, built from the
  **animated** style, checked against the declared); an unlowerable field
  still traps naming `<site>.<field>` or, with `reportsUnlowerableFields`
  (`Frame`'s init parameter, set only by tests), reports. `LayoutAuthority.swift`
  keeps its name and file but now holds only the lowering's surviving
  diagnostic vocabulary, `LoweringSite` and `UnlowerableField`. **A new
  legacy registration site gains its own check and an arm in
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.** A branch lowering
  from a style needs an animated arm. Differential harness:
  `LayoutDifferential.compare` under `DifferentialRoot` — single-authority
  since stage 9 (a tree is rendered once, with diagnostics on and element
  bounds recorded, and a test asserts its answers by hand-derived literal,
  never against a second engine); never a wrapping `Text` or greedy child
  directly under the root; a diagnostics-mode test pre-flights with
  `try #require` on an empty report. The bounds log is recorded at four
  sites; a new group entry records too.
- **Stage 2 lowers the flex ITEM fields, by the parent** (`LR-AB`…`LR-BA`).
  Every lowered site records a `LoweredItem` and reports no item field itself;
  a lowered container consumes its children's records and wraps each, and **a
  record nobody consumes is reported by name** (`LR-AQ`) — a new lowering site
  that receives children consumes or marks them, or its children's fields go
  silent. Lowered: `stretch` and a non-stretch `alignSelf` as cross-axis frames
  (stretch's is **aliased as the element's rect**, so decoration, hitboxes,
  accessibility and text wrap follow it); `flexGrow` as a greedy main-axis
  frame shared equally; a zero `flexBasis` on an unsized grower;
  `flexShrink: 0` as `fixedSize` and any positive shrink as SwiftUI's
  compression; px/rem `minSize`/`maxSize` folded into a declared size as
  `max(min, min(size, max))`; `Style.border` as insets inside the declared
  size (until stage 10 deleted the field, `LR-FM` item 1); a `Text`'s `Style.padding` around **its leaf** (glyphs paint and wrap
  at the leaf); `margin` as a native padding outside the item frame, unaliased,
  `.auto` as 0, negative accepted; `justifyContent`'s three distributions as
  native spacers plus a rigid gap leaf, with a declared main size only;
  `.rowReverse`/`.columnReverse` as the children's **nodes** reversed with the
  main factor mirrored (identity, paint, hit and accessibility order
  untouched). Still reported by name: percentages, unequal
  grow weights, a length `flexBasis`, a non-greedy `maxSize`, `space-*` on an
  unsized container a parent grows — since stage 10 each a
  **permanent refusal** (`owner: nil`, `LR-FO`). The legacy `baseline` fields
  (`alignItems.baseline`, `alignSelf.baseline`) are no longer this list's
  exception: plan task 11 part 1 lowers a row's `alignItems.baseline` to
  `baseline: .first` on its native stack and a column's to `flexStart`, and
  consumes a child's own `alignSelf.baseline` under a baseline row; a
  `display: .stack` container's `alignItems.baseline` and any other
  `alignSelf.baseline` are now permanent refusals too (`TE-L`), so
  `UnlowerableField.owner`'s `"plan task 11"` branch is deleted and every
  remaining report reads `owner: nil`. `hidden()` lowers since stage 6b
  (`LR-DH`). **Structure reads
  the declared style, values the animated one** (`LR-AS`); a new read of
  `Style` in the lowering owes an animated arm, or it is unpinned. A `Stack`
  and a `.frame` layer ignore a child's margin, as the legacy engine did. A
  child with **no record** — a proposal element such as a `Grid` — gets an
  empty plan: it is never stretched, grown or margined (record §23, X2).
- **Stage 3 lowers scrolling and `Component` distribution** (`LR-BB`…`LR-BP`).
  A `ScrollView` lowers its content through `lowerLegacyNode` at site
  `scrollView` (stage 2's container lowering entire) under a
  `requestNativeScrollViewport`, and records **the viewport** as its own
  `LoweredItem`; `flexShrink: 0` is not carried, and the content record is left
  unconsumed, so a later field belongs on the **declared** content style or it
  vanishes silently (`reportUnconsumedLoweredItems` never reads the animated
  one). The lowered viewport **fills its proposal on the scrolling axis** where
  the legacy one hugs; the cross axis agrees, and divergence 54 **survives**
  because only a `ScrollView` records an item. `ScrollContext`, `$anim-content`
  and `$anim-viewport` are unchanged, and `List` still windows against the
  published context. A `Component`'s `.width`/`.height` lowers to **one native
  frame per member**, aligned per axis (`.center` on a declared axis, 0 on an
  `auto` one) with the member's record consumed and planned at
  `parentKind: .stack`, which **drops** its `flexGrow`, `flexShrink`,
  `flexBasis`, `alignSelf` and `margin`; `.padding` lowers as an ordinary
  one-child container; a `.frame` layer over several member nodes is a row of
  per-member frames at spacing 0. Site `component` has **no reachable report**
  left. **Both scroll suites ran under both authorities until stage 9** — 34
  scenarios folded into the registry that stage 4 renamed and stage 5 grew to
  82 (below); stage 9 deleted `AuthorityCoverage` along with the second
  authority and collapsed every surviving scenario onto its single-authority
  assertion (`LR-FI`, `LR-FJ`).
- **Stage 4 lowers `List`** (`LR-BQ`…`LR-CG`). The behaviour is in the `List`
  paragraph above. Two things a reader needs here: the exit criterion was
  **67 scenarios across ten files under both authorities until stage 9**
  (82 across fifteen since stage 5), and
  `ScrollAuthorityCoverage` was **renamed `AuthorityCoverage`**, with
  `everyScrollScenarioRanUnderBothLayoutAuthorities` renamed
  `everyParameterisedScenarioRanUnderBothLayoutAuthorities` and moved to
  `Tests/MetalUITests/ZZAuthorityRollCall.swift` so that it sorted after every
  contributing file. **Both files are deleted since stage 9** (`LR-FI`),
  which collapsed every one of the registry's scenarios onto a single
  assertion instead of a roll call.
- **Stage 5 makes `Deferred`'s absolute content a presentation root**
  (`LR-CH`…`LR-CS`). The behaviour is in the `Deferred` paragraph above. The
  exit criterion is now **82 scenarios across fifteen files under both
  authorities until stage 9** (`AuthorityCoverage.expected`), and
  presentations are laid out in their own native runs, in registration order,
  **before** the root in `Frame.computeRootLayout` — separate runs so a
  presentation's depth counts from its own root and the root's `SA-M` work
  literal is untouched. The `AuthorityCoverage` registry this exit criterion
  used is deleted at stage 9 along with the second authority it tracked
  (`LR-FI`).
- **Stage 6a deprecates the public custom-element registrars**
  (`LayoutPass.requestNode`/`requestLeaf`, `LR-CT`…`LR-DE`) and moves every
  in-repo test caller off them in the same change — onto
  `requestNativeLeaf`/a `ProposalLayout` where the test is
  authority-independent, or onto the internal, undeprecated
  `Frame.requestNode`/`requestLeaf` where the test is about a CSS answer or
  a root-placement question not yet ruled. The internal registrars stay
  undeprecated (every production site already called them, not the public
  pair); at the time, a custom element that still called the public pair
  under `.proposal` trapped naming **stage 9**, not stage 6a
  (`UnlowerableField.owningStage` for `.customElement`) — **stage 9 deleted
  the public pair outright**, so a plain-import caller no longer compiles at
  all (`aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles`, renamed
  from `…IsWarnedTowardTheNativeOnes`), and `.customElement` is gone from
  `UnlowerableField` with it (`LR-FF`). No production
  behaviour moved at 6a. **The stage's entry measurement** — the default
  authority and eight test-helper `.legacy` defaults flipped together,
  diagnostics on — classified all 153 reds it produced and is recorded as
  stage 6b's (root placement, ~78 reds) and stage 7b's (43 CSS reds)
  baseline table (record §38 §2–§4). No SwiftUI probe: the stage's only
  probe, `docs/probes/swift-deprecated-witness-silence.sh`, is a compiler
  determinism check (a deprecated protocol witness warns nothing), not a
  SwiftUI claim.
- **Stage 6b throws the switch** (`LR-DF`…`LR-DR`): `Frame.defaultLayoutAuthority`
  becomes `.proposal`, and with it `Frame.init`'s default and
  `Window.layoutAuthority`'s initial value — **production now runs the
  proposal engine**. No public spelling gained (`LR-DF` item 2); production
  frames keep trapping, never reporting, on an unlowerable field. Of stage
  6a's 92 still-red rows at the flipped default (record §38 §4, this stage's
  work list): the 14 exit-trap tests are untouched (green once traps are
  fatal again; **12** by lane 2's reading — lane 1 turned three into passing
  tests of the new behaviour and added one, `LR-DQ` item 1), the 2 `D` tests
  are rewritten to assert `.proposal`, `hidden()` now lowers (closing the 5
  `AV` rows, `LR-DH`), a declared root axis folds its px/rem
  `minSize`/`maxSize` (closing the root-fold rows, `LR-DI` amended by
  `LR-DO`), and the 75 root-placement rows (54 RP and 21 of the 23 CE+RP) are
  disposed by `LR-DG`'s fixture rule — 28 re-derive their literals as
  `(W − w) / 2` and run `.proposal` (root placement is unmoved, `CN-J`;
  divergence 4, the legacy engine's top-left window-filling root, stays a
  legacy-authority-only row, retired with the CSS engine by 7b), 43 pass under
  either authority once given the window's extent explicitly on an `auto` root
  axis, 2 keep a greedy frame and 2 that neither recipe greens are pinned
  `.legacy`. **20 tests in all are pinned `.legacy`
  by this stage, each with a named owner** (`LR-DQ` item 2): 15 for 7b (12
  CSS, 1 RP+CSS-frame, the 2 neither-recipe rows) and 5 for 9 (3 N9, the 2
  tokenizer tests). `NativeLayoutRun.maxDepth` moves 88 →
  72, the first release re-bisection alongside debug (`LR-DK`, "Depth guard"
  below); the demo's list row gains `.height(Pixels(28))` (respelled
  `.frame(height: Pixels(28))` by stage 8's deprecation) so its labels stay
  centred under the switch (`LR-DJ`), moving its deepest native level 29 → 30.
  Exit test `noProductionFrameReachesTheLegacyEngine` (`demoContent()`,
  `nativeLayoutPreviewContent()` from `MetalUIDemoContent`, `LR-S`, and a
  `List`, each through a real `Window`, bumping `Frame.legacyRootLayoutCounter`
  zero times) is **retired at stage 9** along with the counter it read —
  there is no longer a legacy engine to reach; **stage 10 replaces it** with
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (a `dlsym` check, macOS
  and Linux, compiled out on Windows). Record §41.
- **Stage 7a retires the 97 WebKit goldens** (`LR-DS`…`LR-EB`). Verdicts
  (`LR-DS`): **R** (44) — the golden's own tree, transcribed field for field
  into `Box(style:)` with each `data-id` on `.id(_:)`, reproduces its rounded
  boxes exactly under the proposal authority with an empty report, and a new
  arm named for the golden asserts them (`goldenArm` in
  `Tests/MetalUITests/GoldenReplacementSupport.swift`: `try #require` on an
  empty report and on each id naming exactly one element; tests 1.1–1.8,
  2.1–2.4); **D** (53) — the concept is CSS-only and deleted with the golden:
  wrap (30), percentages (7), length basis and weighted shrink (6), automatic
  minimum (3), border-box floor (3), unequal grow weights (2), sub-one grow
  sum (2); each row cites the report-by-name test or, for the seven shapes
  that lay out silently with another answer, a pin of the golden's own tree at
  the native answer (2.5–2.7), plus 2.8 for `wrap-reverse`'s report. **A
  replacement arm is a lowering test**: one reddening is a lowering change, not
  a golden drifting. `GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/`,
  `Golden/`, four all-consumer files and 96 consumer tests are gone; one
  consumer, `theClampedAutomaticMinimumIsStillFlooredByPaddingAndBorderMatchesWebKit`,
  survives trimmed for 7b. 7a pre-empts nothing of 7b: every other CSS-engine
  test, `FlexEngine` and every `.legacy`-pinned test stay. Record §48.
- **Stage 8 deprecates the sizing vocabulary** (`LR-ER`…`LR-FB`): the eight
  `StyledElement` sizing modifiers carry `@available(*, deprecated, message:)`
  toward `.frame` (the "Sizing modifiers" paragraph has the recipe), pinned by
  the plain-import guard `theSizingModifiersAreDeprecatedTowardFrame` (N3.1).
  **A test keeps a `Style` write only through `Tests/MetalUITests/CSSSizing.swift`**
  (`cssWidth(_:)` …, the public modifier's closure body verbatim, pinned by
  `theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite`): class K, for a
  test whose subject is a legacy field's lowering, a two-authority comparison
  or a registration site's own handler/decoration/focus/accessibility
  (`LR-EW`, `LR-FB` — R2's move onto a frame layer would silently re-point
  such a pin at `ModifiedElement`). A new test that sizes a box writes
  `.frame`. **`css*` was expected to die with the fields at stage 10; it did
  not** — `Style.size`/`minSize`/`maxSize`, the only fields it writes, survive
  stage 10 as the lowering's own inputs (`LR-FM` item 2), so `CSSSizing.swift`
  stays, the reason above still holds, and only its narrower doc comment was
  corrected (`LR-FO` item 6). A framed absolute box is
  a presentation root (`LR-EV`, one node only); unconsumed as the root it
  reports `position`/`inset` `.unconsumed` (`LR-FA`). Stage 8 pre-empted
  nothing of 9–11: at 8, no engine file, `Style` field, legacy registrar or
  the legacy authority was deleted (stage 9 did); `Component.width`/`height`
  stay undeprecated (stage 11). Record §50.
- **Stage 10 resolves `Style`'s CSS fields field by field, and closes the
  deletion mechanically** (`LR-FM`…`LR-FU`). **Deleted**: `aspectRatio`,
  `overflow` (read by nothing), `Style.border` (`Box(style:)` its only
  writer), `flexWrap`, `alignContent` (read only to be reported) and
  `Position.relative` (read only to be reported), with the enums
  `FlexWrap`/`AlignContent`/`Overflow` and the modifiers
  `flexWrap(_:)`/`alignContent(_:)`. **Narrowed**: every surviving stored
  field (seventeen) and `Display`/`JustifyItems` become `package` — outside
  the package `Style` is opaque (`init()`, `default`, `==`), pinned by
  `aPlainImportCannotWriteAStyleField`; `Box`'s `style:`
  initialisers became `package` at plan task 15 (`CX-D`, guard
  `aPlainImportCannotPassBoxAStyle`); the public `Box(decoration:)` spellings
  forward to them.
  **Moved**: `Style.swift` from `MetalUILayout` to `MetalUI`, its only reader
  since stage 9 — `MetalUILayout` declares no CSS vocabulary at all.
  **`UnlowerableField.owningStage: String` becomes `owner: String?`**
  (`LR-FO` item 3): every report this stage inherited becomes a **permanent
  refusal by name**, not work owed to a later stage — percentages, a
  non-greedy `maxSize`, a length `flexBasis`, a floored `space-*`, a root's
  auto-axis min/max and margin, `…absolute` on a `Style`-written box, unequal
  grow weights, a negative `flexGrow`/`flexShrink`, an absolute box outside a
  `Deferred` (`position`/`inset` at the consumer) and `inset` on a static box
  all read `owner: nil` and the trap message
  `"…and is refused by name (plan task 7, LR-FO)"`; `deferred.amended`
  (`"plan task 7, stage 11"`) and a `baseline` field (`"plan task 11"`) are
  the only two with a live owner left. The mechanical closing check lands:
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (`dlsym`, macOS and
  Linux, compiled out on Windows) in place of the retired
  `noProductionFrameReachesTheLegacyEngine`, three plain-import guards
  (`StyleSurfaceCompileGuards`) and a recorded grep (`LR-FP`). No production
  behaviour moves: no production tree wrote a deleted field, and
  `paddedAndSized`'s insets are the padding alone now that `Style.border` is
  gone (the border fold is deleted with it, not kept at `.zero` — `LR-FU`).
  Stage 10 pre-empts nothing of 11:
  `ModifiedElement`/`ModifiedContent` stay separate, legacy `.overlay` and
  `.opacity` G4 are untouched, and `deferred.amended` stays stage 11's.
  Record §53.
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
- **One authority per root** (`SA-G`; its legacy half retired with the CSS
  engine at stage 9 — `aNativeNodeRegisteredUnderALegacyNodeTraps` and the
  five traps beside it, `LR-FJ` rows 19–24): a `Style` on a native node,
  `computeLayout` on a native root and every legacy/native mixed-tree trap
  are gone, because every element now lowers onto the one kernel and there
  is nothing left to mix. What survives is proposal-only:
  `ProposalElementGroup` has one requirement returning `[ProposalNodeID]`;
  `ProposalNodeID`'s init is internal (`MC-G`). One id registered under two
  parents traps (`CN-L`). **A copy of a pinned entry is unpinned**: the typed
  builder-group entries and `EnvironmentScope`'s are line-for-line copies,
  each with its own pin; a new group gets its own. Single-child proposal
  wrappers precondition exactly one node.
- **Invalidation** (`SA-H`, `SA-I`): the cache lives for one call; answers
  assumed pure; `setLayout` traps during measurement; **one `isLayingOut`
  flag guards the layout run — do not split it.** It once bracketed two
  engines; the CSS engine's bracket in `computeLayout`, unpinned since
  stage 7b (`LR-EQ`), was deleted with `computeLayout` itself at stage 9 —
  one engine, one bracket.
- **Validation** (`SA-J`, `SA-K`): reject a parameter only if SwiftUI rejects
  it or it would make a node non-finite at a finite proposal. Measurements may
  be infinite, stored rects may not, nothing may be NaN. Relaxing a trap into a
  clamp later is additive; the reverse breaks callers.
- **Depth guard** `NativeLayoutRun.maxDepth` = **72** (`SA-L`, moved from 88 by
  stage 6b's `LR-DK`); raise only after re-bisecting all four node kinds in
  **both** debug and release (stage 6b was the first release re-bisection).
  **Chosen by legacy's safety fraction, not legacy's number**: the largest
  multiple of 8 not above 0.60 of the smallest native **debug** ceiling on a
  1 MB thread (the one-child stack, 127/128) — 0.60 × 127 = 76.2, so 72; debug
  governs, release's smallest ceiling (653, also the stacks) is 9× headroom.
  A padded, sized legacy container lowers to 3 native levels, and since
  stage 2 an item with a margin, a padding, a size and a stretch is **five**,
  so a chain of those now reaches the 72/73 boundary at 100/101 nodes (test
  4.8, `LANE4-4.8 nodes=100 deepest=72`; 122/123 at 88; record §41 §10.1). **Production roots,
  measured through a real `Window` at the new default** (record §41 §5,
  §12.3): the demo's deepest native level is **30** (modal off, on, and
  animating — one more than the pre-re-spelling 29, `LR-DJ`'s list-row
  height; the earlier "measured at 18" predated stages 3 and 4, whose scroll
  viewport and windowed `List` add levels), the proposal preview 10, a
  `ScrollView { List }` root 15–16 depending on whether its row declares a
  height. **`SA-L`'s pre-6b table was stale in the direction that mattered**:
  the vertical stack completed 128 levels at `cb2e708` where the 2026-09-14
  table read 151, which by `SA-L`'s own rule gives 72 rather than 88 — found
  by the grids track, closed by stage 6b's re-bisection (`LR-Q` item 3,
  `docs/probes/native-depth-ceiling/`).
  **Work counters:** `LayoutTree.lastNativeLayoutWork` (`SA-M`) on a branching
  tree, literals derived before the run.
- **`Grid` and `GridRow` (stage G, `GR-`).** A column is as wide as its widest
  single-column cell, a row as tall as its tallest.
  - **A grid is a kernel CASE, not a `ProposalLayout`** (`GR-C`), so its
    algorithm is not reachable through the public protocol.
    `Content: ProposalElementGroup`, so `Grid { Box() }` is a compile error,
    not an `SA-G` trap (guard).
  - **A `GridRow` is the one proposal group with an identity level of its
    own**: one cursor index, its cells numbering from 0 under it. A
    `GridCellModifier` is layout- and identity-**transparent**, like
    `EnvironmentScope`.
  - **The row mark is written after the content registers and the OUTERMOST
    row mark wins**; a cell attribute keeps the **first** value written, so the
    **innermost** modifier wins; `gridCellColumns` **sums** along a chain and
    unsized axes **union**.
  - **Attributes are read through a modifier chain** (`frame`, `padding`,
    `fixedSize`, `aspectRatio`, `layoutPriority`, an overlay attachment's
    child 0) and the walk **stops** at a stack, a `ZStack`, an overlay's
    content side, a scroll viewport, a custom layout, a nested grid, a spacer
    or a leaf.
  - **Spacing `nil` is the largest platform-default pair spacing meeting at
    each boundary**, not one number for the grid (`GR-D`); a given value is
    used verbatim on every gap of that axis, negative included.
  - **A vanishing cell or row's state no longer hands on to the next one**
    (plan task 8, `ID-B`; divergence 69 retired): an `if` around a cell in a
    `GridRow`, or around a row in a `Grid`, takes one structural slot whether
    or not it produces content, so the cell or row after it keeps its index
    and there is no "next one" left to adopt the vanished state. `.id(_:)` is now
    spellable on a `Grid`/`GridRow` too, via `IdentifiedGroup` (`ID-G`),
    closing the remedy this row used to say could not be spelled until
    task 8.
  - A grid registers and paints nothing of its own, publishes nothing to
    accessibility and never animates (`GR-K`). It **consumes no `LoweredItem`**,
    so a legacy item field on a top-level cell reports
    `<site>.<field>.unconsumed` (record §23, X4).
- **Vocabulary.** Proposal types: `HStack(alignment:spacing:)`,
  `VStack(alignment:spacing:)`, `ZStack`, `Spacer`, `Rectangle`, `Color`,
  `ProposalFrame` (not `Frame`), `Padding`, `Background`, `FixedSize`,
  `ProposalScrollView`, `ProposalText`, `ProposalLayoutContainer`,
  `Grid(alignment:horizontalSpacing:verticalSpacing:)` and `GridRow(alignment:)`
  with the four cell modifiers `.gridCellColumns(_:)`, `.gridCellAnchor(_:)`,
  `.gridColumnAlignment(_:)` and `.gridCellUnsizedAxes(_:)`, and, since plan
  task 10 part 1, `ForEach` (`extension ForEach: ProposalElementGroup where
  Content: ProposalElementGroup`, `DD-B` — legacy content inside a `ForEach`
  inside a proposal stack does not compile, `DD-B`'s guard G1.2) and
  `ScrollViewReader`/`ScrollViewProxy`/`UnitPoint` (`DD-G`). Since plan task
  11 part 2, `Shape`/`RoundedRectangle`/`Circle`/`Capsule`/`Ellipse`/
  `ShapeView<S>`/`Image`/`ImageBitmap` (each a proposal leaf, `TE-AC`
  onward) and `clipShape(_:)`/`.clipped()`/`.cornerRadius(_:)`/
  `aspectRatio(_:contentMode:)`/`scaledToFit()`/`scaledToFill()` as
  `ProposalElementGroup` modifiers; `gridCellAnchor(_: UnitPoint)` joins the
  existing `ProposalAlignment` overload (`@_disfavoredOverload`, `TE-AN`).
  **`.id(_:)` on any
  `ElementGroup`** (plan task 8, `ID-G`) wraps it in `IdentifiedGroup<Content>`
  (`ExplicitIdentity.swift`); a `StyledElement`'s own `id(_:) -> Self` wins
  where both apply. **A legacy `.background(alignment:content:)`**
  (`ID-J`, `BackgroundModifier<Content, Background>`) joins the token
  `background(_:)` overloads, the overlay's recipe line for line. Modifiers
  on `ProposalElementGroup` return `ModifiedContent<ProposalBase,
  LayoutModifier>` — the unified type's proposal arm since stage 11
  (`LR-FV`), the same struct a legacy `.padding`/`.frame` chain returns with
  `Modifier == ModifierLayer`. `Native…` types and
  `native…` methods are deprecated aliases (except the two `nativeFrame`
  overloads — deprecating them breaks the 0-warning baseline); the kernel's
  `requestNative*`/`newNative*`/`computeNativeLayout` are primary API — 13
  registrars each on `LayoutPass` and `LayoutTree`, plus the two mark
  functions. **Count them by type, not by file**: `Passes.swift` holds only 12
  of `LayoutPass`' registrars; the thirteenth, `requestNativeGrid`, and both
  mark functions are in `Grid.swift`'s extension, so a grep of `Passes.swift`
  alone reads 12 and is wrong.
  `.padding` splits by argument type (no proposal `.padding(Pixels)`).
  `Text.proposalLayout()` silently drops background, handlers, id and
  hover/focus colours. **`ScrollView` and `ProposalScrollView` share one
  `ScrollChrome`** (clamp, extent, delta, indicator bounds, `paintIndicator`,
  both `resolvedOffset` overloads), a computed `var chrome` each side rebuilds
  from its `axis`, `cornerRadius` and `indicatorVisibility`, never stored;
  `ScrollView.clamp`/`.extent` are
  gone. A private copy re-inlined on either side **and drifting** reddens
  `theTwoScrollElementsShareOneChromeImplementation` — measured in both
  directions (M1f and the verifier's V7, each a `paintIndicator` copy with a
  30pt thumb floor). A **byte-identical** re-inline reddens nothing: that test
  compares the two elements' output, not their call graph, so it catches the
  drift, not the copy.
- **`SA-N`'s "probed, and the kernel disagrees" list is EMPTY.** Its last item
  — padding placing its child at the child's own size — was closed by stage 2's
  lane 3 (`LR-AU`) on both entries, pinned by
  `aNativePaddingPlacesItsChildAtTheChildsOwnSize`. Do not re-add a row without
  a probe run now.

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
- **State a "the old wording is gone" claim as the grep reads it.** A corrected
  paragraph usually keeps the old sentence as a quoted erratum, so the grep
  returns one hit and a checking reader concludes the fix never landed. Say
  which hit survives and why.
- **Re-run a mutation a doc comment names when the code under it changes.** A
  later lane can delete the branch the mutation targeted, or make the shape
  stop discriminating; both were found by re-running, not by reading.
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
  **Record which branch a mutation was applied to**: a whole-file substitution
  over two byte-identical call sites is a different mutation, with a different
  reddened set, from a scoped one (stage 3's M2g). **And record which SPELLING
  it was applied to, not only which branch**: "the records not consumed" and
  "the records neither read nor consumed" redden the same seven tests with 12
  and 46 issues, so a later reader re-running the wording gets a different
  number with no way to tell which reading is the instrument (stage 4's M2f,
  and M2a's 30 vs 47).
- **A harness decision is a mutation site.** Stage 4 lane 3's host box — the
  largest decision in the lane — was pinned by none of the lane's three
  mutations, and the one the verifier took (drop its declared height) both
  reddened eleven scenarios and refuted the published reason for it.
- **A fixture of fixed-size leaves cannot see a container lowering.**
  `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` are all
  no-ops over children that declare no item field, so "this lowers as the
  container lowering" needs a child that gives the container something to do
  (stage 3's M2b and M4b, the same finding one lane apart).
- **Parallel tracks owe tests for the merge**; only the merged suite runs them.
  **A clause both tracks share can be pinned by neither**: dropping the clamp
  from the lowered `Text` alone left all 1548 merged tests green, because the
  engine track pinned it only through `ProposalText` (record §23, XM4).
- **A green mutant may be the correct spelling** (`LR-X`).
- **A window test in a mode that traps pre-flights in a mode that reports.**

## Reference tables (moved to the record)

Consult before changing the behaviour they describe; each is a table of
expected, measured facts:

- **Known divergences** (**69 live**, stable labels; retired labels never
  reused: 2, 3, 4, 5–8, 11, 12, 14, 15, 16, 17, 18, 19, 24, 28, 35, 36, 37,
  39, 40, 45, 48, 53, 55, 59, 64, 69, 74, 83, 85; label 75 never assigned;
  **next label 103**; **drag and drop added 100–102**, none retired). **The current list is `docs/divergences.md`**
  (plan task 15, `CX-G`, `CX-R`): every live row with SwiftUI's answer,
  MetalUI's, its ruling, its pin and its owner — **none has an owner but 82**
  (the human VoiceOver run) — plus the retired list and the documented
  absences. Record §04 is the history (dated sections per task; some rows'
  pin names there are stale, corrected by §04's closeout section). Many rows
  are *pinned wrong on purpose*; a test named for one reddening may be a fix,
  not a bug. **Plan task 15 retired 2, 35, 39, 53, 55 and 85** (72 → 66): 85
  by `CX-F` (an optional `@State` reads its non-`nil` default before its
  first write, SwiftUI's probe O1); 35, 39, 53 and 55 because stage 9's
  lowering already gave SwiftUI's answer and a live pin asserts it; 2 because
  its subject (the CSS engine's flex clause) is deleted. A new divergence
  gets the next label, a row in `docs/divergences.md`, a section in record
  §04 and a pin. The 2026-10-01 text that carried each earlier task's
  amendments, one paragraph per task, moved verbatim to record §67 §2.

- **Declared but inert** APIs (compile and do little or nothing, by design:
  `onInput`'s `-> Bool`, colour glyphs, `locale`/`layoutDirection`/
  `dynamicTypeSize`, `controlSize` beyond `Button`'s chrome and every text's
  default font (divergence 76), `displayScale` (no framework reader),
  `ButtonRole` (binds a key, draws nothing else), `AXNode.actions`/
  `AXActionKind` (deprecated, never read), `AccessibilityTraits.updatesFrequently`
  (published on neither bridge, as on macOS), one axis each of
  `markNativeGridRow`/`markNativeGridCell`'s alignment, a grid mark outside a
  grid, …) — the table is record §05, whose dated sections carry each task's
  adds and deletions; **plan task 15's section (§05, 2026-10-01) is the
  final list**. Deleted, not inert, since stage 10: `Style.aspectRatio`,
  `overflow`, `Style.border`, `Position.relative`; since plan task 15,
  `Box`'s public `style:` parameter (`CX-D`: the initialiser with it is
  `package`; the public `Box(decoration:)` spellings forward to it). Adding
  an unimplementable property: add a row. The per-task paragraphs this
  bullet used to carry moved verbatim to record §67 §3.

- **Human verification**: every look still owed, across record §03 and every
  task, is the one checklist **`docs/verification/human-checks.md`** (plan
  task 15, `CX-M`; group N, drag and drop, added 2026-10-01) — groups A–N, each item with what to run, what to see,
  the right answer and the headless pin. **Status: not run** — an agent
  cannot. The real-window default/preview capture was last taken unlocked on
  2026-09-30 (`capture.sh`, 0 differing against `1b093b8`, record §66 §0);
  the screen was locked again at plan task 15's close. Demo keys (**M**
  modal, **Space** theme, **F**/**Esc** focus, **=**/**-** count, **A**
  animation, **Q** quit); `METALUI_LOOKS_DEMO=1` builds the surfaces
  checks H, I, J and K look at. Nothing in the suite sees paint order,
  portals, scroll direction, presentation, the display link or real hover;
  those are looks. Padded legacy container rule: container modifiers and
  `.flexGrow(1)` before `.padding`; size (a `.frame`), background and corner
  radius after. The per-task paragraphs this bullet used to carry moved
  verbatim to record §67 §4; `docs/verification/voiceover-script.md` is the
  VoiceOver half (group L).

- **Performance** figures (µs/node, warm frame, cold `List`, native work
  counts) — §19 "Performance", record §07. Most are stale since `f1944f8`;
  re-measure before reasoning from them. **`MP-I`'s 100 000-row cold frame
  re-measured 2026-09-23 on this machine: 12.24 s release legacy / 7.55 s
  release proposal, 37.16 s / 24.98 s debug** — the ~17 s figure carried
  elsewhere is stale, and that staleness is not a change stage 4 made. The
  proposal path's cold frame is about a third faster than the legacy one at
  that size: measured, not a goal, and asserted by nothing.
- **CI hazards** — §19 "CI", record §08. Key ones: all **125** guards skip
  under the
  default build system — **macOS CI no longer does: it builds and tests
  with `--build-system native` and `METALUI_REQUIRE_GUARDS=1`, so a skipped
  guard fails** (`CX-J`, `theTypecheckGuardsRanWhereTheyAreRequired`; the
  workflow is owed to CI on push). Locally take guard counts under
  `--build-system native`, and
  grep logs for `FR-J no-argument frame: succeeded=` to know guards ran — a
  guard that ran costs real `swiftc -typecheck` time, ~0.46 s each for the four
  `GridCompileGuards`, which is the only way to tell it from one that returned
  true for free); **retired with stage 7b's removal of
  `FreezeLoopAllocationTests.swift`**: the freeze-loop allocation pin that
  checked only half itself on Apple toolchains
  (`FREEZE-ALLOC: strict per-pass bound NOT CHECKED`) — the surviving
  `malloc_logger` installer is `ModifiedElementTests`' own copy, whose
  hazard (two installers racing under a parallel run) is now moot with only
  one left; `malloc_logger` tests still
  need `--no-parallel`; E24 hard-fails under the root locale; seven
  `AnimationTests` hard-fail without a display device. **Two more, added by
  stage 3 and widened through stage 5, are retired at stage 9** along with
  `AuthorityCoverage` and `ZZAuthorityRollCall.swift` (`LR-FI`): the
  cross-file-order roll-call hazard (`everyParameterisedScenarioRanUnderBothLayoutAuthorities`,
  which depended on Swift Testing's unspecified cross-file order across
  fifteen files) and the `AccessibilityDefaultsTests`-recording-after-`#require`
  ordering hazard against that same registry. Neither registry nor roll call
  exists to be spuriously red any more. Two hazards survive, unrelated to
  either (the second added by PR #30, merged at stage 9's close), and two
  more follow them (stage 10's Windows-only absence and SDL's run-loop stop,
  record §61 §9):
  - A proposal-authority regression that reports an `…unconsumed` field now
    **traps in a `Window` test and truncates the run with no summary line**
    (the first such test is #1251). Read the last lines of the log, not the
    summary. **Stage 5 widens this**: any regression a presentation reports
    by name (`deferred.*`, `position`/`inset`, `…absolute`) traps the same
    way inside `PresentationWindowTests`, which is why every scenario there
    pre-flights under diagnostics with `try #require` on an empty report
    before opening its `Window` — a new presentation window test owes one
    pre-flight (and one per animated end state). **Stage 6b makes this a
    production hazard, not only a test one**: every `Frame`/`Window` built
    with no explicit authority now runs `.proposal` by default, so a
    lowering site that receives a `LoweredItem` nobody consumes traps at
    runtime in the app, not only in a test that opted into diagnostics.
  - **Windows threads have 1 MB stacks** (the main thread and Swift Testing's
    workers; macOS's and Linux's main threads have 8 MB), and a debug builder
    closure reserves a slot for every temporary it holds — the demo's tree
    value is 35 KB, so its builder frames measured 138–248 KB each on macOS
    arm64, and `demoContent()` needed a 1200 KB thread at `b9a5d7f` (stage
    8's `.frame` layers; 896 KB at `85217e3`), overflowing both Windows jobs
    while macOS and Linux passed. Since the fix it needs 528 KB: each section
    is its own function, passed as an argument to a generic composing
    function (the note after `demoContent()`). **A new demo section goes in
    its own function the same way**, not inline in a composing builder. Guard:
    `everyProductionTreeBuildsOnAOneMegabyteThread` (an exit test, all three
    platforms; it builds, it cannot render off the main thread —
    `assumeIsolated`). swift-corelibs Foundation silently ignores a
    `Thread.stackSize` of 64 KB, so a small-stack control there needs 128 KB
    or more. Record §50 §14.
  - **A C enum's `rawValue` is `Int32` on Windows and `UInt32` on Apple.**
    Passing `SOME_C_ENUM.rawValue` straight into a `UInt32`/`MUIUInt` field
    compiles on macOS and Linux and fails the Windows build — twice so far
    (`SDLWindowRendererTests`, PR #32; `AccessKitControlsParityTests`, after
    task 12 part 2). Always convert explicitly (`UInt32(X.rawValue)`,
    `MUIUInt(X.rawValue)`); only Windows CI can see a miss.
  - **Stage 10's closing check is compiled out on Windows.**
    `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
    (`Tests/MetalUICrossPlatformTests/LegacyEngineSymbolTests.swift`) is
    `#if canImport(Darwin) || canImport(Glibc)` — it runs on macOS and Linux,
    where `dlsym` resolves each mangled name against the test process, and
    does not exist on Windows, which has neither C library.
    `root-windows` CI never runs it; its absence there is by design, not a
    skip to investigate. Record §53 §6.2 item 6.
  - **A macOS test process that initialises SDL video can exit 0
    mid-run** (record §61 §9). SDL reads events through
    `nextEventMatchingMask` but never calls `-[NSApplication run]`, the only
    path to AppKit's event-queue signal block (`NSUpdateCycleInitialize`);
    without it HIToolbox's event thread wakes the main thread by queueing a
    `CFRunLoopStop` of the main run loop, and when that reaches Swift
    Testing's **outermost** `CFRunLoopRun` the executor returns and
    `exit(0)`s — the last tests and the `Test run with` line vanish, exit
    status 0. Timing decides whether it shows (`--no-parallel` 3/3 on the
    branch, 0 of 36 parallel runs). `SDLPlatform.init` runs `NSApp.run()` once,
    stopped at once (`SDLPlatform+AppKit.swift`); a new entry point that
    initialises SDL video with windows on macOS owes the same call. Guards:
    `windowServerTrafficNeverStopsTheMainRunLoop` (red 25–35 of 40 without
    the call) and `armMainRunLoopExitCheck()`, an `atexit` that turns such an
    exit into `exit(1)` with a message — **arm it in every new SDL test
    helper that creates an `SDLPlatform`**. macOS CI does not run
    `Backends/SDL`'s tests, so only a local run sees this.
