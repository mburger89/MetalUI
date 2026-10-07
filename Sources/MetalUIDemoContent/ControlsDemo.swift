import MetalUI

/// The controls demo (plan task 10, part 2, lane 3; spec
/// `2026-09-26-controls-and-selection-design.md` §11), reached with
/// `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo`. Every control this part
/// adds, bound to `@State` through `$`, plus a selectable `List` and a
/// `ForEach` over a binding — **the human look record §03 owes**: every
/// control by pointer, the list's ⌘/⇧ clicks and arrows (a click on a row
/// focuses the list, `DD-Z` item 5; the other controls take keys only once
/// focused, which a click does not do), and the wheel over a row (`DD-Y`).
/// Beside them, the same controls in the **SwiftUI vocabulary**
/// (`swiftUIVocabularySection`, spec `2026-10-06-proposal-controls-design.md`
/// §7, `PE-M`): human checks V1–V4.
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
    /// The SwiftUI-vocabulary section's own values (its picker and stepper
    /// share `flavor` and `quantity` with the controls above). `speed` starts
    /// at 0.75 so its slider never reads as the volume slider's value.
    @State var name = ""
    @State var enabled = true
    @State var speed = 0.75

    var content: some ElementGroup {
        Row(gap: Pixels(32)) {
            Column(gap: Pixels(14)) {
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
            .alignItems(.flexStart)
            swiftUIVocabularySection(name: $name, enabled: $enabled, speed: $speed,
                                     flavor: $flavor, quantity: $quantity)
        }
        .alignItems(.flexStart)
    }
}

/// The controls demo's "SwiftUI vocabulary" section (spec
/// `2026-10-06-proposal-controls-design.md` §7, rulings `PE-B`, `PE-M`): the
/// probe's form `FM0` and the configurator's status bar `ST0`
/// (`docs/probes/swiftui-controls-in-stacks.swift`), written as SwiftUI writes
/// them — legacy controls inside `HStack`/`VStack`, adopted by
/// `ProposalContentBuilder`. The form's rows are test 1.5's tree, so they lay
/// out as its literals (test 3.1). **Its own function**, as are its two halves:
/// a debug build reserves a slot per temporary for a whole function, and the
/// Windows main thread has 1 MB (`everyProductionTreeBuildsOnAOneMegabyteThread`).
@MainActor
func swiftUIVocabularySection(name: Binding<String>, enabled: Binding<Bool>, speed: Binding<Double>,
                              flavor: Binding<DemoFlavor>, quantity: Binding<Int>) -> some Element {
    VStack(alignment: .leading, spacing: Pixels(12)) {
        Text("SwiftUI vocabulary").font(size: 22)
        swiftUIVocabularyForm(name: name, enabled: enabled, speed: speed, flavor: flavor, quantity: quantity)
        swiftUIVocabularyStatusBar(name: name.wrappedValue, enabled: enabled.wrappedValue,
                                   speed: speed.wrappedValue, flavor: flavor.wrappedValue,
                                   quantity: quantity.wrappedValue)
    }
    .frame(maxWidth: Pixels(400))
}

/// `FM0`: a label and a greedy field, a toggle and a trailing button, a label
/// and a greedy slider, a menu picker, a divider, a stepper.
@MainActor
func swiftUIVocabularyForm(name: Binding<String>, enabled: Binding<Bool>, speed: Binding<Double>,
                           flavor: Binding<DemoFlavor>, quantity: Binding<Int>) -> some ProposalElement {
    VStack(alignment: .leading) {
        HStack {
            Text("Name")
            TextField("Name", text: name)
        }
        HStack {
            Toggle("Enabled", isOn: enabled)
            Spacer()
            Button("Apply") { name.wrappedValue = "" }
        }
        HStack {
            Text("Speed")
            Slider(value: speed)
        }
        Picker("Mode", selection: flavor) {
            Text("Vanilla").tag(DemoFlavor.vanilla)
            Text("Chocolate").tag(DemoFlavor.chocolate)
            Text("Strawberry").tag(DemoFlavor.strawberry)
        }
        .pickerStyle(.menu)
        Divider()
        HStack {
            Stepper("Qty", value: quantity, in: 0...10)
            Spacer()
        }
    }
    .padding(Edges(all: Pixels(16)))
}

/// `ST0`: the configurator's status bar — a dot and a label, three labels, a
/// spacer and a trailing label, 11-point text, 26 tall and greedy wide
/// (`.frame(maxWidth: .infinity)`, `PE-F` item 2).
@MainActor
func swiftUIVocabularyStatusBar(name: String, enabled: Bool, speed: Double, flavor: DemoFlavor,
                                quantity: Int) -> some ProposalElement {
    HStack(spacing: Pixels(16)) {
        HStack(spacing: Pixels(6)) {
            Circle().frame(width: Pixels(7), height: Pixels(7))
            Text(enabled ? "Enabled" : "Disabled")
        }
        Text("Qty \(quantity)")
        Text("Speed \(Int((speed * 100).rounded()))%")
        Text("\(flavor)")
        Spacer()
        Text(name.isEmpty ? "no name" : name)
    }
    .font(.system(size: 11))
    .padding(Edges(top: Pixels(0), right: Pixels(16), bottom: Pixels(0), left: Pixels(16)))
    .frame(maxWidth: .infinity, minHeight: Pixels(26), maxHeight: Pixels(26))
    .background(.surfaceSecondary)
}
