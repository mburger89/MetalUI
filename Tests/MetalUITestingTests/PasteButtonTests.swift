import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `PasteButton` and the clipboard change notification (rulings `CP-B`, `CP-D`, `CP-G`, `CP-H`, `CP-L`, `CP-M`; spec
// `docs/superpowers/specs/2026-10-22-clipboard-extras-design.md` §5, tests 1.1-1.9). PLAIN imports; the clipboard is the
// headless window's private one. `Graph`/`Blob` are `ClipboardTypesTests`' types.

@MainActor private final class PasteLog {
    var pasted: [[Graph]] = []
    var dropped: [[DropItem]] = []
    var destination: [[Graph]] = []
}

#if os(macOS)
private let primary: EventModifiers = .command
#else
private let primary: EventModifiers = .control
#endif

@MainActor private func pasteWindow(_ log: PasteLog, disabled: Bool = false) throws -> TestWindow {
    try harnessWindow {
        VStack(spacing: 0) {
            PasteButton(payloadType: Graph.self) { log.pasted.append($0) }.disabled(disabled)
        }
    }
}

@MainActor private func paste(_ window: TestWindow) throws -> TestElement { try window.element(label: "Paste") }

/// 1.1 — enablement follows the clipboard, redrawn by the platform's change handler alone: empty is disabled, a matching item
/// enables, a non-matching one disables, cleared disables. The window draws nothing until the tick, then once.
/// **Red before:** `PasteButton` does not exist (compile failure). **Mutation:** enablement read once at the first layout.
@Test @MainActor func aPasteButtonIsEnabledOnlyWhileTheClipboardHoldsWhatItImports() throws {
    let window = try pasteWindow(PasteLog())
    #expect(try !paste(window).isEnabled, "empty clipboard")
    let drawn = window.framesDrawn
    window.setClipboard(items: [Graph(label: "a")])
    #expect(window.framesDrawn == drawn, "the change itself draws nothing")
    window.tick()
    #expect(window.framesDrawn == drawn + 1, "the handler marked the window dirty with no input")
    #expect(try paste(window).isEnabled)
    window.setClipboard(items: [Blob(bytes: [1])])
    window.tick()
    #expect(try !paste(window).isEnabled, "a type it does not import")
    window.setClipboard(items: [Graph(label: "b")])
    window.tick()
    #expect(try paste(window).isEnabled)
    window.platformWindow.clipboard = nil
    window.tick()
    #expect(try !paste(window).isEnabled, "cleared")
}

/// 1.2 — a click delivers every decoded item, in order, in one call. **Mutation:** deliver `.first` only.
@Test @MainActor func aClickDeliversEveryDecodedItemOnce() throws {
    let log = PasteLog()
    let window = try pasteWindow(log)
    window.setClipboard(items: [try #require(Graph(label: "7").clipboardItem()), try #require(Blob(bytes: [0]).clipboardItem()),
                                try #require(Graph(label: "8").clipboardItem())])
    window.tick()
    try window.click(try paste(window))
    #expect(log.pasted == [[Graph(label: "7"), Graph(label: "8")]], "the Blob is skipped, the order kept, one call")
}

/// 1.3 — the `supportedContentTypes` form enables on a type that **conforms** to a supported one and delivers lazily read
/// `DropItem`s. **Mutation:** match the offered type by exact identifier instead of `satisfies`.
@Test @MainActor func theSupportedContentTypesFormMatchesByConformanceAndDeliversDropItems() throws {
    let log = PasteLog()
    let window = try harnessWindow {
        VStack(spacing: 0) { PasteButton(supportedContentTypes: [.plainText]) { log.dropped.append($0) } }
    }
    #expect(try !paste(window).isEnabled)
    window.setClipboard(items: [Blob(bytes: [1])])
    window.tick()
    #expect(try !paste(window).isEnabled, "a blob is not text")
    window.setClipboard(items: ["a", "b"])
    window.tick()
    #expect(try paste(window).isEnabled, "utf8-plain-text conforms to plain-text")
    try window.click(try paste(window))
    let items = try #require(log.dropped.first)
    #expect(log.dropped.count == 1 && items.count == 2)
    #expect(items.map { $0.load("public.utf8-plain-text") } == [Array("a".utf8), Array("b".utf8)])
}

/// 1.4 — the `.disabled` gate and the keyboard: a `.disabled(true)` button neither clicks nor takes Space; a button the clipboard
/// disables does not fire; an enabled one takes Tab focus and Space. **Mutation:** skip the gate (`gated` returns the
/// body unforced).
@Test @MainActor func aPasteButtonIsGatedAndFocusableLikeAButton() throws {
    let log = PasteLog()
    let off = try pasteWindow(log, disabled: true)
    off.setClipboard(items: [Graph(label: "a")])
    off.tick()
    try off.click(try paste(off))
    off.typeKey(.tab); off.typeKey(.space)
    #expect(log.pasted.isEmpty, ".disabled(true)")

    let empty = try pasteWindow(log)
    try empty.click(try paste(empty))
    empty.typeKey(.tab); empty.typeKey(.space)
    #expect(log.pasted.isEmpty, "nothing to import")

    let on = try pasteWindow(log)
    on.setClipboard(items: [Graph(label: "a")])
    on.tick()
    on.typeKey(.tab)
    #expect(try paste(on).isFocused)
    on.typeKey(.space)
    on.typeKey(.space)   // `ControlKeys.activatesButton`: Space everywhere, Return off Apple only
    #expect(log.pasted.count == 2)
}

/// 1.5 — a window with no `PasteButton` is not redrawn by a clipboard change, and never reads the clipboard for it; one with a
/// button is. **Mutation:** dirty unconditionally in `clipboardDidChange`.
@Test @MainActor func aClipboardChangeDirtiesOnlyAWindowHoldingAPasteButton() throws {
    let plain = try harnessWindow { VStack(spacing: 0) { Box().frame(width: Pixels(40), height: Pixels(40)) } }
    let drawn = plain.framesDrawn
    plain.setClipboard(items: [Graph(label: "a")])
    plain.tick()
    #expect(plain.framesDrawn == drawn, "no button, no frame")
    #expect(plain.window.testingClipboardReads == 0, "and the clipboard was never read for it")

    let button = try pasteWindow(PasteLog())
    let before = button.framesDrawn
    button.setClipboard(items: [Graph(label: "a")])
    button.tick()
    #expect(button.framesDrawn == before + 1)
}

/// 1.6 — accessibility: one `button` node labelled "Paste" whose enabled flag follows the clipboard; no new role.
/// **Mutation:** a label other than "Paste".
@Test @MainActor func aPasteButtonIsOneLabelledButtonNodeThatFollowsEnablement() throws {
    let window = try pasteWindow(PasteLog())
    let buttons = try window.elements(role: .button)
    #expect(buttons.count == 1 && buttons.first?.label == "Paste" && buttons.first?.isEnabled == false)
    window.setClipboard(items: [Graph(label: "a")])
    window.tick()
    #expect(try window.elements(role: .button).map(\.isEnabled) == [true])
}

/// 1.7 — ⌘V is unchanged: with a `pasteDestination` focused and a `PasteButton` beside it, the shortcut runs only the destination.
/// **Mutation:** give the button a ⌘V `.keyboardShortcut` (the second arm, with no destination, would press it).
@Test @MainActor func commandVRunsTheDestinationAndNotThePasteButton() throws {
    let log = PasteLog()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(40), height: Pixels(40)).focusable()
                .pasteDestination(for: Graph.self, action: { log.destination.append($0) })
            PasteButton(payloadType: Graph.self) { log.pasted.append($0) }
        }
    }
    window.setClipboard(items: [Graph(label: "a")])
    window.tick()
    window.typeKey(.tab)
    window.typeKey("v", modifierFlags: primary)
    #expect(log.destination == [[Graph(label: "a")]])
    #expect(log.pasted.isEmpty)

    // Second arm: nothing focused, no destination on the chain: ⌘V still does not press the button.
    let bare = try harnessWindow {
        VStack(spacing: 0) { PasteButton(payloadType: Graph.self) { log.pasted.append($0) } }
    }
    bare.setClipboard(items: [Graph(label: "b")])
    bare.tick()
    bare.typeKey("v", modifierFlags: primary)
    #expect(log.pasted.isEmpty, "the shortcut belongs to pasteDestination and the Edit menu, not to PasteButton")
}

