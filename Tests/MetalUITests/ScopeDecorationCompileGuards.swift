import Testing
import MetalUITestSupport

// Scope decorations (rulings `ES-A`…): a `Self`-returning decoration written after a transparent
// scope compiles, as in SwiftUI. Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN
// import — a `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards");
// grep the log for `ES-A app spellings` and `ES-A geometry` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **ES-A.1** What an app writes after each converted scope: `lineLimit`, `disabled`, the other
/// `EnvironmentScope` modifiers, and the lifecycle, presentation and toolbar scopes, each followed
/// by `.padding`, `.background`, `.accessibilityIdentifier` and `.onClick`.
///
/// Mutation **MES-1**: delete `extension EnvironmentScope: StyledElement` (the file is refused
/// for `padding`/`background`/`accessibilityIdentifier`/`onClick`); likewise for each scope's
/// own conformance, which is refused at that scope's lines only.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func decorationsChainAfterTransparentScopes() throws {
    let result = try typecheckFile("""
        @MainActor func tree(_ shown: Binding<Bool>) -> some Element {
            Column {
                Text("x").lineLimit(1).padding(.horizontal, 6).background(Color(.surface)).accessibilityIdentifier("chip")
                Button("b") {}.disabled(true).accessibilityIdentifier("b")
                Text("x").lineLimit(1).onClick {}
                Text("x").lineLimit(1...2).padding(4)
                Text("x").disabled(false).controlSize(.small).padding(4).accessibilityIdentifier("c")
                Text("x").dynamicTypeSize(.large).background(Color(.surface))
                Text("x").environment(\\.isEnabled, true).padding(2)
                Text("x").onAppear {}.padding(4).background(Color(.surface)).accessibilityIdentifier("l")
                Text("x").onDisappear {}.onClick {}
                Text("x").alert("A", isPresented: shown) {}.padding(4).accessibilityIdentifier("p")
                Text("x").toolbar { ToolbarItem { Button("t") {} } }.padding(4).accessibilityIdentifier("t")
                Text("x").navigationTitle("T").padding(4)
            }
        }
        """, importing: "MetalUI")
    print("ES-A app spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}

/// **ES-A.2** `.onGeometryChange` is the one scope that does NOT chain: it measures its content,
/// and a decoration forwarded inside it would change what it measures (a `.padding(4)` after
/// SwiftUI's `.onGeometryChange` is outside the measured size). Before it compiles (the control).
///
/// Mutation **MES-2**: add `extension GeometryChangeScope: StyledElement` (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aDecorationAfterOnGeometryChangeStillDoesNotCompile() throws {
    let control = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Box {}.padding(4).onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in } }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column { Box {}.onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }.padding(4) }
        }
        """, importing: "MetalUI")
    print("ES-A geometry: control succeeded=\(control.succeeded); negative succeeded=\(negative.succeeded) messages=[\(negative.messages)]")
    try #require(control.succeeded && !negative.succeeded, "\(control.output)\n\(negative.output)")
    #expect(negative.messages.contains("padding"), "\(negative.output)")
}
