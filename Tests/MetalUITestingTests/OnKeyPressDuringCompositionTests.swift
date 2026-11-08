import MetalUI
import Foundation
import Observation
import MetalUITesting
import Testing

// `KF-AB` (Alloy G14): on macOS a key reaches `Window` only when AppKit's input context declined it, and
// SwiftUI then delivers it to `onKeyPress` even with marked text (probe `swiftui-onkeypress-marked-text.swift`).
// So `Window` does NOT gate `onKeyPress` on a composition; the SDL backend suppresses keys instead. This pins
// the SwiftUI-aligned half. Mutation: gate `dispatchKeyPress` on the focused field's composition and the test reddens.

@Observable @MainActor private final class PressModel {
    var text = ""
    var keys: [String] = []
}

@Test @MainActor func aKeyThatReachesWindowDuringACompositionStillReachesOnKeyPress() throws {
    let m = PressModel()
    let window = try harnessWindow {
        TextField("t", text: Binding(get: { m.text }, set: { m.text = $0 }))
            .accessibilityIdentifier("field")
            .onKeyPress(keys: [.downArrow, .escape]) { press in
                m.keys.append(String(press.key.character.unicodeScalars.first!.value, radix: 16))
                return .ignored
            }
    }
    window.tick(); window.tick()
    try window.click(try window.element(identifier: "field"))
    window.typeKey(.downArrow)
    #expect(m.keys == ["f701"], "no composition: delivered")
    #expect(window.setMarkedText("ni"))
    window.typeKey(.downArrow)
    window.typeKey(.escape)
    #expect(m.keys == ["f701", "f701", "1b"], "composing: still delivered, as SwiftUI does: \(m.keys)")
    #expect(window.commitMarkedText())
    window.typeKey(.downArrow)
    #expect(m.keys.count == 4)
}
