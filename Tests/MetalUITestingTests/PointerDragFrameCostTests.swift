@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// What a pointer drag that changes nothing a frame would show costs (`FP-U`, record 386; widens `FP-T`, record 360). The
// terminal's selection drag was priced at 1 build, 2 element requests and 1 surface draw an event, blamed (`TRM-BP`) on the
// window dirtying "after a claimed event". The drag is not claimed: `dispatchGestures` declines `.mouseDragged` (`IX-D` item 6),
// it reaches the input tail, and `FP-T`'s helper spared only `.mouseMoved`. `Window.pointerEventChangesNothing` now also spares
// an unclaimed `.mouseDragged` and the button arena's (`CI-F`) `.rightMouseDragged` and `.otherMouseDragged` that stay on one
// topmost hitbox with no state written, no tooltip and no window `onInput`; what a gesture's callback changes invalidates on its own
// (`@State`, `@GestureState`, a binding, observation, a surface trigger). `.beginWindowDrag` clears unobserved state (`active`)
// and so asks for its frame itself. Each test names its mutation. Every count is read after `runUntilIdle` (off Darwin a dirty
// mark hops through a Task), summed over `frameWork`, never `lastFrameWork`, and events are sent raw (`TestWindow.drag` ticks
// between steps). The harness text system; windows kept alive.

/// A plain, unobserved counter: a drag callback that bumps it changes nothing a build reads.
@MainActor private final class Counter { var value = 0 }

@MainActor private final class DxLog { var lastBuiltDx: Float = -1; var builds = 0 }

private func down(_ p: Point<Pixels>, button: Int = 0) -> InputEvent {
    button == 0 ? .mouseDown(MouseEvent(position: p)) : .rightMouseDown(MouseEvent(position: p, buttonNumber: button))
}
private func dragged(_ p: Point<Pixels>, button: Int = 0) -> InputEvent {
    button == 0 ? .mouseDragged(MouseEvent(position: p)) : .rightMouseDragged(MouseEvent(position: p, buttonNumber: button))
}
private func up(_ p: Point<Pixels>, button: Int = 0) -> InputEvent {
    button == 0 ? .mouseUp(MouseEvent(position: p)) : .rightMouseUp(MouseEvent(position: p, buttonNumber: button))
}

@MainActor private func builds(_ w: TestWindow) -> Int { w.frameWork.map(\.builds).reduce(0, +) }
@MainActor private func requests(_ w: TestWindow) -> Int { w.frameWork.map(\.elementRequests).reduce(0, +) }

/// A 200 x 200 target under a drag gesture, and a marker whose width reads `dx` (the build reads what the gesture wrote).
private struct WriterChip: Component {
    let log: DxLog
    let button: MouseButton
    @State var dx: Float = 0
    var content: some ElementGroup {
        _ = { log.lastBuiltDx = dx; log.builds += 1 }()
        VStack(spacing: 0) {
            Rectangle().frame(width: Pixels(200), height: Pixels(200))
                .gesture(DragGesture(minimumDistance: Pixels(0), button: button).onChanged { v in dx = Float(v.translation.width.value) })
            Rectangle().frame(width: Pixels(20 + dx), height: Pixels(10))
        }
    }
}

@MainActor private func counterWindow(_ counter: Counter, button: MouseButton = .primary) throws -> TestWindow {
    try harnessWindow {
        Rectangle().frame(width: Pixels(200), height: Pixels(200))
            .gesture(DragGesture(minimumDistance: Pixels(0), button: button).onChanged { _ in counter.value += 1 })
    }
}

/// Presses at the window's centre, inside the 200 x 200 target, and settles (the press dirties: `active`).
@MainActor private func press(_ w: TestWindow, button: Int = 0) async throws {
    w.send(down(pt(200, 150), button: button))
    try await w.runUntilIdle()
}

