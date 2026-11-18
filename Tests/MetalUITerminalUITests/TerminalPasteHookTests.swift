import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// The terminal's paste hook (`TRM-BG`, record 378), headless on `TermRig`: `onPaste` sees the text and the newest modes
// before the default paste, for every route, and its answer decides. Mutations, each shown red against this file:
//   - skip the hook call in `TerminalViewModel.paste` (items 1, 2, 3, 4 fail);
//   - ignore its return (call it, then send anyway: item 4 fails);
//   - pass `TerminalModes()` or the last drawn snapshot's modes instead of `modes` (item 3 fails);
//   - route one path around the hook (send `encodePaste` straight from the Ctrl+Shift+V branch, or build the
//     pasteDestination's action without `paste`: item 1 off Apple, item 2 on Apple fail);
//   - hand the hook the text after `encodePaste` (item 1's text equality fails);
//   - drop `onPaste` from the field's `model.onPaste = onPaste` (every hook item fails);
//   - compare `onPaste` in the field's `==` (not mutable: a closure has no equality; the cost item guards a stored
//     per-frame cost instead).

private func esc(_ s: String) -> [UInt8] { [0x1B] + Array(s.utf8) }

/// What a hook saw, and what it answers.
@MainActor private final class Hook {
    var calls: [(text: String, modes: TerminalModes)] = []
    var answer: Bool
    init(_ answer: Bool) { self.answer = answer }
    var closure: @MainActor (String, TerminalModes) -> Bool { { [self] text, modes in calls.append((text, modes)); return answer } }
}

@MainActor private func rigWith(_ hook: Hook?) async throws -> TermRig {
    let rig = try TermRig(paste: hook?.closure)
    await rig.settle()
    await rig.focusTerminal()
    return rig
}

/// The paste key of this platform: ⌘V on Apple, Ctrl+Shift+V elsewhere.
@MainActor private func pasteKey(_ rig: TermRig) {
    let chord: Modifiers = Modifiers.primary == .command ? .command : [.control, .shift]
    let letter = Modifiers.primary == .command ? "v" : "V"
    rig.key(letter, chord, ignoring: "v")
}

/// **1** The paste key reaches the hook with the clipboard text, once, and the modes. Mutation: skip the hook call, or
/// route the key's branch around `paste`.
@MainActor @Test func primaryVReachesTheHook() async throws {
    let hook = Hook(true)
    let rig = try await rigWith(hook)
    _ = rig.window.window.clipboard.write("one\ntwo\u{1B}[31m")
    pasteKey(rig)
    #expect(hook.calls.count == 1, "\(hook.calls.count)")
    #expect(hook.calls.first?.text == "one\ntwo\u{1B}[31m", "the hook sees the raw text, not the encoded paste")
}

/// **2** The route the paste destination serves (Edit ▸ Paste, and ⌘V on Apple) reaches the hook: the focus chain's
/// clipboard handler, called as the menu's `.paste` does, and on Apple the menu's own delivery. Mutation: the
/// destination's action does not go through `paste`.
@MainActor @Test func editPasteMenuReachesTheHook() async throws {
    let hook = Hook(true)
    let rig = try await rigWith(hook)
    _ = rig.window.window.clipboard.write("menu text")
    let window = rig.window.window
    var found: (@MainActor @Sendable ([DropItem]) -> Bool)?
    for id in window.focusChain where found == nil { found = window.lastFocusRegistry.clipboardHandler(for: id)?.paste }
    let handler = try #require(found)
    let items = window.clipboard.items
    #expect(handler(items))
    #expect(hook.calls.map(\.text) == ["menu text"], "\(hook.calls.map(\.text))")
    #expect(rig.sent.isEmpty, "answered true: nothing sent")
    #if os(macOS)
    window.deliverStandardEditKey(.paste)
    #expect(hook.calls.map(\.text) == ["menu text", "menu text"], "Edit ▸ Paste on Apple: \(hook.calls.map(\.text))")
    #endif
}

