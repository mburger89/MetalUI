import MetalUI
import MetalUITesting
import XCTest

// Spec §4.1 test 1.38: the harness from XCTest (ruling `HT-A` item 3) — every
// API is `@MainActor` and synchronous but `runUntilIdle()`, so an XCTest
// method isolated to the main actor drives it as a swift-testing one does.

/// A box that counts its clicks.
@MainActor private final class XCTestClicks {
    var count = 0
}

final class XCTestHarnessTests: XCTestCase {
    /// 1.38 — a click runs an `onClick` from an XCTest method. Mutation: as 1.4
    /// (`click` sends only `.mouseDown`).
    @MainActor func testAClickRunsAnOnClickFromXCTest() async throws {
        let clicks = XCTestClicks()
        let window = try TestWindow(size: Size(width: Pixels(400), height: Pixels(300)),
                                    textSystem: harnessTextSystem) {
            Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent).onClick { clicks.count += 1 }
        }
        window.click(at: Point(x: Pixels(200), y: Pixels(150)))
        try await window.runUntilIdle()
        XCTAssertEqual(clicks.count, 1)
    }
}
