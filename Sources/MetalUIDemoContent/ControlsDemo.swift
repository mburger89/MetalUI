import MetalUI

/// The controls demo (plan task 10, part 2, lane 3; spec
/// `2026-09-26-controls-and-selection-design.md` §11), reached with
/// `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo`. Every control this part
/// adds, bound to `@State` through `$`, plus a selectable `List` and a
/// `ForEach` over a binding — **the human look record §03 owes**: every
/// control by pointer, the list's ⌘/⇧ clicks and arrows (a click on a row
/// focuses the list, `DD-Z` item 5; the other controls take keys only once
/// focused, which a click does not do), and the wheel over a row (`DD-Y`).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`; its deepest native level
/// is recorded by `theControlsDemoPublishesEveryControlsRole`.
@MainActor
public func controlsDemoContent() -> some Element {
    Column(gap: Pixels(14)) {
        ControlsDemo()
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .background(.surface)
}

/// One row of the demo's chores.
struct DemoChore: Identifiable {
    var id: Int
    var title: String
    var done: Bool
}

/// One row of the demo's selectable list.
struct DemoRow: Identifiable {
    var id: Int
}

/// The picker's choices.
enum DemoFlavor: Hashable {
    case vanilla, chocolate, strawberry
}

/// The demo's state, all `@State`, so every control's binding is a `$`
/// projection, as a caller writes it.
struct ControlsDemo: Component {
    @State var presses = 0
    @State var wifi = true
    @State var volume = 0.4
    @State var quantity = 2
    @State var flavor = DemoFlavor.chocolate
    @State var size = 1
    @State var chores = [DemoChore(id: 0, title: "Water the plants", done: false),
                         DemoChore(id: 1, title: "Take out the bins", done: true),
                         DemoChore(id: 2, title: "Call the plumber", done: false)]
    /// A `Set`, so the list shows ⌘- and ⇧-clicks. **Not `@State var picked:
    /// Int? = 2`**: an optional `@State` with a non-`nil` initial value reads
    /// `nil` until its first write (`StateTable.peek`'s `as? Int?` cast of an
    /// absent entry succeeds with `.some(nil)`, so `wrappedValue`'s `??
    /// initialValue` never runs) — found by this demo, reported to the Record
    /// phase, not fixed in this lane (`DD-AG` item 3).
    @State var picked: Set<Int> = [2]

    var content: some ElementGroup {
        Text("Controls").font(size: 22)
        Row(gap: Pixels(12)) {
            Button("Press me") { presses += 1 }
            Text("pressed \(presses) times")
        }
        Toggle("Wi-Fi", isOn: $wifi)
        Row(gap: Pixels(12)) {
            Slider(value: $volume, in: 0...1, step: 0.1)
                .frame(width: Pixels(220))
            Text("volume \(Int((volume * 10).rounded()))")
        }
        Stepper("Quantity \(quantity)", value: $quantity, in: 0...10)
        Picker("Flavor", selection: $flavor) {
            Text("Vanilla").tag(DemoFlavor.vanilla)
            Text("Chocolate").tag(DemoFlavor.chocolate)
            Text("Strawberry").tag(DemoFlavor.strawberry)
        }
        Picker("Size", selection: $size) {
            Text("Small").tag(0)
            Text("Medium").tag(1)
            Text("Large").tag(2)
        }
        .pickerStyle(.radioGroup)
        Row(gap: Pixels(24)) {
            Column(gap: Pixels(4)) {
                ForEach($chores) { $chore in
                    Toggle(chore.title, isOn: $chore.done)
                }
            }
            .alignItems(.flexStart)
            ScrollView {
                List((0..<40).map { DemoRow(id: $0) }, selection: $picked, rowHeight: Pixels(24)) { row in
                    Text("Row \(row.id)")
                }
            }
            .frame(width: Pixels(200), height: Pixels(120))
            .background(.surfaceSecondary)
        }
    }
}
