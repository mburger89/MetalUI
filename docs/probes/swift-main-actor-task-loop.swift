// Language/runtime probe: does a main-actor `Task` progress while the main
// thread spins a hand-written event loop — the shape of `SDLPlatform.run()`
// (`while running { poll; tick }`, never entering `RunLoop`/`dispatchMain`)?
// Evidence for ruling LC-L (`.task` deferred or built) in
// docs/superpowers/2026-10-03-lifecycle-decisions.md.
//
// HOW TO RUN:
//   macOS:  xcrun swiftc docs/probes/swift-main-actor-task-loop.swift -o /tmp/mat && /tmp/mat
//   Linux:  docker run --rm -v "$PWD/docs/probes:/p" swift:6.4-noble \
//             sh -c 'swiftc /p/swift-main-actor-task-loop.swift -o /tmp/mat && /tmp/mat'
//
// ARMS (each a fresh Task created on the main actor, then a loop of 200
// iterations sleeping 1 ms each — 200 ms of a polling loop):
// - P0 positive control: the loop runs `RunLoop.main.run(until: now + 1 ms)`
//   — the AppKit platform's shape (NSApp.run drains the main queue).
// - B1 the SDL shape on Linux: the loop only sleeps (`usleep`), as
//   `mui_poll_event`/`mui_wait_event` do. The separating arm.
// - B2 a repair candidate: B1 plus one `RunLoop.main.run(mode: .default,
//   before: .distantPast)` per iteration (not built here — the owner's).
//
// RECORDED 2026-10-03 by the lifecycle design session. macOS 27.0.1, Apple
// Swift 6.4 (swiftlang-6.4.0.33.1), compiled form; and swift:6.4-noble under
// Docker (OrbStack), compiled form. Both, exit 0, stderr empty:
//
//   P0 RunLoop.main.run(until: +1 ms) per iteration: task ran=true resumed after yield=true
//   B1 usleep(1000) per iteration (SDLPlatform.run's shape): task ran=false resumed after yield=false
//   B2 usleep(1000) + RunLoop.main.run(mode: .default, before: .distantPast): task ran=true resumed after yield=true
//
// (each preceded by a `platform: Darwin` / `platform: Linux` line).
//
// READING: a main-actor Task created while the main thread runs a loop that
// never enters the run loop or `dispatchMain` does not run at all, on either
// OS (B1). `SDLPlatform.run()` is that loop on Linux (measured here) and on
// Windows (the same Swift loop; not measured — no Windows host) (on macOS
// SDL's own event pump goes through Cocoa, which this probe does not model).
// One `RunLoop.main.run(mode:before: .distantPast)` per iteration is enough
// to let it run (B2) — the repair the owner of `.task` would measure in
// `SDLPlatform.run()` itself.

import Foundation

@MainActor final class Flag { var ran = false; var resumed = false }

@MainActor func arm(_ name: String, _ iteration: () -> Void) {
    let flag = Flag()
    Task { @MainActor in
        flag.ran = true
        await Task.yield()
        flag.resumed = true
    }
    for _ in 0..<200 {
        iteration()
        if flag.resumed { break }
    }
    print("\(name): task ran=\(flag.ran) resumed after yield=\(flag.resumed)")
}

MainActor.assumeIsolated {
    #if canImport(Darwin)
    print("platform: Darwin")
    #else
    print("platform: Linux")
    #endif
    arm("P0 RunLoop.main.run(until: +1 ms) per iteration") {
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }
    arm("B1 usleep(1000) per iteration (SDLPlatform.run's shape)") {
        usleep(1000)
    }
    arm("B2 usleep(1000) + RunLoop.main.run(mode: .default, before: .distantPast)") {
        usleep(1000)
        _ = RunLoop.main.run(mode: .default, before: .distantPast)
    }
}
