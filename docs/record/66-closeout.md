# 66 — Replacement closeout (plan task 15)

Branch `feat/closeout` from `1b093b8` (master: plan task 13 merged, task 14's
record). Spec `docs/superpowers/specs/2026-09-30-closeout-design.md`; rulings
`CX-A`…`CX-R` in `docs/superpowers/2026-09-30-closeout-decisions.md` (next
unused `CX-S`); probe `docs/probes/swiftui-closeout.swift` (lane 1).

**Status: DESIGN committed and critiqued (`CX-P`); lane 1 landed (§4); lane 2 landed (§1–§3, §5, `CX-R`); lane 3 and the Record phase to run.**

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

## §1 Inventory (`CX-A`) — family table (lane 2)

Classes: **A** SwiftUI-aligned (probe arm + discriminating test), **D**
documented divergence (live label in `docs/divergences.md`), **M**
MetalUI-only by design (ruling), **X** deprecated (replacement), **R**
documented absence (not a census row, §1.3). The divergence column lists the
live labels a family carries beside its class.

**The mechanical form** is `docs/probes/closeout-inventory-map.tsv` (97 `F`
family rows, 178 ordered `M` rules matching target, file, owner, name and —
where one name has overloads in different classes — the declaration's
signature) and `docs/probes/closeout-inventory-check.sh`, which runs the
census live and prints thirteen kinds of problem (its header lists them;
`CITE`, the thirteenth, added by lane 2's fix round, `CX-S`).
**At lane 2's tip it prints nothing**: the census reads **1872** rows (the
1871 of `1b093b8` plus lane 1's public `looksDemoContent()`, `CX-Q` item 3;
the `Box` initialiser split moved lines, not rows), every row is claimed,
every A family's probe file exists, its arm occurs in it, its test
resolves and (since `CX-S`) that test names the arm, every D family has a label, every label is live, every ruling id
occurs in `docs/superpowers/`, every X member carries `@available(*,
deprecated …)` and every deprecated declaration is in an X family. Totals:
**A 835 rows / 52 families, D 2 / 2, M 989 / 36, X 46 / 7** at lane 2's
tip; **A 833 / 51, M 991 / 37** after its fix round (`text-input-binding`
reclassified M, `CX-S` item 4).

**The check can fail** — twelve mutations of the map or `docs/divergences.md`,
each on the committed tree `4005bd8`, restored with `git checkout -- docs`,
`git status --short` empty after each, each printing exactly its kind:

| id | mutation | printed |
|---|---|---|
| K1 | the `UnitPoint.swift` rule deleted | `UNMAPPED` × 14 (`UnitPoint.swift:14` …) |
| K2 | `stacks`' test name misspelt | `TEST stacks …X` |
| K3 | `stacks`' arm `G1` → `G999` | `ARM stacks … G999` |
| K4 | `grid`'s probe file misspelt | `PROBE grid swiftui-gridz.swift` |
| K5 | `theme`'s class `M` → `Q` | `CLASS theme Q` |
| K6 | `native-aliases` `X` → `M` | `DEPR native-aliases …NativeRow` (26 rows) |
| K7 | `theme` `M` → `X` | `NOTDEPR theme …` (16 rows) |
| K8 | a ruling `EV-H` → `EV-ZZ` | `RULING theme EV-ZZ` |
| K9 | row 90 deleted from `docs/divergences.md` | `LIVE shapes 90` |
| K10 | a family no rule names appended | `UNUSED ghost` |
| K11 | `environment-layout-direction`'s label removed | `DLABEL …` |
| K12 | a rule naming an undefined family | `NOFAMILY unit-pointz …` |

Lane 3's doc comments move line numbers only; the map keys on file, owner,
name and signature, never a line, and the deprecation walk reads the
attribute block above each declaration, doc comments included.

**Re-run**: `zsh docs/probes/closeout-inventory-check.sh` (≈ 10 s; prints
nothing). Row counts per family: the same script with `used[hit] = 1`
followed by a print of `hit` (a scratch copy, not committed).

### §1.1 The families

Evidence for A is `probe` arm; `test`; then the rulings. For D, M and X the
rulings (X: the replacement is in the behaviour cell).

