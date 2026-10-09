import MetalUI
import Observation
import Foundation

/// The input-APIs canvas demo (spec `2026-10-08-input-apis-design.md` §6,
/// rulings `CI-AE` item 3, `CI-AI`), reached with `METALUI_CANVAS_DEMO=1 swift
/// run MetalUIDemo` (and `MetalUISDLDemo`): a 640 × 420 node-graph canvas in
/// the shape MetalCreator's graph and viewport need.
///
/// - **Pan**: a middle or right drag anywhere on the canvas, a primary drag on
///   the strip along its top (the open hand there, the closed hand while any
///   pan drags), or a two-finger scroll (momentum honoured: a glide keeps
///   panning).
/// - **Zoom about the pointer**: a pinch (about its `startLocation`) or a
///   ⌘- or ⌃-scroll (about the wheel's `location`; ⌃ is how a Windows
///   precision touchpad's pinch arrives, human check Y10). The canvas point
///   under the pointer stays put. Zoom is clamped to 0.25…4.
/// - **Pick**: a click selects the node under its `SpatialTapGesture` location
///   (an accent outline); a click on empty canvas clears the selection.
/// - **Menu**: a right-click on a node opens a located context menu naming
///   it, on the release (a right drag pans instead, `CI-F` item 4).
/// - **Pointer**: the crosshair (`.rectSelection`) over empty canvas, the
///   pointing hand (`.link`) over a node; **C** toggles the canvas's crosshair
///   off and on without moving the pointer (human check Y12).
/// - **Rotate**: the "Revolve" node carries a `RotateGesture` inside the
///   canvas's `MagnifyGesture` (human check Y4's corner).
/// - A **style strip** below the canvas shows one swatch per `PointerStyle`
///   (Y5, Y6), and a status line shows pan, zoom, rotation, the last scroll's
///   phase, momentum phase and precision, and the current drag's modifiers.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each part is its own function, passed as an
/// argument to a generic composing function — the Windows stack rule
/// `demoContent()`'s note records; built on a 1 MB thread by
/// `everyProductionTreeBuildsOnAOneMegabyteThread` (test 3.36).
@MainActor
public func canvasDemoContent() -> some Element {
    canvasRoot(header: canvasHeader(), canvas: canvasSurface(), strip: canvasStyleStrip(),
               status: canvasStatus())
}

/// One node of the demo graph, in canvas coordinates.
struct CanvasDemoNode {
    let name: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    /// Whether the canvas point (`cx`, `cy`) is inside the node.
    func contains(_ cx: Double, _ cy: Double) -> Bool {
        cx >= x && cx < x + width && cy >= y && cy < y + height
    }
}

/// The six nodes, in canvas coordinates (120 × 56 each).
let canvasDemoNodes: [CanvasDemoNode] = [
    CanvasDemoNode(name: "Sketch", x: 40, y: 60, width: 120, height: 56),
    CanvasDemoNode(name: "Extrude", x: 220, y: 40, width: 120, height: 56),
    CanvasDemoNode(name: "Revolve", x: 400, y: 90, width: 120, height: 56),
    CanvasDemoNode(name: "Fillet", x: 80, y: 220, width: 120, height: 56),
    CanvasDemoNode(name: "Mirror", x: 280, y: 250, width: 120, height: 56),
    CanvasDemoNode(name: "Export", x: 470, y: 300, width: 120, height: 56),
]

/// The node that carries the `RotateGesture` ("Revolve").
let canvasDemoRotatingNode = 2

/// The canvas's size in points.
let canvasDemoWidth = 640.0
let canvasDemoHeight = 420.0

/// The demo's state: the view transform, the selection, the rotating node's
/// angle and what the status line reports. Written only from input (gesture,
/// wheel and menu callbacks, the **C** key).
@MainActor
@Observable
public final class CanvasDemoModel {
    /// The canvas-local point where canvas point (0, 0) is drawn.
    public var panX = 0.0
    /// The canvas-local point where canvas point (0, 0) is drawn.
    public var panY = 0.0
    /// Points per canvas unit, 0.25…4.
    public var zoom = 1.0
    /// The selected node's index into the demo's nodes.
    public var selected: Int?
    /// The "Revolve" node's rotation in degrees, clockwise.
    public var rotation = 0.0
    /// Whether a pan drag is under way (the closed hand).
    public var grabbing = false
    /// Whether **C** turned the canvas's crosshair off (human check Y12).
    public var crosshairOff = false
    /// The last scroll's phase, momentum phase and precision.
    public var lastScroll = "none"
    /// The current (or last) drag's modifiers.
    public var dragModifiers = "none"
    /// What the context menu last chose.
    public var lastMenu = "none"

