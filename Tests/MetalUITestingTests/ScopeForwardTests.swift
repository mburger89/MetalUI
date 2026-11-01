import MetalUI
import MetalUITesting
import Testing

// `ES-K`: the `style` and `elementID` forwards of the transparent scopes (`ES-A`, `ES-D`, `ES-E`, `ES-H`,
// `ES-J`) have a public-API consequence after all. `StyledElement.style` and `.elementID` are public
// requirements and `ElementID(_:)` is public; a scope used as a window's root is an element, and what it was
// given through the protocol reaches the laid-out content: `style` through the content's lowering to the
// kernel (`package` fields, writable from this package's tests), `elementID` through the identity path that
// `TestWindow.frame(ofID:)` reads. The earlier reading ("every Style-writing modifier is refused by name",
// "no StyledElement method writes elementID") looked only at modifiers, not at the protocol's own setters.
//
// Mutations: each scope's `style` setter drops the write (every `…StyleThroughTheScope…` arm for that scope
// reddens); each scope's `elementID` setter drops the write (every `…IdentifierThroughTheScope…` arm).

private let sixty = Pixels(60)
private let thirty = Pixels(30)

private func sized(_ style: Style) -> Style {
    var style = style
    style.size = Size(width: .length(.pixels(sixty)), height: .length(.pixels(thirty)))
    return style
}

/// The frame of the content (named "k" before the scope) when `style` is written through `scope`.
@MainActor private func frameAfterStyleWrite<S: StyledElement>(_ scope: S) throws -> Bounds<Pixels> {
    var scope = scope
    scope.style = sized(scope.style)
    let window = try harnessWindow { VStack { scope } }
    return try window.frame(ofID: "k")
}

/// The frame of the sized content when `elementID` is written through `scope`.
@MainActor private func frameAfterIDWrite<S: StyledElement>(_ scope: S) throws -> Bounds<Pixels> {
    var scope = scope
    scope.elementID = ElementID("k")
    let window = try harnessWindow { VStack { scope } }
    return try window.frame(ofID: "k")
}

@MainActor private func leaf() -> Box<EmptyGroup> { Box() }
@MainActor private func sizedLeaf() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: sixty, height: thirty)
}

/// Records an issue naming `what` (not aborting the test) unless `body` yields a 60 x 30 frame, so one mutation of
/// several scopes' setters shows which scopes it reddened.
private func check(_ what: String, _ body: () throws -> Bounds<Pixels>) {
    do {
        let b = try body()
        #expect(b.size.width.value == 60 && b.size.height.value == 30, "\(what): \(b)")
    } catch {
        Issue.record("\(what): \(error)")
    }
}

/// ES-K. A `style` written through a forwarding scope reaches its content: the content, 0 x 0 without a style
/// (the control, the unwritten twin), is 60 x 30 once the scope's `style` setter wrote it. The forwarding
/// scopes only; the layered ones are the next test. Mutation: the scope's `style` setter drops the write.
@Test @MainActor func aStyleWrittenThroughAForwardingScopeReachesTheContent() throws {
    let plain = try harnessWindow { VStack { leaf().id("k") } }
    let control = try plain.frame(ofID: "k")
    try #require(control.size.width.value == 0 && control.size.height.value == 0, "control: \(control)")

    check("EnvironmentScope") { try frameAfterStyleWrite(leaf().id("k").disabled(false)) }
    check("LifecycleScope") { try frameAfterStyleWrite(leaf().id("k").onAppear {}) }
    check("PresentationScope") { try frameAfterStyleWrite(leaf().id("k").alert("A", isPresented: .constant(false)) {}) }
    check("ToolbarScope") { try frameAfterStyleWrite(leaf().id("k").toolbar { ToolbarItem { Button("t") {} } }) }
    check("ModifierKeysScope") { try frameAfterStyleWrite(leaf().id("k").onModifierKeysChanged(mask: .shift) { _, _ in }) }
    check("GlassTagScope") { try frameAfterStyleWrite(leaf().id("k").glassEffectID("a", in: Namespace().wrappedValue)) }
    check("TransitionGroup") { try frameAfterStyleWrite(leaf().id("k").transition(.opacity)) }
}

