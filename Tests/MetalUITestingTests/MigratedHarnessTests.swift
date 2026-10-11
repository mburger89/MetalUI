import MetalUI
import MetalUITesting
import Testing

// Proof by migration (ruling `HT-N`, spec §4.3 tests 3.5–3.8): four tests
// that ran on `@testable` fakes (`FakePlatformWindow`, `makeFakeWindow`) moved
// here, names kept, onto the public harness with PLAIN imports — what an app's
// own test target can write. Their old copies are deleted (a comment at each
// old site names this file), so the suite's count does not move for them.
//
// Two of the four the spec named needed an internal in their assertion, so the
// lane swapped in another test from the same file (`HT-N`'s rule; record §91,
// `HT-V`): `anAlertResultWritesIsPresentedFalseThenRunsTheAction` reads
// `StateDispatch.owner` and `aChosenItemRunsItsActionFromInputUnderStateDispatch`
// reads `Window.stateTable`; both stay in `AlertTests`/`ContextMenuTests`, and
// `aStaleAlertAnswerNeverReachesTheNextAlert` and
// `aMenuActionWithAStaleTokenRunsNothing` moved instead.
//
// Every model here is a plain class, not `@Observable`: a write between frames
// is followed by `window.window.setNeedsRedraw()` and a tick, as the old
// tests' `drawFrameIfNeeded()` was, so nothing waits on the observation hop
// (asynchronous off macOS, `HT-U` item 1).

/// Marks the window dirty and fires one tick — a model write's frame.
@MainActor private func redraw(_ window: TestWindow) {
    window.window.setNeedsRedraw()
    window.tick()
}

// MARK: - From `InputDispatchTests`

/// **3.5** (moved from `InputDispatchTests`). A click inside an `onClick`
/// box's bounds runs its handler exactly once.
///
/// **The `count == 1` is not decoration.** A dispatcher that fired on
/// `.mouseDown` *and* `.mouseUp`, or one that ran every hit rather than the
/// topmost, passes a bare "did it run" assertion and fails this one. The root
/// declares both axes, so it is centred at its own 40 × 40 answer (`CN-J`):
/// (100 − 40) / 2 = 30, the box at 30…70 on both axes. Mutation (record §91):
/// `Window.dispatchClick` calls `runClick` twice (measured, `HT-W` item 3).
@Test @MainActor func aClickInsideTheBoundsRunsTheHandler() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(100, 100)) {
        Box().frame(width: Pixels(40), height: Pixels(40)).onClick { log.add("btn") }
    }
    window.click(at: pt(50, 50))
    #expect(log.entries == ["btn"], "a press and release inside the box is one click")
}

// MARK: - From `LifecycleTests`

/// What the lifecycle test toggles between frames.
@MainActor private final class Presence {
    var shown = false
}

/// **3.6** (moved from `LifecycleTests`, its 1.1; `A1`, `LC-C` item 1). An
/// `if` that inserts content runs its `onAppear` once, however many frames
/// follow. Mutation: `endFrame` treats every `current` key as appearing.
@Test @MainActor func anIfThatInsertsContentRunsItsOnAppearOnce() throws {
    let m = Presence(), log = HarnessLog()
    let window = try harnessWindow(size: sz(200, 200)) {
        Column {
            if m.shown {
                Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent)
                    .onAppear { log.add("appear") }
            }
        }
    }
    try #require(log.entries.isEmpty, "set up: nothing present")
    m.shown = true
    for _ in 0..<3 { redraw(window) }
    #expect(log.entries == ["appear"], "\(log.entries)")
}

// MARK: - From `AlertTests` (the swap for 2.22)

/// The alert's model: what `isPresented` reads and what each answer ran.
@MainActor private final class AlertModel {
    var shown = false
    var log: [String] = []

    var binding: Binding<Bool> {
        Binding(get: { self.shown }, set: { self.shown = $0; self.log.append("isPresented=\($0)") })
    }
}

/// `AlertTests`' A1 tree: a destructive Delete and a Cancel.
@MainActor private func alertTree(_ m: AlertModel) -> some Element {
    Column {
        Box().frame(width: Pixels(10), height: Pixels(10)).background(.accent)
            .alert("Delete keymap?", isPresented: m.binding) {
                Button("Delete", role: .destructive) { m.log.append("delete") }
                Button("Cancel", role: .cancel) { m.log.append("cancel") }
            } message: {
                Text("This cannot be undone.")
            }
    }
}

/// **3.7** (moved from `AlertTests`, its 2.23b; `SV-I` item 4 — the swap for
/// 2.22, whose owner check reads `StateDispatch.owner`). A stale alert answer
/// never reaches the alert presented after it: A is dismissed, B is
/// presented, A's late answer runs nothing and B's own answer lands. The
/// window presents natively (`HeadlessPlatformWindow.Options`' AppKit
/// default). Mutation: drop `token == result.token` from `handleAlertResult`
/// (A's answer runs B's "Delete").
@Test @MainActor func aStaleAlertAnswerNeverReachesTheNextAlert() throws {
    let m = AlertModel()
    m.shown = true
    let window = try harnessWindow(size: sz(200, 200)) { alertTree(m) }
    let a = try #require(window.presentedAlert, "the first frame presents the alert")
    m.shown = false
    redraw(window)
    try #require(window.platformWindow.dismissedPresentations == [a.token])
    m.shown = true
    redraw(window)
    try #require(window.platformWindow.presentedAlerts.count == 2)
    let b = try #require(window.presentedAlert)
    try #require(b.token != a.token)
    _ = window.send(.alertResult(AlertResultEvent(token: a.token, button: 0)))
    #expect(m.log.isEmpty, "A's answer runs nothing: \(m.log)")
    #expect(m.shown == true)
    try window.respondToAlert(button: "Cancel")
    #expect(m.log == ["isPresented=false", "cancel"])
}

// MARK: - From `ContextMenuTests` (the swap for 1.2)

/// **3.8** (moved from `ContextMenuTests`, its 1.3; `MN-C` item 4 — the swap
/// for 1.2, which reads `Window.stateTable`). A `.menuAction` naming an
/// earlier menu's token runs nothing; the current token's runs. The window
/// presents menus natively (AppKit's answer), so each right click is one
/// `presentMenu` with its own token. Mutation: skip the token comparison.
@Test @MainActor func aMenuActionWithAStaleTokenRunsNothing() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(400, 400)) {
        Box().frame(width: Pixels(400), height: Pixels(400)).contextMenu {
            Button("Copy") { log.add("copy") }
            Button("Delete") { log.add("delete") }
        }
    }
    window.rightClick(at: pt(10, 10))
    window.rightClick(at: pt(20, 20))
    let menus = window.platformWindow.presentedMenus
    try #require(menus.count == 2)
    let (old, current) = (menus[0].menu.token, menus[1].menu.token)
    try #require(old != current, "each presentation has its own token")
    _ = window.send(.menuAction(MenuActionEvent(menu: old, item: 1)))
    #expect(log.entries.isEmpty, "a stale token runs nothing")
    try #require(window.presentedMenu?.token == current)
    try window.chooseMenuItem("Delete")
    #expect(log.entries == ["delete"], "the current token runs its item")
}
