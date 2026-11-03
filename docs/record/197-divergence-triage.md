<!-- Record 197. Published 2026-11-02 from the read-only triage below, unedited. Its "verified" is the weak standard its first paragraph defines: no test was run, and the size estimates are unprobed. Order and batches live in Tasks.md (R4-1...R4-7). -->

# MetalUI divergence triage (208 live rows)

Read-only triage of `docs/divergences.md` `## Live` at master df88eec4 (worktree `divergence-triage`). Question: are the divergences something to fix?

**Verification standard.** *verified* = for that row I read the cited ruling and/or source, or an SDL3 header (`/opt/homebrew/Cellar/sdl3/3.4.18/include/SDL3`), and the pin test it names exists in the tree (function found by grep at the `file:line` in the table; tests were not run). *unverified* = pin existence and the row's own text only; used for fixable-gaps outside the top 25 (as instructed) and for a few rows with no pin and no source read. Pin existence is weaker than a run: CLAUDE.md records the suite green at b83efde2, and merges since then (PRs through #191) were not re-run here.

## 1. Summary

| class | rows | verified | unverified |
|---|---|---|---|
| platform-limit | 18 | 18 | 0 |
| design-choice | 103 | 101 | 2 |
| fixable-gap | 87 | 31 | 56 |
| stale | 0 | 0 | 0 |
| **total** | **208** | **150** | **58** |

Check by script: classes sum to 208 = 208 live rows (`## Live` to `## Retired`, rows matching `| <number> |`); label set equals the live label set exactly (asserted in the generator, no duplicates). Verified + unverified = 150+58 = 208.

**Stale: none fully.** Two partial findings, both in section 4: row 208's right-to-left clause, and a source comment contradicting row 295. The header count of 208 matches the table (the row-count line in `docs/divergences.md:4` is right).

**Depth caveat.** Of the 103 design-choice rows, 28 have 'read' in their evidence (I opened the ruling text); the other 75 are marked verified on the weaker basis that the cited pin exists and the ruling id's heading exists in `docs/superpowers/`, with the reason taken from the row. All 18 platform-limit rows rest on a header, source or probe citation; 465 (SDL cursor hot spot) rests on the row's own wording plus the `SDL_mouse.h` parameter docs, not a run.

## 2. Recommendation

- **Mostly leave alone.** 121 of 208 rows (18 platform-limit + 103 design-choice) are measured, pinned, and either forced by SDL3/the toolchain or ruled with a reason that still holds (legacy CSS vocabulary, additive MetalUI-only fields, theme/cross-platform uniformity, virtualized lists). Do not spend effort on them; the 18 platform limits are real (SDL3 3.4.18 headers have no outgoing drag, drop types, wheel phase, subtitle, closable flag, menu bar or combined folder/file dialog).
- **Fix a short list, about 40 rows in 6 batches.** The rest of the 87 fixable-gaps are mostly small, rare, or loud (compile error or trap), so they can wait until an app asks.
- **Batch 1 (silent wrong results, small, do first):** 295 (empty `Text` one line tall; a stale comment already claims it is 0x0), 81 (automatic `Picker` should be the pop-up menu), 125 (`@State` default kept from the first evaluation; needs its own ruling because LC-S said "must not move"), 1 (layer colour space), 885, 154.
- **Batch 2 (layout parity):** 51/65/89 font-derived stack and grid spacing (needs a spacing-preference mechanism in `MetalUILayout`, a probe and a decisions doc).
- **Batch 3 (animation):** 98 default cross-fade with 898/897, then 169/947 `Animatable`, then 828 glass morph (unblocked by `matchedGeometryEffect`).
- **Batch 4 (text and focus):** 150 clickable links, 186 initial focus, 94 click-to-focus, 119 hierarchical styles.
- **Batch 5 (L, renderer):** 205 offscreen group compositing, shared with 167/248/1066; then 975 gradient text, 106/109 text under scale, 90/91/92 shader work.
- **Batch 6 (lazy/viewport root):** 13, 124, 636, 638 share one cause (viewport unknown at build). Only worth it if apps hit it; 100k-row work is already pinned.
- **Leave alone on purpose:** 21-23, 41-44, 57, 114, 141 (hitbox model), 61-70 (Grid reference model), 80, 95, 103, 110-113, 116-118, 121-122, 145-147 and everything additive (27, 140, 235, 236, 735).
- Human checks (not runnable by an agent) would have to confirm: 81, 82, 885, 1025/1026 (LB), 165, 825/826 (LG), 977 (SS), 315 (MT-1), 325 (IM-1), 206 (HSplitView look), 1045 (LD), 112, 1076/1078/1079 (AD).

## 3. Ranked fixable gaps

Ranked by value to a SwiftUI-knowing app author: frequency of the hit times severity (silent wrong layout/state/paint above dropped input above cosmetic above compile error/trap). Size: S under a day, M a milestone with probe and decisions doc, L cross-backend or shader work. Rank 1-25 are verified; later fixable-gaps are in section 5 and mostly unverified.

