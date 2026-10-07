import Testing
import Metal
import Observation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI
@testable import MetalUIText

// `.task` and `.task(id:)` (rulings `PX-F`, `PX-G`, `PX-L`;
// `docs/superpowers/2026-10-07-portable-app-decisions.md`; spec
// `docs/superpowers/specs/2026-10-07-portable-app-design.md` §4.3, tests
// 3.1–3.19). SwiftUI's side is `docs/probes/swiftui-task.swift`; each test
// names the arm it follows.
//
// **No test sleeps.** Windows are `makeFakeWindowOnDefaultDevice` windows
// driven by `drawFrameIfNeeded()` (the lifecycle harness, `LC-K`: `LCLog`,
// `LCModel`, `lcLeaf`, `lcWindow`, `lcWidth` from `LifecycleTests.swift`),
// transitions by `simulateTick(timestamp:)`. A task's later progress is
// awaited by counting `Task.yield()`s up to a bound (`pumpMainActor`), and a
// task meant to be cancelled waits on `withTaskCancellationHandler` and a
// continuation its `onCancel` resumes (`untilCancelled`) — never on a sleep a
// broken cancel would leave hanging (`PX-L` item 1). Red before, for every
// test here: the file does not compile at `359444e` (no `task`).

// MARK: - Harness

/// Yields the main actor until `condition` holds or `maxYields` yields have
/// passed; answers whether it holds. Counts turns, never time.
@MainActor func pumpMainActor(until condition: () -> Bool, maxYields: Int = 1000) async -> Bool {
    var yields = 0
    while !condition(), yields < maxYields {
        await Task.yield()
        yields += 1
    }
    return condition()
}

/// The continuation a cancellable wait parks on, resumed by its `onCancel`.
@MainActor private final class CancelGate {
    var continuation: CheckedContinuation<Void, Never>?
}

/// Suspends the calling task until it is cancelled. `onCancel` runs inside
/// the `cancel()` call — synchronously, on the main thread, since every
/// cancel the window issues is issued there — so a log line it adds records
/// where the cancel CALL sits among the other events (`X5`'s instrument).
@MainActor func untilCancelled(_ onCancel: @escaping @MainActor @Sendable () -> Void) async {
    let gate = CancelGate()
    await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if Task.isCancelled { continuation.resume() } else { gate.continuation = continuation }
        }
    } onCancel: {
        MainActor.assumeIsolated {
            onCancel()
            gate.continuation?.resume()
            gate.continuation = nil
        }
    }
}

/// A 10 × 7 tile whose `.task` writes 70 into its width before its first
/// `await` (`X1`): written outside its `onAppear`.
private struct TKPresenter: Component {
    let log: LCLog
    @State var width: Float = 10
    var content: some ElementGroup {
        Box().frame(width: Pixels(width), height: Pixels(7)).background(.accent)
            .onAppear { log.add("appear") }
            .task {
                log.add("task")
                width = 70
                await Task.yield()
                log.add("after")
            }
    }
}

/// One value placed twice (`ID-F`): each occurrence's task increments its
/// own `n` in its synchronous prefix; the tile is `10 + n` wide.
private struct TKTwice: Component {
    @State var n: Float = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(10 + n), height: Pixels(13)).background(.accent)
            .task { n += 1 }
    }
}

@MainActor private func taskTransitionWindow<Content: ElementGroup>(
    @ElementBuilder _ content: @escaping @MainActor () -> Content
) throws -> (Window, FakePlatformWindow) {
    try lcWindow(size: 300, startsDisplayLink: true) {
        Column {
            Stack {
                Box().frame(width: Pixels(200), height: Pixels(100))
                content()
            }
        }
    }
}

// MARK: - Start (3.1–3.4)

/// **3.1** (`X1`, `X15`, `PX-F` item 3). A `.task` written outside an
/// `onAppear` starts after it, inside the first frame's drain, and runs its
/// prefix synchronously: after one `drawFrameIfNeeded()` the log is
/// `["appear", "task"]`, the prefix's write (70) is presented by the settle
/// build (two builds), and after pumping the rest of the body follows.
/// Mutation: start with `Task {}` (not `Task.immediate`).
@MainActor
@Test func aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear() async throws {
    let log = LCLog()
    let (window, _) = try lcWindow { Column { TKPresenter(log: log) } }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["appear", "task"], "\(log.entries)")
    #expect(lcWidth(window, height: 7) == 70, "presented: \(String(describing: lcWidth(window, height: 7)))")
    #expect(window.lastDrawBuildCount == 2)
    let resumed = await pumpMainActor(until: { log.entries.count == 3 })
    #expect(resumed && log.entries == ["appear", "task", "after"], "\(log.entries)")
}

