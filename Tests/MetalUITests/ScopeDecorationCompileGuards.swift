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

/// **ES-D / ES-E** What an app writes after the remaining scopes that forward: `.onModifierKeysChanged`,
/// `.glassEffectID`, `.glassEffectUnion` (`ES-D`) and `.transition` (`ES-E`), each followed by `.padding`,
/// `.background`, `.accessibilityIdentifier` and `.onClick`, one of each as a window root (`some Element`), and
/// `.id` after each still typed `IdentifiedGroup` (`ES-C` carried).
///
/// Mutation **MES-3**: delete `extension ModifierKeysScope: StyledElement` (refused at its lines only); likewise
/// `GlassTagScope`'s and `TransitionGroup`'s. Mutation **MES-4**: delete one scope's `id(_:) -> IdentifiedGroup<Self>`
/// (the `IdentifiedGroup` assignment of the unannotated `.id` result is refused: `.id` then returns the scope itself; with the
/// annotation on the call instead, the mutant stayed green - the annotation picks the `ElementGroup` overload).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func decorationsChainAfterTheRemainingForwardingScopes() throws {
    let result = try typecheckFile("""
        @MainActor func tree(_ ns: Namespace.ID) -> some Element {
            Column {
                Text("x").onModifierKeysChanged { _, _ in }.padding(4).background(Color(.surface)).accessibilityIdentifier("m")
                Text("x").onModifierKeysChanged(mask: .command) { _, _ in }.onClick {}
                Text("x").glassEffectID("a", in: ns).padding(4).accessibilityIdentifier("g")
                Text("x").glassEffectUnion(id: "u", namespace: ns).background(Color(.surface)).onClick {}
                Text("x").transition(.opacity).padding(4).background(Color(.surface)).accessibilityIdentifier("t")
                Text("x").transition(.opacity).onClick {}
            }
        }
        @MainActor func roots(_ ns: Namespace.ID) -> (some Element, some Element, some Element) {
            (Text("r").onModifierKeysChanged { _, _ in }.accessibilityIdentifier("r"),
             Text("r").glassEffectUnion(id: "u", namespace: ns),
             Text("r").transition(.opacity).accessibilityIdentifier("r"))
        }
        @MainActor func ids(_ ns: Namespace.ID) {
            // Unannotated first: an annotation would pick the `ElementGroup` overload with or without the member.
            let m = Text("x").onModifierKeysChanged { _, _ in }.id("k")
            let g = Text("x").glassEffectID("a", in: ns).id("k")
            let t = Text("x").transition(.opacity).id("k")
            let _: IdentifiedGroup<ModifierKeysScope<Text>> = m
            let _: IdentifiedGroup<GlassTagScope<Text>> = g
            let _: IdentifiedGroup<TransitionGroup<Text>> = t
        }
        """, importing: "MetalUI")
    print("ES-D/E app spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}

/// **ES-F / ES-G** `.coordinateSpace` and `.animation(_:value:)` / `.transaction` do NOT chain: a decoration
/// forwarded inside them was measured wrong (record 168: an `.offset` after the space moved a child in it by the
/// offset, where SwiftUI's G3 reads the child unmoved; a `.background` after `.animation(_:value:)` animated, where
/// SwiftUI's T3b snaps). The decoration before each compiles (the controls).
///
/// Mutation **MES-5**: add `extension CoordinateSpaceScope: StyledElement` (that negative compiles); **MES-6**: the
/// same for `TransactionScope` (both of its negatives compile).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile() throws {
    let control = try typecheckFile("""
        @MainActor func tree(_ v: Int) -> some Element {
            Column {
                Box {}.offset(x: 7).coordinateSpace(.named("s"))
                Box {}.background(Color(.surface)).animation(.default, value: v)
                Box {}.background(Color(.surface)).transaction { $0.animation = nil }
            }
        }
        """, importing: "MetalUI")
    func negative(_ line: String) throws -> TypecheckResult {
        try typecheckFile("""
            @MainActor func tree(_ v: Int) -> some Element {
                Column { \(line) }
            }
            """, importing: "MetalUI")
    }
    let space = try negative(#"Box {}.coordinateSpace(.named("s")).offset(x: 7)"#)
    let animation = try negative("Box {}.animation(.default, value: v).background(Color(.surface))")
    let transaction = try negative("Box {}.transaction { $0.animation = nil }.background(Color(.surface))")
    print("ES-F/G negatives: control succeeded=\(control.succeeded); space=\(space.succeeded) "
          + "animation=\(animation.succeeded) transaction=\(transaction.succeeded)")
    try #require(control.succeeded, "\(control.output)")
    #expect(!space.succeeded && space.messages.contains("offset"), "\(space.output)")
    #expect(!animation.succeeded && animation.messages.contains("background"), "\(animation.output)")
    #expect(!transaction.succeeded && transaction.messages.contains("background"), "\(transaction.output)")
}