/// 1.8a — the headless handler fires once per changing write and never for an identical one; a `.later` write always counts.
/// **Mutation:** fire on every write.
@Test @MainActor func theHeadlessChangeHandlerFiresOnlyOnAChange() {
    let platform = HeadlessPlatformWindow(title: "cb", size: sz(10, 10))
    var count = 0
    platform.setClipboardChangeHandler { count += 1 }
    func item(_ text: String) -> ClipboardItem {
        ClipboardItem(payloads: [ClipboardPayload(type: PasteboardType(identifier: "public.utf8-plain-text"), bytes: .now(Array(text.utf8)))])
    }
    #expect(platform.writeClipboard(items: [item("a")]) && count == 1)
    #expect(platform.writeClipboard(items: [item("a")]) && count == 1, "identical: no change")
    #expect(platform.writeClipboard(items: [item("b")]) && count == 2)
    platform.clipboard = "b"
    #expect(count == 2, "the text view of the same content")
    platform.clipboard = nil
    #expect(count == 3)
    platform.clipboard = nil
    #expect(count == 3, "empty to empty")
    #expect(!platform.writeClipboard(items: []) && count == 3, "nothing written")
    platform.setClipboardChangeHandler(nil)
    _ = platform.writeClipboard(items: [item("c")])
    #expect(count == 3, "removed")
}

private struct PasteHolder: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup {
        VStack(spacing: 0) { PasteButton(payloadType: Graph.self) { _ in } }
    }
}

/// 1.9 — retention: a `PasteButton` inside an `.equatable()` component follows a clipboard change after the component has been
/// warm for several frames, and retention names the refusal. **Mutation:** remove all three taints at once (`taintRetention`'s two
/// channels and `notePasteButton`'s prepaint taint; each alone survives, the channels being redundant by design, measured):
/// the stale disabled record replays and the button stays disabled.
@Test @MainActor func aPasteButtonUnderARetainedComponentStillFollowsTheClipboard() throws {
    let window = try harnessWindow { VStack(spacing: 0) { PasteHolder(tag: 1).equatable() } }
    for _ in 0..<6 { window.window.setNeedsRedraw(); window.tick() }
    #expect(try !paste(window).isEnabled)
    window.setClipboard(items: [Graph(label: "a")])
    window.tick()
    #expect(try paste(window).isEnabled, "the clipboard changed under a warm retained occurrence")
    window.window.setNeedsRedraw(); window.tick()
    #expect(try paste(window).isEnabled)
    let reasons = window.lastFrameWork.retainedIneligibleReasons
    #expect((reasons["pasteButton"] ?? 0) > 0, "retention refuses by name: \(reasons)")
}
