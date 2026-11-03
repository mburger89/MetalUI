## Declared but inert — the current list

Re-derived 2026-11-02 from the source at `e92c1751` (record 196; rulings `RD-A`..`RD-F`,
`docs/superpowers/2026-11-02-record-05-rederive-decisions.md`). The earlier text of this
file, with its dated sections, is frozen verbatim in record 196 and is history, not a list.

**Why the list exists.** The single most likely way to write a bug in this repo is to use an
API that exists, compiles, and does nothing. A modifier for an inert property is worse than
none, because from outside it is indistinguishable from an implemented one; silence at a
declaration reads as "implemented". So an inert declaration gets a row here, and the task
that makes it live deletes the row in the same change.

**What a row is (`RD-A`).** A declaration the compiler accepts that an author can write or
read in expectation that the framework acts on it, and that, in the context named in the
`inert where` column, is stored and has no production reader that changes layout, paint,
input, accessibility or platform output. Not production readers: tests, the demo, the
retained verify snapshots, and equality, diff or fingerprint code. A declaration that works
in some contexts is a row only for the contexts where it does nothing. Not rows: a function
that does what it says (no caller is dead code, not inertness), a deprecated declaration
(its warning is the non-silence), a value the framework produces for an author's code to
read (events, metrics, queries), and a component of a value with no meaning in its context.

**Against `docs/divergences.md` (`RD-B`).** Where SwiftUI's built-ins measurably react and
MetalUI does not, the row carries that divergence label and sits in both lists: this file
indexes the inertness, the divergence compares with SwiftUI. Where SwiftUI does not react,
or it was not measured, the divergence column is `none`. The `SwiftUI (macOS) does` column
is carried from the cited probes and rulings, not re-measured by the re-derivation.

**Keys (`RD-C`).** One public row per census key `(target, owner, name)`; overloads share it,
and an overload set spanning two inventory families names one of them. The census is
`zsh docs/probes/closeout-public-api.sh`; it lists `public` and `open` declarations only,
so a protocol requirement, an internal declaration or a `package` one goes in the internal
table, keyed by file and an ERE of its declaration line.

**Checking (`RD-E`).** `zsh docs/probes/record-05-check.sh` prints nothing when every public
row names a live census declaration in the family the inventory map gives it, every family
with a row carries `record §05` in its behaviour column (and no other does), every pin
exists, every divergence label is live and every ruling id occurs in `docs/superpowers/`.
It cannot read meaning: whether a declaration is *inert* was decided by a reader grep in
record 196's ledger, and a new row owes one.

**Editing (`RD-D`).** This file gets no new dated sections. A milestone that adds, narrows or
deletes an inert declaration edits the table in place, says so in its own record, adds or
removes `record §05` on the inventory family, and runs the check.

### Public rows

Cells hold no `|`. `pin` is a test function name or `unpinned`; `divergence` is live labels
or `none`.