/// **G1** A drag whose handler writes `@State` that a build reads costs one build per event and shows the new value: the skip
/// must not swallow a dirty the state raised itself. Mutation: implement the skip by clearing `needsRedraw` when the helper
/// says nothing changed, with its `writeCount` guard dropped (the writer's own dirty is lost: 0 builds, a stale `dx`).
@Test @MainActor func aDragWhoseHandlerWritesStateRedrawsOncePerEvent() async throws {
    let log = DxLog()
    let w = try harnessWindow { Column { WriterChip(log: log, button: .primary) } }
    try await w.runUntilIdle()
    try await press(w)
    for step in 1...4 {
        w.resetFrameWork()
        w.send(dragged(pt(200 + Float(step * 5), 150)))
        try await w.runUntilIdle()
        #expect(builds(w) == 1, "step \(step): \(builds(w)) builds")
        #expect(log.lastBuiltDx == Float(step * 5), "step \(step): the last build read dx \(log.lastBuiltDx)")
    }
}

/// **G2** A drag whose handler changes only unobserved state draws no frame: the window is clean right after the send (before
/// any tick), no frame is drawn, no build runs, and the handler did run. Mutation: the helper rejects `.mouseDragged`.
@Test @MainActor func aDragWhoseHandlerChangesNothingDrawsNoFrame() async throws {
    let counter = Counter()
    let w = try counterWindow(counter)
    try await w.runUntilIdle()
    try await press(w)
    w.resetFrameWork()
    let frames = w.framesDrawn
    for step in 1...4 {
        let before = counter.value
        w.send(dragged(pt(200 + Float(step * 5), 150)))
        #expect(!w.window.needsRedraw, "step \(step): the drag leaves the window clean")
        try await w.runUntilIdle()
        #expect(counter.value == before + 1, "step \(step): the handler ran")
    }
    #expect(w.framesDrawn == frames, "\(w.framesDrawn - frames) frames")
    #expect(builds(w) == 0, "\(builds(w)) builds")
}

/// **G3** A drag within a pressed Button draws nothing, a drag off it draws (the hovered hitbox, so the pressed look, changes),
/// and a drag back onto it draws again. Mutation: the hitbox comparison replaced by `true` (the first, within-button, step
/// stays clean, but the drag off the button no longer draws: the second reddens).
@Test @MainActor func aDragOffAPressedButtonAndBackStillDraws() async throws {
    let w = try harnessWindow {
        VStack(spacing: 0) {
            Button("Target") {}.accessibilityIdentifier("t").frame(width: Pixels(400), height: Pixels(30))
            Rectangle().frame(width: Pixels(400), height: Pixels(200))
        }
    }
    try await w.runUntilIdle()
    let b = try w.element(identifier: "t").frame
    let onX = b.origin.x.value + b.size.width.value / 2, onY = b.origin.y.value + b.size.height.value / 2
    let offY = b.origin.y.value + b.size.height.value + 60
    w.send(down(pt(onX, onY)))
    try await w.runUntilIdle()
    var frames = w.framesDrawn
    w.send(dragged(pt(onX + 10, onY + 1)))
    try await w.runUntilIdle()
    #expect(w.framesDrawn == frames, "within the button: \(w.framesDrawn - frames) frames")
    frames = w.framesDrawn
    w.send(dragged(pt(onX, offY)))
    try await w.runUntilIdle()
    #expect(w.framesDrawn - frames >= 1, "off the button: \(w.framesDrawn - frames) frames")
    frames = w.framesDrawn
    w.send(dragged(pt(onX, onY)))
    try await w.runUntilIdle()
    #expect(w.framesDrawn - frames >= 1, "back onto the button: \(w.framesDrawn - frames) frames")
}