| family | class | rows | behaviour classified | evidence | div. |
|---|---|---|---|---|---|
| `host` | M | 31 | the host: one App, windows driven by a display link, a headless renderFrame; SwiftUI's App/Scene lifecycle is not offered | `PB-A`, `RS-A`, `DC-A`, `XP-B` |  |
| `element-protocols` | M | 15 | Element/ElementGroup/StyledElement/ProposalElement/ProposalElementGroup: gpui's three-phase requestLayout/prepaint/paint protocols in place of View | `SA-G`, `MC-B`, `LR-AA` |  |
| `passes` | M | 37 | LayoutPass/PrepaintPass/PaintPass phase objects; isHovered/isActive/isFocused paint-only (PhaseSeparationTests) | `SA-H`, `EV-L` |  |
| `kernel-registrars` | M | 15 | LayoutPass's requestNative*/markNativeGrid* registrars: the kernel's primary API for a custom element | `SA-A`, `GR-C` |  |
| `builder` | A | 45 | @ViewBuilder's shapes: one structural slot per if/for, content an evaluated conditional removes is reset on return, if/else/switch in every container | `swiftui-composition-identity.swift` V2; `anElementAfterAnAppearingIfKeepsItsOwnState`; `ID-B`, `ID-C`, `ID-D` |  |
| `any-element` | A | 16 | AnyView: @State/@Environment bind inside an AnyElement | `swiftui-composition-identity.swift` S2; `stateInsideAnAnyElementPersistsAcrossFrames`; `ID-E` |  |
| `explicit-identity` | A | 14 | .id(_:) on every element group; a changed name resets, a departed name starts fresh on return; two same-named siblings share one identity (72) | `swiftui-composition-identity.swift` X9; `anIDThatReturnsToAnEarlierNameStartsFresh`; `ID-G`, `ID-R` | 72 |
| `global-id` | M | 8 | GlobalElementID/PathComponent: the structural identity path value (positional/named components, -1 for an overlay) | `MC-C`, `MC-P`, `C-3` |  |
| `component` | M | 17 | Component/StyledComponent: layout-transparent, identity-opaque composition; .width/.height frame each member; .frame is one layer over a row of per-member frames, the members aligned by the frame's own alignment where SwiftUI's Group uses the parent's (56) | `OM-D`, `LR-BG`, `ID-I`, `ID-K` | 56, 73 |
| `deferred` | M | 8 | Deferred: a portal hoisting to the root layer; absolute content is a presentation root against the window | `LR-CH`, `AP-I`, `OM-AA` | 9, 10, 46 |
| `handlers` | M | 13 | Handlers/HitboxID/KeyHandler: handler storage and hitbox ids | `OM-AI`, `IX-N` |  |
| `state` | A | 4 | @State per occurrence, dispatch-resolved; an optional with a non-nil default reads it before its first write (85 retired); a write from outside dispatch reaches the last-bound occurrence (71) | `swiftui-closeout.swift` O1; `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite`; `ID-F`, `CX-F`, `DD-D` | 71 |
| `binding` | A | 12 | Binding<Value>: SwiftUI's surface (get/set, constant, dynamic member, optional initialisers, animation/transaction), @MainActor (78) | `swiftui-data-and-scrolling.swift` B5; `theOptionalBindingInitialisersMatchSwiftUI`; `DD-D`, `AN-Z` | 78 |
| `environment` | A | 17 | @Environment/EnvironmentValues/EnvironmentKey/.environment/.transformEnvironment/.disabled: nearest writer wins, a transform composes, a modifier after a scope is outside it | `swiftui-environment-scoping.swift` A1; `theNearestWriterWinsAndAScopeEndsWithItsSubtree`; `EV-A`, `EV-B`, `EV-C`, `EV-D`, `EV-X` |  |
| `environment-control` | A | 7 | displayScale/pixelLength, controlActiveState, controlSize, accessibilityReduceMotion: platform-stamped, scope-writable (reduce motion get-only); controlSize reaches only text and Button chrome (76); layout rounds to points (77) | `swiftui-environment-control-state.swift` S2; `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows`; `EV-AA`, `EV-AB`, `EV-AC`, `AN-AD` | 76, 77 |
| `environment-dynamic-type` | A | 4 | dynamicTypeSize is carried and changes no built-in text size, as SwiftUI on macOS | `swiftui-environment-scoping.swift` G0; `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority`; `EV-I`, `TE-E` |  |
| `environment-layout-direction` | D | 1 | layoutDirection is carried and readable; no container mirrors (25) | `EV-K` | 25 |
| `environment-locale` | M | 1 | locale is carried and window-stamped; MetalUI has no formatter or tokenizer that reads it (record §05) | `EV-Y` |  |
| `theme` | M | 16 | Theme/ColorToken/.theme: scoped, paint-only theme tokens | `EV-G`, `EV-H` |  |
| `focus-state` | A | 10 | @FocusState/.focused: read the window's focus, move it from input; focus leaves with its identity; a click does not focus a .focusable() (94) | `swiftui-interaction.swift` F1; `focusDropsWhenItsElementIsRenamedAndDoesNotReturn`; `IX-I`, `IX-J` | 94 |
| `stacks` | A | 36 | HStack/VStack/ZStack/Spacer/alignments/.layoutPriority: SwiftUI's stack algorithms, typed alignment, text baselines | `swiftui-stack-algorithms.swift` G1; `aStackServesItsLeastFlexibleChildFirst`; `CN-B`, `CN-C`, `CN-E`, `CN-H`, `CN-I`, `TE-K` | 51, 58, 70, 89 |
| `proposal-frame` | A | 24 | ProposalFrame/.frame on proposal content: fixed and flexible frames, ideal on an unspecified axis; a negative fixed size traps (38) | `swiftui-frame-semantics.swift` D1; `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`; `FR-A`, `FR-M`, `CN-F`, `SA-J` | 38 |
| `native-frame-alias` | M | 2 | nativeFrame(...): an undeprecated alias of .frame, kept because deprecating it breaks the 0-warning baseline (record §09) | `SA-K` |  |
| `proposal-padding` | A | 8 | Padding/.padding on proposal content: insets the proposal, places the child at its own size | `swiftui-engine-replacement-stage2.swift` N1; `aNativePaddingPlacesItsChildAtTheChildsOwnSize`; `LR-AU`, `SA-N` |  |
| `proposal-background` | A | 8 | Background/.background(token) on proposal content: fills the box it is written on, beneath its content | `swiftui-outer-modifier-order.swift` A1; `nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent`; `OM-C` |  |
| `fixed-size` | A | 9 | FixedSize/.fixedSize: withholds the selected axes from the child's proposal | `swiftui-engine-replacement-stage2.swift` F7; `aFixedSizeTextKeepsItsOneLineWidthInANarrowStack`; `CN-B` |  |
| `color-fill` | A | 6 | Color: a greedy fill answering its proposal | `swiftui-shapes-and-rendering.swift` P2; `aColorAnswersItsProposalAndTenOnANilAxis`; `FR-A` |  |
| `aspect-ratio` | A | 4 | .aspectRatio/.scaledToFit/.scaledToFill/ContentMode; nil ratio uses the child's own | `swiftui-stack-algorithms.swift` AR1; `anAspectRatioAnswersItsChildsAnswerToTheRatioProposal`; `TE-AM` | 97 |
| `proposal-border` | A | 1 | .border on proposal content: a square band over whatever it is written after | `swiftui-border-clip-paint.swift` D1; `aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill`; `OM-W`, `CX-B` |  |
| `opacity` | A | 2 | .opacity on either vocabulary: what is written after it escapes it; a second opacity replaces the first (46) | `swiftui-border-clip-paint.swift` G3; `theOpacityOrderAnswersTheSameOnBothPathsThroughTheUnifiedType`; `OM-N`, `LR-FW` | 46 |
| `hit-testing` | A | 2 | .allowsHitTesting: gates the pointer target; per layer (44); default region the whole frame (41); a disabled target passes the click (23) | `swiftui-content-shape-hit-region.swift` N1; `allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTargetAndItsSubtreesAndKeepsTheKeyboardOnes`; `OM-AK`, `OM-AL`, `EV-E`, `IX-Z` | 23, 41, 42, 44 |
| `content-shape` | A | 3 | .contentShape(inset:)/.contentShape(Shape): moves the pointer region only | `swiftui-content-shape-hit-region.swift` H3; `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout`; `OM-J`, `OM-AB`, `IX-L` | 43, 50 |
| `modified-content` | A | 25 | ModifiedContent<Content, Modifier>/LayoutModifier/ModifierLayerKind: one flat modifier chain, one layer per modifier, SwiftUI's ModifiedContent | `swiftui-outer-modifier-order.swift` L1; `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`; `LR-FV`, `MC-A` |  |
| `modifier-layer` | M | 8 | ModifierLayer, the ModifiedElement typealias, _wrap: the legacy arm of ModifiedContent; a layer added at run time is adopted by the new outermost (20) | `MC-A`, `MC-C`, `CX-C` | 20 |
| `overlay` | A | 11 | OverlayModifier/.overlay: the overlay at the primary's size under child -1; a multi-member primary traps (73) | `swiftui-overlay-primary-shape.swift` P1; `aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape`; `MC-P`, `LR-FX` | 73 |
| `background-modifier` | A | 11 | BackgroundModifier/.background(alignment:content:): the overlay's recipe, painted first; a non-clickable primary passes a click to it (57) | `swiftui-overlay-presentation.swift` H1; `aLegacyBackgroundSitsBehindItsPrimaryAtThePrimarysSize`; `ID-J`, `CN-K` | 57, 73 |
| `scroll` | A | 15 | ProposalScrollView/ScrollAxis/ScrollIndicatorVisibility: scroll axes, indicators (.visible as .automatic, .never as .hidden) | `swiftui-data-and-scrolling.swift` T11; `scrollToWorksHorizontallyAndInAProposalScrollView`; `DD-G`, `DD-H`, `CN-F` |  |
| `scroll-reader` | A | 9 | ScrollViewReader/ScrollViewProxy.scrollTo: one slot, reach its own subtree, keys by value | `swiftui-scrollviewreader-scope.swift` S2; `scrollToIsScopedToItsReader`; `DD-G`, `DD-K` |  |
| `unit-point` | A | 14 | UnitPoint: scrollTo anchors and grid cell anchors | `swiftui-data-and-scrolling.swift` T9; `scrollToAnAnchorLandsTheTargetAtTheAnchor`; `DD-G`, `TE-AN` |  |
| `proposal-text` | A | 12 | ProposalText: text in the proposal vocabulary; answers min(proposal, widest line) | `swiftui-engine-replacement-stage1.swift` T3; `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal`; `LR-AU`, `TE-H` | 60, 86, 87 |
| `proposal-layout` | A | 35 | ProposalLayout/ProposalLayoutContainer/subview proxies/ProposedSize: SwiftUI's Layout without a cache | `swiftui-layout-protocol-contract.swift` I2; `anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal`; `SA-A`, `SA-B`, `SA-F` |  |
| `grid` | A | 34 | Grid/GridRow/cell modifiers: SwiftUI's Grid (reference model; residual disagreements 61, 62) | `swiftui-grid.swift` GA1; `gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI`; `GR-C`, `GR-D`, `GR-O`, `CX-H` | 61, 62, 63, 65, 66, 67, 68, 88 |
| `foreach` | A | 13 | ForEach: identity by key, a dropped element resets; description-colliding ids keep the first (79) | `swiftui-data-and-scrolling.swift` F1; `aForEachKeepsEachElementsStateThroughAReorder`; `DD-B`, `DD-C` | 79 |
| `transaction` | A | 14 | Transaction/withTransaction/.transaction/.animation(_:value:): a transaction stack; one root transaction per build (99) | `swiftui-transactions-animation.swift` T5; `withTransactionAnimatesAChangeAsWithAnimationDoes`; `AN-Y`, `AN-Z` | 99 |
| `transition` | A | 19 | AnyTransition/Edge/.transition: the documented set; no default transition (98) | `swiftui-transactions-animation.swift` X1; `anOpacityTransitionFadesAnInsertedElementIn`; `AN-AE`, `AN-AH` | 98 |
| `animation` | A | 10 | Animation curves and withAnimation: modifier wrappers animate at their phase; interpolation of declared input, not placed geometry (96); what snaps (97) | `swiftui-transactions-animation.swift` W3; `aProposalOpacityAnimates`; `AN-X`, `AN-AB` | 96, 97 |
| `native-aliases` | X | 26 | Native… typealiases and native… modifiers: use the un-prefixed name (HStack, VStack, ZStack, ProposalFrame, Padding, Background, FixedSize, Spacer, Rectangle, Color, LayoutModifier, ModifiedContent, OverlayModifier, OnTapModifier; .padding/.fixedSize/.background/.clip/.border/.opacity/.allowsHitTesting/.overlay/.onTap) | deprecated; `CX-C` |  |
| `stack-spacing-first-init` | X | 2 | HStack/VStack init(spacing:alignment:content:): use init(alignment:spacing:content:) | deprecated; `CN-I` |  |
| `rectangle-color-init` | X | 1 | Rectangle(color:): use Rectangle().fill(_:) (Rectangle(width:height:color:) stays, the fixed leaf convenience) | deprecated; `TE-AC` |  |
| `frame-no-args` | X | 2 | .frame() with no arguments: a deprecated no-op; delete the call | deprecated; `FR-J` |  |
| `box` | M | 14 | Box: the legacy (CSS-derived) container, lowered onto the kernel; public init(decoration:), the style: initialisers package (CX-D) | `CN-A`, `CX-D`, `EP-8` |  |
| `decoration` | M | 26 | Decoration/BorderStyle and the legacy background/hoverBackground/focusBackground/cornerRadius/border/hoverBorder/focusBorder: paint-only decoration on one order-insensitive record; corner radius rounds fill and border without clipping (47); a rounded border follows the arc (49) | `OM-G`, `OM-W`, `LR-FW` | 47, 49 |
| `legacy-containers` | M | 56 | Row/Column/Stack/Alignment/legacy ScrollView/ScrollState/ScrollContext: the legacy containers, lowered; Row/Column gap 0 (52); legacy ScrollView's cross axis from its parent (54) | `CN-A`, `CN-P`, `CX-E` | 52, 54 |
| `style` | M | 10 | Style/Position/FlexDirection/AlignItems/AlignSelf/JustifyContent: opaque outside the package | `LR-FM`, `LR-FO` |  |
| `list` | M | 13 | List: virtualized, data-driven, uniform rows; selection; windows against its own origin | `LR-BQ`, `DD-F`, `DD-Z`, `DD-AB` | 13, 32, 84 |
| `css-item-fields` | M | 14 | margin/gap/justifyContent/alignItems/flexGrow/flexShrink/flexBasis(length)/alignSelf/position/inset/flexDirection: CSS item and container fields lowered onto the kernel, unlowerable cases refused by name | `LR-AB`, `LR-AS`, `LR-FO` |  |
| `legacy-padding` | A | 2 | StyledElement.padding: one wrapper layer; chained padding accumulates; a padded click target is hittable in its padding (42) | `swiftui-outer-modifier-order.swift` E2; `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`; `OM-D`, `OM-E` | 42 |
| `legacy-frame` | A | 2 | ElementGroup.frame(...): SwiftUI's frame surface on legacy content, lowered onto the kernel frame (ideal and flexible maxima answer as SwiftUI; 35 and 39 retired by CX-G) | `swiftui-frame-semantics.swift` E1; `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`; `FR-C`, `CN-N`, `LR-DH`, `CX-G` |  |
| `legacy-clip` | A | 2 | StyledElement.clipped/.clipShape: clip the subtree and its hitboxes | `swiftui-border-clip-paint.swift` E1; `aLegacyClipShapeClipsItsChildrenAndItsHitboxes`; `TE-AJ`, `OM-G` | 91, 92 |
| `hidden` | A | 1 | .hidden(): keeps its space, paints nothing, takes no hit, is not published, leaves the keyboard's focus half | `swiftui-engine-replacement-stage1.swift` H1; `aHiddenChildKeepsItsSpaceUnderTheProposalAuthority`; `LR-DH`, `IX-K` |  |
| `legacy-keyboard` | M | 4 | onKey/focusable/onAction/keyContext: gpui's raw key and action handlers and focusability (21, 22, 26, 94) | `EV-F`, `IX-K`, `TI-J` | 21, 22, 26, 94 |
| `on-click` | M | 12 | onClick (and proposal onTap/OnTapModifier): Button semantics (press and release on one element), pressable through accessibility (27) | `IX-B`, `AB-G` | 27 |
| `focus-border` | M | 3 | focusBorder/focusBackground: the opt-in focus ring and focus fill | `OM-V`, `IX-H` |  |
| `button` | A | 26 | Button/ButtonRole/ButtonStyle/.keyboardShortcut on a Button: actions, roles (ButtonRole binds a key, draws nothing), styles, pressed look | `swiftui-interaction.swift` B2; `aButtonRunsItsActionOncePerClickAndNotOnAPressReleasedOutside`; `DD-R`, `IX-E`, `IX-F` | 76, 80 |
| `controls` | A | 32 | Toggle/Slider/Stepper on Binding: values, steps, clamping, keys once focused (80); the partial accessibility fold (82) | `swiftui-controls-and-selection.swift` SA1; `anUnsteppedAdjustmentMovesTenPercentOfTheSpan`; `DD-S`, `DD-W`, `DD-X` | 80, 82 |
| `picker` | A | 29 | Picker/PickerStyle/.tag/TaggedElement: options found through tags; automatic is segmented, not a menu (81) | `swiftui-controls-and-selection.swift` PA1; `pressingAnOptionWritesItsTag`; `DD-V`, `DD-AA` | 80, 81, 82 |
| `text` | A | 17 | Text (legacy-vocabulary leaf): measured and drawn through the text seam; fonts, line limits, truncation; width not ceiled to the pixel grid (60); line advance (86); middle truncation (87) | `swiftui-text-semantics.swift` F6a; `theEnvironmentFontReachesATextAndTheTextsOwnWins`; `TE-A`, `TE-F`, `TE-H`, `TE-AA` | 60, 86, 87 |
| `text-proposal-bridge` | M | 1 | Text.proposalLayout(): converts a legacy Text to a ProposalText, dropping background, handlers, id and hover/focus colours | `LR-S`, `CN-A` |  |
| `font` | A | 33 | Font, Font.Weight, Font.Design, Font.TextStyle: system sizes/weights/designs, the eleven text styles, custom families | `swiftui-text-semantics.swift` F1; `aTextStyleResolvesToMacOSsFace`; `TE-B`, `TE-C`, `TE-D`, `TE-E` |  |
| `text-modifiers` | A | 28 | .font/.fontWeight/.italic/.foregroundStyle/.foregroundColor/.lineLimit/.truncationMode/.multilineTextAlignment, TextAlignment, Text.TruncationMode | `swiftui-text-semantics.swift` L1; `aLineLimitCapsLinesAndAnswersTheWidestKeptLine`; `TE-H`, `TE-I`, `TE-J`, `TE-AA` |  |
| `text-input` | M | 40 | TextField/TextEditor controlled initialisers, submit, undo, paging: MetalUI's own text-input surface | `TI-A`, `TI-B`, `TI-D`, `TI-G`, `TI-H` |  |
| `text-input-binding` | M | 2 | TextField(_:text:)/TextEditor(_:text:) over Binding<String>, forwarding to the controlled initialisers; MetalUI-only evidence: no probe arm exercises TextField(text:)/TextEditor(text:) (data-and-scrolling's B4 is a Binding built outside any view), so the forwarding is pinned by aTextFieldBoundToStateUpdatesItOnEveryEdit alone; the Binding surface itself is the binding family's (B4/B5) | `DD-E` |  |
| `shapes` | A | 50 | Shape/ShapeGeometry/Rectangle/RoundedRectangle/Circle/Capsule/Ellipse/ShapeView/.fill/.stroke/.strokeBorder; continuous corners drawn circular (90) | `swiftui-shapes-and-rendering.swift` S1; `everyBuiltInShapeAnswersItsProposalAndACircleTheSmallerSquare`; `TE-AC`, `TE-AG`, `TE-AH`, `TE-AE` | 90 |
| `clip-shape` | A | 4 | .clipShape/.clipped/.cornerRadius/.clip on proposal content: one clip layer; an ellipse clip traps (91); crossing rounded clips square (92) | `swiftui-shapes-and-rendering.swift` C3; `clippedAndCornerRadiusClipOnTheProposalPath`; `TE-AJ` | 91, 92 |
| `shape-background` | A | 2 | .background(_:in:)/.background(in:): a filled shape behind the content | `swiftui-shapes-and-rendering.swift` O2; `backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken`; `TE-AK` |  |
| `image` | A | 9 | Image/Image.Interpolation: decorative and labelled images, .resizable, .interpolation (.high draws bilinear, 93) | `swiftui-shapes-and-rendering.swift` I1; `anImageAnswersItsPointSizeAtEveryProposal`; `TE-AL`, `TE-AM` | 93 |
| `image-bitmap` | M | 5 | ImageBitmap: the portable stand-in for CGImage (premultiplied RGBA8) | `TE-AL` |  |
| `gestures` | A | 60 | Gesture/TapGesture/LongPressGesture/DragGesture/composition and .gesture/.simultaneousGesture/.highPriorityGesture/.onTapGesture/.onLongPressGesture: one arena per press | `swiftui-interaction.swift` H2; `anOuterHighPriorityGestureBeatsTheInnerOneAndAButton`; `IX-B`, `IX-C`, `IX-D`, `IX-Q` |  |
| `keyboard-shortcut` | A | 26 | KeyEquivalent/KeyboardShortcut/EventModifiers: exact, case-folded matching in tree order | `swiftui-interaction.swift` B4e; `aShortcutFiresItsButtonWithoutFocusOnAnExactModifierMatch`; `IX-F` |  |
| `keymap` | M | 24 | Keymap/KeyBinding/Keystroke/KeymapBuilder/KeyContext/ContextPredicate/Action/ActionHandler: gpui's keymap and actions | `EV-N`, `IN-A` |  |
| `accessibility-modifiers` | A | 55 | accessibility modifiers on both vocabularies, AccessibilityModifier/Traits/ChildBehavior/Adjustment: .ignore/.combine/.contain, hidden, hint, identifier, traits, declared and named actions, modal isolation (95) | `swiftui-accessibility-part2.swift` E3; `aCombinedElementJoinsItsChildrenIntoOneStaticText`; `IX-U`, `IX-V`, `IX-X`, `IX-Y`, `AB-T` | 29, 30, 31, 33, 34, 82, 95 |
| `axnode` | M | 13 | AXNode/AXRole/AXTrait: the neutral accessibility record a StyledElement declares; a List publishes realised rows only (32) | `AB-C`, `AB-F`, `AB-U` | 32 |
| `axnode-actions` | X | 3 | AXActionKind/AXNode.actions/AXNode.init(…actions:…): use accessibilityAction(_:)/accessibilityAdjustableAction(_:) | deprecated; `IX-Y`, `CX-C` |  |
| `sizing-modifiers` | X | 10 | width/height/minWidth/minHeight/maxWidth/maxHeight and width/height(fraction:)/(percent:): use .frame (LR-ES recipe R1–R8) | deprecated; `FR-I`, `LR-ER`, `LR-EU`, `CN-O` |  |
| `flex-basis-fraction` | X | 2 | flexBasis(fraction:)/flexBasis(percent:): no SwiftUI counterpart; declare a length or a .frame | deprecated; `CX-C` |  |
| `core-geometry` | M | 62 | MetalUICore geometry and units (Point, Size, Bounds, Edges, Corners, Axes, Pixels, Rems, Length, Dimension, …) | `C-1`, `PC-A` |  |
| `core-color` | M | 18 | Hsla/Rgba: colours authored in sRGB, composited in a Display P3 layer (1) | `F-1`, `TB-A` | 1 |
| `core-appearance` | M | 1 | Appearance: the host's light/dark appearance, selecting the theme | `EV-H` |  |
| `control-active-state` | A | 1 | ControlActiveState: key/active/inactive, SwiftUI's cases; the platform mapping is MetalUI's own (C1–C3 unmeasured) | `swiftui-environment-control-state.swift` V0; `controlActiveStateIsKeyInABareValueAndAWindowlessFrameAndAScopeCanWriteIt`; `EV-AB` |  |
| `layout-direction-type` | D | 1 | LayoutDirection: carried, read by no container (25) | `EV-K` | 25 |
| `layout-kernel` | M | 66 | MetalUILayout's LayoutTree, node ids, registrars, measure functions, grid marks, spacing, rounding (77) | `SA-L`, `SA-M`, `GR-C` | 77 |
| `platform` | M | 78 | MetalUIPlatform: Platform/PlatformWindow/WindowRenderer, input events, the neutral accessibility tree | `RS-A`, `AB-R`, `EV-AB`, `AN-AD` |  |
| `render` | M | 43 | MetalUIRender/MetalUIPrimitives/MetalUIAppKit: the Metal renderer, surfaces, shader library, the AppKit platform | `RS-B`, `RS-C` |  |
| `scene` | M | 77 | MetalUIScene: Scene, draw runs, the glyph atlas, FontKey, GlyphImage, ImageTexture | `PS-A`, `PS-B`, `TE-AF` |  |
| `text-system` | M | 97 | MetalUIText/MetalUITextSystem: the TextSystem seam and its CoreText conformer | `TS-A`, `TS-B`, `TX-B` |  |
| `portable-text` | M | 116 | MetalUIFreeType/MetalUIHarfBuzz/MetalUIPortableText/MetalUISystemFonts: the portable text pipeline | `FT-B`, `SH-B`, `PT-A`, `LB-A`, `FN-A`, `FB-A`, `BD-B`, `SF-A` |  |
| `demo-content` | M | 25 | MetalUIDemoContent: the demo trees, importable by tests | `LR-S`, `CX-Q` |  |

### §1.2 Where lane 2 departed from the design session's proposals

- **Split per modifier** (`CX-A` item 4): `StyledElement`'s extension in
  `Box.swift` into `on-click` (M, 27), `legacy-keyboard` (M; 21, 22, 26, 94),
  `explicit-identity` (`.id`, A), `decoration` (M; 47, 49), `focus-border`
  (M), `sizing-modifiers` (X), `legacy-padding` (A, 42),
  `flex-basis-fraction` (X, by signature), `css-item-fields` (M), `hidden`
  (A — keeps its space, `LR-DH`, stage-1 probe H1), `opacity` (A, 46),
  `legacy-clip` (A; 91, 92), `hit-testing` (A; 23, 41, 42, 44),
  `content-shape` (A; 43, 50); `NativeModifiedContent.swift`'s modifiers
  likewise, per modifier.
- **Split by signature** (`decl-ERE`): `TextField`/`TextEditor`'s
  `Binding<String>` initialisers (A at lane 2's tip, M since `CX-S`: no
  probe arm exercises them; `DD-E`) from their controlled surface
  (M, `TI-`); the deprecated `AXNode.init(…actions:…)`, `Rectangle(color:)`,
  `HStack`/`VStack(spacing:alignment:)` and the two no-argument `frame()`s
  (X) from their undeprecated siblings; `flexBasis(fraction:/percent:)` (X)
  from `flexBasis(_ Length)` (M).
- **The environment** split five ways: scoping (A), the control state and
  scale keys (A; 76, 77), `dynamicTypeSize` (A, `EV-I`: inert as on macOS),
  `layoutDirection` and `LayoutDirection` (D, 25), `locale` (M, `EV-Y`: no
  reader exists).
- **Identity**: `ElementID`/`.id` (A, 72) from `GlobalElementID`/
  `PathComponent` (M, the structural path value).
- **`nativeFrame(…)` is M, not X**: undeprecated on purpose (`SA-K`; record
  §09: deprecating it breaks the 0-`warning:` baseline). `CX-C` item 1's
  "the `Native…` aliases stay deprecated" is true of every other one.
- **Two X families the design did not list**: `stack-spacing-first-init`
  (`CN-I`) and `rectangle-color-init` (`TE-AC`).
- **Labels moved by `CX-R`**: the legacy frame carries no label (35, 39
  retired); `legacy-containers` carries 52 and 54 (53, 55 retired); grid's
  exact set is 61, 62, 63, 65, 66, 67, 68, 88 (70 is a stack rule, on
  `stacks`; 64, 69 retired); `text` carries 60, 86, 87 (51 is the stack
  spacing beside text, on `stacks`).
- **`Text.proposalLayout()`** is its own M family (`text-proposal-bridge`):
  it drops background, handlers, id and hover/focus colours by design.

### §1.4 Lane 2's fix round: the A citations re-audited (`CX-S`)

The reviewer found class-A rows citing an arm their test does not assert
(keyboard-shortcut B1, foreach F2, text F1, accessibility-modifiers A1,
color-fill P1, text-input-binding B4), all passing `ARM` because short ids
occur in almost every probe. **The check was tightened first** (`CITE`: the
cited test must name the arm in its doc comment or body) and run on the
unfixed map: **24 `CITE` lines**, the six the reviewer named among them.
Every one of the 52 A families was then compared by hand — the arm's
recorded output line in the probe header against what the cited test
asserts — and each `CITE` line disposed (decisions `CX-S` item 2):

| family | was | now | why |
|---|---|---|---|
| builder | V1 | V2 | the test is the appearing `if` (V2) |
| proposal-frame | D4 | D1 | the test cites D control/D1/D2/D13 (greedy clamp) |
| proposal-padding | P1 | N1 | the test is group N (a padding places its child at its own size) |
| fixed-size | F7, a proposal-shape test | F7, `aFixedSizeTextKeepsItsOneLineWidthInANarrowStack` (new) | F7 records answers, not proposals |
| color-fill | P1 (ink control), a shape test | P2, `aColorAnswersItsProposalAndTenOnANilAxis` (new) | the old test never built a `Color` |
| modified-content | D1 | L1 (L1–L9) | the matrix asserts padding grows, the rest are layout-neutral |
| background-modifier | H0 (control) | H1 | the click arm the test asserts |
| scroll | T1 | T11 | the test is horizontal + `ProposalScrollView` |
| proposal-layout | I2, the stack reimplementation test | I2, `anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal` | I2 is the unplaced-subview arm |
| foreach | F2 | F1 | the test is the reorder |
| legacy-frame | B1 | E1 | the test cites E1/E2/E6 (chained frames) |
| button | controls-and-selection BA0 (an AX press) | interaction B2 (and B0) | the test is a click, and a press released outside |
| text | F1 | F6a | the environment font reaching a `Text` |
| font | F2 | F1 | the eleven text styles |
| text-modifiers | L5 | L1 (and L6b) | the test's `lineLimit` shape |
| text-input-binding | data-and-scrolling B4 | — (class M, `DD-E`) | no arm exercises `TextField(text:)` |
| shape-background | F2 | O2 | `background(_:in:)` equals the filled shape |
| keyboard-shortcut | B1 (Button press excursion) | B4e | the shortcut arms |
| accessibility-modifiers | A1 | E3 | `.combine` over two texts |
| control-active-state | C0 | V0 (and C4) | the bare value is `.key`; a scope writes it |
| any-element, environment-dynamic-type, proposal-background, legacy-clip | S2, G0, A1, E1 | unchanged | right arm; the test's doc comment now names it |

The other 28 A families' arms were already named by their tests and matched
by hand. **Red first for the two new tests** and the check's own failure
modes are §1.5's mutation table.

### §1.5 Fix-round mutations and counts (`CX-S`)

Committed tree `e69bc15`; each source mutation restored from a scratch copy,
full unfiltered `swift test --build-system native --no-parallel`, `git
status --short` empty after each.

| id | mutation | reddened |
|---|---|---|
| MS1 | `Color.measurement`'s nil-axis ideal 10 → 20 (`NativeElements.swift`) | `aColorAnswersItsProposalAndTenOnANilAxis` (1 issue), `aNativeFillAcceptsEachWindowsCurrentProposal` (3) — 4 issues |
| MS2 | `fixedSizeProposal` forwards the width unchanged (`LayoutTree.swift`) | `aFixedSizeTextKeepsItsOneLineWidthInANarrowStack` (1), `aNativeFixedSizeWithholdsOnlyItsSelectedAxesFromTheChildProposal` (1), `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal` (3), `builderFixedSizeWithholdsOnlyItsSelectedAxisFromTheChildProposal` (1), `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` (3), `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI` (2), `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (2), `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer` (1), `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows` (2), `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified` (1) — 17 issues |
| KS1 | map: `keyboard-shortcut`'s arm `B4e` → `H2` (a real gesture arm in the same probe, the reviewer's case) | `CITE keyboard-shortcut H2 …` (passed `ARM` silently before `CX-S`) |
| KS2 | map: `foreach`'s arm `F1` → `F2` (named by the NEXT test in the file) | `CITE foreach F2 …` — the body bound stops at the function's closing `}`, so a neighbour's comment does not satisfy it |

Counts at the fix round's tip: **1976 tests in 3 suites passed** (1974 + the
two new tests; the `FR-J no-argument frame: succeeded=` line present), 0
`error:`, the one native deprecation `warning:` and 0 under the default build
system; guards unmoved (no guard added). No `Sources/` line changed, so the
fourteen offscreen images are not re-taken. `closeout-inventory-check.sh`
prints nothing.

### §1.3 Documented absences (R rows; owner none unless stated)

Published as `docs/divergences.md` § "Not offered", each with its ruling:
SwiftUI's `App`/`Scene` lifecycle and every non-desktop platform (`PB-A`);
`LazyVGrid`/`LazyHGrid`/`GridItem` (`GR-L`); two-axis scrolling (`CN-M`),
`scrollPosition(id:)` (`DD-AB` items 5–6), an animated `scrollTo`/scroll
offset (`CX-I` item 2); open `ButtonStyle`/`PrimitiveButtonStyle`,
`.borderedProminent`, `.link`, `.toggleStyle`, `.pickerStyle(.menu)`, menus,
`.contextMenu` (`IX-E`, `IX-M`); `sequenced`, `@GestureState`, `GestureMask`,
a custom gesture `body`, location taps (`IX-B`); `Path`, gradients,
`StrokeStyle`, SF Symbols, colour glyphs (shapes spec §9, record §05);
elliptical corners and `UnevenRoundedRectangle` (shapes spec §9, `CX-I` item
3); `matchedGeometryEffect`, `contentTransition`, custom transitions,
`AnyTransition.animation(_:)`, `.blurReplace` (`AN-AE`); a readable
`colorScheme`, Increase Contrast, Reduce Transparency, Differentiate Without
Colour (`TE-AO` item 1, `CX-I` item 3); `Image(systemName:)` and asset images
(`TE-AL`, guard `anImageHasNoSystemNameOrAssetInitialiser`) — the last added
by lane 2.

## §2 Divergences re-read (`CX-G`, `CX-R`) — lane 2

Every row live at `1b093b8` (72), re-read against `CX-G`'s criterion. "Pin"
is the live test, each name resolved by `grep -rqE "func <name>\(" Tests`
(all resolve; the command over every name in `docs/divergences.md` prints
only four API names, `accessibilityReduceMotion`, `allowsHitTesting`,
`contentTransition`, `matchedGeometryEffect`, which are not tests). "Stale in
§04" is the name record §04's latest row for that label still carries, where
it no longer exists — the Record phase corrects those rows. "Arm" is the
probe arm the row cites (each found in its probe file by the same word-boundary
grep `closeout-inventory-check.sh` uses). Result: **6 retire** (85 by `CX-F`;
2, 35, 39, 53, 55 by `CX-R`), **66 live**, every live owner **none** except
82 (the human VoiceOver run).

| # | live pin | stale in §04 | arm | verdict | owner |
|---|---|---|---|---|---|
| 1 | unpinned — a `CAMetalLayer` property, no headless reading | — | (spec §7.8) | keep | none |
| 2 | `aGrowFactorSumBelowOneStillFillsTheLine` (the deleted concept's D pin) | `subOneScalingNeverExceedsTheRemainingFreeSpace` (deleted at 7b) | stage-7a G0 | **retire** — subject deleted (`CX-R` item 1) | — |
| 9 | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` | — | (vs CSS) | keep — no SwiftUI absolute positioning; a CSS-vs-MetalUI fact on a public spelling | none |
| 10 | `aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface`, `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll` | — | overlay-presentation P1/P2, P4/P5 | keep (design) | none |
| 13 | `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `aGrownViewportIsFilledOnTheNextFrameWithoutInput` | — | — (a MetalUI limit) | keep | none |
| 20 | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` | — | — (design) | keep | none |
| 21 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce` | — | disabled-interaction K2 | keep | none (`IX-G`) |
| 22 | `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`, `aDisabledPaneContributesNoKeyContext` | — | disabled-interaction K6 | keep | none (`IX-G`) |
| 23 | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` | — | disabled-interaction P2f/P2g | keep | none |
| 25 | `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack` | "E17" | environment-scoping H0/H1 | keep | none |
| 26 | `anUnhandledKeyEventBubblesToItsAncestorsInnermostFirst` | "—" | disabled-interaction K5 | keep | none |
| 27 | `aGestureOrTapPublishesNoPressAndAnAccessibilityActionAddsOne` | — | accessibility-part2 G1–G5, G7 | keep (narrowed by `IX-Y` item 3) | none |
| 29 | unpinned (record §04's 2026-09-15 table) | — | accessibility-bridge-rules R7 | keep | none |
| 30 | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` (arm 7) | — | bridge-critic2 C5i, C6 | keep | none |
| 31 | unpinned (record §04's 2026-09-15 table) | — | bridge arm 13 | keep | none |
| 32 | `theAppKitBridgePublishesHintIdentifierHeadingLinkAndOutline` | — | bridge-rules R16; part2 L1 | keep (amended by `IX-AA` item 3) | none |
| 33 | `anAccessibilityElementIgnoresItsChildrenByDefault` | — | bridge-rules R6; part2 T3 | keep | none |
| 34 | unpinned (record §04's 2026-09-15 table) | — | bridge arm 4 | keep | none |
| 35 | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswer` | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`; `…WhereTheLegacyFrameClamps` | frame-semantics D4 | **retire** (`CX-R` item 1) | — |
| 38 | `aNegativeFixedFrameDimensionTraps`, `aNegativeFrameMaximumTraps` | "— (task 7)" | frame-negative-sizes H6, H10 | keep | none |
| 39 | `anIdealFrameLowersAtANilProposal` | `anIdealDimensionOnTheLegacyFrameTraps` | frame-semantics C1 | **retire** (`CX-R` item 1) | — |
| 41 | `metalUIsDefaultHitRegionIsTheElementsWholeFrame` | — | content-shape H1 | keep | none |
| 42 | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | — | content-shape P1/P2 | keep | none |
| 43 | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `aClipShapesCornersStayHittableAndItsRectBoundsTheHit` | — | content-shape H6 | keep | none |
| 44 | `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt` | — | content-shape X1–X3 | keep | none |
| 46 | `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies` | — | border-clip G1/G2 | keep | none |
| 47 | `aBareCornerRadiusDoesNotClipTheChildren`, `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` | "(C3/D1 orders unpinned)" — pinned since lane 1 | border-clip C1, C3 | keep, amended (the legacy C3/D1 answer; proposal path agrees, tests 1.3/1.4) | none |
| 49 | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`, `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` | — | border-clip D2 vs M1, D1 | keep | none |
| 50 | `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt` | — | content-shape S1/S2 (record §16) | keep | none |
| 51 | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` | — | stack-algorithms S | keep | none |
| 52 | `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` | stack-algorithms S | keep (`CX-E`) | none |
| 53 | `aLoweredStackOffersItsChildItsProposal` | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | stack-algorithms A5 | **retire** (`CX-R` item 1) | — |
| 54 | `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem` | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` (table) | stack-algorithms SC2 | keep — fails (c): the legacy `ScrollView` spelling still answers its parent's cross axis | none (`DD-AB` item 5) |
| 55 | `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` | "— (covered by the CSS goldens)" | stack-algorithms G9 | **retire** (`CX-R` item 1) | — |
| 56 | `aFrameOverAMultiMemberComponentFramesEachMember`, `aMultiMemberFrameRowAlignsItsMembersByTheFramesOwnAlignment` | `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`, `chainedFramesRemainConcreteAndNestTheirLayoutNodes` (table) | composition-identity L1–L3, L5, L8 | keep | none |
| 57 | `aDrawnElementWithoutAPointerTargetDoesNotBlockAClickBeneathIt` | "unpinned" (table) | overlay-presentation H3 | keep | none |
| 58 | `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` | — | — (design) | keep | none |
| 60 | `aTextAnswersItsUnroundedWidestLineWhereSwiftUICeilsToThePixelGrid` | "unpinned" (table) | text-semantics (M1, `TE-G` item 1) | keep | none |
| 61 | `theModelsDisagreementsWithSwiftUIArePinned` | — | grid GZ2–GZ8 | keep (`CX-H`) | none |
| 62 | `theModelDisagreesWithSwiftUIOnTheDivergenceCorpus` | — | grid `divergences` mode; finite-shares O1 | keep (`CX-H`) | none |
| 63 | `gridCellColumnsZeroLaysOutAsOne` | — | (`GR-O` 3) | keep | none |
| 65 | `textRowsTakeTheDefaultRowSpacing` | — | (`GR-O` 5) | keep | none |
| 66 | `aModifierOnAMultiCellGridRowTraps` | — | (`GR-O` 6) | keep | none |
| 67 | `aColumnCountAboveInt32MaxTraps` | — | (`GR-O` 7) | keep | none |
| 68 | unpinned (`aColumnCountAboveInt32MaxTraps`' doc comment) | — | — (a limit) | keep | none |
| 70 | `aStackServesItsLeastFlexibleChildFirst` | — | grid-stack-ties T7 | keep, re-owned from "task 6" | none |
| 71 | `aClosureRunOutsideInputDispatchWritesTheLastBoundOccurrence` | — | composition-identity S5, S6 | keep | none |
| 72 | `twoSiblingsWithTheSameIDShareOneStateEntry`, `twoSiblingGroupsWithTheSameIDShareOneIdentity` | — | composition-identity X2 | keep | none |
| 73 | `aLegacyOverlayOnATwoMemberComponentTrapsNamingItsPrimaryCount`, `aLegacyBackgroundOnATwoMemberComponentTrapsNamingItsPrimaryCount` | "N1.7", "B3.3" | composition-identity G3–G6 | keep | none |
| 76 | `controlSizeReachesTheDefaultFontButNoControlsChrome` | `controlSizeReachesNoBuiltInMeasurement` | environment-control-state Z2, Z3 | keep | none |
| 77 | `layoutRoundsToWholePointsWhateverTheDisplayScale` | — | environment-control-state S4 | keep | none |
| 78 | `aBindingIsMainActorIsolated` | — | — (isolation, a compile fact) | keep | none |
| 79 | `aForEachWhoseIDsCollideInDescriptionProducesOnlyTheFirst` | — | scrollviewreader-scope S6 | keep | none |
| 80 | `aFocusedButtonActivatesOnSpaceAndOnReturnOnlyOffApple`, `tabVisitsTheControlsAndAControlItFocusedTakesItsKeys` | — | interaction F5/F6 | keep | none |
| 81 | `aMenuPickerStyleIsNotOffered` | "guard G1.2" | controls-and-selection PK0/PK1 | keep | none (`IX-M`) |
| 82 | `aPickerPublishesARadioGroupTitledByItsTitle`, `aStepperPublishesALabelledIncrementorWithTwoArrowButtons` | — | controls-and-selection (`DD-U`) | keep | the human VoiceOver run |
| 84 | `aListSizesItselfToCountTimesRowHeight` | "`List`'s existing pins" | controls-and-selection LS0 | keep | none |
| 85 | `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite` | "unpinned" | closeout O1 | **retire** (`CX-F`, lane 1) | — |
| 86 | `aNotoSansLineIsTwentyFourPointsWhereSwiftUIsIsTwentyThree` | — | text-semantics X13 | keep | none |
| 87 | `aMiddleTruncationKeepsCoreTextsStringWhereSwiftUIKeepsMore` | — | text-semantics X5 | keep | none |
| 88 | `aGridRowWithATextBaselineAlignmentTraps` | — | text-semantics X11 | keep | none |
| 89 | `aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes` (its two spacer arms) | "spec 3.23" | text-in-stacks K1, K4 | keep | none |
| 90 | `theContinuousStyleIsTheDefaultAndIsDrawnCircular` | — | shapes-and-rendering S3, C4 | keep | none |
| 91 | `clipShapeOfAnEllipseTrapsNamingDivergence91` | — | shapes-and-rendering C5 | keep | none |
| 92 | `twoCrossingRoundedClipsIntersectAsTheSquareBox` | — | shapes-and-rendering C6 | keep | none |
| 93 | `interpolationNoneIsNearestAndEveryOtherLinear` | — | shapes-and-rendering I11 | keep | none |
| 94 | `clickingAFocusableElementDoesNotFocusIt`, `aButtonIsFocusableButAClickDoesNotFocusIt` | — | interaction F3 | keep | none |
| 95 | `aRequestForAnElementOutsideTheModalIsRefused` | — | accessibility-part2 M5 | keep | none |
| 96 | `aProposalFrameReLaysItsChildAtEachIntermediateWidth` | — | transactions W1, P1, P2, X00 | keep | none |
| 97 | `aProposalFlexibleFrameAnimatesAFiniteBoundAndSnapsAnInfiniteOne` | — | transactions W7, W10 | keep | none |
| 98 | `anUnannotatedInsertionAndRemovalAreInstant` | — | transactions X0, W10 | keep | none |
| 99 | unpinned — no test asserts the shared curve | — | transactions T9, T10 | keep | none |

**Corrected on the way** (§04 wording, not verdicts): 53's stage-9 sentence
(see `CX-R` item 1); 76's pin rename; 54's table name stale since 7b (the
stage-10 section already named its live pin). The `CX-G` candidates `LR-GG`
item 5 named (35, 53, 55) all retire; 39 and 2 are additions found by the
same grep.

## §3 Items addressed to "plan task 15", disposed (`CX-I`)

Collected by `grep -rn -i -E "task 15|task-15|\(closeout\)" docs/superpowers
docs/record Sources Tests docs/verification --include='*.md' --include='*.swift'`
excluding record §19 and this task's own three files — **125 hits at lane
2's tip** (101 at `1b093b8`; the rest are lane 1's own past-tense mentions in
`Sources`/`Tests`, the checklist and the looks demo). Every hit is a citation
of one item below, a past-tense mention, or one of the inventory's
"found by plan task 15's inventory" cost paragraphs:

| item | source | disposition |
|---|---|---|
| divergence 52 (`Row`/`Column` gap) | `LR-ER` item 3, `LR-EY`; stage-8/10 specs; plan 784, 928; record §04 1185, §50, §53 | kept, owner none (`CX-E`) |
| the eight deprecated sizing modifiers, `fraction:`/`percent:` | `LR-FN` item 5; engine decisions 9617/9622 ("trap in production reachable until task 15"); plan 887; record §53 610, §55 805 | kept deprecated (`CX-C` item 1): a nonzero `fraction:` still traps by name (`LR-FO` item 1), which is what the deprecation message says |
| `flexBasis(fraction:)` | (found by the design) | deprecated (`CX-C` item 2) |
| `Box`'s inert public `style:` | `LR-FR` F5; engine decisions 9610, 9864–9896; stage-10 spec 158; record §05 457, §53 219 | narrowed to `package` (`CX-D`) |
| the `ModifiedElement` typealias | stage-11 spec 262, 751; engine decisions 10077; record §54 737 | kept, undeprecated (`CX-C` item 3); `ModifiedContent.swift:376`'s sentence re-spelled by lane 3 |
| `AXNode.actions` "until task 15 removes the field" | `IX-Y` item 4 (interaction decisions 1492) | kept deprecated (`CX-C` item 1) |
| divergence 85 (optional `@State`) | `DD-AI` (data decisions 17, 1979–2012); plan 1176; record §04 1773, §58 429 | fixed, retires (`CX-F`) |
| divergence 35 counting question (and 53, 55) | `LR-GG` item 5 (engine decisions 10815, 10840); record §04 1380, §54 839 | **35, 53, 55 retire** (`CX-R`), with 2 and 39 found by the same grep |
| divergences 61, 62, the GZ re-run | `GR-AA`, `GR-N`, `GR-O` 2 (grids decisions 671, 701, 1105, 1167, 1173, 1424); record §04 853–854, §22 | baseline holds, kept owner none (`CX-H`) |
| a grid on screen | `GR-N`, `GR-AE` (grids decisions 674, 1298; grids spec 666; plan 480; record §03 1343, §22, §23 234) | human checklist (`CX-M`) |
| per-entry memory harness; settled-store allocation count | `AN-AJ` (animation decisions 1991, 2085); transactions spec 70; record §64 258, 445, 530 | the allocation figure taken (test 1.6, record §66 §4.4); the isolated-process harness itself is not built — the figure answers what it was for (per-entry cost), owner none (`CX-I` item 1) |
| Increase Contrast, system accessibility settings | `AN-AF` (animation decisions 1658); transactions spec 71; record §64 446, 533 | R row (`CX-I` item 3) |
| animated `scrollTo` | transactions spec 73; record §64 448, 535 | R row |
| guards only under `--build-system native` | transactions spec 77; record §64 452, 468, 539 | fixed (`CX-J`) |
| `switch` transitions unpinned | record §64 §14 | probe SW1, test 1.5 (`CX-I` item 2) |
| two-axis scrolling, divergence 54 | `DD-AB` item 5 (data decisions 1399, 1564) | R row / D row kept, owner none (`CX-R` item 2) |
| `colorScheme` | `TE-AO` item 1 (text-semantics decisions 1763) | R row |
| the inventory catching missed items | `IX-AD` (interaction decisions 1336), `TE-A` (text-semantics decisions 95, 1418) cost paragraphs | §1 and the check (`CX-A`); neither table's rows surfaced an unmapped declaration |
| elliptical corners, `UnevenRoundedRectangle` | shapes spec §9 table (513) | R row (`CX-I` item 3, `CX-P` item 6) |
| `ModifiedElement`'s "fate is plan task 15's" doc sentence | `ModifiedContent.swift:376` | `CX-C` item 3; lane 3 re-spells (the only future-tense hit left in `Sources`/`Tests`) |
| divergences 61/62 "Owner: plan task 15's closeout" doc comment | `NativeGridTests.swift` | `CX-H`; lane 1 re-spelled (now past tense, line 2616) |
| `flexBasis(percent:)`'s `renamed:` to a now-deprecated name | `Box.swift` | `message:` instead (`CX-P` item 7) |
| a ghost's paint order; two stacked transitions; `.id` outside `.transition`; divergence 99's gap | record §64 540–551 | already owner none there; 99 is a live row (unpinned, `docs/divergences.md`) |

**The older milestones' "Carried…" sections** (`CX-I` item 6), each re-read:

| doc (section) | item | disposition |
|---|---|---|
| m0 (Carried into M1) | gate the ABI probe on an env var; a tracked shader header; a blend-readback pixel-format guard | the guard exists (`compositingIsGammaEncodedNotLinear`, `drawableFormatIsGammaEncodedNotSRGB`); the header symlink is still untracked — `CLAUDE.md`'s `swift package clean` hazard names it; the ABI probe's device skip is a CI hazard already recorded (record §08). No new owner |
| m1a (Carried to the first CI setup; known-unproven guards) | the ABI probe skips without Metal; `committedGoldensMatchTheBrowser` the only live-WebKit consumer | the goldens and that test are deleted (stage 7a, `CX-N`); the ABI skip as above |
| alignment, box model, flex sizing, wrapping (Carried risk) | four re-derivations of `isRow`/gap; `ResolveFlexibleLengths`' gap arithmetic; `distributeMainAxis`' dead guard; the justify-between golden; content cross sizing; the automatic minimum; percentage root width; BM-4; `margin: auto`; FS-9/AL-4; `LayoutNodeID` generation | every subject is the CSS engine or a golden, deleted at stages 7a/9 (`LR-DS`, `LR-FC`); `margin: auto` stays record §05's row (unreachable outside the package since `LR-FM`); `LayoutNodeID` has had a `generation` since `C-3` (`LayoutTreeTests`' generation traps) |
| content sizing (Carried risk) | §9.9.1's growth rule under intrinsic sizing | the CSS engine is deleted (stage 9) |
| element pipeline (Carried into the next milestone; Carried risk) | structural identity; an `auto` cross size; guards skipping silently; no border drawable; `LayoutTree.reset` uncalled; no builder-made `AnyElement`; a default blinding a test | identity is structural since `SI-`/task 8; borders are drawn (`OM-`); guards fixed by `CX-J`; `reset`'s row stays record §05's; `AnyElement` is still hand-written only (its row deleted at task 8, `ID-E`); the default-blinding shape is a practice (`docs/practices/`), not an item |
| frame sizing (Carried into this task, and where each went) | its own table, every row landed at the time; "port sizing as layers" went to task 7 | stage 8 (`LR-ER`): deprecated toward `.frame`; tasks 4/5 below |
| animation (Carried forward) | `AN-B`, `AN-C` (keep), `AN-D` (a second window), `AN-U` (a hover fade), `AN-V` (guards), overshoot and reverse unobserved | `AN-B`/`AN-C` are standing rules; hover and focus fade through the colour path since task 13 (`hoverAndFocusFadeThroughTheSameEffectiveColourPath`); a second window's animation is still `AN-D`'s named narrowing, owner none; `AN-V` fixed by `CX-J`; overshoot/reverse is a human check (`docs/verification/human-checks.md`, group M) |