/// **3.2** (`X1b`). A `.task` written inside an `onAppear` starts first.
/// Mutation: append starts after all appearances.
@MainActor
@Test func aTaskWrittenInsideOnAppearStartsFirst() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column { lcLeaf().task { log.add("task") }.onAppear { log.add("appear") } }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["task", "appear"], "\(log.entries)")
}

/// **3.3** (`X9`, `LC-F`). Siblings and parents start in reverse pre-order,
/// interleaved with `onAppear` by modifier order. Mutation: sort starts
/// ascending.
@MainActor
@Test func siblingsAndParentsStartInReversePreOrder() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            Column {
                lcLeaf().task { log.add("task child1") }.onAppear { log.add("appear child1") }
                lcLeaf().task { log.add("task child2") }.onAppear { log.add("appear child2") }
            }
            .task { log.add("task parent") }.onAppear { log.add("appear parent") }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["task child2", "appear child2", "task child1", "appear child1",
                            "task parent", "appear parent"], "\(log.entries)")
}

/// **3.4** (`X3`, `PX-F` item 9). The priority passes through and defaults to
/// `.userInitiated`: raw 25, 17, 25, 9 for the default, `.low`, `.high`,
/// `.background`, and 25 for the id form's default. Mutation: omit
/// `priority:` in `TaskStart.start`.
@MainActor
@Test func theTaskPriorityDefaultsToUserInitiatedAndPassesThrough() throws {
    var seen: [String: UInt8] = [:]
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().task { seen["default"] = Task.currentPriority.rawValue }
            lcLeaf().task(priority: .low) { seen["low"] = Task.currentPriority.rawValue }
            lcLeaf().task(priority: .high) { seen["high"] = Task.currentPriority.rawValue }
            lcLeaf().task(priority: .background) { seen["background"] = Task.currentPriority.rawValue }
            lcLeaf().task(id: 0) { seen["id"] = Task.currentPriority.rawValue }
        }
    }
    window.drawFrameIfNeeded()
    let raw = ["default", "low", "high", "background", "id"].map { seen[$0] }
    #expect(raw == [25, 17, 25, 9, 25], "\(raw)")
}

// MARK: - Cancellation and id (3.5–3.9)

/// **3.5** (`X4`, `X4b`, `PX-F` item 4). Removal cancels at its place in the
/// disappearance order — before an outer `onDisappear`, after an inner one —
/// and the task resumes seeing `Task.isCancelled`. Mutations: cancel in a
/// pass before all disappearances (the `X4b` arm reddens); never cancel (both).
@MainActor
@Test func removalCancelsAtItsPlaceInTheDisappearanceOrder() async throws {
    let m = LCModel(), log = LCLog(), resumed = LCLog()
    m.s1 = true; m.s2 = true
    let (window, _) = try lcWindow {
        Column {
            if m.s1 {
                lcLeaf().onAppear {}
                    .task { await untilCancelled { log.add("cancel") }; resumed.add("A \(Task.isCancelled)") }
                    .onDisappear { log.add("disappear") }
            }
            if m.s2 {
                lcLeaf().onDisappear { log.add("disappear") }
                    .task { await untilCancelled { log.add("cancel") }; resumed.add("B \(Task.isCancelled)") }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.entries.isEmpty)
    m.s1 = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["cancel", "disappear"], "task inside onDisappear (X4)")
    m.s2 = false
    window.drawFrameIfNeeded()
    #expect(log.take() == ["disappear", "cancel"], "task outside onDisappear (X4b)")
    let done = await pumpMainActor(until: { resumed.entries.count == 2 })
    #expect(done && resumed.entries == ["A true", "B true"], "\(resumed.entries)")
}

/// **3.6** (`X5`, `PX-F` item 5). An id change cancels the old task, then
/// starts the new one, in one step. Mutation: start before cancelling.
@MainActor
@Test func anIDChangeCancelsTheOldTaskThenStartsTheNewOne() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            let k = m.key
            lcLeaf().task(id: k) {
                log.add("start \(k)")
                await untilCancelled { log.add("cancel \(k)") }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["start 0"])
    m.key = 1
    window.drawFrameIfNeeded()
    #expect(log.take() == ["cancel 0", "start 1"])
    m.key = 2
    window.drawFrameIfNeeded()
    #expect(log.take() == ["cancel 1", "start 2"])
    #expect(window.animationStore.lifecycle.runningTaskCount == 1)
}