/// **G4** The secondary button's drag follows the same rule through the button arena (`CI-F`): a `@State` writer costs one
/// build per event, a plain counter costs no frame. Mutation: an unconditional `setNeedsRedraw()` in the arena branch (the counter
/// arm draws); the helper rejecting `.rightMouseDragged` (the same).
@Test @MainActor func aSecondaryButtonDragFollowsTheSameRule() async throws {
    let secondary = MouseButton.secondary.buttonNumber
    let log = DxLog()
    let writer = try harnessWindow { Column { WriterChip(log: log, button: .secondary) } }
    try await writer.runUntilIdle()
    try await press(writer, button: secondary)
    for step in 1...3 {
        writer.resetFrameWork()
        writer.send(dragged(pt(200 + Float(step * 5), 150), button: secondary))
        try await writer.runUntilIdle()
        #expect(builds(writer) == 1, "writer step \(step): \(builds(writer)) builds")
        #expect(log.lastBuiltDx == Float(step * 5), "writer step \(step): dx \(log.lastBuiltDx)")
    }
    let counter = Counter()
    let plain = try counterWindow(counter, button: .secondary)
    try await plain.runUntilIdle()
    try await press(plain, button: secondary)
    let frames = plain.framesDrawn
    plain.resetFrameWork()
    for step in 1...3 {
        let before = counter.value
        plain.send(dragged(pt(200 + Float(step * 5), 150), button: secondary))
        try await plain.runUntilIdle()
        #expect(counter.value == before + 1, "plain step \(step): the handler ran")
    }
    #expect(plain.framesDrawn == frames && builds(plain) == 0, "plain: \(plain.framesDrawn - frames) frames, \(builds(plain)) builds")
}

/// **G5** A window with an `onInput` keeps a frame per drag: its fallback could change what a frame reads without a write the
/// window observes. Mutation: drop the `onInput == nil` guard (the drag leaves the window clean).
@Test @MainActor func aDragInAWindowWithOnInputStillDraws() async throws {
    let counter = Counter()
    let w = try counterWindow(counter)
    try await w.runUntilIdle()
    w.window.onInput = { _ in false }
    try await press(w)
    for step in 1...3 {
        w.send(dragged(pt(200 + Float(step * 5), 150)))
        #expect(w.window.needsRedraw, "step \(step): the drag asks for a frame")
        try await w.runUntilIdle()
    }
}

/// **G6** A drag over a `.help` element keeps its frame: the tooltip's timer rides the display link a dirty window starts.
/// Mutation: drop the tooltip `.idle` guard (an in-region drag leaves the window clean).
@Test @MainActor func aDragOverAHelpedElementKeepsTheTooltipFrame() async throws {
    let w = try harnessWindow { Box().frame(width: Pixels(200), height: Pixels(100)).background(.accent).help("Explains") }
    try await w.runUntilIdle()
    w.hover(at: pt(150, 150))
    try await w.runUntilIdle()
    w.send(dragged(pt(160, 152)))
    #expect(w.window.needsRedraw, "an in-region drag with a tooltip pending asks for a frame")
    try await w.runUntilIdle()
}

/// **R1** A draggable opens its session and the preview is captured by the frame that event asks for, within one hitbox
/// (the drag that begins a session moves inside the source, so the helper would spare it were `beginDragSession` not dirtying).
/// Mutation: delete `setNeedsRedraw()` in `beginDragSession` (no frame, no captured preview).
@Test @MainActor func aDraggableOpensItsSessionAndDrawsThePreviewWithinOneHitbox() async throws {
    let w = try harnessWindow {
        Rectangle().frame(width: Pixels(200), height: Pixels(200)).draggable("x")
    }
    try await w.runUntilIdle()
    w.send(down(pt(200, 150)))
    try await w.runUntilIdle()
    w.send(dragged(pt(220, 150)))
    try await w.runUntilIdle()
    try #require(w.window.dragSession != nil, "the draggable began its session")
    #expect(w.window.dragSession?.snapshot.isEmpty == false, "the frame captured the preview")
}

