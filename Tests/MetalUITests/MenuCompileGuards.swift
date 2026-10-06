import Testing
import MetalUITestSupport

// Menus, popovers and tooltips, lane 1, guards G1.1–G1.4 (rulings `MN-C`,
// `MN-D`, `MN-H`, `MN-AD`; spec §6.1). Every fixture is whole-file Swift 6
// (`typecheckFile`, ruling SA-P) against a PLAIN import — a `@testable` test
// cannot prove what an external module can write (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MN-D`/`MN-C` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// **G1.1** (`MN-D` item 1). `MenuContent`'s one requirement is SPI, so an
/// outside type writing it does not conform; the control — a plain `Button`
/// inside `.contextMenu` — compiles.
///
/// Mutation **MG1.1**: the requirement made plain `public` (the negative
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func anOutsideTypeCannotConformToMenuContent() throws {
    let fabricated = try typecheckFile("""
        struct Mine: MenuContent {
            func _menuNodes(in context: _MenuContext) -> _MenuNodes { Divider()._menuNodes(in: context) }
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor public func good() -> some ElementGroup {
            Box().contextMenu { Button("Copy") {} }
        }
        """, importing: "MetalUI")
    print("""
        MN-D outside conformance: fabricated succeeded=\(fabricated.succeeded) messages=[\(fabricated.messages)]; \
        control succeeded=\(control.succeeded) messages=[\(control.messages)]
        """)
    try #require(fabricated.succeeded != control.succeeded,
                 "the two arms must disagree, or the guard measures nothing:\n\(fabricated.output)\n\(control.output)")
    #expect(!fabricated.succeeded, "an outside conformance to MenuContent must not compile:\n\(fabricated.output)")
    #expect(control.succeeded, "a Button item must compile outside the module:\n\(control.output)")
}

