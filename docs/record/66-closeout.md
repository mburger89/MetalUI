# 66 — Replacement closeout (plan task 15)

Branch `feat/closeout` from `1b093b8` (master: plan task 13 merged, task 14's
record). Spec `docs/superpowers/specs/2026-09-30-closeout-design.md`; rulings
`CX-A`…`CX-P` in `docs/superpowers/2026-09-30-closeout-decisions.md` (next
unused `CX-Q`); probe `docs/probes/swiftui-closeout.swift` (lane 1).

**Status: DESIGN committed and critiqued (`CX-P`); lanes 1–3 and the Record phase to run.**

**Critic round (2026-09-30).** Probe group O committed and run twice
(identical): O0 2, O1n nil, **O1 2**, O2 nil — `CX-F`'s SwiftUI claim
measured. `swiftui-border-clip-paint.swift` re-run: K0, C3, D1
byte-identical. Corrections in `CX-P`: test numbering; legacy C3/D1 pins
1.3L/1.4L (row 47 read "unpinned"); divergence 52's stale pin name; guard
count 121 (G2 calls `canTypecheck`); `Box(decoration:)` forwards to the
package init; three "task 15" sentences the sweep table missed; the
checklist moved to lane 1. Expected counts after lane 1: **1971 / 0 / 121**.

## §0 Design session (2026-09-30)

- **Census** (`CX-A`): `docs/probes/closeout-public-api.sh` (written by an
  interrupted predecessor session and found uncommitted in the worktree;
  re-run here, byte-identical to its TSV) — **1871** public declarations in
  fifteen targets, 0 unattributed owners. Kinds: 659 `func`, 439 `var`, 229
  `struct`, 220 `let`, 183 `init`, 68 `enum`, 30 `typealias`, 19 `protocol`,
  18 `class`, 5 `subscript`, 1 `prefix` operator.
- **Doc comments** (`CX-K`): 888 census rows have no `///` above them; 592
  once protocol-requirement witnesses are exempted (MetalUI 302, MetalUICore
  68, MetalUIPlatform 46, MetalUILayout 33, MetalUIScene 30, MetalUIRender
  23, MetalUITextSystem 22, MetalUIText 21, MetalUIPortableText 15,
  MetalUIHarfBuzz 10, MetalUIDemoContent 8, MetalUIFreeType 7,
  MetalUISystemFonts 4, MetalUIAppKit 3).
- **GZ re-run** (`CX-H`): `xcrun swiftc -O docs/probes/swiftui-grid.swift -o
  grid; ./grid` → stdout sha256
  `5d2030386ae93bba614ff68f203e8d56a1bf284bad9912232f261088172f61ba`, the
  committed default run's recorded hash, 435 lines (GZ0 212/300, GZ1
  1000/1000, GZ2 988/1000, GZ3 469/500, GZ4 441/500, GZ5 482/500, GZ6
  376/500, GZ7 231/300, GZ8 662/1000, GZ9–GZ12 300/300); `./grid
  divergences` → the committed 65 cases line for line (the committed file
  adds only its `//` header; the run adds BEGIN/END framing lines). Exit 0
  both. Baseline holds.
- **Lock probe** 23:41 PDT: no `CGSSessionScreenIsLocked` line,
  `displayAsleep main: 0`, `displayActive main: 1`. **Real-window capture
  taken**: `capture.sh <scratch> 1b093b8` (a-vs-b 0 both states; control
  958986), then `capture.sh <scratch> 6c961e3 1b093b8`: every a-vs-b 0,
  **`6c961e3 -> 1b093b8` default 0, preview 0 differing**, control
  default-vs-preview at `1b093b8` 958986 bbox (0,15)-(1839,1175). The last
  unlocked reading was `6c961e3` (task 12 part 2, lane 1); tasks 12's later
  lanes, 13 and 14 moved no pixel of the real default and preview windows.
- **Retired engine and goldens** (`CX-N`): to be re-run at the Record phase.

