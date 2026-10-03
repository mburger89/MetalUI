import Testing
import MetalUITestSupport

// Menus, popovers and tooltips, lane 3, guards G3.1–G3.2 (rulings `MN-L`,
// `MN-P`, `MN-X`, `MN-T`; spec §6.3). Every fixture is whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import — a `@testable` test
// cannot prove what an external module can write (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MN-X popover` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1** (`MN-L`, `MN-P`, `MN-X` item 1). Lane 3's spellings compile under
/// `import MetalUI`: both `.popover` spellings on a `Box` and on an `HStack`,
/// with no edge, `arrowEdge: nil` and an edge, the `PopoverModifier` type, and
/// `.help(_:)` on both vocabularies (the proposal one a `ContextualModifier`).
/// `.help(Text(…))` does **not** (deferred, spec §10).
///
/// Mutation **MG3.1**: a `help(_ text: Text)` overload (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func thePopoverAndHelpSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        struct Note: Identifiable { let id: Int }

        @MainActor func styled(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) { Text("Popover") }
        }

        @MainActor func explicitNil(shown: Binding<Bool>) -> some ElementGroup {
            Button("B") {}.popover(isPresented: shown, arrowEdge: nil) { Text("Nil") }
        }

        @MainActor func item(note: Binding<Note?>) -> some ElementGroup {
            Box().frame(width: Pixels(10), height: Pixels(10)).popover(item: note, arrowEdge: .bottom) { note in Text("Note \\(note.id)") }
        }

        @MainActor func help() -> some ElementGroup {
            Box().help("Explains")
        }

        @MainActor func proposal(shown: Binding<Bool>) -> some ProposalElementGroup {
            HStack { Rectangle() }.popover(isPresented: shown, arrowEdge: .leading) { Text("P") }
        }

        @MainActor func types(shown: Binding<Bool>) -> (PopoverModifier<Rectangle, Text>, ContextualModifier<Rectangle>) {
            (Rectangle().popover(isPresented: shown) { Text("T") }, Rectangle().help("H"))
        }
        """, importing: "MetalUI")
    let helpText = try typecheckFile("""
        @MainActor func view() -> some ElementGroup {
            Box().help(Text("Explains"))
        }
        """, importing: "MetalUI")
    print("""
        MN-X popover spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        helpText succeeded=\(helpText.succeeded) messages=[\(helpText.messages)]
        """)
    try #require(spellings.succeeded && !helpText.succeeded,
                 """
                 the spellings must compile and .help(Text) must not, or this guard \
                 cannot fail:
                 spellings:
                 \(spellings.output)
                 helpText:
                 \(helpText.output)
                 """)
    #expect(helpText.messages.contains("Text") || helpText.messages.contains("String"),
            "refused for the Text argument:\n\(helpText.output)")
}

/// **G3.2** (`MN-L` item 3). `.popover` takes no `attachmentAnchor:` — the
/// anchor is always the wrapped element's bounds. **Positive control**: the
/// same call without it compiles.
///
/// Mutation **MG3.2**: an overload taking `attachmentAnchor: Int = 0` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aPopoverHasNoAttachmentAnchorParameter() throws {
    let with = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown, attachmentAnchor: 0) { Text("A") }
        }
        """, importing: "MetalUI")
    let without = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) { Text("A") }
        }
        """, importing: "MetalUI")
    print("""
        MN-X popover attachmentAnchor: with succeeded=\(with.succeeded) messages=[\(with.messages)]; \
        without succeeded=\(without.succeeded) messages=[\(without.messages)]
        """)
    try #require(without.succeeded && !with.succeeded,
                 "the control must compile and attachmentAnchor must not:\n\(without.output)\n\(with.output)")
    #expect(with.messages.contains("attachmentAnchor"), "refused FOR attachmentAnchor:\n\(with.output)")
}

/// **G3.3** (divergence 115, `MN-AH` item 5). On the legacy vocabulary a
/// `StyledElement` modifier cannot follow `.popover` — neither `.padding` nor
/// a second `.popover` — because `PopoverModifier` is not a `StyledElement`
/// (`MN-AG` item 4). **Positive control**: the `ElementGroup`-level modifiers
/// (`.frame`, `.id`, `.overlay`) do follow it, and the same `.padding` written
/// before `.popover` compiles.
///
/// Mutation **MG3.3**: a `public func padding(_: Pixels) -> Self` on
/// `PopoverModifier` in `Popover.swift` (the `.padding` negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aStyledModifierCannotFollowALegacyPopover() throws {
    let control = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().padding(Pixels(4)).popover(isPresented: shown) { Text("A") }
                .frame(width: Pixels(40), height: Pixels(20))
                .overlay { Text("O") }
                .id("p")
        }
        """, importing: "MetalUI")
    let padding = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) { Text("A") }.padding(Pixels(4))
        }
        """, importing: "MetalUI")
    let second = try typecheckFile("""
        @MainActor func view(shown: Binding<Bool>, other: Binding<Bool>) -> some ElementGroup {
            Box().popover(isPresented: shown) { Text("A") }.popover(isPresented: other) { Text("B") }
        }
        """, importing: "MetalUI")
    print("""
        MN-AH popover chaining: control succeeded=\(control.succeeded) messages=[\(control.messages)]; \
        padding succeeded=\(padding.succeeded) messages=[\(padding.messages)]; \
        second succeeded=\(second.succeeded) messages=[\(second.messages)]
        """)
    try #require(control.succeeded && !padding.succeeded && !second.succeeded,
                 """
                 the control must compile and both chains must not, or this guard cannot fail:
                 control:
                 \(control.output)
                 padding:
                 \(padding.output)
                 second:
                 \(second.output)
                 """)
    #expect(padding.messages.contains("padding"), "refused FOR padding:\n\(padding.output)")
    #expect(second.messages.contains("popover"), "refused FOR popover:\n\(second.output)")
}
