import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// The SDL half of the link seam (`LI-D`): `SDLWindow.openURL(_:)` refuses a string with no scheme and hands any other to
// `SDL_OpenURL` (`mui_open_url`). **No test here calls `SDL_OpenURL`**: every window replaces `openURLRequest`, because the
// native call would launch the user's browser (and the offscreen driver has no handler to answer it).

@MainActor
private func linkWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI open URL test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()
    return (platform, window)
}

/// The scheme test is RFC 3986's: a letter, then letters, digits, `+`, `-`, `.`, then `:`. Mutation: accept any string
/// containing a colon (`1http://x`, `:x` and a leading `-` redden).
@MainActor
@Test func aStringIsAnAbsoluteURLOnlyWithASyntacticScheme() {
    for accepted in ["https://x.org", "HTTP://X", "mailto:a@b.org", "a+b-c.d://x", "probe://x", "x:"] {
        #expect(SDLWindow.hasURLScheme(accepted), "\"\(accepted)\" has a scheme")
    }
    for refused in ["", "example.com", ":x", "1http://x", "-x://y", "a b://c", "//host/p", "/path:with:colons", "x y:z"] {
        #expect(!SDLWindow.hasURLScheme(refused), "\"\(refused)\" has none")
    }
}

/// An accepted URL reaches the request seam once, as written, and is recorded; a refused one reaches nothing and the
/// answer is `false`; the seam's answer is the call's. Mutation: send a scheme-less string on.
@MainActor
@Test func sdlOpenURLSendsAbsoluteURLsToTheSeamAndRefusesTheRest() throws {
    let (platform, window) = try linkWindow()
    _ = platform
    var sent: [String] = []
    window.openURLRequest = { sent.append($0); return true }
    #expect(window.openURL("https://x.org/a?b=c"))
    #expect(!window.openURL("example.com"))
    #expect(!window.openURL("-flag"))
    #expect(sent == ["https://x.org/a?b=c"], "\(sent)")
    #expect(window.openedURLRequests == ["https://x.org/a?b=c"])
    window.openURLRequest = { _ in false }
    #expect(!window.openURL("mailto:a@b.org"), "the seam's refusal is the answer")
}
