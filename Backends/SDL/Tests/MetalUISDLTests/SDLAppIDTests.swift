import Foundation
import Testing
import SDLBridge
@testable import MetalUISDL

// The SDL application id (item XP-G13, rulings `AP-A`...`AP-F`; spec
// `docs/superpowers/specs/2026-10-21-sdl-app-id-design.md` §5). SDL is refcounted and other tests leave it
// initialised, so a read-back of `SDL_GetHint` after init could not prove the hint came *before* init: the
// pins read the bridge's C recorders (`mui_app_id_*`, written in the production path, `AP-E`), which order
// the hint's call before `SDL_Init`'s and record the value MetalUI passed (never the process environment's
// `SDL_APP_ID`, `AP-F`). The recorders are process-global, so the tests live in one serialized suite and
// compare deltas. Every test that creates an `SDLPlatform` arms `armMainRunLoopExitCheck()` on macOS.

@MainActor
private func armed() {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
}

@MainActor
private func lastID() -> String { String(cString: mui_app_id_last()) }

private func uniqueID() -> String { "com.example.apid" + UUID().uuidString.prefix(8).lowercased() }

@MainActor
@Suite(.serialized)
struct SDLAppIDTests {
    /// 1. An explicit option reaches SDL's hint, and the hint call precedes `SDL_Init`.
    @Test func explicitOptionIsSetBeforeInit() throws {
        armed()
        let before = mui_app_id_set_count()
        let id = uniqueID()
        _ = try SDLPlatform(options: .init(hidesWindows: true, applicationID: id))
        #expect(mui_app_id_set_count() == before + 1)
        #expect(lastID() == id)
        #expect(mui_app_id_hint_precedes_init())
    }

    /// 2. `launchingSingleInstance(id:)` supplies the id when the option is `nil`.
    @Test func singleInstanceIdDefaultsTheApplicationID() throws {
        armed()
        let before = mui_app_id_set_count()
        let id = uniqueID()
        let platform = try SDLPlatform.launchingSingleInstance(id: id, forwarding: [], options: .headless)
        _ = try #require(platform, "the first launch of a unique id must be primary")
        #expect(mui_app_id_set_count() == before + 1)
        #expect(lastID() == id)
        #expect(mui_app_id_hint_precedes_init())
    }

    /// 3. With neither, no hint is set (today's behaviour).
    @Test func neitherLeavesTheHintUntouched() throws {
        armed()
        let before = mui_app_id_set_count()
        _ = try SDLPlatform(options: .headless)
        #expect(mui_app_id_set_count() == before)
    }

    /// 4. An explicit option wins over the single-instance id.
    @Test func explicitOptionBeatsTheSingleInstanceId() throws {
        armed()
        let before = mui_app_id_set_count()
        let explicit = uniqueID()
        var options = SDLPlatform.Options.headless
        options.applicationID = explicit
        let platform = try SDLPlatform.launchingSingleInstance(id: uniqueID(), forwarding: [], options: options)
        _ = try #require(platform)
        #expect(mui_app_id_set_count() == before + 1)
        #expect(lastID() == explicit)
    }

    /// 5. Empty, whitespace-only and NUL-bearing values are ignored, never a trap.
    @Test(arguments: ["", "  ", "a\u{0}b"])
    func unusableValuesAreIgnored(_ value: String) throws {
        armed()
        let before = mui_app_id_set_count()
        _ = try SDLPlatform(options: .init(hidesWindows: true, rendersOffscreen: true, applicationID: value))
        #expect(mui_app_id_set_count() == before)
    }
}
