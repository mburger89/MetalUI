import Testing
import MetalUITestSupport

// Plan task 10, part 2, lane 2, guard G2.1 (rulings `DD-W`, `DD-X`). The
// fixture compiles against a PLAIN `import MetalUI` — this file's own imports
// are irrelevant (shape 16) — as whole-file Swift 6 (`typecheckFile`, ruling
// SA-P), so it can fail only for its spelling.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SLIDER STEPPER GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — the lane-2 controls' SwiftUI spellings compile from outside the
/// module** (spec §3): `Slider(value:)`, `Slider(value:in:)` and
/// `Slider(value:in:step:)` over a `@State` projection of a `Double` and a
/// `Float`, `Stepper(_:value:in:step:)`, `Stepper(_:value:step:)` and
/// `Stepper(_:onIncrement:onDecrement:)`. The control passes a plain `Double`
/// where the slider's binding goes.
///
/// Mutation that must redden it (MG2.1): `Slider.init(value:in:step:)` made
/// internal.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSliderAndStepperSpellingsCompileFromOutsideTheModule() throws {
    func source(_ volume: String) -> String {
        """
        public struct Mixer: Component {
            @State var volume = 0.5
            @State var pan: Float = 0
            @State var count = 1
            public init() {}
            public var content: some ElementGroup {
                Slider(value: \(volume))
                Slider(value: $pan, in: -1...1)
                Slider(value: $volume, in: 0...10, step: 0.5)
                Stepper("Count", value: $count, in: 0...10)
                Stepper("Count", value: $count, in: 0...10, step: 2)
                Stepper("Count", value: $count, step: 5)
                Stepper("Nudge", onIncrement: { count += 1 }, onDecrement: nil)
            }
        }
        """
    }
    let positive = try typecheckFile(source("$volume"), importing: "MetalUI")
    print("SLIDER STEPPER GUARD G2.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("volume"), importing: "MetalUI")
    print("SLIDER STEPPER GUARD G2.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the SwiftUI spellings must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a plain Double is not a binding:\n\(control.output)")
}
