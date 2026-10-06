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

Prefix **`PE-`**, lettered. **Next unused: `PE-O`.** (This line moves in the
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
49.36x48).

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
(the demo's every frame) unchanged. Lane 1 re-takes the fourteen images
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

**Why 512 KiB.** One pane is 172 KB after `PE-J`; every production tree must
lay out under the threshold (spec test 2.5 — the counted bound that protects
Windows), and the inline-12 tree (950 KB) must warn (test 2.4).

**Cost if wrong.** A false warning is one line on stderr; a missed one is
today's crash, no worse.

---

## PE-M — Lanes, demo, human checks

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

