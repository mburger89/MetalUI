import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// The keypad hint (`TRM-BM`, record 383): under DECKPAM the focused terminal asks the platform to deliver keypad
// characters as keys (`PlatformWindow.setRawKeypadKeys`), so `ESC O p`..`y` is sent for them. Headless: the window's
// side (who asks, when, how often) and the view's. The AppKit and SDL routing are `SDLTerminalKeysTests` (SDL package)
// and `TextInputPlatformTests.theKeypadHintMakesKeypadKeysKeysNotText`. Each test names the mutation it was shown red against
// (`docs/practices/verifying-tests-can-fail.md`).

private func esc(_ s: String) -> [UInt8] { [0x1B] + Array(s.utf8) }

extension TermRig {
    /// The hint requests so far.
    var keypadRequests: [Bool] { window.platformWindow.rawKeypadKeyRequests }

    /// A keypad 5 as the platform delivers it: a key with `isKeypad` while the hint is on, text otherwise (what AppKit's
    /// input context and SDL's `TEXT_INPUT` do with it).
    func keypadFive() {
        if keypadRequests.last == true { key("5", keypad: true) } else { typed("5") }
    }

    func focusEditor() async {
        if let first = window.window.lastFocusRegistry.tabOrder.first { window.window.focus(first) }
        await settle()
        log.inputs = []
    }
}

/// **1** The hint follows DECKPAM and focus, and only changes are sent: nothing before the terminal is focused; ESC =
/// asks true; ESC > false; ESC = true again; focus to the editor false; back to the terminal true (the mode is still
/// set); a steady run of frames adds nothing. Mutations: send the hint on every sync (the request lists grow: the
/// exact-list checks fail); ignore the mode (never true); ignore focus (the editor row stays true); drop the sync
/// from the surface-only frame (ESC = never asks: the first row fails).
@MainActor @Test func keypadHintFollowsDeckpamAndFocus() async throws {
    let rig = try TermRig(extra: true)
    await rig.settle()
    #expect(rig.keypadRequests.isEmpty, "nothing before focus: \(rig.keypadRequests)")
    await rig.focusTerminal()
    #expect(rig.keypadRequests.isEmpty, "focused, DECKPAM off: no request (the hint is already off)")
    await rig.feedModes("\u{1B}=")
    #expect(rig.keypadRequests == [true], "\(rig.keypadRequests)")
    for _ in 0..<5 { await rig.frame() }
    #expect(rig.keypadRequests == [true], "steady frames send nothing: \(rig.keypadRequests)")
    await rig.feedModes("\u{1B}>")
    #expect(rig.keypadRequests == [true, false], "\(rig.keypadRequests)")
    await rig.feedModes("\u{1B}=")
    #expect(rig.keypadRequests == [true, false, true], "\(rig.keypadRequests)")
    await rig.focusEditor()
    #expect(rig.keypadRequests == [true, false, true, false], "focus left: \(rig.keypadRequests)")
    await rig.focusTerminal()
    #expect(rig.keypadRequests == [true, false, true, false, true], "back: \(rig.keypadRequests)")
    rig.window.window.focus(nil)
    await rig.settle()
    #expect(rig.keypadRequests.last == false && rig.keypadRequests.count == 6, "focus cleared: \(rig.keypadRequests)")
}

/// **2** End to end: under DECKPAM a keypad 5 reaches the program as `ESC O u`, once, through the platform's routing
/// (key while the hint is on, text while off); without DECKPAM it is the digit, once; after DECKPAM is reset it is the
/// digit again. Mutation: the view's closure answers false (the hint never goes out, the digit arrives as text and the
/// application row fails), or the closure reads the last drawn snapshot instead of the newest modes (no change here
/// once drawn; the row still passes, see item 3).
@MainActor @Test func aKeypadDigitUnderDeckpamSendsTheApplicationSequence() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.keypadFive()
    #expect(rig.sent == [[0x35]], "plain: \(rig.sent)")
    await rig.feedModes("\u{1B}=")
    rig.keypadFive()
    #expect(rig.sent == [esc("Ou")], "application: \(rig.sent)")
    rig.log.inputs = []
    await rig.feedModes("\u{1B}>")
    rig.keypadFive()
    #expect(rig.sent == [[0x35]], "reset: \(rig.sent)")
}

