import Foundation
import Testing
import MetalUITestSupport

// The "typed units never implicitly convert" invariant is a *negative* property:
// it is about what must NOT compile. No ordinary test can observe it, because a
// regression (adding `Numeric`, or a cross-unit operator overload) would make the
// offending code compile and every existing test would stay green. So this guard
// shells out to `swiftc -typecheck` against the built module and asserts that each
// illegal expression is rejected — and, to keep the guard honest, that the legal
// ones are still accepted.
//
// The machinery — `typecheck`, `modulesDirectory`, `canTypecheck` — used to be
// `private` here. It now lives in `MetalUITestSupport` so this target and
// `MetalUITests` share **one** copy; ruling EP-1 explains why a second copy is a
// hazard rather than a duplication.

@Test(
    .enabled(if: canTypecheck(module: "MetalUICore"),
             "built module directory .build/<triple>/debug/Modules not found — unit-mixing guard skipped")
)
func illegalUnitExpressionsDoNotCompile() throws {
    // Each case names the types its diagnostic must mention. **`!succeeded`
    // alone is not enough**, and this test proved it twice: a `Pixels` ->
    // `Pixles` typo in one fixture left it green (`cannot find 'Pixles' in
    // scope` is a perfectly good failure to compile), and so did a poisoned
    // `.build/index-build` module, under which *nothing* compiled and every
    // illegal case "passed". A guard that green-lights an empty compiler is
    // asserting nothing about units.
    //
    // The types are asserted rather than the message wording: `binary operator
    // '+' cannot be applied to operands of type 'Pixels' and 'ScaledPixels'`
    // may be reworded by a future compiler, but a rejection *about these two
    // types* is the invariant. Note that `Pixles` contains neither `Pixels` nor
    // `ScaledPixels`, which is what makes a fixture typo visible here.
    let illegal: [(description: String, code: String, mentions: [String])] = [
        ("adding Pixels to ScaledPixels",
         "let v = Pixels(1) + ScaledPixels(1); _ = v", ["Pixels", "ScaledPixels"]),
        ("multiplying Pixels by Pixels",
         "let v = Pixels(1) * Pixels(2); _ = v", ["Pixels", "Float"]),
        ("assigning ScaledPixels to Pixels",
         "let v: Pixels = ScaledPixels(1); _ = v", ["Pixels", "ScaledPixels"]),
        ("comparing Pixels with ScaledPixels",
         "let v = Pixels(1) < ScaledPixels(2); _ = v", ["Pixels", "ScaledPixels"]),
    ]

    for (description, code, mentions) in illegal {
        let result = try typecheck(code, importing: "MetalUICore")
        #expect(
            !result.succeeded,
            "\(description) compiled, but must not — units are mixing implicitly.\n\(result.output)"
        )
        for type in mentions {
            #expect(
                result.messages.contains(type),
                "\(description) was rejected, but no diagnostic mentions '\(type)', so this case is not testing units — a fixture typo and a broken toolchain both land here.\n\(result.output)"
            )
        }
    }
}

@Test(
    .enabled(if: canTypecheck(module: "MetalUICore"),
             "built module directory .build/<triple>/debug/Modules not found — unit-mixing guard skipped")
)
func legalUnitExpressionsStillCompile() throws {
    let legal: [(description: String, code: String)] = [
        ("adding Pixels to Pixels", "let v = Pixels(1) + Pixels(2); _ = v"),
        ("integer literal as Pixels", "let v: Pixels = 5; _ = v"),
        ("scaling Pixels by a Float", "let v = Pixels(1) * 2.0; _ = v"),
    ]

    for (description, code) in legal {
        let result = try typecheck(code, importing: "MetalUICore")
        #expect(
            result.succeeded,
            "\(description) failed to compile, but must succeed — the guard itself is broken.\n\(result.output)"
        )
    }
}
