import Foundation
import Testing
import MetalUIDemoContent

// Windows threads get a 1 MB stack by default — the main thread (the linker's
// `/STACK` default; `Backends/SDL`'s `DemoCapture.exe` builds the demo there)
// and the Swift Testing worker that runs
// `theDemoFrameMatchesTheValuesRecordedOnMacOS` alike — where macOS's and
// Linux's main threads get 8 MB. In a debug build a builder closure reserves a
// slot for every temporary it holds, and the demo's tree value is 35 KB, so at
// `b9a5d7f` (plan task 7 stage 8's `.frame` layers) building `demoContent()`
// overflowed both Windows jobs. Smallest thread stack that builds it on macOS
// arm64: 896 KB at `85217e3`, 1200 KB at `b9a5d7f`, 528 KB since the fix (the
// note after `demoContent()`; record §50, "2026-09-24 — Windows stack
// budget"). This builds every production tree on a 1 MB thread on every
// platform, inside an exit test so that an overflow fails this test rather
// than killing the run. Red at `b9a5d7f`: `.signal(SIGBUS)` on macOS arm64,
// `.signal(SIGSEGV)` in a `swift:6.4-noble` aarch64 container.
//
// Only the BUILD runs on the small thread: rendering reaches `Text`'s and
// `ProposalText`'s unguarded `MainActor.assumeIsolated`, which traps off the
// main thread on Apple platforms and Linux. The build is where both Windows
// crashes were, and the demo-frame pin renders on Windows' own 1 MB worker.

/// Every tree `runDemo` (and `Backends/SDL`'s `DemoCapture`) can open.
@MainActor
private func buildEveryProductionTree() {
    _ = demoContent()
    _ = nativeLayoutPreviewContent()
    _ = textInputDemoContent()
}

/// Windows' default thread stack size.
let windowsDefaultStackSize = 1 << 20

/// Builds every production tree on a new thread of `stackSize` bytes and waits
/// for it. The trees are `@MainActor`; the cast strips the isolation so a
/// secondary thread can call them — nothing they build checks its executor at
/// run time (only layout's `assumeIsolated` does, which this never reaches).
func buildEveryProductionTree(onAThreadOf stackSize: Int) {
    nonisolated(unsafe) let build = unsafeBitCast(buildEveryProductionTree as @MainActor () -> Void,
                                                  to: (() -> Void).self)
    let thread = Thread { build() }
    thread.stackSize = stackSize
    thread.start()
    while !thread.isFinished { Thread.sleep(forTimeInterval: 0.001) }
}

/// Too small for the demo on every platform (it needs 528 KB on macOS arm64),
/// and large enough that every `Foundation` honours it: swift-corelibs
/// silently keeps its 8 MB default for a request of 64 KB (measured in a
/// `swift:6.4-noble` container: `stackSize` read back 8388608, and a recursion
/// reached 8184 KB), which made a 64 KB arm of this harness pass on Linux.
let tooSmallForTheDemo = 256 * 1024

@Test func everyProductionTreeBuildsOnAOneMegabyteThread() async {
    await #expect(processExitsWith: .success) {
        buildEveryProductionTree(onAThreadOf: windowsDefaultStackSize)
    }
}

/// Not vacuous: the same harness with a thread too small for the demo fails,
/// so the test above can see an overflow at all — and both sizes are the ones
/// the thread will really get, not a request `Foundation` drops.
@Test func aThreadTooSmallForTheDemoFailsTheSameHarness() async {
    for size in [windowsDefaultStackSize, tooSmallForTheDemo] {
        let thread = Thread {}
        thread.stackSize = size
        #expect(thread.stackSize == size, "Foundation did not keep a \(size)-byte stack request")
    }
    await #expect(processExitsWith: .failure) {
        buildEveryProductionTree(onAThreadOf: tooSmallForTheDemo)
    }
}
