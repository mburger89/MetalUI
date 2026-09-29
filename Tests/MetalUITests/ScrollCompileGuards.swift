import Testing
import MetalUITestSupport

// Plan task 10, part 1, lane 3, guards G3.1–G3.2 (rulings `DD-G`, `DD-H`).
// Whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling
// SA-P): what an external module may write with `ScrollViewReader`.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `SCROLL GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1 — an external module can write `ScrollViewReader`, `scrollTo` and the
/// new indicator cases.** `ScrollViewReader { proxy in ScrollView { … } }`, a
/// handler calling `proxy.scrollTo(3, anchor: .top)` and `proxy.scrollTo("x")`,
/// `UnitPoint(x: 0, y: 0.25)`, and `.scrollIndicators(.never)`/`.visible`
/// (`DD-G` item 1, `DD-H`). The control spells `UnitPoint` without its argument
/// labels, which SwiftUI's does not take either; the two arms are `#require`d
/// to disagree first.
///
/// Mutation that must redden it: `scrollTo` made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anExternalModuleCanWriteScrollViewReaderAndScrollTo() throws {
    let positive = try typecheckFile("""
        @MainActor public func reader() {
            _ = Column {
                ScrollViewReader { proxy in
                    ScrollView {
                        Column { ForEach(0..<20) { i in Text("\\(i)") } }
                    }
                    .scrollIndicators(.never)
                    Box().onClick {
                        proxy.scrollTo(3, anchor: .top)
                        proxy.scrollTo("x")
                        proxy.scrollTo(7, anchor: UnitPoint(x: 0, y: 0.25))
                    }
                }
            }
            _ = ProposalScrollView { Rectangle() }.scrollIndicators(.visible)
        }
        """, importing: "MetalUI")
    print("SCROLL GUARD G3.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let control = try typecheckFile("""
        @MainActor public func bad() {
            _ = UnitPoint(0, 0.25)
        }
        """, importing: "MetalUI")
    print("SCROLL GUARD G3.1 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(positive.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(control.output)")
    #expect(positive.succeeded, "the reader, scrollTo and the new cases must compile outside the module:\n\(positive.output)")
    #expect(!control.succeeded, "UnitPoint takes labelled arguments:\n\(control.output)")
}

/// **G3.2 — a `ScrollViewProxy` cannot be constructed outside the framework.**
/// As SwiftUI's, it has no public initialiser (`DD-G` item 1): the only proxy
/// is the one a reader hands its content, which is what scopes a request to
/// that reader's subtree. The control is a proxy received from a reader.
///
/// Mutation that must redden it: a public no-argument initialiser added.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aScrollViewProxyCannotBeConstructedOutsideTheFramework() throws {
    let fabricated = try typecheckFile("""
        @MainActor public func bad() {
            let proxy = ScrollViewProxy()
            proxy.scrollTo(1)
        }
        """, importing: "MetalUI")
    print("SCROLL GUARD G3.2 fabricated: succeeded=\(fabricated.succeeded)\n\(fabricated.messages)")

    let control = try typecheckFile("""
        @MainActor public func good() {
            _ = Column { ScrollViewReader { proxy in Box().onClick { proxy.scrollTo(1) } } }
        }
        """, importing: "MetalUI")
    print("SCROLL GUARD G3.2 control: succeeded=\(control.succeeded)\n\(control.messages)")

    try #require(fabricated.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(fabricated.output)\n\(control.output)")
    #expect(!fabricated.succeeded, "a proxy must not be constructible outside the framework:\n\(fabricated.output)")
    #expect(fabricated.messages.contains("ScrollViewProxy"),
            "rejected FOR the initialiser:\n\(fabricated.output)")
}
