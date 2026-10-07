# Proposal controls — decisions

Rulings for controls (and every other legacy element) inside SwiftUI-vocabulary
containers, and for the stack a `Component` tree costs (user request
2026-10-02, an item of the gpui-gap priority list — the SMK configurator port's
gaps **MG-1** and **MG-15**, both high; **not a plan task**). Spec:
[`specs/2026-10-06-proposal-controls-design.md`](specs/2026-10-06-proposal-controls-design.md).
Record: `../record/78-proposal-controls.md`. Evidence:

- [`../probes/swiftui-controls-in-stacks.swift`](../probes/swiftui-controls-in-stacks.swift)
  (arms `FX0`–`FX3` controls, `FL0`–`FL21` each control's answer to six
  proposals, `FM0`/`FM1` a form, `ST0` the configurator's status bar,
  `IN0`/`IN1` the frame-reader instrument check, `SP0`–`SP2` the separating
  arm between greedy and hugging, `MD0`–`MD4` modifiers in a stack); run three
  times by the design session, 95 lines byte-identical.
- The design session's MetalUI measurements (scratch tests, not committed;
  their outputs are quoted in the rulings and in spec §1.3): MetalUI's answer
  to the same six proposals for every control (through the existing
  `LegacyUnderProposal` semantics), the same form and status bar, a
  prototype of `PE-B`'s builder run against the whole suite, a prototype of
  `PE-D`'s sizing run against the whole suite, and the stack high-water mark
  of synthetic trees under four variants of `PE-J`.