/// **3.7** (`X6`, `X7`). Writing the same id, or rebuilding for other state,
/// restarts nothing — before or after the task finished; after it finished,
/// an id change starts it again. Mutation: `isEqual` always `false`.
@MainActor
@Test func theSameIDOrARebuildRestartsNothing() async throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            let k = m.key
            lcLeaf(Float(10 + m.value), 10).task(id: k) {
                log.add("start \(k)")
                await Task.yield()
                log.add("done \(k)")
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["start 0"])
    m.key = 0
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(log.entries == [], "the same id (X6): \(log.entries)")
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.entries == [], "a rebuild, id unchanged (X7): \(log.entries)")
    let finished = await pumpMainActor(until: { log.entries == ["done 0"] })
    try #require(finished, "set up: the task finished: \(log.entries)")
    log.entries.removeAll()
    m.value = 2
    window.drawFrameIfNeeded()
    #expect(log.entries == [], "a rebuild after it finished: \(log.entries)")
    m.key = 1
    window.drawFrameIfNeeded()
    #expect(log.take() == ["start 1"], "an id change after it finished starts it again (X7)")
}

/// **3.8** (`X12`, `X12b`). An id restart runs at its place among the
/// `onChange` actions of the same build: inner first. Mutation: put id
/// restarts in the appearance bucket.
@MainActor
@Test func anIDRestartRunsAtItsPlaceAmongOnChangeActions() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            let v = m.value
            if m.flag {
                lcLeaf().task(id: v) { log.add("start") }.onChange(of: v) { log.add("change") }
            } else {
                lcLeaf().onChange(of: v) { log.add("change") }.task(id: v) { log.add("start") }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.take() == ["start"], "set up: the first start is an appearance")
    m.value = 1
    window.drawFrameIfNeeded()
    #expect(log.take() == ["change", "start"], "onChange inside (X12)")
    m.flag = true
    window.drawFrameIfNeeded()
    try #require(log.take() == ["start"], "set up: the other branch appeared")
    m.value = 2
    window.drawFrameIfNeeded()
    #expect(log.take() == ["start", "change"], "task(id:) inside (X12b)")
}

/// **3.9** (`X14b`, `LC-F`). An if/else swap starts the new branch's task
/// before cancelling the old one's: appearances before disappearances.
/// Mutation: run disappearances before appearances (reddens `LC-` tests too).
@MainActor
@Test func anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            if m.flag {
                lcLeaf().onAppear { log.add("appear then") }.task { log.add("start then") }
            } else {
                lcLeaf().onDisappear { log.add("disappear else") }
                    .task { await untilCancelled { log.add("cancel else") } }
            }
        }
    }
    window.drawFrameIfNeeded()
    try #require(log.entries.isEmpty)
    m.flag = true
    window.drawFrameIfNeeded()
    #expect(log.entries == ["appear then", "start then", "disappear else", "cancel else"], "\(log.entries)")
}

// MARK: - Presence (3.10–3.13)

/// **3.10** (`X10`, `PX-F` item 6, `LC-P` item 1). A `.task` on a group starts
/// once while the group has content and is cancelled when it empties.
/// Mutation: note the scope when `nodes.isEmpty`.
@MainActor
@Test func aGroupStartsOneTaskWhileItHasContent() throws {
    let m = LCModel(), log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            ForEach(0..<m.count) { _ in lcLeaf() }
                .task { log.add("start"); await untilCancelled { log.add("cancel") } }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.take() == [], "an empty ForEach starts nothing")
    #expect(window.animationStore.lifecycle.runningTaskCount == 0)
    m.count = 3
    window.drawFrameIfNeeded()
    #expect(log.take() == ["start"])
    #expect(window.animationStore.lifecycle.runningTaskCount == 1)
    m.count = 1
    window.drawFrameIfNeeded()
    #expect(log.take() == [])
    m.count = 0
    window.drawFrameIfNeeded()
    #expect(log.take() == ["cancel"])
    #expect(window.animationStore.lifecycle.runningTaskCount == 0)
}

