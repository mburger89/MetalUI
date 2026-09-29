// SwiftUI probe: common controls and selection (plan task 10, part 2).
// `Button`, `Toggle(isOn:)`, `Slider(value:in:step:)`, `Stepper`,
// `Picker(selection:)` and `List(selection:)` — layout size, accessibility
// role/value/actions, what an accessibility press/increment/decrement does
// (value clamping and stepping), disabled behaviour, and whether a click or a
// key reaches each one on this machine.
//
// Evidence for rulings DD-Q… in
// docs/superpowers/2026-09-25-data-and-scrolling-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms):
//
//   /usr/bin/swift docs/probes/swiftui-controls-and-selection.swift
//   xcrun swiftc docs/probes/swiftui-controls-and-selection.swift -o /tmp/cs-probe && /tmp/cs-probe
//
// INSTRUMENTS.
// - SIZE: each control is hosted alone in a 300x200 window; its own size is
//   read with `.onGeometryChange(for: CGSize.self)` on the control itself, so
//   a greedy control reads 300 wide and a hugging one its own width. The
//   hosting view's `fittingSize` is printed beside it (the ideal size).
// - AX: the hosting view's accessibility tree, walked with KVC, as in
//   `swiftui-accessibility-bridge.swift`. Actions are invoked by calling the
//   element's `accessibilityPerformPress`/`…Increment`/`…Decrement` directly.
// - BINDING LOG: every control's binding is `Binding(get:set:)` over a model,
//   and the setter logs each write, so a write SwiftUI makes on its own (a
//   clamp on appear, a snap to a step) shows as a line.
// - CLICK/KEY: `NSEvent`s sent through `NSWindow.sendEvent`, each arm with a
//   positive control (an `onTapGesture` view for clicks; a focused
//   `onKeyPress` view for keys). An arm whose control reads 0 measures
//   nothing, and is recorded as such.
//
// POSITIVE CONTROLS. BT2/TG2/BT5 (a bare `Text`) are the label sizes the
// control sizes are read against. CK0 (a SwiftUI `onTapGesture`) and CK1 (an
// AppKit `NSButton`) are the click controls: **CK0 reads nothing**, so no
// SwiftUI click arm (CK2-CK4) measures anything — synthesized clicks do not
// reach SwiftUI's gesture system on this machine; CK1 shows the events
// themselves are delivered. KY0 (a focused `onKeyPress` view) is the key
// control and PASSES, so the KY arms are measurements. WH0 (a wheel over an
// `NSScrollView`'s own document) is the wheel control and **reads 0**, so WH1
// measures nothing (the same failure `swiftui-data-and-scrolling.swift`'s W0
// recorded). The AX arms need no control beyond themselves: each prints the
// tree it acted on, and each action arm prints the binding write it caused.
// `NSApp.isFullKeyboardAccessEnabled` is printed because it decides whether
// a button can hold keyboard focus at all.
//
// RECORDED 2026-09-25 by the plan task 10 part 2 design session, macOS 27.0
// (26A428), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (the lock
// probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). The
// compiled form (`xcrun swiftc … -o /tmp/cs-probe`) was run twice: stdout
// byte-identical (172 lines), exit 0, stderr empty both times. **The script
// form does not run here**: `/usr/bin/swift` (and `xcrun swift`, and either
// with `-target arm64-apple-macos27.0`) stops with `JIT session error:
// Symbols not found: [ ___isPlatformVersionAtLeast ]` before `main` — a JIT
// link failure, not a probe answer — so SA-O's second form is recorded as
// unavailable rather than as agreeing.
//
// RE-RUN 2026-09-25 by the critic round (DD-AC), screen UNLOCKED (lock probe:
// no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`): the compiled
// form of the design's revision, run twice, reproduced all 172 recorded lines
// byte for byte (exit 0, stderr empty) — so CK0's and WH0's failures are NOT
// the lock: synthesized clicks and wheels do not reach SwiftUI or an
// NSScrollView through `sendEvent` on this machine either way. The critic
// round then added PK2 (bare label sizes) and PK3 (a segmented and a radio
// picker whose labels differ widely); that revision was compiled and run
// twice: 182 lines, byte-identical, exit 0, stderr empty, and its other 172
// lines identical to the design's recording. The ten new lines are inserted
// below in output order.
//
//   --- SIZE (own size in a 300x200 window; fitting = hosting view's ideal)
//     BT0 Button("Go") automatic: own size 41x24 fitting 41x24
//     BT0 Button("A longer label") automatic: own size 107x24 fitting 107x24
//     BT1 .bordered: own size 41x24 fitting 41x24
//     BT1 .borderedProminent: own size 41x24 fitting 41x24
//     BT1 .borderless: own size 17x16 fitting 17x16
//     BT1 .plain: own size 17x16 fitting 17x16
//     BT1 .link: own size 17x16 fitting 17x16
//     BT2 control: Text("Go"): own size 17x16 fitting 17x16
//     BT3 Button { Text("Go").frame(maxWidth: .infinity) } automatic: own size 300x24 fitting 41x24
//     BT3 same, .plain: own size 300x16 fitting 17x16
//     BT4 Button("Go") .controlSize(mini): own size 28x13 fitting 28x13
//     BT4 Button("Go") .controlSize(small): own size 35x20 fitting 35x20
//     BT4 Button("Go") .controlSize(regular): own size 41x24 fitting 41x24
//     BT4 Button("Go") .controlSize(large): own size 45x28 fitting 45x28
//     BT4 Button("Go") .controlSize(extraLarge): own size 53x36 fitting 53x36
//     BT5 control: Text("Go") .controlSize(mini): own size 12x11 fitting 12x11
//     BT5 control: Text("Go") .controlSize(small): own size 15x14 fitting 15x14
//     BT5 control: Text("Go") .controlSize(regular): own size 17x16 fitting 17x16
//     BT5 control: Text("Go") .controlSize(large): own size 17x16 fitting 17x16
//     BT5 control: Text("Go") .controlSize(extraLarge): own size 17x16 fitting 17x16
//     TG0 Toggle("Wi-Fi") automatic: own size 53x16 fitting 53x16
//     TG0 Toggle("") automatic (no label): own size 21x19 fitting 21x19
//     TG1 .checkbox: own size 53x16 fitting 53x16
//     TG1 .switch: own size 94x24 fitting 94x24
//     TG1 .button: own size 56x24 fitting 56x24
//     TG2 control: Text("Wi-Fi"): own size 32x16 fitting 32x16
//     SL0 Slider(value:in: 0...10): own size 300x16 fitting 30x16
//     SL0 Slider with label: own size 300x16 fitting 83x16
//     ST0 Stepper("Qty", value:in: 0...3): own size 50x24 fitting 50x24
//     ST0 Stepper("", value:): own size 28x24 fitting 28x24
//     PK0 Picker automatic: own size 139x24 fitting 139x24
//     PK1 .menu: own size 139x24 fitting 139x24
//     PK1 .segmented: own size 256x24 fitting 256x24
//     PK1 .radioGroup: own size 112x61 fitting 112x61
//     PK1 .inline: own size 112x61 fitting 112x61
//     PK2 control: Text("Alpha"): own size 34x16 fitting 34x16
//     PK2 control: Text("Beta"): own size 28x16 fitting 28x16
//     PK2 control: Text("Gamma"): own size 46x16 fitting 46x16
//     PK2 control: Text("Flavor"): own size 37x16 fitting 37x16
//     PK2 control: Text("Qty"): own size 22x16 fitting 22x16
//     PK2 control: Text("A"): own size 9x16 fitting 9x16
//     PK2 control: Text("A much longer label"): own size 120x16 fitting 120x16
//     PK2 control: Text(""): own size 0x14 fitting 0x14
//     PK3 .segmented [A, A much longer label]: own size 289x24 fitting 289x24
//     PK3 .radioGroup [A, A much longer label]: own size 141x38 fitting 141x39
//     LS0 List(selection:) rows 0..<3 in 300x200: own size 300x200 fitting 0x0
//   --- AX (tree under the hosting view) and AX actions
//     BA0 Button("Go") { count += 1 }:
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil size=41x24 kids=0
//     BA0 press -> true action
//     BA1 Button("Go").disabled(true):
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil size=41x24 kids=0 DISABLED
//     BA1 press -> false -
//     BA2 Button { Text("A"); Image(systemName: "star") }:
//     AccessibilityNode role=AXButton sub=nil label=A value=nil size=57x24 kids=0
//     BA3 Button("Go").buttonStyle(.plain):
//     AccessibilityNode role=AXButton sub=nil label=Go value=nil size=17x16 kids=0
//     TA0 Toggle("Wi-Fi", isOn:) automatic, off:
//     AccessibilityNode role=AXCheckBox sub=nil label=Wi-Fi value=0 size=53x16 kids=0
//     TA0 press -> true on set true value now 0
//     TA1 .switch, on:
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Wi-Fi size=32x16 kids=0
//     PlatformSwitch role=AXCheckBox sub=AXSwitch label=nil value=1 size=56x26 kids=0
//     TA2 .button, on:
//     AccessibilityNode role=AXCheckBox sub=AXToggle label=Wi-Fi value=1 size=56x24 kids=0
//     TA3 .disabled(true):
//     AccessibilityNode role=AXCheckBox sub=nil label=Wi-Fi value=0 size=53x16 kids=0 DISABLED
//     SA0 Slider(value: 5, in: 0...10):
//     AccessibilityNode role=AXSlider sub=nil label=nil value=5 size=300x16 kids=1
//       AccessibilityNode role=AXValueIndicator sub=nil label=nil value=nil size=20x16 kids=0
//     SA1 no step, 5 in 0...10: appear writes: -; value 5 | + value set 6.0 ax=6 model=6.0 | + value set 7.0 ax=7 model=7.0 | - value set 6.0 ax=6 model=6.0
//     SA2 no step, 10 in 0...10 (at max): appear writes: -; value 10 | + value set 10.0 ax=10 model=10.0
//     SA3 step 2, 5 in 0...10 (off-step start): appear writes: -; value 5 | + value set 8.0 ax=8 model=8.0 | + value set 10.0 ax=10 model=10.0 | - value set 8.0 ax=8 model=8.0
//     SA4 step 3, 9 in 0...10 (range not a multiple): appear writes: -; value 9 | + value set 9.0 ax=9 model=9.0 | + value set 9.0 ax=9 model=9.0
//     SA5 no step, 15 in 0...10 (out of range start): appear writes: -; value 10 | - value set 9.0 ax=9 model=9.0
//     SA6 no step, -3 in 0...10 (below range start): appear writes: -; value 0 | + value set 1.0 ax=1 model=1.0
//     SA7 no step, 5 in 0...200: appear writes: -; value 5 | + value set 25.0 ax=25 model=25.0
//     SA8 Slider with label { Text("Volume") }:
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Volume size=45x16 kids=0
//     AccessibilityNode role=AXSlider sub=nil label=nil value=5 size=247x16 kids=1
//       AccessibilityNode role=AXValueIndicator sub=nil label=nil value=nil size=20x16 kids=0
//     SA9 .disabled(true):
//     AccessibilityNode role=AXSlider sub=nil label=nil value=5 size=300x16 kids=1 DISABLED
//       AccessibilityNode role=AXValueIndicator sub=nil label=nil value=nil size=20x16 kids=0 DISABLED
//     STA0 Stepper("Qty", value: 1, in: 0...3):
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Qty size=22x16 kids=0
//     EditTrackingStepperCell role=AXIncrementor sub=nil label=nil value=1 size=20x24 kids=2
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXIncrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXDecrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//     STA1 1 in 0...3 step 1: appear writes: -; value 1 | + int set 2 ax=2 model=2 | + int set 3 ax=3 model=3 | + - ax=3 model=3 | - int set 2 ax=2 model=2
//     STA2 0 in 0...3, decrement at min: appear writes: -; value 0 | - - ax=0 model=0
//     STA3 2 in 0...3 step 2 (overshoot): appear writes: -; value 2 | + int set 3 ax=3 model=3 | - int set 1 ax=1 model=1 | - int set 0 ax=0 model=0
//     STA4 5 in 0...3 (out of range start): appear writes: -; value 3 | + int set 3 ax=3 model=3 | - int set 2 ax=2 model=2
//     STA5 no range, 1 step 1: appear writes: -; value 1 | + int set 2 ax=2 model=2 | - int set 1 ax=1 model=1 | - int set 0 ax=0 model=0 | - int set -1 ax=-1 model=-1
//     STA6 Stepper(onIncrement:onDecrement: nil): + -> false, - -> false: onIncrement
//     EditTrackingStepperCell role=AXIncrementor sub=nil label=nil value=0 size=20x24 kids=2
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXIncrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXDecrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//     STA7 .disabled(true):
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Qty size=22x16 kids=0 DISABLED
//     EditTrackingStepperCell role=AXIncrementor sub=nil label=nil value=1 size=20x24 kids=2 DISABLED
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXIncrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//       NSAccessibilityStepperArrowButton role=AXButton sub=AXDecrementArrow label=nil value=nil size=20x12 kids=0 DISABLED
//     PA0 Picker automatic, selection 1:
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Flavor size=37x16 kids=0
//     AccessibilityNode role=AXPopUpButton sub=nil label=nil value=Beta size=94x24 kids=0
//     PA1 .segmented, selection 1:
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Flavor size=37x16 kids=0
//     Cell role=AXRadioGroup sub=nil label=nil value=<element label=Beta> size=211x24 kids=3
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Alpha value=0 size=70x24 kids=0
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Beta value=1 size=70x24 kids=0
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Gamma value=0 size=70x24 kids=0
//     PA1 press segment 2 -> false pick set 2 model=2
//     PA2 .radioGroup, selection 1:
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Flavor size=37x16 kids=0
//     AccessibilityNode role=AXRadioGroup sub=nil label=nil value=nil size=67x61 kids=3
//       AccessibilityNode role=AXRadioButton sub=nil label=Alpha value=0 size=55x16 kids=0
//       AccessibilityNode role=AXRadioButton sub=nil label=Beta value=1 size=48x16 kids=0 SELECTED
//       AccessibilityNode role=AXRadioButton sub=nil label=Gamma value=0 size=67x16 kids=0
//     PA2 press radio 0 -> true pick set 0 model=0
//     PA3 automatic, selection 7 (no matching tag):
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Flavor size=37x16 kids=0
//     AccessibilityNode role=AXPopUpButton sub=nil label=nil value=nil size=94x24 kids=0
//     PA3 writes on appear: -
//     PA4 .segmented .disabled(true):
//     AccessibilityNode role=AXStaticText sub=nil label=nil value=Flavor size=37x16 kids=0 DISABLED
//     Cell role=AXRadioGroup sub=nil label=nil value=<element label=Beta> size=211x24 kids=3 DISABLED
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Alpha value=0 size=70x24 kids=0 DISABLED
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Beta value=1 size=70x24 kids=0 DISABLED
//       NSAccessibilitySegment role=AXRadioButton sub=AXSegment label=Gamma value=0 size=70x24 kids=0 DISABLED
//   --- LIST SELECTION
//     LA0 single, sel nil: AXOutline rows=5 selected rows=[]; appear writes -
//     SwiftUIOutlineListView role=AXOutline sub=nil label=nil value=nil size=302x202 kids=6 rows=5 selectedRows=0
//       NSOutlineRow role=AXRow sub=AXOutlineRow label=nil value=nil size=0x0 kids=1
//         NSTableViewCellMockElement role=AXCell sub=nil label=nil value=nil size=0x0 kids=1
//       NSOutlineRow role=AXRow sub=AXOutlineRow label=nil value=nil size=0x0 kids=1
//         NSTableViewCellMockElement role=AXCell sub=nil label=nil value=nil size=0x0 kids=1
//     LA1 single, sel set to 2 by the model: AXOutline rows=5 selected rows=[2]; writes -
//     LA2 single, row 3 setAccessibilitySelected(true): AXOutline rows=5 selected rows=[3]; writes sel set Optional(3) model=3
//     LA3 single, table setAccessibilitySelectedRows([row 1]): AXOutline rows=5 selected rows=[1]; writes sel set Optional(1) model=1
//     LA4 single, table setAccessibilitySelectedRows([row 0, row 4]): AXOutline rows=5 selected rows=[1]; writes - model=1
//     LA5 single, sel 4, row 4 removed from the data: AXOutline rows=3 selected rows=[]; writes - model=4
//     LA5b row 4 back: AXOutline rows=5 selected rows=[4] model=4
//     LB0 multi, []: AXOutline rows=5 selected rows=[]; appear writes -
//     LB1 multi, set to [1, 3] by the model: AXOutline rows=5 selected rows=[1, 3]; writes -
//     LB2 multi, setAccessibilitySelectedRows([row 0, row 4]): AXOutline rows=5 selected rows=[0, 4]; writes multi set [0, 4] model=[0, 4]
//     LB3 multi, row 2 setAccessibilitySelected(true): AXOutline rows=5 selected rows=[2]; writes multi set [2] model=[2]
//     LC0 control, List without selection: AXOutline rows=5 selected rows=[]
//     LD0 single .disabled(true), sel 4: AXOutline rows=5 selected rows=[4]
//   --- CLICK (NSEvent through NSWindow.sendEvent)
//     CK0 control: onTapGesture, click at centre: -
//     CK1 control: AppKit NSButton, click at centre: appkit action
//     CK2 Button, click at centre: -
//     CK3 Button, press at centre, release outside: -
//     CK4 List single, click near the top: writes - model=nil
//   --- WHEEL over an AppKit NSButton inside an NSScrollView (NSEvent through NSWindow.sendEvent)
//     WH0 control: wheel over the document, off the button: clip y 0.0
//     WH1 wheel over the NSButton inside the scroll view: clip y 0.0
//   --- KEY (NSEvent through NSWindow.sendEvent)
//     NSApp.isFullKeyboardAccessEnabled = false
//     KY0 control: focused onKeyPress view, 'a': keyPress "a"
//     KY1 Button .focused, space: -
//     KY2 Button .focused, return: -
//     KY3 Button .keyboardShortcut(.defaultAction), return: default action
//     KY4 Button .focusable().focused, space: -
//     KY4b same, return: -
//     KY5 Toggle .focusable().focused, space: -
//     KY6 List single .focused, sel 1, down arrow: sel set Optional(2) model=2
//     KY6b up arrow: sel set Optional(1) model=1
//     KY6c sel nil, down arrow: sel set Optional(0) model=0
//     KY6d sel 4 (last), down arrow: - model=4
//     KY6e sel nil, up arrow: sel set Optional(4) model=4
//     KY6f sel 0 (first), up arrow: - model=0
//     KY8 List multi .focused, [1], down arrow: multi set [2] model=[2]
//     KY8b shift-down arrow: multi set [2, 3] model=[2, 3]
//     KY8c command-A: - model=[2, 3]
//     KY8d space: - model=[2, 3]
//     KY8e shift-up arrow: multi set [2] model=[2]
//     KY8f shift-down twice: multi set [2, 3]; multi set [2, 3, 4] model=[2, 3, 4]
//     KY8g down arrow: multi set [4] model=[4]
//     KY7 Slider .focusable().focused, right arrow: -
//
// READING (what rulings DD-Q… rely on; arm ids cited there):
// - BT0/BT4/BT5: a bordered (automatic) Button is its label plus a fixed
//   horizontal padding, 24 tall at `.regular`: "Go" 17x16 -> 41x24 (12 a side);
//   "A longer label" +24 too. Per control size the height is 13/20/24/28/36
//   and the padding (button width - label width) / 2 is 8/10/12/14/18
//   (28-12, 35-15, 41-17, 45-17, 53-17). BT1: `.plain`/`.borderless`/`.link`
//   are the label alone. BT3: a greedy label grows the bezel (300 wide).
// - TG0/TG1: the automatic Toggle on macOS IS the checkbox (53x16 = label 32
//   + 21); `.switch` 94x24 and `.button` 56x24 are other styles.
// - SL0: a Slider is greedy on the width (300 in a 300 window), 16 tall;
//   ideal (fitting) width 30. ST0: a Stepper is its label + 8 + a 20x24
//   control, the 8 kept with an empty label (28x24). PK0/PK1: a Picker is its
//   label + 8 + the control; the automatic style IS the menu (139x24, a 94x24
//   pop-up); `.segmented` 211x24 for three segments, each 70 wide whatever its
//   label (equal widths, PA1); `.radioGroup` (= `.inline` here) a 67x61 column.
// - BA0/BA1/BA2/BA3: a Button is one AXButton labelled by its label's text
//   (children folded, kids=0), whatever its style; a disabled one is
//   published DISABLED and its press is refused and runs nothing.
// - TA0-TA3: a Toggle is an AXCheckBox labelled by its label, value 0/1; a
//   press writes the negation (`on set true`) through the binding; disabled
//   is published DISABLED. (TA0's "value now 0" is read before the re-render.)
//   `.switch` publishes a sibling static text and an unlabelled switch.
// - SA0/SA8/SA9: a Slider is an AXSlider, value the number, label nil (a
//   label view is a sibling static text); disabled is published DISABLED.
//   SA1/SA7: an increment/decrement with no step moves 10% of the span
//   (+1 on 0...10, +20 on 0...200). SA3: with a step it moves one step and
//   lands on the grid lower + k*step, rounding half up (5 +2 -> 8). SA4: never
//   past the last grid point inside the range (9 +3 -> 9 on 0...10 step 3).
//   SA5/SA6: an out-of-range value is shown clamped (15 -> 10, -3 -> 0), is
//   NOT written back on appear, and an adjustment starts from the clamped
//   value (15 -1 -> 9). SA2: at the maximum an increment still WRITES (10).
// - STA0-STA7: a Stepper is its label as a sibling AXStaticText and an
//   unlabelled AXIncrementor (value the number) with two arrow buttons.
//   STA1-STA4: an increment/decrement moves one step, clamped into the range
//   (2 +2 -> 3, 1 -2 -> 0), and writes NOTHING when the value would not change
//   (at 3, +; at 0, -); an out-of-range value is shown clamped (5 -> 3) and
//   the next step starts from the clamped value and writes (5 + -> 3, then
//   3 - -> 2). STA5: no range, no clamp (-1). STA6: `onIncrement:` runs its
//   closure; a nil `onDecrement` makes decrement do nothing.
// - PA0/PA3: the automatic Picker is an AXPopUpButton (value the selected
//   option's text; nil when no tag matches, and nothing is written). PA1:
//   `.segmented` is an AXRadioGroup of AXRadioButtons (value 1 on the
//   selected one); pressing one writes its tag. PA2: `.radioGroup` likewise,
//   the selected radio also SELECTED. PA4: disabled is published DISABLED,
//   children too. The title is a sibling static text in every style.
// - LA0-LD0: a List with `selection:` publishes AXOutline rows; the selected
//   row(s) are AXSelected, set by the model (LA1, LB1). An accessibility
//   client can select: a row's AXSelected (LA2, LB3 — in a multi-selection
//   list it REPLACES the set) or the table's AXSelectedRows (LA3, LB2); a
//   single-selection list ignores a two-row request (LA4). LA5: removing the
//   selected datum writes nothing — the binding keeps the stale id, and the
//   row is selected again when it returns. LD0: a disabled list still shows
//   its selection.
// - PK2/PK3 (critic round): a segment is its label + 24 (Gamma 46 -> 70) and
//   every segment takes the widest's width (PK3: 2 x (120 + 24) + 1 = 289;
//   PK1: 3 x 70 + 1 = 211 — the control is n x w + 1). A radio row is its
//   label + 21 (Alpha 34 -> 55, Gamma 46 -> 67, "A much longer label" 120 ->
//   141; Beta 28 -> 48 is the one 20, a rounding of fractional text widths),
//   the same 21 as the checkbox (TG0); rows are 6 apart in PK3 (38 = 2 x 16 +
//   6) and 6.5 in PK1 (61 = 3 x 16 + 2 x 6.5). An empty Text is 0x14, while
//   TG0's empty-label Toggle is 21x19.
// - CK0-CK4: NOT MEASURED (the SwiftUI click control reads nothing).
// - KY1-KY5/KY7: `NSApp.isFullKeyboardAccessEnabled = false` here, and a
//   focused Button, a focused `.focusable()` Button, Toggle or Slider ignore
//   space, return and arrows — SwiftUI's controls take no keyboard input
//   without Full Keyboard Access. KY3: return runs a
//   `.keyboardShortcut(.defaultAction)` Button without focus.
// - KY6/KY8: a focused List moves its selection with the arrows: down/up
//   select the next/previous row (KY6, KY6b); with nothing selected down
//   selects the first row and up the last (KY6c, KY6e); at the last row down
//   and at the first row up write nothing in a single-selection list (KY6d,
//   KY6f). In a multi-selection list a plain arrow collapses to one row
//   (KY8: [1] -> [2]; KY8g: [2,3,4] at the end -> [4], a write), shift+arrow
//   extends or shrinks from the anchor (KY8b [2,3], KY8e [2], KY8f [2,3,4]),
//   and neither command-A nor space does anything (KY8c, KY8d).
// - WH0/WH1: NOT MEASURED (the wheel control reads 0).

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }
func kv(_ o: NSObject, _ key: String) -> Any? {
    if o.responds(to: Selector(key)) { return o.value(forKey: key) }
    // A Bool attribute's modern getter is `isAccessibility…`.
    let isKey = "is" + key.prefix(1).uppercased() + key.dropFirst()
    if o.responds(to: Selector(isKey)) { return o.value(forKey: key) }
    // Older elements (an outline's rows) answer only the attribute API.
    let names: [String: String] = ["accessibilityRole": "AXRole", "accessibilitySubrole": "AXSubrole",
                                   "accessibilityLabel": "AXDescription", "accessibilityValue": "AXValue",
                                   "accessibilityChildren": "AXChildren", "accessibilitySelected": "AXSelected",
                                   "accessibilityFrame": "AXFrame", "accessibilityEnabled": "AXEnabled"]
    if let name = names[key], o.responds(to: Selector(("accessibilityAttributeValue:"))) {
        return o.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: name))
    }
    return "<n/a>"
}
@MainActor func setAttr(_ o: NSObject, _ name: String, _ value: Any) {
    o.accessibilitySetValue(value, forAttribute: NSAccessibility.Attribute(rawValue: name))
}