/// **3** The hook's modes are the current ones: a child that set bracketed paste (2004) shows it, and one that has not
/// does not, and a mode set in the same burst as the paste, before the view drew it, already shows (the source's
/// pending modes). Mutation: pass `TerminalModes()`, or the last drawn snapshot's modes.
@MainActor @Test func hookGetsCurrentBracketedPasteMode() async throws {
    let hook = Hook(true)
    let rig = try await rigWith(hook)
    _ = rig.window.window.clipboard.write("x")
    pasteKey(rig)
    #expect(hook.calls.last?.modes.bracketedPaste == false)
    await rig.feedModes("\u{1B}[?2004h")
    pasteKey(rig)
    #expect(hook.calls.last?.modes.bracketedPaste == true, "mode 2004 drawn")
    rig.feed("\u{1B}[?2004l")        // not drawn yet: no settle, no frame
    pasteKey(rig)
    #expect(hook.calls.last?.modes.bracketedPaste == false, "mode 2004 reset in the same burst as the paste")
    #expect(hook.calls.count == 3)
}

/// **4** Answering true sends nothing; the host owns the paste. Mutation: ignore the return.
@MainActor @Test func returningTrueSendsNothing() async throws {
    let hook = Hook(true)
    let rig = try await rigWith(hook)
    _ = rig.window.window.clipboard.write("abc")
    pasteKey(rig)
    #expect(hook.calls.count == 1)
    #expect(rig.sent.isEmpty, "\(rig.sent)")
}

/// **5** Answering false falls through to the default paste: the bytes equal the hook-less paste's, plain and bracketed,
/// ESC still stripped. Mutation: answer false still returns early (nothing sent); strip nothing in `encodePaste`.
@MainActor @Test func returningFalseFallsThrough() async throws {
    let hook = Hook(false)
    let rig = try await rigWith(hook)
    let reference = try await rigWith(nil)
    for r in [rig, reference] { _ = r.window.window.clipboard.write("one\ntwo\u{1B}[31m"); pasteKey(r) }
    #expect(hook.calls.count == 1)
    #expect(rig.sent == [Array("one\ntwo[31m".utf8)], "\(rig.sent)")
    #expect(rig.sent == reference.sent)
    for r in [rig, reference] { await r.feedModes("\u{1B}[?2004h"); pasteKey(r) }
    #expect(rig.sentBytes == esc("[200~") + Array("one\ntwo[31m".utf8) + esc("[201~"), "\(rig.sentBytes)")
    #expect(rig.sent == reference.sent)
}

/// **6** With no hook the paste is today's: bytes through `encodePaste`. Mutation: a nil hook swallows the paste.
@MainActor @Test func nilKeepsTodaysBehaviour() async throws {
    let rig = try await rigWith(nil)
    _ = rig.window.window.clipboard.write("plain")
    pasteKey(rig)
    #expect(rig.sent == [Array("plain".utf8)], "\(rig.sent)")
}

/// **7** (cost) The hook costs nothing per frame: a window with a hooked terminal and one without do the same work on a
/// steady rebuilt frame, and on a keystroke into an editor beside it (the field is retained, closures are not compared).
/// Literals as `anIdleTerminalCostsAWindowNothingExtra`: 2 requests steady, 2 requests and 1 build for the keystroke.
/// Mutation: compare `onPaste` in the field's `==` (impossible), or read the hook in the surface element's identity
/// (the keystroke frame's requests rise to 4).
@MainActor @Test func aPasteHookCostsNothingPerFrame() async throws {
    func measure(_ hook: Hook?) async throws -> (steady: FrameWork, key: FrameWork, frames: Int) {
        let rig = try TermRig(extra: true, paste: hook?.closure)
        await rig.settle()
        try rig.window.focus(rig.window.element(identifier: "ed"))
        await rig.settle()
        for _ in 0..<3 { rig.window.window.setNeedsRedraw(); rig.window.tick() }
        let steady = rig.window.lastFrameWork
        for _ in 0..<2 { rig.window.window.setNeedsRedraw(); rig.window.tick() }
        rig.window.typeText("z")
        return (steady, rig.window.lastFrameWork, 1)
    }
    let with = try await measure(Hook(false)), without = try await measure(nil)
    #expect(with.steady.elementRequests == without.steady.elementRequests && without.steady.elementRequests == 2,
            "steady \(with.steady.elementRequests) vs \(without.steady.elementRequests)")
    #expect(with.key.elementRequests == without.key.elementRequests && with.key.builds == without.key.builds
            && with.key.retainedHits == without.key.retainedHits && without.key.elementRequests == 2 && without.key.builds == 1,
            "key frame with \(with.key.elementRequests) requests \(with.key.builds) builds \(with.key.retainedHits) hits; without \(without.key.elementRequests), \(without.key.builds), \(without.key.retainedHits)")
}
