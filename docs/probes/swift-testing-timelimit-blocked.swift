// Probe TL-1 (item HG, record 154): does Swift Testing's `.timeLimit(.minutes(1))` end a test whose body is blocked?
// Run: a scratch package with `.testTarget(name: "TLTests")` holding this file (it is NOT part of any package here);
//   swift test --filter "S/blockedOnMain"        (main-actor body blocked on a DispatchSemaphore)
//   swift test --filter "S2"                     (async body awaiting a continuation nobody resumes)
// Recorded 2026-10-24, Xcode 6.4.2 toolchain, swift-testing 1.0 (2403), macOS 27, arm64:
//   blockedOnMain: the helper was still alive and asleep at 4 minutes (sample: main thread in
//     _dispatch_semaphore_wait_slow under S.blockedOnMain()), no issue recorded, no summary line.
//   blockedOffMain (S2): still alive at 3m47s, no issue recorded, no summary line.
//   Separating arm: the same helper died on SIGTERM at once (a process with no SDL), and after `kill -9` of
//     the parent `swift test` it was re-parented to PID 1 and kept sleeping (the orphan path).
// Reading: a time limit cannot abandon a body that never returns; it is not a hang cure for blocking waits.
import Testing
import Foundation
@MainActor @Suite(.serialized) struct S {
    @Test(.timeLimit(.minutes(1))) func blockedOnMain() {
        let s = DispatchSemaphore(value: 0); s.wait()
    }
    @Test func after() { print("AFTER RAN") }
}
@Suite(.serialized) struct S2 {
    @Test(.timeLimit(.minutes(1))) func blockedOffMain() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in }
    }
}
