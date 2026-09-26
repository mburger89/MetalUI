import Testing
import MetalUITestSupport

// Plan task 10, part 2, lane 1, guards G1.1–G1.2 (rulings `DD-R`, `DD-S`,
// `DD-V`). Each fixture compiles against a PLAIN `import MetalUI` — this file's
// own imports are irrelevant (shape 16). Both are whole-file Swift 6
// (`typecheckFile`, ruling SA-P), `@MainActor` where a main-actor API is
// called, so a fixture can fail only for its spelling.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `CONTROLS GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.1 — the lane-1 controls' SwiftUI spellings compile from outside the
/// module** (spec §3): `Button(action:label:)`, `Button(_:action:)`,
/// `Toggle(isOn:label:)`, `Toggle(_:isOn:)` over a `@State` projection,
/// `Picker(_:selection:content:)` with `.tag(_:)` options and
/// `.pickerStyle(.segmented/.radioGroup/.automatic)`, and `.controlSize` on a
/// button. The control passes a plain `Bool` where the binding goes.
///
/// Mutation that must redden it (MG1.1): `Toggle.init(_:isOn:)` made internal.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theControlsSwiftUISpellingsCompileFromOutsideTheModule() throws {
    func source(_ isOn: String) -> String {
        """
        public enum Flavor: Hashable, Sendable { case vanilla, chocolate }

        public struct Settings: Component {
            @State var wifi = false
            @State var flavor = Flavor.vanilla
            public init() {}
            public var content: some ElementGroup {
                Button("Go") { wifi.toggle() }
                Button(action: { wifi = true }) { Text("Label") }
                    .controlSize(.small)
                Toggle("Wi-Fi", isOn: \(isOn))
                Toggle(isOn: $wifi) { Text("Bluetooth") }
                Picker("Flavor", selection: $flavor) {
                    Text("Vanilla").tag(Flavor.vanilla)
                    Text("Chocolate").tag(Flavor.chocolate)
                }
                .pickerStyle(.segmented)
                Picker("Again", selection: $flavor) {
                    Text("Vanilla").tag(Flavor.vanilla)
                }
                .pickerStyle(.radioGroup)
                Picker("Default", selection: $flavor) {
                    Text("Vanilla").tag(Flavor.vanilla)
                }
                .pickerStyle(.automatic)
            }
        }
        """
    }
    let positive = try typecheckFile(source("$wifi"), importing: "MetalUI")
    print("CONTROLS GUARD G1.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("wifi"), importing: "MetalUI")
    print("CONTROLS GUARD G1.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the SwiftUI spellings must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a plain Bool is not a binding:\n\(control.output)")
}

/// **G1.2 — `.pickerStyle(.menu)` is not offered** (`DD-V` item 4, divergence
/// 81): the menu style fails to typecheck, where the same picker with
/// `.segmented` succeeds (control).
///
/// Mutation that must redden it (MG1.2): `public static let menu` added to
/// `PickerStyle`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aMenuPickerStyleIsNotOffered() throws {
    func source(_ style: String) -> String {
        """
        @MainActor func picker(_ selection: Binding<Int>) -> some Element {
            Picker("N", selection: selection) {
                Text("one").tag(1)
            }
            .pickerStyle(.\(style))
        }
        """
    }
    let menu = try typecheckFile(source("menu"), importing: "MetalUI")
    print("CONTROLS GUARD G1.2 menu: succeeded=\(menu.succeeded)\n\(menu.messages)")
    let control = try typecheckFile(source("segmented"), importing: "MetalUI")
    print("CONTROLS GUARD G1.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(menu.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(menu.output)\n\(control.output)")
    #expect(!menu.succeeded, "`.menu` must not be offered:\n\(menu.output)")
    #expect(menu.messages.contains("menu"), "rejected for the missing member:\n\(menu.output)")
    #expect(control.succeeded, "`.segmented` is offered:\n\(control.output)")
}