@MainActor func line(_ o: NSObject) -> String {
    let kids = (kv(o, "accessibilityChildren") as? [Any]) ?? []
    var extras = ""
    if let sel = kv(o, "accessibilitySelected") as? Bool, sel { extras += " SELECTED" }
    if let en = kv(o, "accessibilityEnabled") as? Bool, !en { extras += " DISABLED" }
    if let rows = kv(o, "accessibilityRows") as? [Any] { extras += " rows=\(rows.count)" }
    if let srows = kv(o, "accessibilitySelectedRows") as? [Any] { extras += " selectedRows=\(srows.count)" }
    let frame = (kv(o, "accessibilityFrame") as? NSValue)?.rectValue ?? .zero
    let typeName = "\(type(of: o))".components(separatedBy: "<").first!
    // An element-valued AXValue (a segmented control's selected segment) is
    // printed by its label, not its address, so two runs compare.
    var value = str(kv(o, "accessibilityValue"))
    if let element = kv(o, "accessibilityValue") as? NSObject, !(element is NSNumber), !(element is NSString) {
        value = "<element label=\(str(kv(element, "accessibilityLabel")))>"
    }
    return "\(typeName) role=\(str(kv(o, "accessibilityRole"))) sub=\(str(kv(o, "accessibilitySubrole"))) label=\(str(kv(o, "accessibilityLabel"))) value=\(value) size=\(Int(frame.width))x\(Int(frame.height)) kids=\(kids.count)\(extras)"
}

