import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// `BY-N` / `PE-K`: the stack a menu `Picker` costs in a debug build, on a 1 MB Windows test thread. Figures are bytes of stack
// measured with `StackMeter` through `stackHighWater` (ComponentStackTests.swift) and printed as `PICKER-STACK` lines.

private struct LoneMenuPickerTree: Component {
    var content: some ElementGroup {
        Picker("Mode", selection: .constant(3)) { Text("Default").tag(0); Text("Accept edits").tag(1); Text("Auto").tag(3) }
    }
}
private struct PickerBesideMenuStackTree: Component {
    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Picker("Mode", selection: .constant(3)) { Text("Default").tag(0); Text("Accept edits").tag(1); Text("Auto").tag(3) }
                .buttonBorderShape(.capsule)
            Menu("Model") { Button("x") {} }.buttonBorderShape(.capsule)
        }
    }
}
private struct SegmentedPickerStackTree: Component {
    var content: some ElementGroup {
        Picker("Mode", selection: .constant(3)) { Text("Default").tag(0); Text("Accept edits").tag(1); Text("Auto").tag(3) }
            .pickerStyle(.segmented)
    }
}

@MainActor private func stackOf<E: ElementGroup>(_ make: @MainActor () -> E) -> Int {
    stackHighWater(width: 400, height: 200, make).bytes
}
@MainActor @inline(never) private func loneStack() -> Int { stackOf { VStack { LoneMenuPickerTree() } } }
@MainActor @inline(never) private func besideStack() -> Int { stackOf { VStack { PickerBesideMenuStackTree() } } }
@MainActor @inline(never) private func segmentedStack() -> Int { stackOf { VStack { SegmentedPickerStackTree() } } }

/// `BY-N`: a menu `Picker` keeps its options (about 12 KB for three) and its box and layout on the heap, so a lone picker and
/// a picker beside a `Menu` fit a 1 MB Windows test thread with a wide margin. macOS debug figures, 2026-11: lone 239 KB
/// (482 before), beside a Menu 340 KB (1 017 before: it overflowed on Windows), segmented 179 KB (283 before). The ceilings
/// leave room for another platform's frames; a release build measures 0. Mutation: holding the options by value in
/// `OptionRow` or `OptionSink`, or the menu's box and layout in the picker's `Layout`, raises beside past its ceiling.
@Test @MainActor func aMenuPickersStackStaysWellUnderAWindowsThread() {
    let (lone, beside, segmented) = (loneStack(), besideStack(), segmentedStack())
    print("PICKER-STACK lone", lone, "beside", beside, "segmented", segmented)
    #expect(lone < 400_000, "a lone menu Picker: \(lone) bytes")
    #expect(beside < 500_000, "a menu Picker beside a Menu: \(beside) bytes")
    #expect(segmented < 300_000, "a segmented Picker: \(segmented) bytes")
}
