import MetalUI
import Observation
import Foundation

/// The key-and-focus demo (spec `2026-10-08-key-focus-design.md` §6, rulings
/// `KF-B`…`KF-K`), reached with `METALUI_KEY_FOCUS_DEMO=1 swift run MetalUIDemo`
/// (and `MetalUISDLDemo`): the shapes MetalCreator's node editor needs.
///
/// - **Canvas and inspector**: a canvas that is a key region
///   (`.hoverKeyRegion()`, `.keyContext("Canvas")`) beside an inspector of
///   `TextField`s inside `.keyContext("Panel")`. With nothing focused, Tab over
///   the canvas opens the palette; a press on the canvas clears a field's
///   focus; Tab from a focused field moves focus. The **Depth** field drops
///   letters (`onKeyPress(characters:)`, human check KF-7).
/// - **Palette**: a search field whose `onKeyPress(keys: [.upArrow,
///   .downArrow])` moves a highlight; Return picks, Escape closes.
/// - **Viewport**: a `GPUSurface` that takes focus on a press
///   (`.focusable(interactions: .edit)`, one `KeyboardModifier` layer), reports
///   its size through `.onGeometryChange`, and carries a `TimelineView(.animation)`
///   label orbiting with the time.
/// - A **status line** shows the last key's walk: the root's `onKeyPress`
///   (outermost first) and whoever took it.
///
/// Nothing here is in the default demo, so the fourteen offscreen images and
/// `Expected.swift` do not move. Each part is its own function, passed as an
/// argument to a generic composing function (the Windows 1 MB stack rule);
/// built on a 1 MB thread by `everyProductionTreeBuildsOnAOneMegabyteThread`.
@MainActor
public func keyFocusDemoContent() -> some Element {
    keyFocusRoot(header: keyFocusHeader(), canvas: keyFocusCanvas(), inspector: keyFocusInspector(),
                 palette: keyFocusPalette(), viewport: keyFocusViewport(), status: keyFocusStatus())
}

/// The demo's state, written only from input (key and click handlers) and
/// from the geometry action (the lifecycle drain).
@MainActor
@Observable
public final class KeyFocusDemoModel {
    /// The last key's walk, outermost first.
    public var trail: [String] = []
    /// What the last key did.
    public var last = "none"
    /// Whether the palette is open.
    public var paletteOpen = false
    /// The highlighted palette row.
    public var highlight = 0
    /// The palette's search text.
    public var query = ""
    /// The last palette pick.
    public var picked = "none"
    /// The inspector's name field.
    public var name = "Extrude"
    /// The inspector's depth field (digits only).
    public var depth = "10"
    /// The viewport's size, from its geometry action.
    public var viewportSize = "unknown"
    /// Keys the focused viewport took.
    public var viewportKeys = 0

    /// A fresh model.
    public init() {}

    /// Back to the launch state.
    public func reset() {
        trail = []; last = "none"; paletteOpen = false; highlight = 0; query = ""; picked = "none"
        name = "Extrude"; depth = "10"; viewportSize = "unknown"; viewportKeys = 0
    }

    /// The palette's rows matching the query.
    var rows: [String] {
        let all = ["Extrude", "Revolve", "Fillet", "Mirror", "Export", "Sketch"]
        return query.isEmpty ? all : all.filter { $0.lowercased().contains(query.lowercased()) }
    }

    /// A key's walk starts at the root.
    func begin(_ press: KeyPress) {
        trail = ["root"]
        last = keyFocusDemoDescribe(press.key)
    }

    /// Moves the palette's highlight by `step`, wrapping.
    func move(_ step: Int) {
        let count = rows.count
        guard count > 0 else { return }
        highlight = (highlight + step + count) % count
    }

    /// Picks the highlighted row and closes the palette.
    func pick() {
        let rows = self.rows
        picked = rows.isEmpty ? "nothing" : rows[min(highlight, rows.count - 1)]
        paletteOpen = false
        query = ""
        highlight = 0
    }
}

/// The one model the demo and its tests share.
@MainActor public let keyFocusDemoModel = KeyFocusDemoModel()

/// A key's name for the status line.
func keyFocusDemoDescribe(_ key: KeyEquivalent) -> String {
    switch key {
    case .tab: return "Tab"
    case .return: return "Return"
    case .escape: return "Escape"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return String(key.character)
    }
}

/// The root: the header, a row of canvas, inspector and viewport, the palette
/// and the status line. Its `onKeyPress` runs first for every key (outermost
/// first, `KF-C`) and only records the walk.
@MainActor
private func keyFocusRoot(header: some Element, canvas: some Element, inspector: some Element,
                          palette: some Element, viewport: some Element,
                          status: some Element) -> some Element {
    Column(gap: Pixels(12)) {
        header
        Row(gap: Pixels(16)) {
            canvas
            inspector
            viewport
        }
        .alignItems(.flexStart)
        palette
        status
    }
    .alignItems(.flexStart)
    .padding(Pixels(24))
    .frame(maxWidth: Pixels(.infinity), maxHeight: Pixels(.infinity), alignment: .topLeading)
    .background(.surface)
    .onKeyPress { press in
        keyFocusDemoModel.begin(press)
        return .ignored
    }
}

