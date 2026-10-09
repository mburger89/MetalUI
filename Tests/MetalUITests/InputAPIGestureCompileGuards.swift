import Testing
import MetalUITestSupport

// Input APIs, lane 2, guards 2.1, 2.2 and 2.25 (rulings `CI-B`, `CI-C`,
// `CI-F`, `CI-G`, `CI-R`; spec `docs/superpowers/specs/2026-10-08-input-apis-design.md`
// §4.2). Whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`,
// ruling SA-P): what an external module may write with the new gesture surface.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `CI GESTURE GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **2.1 — an outside module can spell the input-API gestures**: a spatial
/// tap, a magnify, a rotate, a middle-button global drag reading its
/// modifiers, `MouseButton.other(_:)`, and the old `DragGesture(minimumDistance:)`.
/// The negative arm reads `MagnifyGesture.Value.velocity`, which `CI-A`
/// defers.
///
/// Mutation that must redden it: `MouseButton.other(_:)` made internal.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func anOutsideModuleCanSpellTheInputAPIGestures() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let tap: SpatialTapGesture = SpatialTapGesture(count: 2, coordinateSpace: .local)
                .onEnded { (v: SpatialTapGesture.Value) in let _: Point<Pixels> = v.location }
            let magnify: MagnifyGesture = MagnifyGesture(minimumScaleDelta: 0.02)
                .onChanged { (v: MagnifyGesture.Value) in
                    let _: Double = v.magnification
                    let _: UnitPoint = v.startAnchor
                    let _: Point<Pixels> = v.startLocation
                }
                .onEnded { _ in }
            let rotate: RotateGesture = RotateGesture(minimumAngleDelta: .degrees(2))
                .onChanged { _ in }
                .onEnded { (v: RotateGesture.Value) in
                    let _: Double = v.rotation.degrees
                    let _: UnitPoint = v.startAnchor
                }
            let drag: DragGesture = DragGesture(minimumDistance: 0, coordinateSpace: .global, button: .middle)
                .onChanged { (v: DragGesture.Value) in let _: Bool = v.modifiers.contains(.option) }
            let button: MouseButton = MouseButton.other(4)
            let _: Int = button.buttonNumber
            let _: [MouseButton] = [.primary, .secondary, .middle]
            let _: CoordinateSpace = .global
            _ = DragGesture(minimumDistance: Pixels(4))
            _ = DragGesture.Value(startLocation: Point(x: Pixels(0), y: Pixels(0)),
                                  location: Point(x: Pixels(1), y: Pixels(1)), modifiers: [.shift])
            _ = RotateGesture()
            _ = MagnifyGesture()
            _ = SpatialTapGesture()
            let _: Box<EmptyGroup> = Box().gesture(tap).gesture(magnify.simultaneously(with: rotate))
                .highPriorityGesture(drag)
            _ = Rectangle().gesture(magnify).simultaneousGesture(rotate)
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = MagnifyGesture().onChanged { _ = $0.velocity }
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.1 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "every input-API gesture spelling must compile outside the module:\n\(positive.output)")
    #expect(!negative.succeeded, "MagnifyGesture.Value.velocity is deferred (CI-A):\n\(negative.output)")
}

/// **2.2 — `onTapGesture` resolves by closure arity** on both vocabularies
/// (`CI-B` item 2, probe `T0`/`T3`): `{ }` is the location-less overload,
/// `{ p in }` the located one, and `count:coordinateSpace:` spells it with
/// either name. The negative arm passes a two-parameter closure.
///
/// Mutation that must redden it: the location overload removed.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func onTapGestureResolvesByClosureArity() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let _: Box<EmptyGroup> = Box()
                .onTapGesture { }
                .onTapGesture { p in _ = p.x }
                .onTapGesture(count: 2, coordinateSpace: .global) { _ in }
                .onTapGesture(count: 2) { }
            let _: GestureModifier<GestureModifier<GestureModifier<ProposalText>>> = ProposalText("t")
                .onTapGesture { }
                .onTapGesture { p in _ = p.x }
                .onTapGesture(count: 2, coordinateSpace: .global) { _ in }
            let _: GestureModifier<Rectangle> = Rectangle().onTapGesture(coordinateSpace: .local) { (p: Point<Pixels>) in
                _ = p.y
            }
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.2 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = Box().onTapGesture { a, b in }
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.2 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "both onTapGesture overloads must resolve by arity:\n\(positive.output)")
    #expect(!negative.succeeded, "a two-parameter closure matches no overload:\n\(negative.output)")
}

/// **2.25 — `contextMenu` resolves by closure arity** (`CI-R` item 2): `{ … }`
/// is SwiftUI's overload, `{ p in … }` the located one handing a
/// `Point<Pixels>?`, on a `Box` and a `ProposalText`. The negative arm passes
/// a two-parameter closure.
///
/// Mutation that must redden it: the located overload removed.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func contextMenuResolvesByClosureArity() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let _: Box<EmptyGroup> = Box()
                .contextMenu { Button("a") {} }
                .contextMenu { p in Button("a") { _ = p?.x } }
            let _: ContextualModifier<ContextualModifier<ProposalText>> = ProposalText("t")
                .contextMenu { Button("a") {} }
                .contextMenu { (p: Point<Pixels>?) in Button("a") { _ = p?.y } }
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.25 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")

    let negative = try typecheckFile("""
        @MainActor public func bad() {
            _ = Box().contextMenu { a, b in Button("a") {} }
        }
        """, importing: "MetalUI")
    print("CI GESTURE GUARD 2.25 negative: succeeded=\(negative.succeeded)\n\(negative.messages)")

    try #require(positive.succeeded != negative.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(positive.output)\n\(negative.output)")
    #expect(positive.succeeded, "both contextMenu overloads must resolve by arity:\n\(positive.output)")
    #expect(!negative.succeeded, "a two-parameter closure matches no overload:\n\(negative.output)")
}
