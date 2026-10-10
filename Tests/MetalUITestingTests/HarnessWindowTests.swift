import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Spec §4.1 tests 1.1–1.3 and 1.28–1.32: the headless window opens, presents,
// retries a failed frame, resizes, scales and closes through the real seams.

/// 1.1 — the window presents its first frame inside `App.openWindow`, headless,
/// and the scene holds the root's background at the window's size. Mutation:
/// `HeadlessWindowRenderer.beginFrame` answers `nil` (nothing presented).
@Test @MainActor func aTestWindowOpensAndPresentsItsFirstFrameHeadless() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(400), height: Pixels(300)).background(.accent)
    }
    #expect(window.framesDrawn == 1, "App.openWindow draws the first frame before it returns")
    #expect(window.platformWindow.headlessRenderer.framesPresented == 1)
    #expect(rects(window, height: 300).map(xywh) == [[0, 0, 400, 300]],
            "the root's background fills the 400 × 300 window")
}

/// 1.2 — an accessibility client active at open (the default option) has the
/// tree in the FIRST frame, and costs no extra frame: `framesDrawn` is 1 as in
/// 1.1. Mutation: drop the `onAccessibilityRequest` `didSet` activation.
@Test @MainActor func anAccessibilityClientActiveAtOpenHasTheTreeInTheFirstFrame() throws {
    let window = try harnessWindow {
        Text("Hello")
    }
    #expect(window.framesDrawn == 1, "activation at open draws no extra frame")
    let tree = try #require(window.platformWindow.publishedAccessibilityTrees.last,
                            "the first frame published a tree")
    #expect(!tree.nodes.isEmpty && !tree.roots.isEmpty)
    #expect(tree.nodes.values.contains { $0.label == "Hello" }, "the text is a node of the first tree")
}

/// 1.3 — a renderer that has no drawable for one tick leaves the window dirty,
/// and the next tick draws. Mutation: `failsNextFrame` ignored.
@Test @MainActor func aRendererThatFailsAFrameLeavesTheWindowDirtyAndTheNextTickDraws() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
    }
    let opened = window.framesDrawn
    window.platformWindow.headlessRenderer.failsNextFrame = true
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.framesDrawn == opened, "the failed tick presented nothing")
    #expect(window.window.needsRedraw, "and left the window dirty")
    window.tick()
    #expect(window.framesDrawn == opened + 1, "the next tick draws")
}

/// 1.28 — `resize(to:)` reflows the root: a greedy root named `fill` is the
/// window's size before and after. Mutation: `simulateResize` skips `onResize`.
@Test @MainActor func resizeReflowsTheRoot() throws {
    let window = try harnessWindow {
        Box().frame(maxWidth: .infinity, maxHeight: .infinity).background(.accent).id("fill")
    }
    #expect(try window.frame(ofID: "fill") == rect(0, 0, 400, 300))
    window.resize(to: sz(500, 200))
    #expect(try window.frame(ofID: "fill") == rect(0, 0, 500, 200))
}

/// 1.29 — at scale factor 2 the scene's rects are in device pixels: the 40 × 40
/// box centred in 400 × 300 at (180, 130) is (360, 260, 80, 80). Mutation: the
/// renderer's `beginFrame` answers 1.
@Test @MainActor func scaleFactorTwoDoublesTheScenesDeviceRects() throws {
    let window = try harnessWindow(scaleFactor: 2) {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
    }
    #expect(rects(window, height: 80).map(xywh) == [[360, 260, 80, 80]])
}

/// 1.30 — `close()` is the platform's close: every present `onDisappear` runs
/// once (`LC-J`), and a second close runs nothing. Mutation:
/// `HeadlessPlatformWindow.close()` does not fire `onClose`.
@Test @MainActor func closeRunsEveryOnDisappearOnce() throws {
    let log = HarnessLog()
    let window = try harnessWindow {
        VStack {
            Box().frame(width: Pixels(10), height: Pixels(10)).onDisappear { log.add("a") }
            Box().frame(width: Pixels(10), height: Pixels(10)).onDisappear { log.add("b") }
        }
    }
    #expect(log.entries.isEmpty)
    window.close()
    #expect(log.entries.sorted() == ["a", "b"], "each onDisappear ran once at close")
    #expect(window.platformWindow.isClosed)
    window.close()
    #expect(log.entries.count == 2, "a second close runs nothing")
}

/// 1.31 — a user's close request is asked of `Window.onCloseRequest`; a veto
/// keeps the window open and drawing (`AS-B`). Mutation:
/// `simulateCloseRequest` ignores the answer.
@Test @MainActor func aVetoedCloseRequestKeepsTheWindowOpen() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
    }
    var asked = 0
    window.window.onCloseRequest = { asked += 1; return .cancel }
    #expect(window.requestClose() == false)
    #expect(asked == 1)
    #expect(!window.platformWindow.isClosed)
    let drawn = window.framesDrawn
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.framesDrawn == drawn + 1, "the window still draws")
}

/// 1.32 — the last window's close ends the app through `Platform.terminate()`
/// (`AS-C` item 5). Mutation: `HeadlessPlatform.terminate()` not counted.
@Test @MainActor func theLastWindowsCloseTerminatesTheTestApp() throws {
    let window = try harnessWindow {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
    }
    #expect(window.testApp.platform.terminateCalls == 0)
    window.close()
    #expect(window.testApp.platform.terminateCalls == 1)
}