<!-- record-05:public:begin -->
| target | owner | name | kind | family | inert where | MetalUI does | SwiftUI (macOS) does | divergence | pin | ruling |
|---|---|---|---|---|---|---|---|---|---|---|
| `MetalUI` | `EnvironmentValues` | `locale` | var | environment-locale | every view | stamped from the host locale and scoped; no formatter or tokenizer reads it | same on macOS for built-in Text | none | aLocaleChangesNoTextMeasurementUnderTheProposalAuthority | EV-I EV-Y |
| `MetalUI` | `EnvironmentValues` | `dynamicTypeSize` | var | environment-dynamic-type | every view | carried and scoped; no text style has a size column to scale | same on macOS | none | dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority | EV-I TE-E |
| `MetalUI` | `ElementGroup` | `dynamicTypeSize` | func | environment-dynamic-type | every view | writes the environment key above and nothing else reads it | same on macOS | none | dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority | EV-I TE-E |
| `MetalUI` | `EnvironmentValues` | `displayScale` | var | environment-control | everything: drawing scales by the frame scale factor, layout rounds to whole points | writable and re-stamped each frame, for authors to read | SwiftUI drawing also ignores a written value | none | aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses | EV-AA EV-K |
| `MetalUI` | `EnvironmentValues` | `pixelLength` | var | environment-control | everything: computed from displayScale and read only by authors | one over displayScale | same function of the scale | none | aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses | EV-AA EV-K |
| `MetalUI` | `EnvironmentValues` | `controlSize` | var | environment-control | Toggle switch and checkbox, Picker, Slider, Stepper, ColorPicker, Menu and TextEditor chrome | read by every default font, Button chrome, the bordered TextField inset, a button-style Toggle and ProgressView | resizes every control chrome | 76 | controlSizeReachesTheDefaultFontButNoControlsChrome | EV-AC TE-F MD-V |
| `MetalUI` | `ElementGroup` | `controlSize` | func | environment-control | the same controls as the key | writes the key and nothing else | as the key | 76 | controlSizeReachesTheDefaultFontButNoControlsChrome | EV-AC |
| `MetalUI` | `EnvironmentValues` | `colorSchemeContrast` | var | accessibility-display | every built-in view | stamped by the window and read by authors only | built-in colours and several controls react | 1076 | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-B |
| `MetalUI` | `EnvironmentValues` | `accessibilityDifferentiateWithoutColor` | var | accessibility-display | every built-in view | stamped by the window and read by authors only | no built-in control changed (probe D1) | none | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `accessibilityInvertColors` | var | accessibility-display | every built-in view | stamped by the window and read by authors only | no built-in control changed (probe I1) | none | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `accessibilityShowBorders` | var | accessibility-display | every built-in view | stamped by the window and read by authors only | bordered Button and checkbox Toggle react (probe B1) | 1078 | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `accessibilityShowButtonShapes` | var | accessibility-display | every built-in view | get-only alias of accessibilityShowBorders | as accessibilityShowBorders | 1078 | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `accessibilityDimFlashingLights` | var | accessibility-display | every built-in view | stamped by the window; MetalUI plays no video | unmeasured: nothing to dim | none | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `accessibilityPlayAnimatedImages` | var | accessibility-display | every built-in view | stamped by the window; MetalUI decodes no animated image | unmeasured: nothing to animate | none | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-D |
| `MetalUI` | `EnvironmentValues` | `legibilityWeight` | var | accessibility-display | Text and every built-in view | writable and scoped; Text does not widen | Text widens under bold (probe L1) | 1079 | noBuiltInControlReactsToAccessibilityDisplaySettings | AD-J |
| `MetalUI` | `-` | `ButtonRole` | struct | button | a plain Button and the built-in button styles | binds no key and changes nothing drawn; an alert action reads cancel and destructive | a role binds no key either (probes B4c B4d) | none | aButtonRoleBindsNoKeyAndChangesNothingDrawn | IX-E |
| `MetalUI` | `AccessibilityTraits` | `updatesFrequently` | let | accessibility-modifiers | both accessibility bridges | sets a bit that neither bridge publishes | invisible on macOS too (probe T10) | none | unpinned | IX-W |
| `MetalUI` | `AXNode` | `children` | var | axnode | every node: emitAXNode always passes an empty list | always empty in production; the bridge derives structure from the registry | not applicable | none | unpinned | TB-W TB-M |
| `MetalUI` | `-` | `GridRow` | struct | grid | outside a Grid | its alignment mark is never read; the row is simply its cells | same (probes GG1 GG2) | none | aGridRowOutsideAGridIsItsCells | GR-I GR-J |
| `MetalUI` | `ProposalElementGroup` | `gridCellColumns` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-F GR-I |
| `MetalUI` | `ProposalElementGroup` | `gridCellAnchor` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-G |
| `MetalUI` | `ProposalElementGroup` | `gridColumnAlignment` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-G |
| `MetalUI` | `ProposalElementGroup` | `gridCellUnsizedAxes` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-H |
| `MetalUI` | `ElementGroup` | `gridCellColumns` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-F GR-I |
| `MetalUI` | `ElementGroup` | `gridCellAnchor` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-G |
| `MetalUI` | `ElementGroup` | `gridColumnAlignment` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-G |
| `MetalUI` | `ElementGroup` | `gridCellUnsizedAxes` | func | grid | outside a Grid | the mark is carried and never read | same | none | unpinned | GR-I GR-H |
| `MetalUI` | `LayoutPass` | `markNativeGridRow` | func | kernel-registrars | a node outside a grid; and the horizontal factor of alignment: anywhere | only the vertical factor is read | not applicable: GridRow takes a vertical alignment | none | unpinned | GR-G GR-I |
| `MetalUI` | `LayoutPass` | `markNativeGridCell` | func | kernel-registrars | a node outside a grid; and the vertical factor of columnAlignment: anywhere | only the horizontal factor is read | not applicable: the modifier takes a horizontal alignment | none | unpinned | GR-G GR-I |
| `MetalUILayout` | `LayoutTree` | `markNativeGridRow` | func | layout-kernel | a node outside a grid; and the horizontal factor of alignment: anywhere | only the vertical factor is read | not applicable: GridRow takes a vertical alignment | none | unpinned | GR-G GR-I |
| `MetalUILayout` | `LayoutTree` | `markNativeGridCell` | func | layout-kernel | a node outside a grid; and the vertical factor of columnAlignment: anywhere | only the horizontal factor is read | not applicable: the modifier takes a horizontal alignment | none | unpinned | GR-G GR-I |
| `MetalUI` | `StyledElement` | `alignSelf` | func | css-item-fields | a child of a Stack (the legacy stack container) | written to the child style; the stack lowering never reads it | not applicable: MetalUI-only vocabulary | none | aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields | LR-AD |
| `MetalUI` | `StyledElement` | `flexGrow` | func | css-item-fields | a child of a Stack (the legacy stack container) | written to the child style; the stack lowering never reads it | not applicable: MetalUI-only vocabulary | none | aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields | LR-AD |
| `MetalUI` | `StyledElement` | `flexShrink` | func | css-item-fields | a child of a Stack (the legacy stack container) | written to the child style; the stack lowering never reads it | not applicable: MetalUI-only vocabulary | none | aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields | LR-AD |
| `MetalUI` | `StyledElement` | `flexBasis` | func | css-item-fields | a child of a Stack (the legacy stack container) | written to the child style; the stack lowering never reads it | not applicable: MetalUI-only vocabulary | none | aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields | LR-AD |
| `MetalUI` | `Element` | `tag` | func | picker | outside a Picker or toolbar picker | transparent: the tag is stored and read by nothing | a tag outside a Picker selects nothing | none | aTagOutsideAPickerChangesNothing | DD-V |
| `MetalUI` | `StyledElement` | `contentShape` | func | content-shape | inset: with no onClick on its own layer, and written before the layer that carries the click | the inset is never read | the inset is honoured (probes S1 S2) | 44 50 | aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt | OM-AB |
| `MetalUI` | `ElementGroup` | `disabled` | func | environment | a ScrollView: its scroll region bypasses the gate | the wheel still scrolls a disabled ScrollView | unmeasured | none | aDisabledScrollViewStillScrollsOnTheWheel | EV-F |
| `MetalUI` | `AttributeScopes.MetalUIAttributes` | `foundation` | let | attributed-text | the link attribute of a run | styled in the accent colour; no click, key or accessibility link | a link run opens its URL | 150 | aLinkRegistersNothingAPlainTextDoesNot | RT-K |
| `MetalUI` | `ElementGroup` | `glassEffectID` | func | glass-id-transition | everywhere: the id is carried and read by nothing | no morph between shapes of one id | glass effects sharing an id morph | 828 | unpinned | LG-K |
| `MetalUI` | `Glass` | `interactive` | func | glass | content that is not a control | a bare interactive glass registers no hitbox | SwiftUI answers a press on any glass view | 827 | aBareInteractiveGlassRegistersNoHitbox | LG-J |
| `MetalUI` | `ElementGroup` | `confirmationDialog` | func | alerts | the titleVisibility: parameter | accepted and never hides the title | NSAlert shows the title in every case (probes C1 to C8) | none | titleVisibilityIsAcceptedAndNeverHidesTheTitle | SV-AO |
| `MetalUI` | `PointerStyle` | `image` | func | image-cursor | resizable(), interpolation(_:) and an accessibility label on the Image | the cursor is the bitmap at its own size | same (probe I5) | none | anImageIgnoresResizableAndInterpolation | IC-B |
| `MetalUI` | `Binding` | `transaction` | var | binding | a Binding made from get and set closures | the transaction is carried and never applied | same (probe T11) | none | aClosureBindingIgnoresItsTransaction | AN-Z |
| `MetalUI` | `ElementGroup` | `presentationBackground` | func | presentation-background | outside the popover content, on an anchored overlay, and on the drawn alert and menu panels | changes nothing | a scope outside the presentation reports nothing (probe B4) | none | aPresentationBackgroundOutsideThePopoverContentChangesNothing | BG-A |
| `MetalUI` | `ElementGroup` | `transition` | func | transition | a group nested deeper than the content a conditional or loop produces | the transition is not applied | measured as inert (probes X15 X15b X16) | none | aNestedTransitionIsInert | AN-AE |
| `MetalUI` | `-` | `ModifierLayerKind` | protocol | modified-content | an external conformer | compiles and is inert: nothing public builds a ModifiedContent over it | not applicable: SwiftUI has no such protocol | none | anExternalModifierLayerKindCannotBuildAModifiedContent | MC-A |
| `MetalUI` | `StyledElement` | `margin` | func | css-item-fields | a child of a Stack, of a frame layer or of a presentation placeholder | a flex parent lowers it to outer padding; these parents drop it in size and position | not applicable: MetalUI-only vocabulary | none | unpinned | LR-AZ |
<!-- record-05:public:end -->

