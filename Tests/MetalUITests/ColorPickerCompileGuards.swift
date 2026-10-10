import Testing
import MetalUITestSupport

// C10 lane 1 guards (rulings `LK-B`, `LK-P`; spec
// `2026-10-08-controls-looks-design.md` §4.1). Each fixture compiles against a
// PLAIN `import MetalUI` as whole-file Swift 6 (`typecheckFile`, ruling SA-P),
// so it can fail only for its spelling. No `PlatformWindow` conformer here
// (`LK-T` item 1).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `CONTROLS LOOKS GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G1.1** (`LK-B` item 1) — SwiftUI's spellings: `Slider(value:in:onEditingChanged:)`,
/// `Slider(value:in:step:onEditingChanged:)` and the trailing closure
/// `Slider(value:) { editing in … }`, from outside the module. The control
/// misspells the label (`onEditingChange:`), which must not compile.
///
/// Mutation that must redden it: rename the parameter.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSliderInitialisersKeepTheirSwiftUISpellings() throws {
    func source(_ label: String) -> String {
        """
        public struct Editor: Component {
            @State var level = 0.5
            @State var steps: Float = 2
            @State var edits = 0
            public init() {}
            public var content: some ElementGroup {
                Slider(value: $level, in: 0...1, \(label): { editing in if !editing { edits += 1 } })
                Slider(value: $steps, in: 0...10, step: 1, onEditingChanged: { _ in })
                Slider(value: $level) { editing in if editing { edits += 1 } }
            }
        }
        """
    }
    let positive = try typecheckFile(source("onEditingChanged"), importing: "MetalUI")
    print("CONTROLS LOOKS GUARD G1.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("onEditingChange"), importing: "MetalUI")
    print("CONTROLS LOOKS GUARD G1.1 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "SwiftUI's slider spellings must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a misspelled label must not compile:\n\(control.output)")
}

/// **G1.2** (`LK-P` items 2, 4) — `ColorPicker` is one `StyledElement`: a
/// title or a label view, `supportsOpacity:`, then `.padding(4).background(.surface)`
/// chained on it, from outside the module. The control chains the same on a
/// `Component` (which takes no `StyledElement` modifier), so the two arms
/// disagree for the conformance alone.
///
/// Mutation that must redden it: drop the `StyledElement` conformance.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aColorPickerTakesABackgroundAndPadding() throws {
    func source(_ subject: String) -> String {
        """
        struct Pane: Component {
            var content: some ElementGroup { Text("pane") }
        }
        public struct Palette: Component {
            @State var tint = Color.red
            @State var solid = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6)
            public init() {}
            public var content: some ElementGroup {
                \(subject).padding(Pixels(4)).background(.surface)
                ColorPicker(selection: $solid, supportsOpacity: false) { Text("Solid") }
                ColorPicker("", selection: $tint)
            }
        }
        """
    }
    let positive = try typecheckFile(source("ColorPicker(\"Tint\", selection: $tint, supportsOpacity: true)"),
                                     importing: "MetalUI")
    print("CONTROLS LOOKS GUARD G1.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("Pane()"), importing: "MetalUI")
    print("CONTROLS LOOKS GUARD G1.2 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "a ColorPicker must take StyledElement modifiers:\n\(positive.output)")
    #expect(!control.succeeded, "a Component takes no StyledElement modifier:\n\(control.output)")
}