/// **3.11** (`X8`, `LC-C`). Hidden and transparent content starts its task.
/// Shares `LC-C`'s instrument (test 1.4); no separate mutation — presence
/// code has no visibility branch to mutate (recorded so in `PX-U`).
@MainActor
@Test func hiddenAndTransparentContentStartsItsTask() throws {
    let log = LCLog()
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().hidden().task { log.add("hidden") }
            lcLeaf().opacity(0).task { log.add("transparent") }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["transparent", "hidden"], "\(log.entries)")
}

/// **3.12** (`X16`, `PX-F` item 7, `LC-H`). A task under a 0.6 s removal
/// transition is cancelled when the ghost ends: not at the removal frame,
/// not mid-way, in the first frame after. Mutation: never park task
/// cancellations.
@MainActor
@Test func aTaskUnderARemovalTransitionIsCancelledWhenTheGhostEnds() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try taskTransitionWindow {
        if m.shown {
            lcLeaf(50, 30).task { await untilCancelled { log.add("cancel") } }.transition(.opacity)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(window.animationStore.lifecycle.runningTaskCount == 1, "set up: running")
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    try #require(window.animationStore.transitions.ghostCount == 1, "set up: a ghost")
    #expect(log.entries == [], "the removal frame: \(log.entries)")
    platform.simulateTick(timestamp: 101.3)
    #expect(log.entries == [], "mid-fade: \(log.entries)")
    #expect(window.animationStore.lifecycle.parkedCount == 1)
    platform.simulateTick(timestamp: 101.7)
    #expect(log.entries == ["cancel"], "\(log.entries)")
    #expect(window.animationStore.lifecycle.runningTaskCount == 0)
}

/// **3.13** (`X17`, `PX-F` item 7). Content re-inserted mid-removal keeps its
/// task: no cancel, no second start, the same task still running — and a
/// later plain removal still cancels it. Mutation: drop the carry of the
/// running box across the parked key (a second start).
@MainActor
@Test func aTaskReinsertedMidRemovalKeepsRunning() throws {
    let m = LCModel(), log = LCLog()
    m.shown = true
    let (window, platform) = try taskTransitionWindow {
        if m.shown {
            lcLeaf(50, 30).task { log.add("start"); await untilCancelled { log.add("cancel") } }
                .transition(.opacity)
        }
    }
    platform.simulateTick(timestamp: 100)
    try #require(log.take() == ["start"])
    withAnimation(.linear(duration: 0.6)) { m.shown = false }
    platform.simulateTick(timestamp: 101)
    withAnimation(.linear(duration: 0.6)) { m.shown = true }
    platform.simulateTick(timestamp: 101.15)
    for t in [101.4, 101.8, 102.5, 103.0] { platform.simulateTick(timestamp: t) }
    #expect(log.entries == [], "neither a cancel nor a second start: \(log.entries)")
    #expect(window.animationStore.lifecycle.runningTaskCount == 1)
    #expect(window.animationStore.lifecycle.parkedCount == 0)
    m.shown = false
    platform.simulateTick(timestamp: 104)
    #expect(log.entries == ["cancel"], "the kept task is the one a later removal cancels: \(log.entries)")
}

// MARK: - Window and headless (3.14–3.16)

/// **3.14** (`LC-J` item 1, `X11`, `PX-F` item 8). Closing the window cancels
/// every running task once, in reverse pre-order with the `onDisappear`s; a
/// second close finds nothing. Mutation: `closeAll` ignores running boxes.
@MainActor
@Test func closingTheWindowCancelsEveryTask() throws {
    let log = LCLog()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = FakePlatform(device: device)
    let app = App(platform: platform)
    try app.openWindow(title: "Task", size: Size(width: Pixels(100), height: Pixels(100)),
                       startsDisplayLink: false) {
        Column {
            Column { lcLeaf().task { await untilCancelled { log.add("child cancel") } } }
                .onDisappear { log.add("parent") }
            lcLeaf().onDisappear { log.add("sibling") }
                .task { await untilCancelled { log.add("sibling cancel") } }
        }
    }
    let fake = try #require(platform.openedWindows.first)
    try #require(log.entries.isEmpty)
    fake.onClose?()
    #expect(log.take() == ["sibling", "sibling cancel", "child cancel", "parent"])
    fake.onClose?()
    #expect(log.entries == [], "a second close cancels nothing")
}

/// **3.15** (`LC-J` item 4). A headless `renderFrame` starts no task.
/// Mutation: run the store's events at the end of `renderFrame`'s render.
@MainActor
@Test func aHeadlessRenderFrameStartsNoTask() async {
    let log = LCLog()
    _ = renderFrame({ Column { lcLeaf().task { log.add("task") } } },
                    size: Size(width: Pixels(100), height: Pixels(100)), scaleFactor: 1,
                    textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 64, height: 64))
    _ = await pumpMainActor(until: { !log.entries.isEmpty }, maxYields: 50)
    #expect(log.entries.isEmpty, "\(log.entries)")
}

