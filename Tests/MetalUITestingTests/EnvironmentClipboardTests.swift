import Foundation
import MetalUI
import MetalUIMarkdown
import MetalUITesting
import Testing

// The environment clipboard and the Markdown fence copy button (rulings `CB-S`, `BM-K`, record 240): a view's action
// writes the hosting window's clipboard through `@Environment(\.clipboard)`. PLAIN imports, headless platform.

/// A copy button reading the environment clipboard. Equatable on its text, so it is `.equatable()`: the replay test
/// below counts how often its content runs.
@MainActor private final class CopyCounter { var evaluations = 0 }

private struct CopyButton: Component, @MainActor Equatable {
    let text: String
    let id: String
    let counter: CopyCounter?
    @Environment(\.clipboard) var clipboard

    var content: some ElementGroup {
        counter?.evaluations += 1
        let clipboard = clipboard, text = text
        return Button(action: { clipboard.write(text) }) { Text(verbatim: "Copy").accessibilityIdentifier(id) }
            .accessibilityIdentifier(id + "-button")
    }

    static func == (l: CopyButton, r: CopyButton) -> Bool { l.text == r.text && l.id == r.id }
}

@MainActor private func copyWindow(text: String = "hello", counter: CopyCounter? = nil) throws -> TestWindow {
    try harnessWindow {
        VStack(spacing: 0) { CopyButton(text: text, id: "copy", counter: counter).equatable() }
    }
}

/// **CB-S, test 1.** A `Button` action that writes `@Environment(\.clipboard)` lands in the hosting window's
/// clipboard, as text. Mutation: the root stamp (`stampClipboardSource`) removed in `Window.swift` (the clipboard is
/// the no-op one and the window's stays empty).
@Test @MainActor func aButtonActionWritesTheWindowsClipboardThroughTheEnvironment() throws {
    let window = try copyWindow()
    #expect(window.platformWindow.clipboard == nil)
    try window.click(try window.element(identifier: "copy-button"))
    #expect(window.platformWindow.clipboard == "hello", "\(String(describing: window.platformWindow.clipboard))")
    #expect(window.window.clipboard.read(String.self) == "hello", "the same bytes read back through Window.clipboard")
}

/// **CB-S, test 2.** Outside a window the environment's clipboard is a no-op: a write answers `false`, reads answer
/// `nil`, nothing is held. Mutation: the no-op branch (`platform` falling back to something else) is exercised by
/// `Clipboard(weakly: nil)` reaching a platform; the `?? false`/`guard let platform` in `write` removed does not
/// compile, so the observable mutant is `itemCount`'s `?? 0` replaced by `?? 1`.
@Test @MainActor func outsideAWindowTheEnvironmentClipboardIsANoOp() {
    let clipboard = EnvironmentValues().clipboard
    #expect(clipboard.write("x") == false)
    #expect(clipboard.read(String.self) == nil)
    #expect(clipboard.itemCount == 0 && clipboard.contentTypes == [] && clipboard.readAll(String.self) == [])
    #expect(clipboard.hasContent(of: .plainText) == false && clipboard.readData(of: .plainText) == nil)
}

/// **CB-S, test 3.** Two windows of one app each get their own: a press in one writes only its clipboard. Mutation:
/// the stamp taking one shared source (the first window's) for both.
@Test @MainActor func twoWindowsEachWriteTheirOwnClipboard() throws {
    let app = try TestApp(textSystem: harnessTextSystem)
    let a = try app.openWindow { VStack(spacing: 0) { CopyButton(text: "from a", id: "copy", counter: nil).equatable() } }
    let b = try app.openWindow { VStack(spacing: 0) { CopyButton(text: "from b", id: "copy", counter: nil).equatable() } }
    try b.click(try b.element(identifier: "copy-button"))
    #expect(a.platformWindow.clipboard == nil && b.platformWindow.clipboard == "from b")
    try a.click(try a.element(identifier: "copy-button"))
    #expect(a.platformWindow.clipboard == "from a" && b.platformWindow.clipboard == "from b")
    #expect(a.window.clipboard == a.window.clipboard && a.window.clipboard != b.window.clipboard, "equal per window (replay compares it)")
}