### Internal and protocol-requirement rows

Declarations the census cannot key: a stored internal value nothing in production reads
(the future contributor is the reader this warns), and a protocol requirement. This table is
the set the old list named, re-verified, plus what the 196 sweep found; it is **not** a census
of internal counters (`RD-F`). `declaration ERE` must match a line of `file`.

<!-- record-05:internal:begin -->
| file | declaration ERE | writer | readers | pin | ruling |
|---|---|---|---|---|---|
| `Sources/MetalUIPlatform/Platform.swift` | `var onInput: \(\(InputEvent\) -> Bool\)\?` | every host; the Window callback computes the answer | AppKit reads the Bool for performKeyEquivalent and the drop targets only; discarded for pointer, scroll, key and text events on AppKit and for every event on SDL | inputReachesTheHandlerAndTheAnswerReachesTheHost | - |
| `Sources/MetalUI/Frame.swift` | `var scrollRegions:` | derived from the hitbox list on each call | tests only | unpinned | - |
| `Sources/MetalUI/Window.swift` | `var lastScrollRegions:` | derived from lastHitboxes on each call | tests only | unpinned | - |
| `Sources/MetalUI/StateTable.swift` | `private\(set\) var isDirty` | write sets it; Window.drawFrameIfNeeded clears it | tests only: the production mechanism is the onWrite hook | writingStateMarksTheTableDirtyAndReadingDoesNot | - |
| `Sources/MetalUI/StateTable.swift` | `private\(set\) var writeCount` | withState increments it | tests only | aSettledFieldStopsIncrementingTheWriteCount | - |
| `Sources/MetalUI/Frame.swift` | `private\(set\) var axNodes` | emitAXNode, every frame | verify-only: captureRetainedVerifySnapshot and the retained ledger | unpinned | - |
| `Sources/MetalUI/AXEmission.swift` | `let synthesizes: Bool` | Frame.registerHandlers | verify-only: the retained verify snapshot | unpinned | - |
| `Sources/MetalUILayout/LayoutTree.swift` | `package private\(set\) var lastNativeLayoutWork` | every native layout run | tests only, through the testingOnFrameAdopted seam | unpinned | - |
| `Sources/MetalUILayout/NativeGrid.swift` | `var bookkeepingSteps = 0` | the grid solver | tests only | unpinned | - |
<!-- record-05:internal:end -->

