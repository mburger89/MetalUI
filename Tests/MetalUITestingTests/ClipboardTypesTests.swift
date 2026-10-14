import Foundation
import MetalUI
import MetalUITesting
import Testing

// Clipboard beyond text (rulings `CB-A`…`CB-N`; spec
// `docs/superpowers/specs/2026-10-14-clipboard-types-design.md` §5, tests 1.1-1.15):
// `copyable`, `cuttable`, `pasteDestination` and `Window.clipboard` over the headless
// clipboard, driven by the real ⌘C / ⌘X / ⌘V keystroke. PLAIN imports. The copy
// shortcut is `.primary` (⌘ on Apple, Ctrl elsewhere, `SG-B`).

/// An app's own clipboard type with a plain-text fallback (`CB-C`): its own type
/// first, `.utf8PlainText` after it.
struct Graph: Transferable, Equatable {
    static let contentType = ContentType("com.example.metalui.graph", conformingTo: [.data])
    var label: String

    func exportedContentTypes() -> [ContentType] { [Graph.contentType, .utf8PlainText] }
    static func importedContentTypes() -> [ContentType] { [Graph.contentType, .utf8PlainText] }
    func exported(as contentType: ContentType) -> Data? {
        if contentType == Graph.contentType { return Data("graph:\(label)".utf8) }
        if contentType == .utf8PlainText { return Data("graph \(label)".utf8) }
        return nil
    }
    init(label: String) { self.label = label }
    init?(importing data: Data, contentType: ContentType) {
        let text = String(decoding: data, as: UTF8.self)
        if contentType == Graph.contentType {
            guard text.hasPrefix("graph:") else { return nil }
            label = String(text.dropFirst(6))
        } else if contentType == .utf8PlainText {
            label = "text:" + text
        } else {
            return nil
        }
    }
}

/// A type that lists only its own type (no text fallback).
struct Blob: Transferable, Equatable {
    static let contentType = ContentType("com.example.metalui.blob", conformingTo: [.data])
    var bytes: [UInt8]
    func exportedContentTypes() -> [ContentType] { [Blob.contentType] }
    static func importedContentTypes() -> [ContentType] { [Blob.contentType] }
    func exported(as contentType: ContentType) -> Data? { contentType == Blob.contentType ? Data(bytes) : nil }
    init(bytes: [UInt8]) { self.bytes = bytes }
    init?(importing data: Data, contentType: ContentType) { bytes = [UInt8](data) }
}

@MainActor private final class ClipboardModel {
    var graph = Graph(label: "g1")
    var pasted: [[Graph]] = []
    var cuts = 0
    var log: [String] = []
    var text = ""
}

#if os(macOS)
private let primary: EventModifiers = .command
#else
private let primary: EventModifiers = .control
#endif

@MainActor private func square(_ id: String) -> some StyledElement {
    Box().frame(width: Pixels(40), height: Pixels(40)).accessibilityIdentifier(id)
}

/// One focusable box with all three handlers, in a 400 x 300 window, focused by Tab.
@MainActor private func clipboardWindow(_ m: ClipboardModel, focused: Bool = true,
                                        validator: @escaping @MainActor ([Graph]) -> [Graph] = { $0 }) throws -> TestWindow {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("a").focusable()
                .copyable([m.graph])
                .cuttable(for: Graph.self) { m.cuts += 1; return [m.graph] }
                .pasteDestination(for: Graph.self, action: { m.pasted.append($0) }, validator: validator)
        }
    }
    if focused { window.typeKey(.tab) }
    return window
}

@MainActor private func ids(_ window: TestWindow) -> [String] { window.clipboardRepresentations.map(\.type.identifier) }

/// 1.1 — a focused `copyable` writes its own type first and its text fallback second.
/// Mutation: write only the first representation, or drop the fallback type from the order.
@Test @MainActor func aCopyableFocusedElementWritesItsTypeAndItsTextFallback() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m)
    window.typeKey("c", modifierFlags: primary)
    let reps = window.clipboardRepresentations
    #expect(reps.map(\.type.identifier) == ["com.example.metalui.graph", "public.utf8-plain-text"])
    #expect(reps.map { String(decoding: $0.bytes, as: UTF8.self) } == ["graph:g1", "graph g1"])
    #expect(window.platformWindow.clipboard == "graph g1", "the text property is a view of the text representation (1.15)")
}

