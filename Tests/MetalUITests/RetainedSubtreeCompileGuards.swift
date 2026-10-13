import Testing
import MetalUITestSupport

// Plain-import guards for retained subtrees (`SB-L`, spec test 1.17; `SA-P`): each fixture is a whole
// Swift 6 file importing `MetalUI` and `MetalUITesting` and nothing else, what an app's test target
// writes. **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Build and test"). Each was mutated red once; the mutations are in record §109.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI and MetalUITesting not found — guard skipped"

private let modulesBuilt = canTypecheck(module: "MetalUI") && canTypecheck(module: "MetalUITesting")

/// **1.17a** — the record, its counters and the log are unreachable from a plain import, while the
/// counted work (`FrameWork`'s public fields) is readable: the control. Mutation: `RetainedCounters`
/// made `public` → red.
@Test(.enabled(if: modulesBuilt, skipReason))
func theRecordIsUnreachableFromAPlainImport() throws {
    let control = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func read(_ window: TestWindow) -> Int {
            let work = window.lastFrameWork
            return work.retainedHits + work.retainedMisses + work.retainedIneligible + work.elementPaints
        }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the control (public counters) must compile:\n\(control.output)")

    let counters = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func reach(_ window: TestWindow) -> Int {
            window.window.testingContentMemos.lastRetained.hits
        }
        """, importing: "MetalUI")
    #expect(!counters.succeeded, "the memo store's counters are package API:\n\(counters.output)")

    let record = try typecheckFile("""
        public func make() -> Int { RetainedCounters().hits }
        """, importing: "MetalUI")
    #expect(!record.succeeded, "RetainedCounters is package API:\n\(record.output)")
}

/// **1.17b** — a plain import cannot turn replay off: `Window.testingRetainedSubtrees` is `package`
/// (`SB-B`: no public switch, `.equatable()` is the opt-in). Mutation: the property made `public`
/// → red.
@Test(.enabled(if: modulesBuilt, skipReason))
func thePlainImportCannotTurnReplayOff() throws {
    let result = try typecheckFile("""
        import MetalUITesting

        @MainActor
        public func off(_ window: TestWindow) {
            window.window.testingRetainedSubtrees = false
        }
        """, importing: "MetalUI")
    #expect(!result.succeeded, "the replay switch is package API:\n\(result.output)")
    #expect(result.messages.contains("testingRetainedSubtrees"), "rejected, but not for the switch:\n\(result.output)")
}