/// ES-K. An `elementID` written through a forwarding scope names its content: `frame(ofID:)` finds the sized
/// content under the id, where the unwritten twin has none. Mutation: the scope's `elementID` setter drops the
/// write (`noElement`).
@Test @MainActor func anIdentifierWrittenThroughAForwardingScopeNamesTheContent() throws {
    let unnamed = try harnessWindow { VStack { sizedLeaf().disabled(false) } }
    #expect(throws: TestHarnessError.self, "control: nothing is named before the write") { try unnamed.frame(ofID: "k") }

    check("EnvironmentScope") { try frameAfterIDWrite(sizedLeaf().disabled(false)) }
    check("LifecycleScope") { try frameAfterIDWrite(sizedLeaf().onAppear {}) }
    check("PresentationScope") { try frameAfterIDWrite(sizedLeaf().alert("A", isPresented: .constant(false)) {}) }
    check("ToolbarScope") { try frameAfterIDWrite(sizedLeaf().toolbar { ToolbarItem { Button("t") {} } }) }
    check("ModifierKeysScope") { try frameAfterIDWrite(sizedLeaf().onModifierKeysChanged(mask: .shift) { _, _ in }) }
    check("GlassTagScope") { try frameAfterIDWrite(sizedLeaf().glassEffectID("a", in: Namespace().wrappedValue)) }
    check("TransitionGroup") { try frameAfterIDWrite(sizedLeaf().transition(.opacity)) }
}

/// ES-K. The three scopes that layer (`ES-H`, `ES-J`) keep both on the layer around themselves: the id names the
/// layer, which is as large as its content; a `style` written to the layer sizes it (the content inside stays
/// the layer's child). Mutation: the scope's `elementID` / `style` setter drops the write.
@Test @MainActor func aStyleAndAnIdentifierWrittenThroughALayeredScopeReachTheLayer() throws {
    check("CoordinateSpaceScope id") { try frameAfterIDWrite(sizedLeaf().coordinateSpace(.named("s"))) }
    check("TransactionScope id") { try frameAfterIDWrite(sizedLeaf().animation(.default, value: 1)) }
    check("GeometryChangeScope id") { try frameAfterIDWrite(sizedLeaf().onGeometryChange(for: Int.self, of: { _ in 0 }) { _ in }) }

    func layered<S: StyledElement>(_ scope: S, _ what: String) throws {
        var scope = scope
        scope.elementID = ElementID("k")
        scope.style = sized(scope.style)
        let window = try harnessWindow { VStack { scope } }
        check(what) { try window.frame(ofID: "k") }
    }
    try layered(leaf().coordinateSpace(.named("s")), "CoordinateSpaceScope style")
    try layered(leaf().animation(.default, value: 1), "TransactionScope style")
    try layered(leaf().onGeometryChange(for: Int.self, of: { _ in 0 }) { _ in }, "GeometryChangeScope style")
}

/// ES-K (a defect the owner-by-id pin found). A scope entered as an *element* - erased in an `AnyElement`, which a
/// container enters as a group member named by `elementID` - answered `Element`'s default `nil`, because its
/// `StyledElement` conformance's `elementID` is constrained to `Content: StyledElement` and cannot satisfy the
/// `Element` requirement of the wider conformance. A named element lost its name (identity by position, and no
/// `frame(ofID:)`) the moment a scope was written after it and it was erased. Each forwarding scope now answers
/// its content's name. Mutation: delete the `elementID` getter from a scope's `Element` extension (that scope's
/// arm finds no element "r").
@Test @MainActor func aNamedElementKeepsItsNameThroughAScopeWhenErased() throws {
    func found<E: Element>(_ element: E, _ what: String) throws {
        let window = try harnessWindow { VStack { AnyElement(element) } }
        check(what) { try window.frame(ofID: "r") }
    }
    try found(sizedLeaf().id("r"), "control: no scope")
    try found(sizedLeaf().id("r").disabled(false), "EnvironmentScope")
    try found(sizedLeaf().id("r").onAppear {}, "LifecycleScope")
    try found(sizedLeaf().id("r").alert("A", isPresented: .constant(false)) {}, "PresentationScope")
    try found(sizedLeaf().id("r").toolbar { ToolbarItem { Button("t") {} } }, "ToolbarScope")
    try found(sizedLeaf().id("r").onModifierKeysChanged(mask: .shift) { _, _ in }, "ModifierKeysScope")
    try found(sizedLeaf().id("r").glassEffectID("a", in: Namespace().wrappedValue), "GlassTagScope")
    try found(sizedLeaf().id("r").transition(.opacity), "TransitionGroup")
}
