import Foundation
@testable import JotterKit
import MetalUI
import Testing

// A Windows thread has a 1 MB stack, and a debug build of a large element tree is deep (MetalUI's
// own `everyProductionTreeBuildsOnAOneMegabyteThread` is the same check for the demo). Each screen
// here is its own `Component`, so no builder holds the whole tree.

/// Builds the app's trees on a thread of `stackSize` bytes and waits for it. The trees are
/// `@MainActor`; the cast strips the isolation so a secondary thread can call them.
///
/// **Only these trees**: `SidebarList`, `DetailArea`, `NoteRow`, `StatsView` and `PerDayLine` read
/// the model through a closure handed to the standard library (`first { }`, `flatMap`), which
/// checks its actor at run time and traps off the main thread - the same fact `SV-AK` and `HP-C`
/// record. They run on the main thread in the app, and in every window test above.
@MainActor
func buildEveryJotterTree() {
    let model = NotesModel.seeded(today: { 20_000 })
    _ = rootView(model: model)
    _ = JotterScreen(model: model).content
    _ = SidebarView(model: model).content
    _ = DetailEditor(model: model, note: model.notes[0]).content
    _ = DetailFooter(model: model).content
    _ = WordBars(model: model).content
}

func buildJotterTrees(onAThreadOf stackSize: Int) {
    nonisolated(unsafe) let build = unsafeBitCast(buildEveryJotterTree as @MainActor () -> Void, to: (() -> Void).self)
    let thread = Thread { build() }
    thread.stackSize = stackSize
    thread.start()
    while !thread.isFinished { Thread.sleep(forTimeInterval: 0.001) }
}

@Test func theRootTreeBuildsOnAOneMegabyteThread() async {
    await #expect(processExitsWith: .success) {
        buildJotterTrees(onAThreadOf: 1 << 20)
    }
}

#if canImport(Darwin)
/// Not vacuous: the same harness with a thread far too small fails (measured on macOS arm64, debug:
/// 64 KB is `SIGBUS`, 128 KB passes). Darwin only, because swift-corelibs keeps its 8 MB default for
/// a request this small.
@Test func aThreadTooSmallForTheTreesFailsTheSameHarness() async {
    let thread = Thread {}
    thread.stackSize = 64 * 1024
    #expect(thread.stackSize == 64 * 1024, "Foundation did not keep the stack request")
    await #expect(processExitsWith: .failure) {
        buildJotterTrees(onAThreadOf: 64 * 1024)
    }
}
#endif
