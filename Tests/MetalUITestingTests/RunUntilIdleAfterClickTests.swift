import MetalUI
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
