import Foundation
@testable import MetalUI
import MetalUIDemoContent
import MetalUITesting
import MetalUITestSupport
import Testing

// Record 435 (`HP-P`): in a release build the first frame's stack is dominated by the constructed tree value, at about six times its size in the composing frames
// (the default demo's 51,680-byte root cost 1,107,040 bytes below `Window.drawFrameIfNeeded`, over the 1 MiB a Windows main thread has). A large static tree is split at
// `Component` boundaries, which are empty values until layout builds their `content` one at a time.

/// **1** The default demo's root value is a few kilobytes, not the whole tree. Measured on macOS arm64: 51,680 bytes before, 4,720 after (`Component`s for the header, sidebar, main pane, hero stack and
/// scroll box; the body row and the root column stay values, they hold only empty components and the hairline). The ceiling is a little above the reading and only ever goes down.
/// **Mutations:** the whole file as on master reads 51,680; `demoBody()` holding `DemoSidebar().content` inline reads over the ceiling too.
@Test @MainActor func theDefaultDemosRootValueIsAFewKilobytes() {
    let size = MemoryLayout.size(ofValue: demoContent())
    #expect(size <= 5_120, "the default demo's root value is \(size) bytes")
}

/// **2** An idle frame of the default demo costs what it did before the sections became components: the same 87 element requests, and 16 allocations more of 19,952 (a component's layout record is one
/// heap box, the price record 427 named). Measured on macOS arm64 with the demo as on master (19,952) and as here (19,968). The allocation ceiling only goes down.
@Test @MainActor func anIdleFrameOfTheDefaultDemoCostsWhatItDid() throws {
    let w = try harnessWindow(size: sz(1100, 700)) { demoContent() }
    for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
    #if canImport(Darwin)
    let allocations = try #require(countAllocations { w.window.setNeedsRedraw(); w.tick() })
    let requests = w.lastFrameWork.elementRequests
    #expect(requests == 87 && allocations <= 19_968, "an idle frame: \(allocations) allocations, \(requests) requests")
    #endif
}
