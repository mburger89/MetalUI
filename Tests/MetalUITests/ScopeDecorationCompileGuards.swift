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

/// **ES-J** (lifting `ES-B`, formerly ES-A.2's negative) What an app writes after `.onGeometryChange`: `.padding`,
/// `.offset`, `.background`, `.accessibilityIdentifier` and `.onClick`, one as a window root, and `.id` still typed
/// `IdentifiedGroup` (`ES-C`; unannotated first, MES-4). The decoration configures the scope's own layer, outside
/// the measurement (record 172's pins).
///
/// Mutation **MES-10**: make `extension GeometryChangeScope: StyledElement` a plain extension (refused);
/// **MES-11**: delete `GeometryChangeScope.id(_:) -> IdentifiedGroup<Self>` (the `IdentifiedGroup` assignment is
/// refused).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func decorationsChainAfterOnGeometryChange() throws {
    let result = try typecheckFile("""
        @MainActor func tree() -> some Element {
            Column {
                Box {}.onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }.padding(4)
                Text("x").onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }
                    .offset(x: 10).background(Color(.surface)).accessibilityIdentifier("g").onClick {}
            }
        }
        @MainActor func root() -> some Element {
            Text("r").onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }.accessibilityIdentifier("r")
        }
        @MainActor func ids() {
            let g = Text("x").onGeometryChange(for: Float.self, of: { $0.size.width.value }) { _ in }.id("k")
            let _: IdentifiedGroup<GeometryChangeScope<Text>> = g
        }
        """, importing: "MetalUI")
    print("ES-J app spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
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

/// **ES-H** (lifting `ES-F`, `ES-G`) What an app writes after `.coordinateSpace`, `.animation(_:value:)` and
/// `.transaction`: `.offset`, `.padding`, `.background`, `.accessibilityIdentifier` and `.onClick`, one of each as a
/// window root, and `.id` after each still typed `IdentifiedGroup` (`ES-C`, unannotated first - MES-4). The decoration
/// configures the scope's own layer, outside the space or the transaction (record 169's pins).
///
/// Mutation **MES-5**: delete `extension CoordinateSpaceScope: StyledElement` (refused for `offset`/`background`/
/// `accessibilityIdentifier`/`onClick` at its lines); **MES-6**: the same for `TransactionScope`; **MES-8**: delete
/// `CoordinateSpaceScope.id(_:) -> IdentifiedGroup<Self>` (the `IdentifiedGroup` assignment is refused).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func decorationsChainAfterACoordinateSpaceAndATransaction() throws {
    let result = try typecheckFile("""
        @MainActor func tree(_ v: Int) -> some Element {
            Column {
                Text("x").coordinateSpace(.named("s")).offset(x: 7, y: 9).background(Color(.surface)).accessibilityIdentifier("s")
                Box {}.coordinateSpace(.named("s")).padding(4).onClick {}
                Text("x").animation(.default, value: v).background(Color(.surface)).accessibilityIdentifier("a")
                Box {}.animation(.default, value: v).onClick {}.padding(2)
                Text("x").transaction { $0.animation = nil }.background(Color(.surface)).onClick {}
            }
        }
        @MainActor func roots(_ v: Int) -> (some Element, some Element, some Element) {
            (Text("r").coordinateSpace(.named("s")).offset(x: 7).accessibilityIdentifier("r"),
             Text("r").animation(.default, value: v).background(Color(.surface)),
             Text("r").transaction { $0.animation = nil }.onClick {})
        }
        @MainActor func ids(_ v: Int) {
            // Unannotated first: an annotation would pick the `ElementGroup` overload with or without the member.
            let s = Text("x").coordinateSpace(.named("s")).id("k")
            let a = Text("x").animation(.default, value: v).id("k")
            let _: IdentifiedGroup<CoordinateSpaceScope<Text>> = s
            let _: IdentifiedGroup<TransactionScope<Text>> = a
        }
        """, importing: "MetalUI")
    print("ES-H app spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}
