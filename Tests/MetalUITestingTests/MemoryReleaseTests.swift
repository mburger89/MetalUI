import MetalUI
import MetalUITesting
import Observation
import Testing

// PERF-c (`IV-S`, record 104): a released window frees what its content memos hold. An
// observation session's `onChange` lived in the observed model's registrar and held the memo
// entry (whose pristine content holds the model) strongly: model -> registrar -> closure ->
// handle -> entry -> pristine -> model, a cycle nothing broke while the model stayed unchanged.

@Observable @MainActor private final class ReleaseModel {
    var count = 0
}

private struct ReleaseCard: Component, Equatable {
    let id: Int
    let model: ReleaseModel
    nonisolated static func == (a: ReleaseCard, b: ReleaseCard) -> Bool { a.id == b.id && a.model === b.model }
    var content: some ElementGroup {
        Text("card \(id) \(model.count)").frame(width: 120, height: 20)
    }
}

private struct ReleasePlain: Component {
    let id: Int
    let model: ReleaseModel
    var content: some ElementGroup {
        Text("plain \(id) \(model.count)").frame(width: 120, height: 20)
    }
}

private struct ReleaseWeak {
    weak var model: ReleaseModel?
    weak var testWindow: TestWindow?
    weak var window: Window?
    weak var store: ContentMemoStore?
}

/// Builds a window over `cards` occurrences, draws `frames` frames, and returns weak refs with
/// nothing else holding the window or the model.
@MainActor private func openAndRelease(equatable: Bool, retain: Bool, frames: Int, cards: Int = 4) throws -> ReleaseWeak {
    let model = ReleaseModel()
    var weakRefs = ReleaseWeak()
    do {
        let testWindow = try TestWindow(size: sz(400, 300), textSystem: harnessTextSystem) {
            VStack {
                ForEach(0..<cards, id: \.self) { i in
                    if equatable { ReleaseCard(id: i, model: model).equatable() } else { ReleasePlain(id: i, model: model) }
                }
            }
        }
        testWindow.window.testingContentMemos.retainsSubtrees = retain
        for _ in 0..<frames {
            testWindow.window.setNeedsRedraw()
            testWindow.tick()
        }
        weakRefs.model = model
        weakRefs.testWindow = testWindow
        weakRefs.window = testWindow.window
        weakRefs.store = testWindow.window.testingContentMemos
        testWindow.close()
    }
    return weakRefs
}

@MainActor private func released(_ refs: ReleaseWeak, equatable: Bool) {
    #expect(refs.testWindow == nil, "the TestWindow is freed")
    #expect(refs.window == nil, "the Window is freed")
    #expect(refs.store == nil, "the ContentMemoStore is freed")
    #expect(refs.model == nil, "the model is freed")
}

@MainActor @Suite(.serialized) struct MemoryReleaseTests {
    @Test func aPlainComponentReleasesItsWindowAndModel() throws {
        let refs = try openAndRelease(equatable: false, retain: false, frames: 3)
        released(refs, equatable: false)
    }

    @Test func anEquatableComponentReadingAModelReleasesIt() throws {
        let refs = try openAndRelease(equatable: true, retain: false, frames: 3)
        released(refs, equatable: true)
    }

    @Test func anEquatableComponentWithRetentionReleasesItsWindowAndModel() throws {
        let refs = try openAndRelease(equatable: true, retain: true, frames: 12)
        released(refs, equatable: true)
    }

    @Test func aModelWriteStillDirtiesALiveEquatableWindow() async throws {
        let model = ReleaseModel()
        let testWindow = try TestWindow(size: sz(400, 300), textSystem: harnessTextSystem) {
            VStack { ReleaseCard(id: 0, model: model).equatable() }
        }
        testWindow.tick(); testWindow.tick()
        let before = testWindow.window.framesDrawn
        model.count += 1
        await rsSettle()   // off macOS the observation hop is asynchronous (HT-, IV-Q): let it land before the tick
        testWindow.tick()
        #expect(testWindow.window.framesDrawn > before)
    }
}
