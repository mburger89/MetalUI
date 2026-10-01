import Testing
import MetalUITestSupport

// Compile-time guards for plan task 6's typed stack alignments (lane 3 of
// `docs/superpowers/specs/2026-09-16-containers-design.md`; ruling CN-I in
// `docs/superpowers/2026-09-16-containers-decisions.md`).
//
// `HStack` takes a `VerticalAlignment` and `VStack` a `HorizontalAlignment`,
// `alignment:` before `spacing:` as in SwiftUI; the old spacing-first
// initializer over the nine-case `ProposalAlignment` stays, deprecated, with no
// default arguments. What an external module can and cannot write is a
// compile-time property, so every fixture uses `typecheckFile` against a PLAIN
// `import MetalUI` (ruling SA-P; practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "CI — what lapses silently"): take its run under
// `--build-system native`. Each guard here was run red once, and mutated red
// once after the lane landed; the lines are in record §17 under lane 3.
//
// **Each real diagnostic is printed before it is asserted on**, so a guard
// whose fragment stopped matching shows what the compiler said instead.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("CONTAINER GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// The number of diagnostics in `result` that report a deprecated use.
private func deprecations(_ result: TypecheckResult) -> Int {
    result.messages.split(separator: "\n").filter { $0.contains("is deprecated") }.count
}

/// **G1 — an alignment of the wrong axis does not compile.** SwiftUI's
/// `HStack(alignment: .leading)` is an error (`VerticalAlignment` has no
/// `leading`), and so is `VStack(alignment: .top)`. Before lane 3 both compiled
/// over the nine-case `ProposalAlignment` and placed like `.center` (CLAUDE.md's
/// inert row). The positive control is the same shape with the right axis.
///
/// Mutation that must redden it: give `VerticalAlignment` a `leading` case.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks() throws {
    let control = try typecheckFile("""
        @MainActor func build() {
            _ = HStack(alignment: .top) { Rectangle(width: Pixels(10), height: Pixels(10)) }
            _ = VStack(alignment: .leading) { Rectangle(width: Pixels(10), height: Pixels(10)) }
        }
        """, importing: "MetalUI")
    show("G1 control", control)
    try #require(control.succeeded, "the right-axis spellings must compile:\n\(control.output)")

    let hStack = try typecheckFile("""
        @MainActor func build() {
            _ = HStack(alignment: .leading) { Rectangle(width: Pixels(10), height: Pixels(10)) }
        }
        """, importing: "MetalUI")
    show("G1 HStack .leading", hStack)
    #expect(!hStack.succeeded, "HStack(alignment: .leading) must not compile:\n\(hStack.output)")
    #expect(hStack.messages.contains("type 'VerticalAlignment' has no member 'leading'"),
            "rejected, but not by the alignment's type:\n\(hStack.output)")

    let vStack = try typecheckFile("""
        @MainActor func build() {
            _ = VStack(alignment: .top) { Rectangle(width: Pixels(10), height: Pixels(10)) }
        }
        """, importing: "MetalUI")
    show("G1 VStack .top", vStack)
    #expect(!vStack.succeeded, "VStack(alignment: .top) must not compile:\n\(vStack.output)")
    #expect(vStack.messages.contains("type 'HorizontalAlignment' has no member 'top'"),
            "rejected, but not by the alignment's type:\n\(vStack.output)")
}

/// **G2 — SwiftUI's spellings compile, with no deprecation.** `alignment:`
/// before `spacing:`, `spacing: nil` for the platform default, a `Pixels`
/// spacing, and a stack with neither argument. None of the first two compiled
/// before lane 3.
///
/// Mutation that must redden it: swap the new initializer's two parameters.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theTypedStackInitializersCompileInSwiftUIsArgumentOrder() throws {
    let result = try typecheckFile("""
        @MainActor func build() {
            _ = HStack(alignment: .top, spacing: nil) { Rectangle(width: Pixels(10), height: Pixels(10)) }
            _ = VStack(alignment: .trailing, spacing: Pixels(4)) { Rectangle(width: Pixels(10), height: Pixels(10)) }
            _ = HStack {}
        }
        """, importing: "MetalUI")
    show("G2", result)
    #expect(result.succeeded, "SwiftUI's argument order must compile:\n\(result.output)")
    #expect(deprecations(result) == 0, "the new initializers are not deprecated:\n\(result.output)")
}

