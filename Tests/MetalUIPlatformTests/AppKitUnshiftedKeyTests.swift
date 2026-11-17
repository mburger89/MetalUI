import Testing
import Carbon.HIToolbox
@testable import MetalUIAppKit

// `KF-AL`: the layout's unshifted character for a key code, which
// `charactersIgnoringModifiers` is not (it keeps Shift's effect).

/// The current layout's input-source ID.
@MainActor
private func currentLayoutID() -> String {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

/// On a US or ABC layout key codes 44, 18 and 35 are "/", "1" and "p" with no
/// modifier, and Return (36) and the arrows are no base key. Skipped (passes
/// vacuously, recorded) on any other layout, since the answer is the layout's.
/// Mutation: `UCKeyTranslate`'s modifier state 0 becomes 2 (Shift) — "/" reads
/// "?" and the test reddens.
@MainActor
@Test func theLayoutsUnshiftedKeyIsTheBaseCharacter() throws {
    let layout = currentLayoutID()
    guard layout.hasSuffix(".US") || layout.hasSuffix(".ABC") else {
        Issue.record("layout \(layout) is not US/ABC: the unshifted-key arm was not observed")
        return
    }
    #expect(UnshiftedKey.character(forKeyCode: 44) == "/")
    #expect(UnshiftedKey.character(forKeyCode: 18) == "1")
    #expect(UnshiftedKey.character(forKeyCode: 35) == "p")
    #expect(UnshiftedKey.character(forKeyCode: 36) == "", "Return is a control character, not a base key")
    #expect(UnshiftedKey.character(forKeyCode: 126) == "", "an arrow is private-use, not a base key")
}
