import Testing
import MetalUITestSupport

// C10 lane 3 guard (rulings `LK-R`, `LK-L`; spec
// `2026-10-08-controls-looks-design.md` §4.3, guard 3.T1). The fixture
// compiles against a PLAIN `import MetalUI` as whole-file Swift 6
// (`typecheckFile`, ruling SA-P), so it can fail only for its spellings. No
// `PlatformWindow` conformer here (`LK-T` item 1).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `CONTROLS LOOKS GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **3.T1** (`LK-R` items 2 and 4, `LK-L` item 1) — the gradient and material
/// spellings resolve without ambiguity beside the colour and token ones, from
/// outside the module, in one file: `.background(.ultraThinMaterial)` and
/// `.background(.surface)` on a proposal view, `.fill(.red)`,
/// `.fill(LinearGradient(…))`, `.fill(LinearGradient(…), style:
/// FillStyle(eoFill: true))`, a `RadialGradient` fill and background, a
/// gradient view in a stack, `.blur(radius:)` on both vocabularies, and the
/// legacy `Text("x").background(.thinMaterial, in: Capsule())`. The control
/// writes `.background(.surfaceMaterial)`, a member no type offers, which must
/// not compile.
///
/// Mutations that must redden it: add `static let surface` to `Material`
/// (`.background(.surface)` becomes ambiguous); declare `background(_:in:)`
/// on `ProposalElementGroup` only (the legacy line fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func materialSpellingsResolveWithoutAmbiguity() throws {
    func source(_ member: String) -> String {
        """
        let wash = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
        let glow = RadialGradient(colors: [.white, .black], center: .center, startRadius: Pixels(0),
                                  endRadius: Pixels(40))

        public struct Looks: Component {
            public init() {}
            public var content: some ElementGroup {
                VStack {
                    Text("glass").padding(Pixels(4)).background(.\(member))
                    Text("token").background(.surface)
                    Circle().fill(.red)
                    Circle().fill(wash)
                    Circle().fill(wash, style: FillStyle(eoFill: true))
                    Rectangle().fill(glow).stroke(.blue, lineWidth: Pixels(2))
                    RoundedRectangle(cornerRadius: Pixels(6)).fill(.regularMaterial)
                    Text("panel").background(wash)
                    Text("halo").background(glow)
                    wash.frame(width: Pixels(40), height: Pixels(10))
                    Text("soft").blur(radius: Pixels(3))
                }
                Text("x").background(.thinMaterial, in: Capsule())
                Box().background(wash).blur(radius: Pixels(2))
                Box().background(.bar)
            }
        }
        """
    }
    let positive = try typecheckFile(source("ultraThinMaterial"), importing: "MetalUI")
    print("CONTROLS LOOKS GUARD 3.T1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let control = try typecheckFile(source("surfaceMaterial"), importing: "MetalUI")
    print("CONTROLS LOOKS GUARD 3.T1 control: succeeded=\(control.succeeded)\n\(control.messages)")
    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the looks spellings must resolve outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "a member no type offers must not compile:\n\(control.output)")
}
