import MetalUI
import Observation
import Foundation

/// The overlays-and-coordinates demo (spec
/// `2026-10-10-overlays-coords-design.md` §3.2, rulings `OV-A`…`OV-N`),
/// reached with `METALUI_OVERLAYS_DEMO=1 swift run MetalUIDemo`: MetalCreator's
/// EP-a and EP-b in one window.
///
/// - **Canvas**: declares `.coordinateSpace(.named("canvas"))`; a crosshair
///   follows `onContinuousHover(coordinateSpace: .named("canvas"))`.
/// - **Palette**: a click on the canvas opens a chrome-less palette
///   (`anchoredOverlay(at: click, in: .named("canvas"))`) with its top-leading
///   corner at the click, flipped at the window's right and bottom edges. Any
///   press outside it — any button, onto the note field, the slider or the
///   context-menu card beside it — closes it and still lands; a press on the
///   canvas closes it and reopens it at the new point; Escape closes it;
///   typing reaches its search field.
/// - A **readout** of `@Environment(\.windowSize)` and the palette's frame in
///   the canvas's space (`onGeometryChange` with `.named("canvas")`).
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each part is its own function, passed to a
/// generic composer (the Windows 1 MB stack rule); built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func overlaysDemoContent() -> some Element {
    overlaysRoot(header: overlaysHeader(), canvas: overlaysCanvas(), side: overlaysSide(),
                 readout: OverlaysReadout())
}

/// The demo's state, written only from input and the geometry action.
@MainActor
@Observable
public final class OverlaysDemoModel {
    /// The pointer over the canvas, in the canvas's space, or `nil` outside.
    public var pointer: Point<Pixels>?
    /// Where the palette opens, in the canvas's space.
    public var palettePoint = Point(x: Pixels(0), y: Pixels(0))
    /// Whether the palette is open.
    public var paletteShown = false
    /// The palette's search text.
    public var query = ""
    /// The note field's text.
    public var note = ""
    /// The slider's value.
    public var level = 0.5
    /// The last context-menu choice.
    public var menuChoice = "none"
    /// The palette's frame in the canvas's space, from its geometry action.
    public var paletteFrame = "closed"

    /// A fresh model.
    public init() {}

    /// Back to the launch state.
    public func reset() {
        pointer = nil; palettePoint = Point(x: Pixels(0), y: Pixels(0)); paletteShown = false; query = ""
        note = ""; level = 0.5; menuChoice = "none"; paletteFrame = "closed"
    }
}

/// The one model the demo and its tests share.
@MainActor public let overlaysDemoModel = OverlaysDemoModel()

/// The canvas's size.
let overlaysCanvasSize = Size(width: Pixels(520), height: Pixels(380))

