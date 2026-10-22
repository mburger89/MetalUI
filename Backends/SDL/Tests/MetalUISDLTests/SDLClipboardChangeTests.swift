// SDL's clipboard change event (ruling CP-G; probe `docs/probes/sdl-clipboard-update.c`; spec test 1.10): every own set, text
// set and clear posts one `SDL_EVENT_CLIPBOARD_UPDATE` with no window, which `SDLPlatform` turns into the window's handler
// call. Events need no presented frame, so the offscreen Linux image runs it.
import Foundation
import MetalUIPlatform
import MetalUICore
import SDLBridge
import Testing
@testable import MetalUISDL

@MainActor
private final class Counter { var count = 0 }

@Suite(.serialized)
@MainActor
struct SDLClipboardChangeTests {
    /// 1.10: an own typed set, a text set and a clear each call the handler once, on the pump; a removed handler hears nothing.
    /// Mutation: drop the `MUI_EVENT_CLIPBOARD` case in `SDLPlatform.dispatch`.
    @Test func anOwnSetATextSetAndAClearEachCallTheHandlerOnce() throws {
        #if os(macOS)
        armMainRunLoopExitCheck()
        #endif
        let platform = try SDLPlatform(hiddenWindows: true)
        let window = try platform.openSDLWindow(title: "MetalUI clipboard change test",
                                                size: Size(width: Pixels(320), height: Pixels(200)))
        defer { mui_clipboard_clear() }
        mui_clipboard_clear()
        platform.pumpEvents()   // drain what the setup posted
        let counter = Counter()
        window.setClipboardChangeHandler { counter.count += 1 }

        #expect(window.writeClipboard(items: [ClipboardItem(payloads: [
            ClipboardPayload(type: PasteboardType(identifier: "com.acme.graph"), bytes: .now([1, 2, 3]))])]))
        platform.pumpEvents()
        #expect(counter.count == 1, "a typed own set")

        window.writeClipboard("hello")
        platform.pumpEvents()
        #expect(counter.count == 2, "a text set")

        mui_clipboard_clear()
        platform.pumpEvents()
        #expect(counter.count == 3, "a clear")

        platform.pumpEvents()
        #expect(counter.count == 3, "no event, no call")
        window.setClipboardChangeHandler(nil)
        window.writeClipboard("again")
        platform.pumpEvents()
        #expect(counter.count == 3, "a removed handler")
    }
}