/// **3.16** (`PX-G` items 2–3, divergence 137). The deferred start — what
/// macOS 14–25 gets — runs the body on a later main-actor turn: after the
/// first draw only the `onAppear` ran, after pumping the task did, and its
/// write is presented by the next `drawFrameIfNeeded()`. Mutation: ignore
/// the `forcesDeferredStart` seam.
@MainActor
@Test func theDeferredStartRunsTheBodyOnALaterTurn() async throws {
    TaskStart.forcesDeferredStart = true
    defer { TaskStart.forcesDeferredStart = false }
    let log = LCLog()
    let (window, _) = try lcWindow { Column { TKPresenter(log: log) } }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["appear"], "\(log.entries)")
    #expect(lcWidth(window, height: 7) == 10)
    let ran = await pumpMainActor(until: { log.entries.contains("task") })
    #expect(ran && Array(log.entries.prefix(2)) == ["appear", "task"], "\(log.entries)")
    window.drawFrameIfNeeded()
    #expect(lcWidth(window, height: 7) == 70, "presented one frame late: \(String(describing: lcWidth(window, height: 7)))")
}

// MARK: - Name, dispatch, work (3.17–3.19)

/// **3.17** (`X13`, `PX-F` item 9). A task carries SwiftUI's default name,
/// `"View.task @ <fileID>:<line>"`, and a given `name:` wins. `Task.name`
/// needs macOS 26.4. Mutation: pass `nil` as the name.
@MainActor
@Test func aTaskCarriesSwiftUIsDefaultName() throws {
    guard #available(macOS 26.4, *) else { return }
    let log = LCLog()
    let line = #line + 3
    let (window, _) = try lcWindow {
        Column {
            lcLeaf().task { log.add("default \(Task.name ?? "nil")") }
            lcLeaf().task(name: "given") { log.add("given \(Task.name ?? "nil")") }
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.entries == ["given given",
                            "default View.task @ MetalUITests/TaskModifierTests.swift:\(line)"], "\(log.entries)")
}

/// **3.18** (`ID-F`, `PX-F` item 3). One element value placed twice: each
/// occurrence's `.task` writes its own `@State` in its synchronous prefix,
/// because the prefix runs under the occurrence's `StateDispatch`. Mutation:
/// run starts outside `StateDispatch.dispatching`.
@MainActor
@Test func aStateWriteInTheSynchronousPrefixReachesItsOwnOccurrence() throws {
    let (window, _) = try lcWindow {
        let twice = TKTwice()
        return Column { twice; twice }
    }
    window.drawFrameIfNeeded()
    let widths = window.lastScene.rects.filter { $0.bounds.size.height == 13 }.map(\.bounds.size.width)
    #expect(widths == [11, 11], "each occurrence's own n; the last-bound one would read [10, 12]: \(widths)")
}

/// **3.19** (`LC-M`, `PX-F` item 10). K task scopes cost what K lifecycle
/// scopes cost: `lastFrameWork == 3K` steady (registrations, this build's
/// entries, the last build's), and 0 with none. Derived before the run: K =
/// 5 → 15. Mutation: an extra store visit per running box.
@MainActor
@Test func taskScopesCostWhatLifecycleScopesCost() throws {
    let m = LCModel()
    let (window, _) = try lcWindow {
        Column {
            if m.flag {
                ForEach(0..<5) { _ in lcLeaf().task { await untilCancelled {} } }
            } else {
                lcLeaf()
            }
        }
    }
    window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.lastFrameWork == 0, "no scope, no work")
    m.flag = true
    window.drawFrameIfNeeded()
    try #require(window.animationStore.lifecycle.runningTaskCount == 5, "set up: five running")
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.lastFrameWork == 15)
    m.flag = false
    window.drawFrameIfNeeded()
    #expect(window.animationStore.lifecycle.runningTaskCount == 0)
}
