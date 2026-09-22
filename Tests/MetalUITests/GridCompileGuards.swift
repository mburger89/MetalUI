import Testing
import MetalUITestSupport

// Compile-time guards for the grid element API (lane 4 of
// `docs/superpowers/specs/2026-09-17-grids-design.md`, rows G1–G4; rulings GR-J,
// GR-G).
//
// **Every fixture uses `typecheckFile` against a PLAIN `import MetalUI`** (ruling
// SA-P; practices shape 16): three of the four are about what an EXTERNAL module
// may write, and a `@testable` test cannot see an access level or a missing
// overload at all. This file's own imports are irrelevant; the fixture's is the
// one that counts.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "CI — what lapses silently"). Each guard here was run red once on a
// `--build-system native` build, against the mutation its doc names; the red
// lines are in record §22 under lane 4.
//
// **Each real diagnostic is printed before it is asserted on**, so a guard whose
// fragment stopped matching shows what the compiler said instead. And each guard
// carries a POSITIVE control that must compile, so "it did not compile" cannot be
// satisfied by a fixture that is broken for an unrelated reason.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private func show(_ label: String, _ result: TypecheckResult) {
    print("GRID GUARD \(label): succeeded=\(result.succeeded)\n\(result.messages)")
}

/// **G1 — a `Grid` rejects legacy content.** `Grid`'s content is a
/// `ProposalElementGroup`, which no CSS-layout element satisfies, so the
/// migration boundary is a compile error rather than a run-time `SA-G` trap.
///
/// Mutation that must redden it: add an overload
/// `init<L: ElementGroup>(alignment:horizontalSpacing:verticalSpacing:content:)
/// where Content == Rectangle` whose body is `fatalError()` — `Grid { Box() }`
/// then compiles.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aGridRejectsLegacyContent() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() -> Grid<Rectangle> {
            Grid { Rectangle() }
        }
        """, importing: "MetalUI")
    show("1 control", control)
    try #require(control.succeeded,
                 "the positive control must compile, or the negative proves nothing:\n\(control.output)")

    let legacy = try typecheckFile("""
        @MainActor public func bad() {
            _ = Grid { Box() }
        }
        """, importing: "MetalUI")
    show("1 legacy", legacy)
    #expect(!legacy.succeeded, "a Grid over legacy content must not compile:\n\(legacy.output)")
    #expect(legacy.messages.contains("ProposalElementGroup"),
            "rejected, but not by the proposal marker:\n\(legacy.output)")
}

/// **G2 — a `GridRow`'s alignment is a `VerticalAlignment`.** A row aligns its
/// cells on the vertical axis only (ruling GR-G, the kernel reads the vertical
/// factor), and SwiftUI's typed `VerticalAlignment` has no horizontal case, so
/// `GridRow(alignment: .leading)` must not compile — as `HStack`'s does not
/// (`aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks`).
///
/// Mutation that must redden it: make `alignment` a `ProposalAlignment?`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aGridRowAlignmentIsAVerticalAlignment() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() -> GridRow<Rectangle> {
            GridRow(alignment: .top) { Rectangle() }
        }
        """, importing: "MetalUI")
    show("2 control", control)
    try #require(control.succeeded,
                 "the positive control must compile:\n\(control.output)")

    let horizontal = try typecheckFile("""
        @MainActor public func bad() {
            _ = GridRow(alignment: .leading) { Rectangle() }
        }
        """, importing: "MetalUI")
    show("2 horizontal", horizontal)
    #expect(!horizontal.succeeded,
            "a horizontal case must not be a GridRow alignment:\n\(horizontal.output)")
    #expect(horizontal.messages.contains("leading"),
            "rejected, but not for the alignment argument:\n\(horizontal.output)")
}

/// **G3 — `gridColumnAlignment` takes a `HorizontalAlignment`.** A column aligns
/// its cells horizontally only (ruling GR-G, the kernel reads the horizontal
/// factor), so `.gridColumnAlignment(.top)` must not compile.
///
/// Mutation that must redden it: take a `ProposalAlignment`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aGridColumnAlignmentIsAHorizontalAlignment() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() -> GridCellModifier<Rectangle> {
            Rectangle().gridColumnAlignment(.trailing)
        }
        """, importing: "MetalUI")
    show("3 control", control)
    try #require(control.succeeded,
                 "the positive control must compile:\n\(control.output)")

    let vertical = try typecheckFile("""
        @MainActor public func bad() {
            _ = Rectangle().gridColumnAlignment(.top)
        }
        """, importing: "MetalUI")
    show("3 vertical", vertical)
    #expect(!vertical.succeeded,
            "a vertical case must not be a column alignment:\n\(vertical.output)")
    #expect(vertical.messages.contains("top"),
            "rejected, but not for the alignment argument:\n\(vertical.output)")
}

/// **G4 — a cell anchor is nine-point.** Divergence `GR-O` 4: SwiftUI's
/// `gridCellAnchor` takes a `UnitPoint` and probe GL14 reads a fractional one;
/// MetalUI has no `UnitPoint` and takes the nine-case `ProposalAlignment`, so a
/// fractional anchor is a compile error rather than a silent rounding. The owner
/// of the gap is plan task 11 (`GR-N`).
///
/// Mutation that must redden it: add a public `UnitPoint` and a
/// `gridCellAnchor(_: UnitPoint)` overload.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aGridCellAnchorIsNinePoint() throws {
    let control = try typecheckFile("""
        @MainActor public func ok() -> GridCellModifier<Rectangle> {
            Rectangle().gridCellAnchor(.topLeading)
        }
        """, importing: "MetalUI")
    show("4 control", control)
    try #require(control.succeeded,
                 "the positive control must compile:\n\(control.output)")

    let unitPoint = try typecheckFile("""
        @MainActor public func bad() {
            _ = Rectangle().gridCellAnchor(UnitPoint(x: 0.25, y: 1))
        }
        """, importing: "MetalUI")
    show("4 unit point", unitPoint)
    #expect(!unitPoint.succeeded,
            "a fractional anchor must not compile:\n\(unitPoint.output)")
    #expect(unitPoint.messages.contains("UnitPoint"),
            "rejected, but not for the anchor argument:\n\(unitPoint.output)")
}