/// **G1.2** (`MN-D`, `MN-E`, `MN-H` item 3, `MN-AD`). Lane 1's spellings
/// compile under `import MetalUI`: `.contextMenu` on a `Box` and on an
/// `HStack`, `Menu("…") { … }` as a submenu item, `Divider()`, a `Toggle`, a
/// `.disabled(true)` and a `.keyboardShortcut` item, `if`/`else` and `for` in
/// the builder. A view that is not menu content — a `Rectangle` — in a menu
/// builder does **not**. (Until platform services the negative was `Divider()`
/// as a view in a stack, `MN-H` item 3; `SV-O` made `Divider` an element, which
/// reddened this guard — its flip, record §77 lane 3.)
///
/// Mutation **MG1.2**, re-spelled with the negative: `Rectangle` made
/// `MenuContent` (the negative compiles) — measured as MG3.12 (`SV-AK`).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theMenuSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        @MainActor func styled(flag: Binding<Bool>, names: [String], wide: Bool) -> some ElementGroup {
            Box().contextMenu {
                Button("Copy") {}
                Button(role: .destructive) { } label: { Text("Delete") }
                Divider()
                Menu("More") {
                    Button("A") {}
                    Menu("Deeper") { Button("B") {} }
                }
                Toggle("Pinned", isOn: flag)
                Button("Off") {}.disabled(true)
                Button("Short") {}.keyboardShortcut("k")
                Button("Shift") {}.keyboardShortcut("s", modifiers: [.command, .shift])
                Text("Plain")
                if wide { Button("Wide") {} } else { Button("Narrow") {} }
                if flag.wrappedValue { Divider() }
                for name in names { Button(name) {} }
            }
        }

        @MainActor func proposal() -> some ProposalElementGroup {
            HStack { Rectangle() }.contextMenu { Button("Copy") {} }
        }

        @MainActor func types() -> ContextualModifier<Rectangle> {
            Rectangle().contextMenu { Divider() }
        }
        """, importing: "MetalUI")
    let nonItem = try typecheckFile("""
        @MainActor func view() -> some ElementGroup {
            Box().contextMenu { Button("Copy") {}; Rectangle() }
        }
        """, importing: "MetalUI")
    print("""
        MN-D spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        nonItem succeeded=\(nonItem.succeeded) messages=[\(nonItem.messages)]
        """)
    try #require(spellings.succeeded && !nonItem.succeeded,
                 """
                 the spellings must compile and a Rectangle menu item must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 nonItem:
                 \(nonItem.output)
                 """)
    #expect(nonItem.messages.contains("Rectangle"), "refused FOR Rectangle:\n\(nonItem.output)")
}

/// **G1.3** (`MN-D` item 5). A `Picker` is not a menu item (SwiftUI renders it
/// as a submenu of state items, C1; MetalUI does not offer it). The control, a
/// `Toggle` item, compiles.
///
/// Mutation **MG1.3**: `Picker` conforming to `MenuContent` (the negative
/// compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aPickerIsNotAMenuItem() throws {
    let picker = try typecheckFile("""
        @MainActor func menu(choice: Binding<Int>) -> some ElementGroup {
            Box().contextMenu {
                Picker("Size", selection: choice) { Text("S").tag(0); Text("L").tag(1) }
            }
        }
        """, importing: "MetalUI")
    let control = try typecheckFile("""
        @MainActor func menu(flag: Binding<Bool>) -> some ElementGroup {
            Box().contextMenu { Toggle("Size", isOn: flag) }
        }
        """, importing: "MetalUI")
    print("""
        MN-D picker: picker succeeded=\(picker.succeeded) messages=[\(picker.messages)]; \
        control succeeded=\(control.succeeded) messages=[\(control.messages)]
        """)
    try #require(control.succeeded && !picker.succeeded,
                 "the control must compile and the Picker must not:\n\(control.output)\n\(picker.output)")
    #expect(picker.messages.contains("MenuContent"), "refused FOR MenuContent:\n\(picker.output)")
}

/// A `PlatformWindow` conformer with every requirement except `presentMenu`,
/// which the caller splices in (or not).
private func conformer(member: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: PlatformWindow {
        var contentSize: Size<Pixels> { Size(width: Pixels(1), height: Pixels(1)) }
        var scaleFactor: Float { 1 }
        var renderer: any WindowRenderer { fatalError("never drawn") }
        var title: String = ""
        var appearance: Appearance { .light }
        var onInput: ((InputEvent) -> Bool)?
        var onResize: ((Size<Pixels>, Float) -> Void)?
        var onAppearanceChange: ((Appearance) -> Void)?
        var controlActiveState: ControlActiveState { .key }
        var onControlActiveStateChange: ((ControlActiveState) -> Void)?
        var accessibilityReduceMotion: Bool { false }
        var onAccessibilityReduceMotionChange: ((Bool) -> Void)?
        var onClose: (() -> Void)?
        var onAccessibilityRequest: ((AccessibilityRequest) -> Bool)?
        func publishAccessibilityTree(_ tree: AccessibilityTree) {}
        func setTextInputArea(_ caret: Bounds<Pixels>?) {}
        func readClipboard() -> String? { nil }
        func writeClipboard(_ text: String) {}
        func startDisplayLink(_ tick: @escaping (Double) -> Void) {}
        func setDisplayLinkPaused(_ paused: Bool) {}
        func beginExternalDrag(_: [DragRepresentation], at: Point<Pixels>) -> Bool { false }
        // Colour scheme (`CR-M`), defaultless too, so every arm here carries
        // it; `ColorSchemeCompileGuards` pins it.
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
        // Platform services (`SV-B`), defaultless too, so every arm here carries
        // them; `PlatformServicesCompileGuards` pins them.
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
    \(member)
    }
    """
}

/// **G1.4** (`MN-C` item 1). `PlatformWindow.presentMenu(_:at:)` has **no
/// default implementation** (`EV-AB`'s reason): a conformer that forgets it
/// fails to compile, naming it. **Positive control**: the same conformer with
/// the member — the migration note's spelling, verbatim — compiles.
///
/// Mutation **MG1.4**: a protocol-extension default answering `false` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutPresentMenuDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func presentMenu(_: PlatformMenu, at: Point<Pixels>) -> Bool { false }
        """), importing: "MetalUIPlatform")
    print("""
        MN-C member required: without succeeded=\(without.succeeded) \
        messages=[\(without.messages)]; with succeeded=\(with.succeeded) \
        messages=[\(with.messages)]
        """)
    try #require(with.succeeded && !without.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("presentMenu"),
            "the negative must be refused FOR presentMenu:\n\(without.output)")
}