    // A gesture's starting view, so its cumulative value applies to it.
    var dragStart: (panX: Double, panY: Double)?
    var pinchStart: (panX: Double, panY: Double, zoom: Double)?
    var rotationStart: Double?

    /// A fresh model.
    public init() {}

    /// Back to the identity view, nothing selected, nothing under way.
    public func reset() {
        panX = 0; panY = 0; zoom = 1; selected = nil; rotation = 0; grabbing = false; crosshairOff = false
        lastScroll = "none"; dragModifiers = "none"; lastMenu = "none"
        dragStart = nil; pinchStart = nil; rotationStart = nil
    }

    /// The node under the canvas-local point, topmost (last drawn) first.
    func node(at location: Point<Pixels>) -> Int? {
        let cx = (Double(location.x.value) - panX) / zoom
        let cy = (Double(location.y.value) - panY) / zoom
        return canvasDemoNodes.indices.last { canvasDemoNodes[$0].contains(cx, cy) }
    }

    /// Selects the node under the canvas-local point, or clears the selection.
    func pick(at location: Point<Pixels>) {
        selected = node(at: location)
    }

    /// Sets the zoom to `zoom` (clamped) keeping the canvas point under the
    /// canvas-local point (`px`, `py`) fixed, from the view `from`.
    func zoom(to newZoom: Double, aboutX px: Double, y py: Double,
              from start: (panX: Double, panY: Double, zoom: Double)) {
        let clamped = min(max(newZoom, 0.25), 4)
        let factor = clamped / start.zoom
        panX = px - (px - start.panX) * factor
        panY = py - (py - start.panY) * factor
        zoom = clamped
    }

    /// A pan drag's change: the pan is the drag's starting pan plus its
    /// translation.
    func panDragChanged(_ value: DragGesture.Value) {
        if dragStart == nil { dragStart = (panX, panY) }
        let start = dragStart ?? (panX, panY)
        panX = start.panX + Double(value.translation.width.value)
        panY = start.panY + Double(value.translation.height.value)
        grabbing = true
        dragModifiers = canvasDemoDescribe(value.modifiers)
    }

    /// A pan drag's end.
    func panDragEnded(_ value: DragGesture.Value) {
        dragModifiers = canvasDemoDescribe(value.modifiers)
        dragStart = nil
        grabbing = false
    }

    /// A pinch's change: zoom by its cumulative magnification about where it
    /// began.
    func pinchChanged(_ value: MagnifyGesture.Value) {
        if pinchStart == nil { pinchStart = (panX, panY, zoom) }
        guard let start = pinchStart else { return }
        zoom(to: start.zoom * value.magnification, aboutX: Double(value.startLocation.x.value),
             y: Double(value.startLocation.y.value), from: start)
    }

    /// A pinch's end.
    func pinchEnded(_ value: MagnifyGesture.Value) {
        pinchChanged(value)
        pinchStart = nil
    }

    /// The "Revolve" node's twist: its starting angle plus the gesture's.
    func rotateChanged(_ value: RotateGesture.Value) {
        if rotationStart == nil { rotationStart = rotation }
        rotation = (rotationStart ?? rotation) + value.rotation.degrees
    }

    /// A twist's end.
    func rotateEnded(_ value: RotateGesture.Value) {
        rotateChanged(value)
        rotationStart = nil
    }

    /// A scroll: ⌘ or ⌃ zooms by `2^(Δy / 100)` about the pointer, anything
    /// else pans by the delta. Always claims.
    func scroll(_ event: ScrollEvent) -> Bool {
        lastScroll = "phase \(event.phase) · momentum \(event.momentumPhase) · "
            + (event.isPrecise ? "precise" : "lines")
        if event.modifiers.contains(.command) || event.modifiers.contains(.control) {
            zoom(to: zoom * pow(2, Double(event.delta.y.value) / 100),
                 aboutX: Double(event.location.x.value), y: Double(event.location.y.value),
                 from: (panX, panY, zoom))
        } else {
            panX += Double(event.delta.x.value)
            panY += Double(event.delta.y.value)
        }
        return true
    }
}

/// The one model the demo, its tests and the demo's **C** key share.
@MainActor public let canvasDemoModel = CanvasDemoModel()

