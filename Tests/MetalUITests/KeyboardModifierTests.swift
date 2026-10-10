import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Key and focus scoping, lane C — the proposal `KeyboardModifier` (rulings
// `KF-H`, `KF-W` item 1; spec `docs/superpowers/specs/2026-10-08-key-focus-design.md`
// §4.4, tests C4 and C5) and MetalCreator's `TextEditor` commit key (CM-a:
// `.onKeyPress(keys: [.return])` taking ⌘↩ on a focused `TextEditor`).
//
// Windows are 200 × 200 over `FakePlatformWindow`, roots centred (`CN-J`).
// Nothing sleeps. Red before: the stub commit's `KeyboardModifier` lays its
// content out and registers nothing — each test names what it read there.

// MARK: - Harness

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func kd(_ c: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: modifiers,
                      isRepeat: false, timestamp: 0))
}

@MainActor private final class KMLog {
    var log: [String] = []
    var text: String
    var setFlag: (Bool) -> Void = { _ in }
    var flags: [Bool] = []
    init(_ text: String = "") { self.text = text }
}

@MainActor private func kmWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, content: content)
    window.drawFrameIfNeeded()
    return (window, platform)
}

// MARK: - C4, C5: one layer on the focus target

/// **C4** (was A34; `KF-H` items 1–2, MetalCreator M4-a). A `MetalView`
/// viewport written `.focusable(interactions: .edit).keyContext("Viewport")
/// .onKeyPress("f")` is **one** keyboard layer: the one focusable id carries
/// the context and the handler, a primary press on it focuses it (FC3), and
/// `f` then reaches its handler. Red before: does not compile; against the
/// stub nothing is focusable (`tabOrder` empty). Mutation: make
/// `KeyboardModifier`'s own methods return a nested wrapper (the context and
/// handler land on other ids).
@MainActor
@Test func aMetalViewTakesFocusOnPressAndHearsKeysThroughOneLayer() throws {
    let m = KMLog()
    let (window, platform) = try kmWindow {
        HStack(spacing: 0) {
            MetalView { _ in }
                .frame(width: px(100), height: px(100))
                .focusable(interactions: .edit)
                .keyContext("Viewport")
                .onKeyPress("f") { m.log.append("f"); return .handled }
        }
    }
    let registry = window.lastFocusRegistry
    try #require(registry.tabOrder.count == 1, "one focusable layer: \(registry.tabOrder)")
    let id = registry.tabOrder[0]
    #expect(registry.context(for: id)?.name == "Viewport", "the context sits on the focus target")
    #expect(registry.keyPresses(for: id).count == 1, "the handler sits on the focus target")
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(100, 100))))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(100, 100))))
    #expect(window.focusedElement == id, "a press focused the viewport (FC3)")
    window.drawFrameIfNeeded()
    #expect(platform.simulateInput(kd("f")), "the viewport's handler claims f")
    #expect(m.log == ["f"], "\(m.log)")
}

/// A proposal pane binding its viewport's focus to a `@FocusState`.
private struct KMFocusPane: Component {
    @FocusState var flag: Bool
    let model: KMLog

    var content: some ProposalElementGroup {
        let _ = model.flags.append(flag)
        let _ = model.setFlag = { [flag = $flag] in flag.wrappedValue = $0 }
        Rectangle(width: Pixels(40), height: Pixels(40))
            .focused($flag)
            .focusable()
            .keyContext("Viewport")
    }
}

/// **C5** (was A35; `KF-H` item 2). On proposal content `.focused($flag)`
/// written first, then `.focusable()` and `.keyContext`, all sit on one id: the
/// binding is recorded on the focusable id, a write of `true` from input
/// focuses it, and the flag reads `true` back. Red before: does not compile;
/// against the stub no binding is recorded. Mutation: register the binding on
/// the content's id.
@MainActor
@Test func aProposalFocusedBindingAndKeyContextSitOnTheFocusTarget() throws {
    let m = KMLog()
    let (window, _) = try kmWindow { HStack { KMFocusPane(model: m) } }
    let registry = window.lastFocusRegistry
    try #require(registry.tabOrder.count == 1, "one focusable layer: \(registry.tabOrder)")
    let id = registry.tabOrder[0]
    #expect(registry.focusBinding(for: id) != nil, "the binding sits on the focus target")
    #expect(registry.context(for: id)?.name == "Viewport", "and so does the context")
    m.setFlag(true)
    for _ in 0..<4 { window.drawFrameIfNeeded() }
    #expect(window.focusedElement == id, "the write focused the bound layer")
    #expect(m.flags.last == true, "and the state reads it back: \(m.flags)")
}

// MARK: - CM-a: a TextEditor's commit key

/// A focused one-editor window: `TextEditor` with `extra` applied, focused by
/// Tab, the caret moved to the end.
@MainActor private func editorWindow(_ model: KMLog,
                                     _ extra: @escaping @MainActor (TextEditor) -> TextEditor)
    throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try kmWindow {
        Box { extra(TextEditor("", text: model.text) { model.text = $0 }) }
    }
    platform.simulateInput(kd("\t"))
    window.drawFrameIfNeeded()
    try #require(window.focusedElement != nil, "set up: Tab focuses the editor")
    platform.simulateInput(kd(TextEditing.rightArrow))
    window.drawFrameIfNeeded()
    return (window, platform)
}

/// **CM-a** (MetalCreator: committing a multi-line field). A focused
/// `TextEditor` with `.onKeyPress(keys: [.return])` answering `.handled` for
/// ⌘↩ runs the handler and leaves the text unchanged; a plain Return, which the
/// handler ignores, still inserts a line break (`TI-H`). Red before: does not
/// compile at `c62d6ba` (no `onKeyPress`). Mutation: move `dispatchKeyPress`
/// after `dispatchTextKey` (⌘↩ inserts a line break).
@MainActor
@Test func aTextEditorsOnKeyPressTakesCommandReturnAndPlainReturnStillBreaksTheLine() throws {
    let m = KMLog("ab")
    let (window, platform) = try editorWindow(m) {
        $0.onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            m.log.append("commit")
            return .handled
        }
    }
    #expect(platform.simulateInput(kd("\r", .command)), "the handler claims ⌘↩")
    window.drawFrameIfNeeded()
    #expect(m.log == ["commit"], "\(m.log)")
    #expect(m.text == "ab", "⌘↩ left the text unchanged: \(m.text.debugDescription)")
    platform.simulateInput(kd("\r"))
    window.drawFrameIfNeeded()
    #expect(m.log == ["commit"], "plain Return is not a commit: \(m.log)")
    #expect(m.text == "ab\n", "plain Return broke the line (TI-H): \(m.text.debugDescription)")
}

/// **CM-a**, the declined arm. A handler that ignores ⌘↩ passes it on: it
/// reaches the window's `onInput` and the text is unchanged. Red before: does
/// not compile at `c62d6ba`.
@MainActor
@Test func aDeclinedCommandReturnInATextEditorReachesTheWindowsOnInput() throws {
    let m = KMLog("ab")
    let (window, platform) = try editorWindow(m) {
        $0.onKeyPress(keys: [.return]) { _ in m.log.append("heard"); return .ignored }
    }
    window.onInput = { event in
        if case .keyDown(let key) = event, key.charactersIgnoringModifiers == "\r" { m.log.append("input") }
        return false
    }
    platform.simulateInput(kd("\r", .command))
    window.drawFrameIfNeeded()
    #expect(m.log == ["heard", "input"], "the handler heard it, then onInput: \(m.log)")
    #expect(m.text == "ab", "a declined ⌘↩ inserted nothing: \(m.text.debugDescription)")
}
