import Testing
import MetalUITestSupport

// Port gaps (medium), lane 2 — guards 3.13, 3.14 and 3.17 (rulings `MD-I`
// items 2–3, `MD-J` item 2, `MD-S` item 3; spec §4.3). Every fixture is
// whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import —
// a `@testable` test cannot prove what an external module can write.
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MD-I`/`MD-J`/`MD-S` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// Test 3.1's tree, as an outside module writes it.
private let fullToolbar = """
    @MainActor func tree(mode: Binding<Int>, on: Binding<Bool>, text: Binding<String>,
                         bitmap: ImageBitmap, flag: Bool, names: [String]) -> some ElementGroup {
        Column {
            Text("Body")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Button("Nav") {} }
                    ToolbarItem(placement: .principal) {
                        Picker("Mode", selection: mode) { Text("A").tag(0); Text("B").tag(1) }
                            .pickerStyle(.segmented)
                    }
                    ToolbarItem(id: "share", placement: .primaryAction) {
                        Button(action: {}) { Image(bitmap, scale: 1, label: Text("Share")) }
                    }
                    ToolbarItem { Toggle("Advanced", isOn: on) }
                    ToolbarItem { TextField("Filter", text: text) }
                    ToolbarItem(placement: .status) { Text("Ready") }
                    ToolbarItemGroup(placement: .automatic) {
                        Button("One") {}.help("the first")
                        Button("Two") {}.disabled(true)
                    }
                    if flag { ToolbarItem { Button("If") {} } } else { ToolbarItem { Text("Else") } }
                    for name in names { ToolbarItem(id: name) { Button(name) {} } }
                }
                .searchable(text: text)
            VStack { Text("p").toolbar { ToolbarItem { Button("P") {} } }.searchable(text: text, prompt: "Find") }
        }
    }
    """

/// **3.13** (`MD-I` items 2–3, divergence 135). The closed item set compiles
/// from a plain import (the control: test 3.1's tree, a group, `.help`,
/// `.disabled`, `if`/`else` and `for`); a view outside the set in a
/// `ToolbarItem` does not, and neither does an outside type writing either
/// SPI requirement.
///
/// Mutation **M3.13**: `ToolbarItemContent`'s requirement made plain `public`
/// (the outside item conformance compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func onlyTheClosedSetIsToolbarContent() throws {
    let control = try typecheckFile(fullToolbar, importing: "MetalUI")
    let shape = try typecheckFile("""
        @MainActor func tree() -> some ElementGroup {
            Column { Text("x").toolbar { ToolbarItem { Rectangle() } } }
        }
        """, importing: "MetalUI")
    let outsideItem = try typecheckFile("""
        struct Mine: ToolbarItemContent {
            func _toolbarControls(in context: _ToolbarItemContext) -> _ToolbarControls {
                Text("x")._toolbarControls(in: context)
            }
        }
        """, importing: "MetalUI")
    let outsideContent = try typecheckFile("""
        struct Mine: ToolbarContent {
            func _toolbarEntries(in context: _ToolbarContext) -> _ToolbarEntries {
                ToolbarItem { Text("x") }._toolbarEntries(in: context)
            }
        }
        """, importing: "MetalUI")
    print("""
        MD-I closed toolbar set: control succeeded=\(control.succeeded) messages=[\(control.messages)]; \
        shape succeeded=\(shape.succeeded); outside item succeeded=\(outsideItem.succeeded) \
        messages=[\(outsideItem.messages)]; outside content succeeded=\(outsideContent.succeeded)
        """)
    try #require(control.succeeded, "the closed set must compile from a plain import:\n\(control.output)")
    #expect(!shape.succeeded, "a Rectangle is not a toolbar item:\n\(shape.output)")
    #expect(!outsideItem.succeeded, "an outside ToolbarItemContent must not compile:\n\(outsideItem.output)")
    #expect(!outsideContent.succeeded, "an outside ToolbarContent must not compile:\n\(outsideContent.output)")
}

/// A `PlatformWindow` conformer with every requirement `34f68c3` had, plus
/// `extra`.
private func conformer(_ extra: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: PlatformWindow {
        // The app-shell requirements (`AS-H`, `AS-J`).
        var onCloseRequest: (() -> Bool)?
        func close() { onClose?() }
        func setDocumentEdited(_ edited: Bool) {}
        func setRepresentedFilePath(_ path: String?) {}
        func setTitleBarStyle(_ style: PlatformTitleBarStyle) -> Bool { false }
        var titleBarInsets: Edges<Pixels> { Edges(all: Pixels(0)) }
        func performTitleBarPress(clickCount: Int) -> Bool { false }
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
        func setPreferredColorScheme(_ colorScheme: ColorScheme?) {}
        func presentMenu(_: PlatformMenu, at: Point<Pixels>) -> Bool { false }
        func presentFileDialog(_: PlatformFileDialog) -> Bool { false }
        func presentAlert(_: PlatformAlert) -> Bool { false }
        func dismissPresentation(token: Int) {}
        func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}
        func setPointerStyle(_ style: PlatformPointerStyle) {}
    \(extra)
    }
    """
}

/// **3.14** (`MD-J` item 2). `setToolbar(_:)` has no default: a conformer
/// without it fails to compile, naming it; with the migration note's spelling
/// it compiles.
///
/// Mutation **M3.14**: a protocol-extension default answering `false`.
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func setToolbarHasNoDefault() throws {
    let without = try typecheckFile(conformer(""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer("    func setToolbar(_: PlatformToolbar?) -> Bool { false }"),
                                 importing: "MetalUIPlatform")
    print("""
        MD-J member required (setToolbar): without succeeded=\(without.succeeded) \
        messages=[\(without.messages)]; with succeeded=\(with.succeeded) messages=[\(with.messages)]
        """)
    try #require(with.succeeded && !without.succeeded,
                 "the control must compile and the negative must not:\nwith:\n\(with.output)\nwithout:\n\(without.output)")
    #expect(without.messages.contains("setToolbar"), "refused FOR setToolbar:\n\(without.output)")
}

/// **3.17** (`MD-S` item 3, divergence 120 amended). A `.toolbar` cannot be a
/// window's root — `ToolbarScope` is an `ElementGroup`, not an `Element` —
/// and inside a container it compiles (the spelling divergence 120 names).
///
/// Mutation **M3.17**: `ToolbarScope` given a conditional `Element`
/// conformance (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aToolbarOnAWindowRootNeedsAContainer() throws {
    let positive = try typecheckFile("""
        @MainActor func open(_ app: App) throws {
            _ = try app.openWindow(title: "w", size: Size(width: Pixels(100), height: Pixels(100))) {
                Column { Text("x").toolbar { ToolbarItem { Button("b") {} } } }
            }
        }
        """, importing: "MetalUI")
    let negative = try typecheckFile("""
        @MainActor func open(_ app: App) throws {
            _ = try app.openWindow(title: "w", size: Size(width: Pixels(100), height: Pixels(100))) {
                Text("x").toolbar { ToolbarItem { Button("b") {} } }
            }
        }
        """, importing: "MetalUI")
    print("""
        MD-S window root: positive succeeded=\(positive.succeeded); negative \
        succeeded=\(negative.succeeded) messages=[\(negative.messages)]
        """)
    try #require(positive.succeeded && !negative.succeeded,
                 "inside a container must compile and as the root must not:\n\(positive.output)\n\(negative.output)")
    #expect(negative.messages.contains("Element"), "refused for Element conformance:\n\(negative.output)")
}
