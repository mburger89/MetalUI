import Foundation
import Testing
import MetalUICore
import SDLBridge
@_spi(Checks) @testable import MetalUISDL

// AccessKit before the first show (item C11; rulings `WS-B`, `WS-C`, `WS-D`,
// `WS-G`; spec §5). AccessKit's Windows adapter panics when it is made on a
// window that is already visible (`accesskit_windows` `subclass.rs:168`), and
// at `cd84b0c` `SDL_CreateWindow` showed every non-hidden window before the
// adapter existed. Every SDL window is now created hidden; the adapter, then
// `SDL_ShowWindow` (unless `hiddenWindows`), then the renderer.
//
// The order is read from SDL's own flag (`mui_window_is_shown`), which tracks
// the show on every driver — native visibility does not change in the Windows
// VM's session 0 (`WS-D`). Every window here renders offscreen, so no test
// claims a swapchain (the VM over SSH, the image's offscreen driver).

/// The platform for one test: `hiddenWindows: hidden`, offscreen renderers.
@MainActor
private func platform(hidden: Bool) throws -> SDLPlatform {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLPlatform(hiddenWindows: hidden, offscreenRenderers: true)
}

/// A stubbed show's calls, observed from the test (a box: the stub is a
/// main-actor closure and cannot mutate a captured local).
@MainActor
private final class ShowCalls {
    var windowIDs: [UInt32] = []
}

private let visibleWindowTestEnabled: Bool = {
    #if os(macOS)
    // macOS's adapter checks nothing, and this test puts a window on screen.
    return ProcessInfo.processInfo.environment["METALUI_RUN_VISIBLE_SDL_WINDOW_TEST"] == "1"
    #else
    return true
    #endif
}()

/// **T1** (`WS-B`). A non-hidden window is created hidden; its adapter is made
/// while it is hidden, then it is shown, then its renderer is made. The show
/// is stubbed, so nothing reaches the screen and the renderer step reads the
/// window still hidden. Mutations M1 (create with `hidden` again), M2 (adapter
/// after the show), M4 (renderer before the show).
@MainActor
@Test func aWindowIsCreatedHiddenAndItsAdapterPrecedesTheShow() throws {
    let platform = try platform(hidden: false)
    let calls = ShowCalls()
    platform.showWindow = { raw in
        calls.windowIDs.append(mui_window_id(raw))
        return true
    }
    let window = try platform.openSDLWindow(title: "T1", size: Size(width: 120, height: 80))
    #expect(window.openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false),
                                    .shown, .renderer(windowShown: false)])
    #expect(calls.windowIDs == [window.id], "shown once, this window")
    #expect(window.isAccessibilityConnected)
}

/// **T2** (`WS-E`). The real `SDL_ShowWindow`: the window becomes shown only
/// after its adapter exists, and is shown once open. On GitHub's interactive
/// Windows runner the `cd84b0c` order aborts this process (the C11 panic).
/// Off macOS always; on macOS only with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1`.
/// Mutations M1, M2.
@MainActor
@Test(.enabled(if: visibleWindowTestEnabled, "puts a window on screen; set METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1"))
func aShownWindowBecomesVisibleOnlyAfterItsAccessKitAdapter() throws {
    let platform = try platform(hidden: false)
    let window = try platform.openSDLWindow(title: "T2", size: Size(width: 120, height: 80))
    #expect(window.openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false),
                                    .shown, .renderer(windowShown: true)])
    #expect(mui_window_is_shown(window.rawHandle), "a non-hidden platform's window is shown once open")
    #expect(window.isAccessibilityConnected)
}

/// **T3** (`WS-B` step 3). A `hiddenWindows` platform never shows its window:
/// the show is never called and SDL's flag stays hidden. Mutation M3 (show
/// regardless of `hiddenWindows`).
@MainActor
@Test func aHiddenWindowsPlatformNeverShowsItsWindow() throws {
    let platform = try platform(hidden: true)
    platform.showWindow = { _ in
        Issue.record("a hiddenWindows platform showed its window")
        return true
    }
    let window = try platform.openSDLWindow(title: "T3", size: Size(width: 120, height: 80))
    #expect(window.openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false),
                                    .renderer(windowShown: false)])
    #expect(!mui_window_is_shown(window.rawHandle))
}

/// **T4** (`WS-C`, `WS-G`). A show that fails throws `SDL_ShowWindow`'s error,
/// and the window it abandons is destroyed (by `SDLWindow`'s `deinit`, once)
/// and never registered; the platform still opens the next window. Mutations
/// M5 (ignore the show's answer), M6 (`deinit` without `mui_window_destroy`).
@MainActor
@Test func aWindowWhoseShowFailsIsDestroyedAndNotOpened() throws {
    let platform = try platform(hidden: false)
    let calls = ShowCalls()
    platform.showWindow = { raw in
        calls.windowIDs.append(mui_window_id(raw))
        return false
    }
    var thrown: (any Error)?
    do {
        _ = try platform.openSDLWindow(title: "T4", size: Size(width: 120, height: 80))
    } catch {
        thrown = error
    }
    let error = try #require(thrown as? SDLPlatformError, "a failed show throws SDLPlatformError")
    #expect(error.description.hasPrefix("SDL_ShowWindow"), "\(error.description)")
    let captured = try #require(calls.windowIDs.first, "the show was asked for")
    #expect(calls.windowIDs.count == 1)
    #expect(!mui_window_id_is_open(captured), "the abandoned window is destroyed")
    #expect(platform.openWindowCount == 0, "the abandoned window is not registered")

    platform.showWindow = { _ in true }
    let next = try platform.openSDLWindow(title: "T4 again", size: Size(width: 120, height: 80))
    #expect(platform.openWindowCount == 1)
    #expect(mui_window_id_is_open(next.id))
}