/// **C** in the canvas demo: toggles the canvas's crosshair (human check Y12 —
/// the style changes under a still pointer).
public struct ToggleCanvasCrosshair: Action {
    /// The action.
    public init() {}
}

/// Runs the canvas demo's own action; `false` for any other.
@MainActor
public func canvasDemoHandle(_ action: any Action) -> Bool {
    guard action is ToggleCanvasCrosshair else { return false }
    canvasDemoModel.crosshairOff.toggle()
    return true
}

/// "⌥⇧", or "none".
func canvasDemoDescribe(_ modifiers: EventModifiers) -> String {
    var text = ""
    if modifiers.contains(.control) { text += "⌃" }
    if modifiers.contains(.option) { text += "⌥" }
    if modifiers.contains(.shift) { text += "⇧" }
    if modifiers.contains(.command) { text += "⌘" }
    return text.isEmpty ? "none" : text
}

private func cpx(_ value: Double) -> Pixels { Pixels(Float(value)) }

/// The root: the header, the canvas, the strip and the status line.
@MainActor
private func canvasRoot(header: some Element, canvas: some Element, strip: some Element,
                        status: some Element) -> some Element {
    Column(gap: Pixels(12)) {
        header
        canvas
        strip
        status
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
}

@MainActor
private func canvasHeader() -> some Element {
    Text("Canvas — middle/right drag or scroll pans · pinch or ⌘-scroll zooms · click picks · C toggles the crosshair")
        .font(size: 13)
}

/// The canvas: grid, nodes and the pan strip, with every input on it.
@MainActor
private func canvasSurface() -> some Element {
    let model = canvasDemoModel
    let style: PointerStyle = model.grabbing ? .grabActive : (model.crosshairOff ? .default : .rectSelection)
    return Stack(alignment: .topLeading) {
        canvasGrid()
        ForEach(Array(canvasDemoNodes.indices), id: \.self) { index in
            CanvasDemoNodeView(index: index)
        }
        canvasPanStrip()
    }
    .frame(width: cpx(canvasDemoWidth), height: cpx(canvasDemoHeight))
    .background(.surfaceSecondary)
    .clipped()
    .pointerStyle(style)
    .onScrollWheel { canvasDemoModel.scroll($0) }
    .gesture(SpatialTapGesture().onEnded { canvasDemoModel.pick(at: $0.location) })
    .gesture(MagnifyGesture()
        .onChanged { canvasDemoModel.pinchChanged($0) }
        .onEnded { canvasDemoModel.pinchEnded($0) })
    .gesture(DragGesture(button: .middle)
        .onChanged { canvasDemoModel.panDragChanged($0) }
        .onEnded { canvasDemoModel.panDragEnded($0) })
    .gesture(DragGesture(button: .secondary)
        .onChanged { canvasDemoModel.panDragChanged($0) }
        .onEnded { canvasDemoModel.panDragEnded($0) })
    .contextMenu { (location: Point<Pixels>?) in
        canvasDemoMenu(node: location.flatMap { canvasDemoModel.node(at: $0) })
    }
}

/// The context menu: the node under the press, or the canvas.
@MainActor @MenuContentBuilder
private func canvasDemoMenu(node: Int?) -> some MenuContent {
    Button(node.map { "Inspect \(canvasDemoNodes[$0].name)" } ?? "Inspect canvas") {
        canvasDemoModel.lastMenu = node.map { "inspect \(canvasDemoNodes[$0].name)" } ?? "inspect canvas"
    }
    Button("Reset view") {
        canvasDemoModel.panX = 0; canvasDemoModel.panY = 0; canvasDemoModel.zoom = 1
        canvasDemoModel.lastMenu = "reset view"
    }
}

/// Grid lines every 40 canvas units (doubled until at least 20 points apart),
/// following the pan and zoom.
@MainActor
private func canvasGrid() -> some Element {
    let model = canvasDemoModel
    var spacing = 40 * model.zoom
    while spacing < 20 { spacing *= 2 }
    let firstX = model.panX.truncatingRemainder(dividingBy: spacing)
    let firstY = model.panY.truncatingRemainder(dividingBy: spacing)
    let xs = Array(stride(from: firstX < 0 ? firstX + spacing : firstX, to: canvasDemoWidth, by: spacing))
    let ys = Array(stride(from: firstY < 0 ? firstY + spacing : firstY, to: canvasDemoHeight, by: spacing))
    return Stack(alignment: .topLeading) {
        ForEach(Array(xs.indices), id: \.self) { index in
            Box().frame(width: Pixels(1), height: cpx(canvasDemoHeight)).background(.separator)
                .offset(x: cpx(xs[index]))
        }
        ForEach(Array(ys.indices), id: \.self) { index in
            Box().frame(width: cpx(canvasDemoWidth), height: Pixels(1)).background(.separator)
                .offset(y: cpx(ys[index]))
        }
    }
    .frame(width: cpx(canvasDemoWidth), height: cpx(canvasDemoHeight))
}

/// One node, drawn at `pan + position × zoom`, the pointing hand over it.
struct CanvasDemoNodeView: Component {
    let index: Int

    var content: some ElementGroup {
        let model = canvasDemoModel
        let node = canvasDemoNodes[index]
        let zoom = model.zoom
        let selected = model.selected == index
        let card = Box {
            Text(node.name).font(size: 13 * zoom)
        }
        .alignItems(.center)
        .justifyContent(.center)
        .frame(width: cpx(node.width * zoom), height: cpx(node.height * zoom))
        .background(.surface)
        .border(selected ? .accent : .separator, width: Pixels(selected ? 3 : 1))
        .cornerRadius(cpx(8 * zoom))
        .pointerStyle(.link)
        if index == canvasDemoRotatingNode {
            card
                .gesture(RotateGesture()
                    .onChanged { canvasDemoModel.rotateChanged($0) }
                    .onEnded { canvasDemoModel.rotateEnded($0) })
                .rotationEffect(.degrees(model.rotation))
                .offset(x: cpx(model.panX + node.x * zoom), y: cpx(model.panY + node.y * zoom))
        } else {
            card.offset(x: cpx(model.panX + node.x * zoom), y: cpx(model.panY + node.y * zoom))
        }
    }
}

/// The strip along the canvas's top: the open hand, and a primary drag pans.
@MainActor
private func canvasPanStrip() -> some Element {
    Box {
        Text("drag here to pan").font(size: 11)
    }
    .alignItems(.center)
    .justifyContent(.center)
    .frame(width: cpx(canvasDemoWidth), height: Pixels(22))
    .background(.surface)
    .pointerStyle(canvasDemoModel.grabbing ? .grabActive : .grabIdle)
    .gesture(DragGesture(minimumDistance: Pixels(1))
        .onChanged { canvasDemoModel.panDragChanged($0) }
        .onEnded { canvasDemoModel.panDragEnded($0) })
}

/// Every `PointerStyle` the demo can show, with its swatch label.
let canvasDemoStyles: [(String, PointerStyle)] = [
    ("default", .default), ("hText", .horizontalText), ("vText", .verticalText),
    ("rectSel", .rectSelection), ("grabIdle", .grabIdle), ("grabActive", .grabActive),
    ("link", .link), ("zoomIn", .zoomIn), ("zoomOut", .zoomOut),
    ("column", .columnResize), ("row", .rowResize),
    ("top", .frameResize(position: .top)), ("trailing in", .frameResize(position: .trailing, directions: .inward)),
    ("corner", .frameResize(position: .bottomTrailing)),
]

/// One swatch per pointer style, in two rows of seven (human checks Y5, Y6).
@MainActor
private func canvasStyleStrip() -> some Element {
    Column(gap: Pixels(4)) {
        canvasStyleRow(0..<7)
        canvasStyleRow(7..<14)
    }
    .alignItems(.flexStart)
}

@MainActor
private func canvasStyleRow(_ range: Range<Int>) -> some Element {
    Row(gap: Pixels(4)) {
        ForEach(Array(range), id: \.self) { index in
            Box {
                Text(canvasDemoStyles[index].0).font(size: 11)
            }
            .alignItems(.center)
            .justifyContent(.center)
            .frame(width: Pixels(86), height: Pixels(26))
            .background(.surfaceSecondary)
            .pointerStyle(canvasDemoStyles[index].1)
        }
    }
}

@MainActor
private func canvasStatus() -> some Element {
    let model = canvasDemoModel
    var selected = "none"
    if let index = model.selected { selected = canvasDemoNodes[index].name }
    return Column(gap: Pixels(2)) {
        Text(String(format: "pan %.0f, %.0f · zoom %.2f · rotation %.1f° · selected %@ · menu %@",
                    model.panX, model.panY, model.zoom, model.rotation, selected, model.lastMenu))
            .font(size: 12)
        Text("scroll \(model.lastScroll) · drag modifiers \(model.dragModifiers)").font(size: 12)
    }
    .alignItems(.flexStart)
}
