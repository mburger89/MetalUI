// SwiftUI probe: what may follow `.popover` (menus, popovers and tooltips,
// lane 3 review round; evidence for divergence 115 and ruling MN-AH item 5 in
// docs/superpowers/2026-10-02-menus-popovers-decisions.md).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-popover-chaining.swift -o /tmp/popover-chaining
//   /tmp/popover-chaining
//   xcrun swiftc -typecheck -DNEGATIVE docs/probes/swiftui-popover-chaining.swift
//
// THE INSTRUMENT. The Swift compiler: arm CH1 chains `.padding` and a second
// `.popover` after a `.popover` and prints the chain's static type, so the
// order of the layers is read back; arm CH2 is the positive control (the
// same `.padding` written before the popover). The separating arm is NEGATIVE:
// the same compiler refuses an argument `.popover` does not take
// (`attachmentAnchor: 0`, an `Int`), so a refusal is visible when there is one.
//
// RECORDED OUTPUT (2026-10-03, macOS 27, Xcode's swiftc; run twice, identical):
//
//   CH1 popover then padding then popover: compiles
//   CH1 type: ModifiedContent<ModifiedContent<ModifiedContent<Button<Text>, PopoverPresentationModifier<Item, Text>>, _PaddingLayout>, PopoverPresentationModifier<Item, Text>>
//   CH2 padding then popover: compiles
//
// NEGATIVE: `error: cannot convert value of type 'Int' to expected argument
// type 'PopoverAttachmentAnchor'` — the compiler refuses what the API lacks.
//
// READING. SwiftUI chains any modifier after `.popover`, a second `.popover`
// included: the popover is one more `ModifiedContent` layer. MetalUI's legacy
// `PopoverModifier` is not a `StyledElement`, so `.padding` and a second
// `.popover` do not follow it there (divergence 115).

import SwiftUI

struct Probe: View {
    @State var a = false
    @State var b = false
    var chained: some View {
        Button("A") {}.popover(isPresented: $a) { Text("P") }.padding(4).popover(isPresented: $b) { Text("Q") }
    }
    var control: some View {
        Button("A") {}.padding(4).popover(isPresented: $a) { Text("P") }
    }
    var body: some View { VStack { chained; control } }
}

#if NEGATIVE
struct Negative: View {
    @State var a = false
    var body: some View { Button("A") {}.popover(isPresented: $a, attachmentAnchor: 0) { Text("P") } }
}
#endif

MainActor.assumeIsolated {
    let probe = Probe()
    print("CH1 popover then padding then popover: compiles")
    print("CH1 type: \(type(of: probe.chained))")
    print("CH2 padding then popover: compiles")
    _ = probe.control
}
