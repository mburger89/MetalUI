import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// C24 on every platform (Linux and Windows CI run `MetalUICrossPlatformTests`):
// the portable copy of test 1, over `PortableFakeWindow`. Mutation: as test 1
// (drop `|| resignsOnPress` from `focusOnPress`'s `region` predicate).

@MainActor
@Test func aResignRegionClearsFocusOnEveryPlatform() throws {
    let (window, platform) = try makePortableWindow {
        Box { Box().frame(width: Pixels(20), height: Pixels(20)).focusable() }
            .frame(width: Pixels(200), height: Pixels(200))
            .resignsFocusOnPress()
    }
    window.drawFrameIfNeeded()
    let id = try #require(window.lastFocusRegistry.tabOrder.first)
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "set up: focused")
    let corner = Point(x: Pixels(190), y: Pixels(190))
    platform.simulateInput(.mouseDown(MouseEvent(position: corner)))
    platform.simulateInput(.mouseUp(MouseEvent(position: corner)))
    #expect(window.focusedElement == nil, "the press on blank space inside the region resigned")
}
