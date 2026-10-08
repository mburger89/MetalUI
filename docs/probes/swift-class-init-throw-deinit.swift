// Probe: does a final class's `deinit` run when its designated `init` throws?
// Evidence for ruling WS-G (docs/superpowers/2026-10-08-accesskit-window-show-decisions.md).
//
// `SDLWindow.init(handle:offscreen:)` assigns `handle` and `id` first; every
// other stored property has a default. So any throw inside it (the renderer at
// cd84b0c, the show under WS-C) happens after the instance is fully
// initialised, and `deinit` — which calls `mui_window_destroy` — would run,
// before `openSDLWindow`'s `catch` destroys the same handle again.
//
// Arms:
//   A (positive control): throw after every stored property is set  -> deinit runs
//   B (separating):       throw before a defaultless property is set -> no deinit
//
// Run: xcrun swiftc -Onone docs/probes/swift-class-init-throw-deinit.swift -o /tmp/p && /tmp/p
//      (and -O). Recorded 2026-10-08, Swift 6.4, macOS 27 arm64, both -Onone and -O:
//
//   A: deinit 1
//   A: catch 1
//   B: catch 2
//
// Reading: arm A's deinit runs before the caller's catch; arm B's never does.
// SDLWindow is arm A's shape.
struct Failure: Error {}

final class FullyInitialised {
    let handle: Int
    var renderer: Int?          // defaulted, like SDLWindow.windowRenderer
    init(_ handle: Int) throws {
        self.handle = handle
        throw Failure()
    }
    deinit { print("A: deinit \(handle)") }
}

final class PartlyInitialised {
    let handle: Int
    let renderer: Int           // defaultless, not yet set when the throw comes
    init(_ handle: Int) throws {
        self.handle = handle
        throw Failure()
    }
    deinit { print("B: deinit \(handle)") }
}

do { _ = try FullyInitialised(1) } catch { print("A: catch 1") }
do { _ = try PartlyInitialised(2) } catch { print("B: catch 2") }
