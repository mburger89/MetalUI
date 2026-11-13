import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Observation
import Testing

// One keystroke, one frame (rulings `FP-N`, `FP-O`, record 277). A key release nothing claims asks for no frame, so
// the keystroke's immediate frame (`FP-M`) is its only one. Portable: the headless window takes the same events
// AppKit sends (committed text, then the release).

@MainActor private final class TypingModel {
    var text = ""
    var ups = 0
}

@MainActor private final class ClockBox { var now: UInt64 = 1_000_000_000 }

/// A window with immediate input on and a hand-driven clock, focus on the first field, settled and clean.
@MainActor private func typingWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (TestWindow, ClockBox) {
    let window = try harnessWindow(content)
    let clock = ClockBox()
    window.window.immediateInputClock = { clock.now }
    window.window.drawsImmediatelyOnInput = true
    window.typeKey(.tab)
    window.tick()
    return (window, clock)
}

/// Types `count` characters as AppKit delivers them (committed text, then the key release), a refresh interval
/// apart, ticking the display link after each; returns the frames drawn.
@MainActor private func typeCharacters(_ count: Int, into window: TestWindow, _ clock: ClockBox) -> Int {
    let before = window.window.framesDrawn
    for i in 0..<count {
        clock.now += 2 * ImmediateInput.fallbackInterval
        let character = String(UnicodeScalar(UInt8(97 + i % 26)))
        window.send(.textInput(character))
        window.send(.keyUp(KeyEvent(charactersIgnoringModifiers: character, characters: character, timestamp: 0)))
        window.tick()
    }
    return window.window.framesDrawn - before
}

/// 1.1 — 200 characters typed into a `TextField`, then into a `CodeView`: one frame per character, not two.
/// **Red before:** 400 frames each (the unclaimed `keyUp` dirtied the window and the next tick drew it). Mutation:
/// the `keyUp` exemption in `Window`'s input handler removed.
@Test @MainActor func aKeystrokeInATextFieldDrawsOneFrame() throws {
    let model = TypingModel()
    let (window, clock) = try typingWindow {
        TextField("", text: model.text) { model.text = $0 }.frame(width: Pixels(200), height: Pixels(24))
    }
    let frames = typeCharacters(200, into: window, clock)
    #expect(model.text.count == 200)
    #expect(frames == 200, "frames per keystroke: \(Double(frames) / 200)")
}

@Test @MainActor func aKeystrokeInACodeViewDrawsOneFrame() throws {
    let buffer = CodeBuffer("")
    let window0 = try codeWindow(buffer: buffer, decorations: CodeDecorations(buffer: buffer))
    window0.click(at: pt(60, 6))
    let clock = ClockBox()
    window0.window.immediateInputClock = { clock.now }
    window0.window.drawsImmediatelyOnInput = true
    window0.tick()
    let frames = typeCharacters(200, into: window0, clock)
    #expect(buffer.snapshot().text.count == 200)
    #expect(frames == 200, "frames per keystroke: \(Double(frames) / 200)")
}

/// 1.2 — a release an `onKeyPress(phases: .up)` handler claims still redraws: the handler's `@State` write shows.
/// Mutation: the exemption widened to every `keyUp`.
@Test @MainActor func aKeyUpAnOnKeyPressUpHandlerClaimsStillRedraws() throws {
    let (window, clock) = try typingWindow { VStack(spacing: 0) { KeyUpCounter() } }
    clock.now += 2 * ImmediateInput.fallbackInterval
    let before = window.window.framesDrawn
    window.send(.keyUp(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0)))
    window.tick()
    #expect(window.window.framesDrawn == before + 1, "the claimed release drew a frame")
    #expect(window.window.needsRedraw == false)
}

private struct KeyUpCounter: Component {
    @State var ups = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(20 + Float(ups)), height: Pixels(20)).background(.accent)
            .focusable()
            .onKeyPress("a", phases: .up) { _ in ups += 1; return .handled }
    }
}

/// 1.3 — a release nothing claims, and the window's `onInput` declining it, leaves the window clean; the same
/// release claimed by `onInput` dirties it. Mutation: the exemption removed.
@Test @MainActor func anUnclaimedKeyUpLeavesTheWindowCleanAndAClaimedOneDirtiesIt() throws {
    let (window, _) = try typingWindow { Box().frame(width: Pixels(20), height: Pixels(20)).focusable() }
    let up = InputEvent.keyUp(KeyEvent(charactersIgnoringModifiers: "a", characters: "a", timestamp: 0))
    window.send(up)
    #expect(window.window.needsRedraw == false)
    window.window.onInput = { _ in true }
    window.send(up)
    #expect(window.window.needsRedraw == true)
}
