import MetalUI
import Observation
import MetalUITesting
import Testing

// Item C29 (ruling family `RU-`): `runUntilIdle()` after a `Button` click must
// return on every platform. Plain imports, portable; runs on Linux in the
// swift:6.4-noble image.

/// 3.1 — a Button is clicked through the tree; `runUntilIdle()` returns.
@Test @MainActor func runUntilIdleReturnsAfterAButtonClick() async throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        Button("Go") { log.add("go") }.frame(width: Pixels(80), height: Pixels(30)).accessibilityIdentifier("go")
    }
    try window.click(try window.element(identifier: "go"))
    #expect(log.entries == ["go"])
    try await window.runUntilIdle()
}

@Observable @MainActor private final class ClickWide { var wide = false }

/// 3.2 — the fix does not swallow a real change: after a click (so an
/// observation session is armed behind a drawn frame), an `@Observable` write
/// is still drawn by `runUntilIdle()` — the box goes 10 → 70 wide — and the
/// window then goes idle. Mutation: the `defer`'s `flushingThread.set(nil)`
/// removed (the main thread stays "flushing" and its own write is dropped).
@Test @MainActor func anObservableWriteAfterAClickIsStillDrawnAndThenIdle() async throws {
    let model = ClickWide()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Button("Go") {}.frame(width: Pixels(80), height: Pixels(30)).accessibilityIdentifier("go")
            Box().frame(width: Pixels(model.wide ? 70 : 10), height: Pixels(10)).background(.accent)
        }
    }
    try window.click(try window.element(identifier: "go"))
    try await window.runUntilIdle()
    #expect(rects(window, height: 10).map { $0.bounds.size.width } == [10])
    model.wide = true
    try await window.runUntilIdle()
    #expect(rects(window, height: 10).map { $0.bounds.size.width } == [70], "the write was drawn")
}
