import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-i (`RZ-`, record 133): the fixture of the retained-zoom pins. Ten `.equatable()` nodes in a row (text, a filled rounded rect,
// a stroked `Path`, a labelled `Button`), under `.scaleEffect(s, anchor: .topLeading)` then a non-identity `.offset`, in a clipped
// frame. The scale is `side.inputs.offset` (an `RPInputs` field the `RPPair` helpers already carry; a `Float`, so 1.1 is inexact on
// purpose), the pan `side.model.n` points on top of the fixed 40 x 24. Counts only (`FrameWork`), never time.

/// What a node holds besides the common four: each variant separates one named refusal or one carry.
enum ZKind: String, CaseIterable, CustomStringConvertible, Sendable {
    case plain
    /// A button inside an effect the occurrence opens itself (`RL-I`).
    case inner
    /// A context menu on the button (a window-space record, `RZ-F`).
    case menu
    /// A closed `.popover` declarer (a presentation anchor, `RZ-F`).
    case popover
    /// A geometry note holding a named space declared inside the node (`RZ-E`).
    case namedSpace
    var description: String { rawValue }
}

struct ZNode: Component, @MainActor Equatable {
    let k: Int
    let log: HarnessLog
    var kind: ZKind = .plain
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("node \(k)").frame(width: Pixels(60), height: Pixels(14))
            if kind == .popover {
                RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2, green: 0.4 + Double(k) * 0.04, blue: 0.8))
                    .frame(width: Pixels(60), height: Pixels(16))
                    .popover(isPresented: .constant(false)) { Text("p\(k)").frame(width: Pixels(40), height: Pixels(20)) }
            } else {
                RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2, green: 0.4 + Double(k) * 0.04, blue: 0.8))
                    .frame(width: Pixels(60), height: Pixels(16))
            }
            ZWire().stroke(Color(red: 0.9, green: 0.4, blue: 0.2), lineWidth: Pixels(2)).frame(width: Pixels(60), height: Pixels(20))
            switch kind {
            case .inner:
                // An effect the occurrence opens itself (`RL-I`): its hitbox and record are re-derived from the recorded step.
                Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(40), height: Pixels(12))
                    .scaleEffect(1.5, anchor: .topLeading).frame(width: Pixels(60), height: Pixels(18), alignment: .topLeading)
            case .menu:
                Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(60), height: Pixels(18))
                    .contextMenu { Button("menu \(k)") { log.add("menu \(k)") } }
            case .namedSpace:
                // The note's space is declared inside the node and the button sits outside it (a hitbox inside a named scope
                // snapshots the stack and makes the prepaint ineligible, `namedSpace`).
                VStack(spacing: 0) {
                    Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(60), height: Pixels(18))
                    HStack(spacing: 0) {
                        Box().frame(width: Pixels(16), height: Pixels(4))
                        Box().frame(width: Pixels(24), height: Pixels(4))
                            .onGeometryChange(for: String.self, of: { ZNode.frame($0) }) { _ in }
                    }
                    .coordinateSpace(.named("zin"))
                }
            case .plain, .popover:
                Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(60), height: Pixels(18))
            }
        }
    }
    static func frame(_ p: GeometryProxy) -> String {
        let g = p.frame(in: .global), f = p.frame(in: .named("zin"))
        return "\(g.origin.x.value),\(g.origin.y.value) in \(f.origin.x.value),\(f.origin.y.value) \(f.size.width.value)x\(f.size.height.value)"
    }
    static func == (l: ZNode, r: ZNode) -> Bool { l.k == r.k && l.log === r.log && l.kind == r.kind }
}

struct ZWire: Shape {
    func path(in rect: Bounds<Pixels>) -> Path {
        var p = Path()
        let w = rect.size.width.value, h = rect.size.height.value
        p.move(to: Point(x: Pixels(2), y: Pixels(h - 2)))
        p.addCurve(to: Point(x: Pixels(w - 2), y: Pixels(2)), control1: Point(x: Pixels(w * 0.5), y: Pixels(h)),
                   control2: Point(x: Pixels(w * 0.5), y: Pixels(0)))
        return p
    }
}

/// What a pin changes around the row (each separates one refusal of `RZ-B`).
enum ZExtra: String, CaseIterable, CustomStringConvertible, Sendable {
    case none, nonUniform, outerClip
    var description: String { rawValue }
}

struct ZRow: Component {
    let log: HarnessLog
    var kind: ZKind = .plain
    var content: some ElementGroup {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(0..<10), id: \.self) { k in
                ZNode(k: k, log: log, kind: kind).equatable()
            }
        }
    }
}

struct ZoomRoot: Component {
    let side: RPSide
    var extra: ZExtra = .none
    var rotation = false
    var kind: ZKind = .plain
    var content: some ElementGroup {
        let scale = side.inputs.offset == 0 ? 1.0 : Double(side.inputs.offset)
        let log = side.log
        let pan = Pixels(40 + Float(side.model.n)), panY = Pixels(24)
        // `outerClip`: the frame outside the effect changes with the scale, so the clip the effect opens under changes.
        let width = extra == .outerClip ? Float(1400 - 100 * (scale - 1)) : 1400
        ZStack(alignment: .topLeading) {
            if rotation {
                ZStack(alignment: .topLeading) { ZRow(log: log, kind: kind) }
                    .rotationEffect(.degrees((scale - 1) * 20), anchor: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading).offset(x: pan, y: panY)
            } else if extra == .nonUniform {
                ZStack(alignment: .topLeading) { ZRow(log: log, kind: kind) }
                    .scaleEffect(x: scale, y: 1, anchor: .topLeading).offset(x: pan, y: panY)
            } else {
                ZStack(alignment: .topLeading) { ZRow(log: log, kind: kind) }
                    .scaleEffect(scale, anchor: .topLeading).offset(x: pan, y: panY)
            }
        }
        .frame(width: Pixels(width), height: Pixels(320), alignment: .topLeading)
        .clipped()
        .frame(width: Pixels(1500), height: Pixels(360), alignment: .topLeading)
    }
}

@MainActor func zoomPair(extra: ZExtra = .none, rotation: Bool = false, kind: ZKind = .plain, scale: Float = 2, warm: Int = 8,
                         accessibility: Bool = true, graft: Bool = true) throws -> RPPair<some Element> {
    try RPPair(size: sz(1500, 360), scale: scale, warm: warm, accessibility: accessibility, graft: graft) { side in
        VStack(spacing: 0) { ZoomRoot(side: side, extra: extra, rotation: rotation, kind: kind) }
    }
}

/// Sets the zoom of both sides, settles and draws one frame on each.
@MainActor func zoomStep(_ pair: RPPair<some Element>, to scale: Float) async {
    pair.onSide.inputs.offset = scale; pair.offSide.inputs.offset = scale
    await rsSettle()
    pair.redraw()
}

/// Moves the pan of both sides by `points`, settles and draws one frame on each.
@MainActor func zoomPan(_ pair: RPPair<some Element>, by points: Int) async {
    pair.onSide.model.n += points; pair.offSide.model.n += points
    await rsSettle()
    pair.redraw()
}
