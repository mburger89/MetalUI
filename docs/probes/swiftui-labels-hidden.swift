// SwiftUI probe: `labelsHidden()` and the empty title (round 3 item LB, ruling
// `LB-A`). Which controls drop their label under `.labelsHidden()`, whether an
// EMPTY title (`Picker("", …)`) still takes the label's gap without it, and
// where each control's own view starts relative to a sibling `TextField` in a
// `VStack(alignment: .leading)`. Evidence for
// docs/superpowers/2026-11-01-labels-hidden-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-labels-hidden.swift -o /tmp/labels-hidden-probe
//   /tmp/labels-hidden-probe
//
// Method: no pixels. Each arm hosts the view in an `NSHostingView` inside an
// off-screen `NSWindow`, lays it out, and prints `fittingSize` and the frame
// of every leaf AppKit view in the host's coordinates. A control's x is read
// against the `TextField` placed above it in the same leading-aligned stack.
//
// RECORDED 2026-11-01 by the labels-hidden session, macOS 27.2, Apple Swift 6.4, compiled form, run twice: stdout
// byte-identical (125 lines), exit 0. The tree is the same in every arm: a 100-wide `TextField` above the control in
// `VStack(alignment: .leading, spacing: 4)`; `x` is the control's own view in the host, the TextField's is 0.
//
// READING (ruling `LB-A`; the TextField lines and the `_NSCoreHostingView` wrappers are the reference and noise):
//   P1 Picker("Title").menu             pop-up x=34.5   P2 Picker("").menu             pop-up x=8.0   <- the EMPTY title keeps the gap
//   P3 Picker("Title").menu.labelsHidden  x=0.0         P4 Picker("").menu.labelsHidden  x=0.0
//   S1 segmented x=34.5 (fitting 132) | S2 .labelsHidden x=0.0 (fitting 100) | S3 Picker("").segmented x=8.0
//   R1 radioGroup x=34.5 | R2 .labelsHidden x=0.0 (the three rings keep their 67-tall column)
//   T1 Toggle("Title") ring 47.5 wide | T2 .labelsHidden 16 wide | T3 Toggle("") 21 wide against T2's 16 |
//   T4 switch.labelsHidden x=0.0 | T5 switch x=34.5
//   E1 Stepper("Title") x=34.5 | E2 .labelsHidden x=0.0 | E3 Stepper("") x=8.0
//   C1 ColorPicker("Tint") well x=31.5 | C2 .labelsHidden x=0.0 | C3 ColorPicker("") x=8.0   <- empty keeps the gap
//   G1 ProgressView("Title", value:) fitting 64 tall | G2 .labelsHidden 48 tall (the title row goes, the bar stays 20)
//   The 8 is the row's gap (P1: 34.5 = label 26.5 + 8; C1: 31.5 = 23.5 + 8; T1/T3: the toggle's own 21 + label).
//
// SEPARATING ARMS. P1 against P3 (the label is what moves the control); P2 against P4 (an empty title is not a
// hidden one); every control's shown arm against its hidden arm. Positive control: the same `TextField` row is
// identical in every arm (x = 0, 100 x 24).
//
// OUTPUT:
//
//   === P1 Picker("Title").menu: fitting 107x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=34.5 w=72.5 h=24.0
//   === P2 Picker("").menu: fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=8.0 w=72.5 h=24.0
//   === P3 Picker("Title").menu.labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=72.5 h=24.0
//   === P4 Picker("").menu.labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=72.5 h=24.0
//   === S1 Picker("Title").segmented: fitting 132x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     SwiftUISegmentedControl x=34.5 w=98.0 h=24.0
//     _NSCoreHostingView<AppKitSegmentedControl> x=34.5 w=98.0 h=24.0
//   === S2 Picker("Title").segmented.labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     SwiftUISegmentedControl x=0.0 w=98.0 h=24.0
//     _NSCoreHostingView<AppKitSegmentedControl> x=0.0 w=98.0 h=24.0
//   === S3 Picker("").segmented: fitting 106x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     SwiftUISegmentedControl x=8.0 w=98.0 h=24.0
//     _NSCoreHostingView<AppKitSegmentedControl> x=8.0 w=98.0 h=24.0
//   === R1 Picker("Title").radioGroup: fitting 100x67
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=34.5 w=46.0 h=16.5
//     _FocusRingView x=34.5 w=46.0 h=16.5
//     _FocusRingView x=34.5 w=46.0 h=39.0
//   === R2 Picker("Title").radioGroup.labelsHidden(): fitting 100x67
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=46.0 h=16.5
//     _FocusRingView x=0.0 w=46.0 h=16.5
//     _FocusRingView x=0.0 w=46.0 h=39.0
//   === T1 Toggle("Title"): fitting 100x44
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=47.5 h=16.5
//   === T2 Toggle("Title").labelsHidden(): fitting 100x44
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=16.0 h=16.0
//   === T3 Toggle(""): fitting 100x47
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     _FocusRingView x=0.0 w=21.0 h=19.0
//   === T4 Toggle("Title").switch.labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     PlatformSwitch x=0.0 w=54.0 h=24.0
//     _NSCoreHostingView<AppKitSwitch> x=0.0 w=54.0 h=24.0
//   === T5 Toggle("Title").switch: fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     PlatformSwitch x=34.5 w=54.0 h=24.0
//     _NSCoreHostingView<AppKitSwitch> x=34.5 w=54.0 h=24.0
//   === E1 Stepper("Title"): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     EditTrackingStepper x=34.5 w=20.0 h=24.0
//     _NSCoreHostingView<StepperView> x=34.5 w=20.0 h=24.0
//   === E2 Stepper("Title").labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     EditTrackingStepper x=0.0 w=20.0 h=24.0
//     _NSCoreHostingView<StepperView> x=0.0 w=20.0 h=24.0
//   === E3 Stepper(""): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     EditTrackingStepper x=8.0 w=20.0 h=24.0
//     _NSCoreHostingView<StepperView> x=8.0 w=20.0 h=24.0
//   === C1 ColorPicker("Tint"): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     PlatformColorWell x=31.5 w=48.0 h=24.0
//     _NSCoreHostingView<AppKitColorWell> x=31.5 w=48.0 h=24.0
//   === C2 ColorPicker("Tint").labelsHidden(): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     PlatformColorWell x=0.0 w=48.0 h=24.0
//     _NSCoreHostingView<AppKitColorWell> x=0.0 w=48.0 h=24.0
//   === C3 ColorPicker(""): fitting 100x52
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     PlatformColorWell x=8.0 w=48.0 h=24.0
//     _NSCoreHostingView<AppKitColorWell> x=8.0 w=48.0 h=24.0
//   === G1 ProgressView("Title", value: 0.5): fitting 100x64
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     NSProgressIndicator x=0.0 w=100.0 h=20.0
//   === G2 ProgressView("Title", value: 0.5).labelsHidden(): fitting 100x48
//     AppKitTextField x=0.0 w=100.0 h=24.0
//     _NSCoreHostingView<AppKitTextField> x=0.0 w=100.0 h=24.0
//     NSSimpleLabel x=4.0 w=92.0 h=16.0
//     NSProgressIndicator x=0.0 w=100.0 h=20.0

