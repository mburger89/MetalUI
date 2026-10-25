import Testing
import MetalUITestSupport

// Plain-import guard `TR.1` for the retained trace (`DM-F`): the sink and the switches are `package` API, a tool's seam, not
// something an app's test target can name. Mutated red once (record 140): `RetainedTrace` and its `sink` made `public` (the type being `package` is what hides the sink).

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

private let modulesBuilt = canTypecheck(module: "MetalUI")

/// **TR.1** — a plain import cannot name `RetainedTrace.sink` (the control, a public `FrameWork` count, compiles).
@Test(.enabled(if: modulesBuilt, skipReason))
func theRetainedTraceSinkIsUnreachableFromAPlainImport() throws {
    let control = try typecheckFile("""
        public func read(_ lines: [String]) -> Int { lines.count }
        """, importing: "MetalUI")
    try #require(control.succeeded, "the control must compile:\n\(control.output)")
    let reach = try typecheckFile("""
        public func install() { RetainedTrace.sink = { _ in } }
        """, importing: "MetalUI")
    #expect(!reach.succeeded, "the trace sink is package API:\n\(reach.output)")
    #expect(reach.messages.contains("RetainedTrace"), "rejected, but not for the type:\n\(reach.output)")
}
