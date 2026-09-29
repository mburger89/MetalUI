import Testing
import MetalUITestSupport

// Plan task 12, part 1, lane 2, guard G2.1 (rulings `IX-E`, `IX-F`). Whole-file
// Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling SA-P): what
// an external module may write with the button surface.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `BUTTON GUARD` to know it ran.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G2.1 — every lane-2 button spelling of spec §4 compiles from a plain
/// import**: both role initialisers and the four roles, the four styles, the
/// three `keyboardShortcut` overloads, a `KeyEquivalent` literal and every named
/// key, `KeyboardShortcut`'s two statics and `EventModifiers`. **Three negative
/// arms**, each its own fixture so a failure names which one leaked:
/// `.buttonStyle(.link)` (not offered, `IX-E` item 2), a `keyboardShortcut` on
/// a `Text` (offered on `Button` only, `IX-F` item 1) and
/// `EventModifiers.function` (narrower than SwiftUI's, `IX-F` item 1).
///
/// Mutation that must redden it (mutated red once, `IX-R`): one spelling made
/// `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theButtonSpellingsCompileFromAPlainImport() throws {
    let positive = try typecheckFile("""
        @MainActor public func spellings() {
            let roles: [ButtonRole?] = [.destructive, .cancel, .confirm, .close, nil]
            let styles: [ButtonStyle] = [.automatic, .bordered, .borderless, .plain]
            let keys: [KeyEquivalent] = [.return, .escape, .space, .tab, .delete, .deleteForward, .upArrow,
                                         .downArrow, .leftArrow, .rightArrow, .home, .end, .pageUp,
                                         .pageDown, .clear, "k", KeyEquivalent("j")]
            let _: Character = keys[0].character
            let shortcut: KeyboardShortcut = KeyboardShortcut("s", modifiers: [.command, .shift])
            let _: KeyEquivalent = shortcut.key
            let _: EventModifiers = shortcut.modifiers
            let _: KeyboardShortcut = .defaultAction
            let _: KeyboardShortcut = .cancelAction
            let _: KeyboardShortcut = KeyboardShortcut("k")
            let modifiers: EventModifiers = [.shift, .control, .option, .command]
            let none: KeyboardShortcut? = nil
            let _: Button<Text> = Button("Delete", role: roles[0]) { }
                .buttonStyle(styles[3])
                .keyboardShortcut("d", modifiers: modifiers)
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(none)
                .keyboardShortcut(.escape)
            let _: Button<Box<EmptyGroup>> = Button(role: .cancel, action: { }) { Box() }
        }
        """, importing: "MetalUI")
    print("BUTTON GUARD G2.1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let link = try typecheckFile("""
        @MainActor public func link() { _ = Button("Go") { }.buttonStyle(.link) }
        """, importing: "MetalUI")
    let onText = try typecheckFile("""
        @MainActor public func onText() { _ = Text("x").keyboardShortcut("k") }
        """, importing: "MetalUI")
    let function = try typecheckFile("""
        public func function() { _ = EventModifiers.function }
        """, importing: "MetalUI")
    print("BUTTON GUARD G2.1 negatives: link=\(link.succeeded) onText=\(onText.succeeded) "
          + "function=\(function.succeeded)")
    try #require(positive.succeeded != link.succeeded && positive.succeeded != onText.succeeded
                    && positive.succeeded != function.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(link.output)
                 \(onText.output)
                 \(function.output)
                 """)
    #expect(positive.succeeded, "every button spelling must compile from a plain import:\n\(positive.output)")
    #expect(!link.succeeded, ".buttonStyle(.link) is not offered:\n\(link.output)")
    #expect(!onText.succeeded, "keyboardShortcut is offered on Button only:\n\(onText.output)")
    #expect(!function.succeeded, "EventModifiers has no .function:\n\(function.output)")
}