### Not rows (decided)

So the next re-derivation does not re-litigate them. Each was checked by the reader grep
recorded in record 196's ledger.

- **`AnyElement`, `ElementObject`, `AnyElementBox`**: fully implemented and produced in
  `Toolbar.swift`, `ToolbarStrip.swift`, `PresentationBackground.swift`,
  `WindowControlsStrip.swift`; the old "produced by nothing" is false.
- **Colour glyphs**: a renderer limit, not a declaration; listed under "not offered" in
  `docs/divergences.md`.
- **`StyledElement.hidden()`**: live since `LR-DH`; the legacy glyph-at-the-corner row is gone.
- **`AXNode.logicalCount`**: read by `AccessibilityTreeBuilder` (`AB-L`).
- **`GlyphAtlas.evictUnusedSince`**: removed (`GL-`, record 184).
- **`EnvironmentValues.layoutDirection`**: mirrors layout (`LD-A`, `LD-E`).
- **`controlActiveState`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`**:
  each has a production reader (`ControlLook.swift`, `TransitionGroup.swift`,
  `MaterialTransparency.swift`).
- **`windowSize`, `titleBarInsets`, `fileDialogs`, `textMeasurer`**: MetalUI-only values the
  window stamps for authors; no SwiftUI namesake whose built-ins could react.
- **The `Style` rows of the CSS-engine era** (`aspectRatio`, `overflow`, `Position.relative`,
  `Style.border`, `AlignItems.baseline`, `margin: .auto`, leaf `padding`): the fields are
  deleted or lowered (`LR-FM`, `TE-L`, `LR-AH`); a field with no lowering is a permanent
  refusal by name (`LR-FO`), a trap or a report, never a silent no-op.
- **`MUIRect.borderColor`, `borderWidths`**: a C ABI struct outside the census, and
  `Decoration.border` now sets them.
- **A frame with exactly one infinite maximum**: the kernel frame fills the axis
  (`FR-A`); the legacy "inert" arm went with the legacy engine.
- **The no-argument `frame()`, `AXNode.actions`, `AXActionKind`,
  `AXNode.init(…actions:…)`**: deprecated with a message that says so; the warning is the
  non-silence.
- **`LayoutTree.reset(generation:)`, `Frame.axNode(for:)`**: functions that work when
  called; no caller is dead code.
- **`PaintPass.isActive`/`isHovered`, `ScrollIndicatorVisibility`'s cases,
  `GPUSurfaceContext`, `ScrollContext.axis`, `Box.flexDirection`,
  `ProposalElementGroup.layoutPriority`, `Text.paint`**: read by their consumers or by the
  author they exist for; the doc-comment sweep matched them on history.
- **`ScrollViewProxy.scrollTo(_:anchor:)`'s cross-axis component**: a one-axis scroller has
  no cross offset.
- **`UnlowerableField` sites `.list`, `.component`**: internal diagnostic tags, read by the
  report mechanism; that they raise no entry is a fact about reporting.
- **`ElementGroup._wrap`/`LayerBase`**: a conformer-misuse hazard documented at the
  requirement; the default works.
- **`glassEffectTransition`, `.materialize`, `.matchedGeometry`**: run the opacity
  transition (divergence 828); a difference, not inertness.
- **The `HeadlessPlatform*` and `TestWindow` recorders** (`setSubtitle`, `setDismissEnabled`,
  the counters): the observables are the product of `MetalUITesting`.
- **Internal test counters in general** (`buildCount`, `publishCount`, the `testing*` hooks
  and their kind): read by tests by design behind a named seam; not enumerated (`RD-F`).
