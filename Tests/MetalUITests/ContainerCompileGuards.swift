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

/// **G4 — the `percent:` sizing modifiers are deprecated renames of
/// `fraction:`** (ruling `CN-O`). Both spellings compile from a plain
/// `import MetalUI`; the three `fraction:` calls draw no diagnostic, and the
/// three `percent:` calls draw exactly three deprecations, each naming its
/// `fraction:` replacement.
///
/// Red before the lane: `fraction:` does not exist and `percent:` is not
/// deprecated. Mutation that must redden it: remove one `@available`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func thePercentSizingModifiersAreDeprecatedRenamesOfFraction() throws {
    let control = try typecheckFile("""
        @MainActor func build() {
            _ = Box().width(fraction: 0.5).height(fraction: 0.5).flexBasis(fraction: 0.5)
        }
        """, importing: "MetalUI")
    show("G4 control", control)
    try #require(control.succeeded, "the fraction: spellings must compile:\n\(control.output)")
    #expect(deprecations(control) == 0, "fraction: is not deprecated:\n\(control.output)")

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
    for name in ["width", "height", "flexBasis"] {
        #expect(result.messages.contains("'\(name)(percent:)' is deprecated: renamed to '\(name)(fraction:)'"),
                "\(name)(percent:) is not a deprecated rename of \(name)(fraction:):\n\(result.output)")
    }
}
