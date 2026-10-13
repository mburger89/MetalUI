import Testing
import MetalUITestSupport

// C14 lane 1, guard 1.13 (`IV-E`): the layout memo is `package`. A fixture is a
// whole Swift 6 file with plain imports. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent**; grep the log for `IV-E`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUILayout not found — guard skipped"

private let layoutModuleBuilt = canTypecheck(module: "MetalUILayout")

/// **1.13** (`IV-E`). The separating control: a public member of `LayoutTree`
/// compiles from a plain import; `LayoutTree.memo`, `LayoutMemo` and the keyed
/// leaf registrar do not. Mutation: `LayoutTree.memo` made `public` → red.
@Test(.enabled(if: layoutModuleBuilt, skipReason))
func thePlainImportCannotReachTheMemo() throws {
    let control = try typecheckFile("""
        public func reach(_ tree: LayoutTree) -> UInt64 { tree.generation }
        """, importing: "MetalUILayout")
    try #require(control.succeeded, "the control (a public member) must compile:\n\(control.output)")

    for (name, source) in [
        ("memo", "public func reach(_ tree: LayoutTree) { _ = tree.memo }"),
        ("LayoutMemo", "public func reach() { _ = LayoutMemo() }"),
        ("keyed leaf", "public func reach(_ tree: LayoutTree) { _ = tree.newNativeLeaf(key: 1) { _ in LayoutMeasurement(size: .zero) } }"),
        ("signature", "public func reach(_ tree: LayoutTree, _ id: LayoutNodeID) { _ = tree.structuralSignature(of: id) }"),
    ] {
        let result = try typecheckFile(source, importing: "MetalUILayout")
        #expect(!result.succeeded, "\(name) must be unreachable from a plain import:\n\(result.output)")
    }
}
