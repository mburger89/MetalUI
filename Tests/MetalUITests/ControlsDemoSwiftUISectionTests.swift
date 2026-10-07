import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI
@testable import MetalUIDemoContent   // swiftUIVocabularySection (internal)

// Spec `docs/superpowers/specs/2026-10-06-proposal-controls-design.md` §6.3,
// test 3.1 (lane 3), §7 (the demo). Rulings `PE-B`, `PE-C`, `PE-D`, `PE-M` in
// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`.
//
// The controls demo's "SwiftUI vocabulary" section is the probe's form `FM0`
// and status bar `ST0` written in SwiftUI's spelling, wired to the demo's
// `@State`. The form's rows are the same tree as test 1.5's
// (`aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt`), so its frames,
// relative to the form's own origin, are test 1.5's literals.

private func path(_ base: GlobalElementID, _ tail: [Int]) -> GlobalElementID {
    tail.reduce(base) { GlobalElementID.child(of: $0, at: $1, name: nil) }
}

private func xywh(_ b: Bounds<Pixels>?) -> [Float]? {
    b.map { [$0.origin.x.value, $0.origin.y.value, $0.size.width.value, $0.size.height.value] }
}

/// The section with constant bindings — the demo's initial values.
@MainActor private func section() -> some Element {
    swiftUIVocabularySection(name: .constant(""), enabled: .constant(true), speed: .constant(0.75),
                             flavor: .constant(.chocolate), quantity: .constant(2))
}

/// **3.1** (`PE-B`, `PE-M`; probe `FM0`, `ST0`). The section rendered in
/// diagnostics mode at 920×560 reports nothing; its rows hold the expected
/// controls at the paths the builder gives them (`LegacyContent` is
/// identity-transparent, `PE-C` item 1), laid out as test 1.5's form relative to
/// the form's origin; the status bar's labels sit in one 26-tall row whose
/// trailing label ends 16 before the bar's trailing edge. The whole controls
/// demo also renders with an empty report.
///
/// Red before: does not compile (`swiftUIVocabularySection` does not exist).
/// Mutation M3.1: the section's `TextField` gains `.flexGrow(1)` →
/// `textField.flexGrow.unconsumed` (`PE-C` item 4).
@Test @MainActor func theControlsDemosSwiftUISectionLaysOutWithoutReports() throws {
    let report = LayoutDifferential.report(width: 920, height: 560) { section() }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable.map(\.description))")
    let b = report.bounds
    // `DifferentialRoot` is `[0]`, its content `[0, 0]`: the section's
    // `.frame(maxWidth: 400)` layer, the section's `VStack` `[0, 0, 0]` under it.
    let root = path(GlobalElementID.child(of: nil, at: 0, name: nil), [0])
    let stack = path(root, [0])
    let sectionFrame = try #require(b[root], "the section's frame layer")
    #expect(sectionFrame.size.width.value == 400, "the section is 400 wide: \(sectionFrame)")
    #expect(b[path(stack, [0])] != nil, "the title is the section's first child")

    // The form: `.padding(16)` layer at `[…, 1]`, its `VStack` at `[…, 1, 0]`.
    let formLayer = path(stack, [1])
    let form = path(formLayer, [0])
    let origin = try #require(b[formLayer], "the form's padding layer")
    #expect(origin.size.width.value == 400 && origin.size.height.value == 177,
            "the form is FM0's 400×177 (test 1.5): \(origin)")
    func rel(_ tail: Int...) -> [Float]? {
        xywh(b[path(form, tail)]).map {
            [$0[0] - origin.origin.x.value, $0[1] - origin.origin.y.value, $0[2], $0[3]]
        }
    }
    #expect(rel(0) == [16, 16, 368, 16], "row a: \(String(describing: rel(0)))")
    #expect(rel(0, 0) == [16, 16, 35, 16], "label Name: \(String(describing: rel(0, 0)))")
    #expect(rel(0, 1) == [59, 16, 325, 16], "TextField: \(String(describing: rel(0, 1)))")
    #expect(rel(1, 0) == [16, 44, 70, 16], "Toggle(Enabled): \(String(describing: rel(1, 0)))")
    #expect(rel(1, 2) == [325, 40, 59, 24], "Button(Apply): \(String(describing: rel(1, 2)))")
    #expect(rel(2, 0) == [16, 72, 39, 16], "label Speed: \(String(describing: rel(2, 0)))")
    #expect(rel(2, 1) == [63, 72, 321, 16], "Slider: \(String(describing: rel(2, 1)))")
    // Test 1.5's picker is 113 wide over "Alpha"/"Beta"; this one's options are
    // the demo's flavours, and a menu picker hugs its label and widest option
    // ("Strawberry"): 145, measured by lane 3 (divergence 131's metrics).
    #expect(rel(3) == [16, 96, 145, 24], "Picker.menu: \(String(describing: rel(3)))")
    #expect(rel(4) == [16, 128, 368, 1], "Divider: \(String(describing: rel(4)))")
    #expect(rel(5, 0) == [16, 137, 50, 24], "Stepper(Qty): \(String(describing: rel(5, 0)))")

    // The controls are the ones the rows name (accessibility records by id; a
    // `Button` declares `.generic` and is a button by its click handler, `AB-H`).
    let records = Dictionary(report.frame.axEmissions.map { ($0.id, $0) },
                             uniquingKeysWith: { first, _ in first })
    let expectedRoles: [([Int], AXRole)] = [
        ([0, 1], .textField), ([1, 0], .checkBox), ([2, 1], .slider), ([5, 0], .incrementor),
    ]
    for (tail, role) in expectedRoles {
        let found = records[path(form, tail)]?.declared.role
        #expect(found == role, "\(tail) is a \(role): \(String(describing: found))")
    }
    #expect(records[path(form, [1, 2])]?.isClickable == true, "[1, 2] is the Apply button")

    // The status bar: `.background` `[…, 2]`, `.frame` `[…, 2, 0]`, `.padding`
    // `[…, 2, 0, 0]`, the font scope transparent, its `HStack` `[…, 2, 0, 0, 0]`.
    let barLayer = path(stack, [2])
    let bar = try #require(b[barLayer], "the status bar")
    #expect(bar.size.width.value == 400 && bar.size.height.value == 26, "the bar is 400×26: \(bar)")
    let row = path(barLayer, [0, 0, 0])
    let trailing = try #require(b[path(row, [5])], "the trailing label")
    #expect(trailing.origin.x.value + trailing.size.width.value == bar.origin.x.value + 384,
            "the trailing label ends 16 before the bar's edge: \(trailing) in \(bar)")
    for index in [0, 1, 2, 3, 5] {
        let child = try #require(b[path(row, [index])], "bar child \(index)")
        #expect(child.origin.y.value >= bar.origin.y.value
                    && child.origin.y.value + child.size.height.value <= bar.origin.y.value + 26,
                "bar child \(index) sits inside the bar: \(child)")
    }

    // The whole demo, legacy section and SwiftUI section together.
    let demo = LayoutDifferential.report(width: 920, height: 560) { controlsDemoContent() }
    #expect(demo.unlowerable.isEmpty, "\(demo.unlowerable.map(\.description))")
}