@MainActor private func windowDragTree() -> some Element {
    ZStack(alignment: .top) {
        Rectangle().frame(width: Pixels(300), height: Pixels(300))
        Rectangle().frame(width: Pixels(300), height: Pixels(32)).gesture(WindowDragGesture())
    }
}

/// **R2** A window drag that ends the press asks for a frame itself: `endPressForDrag` clears `active` (unobserved), and the
/// drag event is otherwise unclaimed and within one hitbox. Mutation: remove the `setNeedsRedraw()` in `.beginWindowDrag`.
@Test @MainActor func aWindowDragThatEndsThePressAsksForAFrame() async throws {
    let w = try harnessWindow(size: Size(width: Pixels(300), height: Pixels(300))) { windowDragTree() }
    try await w.runUntilIdle()
    w.send(down(pt(100, 16)))
    try await w.runUntilIdle()
    try #require(w.window.active != nil, "set up: the press is held")
    w.send(dragged(pt(140, 16)))
    #expect(w.windowDrags == 1)
    #expect(w.window.active == nil, "the press ended")
    #expect(w.window.needsRedraw, "and the pressed look's frame was asked for")
    try await w.runUntilIdle()
}

@MainActor private final class FieldModel { var text = "abcdefghijklmnopqrstuvwxyz" }

/// **R3** A text field's selection drag is claimed (`dispatchTextInput`) and keeps one frame per step: the selection is
/// window-owned and raises no dirty of its own. The selection grows (read by copying). Mutation: apply the skip to the
/// `dispatchTextInput` claim with the `writeCount` guard ignored (no frame per step; the highlight lags). With the guard intact the
/// skip is harmless here: the field's edit state is a `withState` write, which the guard sees.
@Test @MainActor func aTextFieldSelectionDragStillDrawsEachStep() async throws {
    let m = FieldModel()
    let w = try harnessWindow {
        TextField("", text: Binding(get: { m.text }, set: { m.text = $0 })).accessibilityIdentifier("f")
            .frame(width: Pixels(300), height: Pixels(24))
    }
    try await w.runUntilIdle()
    let frame = try w.element(identifier: "f").frame
    let y = frame.origin.y.value + frame.size.height.value / 2, x0 = frame.origin.x.value + 4
    w.send(down(pt(x0, y)))
    try await w.runUntilIdle()
    func copied() async throws -> Int {
        w.typeKey("c", modifierFlags: Modifiers.primary)
        try await w.runUntilIdle()
        return w.platformWindow.clipboard?.count ?? 0
    }
    var lengths: [Int] = []
    for step in 1...6 {
        let frames = w.framesDrawn
        w.send(dragged(pt(x0 + Float(step * 12), y)))
        try await w.runUntilIdle()
        #expect(w.framesDrawn - frames == 1, "step \(step): \(w.framesDrawn - frames) frames")
        if step % 3 == 0 { lengths.append(try await copied()) }
    }
    #expect(lengths.count == 2 && lengths[0] > 0 && lengths[1] > lengths[0], "the selection grew: \(lengths)")
}

@MainActor private final class Plain { var value = 0.2 }

/// **R4** A slider dragged over a binding on plain, unobserved storage keeps its frame per step: the value-track claim writes
/// through the binding and nothing else would dirty. The thumb (the accessibility value) follows. Mutation: apply the skip to
/// the `dispatchValueTrack` claim (no frame; the value reads stale). The binding writes plain storage, so the `writeCount` guard
/// cannot save it.
@Test @MainActor func aSliderDragOverUnobservedStorageStillMovesTheThumb() async throws {
    let p = Plain()
    let w = try harnessWindow {
        Slider(value: Binding(get: { p.value }, set: { p.value = $0 }), in: 0...1).accessibilityIdentifier("s")
            .frame(width: Pixels(300), height: Pixels(24))
    }
    try await w.runUntilIdle()
    let frame = try w.element(identifier: "s").frame
    let y = frame.origin.y.value + frame.size.height.value / 2, x0 = frame.origin.x.value
    w.send(down(pt(x0 + 30, y)))
    try await w.runUntilIdle()
    var values: [String?] = [try w.element(identifier: "s").value]
    for step in 1...4 {
        let frames = w.framesDrawn
        w.send(dragged(pt(x0 + 30 + Float(step * 60), y)))
        try await w.runUntilIdle()
        #expect(w.framesDrawn - frames >= 1, "step \(step): \(w.framesDrawn - frames) frames")
        values.append(try w.element(identifier: "s").value)
    }
    #expect(Set(values.compactMap { $0 }).count == values.count, "the thumb followed: \(values)")
    #expect(p.value > 0.5, "the binding was written: \(p.value)")
}

