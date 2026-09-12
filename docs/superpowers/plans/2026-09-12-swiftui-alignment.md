# SwiftUI behavioral-alignment task list

## Goal and boundary

Replace MetalUI's CSS-derived layout model with a native SwiftUI-style layout
model, then make its public composition, layout, state, environment, input and
accessibility behaviour agree with SwiftUI wherever MetalUI exposes an
equivalent concept. This is **behavioural alignment**, not source-compatible
SwiftUI or a replacement for SwiftUI's platform framework.

SwiftUI's parent proposal / child measurement / placement model is the target;
CSS box, flex, grid, cascade and containing-block rules must not remain the
layout authority. The existing engine and WebKit corpus are temporary migration
evidence: retain them while ports are compared, then retire or reframe CSS-only
fixtures once their SwiftUI replacements are proven. Each difference must be
removed or retained as a documented, tested MetalUI divergence.

Every item that claims SwiftUI behaviour needs a small, versioned SwiftUI
probe with a positive control, followed by a MetalUI test whose alternatives
would produce different observations. Do not infer values, defaults, or
modifier placement from names alone.

## Sequenced work

- [x] **1. Publish the replacement contract and CSS-debt inventory.**
  Catalogue every public `Element`, `ElementGroup`, modifier, container,
  interaction and environment API as: SwiftUI-aligned, CSS-derived,
  divergent, missing, or intentionally unsupported. Map every `Style`,
  `Display`, `LayoutTree` and `FlexEngine` concept to its replacement,
  deletion, or compatibility boundary. Give each entry a SwiftUI probe, a
  MetalUI proof, and an owner milestone. Reconcile the divergence table and
  remove CSS concepts from public documentation when they have no SwiftUI
  counterpart (for example, margin). The baseline inventory is
  [`2026-09-12-swiftui-layout-replacement-inventory.md`](../2026-09-12-swiftui-layout-replacement-inventory.md).

- [ ] **2. Build the native layout kernel.**
  Replace CSS `Style` resolution and flex/grid placement with a layout protocol
  that receives a size proposal, measures a child response, caches the result
  for the frame, and places children in a resolved bounds rectangle. Establish
  the tree, invalidation, measurement cache, coordinate-space and pixel-rounding
  contracts before migrating public elements. Keep a temporary adapter only at
  the old engine boundary, never as the new layout authority.

- [ ] **3. Build a typed modifier-composition foundation.**
  Introduce a modifier wrapper representation that can nest without forcing
  callers to expose ever-growing concrete types such as `Box<Box<Box<Text>>>`.
  It must preserve structural identity, `@State`, handler registration,
  layout/prepaint/paint ordering, and stored subtrees. This is the prerequisite
  for converting the legacy direct-mutating size modifiers; plain return-type
  changes already break concrete `Box<T>` boundaries in the demo.

- [ ] **4. Finish frame and sizing semantics.**
  Specify and implement `.frame(width:height:alignment:)`, optional axes,
  min/ideal/max constraints, alignment within an offered proposal, and the
  ordering rules for chained frames. Move `width`, `height`, min/max sizing and
  alignment-facing convenience APIs onto that representation; deprecate APIs
  whose observable meaning cannot match SwiftUI. The additive
  `.frame(width:height:)` API exists; this task makes it the single semantic
  path.

- [ ] **5. Finish outer modifiers and modifier order.**
  Complete the padding migration, then audit background, overlay, border,
  corner/clip shape, opacity, hit testing, focus drawing and content shape.
  Pin whether each wraps, distributes through a `Component`, or affects only
  paint. Test order-sensitive chains such as padding/background/frame/clip.

- [ ] **6. Replace containers with SwiftUI-style algorithms.**
  Audit `Row`, `Column`, `Stack`, `Box`, `Spacer`, `ScrollView`, `List`, and
  `Deferred` against `HStack`, `VStack`, `ZStack`, `Spacer`, `ScrollView`,
  `List`, and overlay/presentation patterns. Port stack, overlay and spacer
  algorithms directly to the new proposal system. Cover proposal propagation,
  explicit versus platform-default spacing, all nine `Alignment` positions,
  frame alignment, and scroll axes. Preserve the existing centred stack
  defaults only where probes confirm them.