@MainActor
private func overlaysRoot(header: some Element, canvas: some ElementGroup, side: some Element,
                          readout: some ElementGroup) -> some Element {
    Column(gap: Pixels(12)) {
        header
        Row(gap: Pixels(16)) {
            canvas
            side
        }
        .alignItems(.flexStart)
        readout
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
private func overlaysHeader() -> some Element {
    Text("Overlays — click the canvas for the palette · press anywhere else (any button) or Escape to close it")
        .font(size: 13)
}

/// The canvas: a named space with a hover crosshair, opening the palette at
/// a click.
@MainActor
private func overlaysCanvas() -> some ElementGroup {
    let model = overlaysDemoModel
    let shown = Binding(get: { overlaysDemoModel.paletteShown }, set: { overlaysDemoModel.paletteShown = $0 })
    return ZStack(alignment: .topLeading) {
        Rectangle().fill(Color(.surfaceSecondary))
            .frame(width: overlaysCanvasSize.width, height: overlaysCanvasSize.height)
        overlaysCrosshair(model.pointer)
    }
    .onContinuousHover(coordinateSpace: .named("canvas")) { phase in
        switch phase {
        case .active(let point): overlaysDemoModel.pointer = point
        case .ended: overlaysDemoModel.pointer = nil
        }
    }
    .onTapGesture(coordinateSpace: .named("canvas")) { point in
        overlaysDemoModel.palettePoint = point
        overlaysDemoModel.paletteShown = true
    }
    .anchoredOverlay(isPresented: shown, at: model.palettePoint, in: .named("canvas")) {
        overlaysPalette()
    }
    .coordinateSpace(.named("canvas"))
}

/// Two hairlines through `pointer`, or nothing.
@MainActor
private func overlaysCrosshair(_ pointer: Point<Pixels>?) -> some ProposalElementGroup {
    ZStack(alignment: .topLeading) {
        if let pointer {
            Rectangle().fill(Color(.accent)).frame(width: Pixels(1), height: overlaysCanvasSize.height)
                .offset(x: pointer.x, y: Pixels(0))
            Rectangle().fill(Color(.accent)).frame(width: overlaysCanvasSize.width, height: Pixels(1))
                .offset(x: Pixels(0), y: pointer.y)
        }
    }
}

/// The palette: its own `.surface` rounded panel (the overlay draws none), a
/// search field and four rows; reports its frame in the canvas's space.
@MainActor
private func overlaysPalette() -> some ElementGroup {
    let model = overlaysDemoModel
    return Column(gap: Pixels(4)) {
        TextField("Search", text: model.query) { overlaysDemoModel.query = $0 }
            .frame(width: Pixels(180))
        Text("Box").font(size: 12)
        Text("Cylinder").font(size: 12)
        Text("Sphere").font(size: 12)
        Text("Torus").font(size: 12)
    }
    .alignItems(.flexStart)
    .padding(Pixels(8))
    .background(.surface)
    .cornerRadius(Pixels(8))
    .onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("canvas")) }) { frame in
        overlaysDemoModel.paletteFrame = "(\(Int(frame.origin.x.value)), \(Int(frame.origin.y.value))) "
            + "\(Int(frame.size.width.value)) × \(Int(frame.size.height.value))"
    }
}

/// Beside the canvas: a field, a slider and a context-menu card — the
/// presses EP-b names, each closing the palette and still landing.
@MainActor
private func overlaysSide() -> some Element {
    let model = overlaysDemoModel
    return Column(gap: Pixels(12)) {
        TextField("Note", text: model.note) { overlaysDemoModel.note = $0 }
            .frame(width: Pixels(200))
        Slider(value: Binding(get: { overlaysDemoModel.level }, set: { overlaysDemoModel.level = $0 }), in: 0...1)
            .frame(width: Pixels(200))
        Box {
            Text("Right-click me").font(size: 12)
        }
        .alignItems(.center)
        .justifyContent(.center)
        .frame(width: Pixels(200), height: Pixels(60))
        .background(.surfaceSecondary)
        .contextMenu {
            Button("Duplicate") { overlaysDemoModel.menuChoice = "Duplicate" }
            Button("Delete") { overlaysDemoModel.menuChoice = "Delete" }
        }
    }
    .alignItems(.flexStart)
}

/// The readout: the window's size from the environment, the palette's named
/// frame, the pointer and the side controls' values.
struct OverlaysReadout: Component {
    @Environment(\.windowSize) var windowSize

    var content: some ElementGroup {
        let model = overlaysDemoModel
        let pointer = model.pointer.map { "(\(Int($0.x.value)), \(Int($0.y.value)))" } ?? "outside"
        Column(gap: Pixels(2)) {
            Text("window \(Int(windowSize.width.value)) × \(Int(windowSize.height.value)) · pointer \(pointer)")
                .font(size: 12)
            Text("palette \(model.paletteFrame) · note \"\(model.note)\" · level \(Int(model.level * 100)) · menu \(model.menuChoice)")
                .font(size: 12)
        }
        .alignItems(.flexStart)
    }
}