@MainActor func describe(_ o: Any, depth: Int = 1, maxDepth: Int = 4, maxKids: Int = 6) {
    guard let obj = o as? NSObject else { return }
    print(String(repeating: "  ", count: depth) + line(obj))
    guard depth < maxDepth else { return }
    for k in ((kv(obj, "accessibilityChildren") as? [Any]) ?? []).prefix(maxKids) {
        describe(k, depth: depth + 1, maxDepth: maxDepth, maxKids: maxKids)
    }
}

@MainActor func kids(_ o: NSObject) -> [NSObject] {
    ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}

/// Depth-first search for the first node whose role matches.
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if str(kv(o, "accessibilityRole")) == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
@MainActor func findAll(_ o: NSObject, role: String) -> [NSObject] {
    var out: [NSObject] = []
    if str(kv(o, "accessibilityRole")) == role { out.append(o) }
    for k in kids(o) { out += findAll(k, role: role) }
    return out
}

@MainActor func perform(_ e: NSObject, _ sel: String) -> Bool {
    guard e.responds(to: Selector(sel)) else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(e.method(for: Selector(sel)), to: Fn.self)(e, Selector(sel))
}

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ v: V, size: CGSize = CGSize(width: 300, height: 200)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless()
    w.makeKey()
    h.layoutSubtreeIfNeeded()
    spin(0.4)
    windows.append(w)
    return h
}