/// **R5** A window with no pointer feature keeps its steady cost: a drag whose handler writes `@State` is one build and the
/// steady frame's element requests, as before `FP-U` (literal measured on master `328ab5eb`: 6 element requests for the chip's steady
/// frame), and the steady frame itself is unchanged. A pin, not a mutation: it reddens if a new dirty adds a second build or
/// request to a drag event.
@Test @MainActor func aWindowWithoutAPointerFeatureKeepsItsSteadyRequests() async throws {
    let log = DxLog()
    let w = try harnessWindow { Column { WriterChip(log: log, button: .primary) } }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    let steady = w.lastFrameWork.elementRequests
    print("FP-U R5 literal: steady elementRequests \(steady)")
    #expect(steady == 6, "steady \(steady)")
    try await press(w)
    for step in 1...3 {
        w.resetFrameWork()
        w.send(dragged(pt(200 + Float(step * 5), 150)))
        try await w.runUntilIdle()
        #expect(builds(w) == 1 && requests(w) == steady, "step \(step): \(builds(w)) builds, \(requests(w)) requests vs \(steady)")
    }
}

@Observable @MainActor private final class DragModel { var dx: Float = 0 }

private struct ObservedChip: Component {
    let model: DragModel
    let log: DxLog
    var content: some ElementGroup {
        _ = { log.lastBuiltDx = model.dx; log.builds += 1 }()
        VStack(spacing: 0) {
            Rectangle().frame(width: Pixels(200), height: Pixels(200))
                .gesture(DragGesture(minimumDistance: Pixels(0)).onChanged { v in model.dx = Float(v.translation.width.value) })
            Rectangle().frame(width: Pixels(20 + model.dx), height: Pixels(10))
        }
    }
}

/// **R6** (`FP-U` item 6) A drag that writes an observed model a build reads asks for its frame before any hop: off Darwin the
/// observation's dirty mark reaches the window through a Task, after the event returned, so the event itself must count the
/// change. Read right after the send, with no await, and drawn with synchronous `tick()` only (as `TestWindow.drag` does).
/// Mutation: drop the `observationChanges` guard in `pointerEventChangesNothing`. **Red on Linux and Windows** (the dirty hops;
/// the bracket tests failed there); **stays green on macOS**, where `markDirtyFromObservation` runs on the main thread and
/// dirties synchronously, so this is a pin for the portable path, not a macOS detector.
@Test @MainActor func aDragWritingAnObservedModelAsksForItsFrameBeforeTheHop() async throws {
    let model = DragModel(), log = DxLog()
    let w = try harnessWindow { Column { ObservedChip(model: model, log: log) } }
    try await w.runUntilIdle()
    w.send(down(pt(200, 150)))
    try await w.runUntilIdle()
    for step in 1...4 {
        let builds = log.builds
        w.send(dragged(pt(200 + Float(step * 5), 150)))
        #expect(w.window.needsRedraw, "step \(step): the event asked for its frame before any hop")
        w.tick()
        #expect(log.builds == builds + 1 && log.lastBuiltDx == Float(step * 5), "step \(step): built \(log.builds - builds), dx \(log.lastBuiltDx)")
    }
}