/// 1.2 — the separating arm of 1.1: the same handlers on a **hover key region** with nothing
/// focused, pointer resting on it, write nothing (`CB-B`, `KF-U`: the key chain of a hover region
/// feeds only the keymap and `onKeyPress`); focusing it (Tab) then writes. Mutation:
/// `dispatchClipboardKey` walks `keyChain` (the hover region's) instead of `focusChain`.
@Test @MainActor func aCopyOnAnUnfocusedAncestorlessElementWritesNothing() throws {
    let m = ClipboardModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("a").focusable().hoverKeyRegion().copyable([m.graph])
        }
    }
    let box = try window.element(identifier: "a")
    window.hover(at: Point(x: box.frame.origin.x + box.frame.size.width / 2, y: box.frame.origin.y + box.frame.size.height / 2))
    window.typeKey("c", modifierFlags: primary)
    #expect(window.clipboardRepresentations.isEmpty, "hover alone routes no clipboard key")
    window.typeKey(.tab)
    window.typeKey("c", modifierFlags: primary)
    #expect(window.clipboardRepresentations.count == 2, "focus does")
}

/// 1.3 — cut runs its action exactly once and writes what it returned.
/// Mutation: run the action twice, or write before the action.
@Test @MainActor func cutWritesTheItemsThenRunsTheActionOnce() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m)
    window.typeKey("x", modifierFlags: primary)
    #expect(m.cuts == 1)
    #expect(ids(window) == ["com.example.metalui.graph", "public.utf8-plain-text"])
}

/// 1.4 — a paste reads the destination's first imported type that is present.
/// Mutation: invert `importedContentTypes` preference.
@Test @MainActor func aPasteDestinationReadsTheCustomTypeBeforeTheText() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m)
    window.setClipboard(Graph(label: "from elsewhere"))
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted == [[Graph(label: "from elsewhere")]], "the custom type, not the text fallback")
}

/// 1.5 — only text on the clipboard: the destination falls back to its text import.
/// Mutation: `importClipboardItem` ignores the text representation.
@Test @MainActor func aPasteWithOnlyTextFallsBackToTheTextImport() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m)
    window.setClipboard(text: "hello")
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted == [[Graph(label: "text:hello")]])
}

/// 1.6 — a paste with nothing importable is declined, and the next stage runs: a `Button`
/// shortcut on the same key fires. Mutation: claim the key with no import.
@Test @MainActor func aPasteWithNoImportableTypeDeclinesAndTheNextStageRuns() throws {
    let m = ClipboardModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("a").focusable().pasteDestination(for: Graph.self) { m.pasted.append($0) }
            Button("Paste command") { m.log.append("button") }.keyboardShortcut("v")
        }
    }
    window.typeKey(.tab)
    window.setClipboard(Blob(bytes: [1, 2, 3]))   // a type Graph imports neither as itself nor as text
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted.isEmpty)
    #expect(m.log == ["button"], "the declined key reached the Button's shortcut")
    // Separating arm: with a Graph on the clipboard the destination claims it.
    window.setClipboard(Graph(label: "x"))
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted.count == 1)
    #expect(m.log == ["button"])
}

/// 1.7 — the validator decides, and an empty result declines (the next stage runs).
/// Mutation: skip the validator.
@Test @MainActor func theValidatorDecidesAndAnEmptyResultDeclines() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m, validator: { $0.filter { $0.label.hasPrefix("ok") } })
    window.setClipboard(Graph(label: "no"))
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted.isEmpty)
    window.setClipboard(Graph(label: "ok1"))
    window.typeKey("v", modifierFlags: primary)
    #expect(m.pasted == [[Graph(label: "ok1")]])
}

/// 1.8 — a focused text field keeps its own copy, cut and paste under a `copyable` ancestor
/// (`CB-M`; `TI-D` unmoved). Mutation: order the stage before `dispatchTextKey`.
@Test @MainActor func aFocusedTextFieldKeepsItsOwnCopyCutPasteUnderACopyableAncestor() throws {
    let m = ClipboardModel()
    m.text = "abc"
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TextField("", text: m.text) { m.text = $0 }.frame(width: Pixels(200), height: Pixels(24))
        }
        .copyable([m.graph])
        .pasteDestination(for: Graph.self) { m.pasted.append($0) }
    }
    window.typeKey(.tab)
    window.typeKey("a", modifierFlags: primary)
    window.typeKey("c", modifierFlags: primary)
    #expect(window.platformWindow.clipboard == "abc", "the field copied its text")
    #expect(ids(window) == ["public.utf8-plain-text"], "and replaced everything else")
    window.setClipboard(text: "zz")
    window.typeKey("v", modifierFlags: primary)
    #expect(m.text == "zz" && m.pasted.isEmpty, "the field pasted, the ancestor's destination did not")
}