final class Log {
    var lines: [String] = []
    func add(_ s: String) { lines.append(s) }
    func take() -> String { defer { lines = [] }; return lines.isEmpty ? "-" : lines.joined(separator: "; ") }
}
let log = Log()

final class Model: ObservableObject {
    @Published var count = 0
    @Published var on = false
    @Published var value: Double = 5
    @Published var int = 1
    @Published var pick = 0
    @Published var sel: Int? = nil
    @Published var multi: Set<Int> = []
    @Published var items = Array(0..<5)
}

func logged<T>(_ name: String, _ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
    // A Set is printed sorted, so two runs compare.
    Binding(get: get, set: { v in log.add("\(name) set \((v as? Set<Int>).map { "\($0.sorted())" } ?? "\(v)")"); set(v) })
}

/// Re-renders from the model, so a control shows each value its binding wrote.
struct Live<C: View>: View {
    @ObservedObject var m: Model
    let make: (Model) -> C
    var body: some View { make(m) }
}

/// Reports a view's own size (the control's, not its host's).
struct Measured<C: View>: View {
    let name: String
    let content: C
    var body: some View {
        content.onGeometryChange(for: CGSize.self) { $0.size } action: { s in
            log.add("\(name) size \(Int(s.width))x\(Int(s.height))")
        }
    }
}

