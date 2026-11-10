@testable import MetalUI
import MetalUITesting
import Testing

// `MN-AM` (Alloy gap G26): an empty `.help` is no help. `@testable` for
// `Window.visibleTooltip`; the headless window, nothing sleeps.

/// MN-AM 1 — a menu item with `.help("")` presents `help == nil`, and a hover
/// over an element with `.help("")` shows no tooltip (a `.help("x")` beside it
/// does). Mutation: drop the `isEmpty` normalisation in
/// `ContextualAttachment.init` (both expectations redden).
@Test @MainActor func anEmptyHelpIsNilOnTheMenuItemAndShowsNoTooltip() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Button("Target") {}
                .contextMenu {
                    Button("Empty") {}.accessibilityIdentifier("e").help("")
                    Button("Real") {}.accessibilityIdentifier("r").help("Real help")
                }
            Text("Silent").help("")
        }
    }
    try window.rightClick(window.element(label: "Target"))
    let menu = try #require(window.presentedMenu)
    #expect(menu.item(accessibilityIdentifier: "e")?.help == nil)
    #expect(menu.item(accessibilityIdentifier: "r")?.help == "Real help")
    try window.dismissMenu()
    try window.hover(window.element(label: "Silent"))
    window.advance(by: 2)
    #expect(window.window.visibleTooltip == nil)
    #expect(try window.element(label: "Silent").hint == nil, "no accessibility help either")
}