| rank | label(s) | gap | failure mode | size | grouping / dependency | verified | evidence |
|---|---|---|---|---|---|---|---|
| 1 | 125 | `@State` default re-seeded every build until written; reference/impure defaults (`@State var m = Model()`, `UUID()`) give new instances | silent state loss / onAppear and onDisappear see different instances | M | state retention (LC-S, TB-AH, ID-C) | V | LC-S read ("not done; MUST NOT MOVE"); pin LC 5.5/5.6; needs a ruling of its own |
| 2 | 51, 65, 89 | stack/grid default spacing is a constant 8; SwiftUI is font-derived beside Text (text-to-text 0, rect-to-text 4.74) | silently wrong vertical rhythm in every stack of Texts | M | layout kernel spacing preference; with 65 (Grid rows) and 89 | V | Sources/MetalUILayout/ProposalSpacing.swift:6-10; Tests/MetalUITests/ContainerIntegrationTests.swift:481; CN-H |
| 3 | 295 | `Text("")` is one line tall; SwiftUI is 0x0 | silent extra height for optional/empty text in stacks | S | alone; fix the contradicting comment at TextMeasurer.swift:100 too | V | SurfaceTextMeasureTests.swift:193-210 asserts height == one line |
| 4 | 205 | opacity (and every effect but shadow/blur) is per primitive, not group-composited; overlapping children show through | silent visual difference on every faded card/overlay, incl. transitions | L | offscreen pass in both renderers; shared with 167, 248, 1066, 1067 | V | Sources/MetalUI/CompositingGroup.swift:23,38; PF-E 3; TE-AD |
| 5 | 98 (+897, 898) | insertion/removal with no `.transition` is instant; SwiftUI cross-fades; leaver does not move; custom `Transition` limited to opacity/scale/offset | `withAnimation { show.toggle() }` pops instead of fading | M | transitions: AN-AE, MG-F; also Not-offered `contentTransition`, `.blurReplace` | V | Transition.swift:81; TransitionTests.swift:447-461 |
| 6 | 150 | links in `Text` (Markdown, `AttributedString.link`) are styled but inert | looks clickable, does nothing; no AX link | M | text; needs `openURL` plumbing | V | TextRuns.swift:31; TextAttributes.swift:31 |
| 7 | 81 | automatic `Picker` is segmented; SwiftUI macOS is a pop-up menu | visibly different control in every form that omits `.pickerStyle` | S | alone (`.menu` exists); breaking for existing apps, needs migration note | V | Picker.swift:19,84; SV-P |
| 8 | 84 | `List` is not self-scrolling, needs an enclosing `ScrollView`, takes data only (no `List { }`) | not scrolling / compile error on the commonest SwiftUI form | L | lazy/virtualization (DD-AB 3, VL-*) | V | List.swift:335-780 (every init takes `Data`) |
| 9 | 1 | CAMetalLayer colour space is Display P3 while colours author as sRGB | every hex colour is more saturated than SwiftUI | M | one-line change plus a colour probe and golden-free pins; weigh wide-gamut loss | V | MetalLayerSurface.swift:18; spec 7.8 |
| 10 | 186 | nothing is focused when a window shows; SwiftUI focuses the first focusable view | first text field not ready for typing | M | focus (KF-B reversal); with 94 | V | KF-B; grep finds no initial-focus code in Sources |
| 11 | 636, 638, 13, 124 | lazy stack with `if`/`switch`/`for` member is eager; adaptive grid uses last frame width; List windows on last frame; List cold frame builds every row | perf cliff and extra onAppear runs, one-frame glitches | L | one root: viewport/width unknown at build; 637 (DC) falls with it | V (636, 124); 13 and 638 pin only | Sources/MetalUI/LazyStack.swift:170 (non-unit member makes the container eager); LC-Q 1 read; pins exist for 13, 124, 636, 638 |
| 12 | 975 | gradient/material `foregroundStyle` on text, borders and tint lowers to the first stop / flat tint | silent flat colour instead of gradient text | L | shader text path; with SS-G `HierarchicalShapeStyle` | V | ShapeStyle.swift:49,330; SS-C 3 |
| 13 | 169, 947 | no `Animatable`/`animatableData`; `trim` not animatable from a custom wrapper | custom Shape cannot animate (compile error / no animation) | M | one protocol closes both; 97 partly | V | Sources has only VectorArithmetic.swift:11; no `protocol Animatable` |
| 14 | 76 | `controlSize` reaches fonts, Button, TextField inset only; Toggle switch/checkbox, Picker, Slider, Stepper, ColorPicker, Menu, TextEditor ignore it | `.controlSize(.small)` silently does nothing on most controls | M | control chrome (EV-AC, MD-V); also in record 05 | V | Toggle.swift:146 is the only other reader; record 05 |
| 15 | 119 | `.foregroundStyle(.secondary)` is `Color.secondary`, not a hierarchical level of the inherited style | wrong tone under a non-default parent style | M | shape styles (SS-G); `HierarchicalShapeStyle` absent from Sources | V | SS-A 3; grep of Sources |
| 16 | 94 | click on `.focusable()` or `Button` does not focus it | keyboard focus does not follow the pointer | M | focus; with 186; ruling IX-K/KF-F | V | pins clickingAFocusableElementDoesNotFocusIt etc.; DD-T read |
| 17 | 828 | `glassEffectID` carried, no morph | glass shapes snap instead of morphing | M | unblocked by `matchedGeometryEffect` (Tasks.md R3-2) | V | Glass.swift:136; LG-K |
| 18 | 1076, 1078, 1079 (+1075) | Increase Contrast, Show Borders, legibility weight stamped but no built-in reacts; SDL reports defaults only | accessibility settings ignored | M | one batch (AD-I, AD-J); 1075 needs per-OS reads, SDL3 has no query | V | Sources has no reader of `colorSchemeContrast` outside EnvironmentValues; EnvironmentValues.swift:264 |
| 19 | 885 | `.switch` toggle knob snaps | no slide on the most visible control animation | S | animation store already exists for the track fill | V | ToggleStyle.swift:81 |
| 20 | 106 (+109, 104) | text/images soft above 1x under scale; clip between nested rotations; shadow leaf rule | blurry zoomed canvases | L | render fidelity under transforms (GX-L, GX-G, GX-J) | V | pin aTextUnderScaleEffectIsResampledNotReRasterized |
| 21 | 126 | `WindowResizability.automatic` measures nothing; SwiftUI is `contentMinSize` | window can shrink below its content | S | breaking change; needs a ruling (SV-L) | V | Window.swift:827-833 |
| 22 | 154 | `Button("**b**")` titles are verbatim | Markdown title not bold | S | text (RT-A) | V | Button.swift:370-376 |
| 23 | 91 (+92) | `clipShape(Ellipse())`/`Path` traps; crossing rounded clips use the bounding box | trap on a legal SwiftUI spelling | L | mask path in both renderers | V | ClipShape.swift:12,38 |
| 24 | 90 | continuous corners drawn circular | subtle corner shape difference everywhere `.continuous` is used | L | shader + replay.hlsl identically | V | pin theContinuousStyleIsTheDefaultAndIsDrawnCircular |
| 25 | 1045 | RTL does not mirror a shape path, gradient unit points, `trim`, `UnevenRoundedRectangle` corners; no `flipsForRightToLeftLayoutDirection` | RTL shapes/gradients wrong way round | M | Tasks.md R3-10 4 follow-up; human check LD | V | pin aRightToLeftShapeIsNotYetMirrored; LD-A, LD-G |

Rank 11: 636 and 124 verified by source/ruling; 13 and 638 only by their pins. The other 24 have a source, header or ruling read recorded in the evidence column.

### Reconciliation with Tasks.md carried items

| Tasks.md / Not-offered item | divergence row(s) | status |
|---|---|---|
| contentTransition, blurReplace, `AnyTransition.animation` | 98, 898 (Not offered table) | still absent; fold into batch 3 |
| glassEffectID morph | 828 | carried; now unblocked, rank 17 |
| GestureMask, `gesture(_:including:)` | none (Not-offered table only, GE-*) | not a row; no divergence to triage |
| two-axis scrolling, ScrollPosition struct | none (Not-offered) | not a row; absent API, compile error |
| TextField/SecureField in an alert | none (Not-offered) | not a row; SV-I/SV-AD |
| custom PickerStyle / TextFieldStyle / ProgressViewStyle | none (Not-offered) | not a row; related to 81 only for the default style |
| view-level text modifiers on TextField/TextEditor, monospacedDigit, fontWidth, fontDesign | none (Not-offered localization row; TM-* shipped dash patterns and view-level modifiers) | not a row; 133 is the only TextEditor text row |
| RTL layoutDirection | 1045 (and the stale clause in 208) | 25 retired by LD; residual is 1045, rank 25 |
| GPU surface blur pass | 167 | carried until an app asks; groups with 205 |
| Liquid Glass path SDF | 829 | carried until an app asks |
| precise-scroll momentum | 846 | SDL limit (platform-limit), carried TP-L |
| retained-replay arms, layout struct reshape | none | not divergences |

## 4. Stale rows and stale text