@MainActor func size<V: View>(_ label: String, _ v: V) {
    log.lines = []
    let h = host(Measured(name: "own", content: v))
    let fit = h.fittingSize
    print("  \(label): \(log.take()) fitting \(Int(fit.width))x\(Int(fit.height))")
}

@MainActor func ax<V: View>(_ label: String, _ v: V) -> NSHostingView<V> {
    let h = host(v)
    print("  \(label):")
    for k in kids(h) { describe(k) }
    return h
}

// MARK: - click/key synthesis

@MainActor func click(_ h: NSView, at p: NSPoint, releaseAt q: NSPoint? = nil, modifiers: NSEvent.ModifierFlags = []) {
    guard let w = h.window else { return }
    let down = h.convert(p, to: nil)
    let up = h.convert(q ?? p, to: nil)
    let t = ProcessInfo.processInfo.systemUptime
    for (type, at, dt) in [(NSEvent.EventType.leftMouseDown, down, 0.0), (.leftMouseUp, up, 0.05)] {
        let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: modifiers, timestamp: t + dt,
                                   windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                   clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        w.sendEvent(e)
        spin(0.05)
    }
    spin(0.2)
}

@MainActor func key(_ h: NSView, _ chars: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
    guard let w = h.window else { return }
    let t = ProcessInfo.processInfo.systemUptime
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: t,
                                 windowNumber: w.windowNumber, context: nil, characters: chars,
                                 charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
        w.sendEvent(e)
        spin(0.05)
    }
    spin(0.2)
}

struct KeyControl: View {
    @FocusState var f: Bool
    var body: some View {
        Text("keys").focusable().focused($f)
            .onKeyPress { press in log.add("keyPress \(press.characters.debugDescription)"); return .handled }
            .onAppear { f = true }
    }
}

// MARK: - arms