- [ ] **7. Port advanced layout, then remove the legacy engine.**
  Implement the proposal-system equivalents of unspecified, ideal, min/max,
  fixed-size, layout priority, compression, expansion, grids and custom
  layouts. Migrate the remaining elements off `FlexEngine`, delete the CSS
  layout paths and dead `Style` fields, and replace browser-fixture goldens with
  SwiftUI probes or deterministic native layout tests. No production layout
  request may pass through the legacy engine after this task.

- [ ] **8. Audit composition and identity.**
  Verify `Group`, conditional content, explicit identity, `Component`, and
  modifier placement against SwiftUI custom-view behaviour. Preserve MetalUI's
  structural identity model where it matches, and close or document the
  currently known state-retention and reused-value aliasing differences.

- [ ] **9. Expand the environment and control-state model.**
  Evolve `Theme` into scoped environment values: enabled state, layout
  direction, locale, dynamic type/scale, control state and platform metrics.
  Add read/write environment modifiers with nearest-ancestor precedence; do
  not recreate a CSS cascade. Resolve the existing `Binding` naming collision
  before introducing SwiftUI-like bindings.

- [ ] **10. Align data-driven controls and scrolling.**
  Define `ForEach`/identified-data semantics, bindings, common controls and
  selection. Rework `List` and `ScrollView` limitations that make ordinary
  SwiftUI layouts blank or state-destructive, while retaining virtualization as
  an internal implementation choice. Specify scroll position, indicators and
  programmatic scrolling.

- [ ] **11. Close text, shape and rendering-facing semantics.**
  Add the overlapping SwiftUI text controls: foreground style, font metrics,
  line limit, truncation, multiline alignment, baseline alignment and dynamic
  type response. Then cover shapes, images, fills/strokes, overlays and
  clipping where MetalUI exposes them. Keep renderer constraints explicit when
  an exact effect is not supportable yet.

- [ ] **12. Align interaction, focus and accessibility.**
  Specify gesture composition, button semantics, disabled behaviour, keyboard
  focus, pointer hit testing and content shapes. Deliver the missing native
  accessibility bridge and validate it with VoiceOver; until then MetalUI
  cannot claim complete SwiftUI-level application behaviour.

- [ ] **13. Complete transaction and animation semantics.**
  Make modifier wrappers participate in transactions at their correct phase,
  then add environment-driven Reduce Motion and document the supported
  transition surface. Retain the existing distinction between layout and paint
  animation, and drive all animation tests by timestamps rather than sleeps.

- [ ] **14. Resolve platform completeness.**
  MetalUI is macOS-only today. If “complete SwiftUI alignment” includes
  SwiftUI's Apple-platform scope, implement and verify iOS/iPadOS platform
  conformers, touch input, safe areas, lifecycle and native accessibility.
  Otherwise record macOS-only as an explicit product boundary rather than an
  implied parity claim.

- [ ] **15. Run the replacement closeout.**
  Re-run the full inventory; require that no public behaviour is unclassified,
  each supported overlap has a probe and discriminating MetalUI test, and each
  remaining difference is documented. Update migration guidance and public
  API documentation, run the full suite and relevant human visual checks, and
  ensure the retired CSS engine has no production caller, and remove or
  reclassify all browser goldens as migration-only historical evidence.

## Current starting point

- Structural identity, component flattening/distribution, centred `Row` and
  `Column` defaults, `Stack` alignment, and theme propagation already contain
  measured SwiftUI-inspired work; they still belong in the inventory audit.
- `.frame(width:height:)` has been added as an additive wrapper API.
- Ordinary element padding now wraps its content; `Component` padding remains
  a separately measured distribution case. Task 5 decides the complete
  modifier matrix.
- Direct `width`/`height` still mutate style. Do not convert them before task
  3 establishes a composition representation that works across stored generic
  element trees.

## Definition of done

The project may say it is SwiftUI-aligned only for its declared platform and
API scope when the closeout has no unclassified public behaviours, every claim
has measured evidence and a regression proof, each unsupported or intentional
divergence is prominent in the public documentation, and no production layout
request reaches the CSS-derived engine.