@MainActor
private func keyFocusHeader() -> some Element {
    Text("Key and focus — hover the canvas and press Tab · click the canvas to leave a field · click the viewport to focus it")
        .font(size: 13)
}

/// The canvas: a key region with its own context; Tab opens the palette.
@MainActor
private func keyFocusCanvas() -> some Element {
    Box {
        Text("Canvas (key region)").font(size: 12)
    }
    .alignItems(.center)
    .justifyContent(.center)
    .frame(width: Pixels(300), height: Pixels(200))
    .background(.surfaceSecondary)
    .hoverKeyRegion()
    .keyContext("Canvas")
    .onKeyPress(.tab) {
        keyFocusDemoModel.trail.append("canvas")
        keyFocusDemoModel.paletteOpen = true
        return .handled
    }
}

/// The inspector: two fields in a `Panel` context; the depth field drops
/// letters.
@MainActor
private func keyFocusInspector() -> some Element {
    let model = keyFocusDemoModel
    return Column(gap: Pixels(8)) {
        Text("Inspector (Panel)").font(size: 12)
        TextField("Name", text: model.name) { keyFocusDemoModel.name = $0 }
            .onKeyPress { _ in
                keyFocusDemoModel.trail.append("name field")
                return .ignored
            }
            .frame(width: Pixels(180))
        TextField("Depth", text: model.depth) { keyFocusDemoModel.depth = $0 }
            .onKeyPress(characters: .letters) { _ in
                keyFocusDemoModel.trail.append("depth filter")
                return .handled
            }
            .frame(width: Pixels(180))
    }
    .alignItems(.flexStart)
    .keyContext("Panel")
}

/// The palette, while open: a search field taking ↑/↓, Return and Escape
/// before the field's own editing keys.
@MainActor
private func keyFocusPalette() -> some Element {
    let model = keyFocusDemoModel
    let rows = model.rows
    return Column(gap: Pixels(4)) {
        if model.paletteOpen {
            TextField("Search", text: model.query) {
                keyFocusDemoModel.query = $0
                keyFocusDemoModel.highlight = 0
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                keyFocusDemoModel.trail.append("palette")
                keyFocusDemoModel.move(press.key == .upArrow ? -1 : 1)
                return .handled
            }
            .onKeyPress(.return) {
                keyFocusDemoModel.trail.append("palette")
                keyFocusDemoModel.pick()
                return .handled
            }
            .onKeyPress(.escape) {
                keyFocusDemoModel.paletteOpen = false
                return .handled
            }
            .frame(width: Pixels(300))
            ForEach(Array(rows.indices), id: \.self) { index in
                Text(rows[index]).font(size: 12)
                    .padding(Pixels(2))
                    .frame(width: Pixels(300), alignment: .leading)
                    .background(index == model.highlight ? ColorToken.accent : ColorToken.surface)
            }
        }
    }
    .alignItems(.flexStart)
}

/// The viewport: a GPU surface that takes focus on a press and hears keys
/// through one keyboard layer, reports its size, and carries a timeline label.
@MainActor
private func keyFocusViewport() -> some Element {
    HStack(spacing: 0) {
        ZStack(alignment: .topLeading) {
            GPUSurface(redraw: .continuous) { ctx in
                let t = Float(ctx.time.truncatingRemainder(dividingBy: 3600))
                ctx.clear(red: 0.12, green: 0.18 + 0.08 * sin(t), blue: 0.32, alpha: 1)
            }
            .frame(width: Pixels(240), height: Pixels(200))
            .focusable(interactions: .edit)
            .keyContext("Viewport")
            .onKeyPress { _ in
                keyFocusDemoModel.trail.append("viewport")
                keyFocusDemoModel.viewportKeys += 1
                return .handled
            }
            .onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { size in
                keyFocusDemoModel.viewportSize = "\(Int(size.width.value)) × \(Int(size.height.value))"
            }
            TimelineView(.animation) { context in
                keyFocusOrbit(context.date)
            }
        }
    }
}

/// The orbiting label at `date`: a 60-point circle around the viewport's
/// centre, one turn every six seconds.
@MainActor
private func keyFocusOrbit(_ date: Date) -> some ProposalElementGroup {
    let angle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 2 * Double.pi
    return ProposalText("orbit")
        .offset(x: Pixels(Float(100 + 60 * cos(angle))), y: Pixels(Float(92 + 60 * sin(angle))))
}

@MainActor
private func keyFocusStatus() -> some Element {
    let model = keyFocusDemoModel
    return Column(gap: Pixels(2)) {
        Text("last key \(model.last) · walk \(model.trail.joined(separator: " › "))").font(size: 12)
        Text("picked \(model.picked) · viewport \(model.viewportSize), \(model.viewportKeys) keys · depth \(model.depth)")
            .font(size: 12)
    }
    .alignItems(.flexStart)
}
