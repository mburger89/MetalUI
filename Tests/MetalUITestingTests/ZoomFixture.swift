import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-i (`RZ-`, record 133): the fixture of the retained-zoom pins. Ten `.equatable()` nodes in a row (text, a filled rounded rect,
// a stroked `Path`, a labelled `Button`), under `.scaleEffect(s, anchor: .topLeading)` then a fixed non-identity `.offset`, in a
// clipped frame. The scale is `side.inputs.offset` (an `RPInputs` field the `RPPair` helpers already carry; a `Float`, so 1.1 is
// inexact on purpose). Counts only (`FrameWork`), never time.

struct ZNode: Component, @MainActor Equatable {
    let k: Int
    let log: HarnessLog
    var inner = false
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("node \(k)").frame(width: Pixels(60), height: Pixels(14))
            RoundedRectangle(cornerRadius: Pixels(4)).fill(Color(red: 0.2, green: 0.4 + Double(k) * 0.04, blue: 0.8))
                .frame(width: Pixels(60), height: Pixels(16))
            ZWire().stroke(Color(red: 0.9, green: 0.4, blue: 0.2), lineWidth: Pixels(2)).frame(width: Pixels(60), height: Pixels(20))
            if inner {
                // An effect the occurrence opens itself (`RL-I`): its hitbox and record are re-derived from the recorded step.
                Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(40), height: Pixels(12))
                    .scaleEffect(1.5, anchor: .topLeading).frame(width: Pixels(60), height: Pixels(18), alignment: .topLeading)
            } else {
                Button("z\(k)") { log.add("z\(k)") }.accessibilityLabel("z\(k)").frame(width: Pixels(60), height: Pixels(18))
            }
        }
    }
    static func == (l: ZNode, r: ZNode) -> Bool { l.k == r.k && l.log === r.log && l.inner == r.inner }
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

/// What a pin adds around the row (each separates one refusal of `RZ-B`, `RZ-E`, `RZ-F`).
enum ZExtra: String, CaseIterable, CustomStringConvertible, Sendable {
    case none, nonUniform, outerClip
    var description: String { rawValue }
}

struct ZRow: Component {
    let log: HarnessLog
    var inner = false
    var content: some ElementGroup {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(0..<10), id: \.self) { k in
                ZNode(k: k, log: log, inner: inner).equatable()
            }
        }
    }
}

struct ZoomRoot: Component {
    let side: RPSide
    var extra: ZExtra = .none
    var rotation = false
    var inner = false
    var content: some ElementGroup {
        let scale = side.inputs.offset == 0 ? 1.0 : Double(side.inputs.offset)
        let log = side.log
        // `outerClip`: the frame outside the effect changes with the scale, so the clip the effect opens under changes.
        let width = extra == .outerClip ? Float(1400 - 100 * (scale - 1)) : 1400
        ZStack(alignment: .topLeading) {
            if rotation {
                ZStack(alignment: .topLeading) { ZRow(log: log, inner: inner) }
                    .rotationEffect(.degrees((scale - 1) * 20), anchor: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading).offset(x: Pixels(40), y: Pixels(24))
            } else if extra == .nonUniform {
                ZStack(alignment: .topLeading) { ZRow(log: log, inner: inner) }.scaleEffect(x: scale, y: 1, anchor: .topLeading).offset(x: Pixels(40), y: Pixels(24))
            } else {
                ZStack(alignment: .topLeading) { ZRow(log: log, inner: inner) }.scaleEffect(scale, anchor: .topLeading).offset(x: Pixels(40), y: Pixels(24))
            }
        }
        .frame(width: Pixels(width), height: Pixels(320), alignment: .topLeading)
        .clipped()
    }
}

@MainActor func zoomPair(extra: ZExtra = .none, rotation: Bool = false, inner: Bool = false, scale: Float = 2, warm: Int = 8, accessibility: Bool = true,
                         graft: Bool = true) throws -> RPPair<some Element> {
    try RPPair(size: sz(1500, 360), scale: scale, warm: warm, accessibility: accessibility, graft: graft) { side in
        VStack(spacing: 0) { ZoomRoot(side: side, extra: extra, rotation: rotation, inner: inner) }
    }
}

/// Sets the zoom of both sides, settles and draws one frame on each.
@MainActor func zoomStep(_ pair: RPPair<some Element>, to scale: Float) async {
    pair.onSide.inputs.offset = scale; pair.offSide.inputs.offset = scale
    await rsSettle()
    pair.redraw()
}