No row is fully stale (each pin named by a row exists, and every row's MetalUI answer still matches a pin or the source I read). Partial findings:

- **208**: its MetalUI cell says "(no right-to-left layout, divergence 25)". Divergence 25 is retired and `layoutDirection` now mirrors placement of padding, frame, overlay, stacks and scrollers (`docs/superpowers/2026-11-01-layout-direction-decisions.md:24-26`). The comment at `Sources/MetalUI/PaddingSpellings.swift:12` and `:46` repeats the old claim. The default-amount clause of 208 is still live. Fix the wording, keep the row.
- **295** (row live): `Sources/MetalUI/TextMeasurer.swift:100` says "The empty string is 0 by 0 (divergence 295)", contradicting the row and the pin `anEmptyStringMeasuresAsItLaysOut` (`Tests/MetalUITestingTests/SurfaceTextMeasureTests.swift:193-210`, asserts width 0 and height equal to one line). The doc comment is wrong, the row is right.
- **27, 140, 235, 236, 735, 736**: not differences to fix; they are additive MetalUI-only API (or agreement). They could move to the "Not offered"/scope sections, but are not stale.
- **76**: row says Toggle "reads nothing"; `Toggle.swift:146` shows a button-style Toggle reads `controlSize` (record 05 says so). Minor wording.

## 5. All rows

Class: PL platform-limit, DC design-choice, FG fixable-gap. Evidence is the row's own reason/ruling plus the pin location found by grep (or `unpinned`). V = verified, U = unverified (see section 1).

| label | class | reason | evidence | pin | v |
|---|---|---|---|---|---|
| 1 | FG | layer colourspace is Display P3 so sRGB hex renders more saturated than SwiftUI; set/convert to sRGB | Sources/MetalUIAppKit/MetalLayerSurface.swift:18; spec 7.8 only fixes the pixel format, not the layer space | unpinned | V |
| 9 | DC | absolute positioning is MetalUI-only (CSS); SwiftUI has no analogue | AP-F; docs/divergences.md:342 scope | Tests/MetalUITests/PresentationLoweringTests.swift:117 | V |
| 10 | DC | Deferred portal escapes clips by design; SwiftUI sheet/popover are outside the tree anyway | AP-I; Deferred.swift | Tests/MetalUITests/DeferredTests.swift:125 | V |
| 13 | FG | List windows against last frame's viewport (2 rows overscan hides it); needs viewport known at build | MP-F/DD-F; same root as 637, 638, 124 | Tests/MetalUITests/ScrollRoutingTests.swift:584 | U |
| 20 | DC | legacy CSS vocabulary only (MetalUI-only API, has SwiftUI replacement) | MC-C; divergences.md:342 | Tests/MetalUITests/ModifiedElementTests.swift:654 | V |
| 21 | DC | disabled element is out of the keyboard by design (EV-F: no focus, no actions); stated reason holds | EV-F read in 2026-09-15-environment-decisions.md | Tests/MetalUITests/DisabledTests.swift:604 | V |
| 22 | DC | same ruling as 21 for raw onKey/keyContext under a disabled ancestor | EV-F (b) | Tests/MetalUITests/DisabledTests.swift:692 | V |
| 23 | DC | disabled target registers no hitbox; EV-E re-ruled after probe N showed the opposite case | EV-E read ("this ruling was inverted") | Tests/MetalUITests/DisabledTests.swift:510 | V |
| 26 | DC | raw `onKey` is MetalUI-only API; bubbling innermost first | record 04; pin | Tests/MetalUITests/FocusTests.swift:76 | U |
| 27 | DC | additive: MetalUI-only `onClick` is pressable; gestures match SwiftUI (not pressable) | AB-G, IX-Y | Tests/MetalUITests/AccessibilityModifierTests.swift:475 | V |
| 29 | FG | a button over an interactive descendant is not collapsed (AX structure only) | AB-G; unpinned | unpinned | U |
| 30 | FG | labelled focusable/adjustable container keeps a group instead of distributing label/action (AX) | AB-T read: distributor excludes focusable/adjustable | Tests/MetalUITests/AccessibilityDefaultsTests.swift:381 | U |
| 31 | FG | nothing focused reports the host view, not first focusable node (AX) | AB-J; unpinned | unpinned | U |
| 32 | DC | List is virtualized by design, so only realised rows are AXRows | AB-L read; VL-A | Tests/MetalUIPlatformTests/AppKitAccessibilityPart2Tests.swift:72 | V |
| 33 | DC | `AXGroup` chosen over `AXUnknown` deliberately (AB-F title: generic is AXGroup) | AB-F read | Tests/MetalUITests/AccessibilityModifierTests.swift:71 | V |
| 34 | FG | Stack AX order is declaration order, not front-to-back; deferred as builder cannot tell Stack from Column | AB-P read ("Why deferred"); unpinned | unpinned | U |
| 38 | DC | registrar traps what is non-finite or SwiftUI rejects; traps instead of diagnostic (SA-J rule) | SA-J read | Tests/MetalUILayoutTests/NativeValidationTrapTests.swift:125 | V |
| 41 | DC | hit region is the whole frame: no drawn-content geometry exists to derive a shape from (OM-I) | OM-I read | Tests/MetalUITests/HitRegionTests.swift:731 | V |
| 42 | DC | follows from OM-C (onClick writes outermost layer, registers at its box); legacy chain; contentShape(inset:) opts out | OM-K read | Tests/MetalUITests/OuterModifierMatrixTests.swift:1018 | V |
| 43 | DC | grown contentShape bounded by ancestor clip: same insertHitbox path as every hitbox (OM-AJ) | OM-AJ read | Tests/MetalUITests/HitRegionTests.swift:530 | V |
| 44 | FG | inner layer allowsHitTesting(false) does not reach later layers (legacy chain) | OM-AL read ("recorded rather than fixed") | Tests/MetalUITests/HitRegionTests.swift:810 | U |
| 46 | DC | legacy single-Decoration chain only; proposal path multiplies (OM-AH mechanism) | OM-AH read | Tests/MetalUITests/DecorationPaintTests.swift:998 | V |
| 47 | DC | legacy `.cornerRadius` (one order-insensitive Decoration); proposal path agrees with SwiftUI | OM-G, CX-B; row text | Tests/MetalUITests/OuterModifierMatrixTests.swift:1108 | V |
| 49 | DC | legacy vocabulary: rounded stroke follows the arc | OM-W; divergences.md:342 | Tests/MetalUITests/DecorationPaintTests.swift:799 | V |
| 50 | DC | legacy contentShape(inset:) before a wrapper inert; documented opt-out | record 16 | Tests/MetalUITests/FrameDecorationInteractionTests.swift:643 | U |
| 51 | FG | VStack/HStack default spacing is constant 8; SwiftUI is font-derived beside Text (text-to-text 0) | Sources/MetalUILayout/ProposalSpacing.swift:6-10; CN-H read; Tests/MetalUITests/ContainerIntegrationTests.swift:481 | Tests/MetalUITests/ContainerIntegrationTests.swift:481 | V |
| 52 | DC | legacy Row/Column keep CSS gap 0; HStack/VStack are 8 | CN-P 1 | Tests/MetalUITests/LoweringDistributionTests.swift:553 | V |
| 54 | DC | legacy ScrollView only; ProposalScrollView matches | CN-P 3 | Tests/MetalUITests/LoweringScrollTests.swift:812 | V |
| 56 | FG | `.frame` on a multi-member Component is one layer over a row, not per-member (Group semantics) | CN-N, ID-I | Tests/MetalUITests/LoweringComponentTests.swift:433 | U |
| 57 | DC | click passes through a non-clickable primary (hitbox only with pointer handler model) | CN-K read; OM-I | Tests/MetalUITests/ContentShapeTests.swift:292 | V |
| 58 | DC | SwiftUI has no such placement (legacy ZStack in larger bounds) | CN-E | Tests/MetalUILayoutTests/NativeStackDistributionTests.swift:1587 | V |
| 60 | DC | text width not ceiled to pixel grid; TE-G kept it, only stored rect rounded | TE-G read | Tests/MetalUITests/FontTests.swift:259 | V |
| 61 | DC | SwiftUI Grid undocumented span/priority rules; kernel is the reference model, GZ corpus is a floor | GR-O 1 read | Tests/MetalUILayoutTests/NativeGridTests.swift:1652 | V |
| 62 | DC | committed 65-case corpus of 61 | GR-O 2 read | Tests/MetalUILayoutTests/NativeGridTests.swift:2627 | V |
| 63 | DC | gridCellColumns(0) undefined in SwiftUI; lays out as 1 | GR-O 3 | Tests/MetalUILayoutTests/NativeGridTests.swift:2588 | V |
| 65 | FG | rows of text in a Grid use default row spacing, not font-derived (same cause as 51) | GR-O 5 | Tests/MetalUITests/GridElementTests.swift:1149 | U |
| 66 | FG | modifier on multi-cell GridRow traps instead of applying per cell | GR-O 6 | Tests/MetalUITests/GridTrapTests.swift:85 | U |
| 67 | DC | column count above Int32.max traps; unreachable limit | GR-S | Tests/MetalUILayoutTests/NativeGridTrapTests.swift:148 | V |
| 68 | DC | Int32 bookkeeping bound; unreachable limit | GR-S | Tests/MetalUILayoutTests/NativeGridTrapTests.swift:148 | V |
| 70 | DC | stack's infinite tie broken in declaration order; GR-X pins the kernel's figures | GR-X read | Tests/MetalUILayoutTests/NativeStackDistributionTests.swift:169 | V |
| 71 | DC | one value placed twice: dispatch resolves the occurrence (ID-F); only phase/raw writes hit last-bound | ID-F read | Tests/MetalUITests/IdentityTests.swift:640 | V |
| 72 | DC | duplicate sibling ids share identity, kept; duplicate id is an author error | ID-H read ("kept") | Tests/MetalUITests/ElementGroupTrapTests.swift:450 | V |
| 73 | FG | .overlay/.background closure on multi-member primary traps instead of one instance per member | ID-I 3 | Tests/MetalUITests/LegacyOverlayTests.swift:437 | U |
| 76 | FG | controlSize reaches fonts, Button, TextField inset only; Toggle switch, Picker, Slider, Stepper, ColorPicker, Menu, TextEditor ignore it | Sources/MetalUI/Toggle.swift:146 (only button-style Toggle reads it); record 05 row; EV-AC | Tests/MetalUITests/EnvironmentScaleAndSizeTests.swift:343 | V |
| 77 | DC | layout rounds to whole points not the pixel grid; EV-AD "no change", pinned wrong on purpose | EV-AD read | Tests/MetalUITests/EnvironmentScaleAndSizeTests.swift:238 | V |
| 78 | DC | Binding is @MainActor (state is main-actor); SwiftUI spelling compiles unchanged | DD-D read | Tests/MetalUITests/BindingCompileGuards.swift:132 | V |
| 80 | DC | every control focusable and Tab reaches it; SwiftUI needs FKA; kept (IX-K) because MetalUI reads no system setting | DD-T, IX-K read | Tests/MetalUITests/ButtonTests.swift:199 | V |
| 81 | FG | `.automatic` Picker is segmented; SwiftUI macOS is a pop-up menu (.menu exists) | Sources/MetalUI/Picker.swift:19 and :84; SV-P read | Tests/MetalUITests/MenuPickerTests.swift:321 | V |
| 82 | FG | stepper/radio AX: sibling-text fold, no slider value indicator, arrows read enabled; needs VoiceOver run | DD-U; owner human VoiceOver | Tests/MetalUITests/PickerTests.swift:146 | U |
| 84 | FG | List needs an enclosing ScrollView and data; no `List { }` static content, not self-scrolling | Sources/MetalUI/List.swift:335-780 (all inits take Data) | Tests/MetalUITests/ListTests.swift:214 | V |
| 86 | DC | line height ceil(ascent+descent+leading); TE-G: SwiftUI's TextKit heights fit neither ceil nor round (X13 sweep) | TE-G read | Tests/MetalUITests/FontTests.swift:283 | V |
| 87 | DC | middle truncation follows CTLineCreateTruncatedLine; SwiftUI keeps varying amounts | TE-I | Tests/MetalUITests/TruncationTests.swift:18 | V |
| 88 | FG | baseline-aligned GridRow traps where SwiftUI keeps row height | TE-K 4 | Tests/MetalUITests/GridElementTests.swift:1237 | U |
| 89 | FG | wrapping text beside Spacer gets height less spacer minimum | TE-Z | Tests/MetalUITests/LineLimitTests.swift:149 | U |
| 90 | FG | continuous corners drawn circular; shader+replay.hlsl work | TE-AG, GX-C | Tests/MetalUITests/ShapeTests.swift:285 | V |
| 91 | FG | clipShape(Ellipse()) or Path traps; every mask is a rounded rect | Sources/MetalUI/ClipShape.swift:12,38 | Tests/MetalUITests/ClipShapeTests.swift:221 | V |
| 92 | FG | crossing rounded clips use bounding box not exact intersection | TE-AJ 5 | Tests/MetalUITests/ClipShapeTests.swift:299 | U |
| 93 | FG | .interpolation(.high) is bilinear | TE-AL | Tests/MetalUITests/ImageTests.swift:163 | U |
| 94 | FG | click on .focusable()/Button does not focus it (SwiftUI focuses .focusable) | IX-K, KF-F; DD-T read | Tests/MetalUITests/FocusIdentityTests.swift:234 | V |
| 95 | DC | request naming an id outside an isolated modal tree is refused (safety) | IX-Z, IX-AF | Tests/MetalUITests/AccessibilityRequestTests.swift:159 | V |
| 96 | FG | animates declared input re-laid-out each frame; SwiftUI animates geometry laid out once at final values | AN-X read; differs where child re-lays out | Tests/MetalUITests/ModifierAnimationTests.swift:667 | U |
| 97 | FG | frame nil<->value, alignment, fixedSize, layoutPriority, clipShape, stroke width snap rather than animate | AN-AB, GX-E | Tests/MetalUITests/ModifierAnimationTests.swift:140 | U |
| 98 | FG | insertion/removal with no .transition is instant; SwiftUI cross-fades | Sources/MetalUI/Transition.swift:81; Tests/MetalUITests/TransitionTests.swift:447-461 read | Tests/MetalUITests/TransitionTests.swift:447 | V |
| 99 | FG | nested/sequential withAnimation share one parked curve per build | AN-Y; unpinned | unpinned | U |
| 100 | FG | one disabled gate removes drag source and drop target; SwiftUI still drags and drops | DN-G | Tests/MetalUITests/DragAndDropTests.swift:621 | U |
| 101 | PL | SDL3 has no outgoing drag API (verified: SDL_events.h has only inbound SDL_DropEvent); AppKit half uses payload image | SDL_events.h:936-947; DN-K | Tests/MetalUITests/DragAndDropTests.swift:693 | V |
| 102 | PL | SDL_DropEvent carries only x,y,source,data: no types before the drop | SDL_events.h:936-947 | Tests/MetalUITests/DragAndDropTests.swift:806 | V |
| 103 | DC | MetalUI rebuilds the tree every dirty frame so "body re-ran" is meaningless; on-demand redraw by value (MV-G 5) | MV-G item 5 | Tests/MetalUICrossPlatformTests/SurfaceTargetTableTests.swift:59 | V |
| 104 | FG | one shadow per emitted primitive, not per drawn leaf | GX-J | Tests/MetalUITests/ShadowTests.swift:40 | U |
| 105 | DC | three box blurs approximate the Gaussian within 8 grey levels (perf, measured) | GX-J | Tests/MetalUITests/ShadowTests.swift:76 | V |
| 106 | FG | text/images soft when scaled above 1x; SwiftUI re-rasterizes | GX-L | Tests/MetalUITests/PathTests.swift:400 | V |
| 107 | DC | AX frame of a 45-degree view: SwiftUI's own answer unexplained; bounding box chosen | GX-I | Tests/MetalUITests/RenderEffectHitTests.swift:158 | V |
| 108 | DC | legacy StyledElement order-insensitive Decoration wraps whole element | GX-H | Tests/MetalUITests/RenderEffectTests.swift:436 | V |
| 109 | FG | clip between nested rotations becomes axis-aligned box | GX-G | Tests/MetalUITests/RenderEffectTests.swift:453 | U |
| 110 | DC | secondary press only opens context menus; MN-B ruling (new input event, never presses) | MN-B read | Tests/MetalUITests/ContextMenuTests.swift:310 | V |
| 111 | DC | popover drawn in-window, flipped/clamped: one implementation on AppKit and SDL | MN-M read | Tests/MetalUITests/PopoverTests.swift:157 | V |
| 112 | FG | no popover arrow (MN-M item 5 "no arrow"; cosmetic) | MN-M read | Tests/MetalUITests/PopoverTests.swift:558 | U |
| 113 | DC | tooltip drawn by MetalUI on every platform (SDL has no native tooltip) | MN-P read | Tests/MetalUITests/TooltipTests.swift:64 | V |
| 114 | DC | only pointer handlers register hitboxes (same model as 41/141) | MN-V | Tests/MetalUITests/ContextMenuTests.swift:1021 | V |
| 115 | FG | a StyledElement modifier after .popover does not compile on legacy vocabulary | MN-AG 4 | Tests/MetalUITests/PopoverCompileGuards.swift:115 | U |
| 116 | DC | Color.primary/secondary resolve through Theme with fitted alpha ratios | CR-F, SS-D | Tests/MetalUICrossPlatformTests/ColorValueTests.swift:108 | V |
| 117 | DC | hue statics frozen to macOS 27 values on every platform for identical output | CR-F | Tests/MetalUICrossPlatformTests/ColorValueTests.swift:80 | V |
| 118 | DC | Color.Resolved clamps on resolve; stored Color keeps values so equality matches SwiftUI | CR-C 2 | Tests/MetalUICrossPlatformTests/ColorValueTests.swift:125 | V |
| 119 | FG | `.foregroundStyle(.secondary)` resolves to Color.secondary, not a hierarchical level of the inherited style | SS-A 3; grep HierarchicalShapeStyle in Sources finds nothing | Tests/MetalUITests/ColorCompileGuards.swift:126 | V |
| 121 | DC | actions run after the build, two levels per frame; LC-E "outside every phase" safety rule | LC-E read | Tests/MetalUITests/LifecycleTests.swift:825 | V |
| 122 | DC | one callback-order rule always; SwiftUI order has special cases (A2) | LC-F | Tests/MetalUITests/LifecycleTests.swift:544 | V |
| 123 | FG | re-inserted-during-removal view gets fresh @State (ID-C reset) | LC-H, LC-P 8 | Tests/MetalUITests/LifecycleTests.swift:1006 | U |
| 124 | FG | List first frame builds every row so every row's onAppear runs (cold-frame rule); owner none | LC-Q 1 read | Tests/MetalUITests/LifecycleTests.swift:289 | V |
| 125 | FG | never-written @State default re-seeded each build; SwiftUI keeps the first evaluation | LC-S read ("not done: MUST NOT MOVE"); Tests pin 5.5/5.6 | Tests/MetalUITests/LifecycleTests.swift:1257 | V |
| 126 | FG | WindowResizability.automatic measures nothing; SwiftUI is contentMinSize on macOS; breaking change | Sources/MetalUI/Window.swift:827-833; SV-L | Tests/MetalUITests/WindowSizingTests.swift:101 | V |
| 127 | FG | Divider colour is the opaque separator token, not translucent 0.098 black/white | SV-O 4 | Tests/MetalUITests/DividerTests.swift:136 | U |
| 128 | FG | menu Picker option whose content is not Text is titled String(describing: tag) | SV-P 3 | Tests/MetalUITests/MenuPickerTests.swift:299 | U |
| 129 | PL | SDL_DialogFileFilter is {name, pattern} only, so UTType conformance cannot be matched | SDL_dialog.h:70-74; Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:172 | Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:172 | V |
| 130 | DC | controls keep strut/padding minimums below ideal size; "kept" in PE-N (reason is stability, weak) | PE-N read | Tests/MetalUITests/ProposalControlsTests.swift:139 | V |
| 131 | DC | residual +1 caret allowance in TextField ideal; class agreement; kept | PE-N, MD-T | Tests/MetalUITests/ProposalControlsTests.swift:139 | V |
| 132 | DC | field chrome uses theme tokens (surface/separator), geometry matches | MD-E | Tests/MetalUITests/TextFieldChromeTests.swift:126 | V |
| 133 | FG | TextEditor has no 5pt padding and 13pt font (SwiftUI 12pt, 5pt line-fragment padding) | MD-F 3 | Tests/MetalUITests/TextFieldChromeTests.swift:357 | U |
| 134 | DC | message wording only (SwiftUI sentence with MetalUI noun) | MD-H 4 | Tests/MetalUITests/EnvironmentObjectTests.swift:207 | V |
| 135 | DC | toolbar items are native controls in an NSToolbar so a closed item set; arbitrary views can't be hosted | MD-I read | Tests/MetalUITests/ToolbarCompileGuards.swift:57 | V |
| 136 | PL | SDL has no toolbar API (no menu/toolbar header in SDL3, only SDL_tray.h), so MetalUI draws a strip | MD-K, MD-Z; /opt/homebrew/Cellar/sdl3/3.4.18/include/SDL3 listing | Tests/MetalUITests/ToolbarStripTests.swift:100 | V |
| 137 | PL | Task.immediate needs macOS 26; macOS 14-25 start the body on a later main-queue turn | Sources/MetalUI/TaskModifier.swift:47-55 | Tests/MetalUITests/TaskModifierTests.swift:474 | V |
| 138 | DC | PNG/JPEG decoded by own decoder, profiles ignored, identical bytes everywhere (PX-C) | PX-C | Tests/MetalUITests/ImageTests.swift:325 | V |
| 139 | DC | `.global` is the content space; SwiftUI's includes a 32-pt titlebar offset quirk | CI-B 4 | Tests/MetalUITests/InputAPIGestureArenaTests.swift:104 | V |
| 140 | DC | additive: MetalUI-only DragGesture.Value.modifiers | CI-G | Tests/MetalUITests/InputAPIGestureArenaTests.swift:154 | V |
| 141 | DC | paint-only views register no hitbox, so they do not cover a pointer style (same model as 41) | CI-H 5 | Tests/MetalUITests/InputAPIWindowTests.swift:624 | V |
| 145 | DC | row is exactly content height (VL-B: no inset, no floor); SwiftUI adds 8 -- author owns row padding | VL-B read | Tests/MetalUITests/VariableHeightListTests.swift:229 | V |
| 146 | DC | scroll anchoring keeps the top row on screen (deliberate improvement) | VL-G 3, VL-O | Tests/MetalUITests/VariableHeightListTests.swift:399 | V |
| 147 | DC | estimate is declared or running mean (better than constant 24) | VL-C | Tests/MetalUITests/RowExtentIndexTests.swift:43 | V |
| 150 | FG | links in Text are styled but inert: no click, no key, no AX link | Sources/MetalUI/TextRuns.swift:31; TextAttributes.swift:31 | Tests/MetalUITests/RichTextTests.swift:429 | V |
| 151 | DC | `Text("v \(3.5)")` prints 3.5 not %lf 3.500000 (RT-C 3); deliberate | RT-C | Tests/MetalUICrossPlatformTests/LocalizedStringKeyTests.swift:84 | V |
| 152 | DC | underline/strike are the face's unsnapped band (portable text consistency) | RT-J 2, TM-C | Tests/MetalUITests/RichTextPaintTests.swift:77 | V |
| 153 | FG | only 34 named HTML entities decode (SwiftUI HTML5 set) | RT-B 4 | Tests/MetalUICrossPlatformTests/MarkdownInlineTests.swift:95 | U |
| 154 | FG | Button("**b**") control titles are verbatim; SwiftUI renders Markdown | Sources/MetalUI/Button.swift:370-376 String inits; RT-A | Tests/MetalUICrossPlatformTests/LocalizedStringKeyTests.swift:207 | V |
| 155 | DC | decorated Text concatenation: compile error in SwiftUI, trap in MetalUI (language-level, modifiers return Self) | RT-E 4 | Tests/MetalUITests/RichTextTests.swift:472 | V |
| 156 | DC | no deprecation warning on describing-interpolation; harmless | RT-O 6 | Tests/MetalUITests/TextLiteralCompileGuards.swift:34 | V |
| 157 | DC | Linux/Windows: spacing between joined Arabic letters as gap, widths agree; no kashida glyph | RT-P 5 | Tests/MetalUITests/StyledTextSeamTests.swift:531 | V |
| 158 | DC | bold() is the bold weight over the resolved font (Font.bold semantics) | RT-R 6 | Tests/MetalUITests/RichTextTests.swift:152 | V |
| 165 | FG | ColorPicker opens a drawn popover not NSColorPanel on macOS; owner C10-b (presentColorPanel seam) not built | grep presentColorPanel in Sources/Backends finds nothing | Tests/MetalUITests/ColorPickerTests.swift:141 | V |
| 166 | DC | material tint is a fitted table over a real blur since C21 | LK-L, BB-A | Tests/MetalUITests/MaterialTests.swift:33 | V |
| 167 | FG | GPUSurface/MetalView drawn unblurred under .blur(radius:) (needs GPU blur pass) | LK-K 5; Tasks.md "GPU surface blur pass" carried until an app asks | Tests/MetalUITests/BlurTests.swift:135 | U |
| 168 | FG | SpringKeyframe requires duration:; SwiftUI default settling length unfitted | Sources/MetalUI/Keyframes.swift:200 | Tests/MetalUITests/KeyframeCompileGuards.swift:143 | V |
| 169 | FG | Animatable/animatableData absent; keyframe tracks use VectorArithmetic | Sources: only VectorArithmetic.swift:11, no `protocol Animatable` | Tests/MetalUITests/KeyframeCompileGuards.swift:27 | V |
| 171 | DC | zero-duration keyframe returns target, not NaN | LK-I 7 | Tests/MetalUITests/KeyframeTimelineTests.swift:236 | V |
| 175 | DC | hidden title bar: root laid out under the bar, titleBarInsets gives the band (no safe area) | AS-E 3-4 | Tests/MetalUITests/AppShellTests.swift:520 | V |
| 176 | DC | MetalUI never opens a window for an external open; routes to existing windows | AS-G | Tests/MetalUITests/OpenURLTests.swift:36 | V |
| 185 | DC | onKeyPress inside .focusable is order-free (SwiftUI gotcha K12 not reproduced) | KF-H 3 | Tests/MetalUITests/KeyboardModifierTests.swift:84 | V |
| 186 | FG | nothing focused at window show; SwiftUI focuses the first focusable view | KF-B spec 11; grep for initial/first-focus in Sources finds none | Tests/MetalUITests/KeyPressTests.swift:113 | V |
| 187 | DC | typed character offered once as .down from committed text (IME composition never offered); SDL has no release for text | KF-Q | Tests/MetalUITests/KeyPressTests.swift:515 | V |
| 188 | FG | native menu items' command keys: handler hears first, catch-all onKeyPress swallows Cmd-Q | KF-X 4; NSView.performKeyEquivalent could see it | Tests/MetalUITests/KeyPressTests.swift:556 | U |
| 195 | PL | SDL has no window menu-bar API (SDL_tray.h is system tray only), so the bar is drawn | SG-A; SDL3 header listing | Tests/MetalUITests/MenuBarStripTests.swift:123 | V |
| 205 | FG | opacity (and effects but shadow/blur) not composited as a group; overlapping children show through | Sources/MetalUI/CompositingGroup.swift:23,38; PF-E 3; pin aCompositingGroupDoesNotCompositeAnOpacity | Tests/MetalUITests/CompositingGroupTests.swift:236 | V |
| 206 | FG | HSplitView/VSplitView sizing and divider unprobed own rule; human look | HS-A..F | Tests/MetalUITestingTests/SplitViewTests.swift:54 | U |
| 208 | FG | default-amount .padding() spellings do not compile (needs a measured amount); RTL clause now stale | Sources/MetalUI/PaddingSpellings.swift:12 says no RTL; layout-direction-decisions line 24-26 mirror padding | Tests/MetalUITests/TextModifierParityCompileGuards.swift:53 | V |
| 209 | PL | SDL_ShowOpenFolderDialog and file dialog are separate; no combined chooser | SDL_dialog.h:260; Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:211 | Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:211 | V |
| 225 | DC | no Anchor type; PopoverAttachmentAnchor.Source spellings read like SwiftUI's | OV-B | Tests/MetalUITests/PopoverTests.swift:740 | V |
| 235 | DC | additive: modifiers and clickCount on SpatialTapGesture.Value | IF-B, IF-C, IF-O | Tests/MetalUITests/GestureFollowupTests.swift:83 | V |
| 236 | DC | additive onCancelled; SwiftUI never calls onEnded for a cancelled gesture | IF-E, IF-F | Tests/MetalUITests/GestureFollowupTests.swift:191 | V |
| 245 | DC | material blurs only what the window drew (the measured in-window case); behind-window is a platform effect | BB-F | Tests/MetalUIRenderTests/BackdropRenderTests.swift:108 | V |
| 246 | FG | no saturation lift under materials (one multiply in the backdrop shader per owner text) | BB-D 2 | Tests/MetalUIRenderTests/BackdropRenderTests.swift:108 | U |
| 247 | DC | blur region is the shape's box, edge-clamped | BB-D 3,5 | Tests/MetalUIRenderTests/BackdropSceneTests.swift:80 | V |
| 248 | FG | material on a Path or inside a CPU leaf effect draws flat tint | BB-H | Tests/MetalUITests/BackdropRecordTests.swift:103 | U |
| 295 | FG | Text("") is one line tall (SwiftUI 0x0); stale doc comment says 0x0 | Tests/MetalUITestingTests/SurfaceTextMeasureTests.swift:193-210 pin; contradicting comment Sources/MetalUI/TextMeasurer.swift:100 | Tests/MetalUITestingTests/SurfaceTextMeasureTests.swift:195 | V |
| 296 | DC | no Canvas/GraphicsContext; \.textMeasurer is the carrier (GT-G) | GT-B, GT-D, GT-I | Tests/MetalUITestingTests/SurfaceTextMeasureTests.swift:56 | V |
| 265 | FG | programmatic focus keeps stored caret; SwiftUI selects all (TextField) / caret at end; SL-C "not changed: must not move" | SL-C read | Tests/MetalUITestingTests/HarnessTextSelectionTests.swift:106 | U |
| 266 | FG | selection binding written after input only, not at focus/resign | SL-F | Tests/MetalUITestingTests/HarnessTextSelectionTests.swift:196 | U |
| 275 | DC | WindowDragGesture is an arena leaf that cancels neighbours | WD-C | Tests/MetalUITests/WindowDragTests.swift:194 | V |
| 276 | PL | SDL3 has no start-drag call; SDL_SetWindowHitTest regions are the only way (header) | SDL_video.h:2898; CW-E | Tests/MetalUITests/WindowDragTests.swift:409 | V |
| 277 | FG | an opacity(0) drag handle still captures; no hitbox gating on opacity for any gesture | WD-J read | Tests/MetalUITests/WindowDragTests.swift:377 | U |
| 315 | DC | Reduce Transparency draws fitted grey at alpha 1; SwiftUI unmeasured; owner human MT-1 | MT-F, MT-E | Tests/MetalUITests/ReduceTransparencyTests.swift:60 | V |
| 325 | FG | AX value excludes marked text during composition; human check IM-1 | IM-E | Tests/MetalUITestingTests/HarnessInputMethodTests.swift:143 | U |
| 326 | DC | selection write held back while composing; SwiftUI publishes OUT-OF-RANGE offsets | IM-G; SL-H | Tests/MetalUITestingTests/HarnessInputMethodTests.swift:115 | V |
| 346 | FG | equatable component reading @Environment memoized by readings; owner C14-c2 | IV-D, EE-*; Tasks C14-c | Tests/MetalUITestingTests/EnvironmentEpochWindowTests.swift:244 | U |
| 425 | PL | SDL hit-test region: press inside moves the window, the app gets no pointer events there | SDL_video.h:2898; CW-E, CW-V | Tests/MetalUITestingTests/WindowChromeTests.swift:156 | V |
| 465 | PL | SDL_CreateColorCursor refuses a hot spot off the surface; clamp is a platform-safety choice | SDL_mouse.h hot_x/hot_y; IC-C 2 | Tests/MetalUITestingTests/ImageCursorTests.swift:55 | V |
| 635 | FG | ForEach element yielding several views in a lazy grid is ONE cell (SwiftUI: each view a cell) | LZ-X read | Tests/MetalUITests/LazyGridLayoutTests.swift:261 | U |
| 636 | FG | lazy stack with if/switch/for member is eager (every child every frame); owner L1b | LZ-B, LZ-S; FrameWork.lazyUnbounded; Sources/MetalUI/LazyStack.swift:170 | Tests/MetalUITests/LazyStackFrameTests.swift:271 | V |
| 637 | DC | two-line realisation margin because viewport is one frame stale (DD-F); holds until 13 is fixed | LZ-E | Tests/MetalUITestingTests/LazyStackWindowTests.swift:274 | V |
| 638 | FG | adaptive GridItem column count from previous frame's width; first frame builds the old count | LZ-L, LZ-Y | Tests/MetalUITests/LazyGridFrameTests.swift:159 | U |
| 915 | FG | pinned views only for windowed lazy stacks; eager/Deferred stacks pin nothing | SP-J | Tests/MetalUITestingTests/PinnedSectionTests.swift:169 | U |
| 916 | FG | only ForEach elements are scroll targets; SwiftUI makes every direct child of scrollTargetLayout one | SP-B, SP-E | Tests/MetalUITestingTests/ScrollPositionTests.swift:364 | U |
| 426 | PL | same SDL mechanism: a handle under a control isn't draggable | CW-E | Tests/MetalUITestingTests/WindowChromeTests.swift:183 | V |
| 435 | FG | ImageBitmap keeps stored pixels (EXIF orientation applied only on request); owner S2-b | IB-G | Tests/MetalUICrossPlatformTests/DecodedImageTests.swift:99 | U |
| 455 | FG | Edit-menu items enabled by handler presence, not validator (provisional); owner CB1 | CB-G | Tests/MetalUITestingTests/ClipboardTypesTests.swift:413 | U |
| 456 | DC | array forms unprobed; MetalUI writes every item and imports all | CB-C, CP-C, CP-J | Tests/MetalUITestingTests/ClipboardItemsTests.swift:48 | V |
| 715 | PL | SDL_SetClipboardData takes one callback and one mime list per clipboard; items beyond the first use a pack mime | SDL_clipboard.h:255; probe sdl-clipboard-update.c | Backends/SDL/Tests/MetalUISDLTests/SDLClipboardItemsTests.swift:53 | V |
| 716 | DC | SDL data callback is pure C and must return bytes on SDL's thread, so SDL copies eagerly (CB-H) | CB-H read | Tests/MetalUITestingTests/ClipboardItemsTests.swift:144 | V |
| 717 | DC | PasteButton is a bordered Button; no paste prompt exists to mimic | CP-B, CP-G | Tests/MetalUITestingTests/PasteButtonTests.swift:36 | V |
| 645 | FG | simultaneous gestures run updating bodies in declaration order; SwiftUI last-declared first (pin must not move) | GS-D | Tests/MetalUITestingTests/GestureStateTests.swift:492 | U |
| 646 | DC | @MainActor closures; SwiftUI spelling compiles unchanged in view bodies | GS-N, GS-S | Tests/MetalUITests/GestureStateCompileGuards.swift:116 | V |
| 735 | DC | additive: visionOS-only PointerStyle.shape offered with fill/outline | BG-K..M | Tests/MetalUITestingTests/ShapeCursorTests.swift:55 | V |
| 736 | DC | no Scene type in MetalUI; Window property | BG-G, BG-H | Tests/MetalUITestingTests/WindowBackgroundDragTests.swift:58 | V |
| 737 | PL | SDL hit-test region mechanism (same as 425) | BG-I; SDL_video.h:2898 | Tests/MetalUITestingTests/WindowBackgroundDragTests.swift:137 | V |
| 825 | DC | Liquid Glass look fitted to probes within stated tolerance (dark regular minimax line); human checks LG1/LG2 | LG-C..U | Tests/MetalUITests/GlassTests.swift:127 | V |
| 826 | DC | blob holds four members, greedy chunks (renderer uniform budget) | LG-G, LG-H, LG-I | Tests/MetalUITests/GlassTests.swift:160 | V |
| 827 | DC | bare .glassEffect(.interactive()) registers no hitbox (hit testing must not move) | LG-J, OM-AK | Tests/MetalUITests/GlassTests.swift:304 | V |
| 828 | FG | glassEffectID is carried but no morph; matchedGeometryEffect exists so this is unblocked | Sources/MetalUI/Glass.swift:136; Tasks.md R3-2 | Tests/MetalUITests/GlassTests.swift:339 | V |
| 829 | FG | Path under glassEffect gets flat tint; needs path SDF (carried in Tasks.md) | LG-F, LG-L, BB-H | Tests/MetalUITests/GlassTests.swift:251 | U |
| 845 | PL | SDL3 wheel event has only float x,y and integer_x,y; no precise flag | SDL_events.h SDL_MouseWheelEvent; TP-A..K | Backends/SDL/Tests/MetalUISDLTests/SDLScrollClassifierTests.swift:125 | V |
| 846 | PL | SDL forwards no wheel phase; MetalUI synthesizes for precise stream | SDL_events.h; TP-F | Backends/SDL/Tests/MetalUISDLTests/SDLScrollClassifierTests.swift:203 | V |
| 885 | FG | switch toggle knob snaps; SwiftUI slides it | Sources/MetalUI/ToggleStyle.swift:81 | Tests/MetalUITests/ToggleStyleTests.swift:60 | V |
| 895 | DC | matchedGeometry is a paint map over the laid-out rect; hitbox/focus/AX stay at laid-out frame | MG-A, MG-E | Tests/MetalUITests/MatchedGeometryTests.swift:250 | V |
| 896 | DC | matched size is a stretch transform, not a relayout (cheap paint-map design) | MG-A, MG-C | Tests/MetalUITests/MatchedGeometryTests.swift:145 | V |
| 897 | FG | leaver of a matched swap does not move to the newcomer frame | MG-E | Tests/MetalUITests/MatchedGeometryTests.swift:193 | U |
| 898 | FG | custom Transition limited to opacity/scale/offset (TransitionContent); SwiftUI returns any View | MG-F | Tests/MetalUITests/MatchedGeometryTests.swift:355 | U |
| 935 | PL | SDL_ShowFileDialogWithProperties has title and accept label but no message field | SDL_dialog.h:297-298; Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:133 | Backends/SDL/Tests/MetalUISDLTests/SDLPresentationTests.swift:133 | V |
| 925 | DC | composite gesture reports only when a member reports; run count differs from SwiftUI's duplicate run | GE-G | Tests/MetalUITestingTests/GestureCompositionTests.swift:303 | V |
| 945 | DC | Transform2D (Double) instead of CGAffineTransform: portable Path has no CoreGraphics | PG-E, GX-C | Tests/MetalUITests/PathOpsTests.swift:196 | V |
| 946 | DC | strokedPath returns polygons within 0.01 units | PG-B | Tests/MetalUIPathTests/PathTrimTests.swift:315 | V |
| 947 | FG | TrimmedShape animates internally but exposes no Animatable (same root as 169) | PG-F | Tests/MetalUITests/PathOpsTests.swift:109 | U |
| 975 | FG | gradient/material for foregroundStyle on text/borders/tint lowers to first stop / flat tint | Sources/MetalUI/ShapeStyle.swift:49,330; SS-C 3 | Tests/MetalUITests/ShapeStyleTests.swift:229 | V |
| 976 | FG | custom ShapeStyle composition into stored-fill sinks resolves in a bare environment | SS-C 2 | Tests/MetalUITests/ShapeStyleTests.swift:217 | U |
| 977 | FG | menu highlight, menu bar, alert default, scroll chrome ignore .tint (read Theme.accent) | SS-D 4 | Tests/MetalUITests/ShapeStyleTests.swift:49 | U |
| 1025 | DC | hidden label not laid out so only plain Text/String labels survive; author adds .accessibilityLabel | LB-A 3 | Tests/MetalUITests/LabelsHiddenTests.swift:144 | V |
| 1026 | DC | labelsHidden reaches built-ins; custom ToggleStyle/button look draw their own label | LB-A 5 | Tests/MetalUITests/LabelsHiddenTests.swift:174 | V |
| 1035 | PL | SDL3 has no window subtitle API (grep of SDL_video.h finds none) | SDL_video.h; AE-B 3 | Tests/MetalUITests/AppShellExtrasTests.swift:51 | V |
| 1036 | PL | SDL3 cannot disable the system title-bar close button (no closable flag in SDL_video.h) | SDL_video.h; AE-D | Tests/MetalUITests/AppShellExtrasTests.swift:95 | V |
| 1045 | FG | RTL does not mirror a shape's path, gradient unit points, trim, UnevenRoundedRectangle corners; no flipsForRightToLeftLayoutDirection | LD-A, LD-G | Tests/MetalUITestingTests/LayoutDirectionWindowTests.swift:385 | V |
| 1055 | FG | no operation badge during in-window drag (PlatformPointerStyle has no drag cursors) | DE-H | Tests/MetalUITestingTests/DropDelegateHeadlessTests.swift:17 | U |
| 1065 | FG | path/shadow/gradient/blur under a projective effect is CPU raster drawn as image, soft when magnified | PJ-G | Tests/MetalUITests/ProjectionPaintTests.swift:81 | U |
| 1066 | FG | .shadow/.blur enclosing a projective effect contributes nothing from it | PJ-G | Tests/MetalUITests/ProjectionPaintTests.swift:111 | U |
| 1067 | FG | material/glass under a projective effect draws flat tint | PJ-G | Tests/MetalUITests/ProjectionPaintTests.swift:125 | U |
| 1068 | DC | ProjectionTransform has Double fields, no CATransform3D init (no CoreGraphics in portable surface) | PJ-I | Tests/MetalUITests/ProjectionEffectTests.swift:123 | V |
| 1069 | DC | primitive with corner at or behind the eye is dropped (SDL rasteriser leaves depth clipping off) | PJ-C, PJ-G | Tests/MetalUITests/ProjectionPaintTests.swift:143 | V |
| 1056 | DC | DropInfo uses Point/ContentType/DropItem (NSItemProvider is Apple-only) | DE-F | Tests/MetalUITests/DropDelegateTests.swift:374 | V |
| 1075 | FG | SDL windows report standard display settings; SDL3 has no query beyond SDL_GetSystemTheme, per-OS reads carried | SDL_video.h:615; Backends/SDL/Tests/MetalUISDLTests/SDLAccessibilityDisplayTests.swift:13 | Backends/SDL/Tests/MetalUISDLTests/SDLAccessibilityDisplayTests.swift:13 | V |
| 1076 | FG | colorSchemeContrast=increased changes no built-in colour or control | AD-I; Sources grep shows no reader outside EnvironmentValues | Tests/MetalUITests/AccessibilityDisplayTests.swift:176 | V |
| 1078 | FG | accessibilityShowBorders changes no built-in control (SwiftUI bordered Button/checkbox react) | AD-I | Tests/MetalUITests/AccessibilityDisplayTests.swift:176 | U |
| 1079 | FG | legibilityWeight is writable but Text does not read it | Sources/MetalUI/EnvironmentValues.swift:264 only | Tests/MetalUITests/AccessibilityDisplayTests.swift:144 | V |