/// **G3 — the spacing-first initializers are deprecated.** The old spelling
/// still compiles (it has callers) and draws exactly one deprecation per stack.
///
/// Mutation that must redden it: remove one of the two `@available`s.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSpacingFirstStackInitializersAreDeprecated() throws {
    let result = try typecheckFile("""
        @MainActor func build() {
            _ = HStack(spacing: Pixels(8), alignment: .center) {}
            _ = VStack(spacing: Pixels(8), alignment: .center) {}
        }
        """, importing: "MetalUI")
    show("G3", result)
    #expect(result.succeeded, "the old order must still compile:\n\(result.output)")
    #expect(deprecations(result) == 2,
            "one deprecation per spacing-first stack:\n\(result.output)")
    #expect(result.messages.contains("'init(spacing:alignment:content:)' is deprecated"),
            "deprecated, but not the spacing-first initializer:\n\(result.output)")
}

/// **G4 — every `fraction:` and `percent:` sizing spelling is deprecated**
/// (rulings `CN-O`, `LR-EU`, and — inverting this guard's flexBasis arm — `CX-C`
/// item 2, plan task 15). All six spellings compile from a plain
/// `import MetalUI`. The three `fraction:` calls draw three deprecations:
/// stage 8 deprecated the two sizing ones (`LR-EU`, the control arm's T row,
/// T3.1) and the closeout deprecated `flexBasis(fraction:)` (`CX-C`: a fraction
/// basis is a percentage, reported by name and a production trap, `LR-FO`).
/// The `percent:` calls draw three more: `width`/`height(percent:)` as renames
/// of their `fraction:` spellings, `flexBasis(percent:)` with `flexBasis(fraction:)`'s
/// own message rather than a rename to a deprecated name (`CX-P` item 7).
///
/// **T row (`CX-C`)**: this guard was `thePercentSizingModifiersAreDeprecatedRenamesOfFraction`
/// and asserted `flexBasis(fraction:)` was NOT deprecated and `flexBasis(percent:)`
/// renamed to it; both answers inverted by ruling. Red at `1b093b8`. Mutation
/// **MT1**: delete `flexBasis(fraction:)`'s `@available` → this guard.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theFractionAndPercentSizingModifiersAreAllDeprecated() throws {
    // T3.1 (stage 8, `LR-EU` items 3–4) then `CX-C` (plan task 15): the control
    // arm read 0, then 2 (the sizing fractions), and now reads all 3.
    let control = try typecheckFile("""
        @MainActor func build() {
            _ = Box().width(fraction: 0.5).height(fraction: 0.5).flexBasis(fraction: 0.5)
        }
        """, importing: "MetalUI")
    show("G4 control", control)
    try #require(control.succeeded, "the fraction: spellings must compile:\n\(control.output)")
    #expect(deprecations(control) == 3,
            "width(fraction:), height(fraction:) (LR-EU) and flexBasis(fraction:) (CX-C) are deprecated:\n\(control.output)")
    #expect(control.messages.contains("'width(fraction:)' is deprecated")
                && control.messages.contains("'height(fraction:)' is deprecated")
                && control.messages.contains("'flexBasis(fraction:)' is deprecated"),
            "the three deprecations must be the three fractions':\n\(control.output)")
    let basisOnly = try typecheckFile("""
        @MainActor func build() {
            _ = Box().flexBasis(fraction: 0.5)
        }
        """, importing: "MetalUI")
    show("G4 flexBasis(fraction:)", basisOnly)
    try #require(basisOnly.succeeded, "flexBasis(fraction:) must compile:\n\(basisOnly.output)")
    #expect(deprecations(basisOnly) == 1, "flexBasis(fraction:) is deprecated (CX-C item 2):\n\(basisOnly.output)")

    let result = try typecheckFile("""
        @MainActor func build() {
            _ = Box().width(percent: 0.5)
            _ = Box().height(percent: 0.5)
            _ = Box().flexBasis(percent: 0.5)
        }
        """, importing: "MetalUI")
    show("G4", result)
    #expect(result.succeeded, "the percent: spellings must still compile:\n\(result.output)")
    #expect(deprecations(result) == 3, "one deprecation per percent: modifier:\n\(result.output)")
    for name in ["width", "height"] {
        #expect(result.messages.contains("'\(name)(percent:)' is deprecated: renamed to '\(name)(fraction:)'"),
                "\(name)(percent:) is not a deprecated rename of \(name)(fraction:):\n\(result.output)")
    }
    #expect(result.messages.contains("'flexBasis(percent:)' is deprecated")
                && !result.messages.contains("renamed to 'flexBasis(fraction:)'"),
            "flexBasis(percent:) carries a message, not a rename to a deprecated spelling (CX-P item 7):\n\(result.output)")
}