/// **CB-S, test 4.** The environment value does not break `.equatable()` replay: an idle frame over an equatable
/// component that reads it evaluates its content zero times and replays (`retainedHits > 0`), and the press still
/// works afterwards. Mutation: the stamp's reading `.uncomparable`-style (a fresh object identity per frame), which
/// makes every position unreplayable.
@Test @MainActor func theEnvironmentClipboardDoesNotBreakEquatableReplay() throws {
    let counter = CopyCounter()
    let window = try copyWindow(counter: counter)
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let before = counter.evaluations
    window.resetFrameWork()
    window.window.setNeedsRedraw(); window.tick()
    #expect(counter.evaluations == before, "an idle frame re-evaluated the component \(counter.evaluations - before) times")
    if !rsVerifying { #expect(window.lastFrameWork.retainedHits > 0, "hits \(window.lastFrameWork.retainedHits), ineligible \(window.lastFrameWork.retainedIneligibleReasons)") }
    try window.click(try window.element(identifier: "copy-button"))
    #expect(window.platformWindow.clipboard == "hello")
}

/// **CB-S, test 5.** A clipboard kept past its window holds it weakly: once the window is gone the stored value is
/// the no-op clipboard. Mutation: `ClipboardSource.platformWindow` made strong (the write still lands).
@Test @MainActor func aStoredEnvironmentClipboardDoesNotRetainItsWindow() throws {
    let keeper = ClipboardKeeper()
    weak var platform: HeadlessPlatformWindow?
    do {
        var window: TestWindow? = try harnessWindow { VStack(spacing: 0) { ClipboardTaker(keeper: keeper) } }
        platform = window?.platformWindow
        #expect(keeper.clipboard?.write("alive") == true, "while the window lives the stored value writes")
        window = nil
    }
    #expect(platform == nil, "the stored clipboard kept the window alive")
    #expect(keeper.clipboard?.write("dead") == false)
}

@MainActor private final class ClipboardKeeper { var clipboard: Clipboard? }

private struct ClipboardTaker: Component {
    let keeper: ClipboardKeeper
    @Environment(\.clipboard) var clipboard
    var content: some ElementGroup {
        keeper.clipboard = clipboard
        return Box().frame(width: Pixels(10), height: Pixels(10))
    }
}

// MARK: The Markdown fence copy button (`BM-K`)

@MainActor private func fenceWindow(_ source: String, copy: Bool, meter: MarkdownMeterTextSystem? = nil) throws -> TestWindow {
    var theme = MarkdownTheme()
    theme.showsCodeCopyButton = copy
    let document = MarkdownDocument(parsing: source)
    let window = try TestWindow(size: sz(300, 400), textSystem: { meter ?? harnessTextSystem() }) {
        VStack(alignment: .leading, spacing: Pixels(0)) { MarkdownView(document).markdownTheme(theme) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    markdownSettle(window, frames: 3)
    return window
}

private let copyLabel = "Copy code"

@MainActor private func copyButtons(_ window: TestWindow) throws -> [TestElement] {
    try window.elements(where: { $0.label == copyLabel })
}

/// **BM-K, test 1.** A fence's copy button writes the whole fence, every line, as plain text. Mutation: the action
/// writes the language or the first chunk only; the action removed.
@Test @MainActor func theCopyButtonCopiesTheWholeFence() throws {
    let code = (1...40).map { "line \($0)" }.joined(separator: "\n")   // two chunks (`BM-H`: 32 lines each)
    let window = try fenceWindow("```swift\n\(code)\n```", copy: true)
    let buttons = try copyButtons(window)
    try #require(buttons.count == 1, "one button for one fence")
    try window.click(buttons[0])
    #expect(window.platformWindow.clipboard == code, "\(String(describing: window.platformWindow.clipboard))")
}

/// **BM-K, test 2.** A fence nested in a list item and in a quote has its own button, copying its own code. Mutation:
/// the list or the quote not forwarding the theme (it keeps the default: no button).
@Test @MainActor func aNestedFenceHasItsOwnCopyButton() throws {
    let source = "- item\n\n  ```\n  inner a\n  ```\n\n> ```\n> inner b\n> ```\n\n```\nouter\n```"
    let window = try fenceWindow(source, copy: true)
    let buttons = try copyButtons(window).sorted { $0.frame.origin.y.value < $1.frame.origin.y.value }
    try #require(buttons.count == 3, "\(buttons.count) buttons")
    var copied: [String] = []
    for button in buttons { try window.click(button); copied.append(window.platformWindow.clipboard ?? "nil") }
    #expect(copied == ["inner a", "inner b", "outer"], "\(copied)")
}

/// **BM-K, test 3.** By default there is no button. Mutation: `showsCodeCopyButton` defaulting to `true`.
@Test @MainActor func noCopyButtonIsShownByDefault() throws {
    #expect(MarkdownTheme().showsCodeCopyButton == false)
    let window = try fenceWindow("```\ncode\n```", copy: false)
    #expect(try copyButtons(window).isEmpty)
}

/// **BM-K, test 4.** The button changes neither the fence's size nor its text's place, and pressing it shapes
/// nothing (no re-measure of the code), the fence staying `.equatable()`. Mutation: the button as a row in the
/// fence's `VStack` (the code moves down); the press writing an `@State` the fence reads (the code is shaped again).
@Test @MainActor func theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence() throws {
    let source = "```\nlet a = 1\nlet b = 2\n```"
    let plain = try fenceWindow(source, copy: false)
    let meter = MarkdownMeterTextSystem(harnessTextSystem())
    let window = try fenceWindow(source, copy: true, meter: meter)
    func code(_ w: TestWindow) throws -> TestElement {
        try #require(try w.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("let a") })
    }
    let withButton = try code(window).frame, without = try code(plain).frame
    #expect(withButton == without, "the code did not move: \(withButton) vs \(without)")
    let button = try #require(try copyButtons(window).first)
    let fence = try #require(try window.elements(where: { $0.label == "Code" }).first)
    #expect(button.frame.origin.x.value + button.frame.size.width.value <= fence.frame.origin.x.value + fence.frame.size.width.value + 0.5)
    meter.reset()
    try window.click(button)
    markdownSettle(window, frames: 3)
    // Under `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1` every frame re-evaluates on purpose, so only the plain run can count shaping (`BM-M`).
    if !rsVerifying && !layoutMemoVerifying { #expect(meter.measuredStrings.filter { $0.contains("let a") }.isEmpty, "the press re-measured the code: \(meter.measuredStrings)") }
    #expect(window.platformWindow.clipboard == "let a = 1\nlet b = 2")
}
