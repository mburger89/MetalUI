import Testing
import MetalUITestSupport

// Compile-time guards for plan task 11, part 2, lane 2 (spec
// `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §8 lane 2,
// G2.1 and G2.2; rulings `TE-AG`, `TE-AH`, `TE-AQ` items 1–2).
//
// **Both use `typecheckFile`** — whole-file, Swift 6, a PLAIN `import MetalUI`,
// as an external module writes it (`SA-P`; practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards").

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — an outside shape needs only its geometry** (`TE-AG` item 1,
/// `TE-AQ` item 1). A struct conforming to `Shape` with `geometry(in:)` alone
/// compiles, fills, strokes, and **sits bare in an `HStack`** — so `Shape`'s
/// extension supplies the phases and the proposal entry, and a shape is a
/// `ProposalElement`. **Control**: the same struct without `geometry(in:)`
/// fails, naming it — so the positive compiles for the reason given.
///
/// **Control amended by `GX-V` item 2** (paths, shadows and transforms):
/// since `GX-D` both `geometry(in:)` and `path(in:)` are defaulted, so a
/// conformer missing `geometry(in:)` compiles (and traps at its first paint,
/// test 3.4). The control is now the same struct with `geometry(in:)` but
/// **without the `Shape` conformance** — it fails at `.fill`, so the
/// positive's `.fill`, `.stroke` and `HStack` membership come from `Shape`.
///
/// Mutations: **MG2a** `sizeThatFits`'s default removed (the positive fails);
/// **MG2a′** `Shape` refines `Element` instead of `ProposalElement` (the
/// `HStack` arm fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideShapeNeedsOnlyItsGeometry() throws {
    func fixture(_ body: String, conformance: String = ": Shape") -> String {
        """
        public struct Diamondish\(conformance) {
            public init() {}
        \(body)
        }

        @MainActor public func use() {
            _ = Diamondish().fill(.accent)
            _ = Diamondish().stroke(.accent, lineWidth: Pixels(2))
            _ = HStack { Diamondish(); Diamondish().fill(.accent) }
            _ = Diamondish().frame(width: Pixels(10))
        }
        """
    }
    let with = try typecheckFile(fixture("""
            public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
                .roundedRectangle(rect, cornerRadii: Corners(all: Pixels(2)))
            }
        """), importing: "MetalUI")
    let without = try typecheckFile(fixture("""
            public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
                .roundedRectangle(rect, cornerRadii: Corners(all: Pixels(2)))
            }
        """, conformance: ""), importing: "MetalUI")

    print("""
        G2.1 outside shape: with succeeded=\(with.succeeded) messages=[\(with.messages)]; \
        without succeeded=\(without.succeeded) messages=[\(without.messages)]
        """)

    try #require(with.succeeded && !without.succeeded,
                 """
                 the positive must compile and the control must not, or this guard \
                 cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("fill"),
            "the control must be refused FOR .fill (no Shape conformance):\n\(without.output)")
}

/// **G2.2 — `Rectangle(color:)` is deprecated toward `.fill(_:)`** (`TE-AH`):
/// a bare `Rectangle()` fills with the foreground style now, and the explicit
/// colour spelling names its replacement. **Control**: `Rectangle().fill(.accent)`
/// and the undeprecated fixed `Rectangle(width:height:color:)` warn nothing.
///
/// Mutation: **MG2b** the deprecation dropped.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theRectangleColorInitialiserIsDeprecatedTowardFill() throws {
    let deprecated = try typecheckFile("""
        @MainActor public func probe() {
            _ = Rectangle(color: .accent)
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor public func probe() {
            _ = Rectangle().fill(.accent)
            _ = Rectangle(width: Pixels(4), height: Pixels(4), color: .accent)
            _ = Rectangle()
        }
        """, importing: "MetalUI")
    let lines = deprecated.messages.split(separator: "\n").filter { $0.contains("is deprecated") }
    let controlLines = control.messages.split(separator: "\n").filter { $0.contains("is deprecated") }

    print("""
        G2.2 Rectangle(color:): succeeded=\(deprecated.succeeded) count=\(lines.count) \
        messages=[\(deprecated.messages)]; control succeeded=\(control.succeeded) \
        count=\(controlLines.count) messages=[\(control.messages)]
        """)

    try #require(deprecated.succeeded && control.succeeded,
                 "both must still compile:\n\(deprecated.output)\n\(control.output)")
    #expect(lines.count == 1 && lines[0].contains("init(color:)") && lines[0].contains("fill"),
            "one deprecation, naming fill:\n\(deprecated.output)")
    #expect(controlLines.isEmpty, "the control warns nothing:\n\(control.output)")
}
