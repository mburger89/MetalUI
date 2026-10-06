// Runtime probe: does one `RunLoop.main.run(mode: .default, before: .distantPast)`
// per iteration of a hand-written loop let a main-actor `Task` run when the loop
// itself is running INSIDE a main-actor job — the shape of an `async` main that
// calls `SDLPlatform.run()`, and of a Swift Testing `@MainActor` test that pumps
// the SDL loop? Evidence for ruling SV-… (the SDL main-queue drain, the plan's
// gap 10) in docs/superpowers/2026-10-04-platform-services-decisions.md.
// Extends swift-main-actor-task-loop.swift (record §76, LC-L), whose B2 measured
// the drain only from top-level code.
//
// HOW TO RUN:
//   macOS:  xcrun swiftc -parse-as-library docs/probes/swift-main-queue-drain-nested.swift -o /tmp/mqd && /tmp/mqd
//   Linux:  docker run --rm -v "$PWD/docs/probes:/p" swift:6.4-noble \
//             sh -c 'swiftc -parse-as-library /p/swift-main-queue-drain-nested.swift -o /tmp/mqd && /tmp/mqd'
//
// ARMS (each: a fresh `Task { @MainActor }` created, then 200 loop iterations
// of 1 ms; prints whether the task ran and resumed after a yield):
// (The top-level arms are swift-main-actor-task-loop.swift's B1/B2.)
// - J0 inside a main-actor job (after `await`ing into the main actor from an
//   async main): bare loop.
// - J1 inside a main-actor job: B2's drain per iteration — the arm the ruling
//   rests on.
// - J2 inside a main-actor job: the loop `await Task.yield()`s each iteration
//   (an async pump, the separating arm for J1).
// - J3 inside a main-actor job: `RunLoop.main.run(until: +1 ms)` per iteration
//   — B's P0, the shape AppKit's NSApp.run gives — so the answer for the
//   AppKit platform under an async main is measured beside SDL's.
//
// RECORDED 2026-10-03 by the platform-services design session. macOS 27.0,
// Apple Swift 6.4, compiled form, run twice (byte-identical); and
// swift:6.4-noble under Docker (OrbStack), compiled form. Exit 0, stderr
// empty, on both. The same Linux run re-ran swift-main-actor-task-loop.swift:
// P0 true, B1 false, B2 true — its recorded lines reproduced.
//
// OUTPUT, verbatim (macOS, then Linux; the arms print in J0, J1, J3, J2 order):
//
//   platform: Darwin
//   J0 inside a main-actor job, usleep(1000) per iteration: task ran=false resumed after yield=false
//   J1 inside a main-actor job, usleep(1000) + RunLoop.main.run(mode: .default, before: .distantPast): task ran=false resumed after yield=false
//   J3 inside a main-actor job, RunLoop.main.run(until: +1 ms) per iteration (the AppKit platform's shape): task ran=false resumed after yield=false
//   J2 inside a main-actor job, usleep(1000) + await Task.yield(): task ran=true resumed after yield=true
//
//   platform: Linux
//   J0 inside a main-actor job, usleep(1000) per iteration: task ran=false resumed after yield=false
//   J1 inside a main-actor job, usleep(1000) + RunLoop.main.run(mode: .default, before: .distantPast): task ran=false resumed after yield=false
//   J3 inside a main-actor job, RunLoop.main.run(until: +1 ms) per iteration (the AppKit platform's shape): task ran=false resumed after yield=false
//   J2 inside a main-actor job, usleep(1000) + await Task.yield(): task ran=true resumed after yield=true
//
// READING: B2's drain (one RunLoop pass per iteration) runs a main-actor task
// only when the loop runs OUTSIDE every main-actor job — top-level code, as
// `App.run()` is called from every MetalUI main.swift the scaffold writes. A
// loop running inside a job (an `async` main, a Swift Testing `@MainActor`
// test) starves it whatever it spins, on both OSes (J1), and so does the
// AppKit platform's run-loop shape there (J3) — the main queue is serial and
// is not drained re-entrantly from one of its own jobs. Only giving the job
// back (J2's `await`) lets the task run. So: the SDL drain fixes the shape
// every MetalUI app has, and a test of it must run the loop in a process of
// its own, not inside a test function.

import Foundation

@MainActor final class Flag { var ran = false; var resumed = false }

@MainActor func spawn() -> Flag {
    let flag = Flag()
    Task { @MainActor in
        flag.ran = true
        await Task.yield()
        flag.resumed = true
    }
    return flag
}

@MainActor func syncArm(_ name: String, _ iteration: () -> Void) {
    let flag = spawn()
    for _ in 0..<200 {
        iteration()
        if flag.resumed { break }
    }
    print("\(name): task ran=\(flag.ran) resumed after yield=\(flag.resumed)")
}

@MainActor func asyncArm(_ name: String) async {
    let flag = spawn()
    for _ in 0..<200 {
        usleep(1000)
        await Task.yield()
        if flag.resumed { break }
    }
    print("\(name): task ran=\(flag.ran) resumed after yield=\(flag.resumed)")
}

@main
struct Probe {
    static func main() async {
        #if canImport(Darwin)
        print("platform: Darwin")
        #else
        print("platform: Linux")
        #endif
        await MainActor.run {
            syncArm("J0 inside a main-actor job, usleep(1000) per iteration") { usleep(1000) }
            syncArm("J1 inside a main-actor job, usleep(1000) + RunLoop.main.run(mode: .default, before: .distantPast)") {
                usleep(1000)
                _ = RunLoop.main.run(mode: .default, before: .distantPast)
            }
        }
        await MainActor.run {
            syncArm("J3 inside a main-actor job, RunLoop.main.run(until: +1 ms) per iteration (the AppKit platform's shape)") {
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            }
        }
        await asyncArm("J2 inside a main-actor job, usleep(1000) + await Task.yield()")
        exit(0)
    }
}