## §1 Inventory (`CX-A`) — family table

Classes: **A** SwiftUI-aligned (probe arm + discriminating test), **D**
documented divergence (record §04 label), **M** MetalUI-only by design
(ruling), **X** deprecated (replacement), **R** documented absence (not a
census row). "Div." lists labels a family carries beside its class. The
design session drew the families and proposed each class; **lane 2 resolves
every evidence cell** (test names by grep, probe arms by file), splits any
family whose members differ, writes `closeout-inventory-map.tsv`, and makes
`closeout-inventory-check.sh` print nothing.

### §1.1 `MetalUI` — app, phases, element protocols

| family (files) | class | behaviour classified | evidence (to resolve) |
|---|---|---|---|
| `App`, `AppError`, `Window`, `Frame`, `renderFrame` (`App.swift`, `Window.swift`, `Frame.swift`, `RenderFrame.swift`) | M | the host: one app, windows driven by a display link, headless render (`DC-A`) — SwiftUI's `App`/`Scene` lifecycle is not offered | `PB-A`, `RS-A`, `DC-A`, `XP-B` |
| `Element`, `ElementGroup`, `StyledElement`, `ProposalElement`, `ProposalElementGroup`, `ElementObject` | M | the three-phase element protocols (gpui's `requestLayout`/`prepaint`/`paint`) in place of `View` | design spec §2; `SA-A` |
| `LayoutPass`, `PrepaintPass`, `PaintPass` (`Passes.swift`) | M | phase objects; `isHovered`/`isActive`/`isFocused` paint-only (guarded) | `PhaseSeparationTests` |
| `ElementBuilder`, `EmptyGroup`, `Pair`, `OptionalGroup`, `EitherGroup`, `ArrayGroup`, `SingleElementLayout` | A | `@ViewBuilder`'s shapes; one structural slot per `if`/`for` (`ID-B`), reset on return (`ID-C`), `if`/`else`/`switch` in every container (`ID-D`) | probe `swiftui-composition-identity.swift` V1, V5, V7–V9; tests `C2.*` |
| `AnyElement`, `AnyElementBox` | A | `AnyView`: `@State`/`@Environment` bind inside (`ID-E`) | `O1.*` |
| `ElementID`, `GlobalElementID`, `PathComponent`, `IdentifiedGroup`, `IdentifiedGroupLayout`, `.id(_:)` | A, div. 72 | explicit identity, a departed name starts fresh (`ID-G`, `ID-R`) | probe X9–X11; `anIDThatReturnsToAnEarlierNameStartsFresh` |
| `Component`, `StyledComponent`, `ComponentLayout` | M, div. 56 | layout-transparent, identity-opaque composition; `.width`/`.height` frame each member (`LR-BG`) | `OM-D`, `LR-BG`, `ID-K` |
| `Deferred` | M, div. 9, 10, 46 | a portal hoisting to the root layer; a presentation root (stage 5) | `LR-CH`…`LR-CS`; `PresentationWindowTests` |
| `Handlers`, `HitboxID`, `KeyHandler`, `Focus` (type) | M | handler storage, hitbox ids | `OM-AI`, `IX-N` |

### §1.2 `MetalUI` — state, binding, environment

| family | class | behaviour | evidence |
|---|---|---|---|
| `State` | A, div. 71 (85 retires, `CX-F`) | `@State` per occurrence, dispatch-resolved (`ID-F`) | probe O0–O2 (`swiftui-closeout.swift`); 1.1, 1.2 |
| `Binding` | A, div. 78 | SwiftUI's surface, `@MainActor` | `DD-D`; `BindingCompileGuards` |
| `Environment`, `EnvironmentValues`, `EnvironmentKey`, `EnvironmentScope`, `EnvironmentScopeLayout`, `DynamicTypeSize`, `ControlSize` | A, div. 76, 77 | nearest writer wins; `displayScale`/`controlActiveState`/`controlSize`/`accessibilityReduceMotion` | `EV-`, `EV-AA`…`EV-AF`, `AN-AD` |
| `Theme`, `ColorToken` | M | scoped, paint-only theme tokens (`EV-G`) | `EV-G` |
| `FocusState`, `FocusState.Binding` | A, div. 94 | `@FocusState`/`.focused` (`IX-J`) | probe `swiftui-interaction.swift`; `FocusStateCompileGuards` |

### §1.3 `MetalUI` — SwiftUI-vocabulary layout (the proposal path)

| family | class | behaviour | evidence |
|---|---|---|---|
| `HStack`, `VStack`, `ZStack`, `Spacer`, `HorizontalAlignment`, `VerticalAlignment` | A, div. 51, 58 | SwiftUI's stack algorithms (`CN-B`…`CN-I`), baselines (`TE-K`) | probe `swiftui-stack-algorithms.swift`; `CN-` tests |
| `ProposalFrame`, `Padding`, `Background`, `FixedSize`, `Rectangle`, `Color` | A | frame/padding/background/fixedSize leaves and wrappers | `FR-A`, `FR-M`, `SA-N` |
| `LayoutModifier`, `ModifiedContent` (proposal arm), `ModifierLayerKind` | A | `ModifiedContent<Content, Modifier>` (`LR-FV`) | `UnifiedModifiedContentCompileGuards` |
| `OverlayModifier`, `BackgroundModifier` | A, div. 57, 73 | `.overlay`/`.background(alignment:content:)` (`MC-P`, `ID-J`) | probe `swiftui-overlay-primary-shape.swift` |
| `ProposalScrollView`, `ScrollViewReader`, `ScrollViewProxy`, `UnitPoint`, `ScrollIndicatorVisibility`, `ScrollAxis` | A, div. 54 | scrolling, `scrollTo(_:anchor:)`, indicators (`DD-G`, `DD-H`) | probe `swiftui-data-and-scrolling.swift`, `swiftui-scrollviewreader-scope.swift` |
| `ProposalText` | A, div. 86–89 | text in the proposal path (`TE-`) | probe `swiftui-text-semantics.swift` |
| `ProposalLayoutContainer` (+ `ProposalLayout` in `MetalUILayout`) | A | SwiftUI's `Layout` without a cache (`SA-A`…`SA-F`) | `ProposalLayoutCompileGuards` |
| `Grid`, `GridRow`, `GridRowLayout`, `GridCellModifier`, `GridCellAttribute` | A, div. 60–63, 65–68, 70 (lane 2 confirms the exact set) | SwiftUI's `Grid` (`GR-`) | probe `swiftui-grid.swift` (GZ re-run §0) |
| `ForEach`, `ForEachBindingSlot` | A, div. 79 | `ForEach` identity, loop resets (`DD-B`, `DD-C`) | `ForEachCompileGuards` |
| `TransactionScope`, `TransactionScopeLayout`, `TransitionGroup`, `TransitionGroupLayout` | A | `.transaction`/`.animation(_:value:)`/`.transition` scopes | `AN-Y`, `AN-AE` |
| `Native…` typealiases (`NativeRow`, `NativeColumn`, `NativeOverlay`, `NativeFrame`, `NativePadding`, `NativeBackground`, `NativeFixedSize`, `NativeSpacer`, `NativeRectangle`, `NativeColorFill`, `NativeLayoutModifier`, `NativeModifiedContent`, `NativeOverlayModifier`, `NativeTappable`) | X | → the un-prefixed names | `@available` messages |

### §1.4 `MetalUI` — the legacy (CSS-derived) vocabulary

| family | class | behaviour | evidence |
|---|---|---|---|
| `Box`, `Row`, `Column`, `Stack`, `ScrollView`, `ScrollState`, `ScrollContext`, `Alignment`, `Decoration`, `BorderStyle` | M, div. 52, 53, 54, 55 | legacy containers keep their CSS algorithms, lowered onto the kernel (`CN-A`, `CN-P`, stage 9) | `CN-A`, `LR-FC` |
| `Style`, `Position`, `FlexDirection`, `AlignItems`, `AlignSelf`, `JustifyContent` | M | opaque outside the package (`LR-FM`); `Box(style:)` narrowed (`CX-D`) | `StyleSurfaceCompileGuards`; G1 |
| `List` | M, div. 13, 32, 84 | virtualized, data-driven, uniform rows (`DD-AB`) | `LR-BQ`, `DD-F`, `DD-Z` |
| `ModifierLayer`, `ModifiedElement` (typealias) | M | the legacy arm of `ModifiedContent` (`CX-C` item 3) | `LR-FV` |
| `StyledElement` modifier extension (`Box.swift`) — **lane 2 splits per modifier**: `.padding` A (`OM-D`); legacy `.frame` A, div. 35, 39 (`FR-C`); `.background`/`.border`/`.cornerRadius` M, div. 47, 49; `.opacity` A, div. 46; `.clipped`/`clipShape` A, div. 91, 92; `.allowsHitTesting` A, div. 44; `.contentShape` A, div. 41–43, 50; `.focusBorder` M; `.hidden` A; `flexGrow`/`flexShrink`/`alignSelf`/`margin`/`gap`/`alignItems`/`justifyContent` M (CSS item/container fields, `LR-AB`); `onClick` M, div. 27; `onKey`/`focusable`/`keyContext` M, div. 94; the eight sizing modifiers and `width/height(fraction:)`, `…(percent:)`, `flexBasis(fraction:)` (`CX-C`), `flexBasis(percent:)` X → `.frame` | per row | per row |

### §1.5 `MetalUI` — controls, text, shapes, images

| family | class | behaviour | evidence |
|---|---|---|---|
| `Button`, `ButtonRole`, `ButtonStyle` | A, div. 76, 80; `ButtonRole` inert (§05) | `Button`, roles, styles, pressed look (`DD-R`, `IX-E`, `IX-F`) | probe `swiftui-controls-and-selection.swift`, `swiftui-interaction.swift` |
| `Toggle`, `Slider`, `Stepper`, `Picker`, `PickerStyle`, `TaggedElement` | A, div. 80, 81, 82 | the controls on `Binding` (`DD-Q`…`DD-AA`) | probe `swiftui-controls-and-selection.swift` |
| `Text`, `Font`, `Font.Weight`, `Font.Design`, `Font.TextStyle`, `TextAlignment`, `Text.TruncationMode`, text modifiers (`TextModifiers.swift`) | A, div. 51, 86–89 | `TE-A`…`TE-AB` | probe `swiftui-text-semantics.swift` and its four companions |
| `TextField`, `TextEditor` | A (the `Binding` initialisers, `DD-E`), M (controlled initialisers, undo, paging — `TI-`) | text input | `TI-A`…`TI-J` |
| `Shape`, `ShapeGeometry`, `ShapeLayout`, `RoundedRectangle`, `Circle`, `Capsule`, `Ellipse`, `RoundedCornerStyle`, `ShapeView`, clip modifiers (`ClipShape.swift`) | A, div. 90, 91, 92 | `TE-AC`…`TE-AQ` | probe `swiftui-shapes-and-rendering.swift` |
| `Image`, `Image.Interpolation`, `ContentMode` | A, div. 93 | `TE-AL`, `TE-AM` | same probe |
| `ImageBitmap` | M | the portable stand-in for `CGImage` (`TE-AL`) | `TE-AL` |

### §1.6 `MetalUI` — input, gestures, accessibility, animation

| family | class | behaviour | evidence |
|---|---|---|---|
| `Gesture`, `TapGesture`, `LongPressGesture`, `DragGesture`, `ExclusiveGesture`, `SimultaneousGesture`, `GestureModifier`, `OnTapModifier`, `_GestureRecognizers` | A, div. 27 | one arena per press (`IX-B`…`IX-D`, `IX-Q`) | probe `swiftui-interaction.swift`, `swiftui-gesture-presentation-arena.swift` |
| `KeyboardShortcut`, `KeyEquivalent`, `EventModifiers` | A | `.keyboardShortcut` (`IX-F`) | `ButtonCompileGuards` |
| `Keymap`, `KeyBinding`, `Keystroke`, `KeymapBuilder`, `KeyContext`, `ContextPredicate`, `Action`, `ActionHandler` | M | gpui's keymap and actions | design spec |
| `AccessibilityModifier`, `AccessibilityTraits`, `AccessibilityChildBehavior`, `AccessibilityAdjustment`, `AccessibilityAdjustmentDirection`, accessibility modifiers | A, div. 32, 33, 82, 95 | `IX-U`…`IX-AJ` | probe `swiftui-accessibility-part2.swift` |
| `AXNode`, `AXRole`, `AXTrait` | M | the neutral accessibility record | `AB-` |
| `AXActionKind`, `AXNode.actions` | X | → `accessibilityAction(_:)`/`accessibilityAdjustableAction(_:)` | `IX-Y` item 4 |
| `Animation`, `Transaction`, `AnyTransition`, `Edge` | A, div. 96–99 | `AN-X`…`AN-AK` | probe `swiftui-transactions-animation.swift` |

### §1.7 Infrastructure targets (all M unless noted)

| target / families | class | ruling |
|---|---|---|
| `MetalUICore`: `Geometry` (`Point`, `Size`, `Rect`, `Edges`, …), `Units` (`Pixels`, `Length`, `px`, `rem`), `Color`, `Appearance`, `LayoutDirection` (inert, §05), `ControlActiveState` (A, `EV-AB`) | M | `C-`, `F-`, `EV-K` |
| `MetalUILayout`: `LayoutTree` and its registrars, `MeasureFunction`, `NativeGrid`, `ProposalSpacing`, `Rounding` (div. 77); `ProposedSize` (A, `ProposedViewSize`), `ProposalLayout` (A, §1.3) | M / A | `SA-`, `GR-C` |
| `MetalUIPlatform`: `Platform`, `PlatformWindow`, `InputEvent`, `AccessibilityTree` | M | `RS-A`, `AB-R`, `EV-AB`, `AN-AD` |
| `MetalUIRender`: `Renderer`, `MetalWindowRenderer`, `RenderSurface`, `ShaderLibrary` | M | `RS-B` |
| `MetalUIScene`: `Scene`, `Atlas`, `FontKey`, `GlyphImage`, `ImageTexture` | M | `PS-A`…`PS-G`, `TE-AF` |
| `MetalUIText`, `MetalUITextSystem` | M | `TS-A`…`TS-D`, `TX-` |
| `MetalUIFreeType`, `MetalUIHarfBuzz`, `MetalUIPortableText`, `MetalUISystemFonts` | M | `FT-`, `SH-`, `PT-`, `LB-`, `FN-`, `FB-`, `BD-`, `SF-` |
| `MetalUIAppKit`, `MetalUIPrimitives` | M | `RS-C` |
| `MetalUIDemoContent` | M | `LR-S` (the demo tree, importable by tests) |

### §1.8 Documented absences (R rows; owner none unless stated)

Increase Contrast and the other system accessibility settings; a readable
`colorScheme` (`TE-AO` item 1); an animated `scrollTo`/scroll offset;
two-axis scrolling (`CN-M`); `scrollPosition(id:)` (`DD-AB`);
`LazyVGrid`/`LazyHGrid`/`GridItem` (`GR-L`); open `ButtonStyle`/
`PrimitiveButtonStyle`, `.borderedProminent`, `.link`, `.toggleStyle`,
`.pickerStyle(.menu)` (`IX-E`, `IX-M`); `sequenced`, `@GestureState`,
`GestureMask` (`IX-B`); `Path`, gradients, `StrokeStyle`, SF Symbols, colour
glyphs (shapes spec §9, record §05); `matchedGeometryEffect`,
`contentTransition`, custom transitions, `.blurReplace` (`AN-AE`); SwiftUI's
`App`/`Scene` lifecycle and every non-desktop platform (`PB-A`).

## §2 Divergences re-read (`CX-G`) — lane 2

(Per-row table: label, fact, live pin (grep-resolved), probe arm, verdict
keep/retire/narrow, owner. Candidates named by `LR-GG` item 5: 35, 53, 55.)

## §3 Items addressed to "plan task 15", disposed (`CX-I`)

Collected by `grep -rn -i -E "task 15|task-15|\(closeout\)" docs/superpowers
docs/record Sources Tests docs/verification` (excluding record §19), 101
hits at `1b093b8`:

| item | source | disposition |
|---|---|---|
| divergence 52 (`Row`/`Column` gap) | `LR-ER` item 3, `LR-EY` | kept, owner none (`CX-E`) |
| the eight deprecated sizing modifiers, `fraction:`/`percent:` | `LR-FN` item 5 | kept deprecated (`CX-C` item 1) |
| `flexBasis(fraction:)` | (found by this design) | deprecated (`CX-C` item 2) |
| `Box`'s inert public `style:` | `LR-FR` F5 | narrowed to `package` (`CX-D`) |
| the `ModifiedElement` typealias | stage 11 spec §10 | kept, undeprecated (`CX-C` item 3) |
| `AXNode.actions` "until task 15 removes the field" | `IX-Y` item 4 | kept deprecated (`CX-C` item 1) |
| divergence 85 (optional `@State`) | `DD-AI` | fixed, retires (`CX-F`) |
| divergence 35 (and 53, 55) counting question | `LR-GG` item 5 | `CX-G` criterion, lane 2 |
| divergences 61, 62, the GZ re-run | `GR-AA`, `GR-N` | baseline holds, kept owner none (`CX-H`) |
| a grid on screen | `GR-N`, `GR-AE` | human checklist (`CX-M`) |
| per-entry memory harness, settled-store allocation count | `AN-AJ`, record §64 §11 | gated measurement 1.6 (`CX-I` item 1) |
| Increase Contrast, system accessibility settings | `AN-AF`, record §64 §11 | R row (`CX-I` item 3) |
| animated `scrollTo` | `AN-AF` | R row |
| guards only under `--build-system native` | `AN-AF` | fixed (`CX-J`) |
| `switch` transitions unpinned | record §64 §14 | probe SW1, test 1.5 (`CX-I` item 2) |
| two-axis scrolling, divergence 54 | `DD-AB` item 5 | R row / D row kept |
| `colorScheme` | `TE-AO` item 1 | R row |
| the inventory catching missed items | `IX-AD`, `TE-A` cost paragraphs | §1 and the check (`CX-A`) |
| elliptical corners, `UnevenRoundedRectangle` | shapes spec §9 table | R row (`CX-I` item 3, `CX-P` item 6) |
| `ModifiedElement`'s "fate is plan task 15's" doc sentence | `ModifiedContent.swift` | `CX-C` item 3; lane 3 re-spells |
| divergences 61/62 "Owner: plan task 15's closeout" doc comment | `NativeGridTests.swift` | `CX-H`; lane 1 re-spells |
| `flexBasis(percent:)`'s `renamed:` to a now-deprecated name | `Box.swift` | `message:` instead (`CX-P` item 7) |

Lane 2 re-runs the grep at its tip and adds any hit this table does not
cover.

## §4 Lane 1 — code

(To be written by lane 1.)

## §5 Tasks 4 and 5, clause by clause (`CX-B`) — lane 2

(To be written by lane 2, every citation resolved.)

## §6 Lane 3 — doc comments and the human checklist

(To be written by lane 3.)

## §7 Record phase close

(To be written.)
