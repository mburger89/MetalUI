import MetalUI
import Observation

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
///
/// The port-gaps section (`portGapsDemoSection()`, rulings `MD-M`, `MD-Z`)
/// sits below the controls, and `ControlsDemo()` carries the window's toolbar
/// — inside the `Column`, since a `.toolbar` cannot be a window's root
/// (`MD-S`): human checks W1–W5.
@MainActor
public func controlsDemoContent() -> some Element {
    Column(gap: Pixels(14)) {
        portGapsToolbar(ControlsDemo())
        portGapsDemoSection()
        controlsLooksSection()
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

// MARK: - Port gaps (medium)

/// The port-gaps section's model (ruling `MD-M`): a `@MainActor` global, as
/// `demoModel` is — never a never-written `@State` (divergence 125) — provided
/// to the section's `Component` with `.environment(_:)` and bound by the
/// toolbar's controls.
@Observable @MainActor
final class PortGapsModel {
    /// The environment-object `Component`'s counter.
    var count = 0
    var name = ""
    var notes = "A TextEditor draws an opaque fill."
    var mode = 0
    var advanced = false
    var search = ""
    var backPresses = 0
    var sharePresses = 0
}

/// The one instance the demo provides and binds.
@MainActor let portGapsModel = PortGapsModel()

/// The names the section gives its measured elements, so a test finds them
/// (`theControlsDemoShowsThePortGapsSection`, spec test 3.16).
enum PortGapsDemoIDs {
    /// Default, `.roundedBorder`, `.squareBorder`, `.plain`, disabled.
    static let fields = ["portgaps.field.default", "portgaps.field.rounded", "portgaps.field.square",
                         "portgaps.field.plain", "portgaps.field.disabled"]
    static let priorityRow = "portgaps.priority.row"
    static let priorityLabel = "portgaps.priority.label"
    static let priorityGrower = "portgaps.priority.grower"
}

/// An 8 × 8 accent-blue square, the toolbar's image button's label.
@MainActor private let portGapsShareBitmap: ImageBitmap = {
    var rgba: [UInt8] = []
    for _ in 0..<64 { rgba += [40, 110, 230, 255] }
    return ImageBitmap(width: 8, height: 8, rgba: rgba)
}()

@MainActor private func portGapsBinding<V>(_ get: @escaping @MainActor () -> V,
                                           _ set: @escaping @MainActor (V) -> Void) -> Binding<V> {
    Binding(get: get, set: set)
}

/// The demo window's toolbar (rulings `MD-I`, `MD-M`): a leading Back
/// button, a centred segmented picker, Advanced, an image button and
/// `.searchable` — on AppKit a native `NSToolbar`, on SDL the drawn strip
/// (`MD-K`). **Its own function** (Windows' 1 MB stack).
@MainActor
func portGapsToolbar<Content: ElementGroup>(_ content: Content) -> ToolbarScope<ToolbarScope<Content>> {
    let model = portGapsModel
    return content
        .toolbar {
            ToolbarItem(placement: .navigation) { Button("Back") { model.backPresses += 1 } }
            ToolbarItem(placement: .principal) {
                Picker("View", selection: portGapsBinding({ model.mode }, { model.mode = $0 })) {
                    Text("List").tag(0)
                    Text("Grid").tag(1)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem { Toggle("Advanced", isOn: portGapsBinding({ model.advanced }, { model.advanced = $0 })) }
            ToolbarItem(id: "share", placement: .primaryAction) {
                Button(action: { model.sharePresses += 1 }) {
                    Image(portGapsShareBitmap, scale: 1, label: Text("Share"))
                }
            }
        }
        .searchable(text: portGapsBinding({ model.search }, { model.search = $0 }))
}

/// The port-gaps section (ruling `MD-M`; spec §6): the four field styles and
/// a disabled field (`MD-B`…`MD-E`), a 60-tall `TextEditor` (`MD-F`), a
/// 360-wide legacy `Row` whose second child carries
/// `.flexGrow(1).layoutPriority(1)` (`MD-G`), and a `Component` reading the
/// model through `@Environment(PortGapsModel.self)` (`MD-H`). **Its own
/// function**, as are its parts (`everyProductionTreeBuildsOnAOneMegabyteThread`).
@MainActor
func portGapsDemoSection() -> some Element {
    Column(gap: Pixels(12)) {
        Text("Port gaps").font(size: 22)
        portGapsFields()
        portGapsPriorityRow()
        PortGapsCounter()
            .environment(portGapsModel)
    }
    .alignItems(.flexStart)
}

/// Five fields, 240 wide, and the editor.
@MainActor
func portGapsFields() -> some Element {
    let model = portGapsModel
    let name = portGapsBinding({ model.name }, { model.name = $0 })
    return Column(gap: Pixels(8)) {
        TextField("Default", text: name).frame(width: Pixels(240)).id(PortGapsDemoIDs.fields[0])
        TextField("Rounded border", text: name).textFieldStyle(.roundedBorder)
            .frame(width: Pixels(240)).id(PortGapsDemoIDs.fields[1])
        TextField("Square border", text: name).textFieldStyle(.squareBorder)
            .frame(width: Pixels(240)).id(PortGapsDemoIDs.fields[2])
        TextField("Plain", text: name).textFieldStyle(.plain)
            .frame(width: Pixels(240)).id(PortGapsDemoIDs.fields[3])
        TextField("Disabled", text: name).disabled(true)
            .frame(width: Pixels(240)).id(PortGapsDemoIDs.fields[4])
        TextEditor(text: portGapsBinding({ model.notes }, { model.notes = $0 }))
            .frame(width: Pixels(240), height: Pixels(60))
    }
    .alignItems(.flexStart)
}

/// A legacy `Row` 360 wide: a label at its ideal, then a prioritised grower
/// taking the rest (`MD-G`; the configurator's MG-14).
@MainActor
func portGapsPriorityRow() -> some Element {
    Row {
        Text("Label").frame(width: Pixels(80)).id(PortGapsDemoIDs.priorityLabel)
        Text("Grows, with priority 1").flexGrow(1).layoutPriority(1).id(PortGapsDemoIDs.priorityGrower)
    }
    .frame(width: Pixels(360))
    .background(.surfaceSecondary)
    .id(PortGapsDemoIDs.priorityRow)
}

/// Reads the provided model (`MD-H`); "no model" when none is provided —
/// optional, so a missing `.environment(_:)` shows rather than traps.
struct PortGapsCounter: Component {
    @Environment(PortGapsModel.self) var model: PortGapsModel?

    var content: some ElementGroup {
        Row(gap: Pixels(12)) {
            Text(model.map { "Environment object: \($0.count)" } ?? "no model")
            Button("Increment") { model?.count += 1 }
        }
    }
}

/// The "Controls and looks" section (C10 lane 1, ruling `LK-M`; spec
/// `2026-10-08-controls-looks-design.md` §6): a slider whose editing state and
/// coalesced-edit count are shown beside it — one count per drag, the
/// MetalCreator undo-coalescing case (M5-a) — and two `ColorPicker`s, with and
/// without opacity, driving a swatch (M6-f, MG-7). **Its own function**, its
/// state in its own `Component` (Windows' 1 MB stack,
/// `everyProductionTreeBuildsOnAOneMegabyteThread`). Human checks: the well's
/// look, the panel's drag and keys, and one undo step per drag.
@MainActor
func controlsLooksSection() -> some Element {
    Column(gap: Pixels(12)) {
        Text("Controls and looks").font(size: 22)
        ControlsLooksDemo()
    }
    .alignItems(.flexStart)
}

/// The section's state: the slider's level, whether it is being edited, the
/// edits it has coalesced, and the two pickers' colours. The level starts at
/// 0.65 so its slider never publishes a value the controls slider's VoiceOver
/// script steps read (0.3–0.5, `theVoiceOverScriptQuotesThePublishedTree`).
struct ControlsLooksDemo: Component {
    @State var level = 0.65
    @State var editing = false
    @State var edits = 0
    @State var accent = Color(.sRGB, red: 0.2, green: 0.5, blue: 0.9, opacity: 0.8)
    @State var opaque = Color(.sRGB, red: 0.9, green: 0.4, blue: 0.1)

    var content: some ElementGroup {
        Column(gap: Pixels(10)) {
            Row(gap: Pixels(12)) {
                Slider(value: $level, in: 0...1, onEditingChanged: { began in
                    editing = began
                    if !began { edits += 1 }
                })
                .frame(width: Pixels(220))
                Text(editing ? "editing" : "idle")
                Text("\(edits) coalesced edits, level \(Int((level * 100).rounded()))%")
            }
            Row(gap: Pixels(16)) {
                ColorPicker("Accent", selection: $accent)
                ColorPicker("Opaque", selection: $opaque, supportsOpacity: false)
                Box().frame(width: Pixels(48), height: Pixels(24)).background(accent).cornerRadius(Pixels(4))
                Box().frame(width: Pixels(48), height: Pixels(24)).background(opaque).cornerRadius(Pixels(4))
            }
        }
        .alignItems(.flexStart)
    }
}