None is open with an owner after this table.

### §3.1 The three public documents (`CX-L`, `CX-G` item 2)

- **`docs/divergences.md`** — the 66 live rows (label, what differs, SwiftUI's
  answer, MetalUI's, ruling, pin, owner), the retired list, the documented
  absences and what the list does not cover. Its "Live" table is what the
  inventory check reads.
- **`docs/migration.md`** — part 1 maps the legacy spellings onto the
  SwiftUI vocabulary (containers, the eight sizing modifiers by `LR-ES`'s
  recipe, modifiers; "migrate inside-out", since a proposal container takes
  only proposal content); part 2 lists every source and behaviour change
  since 2026-09-12 with old spelling, new spelling and ruling, `CX-C`/`CX-D`/
  `CX-F` included. Collected by `grep -rn -i -E "migration note|\*\*migration|migration:\*\*|Migration\*\*" docs/superpowers --include='*.md'`
  (27 hits outside this task's own files: `ID-B`, `ID-C`, `DD-C` item 4, `IX-I`, `TE-K` item 1, `TE-AQ`
  item 2, `TE-C`, `AN-AD` item 7 and their cross-references) and by the
  removals records §50–§54 list (`EV-N`/`DD-D` item 6, `LR-FM`, `LR-FF`,
  `LR-FD`, `LR-FV`, `OM-M`, `CN-O`), plus the `@available(*, deprecated`
  declarations (`grep -rn -A3 "@available(\*, deprecated" Sources`) for the
  deprecated table.
- **`docs/api-overview.md`** — the public surface by area, each with its
  inventory class and divergence labels.

**Checks** (all run at lane 2's tip): every backticked test-shaped name in
the four documents (`docs/divergences.md`, `docs/migration.md`,
`docs/api-overview.md`, this record) resolves by `grep -rqE "func <name>\("
Tests`, except API names (`accessibilityReduceMotion`,
`matchedGeometryEffect`, `onAccessibilityRequest`, …) and the stale or
deleted names §2 and §3 list on purpose; every ruling id resolves in
`docs/superpowers/` except `EV-ZZ`, mutation K8's deliberate misspelling.

## §4 Lane 1 — code

Commits on `feat/closeout`: `a3a8915` (red first: tests, guards, T1, probe
group SW), `5e58aa7` (implementation, CI, checklist), and this record's commit.

### §4.1 Baseline and probe

- **Baseline re-taken before the first change** (`1b093b8`, native, after the
  design commits): `Test run with 1961 tests in 3 suites passed after 106.617
  seconds`, the FR-J line present, the one `warning:` SwiftPM's deprecation
  notice.
- **Probe group SW** (`docs/probes/swiftui-closeout.swift`, `CX-I` item 2),
  run compiled twice, byte-identical, 2026-09-30 23:58 PDT, screen unlocked
  (lock probe: no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`):
  SW0 (`if`/`else`, `.move(edge: .leading)`, under `withAnimation(A)`) records
  `[-50, 0, 0, 0]` and `[50, 0, 0, 0]`; **SW1 (a three-case `switch`) records the
  same two lines**; SW1n (no transaction) `(nothing animated)`. Group O re-read
  exactly as committed by the critic round (O0 2, O1n nil, O1 2, O2 nil).

### §4.2 Tests (10 added, 1 inverted)

| # | test | red first? | reading |
|---|---|---|---|
| 1.1 | `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite` | **red** at `1b093b8`: `reads.layout → [nil, nil]`, `reads.binding → [nil, nil]` (CloseoutTests.swift:75, :76) | green after `CX-F` |
| 1.2 | `aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue` | green before and after (separating arm) | |
| 1.3 | `aBackgroundWrittenAfterCornerRadiusIsSquare` | **green on arrival** — no stop owed (`CX-P` item 2) | the proposal background is square (radii 0, mask radii 0), the content's mask 12 — C3 |
| 1.4 | `aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill` | **green on arrival** | the band square, the fill's mask 12 — D1 |
| 1.3L | `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` | pin | one rect, radii 12, either order (wrong on purpose against C3; row 47) |
| 1.4L | `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` | pin | band and fill radii 12 (wrong on purpose against D1; divergence 49) |
| 1.5 | `aSwitchBranchTransitionsAsAnIfElseBranchDoes` | pin | both arms: ghost −25, inserted −25 half-way under `linear(1)`, landed 0 ghosts; control: no ghost, inserted at 0 |
| 1.6 | `measureSettledStoreEntryAllocations` (gated) | a figure | §4.4 |
| G1 | `aPlainImportCannotPassBoxAStyle` | **red** at `1b093b8`: all four `style:` calls compiled (`!result.succeeded`, CloseoutCompileGuards.swift:55, 4 issues) | |
| G2 | `theTypecheckGuardsRanWhereTheyAreRequired` | **red** under the default build system with `METALUI_REQUIRE_GUARDS=1` (a `git archive` of `a3a8915`: "no .build/<triple>/debug/Modules holding MetalUI was found under …/g2/.build"; G1 skipped beside it); green under native | |
| T1 | `theFractionAndPercentSizingModifiersAreAllDeprecated` (was `thePercentSizingModifiersAreDeprecatedRenamesOfFraction`) | **red** at `1b093b8`, 4 issues (ContainerCompileGuards.swift:140, :142, :153, :169) | inverted by `CX-C` |

`goldensUnchanged`: no `@Test` removed; one renamed with its answer inverted
by ruling (T1, `CX-C`); every other retained test's answer unchanged (the two
`flexBasis(fraction:)` callers moved — `ModifierTests`' row into the class-D
witness `DeprecatedFlexBasisCase`, byte-identical row; `LoweringItemTests`'
report arm to `cssFlexBasis(fraction:)`, the modifier's closure body verbatim,
pinned by that arm itself: a helper writing nothing would report nothing).

### §4.3 Mutations (committed tree `5e58aa7`, restored from a copy, full unfiltered suite of 1971, `git status --short` empty after each)

| id | file | mutation | reddened (issues) |
|---|---|---|---|
| M1a | `StateTable.swift` | `peek` back to `storage[id]?.value as? S` | `anOptionalStateWithANonNilInitialValueReadsItBeforeItsFirstWrite` (2) — alone |
| M1b | `StateTable.swift` | `peek` treats a stored `Optional.none` as absent (`Mirror` check) | `aNilWrittenToAnOptionalStateReadsNilNotItsInitialValue` (2) — alone |
| M1c | `ModifiedContent.swift` | the proposal `.background` fill wrapped in a 12-point rounded clip | `aBackgroundWrittenAfterCornerRadiusIsSquare` (1) — alone (no other test read a proposal background's mask) |
| M1d | `ModifiedContent.swift` | the proposal `.border` band's radii 12 instead of its own | `aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill` (1), `nativeBorderPaintsOverContentWithoutChangingItsFrame` (1) |
| M1cL | `AnimatedColor.swift` (`paintDecorationBody`) | the legacy fill's radii 0 | `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration` (1), `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` (1), `aBareCornerRadiusDoesNotClipTheChildren` (1), `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority` (1), `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority` (1), `aScaleTransitionScalesCornerRadiiAndBorderWidths` (1), `cornerRadiusReachesTheSceneThroughTheModifier` (2), `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority` (1), `theDemoFrameMatchesTheValuesRecordedOnMacOS` (2) — 11 issues |
| M1dL | `AnimatedColor.swift` (`paintDecorationBody`) | the legacy border band's radii 0 | `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` (1), `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` (2) |
| M1e | `ElementGroup.swift`, the **untyped** `EitherGroup.requestGroupLayout`, `.second` case only | `noteEither` skipped when `branchIndex == 0` — scoped so the test's `if`/`else` (at cursor 1 in its `Stack`) is untouched and only the `switch`'s nested `Either` (cursor 0 under the outer branch) loses its record | `aSwitchBranchTransitionsAsAnIfElseBranchDoes` (2), `everyConditionalSiteRecordsItsTransaction` (1, its legacy `Column { if on … else … }` sits at cursor 0) |
| MG1 | `Box.swift` | `init(style:decoration:content:)` back to `public` | `aPlainImportCannotPassBoxAStyle` (1, the `content:` arm) |
| MG2 | `CloseoutCompileGuards.swift`, in the `git archive` copy under the default build system | `guard false else { return }` (ignore the variable) | G2 **green** under default-with-env — the instrument proof (`CX-J`) |
| MT1 | `Box.swift` | `flexBasis(fraction:)`'s `@available` deleted | `theFractionAndPercentSizingModifiersAreAllDeprecated` (3) |

### §4.4 Measurements

- **`fraction: 0`** (`CX-C` item 2 asked lane 1 to word the message by it),
  through `LayoutDifferential.render` with diagnostics on, a throwaway test
  not committed: `Row { Box().height(10).flexGrow(1).flexBasis(fraction: 0); … }`
  reports `[]` (an unsized grower's zero basis lowers as `auto`, `LR-AB`);
  without grow, or on a sized grower, it reports `[box.flexBasis]`; `0.5` on an
  unsized grower `[box.flexBasis]`. The deprecation message says exactly that.
- **1.6, the settled-frame allocation figure** (`CX-I` item 1, record §64
  §11), `METALUI_STORE_ALLOC_MEASURE=1 swift test --build-system native
  --no-parallel --filter measureSettledStoreEntryAllocations`, debug arm64,
  two runs identical. Three settled frames at 920×560 after three warm ones,
  one `StateTable`/`AnimationStore`/`ShapingCache`/atlas:

  | tree | allocations | requested bytes | store entries |
  |---|---|---|---|
  | proposal preview | 18,363 | 1,658,448 | 12 |
  | legacy demo | 82,121 | 9,104,975 | 0 |
  | 40 × `Rectangle(4×4).frame(4×4)` | 13,107 | 951,606 | 40 |
  | 80 × the same | 25,881 | 1,895,046 | 80 |
  | 40 bare rectangles | 9,612 | 718,326 | 0 |
  | 80 bare rectangles | 18,906 | 1,428,582 | 0 |

  Per element per settled frame: framed 106.45 allocations / 7,862 bytes,
  bare 77.45 / 5,919, so **one settled `.frame` layer, its store entry's
  touch included, adds 29 allocations / ~1.9 KB of transient requests per
  frame** — the layer's whole per-frame work, not the store alone, and
  churn, not retained footprint. Written into `AnimatedStyle.swift` in place
  of "re-owned to plan task 15".

### §4.5 Must-hold checks

- **Suite**: after `swift package clean`, `swift build --build-system native
  --build-tests` (0 `error:`, the one SwiftPM deprecation `warning:`) then
  `swift test --build-system native --no-parallel`: **`Test run with 1971
  tests in 3 suites passed after 105.813 seconds`**, FR-J line present.
  Guards **121** (119 + G1 + G2). Goldens 0.
- **Default build system**: a `git archive` of `5e58aa7`, `swift build
  --build-tests`: exit 0, **0 `warning:`, 0 `error:`**.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> 1b093b8 5e58aa7`:
  **0 differing, scene identical, in all fourteen**. Controls at `1b093b8`
  all non-zero where they must be (light vs dark 1 048 576; default vs modal
  1 031 003; default vs animation 454 895; f0 vs f3 0; preview 1 048 576;
  chrome pair 0; distinct 544/216; prod default vs modal 491 221; distinct
  prod 529; indicator rects 0) — the modal and animation controls read above
  the script header's stage-4 figures (1 030 498, 210 027), a drift of the base
  commit's own images since stage 4 (task 11 part 1's paragraph, task 13), not
  a property of this comparison, which is base against head.
- `Expected.swift` unedited; `theDemoFrameMatchesTheValuesRecordedOnMacOS`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
  `theSevenRetentionSlotsAreMutuallyDistinct` green (unedited).
  `MetalUILayout` imports only `MetalUICore`.
- `peek`'s other callers re-read at the tip: `AnimatedColorState`,
  `FocusStateValue<Value>`, `ListOrigin`, `AXNode`, `Bool`,
  `AnimatedElementState` — none optional, so none can change.
  `StateTable.withState` had the same `as? S ?? initial()` shape; this
  bullet first called it "latent, no caller passes an optional `S`" — **wrong**:
  it is public through `LayoutPass`/`PrepaintPass`/`PaintPass.withState`.
  Fixed in the fix round (§4.7, `CX-Q` item 1).
- **No `Box(style:` in a typecheck fixture string, and none in
  `Backends/SDL`, `Tests/PortableTests` or `Experiments`** (re-grepped at the
  tip), so the `package` narrowing reaches no other package.
- **"Plan task 15" as a future owner** in lane 1's files: re-spelled in
  `AnimatedStyle.swift`, `DecorationCompileGuards.swift` and
  `NativeGridTests.swift`; `grep -rn "task 15" Sources Tests` leaves one
  future-tense hit, `ModifiedContent.swift:376`, lane 3's file (`CX-P` item 6).
- **CI** (`CX-J`): `.github/workflows/swift.yml`'s macOS job now builds with
  `--build-system native --build-tests` and tests with
  `METALUI_REQUIRE_GUARDS=1 … --build-system native --no-parallel`. Checked
  locally exactly as CI will run it: **`Test run with 1971 tests in 3 suites
  passed after 105.024 seconds`**, G2 passed, the FR-J line present. The
  workflow itself is owed to CI on push.
- **`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit`, AccessKit fetched by
  its script): builds; **22 + 33** passed, unmoved from task 13. Its
  pre-existing `warning:`s (an unneeded `try`, `ld`'s SDL3 dylib version) are
  that package's, untouched here.
- **No `swift:6.4-noble` run**: Docker is not available on this machine
  (`docker info` fails). Nothing lane 1 changed is in a portable test target
  (`CloseoutTests`/`CloseoutCompileGuards` are `MetalUITests`); the portable
  `MetalUI` sources it touched (`Box.swift`, `State.swift`, `StateTable.swift`)
  are owed to the Linux and Windows CI jobs on push.
- **Real-window capture not taken by lane 1**: the lock probe read unlocked at
  23:57 PDT (the probe run) but **locked** at 00:36 PDT when lane 1 reached it
  (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`); the offscreen
  fourteen stand in (0 px). The Record phase re-runs the probe.

### §4.6 The human checklist

`docs/verification/human-checks.md` (`CX-M` item 1, moved to lane 1 by
`CX-P` item 9), built from `grep -n "^## " docs/record/03-verified-on-real-hardware.md`
(every dated section, stage 6b through task 13), `grep -n -i -E
"open|owed|unobserved|nobody has" docs/record/03-verified-on-real-hardware.md`,
and record §19's frozen "Human verification" table (every row not closed).
Groups A (real-window capture) through M (older milestone rows), each item
citing its source; the VoiceOver script is linked as L1, not copied. Not run:
an agent cannot.

### §4.7 Fix round (`CX-Q`, commit `01afd16`)

The verifier's four findings, each fixed red-first or pinned and mutated:

| Finding | Fix | Test | Mutation → reddened (full unfiltered suite of 1974) |
|---|---|---|---|
| major: `Box(decoration:)` unpinned (V-BOXDEC/V-BOXDECB green at 1971) | painted pin, both forms, with and without content, against the `package` `Box(style: Style(), …)` | `thePublicBoxDecorationInitialisersPaintWhatTheStyleInitialiserPaints` (green on arrival — the code was right) | V-BOXDEC (plain form forwards `Decoration()`) → that test alone; V-BOXDECB (builder form) → that test alone |
| major: H1, I1, J1, K1–K3 had nothing to run | looks demo, `METALUI_LOOKS_DEMO=1` (`CX-Q` item 3); checklist items reference it | `theLooksDemoDrawsEverySurfaceItsHumanChecksName` (2 ellipses, 4 images, depth 11, a press inserts the opacity tile); `everyProductionTreeBuildsOnAOneMegabyteThread` builds it | V-LOOKS (drop the ellipse stroke band) → that test alone |
| minor: `flexBasis(percent:)`'s body copy unpinned | its own class-D row, 51 → 52 cases | `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` | V-PERCENT (`percent * 2`) → that test alone |
| minor: `withState` over an optional `S` (§4.5's "latent" was wrong) | absent vs stored by lookup (`CX-Q` item 1) | `thePublicWithStateHandsAnOptionalStateItsInitialValueOnFirstAccess` (red first: `[nil, nil]`) | V-WITHSTATE (restore the old line) → that test alone |

`git status --short` empty after each mutation. Counts: **`Test run with 1974
tests in 3 suites passed after 104.227 seconds`** (1971 + 3; the FR-J line
present); guards 121, unmoved; 0 `warning:`/`error:` under the default build
system (`swift build --build-tests`), only SwiftPM's deprecation notice under
native. **0 px against `1b093b8` in all fourteen offscreen images**, every
scene identical (`docs/probes/demo-pixels/compare.sh … 1b093b8 01afd16`).
`Expected.swift` unedited. Not re-taken: `Backends/SDL` (no file it builds
changed), a `swift:6.4-noble` container (no Docker); `LooksDemo.swift` is in
the portable `MetalUIDemoContent` target, owed to Linux/Windows CI on push.

## §5 Tasks 4 and 5, clause by clause (`CX-B`) — lane 2

Every test name below resolves by `grep -rqE "func <name>\(" Tests`, every
ruling id is a `## <id>` heading in `docs/superpowers/`, and every file
exists (checked at lane 2's tip; the command and its empty output are the
evidence). **Both boxes can be ticked by the Record phase**, each with a
dated note citing `CX-B` and this section.

### Task 4 — "Finish frame and sizing semantics"

| clause (plan text) | holds? | evidence |
|---|---|---|
| *Specify and implement `.frame(width:height:alignment:)`, optional axes, min/ideal/max constraints, alignment within an offered proposal, and the ordering rules for chained frames.* | yes | spec `specs/2026-09-15-frame-sizing-design.md`; `FR-A`…`FR-V` (record §14); kernel: `aNativeFrameClampsItsProposalAndResponseToMinimumAndMaximum`, `aNativeFrameUsesIdealDimensionsOnlyForUnspecifiedAxes`, `chainedNativeFramesPreserveTheirDeclarationOrder`; legacy spelling: `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`, `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`, `aLoweredFixedFrameLayerPlacesAFixedChildAtEachAlignment` (renamed at stage 9 from `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild`; the oversized child overflows both axes, `CN-N`, record §49 row 198). The legacy `ideal` that trapped (divergence 39, `FR-D`) lowers since stage 9 — `anIdealFrameLowersAtANilProposal`; 39 retires (`CX-R`) |
| *Move `width`, `height`, min/max sizing and alignment-facing convenience APIs onto that representation; deprecate APIs whose observable meaning cannot match SwiftUI.* | yes | stage 8, `FR-I` as amended by `LR-ER`…`LR-FB` (record §50): the eight `StyledElement` sizing modifiers deprecated toward `.frame` (guard `theSizingModifiersAreDeprecatedTowardFrame`), every in-repo caller converted by `LR-ES`'s recipe; `frame()` deprecated (`FR-J`, `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths`); every `fraction:`/`percent:` spelling deprecated (`CX-C`, `theFractionAndPercentSizingModifiersAreAllDeprecated`). The "alignment-facing conveniences" (`.alignItems`, `.alignSelf`, `.justifyContent`) are the CSS item/container fields: they lower onto the kernel's alignments and stacks, and every case that cannot be lowered is a permanent refusal by name (`LR-FO`) — no spelling silently answers differently, so the clause's deprecation test ("cannot match") does not reach them; they are inventory family `css-item-fields` (M) |
| *The additive `.frame(width:height:)` API exists; this task makes it the single semantic path.* | yes | stage 9 deleted the CSS engine (`LR-FC`, record §51): a legacy `.frame` lowers in `FrameLayer.swift` onto the kernel frame, the only layout path; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` pins the absence (`LR-FP`) |
| the progress note's "also open": a greedy finite maximum, a single-axis infinite maximum, an overflowing oversized child on the legacy path | closed | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswer` (both arms: `.frame(minWidth: 40, maxWidth: 80)` answers 80, `.frame(maxWidth: .infinity)` alone fills; renamed at stage 9 from `…WhereTheLegacyFrameClamps`); the overflow as in row 1 (`CN-N`); confirmed by stage 11's branch check (`LR-GG` item 5); divergence 35 retires (`CX-R`) |
| the `percent:` unit; `ideal` on the legacy path; the release-window captures | closed | `fraction:` (`CN-O`), deprecated (`CX-C`); `ideal` as row 1; captures taken 2026-09-17, 0 differing (record §03) |

### Task 5 — "Finish outer modifiers and modifier order"

| clause (plan text) | holds? | evidence |
|---|---|---|
| *Complete the padding migration* | yes | `OM-D`, `OM-E` (record §15); `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` |
| *then audit background, overlay, border, corner/clip shape, opacity, hit testing, focus drawing and content shape* | yes | the audit (spec `specs/2026-09-15-outer-modifiers-design.md` §3.1; `OM-A`…`OM-AM`); the gaps the note named are filled — legacy `.overlay` (`LR-FX`, `aLegacyOverlayConsumesItsPrimarysAndOverlaysRecordsAsAFrameLayerDoes`), `.background(alignment:content:)` (`ID-J`, `aLegacyBackgroundLowersBothSidesAsAFrameLayerDoes`), clip shapes (`TE-AJ`, `clipShapeClipsToTheShapesGeometry`, `aLegacyClipShapeClipsItsChildrenAndItsHitboxes`), `contentShape<S: Shape>` (`IX-L`, `aCircularContentShapeRefusesTheCornerAndTakesTheCentre`), opacity's write order (`LR-FW`, `aBackgroundOrBorderWrittenAfterOpacityEscapesIt`), the focus ring (`aFocusRingOutranksAHoverBorderAndABorder`) |
| *Pin whether each wraps, distributes through a `Component`, or affects only paint* | yes | the column the note called "never collected" is collected: `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority` (`OuterModifierMatrixTests`; the stage-7b re-spelling of the retired legacy-column test, record §49 row 244); `Component` distribution: `aComponentsWidthFramesEachMember`, `theOrderOfAComponentsDistributingModifiersIsObservable` |
| *Test order-sensitive chains such as padding/background/frame/clip* | yes | padding/background (`aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`), frame/background (`aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes`), hit testing across layers (`aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`), `contentShape` across a wrapper (`aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`); the two the note named as untested, border-clip **C3** and **D1**, are pinned by lane 1 on both paths: `aBackgroundWrittenAfterCornerRadiusIsSquare`, `aBorderWrittenAfterCornerRadiusIsSquareOverARoundedFill` (proposal, SwiftUI's answer), `aLegacyBackgroundWrittenAfterCornerRadiusIsRoundedOnOneDecoration`, `aLegacyBorderWrittenAfterCornerRadiusFollowsTheArc` (legacy, divergences 47 and 49), each mutated (record §66 §4.3, M1c/M1d/M1cL/M1dL) |
| the note's "beyond the task's text": the focus ring's look; the release-window captures | not a clause | the look is a human check (`docs/verification/human-checks.md`, `CX-M`), the reading `AN-AG` made for task 13; the captures were taken 2026-09-17 |

### §5.1 Lane 2's tip checks

Lane 2 touched no `Sources/` or `Tests/` file (`git diff 0887a12 aac9fd9 --stat`
lists only `docs/`). At `aac9fd9`: `swift build --build-system native
--build-tests` — 0 `error:`, the one SwiftPM deprecation `warning:`; `swift
test --build-system native --no-parallel` — **`Test run with 1974 tests in 3
suites passed after 105.398 seconds`**, the FR-J line present (unmoved from
lane 1's fix round); `docs/probes/demo-pixels/compare.sh <scratch> 1b093b8
aac9fd9` — **0 differing, scene identical, in all fourteen**, controls as
lane 1 read them (light vs dark 1 048 576, default vs animation 454 895, prod
default vs modal 491 221, indicator rects 0); `closeout-inventory-check.sh`
prints nothing.

## §6 Lane 3 — doc comments and the human checklist

(The checklist moved to lane 1, `CX-P` item 9; it is §4.6.)

**Red.** `docs/probes/closeout-undocumented.sh` at lane 2's tip `f4c4aae`
printed **578** rows across 87 `Sources/` files — the design's 592 at
`1b093b8` less 14; no row fell in lane 1's four files (`Box.swift`,
`State.swift`, `StateTable.swift`, `AnimatedStyle.swift`) or its new
`LooksDemo.swift`, so lane 3's file set (`CX-O`) was the whole list. No Swift
test was added: the probe is the instrument, committed at design, and its
exit criterion is an empty print (`CX-K`).

**Work** (commit `82bde75`, 87 files, 703 insertions, 2 deletions (the two
are the re-spelled `ModifiedContent.swift` sentence)). Each comment says what the declaration does and,
where it makes a claim, cites the ruling or divergence label it rests on
(e.g. `Row`/`Column`'s `gap` default names divergence 52 and `CX-E`;
`Image.interpolation(_:)` names divergence 93 and `TE-AL`; `Grid`'s row
alignment names divergence 88; `Picker`'s automatic style names divergence
81 and `DD-V`; `List`'s initialiser names divergence 84;
`AccessibilityTraits.isModal` names `IX-X` and divergence 95;
`.updatesFrequently` names record §05). Three draft comments were corrected
against the source before the commit: `KeyBinding.init` (a malformed spelling
never matches; it does not trap), `App.run()` (no claim about when AppKit
returns), and `AccessibilityTree.init` (its fourth argument is the focused
node, not children); `Toggle` is a checkbox (`DD-S`), not a switch.
`ModifiedContent.swift`'s "its fate is plan task 15's" sentence on
`ModifiedElement` now reads as `CX-C` item 3 (undeprecated by ruling: a
spelling with no behaviour, whose deprecation would warn at every
annotation) — `CX-P` item 6. `grep -rn "task 15" Sources` afterwards finds
only lane 1's comments naming `CX-C`/`CX-D`/`CX-F`/`CX-M` and this one; none
names plan task 15 as a future owner. The `InputEvent` enum's `//`-comment
"Reserved: focusMove (tvOS), spatial (visionOS)" is left untouched: the
comment-only filter admits `///` lines alone, and the reservation is history
under `PB-A`, not a doc comment — the Record phase may re-spell it.

**Checks** at `82bde75`:

- `docs/probes/closeout-undocumented.sh` prints **nothing** (0 rows).
- `git diff f4c4aae 82bde75 -- Sources | grep -E '^[-+]' | grep -vE
  '^(\+\+\+|---)' | grep -vE '^[-+]\s*///'` prints **nothing**:
  comment-only. No added line contains `public`, so the census
  (`closeout-public-api.sh`, 1872 rows) is unmoved by lane 3 apart from line
  numbers; `closeout-inventory-check.sh` prints nothing.
- `swift build --build-system native --build-tests`: 0 `error:`, the one
  SwiftPM deprecation `warning:`; `swift build --build-tests` (default build
  system): 0 `error:`, 0 `warning:`.
- `swift test --build-system native --no-parallel`, unfiltered: **`Test run
  with 1976 tests in 3 suites passed after 104.957 seconds`**, the FR-J line
  present — unmoved from lane 2's fix round (the spec's "1971" is lane 1's
  pre-fix-round figure; `CX-Q` +3, `CX-S` +2). `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`,
  `everyProductionTreeBuildsOnAOneMegabyteThread` and
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` green; `Expected.swift`
  unedited against `1b093b8`; `MetalUILayout` imports only `MetalUICore`.
- `docs/probes/demo-pixels/compare.sh <scratch> 1b093b8 82bde75`: **0
  differing, scene identical, in all fourteen**; controls light vs dark
  1 048 576, default vs modal 1 031 003, default vs animation 454 895, prod
  default vs modal 491 221, chrome legacy vs proposal 0, indicator rects 0.

**Deferred.** None of lane 3's own. The recorded census
`docs/probes/closeout-public-api.tsv` still carries `1b093b8`'s line numbers
(its header says to re-run and diff); re-recording it is the Record phase's
choice, since every lane after the design moved lines.

## §7 Record phase close

(To be written.)
