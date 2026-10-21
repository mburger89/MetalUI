import MetalUI
import MetalUITesting
import Testing

// G1 lane 1 — the mirror of the `@GestureState` block of `docs/guides/input.md` (item G1; `GS-M`, `DG-C`, `DG-D`):
// copied BY HAND between the `// guide:` and `// end guide` markers, byte for byte, so the ordinary build compiles it
// on every platform; `GuideDocCheck.swift` compares it with the guide. Below it, the tests the guide pins.
// Mutations: delete `.updating($drag)` (the chip never moves); delete `resetTransaction:` (the return snaps).

// guide: input #10
/// A chip that follows a drag and eases home: its offset is `@GestureState`.
struct InputSnapBackChip: Component {
    @GestureState(wrappedValue: Size(width: Pixels(0), height: Pixels(0)),
                  resetTransaction: Transaction(animation: .easeOut(duration: 0.25))) var drag: Size<Pixels>

    var content: some ElementGroup {
        Rectangle().frame(width: Pixels(60), height: Pixels(40))
            .offset(drag)
            .accessibilityIdentifier("snap-chip")
            .gesture(DragGesture(minimumDistance: 0).updating($drag) { value, state, _ in state = value.translation })
    }
}
// end guide

@MainActor private func snapWindow() throws -> TestWindow {
    try harnessWindow { Column { InputSnapBackChip() } }
}

/// The chip follows the pointer during the drag and is home at the release. Mutation: delete `.updating($drag)`.
@Test @MainActor func theInputGuideAGestureStateSnapsBackAtTheRelease() throws {
    let window = try snapWindow()
    let home = try window.element(identifier: "snap-chip").frame.origin
    let center = Point(x: home.x + Pixels(30), y: home.y + Pixels(20))
    window.send(.mouseDown(MouseEvent(position: center))); window.tick()
    window.send(.mouseDragged(MouseEvent(position: Point(x: center.x + Pixels(40), y: center.y)))); window.tick()
    let moved = try window.element(identifier: "snap-chip").frame.origin
    #expect(moved.x.value - home.x.value == 40, "followed the pointer: \(moved) from \(home)")
    window.send(.mouseUp(MouseEvent(position: Point(x: center.x + Pixels(40), y: center.y)))); window.tick()
    window.advanceFrames(60)
    #expect(try window.element(identifier: "snap-chip").frame.origin == home)
}

/// Right after the release the chip is still on its way home (the 0.25 s ease), and home a second later.
/// Mutation: delete `resetTransaction:`.
@Test @MainActor func theInputGuideTheResetTransactionAnimatesTheReturn() throws {
    let window = try snapWindow()
    let home = try window.element(identifier: "snap-chip").frame.origin
    let center = Point(x: home.x + Pixels(30), y: home.y + Pixels(20))
    let end = Point(x: center.x + Pixels(40), y: center.y)
    window.send(.mouseDown(MouseEvent(position: center))); window.tick()
    window.send(.mouseDragged(MouseEvent(position: end))); window.tick()
    window.send(.mouseUp(MouseEvent(position: end))); window.tick()
    window.advance(by: 0.05)
    let mid = try window.element(identifier: "snap-chip").frame.origin.x.value - home.x.value
    #expect(mid > 0 && mid < 40, "partway home: \(mid)")
    window.advanceFrames(60)
    #expect(try window.element(identifier: "snap-chip").frame.origin == home)
}