/// **3** The newest modes: a DECKPAM that arrived with no frame since still asks (the next surface-only frame reads
/// `pendingModes`, the same modes a key encodes with). Covered by item 1's order (the feed's frame draws first); this
/// one feeds and ticks once with no settle. Mutation: the closure reads only `snapshot.modes` is covered by item 1.
@MainActor @Test func theHintIsAskedOnTheFrameThatDrawsTheMode() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.feed("\u{1B}=")
    await rig.frame()
    #expect(rig.keypadRequests == [true], "\(rig.keypadRequests)")
}

/// **4** A window with no terminal never sends the hint, however keys and focus move. Mutation: send the hint
/// unconditionally on a focus change (the list is not empty).
@MainActor @Test func noTerminalNeverSetsTheHint() async throws {
    let rig = try TermRig(extra: true, terminal: false)
    await rig.settle()
    await rig.focusEditor()
    rig.typed("a"); rig.key("5", keypad: true)
    rig.window.window.focus(nil)
    await rig.settle()
    #expect(rig.keypadRequests.isEmpty, "\(rig.keypadRequests)")
    #expect(rig.window.platformWindow.rawOptionKeyRequests.isEmpty)
}

/// **5** (cost) The hint adds no work to a frame: output setting DECKPAM is one surface-only frame, 0 builds and 0
/// element requests (item 3 of `TRM-BA`'s literals); a keypad keystroke under DECKPAM costs what any key to the view
/// costs (equal to a letter's, measured in the same run); steady frames afterwards draw nothing and send nothing.
/// Off Darwin the frame count per keystroke can differ, so the counts are compared per frame there.
/// Mutation: `syncRawKeypadKeys` calls `setNeedsRedraw()` on a change (the frames after the output build).
@MainActor @Test func theHintCostsNoFrameWork() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.window.resetFrameWork()
    rig.feed("\u{1B}=")
    await rig.frame()
    let work = rig.window.lastFrameWork
    #expect(work.builds == 0 && work.elementRequests == 0 && work.surfaceOnlyFrames == 1,
            "mode output: \(work.builds) \(work.elementRequests) \(work.surfaceOnlyFrames)")
    #expect(rig.keypadRequests == [true])
    await rig.frame(); await rig.frame()   // a rebuild the hint requested would land here
    let after = rig.window.frameWork.reduce((builds: 0, requests: 0)) { ($0.builds + $1.builds, $0.requests + $1.elementRequests) }
    #expect(after.builds == 0 && after.requests == 0, "the frames after the mode output: \(after)")
    await rig.settle()
    func cost(_ send: () -> Void) async -> (builds: Int, requests: Int, frames: Int) {
        rig.window.resetFrameWork()
        let before = rig.window.framesDrawn
        send()
        await rig.frame()
        let w = rig.window.lastFrameWork
        return (w.builds, w.elementRequests, rig.window.framesDrawn - before)
    }
    let letter = await cost { rig.key("a") }
    await rig.settle()
    let keypad = await cost { rig.key("5", keypad: true) }
    #expect(keypad.builds == 1 && keypad.requests == 2, "keypad keystroke: \(keypad)")   // equal to master (`TRM-BC` item 7)
    #expect(keypad.builds == letter.builds && keypad.requests == letter.requests && keypad.frames == letter.frames,
            "keypad \(keypad) letter \(letter)")
    await rig.settle()
    rig.window.resetFrameWork()
    let draws = rig.window.framesDrawn
    for _ in 0..<50 { await rig.frame(0.05) }
    #expect(rig.keypadRequests == [true], "steady: \(rig.keypadRequests)")
    let steady = rig.window.frameWork.reduce((builds: 0, requests: 0)) { ($0.builds + $1.builds, $0.requests + $1.elementRequests) }
    #expect(steady.builds == 0 && steady.requests == 0, "steady: \(steady) \(rig.window.framesDrawn - draws) frames")
}
