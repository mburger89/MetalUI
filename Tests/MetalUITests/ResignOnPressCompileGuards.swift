import Testing
import MetalUITestSupport

// Compile-time guards for `resignsFocusOnPress` (C24; ruling `RF-B`, spec
// section 4). Whole-file, Swift 6, a plain `import MetalUI` (`typecheckFile`,
// `SA-P`). **A guard skips silently when `.build/<triple>/debug/Modules` is
// absent** (CLAUDE.md, "Guards").

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **R1** (`RF-B`). `resignsFocusOnPress` compiles on a `StyledElement` (a
/// `Box`, returning `Self`) and on proposal content (a `Rectangle`, returning
/// the keyboard layer), with and without the argument; a misspelt label does
/// not. Mutation: delete the `StyledElement` overload (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func resignsFocusOnPressCompilesOnAnElementAndOnProposalContent() throws {
    let control = try typecheckFile("""
        @MainActor func spellings(_ on: Bool) {
            let a: Box<EmptyGroup> = Box().resignsFocusOnPress()
            let b: Box<EmptyGroup> = Box().resignsFocusOnPress(on)
            let c = Rectangle(width: Pixels(10), height: Pixels(10)).resignsFocusOnPress()
            let d = Rectangle(width: Pixels(10), height: Pixels(10)).resignsFocusOnPress(false)
            _ = (a, b, c, d)
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func spellings() {
            _ = Box().resignsFocusOnPress(enabled: true)
        }
        """, importing: "MetalUI")
    print("R1 spellings: control succeeded=\(control.succeeded) messages=[\(control.messages)]; "
          + "negative succeeded=\(negative.succeeded) messages=[\(negative.messages)]")
    try #require(control.succeeded && !negative.succeeded,
                 "the control must compile and the negative must not:\n\(control.output)\n\(negative.output)")
}

/// **R2** (`RF-B`, `KF-H`). A chain on proposal content ending in
/// `resignsFocusOnPress` is one `KeyboardModifier<Rectangle>` (it merges into
/// the one layer), not the nested type. Mutation: make the `KeyboardModifier`
/// overload return `KeyboardModifier<Self>` (the control fails).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func resignsFocusOnPressOnProposalContentReturnsTheKeyboardLayer() throws {
    func chain(_ type: String) -> String {
        """
        @MainActor func viewport() {
            let inferred = Rectangle(width: Pixels(10), height: Pixels(10))
                .resignsFocusOnPress()
                .onKeyPress { _ in .ignored }
                .resignsFocusOnPress(false)
                .hoverKeyRegion()
            let x: \(type) = inferred
            _ = x
        }
        """
    }
    let control = try typecheckFile(chain("KeyboardModifier<Rectangle>"), importing: "MetalUI")
    let negative = try typecheckFile(chain("KeyboardModifier<KeyboardModifier<Rectangle>>"),
                                     importing: "MetalUI")
    print("R2 one layer: control succeeded=\(control.succeeded) messages=[\(control.messages)]; "
          + "negative succeeded=\(negative.succeeded) messages=[\(negative.messages)]")
    try #require(control.succeeded && !negative.succeeded,
                 "the one-layer type must compile and the nested one must not:\n\(control.output)\n\(negative.output)")
}
