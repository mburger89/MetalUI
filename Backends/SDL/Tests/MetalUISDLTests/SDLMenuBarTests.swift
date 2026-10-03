import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL

// Menus, popovers and tooltips, lane 2, test S2.1 (ruling `MN-I` item 3; spec
// §3.11). SDL3 has no menu-bar API: `SDLPlatform.setMenuBar` records the bar
// and draws nothing — it never asks the bar for its content, and an open
// window's draw is unchanged.

/// **S2.1** (`MN-I` item 3). The bar is recorded (its `perform` reaches the
/// caller's callback) and never evaluated. Mutation: store nothing.
@MainActor
@Test func sdlRecordsTheMenuBarAndDrawsNothing() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    var contentCalls = 0
    var performed: [Int] = []
    platform.setMenuBar(PlatformMenuBar(content: {
        contentCalls += 1
        return [PlatformMenu(token: 0, title: "Demo", items: [PlatformMenuItem(id: 1, kind: .action, title: "Go")])]
    }, perform: { performed.append($0) }))
    let recorded = try #require(platform.menuBar, "the bar is recorded")
    #expect(contentCalls == 0, "SDL draws no menu bar, so it never asks for its content")
    recorded.perform(1)
    #expect(performed == [1], "the recorded bar is the one installed")
    #expect(contentCalls == 0)
}
