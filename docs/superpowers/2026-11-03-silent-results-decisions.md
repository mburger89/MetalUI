# Silent results (round 4 item R4-1 PR A) — decisions (prefix `SR-`)

Rulings for the first of three R4-1 PRs ("six silent divergences": rows whose SwiftUI side was stated but not, or wrongly, measured). Branch
`feat/r4-1-silent-results`; the orchestrator's plan is not in the repo, its predictions are quoted where a probe refuted them. Code:
`Picker.swift`, `Toolbar.swift` (comments), `Button.swift`, `Toggle.swift`, `MenuContent.swift`, `Stepper.swift`, `ColorPicker.swift`,
`ProgressView.swift`, `PaddingSpellings.swift`, `Font.swift`, `TextMeasurer.swift`, `LayoutTree.swift` (comments). Probes (all recorded in their
headers, macOS 27.2, 2026-11-03): `swiftui-surface-text.swift` (E3-E8), `swiftui-toolbar.swift` (TB-A), `swiftui-control-titles.swift` (new),
`swiftui-switch-knob.swift` (new). Tests: `ToggleStyleTests.swift`, `MenuPickerTests.swift`, `ToolbarTests.swift`, `LocalizedStringKeyTests.swift`,
`ControlsCompileGuards.swift`, `SurfaceTextMeasureTests.swift`, `HarnessSettleTests.swift`. **Next unused: `SR-H`** (`SR-G` is R4-3a's, appended 2026-11-04, record 210). Divergences: 81 and 885 retired, 886
added (from BY's reserved 885-894), 154 narrowed, 295 and 208 reworded. Live count 208 to 207; next label 210 unchanged.

**Two predictions of the plan were refuted by probes** (stated in `SR-A` and `SR-D`); the rulings follow the probes.

## SR-A: an empty `Text` (divergence 295, reworded; amends `GT-C`, `GT-I`)

1. **The "0 by 0" was an instrument artifact.** `swiftui-surface-text.swift` `E2` read a `Text("")` view as (0, 0) through `ImageRenderer`, which returns no image
   for a zero-width view. By `NSHostingView.fittingSize` a `Text("")` is **(0, 14)**, equal to the Canvas measure `E`; in `VStack(spacing: 10) { rect; Text(""); rect }` it
   takes its 14 and both gaps (`E3`: 54 = 10 + 10 + 14 + 10 + 10), padded by 4 it is 8 by 22 (`E5`), beside `Text("x")` in a first-baseline `HStack` it changes nothing (`E4`).
2. **The plan's `textViewMeasurement` seam is not added**: it would have made MetalUI's layout and `TextMeasurer` say 0 by 0, which SwiftUI does not. Layout and
   measure stay as they were (width 0, one line tall), and the pin `anEmptyStringMeasuresAsItLaysOut` stays (it already pins 0 wide and the line's height; its comment is corrected).
3. **The residue, and why the row stays live.** SwiftUI's empty height is a **constant 14 at every font and size** (`E8`: `Text("")` 14 whether the font is 9, 13, 20 or 40 pt
   or `.title`; `Text(" ")` is 11, 16, 24, 47), not a function of the resolved font. MetalUI's is one line of the resolved font (16 at the 13 pt default, 18 in Noto Sans 13).
   They coincide only near 11 pt. A constant is not a rule MetalUI's font metrics express, and a measured SwiftUI constant needs a decision about a platform default
   font no other `Text` reads, so the difference is documented, not guessed. **Cost if wrong:** a layout that places an empty `Text` between rows is 2 to 4 points taller at 13 pt.
4. Every copy of "0 by 0" is corrected (`TextMeasurer.swift`, the `E2` reading in the probe header, the guide, `GT-C`/`GT-I` in the surface-text decisions with a note). Older record files stay as history; record 198 states the correction.

## SR-B: the automatic `Picker` is the pop-up menu (divergence 81 retired; reverses `SV-P` item 1, `DD-V` item 4, the `IX-M` clause)

1. `PickerStyle.automatic` is `.menu`. `SV-P` gave no technical reason to keep it segmented (PK0 equals PK1 `.menu` at 139 by 24).
2. **Toolbar gate, probe `TB-A`**: an automatic-style `Picker` as a `.principal` toolbar item hosts exactly the view list of an explicit `.menu` one (no `SystemSegmentedControl`);
   so `toolbarParts.isMenu` (which now reads true for the automatic style) is right and no `Kind.automatic` is needed. The `ToolbarTests` "auto" expectation is `.menu`.
3. Downstream scan (the plan's, at its commits): MetalFlow `e9d90ef` (12 `Picker`s, all with an explicit `.pickerStyle`) and MetalCreator `a98ed34` (9, all explicit): nobody relies on the automatic
   style. In this repo the two demo sites (`ControlsDemo`, `RetainedSubtreeDemo`) and 17 test fixtures say `.pickerStyle(.segmented)` so each keeps its meaning.
4. Migration (`docs/migration.md`): the title, 8, a button as wide as the widest option; role `popUpButton` for `radioGroup` with `radioButton` children (per-option identifiers, `SE-A`, are gone);
   arrow keys no longer step; options are recorded, not laid out (no `@State`, `onAppear`, `.id` inside an option); a non-`Text` option is titled by its tag (128).

## SR-C: control titles parse a literal (divergence 154 narrowed; reverses `RT-A`'s deferral)

1. **Probe `swiftui-control-titles.swift`**: for `Button`, `Toggle`, `Stepper`, `Picker`, `ColorPicker` and `ProgressView` a string literal `"**b**"` publishes the markup-free `b`
   (AXButton/AXCheckBox/AXProgressIndicator label, or the AXStaticText value) and a `String` variable publishes `**b**` (`AX1`-`AX6`, the variable arms `v` separate). `Menu("**b**")`
   publishes `b` as an attributed title (`AX8`). A `TextField` publishes no placeholder (`AX7`). `NSMenuItem` titles inside a `Menu` were **not measured** (a closed `Menu` hosts no pop-up button).
2. Each of `Button` (both inits), `Toggle`, `Menu`, `Stepper` (three), `Picker`, `ColorPicker` and `ProgressView` (both) has `init(_ titleKey: LocalizedStringKey, ...)` and a
   `@_disfavoredOverload init<S: StringProtocol>(_ title: S, ...)` (shown verbatim, `Text(verbatim:)`): `Text`'s own shape. `Stepper` and `Picker` store a `Text`, with `title` computed
   as `label.string`, which is what the accessibility label and the toolbar read, so they publish the markup-free text.
3. **Left plain, unmeasured:** `TextField`/`TextEditor` placeholders, alert titles; a native menu item's title is `label.string`, the markup-free string. Row 154 stays live for exactly these.
4. **Migration:** a literal containing a Markdown trigger (`*`, `_`, `` ` ``, `[`, `~`, `\`, `@`, `www.`) now parses; write the title as a `String` variable or the label as `Text(verbatim:)` to keep it literal.
5. Compile guard `aControlTitleSpellingsCompile` spells a literal, a `String`, a `Substring` and an explicit `LocalizedStringKey` on every control from a plain `import MetalUI`.

## SR-D: the switch knob slides (divergence 885 retired, 886 added; amends `BY-I`)

1. **Probe `swiftui-switch-knob.swift`** reads the `presentation()` layer of the hosted `NSSwitch` per frame. The knob slides on **every** change: an accessibility press (`K1`), an un-animated
   write (`K2`) and `withAnimation(.linear(duration: 1))` (`K3`) give the same curve, settling in 0.27-0.31 s with a 0.54-point overshoot over an 18-point travel; a `.checkbox` snaps (`K4`).
   **`withAnimation(nil)` still slides (`K6`); `Transaction.disablesAnimations = true` snaps (`K5`).** The plan's design (animate under the transaction, a fallback when there is none, a
   `.linear(1)` test) is refuted by `K3`: SwiftUI's knob does not read the transaction.
2. `paintKnob` animates the knob's fraction (0 off, 1 on) through `animatedNumbers` on a fixed `Animation.spring(duration: 0.25, bounce: 0.25)` (`Toggle.knobSpring`: settles within 0.3% by
   0.3 s, overshoots 2.8%), `AnimationStore` track `switch-knob` beside the others (the `TrimmedShape` precedent, no `StateTable` slot), the transaction not consulted except `disablesAnimations`
   (which passes `nil`, a snap). A first sighting snaps; a settled switch interpolates nothing and lets the window sleep (`animatedNumbers` notes the active animation itself). Retained replays keep
   the baseline through the store's `retainLog` touches. **The curve is an approximation**: the shape between the ends is not matched (the first frames of the measured curve are slower than a spring's).
3. **The right-to-left bug was real** (written test first, red with the knob at offsets [-37, -21] from the track): the row's children are reflected about the row's bounds (`LD-A`) but the
   knob was placed from the unreflected bounds. It is now reflected with its track (off at the right end, on at the left).
4. **Divergence 886** records what stays: SwiftUI's track is 54 by 24 and the knob 32 by 20 inset 2 (`K0`), MetalUI's 38 by 22, 18, 2 (its own, unchanged); the curve; and that the track's fill still
   changes under `withAnimation` only. **Whether Reduce Motion changes SwiftUI's knob is unmeasured**; MetalUI's does not read it (the `AN-` rule).

## SR-E: padding spellings text (divergence 208, reworded)

`leading`/`trailing` agree with SwiftUI's under right-to-left since `LD-A` (probe `swiftui-layout-direction.swift` E1/E2, pinned by `aRightToLeftPaddingAndFrameAlignmentAreMirrored`), so the
row keeps only the absent default-amount spellings. `PaddingSpellings.swift`, `Font.swift`'s `TextAlignment` and `LayoutTree.swift`'s `zeroSpacingEdges` comments that still said "left, no layout direction (divergence 25)" are corrected.

## SR-F: the settle flake (`HarnessSettleTests`)

`runUntilIdleReturnsWhenAnApprovedTerminationClosesTheWindowMidSettle` failed once on Linux CI (PR 193, run 41596564828); the run's log was overwritten by a green re-run, so **the cause is unconfirmed**.
Established by reading: on Linux the main actor is not the main thread, so `Window.markDirtyFromObservation` takes its `Task { @MainActor }` hop arm and `needsRedraw` becomes true only when the hop runs;
`setNeedsRedraw` has no closed-window guard; `runUntilIdle()` treats a closed window as clean and returns after four quiet yields, so it can return before the hop lands and the arm's `needsRedraw` read is false.
That is consistent with the failure; it was not reproduced on macOS. The fix waits for the hop with `yieldUntil` (up to 64 `Task.yield()`s, no sleep) before the read, in that test and its sibling
`runUntilReturnsWhenAnApprovedTerminationClosesTheWindow` (the same read). **Limit:** the documented mutation (`isDirtyAndOpen` without `&& !platformWindow.isClosed`) still reddens the test on macOS, where the
dirty flag lands before the close; on Linux, if the hop lands after `runUntilIdle()` returned, that mutation could pass undetected on that run. The test can no longer fail spuriously.

## SR-G: a segmented `Picker` squeezes its title last (R4-3a; amends `DD-V` item 5; no divergence added, retired or narrowed)

Human check SR1 Finding A: `Picker("Flavor", ...).pickerStyle(.segmented)` in a 420 window drew its title one letter a line. **The cause was not `Text`** (its line counts equal SwiftUI's at all 16 widths of probe TW,
and "Flavor" one letter wide beside a 366 rigid sibling is SwiftUI's own behaviour, SQ1) **but the options row**: `EqualWidthRow` ignored its proposal and always answered `n x widest`, a rigid 362 beside a 37 title in a
380 frame. Probe `docs/probes/swiftui-segmented-sizing.swift` (SG1-SG4, recorded in `swiftui-segmented-sizing-run.txt`, run twice, locked session, nothing reads pixels) measured SwiftUI's rule:

1. **The segmented control is flexible between a floor and an ideal.** Ideal `n x (widest + 24)` (363 here), floor the sum of the natural widths (271); offered more it answers the ideal, between it takes the offer,
   below the floor it answers the floor and overflows its frame. The share-out is `NSSegmentedControl`'s: each segment an equal share, never under its own natural width (335 -> 108, 108, 121; 300 -> 91, 90, 121;
   280 -> 75, 86, 121; 271 and below -> 66, 86, 121, accessibility frames, 1 to 2 over the layout figure). `EqualWidthRow.widths(natural:available:)` is that rule (repeatedly fix every segment whose natural width exceeds
   the current share and share the rest), used by `sizeThatFits` (the sum) and `placeSubviews` (accumulating x). A nil or infinite proposal, or one of at least `n x widest`, is all-equal at the widest, as before.
2. **A labelled picker is its own rule, not a stack's** (SG3e, seven arms): the control is offered `W - 8 - titleIdeal`; if what is left for the title is short of its ideal, the title is offered that remainder and
   the control is offered `W - 8 - titleAnswer`. `PickerTitleLayout` (a `ProposalLayout`, gap 8, both centred vertically, the title offered the proposal's height) does exactly that; `PickerTitleRow`, an `ElementGroup`
   inside the picker's `Box`, consumes and plans the title and options records as `OptionRow` does and registers it. A radio group, a menu and a `labelsHidden()` picker (one node) pass their nodes through, with the
   identity numbering unchanged. An empty title keeps its 8 (SG1c).
3. **Row 131 (pop-up 132 vs 145) is not this cause**: SwiftUI's pop-up is the title + about 48 (144.50 for "Strawberry mint", 56.50 for "A"), MetalUI's `ceil(title) + " v" + padding` (97 + 11 + 24 = 132). Its rigidity is
   row 130. Unchanged; the numbers are added to row 131.
4. **Residues kept** (not new rows: no divergence label is added, retired or narrowed): MetalUI's ideal capsule is 362 where SwiftUI's is 363 (the three widths round to 121, 121, 120; the `n x w + 1` that
   divergence 81 recorded), its floor 270 where SwiftUI's is 271, a long title wraps to 82 where SwiftUI's is 83. The AX segment widths are bounds, not edges; **segment edges in pixels, and how the overflow at the
   floor looks, are not measured** (human check SR1, SR5).

Pins: `SegmentedPickerSizingTests.swift` (the literals are MetalUI's CoreText readings, each commented with SwiftUI's), the `Picker.segmented` row of `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`
(FL10: zero and `w50` 124.85 -> 117.98), and the bracket window's layout counts (one new native node, record 210). Probe `FL9` had proposed zero, nil, infinity, 200 and 50, none between SwiftUI's floor and ideal: that
is how "every Picker style hugs" got pinned.

## Mutations (restored; names are the tests that reddened)

See record 198 section "Mutations".
