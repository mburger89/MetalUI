import Testing
import MetalUITestSupport

// Plain-import guard `RW.1` (`RW-C`, `RW-D`, `RW-N`; `SA-P`): what an app's test target writes. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Build and test"). Mutated red once (record 121).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI and MetalUITesting not found — guard skipped"

private let modulesBuilt = canTypecheck(module: "MetalUI") && canTypecheck(module: "MetalUITesting")

/// **RW.1** — the read-only state surface is unreachable from a plain import: `readState`, the compared `withState` and the
/// ineligible-reason funnel are `package`/internal, while the one public field, `FrameWork.retainedIneligibleReasons`, is
/// readable (the control, `RW-M`). **Mutation:** `PaintPass.readState` made `public` reddens the first arm; the plain
/// `withState(_:initial:_:)` stays public (the second control).
@Test(.enabled(if: modulesBuilt, skipReason))
func theReadOnlyStateSurfaceIsUnreachableFromAPlainImport() throws {
    let control = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func read(_ window: TestWindow, _ pass: inout PaintPass) -> Int {
            pass.withState(GlobalElementID.child(of: nil, at: 0, name: ElementID("x")), initial: 0) { $0 += 1 }
            return window.lastFrameWork.retainedIneligibleReasons.count
        }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the controls (the plain `withState`, the public reasons field) must compile:\n\(control.output)")

    let readState = try typecheckFile("""
        @MainActor
        public func read(_ pass: PaintPass, _ id: GlobalElementID) -> Int {
            pass.readState(id, initial: 0)
        }
        """, importing: "MetalUI")
    #expect(!readState.succeeded, "`readState` is package API:\n\(readState.output)")
    #expect(readState.messages.contains("readState"), "rejected, but not for the member:\n\(readState.output)")

    let compared = try typecheckFile("""
        @MainActor
        public func write(_ pass: PaintPass, _ id: GlobalElementID) {
            pass.withState(id, initial: 0, unchanged: { $0 == $1 }) { $0 = 1 }
        }
        """, importing: "MetalUI")
    #expect(!compared.succeeded, "the compared `withState` is package API:\n\(compared.output)")

    let table = try typecheckFile("""
        public func touch(_ table: StateTable, _ id: GlobalElementID) { table.touchLive(id); _ = table.readJournal }
        """, importing: "MetalUI")
    #expect(!table.succeeded, "`touchLive` and the read journal are internal:\n\(table.output)")

    let counters = try typecheckFile("""
        public func note(_ counters: inout RetainedCounters) { counters.noteIneligible(.paint, reason: "x") }
        """, importing: "MetalUI")
    #expect(!counters.succeeded, "the ineligible funnel is package API:\n\(counters.output)")
}
