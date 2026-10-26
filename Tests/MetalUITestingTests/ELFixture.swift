import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// FS-O (`EL-`, record 157): the fixture of the combined layout-and-effect pins. A header whose height the model moves, above a
// `ZStack` of six `.equatable()` cards under `.scaleEffect(zoom, anchor: .topLeading)` and a non-identity `.offset`: a header step
// moves every card's layout origin and a zoom step changes the effect around it, in one frame (MetalCreator's growing header over a
// zooming canvas). The header height is `10 + side.model.n` points and the zoom `side.inputs.offset` (0 reads as 1), both
// `RPSide` fields the `RPPair` helpers already carry. Counts only (`FrameWork`), never time.

/// What a pin changes in the fixture; each separates one refusal of the combined arm.
enum ELExtra: String, CaseIterable, CustomStringConvertible, Sendable {
    case none
    /// An effect the cards open themselves (`innerScope` at paint).
    case innerOffset
    /// A shadow scope opened inside a card (`innerScope` at paint, the scope is the occurrence's own).
    case shadowInside
    /// The scale becomes non-uniform past 1.15: the effect's flattening class changes.
    case flatten
    /// The frame outside the effect changes with the zoom, so the clip the effect opens under changes.
    case outerClip
    /// A rotation joins the zoom (an identity rotation is a flattening scope, a real one is not).
    case rotate
    /// The frame outside the effect clips (`.clipped()`), the clip moving with the header.
    case clipped
    var description: String { rawValue }
}

/// A card: a bar, a label and a button (a hitbox, a focus stop, an accessibility record).
struct ELCard: Component, @MainActor Equatable {
    let k: Int
    let log: HarnessLog
    var extra: ELExtra = .none
    var content: some ElementGroup {
        HStack(spacing: 4) {
            switch extra {
            case .shadowInside:
                RoundedRectangle(cornerRadius: Pixels(3)).fill(Color(red: 0.2, green: 0.3 + Double(k) * 0.08, blue: 0.8))
                    .frame(width: Pixels(20), height: Pixels(14)).shadow(color: .black, radius: Pixels(2), x: Pixels(0), y: Pixels(1))
            default:
                RoundedRectangle(cornerRadius: Pixels(3)).fill(Color(red: 0.2, green: 0.3 + Double(k) * 0.08, blue: 0.8))
                    .frame(width: Pixels(20), height: Pixels(14))
            }
            Text("card \(k)").frame(width: Pixels(50), height: Pixels(14))
            if extra == .innerOffset {
                Button("e\(k)") { log.add("e\(k)") }.accessibilityLabel("e\(k)").frame(width: Pixels(30), height: Pixels(14))
                    .offset(x: Pixels(2), y: Pixels(1))
            } else {
                Button("e\(k)") { log.add("e\(k)") }.accessibilityLabel("e\(k)").frame(width: Pixels(30), height: Pixels(14))
            }
        }
        .frame(height: Pixels(18))
    }
    static func == (l: ELCard, r: ELCard) -> Bool { l.k == r.k && l.log === r.log && l.extra == r.extra }
}

struct ELPanels: Component {
    let log: HarnessLog
    var extra: ELExtra = .none
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(0..<6), id: \.self) { k in
                ELCard(k: k, log: log, extra: extra).equatable()
            }
        }
    }
}

struct ELRoot: Component {
    let side: RPSide
    var extra: ELExtra = .none
    /// The header's height in points; defaults to the model's step.
    var content: some ElementGroup {
        let scale = side.inputs.offset == 0 ? 1.0 : Double(side.inputs.offset)
        let header = Pixels(10 + Float(side.model.n) + 0.25 * Float(side.model.tint))
        let log = side.log
        let width = extra == .outerClip ? Float(260 - 40 * (scale - 1)) : 260
        VStack(alignment: .leading, spacing: 0) {
            Color(red: 0.5, green: 0.5, blue: 0.5).frame(width: Pixels(260), height: header)
            ZStack(alignment: .topLeading) {
                if extra == .rotate {
                    ZStack(alignment: .topLeading) { ELPanels(log: log, extra: extra) }
                        .rotationEffect(.degrees((scale - 1) * 20), anchor: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading).offset(x: Pixels(8), y: Pixels(6))
                } else if extra == .flatten {
                    ZStack(alignment: .topLeading) { ELPanels(log: log, extra: extra) }
                        .scaleEffect(x: scale, y: scale > 1.15 ? 1 : scale, anchor: .topLeading).offset(x: Pixels(8), y: Pixels(6))
                } else {
                    ZStack(alignment: .topLeading) { ELPanels(log: log, extra: extra) }
                        .scaleEffect(scale, anchor: .topLeading).offset(x: Pixels(8), y: Pixels(6))
                }
            }
            .frame(width: Pixels(width), height: Pixels(300), alignment: .topLeading)
        }
        .frame(width: Pixels(260), height: Pixels(400), alignment: .topLeading)
    }
}

@MainActor func elPair(extra: ELExtra = .none, scale: Float = 2, warm: Int = 8, accessibility: Bool = false,
                       graft: Bool = false) throws -> RPPair<some Element> {
    try RPPair(size: sz(260, 400), scale: scale, warm: warm, accessibility: accessibility, graft: graft) { side in
        VStack(spacing: 0) { ELRoot(side: side, extra: extra) }
    }
}

/// Sets the header (points added to the 10 base) and the zoom of both sides in one change, settles and draws one frame on each.
@MainActor func elStep(_ pair: RPPair<some Element>, header: Int? = nil, quarters: Int? = nil, zoom: Float? = nil) async {
    for s in [pair.onSide, pair.offSide] {
        if let header { s.model.n = header }
        if let quarters { s.model.tint = quarters }
        if let zoom { s.inputs.offset = zoom }
    }
    await rsSettle()
    pair.redraw()
}