import SwiftUI
import AppKit

@MainActor func allViews(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { allViews($0) } }

@MainActor func arm(_ name: String, _ content: some View) {
    let host = NSHostingView(rootView: content)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    print("=== \(name): fitting \(Int(host.fittingSize.width))x\(Int(host.fittingSize.height))")
    for v in allViews(host).dropFirst() where v.subviews.isEmpty || v is NSControl {
        let f = host.convert(v.bounds, from: v)
        print("  \(String(describing: type(of: v))) x=\(f.minX) w=\(f.width) h=\(f.height)")
    }
}

struct Host<Control: View>: View {
    let control: Control
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("field", text: .constant("")).frame(width: 100)
            control
        }.padding(0)
    }
}

@MainActor func run() {
    func menu(_ title: String) -> some View {
        Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.menu)
    }
    arm("P1 Picker(\"Title\").menu", Host(control: menu("Title")))
    arm("P2 Picker(\"\").menu", Host(control: menu("")))
    arm("P3 Picker(\"Title\").menu.labelsHidden()", Host(control: menu("Title").labelsHidden()))
    arm("P4 Picker(\"\").menu.labelsHidden()", Host(control: menu("").labelsHidden()))
    func seg(_ title: String) -> some View {
        Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.segmented)
    }
    arm("S1 Picker(\"Title\").segmented", Host(control: seg("Title")))
    arm("S2 Picker(\"Title\").segmented.labelsHidden()", Host(control: seg("Title").labelsHidden()))
    arm("S3 Picker(\"\").segmented", Host(control: seg("")))
    func radio(_ title: String) -> some View {
        Picker(title, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }.pickerStyle(.radioGroup)
    }
    arm("R1 Picker(\"Title\").radioGroup", Host(control: radio("Title")))
    arm("R2 Picker(\"Title\").radioGroup.labelsHidden()", Host(control: radio("Title").labelsHidden()))
    arm("T1 Toggle(\"Title\")", Host(control: Toggle("Title", isOn: .constant(true))))
    arm("T2 Toggle(\"Title\").labelsHidden()", Host(control: Toggle("Title", isOn: .constant(true)).labelsHidden()))
    arm("T3 Toggle(\"\")", Host(control: Toggle("", isOn: .constant(true))))
    arm("T4 Toggle(\"Title\").switch.labelsHidden()",
        Host(control: Toggle("Title", isOn: .constant(true)).toggleStyle(.switch).labelsHidden()))
    arm("T5 Toggle(\"Title\").switch", Host(control: Toggle("Title", isOn: .constant(true)).toggleStyle(.switch)))
    arm("E1 Stepper(\"Title\")", Host(control: Stepper("Title", value: .constant(1))))
    arm("E2 Stepper(\"Title\").labelsHidden()", Host(control: Stepper("Title", value: .constant(1)).labelsHidden()))
    arm("E3 Stepper(\"\")", Host(control: Stepper("", value: .constant(1))))
    arm("C1 ColorPicker(\"Tint\")", Host(control: ColorPicker("Tint", selection: .constant(Color.red))))
    arm("C2 ColorPicker(\"Tint\").labelsHidden()",
        Host(control: ColorPicker("Tint", selection: .constant(Color.red)).labelsHidden()))
    arm("C3 ColorPicker(\"\")", Host(control: ColorPicker("", selection: .constant(Color.red))))
    arm("G1 ProgressView(\"Title\", value: 0.5)", Host(control: ProgressView("Title", value: 0.5).frame(width: 100)))
    arm("G2 ProgressView(\"Title\", value: 0.5).labelsHidden()",
        Host(control: ProgressView("Title", value: 0.5).labelsHidden().frame(width: 100)))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