@MainActor func run() {
    let m = Model()
    print("--- SIZE (own size in a 300x200 window; fitting = hosting view's ideal)")
    size("BT0 Button(\"Go\") automatic", Button("Go") {})
    size("BT0 Button(\"A longer label\") automatic", Button("A longer label") {})
    size("BT1 .bordered", Button("Go") {}.buttonStyle(.bordered))
    size("BT1 .borderedProminent", Button("Go") {}.buttonStyle(.borderedProminent))
    size("BT1 .borderless", Button("Go") {}.buttonStyle(.borderless))
    size("BT1 .plain", Button("Go") {}.buttonStyle(.plain))
    size("BT1 .link", Button("Go") {}.buttonStyle(.link))
    size("BT2 control: Text(\"Go\")", Text("Go"))
    size("BT3 Button { Text(\"Go\").frame(maxWidth: .infinity) } automatic",
         Button { } label: { Text("Go").frame(maxWidth: .infinity) })
    size("BT3 same, .plain", Button { } label: { Text("Go").frame(maxWidth: .infinity) }.buttonStyle(.plain))
    for s in [ControlSize.mini, .small, .regular, .large, .extraLarge] {
        size("BT4 Button(\"Go\") .controlSize(\(s))", Button("Go") {}.controlSize(s))
    }
    for s in [ControlSize.mini, .small, .regular, .large, .extraLarge] {
        size("BT5 control: Text(\"Go\") .controlSize(\(s))", Text("Go").controlSize(s))
    }
    size("TG0 Toggle(\"Wi-Fi\") automatic", Toggle("Wi-Fi", isOn: .constant(false)))
    size("TG0 Toggle(\"\") automatic (no label)", Toggle("", isOn: .constant(false)))
    size("TG1 .checkbox", Toggle("Wi-Fi", isOn: .constant(false)).toggleStyle(.checkbox))
    size("TG1 .switch", Toggle("Wi-Fi", isOn: .constant(false)).toggleStyle(.switch))
    size("TG1 .button", Toggle("Wi-Fi", isOn: .constant(false)).toggleStyle(.button))
    size("TG2 control: Text(\"Wi-Fi\")", Text("Wi-Fi"))
    size("SL0 Slider(value:in: 0...10)", Slider(value: .constant(5), in: 0...10))
    size("SL0 Slider with label", Slider(value: .constant(5), in: 0...10) { Text("Volume") })
    size("ST0 Stepper(\"Qty\", value:in: 0...3)", Stepper("Qty", value: .constant(1), in: 0...3))
    size("ST0 Stepper(\"\", value:)", Stepper("", value: .constant(1)))
    let options = ["Alpha", "Beta", "Gamma"]
    func picker() -> some View {
        Picker("Flavor", selection: .constant(0)) { ForEach(0..<3) { Text(options[$0]).tag($0) } }
    }
    size("PK0 Picker automatic", picker())
    size("PK1 .menu", picker().pickerStyle(.menu))
    size("PK1 .segmented", picker().pickerStyle(.segmented))
    size("PK1 .radioGroup", picker().pickerStyle(.radioGroup))
    size("PK1 .inline", picker().pickerStyle(.inline))
    // Added by the critic round (DD-AC): the bare label sizes the picker's
    // segment padding and radio-row indicator are derived against, a
    // segmented picker whose labels differ widely (does every segment take
    // the widest's width?), and an empty Text (the empty-label Toggle's height).
    for t in ["Alpha", "Beta", "Gamma", "Flavor", "Qty", "A", "A much longer label", ""] {
        size("PK2 control: Text(\"\(t)\")", Text(t))
    }
    size("PK3 .segmented [A, A much longer label]",
         Picker("", selection: .constant(0)) {
             Text("A").tag(0); Text("A much longer label").tag(1)
         }.pickerStyle(.segmented).labelsHidden())
    size("PK3 .radioGroup [A, A much longer label]",
         Picker("", selection: .constant(0)) {
             Text("A").tag(0); Text("A much longer label").tag(1)
         }.pickerStyle(.radioGroup).labelsHidden())
    size("LS0 List(selection:) rows 0..<3 in 300x200", List(0..<3, id: \.self, selection: .constant(Int?.none)) { Text("Row \($0)") })

    // The hosting view publishes no accessibility children until a client is
    // detected; this is the switch `swiftui-accessibility-bridge.swift` uses.
    NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    print("--- AX (tree under the hosting view) and AX actions")
    let b = ax("BA0 Button(\"Go\") { count += 1 }", Button("Go") { m.count += 1; log.add("action") })
    if let e = find(b, role: "AXButton") { print("  BA0 press -> \(perform(e, "accessibilityPerformPress")) \(log.take())") }
    let bd = ax("BA1 Button(\"Go\").disabled(true)", Button("Go") { log.add("action") }.disabled(true))
    if let e = find(bd, role: "AXButton") { print("  BA1 press -> \(perform(e, "accessibilityPerformPress")) \(log.take())") }
    _ = ax("BA2 Button { Text(\"A\"); Image(systemName: \"star\") }",
           Button { } label: { HStack { Text("A"); Image(systemName: "star") } })
    _ = ax("BA3 Button(\"Go\").buttonStyle(.plain)", Button("Go") {}.buttonStyle(.plain))

    m.on = false
    let t = ax("TA0 Toggle(\"Wi-Fi\", isOn:) automatic, off",
               Toggle("Wi-Fi", isOn: logged("on", { m.on }, { m.on = $0 })))
    if let e = find(t, role: "AXCheckBox") {
        print("  TA0 press -> \(perform(e, "accessibilityPerformPress")) \(log.take()) value now \(str(kv(e, "accessibilityValue")))")
    }
    let ts = ax("TA1 .switch, on", Toggle("Wi-Fi", isOn: .constant(true)).toggleStyle(.switch))
    _ = ts
    _ = ax("TA2 .button, on", Toggle("Wi-Fi", isOn: .constant(true)).toggleStyle(.button))
    _ = ax("TA3 .disabled(true)", Toggle("Wi-Fi", isOn: .constant(false)).disabled(true))

    func slider(_ label: String, start: Double, range: ClosedRange<Double>, step: Double?, steps: [String]) {
        m.value = start
        log.lines = []
        let h: NSView
        if let step {
            h = host(Live(m: m) { m in Slider(value: logged("value", { m.value }, { m.value = $0 }), in: range, step: step) })
        } else {
            h = host(Live(m: m) { m in Slider(value: logged("value", { m.value }, { m.value = $0 }), in: range) })
        }
        let appear = log.take()
        guard let e = find(h, role: "AXSlider") else { print("  \(label): no AXSlider"); return }
        var out = "  \(label): appear writes: \(appear); value \(str(kv(e, "accessibilityValue")))"
        for s in steps {
            let ok = perform(e, s == "+" ? "accessibilityPerformIncrement" : "accessibilityPerformDecrement")
            spin(0.1)
            out += " | \(s)\(ok ? "" : "(returned false)") \(log.take()) ax=\(str(kv(e, "accessibilityValue"))) model=\(m.value)"
        }
        print(out)
    }
    _ = ax("SA0 Slider(value: 5, in: 0...10)", Slider(value: .constant(5), in: 0...10))
    slider("SA1 no step, 5 in 0...10", start: 5, range: 0...10, step: nil, steps: ["+", "+", "-"])
    slider("SA2 no step, 10 in 0...10 (at max)", start: 10, range: 0...10, step: nil, steps: ["+"])
    slider("SA3 step 2, 5 in 0...10 (off-step start)", start: 5, range: 0...10, step: 2, steps: ["+", "+", "-"])
    slider("SA4 step 3, 9 in 0...10 (range not a multiple)", start: 9, range: 0...10, step: 3, steps: ["+", "+"])
    slider("SA5 no step, 15 in 0...10 (out of range start)", start: 15, range: 0...10, step: nil, steps: ["-"])
    slider("SA6 no step, -3 in 0...10 (below range start)", start: -3, range: 0...10, step: nil, steps: ["+"])
    slider("SA7 no step, 5 in 0...200", start: 5, range: 0...200, step: nil, steps: ["+"])
    _ = ax("SA8 Slider with label { Text(\"Volume\") }", Slider(value: .constant(5), in: 0...10) { Text("Volume") })
    _ = ax("SA9 .disabled(true)", Slider(value: .constant(5), in: 0...10).disabled(true))

    func stepper(_ label: String, start: Int, range: ClosedRange<Int>?, step: Int, steps: [String]) {
        m.int = start
        log.lines = []
        let h: NSView
        if let range {
            h = host(Live(m: m) { m in Stepper("Qty", value: logged("int", { m.int }, { m.int = $0 }), in: range, step: step) })
        } else {
            h = host(Live(m: m) { m in Stepper("Qty", value: logged("int", { m.int }, { m.int = $0 }), step: step) })
        }
        let appear = log.take()
        guard let e = find(h, role: "AXIncrementor") else {
            print("  \(label): no AXIncrementor; tree:"); for k in kids(h) { describe(k) }; return
        }
        var out = "  \(label): appear writes: \(appear); value \(str(kv(e, "accessibilityValue")))"
        for s in steps {
            _ = perform(e, s == "+" ? "accessibilityPerformIncrement" : "accessibilityPerformDecrement")
            spin(0.1)
            out += " | \(s) \(log.take()) ax=\(str(kv(e, "accessibilityValue"))) model=\(m.int)"
        }
        print(out)
    }
    _ = ax("STA0 Stepper(\"Qty\", value: 1, in: 0...3)", Stepper("Qty", value: .constant(1), in: 0...3))
    stepper("STA1 1 in 0...3 step 1", start: 1, range: 0...3, step: 1, steps: ["+", "+", "+", "-"])
    stepper("STA2 0 in 0...3, decrement at min", start: 0, range: 0...3, step: 1, steps: ["-"])
    stepper("STA3 2 in 0...3 step 2 (overshoot)", start: 2, range: 0...3, step: 2, steps: ["+", "-", "-"])
    stepper("STA4 5 in 0...3 (out of range start)", start: 5, range: 0...3, step: 1, steps: ["+", "-"])
    stepper("STA5 no range, 1 step 1", start: 1, range: nil, step: 1, steps: ["+", "-", "-", "-"])
    do {
        log.lines = []
        let h = host(Stepper("Qty", onIncrement: { log.add("onIncrement") }, onDecrement: nil))
        if let e = find(h, role: "AXIncrementor") {
            let inc = perform(e, "accessibilityPerformIncrement"); spin(0.1)
            let dec = perform(e, "accessibilityPerformDecrement"); spin(0.1)
            print("  STA6 Stepper(onIncrement:onDecrement: nil): + -> \(inc), - -> \(dec): \(log.take())")
            describe(e)
        }
    }
    _ = ax("STA7 .disabled(true)", Stepper("Qty", value: .constant(1), in: 0...3).disabled(true))

    m.pick = 1
    let pk = ax("PA0 Picker automatic, selection 1",
                Picker("Flavor", selection: logged("pick", { m.pick }, { m.pick = $0 })) {
                    ForEach(0..<3) { Text(options[$0]).tag($0) } })
    _ = pk
    let seg = ax("PA1 .segmented, selection 1",
                 Picker("Flavor", selection: logged("pick", { m.pick }, { m.pick = $0 })) {
                     ForEach(0..<3) { Text(options[$0]).tag($0) } }.pickerStyle(.segmented))
    let radios = findAll(seg, role: "AXRadioButton")
    if radios.count == 3 {
        print("  PA1 press segment 2 -> \(perform(radios[2], "accessibilityPerformPress")) \(log.take()) model=\(m.pick)")
    } else { print("  PA1 radio buttons found: \(radios.count)") }
    m.pick = 1
    let rg = ax("PA2 .radioGroup, selection 1",
                Picker("Flavor", selection: logged("pick", { m.pick }, { m.pick = $0 })) {
                    ForEach(0..<3) { Text(options[$0]).tag($0) } }.pickerStyle(.radioGroup))
    let rgr = findAll(rg, role: "AXRadioButton")
    if rgr.count == 3 {
        print("  PA2 press radio 0 -> \(perform(rgr[0], "accessibilityPerformPress")) \(log.take()) model=\(m.pick)")
    } else { print("  PA2 radio buttons found: \(rgr.count)") }
    m.pick = 7
    _ = ax("PA3 automatic, selection 7 (no matching tag)",
           Picker("Flavor", selection: logged("pick", { m.pick }, { m.pick = $0 })) {
               ForEach(0..<3) { Text(options[$0]).tag($0) } })
    print("  PA3 writes on appear: \(log.take())")
    m.pick = 1
    let pm = ax("PA4 .segmented .disabled(true)",
                Picker("Flavor", selection: .constant(1)) { ForEach(0..<3) { Text(options[$0]).tag($0) } }
                    .pickerStyle(.segmented).disabled(true))
    _ = pm

    print("--- LIST SELECTION")
    struct Single: View {
        @ObservedObject var m: Model
        var body: some View {
            List(m.items, id: \.self, selection: logged("sel", { m.sel }, { m.sel = $0 })) { Text("Row \($0)") }
        }
    }
    struct Multi: View {
        @ObservedObject var m: Model
        var body: some View {
            List(m.items, id: \.self, selection: logged("multi", { m.multi }, { m.multi = $0 })) { Text("Row \($0)") }
        }
    }
    struct NoSel: View {
        @ObservedObject var m: Model
        var body: some View { List(m.items, id: \.self) { Text("Row \($0)") } }
    }
    func rowsLine(_ h: NSView) -> String {
        guard let table = find(h, role: "AXTable") ?? find(h, role: "AXOutline") else { return "no table" }
        let rows = (kv(table, "accessibilityRows") as? [NSObject]) ?? []
        let selected = rows.enumerated().filter { (kv($0.element, "accessibilitySelected") as? Bool) == true }.map(\.offset)
        return "\(str(kv(table, "accessibilityRole"))) rows=\(rows.count) selected rows=\(selected)"
    }
    m.sel = nil
    let s0 = host(Single(m: m), size: CGSize(width: 300, height: 200))
    print("  LA0 single, sel nil: \(rowsLine(s0)); appear writes \(log.take())")
    if let table = find(s0, role: "AXTable") ?? find(s0, role: "AXOutline") { describe(table, maxDepth: 3, maxKids: 2) }
    m.sel = 2; spin(0.3)
    print("  LA1 single, sel set to 2 by the model: \(rowsLine(s0)); writes \(log.take())")
    if let table = find(s0, role: "AXTable") ?? find(s0, role: "AXOutline"),
       let rows = kv(table, "accessibilityRows") as? [NSObject], rows.count > 3 {
        setAttr(rows[3], "AXSelected", true); spin(0.3)
        print("  LA2 single, row 3 setAccessibilitySelected(true): \(rowsLine(s0)); writes \(log.take()) model=\(str(m.sel))")
        setAttr(table, "AXSelectedRows", [rows[1]]); spin(0.3)
        print("  LA3 single, table setAccessibilitySelectedRows([row 1]): \(rowsLine(s0)); writes \(log.take()) model=\(str(m.sel))")
        setAttr(table, "AXSelectedRows", [rows[0], rows[4]]); spin(0.3)
        print("  LA4 single, table setAccessibilitySelectedRows([row 0, row 4]): \(rowsLine(s0)); writes \(log.take()) model=\(str(m.sel))")
    }
    m.sel = 4; spin(0.3); _ = log.take()
    m.items = [0, 1, 2]; spin(0.3)
    print("  LA5 single, sel 4, row 4 removed from the data: \(rowsLine(s0)); writes \(log.take()) model=\(str(m.sel))")
    m.items = Array(0..<5); spin(0.3); _ = log.take()
    print("  LA5b row 4 back: \(rowsLine(s0)) model=\(str(m.sel))")

    m.multi = []
    let mu = host(Multi(m: m), size: CGSize(width: 300, height: 200))
    print("  LB0 multi, []: \(rowsLine(mu)); appear writes \(log.take())")
    m.multi = [1, 3]; spin(0.3)
    print("  LB1 multi, set to [1, 3] by the model: \(rowsLine(mu)); writes \(log.take())")
    if let table = find(mu, role: "AXTable") ?? find(mu, role: "AXOutline"),
       let rows = kv(table, "accessibilityRows") as? [NSObject], rows.count > 4 {
        setAttr(table, "AXSelectedRows", [rows[0], rows[4]]); spin(0.3)
        print("  LB2 multi, setAccessibilitySelectedRows([row 0, row 4]): \(rowsLine(mu)); writes \(log.take()) model=\(m.multi.sorted())")
        setAttr(rows[2], "AXSelected", true); spin(0.3)
        print("  LB3 multi, row 2 setAccessibilitySelected(true): \(rowsLine(mu)); writes \(log.take()) model=\(m.multi.sorted())")
    }
    let ns = host(NoSel(m: m), size: CGSize(width: 300, height: 200))
    print("  LC0 control, List without selection: \(rowsLine(ns))")
    let dis = host(Single(m: m).disabled(true), size: CGSize(width: 300, height: 200))
    print("  LD0 single .disabled(true), sel \(str(m.sel)): \(rowsLine(dis))")

    print("--- CLICK (NSEvent through NSWindow.sendEvent)")
    do {
        log.lines = []
        let h = host(Text("tap me").padding(20).onTapGesture { log.add("tap") }, size: CGSize(width: 200, height: 100))
        click(h, at: NSPoint(x: 100, y: 50))
        print("  CK0 control: onTapGesture, click at centre: \(log.take())")
        let nb = NSButton(title: "AppKit", target: nil, action: nil)
        let target = ClickTarget()
        nb.target = target; nb.action = #selector(ClickTarget.fire)
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled],
                         backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        nb.frame = NSRect(x: 50, y: 30, width: 100, height: 30)
        w.contentView?.addSubview(nb)
        w.orderFrontRegardless()
        windows.append(w)
        spin(0.3)
        click(w.contentView!, at: NSPoint(x: 100, y: 45))
        print("  CK1 control: AppKit NSButton, click at centre: \(log.take())")
        let bh = host(Button("Go") { log.add("action") }, size: CGSize(width: 200, height: 100))
        click(bh, at: NSPoint(x: 100, y: 50))
        print("  CK2 Button, click at centre: \(log.take())")
        click(bh, at: NSPoint(x: 100, y: 50), releaseAt: NSPoint(x: 5, y: 5))
        print("  CK3 Button, press at centre, release outside: \(log.take())")
        m.sel = nil
        let lh = host(Single(m: m), size: CGSize(width: 300, height: 200))
        click(lh, at: NSPoint(x: 100, y: 190))
        print("  CK4 List single, click near the top: writes \(log.take()) model=\(str(m.sel))")
    }

    print("--- WHEEL over an AppKit NSButton inside an NSScrollView (NSEvent through NSWindow.sendEvent)")
    do {
        func wheel(over point: NSPoint) -> CGFloat {
            let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: 200, height: 1000))
            let button = NSButton(title: "Inside", target: nil, action: nil)
            button.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
            doc.addSubview(button)
            scroll.documentView = doc
            w.contentView = scroll
            w.orderFrontRegardless()
            windows.append(w)
            spin(0.2)
            let at = scroll.convert(point, to: nil)
            for _ in 0..<3 {
                let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0)!
                cg.location = CGPoint(x: w.frame.minX + at.x, y: (NSScreen.screens.first?.frame.height ?? 0) - (w.frame.minY + at.y))
                if let e = NSEvent(cgEvent: cg) { w.sendEvent(e) }
                spin(0.05)
            }
            spin(0.2)
            return scroll.contentView.bounds.origin.y
        }
        print("  WH0 control: wheel over the document, off the button: clip y \(wheel(over: NSPoint(x: 150, y: 50)))")
        print("  WH1 wheel over the NSButton inside the scroll view: clip y \(wheel(over: NSPoint(x: 50, y: 80)))")
    }

    print("--- KEY (NSEvent through NSWindow.sendEvent)")
    print("  NSApp.isFullKeyboardAccessEnabled = \(NSApp.isFullKeyboardAccessEnabled)")
    do {
        log.lines = []
        let kh = host(KeyControl(), size: CGSize(width: 200, height: 100))
        key(kh, "a", code: 0)
        print("  KY0 control: focused onKeyPress view, 'a': \(log.take())")
        struct FocusedButton: View {
            @FocusState var f: Bool
            var body: some View {
                Button("Go") { log.add("action") }.focused($f).onAppear { f = true }
            }
        }
        let fb = host(FocusedButton(), size: CGSize(width: 200, height: 100))
        key(fb, " ", code: 49)
        print("  KY1 Button .focused, space: \(log.take())")
        key(fb, "\r", code: 36)
        print("  KY2 Button .focused, return: \(log.take())")
        let db = host(Button("Go") { log.add("default action") }.keyboardShortcut(.defaultAction),
                      size: CGSize(width: 200, height: 100))
        key(db, "\r", code: 36)
        print("  KY3 Button .keyboardShortcut(.defaultAction), return: \(log.take())")
        struct FocusableButton: View {
            @FocusState var f: Bool
            var body: some View {
                Button("Go") { log.add("action") }.focusable().focused($f)
                    .onAppear { f = true }.onChange(of: f) { _, v in log.add("focused \(v)") }
            }
        }
        let fb2 = host(FocusableButton(), size: CGSize(width: 200, height: 100))
        _ = log.take()
        key(fb2, " ", code: 49)
        print("  KY4 Button .focusable().focused, space: \(log.take())")
        key(fb2, "\r", code: 36)
        print("  KY4b same, return: \(log.take())")
        struct FocusedToggle: View {
            @FocusState var f: Bool
            @State var on = false
            var body: some View {
                Toggle("T", isOn: Binding(get: { on }, set: { on = $0; log.add("on set \($0)") }))
                    .focusable().focused($f).onAppear { f = true }
            }
        }
        let ft = host(FocusedToggle(), size: CGSize(width: 200, height: 100))
        key(ft, " ", code: 49)
        print("  KY5 Toggle .focusable().focused, space: \(log.take())")
        struct FocusedList: View {
            @ObservedObject var m: Model
            @FocusState var f: Bool
            var body: some View {
                List(m.items, id: \.self, selection: logged("sel", { m.sel }, { m.sel = $0 })) { Text("Row \($0)") }
                    .focused($f).onAppear { f = true }
            }
        }
        m.sel = 1
        let fl = host(FocusedList(m: m), size: CGSize(width: 300, height: 200))
        _ = log.take()
        key(fl, String(UnicodeScalar(0xF701)!), code: 125)
        print("  KY6 List single .focused, sel 1, down arrow: \(log.take()) model=\(str(m.sel))")
        key(fl, String(UnicodeScalar(0xF700)!), code: 126)
        print("  KY6b up arrow: \(log.take()) model=\(str(m.sel))")
        m.sel = nil; spin(0.2); _ = log.take()
        key(fl, String(UnicodeScalar(0xF701)!), code: 125)
        print("  KY6c sel nil, down arrow: \(log.take()) model=\(str(m.sel))")
        m.sel = 4; spin(0.2); _ = log.take()
        key(fl, String(UnicodeScalar(0xF701)!), code: 125)
        print("  KY6d sel 4 (last), down arrow: \(log.take()) model=\(str(m.sel))")
        m.sel = nil; spin(0.2); _ = log.take()
        key(fl, String(UnicodeScalar(0xF700)!), code: 126)
        print("  KY6e sel nil, up arrow: \(log.take()) model=\(str(m.sel))")
        m.sel = 0; spin(0.2); _ = log.take()
        key(fl, String(UnicodeScalar(0xF700)!), code: 126)
        print("  KY6f sel 0 (first), up arrow: \(log.take()) model=\(str(m.sel))")
        struct FocusedMulti: View {
            @ObservedObject var m: Model
            @FocusState var f: Bool
            var body: some View {
                List(m.items, id: \.self, selection: logged("multi", { m.multi }, { m.multi = $0 })) { Text("Row \($0)") }
                    .focused($f).onAppear { f = true }
            }
        }
        m.multi = [1]
        let fm = host(FocusedMulti(m: m), size: CGSize(width: 300, height: 200))
        _ = log.take()
        key(fm, String(UnicodeScalar(0xF701)!), code: 125)
        print("  KY8 List multi .focused, [1], down arrow: \(log.take()) model=\(m.multi.sorted())")
        key(fm, String(UnicodeScalar(0xF701)!), code: 125, modifiers: [.shift])
        print("  KY8b shift-down arrow: \(log.take()) model=\(m.multi.sorted())")
        key(fm, "a", code: 0, modifiers: [.command])
        print("  KY8c command-A: \(log.take()) model=\(m.multi.sorted())")
        key(fm, " ", code: 49)
        print("  KY8d space: \(log.take()) model=\(m.multi.sorted())")
        key(fm, String(UnicodeScalar(0xF700)!), code: 126, modifiers: [.shift])
        print("  KY8e shift-up arrow: \(log.take()) model=\(m.multi.sorted())")
        key(fm, String(UnicodeScalar(0xF701)!), code: 125, modifiers: [.shift])
        key(fm, String(UnicodeScalar(0xF701)!), code: 125, modifiers: [.shift])
        print("  KY8f shift-down twice: \(log.take()) model=\(m.multi.sorted())")
        key(fm, String(UnicodeScalar(0xF701)!), code: 125)
        print("  KY8g down arrow: \(log.take()) model=\(m.multi.sorted())")
        struct FocusedSlider: View {
            @FocusState var f: Bool
            @State var v = 5.0
            var body: some View {
                Slider(value: Binding(get: { v }, set: { v = $0; log.add("v set \($0)") }), in: 0...10)
                    .focusable().focused($f).onAppear { f = true }
            }
        }
        let fsl = host(FocusedSlider(), size: CGSize(width: 200, height: 100))
        key(fsl, String(UnicodeScalar(0xF703)!), code: 124)
        print("  KY7 Slider .focusable().focused, right arrow: \(log.take())")
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class ClickTarget: NSObject {
    @objc func fire() { log.add("appkit action") }
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    run()
}
exit(0)