Where SwiftUI has no answer (a debug build's stack, a type-erasure spelling)
the ruling says so; gpui is named only where it is the comparison.

Prefix **`PE-`**, lettered. **Next unused: `PE-AA`.** (This line moves in the
commit that appends a ruling; read the last `## PE-` heading.)

Branch `feat/proposal-controls` from `e54c3f6` (master: platform services
merged, PR #48). Baseline re-taken by the design session at `e54c3f6`:
`swift build --build-system native --build-tests` 0 errors, the only
`warning:` SwiftPM's deprecation notice; unfiltered `swift test
--build-system native --no-parallel` **2546 tests in 3 suites** passed, the
`FR-J no-argument frame: succeeded=true` line present; `swift build
--build-tests` (default build system) 0 warnings. `docs/divergences.md`
lines 4 and 12: **96 live, next label 130** (CLAUDE.md's "92 live, next label
126" is stale; the file is the authority).

**Carried items.** `MC-G` (the typed entry: only native registrars mint a
`ProposalNodeID`; seven holes) and `MC-H` (the typed builder copies, each
pinned on its own) — `PE-B` keeps both, and adds one minting site inside
`MetalUI`. `LR-T` (under the proposal authority every node is native) — what
makes `PE-C`'s adapter sound. `LR-AQ` (a record nobody consumes is reported
by name, a production trap) and `LR-CK` (a presentation placeholder leaves
the flow at every collection site) — `PE-C` honours both. `LR-FX`/`ID-J`
(overlays and backgrounds already take legacy content through
`lowerAttachmentChildren`) — the precedent `PE-C` deliberately does **not**
copy for stacks. `CN-B`/`CN-H` (SwiftUI's stack algorithm and spacing) —
unchanged. The test-only `LegacyUnderProposal` (`LoweringItemTests.swift`,
`GridLoweringInteractionTests.swift`) — the semantics `PE-C` makes public.
The Windows 1 MB stack rule (record §50, `everyProductionTreeBuildsOnAOneMegabyteThread`)
— `PE-L`'s threshold.

---

## PE-A — Scope: what this branch builds, what it defers

**Builds.**

1. Every control, the legacy `Text`, `Menu`, a selectable `List`, and any
   other legacy element, group or `Component` composes inside `HStack`,
   `VStack`, `ZStack`, `Grid`, `GridRow`, `ProposalScrollView` and a custom
   `ProposalLayout` container, with **its own type and its own modifiers
   unchanged** (`PE-B`, `PE-C`, `PE-E`).
2. SwiftUI's sizing for the three greedy controls at an infinite proposal
   (`PE-D`); every other control already answers in SwiftUI's class (spec
   §1.3).
3. The proposal-only modifiers a control needs in a stack —
   `layoutPriority`, `fixedSize`, the four grid-cell modifiers — on legacy
   content, and `Pixels.infinity` for `.frame(maxWidth: .infinity)` (`PE-F`).
4. MG-15: a `Component`'s layout record off the stack (`PE-J`); a counted
   stack bound; the rule for what remains (`PE-K`); a loud, early warning
   (`PE-L`).
5. A SwiftUI-vocabulary form and the configurator's status bar laid out
   headless with literal frames, a demo section, docs (`PE-M`).

**Defers** (each named in spec §11 with an owner):

- `.padding(.horizontal, 16)` / `.padding()` on legacy elements — MG-11.
- `.help` after `.disabled` (on an `EnvironmentScope`) — MG-13.
- Field chrome for `TextField`/`TextEditor` (24 tall, a bezel) — MG-20;
  divergence 131 records today's metrics.
- An `ElementGroup` eraser (`AnyElement` over a group) — MG-22; `PE-K`'s
  supported spelling is a `Component` boundary, which needs none.
- Shrinking element values (a copy-on-write `Handlers`/`Decoration`/`Style`
  storage: a `Text` is 1040 bytes, of which `Handlers` 472, `Decoration` 264,
  `Style` 178) — the only lever left on `PE-K`'s residual; owner: the
  gpui-gap list (a performance item), with `PE-L`'s meter as its instrument.
- Deprecating `ProposalText` (`PE-G`) — a later closeout.
- Below-ideal compression of the hugging controls (divergence 130).

**Cost if wrong.** A deferred item is a compile error or a visible
difference the port still works around; none is a silent change.

---

## PE-B — The mechanism: a container builder that adopts legacy content

**Ruling.** A new public result builder, **`ProposalContentBuilder`**, takes
the place of `@ElementBuilder` on the content closures of the containers
`PE-E` names. It is `ElementBuilder` plus two `buildExpression` overloads:

```swift
public static func buildExpression<E: ProposalElementGroup>(_ e: E) -> E
@_disfavoredOverload
public static func buildExpression<E: ElementGroup>(_ e: E) -> LegacyContent<E>
```

and its other methods **forward to `ElementBuilder`'s** (so `PE-L`'s
sampling, added to `ElementBuilder`, covers both). Proposal content keeps its
type and its typed path exactly (`HStack { Spacer(); Rectangle() }` is still
`HStack<Pair<Spacer, Rectangle>>` — measured on the prototype); a legacy
expression becomes `LegacyContent<E>` (`HStack { Text("a"); Spacer() }` is
`HStack<Pair<LegacyContent<Text>, Spacer>>`, measured). The wrapping is per
**expression statement**, so an `if`/`switch`/`for` over legacy content wraps
each branch's statements, and the builder products (`OptionalGroup`,
`EitherGroup`, `ArrayGroup`, `Pair`) stay the `MC-H` typed copies.

**Evidence.**

- *Prototype, whole suite* (HStack/VStack/ZStack switched, scratch; 2554
  tests in 3 suites, 16 issues): every issue is a compile guard asserting the
  old rejection (`PE-H` lists them); **no behavioural test moved**. The
  representative form (spec §1.3) compiled unchanged in SwiftUI's spelling
  and laid out exactly as the same form through `LegacyUnderProposal`.
- *The alternative of conforming the controls themselves* (`extension
  Button: ProposalElement` with a default `requestProposalLayout` over the
  legacy `requestLayout`), prototyped: the module itself stopped compiling
  with 16 `ambiguous use of 'accessibilityHidden'` (`PullDownMenu.swift:44`),
  because **37 modifier names are declared on both `StyledElement` and
  `ProposalElementGroup`** (`accessibility*` ×11, `allowsHitTesting`,
  `background`, `border`, `clipped`, `clipShape`, `contextMenu`,
  `cornerRadius`, `draggable`, `dropDestination`, `gesture`, `help`,
  `highPriorityGesture`, `offset`, `onContinuousHover`, `onHover`,
  `onLongPressGesture`, `onTapGesture`, `opacity`, `padding`, `popover`,
  `rotationEffect`, `scaleEffect`, `shadow`, `simultaneousGesture`), and two
  (`frame`, `background`) on both `ElementGroup` and `ProposalElementGroup`,
  where the proposal one would silently win for a dual type. Even with 39
  disambiguating overloads, a legacy layer modifier (`.padding(8)`,
  `.frame(width:)`) returns `ModifiedContent<Self, ModifierLayer>`, which can
  be a `ProposalElementGroup` only through a second conditional conformance
  of `ModifiedContent` to the same protocol — which Swift forbids.
- *Twins* (`ProposalButton`, …) are not SwiftUI's names: `HStack { Button }`
  would still not compile.
- *Widening the containers' generic constraint to `ElementGroup`* routes every
  proposal child through its untyped entry and leaves the six `MC-H` typed
  copies unreached from any stack — their pins would go green under mutation
  (a broken instrument). Rejected.
- *Overloading each container initializer* (a second `init` whose `Content`
  is the adapter) puts the adapter in every container's type and makes the
  solver choose an overload per nested builder closure; the per-expression
  overload is the shape SwiftUI's own `ViewBuilder.buildExpression` takes.
  Rejected without measurement because the builder form had no cost to
  measure against.

**Cost if wrong.** If `@_disfavoredOverload` stopped ranking the proposal
overload first, proposal content would be wrapped: same nodes, same ids, the
typed copies unreached. Pinned by the type guard, spec test 1.2.

---

## PE-C — `LegacyContent`: transparent, native, reporting

**Ruling.** `public struct LegacyContent<Content: ElementGroup>:
ProposalElementGroup` — the builder makes it; nobody writes it.

1. **Identity-transparent.** Both entries call the wrapped group's
   `requestGroupLayout(under: parent, at: &cursor, …)` with the caller's
   parent and cursor: no index, no level. A legacy control takes exactly the
   id a proposal element in its position would (`MC-A`/`MC-C` unchanged, the
   seven slots unchanged, `.id()` stays outermost because it is inside the
   adapter).
2. **Layout-transparent, native.** The typed entry returns the wrapped
   group's nodes as `ProposalNodeID`s through the internal initializer —
   sound because every node is native under the proposal authority (`LR-T`);
   it is the second minting site inside `MetalUI` after the registrars, and
   `ProposalNodeID.swift`'s header names it (`MC-G`'s list gains no hole:
   nothing outside `MetalUI` can reach it).
3. **Drops presentation placeholders** (`LR-CK`): a `Deferred` presentation
   inside a stack takes no slot and no spacing, as at every legacy
   collection site.
4. **Consumes no record** (`LR-AQ`): a legacy item field (`flexGrow`,
   `margin`, `alignSelf`, `minSize`, …) on content in a proposal container is
   reported `<site>.<field>.unconsumed` and traps in production — the answer
   `LoweringItemTests`' `LegacyUnderProposal` arms already pin ("HStack Text
   flexGrow" → `text.flexGrow.unconsumed`). SwiftUI has no flex item fields;
   the SwiftUI spellings are `.frame(maxWidth: .infinity)`, `Spacer()` and
   `.layoutPriority`. The overlay precedent (`lowerAttachmentChildren`, which
   *drops* `flexGrow` silently at `parentKind: .stack`) is not copied: a
   silent drop in a stack would be an approximation.
5. **Registers nothing**: no hitbox, no handler, no lowering site. So it adds
   **no arm** to `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (it
   reports nothing of its own) or to the D2 guard (it registers no handler),
   and `Handlers`' sixteen members, `HandlerShape` and `HandlerFingerprint`
   are unchanged.

**Cost if wrong.** A cursor or level slip would move every legacy control's
`@State` and focus identity inside a stack (spec test 1.4 pins the ids); a
missing placeholder drop would put 8 points of spacing around every
presentation (test 1.8); a consumed record would silently drop a `flexGrow`
(test 1.7).

---

## PE-D — SwiftUI's sizing: the three greedy controls answer infinity

**Ruling.** `TextField` and `Slider` answer an **infinite** proposed width
with infinity, and `TextEditor` an infinite width or height with infinity —
probe `FL3`, `FL4`, `FL6` (`inf → infx24`, `infx16`) and `FL5` (`infxinf`).
A `nil` proposal keeps answering the ideal (`FL3` 47.50, `FL6` 30, `FL5`
0x12 — MetalUI's own ideals stay, divergence 131). Nothing else changes: the
design session measured every control's answer to the probe's six proposals
inside a proposal container (spec §1.3) and every other control is already in
SwiftUI's class — Button, `.plain` Button, Toggle, Stepper, every Picker
style and Menu hug on both axes; Divider is greedy along its stack's cross
axis; `Text` wraps per `ProposalText`'s rules (`FX3` 49.50x48 at 50, MetalUI
49.36x48). *(Except `List`, divergence 84 — `PE-Q`.)*

**Why it matters.** A stack orders its children by flexibility measured at an
infinite proposal (`CN-B`, `LayoutTree.swift`'s probe "at main ∞"). Today a
`Slider` answers 30 at infinity, so beside a 39-wide `Text` it is served
**first** and takes half the row: the form's `c2` slider measured **180**
where SwiftUI's is **321** (`FM0`). A `TextField` beside a label longer than
its placeholder loses half the row the same way.

**The legacy containers move too — a named exception.** A legacy `Row` is
the same native stack, so the same ordering applies there. Measured on the
whole suite with the change (scratch): **one** issue, `SliderTests`'
`aSliderIsGreedyOnTheWidthAndSixteenTall` asserting `infinite.width == 30`
(an unprobed MetalUI choice, "an infinite proposal is not finite", which
`FL6` refutes) — its arm flips to infinity in this branch; `DemoFrameDeterminismTests`
(the demo's every frame) unchanged. Lane 2 (`PE-O`) re-takes the fourteen images
(0 px expected: `demoContent()` and the preview hold no `TextField`,
`TextEditor` or `Slider`); **if any image moves, the lane stops and this
ruling is re-taken** (the fallback is answering infinity only under
`LegacyContent`). `docs/migration.md`'s "Behaviour changes" gains the row.

**Cost if wrong.** A legacy `Row { Text; TextField }` whose author relied on
the half-row field changes width — towards SwiftUI's answer.

---

## PE-E — Which containers take `ProposalContentBuilder`

**Ruling.** Every SwiftUI-named proposal container and the custom-layout
spellings: `HStack`, `VStack`, `ZStack` (every initializer, the deprecated
ones too), `Grid`, `GridRow`, `ProposalScrollView`, `ProposalLayoutContainer.init`
and `ProposalLayout.callAsFunction`. **Not**: `ProposalFrame`, `Padding`,
`Background`, `FixedSize` (MetalUI-only native wrappers that predate the
modifiers; they keep the `ProposalElementGroup` rejection and become the
guards' new control arms, `PE-H`); `nativeOverlay` (MetalUI-only; the
`.overlay`/`.background` spellings already take legacy content, `LR-FX`);
`ForEach` (its builder stays `ElementBuilder`: a `ForEach` of legacy rows
inside a stack is one expression, wrapped whole, and switching it would change
legacy trees' types); `Popover` content (already any `ElementGroup`).

**Cost if wrong.** A container left out is a compile error in a port, not a
silent difference.

---

## PE-F — Proposal-only modifiers on legacy content; `Pixels.infinity`

**Ruling.**

1. `layoutPriority(_:)`, `fixedSize(horizontal:vertical:)`/`fixedSize()`,
   `gridCellColumns(_:)`, `gridCellAnchor(_:)` (both overloads),
   `gridColumnAlignment(_:)` and `gridCellUnsizedAxes(_:)` gain spellings on
   `ElementGroup` that wrap `LegacyContent(self)` and apply the proposal
   modifier (`ModifiedContent<LegacyContent<Self>, LayoutModifier>`,
   `GridCellModifier<LegacyContent<Self>>`). None of these names exists on
   `StyledElement` or `ElementGroup` today (spec §1.1), so nothing becomes
   ambiguous; for proposal content the `ProposalElementGroup` spelling wins
   by refinement, as `.frame` already does. In a legacy container the result
   is a proposal layer over a legacy element (`LR-T`) — a new capability
   there, not a change.
2. `Pixels.infinity` (`MetalUICore`), so SwiftUI's
   `.frame(maxWidth: .infinity)` compiles (today `Pixels(.infinity)`; the
   configurator writes it in every pane).
3. Not offered: `aspectRatio`/`scaledToFit`/`scaledToFill` on legacy content
   (no control needs them; spec §11).

**Cost if wrong.** A missing spelling is a compile error.

---

## PE-G — `Text` in a proposal container is `ProposalText`'s answer

**Ruling.** The legacy `Text` composes through `LegacyContent` and lays out
exactly as `ProposalText` (measured: identical answers to all six proposals
for a short and a wrapping string; both use `proposalTextMeasurement`, with
baselines, so `.firstTextBaseline` works). `ProposalText` and
`Text.proposalLayout()` stay, undeprecated: deprecating them would put a
`warning:` in every test that uses them (0-warning rule); a later closeout
owns it. `docs/migration.md`'s `Text` → `ProposalText` row is rewritten:
"`Text` works in a proposal container; `ProposalText` remains for the
proposal modifier spellings (`.background` returning a layer)".

**Cost if wrong.** None silent: spec test 1.10 compares the two element by
element.

---

## PE-H — The guards that flip, and their new controls

**Ruling.** These assert the old rejection and change in this branch (the
prototype reddened the first seven; the Grid and scroll-view arms follow from
`PE-E`):

| test | change |
|---|---|
| `proposalLayoutConstructorsRequireProposalContent` | the `HStack`/`VStack`/`ZStack`/`ProposalScrollView` legacy arms move to the positive block; the `ProposalFrame`/`Padding`/`Background`/`FixedSize`/`ModifiedContent`/`OnTapModifier` arms stay negative; the last arm (`HStack { Text("legacy").overlay { Rectangle() } }`) becomes positive |
| `proposalOverlayAcceptsProposalContentAndRejectsLegacyContent` | its negative arm takes `ProposalFrame { … }` as the container |
| `aProposalContainerRejectsAScopeOverLegacyContent` | renamed `aProposalContainerAcceptsAScopeOverLegacyContent`; the negative becomes `ProposalFrame { Box().environment(…) }` |
| `anIfElseAndASwitchCompileInEveryProposalContainer` | its control arm (legacy content must fail) takes `ProposalFrame` |
| `anIDOnAProposalGroupEntersAProposalContainer` | control arm → `ProposalFrame` |
| `theLegacyBackgroundKeepsTheTokenOverloadAndTheProposalSpelling` | control arm → `ProposalFrame` |
| `aForEachOfLegacyContentDoesNotCompileInsideAProposalStack` | renamed `aForEachOfLegacyContentCompilesInsideAProposalStack`, positive; a new negative `ProposalFrame { ForEach(…) { Box() } }` |
| `aGridRejectsLegacyContent` | renamed `aGridAcceptsLegacyContent`, positive; negative → `ProposalFrame` |

Each flipped guard keeps a separating control (`docs/practices/verifying-tests-can-fail.md`):
a guard with only a positive arm is not a guard. Each **new** guard is
mutated red once (spec §6.1).

---

## PE-I — What does not move, and why

**Ruling.** No control's code changes except the three measurement lines of
`PE-D`; `LegacyContent` registers nothing (`PE-C` item 5). So hit testing
(one hitbox each, the one ranking), focus and Tab order, `ControlKeys`, the
`.disabled` gate, accessibility records on both bridges, animation helpers
(`animated`, `animatedBackground`), drag previews (`paintDecoration`, `DN-X`),
`List` windowing and `TB-AH`, `Deferred`, text input and the seven slots are
the legacy element's own, **in either vocabulary**. Spec §6.1 tests 1.11–1.19
pin each inside a proposal stack against the same tree in a `Row`/`Column`
(both vocabularies agree), so a later change to the adapter that broke one
reddens by name.

---

## PE-J — MG-15, measured: box the `Component` layout record

**Measured** (debug, macOS arm64, the stack high-water mark below
`Frame.render`'s entry, sampled at every native leaf; scratch tests; a
"pane" is a `Component` over a `Column` of twelve three-element `Row`s —
`Content` 48 360 bytes, `GroupLayout` 1 984 — and a "shell" a `Component`
whose `content` `switch`es over N distinct pane types):

| tree | e54c3f6 | box `ComponentLayout` | indirect `EitherGroup` layouts | both |
|---|---|---|---|---|
| pane alone | 423 984 | 172 304 | 423 984 | 172 304 |
| shell 2 | 626 944 | 173 840 | 274 448 | 173 776 |
| shell 4 | 728 608 | 174 832 | 275 376 | 174 704 |
| shell 8 | 830 272 | 175 824 | 276 304 | 175 632 |
| shell 12 | 931 936 | 176 816 | 277 232 | 176 560 |
| inline 2 (one `Component`, two inline `Column` branches) | 622 448 | 370 688 | 608 496 | 366 656 |
| inline 12 | 1 217 552 | 965 792 | 1 191 504 | 949 664 |

At e54c3f6 every shell level adds ~100 KB: `ComponentLayout<C>` stores
`C.Content` and `C.Content.GroupLayout` inline (50 344 bytes for a pane), so
each `EitherGroup` level's debug frame holds pane-sized layout temporaries.

**Ruling.** `ComponentLayout<C>` keeps its content and content layout in one
heap box (a `final class` holding a `Payload` struct), mutated in place
through `withPayload(_:)` by `prepaintGroup`/`paintGroup` — the shape the
interrupted design prototype took (scratch patch; whole suite green, 2550 =
2546 + 4 scratch). `ComponentLayout` is 8 bytes. Measured: a shell over 12
panes costs **4.5 KB** more than one pane (was 508 KB), and one pane 59 %
less. `EitherGroup.Layout`/`Prepaint` stay **direct**: `indirect` alone
flattens the shell growth but leaves a pane at 424 KB, and on top of the box
it saves 1.6 % (inline 12: 965 792 → 949 664) for two heap allocations per
evaluated conditional per frame.

**Cost.** One heap allocation per `Component` per laid-out frame (the box is
created in `requestGroupLayout`). Recorded as a figure, not gated (spec test
2.6). `ComponentLayout` is a public type whose stored properties change:
`swift package clean` after the change (CLAUDE.md). The layout box is shared
by copies of the layout value; a layout record is produced fresh each frame
and owned by the frame, so no copy is ever expected to be independent (the
whole suite agreed).

---

## PE-K — What remains: an inline switch, and the rule

**Measured** (`PE-J`'s table, "inline" rows): a `switch` of inline subtrees
inside **one** builder still grows with the sum of its branches after the box
(370 → 966 KB from 2 to 12 branches) — a debug build reserves a slot for
every temporary the `content` getter holds, in every branch (the effect
record §50 measured for the demo's builder closures). This is a compiler
property; MetalUI's only lever is the size of element values (deferred,
`PE-A`).

**Ruling — the rule.** *A branch that holds a large subtree goes in its own
`Component`.* That is the configurator's own shape (its panes are
`Component`s), and with `PE-J` it costs one allocation per frame and no
stack; it needs no eraser. `AnyElement(Box { … })` keeps working but is
neither needed nor recommended for stack depth. `docs/migration.md` and the
`Component` doc comment state the rule with `PE-J`'s numbers. An
`ElementGroup` eraser (MG-22) is deferred: nothing in this item needs it.

---

## PE-L — The failure is loud: a stack meter and a one-time warning

**Ruling.** A debug-only meter (`StackMeter`, internal, `@MainActor`):

1. `StackMeter.measuring(_:)` records the stack pointer at entry and returns
   the high-water mark of the body; samples outside a `measuring` scope are
   ignored. `Window` wraps each frame's build-and-render in it; tests wrap
   what they measure.
2. Samples — the deepest points a tree reaches: every `ElementBuilder` method
   (so the `content` getter's own frame is seen, which a layout-time sample
   misses: the getter has returned before its children register), every
   `Component` layout entry (typed and untyped; remembering the deepest
   `Component`'s type), and `Frame.requestNativeLeaf`.
3. Enabled only when `_isDebugAssertConfiguration()` (a release build's
   frames are a fraction of the size and sampling costs nothing there); one
   pointer read and compare per sample.
4. **`Window` warns once** when a frame's high-water mark exceeds **512 KiB**
   — half of Windows' 1 MiB thread stack, the smallest MetalUI supports —
   through an internal sink (default: one line on standard error) naming the
   figure, the deepest `Component` type, and `PE-K`'s rule. It never traps:
   a debug app on an 8 MB main thread may legitimately pass 512 KiB.

SwiftUI has no answer (its debug frames are its own); gpui has none either
(its element trees are boxed `AnyElement`s on the heap, which is the
"shrink the values" lever `PE-A` defers).

*(Refuted in part by `PE-T`: with the meter as landed a boxed pane reads
1 010 368 bytes, not 172 KB — the design's figures were leaf samples only —
and four production trees are above 512 KiB; item 4 is suspended.)*

**Why 512 KiB.** One pane is 172 KB after `PE-J`; every production tree must
lay out under the threshold (spec test 2.5 — the counted bound that protects
Windows), and the inline-12 tree (950 KB) must warn (test 2.4).

**Cost if wrong.** A false warning is one line on stderr; a missed one is
today's crash, no worse.

---

## PE-M — Lanes, demo, human checks

*(Lane contents and order revised by `PE-O`: `PE-D` moves to lane 2, which runs first.)*

**Ruling.** Three lanes on disjoint files (spec §10): lane 1 (Opus) the
builder, adapter, sizing, modifiers and their tests; lane 2 (Opus) MG-15 and
the meter; lane 3 (Sonnet, after 1 and 2) docs, inventory, divergences, the
demo section and human checks. The demo gains a "SwiftUI vocabulary" section
in the **controls** demo (`METALUI_CONTROLS_DEMO=1`), in its own function
(Windows 1 MB rule) — the controls demo is not one of the fourteen offscreen
images, so they stay 0 px. Human checks group **V**.

---

## PE-N — Divergences 130 and 131

**Ruling.**

- **130 — controls below their ideal size.** SwiftUI compresses a Button to
  10x8 at a zero offer and a menu Picker or Menu to 50 at a 50 offer
  (`FL0`, `FL8`, `FL13`); MetalUI's Button keeps 24x24 at zero (its strut
  and padding), the menu Picker 67 and the Menu wraps its label (49.64x64)
  at 50. Pin: spec test 1.1's `zero`/`w50` arms. Owner: none (kept).
- **131 — control metrics.** `TextField` is one line tall (16) with an ideal
  of its text or placeholder + 1 (`FL3`: SwiftUI 24 tall, 47.50); the menu
  Picker's ideal is 112.56 (124.50), the Menu's 80.66 (93), the Toggle 16
  tall (16.42). Pin: test 1.1's `ideal` arms. Owner: MG-20 (field chrome).

The stack spacing at a text edge (`FM0`'s row origins 48.15, 76.89, 101.04 where MetalUI's are 40, 72, 96) is CN-H's existing note,
and text widths (17.23 vs 17.50) divergence 60 — not new rows.


---

## PE-O — Critic pass: the lanes re-cut, sizing first

**Found.** Spec §10 listed lane 1 with 13 source files, 24 tests and the 8
flipped guards against lane 2's 7 tests, and called the lanes disjoint while
spec §4 item 1 has lane 2 edit the `Component` typed default in
`ProposalNodeID.swift` (~line 125), a file §10 gave lane 1 ("header only")
and lane 2 not at all. Its merge order ("2 then 1, or either") contradicted
§6.1, whose 1.1, 1.5 and 1.22 assert values only `PE-D` produces.

**Ruling.** `PE-D` (the three measurement closures, `SliderTests`, tests 1.9
and 1.23 in a new `GreedyControlSizingTests.swift`, and the fourteen-image
re-take straight after it) moves to **lane 2**, which runs **first**; lane 1
(builder, adapter, modifiers, guards, the rest of §6.1) second; lane 3 third
— one at a time in this worktree. `ProposalNodeID.swift` is listed for both,
sequentially (lane 2 the typed default, lane 1 the header). Neither 1.9 (a
test-local `LegacyUnderProposal`) nor 1.23 (a legacy `Row`) needs the builder.

**Cost if wrong.** None silent: a lane order slip is a red 1.1/1.5/1.22.

---

## PE-P — The stack meter tolerates a sample from another thread

**Found.** `PE-L` item 2 samples in every `ElementBuilder` method, and
`everyProductionTreeBuildsOnAOneMegabyteThread` (`DemoStackBudgetTests.swift`
62–66) runs every production builder on a secondary thread through an
`unsafeBitCast` of a `@MainActor` function — on Linux and Windows CI too. A
`sample()` that asserted isolation would trap that test; one that counted the
secondary thread's stack pointer against the main thread's entry would record
a nonsense high-water mark if a scope were open.

**Ruling.** `sample()` asserts no isolation (no `assumeIsolated`, no
`dispatchPrecondition`) and counts only when a scope is open **and**
`Thread.isMainThread` (Foundation, portable; `Window` and every measuring test
run on the main thread). Test 2.3 gains a secondary-thread arm (a `Thread`
joined with a semaphore — no sleep) and mutation M2.3b (drop the check); the
existing one-megabyte test is the trap guard and must stay green.

**Cost if wrong.** Debug-only: a trap in one CI test, or a false warning line.

---

## PE-Q — `List` in a proposal container keeps divergence 84

**Found.** `PE-D` says "every other control is already in SwiftUI's class",
but spec §1.3's table omits `List(selection:)`; the probe's `FL14` (re-run by
the critic pass, all 95 lines byte-identical to the recorded output) reads
SwiftUI's list greedy on both axes (ideal 0x0, `inf -> infxinf`), while
MetalUI's answers `rowHeight × count` (divergence 84, `DD-AB` item 3).

**Ruling.** Not changed: the list's height answer is its windowing contract
(`DD-F`, `TB-AH` — must not move). Test 1.1 gains a `List` row pinning
MetalUI's measured answers to the six proposals and citing divergence 84; no
new divergence; `PE-D`'s sentence reads "every other control but `List`
(divergence 84)".

**Cost if wrong.** None new: divergence 84 already documents it.

---

## PE-R — Style modifiers are written on the control (rejection of the container form)

**Found.** The item lists `.buttonStyle`, `.pickerStyle` and
`.keyboardShortcut` among modifiers that must work on the proposal path. They
are value modifiers returning `Self` on the control (`Button.swift` 187, 199,
205, 212; `Picker.swift` 118): with `PE-B` they work on a control inside any
stack, but not on a container or after a wrapper
(`Button("x") {}.padding(8).buttonStyle(.plain)`). The design said nothing.

**Ruling — rejected for this branch.** Making them environment values changes
every control's chrome resolution, outside MG-1; the configurator's original
SwiftUI-style source writes none of the three anywhere (critic grep of
`main`'s `Sources/`), so the port has no need. The probe has no arm for a
container-level style, so **no SwiftUI behaviour is claimed** here. Test 1.3
gains a second control arm — the wrapper-then-style spelling fails to
compile — measured by lane 1 at `e54c3f6` first (if it already compiles, the
arm and this ruling's premise are void and the lane says so).
`docs/migration.md` (lane 3) states the rule: write them on the control,
before any wrapper. Owner: the gpui-gap list.

**Cost if wrong.** A compile error in a port that writes the container form.

---

## PE-S — Tests that compare vocabularies also assert literals; M1.11 rewritten

**Found.** (1) Tests 1.13 and 1.14 asserted only that the `HStack`/`VStack`
spelling equals the `Row`/`Column` one, yet their named mutations (M1.13
`Toggle`'s role, M1.14 `Stepper`'s focusability) change a control, which
changes both spellings alike — the equality stays true, so neither mutation
could redden (a broken instrument). (2) M1.11 ("`LegacyContent.prepaintGroup`
skips its content") is unwritable: `prepaintGroup` must return
`Content.GroupPrepaint`, which only the content's own prepaint produces.

**Ruling.** 1.13 asserts the literal roles, labels and values and 1.14 the
literal Tab-order id list, each written in the test, **and** the
cross-vocabulary equality. M1.11 becomes "run the content's prepaint twice (a
discarded first call)" — two hitboxes at the Button's frame redden 1.11's
"one hitbox" arm. M1.12 (`paintGroup` returns `Void`) stays.

**Cost if wrong.** A mutation table that cannot redden certifies nothing.

---

## PE-T — Lane 2's measurement refutes `PE-L`'s 512 KiB threshold; the window warning waits

**Found** (lane 2, with `StackMeter` as landed — samples in every
`ElementBuilder` method, both `Component` layout entries and
`Frame.requestNativeLeaf`; debug, macOS arm64; each production tree built and
rendered once into a `Frame` at 920×560 inside `measuring`, spec test 2.5's
procedure). Bytes of stack below the measurement's entry:

| tree | before `PE-J` (`da3552d`) | after `PE-J` (`6631623`) |
|---|---|---|
| `demoContent()` | 837 904 | **837 904** |
| `nativeLayoutPreviewContent()` | 104 032 | 76 512 |
| `textInputDemoContent()` | 117 296 | 117 296 |
| `controlsDemoContent()` | 2 199 024 | **826 336** |
| `looksDemoContent()` | 3 522 752 | **1 061 408** |
| `dragAndDropDemoContent()` | 924 528 | 401 248 |
| `metalViewDemoContent(…)` | 489 728 | 281 520 |
| `menusDemoContent()` | 668 752 | **668 752** |
| `servicesDemoContent()` | 2 067 440 | 328 944 |

**Four of the nine production trees are above 512 KiB after the box** (bold),
and the looks demo above 1 MiB. `PE-L`'s premise — "every production tree must
lay out under the threshold" — was not measured by the design session (its
table is synthetic trees only), and spec test 2.5 says that if any production
tree is at or above the threshold, the lane stops and `PE-L` is re-taken. The
lane stopped there.

**Why the design's figures were smaller.** The design session sampled at
native leaves only. Re-measured that way on this branch (builder samples
removed, before the box): pane 408 704 (design 423 984), shell 12 916 448
(design 931 936), `demoContent()` 500 912 — the instrument agrees with the
design's. Builder samples see the `content` getters' own frames, which a
leaf sample misses (the getter has returned before its children register —
`PE-L` item 2's own reason): the boxed pane reads 1 010 368, not `PE-L`'s
"172 KB" (leaf samples only, under mutation M2.2: 207 488); inline 2 → 12
reads 1 300 704 → 4 300 576 (leaf only: 405 824 → 1 000 736). `PE-J`'s ratios hold
under the full meter (shell 12 − pane: 507 744 → 4 512 bytes; test 2.1).

**Ruling.** `PE-L` items 1–3 (the meter, its samples, debug-only, and
`PE-P`'s main-thread rule) stand and are landed, with tests 2.1–2.3. **Item 4
(the `Window` warning) and spec tests 2.4 and 2.5 are suspended until `PE-L`
is re-taken against this table** — a warning that fires in four of the
repository's own demos in every debug run is noise, and a threshold above
them has to be chosen, not derived. The figures a re-take can use: the
largest production tree is 1 061 408 bytes; the inline-12 synthetic shell
(the failure the warning exists for) 4 300 576; macOS's and Linux's main
threads have 8 MiB and Windows' 1 MiB (record §50). Whether the looks demo's
1.04 MB on macOS arm64 overflows a 1 MiB Windows thread is **not measured**
(no Windows debug run of it; `DemoCapture` builds `demoContent()` only).
Spec §6.2's rows 2.4 and 2.5 stand as written apart from the threshold; lane
2 wrote and ran both against 512 KiB (2.4 red until item 4 lands; 2.5 red on
the four trees above) and withdrew them with item 4.

**Cost if wrong.** None silent: the meter is internal and warns nobody; the
crash it exists to explain is today's behaviour, no worse.

---

## PE-U — Lane 2's mutation table and figures

**Mutations** (each on a committed tree, restored from git, the **full
unfiltered** native suite per mutation — 2552 tests — and `git status --short`
clean of sources after each; the line numbers are the branch's at `9596802`):

| id | mutation (file — spelling) | reddened |
|---|---|---|
| M1.9a | `TextField.swift` — `proposal.width.flatMap { $0.isFinite ? $0 : nil }` again | `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` (its two `TextField` ∞ arms only) |
| M1.9b (= M1.5's) | `Slider.swift` — `proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth` | `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` (the slider arm), `aLegacyRowServesItsSliderLast` (all three arms), `aSliderIsGreedyOnTheWidthAndSixteenTall` (its ∞ arm) |
| M1.9c | `TextEditor.swift` — both axes' `isFinite` filters again | `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` (the editor arm only) |
| M2.1 | `Component.swift` — `ComponentLayout` stores `var payload: Payload` inline (`mutating withPayload`); `swift package clean` before and after | `aShellOverTwelveComponentPanesUsesTheStackOfOnePane` |
| M2.2 | `ElementBuilder.swift` — all seven `StackMeter.sample()` calls removed | first spelling of 2.2 (laid-out difference only): **nothing** — re-spelled with the getter-alone arm; then `theStackMeterSeesTheContentGettersFrame` |
| M2.3 | `StackMeter.swift` — `sample()` drops `scope != nil` and opens a scope at its own address | `theStackMeterMeasuresOnlyInsideAMeasurement` (the outside-sample arm) |
| M2.3b | `StackMeter.swift` — `sample()` drops `Thread.isMainThread` | first spelling (a Foundation `Thread`): **nothing**, its stack is above the main thread's on macOS arm64 — re-spelled on a stack mapped below it; then `theStackMeterMeasuresOnlyInsideAMeasurement` (the secondary-thread arm); `everyProductionTreeBuildsOnAOneMegabyteThread` green |
| M2.7 | `Component.swift` — `withPayload` mutates a copy (`var p = storage.payload; return body(&p)`) | `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` traps (`AnyElement.swift:177`, "AnyElement.paint before prepaint"), truncating the run; the unmutated suite finishes — so spec test 2.7 is **not** added (its condition: only if nothing reddens) |

**Figures** (debug, macOS arm64; for record §78):

- Stack, `StackMeter` as landed (builder samples included), bytes: pane
  1 211 584 → 1 010 368 with `PE-J`; shell 2 1 414 432 → 1 011 904; shell 12
  1 719 328 → 1 014 880 (shell 12 − pane 507 744 → 4 512); inline 2
  1 501 984 → 1 300 704; inline 12 4 501 856 → 4 300 576; the inline-12
  getter alone 4 245 472. Production trees: `PE-T`'s table.
- Allocations (spec test 2.6, `METALUI_COMPONENT_ALLOC_MEASURE=1`): one
  `Component` costs **2.00 allocations / 152 bytes** per settled frame boxed,
  **1.00 / 56** with the payload inline (under M2.1) — the box adds **+1.00
  allocation / 96 bytes per `Component` per frame**, `PE-J`'s expectation.
- `PE-D`: the fourteen offscreen images 0 px, every scene identical,
  `e54c3f6` → `4da5a7f`; and `e54c3f6` → `9596802` (box and meter) the same.

---

## PE-V — A `ProposalScrollView` publishes its `ScrollContext` (lane 1)

**Found** (lane 1, measured with `PE-B` landed and nothing else changed):
spec test 1.18 — `ProposalScrollView { VStack { List(40 rows, rowHeight: 20,
selection:) } }` in a 200×100 frame, two frames drawn — realised **all forty
rows** (rows 0…39 recorded in `Window.lastElementBounds`). A `List` windows
against `LayoutPass.scrollContext` (`DD-F`), and `ScrollContext` publication
was `ScrollView`'s alone: `ScrollChrome.swift`'s header ruled it so (`LR-BF`)
because "nothing can read one from a `ProposalScrollView`" — true until `PE-B`
made a `List` legal content there. So a SwiftUI-vocabulary port's selectable
list would silently lose its windowing (O(count) per warm frame), the
`TB-AH` contract the item lists as must-not-move.

**Ruling.** `ProposalScrollView.requestProposalLayout` publishes the same
context `ScrollView.requestLayout` does — the raw stored offset and last
frame's viewport from the one `ScrollState` both scrollers' `ScrollChrome`
writes, pushed with `withScrollContext` around its content's typed entry (a
sibling after the scroller sees none). Nothing else reads `scrollContext` but
`List` (and `Deferred`, which resets it), so no existing tree moves: the
proposal scroller's content held no `List` before this branch. `ScrollChrome`'s
header comment is corrected. Spec test 1.18 stands as written; its new
mutation M1.18b (the publication removed) must redden it.

**Cost if wrong.** A `List` in a `ProposalScrollView` windows against a stale
or wrong context: the same exposure a `List` in a `ScrollView` has always had,
pinned there by `DD-F`'s tests and here by 1.18.

---

## PE-W — A ninth guard flips; two measured spellings (lane 1)

**Found** (lane 1's first full run with the containers switched: 2573 tests,
one failing): `aCustomLayoutContainerRejectsLegacyContent`
(`ProposalLayoutCompileGuards.swift`, ruling SA-F) asserts that
`Diagonal() { Text("legacy") }`, `Diagonal { … }` and
`ProposalLayoutContainer(Diagonal()) { … }` fail — `PE-E` switches exactly
those spellings, but `PE-H`'s table (from a prototype that switched only the
three stacks) omits it.

**Ruling.**

1. It flips with the other eight: renamed
   `aCustomLayoutContainerAdoptsLegacyContent`, each spelling now typechecks
   as `ProposalLayoutContainer<Diagonal, LegacyContent<Text>>`, and its
   separating control is `ProposalFrame { Text("legacy") }` failing on
   `ProposalElementGroup`. Spec test 1.24 is nine guards.
2. `PE-R`'s second control arm in test 1.3 is spelled
   `Button("x") {}.padding(8).buttonStyle(.plain)`: measured before the
   implementation, the spec's `.padding(Edges(all: 8))` fails twice (`Edges<Int>`
   is not `Pixels`, then no `buttonStyle` on `ModifiedContent<Button<Text>,
   ModifierLayer>`) — `PE-R`'s premise holds, and the arm fails for the one
   reason it is about.
3. Test 1.1's `List` row (`PE-Q`) pins MetalUI's measured answers: 0×60 at
   zero, 37.26×60 at nil and at h200, **∞×60** at ∞ (its width greedy), 200×60
   and 50×60 at the finite widths — height `rowHeight × count` at every
   proposal (divergence 84).

**Cost if wrong.** None silent: each is a pinned test.

---

## PE-X — Lane 1's mutation table, and two corrections

**Mutations** (each on the committed tree `ae49352`, restored from git, the
**full unfiltered** native suite per mutation — 2573 tests, or fewer where a
file that no longer compiles was set aside, named — and `git status --short`
clean after each). Every new test and guard reddened under its named mutation.

| id | mutation (file — spelling) | reddened |
|---|---|---|
| M1.1a | `TextField.swift` — `let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }` | `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` |
| M1.1b | `Toggle.swift` — label gap 7 → 8 | `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`, `aToggleIsAFourteenPointCheckboxSevenPointsBeforeItsLabel` |
| M1.2 | `ProposalContentBuilder.swift` — the `ProposalElementGroup` `buildExpression` deleted | the test target stops compiling (`LoweringScrollTests.swift`'s `-> ProposalScrollView<Rectangle>` helper: 6 errors, `cannot convert … 'LegacyContent<Rectangle>' to … 'Rectangle'` — a second, compile-time pin); with that file set aside (2561 tests): `proposalContentKeepsItsTypeAndLegacyContentIsAdopted`, `aGridAcceptsLegacyContent`, `aGridRowAlignmentIsAVerticalAlignment`, `theAccessibilityModifiersCompileFromAPlainImport` |
| M1.3 | `Grid.swift` — `GridRow.init` back to `@ElementBuilder` | (`ProposalControlsTests.swift` set aside: it no longer compiles; 2555 tests) `aSwiftUIVocabularyFormTypechecksWithAPlainImport`, `aGridAcceptsLegacyContent` |
| M1.4a | `LegacyContent`'s typed entry — a fresh cursor | 10 tests: `aLegacyControlTakesTheIDAProposalElementWouldInItsPosition`, `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`, `theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary`, `aPresentationInsideAProposalStackTakesNoSlot`, `textInAProposalStackLaysOutAsProposalText`, `accessibilityRecordsOfControlsAgreeAcrossVocabularies`, `tabVisitsControlsInAProposalStackInTreeOrder`, `aShortcutHelpAndHoverWorkOnAButtonInAProposalStack`, `theProposalOnlyModifiersReachLegacyContent`, `aGridFormGivesItsFieldColumnTheRest` |
| M1.4b | `LegacyContent`'s typed entry — enters a member level (`positional(cursor)`, cursor + 1) | 12 tests, among them `aLegacyControlTakesTheIDAProposalElementWouldInItsPosition`, `aButtonInAProposalStackHasOneHitboxAndActsAsInARow`, `aLegacyFrameAnimatesInsideAProposalStack`, `aDragFromAControlInAProposalStackCarriesAPreview` |
| M1.5 (= M1.22) | `Slider.swift` — `proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? idealWidth` | `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `aLegacyRowServesItsSliderLast`, `aSliderIsGreedyOnTheWidthAndSixteenTall`, `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` — **not** `aGridFormGivesItsFieldColumnTheRest` (see correction 2) |
| M1.6 | typed entry — `nodes.reversed()` before minting | `theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary` (its `ForEach` spelling) |
| M1.7 | typed entry — consumes each node's record | `aLegacyItemFieldInAProposalStackIsReportedByName` |
| M1.8 | typed entry — `droppingPresentations` removed | `aPresentationInsideAProposalStackTakesNoSlot` |
| M1.10 | `Text.swift` — measured at `ProposedSize(width: nil, height: proposal.height)` | 27 tests, `textInAProposalStackLaysOutAsProposalText` among them |
| M1.11 | `LegacyContent.prepaintGroup` — the content's prepaint run twice | `aButtonInAProposalStackHasOneHitboxAndActsAsInARow`, `aShortcutHelpAndHoverWorkOnAButtonInAProposalStack` |
| M1.12 | `LegacyContent.paintGroup` — skips its content | `aControlInAProposalStackPaints`, `aDragFromAControlInAProposalStackCarriesAPreview` |
| M1.13 | `Toggle.swift` — default role `.button` | 10 tests, `accessibilityRecordsOfControlsAgreeAcrossVocabularies` among them |
| M1.14 | `Stepper.swift` — `composed.isFocusable = false` | 6 tests, `tabVisitsControlsInAProposalStackInTreeOrder` among them |
| M1.15 | `Window.swift` — `if false && self.dispatchShortcut(event)` | 11 tests, `aShortcutHelpAndHoverWorkOnAButtonInAProposalStack` among them |
| M1.16 | `ModifiedContent.swift` — the legacy layer's `animated(_:_:for:pass:)` call removed | 15 tests, `aLegacyFrameAnimatesInsideAProposalStack` among them |
| M1.17 | `Text.swift` — `paintGlyphs` outside `paintDecoration` | 11 tests, `aDragFromAControlInAProposalStackCarriesAPreview` among them |
| M1.18 | `List.swift` — `context.viewportExtent > .infinity` (always `0..<count`) | 36 tests, `aSelectableListInAProposalScrollViewWindowsAndSelects` among them |
| M1.18b | `ProposalScrollView.swift` — the published context's viewport 0 (`PE-V` disabled) | `aSelectableListInAProposalScrollViewWindowsAndSelects` |
| M1.19 | `Popover.swift` — `layOutPopover` never presents | 20 tests, `aPopoverOnAButtonInAProposalStackPresents` among them |
| M1.20 | `LegacyProposalModifiers.swift` — `LegacyContent(self).layoutPriority(0)` | `theProposalOnlyModifiersReachLegacyContent` |
| M1.21 | `Units.swift` — `Pixels.infinity` deleted | (`ProposalControlsTests.swift` set aside; 2555 tests) `pixelsInfinityIsSwiftUIsFrameSpelling`, `aSwiftUIVocabularyFormTypechecksWithAPlainImport` |
| M1.24 | `NativeElements.swift` — both `ProposalFrame` inits `@ProposalContentBuilder` | the nine flipped guards (`proposalLayoutConstructorsRequireProposalContent`, `proposalOverlayAcceptsProposalContentAndRejectsLegacyContent`, `aProposalContainerAcceptsAScopeOverLegacyContent`, `anIfElseAndASwitchCompileInEveryProposalContainer`, `anIDOnAProposalGroupEntersAProposalContainer`, `theLegacyBackgroundKeepsTheTokenOverloadAndTheProposalSpelling`, `aForEachOfLegacyContentCompilesInsideAProposalStack`, `aGridAcceptsLegacyContent`, `aCustomLayoutContainerAdoptsLegacyContent`) and `aSwiftUIVocabularyFormTypechecksWithAPlainImport` |

**Review of lane 1** (re-verification on `e3d38b3`; each mutation applied to
the committed tree, restored from a copy, full unfiltered native suite —
**2578 tests in 3 suites**, the unmutated suite passing after a
`swift package clean` — and `git status --short` clean after each). The
review found five `LegacyProposalModifiers.swift` spellings and `PE-V`'s
offset half unpinned (V1–V3 green on `982fa21`, 2573 tests); tests 1.18b and
1.20b–e close them, each reddened under its mutation:

| id | mutation (file — spelling) | reddened |
|---|---|---|
| V1 | `LegacyProposalModifiers.swift` — `fixedSize` forwards `horizontal: vertical, vertical: horizontal` | `fixedSizeOnLegacyContentForwardsEachAxis` (both arms) |
| V2a | `LegacyProposalModifiers.swift` — `gridColumnAlignment(.trailing)` whatever it is given | `gridColumnAlignmentOnLegacyContentAlignsItsColumn` (the `.leading` arm) |
| V2b | `LegacyProposalModifiers.swift` — both `gridCellAnchor` spellings pass `.topLeading` | `gridCellAnchorOnLegacyContentPlacesItInItsCell` (the nine-point and `UnitPoint` bottom-trailing arms) |
| V2c | `LegacyProposalModifiers.swift` — `gridCellUnsizedAxes([])` | `gridCellUnsizedAxesOnALegacyControlTakesItsColumnsWidth` (the marked arm) |
| V3 | `ProposalScrollView.swift` — `ScrollContext(offset: 0, viewportExtent: lastViewportExtent, axis: axis)` | `aListInAScrolledProposalScrollViewWindowsAtItsOffset` (row 20 not realised after a 400-pt wheel) |

**Corrections.**

1. Spec test 1.13's "M1.11 (prepaint half) reddens it too" is **refuted**:
   under M1.11 1.13 stays green (the tree builder keys records by id, so a
   doubled emission collapses). 1.13 is reddened by M1.13 and M1.4a; spec row
   and the test's doc comment corrected.
2. Spec test 1.22's mutation M1.22 (`Slider`'s `PE-D` reverted) does **not**
   redden it: inside a `Grid` the slider's column is sized by the grid's own
   distribution, which offers the greedy column the rest whatever the
   slider answers at ∞. The test still separates — M1.4a and M1.4b redden
   it — so it stands as a grid-form layout pin, without `PE-D` as its
   mutation.
3. Spec test 1.6's M1.6 reddens only through a multi-node adopted expression;
   the test gained a second spelling (the middle labels as one `ForEach`).

---

## PE-Y — Lane 3: the demo section beside the controls, its state, V5 suspended

**Found** (lane 3, measured with lanes 1 and 2 landed).

1. *Placement.* Spec §7 put the section "under" the demo's controls. Placed as
   the last child of the controls (and, in a first try, as a third child of
   the chores/list row), the demo's content measured ≈ 583 points tall
   (headless, `LayoutDifferential` at 920×560: the status bar ended at 560
   before the 24-point padding), so in the 920×560 window the centred root
   (`CN-J`) would cut its top and bottom. Beside the controls it measures
   828×456: the legacy controls keep their origin (24, 24) and their order,
   the section starts at (404, 24).
2. *State.* Spec §7 wired the form to "the demo's existing `@State` (name,
   enabled, speed, flavour, quantity)"; the demo had no `name`, `enabled` or
   `speed`. Three `@State`s are appended after `picked` (so every existing
   `$state<n>` slot keeps its number); the form's menu picker shares `flavor`
   and its stepper `quantity` with the legacy controls, so V2 can see one
   control drive the other. `speed` starts at 0.75, not `FM0`'s 0.5: the
   accessibility audit (3.9) finds the legacy slider by its value `"0.4"`
   (`one(_:)` requires one match) and checks `"0.5"` after an increment, which
   a second slider at 0.5 would satisfy without the increment.
3. *Frame.* `.frame(maxWidth: 400)`, not `width:` — so V4 (narrower than the
   form) shows the greedy controls giving up width first (headless at a
   600-wide window: field 165, slider 161, Apply 59) instead of a clipped,
   fixed form. At 920 the section is 400 wide, the form `FM0`'s 400×177.
4. *Composer.* The controls demo has no composer; "its own function" is
   honoured as `swiftUIVocabularySection(…)` called from `ControlsDemo`'s
   content, with its form and status bar in two further functions. The
   section is inside a `Component`'s `content`, built at layout, so
   `everyProductionTreeBuildsOnAOneMegabyteThread` does not build it; spec
   §6.3's sentence saying it does is corrected (test 3.1 covers the layout
   in diagnostics mode, and also renders the whole controls demo).
5. *Test 3.1's literals.* The form's frames, relative to its own origin, are
   test 1.5's (`FM0`) except the menu picker: 145 wide over the demo's
   flavours ("Strawberry" is its widest option) where test 1.5's is 113 over
   "Alpha"/"Beta" — measured by lane 3, a hugging control (divergence 131's
   metrics). A `Button` records `.generic` and is a button by its click
   handler (`AB-H`), so 3.1 checks Apply by `isClickable`.

**Ruling.** As found: the section sits beside the controls, three appended
`@State`s, `.frame(maxWidth: 400)`; spec §6.3 and §7 corrected. **Human check
V5 is suspended with `PE-L` item 4** (`PE-T`): the warning it would observe is
not landed; V5 is re-written when `PE-L` is re-taken, and group V marks it
N/A. `docs/migration.md`'s "Large trees in a debug build" says the same: the
rule (`PE-K`) and the box (`PE-J`) are landed, the warning is not.

**Cost if wrong.** None silent: the placement and the state are a demo's;
3.1 and the audit tests pin what they read.

---

## PE-Z — Lane 3's mutation, and the controls demo's window tests pre-flight

**Found** (lane 3, M3.1 on the committed tree `e0e547e`, the full unfiltered
native suite, restored from a copy, `git status --short` clean after):
`ControlsDemo.swift` — the section's `TextField("Name", text: name)` gains
`.flexGrow(1)`. The run **trapped** inside
`theControlsDemoPublishesTheTreeTheVoiceOverScriptReads`
(`Frame.swift:2289: Fatal error: MetalUI: textField.flexGrow.unconsumed has no
proposal lowering and is refused by name`) — no summary line, the unmutated
suite finishing normally (2579 tests). Three window tests open
`controlsDemoContent()` in a production `Window` without a diagnostics
pre-flight: that one, `theVoiceOverScriptQuotesThePublishedTree` (through the
same `controlsTrees()`), and `theControlsDemoPublishesEveryControlsRole`.
Re-run with those three skipped (2576 tests): **one** test reddened,
`theControlsDemosSwiftUISectionLaysOutWithoutReports` (3.1, its `try #require`
on the empty report: `["textField.flexGrow.unconsumed"]`).

**Why it matters.** CLAUDE.md's rule — a window test in a mode that traps
pre-flights in a mode that reports — was satisfied by the demo before `PE-Y`
only because the legacy controls report nothing a lowered container would not
consume. The SwiftUI-vocabulary section is the first place in that demo where
a legacy item field is reported (`PE-C` item 4), so a regression there would
truncate the whole run.

**Ruling.** `AccessibilityAuditTests`' `scriptWindow` (every demo window the
VoiceOver-script tests open) and `theControlsDemoPublishesEveryControlsRole`
render their content once through `LayoutDifferential.render` with diagnostics
and `try #require` an empty report before opening the window — the change
that introduced the hazard carries the guard. M3.1 is re-run on the hardened
tree; its reddened list is the record's.

**Cost if wrong.** One extra diagnostics render per demo window test.