/// 1.9 — the Keymap and `onKeyPress` still run before a clipboard handler (`CB-B`).
/// Mutation: order the stage first.
@Test @MainActor func onKeyPressAndTheKeymapStillBeatAClipboardHandler() throws {
    let m = ClipboardModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("a").focusable()
                .copyable([m.graph])
                .onKeyPress("c") { m.log.append("keypress"); return .handled }
        }
    }
    window.typeKey(.tab)
    window.typeKey("c", modifierFlags: primary)
    #expect(m.log == ["keypress"])
    #expect(window.clipboardRepresentations.isEmpty)
}

/// 1.10 — the innermost handler of a kind on the chain wins; an outer kind the inner lacks still
/// serves. Mutation: outermost first.
@Test @MainActor func theInnermostHandlerOnTheChainWins() throws {
    let m = ClipboardModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            square("a").focusable().copyable([Graph(label: "inner")])
        }
        .copyable([Graph(label: "outer")])
        .cuttable(for: Graph.self) { m.cuts += 1; return [Graph(label: "outer-cut")] }
    }
    window.typeKey(.tab)
    window.typeKey("c", modifierFlags: primary)
    #expect(window.platformWindow.clipboard == "graph inner")
    window.typeKey("x", modifierFlags: primary)
    #expect(m.cuts == 1 && window.platformWindow.clipboard == "graph outer-cut", "the ancestor's cut serves")
}

/// 1.10b — later keyboard modifiers keep the clipboard attachment: every factory of
/// `KeyboardAttachment` carries it. Mutation: a factory forgetting the field.
@Test @MainActor func eachKeyboardModifierFactoryKeepsTheClipboardAttachment() throws {
    let m = ClipboardModel()
    func check<E: Element>(_ name: String, _ make: @escaping @MainActor () -> E) throws {
        let window = try harnessWindow { VStack(spacing: 0) { make() } }
        window.typeKey(.tab)
        window.typeKey("c", modifierFlags: primary)
        #expect(window.platformWindow.clipboard == "graph g1", "\(name) kept the copy handler")
    }
    try check("focusable") { square("a").copyable([m.graph]).focusable() }
    try check("interactions") { square("a").copyable([m.graph]).focusable(interactions: .edit) }
    try check("onKeyPress") { square("a").focusable().copyable([m.graph]).onKeyPress("q") { .ignored } }
    try check("hoverKeyRegion") { square("a").focusable().copyable([m.graph]).hoverKeyRegion() }
    try check("resigns") { square("a").focusable().copyable([m.graph]).resignsFocusOnPress() }
}

// MARK: - The drawn bar, the seam, the imperative API

/// 1.11 — with `showsMenuBarNatively` off the window draws the bar: the Edit items Copy, Cut and
/// Paste are enabled only with a handler on the focus chain (or a text field), and choosing one
/// reaches the handler. Mutation: `editEnabled` ignores `ClipboardCommands`.
@Test @MainActor func theEditMenuItemsCopyCutPasteReachTheHandlerThroughTheDrawnBar() throws {
    let m = ClipboardModel()
    let app = try TestApp(textSystem: harnessTextSystem)
    app.platform.showsMenuBarNatively = false
    app.platform.nextWindowOptions = .init(presentsMenusNatively: false)
    app.app.commands { CommandMenu("Extra") { Button("Noop") {} } }
    let window = try app.openWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            square("a").focusable()
                .copyable([m.graph])
                .cuttable(for: Graph.self) { m.cuts += 1; return [m.graph] }
        }
    }
    // Nothing focused: the items are disabled.
    try window.click(window.element(label: "Edit"))
    #expect(try window.element(label: "Copy").isEnabled == false)
    #expect(try window.element(label: "Paste").isEnabled == false)
    window.typeKey(.escape)
    window.typeKey(.tab)
    try window.click(window.element(label: "Edit"))
    #expect(try window.element(label: "Copy").isEnabled)
    #expect(try window.element(label: "Cut").isEnabled)
    #expect(try window.element(label: "Paste").isEnabled == false, "no pasteDestination on the chain")
    try window.click(window.element(label: "Copy"))
    #expect(window.platformWindow.clipboard == "graph g1")
    try window.click(window.element(label: "Edit"))
    try window.click(window.element(label: "Cut"))
    #expect(m.cuts == 1)
}

