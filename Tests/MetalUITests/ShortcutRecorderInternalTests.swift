import Testing
import Foundation
import Metal
import MetalUICore
import MetalUITesting
import MetalUIPlatform
@testable import MetalUI

// `ShortcutRecorder`'s internals (ruling `KF-AK`, record 366): the key table as a pure function, and that a window
// without a recorder registers no key capture (the capture stage's one gate, `keyCaptureCount`, stays 0 for an app
// that does not use one).

private func px(_ v: Float) -> Pixels { Pixels(v) }

private func press(_ key: String, _ modifiers: EventModifiers = [], unshifted: String = "") -> KeyPress {
    guard let first = key.first else { preconditionFailure("press needs a non-empty key") }
    return KeyPress(phase: .down, key: KeyEquivalent(first), characters: key, modifiers: modifiers, unshiftedKey: unshifted)
}

/// **I1** A window with no recorder has `keyCaptureCount == 0`; one with a recorder registers exactly one capture
/// layer (idle or not). Mutation: register the capture marker from `ShortcutRecorder` on every window (a global
/// `keyCapture`), or have `Component` machinery add one per frame (the 0 moves).
@MainActor @Test func aWindowWithoutARecorderRegistersNoKeyCapture() throws {
    let without = try TestWindow(size: Size(width: px(200), height: px(100))) { VStack { Text("none") } }
    for _ in 0..<3 { without.window.setNeedsRedraw(); without.advance(by: 0.05) }
    #expect(without.window.lastFocusRegistry.keyCaptureCount == 0)
    let with = try TestWindow(size: Size(width: px(200), height: px(100))) {
        VStack { ShortcutRecorder(nil, onRecord: { _ in }, onClear: {}, onCancel: {}) }
    }
    for _ in 0..<3 { with.window.setNeedsRedraw(); with.advance(by: 0.05) }
    #expect(with.window.lastFocusRegistry.keyCaptureCount == 1)
    withExtendedLifetime((without, with)) {}
}

/// **I2** The key table: every outcome for the keys the rules name. Mutation: swap the Escape and Delete arms; drop
/// the modifier test on either; treat `\u{19}` as a recordable key.
@MainActor @Test func theKeyTable() {
    typealias O = ShortcutRecorderOutcome
    #expect(O.of(press("\u{1b}")) == .cancel)
    #expect(O.of(press("\u{7f}")) == .clear)
    #expect(O.of(press("\u{f728}")) == .clear)
    #expect(O.of(press("\u{1b}", .option)) == .record(KeyboardShortcut(.escape, modifiers: .option)))
    #expect(O.of(press("\u{7f}", .command)) == .record(KeyboardShortcut(.delete, modifiers: .command)))
    #expect(O.of(press("\t")) == .pass && O.of(press("\t", .shift)) == .pass && O.of(press("\u{19}", .shift)) == .pass)
    #expect(O.of(press("\t", .control)) == .record(KeyboardShortcut(.tab, modifiers: .control)))
    #expect(O.of(press("\u{19}", [.shift, .control])) == .record(KeyboardShortcut(.tab, modifiers: [.shift, .control])))
    #expect(O.of(press("?", .shift, unshifted: "/")) == .record(KeyboardShortcut("/", modifiers: .shift)))
    #expect(O.of(press("/", .shift, unshifted: "/")) == .record(KeyboardShortcut("/", modifiers: .shift)))
    #expect(O.of(press("P", [.shift, .command], unshifted: "p")) == .record(KeyboardShortcut("p", modifiers: [.shift, .command])))
    #expect(O.of(press("?", .shift)) == .record(KeyboardShortcut("?", modifiers: .shift)), "no unshifted key: as reported")
    #expect(O.of(press("/", .command, unshifted: "/")) == .record(KeyboardShortcut("/", modifiers: .command)),
            "the base key is read only while Shift is held")
}
