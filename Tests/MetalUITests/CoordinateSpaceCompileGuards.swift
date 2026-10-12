import Testing
import MetalUITestSupport

// Overlays and coordinates (C15), lane A guards GA1–GA3 (rulings `OV-D`,
// `OV-F`, `OV-G`, `OV-H`, `OV-L`; spec
// `docs/superpowers/specs/2026-10-10-overlays-coords-design.md` §4.1).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import —
// a `@testable` test cannot prove what an external module can spell.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `OV windowSize read-only`,
// `OV coordinateSpace named only` and `OV named spellings` to know each ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **Guard GA1** (`OV-G`). `EnvironmentValues.windowSize` reads from an
/// external module and does not write: the window stamps it.
///
/// Mutation **MG-A1**: make the setter `public` (the write compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func windowSizeIsReadOnlyOutsideMetalUI() throws {
    let read = try typecheckFile("""
        @MainActor func read(_ values: EnvironmentValues) -> Size<Pixels> { values.windowSize }
        struct Reader: Component {
            @Environment(\\.windowSize) var size
            var content: some ElementGroup { Text("\\(size.width.value)") }
        }
        """, importing: "MetalUI")
    let write = try typecheckFile("""
        @MainActor func write(_ values: inout EnvironmentValues) {
            values.windowSize = Size(width: Pixels(1), height: Pixels(1))
        }
        """, importing: "MetalUI")
    print("""
        OV windowSize read-only: read succeeded=\(read.succeeded); write succeeded=\(write.succeeded) \
        messages=[\(write.messages)]
        """)
    try #require(read.succeeded && !write.succeeded,
                 "the read must compile and the write must not:\nread:\n\(read.output)\nwrite:\n\(write.output)")
}

/// **Guard GA2** (`OV-D`). `coordinateSpace(_:)` takes only a named space:
/// `.coordinateSpace(.named("x"))` compiles on both vocabularies and
/// `.coordinateSpace(.global)` does not.
///
/// Mutation **MG-A2**: type the parameter `CoordinateSpace` (the negative
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func coordinateSpaceTakesOnlyANamedSpace() throws {
    let named = try typecheckFile("""
        @MainActor func legacy() -> some Element { Column { Box {}.coordinateSpace(.named("x")) } }
        @MainActor func proposal() -> some Element {
            HStack { Rectangle().coordinateSpace(.named("x")) }
        }
        """, importing: "MetalUI")
    let global = try typecheckFile("""
        @MainActor func tree() -> some Element { Column { Box {}.coordinateSpace(.global) } }
        """, importing: "MetalUI")
    print("""
        OV coordinateSpace named only: named succeeded=\(named.succeeded); global \
        succeeded=\(global.succeeded) messages=[\(global.messages)]
        """)
    try #require(named.succeeded && !global.succeeded,
                 "the named space must compile and .global must not:\nnamed:\n\(named.output)\nglobal:\n\(global.output)")
}

/// **Guard GA3** (`OV-D`, `OV-F`, `OV-H`, `OV-L`). Every named-space spelling
/// compiles from an external module under Swift 6: `.coordinateSpace(.named("x"))`,
/// `frame(in: .named("x"))`, `onContinuousHover(coordinateSpace:)` on both
/// vocabularies, `DragGesture(coordinateSpace: .named("x"))`,
/// `SpatialTapGesture(coordinateSpace: .named(Canvas.main))`, an exhaustive
/// three-case `switch`, `\.windowSize`, and `.named(NonSendableName())` (a
/// non-`Sendable` class name, SwiftUI's `some Hashable` — `OV-L`). The
/// separating arm: the same switch over two cases does not compile (the case
/// exists).
///
/// Mutations **MG-A3a**: drop `coordinateSpace:` from the proposal
/// `onContinuousHover`; **MG-A3b** (`OV-L`): constrain the factory
/// `some Hashable & Sendable`. Each fails the positive.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theNamedSpaceSpellingsCompile() throws {
    let positive = try typecheckFile("""
        enum Canvas: Hashable { case main }
        final class NonSendableName: Hashable {
            var tag = 0
            static func == (a: NonSendableName, b: NonSendableName) -> Bool { a === b }
            func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
        }
        @MainActor func legacy() -> some Element {
            Column {
                Box {}
                    .onContinuousHover(coordinateSpace: .named("x")) { _ in }
                    .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("x")) }) { _ in }
                    .coordinateSpace(.named("x"))
                Box {}.coordinateSpace(.named(NonSendableName()))
            }
        }
        @MainActor func proposal() -> some Element {
            HStack {
                Rectangle()
                    .onContinuousHover(coordinateSpace: .named(Canvas.main)) { _ in }
                    .gesture(DragGesture(coordinateSpace: .named("x")).onChanged { _ in })
                    .gesture(SpatialTapGesture(coordinateSpace: .named(Canvas.main)).onEnded { _ in })
                    .coordinateSpace(.named(Canvas.main))
            }
        }
        func describe(_ space: CoordinateSpace) -> String {
            switch space {
            case .local: "local"
            case .global: "global"
            case .named(let name): "\\(name)"
            }
        }
        let path: KeyPath<EnvironmentValues, Size<Pixels>> = \\.windowSize
        """, importing: "MetalUI")
    let twoCases = try typecheckFile("""
        func describe(_ space: CoordinateSpace) -> String {
            switch space {
            case .local: "local"
            case .global: "global"
            }
        }
        """, importing: "MetalUI")
    print("""
        OV named spellings: positive succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        two-case switch succeeded=\(twoCases.succeeded)
        """)
    try #require(positive.succeeded && !twoCases.succeeded,
                 """
                 every spelling must compile and the two-case switch must not, or this guard cannot fail:
                 positive:
                 \(positive.output)
                 two cases:
                 \(twoCases.output)
                 """)
}