/// 1.12 — `setClipboardCommands` is sent when the chain's commands change and not on any other
/// frame. Mutation: send every frame.
@Test @MainActor func setClipboardCommandsIsSentOnChangeOnly() throws {
    let m = ClipboardModel()
    let window = try clipboardWindow(m, focused: false)
    window.tick(); window.tick()
    #expect(window.platformWindow.clipboardCommandRequests.isEmpty, "nothing focused: the default [] is not sent")
    window.typeKey(.tab)
    window.tick(); window.tick(); window.tick()
    #expect(window.platformWindow.clipboardCommandRequests == [[.cut, .copy, .paste]])
    window.typeKey(.tab, modifierFlags: .shift)   // focus leaves (a single focusable wraps or clears)
    window.tick()
    let requests = window.platformWindow.clipboardCommandRequests
    #expect(requests.first == [.cut, .copy, .paste] && requests.count <= 2)
}

/// 1.13 — `Window.clipboard` round-trips a `Transferable`, lists its types, reports `hasContent`,
/// writes nothing for an empty array or a zero-byte value (keeping the contents), and reads an
/// absent type as `nil`. Mutation: write zero-byte representations.
@Test @MainActor func windowClipboardRoundTripsATransferableAndReportsEmptyAndAbsent() throws {
    let window = try harnessWindow { Text("x") }
    let clipboard = window.window.clipboard
    #expect(clipboard.contentTypes.isEmpty && clipboard.read(Graph.self) == nil)
    #expect(clipboard.write(Graph(label: "g")))
    #expect(clipboard.contentTypes == ["com.example.metalui.graph", "public.utf8-plain-text"])
    #expect(clipboard.read(Graph.self) == Graph(label: "g"))
    #expect(clipboard.hasContent(of: Graph.contentType))
    #expect(clipboard.hasContent(of: .plainText), "conformance-aware: utf8 text satisfies plain text")
    #expect(!clipboard.hasContent(of: .json))
    #expect(clipboard.read(Blob.self) == nil, "an absent type reads nil")

    let empty: [Graph] = []
    #expect(!clipboard.write(empty), "an empty array writes nothing")
    #expect(!clipboard.write(Blob(bytes: [])), "a zero-byte value writes nothing")
    #expect(clipboard.read(Graph.self) == Graph(label: "g"), "and the contents are kept")
    #expect(clipboard.write([Graph(label: "first"), Graph(label: "second")]))
    #expect(clipboard.read(Graph.self) == Graph(label: "first"), "only the first item is written (divergence 456)")

    window.setClipboard(text: "just text")
    #expect(clipboard.read(Graph.self) == Graph(label: "text:just text"), "the text import serves as the fallback")
    #expect(clipboard.read(String.self) == "just text")
}

/// 1.14 — an 8 MiB payload round-trips byte for byte. Mutation: truncate in the headless store.
@Test @MainActor func aLargePayloadRoundTripsByteForByte() throws {
    let window = try harnessWindow { Text("x") }
    let bytes = (0..<(8 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ ($0 >> 8)) }
    #expect(window.window.clipboard.write(Blob(bytes: bytes)))
    #expect(window.window.clipboard.read(Blob.self)?.bytes == bytes)
}

/// 1.15 — the existing text path is a view of the text representation: a text-field copy and
/// `clipboard =` set exactly one `public.utf8-plain-text` representation.
@Test @MainActor func theClipboardTextPropertyIsAViewOfTheTextRepresentation() throws {
    let window = try harnessWindow { Text("x") }
    window.platformWindow.clipboard = "abc"
    #expect(window.clipboardRepresentations.map(\.type.identifier) == ["public.utf8-plain-text"])
    #expect(window.clipboardRepresentations.first?.bytes == Array("abc".utf8))
    #expect(window.window.clipboard.read(String.self) == "abc")
    window.platformWindow.clipboard = nil
    #expect(window.clipboardRepresentations.isEmpty)
}

/// 1.11b (divergence 455, `CB-G`) — Paste is enabled by the presence of a destination, not by its
/// validator: a validator rejecting everything leaves the item enabled and the paste does nothing.
/// Mutation: `chainClipboardCommands` omits `.paste`.
@Test @MainActor func thePasteItemIsEnabledByThePresenceOfADestinationNotItsValidator() throws {
    let m = ClipboardModel()
    let app = try TestApp(textSystem: harnessTextSystem)
    app.platform.showsMenuBarNatively = false
    app.platform.nextWindowOptions = .init(presentsMenusNatively: false)
    app.app.commands { CommandMenu("Extra") { Button("Noop") {} } }
    let window = try app.openWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            square("a").focusable()
                .pasteDestination(for: Graph.self, action: { m.pasted.append($0) }, validator: { _ in [] })
        }
    }
    window.typeKey(.tab)
    window.setClipboard(Graph(label: "x"))
    try window.click(window.element(label: "Edit"))
    #expect(try window.element(label: "Paste").isEnabled, "enabled by presence")
    try window.click(window.element(label: "Paste"))
    #expect(m.pasted.isEmpty, "and the validator declined the paste")
}
